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
    local Mutator Mut;
    local PlayerController LocalPC;
    local Pawn ViewportPawn;
    local Actor ViewportActor;

    Super.PostRender(C);

    Log("MutTechDirector: [BEACON-RENDER] PostRender entered C=" $ C);

    // Get PC from canvas viewport actor
    ViewportPawn = None;
    if (C.Viewport != None && C.Viewport.Actor != None)
    {
        ViewportActor = C.Viewport.Actor;
        ViewportPawn = Pawn(ViewportActor);
    }
    // Fall back to the interaction's PC pawn when the viewport actor isn't a
    // pawn (e.g. during booth exit / respawn transitions).
    if (ViewportPawn == None && PC != None && PC.Pawn != None)
    {
        ViewportPawn = PC.Pawn;
        Log("MutTechDirector: [BEACON-RENDER] using PC.Pawn fallback for ViewportPawn");
    }
    if (ViewportPawn == None)
    {
        Log("MutTechDirector: [BEACON-RENDER] early return - no viewport pawn");
        return;
    }

    LocalPC = PlayerController(ViewportPawn.Controller);
    if (LocalPC == None)
    {
        Log("MutTechDirector: [BEACON-RENDER] early return - LocalPC is None, Controller=" $ ViewportPawn.Controller);
        return;
    }
    if (LocalPC.bDeleteMe || LocalPC.Pawn == None)
    {
        Log("MutTechDirector: [BEACON-RENDER] early return - PC invalid: bDeleteMe=" $ LocalPC.bDeleteMe $ ", Pawn=" $ LocalPC.Pawn);
        return;
    }

    Log("MutTechDirector: [BEACON-RENDER] LocalPC=" $ LocalPC $ " Pawn=" $ LocalPC.Pawn);

    // Find mutator on client side by walking the full mutator chain:
    // MutTechDirector may not be BaseMutator when other mutators load first.
    M = None;
    if (LocalPC.Level != None && LocalPC.Level.Game != None)
    {
        Mut = LocalPC.Level.Game.BaseMutator;
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
        Log("MutTechDirector: [BEACON-RENDER] early return - mutator not found on client");
        return;
    }

    // Check if there are any turrets to display
    bHasTurrets = False;
    for (CheckIdx = 0; CheckIdx < 16; CheckIdx++)
    {
        if (M.TeamTurrets[CheckIdx] != None)
        {
            bHasTurrets = True;
            Log("MutTechDirector: [BEACON-RENDER] TeamTurrets[" $ CheckIdx $ "] = " $ M.TeamTurrets[CheckIdx]);
            break;
        }
    }
    if (!bHasTurrets)
    {
        Log("MutTechDirector: [BEACON-RENDER] early return - no turrets in replicated array");
        return;
    }

    // Don't draw for spectators
    if (LocalPC.PlayerReplicationInfo != None && LocalPC.PlayerReplicationInfo.bOnlySpectator)
    {
        Log("MutTechDirector: [BEACON-RENDER] early return - is spectator");
        return;
    }

    // Don't draw while the viewer is in Director booth mode (Spectating state).
    if (LocalPC.IsInState('Spectating'))
    {
        Log("MutTechDirector: [BEACON-RENDER] early return - in Director booth (Spectating state)");
        return;
    }

    Log("MutTechDirector: [BEACON-RENDER] rendering beacons for " $ LocalPC);

    C.FontScaleX = 1.0;
    C.FontScaleY = 1.0;
    if (C.SmallFont != None)
        C.Font = C.SmallFont;
    C.StrLen("Mg", XL, YL);
    if (YL < 10.0)
        YL = 12.0;
    LineH = YL + 2.0;

    C.GetCameraLocation(CamLoc, CamRot);

    // Use replicated turret list from mutator (visible to all clients)
    for (i = 0; i < 16; i++)
    {
        T = DirectorSentinel(M.TeamTurrets[i]);
        if (T == None || T.bDeleteMe || T.Health <= 0)
        {
            Log("MutTechDirector: [BEACON-RENDER] slot[" $ i $ "] skip - T=None/bDeleteMe/dead T=" $ T);
            continue;
        }

        TurretLoc = T.Location + vect(0, 0, 60);

        // Skip anything behind the camera
        if ((TurretLoc - CamLoc) Dot vector(CamRot) <= 0.0)
        {
            Log("MutTechDirector: [BEACON-RENDER] slot[" $ i $ "] T=" $ T $ " behind camera, skipping");
            continue;
        }

        Screen = C.WorldToScreen(TurretLoc);
        if (Screen.X < 0.0 || Screen.X > C.ClipX ||
            Screen.Y < 0.0 || Screen.Y > C.ClipY)
        {
            Log("MutTechDirector: [BEACON-RENDER] slot[" $ i $ "] T=" $ T $ " off-canvas Screen=" $ Screen);
            continue;
        }

        // Line-of-sight check (combatants require LOS)
        if (!HasLineOfSightToTurret(C, T, LocalPC))
        {
            Log("MutTechDirector: [BEACON-RENDER] slot[" $ i $ "] T=" $ T $ " LOS blocked, skipping");
            continue;
        }

        Log("MutTechDirector: [BEACON-RENDER] slot[" $ i $ "] T=" $ T $ " DRAWING beacon Screen=" $ Screen);

        // Team colours (same as player nameplates)
        if (T.GetTeamNum() == 0)
        {
            TeamColor.R = 255; TeamColor.G = 0;   TeamColor.B = 0;   TeamColor.A = 255;
        }
        else
        {
            TeamColor.R = 51;  TeamColor.G = 102; TeamColor.B = 255; TeamColor.A = 255;
        }

        // Format: two centred lines
        //   Sentinel(n)
        //   HP [X/X]
        // No shield line: sentinels are walk-through turrets, not fighters.
        BeaconText = "Sentinel(" $ (i + 1) $ ")";
        C.StrLen(BeaconText, XL, YL);
        C.DrawColor = TeamColor;
        C.SetPos(Screen.X - XL * 0.5, Screen.Y - 2.0 * LineH);
        C.DrawText(BeaconText);

        BeaconText = "HP [" $ T.Health $ "/" $ int(T.HealthMax) $ "]";
        C.StrLen(BeaconText, XL, YL);
        C.SetPos(Screen.X - XL * 0.5, Screen.Y - LineH);
        C.DrawText(BeaconText);
    }
}

defaultproperties
{
    bVisible=True
    bActive=True
}