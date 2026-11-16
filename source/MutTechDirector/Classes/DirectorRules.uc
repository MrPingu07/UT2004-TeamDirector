//=============================================================================
// DirectorRules
//
// Small GameRules companion to MutTechDirector.
//
// The mutator intentionally does not replace or subclass any gametype, so it
// needs a safe place to add team-start fallback behavior without editing core
// files.  This rule is added to Level.Game.GameRulesModifiers at PostBeginPlay.
//
// The only behavior it adds is a last-resort FindPlayerStart fallback:
// GameInfo.FindPlayerStart normally chooses a start, but some custom or
// objective-heavy maps have navigation points with unusual TeamNumber values.
// When the normal chain returns None, this rule searches PlayerStart actors
// for the requested team before giving up.  Returning None from here is safe:
// GameInfo's own search continues exactly as it would without the mutator.
//
// Everything else is deliberately delegated to the next GameRules in the
// chain so other mutators and the stock gametype remain in control.
//=============================================================================
class DirectorRules extends GameRules;

function NavigationPoint FindPlayerStart(Controller Player, optional byte InTeam,
    optional string incomingName)
{
    local NavigationPoint N;
    local PlayerStart PS;
    local PlayerStart AnyStart;
    local byte Team;

    // Let every other rule and the stock game have first refusal.
    N = Super.FindPlayerStart(Player, InTeam, incomingName);
    if (N != None)
        return N;

    if (Player != None && Player.PlayerReplicationInfo != None &&
        Player.PlayerReplicationInfo.Team != None)
        Team = Player.PlayerReplicationInfo.Team.TeamIndex;
    else
        Team = InTeam;

    // First pass: a start explicitly tagged for this team.
    foreach DynamicActors(class'PlayerStart', PS)
    {
        if (PS == None || !PS.bEnabled)
            continue;

        if (PS.TeamNumber == Team)
            return PS;

        if (AnyStart == None && (PS.TeamNumber == 255 || PS.TeamNumber == 0))
            AnyStart = PS;
    }

    // Second pass: neutral or default-tagged start.
    if (AnyStart != None)
        return AnyStart;

    // Final pass: any enabled start in the level.
    foreach DynamicActors(class'PlayerStart', PS)
    {
        if (PS != None && PS.bEnabled)
            return PS;
    }

    return None;
}

defaultproperties
{
}
