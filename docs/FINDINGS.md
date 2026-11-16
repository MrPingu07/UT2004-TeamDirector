# Findings

This document records the concrete engine/API facts that shaped the
implementation. Each item was verified against the decompiled UT2004 v3374
source in `ut2k4tp/reference` and/or by compiling and running the package.

## 1. `Interaction` is `Engine.Interaction`, and package order matters

The client render/input hook is a normal `Interaction` subclass. In a UT2004
install it lives in `Engine.u`. There is no `XInterface.Interaction` and no
separate `UT2004.Interaction` package to add.

The first compile attempt failed with:

```text
Analyzing...Superclass Interaction of class DirectorInteraction not found
```

The cause was **where** the temporary `EditPackages=MutTechDirector` line was
inserted. Putting it immediately after `[Editor.EditorEngine]` makes UCC treat
MutTechDirector as the first package to compile, before `EditPackages=Engine`
has been analyzed. UCC resolves the package's own superclasses from the
packages analyzed before it, so `Interaction` was not yet known.

**Fix:** append the package at the end of the `EditPackages` list, after all
stock dependencies. `tools/build.sh` inserts it after the last existing
`EditPackages` line. This is also why the build script does not use a naive
`sed` insertion at the section header.

## 2. `PlayerStart.TeamNumber` is the team-start field

There is no `TeamPlayerStart` class in stock UT2004. Team-aware maps tag a
`PlayerStart` with `TeamNumber` (normally `0` or `1`, neutral often `255`).
`DirectorRules` and `MutTechDirector.FindHomeLocation()` therefore use
`PlayerStart.TeamNumber`, not a nonexistent subclass.

## 3. `CameraDist` is a multiplier, not a world distance

`PlayerController.CalcBehindView()` receives:

```text
CameraDist * ViewTarget.Default.CollisionRadius
```

So setting `CameraDist = 120` does **not** produce a 120-unit camera. The
Interaction computes:

```text
CameraDist = ZoomDistance / CurrentTarget.Default.CollisionRadius
```

where `ZoomDistance` is the desired world-space distance (clamped 120..1500).
The stock `CameraDistRange` is `(Min=3, Max=40)`, which is too narrow for that
ratio on small pawns, so the Interaction temporarily widens it to `1..400` and
restores the stock range in `Cleanup()`.

Zoom itself is free to stay client-side: it only changes the local camera, not
gameplay state, so no RPC is needed per frame.

## 4. `UnPossess()` already enters `Spectating`

`PlayerController.UnPossess()`:

- moves the controller to the pawn's location,
- sets the pawn's `RemoteRole` to `ROLE_SimulatedProxy`,
- calls `Pawn.UnPossessed()`,
- clears saved moves,
- switches the view target to `self` if it was the pawn,
- sets `Pawn = None`,
- calls `GotoState('Spectating')`.

The mutator still calls `GotoState('Spectating')` explicitly after destroying
the pawn for clarity, but the state transition is not a new invention. The
`Spectating.BeginState()` resets `CameraDist` to `Default.CameraDist` and sets
`bCollideWorld = true`; this is why Director entry sets `bBehindView` and the
initial view target **after** the state change.

`Spectating` does not mark the PRI as a spectator by itself. The mutator also
clears `bOutOfLives` / `bIsSpectator`; the player remains on `TeamInfo`, which
is exactly what preserves roster counts.

## 5. `RestartPlayer()` is the right exit path

`GameInfo.RestartPlayer(Controller)` does all the stock work:

- resolves the team,
- calls `FindPlayerStart()`,
- spawns `PawnClass` (or the default class),
- calls `Possess()`,
- plays the teleport effect,
- calls `AddDefaultInventory()`,
- triggers the start spot's event.

Using it means `DirectorRules` only has to supply a fallback start point; it
never has to know how to spawn a player. It also means the mutator inherits
spawn protection and gametype-specific start logic for free.

## 6. `SetViewTarget` + `ClientSetViewTarget` are the supported pair

`SetViewTarget` is `native final` on `PlayerController`; `ClientSetViewTarget`
is a replicated client event. The server calls both when changing the feed:

```text
DirectorPC.SetViewTarget(NewTarget);
DirectorPC.ClientSetViewTarget(NewTarget);
DirectorPC.bBehindView = True;
DirectorPC.ClientSetBehindView(True);
```

