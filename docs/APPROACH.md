# Approach

## 1. Architecture at a glance

```text
                       SERVER (authority)
 ┌──────────────────────────────────────────────────────────────┐
 │ MutTechDirector (Mutator, config(User))                      │
 │   • mutate director -> start 5 s delay / instant exit        │
 │   • FindTeammate / FindHomeLocation                          │
 │   • UseAbility -> ammo, sentinel, health, shield, berserk,   │
 │     vehicles, team recall                                    │
 │   • placement traces + native FX                             │
 │   • Cooldown1..9 config defaults (Configure Mutators)        │
 │   • ModifyPlayer -> sends DirectorBindKeyMessage             │
 │                                                              │
 │ DirectorReplicationInfo (ReplicationInfo, one per director)  │
 │   • bBoothPending, EntryTimeLeft, bDirectorActive            │
 │   • DirectorTeam, CurrentTarget                              │
 │   • Cooldown1..9 + replicated MaxCooldowns[9] (ticked)       │
 │   • TeamAlive / TeamDead (0.5 s roster recount)              │
 │   • bHealing, heal accumulator, berserk timer                │
 │   • server RPC implementations + entry countdown             │
 └───────────────────────────┬──────────────────────────────────┘
                             │ owner-only replication
                             ▼
                      CLIENT (owner)
 ┌──────────────────────────────────────────────────────────────┐
 │ DirectorReplicationInfo (replicated copy)                    │
 │   • attaches DirectorInteraction on PostBeginPlay /          │
 │     PostNetBeginPlay                                         │
 │                                                              │
 │ DirectorInteraction (Engine.Interaction)                     │
 │   • raw key/mouse capture -> server RPCs                     │
 │   • CameraDist zoom                                          │
 │   • plain-text PostRender telemetry, TeamMates counter,      │
 │     three-line friendly nameplates                           │
 │                                                              │
 │ DirectorBindKeyMessage (LocalMessage)                        │
 │   • ClientReceive -> set Input B mutate director             │
 └──────────────────────────────────────────────────────────────┘
```

`DirectorRules` sits beside the mutator in the `GameRules` chain and only
provides a fallback `FindPlayerStart()`. `MutTechDirectorConfig` is a
`GUIPage` opened by the mutator list's **Configure Mutators** button.

## 2. Class responsibilities

### `MutTechDirector.uc`

The only class allowed to change the world or a pawn. It owns:

- the `Directors` array (`DirectorReplicationInfo` per active booth);
- enter/exit sequencing, including the mandatory 5 s entry delay
  (`StartEntryDelay` / `CompleteEntry`);
- team and roster checks;
- feed target selection (`FindTeammate`);
- ability dispatch and cooldown start/validation;
- ammo, sentinel, vehicle and recall implementations;
- home-anchor lookup for recall;
- clearance traces;
- native deployment effects;
- the `config(User)` cooldown defaults `Cooldown1..9` edited by
  `MutTechDirectorConfig`;
- `ModifyPlayer()` shipping the invisible `DirectorBindKeyMessage` to every
  spawn.

It does **not** draw anything and does **not** read client input directly.

### `DirectorReplicationInfo.uc`

The replicated per-player record and the server-to-client bridge. It owns:

- booth state: `bBoothPending`, `EntryTimeLeft`, `bDirectorActive`, team;
- the 5 s entry countdown (`TickEntryCountdown`);
- the current feed pawn;
- nine cooldown floats plus the replicated `MaxCooldowns[9]` ceiling copied
  from the mutator config;
- the live `TeamAlive` / `TeamDead` roster tally;
- healing state and accumulator;
- berserk pawn and expiry timer;
- auto-cycle timing after a feed loss;
- client Interaction attach/detach;
- `ServerCycleTarget`, `ServerSetHealing`, `ServerUseAbility`,
  `ServerLeaveDirector` RPCs;
