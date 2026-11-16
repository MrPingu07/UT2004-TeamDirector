//=============================================================================
// MutTechDirector
//
// Universal team-gametype mutator that turns a player into the team's
// Tournament Technical Director: a remote broadcast operator who never sets
// foot on the arena floor, but can authorize transmat logistics for the
// fighters currently on the feed.
//
// Design rules enforced here:
//
//   * TeamGame stays in charge of teams and roster counts.  We never call
//     BecomeSpectator() and never remove the player from TeamInfo.
//   * The director's physical Pawn is destroyed.  The player still owns the
//     PlayerController and PRI, so the gametype still counts them.
//   * Entering the booth resets every transmat cooldown to its maximum.
//     Cooldowns are advanced only by DirectorReplicationInfo.Tick while the
//     booth is online, so leaving pauses (and therefore loses) progress.
//   * The server is the only authority for targets, cooldowns, drops and
//     recalls.  Client input is a request, never a decision.
//   * Exit returns the player through Level.Game.RestartPlayer(), i.e. the
//     same spawn path as a normal respawn.
//
// The mutator is intentionally self-contained.  It relies only on stock
// UT2004 classes (XGame, XEffects, UT2k4Assault, Onslaught, OnslaughtBP) and
// uses DynamicLoadObject for optional bonus-pack vehicles so a server without
// the bonus pack still compiles and runs.
//=============================================================================
class MutTechDirector extends Mutator config (User);

// ---------------------------------------------------------------------------
// Configuration (edited by MutTechDirectorConfig through the mutator list's
// Configure button; class defaults are saved into the user ini).
// ---------------------------------------------------------------------------

/** Cooldown ceiling, in seconds, for each transmat slot. */
var() config float Cooldown1;
var() config float Cooldown2;
var() config float Cooldown3;
var() config float Cooldown4;
var() config float Cooldown5;
var() config float Cooldown6;
var() config float Cooldown7;
var() config float Cooldown8;
var() config float Cooldown9;

// ---------------------------------------------------------------------------
// Bookkeeping
// ---------------------------------------------------------------------------

/** Live booth records.  Entries are removed on exit/logout. */
var array<DirectorReplicationInfo> Directors;

/** Mandatory delay before the booth can open.  Exiting is instant. */
const TD_ENTRY_DELAY = 5.0;

// Cooldown values live in DirectorReplicationInfo.GetMaxCooldown(), which is
// the single source of truth for the HUD, the cooldown tick and StartCooldown.

const TD_PI = 3.1415926535897932;

// ---------------------------------------------------------------------------
// Mutator lifecycle
// ---------------------------------------------------------------------------

function PostBeginPlay()
{
    local DirectorRules R;

    Super.PostBeginPlay();

    // DirectorRules is deliberately small: it provides a robust team-start
    // fallback when the stock start search cannot find a navigation point.
    // Keeping it in a GameRules chain means we do not have to subclass or
    // replace any gametype.
    if (Level.Game != None)
    {
        R = Spawn(class'DirectorRules');
        if (R != None)
            Level.Game.AddGameModifier(R);
    }

    // Enable vehicles on all team maps so ONSVehicle subclasses can instantiate
    // and initialize Karma physics on CTF, TDM, AS, BR, DOM maps.
    if (Level.Game != None)
        Level.Game.bAllowVehicles = True;
}

function Mutate(string MutateString, PlayerController Sender)
{
    if (MutateString ~= "director" || MutateString ~= "techdirector" ||
        MutateString ~= "mutdirector")
    {
        ToggleDirector(Sender);
        return;
    }

    if (NextMutator != None)
        NextMutator.Mutate(MutateString, Sender);
}

/**
 * Called on the server for every pawn spawn.  Piggyback the invisible
 * DirectorBindKeyMessage so the owning client runs its ClientReceive and
 * binds K -> "mutate director".  Repeating it per spawn is cheap and makes a
 * missed/overwritten bind self-heal.  LocalMessage.ClientReceive runs on the
 * client, so this needs no custom PlayerController class; other mutators that
 * own the controller (e.g. GTAThirdPerson) stay untouched.
 */
function ModifyPlayer(Pawn Other)
{
    local PlayerController PC;

    if (Other != None)
        PC = PlayerController(Other.Controller);

    if (PC != None && (PC.PlayerReplicationInfo == None ||
        !PC.PlayerReplicationInfo.bOnlySpectator))
    {
        PC.ReceiveLocalizedMessage(class'DirectorBindKeyMessage', 0);
    }

    Super.ModifyPlayer(Other);
}

function NotifyLogout(Controller Exiting)
{
    local DirectorReplicationInfo RI;
    local PlayerController PC;

    PC = PlayerController(Exiting);
    if (PC != None)
    {
        RI = FindDirectorRI(PC);
        if (RI != None)
        {
            if (!RI.bBoothPending)
                RI.ClientCloseBooth();
            RI.bDirectorActive = False;
            RI.bBoothPending = False;
            RI.ClearBerserk();
            RI.Destroy();
            RemoveDirectorRI(RI);
        }
    }

    Super.NotifyLogout(Exiting);
}

// ---------------------------------------------------------------------------
// Enter / leave
// ---------------------------------------------------------------------------

