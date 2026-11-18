# Broadcasting System

This document covers the Tournament Technical Director's ambient **broadcast
feed**: the typewriter banner at the bottom of the booth HUD, its per-client
`.ini` configuration, and the live-match tokens that can appear inside each
message.

It does **not** cover the Director's ability/booth notifications. Those are a
separate channel (`DirectorNotify` / `DirectorNotifyText`) and are described at
the end for contrast.

---

## 1. Two on-screen channels

| Channel | Class | Position | Contents | Configurable |
| --- | --- | --- | --- | --- |
| **Broadcast feed** | `DirectorHUD` | Bottom banner, inside the team-coloured band | Ambient, shuffled messages with live-match tokens | Yes, per client, via `MutTechDirector.ini` |
| **Director notifications** | `DirectorNotify` | Upper centre (`PosY=0.18`) | Ability confirmations, booth state, errors ("Blindage authorized", "Not enough space", ...) | No |

The feed is cosmetic and never authoritative. It reads replicated match state
only; it never changes gameplay, scores, or cooldowns.

---

## 2. Where the code lives

| File | Responsibility |
| --- | --- |
| `source/MutTechDirector/Classes/DirectorFeed.uc` | Config-backed message array plus the token helpers and `ExpandTokens()` |
| `source/MutTechDirector/Classes/DirectorHUD.uc` | Shuffle bag, message selection, snapshotting, typewriter rendering |
| `feed.txt` | Human-editable source list, one message per line |
| `tools/feed2ini.sh` | Converts `feed.txt` into the game's `MutTechDirector.ini` |
| `<UT2004>/System/MutTechDirector.ini` | Runtime configuration read by every client |
| `install/README.txt` | End-user instructions for the same workflow |

The HUD runs on each client. There is no server→client feed message
transmission: every client loads its own `MutTechDirector.ini` and computes
tokens from replicated state locally.

---

## 3. Data flow

```text
feed.txt
   │  tools/feed2ini.sh
   ▼
MutTechDirector.ini  ──►  class'DirectorFeed'.default.Messages
                              │
                              ▼
                    PickMessage()  ── shuffle bag, empty entries skipped
                              │
                              ▼
          DirectorFeed.ExpandTokens(Msg, PlayerOwner)  ── live match state
                              │
                              ▼
                    CurrentMessage  ── snapshot, once per cycle
                              │
                              ▼
              typewriter phases ──► Canvas.DrawText
```

### 3.1 Config file and section

```ini
[MutTechDirector.DirectorFeed]
Messages=TECHNICAL DIRECTOR MODE
Messages=PRESS [B] TO EXIT BOOTH
Messages=WELCOME TO THE TOURNAMENT
```

`Messages` is a **dynamic** array (`var config array<string> Messages`). In
UE2/UT2004 dynamic string arrays are written as repeated bare keys, with no
index and no quotes. The indexed form (`Messages(0)=...`) belongs to static
arrays and is silently ignored here, which leaves the two compiled-in
defaults in place. That specific mistake is the most common reason for "my ini
is not parsed".

### 3.2 Authoring workflow

1. Edit `feed.txt`, one message per line. Blank lines and `#` comments are
   ignored. A final line without a trailing newline is still read.
2. Run `tools/feed2ini.sh`.
3. Copy the generated `System/MutTechDirector.ini` to every client's
   `UT2004/System/` folder. The file is per-client, not replicated.
4. Restart UT2004 (config is loaded at startup).

The compiled defaults are:

```text
TECHNICAL DIRECTOR MODE
PRESS [B] TO EXIT BOOTH
```

They remain the fallback whenever the config array is empty or the ini cannot
be read.

---

## 4. Selection and presentation

### 4.1 Shuffle bag

`DirectorHUD.PickMessage()` keeps a shuffle bag of message indices:

- Every configured message is shown once before any message repeats.
- The bag is refilled and reshuffled when empty.
- Empty strings are consumed and skipped.
- If every entry is empty, the HUD falls back to `TECHNICAL DIRECTOR MODE`.
- The bag lives on the HUD and persists for the booth session.

### 4.2 Snapshot at message start

Tokens are expanded exactly once, when a new message is chosen. The resulting
`CurrentMessage` is what the typewriter animates for the whole cycle. This is
deliberate:

- A score change cannot rewrite half-typed text.
- A long player name cannot re-centre the banner mid-cycle.
- Updated values appear naturally on the next message.

A new message is selected when the 22-second cycle completes, or after a
longer-than-0.5-second drawing gap (pause, menu, map load), which also prevents
stale text after returning to the HUD.

### 4.3 Width filtering: none

Earlier builds skipped messages wider than 90 % of the canvas. That check was
removed by design:

- The server/game already validates player names.
- Dynamic tokens make the final width different from the template width.
- A long name should not silently remove a message from the rotation.

The banner is centred and Canvas-clipped; an extreme name may reach the screen
edges, but the message still runs.

### 4.4 Colours and special characters

Colours and special characters inside player names or server names are passed
through untouched. The banner therefore preserves UT2004 colour sequences and
punctuation exactly as the game reports them. This is intentional; the feed is
not a sanitising layer.

---

## 5. Token reference

### 5.1 General rules

- Tokens are **uppercase and case-sensitive**. `$MAPNAME` expands;
  `$mapname` does not.
- Tokens are plain text in the `.ini`; the `$` character has no special
  meaning to the config parser. In UnrealScript `$` is the concatenation
  operator, but only outside string literals.
- Unknown tokens are left untouched and appear literally.
- Every token has a defined fallback, so a message never becomes empty just
  because a value is unavailable.
- Replacement is longest-first. `$TOPFRAGGERSCORE` is replaced before
  `$TOPFRAGGER`, otherwise the shorter token would eat its prefix. Any new
  token that is a prefix of another must follow the same rule.
- Tokens are expanded once per message snapshot (see §4.2).

### 5.2 Map and arena

| Token | Prints | Source and fallback |
| --- | --- | --- |
| `$MAPNAME` | Display title of the map | `Level.Title`; if empty or equal to the default `Untitled`, the map filename from `string(Level)` (`DM-Rankin.LevelInfo0` → `DM-Rankin`); final fallback `Unknown Arena` |
| `$SERVERNAME` | Public server name | `GRI.ServerName`; fallback `Local Arena` |
| `$PLAYERCOUNT` | Active combatants | Count of `GRI.PRIArray` entries with `!bOnlySpectator`; includes bots; dead-but-not-spectating players still count; fallback `0` |

### 5.3 Rules and match configuration

| Token | Prints | Source and fallback |
| --- | --- | --- |
| `$GAMETYPE` | Active game-mode name | `GRI.GameName`, then `Level.Game.GameName`; fallback `Tournament` |
| `$GOALSCORE` | Score needed to win | `GRI.GoalScore` when greater than zero, otherwise `No Limit` |

`GRI.GameName` is replicated from `GameInfo.GameName`; the `Level.Game`
lookup is a standalone/secondary fallback. `Level.Game.GameName` can differ
from the replication-info copy only briefly during initial join.

### 5.4 Standings and aggregates

All score values are UT2004 **scoreboard points**, which are floats internally
and can include objective points, not only kills. The feed prints them as
integers.

| Token | Prints | Source and fallback |
| --- | --- | --- |
| `$TOPFRAGGER` | Global match leader name | Highest `PRI.Score` among non-spectators; ties go to the first entry in `PRIArray`; fallback `Someone` |
| `$TOPFRAGGERSCORE` | Global leader's score | Score of that same player; fallback `lots of` |
| `$TOPTEAMFRAGGER` | Leader of the Director's team | Highest score filtered by `PRI.Team.TeamIndex == Director team`; fallback `Someone` |
| `$REDVAL` | Red team aggregate | `GRI.Teams[0].Score`; `0` if the slot is empty |
| `$BLUEVAL` | Blue team aggregate | `GRI.Teams[1].Score`; `0` if the slot is empty |
| `$LEADTEAM` | Team currently ahead | Compares the two team scores; `Red`, `Blue`, or `Neither` |
| `$TOTALFRAGS` | Combined score of all active players | Sum of every non-spectator `PRI.Score`; fallback `0` |
| `$HIGHESTSCORE` | Peak score on the board | Highest non-spectator `PRI.Score` as an integer; `0` if nobody is on the board |
| `$LEADMARGIN` | First-place gap over second place | Highest score minus second-highest; `0` when fewer than two combatants or when tied |