- `ClientSwitchSound` RPC;
- HUD helper `GetFriendlyPawns()`.

It deliberately calls back into `MutTechDirector` for abilities instead of
duplicating spawn logic.

### `DirectorInteraction.uc`

A client-only `Engine.Interaction` with four jobs:

1. **Input**: wheel, `1`–`9`, Space, left/right mouse.
2. **Camera**: maintain `ZoomDistance` and write `PC.CameraDist` each tick.
3. **Telemetry**: draw the top-left hotbar, top-right controls, bottom-right
   `TeamMates` counter and the three-line friendly nameplates.
4. **Beacon suppression**: zero `TeamBeaconMaxDist` /
   `TeamBeaconPlayerInfoMaxDist` while the booth is open and restore the saved
   values in `Cleanup()`.

It never spawns actors or changes another pawn's state.

### `DirectorBindKeyMessage.uc`

An invisible `LocalMessage`. Its `ClientReceive` runs on the owning machine
because `PlayerController.ReceiveLocalizedMessage` is a **reliable** RPC, and
writes `set Input B mutate director` (after checking `KEYBINDING B`) exactly
like the stock GUI. This gives every client the B bind with no
`PlayerController` subclass, so controller-replacing mutators such as
GTAThirdPerson stay compatible. It draws nothing (`GetString` returns `""`,
`GetLifeTime` returns `0`).

### `MutTechDirectorConfig.uc`

A `GUIPage` reached through
`ConfigMenuClassName="MutTechDirector.MutTechDirectorConfig"`. Nine
`moEditBox`es (slots 1–9) plus OK and Reset; values are clamped to 0–120 s,
written to `class'MutTechDirector'.default` and saved with
`StaticSaveConfig()`. Changes apply to the next match (the RI copies them at
countdown start).


### `DirectorRules.uc`

A tiny `GameRules` that returns a safe team start if the stock chain fails. It
calls `Super.FindPlayerStart()` first, then tries:

1. `PlayerStart.TeamNumber == team`;
2. neutral/default start (`255` or `0`);
3. any enabled `PlayerStart`.

Returning `None` remains safe: the stock chain continues unchanged.

## 3. Entering the booth

Entry is split into a mandatory delay and the actual booth activation.

Sequence in `MutTechDirector.ToggleDirector(PC)`:

1. **Validate** `PC`, its PRI, a team game and a real team.
2. **Refuse** spectators and deleted controllers.
3. If an RI already exists:
   - active → `ExitDirectorMode()` (instant);
   - pending → `AbortPendingEntry()` (second B press cancels the countdown).
4. Otherwise call `StartEntryDelay(PC)`.

`StartEntryDelay()` spawns the owner-only `DirectorReplicationInfo`
immediately (so the client can already receive popups) and calls
`BeginEntryCountdown(Self, PC, TeamIndex, TD_ENTRY_DELAY)`:

- `bBoothPending = True`, `bDirectorActive = False` — **the player keeps
  playing normally**;
- `EntryTimeLeft = 5.0`, `LastEntrySecond = 5`;
- all nine configured cooldowns are copied into `MaxCooldowns[9]`;
- `UpdateTeamCounts()` seeds the counter;
- the first `Entering Technical Director booth in 5...` popup is sent.

`DirectorReplicationInfo.TickEntryCountdown()` runs each tick while pending:

- if the Director's pawn dies during the delay, abort and notify
  (`Technical Director entry cancelled: you died.`) — this is the whole reason
  the delay exists;
- decrement `EntryTimeLeft`; whenever the whole-second value changes, push a
  new `Entering Technical Director booth in X...` popup;
- at zero, hand control to `MutTechDirector.CompleteEntry(RI)`.

`CompleteEntry()` is the old entry body:

1. Leave a vehicle first (`KDriverLeave(True)`) if entering from one.
2. `RI.ActivateBooth()` — clears `bBoothPending`, sets `bDirectorActive`,
   resets the nine cooldowns to their configured maxima.
