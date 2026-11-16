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
}

simulated event PostNetBeginPlay()
{
    // ASTurret.PostNetBeginPlay spawns TurretBase / TurretSwivel, so apply
    // walk-through collision only after Super has created them.
    Super.PostNetBeginPlay();
    MakeWalkThrough();
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

defaultproperties
{
}
