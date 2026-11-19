# MutTechDirector

A universal team-support mutator for **Unreal Tournament 2004 v3374** (community
patch) that turns a player into their team's **Tournament Technical Director**:
a remote broadcast operator in the booth who never sets foot on the arena floor,
but who can authorize transmat logistics, medical nanites and vehicle
requisitions for the fighters on the live feed.

The mutator is built from stock UT2004 parts only. It does not subclass a
gametype, replace a `PlayerController`, or modify a retail `.u` package. It
swaps in a purpose-built Director HUD only while the booth is occupied and
restores the original HUD on exit.

| Class | Base | Job |
|---|---|---|
| `MutTechDirector` | `Mutator` | Entry/exit, team lookup, all server-side ability execution, entry delay, configured cooldowns and heal rate, replicated sentinel roster |
| `DirectorReplicationInfo` | `ReplicationInfo` | Per-player owner-only state, cooldowns, roster counter, camera target, input RPC bridge, booth HUD swap, server feed replication, entry countdown |
| `DirectorInteraction` | `Interaction` | Client input capture and plain-text `Canvas.DrawText` telemetry: hotbar, cheatsheet, counter, nameplates |
| `DirectorHUD` | `XInterface.HudBase` | Booth-only HUD: suppresses stock vehicle/beacon text and draws the broadcast banner, team score and match clock |
| `DirectorFeed` | `Object` | Shipped feed config, live-match token expansion and dynamic `$RANDOM` values |
| `DirectorBindKeyMessage` | `LocalMessage` | Invisible client-side hook that binds `B` to the booth toggle |
| `MutTechDirectorConfig` | `GUIPage` | **Configure Mutators** submenu for the nine cooldowns and the Nanite heal rate |
| `DirectorRules` | `GameRules` | Last-resort team `PlayerStart` fallback on odd maps |
| `DirectorSentinel` | `ASVehicle_Sentinel_Floor` | Always walk-through, still shootable perimeter turret |
| `DirectorTurretBeaconInteraction` | `Interaction` | Line-of-sight sentinel beacons for field players |
| `DirectorTurretBeaconMessage` | `LocalMessage` | Attaches/reuses the combatant sentinel-beacon interaction |
| `DirectorNotify` / `DirectorNotifyText` | `LocalMessage` / `Object` | Top-of-screen booth notifications |

The result works across `TeamGame` and its sensible subclasses: TDM, CTF,
Onslaught, Assault, Bombing Run, Double Domination, Classic Domination and
custom team gametypes that inherit from `TeamGame`.

---

## Feature summary

- **`B` toggles the booth** for the issuing player, with no manual bind
  required: every human client (and the host) receives the bind automatically on
  spawn. `mutate director` / `mutate techdirector` / `mutate mutdirector` remain
  valid console equivalents.
- **Mandatory 5-second entry delay.** Pressing `B` starts
  `Entering Technical Director booth in 5...` (then 4, 3, 2, 1) while the
  player keeps fighting normally. Dying during the delay cancels the entry, so
  the booth cannot be used to dodge an imminent death. **Exiting is instant.**
- **Physical pawn suppressed and destroyed** once the booth opens. The Director
  cannot be damaged, cannot feed kills and cannot block a spawn. Exiting uses
  the gametype's normal `RestartPlayer()` path, so spawn selection, spawn
  protection and `PawnClass` remain stock behaviour.
- **Anti-cheese cooldowns.** Every transmat slot starts at its full cooldown on
  entry and only ticks down while the booth is occupied. Leaving destroys the
  state, so a player must commit time off the battlefield to earn drops.
  Cooldowns default to **1.0 s** each and are editable from
  **Configure Mutators**.
- **Locked broadcast feed.** Third-person behind-view, strictly living
  teammates. If the feed fighter dies, the booth holds the last frame for one
  second, then automatically cuts to the next living teammate with a subtle
  switch cue.
- **Mouse wheel cycles the feed**, left/right mouse smoothly zoom the camera
  between 120 and 1500 Unreal units.
- **Hold Jump** for the Nanite Med-Surge (2 HP/sec by default, no cooldown,
  configurable 0–199 HP/sec).
- **Nine transmat slots** on keys `1`–`9`, all cooldown-gated and server
  validated, organised into three switchable hotbar pages.
