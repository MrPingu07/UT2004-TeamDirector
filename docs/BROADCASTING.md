# Broadcasting System

This document covers the Tournament Technical Director's ambient **broadcast
feed**: the typewriter banner at the bottom of the booth HUD, its server-side
`.ini` configuration, and the live-match tokens that can appear inside each
message.

It does **not** cover the Director's ability/booth notifications. Those are a
separate channel (`DirectorNotify` / `DirectorNotifyText`) and are described at
the end for contrast.

---

## 1. Two on-screen channels

| Channel | Class | Position | Contents | Configurable |
| --- | --- | --- | --- | --- |
| **Broadcast feed** | `DirectorHUD` | Bottom banner, inside the team-coloured band | Ambient, shuffled messages with live-match tokens | Yes, server-side, via `MutTechDirector.ini` |
| **Director notifications** | `DirectorNotify` | Upper centre (`PosY=0.18`) | Ability confirmations, booth state, errors ("Blindage authorized", "Not enough space", ...) | No |

The feed is cosmetic and never authoritative. It reads replicated match state
only; it never changes gameplay, scores, or cooldowns.

---

## 2. Where the code lives

| File | Responsibility |
| --- | --- |
| `source/MutTechDirector/Classes/DirectorFeed.uc` | Config-backed message array plus the token helpers and `ExpandTokens()` |
| `source/MutTechDirector/Classes/DirectorHUD.uc` | Shuffle bag, message selection, snapshotting, typewriter rendering |
| `source/MutTechDirector/Classes/DirectorReplicationInfo.uc` | Replicates the server's feed list to the Director's client |
| `install/MutTechDirector.ini` | Shipped source copy of the feed config; this is the file edited and released |
| `<UT2004>/System/MutTechDirector.ini` | Runtime configuration read by the **server/host** |
| `install/README.txt` | End-user instructions for the same workflow |

The HUD and token expansion run on each client, but the **message list comes
from the server**. The server reads `MutTechDirector.ini`, snapshots the list
into `DirectorReplicationInfo`, and replicates it to the Director's client.
Joining players therefore do not need the ini, and everyone sees the host's
broadcast. Tokens are still resolved client-side from replicated match state,
so they stay live on each client.

---

## 3. Data flow

```text
install/MutTechDirector.ini                (server/host install)
   │  copied into <UT2004>/System/ (tools/build.sh does this)
   ▼
<UT2004>/System/MutTechDirector.ini        (server/host)
   │
   ▼
class'DirectorFeed'.default.Messages       (server)
   │  CopyFeedMessages() when the booth opens
   ▼
DirectorReplicationInfo.FeedMessages[256]  ── reliable, owner-only ──► client
                                                                        │
                                                                        ▼
                                                          PickMessage()
                                                     shuffle bag, empty entries
                                                                        │
                                                                        ▼
                                          DirectorFeed.ExpandTokens(Msg, PC)
                                              live match state, client-side
                                                                        │
                                                                        ▼
                                                CurrentMessage  (snapshot)
                                                                        │
                                                                        ▼
                                                  typewriter ──► Canvas
```

The list is capped at **256 messages**; entries beyond that are ignored. The
current feed is 110 messages.

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

1. Edit `install/MutTechDirector.ini` in the project. This is the shipped
   source copy; there is no separate message list or conversion script.
2. Keep the `[MutTechDirector.DirectorFeed]` section and use one repeated
   `Messages=` line per entry.
3. Install it into `<UT2004>/System/MutTechDirector.ini` **on the server or
   host**. `tools/build.sh` copies it automatically during a build; for a
   manual install, copy the file. Clients do not need it: the server sends
   them the list when a Director enters the booth.
4. Restart UT2004 on the host (config is loaded at startup).

The compiled defaults are:

```text
TECHNICAL DIRECTOR MODE
PRESS [B] TO EXIT BOOTH
```

They remain the fallback whenever the server's config array is empty, the
server's ini cannot be read, or a client receives no replicated list.

---

## 4. Selection and presentation

### 4.1 Shuffle bag

`DirectorHUD.PickMessage()` keeps a shuffle bag of message indices over the
server-replicated list:

- Every configured message is shown once before any message repeats.
- The bag is refilled and reshuffled when empty.
- Empty strings are consumed and skipped.
- If every entry is empty, the HUD falls back to `TECHNICAL DIRECTOR MODE`.
- The bag is reset when the message source changes (local fallback → server
  list) and persists for the booth session otherwise.

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

Only the message template is uppercased. Dynamic values keep their own casing,
so a player named `xX_Sn1p3r_Xx` is not mangled into `XX_SN1P3R_XX`.

---

## 5. Token reference

### 5.1 General rules

- Literal message text is uppercased before token replacement, so messages may
  be authored in normal sentence case. As a side effect token matching is
  effectively case-insensitive (`$mapname` also works), but uppercase remains
  the canonical style.
- **Token values are inserted after uppercasing**, so player names, server
  names, map names and team names keep their original casing. Only the
  template text is forced to caps.
