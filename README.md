# MutTechDirector

A universal team-support mutator for **Unreal Tournament 2004 v3374** (community
patch) that turns a player into their team's **Tournament Technical Director**:
a remote broadcast operator in the booth who never sets foot on the arena floor,
but who can authorize transmat logistics, medical nanites and vehicle
requisitions for the fighters on the live feed.

The mutator is deliberately built from stock UT2004 parts only:

| Class | Base | Job |
|---|---|---|
| `MutTechDirector` | `Mutator` | Entry/exit, team lookup, all server-side ability execution, entry delay, configured cooldowns |
| `DirectorReplicationInfo` | `ReplicationInfo` | Per-player owner-only state, cooldowns, roster counter, camera target, RPC bridge, entry countdown |
| `DirectorInteraction` | `Interaction` | Client input capture and plain-text `Canvas.DrawText` telemetry |
| `DirectorBindKeyMessage` | `LocalMessage` | Invisible client-side hook that binds `B` to the booth toggle |
| `MutTechDirectorConfig` | `GUIPage` | **Configure Mutators** submenu for the nine cooldowns |
| `DirectorRules` | `GameRules` | Last-resort team `PlayerStart` fallback on odd maps |
| `DirectorSentinel` | `ASVehicle_Sentinel_Floor` | Always walk-through, still shootable perimeter turret |
| `DirectorNotify` / `DirectorNotifyText` | `LocalMessage` | Top-of-screen booth notifications |

No gametype is subclassed, no stock `HUD` is replaced, **no `PlayerController`
class is replaced** (so controller-owning mutators such as GTAThirdPerson keep
working), and no core `.u` package is modified. The result works across
`TeamGame` and its sensible subclasses: TDM, CTF, Onslaught, Assault, Bombing
Run, Double Domination, Classic Domination and custom team gametypes that
inherit from `TeamGame`.

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
- **Hold Jump** for the Nanite Med-Surge (2 HP/sec, no cooldown).
- **Nine transmat slots** on keys `1`–`9`, all cooldown-gated and server
  validated.
- **Plain-text Interaction HUD**: top-left `[TECHNICAL DIRECTOR LOGISTICS]`
  hotbar with live `[READY]` / `[24s]` states, top-right controls cheatsheet,
  bottom-right live `TeamMates` / `Alive` / `Dead` counter, and always-visible
  three-line friendly nameplates (`Name` / `HP [n]` / `Shield [n]`) projected
  through walls in team colours.
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
  startup so clients can load the interaction, nameplates and bind message.

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
   cooldowns (0–120 s, default 1.0 s). Values save to your user config and
   apply from the next match.
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
| Hold `Jump` | Nanite Med-Surge (2 HP/sec) |
| `1` | Ammunition Requisition |
| `2` | Perimeter Defense (floor Sentinel) |
| `3` | Painkillers (health to 300) |
| `4` | Blindage (+100 shield) |
| `5` | Stimuli Dose (Berserk, 30 s) |
| `6` | SPMA Artillery |
| `7` | Light Vehicle Transmat (Raptor/Cicada) |
| `8` | Heavy Asset Drop (Hover Tank) |
| `9` | Emergency Recall |

The Interaction consumes only these keys while the booth is active, so normal
console/chat input still works when those interfaces have focus. `B` itself is a
plain input bind, not an Interaction key, so it also works outside the booth.

---

## Ability reference

All slots default to a **1.0 s** cooldown; every value is configurable per
server via **Configure Mutators** (`Cooldown1..9`).

| Slot | Name | Effect |
|---|---|---|
| Hold Jump | Nanite Med-Surge | +2 HP/sec to the feed fighter, in smooth 1 HP pulses |
| 1 | Ammunition Requisition | One standard ammo pack for every distinct ammo type used by the fighter's carried weapons |
| 2 | Perimeter Defense | Team-aligned `MutTechDirector.DirectorSentinel` on ground near the fighter; walk-through but shootable |
| 3 | Painkillers | Sets the fighter's health to at least 300 |
| 4 | Blindage | `AddShieldStrength(100)` (Super Shield equivalent) |
| 5 | Stimuli Dose | `xPawn.bBerserk` plus `Weapon.StartBerserk()` for 30 s |
| 6 | SPMA Artillery | `OnslaughtBP.ONSArtillery` dropped at the fighter's feet |
| 7 | Light Vehicle Transmat | `OnslaughtBP.ONSDualAttackCraft`, falling back to `Onslaught.ONSAttackCraft` |
| 8 | Heavy Asset Drop | `Onslaught.ONSHoverTank` |
| 9 | Emergency Recall | Teleports all living teammates to the team Flag Base, main Power Core, or team spawn. Each teammate gets a distinct landing spot when possible; if the anchor is full or enclosed, the whole team goes to the exact objective centre instead (flag, power node, random owned DOM point — explicit failure if none owned — or a random team spawn in TDM/Invasion/BR), with 5 s collision transparency. |