Team-index notes:

- UT2004 hardcodes team slots 0 and 1 as Red and Blue. `$REDVAL`, `$BLUEVAL`
  and `$LEADTEAM` are therefore meaningful only in team games; in a free-for-all
  they print `0`, `0`, `Neither`.
- The Director's team comes from
  `PlayerOwner.PlayerReplicationInfo.Team.TeamIndex`, which remains valid while
  the Director is in the booth because the mutator never removes them from the
  team.
- Bots participate in every standings token.

### 5.5 Time and status

| Token | Prints | Source and fallback |
| --- | --- | --- |
| `$MATCHSTATUS` | Match phase | See §6; fallback `Unknown` |
| `$TIMEELAPSED` | Time since the match started | `GRI.ElapsedTime` formatted `m:ss`; fallback `0:00` |
| `$TIMEREMAINING` | Time before the clock runs out | `GRI.RemainingTime` formatted `m:ss`, or `Warmup`, `No Limit`, `Overtime`; fallback `Unknown` |

Clock format is minutes without leading zero and seconds with two digits:
`0:07`, `4:05`, `12:34`.

---

## 6. Match-state semantics

`$MATCHSTATUS` is resolved in this order:

| Result | Condition |
| --- | --- |
| `Unknown` | No `GameReplicationInfo` yet |
| `Warmup` | `!GRI.bMatchHasBegun` |
| `Concluded` | `GRI.bStopCountDown` or `GRI.Winner != None` |
| `Overtime` | `GRI.TimeLimit > 0 && GRI.RemainingTime <= 0` |
| `Live` | Anything else |

`$TIMEREMAINING` uses the same information:

| Result | Condition |
| --- | --- |
| `Unknown` | No `GameReplicationInfo` |
| `Warmup` | Match has not begun |
| `No Limit` | `GRI.TimeLimit <= 0` |
| `Overtime` | Time limit exists and `GRI.RemainingTime <= 0` |
| `m:ss` | Normal countdown |

**Sudden death is not exposed by `GameReplicationInfo`.** Stock UT2004 keeps
the overtime/sudden-death flag on the server-side `GameInfo`, not in the
replicated info. The feed therefore reports `Overtime` for both. Adding a
replicated flag would require a custom game-info/RI and is intentionally out of
scope.

`$TIMEELAPSED` does not stop at zero: it continues to climb after the clock
expires, which is useful for overtime narration.

---

## 7. Examples

```text
$TOPFRAGGER LEADS THE BOARD WITH $TOPFRAGGERSCORE
SYNTONIZE THE TOURNAMENT IN $MAPNAME TODAY!
$SERVERNAME HOSTING $PLAYERCOUNT COMBATANTS IN $MAPNAME ($GAMETYPE)
LEAD MARGIN SITS AT $LEADMARGIN POINTS AS $TOPFRAGGER DRIVES THE PACE
MATCH STATUS: $MATCHSTATUS | TOTAL CUMULATIVE FRAGS: $TOTALFRAGS
$TOPTEAMFRAGGER IS CARRYING OUR COLOURS. RED $REDVAL - BLUE $BLUEVAL.
$LEADTEAM HOLDS THE ADVANTAGE.
THE CLOCK READS $TIMEREMAINING. $TIMEELAPSED HAS ALREADY GONE BY.
```

Fallback rendering (no GRI, warmup, or empty board):

```text
SOMEONE LEADS THE BOARD WITH LOTS OF
SYNTONIZE THE TOURNAMENT IN DM-RANKIN TODAY!
LOCAL ARENA HOSTING 0 COMBATANTS IN DM-RANKIN (TOURNAMENT)
LEAD MARGIN SITS AT 0 POINTS AS SOMEONE DRIVES THE PACE
MATCH STATUS: WARMUP | TOTAL CUMULATIVE FRAGS: 0
SOMEONE IS CARRYING OUR COLOURS. RED 0 - BLUE 0.
NEITHER HOLDS THE ADVANTAGE.
THE CLOCK READS WARMUP. 0:00 HAS ALREADY GONE BY.
```

---

## 8. Adding a new token

