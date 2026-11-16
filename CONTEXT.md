# Project Context

Session-oriented notes for continuing work on MutTechDirector.

## What this is

A UT2004 v3374 mutator that adds a team support role, **Tournament Technical
Director**, with:

- `mutate director` enter/exit;
- pawn suppression while keeping team roster identity;
- server-authoritative cooldowns that reset on entry and pause on exit;
- third-person locked camera on living teammates, auto-cycling after 1 s;
- wheel feed cycling and 120–1500 unit zoom;
- Jump-heal and nine configurable transmat abilities;
- client-side `Interaction` hotbar, controls and friendly nameplates.

Original specification: `prompt.txt`.

## Important paths

| Path | Purpose |
|---|---|
| `source/MutTechDirector/Classes/` | canonical UnrealScript source |
| `install/MutTechDirector.int` | mutator metadata/localization |
| `tools/build.sh` | safe sync + compile + install |
| `prebuilt/System/` | compiled release copies |
| `docs/` | philosophy, findings, approach, roadmap |
| `/home/jdmr/Juegos/UT2004` | local Windows-edition game install |
| `/home/jdmr/Juegos/UT2004/System/UCC.exe` | compiler |
| `/home/jdmr/Juegos/UT2004/System/UT2004.ini` | temporary `EditPackages` target |
| `/home/jdmr/Juegos/UT2004/MutTechDirector/Classes/` | build-time sync target |
| `ut2k4tp/reference/` (sibling project) | decompiled stock source |
| `ut2004fragfeedback/` (sibling project) | proven RI + Interaction pattern |

## Build

```bash
cd /home/jdmr/Proyectos/ut2k4mutators/TeamDirector
./tools/build.sh
```

Override install path with `UT2004_DIR=/path/to/UT2004`.

The script backs up `UT2004.ini`, appends `EditPackages=MutTechDirector` after
the **last** existing `EditPackages` line, compiles, exports the `.ucl`,
installs the `.int`, copies artifacts to `prebuilt/System/`, and restores the
INI via a trap.

### Critical gotcha

Do **not** insert `EditPackages=MutTechDirector` immediately after
`[Editor.EditorEngine]`. The package must compile after `Engine`, otherwise:

```text
Superclass Interaction of class DirectorInteraction not found
```

The build script handles this correctly.

## Current verification state

- `UCC.exe make`: **0 errors, 0 warnings**.
- `UCC.exe exportcache MutTechDirector.u`: successful.
- Dedicated server smoke test on `DM-Rankin?game=XGame.xTeamGame` with the
  mutator: clean load, no UnrealScript runtime errors.
- `UT2004.ini` restored after build (zero `EditPackages=MutTechDirector`
  entries).
- Artifacts present in `prebuilt/System/`.
- **Not yet done:** live multi-client playtest of input/camera/HUD and all
  abilities in CTF/ONS/AS/BR/DOM.

## Design invariants (do not break)

1. Server is the only authority for target, cooldown, placement and pawn state.
2. Never call `BecomeSpectator()`; keep the player on `TeamInfo`.
3. `mutate director` toggling must not despawn bots or change team roster size.
4. Exiting must use `Level.Game.RestartPlayer()`.
5. Cooldowns live on `DirectorReplicationInfo`; destroy the RI on exit so
   progress cannot be banked.
6. Failed placement or invalid target must **not** start a cooldown.
7. UI is a plain `Engine.Interaction` with `Canvas.DrawText`; do not replace
   the HUD.
8. Do not edit retail `.u` packages or leave `UT2004.ini` modified.

## Class map

- `MutTechDirector.uc` — mutator, enter/exit, abilities, placement, FX.
- `DirectorReplicationInfo.uc` — replicated state, cooldowns, RPCs, heal,
  berserk timer, auto-cycle, Interaction attach.
- `DirectorInteraction.uc` — raw input, camera zoom, hotbar/cheatsheet/
  TeamMates counter/nameplates, native beacon suppression.
- `DirectorBindKeyMessage.uc` — invisible LocalMessage whose client-side
  `ClientReceive` binds K -> `mutate director` (no PlayerController subclass).
- `MutTechDirectorConfig.uc` — Configure Mutators submenu for the cooldowns.
- `DirectorRules.uc` — fallback `FindPlayerStart`.

## Key implementation facts

