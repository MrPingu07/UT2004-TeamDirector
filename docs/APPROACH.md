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
 │   • Cooldown1..9 + NaniteHealRate config defaults (Configure Mutators) │
 │   • ModifyPlayer -> sends DirectorBindKeyMessage             │
 │   • Replicates TeamTurrets[16] for beacon display            │
 │                                                              │
 │ DirectorReplicationInfo (ReplicationInfo, one per director)  │
 │   • bBoothPending, EntryTimeLeft, bDirectorActive            │
 │   • DirectorTeam, CurrentTarget                              │
 │   • Cooldown1..9 + replicated MaxCooldowns[9] (ticked)       │
 │   • TeamAlive / TeamDead (0.5 s roster recount)              │
 │   • bHealing, heal accumulator, berserk timer                │
 │   • FeedMessages[512] + FeedMessageCount (merged server feed) │
 │   • server RPC implementations + entry countdown             │
 │   • HUD swap RPCs: ClientActivateBooth / ClientCloseBooth    │
 └───────────────────────────┬──────────────────────────────────┘
                              │ owner-only replication
                              ▼
                       CLIENT (owner)
 ┌──────────────────────────────────────────────────────────────┐
 │ DirectorReplicationInfo (replicated copy)                    │
 │   • attaches DirectorInteraction on PostBeginPlay /          │
 │     PostNetBeginPlay                                         │
 │   • swaps HUD to DirectorHUD on ClientActivateBooth          │
 │   • restores original HUD on ClientCloseBooth                │
 │                                                              │
 │ DirectorHUD (XInterface.HudBase)                             │
 │   • suppresses native vehicle names, team beacons, crosshair │
 │   • draws broadcast banner (logo, score, clock, typewriter)  │
 │                                                              │
 │ DirectorInteraction (Engine.Interaction)                     │
 │   • raw key/mouse capture -> server RPCs                     │
 │   • CameraDist zoom                                          │
 │   • plain-text PostRender telemetry, TeamMates counter,      │
 │     three-line friendly nameplates, sentinel beacons         │
 │                                                              │
 │ DirectorBindKeyMessage (LocalMessage)                        │
 │   • ClientReceive -> set Input B mutate director             │
 │   • sent on every spawn via ModifyPlayer                     │
 └──────────────────────────────────────────────────────────────┘