3. **Keep roster identity**:
   - set `bOutOfLives = True` (hidden from respawn systems);
   - clear `bIsSpectator`;
   - do not remove the PRI from `TeamInfo`;
   - do not call `BecomeSpectator()`.
4. **Remove the body**:
   - `PC.UnPossess()`;
   - `OldPawn.Destroy()` if still valid (the pawn cannot be damaged or score a
     death, and cannot occupy a spawn).
5. **Enter spectator state** and set behind view.
6. **Pick the first feed** with `FindTeammate(PC, None, 1)`.
7. **Message** the player with the booth state and feed name.

The replication actor is spawned at the start of the countdown so the client
has the Interaction available the moment the booth opens.

## 4. Leaving the booth

`ExitDirectorMode(RI)`:

1. Mark the RI inactive and clear healing/berserk state.
2. Restore the local camera:
   - `bBehindView = False`;
   - `ClientSetBehindView(False)`;
   - `CameraDist = Default.CameraDist`;
   - view target self.
3. `RI.Destroy()`; client `Destroyed()` calls `DirectorInteraction.Cleanup()`,
   which removes the Interaction and restores `CameraDistRange`.
4. Remove the RI from `Directors`.
5. Clear `bOutOfLives`.
6. `Level.Game.RestartPlayer(PC)`.
7. If no pawn appeared, tell the player to press Fire.

Because cooldowns live on the destroyed RI, leaving is also the cooldown
"wipe". Re-entering creates a fresh RI with all slots at max.

Leaving is **instant**: no countdown, no penalty. Only entering has the
mandatory 5 s delay. A pending entry that is cancelled or interrupted never
opens the booth, so it cannot be used to escape an imminent death.

### Stray pawn suppression

Some gametypes restart every non-spectator controller at round boundaries
(Assault reinforcement resets and Onslaught link resets both do this). Since
the Director intentionally remains a non-spectator team member, one of those
resets can hand them a fresh pawn while the booth is still active.

`DirectorReplicationInfo.Tick()` therefore checks
`DirectorPC.Pawn != None` on the server and calls `SuppressStrayPawn()`:

1. `UnPossess()` the unexpected pawn;
2. `Destroy()` it (no kill credit, no scoreboard death);
3. return the controller to `Spectating`;
4. re-assert `bBehindView` / `ClientSetBehindView`;
4. re-apply the current feed target.

This keeps the booth stable across round transitions without touching the
gametype's respawn code.

## 5. Feed selection and cycling

`FindTeammate(PC, Current, Dir)`:

- iterates `AllControllers`;
- skips the Director, dead pawns, controllers without a PRI and other teams;
- builds a `List` of living teammate pawns;
- with `Current == None`, returns the first (or last for negative direction);
- otherwise finds `Current` in the list and wraps by `Dir`.

The server never trusts a client-supplied target. Wheel events only send a
direction (`-1`/`+1`).

`DirectorReplicationInfo.Tick()` watches the feed:

- if the target is `None`, deleted or dead, start a one-second timer;
- when it expires, try to find the next living teammate;
- if one exists, call `SetTarget()` and `ClientSwitchSound()`;
- if none exists, keep the last frame and retry once per second (no sound
  spam).

`SetTarget()` sets both the server and client view targets and behind-view
state.

## 6. Camera and zoom

The Interaction's `Tick()` runs only while `RI.bDirectorActive`:

1. Widen `PC.CameraDistRange` to `1..400` (stock is `3..40`).
2. Move `ZoomDistance` toward the held direction at 950 units/sec.
3. Clamp to `120..1500`.
4. Convert to the multiplier the stock camera expects:
   `CameraDist = ZoomDistance / target.Default.CollisionRadius` (using 40 as a
   fallback radius).
5. Clamp the multiplier to `1..400`.
6. Force `bBehindView = True` while a feed exists.

