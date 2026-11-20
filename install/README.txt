Tournament Technical Director (TeamDirector) for Unreal Tournament 2004
=========================================================================

A team-support mutator that turns one player into the team's Tournament
Technical Director: a remote broadcast operator with a locked fighter feed,
tactical zoom, nanite healing and nine transmat abilities.

Requires Unreal Tournament 2004 v3374 (or a compatible community patch).
The vehicle drops require the Onslaught / ECE packages present in a normal
UT2004 install.


INSTALL
-------

1. Copy the four files from the "System" folder of this archive into your
   UT2004 "System" folder:

       MutTechDirector.u
       MutTechDirector.ucl
       MutTechDirector.int
       MutTechDirector.ini

2. Start the game and open Instant Action or Host Game.
3. Add "Tournament Technical Director" in the Mutators list.
4. Optional: click "Configure Mutators" to tune the nine cooldowns and the
   Nanite heal rate.
5. In game, press B to enter the booth (5 second delay) or leave instantly.

If you only join other people's servers, MutTechDirector.ini is optional: the
server sends its feed list to your client. Install it if you host or play
Instant Action and want to customize the banner text.

The B key is bound automatically on spawn. The console command
"mutate director" also works. Older installs that used N have that stale bind
cleared automatically.


CONTROLS
--------

    B                    Enter the booth (5 s delay) / leave instantly
    Mouse wheel up/down  Cycle the fighter on the feed
    Hold left mouse      Zoom in
    Hold right mouse     Zoom out
    Hold Jump            Nanite Med-Surge (heals the fighter on the feed)
    Q / E                Cycle pages: Personal -> Machinery -> All
    1 / 2 / 3            Open Personal / Machinery / All page
    Crouch (C or Ctrl)   Return to the Pages picker
    H                    Show/hide the cheatsheet; the H hint stays visible

Jump healing works on every page, even while the Pages picker is open.

The booth opens on the Pages picker by default:

    [1] Personal         Original slots 1, 3, 4, 5, 9 -> keys 1-5
    [2] Machinery        Original slots 2, 6, 7, 8 -> keys 1-4
    [3] All              The full original 1-9 list

Q and E cycle Personal -> Machinery -> All and wrap in both directions.
Crouch returns to the picker from any page. Every picker/page also shows
"[Crouch] Back | [Q/E] Cycle pages" unless H has hidden the cheatsheet.

Pressing H hides every cheatsheet line except "[H] Show controls". Press H
again to restore the list. Re-entering the booth restores it automatically.


TRANSMAT SLOTS
--------------

    1  Ammunition Requisition
    2  Perimeter Defense (walk-through, shootable sentinel turret)
    3  Painkillers (raises fighter health to at least 300)
    4  Blindage (+100 shield)
    5  Stimuli Dose (Berserk for 30 seconds)
    6  SPMA Artillery
    7  Light Vehicle Transmat (Raptor / Cicada)
    8  Heavy Asset Drop (Hover Tank)
    9  Emergency Recall

All slots default to a 1.0 second cooldown and are configurable from
Configure Mutators. The Nanite Med-Surge defaults to 2 HP/sec and is
configurable there too (0-199 HP/sec).


HUD AND SENTINEL BEACONS
------------------------

While the booth is open, the stock HUD is swapped for a Director HUD. It draws
a clean broadcast frame, the team score and match clock, and the typewriter
feed banner at the bottom. The original HUD returns when you leave.

The top-left hotbar shows the Pages picker or the selected page, with live
[READY] / [Ns] cooldown states. The top-right cheatsheet lists one control per
line. The bottom-right TeamMates / Alive / Dead counter is server-authoritative
and includes bots, but not the Director.

Friendly fighters, driven vehicles and deployed sentries are labelled through
walls: three lines for players (Name / HP / Shield), two lines for sentries
(Sentry / HP [current/max]). Field players also see friendly sentry beacons as
two team-coloured lines, but only with clear line of sight.

Emergency Recall first tries a distinct landing spot for every living
teammate. If the team anchor cannot fit everyone, the whole team is moved to
the gametype's objective centre (CTF flag, ONS power core/node, an owned DOM
point, or a team spawn in TDM/Invasion/Bombing Run) with 5 seconds of
collision transparency. In DOM/cDOM2, a recall fails explicitly if the team
owns no control point.


FEED MESSAGES (TYPEWRITER BANNER)
---------------------------------

The bottom banner types random messages from a config array. The **server or
host** reads MutTechDirector.ini and sends its message list to each Director's
client, so joining players do not need the file. The copy shipped with this
archive contains 155 tournament-feed messages.

To customize messages, edit the [MutTechDirector.DirectorFeed] section of
MutTechDirector.ini on the server/host:

    [MutTechDirector.DirectorFeed]
    Messages=TECHNICAL DIRECTOR MODE
    Messages=PRESS [B] TO EXIT BOOTH

The ini uses the UT2004 dynamic-array format: one repeated bare key per
message, with no index and no quotes. Do NOT write "Messages(0)=..." - the
indexed form is only for static arrays and is silently ignored. A missing or
unreadable ini falls back to the two compiled defaults above.

Messages may contain live-match tokens such as $MAPNAME, $TOPFRAGGER,
$TOPFRAGGERSCORE, $PLAYERCOUNT, $TOPTEAMNAME, $TOPTEAMSHORT, $LEADTEAMNAME,
$LEADTEAMSHORT, $LEADTEAMFRAGGER and the rest of the roster. Random numbers
use the dynamic $RANDOM<min>_<max> form, e.g. $RANDOM1_9, $RANDOM25_50 or
$RANDOM1_50K. Large random results are grouped with dots (e.g. 43.781). The
full list, fallbacks and match-state rules are documented in
docs/BROADCASTING.md.

Message text is uppercased automatically, so it can be written in normal
sentence case. Token values are uppercased too: player names, server names,
map titles and team names all render in caps. Messages are never filtered by
width.

The HUD runs on the client, but the message list is replicated from the
server. A client-local MutTechDirector.ini is ignored during a networked match
when the server provides a list. For standalone/Instant Action, the local file
is used as usual.


TROUBLESHOOTING
---------------

B does nothing:
    Check Options -> Input for the B binding, or type "mutate director" in the
    console. Other mods that rebind B are overwritten on your next spawn.

The mutator does not appear:
    Confirm the three System files are present and that this is a team
    gametype (TDM, CTF, ONS, DOM, Bombing Run, Assault, etc.).

The hotbar starts on a page list:
    That is the default. Press 1, 2 or 3 to choose a page, or Q/E to cycle.
    Crouch returns to the picker.

The cheatsheet vanished:
    Press H. The "[H] Show controls" reminder is intentionally left visible.

The banner shows the two compiled defaults:
    The server/host did not read MutTechDirector.ini. Confirm the
    [MutTechDirector.DirectorFeed] section exists and uses repeated
    "Messages=" keys, then restart the server.

Emergency Recall says no safe destination:
    The team anchor is full and the gametype fallback is unavailable. In DOM
    or cDOM2, capture at least one control point first.