function ToggleDirector(PlayerController PC)
{
    local DirectorReplicationInfo RI;

    if (PC == None || PC.PlayerReplicationInfo == None)
        return;

    if (Level.Game == None || !Level.Game.bTeamGame ||
        PC.PlayerReplicationInfo.Team == None)
    {
        PC.ClientMessage("Technical Director Mode requires a team gametype.");
        return;
    }

    if (PC.bDeleteMe || PC.PlayerReplicationInfo.bOnlySpectator)
    {
        PC.ClientMessage("Only an active team fighter can occupy the Director booth.");
        return;
    }

    RI = FindDirectorRI(PC);
    if (RI != None && !RI.bDeleteMe)
    {
        if (RI.bDirectorActive)
        {
            // Leaving is immediate: no delay, no penalty.
            ExitDirectorMode(RI);
            return;
        }

        if (RI.bBoothPending)
        {
            // Toggling again during the entry delay cancels it.
            RI.ClientNotify("Technical Director entry cancelled.");
            RI.AbortPendingEntry();
            return;
        }
    }

    StartEntryDelay(PC);
}

function DirectorReplicationInfo FindDirectorRI(PlayerController PC)
{
    local int i;

    if (PC == None)
        return None;

    for (i = 0; i < Directors.Length; i++)
    {
        if (Directors[i] != None && Directors[i].DirectorPC == PC)
            return Directors[i];
    }

    return None;
}

function RemoveDirectorRI(DirectorReplicationInfo RI)
{
    local int i;

    for (i = 0; i < Directors.Length; i++)
    {
        if (Directors[i] == RI)
        {
            Directors.Remove(i, 1);
            return;
        }
    }

}
/**
 * Open the mandatory entry delay.  The booth object exists immediately so the
 * client can receive the countdown popups, but DirectorPC keeps playing
 * normally until the timer expires and CompleteEntry() runs.
 */
function StartEntryDelay(PlayerController PC)
{
    local DirectorReplicationInfo RI;

    if (FindDirectorRI(PC) != None)
        return;

    // Owner-only actor: the client receives its own countdown/cooldown record,
    // nobody else's.  bOnlyRelevantToOwner is set in the RI defaults.
    RI = Spawn(class'DirectorReplicationInfo', PC);
    if (RI == None)
    {
        PC.ClientMessage("Technical Director booth could not be opened.");
        return;
    }

    RI.BeginEntryCountdown(Self, PC, PC.PlayerReplicationInfo.Team.TeamIndex,
        TD_ENTRY_DELAY);
    Directors[Directors.Length] = RI;
}

/** The entry delay expired: take the player off the field and open the booth. */
function CompleteEntry(DirectorReplicationInfo RI)
{
    local PlayerController PC;
    local Pawn OldPawn;
    local Pawn Initial;

    if (RI == None || RI.bDeleteMe)
        return;

    PC = RI.DirectorPC;
    if (PC == None || PC.bDeleteMe)
    {
        RI.AbortPendingEntry();
        return;
    }

    OldPawn = PC.Pawn;

    // If the player enters from a vehicle, leave the vehicle first so that
    // Destroy() removes only the director's on-foot body.  Passengers stay in
    // their seats and the vehicle is not damaged.
    if (Vehicle(OldPawn) != None)
    {
        Vehicle(OldPawn).KDriverLeave(True);
        OldPawn = PC.Pawn;
    }

    RI.ActivateBooth();

    // Keep the player on the team.  While in the booth we must keep
    // bOutOfLives = True so external respawn systems (vanilla bForceRespawn,
    // ut2k4rd/RespawnDelay, etc.) treat the Director as "already out of lives"
    // and skip them.  The flag is cleared in ExitDirectorMode() just before
    // calling RestartPlayer().
    PC.PlayerReplicationInfo.bOutOfLives = True;
    PC.PlayerReplicationInfo.bIsSpectator = False;

    // Suppress the physical pawn.  UnPossess() runs the stock Spectating
    // state transition; Destroy() removes the body from the world so it
    // cannot be damaged, score a death, or block a spawn.
    if (OldPawn != None)
    {
        PC.UnPossess();
        // A failed vehicle exit leaves the vehicle itself as the old pawn;
        // never destroy a vehicle that may still have passengers.
        if (OldPawn != None && !OldPawn.bDeleteMe && Vehicle(OldPawn) == None)
            OldPawn.Destroy();
    }

    PC.GotoState('Spectating');
    PC.bBehindView = True;
    PC.CameraDist = PC.Default.CameraDist;
    PC.ClientSetBehindView(True);

    Initial = FindTeammate(PC, None, 1);
    RI.SetTarget(Initial);

    if (Initial == None)
        Notify(RI, "Technical Director online. No living teammates on the feed.");
    else
        Notify(RI, "Technical Director online. Broadcast feed locked to " $ Initial.PlayerReplicationInfo.PlayerName $ ".");
}

function ExitDirectorMode(DirectorReplicationInfo RI)
{
    local PlayerController PC;

    if (RI == None)
        return;

    PC = RI.DirectorPC;

    RI.bDirectorActive = False;
    RI.bHealing = False;
    RI.ClearBerserk();

    // Reliable client teardown: the HUD/key hook must die with the booth even
    // if the client misses the actor-destruction event.  The final message goes
    // out through the same reliable RPC so remote clients see it too.
    RI.ClientCloseBooth("Technical Director offline. Returning to the arena.");

    if (PC != None)
    {
        PC.bBehindView = False;
        PC.ClientSetBehindView(False);
        PC.CameraDist = PC.Default.CameraDist;
        PC.SetViewTarget(PC);
        PC.ClientSetViewTarget(PC);
    }

    RI.Destroy();
    RemoveDirectorRI(RI);

    if (PC != None && Level.Game != None)
    {
        // This is the exact standard respawn path.  It respects the
        // gametype's player-start selection, spawn protection and PawnClass.
        if (PC.PlayerReplicationInfo != None)
            PC.PlayerReplicationInfo.bOutOfLives = False;

        Level.Game.RestartPlayer(PC);

        if (PC.Pawn == None)
            PC.ClientMessage("No spawn point was available; press Fire to respawn.");
    }

}
// ---------------------------------------------------------------------------
// Fighter feed
// ---------------------------------------------------------------------------

