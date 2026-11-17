# Roadmap

## Current status

| Area | Status |
|---|---|
| Compiles on UT2004 v3374 | Done — `0 errors, 0 warnings` |
| `.u` / `.ucl` / `.int` produced | Done |
| Server smoke test | Done — mutator loads on a dedicated server |
| Team-game entry/exit | Implemented |
| Mandatory 5 s entry delay (cancel on death / second press) | Implemented |
| Instant exit | Implemented |
| Pawn suppression and roster preservation | Implemented |
| Cooldown reset/pause rule | Implemented |
| Configurable cooldowns (Configure Mutators) | Implemented |
| Automatic `N` bind for host and clients, no PC subclass | Implemented |
| Locked third-person feed | Implemented |
| Death auto-cycle with 1 s hold | Implemented |
| Wheel cycling | Implemented |
| Smooth 120–1500 zoom | Implemented |
| Nanite heal on Jump | Implemented |
| Abilities 1–9 | Implemented |
| Vehicle placement (simplified priority search) | Implemented |
| Round-reset stray pawn suppression | Implemented |
| Respawn-delay compatibility (`bOutOfLives`) | Implemented |
| Top-left hotbar, top-right cheatsheet (24 px margins) | Implemented |
| Bottom-right `TeamMates` / `Alive` / `Dead` counter | Implemented |
| Three-line custom nameplates + native beacon suppression | Implemented |
| GTAThirdPerson compatibility (no `PlayerController` replacement) | Implemented |
| Build tooling with INI restore | Done |
| Documentation | Done |
| Multi-client live playtest | Not yet performed |

## Known limitations

1. **One Director per player, not one per team.** Two players on the same team
   can both enter the booth. The brief says "a player can toggle the mode", so
   this is allowed, but a future version may add a `bOneDirectorPerTeam` option.
2. **Nameplates depend on client actor relevancy.** The Interaction draws all
   friendly pawns the client knows. A pawn outside network relevancy cannot be
   projected by any client overlay. A future fix would replicate a compact
   friendly-roster struct on the RI, but that adds traffic.
3. **Recall teleports vehicle pawns as vehicles.** Occupants are not extracted
   first. In practice the vehicle is moved with its driver, which is consistent
   with a transmat recall, but it can look dramatic on slopes.
4. **Berserk is a 30-second timer.** If another mutator also manages
   `bBerserk`, the last writer wins. The expiry path clears only the state this
   RI set.
5. **No localization layer.** All strings are English literals in source.
6. **Cooldown modifications apply next match.** Editing them through Configure Mutators
   writes class defaults; a booth that is already open keeps the values copied
   at its entry countdown, and the change takes effect on the next match.

## Near-term work

### 1. Immediate fixes (from original roadmap)

- ✅ **Flag carrier immunity** — Emergency recall must not affect the flag carrier. (Already implemented: `HasFlag` check in `RecallTeam`)
- **Death spectate delay** — When the spectated player dies, wait 1 second before auto-cycling to the next. During this delay, purposefully glitch out all on-screen text. Account for edge case of a vehicle spawning on a dead player.
- ✅ **Configurable Nanite heal rate** — Expose "Healing per second" in the GUI (range 0.00–199). (Implemented: `NaniteHealRate` config + GUI)
- ✅ **Team-visible turret beacon** — Show mounted turret beacon for every team member deployed in the arena (combatants and the Director alike), not just the Director. Format is two centred, team-coloured lines above the turret: `Sentinel(n)` on the first line and `HP [X/X]` on the second (no quotes, no shield line — sentinels are walk-through turrets, not fighters). Combatants require line-of-sight from their camera to the turret (world geometry + actor occlusion); the Director sees all friendly turrets without a LOS gate. Implemented via `DirectorTurretBeaconInteraction` (combatants, LOS-checked) plus sentinel rendering in `DirectorInteraction.PostRender` (Director, no LOS gate), both reading the replicated `TeamTurrets[16]` array in `MutTechDirector`. `DirectorTurretBeaconMessage` attaches/reuses (deduped) the interaction on field players via `ReceiveLocalizedMessage`. The list skips `bDeleteMe`/dead sentinels so destroyed turrets drop out of the beacon display.

  **Diagnostics:** every pipeline step emits `[BEACON-*]` / `[DIRECTOR-RENDER]` script logs:
  - `DeploySentinel` — spawn result, team, spot, `OnTurretChange()` call.
  - `OnTurretChange` — calls `RefreshTurretList()` then `AttachTurretBeaconsToTeam()` so every current combatant gets the beacon interaction attached whenever the turret roster changes (not only at booth entry).
  - `RefreshTurretList` — each sentinel scanned, team-match decision, final slot count, push to mutator array.
  - `RefreshTeamTurrets` — copy count into replicated `MutTechDirector.TeamTurrets`.
  - `AttachTurretBeaconsToTeam` / `ModifyPlayer` — each field player considered, whether `DirectorTurretBeaconMessage` is sent. `ModifyPlayer` sends to non-Director combatants only when a Director is active (`RI != None`); the Director is excluded to prevent duplicate beacon text with `DirectorInteraction.PostRender`.
  - `ExitDirectorMode` — sends `DirectorTurretBeaconMessage` to the exiting Director so they see sentries as a combatant after leaving the booth.
  - `CompleteEntry` — attempts to remove any leftover combatant beacon interaction from the Director (server-side; the `IsInState('Spectating')` guard in the combatant interaction is the reliable client-side backstop).
  - `DirectorTurretBeaconMessage.ClientReceive` — mutator found/not found, existing interaction reused vs new added, final `bVisible`/`bActive`.
  - `DirectorTurretBeaconInteraction.PostRender` — entry, viewport pawn (with `PC.Pawn` fallback), LocalPC, mutator found, per-slot skip/draw reasons (behind camera, off-canvas, LOS blocked), text drawn. Uses `C.SmallFont` to match player nameplate typography/size. Skips drawing while the viewer is in Director booth mode (`IsInState('Spectating')`) since `DirectorInteraction.PostRender` already draws Director sentinel beacons — prevents duplicate overlapping text when a former Director re-enters the booth.
  - `DirectorInteraction.PostRender` — Director sentinel block entry, mutator found, per-slot skip/draw.
  - `DirectorSentinel.PostRender` — overridden to suppress stock engine native name/beacon drawing above sentinels (stock `Vehicle`/`ASTurret.PostRender` draws the actor name, which overlaps our custom beacon text). Only our custom `Sentinel(n)` / `HP [X/X]` beacon is drawn.

  Tail the server log (`-log`) on the server and each client log to verify turrets enter the array, interactions attach, and beacons draw.

