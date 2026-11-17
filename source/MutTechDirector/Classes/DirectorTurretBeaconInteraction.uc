//=============================================================================
// DirectorTurretBeaconInteraction
//
// Lightweight client-side interaction attached to field players (non-Director
// team members) to render mounted turret beacons with line-of-sight checking.
//
// The Director (TD) sees all friendly pawns including turrets at all times
// via DirectorInteraction. Field players only see turret beacons when they
// have line-of-sight to the turret (world geometry + actor occlusion).
//
// Format: Sentinel(n\)HP [X/X] - team-colored, centered like player nameplates.
//=============================================================================
class DirectorTurretBeaconInteraction extends Interaction;

var DirectorReplicationInfo RI;
var PlayerController PC;

function Cleanup()
{
    bVisible = False;
    bActive = False;

    if (Master != None)
        Master.RemoveInteraction(Self);

    RI = None;
    PC = None;
}

function Tick(float DeltaTime)
{
    if (PC == None || PC.bDeleteMe)
    {
        Cleanup();
        return;
    }
}

/**
 * Check line-of-sight from viewer's camera to turret.
 * Uses PlayerController.Trace against world geometry and actors.
 */
simulated function bool HasLineOfSightToTurret(Canvas C, DirectorSentinel Turret, PlayerController LocalPC)
{
    local vector CamLoc, TurretLoc, HitLoc, HitNorm;
    local Rotator CamRot;
    local Actor HitActor;

    if (C == None || Turret == None || LocalPC == None)
        return False;

    C.GetCameraLocation(CamLoc, CamRot);
    TurretLoc = Turret.Location + vect(0, 0, 60); // Same head offset as nameplates

    // Trace from camera to turret, checking world geometry and actors.
    // Zero extent for line trace. Returns None if clear, or the hit actor if blocked.
    HitActor = LocalPC.Trace(HitLoc, HitNorm, TurretLoc, CamLoc, True, vect(0,0,0));

    // If we hit something before the turret, LOS is blocked.
    // If HitActor is the turret itself or its components, LOS is clear.
    return (HitActor == None || HitActor == Turret || HitActor == Turret.TurretBase || HitActor == Turret.TurretSwivel);
}

event PostRender(Canvas C)
{
    local int i;
    local DirectorSentinel T;
    local vector CamLoc, TurretLoc, Screen;
    local Rotator CamRot;
    local float XL, YL, LineH;
    local color TeamColor;
    local string BeaconText;
    local bool bHasTurrets;
    local int CheckIdx;
    local MutTechDirector M;
    local PlayerController LocalPC;
    local Pawn ViewportPawn;
    local Actor ViewportActor;
    local DirectorReplicationInfo DRI;

    Super.PostRender(C);

    // Get PC from canvas viewport actor
    ViewportPawn = None;
    if (C.Viewport != None && C.Viewport.Actor != None)
    {
        ViewportActor = C.Viewport.Actor;
        ViewportPawn = Pawn(ViewportActor);
    }
    if (ViewportPawn == None)
    {
        Log("MutTechDirector: PostRender - no viewport pawn");
        return;
    }

    LocalPC = PlayerController(ViewportPawn.Controller);
    if (LocalPC == None)
    {
        Log("MutTechDirector: PostRender - LocalPC is None, Controller=" $ ViewportPawn.Controller);
        return;
    }
    if (LocalPC.bDeleteMe || LocalPC.Pawn == None)
    {
        Log("MutTechDirector: PostRender - PC invalid: bDeleteMe=" $ LocalPC.bDeleteMe $ ", Pawn=" $ LocalPC.Pawn);
        return;
    }

    // Find mutator on client side (doesn't replicate from server)
    M = MutTechDirector(LocalPC.Level.Game.BaseMutator);
    while (M != None && !M.IsA('MutTechDirector'))
        M = MutTechDirector(M.NextMutator);
    if (M == None)
    {
        Log("MutTechDirector: PostRender - mutator not found on client");
        return;
    }

    // Check if there are any turrets to display
    bHasTurrets = False;
    for (CheckIdx = 0; CheckIdx < 16; CheckIdx++)
    {
        if (M.TeamTurrets[CheckIdx] != None)
        {
            bHasTurrets = True;
            break;
        }
    }
    if (!bHasTurrets)
        return;

    // Don't draw for spectators
    if (LocalPC.PlayerReplicationInfo != None && LocalPC.PlayerReplicationInfo.bOnlySpectator)
    {
        Log("MutTechDirector: PostRender - early return (is spectator)");
        return;
    }

    // Don't draw for the Director (they already see everything via DirectorInteraction)
    // The beacon interaction is only attached to non-Director players, so this check
    // is redundant but kept for safety. Skip the AllActors iteration to avoid
    // compiler issues in Interaction.PostRender context.

    Log("MutTechDirector: PostRender - rendering beacons for " $ LocalPC);

    C.FontScaleX = 1.0;
    C.FontScaleY = 1.0;
    C.StrLen("Mg", XL, YL);
    if (YL < 10.0)
        YL = 12.0;
    LineH = YL + 2.0;

    C.GetCameraLocation(CamLoc, CamRot);

    // Use replicated turret list from mutator (visible to all clients)
    for (i = 0; i < 16; i++)
    {
        T = DirectorSentinel(M.TeamTurrets[i]);
        if (T == None || T.Health <= 0)
            continue;

        TurretLoc = T.Location + vect(0, 0, 60);

        // Skip anything behind the camera
        if ((TurretLoc - CamLoc) Dot vector(CamRot) <= 0.0)
            continue;

        Screen = C.WorldToScreen(TurretLoc);
        if (Screen.X < 0.0 || Screen.X > C.ClipX ||
            Screen.Y < 0.0 || Screen.Y > C.ClipY)
            continue;

        // Line-of-sight check
        if (!HasLineOfSightToTurret(C, T, LocalPC))
            continue;

        // Team colours (same as DirectorInteraction)
        if (T.GetTeamNum() == 0)
        {
            TeamColor.R = 255; TeamColor.G = 0;   TeamColor.B = 0;   TeamColor.A = 255;
        }
        else
        {
            TeamColor.R = 51;  TeamColor.G = 102; TeamColor.B = 255; TeamColor.A = 255;
        }

        // Format: Sentinel(n\)HP [X/X]
        // n = turret index/number (for now just use array index + 1)
        // X/X = current HP / max HP (199 for super health cap)
        BeaconText = "Sentinel(" $ (i + 1) $ "\\)HP [" $ T.Health $ "/" $ 199 $ "]";

        C.StrLen(BeaconText, XL, YL);
        C.DrawColor = TeamColor;
        C.SetPos(Screen.X - XL * 0.5, Screen.Y - LineH);
        C.DrawText(BeaconText);
    }
}

defaultproperties
{
    bVisible=True
    bActive=True
}