- **Broadcast-feed banner**: a custom booth HUD replaces the stock spectator
  banner with a team-striped typewriter feed, live team score and match clock.
  The message list is **owned by the server** and replicated to each Director;
  nested tokens expand from replicated match state on the client.
- **Plain-text Interaction telemetry**: hotbar with live `[READY]` / `[24s]`
  states, one-line-per-control cheatsheet, bottom-right live `TeamMates` /
  `Alive` / `Dead` counter, and always-visible friendly nameplates
  (`Name` / `HP [n]` / `Shield [n]`).
- **Sentinel beacons for everyone**: the Director sees all friendly sentries
  without a range or line-of-sight gate; field players see team-coloured
  `Sentry` / `HP [current/max]` beacons only with clear line of sight.
- **Native cues**: `XEffects.NewTransEffect*`, `XEffects.LinkSparks`,
  `XEffects.ComboActivation`, `ClientPlaySound` switch/deployment cues.

---

## Requirements

- UT2004 **v3374** (the 2004 community patch is fine).
- Windows-edition files running through Wine if you are on Linux (the build
  script assumes this), or a native Windows install if you invoke `UCC.exe`
  yourself.
- No bonus-pack dependency at runtime for the core mutator. The SPMA and light
  vehicle use `OnslaughtBP.*` when available and fall back gracefully; the heavy
  slot uses `Onslaught.ONSHoverTank`.
- `ServerPackages=MutTechDirector` must be listed in the server's
  `UT2004.ini` (`[Engine.GameEngine]`). The mutator sets
  `bAddToServerPackages=True`, but a dedicated server still needs the line at
  startup so clients can load the interaction, HUD, nameplates, beacons and bind
  message.

---

## Installation (players)

1. Copy `prebuilt/System/MutTechDirector.u`,
   `prebuilt/System/MutTechDirector.ucl` (if present),
   `install/MutTechDirector.int` and `install/MutTechDirector.ini` into
   `UT2004/System/`. The `.ini` is only needed on the server/host or for
   standalone play: on a server, the message list is replicated to each
   Director's client, so joining players can skip it.
2. Start the game, open **Instant Action** or **Host Game**, and select
   **Tournament Technical Director** in the mutator list.
3. Optional: press **Configure Mutators** in that list to tune the nine transmat
   cooldowns (0–120 s, default 1.0 s) and the Nanite heal rate (0–199 HP/sec,
   default 2.0). Values save to your user config and apply from the next match.
4. In game, press **`B`**. The bind is installed automatically on spawn; the
   console command `mutate director` works as a fallback.

A normal release does **not** need the `MutTechDirector/Classes` source
directory inside the game install; that directory is only used by the build
script.

---

## Controls

| Input | Action |
|---|---|
| `B` | Start the 5 s entry delay / leave the booth instantly |
| `mutate director` | Console equivalent of `B` |
| Mouse wheel up / down | Cycle living teammates |
| Hold left mouse | Zoom camera in |
| Hold right mouse | Zoom camera out |
| Hold `Jump` | Nanite Med-Surge (default 2 HP/sec) |
| `Q` / `E` | Cycle hotbar pages: Personal → Machinery → All (`Q` reverses, wrapping both ways) |
| `1` / `2` / `3` in page picker | Open Personal / Machinery / All |
| `Crouch` (`C` or `Ctrl`) | Return to the Pages picker from any page |
| `H` | Show/hide the cheatsheet; the `[H]` reminder stays visible |
| `1` | Ammunition Requisition |
| `2` | Perimeter Defense (floor Sentinel) |
| `3` | Painkillers (health to 300) |
| `4` | Blindage (+100 shield) |
| `5` | Stimuli Dose (Berserk, 30 s) |
| `6` | SPMA Artillery |
| `7` | Light Vehicle Transmat (Raptor/Cicada) |
| `8` | Heavy Asset Drop (Hover Tank) |
| `9` | Emergency Recall |

### Hotbar pages

The **Pages picker is the default** whenever the booth opens.

- **`[1] Personal`** — original slots 1, 3, 4, 5, 9 → visible keys 1–5.
- **`[2] Machinery`** — original slots 2, 6, 7, 8 → visible keys 1–4.
- **`[3] All`** — the full original 1–9 list; the page itself has no `[ALL]`
  label because the list is self-evident.

