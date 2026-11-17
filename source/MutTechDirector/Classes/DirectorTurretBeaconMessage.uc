//=============================================================================
// DirectorTurretBeaconMessage
//
// Invisible "message" whose only job is to run code on the owning client.
// 
// UT2004 has no server->client script RPC that is independent of a
// client-owned actor, but LocalMessage.ClientReceive is executed on the
// receiving machine by the reliable PlayerController.ReceiveLocalizedMessage.
// The mutator sends this to field players when a Director becomes active,
// so they attach the turret beacon interaction for LOS-checked beacon display.
//=============================================================================
class DirectorTurretBeaconMessage extends LocalMessage;

/** Nothing is ever drawn: this is a client-side code hook, not a notice. */
static function string GetString(
    optional int Switch,
    optional PlayerReplicationInfo RelatedPRI_1,
    optional PlayerReplicationInfo RelatedPRI_2,
    optional Object OptionalObject
    )
{
    return "";
}

static function bool IsConsoleMessage(int Switch)
{
    return False;
}

static function float GetLifeTime(int Switch)
{
    return 0.0;
}

static function ClientReceive(
    PlayerController P,
    optional int Switch,
    optional PlayerReplicationInfo RelatedPRI_1,
    optional PlayerReplicationInfo RelatedPRI_2,
    optional Object OptionalObject
    )
{
    local DirectorTurretBeaconInteraction BeaconInteraction;
    local MutTechDirector M;

    Log("MutTechDirector: DirectorTurretBeaconMessage.ClientReceive called for " $ P);

    if (P == None || P.PlayerReplicationInfo == None || P.PlayerReplicationInfo.Team == None)
    {
        Log("MutTechDirector: ClientReceive early return - invalid P or PRI");
        return;
    }

    // Find the MutTechDirector mutator through PlayerController.Level.Game (works in static ClientReceive)
    M = MutTechDirector(P.Level.Game.BaseMutator);
    while (M != None && !M.IsA('MutTechDirector'))
        M = MutTechDirector(M.NextMutator);

    if (M == None)
    {
        Log("MutTechDirector: ClientReceive - mutator not found");
        return;
    }

    Log("MutTechDirector: ClientReceive - mutator found");

    // Attach the beacon interaction and set mutator reference for turret list access
    // No Director RI needed - reads directly from mutator's replicated TeamTurrets array
    BeaconInteraction = DirectorTurretBeaconInteraction(
        P.Player.InteractionMaster.AddInteraction(
            "MutTechDirector.DirectorTurretBeaconInteraction", P.Player));
    if (BeaconInteraction != None)
    {
        BeaconInteraction.RI = None; // Not needed
        BeaconInteraction.PC = P;
        Log("MutTechDirector: attached turret beacon interaction for field player on client");
    }
    else
    {
        Log("MutTechDirector: ClientReceive - Failed to add interaction!");
    }
}

defaultproperties
{
    bIsSpecial=False
    bIsUnique=False
    bIsConsoleMessage=False
    bFadeMessage=False
    bBeep=False
    Lifetime=0.0
}