/** Return the next living teammate on PC's team, wrapping in Dir order. */
function Pawn FindTeammate(PlayerController PC, Pawn Current, int Dir)
{
    local Controller C;
    local array<Pawn> List;
    local int i;
    local int Idx;

    if (PC == None || PC.PlayerReplicationInfo == None ||
        PC.PlayerReplicationInfo.Team == None)
        return None;

    foreach AllControllers(class'Controller', C)
    {
        if (C == None || C == PC || C.Pawn == None)
            continue;
        if (C.Pawn.Health <= 0)
            continue;
        if (C.PlayerReplicationInfo == None ||
            C.PlayerReplicationInfo.Team != PC.PlayerReplicationInfo.Team)
            continue;

        List[List.Length] = C.Pawn;
    }

    if (List.Length == 0)
        return None;

    if (Current == None)
    {
        if (Dir < 0)
            return List[List.Length - 1];
        return List[0];
    }

    Idx = -1;
    for (i = 0; i < List.Length; i++)
    {
        if (List[i] == Current)
        {
            Idx = i;
            break;
        }
    }

    if (Idx < 0)
    {
        if (Dir < 0)
            return List[List.Length - 1];
        return List[0];
    }

    Idx = (Idx + Dir + List.Length) % List.Length;
    return List[Idx];
}

// ---------------------------------------------------------------------------
// Ability dispatch
// ---------------------------------------------------------------------------

function UseAbility(DirectorReplicationInfo RI, int Slot)
{
    local Pawn T;
    local byte Team;

    if (RI == None || RI.bDeleteMe || !RI.bDirectorActive ||
        RI.DirectorPC == None || RI.DirectorPC.bDeleteMe)
        return;

    if (Slot < 1 || Slot > 9)
        return;

    Team = RI.DirectorTeam;

    // Slots 1-8 target the current feed.  Slot 9 is a team-wide recall and
    // therefore does not require a living target.
    if (Slot != 9)
    {
        T = RI.CurrentTarget;
        if (T == None || T.bDeleteMe || T.Health <= 0)
        {
            Notify(RI, "No living fighter on the feed.");
            return;
        }
    }

    if (!CheckCooldown(RI, Slot))
        return;

    switch (Slot)
    {
        case 1:
            if (!GrantAmmo(T))
            {
                Notify(RI, "That fighter has no weapons to resupply.");
                return;
            }
            DeployFX(T.Location, Team, 0);
            StartCooldown(RI, Slot);
            Notify(RI, "Ammunition requisition authorized.");
            break;

        case 2:
            if (!DeploySentinel(T, Team, RI))
            {
                Notify(RI, "Not enough space.");
                return;
            }
            StartCooldown(RI, Slot);
            Notify(RI, "Perimeter sentinel deployed.");
            break;

        case 3:
            T.Health = Max(T.Health, 300);
            DeployFX(T.Location, Team, 0);
            StartCooldown(RI, Slot);
            Notify(RI, "Painkiller nanites administered. Health set to 300.");
            break;

        case 4:
            if (!T.AddShieldStrength(100))
            {
                Notify(RI, "Blindage already at maximum.");
                return;
            }
            DeployFX(T.Location, Team, 0);
            StartCooldown(RI, Slot);
            Notify(RI, "Blindage authorized: +100 shield.");
            break;

        case 5:
            if (xPawn(T) == None)
            {
                Notify(RI, "Stimuli Dose can only be applied to a fighter.");
                return;
            }
            RI.ApplyBerserk(T);
            Spawn(class'XEffects.ComboActivation', T,, T.Location, T.Rotation);
            if (RI.DirectorPC != None)
                RI.DirectorPC.ClientPlaySound(
                    Sound'GameSounds.Combo.ComboActivated', true, 1.0, SLOT_None);
            StartCooldown(RI, Slot);
            Notify(RI, "Stimuli Dose active: fighter is berserk for 30 seconds.");
            break;

        case 6:
            if (!DropVehicle(T, Team, "OnslaughtBP.ONSArtillery", "", 6, RI))
            {
                Notify(RI, "Not enough space.");
                return;
            }
            StartCooldown(RI, Slot);
            Notify(RI, "SPMA transmat complete.");
            break;

        case 7:
            if (!DropVehicle(T, Team, "OnslaughtBP.ONSDualAttackCraft", "Onslaught.ONSAttackCraft", 7, RI))
            {
                Notify(RI, "Not enough space.");
                return;
            }
            StartCooldown(RI, Slot);
            Notify(RI, "Light vehicle transmat complete.");
            break;

        case 8:
            if (!DropVehicle(T, Team, "Onslaught.ONSHoverTank", "", 8, RI))
            {
                Notify(RI, "Not enough space.");
                return;
            }
            StartCooldown(RI, Slot);
            Notify(RI, "Heavy asset drop complete.");
            break;

        case 9:
            if (!RecallTeam(RI))
            {
                Notify(RI, "Emergency recall failed: no safe team destination.");
                return;
            }
            StartCooldown(RI, Slot);
            Notify(RI, "Emergency recall executed.");
            break;
    }

}
function bool CheckCooldown(DirectorReplicationInfo RI, int Slot)
{
    local float Left;

    Left = RI.GetCooldown(Slot);
    if (Left > 0.01)
    {
        Notify(RI, "Transmat slot " $ Slot $ " recharging ("
            $ int(Left + 0.999) $ "s).");
        return False;
    }

    return True;
}