This feeds the stock `PlayerController.CalcBehindView()` path, so the camera
still respects world collision, view rotation and stock behind-view geometry.
No custom camera actor is involved.

Raw input mapping:

| Key | Event |
|---|---|
| `IK_MouseWheelUp` | `ServerCycleTarget(-1)` |
| `IK_MouseWheelDown` | `ServerCycleTarget(1)` |
| `IK_1`..`IK_9` | `ServerUseAbility(slot)` |
| `IK_Space` press/release | `ServerSetHealing(True/False)` |
| `IK_LeftMouse` press/release | local `bZoomIn` |
| `IK_RightMouse` press/release | local `bZoomOut` |
| `IK_MouseW` axis | wheel fallback with a 0.15 s debounce |

The Interaction consumes these events (`return True`) only while the booth is
active. Other keys fall through to the game/console.

## 7. Cooldowns

All values are floats in seconds on `DirectorReplicationInfo`. The **ceiling**
per slot is configurable per player/server through **Configure Mutators**
(`MutTechDirector.Cooldown1..9`, `var() config float`, each defaulting to
`1.0` s). The mutator copies them into the replicated `MaxCooldowns[9]` when
the entry countdown starts, so both the authority and the HUD client agree on
the values.

| Slot | Ability | Default |
|---|---|---|
| 1 | Ammunition Requisition | 1.0 s |
| 2 | Perimeter Defense | 1.0 s |
| 3 | Painkillers | 1.0 s |
| 4 | Blindage | 1.0 s |
| 5 | Stimuli Dose | 1.0 s |
| 6 | SPMA Artillery | 1.0 s |
| 7 | Light Vehicle Transmat | 1.0 s |
| 8 | Heavy Asset Drop | 1.0 s |
| 9 | Emergency Recall | 1.0 s |

`GetMaxCooldown(Slot)` returns `FMax(0.0, MaxCooldowns[Slot - 1])`, so `0`
means "always ready". The config page clamps edits to `0..120` s and saves
them with `StaticSaveConfig()`; new values apply from the next match.

`Tick()` decrements each positive cooldown by `DeltaTime` only when
`Role == ROLE_Authority && bDirectorActive`. The client does not simulate
cooldowns; it reads the replicated values and renders either `[READY]` or
`[Ns]`.

`UseAbility()` calls `CheckCooldown()` **before** executing the ability. On
success it calls `StartCooldown()`. On a rejected target or failed placement it
returns early, so the cooldown is not consumed.

## 8. Ability details

### Slot 1 — Ammunition Requisition

- Walk the fighter's inventory.
- For each `Weapon`, ask `GetAmmoClass(0)` and `GetAmmoClass(1)`.
- Skip a duplicate alternate ammo class within the same weapon.
- Use `Weapon.AddAmmo(Amount, modeIndex)` where `Amount` is
  `AmmoClass.Default.AmmoAmount` (or `InitialAmount`).
- Because `bNoAmmoInstances` weapons keep their own `AmmoCharge`, every weapon
  is topped up separately, even when several weapons share an ammo class.
- If no weapon accepts ammo, print a reason and do not start the cooldown.

### Slot 2 — Perimeter Defense

- `TrySpawnSpot()` seeks a floor point with cylinder room for a 90/110 body.
- Spawn `UT2k4Assault.ASVehicle_Sentinel_Floor`.
- `SetTeamNum(Team)`, `bTeamLocked = True`.
- Native deployment FX.

### Slot 3 — Painkillers

- `Health = Max(Health, 300)`; never lowers a fighter who is already above 300.
- FX at the fighter.

### Slot 4 — Blindage

- `AddShieldStrength(100)`.
- If the pawn refuses (already at maximum), print a reason; no cooldown.

### Slot 5 — Stimuli Dose

- `RI.ApplyBerserk(T)`:
  - `xPawn.bBerserk = True`;
  - `Weapon.StartBerserk()`;
  - 30-second timer on the RI.
