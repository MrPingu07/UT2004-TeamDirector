//=============================================================================
// DirectorBindKeyMessage
//
// Invisible "message" whose only job is to run code on the owning client.
//
// UT2004 has no server->client script RPC that is independent of a
// client-owned actor, but LocalMessage.ClientReceive is executed on the
// receiving machine by the reliable PlayerController.ReceiveLocalizedMessage.
// MutTechDirector.ModifyPlayer() sends this message on every spawn, so each
// client (and the host) binds B -> "mutate director" into its own input
// config without replacing PlayerControllerClass and without touching any
// other mutator's controller (Ultimate Third Person stays fully compatible).
//
// B is the default toggle key.  Older builds bound N, so any stale N binding
// left over from those builds is cleared here before B is written.
//
// Binds are written exactly the way the stock GUI does it:
//   read  : ConsoleCommand("KEYBINDING B")
//   write : ConsoleCommand("set Input B mutate director")
//   clear : ConsoleCommand("SET Input N")
//=============================================================================
class DirectorBindKeyMessage extends LocalMessage;

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
    local string Cur;

    if (P == None)
        return;

    // Migration: older builds bound N.  Drop that stale bind so the toggle
    // lives only on B.
    Cur = P.ConsoleCommand("KEYBINDING N");
    if (Cur ~= "mutate director")
    {
        P.ConsoleCommand("SET Input N");
        Log("MutTechDirector: cleared legacy N bind");
    }

    Cur = P.ConsoleCommand("KEYBINDING B");
    if (Cur ~= "mutate director")
        return;

    P.ConsoleCommand("set Input B mutate director");
    Log("MutTechDirector: bound B -> mutate director on client (was '" $ Cur $ "')");
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