function StartCooldown(DirectorReplicationInfo RI, int Slot)
{
    RI.SetCooldown(Slot, RI.GetMaxCooldown(Slot));
}

function Notify(DirectorReplicationInfo RI, string S)
{
    if (RI != None && !RI.bDeleteMe)
        RI.ClientNotify(S);
}

// ---------------------------------------------------------------------------
// Slot 1: Ammunition Requisition
// ---------------------------------------------------------------------------

/**
 * Add one standard ammo pack for every ammo class used by each weapon the
 * fighter is carrying.  Weapon.AddAmmo() works both with UT2004's default
 * bNoAmmoInstances mode and with modded weapons that still create Ammunition
 * actors, so no parallel ammo actors are spawned here.
 */
function bool GrantAmmo(Pawn P)
{
    local Inventory Inv;
    local Weapon W;
    local class<Ammunition> AmmoClass;
    local class<Ammunition> PrimaryAmmo;
    local int Mode;
    local int Amount;
    local bool bGave;

    if (P == None)
        return False;

    for (Inv = P.Inventory; Inv != None; Inv = Inv.Inventory)
    {
        W = Weapon(Inv);
        if (W == None)
            continue;

        // Resupply each carried weapon.  bNoAmmoInstances weapons keep their
        // own AmmoCharge, so a shared ammo class still has to be topped up on
        // every weapon that uses it.  Within one weapon, a shared primary /
        // alternate ammo class is only filled once.
        PrimaryAmmo = W.GetAmmoClass(0);
        for (Mode = 0; Mode < 2; Mode++)
        {
            AmmoClass = W.GetAmmoClass(Mode);
            if (AmmoClass == None)
                continue;
            if (Mode == 1 && AmmoClass == PrimaryAmmo)
                continue;

            Amount = AmmoClass.Default.AmmoAmount;
            if (Amount <= 0)
                Amount = Max(1, AmmoClass.Default.InitialAmount);

            if (W.AddAmmo(Amount, Mode))
                bGave = True;
        }
    }

    return bGave;
}

// ---------------------------------------------------------------------------
// Slot 2: Perimeter Defense
// ---------------------------------------------------------------------------

function bool DeploySentinel(Pawn P, byte Team, optional DirectorReplicationInfo RI)
{
    local vector Spot;
    local ASVehicle_Sentinel T;
    local class<ASVehicle_Sentinel> SClass;
    local float BaseHalfHeight;

    if (P == None)
        return False;

    // The Floor Sentinel's mesh pivot is at the top of its static base: the
    // turret gun is drawn above the origin and the base body hangs below it.
    // ASVehicle_Sentinel_Floor_Base carries CollisionHeight=100 (a half-extent),
    // but the drawn base bottom sits a little above the collision cylinder's
    // bottom, so 70 puts the visible base on the deck without burying it.
    BaseHalfHeight = 70.0;

    SClass = class'DirectorSentinel';
    if (!FindVehicleSpot(P, 90.0, BaseHalfHeight, Spot, 2.0))
    {
        // Feet fallback: P.Location is the pawn's centre, so subtract its
        // collision height to reach the deck.  Sentinels have no gravity, so
        // an incorrect Z never corrects itself.
        Spot = P.Location;
        Spot.Z = P.Location.Z - P.CollisionHeight + BaseHalfHeight + 2.0;
    }

    T = Spawn(SClass,,, Spot, P.Rotation);
    if (T == None)
        return False;

    T.SetTeamNum(Team);
    T.bTeamLocked = True;

    // DirectorSentinel enforces walk-through collision (turret, base and
    // swivel) while keeping bCollideActors for hitscan/projectile hits.
    log("MutTechDirector: DeploySentinel deployed walk-through turret Spot=" $ Spot);

    DeployFX(Spot, Team, 1);
    return True;
}

// ---------------------------------------------------------------------------
// Slots 6, 7 & 8: vehicle transmats
// ---------------------------------------------------------------------------

