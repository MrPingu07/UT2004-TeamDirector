# Roadmap

## Current status

| Area | Status |
|---|---|
| Compiles on UT2004 v3374 | Done — `0 errors, 5 known warnings` |
| `.u` / `.ucl` / `.int` produced | Done |
| Server smoke test | Done — mutator loads on a dedicated server |
| Team-game entry/exit | Implemented |
| Mandatory 5 s entry delay (cancel on death / second press) | Implemented |
| Instant exit | Implemented |
| Pawn suppression and roster preservation | Implemented |
| Cooldown reset/pause rule | Implemented |
| Configurable cooldowns (Configure Mutators) | Implemented |
| Configurable Nanite heal rate (Configure Mutators) | Implemented |
| Automatic `B` bind for host and clients (default toggle key), no PC subclass | Implemented |
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
| Three-page hotbar: Personal / Machinery / All with Q/E cycling and Crouch | Implemented |
| H cheatsheet toggle with `[H] Show controls` reminder | Implemented |
| Bottom-right `TeamMates` / `Alive` / `Dead` counter | Implemented |
| Three-line custom nameplates + native beacon suppression | Implemented |
| Sentinel beacons for field players (LOS-checked) + Director (no LOS) | Implemented |
| GTAThirdPerson compatibility (no `PlayerController` replacement) | Implemented |
| Temporary Director HUD swap with original restore on exit | Implemented |
| Server-authoritative broadcast feed replicated to Director clients | Implemented |
| Dynamic `$RANDOM<min>_<max>[K|M]` tokens with dot grouping | Implemented |
| Build tooling with INI restore | Done |
| Documentation | In progress (this pass) |
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
7. **Switch Teams while Director is ignored until exit.** The booth suppresses
   pawn respawn and team changes; switching teams via the in-game menu does not
   take effect until the Director leaves the booth and `RestartPlayer()` runs.
8. **HUD warnings.** The 5 pre-existing `DirectorHUD` default-property warnings
   (`bShowScores`, `bShowStats`, `bShowCrosshair`, `bShowRadar`,
   `bShowVehicleNames`) are known and accepted; they do not affect runtime.

## Near-term work

### 1. Immediate fixes (from original roadmap)

- **Director-mode HUD (planned)**: see "Longer-term ideas" — building our own
  booth HUD is the clean way to stop native C++ vehicle strings from leaking
  into Director view.
- ✅ **Flag carrier immunity** — Emergency recall must not affect the flag carrier. (Already implemented: `HasFlag` check in `RecallTeam`)
- **Death spectate delay** — When the spectated player dies, wait 1 second before auto-cycling to the next. During this delay, purposefully glitch out all on-screen text. Account for edge case of a vehicle spawning on a dead player.
- ✅ **Configurable Nanite heal rate** — Expose "Healing per second" in the GUI (range 0.00–199). (Implemented: `NaniteHealRate` config + GUI)
- ✅ **Team-visible turret beacon** — Show mounted turret beacon for every team member deployed in the arena. Format is two centred, team-coloured lines above the turret: `Sentinel(n)` on the first line and `HP [X/X]` on the second (no quotes, no shield line — sentinels are walk-through turrets, not fighters). Combatants require line-of-sight from their camera to the turret (world geometry + actor occlusion). Implemented via `DirectorTurretBeaconInteraction` (combatants, LOS-checked) reading the replicated `TeamTurrets[16]` array in `MutTechDirector`. `DirectorTurretBeaconMessage` attaches/reuses (deduped) the interaction on field players via `ReceiveLocalizedMessage`.

  The Director does **not** get custom sentinel drawing: while spectating, the
  stock engine draws the native class name (`DirectorSentinel`) above every
  vehicle and this cannot be suppressed from UnrealScript (`Actor.PostRender`
  is native; `VehicleNameString` has no effect on the spectator overlay;
  `Level.Game.VehicleList` does not contain our spawned sentinel). Drawing our
  own text at the same spot would only overlap the native string, so the
  Director sees the stock name alone until the custom-HUD roadmap item lands.

  **Diagnostics:** every pipeline step emits `[BEACON-*]` script logs:
  - `DeploySentinel` — spawn result, team, spot, `OnTurretChange()` call.
  - `OnTurretChange` — calls `RefreshTurretList()` then `AttachTurretBeaconsToTeam()` so every current combatant gets the beacon interaction attached whenever the turret roster changes (not only at booth entry).
  - `RefreshTurretList` — each sentinel scanned, team-match decision, final slot count, push to mutator array.
  - `RefreshTeamTurrets` — copy count into replicated `MutTechDirector.TeamTurrets`.
  - `AttachTurretBeaconsToTeam` / `ModifyPlayer` — each field player considered, whether `DirectorTurretBeaconMessage` is sent. `ModifyPlayer` sends to non-Director combatants only when a Director is active (`RI != None`); the Director is excluded.
  - `ExitDirectorMode` — sends `DirectorTurretBeaconMessage` to the exiting Director so they see sentries as a combatant after leaving the booth.
  - `CompleteEntry` — attempts to remove any leftover combatant beacon interaction from the Director (server-side; the `IsInState('Spectating')` guard in the combatant interaction is the reliable client-side backstop).
  - `DirectorTurretBeaconMessage.ClientReceive` — mutator found/not found, existing interaction reused vs new added, final `bVisible`/`bActive`.
  - `DirectorTurretBeaconInteraction.PostRender` — entry, viewport pawn (with `PC.Pawn` fallback), LocalPC, mutator found via full `NextMutator` chain walk, per-slot skip/draw reasons (behind camera, off-canvas, LOS blocked), text drawn. Uses `C.SmallFont` to match player nameplate typography/size. Skips drawing while the viewer is in Director booth mode (`IsInState('Spectating')`).

  Tail the server log (`-log`) on the server and each client log to verify turrets enter the array, interactions attach, and beacons draw.