- `Interaction` is `Engine.Interaction`.
- `CameraDist` is a multiplier: `CameraDist * target.Default.CollisionRadius`.
  Interaction converts desired world units to that multiplier.
- `PlayerController.UnPossess()` already enters `Spectating`.
- `Pawn.AddShieldStrength(100)` is the Super Shield equivalent.
- `xPawn.bBerserk` + `Weapon.StartBerserk()/StopBerserk()` is the stock combo
  path.
- `PlayerStart.TeamNumber` is the team-start field; there is no
  `TeamPlayerStart` class.
- `CTFBase` is in `UnrealGame`; `ONSPowerCore` in `Onslaught`;
  `ASVehicle_Sentinel_Floor` in `UT2k4Assault`; `ONSHoverTank` in `Onslaught`;
  `ONSDualAttackCraft` in `OnslaughtBP`.
- Vehicle classes use `DynamicLoadObject` to survive missing bonus content.
- Recall prefers `CTFBase`, then `ONSPowerCore` (`bFinalCore` first), then
  team-tagged `PlayerStart`.

## UnrealScript compiler quirks already fixed

- No redundant `float(...)` casts (`No need to cast 'FloatProperty' to itself`).
- No `vect(0,0,expr)` with arithmetic; assign `.Z` on a local vector.
- `Trace` extent must be a vector variable, not inline arithmetic.
- `%`/`*` are left-associative at the same precedence; parenthesize.
- `DynamicActors(class'Actor', A)` + cast instead of a concrete subclass
  literal in some cases.

## Smoke-test command

```bash
cd /home/jdmr/Juegos/UT2004/System
timeout 50 wine UCC.exe server \
  'DM-Rankin?game=XGame.xTeamGame?mutator=MutTechDirector.MutTechDirector' \
  -log=/tmp/opencode/mtd-server.log -nohomedir
```

Expect `Mutators MutTechDirector.MutTechDirector` in the log. Ignore this
install's unrelated `LiandriExchange`, `Infestation` and master-server DNS
noise.

## Current state of vehicle placement

`DropVehicle()` (slots 6/7/8) — ground trace with feet fallback and driver forcing.
Spawned vehicles are fully solid; there is no ghost/passthrough state for them:

```unrealscript
function bool DropVehicle(Pawn P, byte Team, string VClassName, string VClassFallback, int Slot, optional DirectorReplicationInfo RI)
{
    // 1. Load vehicle class via DynamicLoadObject with optional fallback.
    // 2. Level.Game.bAllowVehicles = True (engine-safe instantiation).
    // 3. FindVehicleSpot(P, Radius, Height, Spot):
    //      - Single box trace from P.Z + 200 down to P.Z - 1000 at P's XY.
    //      - Accept if HitNormal.Z > 0.7 (real upward-facing ground).
    //      - Spot = FloorLoc + Height + 25 (vehicle bottom clears ground).
    //      - If trace fails (overhead mesh, depressions), fall back to
    //        P.Location + vect(0,0,40.0) (pawn's feet).
    // 4. Spawn(VClass,,, Spot, P.Rotation), set team + bTeamLocked.
    // 5. Force driver: if P has a controller and isn't already in a vehicle,
    //    call V.KDriverEnter(P) so the spectated teammate is instantly in the
    //    driver seat (prevents self-telefrag).
    // 6. DeployFX spawn flash.  No collision changes: the vehicle is solid.
    // On total spawn failure: refund cooldown slot, send "Not enough space."
}
```

Slot layout (all cooldowns currently 1.0 s, tuned in
`DirectorReplicationInfo.GetMaxCooldown()`):
- **Slot 6**: SPMA Artillery (`OnslaughtBP.ONSArtillery`)
- **Slot 7**: Cicada/Raptor (`OnslaughtBP.ONSDualAttackCraft` → `Onslaught.ONSAttackCraft`)
- **Slot 8**: Hover Tank (`Onslaught.ONSHoverTank`)
- **Slot 9**: Emergency Recall

Telefrag mitigation summary:
- **Selected player**: Forced into driver seat via `KDriverEnter(P)` — cannot be
  telefragged by their own spawn.
- **All spawned vehicles**: Fully solid.  Earlier ghost/passthrough behaviour was
  removed because it let players stand inside vehicles and get telefragged when
  collision returned, and it made vehicles unshootable.