function bool DropVehicle(Pawn P, byte Team, string VClassName, string VClassFallback, int Slot, optional DirectorReplicationInfo RI)
{
    local class<Vehicle> VClass;
    local Vehicle V;
    local vector Spot;
    local float Radius;
    local float Height;

    log("MutTechDirector: DropVehicle START P=" $ P $ " VClassName=" $ VClassName $ " Fallback=" $ VClassFallback);

    VClass = class<Vehicle>(DynamicLoadObject(VClassName, class'Class'));
    log("MutTechDirector: DropVehicle Requested=" $ VClassName $ " VClass=" $ VClass);
    if (VClass == None && VClassFallback != "")
    {
        VClass = class<Vehicle>(DynamicLoadObject(VClassFallback, class'Class'));
        log("MutTechDirector: DropVehicle Fallback=" $ VClassFallback $ " VClass=" $ VClass);
    }

    if (VClass == None)
    {
        log("MutTechDirector: DropVehicle FAIL class not found");
        if (RI != None)
            Notify(RI, "Vehicle class not found!");
        return False;
    }
    log("MutTechDirector: DropVehicle PASS class VClass=" $ VClass);

    Radius = FMax(60.0, VClass.Default.CollisionRadius);
    Height = FMax(60.0, VClass.Default.CollisionHeight);
    log("MutTechDirector: DropVehicle Radius=" $ Radius $ " Height=" $ Height);

    // Engine-safe: vehicles are allowed on this map before we spawn one.
    if (Level.Game != None)
        Level.Game.bAllowVehicles = True;
    log("MutTechDirector: DropVehicle bAllowVehicles=" $ Level.Game.bAllowVehicles);

    // Try a ground trace under the pawn; if that fails fall back to the pawn's feet.
    if (!FindVehicleSpot(P, Radius, Height, Spot, 25.0))
    {
        log("MutTechDirector: DropVehicle FindVehicleSpot FAIL falling back to feet");
        Spot = P.Location + vect(0,0,40.0);
    }
    else
    {
        log("MutTechDirector: DropVehicle FindVehicleSpot PASS Spot=" $ Spot);
    }
    log("MutTechDirector: DropVehicle final Spot=" $ Spot);

    V = Spawn(VClass,,, Spot, P.Rotation);
    log("MutTechDirector: DropVehicle Spawn result V=" $ V);
    if (V == None)
    {
        log("MutTechDirector: DropVehicle FAIL spawn returned None");
        if (RI != None)
        {
            RI.SetCooldown(Slot, 0.0);
            Notify(RI, "Spawn failed; cooldown refunded.");
        }
        return False;
    }
    log("MutTechDirector: DropVehicle PASS spawn V=" $ V);

    V.SetTeamNum(Team);
    V.bTeamLocked = True;
    log("MutTechDirector: DropVehicle team set Team=" $ Team);

    // Force the spectated teammate into the driver seat instantly, so they
    // cannot be telefragged by their own spawn.
    if (P != None && P.Controller != None && Vehicle(P) == None && V.Driver == None)
    {
        V.KDriverEnter(P);
        log("MutTechDirector: DropVehicle forced driver P=" $ P);
    }

    // Spawned vehicles are fully solid: no ghost/passthrough state.  Only the
    // automated sentinel turret is made walk-through (see DeploySentinel).
    DeployFX(Spot, Team, 2);
    log("MutTechDirector: DropVehicle SUCCESS vehicle spawned");
    return True;
}

/**
 * Simple spawn spot: drop a trace down from above the pawn to find ground,
 * then place the actor origin at FloorLoc + Height + GroundClearance.
 *
 * Height is the actor's centre-to-bottom distance (collision height for
 * centre-origin vehicles, 0 for floor-origin turrets).  GroundClearance is the
 * gap left between the bottom of the actor and the floor.
 */
function bool FindVehicleSpot(Pawn P, float Radius, float Height, out vector Spot, float GroundClearance)
{
    local vector HitLoc, HitNormal;
    local Actor Hit;
    local vector FloorLoc;
    local vector TraceStart;
    local vector TraceEnd;
    local vector GroundExtent;

    if (P == None)
    {
        log("MutTechDirector: FindVehicleSpot FAIL P=None");
        return False;
    }

    log("MutTechDirector: FindVehicleSpot P=" $ P $ " P.Loc=" $ P.Location $ " Radius=" $ Radius $ " Height=" $ Height);

    // Trace from just above the pawn down to below them at the pawn's XY.
    GroundExtent.X = Radius * 1.05;
    GroundExtent.Y = Radius * 1.05;
    GroundExtent.Z = 200.0;
    TraceStart = P.Location + vect(0,0,200.0);
    TraceEnd = P.Location;
    TraceEnd.Z = P.Location.Z - 1000.0;
    Hit = Trace(HitLoc, HitNormal, TraceStart, TraceEnd, false, GroundExtent);

    log("MutTechDirector: FindVehicleSpot trace Hit=" $ Hit $ " HitLoc=" $ HitLoc $ " HitNormal.Z=" $ HitNormal.Z);

    if (Hit == None)
    {
        log("MutTechDirector: FindVehicleSpot FAIL Hit=None");
        return False;
    }
    if (HitNormal.Z < 0.7)
    {
        log("MutTechDirector: FindVehicleSpot FAIL HitNormal.Z=" $ HitNormal.Z);
        return False;
    }

    FloorLoc = HitLoc;

    // Place the actor bottom at floor + clearance.
    Spot = FloorLoc;
    Spot.Z = Spot.Z + Height + GroundClearance;
    log("MutTechDirector: FindVehicleSpot PASS Spot=" $ Spot);
    return True;
}

// ---------------------------------------------------------------------------
// Slot 8: Emergency Recall
// ---------------------------------------------------------------------------

function bool RecallTeam(DirectorReplicationInfo RI)
{
    local Controller C;
    local Pawn P;
    local array<Pawn> TeamPawns;
    local vector BaseLoc;
    local string HomeName;
    local vector Dest;
    local int i;
    local bool bAny;

    if (RI == None || RI.DirectorPC == None ||
        RI.DirectorPC.PlayerReplicationInfo == None)
        return False;

    log("MutTechDirector: RecallTeam START Team=" $ RI.DirectorTeam);

    foreach AllControllers(class'Controller', C)
    {
        if (C == RI.DirectorPC || C.Pawn == None || C.Pawn.Health <= 0)
            continue;
        if (C.PlayerReplicationInfo == None ||
            C.PlayerReplicationInfo.Team != RI.DirectorPC.PlayerReplicationInfo.Team)
            continue;

        TeamPawns[TeamPawns.Length] = C.Pawn;
    }

    log("MutTechDirector: RecallTeam teammates found=" $ TeamPawns.Length);

    if (TeamPawns.Length == 0)
        return False;

    if (!FindHomeLocation(RI.DirectorTeam, BaseLoc, HomeName))
    {
        log("MutTechDirector: RecallTeam FAIL no home location for team " $ RI.DirectorTeam);
        return False;
    }

    log("MutTechDirector: RecallTeam home=" $ HomeName $ " BaseLoc=" $ BaseLoc);

    for (i = 0; i < TeamPawns.Length; i++)
    {
        P = TeamPawns[i];
        if (P == None || P.Health <= 0)
            continue;

        if (!FindRecallSpot(BaseLoc, P, i, TeamPawns.Length, Dest))
        {
            log("MutTechDirector: RecallTeam no recall spot for pawn " $ P);
            continue;
        }

        P.SetLocation(Dest);
        P.Velocity = vect(0,0,0);
        if (Vehicle(P) == None)
            P.SetPhysics(PHYS_Falling);
        P.PlayTeleportEffect(False, True);
        log("MutTechDirector: RecallTeam moved pawn " $ P $ " to " $ Dest);
        bAny = True;
    }

    log("MutTechDirector: RecallTeam finished bAny=" $ bAny);

    if (bAny && RI.DirectorPC != None)
        RI.DirectorPC.ClientPlaySound(
            Sound'WeaponSounds.LinkGun.BLinkGunBeam1', true, 1.0, SLOT_None);

    return bAny;
}

