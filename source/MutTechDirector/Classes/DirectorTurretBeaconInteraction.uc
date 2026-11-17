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
    Super.PostRender(C);
}

defaultproperties
{
    bVisible=True
    bActive=True
}