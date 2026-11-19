# Philosophy

## The fiction drives the mechanics

The Technical Director is not a spectator with admin powers. The fiction is a
broadcast booth: one person watches the team's live fighter feed, talks the
fighters through the match, and authorizes logistics that the arena's transmat
grid can physically deliver. Every design decision follows from that fiction.

- The Director has **no body on the floor**. A broadcaster is not a combatant.
- The Director sees through the **team's eyes**, not through walls as a free
  camera. The feed is locked to a living fighter in third-person.
- The Director's tools are **logistics**, not weapons: ammo, turrets, medical
  nanites, shields, stimulants, vehicles and an emergency recall.
- Drops arrive with **native Unreal effects and sounds**, so they feel like
  arena technology rather than menu commands.

## Support should cost commitment

The obvious failure mode for any spectator-support role is the "coach with
infinite strikes" problem: a player who never risks a pawn but continuously
buffs the team. MutTechDirector makes that impossible with a single rule:

> Every ability starts at its **full** cooldown when the booth comes online,
> and cooldowns only advance while the booth is occupied.

This has several consequences that are all intentional:

1. A player cannot hop in, fire a 120-second recall, and hop out.
2. Leaving the booth destroys the cooldown record. There is no way to bank
   progress while fighting.
3. The team pays for support with a missing fighter. The Director is trading
   presence on the floor for presence in the logistics channel.
4. Re-entering is allowed, but it is a **fresh commitment**, not a free reset
   of a partially charged ability.

The rule is enforced entirely on the server. The client HUD only displays what
the server replicates.

The cooldown ceilings are editable per player/server through **Configure
Mutators** (`Cooldown1..9`, default 1.0 s). Making them configurable is not a
retreat from the commitment rule: the reset-on-entry and paused-on-exit rules
still apply to whatever ceiling the server chooses, so a server can tune the
pace without breaking the "no banking" contract.

## The booth must not be an escape hatch

A support role that can be entered instantly turns into a dodge button: a
player caught in a losing fight presses the toggle and vanishes before the
killing blow. MutTechDirector closes that hole with a **mandatory 5-second
entry delay**:

- the countdown is server-side; the client only receives per-second popups;
- the player keeps fighting normally the whole time — the booth is off until
  the timer ends;
- dying during the delay cancels the entry;
- pressing the toggle again cancels it too;
- leaving the booth, once inside, remains instantaneous.

The delay is deliberately asymmetric. Getting in is a decision you have to
survive five seconds to commit to; getting out never punishes you. This makes
the booth a planned role change, not a panic button.

## Bind the key without owning the controller

The automatic **B** bind is implemented with an invisible `LocalMessage` whose
`ClientReceive` runs on the owning machine, triggered through the reliable
`ReceiveLocalizedMessage` RPC. That choice is philosophical as much as
technical: a universal mutator should not seize `PlayerControllerClass`.
Subclassing the controller would collide with Ultimate Third Person and any other mod
that already owns it. The message hook gets the same result — every client
binds B on spawn — while leaving the stock controller chain untouched.

## Server authority, client presentation

UnrealScript networking is easiest to reason about when there is exactly one
authority for every state transition. MutTechDirector follows that rule
strictly:

- The **server** decides whether the booth can open, which team the Director
  belongs to, which pawn is on the feed, whether a drop has clearance, whether
  a cooldown is ready, and what every ability does.
- The **client** captures raw input and sends *requests*. It never decides a
  target, a cooldown or a spawn.
- The **Interaction** draws telemetry. It is a presentation layer, not a
  gameplay authority. It cannot create items, heal anyone or move a pawn.

This is why `DirectorInteraction` calls `ServerCycleTarget`,
`ServerSetHealing`, `ServerUseAbility`, and `ServerLeaveDirector` rather than
acting locally. A malicious client can spam requests, but the server's
cooldown and target validation make spam harmless.

## Do not replace the gametype

A universal mutator must not require a custom gametype. Replacing or
subclassing `TeamGame` would immediately exclude custom team modes, break
server packages and create compatibility work forever. Instead:

- `MutTechDirector` is a normal `Mutator`.
- `DirectorRules` is a normal `GameRules` inserted into the existing chain.
- Team membership stays on the stock `TeamInfo`.
- Exit respawns through `Level.Game.RestartPlayer()`.
- The Director's pawn is removed with `UnPossess()` + `Destroy()`, not by
  calling `BecomeSpectator()` or editing the roster.

The only gametype assumption is `Level.Game.bTeamGame`, which is exactly the
contract the design brief asks for.

## Minimal surface, maximal reliability

The implementation prefers a smaller number of well-understood stock calls over
clever engine tricks:

- Camera zoom uses the stock `PlayerController.CameraDist` path that
  `CalcBehindView()` already consumes. No custom camera actor, no `SpecialCalcView`
  hijack, no rendering replacement.
- Healing writes `Pawn.Health` in controlled one-point pulses rather than
  spawning a custom emitter or replicating a per-frame float.
- Ammo uses `Weapon.AddAmmo()`, which works with both stock no-ammo-instance
  weapons and modded weapons that still use `Ammunition` actors.
