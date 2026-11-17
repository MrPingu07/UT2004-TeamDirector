//=============================================================================
// DirectorSentinel
//
// Automated turret deployed by transmat slot 2.
//
// A stock floor sentinel is a hard obstacle: its static base actor carries a
// 96x100 collision cylinder and blocks pawns, which lets the deployment trap a
// player inside (or telefrag them if they are standing on the spot).  The
// deployed turret is therefore always walk-through: all three actors involved
// (the turret, its base and its swivel) keep bCollideActors so hitscan and
// projectiles still register, but drop bBlockActors so players pass through.
//
// Collision is reapplied whenever the actors are (re)created, because the base
// and swivel are spawned by ASTurret.PostNetBeginPlay and the base's own
// PostBeginPlay forces bBlockActors back on.
//=============================================================================
class DirectorSentinel extends ASVehicle_Sentinel_Floor;

simulated event PostBeginPlay()
{
    Super.PostBeginPlay();
    MakeWalkThrough();

    // Clear the vehicle name string so the stock HUD has nothing to draw
    // above the sentinel.
    VehicleNameString = "";
    Log("MutTechDirector: [SENTINEL-PB] PostBeginPlay VehicleNameString=" $ VehicleNameString $ " Level.Game=" $ Level.Game);

    // Remove from Level.Game.VehicleList (linked list) so the stock HUD's
    // DrawVehicleName does not iterate this sentinel and draw its native name
    // above it.
    RemoveFromVehicleList();
}

simulated event PostNetBeginPlay()
{
    // ASTurret.PostNetBeginPlay spawns TurretBase / TurretSwivel, so apply
    // walk-through collision only after Super has created them.
    Super.PostNetBeginPlay();
    MakeWalkThrough();

    // Also purge after base/swivel creation in case the list was repopulated.
    Log("MutTechDirector: [SENTINEL-PNB] PostNetBeginPlay Level.Game=" $ Level.Game);
    RemoveFromVehicleList();
}

simulated function RemoveFromVehicleList()
{
    local Vehicle Prev, V;

    if (Level.Game == None)
    {
        Log("MutTechDirector: [SENTINEL-RVL] Level.Game is None");
        return;
    }

    Log("MutTechDirector: [SENTINEL-RVL] VehicleList head=" $ Level.Game.VehicleList);

    if (Level.Game.VehicleList == Self)
    {
        Log("MutTechDirector: [SENTINEL-RVL] Self is head of list");
        Level.Game.VehicleList = NextVehicle;
    }
    else
    {
        Prev = Level.Game.VehicleList;
        V = Level.Game.VehicleList.NextVehicle;
        while (V != None)
        {
            if (V == Self)
            {
                Log("MutTechDirector: [SENTINEL-RVL] Found Self in list, removing");
                Prev.NextVehicle = NextVehicle;
                break;
            }
            Prev = V;
            V = V.NextVehicle;
        }
    }

    // Detach from the list to avoid dangling references.
    NextVehicle = None;
    Log("MutTechDirector: [SENTINEL-RVL] Removed Self from VehicleList");
}

simulated function MakeWalkThrough()
{
    // Collide (shootable) but never block (passable).
    SetCollision(True, False);
    bProjTarget = True;

    if (TurretBase != None)
    {
        TurretBase.SetCollision(True, False);
        TurretBase.bProjTarget = True;
    }

    if (TurretSwivel != None)
    {
        TurretSwivel.SetCollision(True, False);
        TurretSwivel.bProjTarget = True;
    }
}

/**
 * Suppress stock engine native name/beacon drawing above sentinels.
 * The custom sentinel beacon (Sentinel(n) / HP [X/X]) is drawn by
 * DirectorInteraction.PostRender (Director) and
 * DirectorTurretBeaconInteraction.PostRender (combatants).
 */
simulated event PostRender(Canvas C)
{
    // Do not call Super.PostRender(): stock Vehicle/ASTurret.PostRender draws
    // the actor name above the sentinel, which overlaps our custom beacon.
    // Mesh rendering happens separately and is unaffected.
    Log("MutTechDirector: [SENTINEL-POSTRENDER] suppressing stock name drawing for " $ Self);
}

defaultproperties
{
    VehicleNameString=""
}