- Spawn `XEffects.ComboActivation` and play `GameSounds.Combo.ComboActivated`
  to the Director.
- `ClearBerserk()` on expiry, exit or logout calls `bBerserk = False` and
  `Weapon.StopBerserk()`.

### Slot 6 — SPMA Artillery

- Resolve `OnslaughtBP.ONSArtillery`.
- Drop it at the fighter's feet through `DropVehicle()` (same clearance scan as
  the other vehicles).
- If no spot is found: print `Not enough space.` and leave the cooldown ready.

### Slots 7 and 8 — Vehicle Transmat

- Resolve the class:
  - light (7): `OnslaughtBP.ONSDualAttackCraft` → fallback
    `Onslaught.ONSAttackCraft`;
  - heavy (8): `Onslaught.ONSHoverTank`.
- Compute a safe cylinder radius/height from the vehicle defaults (minimum
  60/60).
- `TrySpawnSpot()` searches 18 candidate positions (front, player location,
  8×150UU ring, 8×300UU ring):
  - Box trace down from +1000UU with tall extent (Z=200) to find ground.
  - Verify with 50 UU box sweep at found ground.
  - Reject if `HitNormal.Z < 0.7` (bridge bottoms, walls).
  - Actor overlap check at `FloorLoc + Height + 25` with 1.1× radius.
- Spawn, set team, lock team, FX.
- If no spot is found: print `Not enough space.` and leave the cooldown ready.

### Slot 9 — Emergency Recall

- Collect all living teammate pawns (same team, not the Director).
- Find the team home:
  1. `CTFBase` with `DefenderTeamIndex == team`;
  2. `ONSPowerCore` with `DefenderTeamIndex == team`, preferring `bFinalCore`;
  3. `PlayerStart.TeamNumber == team`;
  4. neutral/default start.
- Preferred: each teammate gets its own distinct ring spot around the anchor,
  skipping spots already assigned in this recall.
- If **any** teammate cannot be placed there, abandon individual placement and
  send the **whole team** to one gametype emergency point:
  - CTF -> the team flag actor's exact location;
  - ONS -> the team's power core/node (final core preferred);
  - DOM / cDOM2 -> one randomly chosen **owned** `DominationPoint`. If the
    team owns none, this fallback explicitly fails and the Director gets the
    "Emergency recall failed: no safe team destination." popup; it does not
    silently substitute a spawn point;
  - Bombing Run -> one random team-base `PlayerStart`;
  - TDM / Invasion / other -> one random `PlayerStart` for everyone.
  This is the mitigation for objectives enclosed in tight geometry (e.g. a
  flag boxed in on five faces) instead of a silent failure.
- Fallback pawns get a **5 s** collision-transparency window; normal distinct
  placements get 3 s.  Before moving each pawn, `GrantRecallPass()` stores its
  collision state and disables collision (`SetCollision(False, False)`), then
  `FinishRecallPassMove()` restores trace/projectile collision immediately but
  keeps pawn blocking off. `MutTechDirector.Tick` restores the saved collision
  flags when the window expires.
- Absolute edge: if even the emergency point rejects `SetLocation`, try the
  team's enabled `PlayerStart`s, then leave that pawn in place and cancel its
  grace entry. It does not count as a successful recall, so success feedback is
  never faked.
- `SetLocation`, zero velocity, `SetPhysics(PHYS_Falling)` for non-vehicles,
  `PlayTeleportEffect(False, True)`.
- One recall sound cue for the Director.
- If any teammate moved, start the slot 9 cooldown; otherwise fail without
  consuming it.

The spacing and clearance logic is specifically there to prevent telefrags:
the destination is checked against every pawn's collision radius before the
move.

## 9. Telemetry HUD

`DirectorInteraction.PostRender(Canvas C)` draws only while
`RI.bDirectorActive`:

1. **Font/layout**: `SmallFont`, scale 1.0, measured line height.
2. **Top-left hotbar** (`X = 24`, `Y = 24`):
   - header `[TECHNICAL DIRECTOR LOGISTICS]`;
   - Nanite row with `[HOLD]` / `[BEAM]`;
   - full mode: slots 1–9 with names and status;
   - page picker (default): `[1] Personal`, `[2] Machinery`, `[3] All`,
     plus `[Crouch] Back | [Q/E] Cycle pages`;
   - Personal page: original 1, 3, 4, 5, 9 as visible 1–5;
   - Machinery page: original 2, 6, 7, 8 as visible 1–4;
   - All page: original 1–9, with no `[ALL]` label.
   Q/E cycle Personal → Machinery → All (Q reverses). Crouch always returns
   to the page picker. The `[Crouch] Back | [Q/E] Cycle pages` footer appears
   on every page and is hidden together with the cheatsheet by `H`.
   Status is `[READY]` when cooldown ≤ 0.01, otherwise `[Ns]`. Color is green
   when ready, yellow at ≤ half cooldown, red above. Jump healing is handled
   before hotbar dispatch and works in every mode.
3. **Top-right cheatsheet** (`X = ClipX - 24 - width`, `Y = 24 + n*LineH`),
   one control per line, no separators:
   `[Wheel] Cycle Fighter Feed`, `[Hold Fire/AltFire] Zoom Cam`,
   `[Hold Jump] Heal`, `[1-9] Transmat Drop`, `[B] Toggle Booth`,
   `[Q/E] Cycle Pages`, `[1/2/3] Select Page`, `[Crouch] Back`,
   `[H] Hide controls`.
   Pressing `H` hides every line except `[H] Show controls`, which restores
   the full list. The cheatsheet starts visible each time the booth opens.
4. **Bottom-right `TeamMates` counter**, kept above the chat area and the
   "Now spectating..." banner (`ClipY - 14 - 8/7/6*LineH`):
   - cyan header `TeamMates`;
   - `Alive: n` and `Dead: n`.
   Values come from the RI's server-authoritative `TeamAlive` / `TeamDead`,
   recounted every 0.5 s over `Level.ControllerList`. Bots count; the Director
   does not. Colours use a 5-range scale (20% each) on `Alive / total`:
    - 80–100%: Green (70, 255, 110)
    - 60–80%: Lime (200, 255, 0)
    - 40–60%: Yellow (255, 220, 60)
    - 20–40%: Orange (255, 140, 40)
    - 0–20%: Red (255, 72, 72)
    `Dead` uses the exact inverse ratio (0% dead = green, 100% dead = red).
5. **Nameplates**:
   - `RI.GetFriendlyPawns()` collects living teammates on the client;
   - head position = `Location + vect(0,0,60)`;
   - discard points behind the camera with a dot product against
     `vector(CamRot)`;
   - `WorldToScreen`; discard off-canvas;
   - draw three **centred** lines above the head: `Name`, `HP [n]`,
     `Shield [n]`;
   - team colours: red `rgb(255,0,0)`, blue `rgb(51,102,255)`; the fighter on
     the feed uses the brighter selected variants `rgb(255,153,51)` and
     `rgb(51,204,255)`;
   - no `FastTrace`: the brief explicitly asks for through-wall visibility.

Native floating team beacons are suppressed while the booth is open: the
Interaction saves `TeamBeaconMaxDist` / `TeamBeaconPlayerInfoMaxDist`, sets
both to `0`, and restores them in `Cleanup()`. Stock beacons are range-gated
(6000 / 1800 units), carry no HP/shield, and cannot be made always-visible from
script, so the custom plates replace them.

No stock HUD class is overridden. Removing the RI removes the Interaction.

## 10. Networking and failure handling

