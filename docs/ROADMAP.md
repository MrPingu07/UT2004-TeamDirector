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
| Automatic `K` bind for host and clients, no PC subclass | Implemented |
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
3. **No custom HUD.** This is deliberate. The Interaction is the whole UI.
4. **Recall teleports vehicle pawns as vehicles.** Occupants are not extracted
   first. In practice the vehicle is moved with its driver, which is consistent
   with a transmat recall, but it can look dramatic on slopes.
5. **Berserk is a 30-second timer.** If another mutator also manages
   `bBerserk`, the last writer wins. The expiry path clears only the state this
   RI set.
6. **No localization layer.** All strings are English literals in source.
7. **Cooldowns apply next match.** Editing them through Configure Mutators
   writes class defaults; a booth that is already open keeps the values copied
   at its entry countdown, and the change takes effect on the next match.

## Near-term work

### 1. Live multi-client playtest

- Host a listen server with one human Director and at least two human/bot
  fighters.
- Verify:
  - the automatic `K` bind arrives on every joining client;
  - the 5 s entry countdown popups, cancel-on-death and cancel-on-second-press;
  - wheel and zoom on a real input stack;
  - feed auto-cycle timing after a death;
  - nameplate projection at range and through walls;
  - the `TeamMates` counter with bots and with a partial roster;
  - every ability in CTF, ONS and TDM;
  - recall spacing with a full team;
  - exit respawn with spawn protection;
  - cooldown pause on exit and full reset on re-entry;
  - Configure Mutators round-trips the nine values.
- Capture client logs for replication warnings (`ScriptLog`, `NetLog`).

### 2. Remaining config options

`Cooldown1..9` is done. Still candidates for the same `config(User)` block:

- `bOneDirectorPerTeam`;
- `bAllowInNonTeamGames` (probably stay `False`);
- heal rate;
- zoom min/max.

Keep the defaults identical to the current constants so behaviour does not
change for existing servers.

### 3. Friendly roster replication (nameplates)

If live tests show missing distant nameplates, add a compact replicated array
of `{Pawn, Name, Health, Shield}` to the RI, updated at a low rate (2–4 Hz).
This is a deliberate trade: more bandwidth for guaranteed through-wall
telemetry. Measure before adding it.

### 4. Ability polish

- Add a short transmat "incoming" delay (0.5–1 s) with a warning sound, so
  drops feel physical and fighters can react.
- Add team-colored sentinel FX and a sentinel ownership check to avoid
  stacking dozens on one point.
- Add a recall confirmation cue for affected teammates (a short client
  message).
- Add a cooldown-completion cue to the Director (subtle, once per slot).

### 5. Compatibility test matrix

| Gametype | Map | Status |
|---|---|---|
| TDM (`xTeamGame`) | DM-Rankin | Smoke-tested server load |
| CTF (`xCTFGame`) | CTF-FaceClassic | To test |
| ONS (`ONSOnslaughtGame`) | ONS-Torlan | To test |
| AS (`ASGameInfo`) | AS-Convoy | To test |
| BR (`BombingRun`) | BR-Ankh | To test |
| DOM (`xDomination`) | DOM-Suntemple | To test |
| cDOM (`ClassicDom`) | any DOM map | To test |

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

- **Team comms flavor**: director-only voice/text macros ("push mid", "fall
  back") that appear in team chat, reinforcing the broadcast fiction.
- **Broadcast overlay**: optional top-center score strip for the Director,
  still plain text.
- **Spectator-safe director**: allow a true spectator to take the booth in
  warmup without counting as a fighter.
- **Map-aware anchors**: cache nearby `NavigationPoint`s for recall spots
  instead of only radial traces, for tighter bases.
- **Configurable hotbar binding**: let servers remap slots off the number row.
- **Replay-friendly telemetry**: write a compact director log to the server log
  for shoutcasting.

## Non-goals

- Replacing the stock HUD.
- Subclassing every team gametype.
- Adding networked custom assets (textures, meshes, sounds).
- Turning the Director into a combatant.
- Bypassing the server authority model for "responsiveness".

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

Package hash at last build:
`768c3af7247be7bb37acfacda4a7942e2f60449edd4f3f0b7f18ee9f1a0f2db2`.

If source changes, rerun `./tools/build.sh` and update these hashes and
`prebuilt/BUILD`. Do not compare `.u` hashes across builds: UCC may embed
build-time data, so the binary hash is not a stable content identifier.