`Q` / `E` cycle Personal → Machinery → All and wrap in both directions. From
the picker, `Q` opens All and `E` opens Personal, so the first press always
moves to a real page. `Crouch` returns to the picker from any page.

Every picker/page shows `[Crouch] Back | [Q/E] Cycle pages` unless `H` hides the
cheatsheet. Jump healing is dispatched before hotbar handling, so it **always**
works regardless of the active page.

The Interaction consumes only these keys while the booth is active, so normal
console/chat input still works when those interfaces have focus. `B` itself is a
plain input bind, not an Interaction key, so it also works outside the booth.

---

## Ability reference

All slots default to a **1.0 s** cooldown; every value is configurable per
server via **Configure Mutators** (`Cooldown1..9`). The Nanite heal rate
(`NaniteHealRate`) is also configurable there, defaulting to **2.0 HP/sec**.

| Slot | Name | Effect |
|---|---|---|
| Hold Jump | Nanite Med-Surge | Heals the feed fighter at `NaniteHealRate` HP/sec in smooth pulses (default 2 HP/sec, no cooldown) |
| 1 | Ammunition Requisition | One standard ammo pack for every distinct ammo type used by the fighter's carried weapons |
| 2 | Perimeter Defense | Team-aligned `MutTechDirector.DirectorSentinel` on ground near the fighter; walk-through but shootable |
| 3 | Painkillers | Sets the fighter's health to at least 300 |
| 4 | Blindage | `AddShieldStrength(100)` (Super Shield equivalent) |
| 5 | Stimuli Dose | `xPawn.bBerserk` plus `Weapon.StartBerserk()` for 30 s |
| 6 | SPMA Artillery | `OnslaughtBP.ONSArtillery` dropped at the fighter's feet |
| 7 | Light Vehicle Transmat | `OnslaughtBP.ONSDualAttackCraft`, falling back to `Onslaught.ONSAttackCraft` |
| 8 | Heavy Asset Drop | `Onslaught.ONSHoverTank` |
| 9 | Emergency Recall | Teleports all living teammates to the team Flag Base, main Power Core, or team spawn. Each teammate gets a distinct landing spot when possible; if the anchor is full or enclosed, the whole team goes to the exact objective centre instead (flag, power node, random owned DOM point — explicit failure if none owned — or a random team spawn in TDM/Invasion/BR), with 5 s collision transparency. |

Failed placement prints `Not enough space.` and **does not start the
cooldown**. Failed target checks print a reason and also leave the slot ready.
If a fighter cannot be found at all, the ability reports that instead of
silently dropping.

Spawned vehicles are fully solid. Only the automated sentinel turret is
walk-through (its turret, base and swivel all use `SetCollision(True, False)`),
so it can be shot but never traps or telefrags players.

### Sentinel beacons

- **Director:** sees friendly pawns, occupied vehicles and deployed sentries
  through walls with no range test. Sentries use two lines, `Sentry` and
  `HP [current/max]`.
- **Field players:** `DirectorTurretBeaconInteraction` draws the same two
  lines, but only when the turret is in front of the camera, on screen, and
  unobstructed by world geometry or actors.

The native `Sentinel(n)`/vehicle-name overlay is suppressed by `DirectorHUD`
so it cannot overlap the custom beacons.

---

## HUD reference

While the booth is open, the owning client swaps its stock HUD for
`DirectorHUD`, which draws a clean broadcast frame and suppresses native vehicle
names, native team beacons, the crosshair and stock message text. The original
HUD and scoreboard class are restored on exit. `DirectorInteraction.PostRender`
draws the telemetry on top.

Both upper blocks use a **24 px top margin**.

```text
[TECHNICAL DIRECTOR LOGISTICS]              [Wheel] Cycle Fighter Feed
[Jump] Nanite Med-Surge          [BEAM]     [Hold Fire/AltFire] Zoom Cam
[1] Personal                                [Hold Jump] Heal
[2] Machinery                               [1-9] Transmat Drop
[3] All                                     [B] Toggle Booth
[Crouch] Back | [Q/E] Cycle pages           [Q/E] Cycle Pages
                                            [1/2/3] Select Page
                                            [Crouch] Back
                                            [H] Hide controls
```