- The RI is owner-only (`bOnlyRelevantToOwner=True`) and non-always-relevant.
- The owning client gets `DirectorTeam`, `bDirectorActive`, `bHealing`,
  `CurrentTarget`, the nine cooldowns, `MaxCooldowns[9]`, `TeamAlive`,
  `TeamDead`, `bBoothPending`, `EntryTimeLeft` and `ClientSwitchSound`.
- Server RPCs are declared in the `Role < ROLE_Authority` block and every
  implementation re-checks `Role`, `bDirectorActive` and references.
- Interaction attach is retried up to 20 times at 0.25 s if the client's
  `Player`/`InteractionMaster` is not ready.
- `Destroyed()` cleans the Interaction and restores camera state.
- `NotifyLogout()` disables the booth, clears berserk and destroys the RI.
- `ToggleDirector()` exits when active, cancels when pending, and otherwise
  starts the entry delay, so double mutate commands cannot create duplicates.
- The B bind is pushed through `PlayerController.ReceiveLocalizedMessage`,
  which is declared **reliable** in `Engine/PlayerController.uc`; the
  `LocalMessage.ClientReceive` hook therefore always reaches the owning client
  (host or remote) without any custom `PlayerController` subclass.

## 11. Build pipeline

`tools/build.sh` exists because UCC is picky and the game install must remain
usable:

- source is synced into a disposable `MutTechDirector/Classes` directory;
- `UT2004.ini` is backed up with `mktemp`;
- a Python block registers `EditPackages=MutTechDirector` **after** the last
  `EditPackages` line, removes duplicate entries and leaves the rest of the
  section intact;
- the old `.u` is removed to force a real rebuild;
- `UCC.exe make` output is filtered for Wine noise;
- the build fails if the package is missing or the log contains
  `Compile aborted due to errors`;
- `exportcache` generates the `.ucl`;
- `.int` is installed;
- `prebuilt/System/` receives the release artifact;
- a trap restores the original INI on `EXIT`, `INT` and `TERM`.

The script is idempotent and safe to rerun.

## 12. Why this structure scales to other team gametypes

- Team membership comes from `PlayerReplicationInfo.Team`, not from a specific
  gametype class.
- Feed selection comes from `AllControllers`, so it covers players, bots and
  any custom controller subclass.
- Recall anchors are discovered by class and team tag, not hard-coded map
  actors.
- Exit uses `GameInfo.RestartPlayer()`, so custom spawn logic still runs.
- The HUD is a generic `Interaction`, so no per-gametype HUD class is needed.
- Optional content is string-loaded, so missing packages degrade gracefully.

The only hard requirement is `Level.Game.bTeamGame` and a real team assignment.

## 13. Vehicle placement: the simple priority search

The new `FindClearSpot()` replaces the complex expanding-ring algorithm with a
straightforward priority-based search:

```unrealscript
function bool FindClearSpot(...)
{
    // Try positions in order of preference:
    // 1. 150 UU in front of player (where they're looking)
    // 2. Player's exact location
    // 3. Circle at 150 UU radius (8 directions)
    // 4. Circle at 300 UU radius (8 directions)
    // First valid spot wins - nearest to player
}
```

**Helper `TrySpawnSpot()`** for each candidate:

1. **Box trace down** from 1000 UU above → find ground (HitNormal.Z > 0.7)
2. **Box trace verify** at found ground (50 UU sweep)
3. **Overlap check** - no actors in vehicle cylinder (1.1× radius)
4. Returns `Spot = FloorLoc + Height + 25`

**Key simplifications over the previous version:**

- **No expanding rings / radial staggering** — fixed candidate order
- **No line traces** — box traces only, more reliable for terrain
- **No ceiling sweep** — vehicles don't need it; if there's a ceiling, the
  upward box trace in the overlap check will catch it
- **Fixed candidate order** = predictable, deterministic
- **Early exit** on first valid spot = faster
- ~150 lines removed from `FindClearSpot()`

**Separate extents** for ground detection (tall Z=200) vs overlap check
(vehicle height).