/**
 * Find the team's home anchor.  CTF bases are preferred, then the main
 * Onslaught power core (final core first), then a team-tagged PlayerStart.
 *
 * UT2004's stock class is PlayerStart.TeamNumber; the "TeamPlayerStart" name
 * in the design brief maps to that field rather than a separate class.
 */
function bool FindHomeLocation(byte Team, out vector BaseLoc, out string HomeName)
{
    local Actor A;
    local CTFBase CTF;
    local ONSPowerCore Core;
    local ONSPowerCore CoreAny;
    local PlayerStart PS;
    local PlayerStart StartAny;

    // DynamicActors with a concrete subclass literal has a class-type
    // mismatch in some UT2004 compiler builds, so scan Actor and cast.
    foreach DynamicActors(class'Actor', A)
    {
        CTF = CTFBase(A);
        if (CTF != None && CTF.DefenderTeamIndex == Team)
        {
            BaseLoc = CTF.Location;
            HomeName = "Flag Base";
            return True;
        }
    }

    foreach DynamicActors(class'Actor', A)
    {
        Core = ONSPowerCore(A);
        if (Core == None || Core.DefenderTeamIndex != Team)
            continue;

        if (Core.bFinalCore)
        {
            BaseLoc = Core.Location;
            HomeName = "Main Power Core";
            return True;
        }

        if (CoreAny == None)
            CoreAny = Core;
    }

    if (CoreAny != None)
    {
        BaseLoc = CoreAny.Location;
        HomeName = "Power Core";
        return True;
    }

    foreach DynamicActors(class'Actor', A)
    {
        PS = PlayerStart(A);
        if (PS == None || !PS.bEnabled)
            continue;

        if (PS.TeamNumber == Team)
        {
            BaseLoc = PS.Location;
            HomeName = "Team Spawn";
            return True;
        }

        if (StartAny == None && (PS.TeamNumber == 255 || PS.TeamNumber == 0))
            StartAny = PS;
    }

    if (StartAny != None)
    {
        BaseLoc = StartAny.Location;
        HomeName = "Team Spawn";
        return True;
    }

    return False;
}

function bool FindRecallSpot(vector BaseLoc, Pawn P, int Index, int Count,
    out vector Result)
{
    local int Attempt;
    local float Angle;
    local float Radius;
    local vector Cand;
    local vector HitLoc;
    local vector HitNormal;
    local Actor Hit;
    local float PawnRadius;
    local float PawnHeight;
    local vector Extent;

    if (P == None)
        return False;

    PawnRadius = FMax(24.0, P.CollisionRadius);
    PawnHeight = FMax(48.0, P.CollisionHeight);

    // Simple ring around the base location, up to 3 rings with 6 positions each
    for (Attempt = 0; Attempt < 18; Attempt++)
    {
        Radius = 100.0 + 80.0 * (Attempt / 6);
        Angle = (2.0 * TD_PI * float(Index + Attempt) / float(Max(1, Count)));

        Cand.X = BaseLoc.X + Cos(Angle) * Radius;
        Cand.Y = BaseLoc.Y + Sin(Angle) * Radius;
        Cand.Z = BaseLoc.Z + 256.0;

        Extent.X = PawnRadius * 0.6;
        Extent.Y = PawnRadius * 0.6;
        Extent.Z = 1.0;
        Hit = Trace(HitLoc, HitNormal,
            Cand - vect(0,0,512), Cand, false, Extent);

        if (Hit == None || HitNormal.Z < 0.55)
            continue;

        Result = HitLoc;
        Result.Z = Result.Z + PawnHeight + 16.0;
        if (SpotIsFree(Result, P, PawnRadius, PawnHeight))
            return True;
    }

    // Last resort: the base location itself
    Result = BaseLoc;
    Result.Z = Result.Z + PawnHeight + 16.0;
    if (SpotIsFree(Result, P, PawnRadius, PawnHeight))
        return True;

    return False;
}

// ---------------------------------------------------------------------------
// Placement and clearance
// ---------------------------------------------------------------------------

/**
 * Expanding-ring search for the nearest valid vehicle spawn spot.
 *
 * Algorithm:
 *   1. Search in expanding rings from player outward (max 6 rings).
 *      Ring radius = (Ring + 1) * (VehicleRadius + 50), capped at SearchRadius
 *      so dropped vehicles stay near the fighter who requested them.
 *   2. Each ring samples N points (8 + Ring * 4), staggered by Ring * 0.3 rad
 *      so rings don't align.
 *   3. For each candidate:
 *      a) FastTrace LOS from candidate to player (must be in open space).
 *      b) Downward box trace from 1000 UU above to find ground
 *         (HitNormal.Z > 0.7; rejects bridge bottoms / vertical walls).
 *      c) Upward box trace from floor+15 to floor+2*Height+40 for ceiling
 *         clearance (rejects spots under overhangs / low bridges).
 *      d) CollidingActors overlap check at the final spawn position.
 *   4. Returns the first valid spot (closest to the player).
 *
 * Returns False if all rings are exhausted, which triggers "Not enough space"
 * plus a cooldown refund in the caller.
 */