The picker is shown above; opening a page replaces the three page entries with
its ability list:

- **Personal:** `[PERSONAL]` header plus five slots.
- **Machinery:** `[MACHINERY]` header plus four slots.
- **All:** the nine original slots, with no header.

Status is `[READY]` when the cooldown is ≤ 0.01 s, otherwise `[Ns]`. Colour is
green when ready, yellow at ≤ half cooldown, red above. The Nanite row shows
`[HOLD]` or `[BEAM]` depending on whether Jump is currently held.

Pressing `H` hides every cheatsheet line except:

```text
[H] Show controls
```

Press `H` again to restore the list. The picker/page footer is part of that
toggle. Re-entering the booth restores the full cheatsheet.

### Broadcast banner

`DirectorHUD.DrawSpectatingHud()` replaces the stock "Now Viewing..." banner
with a full-width dark band, team-coloured top/bottom stripes, the stock
`LMSLogoSmall` "U" logo, and a centred typewriter feed at normal `MedFont`
size. Above it, the HUD shows the red–blue team score at 2× size and the match
clock in white (both hidden while the scoreboard is open).

The feed runs a 22-second cycle: flicker, blink, type, blink, hold, flicker,
blink, delete, blink, rest. A new message is chosen at the end of the cycle, or
after a drawing gap longer than 0.5 s (menu, pause, map load). The message is
snapshotted once so live values cannot rewrite half-typed text.

Bottom-right, kept above the chat area and the banner:

```text
        TeamMates        <- cyan header
        Alive: 3         <- green / lime / yellow / orange / red band
        Dead: 1          <- inverse band
```

- Counts are server-authoritative (`TeamAlive` / `TeamDead` on the RI),
  refreshed twice a second, and include **bots**; the Director is excluded.
- Band scale: 0–20 % red, 20–40 % orange, 40–60 % yellow, 60–80 % lime,
  80–100 % green. `Dead` runs `1 - ratio` through the same scale, so a healthy
  roster is green/green and a wiped one is red/red.

Friendly nameplates (drawn for pawns, vehicle drivers and sentries):

```text
        Name              (players/vehicle drivers: 3 lines)
        HP [100]
        Shield [50]

        Sentry            (sentries/empty vehicles: 2 lines)
        HP [500/500]
```

Three lines are centred and team-coloured (`rgb(255,0,0)` red team,
`rgb(51,102,255)` blue team), with the fighter on the broadcast feed using the
brighter selected variant (`rgb(255,153,51)` / `rgb(51,204,255)`). They are
drawn without occlusion or range tests, so they are always visible to the
Director. Empty non-sentry vehicles are not labelled.

Native floating team beacons are suppressed for the Director
(`TeamBeaconMaxDist` / `TeamBeaconPlayerInfoMaxDist` set to `0` and restored on
exit). They are range-gated (6000 / 1800 units), carry no HP/shield and cannot
be made always-visible from script, so the custom plates replace them.

---

## Broadcast feed

The bottom banner is an ambient, non-authoritative feed. The server reads
`MutTechDirector.ini`, snapshots its list into `DirectorReplicationInfo`, and
replicates it to each Director. The client then expands tokens from replicated
match state and displays the result. Joining players therefore do **not** need
the ini, and every Director sees the host's authored feed.

- **155 messages** ship in `install/MutTechDirector.ini` (the replicated array
  caps at 256).
- The section is `[MutTechDirector.DirectorFeed]`, using repeated bare
  `Messages=` keys; `Messages(0)=...` is the wrong format for a dynamic array
  and is silently ignored.
- A shuffle bag shows every message once before repeating. Empty entries are
  skipped; if every entry is empty, `TECHNICAL DIRECTOR MODE` is used.
- Width is deliberately **not** filtered. Names are validated by the game, and
  a long dynamic value should not remove a message from rotation.
- Templates and the finished output are uppercased, so token values (player,
  server, map and team names) render in caps too.
- Tokens cover map/server/player counts, match status, clocks, scores, team
  standings and more. `$TOPTEAMNAME` / `$TOPTEAMFRAGGER` mean the **Director's
  own team**; `$LEADTEAMNAME` / `$LEADTEAMFRAGGER` mean the **currently leading
  team**.
