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
    local Mutator Mut;
    local int Idx;

    Log("MutTechDirector: [BEACON] DirectorTurretBeaconMessage.ClientReceive called for P=" $ P);

    if (P == None || P.PlayerReplicationInfo == None || P.PlayerReplicationInfo.Team == None)
    {
        Log("MutTechDirector: [BEACON] ClientReceive early return - invalid P or PRI");
        return;
    }

    Log("MutTechDirector: [BEACON] P=" $ P $ " Team=" $ P.PlayerReplicationInfo.Team.TeamIndex $ " bOnlySpectator=" $ P.PlayerReplicationInfo.bOnlySpectator $ " Pawn=" $ P.Pawn);

    // Find the MutTechDirector mutator through PlayerController.Level.Game (works in static ClientReceive)
    // Walk the full mutator chain: MutTechDirector may not be BaseMutator when other
    // mutators are loaded before it.
    M = None;
    if (P != None && P.Level != None && P.Level.Game != None)
    {
        Mut = P.Level.Game.BaseMutator;
        while (Mut != None)
        {
            M = MutTechDirector(Mut);
            if (M != None)
                break;
            Mut = Mut.NextMutator;
        }
    }

    if (M == None)
    {
        Log("MutTechDirector: [BEACON] ClientReceive - mutator NOT found on BaseMutator chain for P=" $ P);
        return;
    }

    Log("MutTechDirector: [BEACON] ClientReceive - mutator found M=" $ M);

    // Attach the beacon interaction, reusing an existing one so repeated
    // attaches (booth re-entry, respawn, self-healing bind) don't stack
    // duplicate interactions that would draw the beacon text multiple times.
    BeaconInteraction = None;
    for (Idx = 0; Idx < P.Player.LocalInteractions.Length; Idx++)
    {
        BeaconInteraction = DirectorTurretBeaconInteraction(
            P.Player.LocalInteractions[Idx]);
        if (BeaconInteraction != None)
        {
            Log("MutTechDirector: [BEACON] Found existing beacon interaction at LocalInteractions[" $ Idx $ "] BeaconInteraction=" $ BeaconInteraction);
            break;
        }
        BeaconInteraction = None;
    }

    if (BeaconInteraction == None)
    {
        Log("MutTechDirector: [BEACON] No existing beacon interaction; adding new one via InteractionMaster.");
        BeaconInteraction = DirectorTurretBeaconInteraction(
            P.Player.InteractionMaster.AddInteraction(
                "MutTechDirector.DirectorTurretBeaconInteraction", P.Player));
        Log("MutTechDirector: [BEACON] AddInteraction result BeaconInteraction=" $ BeaconInteraction);
    }
    else
    {
        Log("MutTechDirector: [BEACON] Reusing existing beacon interaction.");
    }

    if (BeaconInteraction != None)
    {
        BeaconInteraction.RI = None; // Not needed
        BeaconInteraction.PC = P;
        BeaconInteraction.bVisible = True;
        BeaconInteraction.bActive = True;
        Log("MutTechDirector: [BEACON] attached turret beacon interaction for field player on client P=" $ P $ " bVisible=" $ BeaconInteraction.bVisible $ " bActive=" $ BeaconInteraction.bActive);
    }
    else
    {
        Log("MutTechDirector: [BEACON] ClientReceive - Failed to add interaction!");
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