```

`DirectorRules` sits beside the mutator in the `GameRules` chain and only
provides a fallback `FindPlayerStart()`. `MutTechDirectorConfig` is a
`GUIPage` opened by the mutator list's **Configure Mutators** button.
`DirectorTurretBeaconInteraction` / `DirectorTurretBeaconMessage` provide
combatant-only sentinel beacons with line-of-sight checks. `DirectorNotify` /
`DirectorNotifyText` handle top-of-screen booth notifications.

---

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
- the `config(User)` cooldown defaults `Cooldown1..9` and `NaniteHealRate`
  edited by `MutTechDirectorConfig`;
- the replicated `TeamTurrets[16]` array for beacon display;
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
- server feed replication: `CopyFeedMessages()` reads the merged
  `DirectorFeed` config array (own lines plus RespawnDelay's, when installed)
  and replicates `FeedMessages[512]` + `FeedMessageCount` to the Director's
  client;
- `ServerCycleTarget`, `ServerSetHealing`, `ServerUseAbility`,
  `ServerLeaveDirector` RPCs;
- `ClientSwitchSound` RPC;
- HUD swap RPCs: `ClientActivateBooth` (spawns `DirectorHUD`, preserves
  scoreboard) and `ClientCloseBooth` (restores original HUD and scoreboard);
- HUD helper `GetFriendlyPawns()`.

It deliberately calls back into `MutTechDirector` for abilities instead of
duplicating spawn logic.

### `DirectorHUD.uc`

A purpose-built booth HUD that replaces the stock HUD while the Director is
in the booth. It draws:

- A clean broadcast frame: full-width dark band with team-coloured stripes,
  stock `LMSLogoSmall` "U" logo at left.
- Team score counter at top centre (red–blue) and match clock in white above
  it (`TimeY = TScoreY - PH * 2.5` after setting `TScoreY = 16.0 * Scale`),
  hidden during F1.
- A centred typewriter feed inside the banner with explicit per-block font and
  scale state so shared `Canvas` properties from other HUD passes do not cause
  size oscillations. Messages word-wrap at the last space before the
  60-character limit; the whole line block is centred vertically between the
  banner stripes, and each line is centred in the text area right of the Unreal
  logo (shifted 50px left for visual balance).
  22-second cycle: flicker, blink, type, blink, hold, flicker, blink, delete,
  blink, rest. New message chosen at cycle end or after a >0.5 s drawing gap.
  Tokens expanded once per message via `DirectorFeed.ExpandTokens()`.
- Resolves `HugeFont` (`GetFontSizeIndex(C, 0)` with fallback to
  `UT2003Fonts.FontEurostile37`) for score/clock. The feed uses fixed
  `FontEurostile17` scaled by `0.8 * (C.ClipY / 768.0)` rather than the
  resolution-aware ladder, keeping the feed the same size relative to the
  banner at every resolution. Explicitly sets `C.Font`, `C.FontScaleX`, and
  `C.FontScaleY` before every `StrLen` / `DrawText` block.
- Suppresses native vehicle name drawing (`DrawVehicleName`), native team
  beacon drawing (`DrawCustomBeacon`), crosshair (`DrawCrosshair`), and stock
  message text (`DrawMessage`).
- Calls `Super.DrawHud()` to preserve vanilla HUD elements (flag/score
  counters, F1 match summary, chat feed). Custom telemetry (hotbar,
  cheatsheet, counter, nameplates) is drawn by `DirectorInteraction.PostRender`.

### `DirectorInteraction.uc`

A client-only `Engine.Interaction` with four jobs:

1. **Input**: wheel, `1`–`9`, Space, left/right mouse, `Q`/`E`, `H`, Crouch.
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
Ultimate Third Person stay compatible. It draws nothing (`GetString` returns `""`,
`GetLifeTime` returns `0`).

### `MutTechDirectorConfig.uc`

A `GUIPage` reached through
`ConfigMenuClassName="MutTechDirector.MutTechDirectorConfig"`. Nine
`moEditBox`es (slots 1–9) plus one for `NaniteHealRate`, plus OK and Reset;
values are clamped to 0–120 s (cooldowns) and 0–199 (heal rate), written to
`class'MutTechDirector'.default` and saved with
`StaticSaveConfig()`. Changes apply to the next match (the RI copies them at
countdown start).

### `DirectorRules.uc`

A tiny `GameRules` that returns a safe team start if the stock chain fails. It
calls `Super.FindPlayerStart()` first, then tries:

1. `PlayerStart.TeamNumber == team`;
2. neutral/default start (`255` or `0`);
3. any enabled `PlayerStart`.

Returning `None` remains safe: the stock chain continues unchanged.

### `DirectorTurretBeaconInteraction.uc` / `DirectorTurretBeaconMessage.uc`

Combatant-only line-of-sight sentinel beacons. The message attaches the
interaction to non-Director team members when a Director is active. The
interaction draws two centred lines (`Sentry` / `HP [X/X]`) only when the
turret is in front of the camera, on screen, and unobstructed by world
geometry or actors. The Director is excluded (they see all beacons without LOS
check via `DirectorInteraction.PostRender`).

---

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
- all nine configured cooldowns and `NaniteHealRate` are copied into
  `MaxCooldowns[9]` and `HealRate`;
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
   resets the nine cooldowns to their configured maxima, sends
   `ClientActivateBooth()`.
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

---

## 4. Leaving the booth

`ExitDirectorMode(RI)`:

1. Mark the RI inactive and clear healing/berserk state.
2. Restore the local camera:
   - `bBehindView = False`;
   - `ClientSetBehindView(False)`;
   - `CameraDist = Default.CameraDist`;
   - view target self.
3. `RI.Destroy()`; client `Destroyed()` calls `DirectorInteraction.Cleanup()`,
   which removes the Interaction and restores `CameraDistRange` and native
   beacon ranges.
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
5. re-apply the current feed target.

This keeps the booth stable across round transitions without touching the
gametype's respawn code.

---

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

---

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
| `IK_Q` | `CycleHotbarPage(-1)` |
| `IK_E` | `CycleHotbarPage(1)` |
| `IK_H` | toggle `bShowCheatsheet` |
| `IK_C` / `IK_Ctrl` | `HotbarBack()` |

The Interaction consumes these events (`return True`) only while the booth is
active. Other keys fall through to the game/console.

---

## 7. Hotbar pages

The hotbar has three modes, managed by `HotbarMode`:

| Constant | Value | Meaning |
|---|---|---|
| `HOTBAR_ALL` | 0 | Full 1–9 list |
| `HOTBAR_PAGE_PICK` | 1 | Page picker (default on entry) |
| `HOTBAR_PERSONAL` | 2 | Personal page (slots 1,3,4,5,9 → keys 1–5) |
| `HOTBAR_MACHINERY` | 3 | Machinery page (slots 2,6,7,8 → keys 1–4) |

- **Default on booth entry:** `HOTBAR_PAGE_PICK` (shows `[1] Personal`,
  `[2] Machinery`, `[3] All`).
- **`Q` / `E`**: cycle Personal → Machinery → All (`Q` reverses), wrapping in
  both directions. From the picker, `Q` opens All and `E` opens Personal.
- **Number keys in picker**: `1` opens Personal, `2` opens Machinery, `3`
  opens All.
- **Crouch** (`C` or `Ctrl`): returns to the page picker from any page.
- **Jump healing** is handled before hotbar dispatch, so it works in every
  mode.
- **Cheatsheet footer** `[Crouch] Back | [Q/E] Cycle pages` appears on every
  picker/page unless `H` hides the cheatsheet.

`ResetHotbar()` (called on booth activation and re-attach) sets
`HotbarMode = HOTBAR_PAGE_PICK` and `bShowCheatsheet = True`.

---

## 8. Cheatsheet

The top-right cheatsheet is drawn one control per line, no separators.
When visible (`bShowCheatsheet == True`):

```text
[Wheel] Cycle Fighter Feed
[Hold Fire/AltFire] Zoom Cam
[Hold Jump] Heal
[1-9] Transmat Drop
[B] Toggle Booth
[Q/E] Cycle Pages
[1/2/3] Select Page
[Crouch] Back
[H] Hide controls
```

When hidden (`bShowCheatsheet == False`), only the reminder remains:

```text
[H] Show controls
```

Pressing `H` toggles. The cheatsheet starts visible each time the booth opens
(`ResetHotbar()`).

---

## 9. Cooldowns

All values are floats in seconds on `DirectorReplicationInfo`. The **ceiling**
per slot is configurable per player/server through **Configure Mutators**
(`MutTechDirector.Cooldown1..9`, `var() config float`, each defaulting to
`1.0` s). The Nanite heal rate (`NaniteHealRate`) is also configurable,
defaulting to `2.0` HP/sec. The mutator copies them into the replicated
`MaxCooldowns[9]` and `HealRate` when the entry countdown starts, so both the
authority and the HUD client agree on the values.

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
| Hold Jump | Nanite Med-Surge | 2.0 HP/sec |

`GetMaxCooldown(Slot)` returns `FMax(0.0, MaxCooldowns[Slot - 1])`, so `0`
means "always ready". The config page clamps edits to `0..120` s and `0..199`
(heal rate), saves them with `StaticSaveConfig()`; new values apply from the
next match.

`Tick()` decrements each positive cooldown by `DeltaTime` only when
`Role == ROLE_Authority && bDirectorActive`. The client does not simulate
cooldowns; it reads the replicated values and renders either `[READY]` or
`[Ns]`.

`UseAbility()` calls `CheckCooldown()` **before** executing the ability. On
success it calls `StartCooldown()`. On a rejected target or failed placement it
returns early, so the cooldown is not consumed.

---

## 10. Ability details

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
- OnTurretChange() refreshes the replicated `TeamTurrets` array and attaches
  combatant beacon interactions.

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

---

## 11. Telemetry HUD

`DirectorInteraction.PostRender(Canvas C)` draws only while
`RI.bDirectorActive`:

1. **Font/layout**: `SmallFont`, scale 1.0, measured line height.
2. **Top-left hotbar** (`X = 24`, `Y = 24`):
   - header `[TECHNICAL DIRECTOR LOGISTICS]`;
   - Nanite row with `[HOLD]` / `[BEAM]`;
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
     `Shield [n]` for players and vehicle drivers;
   - draw two **centred** lines for sentries/empty vehicles: `Sentry` /
     `HP [current/max]`;
   - team colours: red `rgb(255,0,0)`, blue `rgb(51,102,255)`; the fighter on
     the feed uses the brighter selected variants `rgb(255,153,51)` and
     `rgb(51,204,255)`;
   - no `FastTrace`: the brief explicitly asks for through-wall visibility.
   - empty non-sentry vehicles are not labelled.

Native floating team beacons are suppressed while the booth is open: the
Interaction saves `TeamBeaconMaxDist` / `TeamBeaconPlayerInfoMaxDist`, sets
both to `0`, and restores them in `Cleanup()`. Stock beacons are range-gated
(6000 / 1800 units), carry no HP/shield, and cannot be made always-visible from
script, so the custom plates replace them.

No stock HUD class is overridden permanently. The booth temporarily swaps to
`DirectorHUD` and restores the original on exit. Removing the RI removes the
Interaction.

---

## 12. Sentinel beacons for field players

`DirectorTurretBeaconInteraction` draws two centred, team-coloured lines above
friendly sentries for combatants:

```text
Sentry
HP [current/max]
```

Requirements:
- Turret is in front of the camera (dot product > 0).
- Turret projects on screen.
- Line of sight from camera to turret (world geometry + actors). The trace
  passes if it hits the turret itself, its base or its swivel.

The Director does **not** use this interaction; `DirectorInteraction.PostRender`
draws all friendly sentries without the LOS gate.

`DirectorTurretBeaconMessage` is a `LocalMessage` sent to non-Director team
members on spawn (`ModifyPlayer`), on turret roster changes
(`OnTurretChange`/`RefreshTurretList`), and on Director exit. It attaches or
reuses (dedupes) the interaction. The interaction skips drawing while the
viewer is in `Spectating` state (i.e., in the booth).

---

## 13. Networking and failure handling

- The RI is owner-only (`bOnlyRelevantToOwner=True`) and non-always-relevant.
- The owning client gets `DirectorTeam`, `bDirectorActive`, `bHealing`,
  `CurrentTarget`, the nine cooldowns, `MaxCooldowns[9]`, `TeamAlive`,
  `TeamDead`, `bBoothPending`, `EntryTimeLeft`, `FeedMessages[512]`,
  `FeedMessageCount`, `ClientSwitchSound`, `HealRate`, and HUD swap RPCs.
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

---

## 14. Broadcast feed replication

The server is the source of truth for the broadcast-feed message list.

1. **Config read**: on the server/host, `MutTechDirector.ini` section
   `[MutTechDirector.DirectorFeed]` is read into `class'DirectorFeed'.default.Messages`.
   If RespawnDelay is installed, its `[RespawnDelay.RespawnDelayFeed]` lines are
   appended (reflection via `DynamicLoadObject` + `GetPropertyText`; no compile
   dependency).
2. **Merge & deduplicate**: `DirectorFeed.GetMergedFeedMessages()` builds the
   combined list, removing exact duplicate lines (case-insensitive comparison).
3. **Snapshot**: when a Director enters the booth (`BeginEntryCountdown`),
   `DirectorReplicationInfo.CopyFeedMessages()` copies the merged array into the
   fixed-size replicated `FeedMessages[512]` and `FeedMessageCount`.
4. **Replication**: the array is replicated owner-only to the Director's
   client.
5. **Client selection**: `DirectorHUD.PickMessage()` prefers the replicated
   feed; if unavailable (standalone/instant action), it falls back to the local
   merged feed; if that is also empty, it uses `TECHNICAL DIRECTOR MODE`.
5. **Shuffle bag**: `DirectorHUD` maintains a `FeedBag` array of indices.
   When `FeedBagSize` (the source message count) changes, the bag is reset.
   Every configured message is shown once before any repeats.
6. **Token expansion**: `DirectorFeed.ExpandTokens(Msg, PC)` runs on the
   client, expanding tokens from replicated match state (`GRI`, `PRIArray`,
   `Level.Title`, etc.). The template is uppercased before replacement; the
   finished message is uppercased again so token values (player, server, map,
   team names) also render in caps.
7. **Dynamic random tokens**: `$RANDOM<min>_<max>[K|M]` parsed by
   `ExpandRandomTokens()`, rolled once per message per client via `RollRange()`.
   Results are formatted with dot thousands separators (`FormatNumber()`) —
   e.g., `43.781`, never compact `43K`.

---

## 15. Build pipeline

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
- the shipped feed config `MutTechDirector.ini` is copied into `System/`;
- `prebuilt/System/` receives the release artifact;
- a trap restores the original INI on `EXIT`, `INT` and `TERM`.

The script is idempotent and safe to rerun.

---

## 16. Why this structure scales to other team gametypes

- Team membership comes from `PlayerReplicationInfo.Team`, not from a specific
  gametype class.
- Feed selection comes from `AllControllers`, so it covers players, bots and
  any custom controller subclass.
- Recall anchors are discovered by class and team tag, not hard-coded map
  actors.
- Exit uses `GameInfo.RestartPlayer()`, so custom spawn logic still runs.
- The HUD is a generic `Interaction` + temporary `DirectorHUD` swap, so no
  per-gametype HUD class is needed.
- Optional content is string-loaded, so missing packages degrade gracefully.

The only hard requirement is `Level.Game.bTeamGame` and a real team assignment.

---

## 17. Vehicle placement: the simple priority search

The `FindClearSpot()` / `TrySpawnSpot()` algorithm replaces the complex
expanding-ring algorithm with a straightforward priority-based search:

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