- **Visual**: `DeployFX` spawn flash only.

`DeploySentinel()` (slot 2) — perimeter sentinel placement:
- Uses `FindVehicleSpot(P, 90.0, 0.0, Spot, 2.0)` + feet fallback instead of the
  old ring-based `FindClearSpot`, so sentinel drops succeed on the same ground
  trace logic as vehicle transmats.
- Height bug fixed: the old call passed `Height = 110.0` with the helper's fixed
  `+25`, putting the turret origin 135 units above the floor.  The Floor Sentinel
  is not centre-origin: its gun is drawn above the origin and the static base
  hangs below it.  `ASVehicle_Sentinel_Floor_Base` has `CollisionHeight = 100`
  (a half-extent), and the drawn base bottom sits a little above the collision
  cylinder bottom, so the origin sits `70` units above the deck:
  `Height = 70`, `GroundClearance = 2`.
- The feet fallback is also floor-correct now: `P.Location` is the pawn's
  centre, so it uses
  `P.Location.Z - P.CollisionHeight + BaseHalfHeight + 2`.  Sentinels have
  `bSimulateGravity=False`, so a wrong Z never settles and stays visibly
  floating (or buried).
- `FindVehicleSpot()` gained an explicit `GroundClearance` parameter; vehicle
  transmats pass `25.0` (unchanged behaviour), the sentinel passes `2.0`.
- Spawns `MutTechDirector.DirectorSentinel` (subclass of
  `ASVehicle_Sentinel_Floor`), which is **always walk-through**: turret, static
  base and swivel all use `SetCollision(True, False)` (`bCollideActors` keeps
  hitscan/projectile hits; `bBlockActors = False` prevents trapping and
  telefrags).  The base is where the real 96x100 collision volume lives, which
  is why the stock turret could still trap players after only the gun actor was
  made passable.

## Booth HUD layout

All drawing happens in `DirectorInteraction.PostRender` (no HUD subclass), with
a uniform **24 px top margin** for the two upper blocks:

- **Top-left:** `[TECHNICAL DIRECTOR LOGISTICS]` hotbar, `X=24`,
  `Y=24`, one line per ability (header + Nanite row + slots 1-9).
- **Top-right:** controls cheatsheet, right-aligned at `C.ClipX - 24`, one
  control per line (`24 + n*LineH`), no `|` separators.
- **Bottom-right:** live `TeamMates` counter, right-aligned, anchored at
  `ClipY - 14 - (8/7/6 * LineH)` so it keeps the old cheatsheet uplift above the
  chat area and the "Now spectating..." banner.  Header word `TeamMates` is cyan.
  - `TeamAlive`/`TeamDead` are server-authoritative replicated ints on
    `DirectorReplicationInfo`, recounted every 0.5 s from `Level.ControllerList`
    (director excluded, spectators excluded, bots included, same `DirectorTeam`).
    A teammate with no pawn or a dead corpse counts as Dead, so
    Alive + Dead equals the whole team.
  - Band scale (`RatioColor`): 0-25 % red, 25-50 % yellow, 50-75 % orange,
    75-100 % green.  Dead feeds `1 - ratio` through the same scale, so the two
    lines move inversely (healthy roster green/green, wiped roster red/red).
- **Nameplates:** three centred lines per living teammate —
  `Name` / `HP [n]` / `Shield [n]` — never left/right aligned, and drawn without
  occlusion or range tests.  Colours: blue team `rgb(51,102,255)`, red team
  `rgb(255,0,0)`; the fighter on the broadcast feed uses the brighter selected
  variant (blue `rgb(51,204,255)`, red `rgb(255,153,51)`).

Native floating team beacons are suppressed for the director's
`PlayerController` (`TeamBeaconMaxDist = 0`,
`TeamBeaconPlayerInfoMaxDist = 0`) and restored in `Cleanup()`: they are
range-gated (6000 / 1800 units), carry no HP/shield and cannot be made
always-visible from script, so the custom plates replace them entirely.

## Booth entry, K bind and cooldown configuration