- Random values use the dynamic `$RANDOM<min>_<max>[K|M]` syntax, e.g.
  `$RANDOM1_9`, `$RANDOM25_50`, `$RANDOM1_50K`. Results are full integers
  grouped with dots (`43.781`), never compact (`43K`), and are rolled once per
  message on each client.

The full token table, fallbacks, match-state rules and authoring workflow are in
[`docs/BROADCASTING.md`](docs/BROADCASTING.md).

---

## Building from source

The safe build script lives at `tools/build.sh`:

```bash
./tools/build.sh
```

It performs these steps:

1. Syncs `source/MutTechDirector/Classes/*.uc` into
   `$UT2004_DIR/MutTechDirector/Classes` (wiping stale renamed classes first).
2. Backs up `UT2004.ini`, then temporarily appends
   `EditPackages=MutTechDirector` to `[Editor.EditorEngine]` **after** all stock
   dependencies.
3. Removes any old `System/MutTechDirector.u` and runs `wine UCC.exe make`.
4. Runs `wine UCC.exe exportcache MutTechDirector.u`.
5. Installs `MutTechDirector.int` and the shipped feed config
   `MutTechDirector.ini` into `System/`.
6. Restores `UT2004.ini` via an `EXIT`/`INT`/`TERM` trap, even on failure.
7. Copies the compiled package into `prebuilt/System/` for release packaging.

Override the game path if needed:

```bash
UT2004_DIR=/path/to/UT2004 ./tools/build.sh
```

An interrupted build leaves **no** `MutTechDirector.u` installed (the script
deletes the old one before compiling), so always let a build finish.

The `.int` uses `Object=(Name=MutTechDirector.MutTechDirector,...)` so mutator
lists work even if the `.ucl` cache is missing.

### Manual build

If you prefer to compile by hand, add this line at the **end** of
`[Editor.EditorEngine]` in `UT2004.ini` (never at the top: the package must be
compiled after its dependencies), sync the classes, then run:

```bash
cd "$UT2004/System"
rm -f MutTechDirector.u
wine UCC.exe make
wine UCC.exe exportcache MutTechDirector.u
```

Remove the temporary `EditPackages` line afterward. The build script does this
for you and also verifies that the `.u` file actually appeared.

---

## Verification performed

- `UCC.exe make` completes with **0 errors, 5 known warnings** (pre-existing
  `DirectorHUD` unknown default properties: `bShowScores`, `bShowStats`,
  `bShowCrosshair`, `bShowRadar`, `bShowVehicleNames` — these properties belong
  to stock `HudBase` but are not visible to the compiler in this package setup).
- `UCC.exe exportcache MutTechDirector.u` reports
  `Mutator exported successfully`.
- A dedicated-server smoke test (`DM-Rankin?game=XGame.xTeamGame` with the
  mutator) starts cleanly, loads the mutator and `DirectorRules`, and logs no
  UnrealScript runtime errors.
- The build script restores `UT2004.ini` byte-for-byte after compiling (the
  temporary `EditPackages` entry is absent afterward).
- Artifacts present in `prebuilt/System/`.
- In-game iterations tested by the maintainer: sentinel ground height, HUD
  placement, counter data, nameplate colours, feed layout, hotbar paging and
  the entry flow.

The 5 warnings are known and accepted; they do not affect the compiled package.

---

## Compatibility notes

- **Team detection** uses `Level.Game.bTeamGame` plus a non-`None`
  `PlayerReplicationInfo.Team`.
- **Feed selection** iterates `AllControllers` and accepts only living pawns on
  the Director's team. Bots are included naturally.
- **Recall anchors** prefer `CTFBase` (CTF/Bombing Run), then `ONSPowerCore`
  (Onslaught, main/final core first), then `PlayerStart.TeamNumber`. Stock
  UT2004 has no `TeamPlayerStart` class; the design brief's name maps to the
  `TeamNumber` field.
- **Vehicle classes** are resolved with `DynamicLoadObject`, so missing
  bonus-pack content degrades to a fallback or a clean ability failure instead
  of a package-load crash.
- **No `PlayerController` subclass.** The automatic `B` bind rides on
  `LocalMessage.ClientReceive`, which runs on the owning machine. Mutators that
  replace `PlayerControllerClass` (e.g. GTAThirdPerson) are therefore
  unaffected.