Failed placement prints `Not enough space.` and **does not start the cooldown**.
Failed target checks print a reason and also leave the slot ready.

Spawned vehicles are fully solid. Only the automated sentinel turret is
walk-through (its turret, base and swivel all use `SetCollision(True, False)`),
so it can be shot but never traps or telefrags players.

---

## HUD reference

All drawing happens in `DirectorInteraction.PostRender`; no HUD subclass is
installed. Both upper blocks use a **24 px top margin**.

```text
[TECHNICAL DIRECTOR LOGISTICS]              [Wheel] Cycle Fighter Feed
[Jump] Nanite Med-Surge  [BEAM]             [Hold Fire/AltFire] Zoom Cam
[1] Ammunition Requisition      [READY]     [Hold Jump] Heal
[2] Perimeter Defense           [READY]     [1-9] Transmat Drop
...                                         [B] Toggle Booth
[9] Emergency Recall            [READY]
```

Bottom-right, kept above the chat area and the "Now spectating..." banner:

```text
        TeamMates        <- cyan header
        Alive: 3         <- green / orange / yellow / red band
        Dead: 1          <- inverse band
```

- Counts are server-authoritative (`TeamAlive` / `TeamDead` on the RI),
  refreshed twice a second, and include **bots**; the Director is excluded.
- Band scale: 0–25 % red, 25–50 % yellow, 50–75 % orange, 75–100 % green.
  `Dead` runs `1 - ratio` through the same scale, so a healthy roster is
  green/green and a wiped one is red/red.

Nameplates:

```text
        Name
        HP [100]
        Shield [50]
```

Three centred lines, team-coloured (`rgb(255,0,0)` red team,
`rgb(51,102,255)` blue team), with the fighter on the broadcast feed using the
brighter selected variant (`rgb(255,153,51)` / `rgb(51,204,255)`). They are
drawn without occlusion or range tests, so they are always visible.

Native floating team beacons are deliberately **disabled** for the Director
(`TeamBeaconMaxDist` / `TeamBeaconPlayerInfoMaxDist` set to `0` and restored on
exit). They are range-gated (6000 / 1800 units), carry no HP/shield and cannot
be made always-visible from script, so the custom plates replace them.

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

- `UCC.exe make` completes with **0 errors, 0 warnings**.
- `UCC.exe exportcache MutTechDirector.u` reports
  `Mutator exported successfully`.
- A dedicated-server smoke test (`DM-Rankin?game=XGame.xTeamGame` with the
  mutator) starts cleanly, loads the mutator and `DirectorRules`, and logs no
  UnrealScript runtime errors.
- The build script restores `UT2004.ini` byte-for-byte after compiling (the
  temporary `EditPackages` entry is absent afterward).
- Artifacts present in `prebuilt/System/`.
- In-game iterations tested by the maintainer: sentinel ground height, HUD
  placement, counter data, nameplate colours and the entry flow.

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

**A vehicle drop says `Not enough space.`**
The clearance scan rejected every candidate position around the fighter. Move
the fighter to a more open area and retry. The cooldown was not consumed.

**Nameplates are missing for a distant teammate.**
The Interaction draws every friendly pawn the client currently knows about.
Actor relevancy still applies in network play; a pawn outside replication range
cannot be projected by any client-side overlay.

**The server build logs `Failed loading package: LiandriExchange`.**
That is an unrelated stock `make.ini`/server-package message from this
particular install, not a MutTechDirector error.

---

## License / attribution

Original UnrealScript for UT2004. Uses only stock UT2004 class names, sounds and
effects; no retail assets are redistributed. UT2004 and Unreal are trademarks of
Epic Games, Inc.
