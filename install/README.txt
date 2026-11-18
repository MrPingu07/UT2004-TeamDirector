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
4. Optional: click "Configure Mutators" to tune the nine cooldowns.
5. In game, press B to enter the booth (5 second delay) or leave instantly.

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
Configure Mutators.


TEAM SENTINEL BEACONS
---------------------

Teammates see two team-coloured lines above friendly sentinels:

    Sentinel(n)
    HP [current/max]

Combatants need line of sight to the sentinel. The Director does not draw a
custom beacon; while spectating, the stock engine displays the sentinel's
native name instead.

Emergency Recall first tries a distinct landing spot for every living
teammate. If the team anchor cannot fit everyone, the whole team is moved to
the gametype's objective centre (CTF flag, ONS power core/node, an owned DOM
point, or a team spawn in TDM/Invasion/Bombing Run) with 5 seconds of
collision transparency. In DOM/cDOM2, a recall fails explicitly if the team
owns no control point.


FEED MESSAGES (TYPEWRITER BANNER)
---------------------------------

The bottom banner types random messages from a config array. Each client reads
its own MutTechDirector.ini. The file shipped with this archive already
contains the tournament feed.

To customize messages, edit the [MutTechDirector.DirectorFeed] section of
UT2004/System/MutTechDirector.ini directly:

    [MutTechDirector.DirectorFeed]
    Messages=TECHNICAL DIRECTOR MODE
    Messages=PRESS [B] TO EXIT BOOTH

The ini uses the UT2004 dynamic-array format: one repeated bare key per
message, with no index and no quotes. Do NOT write "Messages(0)=..." - the
indexed form is only for static arrays and is silently ignored. A missing or
unreadable ini falls back to the two compiled defaults above.

Messages may contain live-match tokens such as $MAPNAME, $TOPFRAGGER,
$TOPFRAGGERSCORE, $PLAYERCOUNT, $TOPTEAMNAME and the rest of the roster. The
full list, fallbacks and match-state rules are documented in
docs/BROADCASTING.md.

The HUD runs on the client, so each client must have the .ini file.

TROUBLESHOOTING
---------------

B does nothing:
    Check Options -> Input for the B binding, or type "mutate director" in the
    console. Other mods that rebind B are overwritten on your next spawn.

The mutator does not appear:
    Confirm the three System files are present and that this is a team
    gametype (TDM, CTF, ONS, DOM, Bombing Run, Assault, etc.).

Emergency Recall says no safe destination:
    The team anchor is full and the gametype fallback is unavailable. In DOM
    or cDOM2, capture at least one control point first.