- Berserk sets `xPawn.bBerserk` and calls `Weapon.StartBerserk()` / `StopBerserk()`,
  matching the stock combo behavior.
- Vehicles are loaded with `DynamicLoadObject` so a missing bonus pack cannot
  turn into a package-load failure.
- The entry delay is a plain `Tick()` countdown on the RI, not a timer actor or
  a gametype hook.
- The B bind reuses the reliable localized-message path instead of replacing
  the player controller.

## UI as telemetry, not as a HUD overhaul

The brief explicitly asks for a plain-text `Interaction`. That is also the
right engineering choice:

- It does not fight the gametype HUD for layout or font state.
- It works in every team gametype without knowing the HUD class.
- It can be attached and detached with the booth's `ReplicationInfo`.
- It can be drawn with the smallest possible API surface: `DrawText`, `StrLen`,
  `SetPos`, `WorldToScreen`, and `GetCameraLocation`.

The visual language is deliberately austere: monospaced small font, green for
ready, yellow/red for recharging, white for the active feed fighter. It reads
like a broadcast console, not a game menu.

The layout is split into four readable blocks:

- top-left: `[TECHNICAL DIRECTOR LOGISTICS]` hotbar with live cooldown states;
- top-right: a one-control-per-line cheatsheet;
- bottom-right: a `TeamMates` counter with `Alive` / `Dead` bands, so the
  Director can read the team's health at a glance without opening a scoreboard;
- over each teammate: three centred lines (`Name`, `HP [n]`, `Shield [n]`),
  team-coloured and always visible, because stock team beacons are range-gated
  and carry no shield data.

Both upper blocks use a 24 px margin so the console reads as one deliberate
frame rather than a pile of floating labels.

## Safety around the player's install

A mutator that breaks the game install is not a mutator; it is a liability.
The build pipeline therefore:

- never edits a `.u` package directly;
- keeps source in the project and syncs it into a disposable class directory;
- backs up `UT2004.ini` before registering the package;
- restores the backup through traps on normal exit, error, interrupt and
  termination;
- verifies the compiled `.u` exists before reporting success;
- keeps release copies in `prebuilt/System/` instead of relying on the live
  install as the only artifact.

The game install is a build target, not a source of truth.

## Vehicle placement: simple and honest

The new placement algorithm is deliberately simple:

```unrealscript
// Try positions in order:
// 1. 150 UU in front of player
// 2. Player's exact location
// 3. Circle at 150 UU (8 directions)
// 4. Circle at 300 UU (8 directions)
// First valid spot wins
```

Each candidate goes through `TrySpawnSpot()`:

1. **Box trace down** from 1000 UU above → find ground (HitNormal.Z > 0.7)
2. **Box trace verify** at found ground (50 UU sweep)
3. **Overlap check** - no actors in vehicle cylinder (1.1× radius)
3. Returns `Spot = FloorLoc + Height + 25`

No expanding rings, no radial staggering, no line traces, no ceiling sweeps.
Fixed candidate order = predictable, deterministic. Early exit on first valid
spot = faster.

If all positions fail, the player sees "Not enough space" and the cooldown is
not consumed. This is honest: if the arena doesn't have room, the transmat
grid cannot deliver.

## Respawn compatibility

Two different respawn-delay systems exist in the UT2004 ecosystem:

- **Vanilla**: `DeathMatch.RestartPlayer()` refuses to spawn a PRI with
  `bOutOfLives = True`.
- **ut2k4rd/RespawnDelay**: detects fresh deaths by looking for controllers
  with no pawn in `Dead`/`Spectating` state and `PRI.bOutOfLives == False`.

MutTechDirector sets `bOutOfLives = True` on booth entry, re-asserts it every
tick while the booth is active, and clears it on exit just before calling
`RestartPlayer()`. This makes the Director invisible to both systems while in
the booth, and ensures a clean respawn on exit.

If a round reset (Assault/Onslaught) hands the Director a fresh pawn while the
booth is active, `DirectorReplicationInfo.Tick()` detects it and suppresses
the stray pawn without scoring a death.

## No magic, no hidden state

Every mechanic is traceable to a specific function call:

- `ToggleDirector()` → `StartEntryDelay()` / `ExitDirectorMode()`
- `TickEntryCountdown()` → `CompleteEntry()` → `ActivateBooth()`
- `UseAbility()` → `CheckCooldown()` → `StartCooldown()`
- `GetMaxCooldown()` → replicated `MaxCooldowns[]` from the config
- `ModifyPlayer()` → `DirectorBindKeyMessage.ClientReceive()` → `set Input B …`
- `TrySpawnSpot()` → `Trace()` → `Trace()` → `CollidingActors()`
- `Tick()` → `Cooldown -= DeltaTime` (server only)
- `UpdateTeamCounts()` → `TeamAlive` / `TeamDead`
- `ClientCloseBooth()` → `Cleanup()` → `RemoveInteraction()`

There is no global state, no singletons, no `static` variables, no hidden
timers. If something breaks, the log tells you exactly which check failed and
where.