- **Booth HUD is temporary.** `DirectorHUD` is spawned only while the booth is
  active; the original HUD class and scoreboard class are restored on exit.
- **No core game files are edited.** The only temporary game-install change is
  the `EditPackages` line during compilation, which is restored.

---

## Repository layout

```text
TeamDirector/
├── CONTEXT.md                       # session-oriented project context
├── README.md
├── docs/
│   ├── APPROACH.md                  # architecture and implementation details
│   ├── BEACON_FIX.md                # sentinel beacon debugging notes
│   ├── BROADCASTING.md              # feed banner, ini config and live tokens
│   ├── FINDINGS.md                  # stock-code findings and compiler quirks
│   ├── PHILOSOPHY.md                # design principles and lore
│   └── ROADMAP.md                   # status, limits and future work
├── install/
│   ├── MutTechDirector.ini          # shipped broadcast feed source
│   ├── MutTechDirector.int
│   └── README.txt
├── prebuilt/
│   ├── BUILD
│   └── System/                      # compiled .u / .ucl release copies
├── source/MutTechDirector/Classes/
│   ├── DirectorBindKeyMessage.uc
│   ├── DirectorFeed.uc
│   ├── DirectorHUD.uc
│   ├── DirectorInteraction.uc
│   ├── DirectorNotify.uc
│   ├── DirectorNotifyText.uc
│   ├── DirectorReplicationInfo.uc
│   ├── DirectorRules.uc
│   ├── DirectorSentinel.uc
│   ├── DirectorTurretBeaconInteraction.uc
│   ├── DirectorTurretBeaconMessage.uc
│   ├── MutTechDirector.uc
│   └── MutTechDirectorConfig.uc
├── prompt.txt                       # original specification
└── tools/build.sh                   # safe compile/install pipeline
```

---

## Troubleshooting

**The mutator does not appear in the list.**
Check that `MutTechDirector.int` and `MutTechDirector.u` are both in `System/`.
Restart UT2004 after installing new mutators.

**`B` does nothing.**
The bind is pushed on every spawn; if you joined mid-match, die once (or
respawn) and it will be applied. You can always type `mutate director` in the
console. Another mod that rebinds `B` will be overwritten on your next spawn.

**`mutate director` says a team game is required.**
The mutator intentionally refuses non-team modes (Deathmatch, Invasion,
Mutant, etc.). Use TDM, CTF, ONS, AS, BR, DOM, cDOM or another `TeamGame`.

**The booth takes five seconds to open.**
That is intentional. The delay exists so the booth cannot be used to escape an
imminent death. Exiting is immediate.

**The camera shows the last dead teammate and does not cut.**
That is the intended one-second hold. If the whole team is dead, the booth
keeps checking once a second and cuts as soon as a teammate respawns.

**The hotbar opens on a page list instead of keys 1–9.**
That is the default. Press `1`, `2` or `3` to open a page, or `Q`/`E` to cycle.
`Crouch` returns to the picker; `H` hides the cheatsheet.

**The cheatsheet disappeared.**
Press `H`. The `[H] Show controls` reminder is intentionally left visible so
the full list can be restored.

**A vehicle drop says `Not enough space.`**
The clearance scan rejected every candidate position around the fighter. Move
the fighter to a more open area and retry. The cooldown was not consumed.

**Nameplates are missing for a distant teammate.**
The Interaction draws every friendly pawn the client currently knows about.
Actor relevancy still applies in network play; a pawn outside replication range
cannot be projected by any client-side overlay.

**The banner repeats the compiled defaults instead of the server's feed.**
The server did not read its ini. Confirm `[MutTechDirector.DirectorFeed]` uses
repeated bare `Messages=` keys on the **server/host**, then restart it. See
`docs/BROADCASTING.md`.

**The server build logs `Failed loading package: LiandriExchange`.**
That is an unrelated stock `make.ini`/server-package message from this
particular install, not a MutTechDirector error.

---

## License / attribution

Original UnrealScript for UT2004. Uses only stock UT2004 class names, sounds and
effects; no retail assets are redistributed. UT2004 and Unreal are trademarks of
Epic Games, Inc.