- Tokens are plain text in the `.ini`; the `$` character has no special
  meaning to the config parser. In UnrealScript `$` is the concatenation
  operator, but only outside string literals.
- Unknown tokens are left untouched and appear literally.
- Every token has a defined fallback, so a message never becomes empty just
  because a value is unavailable.
- Random tokens (`$RANDOM1_25`, `$RANDOM25_50`, `$RANDOM75_100`) are resolved
  once per message, alongside the live values, and differ per client.
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
| `$TOPTEAMNAME` | Display name of the Director's team | `GRI.Teams[team].TeamName`; `Red`/`Blue` if the name is blank; fallback `Our Team` |
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
- `$TOPTEAMNAME` and `$TOPTEAMFRAGGER` both refer to that team. Neither means
  "the team currently leading"; use `$LEADTEAM` for that.
- Bots participate in every standings token.

### 5.5 Time and status

| Token | Prints | Source and fallback |
| --- | --- | --- |
| `$MATCHSTATUS` | Match phase | See §6; fallback `Unknown` |
| `$TIMEELAPSED` | Time since the match started | `GRI.ElapsedTime` formatted `m:ss`; fallback `0:00` |
| `$TIMEREMAINING` | Time before the clock runs out | `GRI.RemainingTime` formatted `m:ss`, or `Warmup`, `No Limit`, `Overtime`; fallback `Unknown` |

Clock format is minutes without leading zero and seconds with two digits:
`0:07`, `4:05`, `12:34`.

### 5.6 Random values

These produce a fresh integer each time a message is selected. The ranges are
**inclusive** on both ends, and the numbers are resolved during the same
single expansion pass as every other token, so they stay fixed for the whole
typewriter cycle.

| Token | Prints |
| --- | --- |
| `$RANDOM1_25` | Random integer from 1 to 25 inclusive |
| `$RANDOM25_50` | Random integer from 25 to 50 inclusive |
| `$RANDOM75_100` | Random integer from 75 to 100 inclusive |

Randomness is local to each client, not replicated: two Directors watching the
same message can see different values. That matches the cosmetic nature of the
feed. The ranges deliberately overlap at 25; `25` can come from either of the
first two tokens.

```text
TONIGHT'S CROWD: $RANDOM75_100 PERCENT HERE FOR THE VIOLENCE.
ODDS OF SURVIVAL: $RANDOM1_25 PERCENT. ODDS OF STYLE: $RANDOM25_50.
```

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
The server did not read its ini, so the compiled defaults were replicated.
Check on the **server/host**:

```sh
grep -n '^\[MutTechDirector.DirectorFeed\]' \
     "$HOME/Juegos/UT2004/System/MutTechDirector.ini"
grep -c '^Messages=' \
     "$HOME/Juegos/UT2004/System/MutTechDirector.ini"
```

The section must exist and use repeated `Messages=` keys. `Messages(0)=` will
not work. Confirm the file is in the server's `System` directory next to
`MutTechDirector.u`, then restart the server. The server's log prints
`replicated N feed messages` when a Director enters the booth.

**A client still shows the compiled defaults while the server has a feed.**
The client did not receive `DirectorReplicationInfo`, or the booth was opened
before it replicated. Re-enter the booth. The client-local
`MutTechDirector.ini` is ignored whenever the replicated list has entries.

**A token appears literally (e.g. `$MAPNAME`).**
Check spelling and that the token exists in the compiled package. Token
matching is case-insensitive because the template is uppercased first, but
the canonical style is uppercase. Rebuild after adding a token.

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
- **256-message cap.** The replicated array is fixed at 256 entries. Extra
  `Messages=` lines beyond that are dropped. The shipped feed has 110.
- **Client-local ini is ignored when the server list arrives.** Editing your
  own `MutTechDirector.ini` on a client has no effect during a networked
  match; edit the server's copy instead. Standalone/Instant Action uses the
  local file, so single-player still works as before.
- **Server list is snapshotted when the booth opens.** Changing the server's
  ini mid-match does not reach an already-active booth; it applies on the next
  entry (or after a map change/restart).
- **Control characters.** Player colour codes are preserved by design. A name
  with unusual control sequences will render exactly as the game would render
  it.
- **No width filter.** See §4.3.
- **Random tokens are per client.** `$RANDOM1_25`, `$RANDOM25_50` and
  `$RANDOM75_100` are rolled locally when the message is selected, so two
  clients can show different numbers for the same feed entry.

---

## 11. Related documentation

- `docs/APPROACH.md` — overall booth/HUD architecture.
- `docs/FINDINGS.md` — verified engine facts and compiler quirks.
- `install/README.txt` — end-user installation and feed-editing workflow.
- `source/MutTechDirector/Classes/DirectorFeed.uc` — config defaults, token
  helpers, and `ExpandTokens()`.
- `source/MutTechDirector/Classes/DirectorHUD.uc` — shuffle bag, snapshot,
  typewriter phases.