function bool FindClearSpot(Pawn P, float Radius, float Height, out vector Spot, optional DirectorReplicationInfo RI)
{
    local int Ring, Sample, MaxRings, NumSamples;
    local int CloseYaw;
    local float RingRadius, SearchRadius, Angle, RingStagger;
    local rotator DirRot, CloseRot;
    local vector Dir;
    local vector Candidate;
    local string DebugMsg;

    if (P == None)
    {
        log("MutTechDirector: FindClearSpot - P is None");
        return False;
    }

    // Search bounds: keep the whole search reasonably close to the player, but
    // large enough to fit the vehicle being dropped.  Pawn-only radius is too
    // small for heavy assets, so scale with the vehicle radius too.
    SearchRadius = FMax(P.CollisionRadius * 6.0, Radius * 2.0);
    MaxRings = 6;

    log("MutTechDirector: FindClearSpot START P=" $ P $ " P.Loc=" $ P.Location $ " P.Radius=" $ P.CollisionRadius $ " Radius=" $ Radius $ " Height=" $ Height $ " SearchRadius=" $ SearchRadius);

    // Try close-in candidates first: the player's feet and a short distance
    // outward.  The expanding rings start further out, so without these the
    // ground right next to the fighter is never sampled.

    // 1. Player's exact location (slightly above feet to clear the pawn).
    Candidate = P.Location;
    Candidate.Z = Candidate.Z + 10.0;
    if (TrySpawnSpotAt(P, Radius, Height, Candidate, Spot, "Close_PawnLoc"))
        return True;

    // 2. 150 UU straight ahead of the player.
    Candidate = P.Location + vector(P.Rotation) * 150.0;
    if (TrySpawnSpotAt(P, Radius, Height, Candidate, Spot, "Close_Front150"))
        return True;

    // 3. Circle at 150 UU around the player (8 directions).
    for (CloseYaw = 0; CloseYaw < 8; CloseYaw++)
    {
        CloseRot.Pitch = 0;
        CloseRot.Yaw = CloseYaw * 8192;
        CloseRot.Roll = 0;
        Candidate = P.Location + vector(CloseRot) * 150.0;
        if (TrySpawnSpotAt(P, Radius, Height, Candidate, Spot, "Close_Circle150"))
            return True;
    }

    // Expanding rings from player outward.
    for (Ring = 0; Ring < MaxRings; Ring++)
    {
        RingRadius = (Ring + 1) * (Radius + 50.0);
        if (RingRadius > SearchRadius)
            RingRadius = SearchRadius;

        // More samples on larger rings.
        NumSamples = 8 + Ring * 4;

        // Stagger each ring by 0.3 rad (~17 deg) so rings don't align.
        RingStagger = Ring * 0.3;

        for (Sample = 0; Sample < NumSamples; Sample++)
        {
            Angle = (2.0 * 3.14159265 * Sample / NumSamples) + RingStagger;

            DirRot.Yaw = int(Angle * 32768.0 / 3.14159265);  // convert rad to UU rotator
            Dir = vector(DirRot);

            // Candidate at ring radius from player.
            Candidate = P.Location + Dir * RingRadius;

            DebugMsg = "Ring" $ Ring $ "_S" $ Sample $ "_R" $ RingRadius $ "_Ang" $ int(Angle * 180.0 / 3.14159);
            log("MutTechDirector: FindClearSpot " $ DebugMsg $ " Candidate=" $ Candidate $ " P.Loc=" $ P.Location);

            if (TrySpawnSpotAt(P, Radius, Height, Candidate, Spot, DebugMsg))
                return True;
        }
    }

    // All rings exhausted.
    log("MutTechDirector: FindClearSpot - All rings exhausted for Radius=" $ Radius $ " SearchRadius=" $ SearchRadius $ " MaxRings=" $ MaxRings);
    if (RI != None)
        Notify(RI, "Not enough space.");
    return False;
}

/**
 * Validate a single candidate spawn position: LOS to player, ground below,
 * ceiling clearance above, and no actor overlap.  Sets Spot on success.
 * DebugMsg is prefixed to log lines for traceability.
 */