`ClientSetBehindView` is also a replicated event, so the client camera mode
matches the server's authoritative view state. The Interaction separately
sets `bBehindView = True` if a target exists, to recover from any local state
reset (for example, a stock spectator input path).

## 7. `AddShieldStrength()` is the clean Super Shield equivalent

`Pawn.AddShieldStrength(int Amount)` returns `bool` and enforces the shield
limit. Spawning a `SuperShieldPack` actor would add pickup physics, respawn
logic and a second source of truth for shield state. The direct call gives the
same +100 result without an intermediate actor.

Painkillers are the exception: `Health` has no setter with a 300 cap, so the
mutator assigns the field directly:

```text
T.Health = Max(T.Health, 300);
```

## 8. Berserk is a pawn flag plus a weapon hook

`xPawn.bBerserk` is replicated to the owner and changes weapon firing behavior.
The stock combo path also calls `Weapon.StartBerserk()` / `StopBerserk()`. The
ReplicationInfo applies both and keeps a 30-second timer so the buff is always
removed, even if the fighter changes weapons.

## 9. Optional content needs `DynamicLoadObject`

`OnslaughtBP.ONSDualAttackCraft` is bonus-pack content. A hard class literal
would make the mutator fail to load on installs without that package. The
vehicle slot therefore resolves strings:

```text
VClass = class<Vehicle>(DynamicLoadObject(Requested, class'Class'));
if (VClass == None && Fallback != "")
    VClass = class<Vehicle>(DynamicLoadObject(Fallback, class'Class'));
```

`Onslaught.ONSHoverTank` (Goliath) is stock and used for the heavy slot.
`UT2k4Assault.ASVehicle_Sentinel_Floor` is stock and used for the turret.

## 10. Placement needs explicit clearance work

There is no stock `FindSpot()` helper with cylinder clearance semantics in
UT2004. The mutator implements its own:

- **Floor:** a downward box trace (`Trace` with `Extent`) for a walkable
  surface whose `HitNormal.Z >= 0.55`.
- **Body:** `SpotIsFree()` scans `CollidingActors` for `Pawn` and blocking
  `Actor` overlaps using combined collision radii.
- **Ceiling:** an upward box trace above the spot; a blocking hit between the
  floor and the requested body height rejects the spot.
- **Recall:** the same idea plus a ring of candidate offsets around the team
  anchor, 18 attempts per teammate, with spacing derived from the teammate
  index and attempt number.

A rejected drop returns `False` before `StartCooldown()` is called, so
`Not enough space.` never costs the Director a cooldown.

## 11. `ReplicationInfo` is a good owner-only RPC carrier

`DirectorReplicationInfo` uses the pattern proven by the FragFeedback project:

- spawn it on the server with the `PlayerController` as `Owner`;
- `bOnlyRelevantToOwner=True`, `bAlwaysRelevant=False`;
- `RemoteRole=ROLE_SimulatedProxy`;
- on the owning client, `PostBeginPlay` (listen server/standalone) or
  `PostNetBeginPlay` (network client) attaches a local `Interaction`;
- `Destroyed()` detaches it;
- bounded `SetTimer(0.25, true)` retries cover the case where the client's
  `Player`/`InteractionMaster` is not ready yet.

The owner's client receives the replicated cooldowns and target; no other
client does.

## 12. UnrealScript compiler quirks encountered

These are practical notes for future edits:

- `Trace()` extent arguments must be a `vector` variable, not an inline
  `vect(...)` expression with arithmetic in one component.
- `vect(0,0,expr)` with arithmetic in the third component can trip the parser;
  assign to a local vector and set `.Z` afterward.
- Do not cast values that are already `float` to `float`; UCC reports
  `No need to cast 'FloatProperty' to itself`.
- `DynamicActors(class'Actor', A)` with a concrete subclass literal caused a
  class-type mismatch in this compiler build. Scan with `class'Actor'` and cast
  inside the loop.
- `%` and `*` have the same precedence and evaluate left-to-right. Write
  `56.0 * (Index % 3)`, not `56.0 * Index % 3`.
- `FLOAT` is accepted as a type name in the stock `Interaction.KeyEvent`
  signature; keep the signature identical to `Engine.Interaction` when
  overriding it.