### 2. Live multi-client playtest

- Host a listen server with one human Director and at least two human/bot
  fighters.
- Verify:
  - the automatic `N` bind arrives on every joining client;
  - the 5 s entry countdown popups, cancel-on-death and cancel-on-second-press;
  - wheel and zoom on a real input stack;
  - feed auto-cycle timing after a death;
  - nameplate projection at range and through walls;
  - sentinel beacons appear for combatants (LOS-checked) and the Director (no LOS gate) as `Sentinel(n)` / `HP [X/X]`, no Shield line;
  - no duplicate/stacked beacon text on booth re-entry or respawn;
  - destroyed sentinels drop out of the beacon display;
  - the `TeamMates` counter with bots and with a partial roster;
  - every ability in CTF, ONS and TDM;
  - recall spacing with a full team;
  - exit respawn with spawn protection;
  - cooldown pause on exit and full reset on re-entry;
  - Configure Mutators round-trips the nine values.
- Capture client logs for replication warnings (`ScriptLog`, `NetLog`).

### 3. Remaining config options

`Cooldown1..9` and `NaniteHealRate` are done. Still candidates for the same `config(User)` block:

- `bOneDirectorPerTeam`;
- `bAllowInNonTeamGames` (probably stay `False`);

Keep the defaults identical to the current constants so behaviour does not
change for existing servers.

### 4. Friendly roster replication (nameplates)

If live tests show missing distant nameplates, add a compact replicated array
of `{Pawn, Name, Health, Shield}` to the RI, updated at a low rate (2–4 Hz).
This is a deliberate trade: more bandwidth for guaranteed through-wall
telemetry. Measure before adding it.

### 5. Ability polish

- Add team-colored sentinel FX.
- Add a recall confirmation cue for affected teammates (a short client
  message simmilar to those the TD gets. But not for constant effects like the Jump one).


For each: enter (wait out the 5 s delay), cycle, heal, all nine slots, exit,
verify roster count and respawn.

### 6. Release packaging

- Add `tools/package.sh` that zips:
  - `prebuilt/System/MutTechDirector.u`
  - `prebuilt/System/MutTechDirector.ucl`
  - `install/MutTechDirector.int`
  - `README.md`
- Include a `BUILD` file with timestamp and source hash.
- Keep the compiled package in `prebuilt/` so releases do not require the
  retail game files.

## Longer-term ideas

- **Broadcast overlay**: optional top-center score strip for the Director,
  still plain text.
- **Map-aware anchors**: cache nearby `NavigationPoint`s for recall spots
  instead of only radial traces, for tighter bases.


## Non-goals

- Replacing the stock HUD.
- Subclassing every team gametype.
- Adding networked custom assets (textures, meshes, sounds).
- Turning the Director into a combatant.
- Bypassing the server authority model for "responsiveness".

## Source hashes at last build

```text
44732479be00958d24eaf9a7d7a746d779ca647f80f272d4566feb3c25c84da0  DirectorBindKeyMessage.uc
0e3cb21ef3e04b6260197e91717618b8140476ba137bcd3a6ecaa14ab4506399  DirectorInteraction.uc
06699d1cc107d1f0350aa985287966f684e82363ef78afb6e377f37fb3925911  DirectorNotifyText.uc
0b14e76addd69ca2833d2e1c62e01beadd9222edf9e6ee60cdf360a41b83ce73  DirectorNotify.uc
a8da70ba6db1b196143776b62ba2f2d1a50aa89fcef4c6683691fe4325a7c162  DirectorReplicationInfo.uc
9d826eb1c12e23163440e9f73b16ef9935709f7043ac77e6337e62f679d49648  DirectorRules.uc
09fba41044bb77c641768adeedad6214e2e1998b137d4ab4d4979d517e5d0035  DirectorSentinel.uc
a52d794f7a16c595c584bf7467368728e3f46a8cfae5892ffb1cba1ba94a1931  DirectorTurretBeaconInteraction.uc
bd2c5e491e1f10da5a151b142b6621ea9184804a2d76088dcf270b4af1726171  DirectorTurretBeaconMessage.uc
c7524efb89fec707e6b58b7c76eb80e90ea103ecbe9d5366579da063c1838732  MutTechDirectorConfig.uc
ced7b1af2e17283786b887b8043cf2bb53ff486d010b0bf574865fdbfb779f57  MutTechDirector.uc
```

Package hash at last build:
`9e76dc7fbdca9ae39d74301b87fe7f61e3f28ff528b968a68122cf5483e10823`.

If source changes, rerun `./tools/build.sh` and update these hashes and
`prebuilt/BUILD`. Do not compare `.u` hashes across builds: UCC may embed
build-time data, so the binary hash is not a stable content identifier.