- **K toggles the booth, with no PlayerController subclass.**  `ModifyPlayer()`
  sends the invisible `DirectorBindKeyMessage` (a `LocalMessage`) to the pawn's
  controller on every spawn.  `PlayerController.ReceiveLocalizedMessage` is a
  **reliable** RPC, and `LocalMessage.ClientReceive` executes on the owning
  machine, where it runs `set Input K mutate director` (after checking
  `KEYBINDING K`), exactly like the stock GUI writes binds.  This works for the
  host and joining clients, needs no `PlayerControllerClassName` override, and
  therefore keeps controller-replacing mutators (GTAThirdPerson) fully
  compatible.  A missed or manually overwritten bind self-heals on the next
  spawn.
- **Mandatory 5 s entry delay, instant exit.**  `ToggleDirector()` spawns the
  RI immediately but `BeginEntryCountdown()` keeps `bDirectorActive = False`
  for `TD_ENTRY_DELAY` (5 s).  `DirectorReplicationInfo.TickEntryCountdown()`
  pushes "Entering Technical Director booth in X..." through the normal
  `ClientNotify` RPC once per second, then calls
  `MutTechDirector.CompleteEntry()`, which performs the actual booth
  activation (leave vehicle, unpossess, destroy pawn, spectate, set feed).  Pressing K again cancels; dying during the delay cancels too (that is
  the point of the delay: it cannot be used to dodge an imminent death).
  Exiting is never delayed.
- **Cooldowns are configurable.**  `MutTechDirector` is `config(User)` and
  carries `Cooldown1..9` (`var() config float`, all defaulting to 1.0 s).
  `ConfigMenuClassName="MutTechDirector.MutTechDirectorConfig"` adds the
  Configure Mutators submenu (9 `moEditBox`es, OK / Reset, clamped 0-120 s,
  saved with `StaticSaveConfig()`; changes apply on the next match).
  The RI copies the nine values into its replicated `MaxCooldowns[9]` at
  entry-countdown start, so `GetMaxCooldown()` is correct on the HUD client
  as well as on the server.

## Client HUD notifications

`Notify()` no longer sends a server-created `DirectorNotifyText` as
`ReceiveLocalizedMessage(OptionalObject)`: that object only exists on the
server, so remote clients received `None` and drew nothing.  Notifications now
travel as a reliable string RPC, `DirectorReplicationInfo.ClientNotify(string)`,
which builds the wrapper on the owning client and renders the same top-of-screen
`DirectorNotify` line.  Booth teardown reuses the same path through
`ClientCloseBooth(optional string NotifyText)`.

## Current build state

- **Package hash:** `768c3af7247be7bb37acfacda4a7942e2f60449edd4f3f0b7f18ee9f1a0f2db2`
- **Installed:** `/home/jdmr/Juegos/UT2004/System/MutTechDirector.u`, `.ucl`, `.int`
- **UT2004.ini:** Clean (no `EditPackages=MutTechDirector`)
- **Warnings:** None (0 errors, 0 warnings). `FindClearSpot` dead-code / unreferenced-local warnings removed with the algorithm rewrite.

## Source hashes at last build

```text
3d5057fd47922759e75bfcb62bfb6f4345412ad23d8480288fd595f58151bf70  DirectorBindKeyMessage.uc
917b74d6480939bbe080c40bdb5a7f8cb184a9060679ed8e7a482b8f34c97b15  DirectorInteraction.uc
06699d1cc107d1f0350aa985287966f684e82363ef78afb6e377f37fb3925911  DirectorNotifyText.uc
0b14e76addd69ca2833d2e1c62e01beadd9222edf9e6ee60cdf360a41b83ce73  DirectorNotify.uc
81ce8347e9415d0ef1b2acc2c9ae928ffd4117810fe2ceb0ec3cb2b347bc0ff3  DirectorReplicationInfo.uc
9d826eb1c12e23163440e9f73b16ef9935709f7043ac77e6337e62f679d49648  DirectorRules.uc
09fba41044bb77c641768adeedad6214e2e1998b137d4ab4d4979d517e5d0035  DirectorSentinel.uc
054b3b94726b1e8b0ea6c91c62af04d55af11044c846bd5c1e44451286131a59  MutTechDirectorConfig.uc
3b28a6e97ac5693c1694916f3df2db0a0314ccb8a4eb39525ffe42ee19aa44e9  MutTechDirector.uc
```

If source changes, rerun `./tools/build.sh` and update these hashes and
`prebuilt/BUILD`. Do not compare `.u` hashes across builds: UCC may embed
build-time data, so the binary hash is not a stable content identifier.