- Local variables must be declared at the top of the function (no
  mid-function `local` declarations). This caused several "Local is not
  allowed here" errors during development.
- Ternary `A ? B : C` is not supported for function arguments; use a local
  variable instead.
- A `const` and a `var` whose names differ only by case (for example
  `TD_BINDVERSION` and `TD_BindVersion`) collide: UCC reports a duplicate
  declaration. Pick genuinely different identifiers (`TD_BINDCURRENT`).
- Arithmetic is not accepted inside a `vect(...)` argument; assign the vector
  to a local and modify `.Z` (or build it in steps).

## 13. `ReceiveLocalizedMessage` is reliable and runs `ClientReceive` client-side

`Engine.PlayerController` declares:

```text
reliable if (Role == ROLE_Authority)
    ClientMessage, TeamMessage, ReceiveLocalizedMessage, QueueAnnouncement;
```

So a `LocalMessage` subclass can act as a script hook on the owning client:

```unrealscript
class DirectorBindKeyMessage extends LocalMessage;

static function ClientReceive(PlayerController P, optional int Switch, ...)
{
    P.ConsoleCommand("set Input K mutate director");
}
```

The server calls `PC.ReceiveLocalizedMessage(class'DirectorBindKeyMessage', 0)`
and the client's static `ClientReceive` runs there. This is the mechanism used
to install the automatic **K** bind without replacing `PlayerControllerClass`,
which is what keeps GTAThirdPerson and other controller-owning mutators
compatible. `GetString()` returns `""` and `GetLifeTime()` returns `0`, so the
message is never drawn.

Binds are written exactly like the stock GUI does it:
`KEYBINDING K` to read, `set Input K mutate director` to write. UT2004 has no
`bind` console command.

Sending it from `MutTechDirector.ModifyPlayer()` means it fires on every spawn,
so a late joiner or an overwritten bind self-heals on the next respawn.

## 14. Native team beacons are not usable as custom nameplates

Floating team beacons (`TeamBeaconMaxDist`, `TeamBeaconPlayerInfoMaxDist`) are
range-gated (6000 units for the icon, 1800 for the player info) and carry only
name/health from the stock HUD path; they cannot show shield and cannot be
forced always-visible from a mutator. The Director therefore zeroes both
distances while the booth is open (saving and restoring the originals in
`Cleanup()`) and draws its own three-line plates through walls instead.

## 15. Sentinel spawn origin and height

`UT2k4Assault.ASVehicle_Sentinel_Floor` is placed through the same
`FindVehicleSpot(P, 90.0, 70.0, Spot, 2.0)` path as the vehicle drops. The
spawn height had to be settled empirically:

- the sentinel base wants to sit on the floor, so the search uses a half-height
  of `70.0` and the feet fallback is
  `P.Location.Z - P.CollisionHeight + 70.0 + 2.0`;
- spawning it at the pawn's centre or at head height leaves it hovering or
  intersecting the ground, so the `-CollisionHeight + 70 + 2` formula is the
  one that lands cleanly on flat and mildly sloped terrain.

The sentinel is made walk-through (`SetCollision(True, False)` on turret, base
and swivel) so it can be shot but never traps or telefrags, and it is
team-locked with `SetTeamNum(Team)` / `bTeamLocked = True`.

## 16. Server smoke test

A dedicated server run with:

```text
UCC.exe server DM-Rankin?game=XGame.xTeamGame?mutator=MutTechDirector.MutTechDirector
```

started cleanly, reported:

```text
Mutators MutTechDirector.MutTechDirector
```

and produced no UnrealScript runtime errors. Unrelated install noise
(`LiandriExchange`, missing `Infestation` package for an unrelated map summary,
master-server DNS failures) appears in this install regardless of the mutator.

## 17. What was deliberately not done

- No custom `HUD` subclass: the brief asks for an `Interaction`, and avoiding a
  HUD replacement keeps compatibility with every team gametype.
- No `PlayerController` subclass: the K bind rides on a `LocalMessage`, so
  controller-replacing mutators (GTAThirdPerson) are unaffected.
- No `BecomeSpectator()`: it would remove the player from the team roster and
  defeat the roster-count requirement.
- No direct editing of `UT2004.ini` outside the build script's guarded
  temporary edit.
- No custom ammo actor spawning: `Weapon.AddAmmo()` is sufficient and works
  with stock ammo-instance behavior.