1. Add a helper to `DirectorFeed.uc` (or reuse an existing one). Helpers are
   `static` and take `PlayerController` and/or `GameReplicationInfo`; they must
   tolerate `None`.
2. Add one `ReplaceText(Msg, "$NEWTOKEN", Value);` line inside
   `ExpandTokens()`. `ReplaceText` is an in-place `out` function; do not assign
   its return value.
3. Respect prefix ordering: if the new token starts with, or is a prefix of,
   an existing token, replace the longer one first.
4. Choose and document a non-empty fallback.
5. Verify the value is available on the **client**. Anything read from
   `GRI` must be replicated (see the replication block in
   `Engine/GameReplicationInfo.uc`). Server-only fields will be zero/empty in
   the booth.
6. Update this document and the in-game examples if the token belongs to a
   user-facing workflow.
7. Rebuild with `tools/build.sh`.

Data that is *not* currently replicated and therefore not suitable for a
client-side token without extra networking:

- server-side `GameInfo.bOverTime` / sudden-death flags
- per-player kill/death counters (only `Score` is replicated in the PRI)
- objective internals that live only on the server (node/core health, etc.)
  unless exposed by an existing replicated field.

---

## 9. Testing and troubleshooting

**All cycles show the same two messages.**
The ini was not read. Check:

```sh
grep -n '^\[MutTechDirector.DirectorFeed\]' \
     "$HOME/Juegos/UT2004/System/MutTechDirector.ini"
grep -c '^Messages=' \
     "$HOME/Juegos/UT2004/System/MutTechDirector.ini"
```

The section must exist and use repeated `Messages=` keys. `Messages(0)=` will
not work. Also confirm the file is in the same `System` directory as
`MutTechDirector.u`, and restart the game.

**A token appears literally (e.g. `$MAPNAME`).**
Check spelling and capitalisation. Tokens are case-sensitive and must exist in
the compiled package. Rebuild after adding a token.

**The banner is blank for a cycle.**
An entry in the ini is empty. Empty entries are skipped, so this only matters
if every entry is empty; then `TECHNICAL DIRECTOR MODE` is used.

**Values look frozen.**
They are snapshotted per message; wait for the next cycle. If they never
change, confirm the client is receiving `GameReplicationInfo` (you are in a
match, not a menu/demo) and that the server is actually updating scores.

**Team tokens say `Someone` or `Neither`.**
The Director has no valid team reference yet, or the game is not a team game.
`$TOPTEAMFRAGGER` only searches the Director's team.

**Standings are one replication tick behind.**
Expected; see §10.

---

## 10. Known limitations

- **Replication lag.** Player scores and team scores arrive through normal
  actor replication, so a client can trail the server briefly. Irrelevant for
  an ambient banner.
- **No sudden-death token.** `GameReplicationInfo` does not expose it; see §6.
- **Score is not kills.** Objective gametypes award points for captures,
  nodes, etc. `$TOPFRAGGER` means "scoreboard leader", not necessarily the
  player with the most kills.
- **Ties.** `$TOPFRAGGER` keeps the first player encountered in `PRIArray`;
  `$LEADMARGIN` is `0` when first and second are tied.
- **Free-for-all team tokens.** Slots 0/1 exist but are not meaningful.
- **Localisation.** `Level.Title`, `GRI.GameName` and player names are printed
  as reported by the game; the feed does not translate or normalise them.
- **Per-client configuration.** Two clients can run different message lists.
  The feed is cosmetic, so this is acceptable, but it means "everyone sees the
  same broadcast" is not guaranteed.
- **Control characters.** Player colour codes are preserved by design. A name
  with unusual control sequences will render exactly as the game would render
  it.
- **No width filter.** See §4.3.

---

## 11. Related documentation

- `docs/APPROACH.md` — overall booth/HUD architecture.
- `docs/FINDINGS.md` — verified engine facts and compiler quirks.
- `install/README.txt` — end-user installation and feed-editing workflow.
- `source/MutTechDirector/Classes/DirectorFeed.uc` — config defaults, token
  helpers, and `ExpandTokens()`.
- `source/MutTechDirector/Classes/DirectorHUD.uc` — shuffle bag, snapshot,
  typewriter phases.