### 2. Live multi-client playtest

- Host a listen server with one human Director and at least two human/bot
  fighters.
- Verify:
  - the automatic `B` bind arrives on every joining client;
  - the 5 s entry countdown popups, cancel-on-death and cancel-on-second-press;
  - wheel and zoom on a real input stack;
  - feed auto-cycle timing after a death;
  - nameplate projection at range and through walls;
  - sentinel beacons appear for combatants (LOS-checked) and the Director (no LOS gate) as `Sentry` / `HP [X/X]`, no Shield line;
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
- **Custom Director-mode HUD**: replace the reliance on the stock HUD while in
  the booth with a purpose-built HUD layer drawn by the mutator itself, so the
  Director no longer inherits native C++ strings that UnrealScript cannot
  suppress (the stock `DirectorSentinel` / vehicle name / `HEALTH` / `SHIELD`
  overlay drawn above every vehicle while spectating). A custom HUD would let
  us render sentinel beacons, team plates and counters with full control over
  position, typography and lifetime instead of working around the engine.
  Scope: feasible as an `Interaction.PostRender` HUD while the Director is in
  the booth, but it must coexist with the stock HUD (or hide it) and reproduce
  the pieces we still rely on (crosshair-free feed, hotbar, cheatsheet,
  counters, friendly plates). Long-term: also a clean path to removing the
  native vehicle-name overlay from Director view entirely.
- **Map-aware anchors**: cache nearby `NavigationPoint`s for recall spots
  instead of only radial traces, for tighter bases.
- **cDOM2 compatibility**: decompile the cDOM2 packages (same workflow used for
  the stock engine in `/home/jdmr/Proyectos/EngineDecomp`) to identify its
  gametype, control-point actors, team indexing, spawn selection and any
  `PlayerController`/`Pawn` overrides. Then add compatibility so the Director
  works on cDOM2 maps: correct home anchor for Emergency Recall (likely the
  team's owned control point or nearest team spawn), valid transmat landing
  spots around control points, and verification that booth entry, nameplates,
  sentinel/turret beacons, all nine abilities and roster counters behave the
  same as in stock DOM. Add a cDOM2 smoke test to the live playtest checklist.

## Non-goals

- Subclassing every team gametype.
- Adding networked custom assets (textures, meshes, sounds).
- Turning the Director into a combatant.
- Bypassing the server authority model for "responsiveness".

## Source hashes at last build

```text
b9b093930b921c1e3b465c4c0c427960db741a15b74e85d76bdfddad8369b9f6  DirectorBindKeyMessage.uc
3fa17d82e05a1af520f8c649a42fc4ea8651401a19b34bad59aa992986dad667  DirectorInteraction.uc
06699d1cc107d1f0350aa985287966f684e82363ef78afb6e377f37fb3925911  DirectorNotifyText.uc
0b14e76addd69ca2833d2e1c62e01beadd9222edf9e6ee60cdf360a41b83ce73  DirectorNotify.uc
a8da70ba6db1b196143776b62ba2f2d1a50aa89fcef4c6683691fe4325a7c162  DirectorReplicationInfo.uc
9d826eb1c12e23163440e9f73b16ef9935709f7043ac77e6337e62f679d49648  DirectorRules.uc
09fba41044bb77c641768adeedad6214e2e1998b137d4ab4d4979d517e5d0035  DirectorSentinel.uc
f41efe9bc384e338c62d89957f0cb51c0e49642426328fc06f28b4c3937bed09  DirectorTurretBeaconInteraction.uc
bd2c5e491e1f10da5a151b142b6621ea9184804a2d76088dcf270b4af1726171  DirectorTurretBeaconMessage.uc
c7524efb89fec707e6b58b7c76eb80e90ea103ecbe9d5366579da063c1838732  MutTechDirectorConfig.uc
28e553c447e64042aa8354691e598fdcd855abb7e8921e7d2eef6a8202ee01b5  MutTechDirector.uc
```

Package hash at last build:
`62be5a2b673bc5ea0a75ae185f842ebc9abf3a0af1ba1ec8f5385d2fb0a741e3`.

If source changes, rerun `./tools/build.sh` and update these hashes and
`prebuilt/BUILD`. Do not compare `.u` hashes across builds: UCC may embed
build-time data, so the binary hash is not a stable content identifier.