function bool TrySpawnSpotAt(Pawn P, float Radius, float Height, vector Candidate, out vector Spot, string DebugMsg)
{
    local vector HitLoc, HitNormal;
    local Actor Hit;
    local vector FloorLoc;
    local vector Extent;
    local vector CeilEndVec;
    local vector OverlapCenter;
    local array<Actor> OverlapActors;
    local Actor OverlapActor;
    local bool bOverlap;

    // Box trace extent: full vehicle radius/height for conservative checks.
    Extent.X = Radius * 1.05;
    Extent.Y = Radius * 1.05;
    Extent.Z = Height * 0.5;

    // 1. FastTrace LOS from candidate to player (must be in open space).
    if (!FastTrace(Candidate, P.Location))
    {
        log("MutTechDirector: FindClearSpot " $ DebugMsg $ " FAIL FastTrace LOS");
        return False;
    }
    log("MutTechDirector: FindClearSpot " $ DebugMsg $ " PASS FastTrace LOS");

    // 2. Downward box trace from HIGH above to find floor.
    // Start at 1000 UU above candidate to clear overhangs/bridges.
    Hit = Trace(HitLoc, HitNormal,
        Candidate + vect(0,0,1000.0),
        Candidate - vect(0,0,500.0),
        false, Extent);

    // Only accept upward-facing ground (HitNormal.Z > 0.7).
    // Ignore bridge bottoms (normal -1.0) and vertical walls (~0).
    if (Hit == None)
    {
        log("MutTechDirector: FindClearSpot " $ DebugMsg $ " FAIL Trace Hit=None");
        return False;
    }
    if (HitNormal.Z < 0.7)
    {
        log("MutTechDirector: FindClearSpot " $ DebugMsg $ " FAIL HitNormal.Z=" $ HitNormal.Z $ " Hit=" $ Hit $ " HitLoc=" $ HitLoc $ " HitNormal=" $ HitNormal);
        return False;
    }

    FloorLoc = HitLoc;
    log("MutTechDirector: FindClearSpot " $ DebugMsg $ " PASS Floor HitLoc=" $ FloorLoc $ " Normal.Z=" $ HitNormal.Z);

    // 3. Upward box trace: floor+15 to floor+2*Height+40 for ceiling
    // clearance (rejects spots under overhangs / low ceilings).
    CeilEndVec = FloorLoc;
    CeilEndVec.Z = CeilEndVec.Z + (Height * 2.0) + 40.0;
    log("MutTechDirector: FindClearSpot " $ DebugMsg $ " CeilSweep FloorLoc.Z=" $ FloorLoc.Z $ " CeilEndVec.Z=" $ CeilEndVec.Z $ " Extent=" $ Extent);
    Hit = Trace(HitLoc, HitNormal,
        FloorLoc + vect(0,0,15.0),
        CeilEndVec,
        false, Extent);

    if (Hit != None)
    {
        log("MutTechDirector: FindClearSpot " $ DebugMsg $ " FAIL Ceiling Hit=" $ Hit $ " HitLoc=" $ HitLoc $ " HitNormal=" $ HitNormal);
        return False;
    }
    log("MutTechDirector: FindClearSpot " $ DebugMsg $ " PASS CeilSweep");

    // 4. Actors overlap check at final spawn position.
    // Vehicle bottom will be at FloorLoc.Z + Height + 25.  Check for any
    // actors overlapping the vehicle's cylinder.
    OverlapCenter = FloorLoc;
    OverlapCenter.Z = OverlapCenter.Z + Height * 0.5 + 25.0;

    OverlapActors.Length = 0;
    bOverlap = False;

    foreach CollidingActors(class'Actor', OverlapActor, Radius * 1.1, OverlapCenter)
    {
        if (OverlapActor == None || OverlapActor.bDeleteMe)
            continue;
        if (!OverlapActor.bBlockActors || OverlapActor.CollisionRadius < 8.0 || OverlapActor.CollisionHeight < 8.0)
            continue;
        if (VSize(OverlapActor.Location - OverlapCenter) < Radius + OverlapActor.CollisionRadius)
        {
            bOverlap = True;
            break;
        }
    }

    if (bOverlap)
    {
        log("MutTechDirector: FindClearSpot " $ DebugMsg $ " FAIL ActorOverlap Center=" $ OverlapCenter $ " Radius=" $ Radius);
        return False;
    }
    log("MutTechDirector: FindClearSpot " $ DebugMsg $ " PASS ActorOverlap");

    // Valid spot found! Place vehicle bottom at FloorLoc + Height + 25.
    Spot = FloorLoc;
    Spot.Z = Spot.Z + Height + 25.0;

    log("MutTechDirector: FindClearSpot " $ DebugMsg $ " SUCCESS Spot=" $ Spot $ " Radius=" $ Radius $ " Height=" $ Height);
    return True;
}

function bool SpotIsFree(vector Spot, Pawn Ignore, float Radius, float Height, optional DirectorReplicationInfo RI)
{
    // No clearance checks — always allow spawn at head height.
    // Team coordination issue if it spawns in a wall/ceiling.
    log("MutTechDirector: SpotIsFree - Spot=" $ Spot $ " Radius=" $ Radius);
    return True;
}

// ---------------------------------------------------------------------------
// Native effects and sounds
// ---------------------------------------------------------------------------

/**
 * Spawn a native teleport emitter at the deployment point and send a native
 * weapon/teleport cue to the director.  Kind is only used to choose a small
 * colour/impact variation; all paths use stock UT2004 assets so no extra
 * texture or sound packages are required.
 */
function DeployFX(vector Loc, byte Team, int Kind)
{
    local Actor FX;

    if (Team == 1)
        FX = Spawn(class'XEffects.NewTransEffectBlue',,, Loc + vect(0,0,40));
    else
        FX = Spawn(class'XEffects.NewTransEffect',,, Loc + vect(0,0,40));
}

defaultproperties
{
    FriendlyName="Tournament Technical Director"
    Description="Turns one player per team into the Tournament Technical Director: a remote broadcast operator with a locked fighter feed, tactical zoom, nanite healing and nine configurable transmat abilities. Press K to enter (5 second delay) or leave instantly. Works in any TeamGame-derived gametype."
    GroupName="MutTechDirector"
    bAddToServerPackages=True

    // Configure Mutators button -> our own settings submenu.
    ConfigMenuClassName="MutTechDirector.MutTechDirectorConfig"

    Cooldown1=1.000000
    Cooldown2=1.000000
    Cooldown3=1.000000
    Cooldown4=1.000000
    Cooldown5=1.000000
    Cooldown6=1.000000
    Cooldown7=1.000000
    Cooldown8=1.000000
    Cooldown9=1.000000
}
