//=============================================================================
// DirectorReplicationInfo
//
// Per-player, owner-only replication proxy for MutTechDirector.
//
// One of these is spawned on the server for every player who enters Technical
// Director Mode.  It is owned by that player's PlayerController and marked
// bOnlyRelevantToOwner, so the server can keep all cooldown/ability/target
// state authoritative while the owning client receives exactly the telemetry
// it needs for the Interaction HUD.
//
// Responsibilities:
//   * hold the nine transmat cooldown timers (server-authoritative)
//   * hold the currently broadcast fighter feed (Pawn)
//   * tick cooldowns only while Director Mode is active
//   * run the Nanite Med-Surge while the Jump key is held
//   * notice the death of the viewed fighter and auto-cycle after 1 second
//   * attach/detach the client-side DirectorInteraction
//   * forward key-driven client requests to MutTechDirector
//
// The class deliberately does not implement the abilities itself.  The
// Mutator is the only authority that spawns actors and changes pawn state;
// this RI is the replicated scoreboard/telemetry record for that authority.
//=============================================================================
class DirectorReplicationInfo extends ReplicationInfo;

// ---------------------------------------------------------------------------
// Server-side references (not replicated)
// ---------------------------------------------------------------------------

/** The player who owns this booth. */
var PlayerController DirectorPC;

/** The mutator authority that executes the actual transmat drops. */
var MutTechDirector DirectorMutator;

// ---------------------------------------------------------------------------
// Replicated state
// ---------------------------------------------------------------------------

/** The team the director is observing. Kept on TeamInfo by the mutator. */
var byte DirectorTeam;

/** True while the booth is online. */
var bool bDirectorActive;

/** True while the Nanite Med-Surge beam is being held. */
var bool bHealing;

/** The living friendly pawn currently on the broadcast feed. */
var Pawn CurrentTarget;

/** Live roster tally for the HUD counter: teammates only, bots included. */
var int TeamAlive;
var int TeamDead;

/** Replicated list of friendly turrets (DirectorSentinels) for beacon display. */
var Pawn TeamTurrets[16];

/** Server-configured cooldown ceiling per slot, replicated from the mutator. */
var float MaxCooldowns[9];

/** Per-slot cooldowns in seconds.  Slot 0 is unused (Jump has no cooldown). */
var float Cooldown1;
var float Cooldown2;
var float Cooldown3;
var float Cooldown4;
var float Cooldown5;
var float Cooldown6;
var float Cooldown7;
var float Cooldown8;
var float Cooldown9;

// ---------------------------------------------------------------------------
// Server-only transient state
// ---------------------------------------------------------------------------

/** Waiting for the one-second post-death delay before auto-cycling. */
var bool bPendingCycle;

/** Level.TimeSeconds at which the pending auto-cycle fires. */
var float CycleAt;

/** Accumulator for the 2 HP/sec Nanite beam. */
var float HealAccum;

/** The pawn currently benefiting from the Stimuli Dose. */
var Pawn BerserkPawn;

/** Seconds left on the Stimuli Dose. */
var float BerserkTime;

/** Accumulator for the 0.5 s roster recount. */
var float TeamAccum;

/** Accumulator for the 2 s turret list refresh. */
var float TurretAccum;

/** Hidden actor at beacon position (vehicle + 60 Z) for camera orbit.
 *  When target is a vehicle with driver, camera orbits this actor instead
 *  of the vehicle center, so beacon stays fixed on screen. */
var Actor BeaconOrbitActor;

/** True while the 5 s entry delay is running; the booth is not online yet. */
var bool bBoothPending;

/** Seconds left on the entry delay. */
var float EntryTimeLeft;

/** Last whole second broadcast to the client, to avoid duplicate popups. */
var int LastEntrySecond;

/** True once a live pawn was seen during the delay (death detection arm). */
var bool bEntrySawPawn;

// ---------------------------------------------------------------------------
// Client-side attachment bookkeeping
// ---------------------------------------------------------------------------

var transient DirectorInteraction DirectorInteractionRef;
var transient int AttachTries;

/** Original HUD class, saved on the client so we can restore it on exit. */
var transient class<HUD> OriginalHUDClass;
/** Original HUD's ScoreBoard class, saved so we can restore it on the new HUD. */
var transient class<Scoreboard> OriginalScoreBoardClass;

// ---------------------------------------------------------------------------
// Replication
// ---------------------------------------------------------------------------

replication
{
    // Server -> owning client: live telemetry used by the HUD and camera.
    reliable if (Role == ROLE_Authority)
        DirectorPC, DirectorTeam, bDirectorActive, bHealing, CurrentTarget,
        TeamAlive, TeamDead, MaxCooldowns, TeamTurrets;

    reliable if (Role == ROLE_AuthorITY)
        Cooldown1, Cooldown2, Cooldown3, Cooldown4,
        Cooldown5, Cooldown6, Cooldown7, Cooldown8,
        Cooldown9;

    // Server -> owning client: one-shot camera-switch cue, booth teardown and
    // HUD notification text.  The text must travel as a string RPC, not as an
    // OptionalObject: a transient local-message wrapper created on the server
    // only exists there, so remote clients would receive None and draw nothing.
    reliable if (Role == ROLE_Authority)
        ClientSwitchSound, ClientCloseBooth, ClientNotify;

    // Owning client -> server: raw input requests.  The server re-validates
    // every one of these; the client never decides a cooldown or a target.
    reliable if (Role < ROLE_Authority)
        ServerCycleTarget, ServerSetHealing, ServerUseAbility,
        ServerLeaveDirector;
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

simulated event PostBeginPlay()
{
    Super.PostBeginPlay();

    if (DirectorPC == None)
        DirectorPC = PlayerController(Owner);

    if (Level.NetMode != NM_DedicatedServer)
        TryAttachInteraction();
}

simulated event PostNetBeginPlay()
{
    Super.PostNetBeginPlay();

    if (DirectorPC == None)
        DirectorPC = PlayerController(Owner);

    TryAttachInteraction();
}

simulated function Timer()
{
    SetTimer(0.0, false);
    if (DirectorInteractionRef == None)
        TryAttachInteraction();
}

/**
 * Create the local render/input hook.  A client can receive this actor before
 * its Player or InteractionMaster exists (especially during a network join),
 * so we retry with a short timer instead of assuming one-shot success.
 */
simulated function TryAttachInteraction()
{
    local DirectorInteraction I;
    local int LoopIdx;

    if (Level.NetMode == NM_DedicatedServer || DirectorInteractionRef != None)
        return;

    if (DirectorPC == None)
        DirectorPC = PlayerController(Owner);

    if (DirectorPC == None || DirectorPC.Player == None ||
        DirectorPC.Player.InteractionMaster == None)
    {
        AttachTries++;
        if (AttachTries <= 20)
            SetTimer(0.25, true);
        return;
    }

    // LocalInteractions survives level travel.  Reuse our own Interaction if
    // it is still attached, and evict stale DirectorInteractions left over
    // from a previous match before adding a fresh one.
    for (LoopIdx = DirectorPC.Player.LocalInteractions.Length - 1; LoopIdx >= 0; LoopIdx--)
    {
        I = DirectorInteraction(DirectorPC.Player.LocalInteractions[LoopIdx]);
        if (I == None)
            continue;

        if (I.RI == Self)
        {
            DirectorInteractionRef = I;
            I.PC = DirectorPC;
            I.bVisible = True;
            I.bActive = True;
            SetTimer(0.0, false);
            return;
        }

        I.Cleanup();
    }

    I = DirectorInteraction(
        DirectorPC.Player.InteractionMaster.AddInteraction(
            "MutTechDirector.DirectorInteraction", DirectorPC.Player));

    if (I == None)
    {
        AttachTries++;
        if (AttachTries <= 20)
            SetTimer(0.25, true);
        return;
    }

    I.RI = Self;
    I.PC = DirectorPC;
    I.bVisible = True;
    I.bActive = True;
    DirectorInteractionRef = I;
    SetTimer(0.0, false);
}

simulated event Destroyed()
{
    // Safety net: restore the original HUD if we're being destroyed without
    // going through ClientCloseBooth (e.g., network disconnect, level change).
    if (DirectorPC == None || DirectorPC.bDeleteMe)
        DirectorPC = PlayerController(Owner);

    if (DirectorPC != None && !DirectorPC.bDeleteMe && OriginalHUDClass != None)
    {
        DirectorPC.myHUD = Spawn(OriginalHUDClass, DirectorPC);
        if (DirectorPC.myHUD != None)
        {
            log("MutTechDirector: Destroyed - restored original HUD=" $ OriginalHUDClass);
        }
        OriginalHUDClass = None;
    }

    if (DirectorInteractionRef != None)
    {
        DirectorInteractionRef.Cleanup();
        DirectorInteractionRef = None;
    }

    // Clean up beacon orbit actor
    if (BeaconOrbitActor != None && !BeaconOrbitActor.bDeleteMe)
    {
        BeaconOrbitActor.Destroy();
        BeaconOrbitActor = None;
    }

    Super.Destroyed();
}

// ---------------------------------------------------------------------------
// Booth state
// ---------------------------------------------------------------------------

/**
 * Open the 5 s entry delay.  The booth is NOT online yet: the player keeps
 * playing normally until CompleteEntry() runs, so the delay cannot be used to
 * dodge an imminent death.  Exiting is immediate and needs no delay.
 */
function BeginEntryCountdown(MutTechDirector M, PlayerController PC, byte Team,
                             float Seconds)
{
    DirectorMutator = M;
    DirectorPC = PC;
    SetOwner(PC);
    DirectorTeam = Team;
    bDirectorActive = False;
    bBoothPending = True;
    EntryTimeLeft = Seconds;
    LastEntrySecond = int(Seconds + 0.999);
    bEntrySawPawn = False;
    bHealing = False;
    bPendingCycle = False;
    HealAccum = 0.0;
    BerserkPawn = None;
    BerserkTime = 0.0;
    TeamAccum = 0.0;
    TurretAccum = 0.0;
    TeamAlive = 0;
    TeamDead = 0;
    CopyCooldownSettings(M);
    UpdateTeamCounts();
    ClientNotify("Entering Technical Director booth in " $ LastEntrySecond $ "...");
}

/** Copy the mutator's configurable cooldowns into the replicated ceiling. */
function CopyCooldownSettings(MutTechDirector M)
{
    if (M == None)
        return;

    MaxCooldowns[0] = M.Cooldown1;
    MaxCooldowns[1] = M.Cooldown2;
    MaxCooldowns[2] = M.Cooldown3;
    MaxCooldowns[3] = M.Cooldown4;
    MaxCooldowns[4] = M.Cooldown5;
    MaxCooldowns[5] = M.Cooldown6;
    MaxCooldowns[6] = M.Cooldown7;
    MaxCooldowns[7] = M.Cooldown8;
    MaxCooldowns[8] = M.Cooldown9;
}

/** The entry delay expired: bring the booth online. */
function ActivateBooth()
{
    bBoothPending = False;
    bDirectorActive = True;
    RefreshTurretList();

    // Swap to the custom Director HUD on the owning client.
    // This must be a simulated RPC so the client replaces its stock HUD.
    ClientActivateBooth();
}

/**
 * Client-side RPC: replace the stock HUD with DirectorHUD.
 * Called from ActivateBooth() on the server via replication.
 * The custom HUD suppresses native vehicle name drawing (which cannot be
 * suppressed from UnrealScript otherwise) and provides a clean canvas for
 * DirectorInteraction.PostRender to draw all telemetry.
 */
simulated function ClientActivateBooth()
{
    local DirectorHUD NewHUD;

    if (DirectorPC == None || DirectorPC.bDeleteMe)
        DirectorPC = PlayerController(Owner);

    if (DirectorPC == None || DirectorPC.bDeleteMe || DirectorPC.myHUD == None)
    {
        log("MutTechDirector: ClientActivateBooth - ABORT: DirectorPC=" $ DirectorPC $ " myHUD=" $ DirectorPC.myHUD);
        return;
    }

    // Save the original HUD class and its ScoreBoard class so we can restore both on exit.
    OriginalHUDClass = DirectorPC.myHUD.Class;
    if (DirectorPC.myHUD.ScoreBoard != None)
        OriginalScoreBoardClass = DirectorPC.myHUD.ScoreBoard.Class;
    else
        OriginalScoreBoardClass = None;

    // Spawn and set the custom Director HUD.
    NewHUD = Spawn(class'DirectorHUD', DirectorPC);
    if (NewHUD != None)
    {
        DirectorPC.myHUD = NewHUD;
        // Give the new HUD the same scoreboard class the original had.
        if (OriginalScoreBoardClass != None)
            NewHUD.SetScoreBoardClass(OriginalScoreBoardClass);
        log("MutTechDirector: ClientActivateBooth - swapped to DirectorHUD, originalHUD=" $ OriginalHUDClass $ " scoreboard=" $ OriginalScoreBoardClass $ " newHUD.ScoreBoard=" $ NewHUD.ScoreBoard); // REMOVE: debug
    }
    else
    {
        log("MutTechDirector: ClientActivateBooth - FAILED to spawn DirectorHUD");
    }
}

/** Refresh the replicated list of friendly turrets for beacon display. */
function RefreshTurretList()
{
    local DirectorSentinel T;
    local int i;
    local int Count;
    local byte TeamNum;

    if (Role < ROLE_Authority)
    {
        log("MutTechDirector: RefreshTurretList called but Role < ROLE_Authority, ignoring.");
        return;
    }

    i = 0;
    Count = 0;

    log("MutTechDirector: RefreshTurretList START DirectorTeam=" $ DirectorTeam $ " DirectorMutator=" $ DirectorMutator);

    foreach AllActors(class'DirectorSentinel', T)
    {
        TeamNum = T.GetTeamNum();
        if (T == None || T.bDeleteMe || T.Health <= 0)
        {
            log("MutTechDirector: RefreshTurretList skip T=" $ T $ " (none/bDeleteMe/dead)");
            continue;
        }
        if (T.GetTeamNum() != DirectorTeam)
        {
            log("MutTechDirector: RefreshTurretList skip T=" $ T $ " team=" $ TeamNum $ " != DirectorTeam=" $ DirectorTeam);
            continue;
        }
        if (i < 16)
        {
            TeamTurrets[i] = T;
            log("MutTechDirector: RefreshTurretList slot[" $ i $ "] = T=" $ T $ " team=" $ TeamNum $ " health=" $ T.Health);
            i++;
            Count++;
        }
    }

    // Clear remaining slots
    while (i < 16)
    {
        TeamTurrets[i] = None;
        i++;
    }

    log("MutTechDirector: RefreshTurretList done, " $ Count $ " turrets registered for team " $ DirectorTeam);

    // Also update the mutator's replicated array for field players
    if (DirectorMutator != None)
    {
        log("MutTechDirector: RefreshTurretList calling DirectorMutator.RefreshTeamTurrets()");
        DirectorMutator.RefreshTeamTurrets(TeamTurrets);
    }
    else
    {
        log("MutTechDirector: RefreshTurretList DirectorMutator is None, NOT pushing to mutator array.");
    }
}

/** Called by mutator when a turret is deployed or destroyed. */
function OnTurretChange()
{
    log("MutTechDirector: OnTurretChange() called Role=" $ Role);
    if (Role == ROLE_Authority)
    {
        RefreshTurretList();
        // Attach/reattach beacon interactions to all current combatants so they
        // get the turret beacon interaction whenever the turret roster changes
        // (not only when the Director first enters the booth).
        if (DirectorMutator != None)
        {
            log("MutTechDirector: OnTurretChange calling DirectorMutator.AttachTurretBeaconsToTeam()");
            DirectorMutator.AttachTurretBeaconsToTeam(DirectorTeam, Self);
        }
    }
}

/** Drop a pending entry without ever opening the booth. */
function AbortPendingEntry()
{
    bBoothPending = False;
    bDirectorActive = False;
    
    // Clean up beacon orbit actor
    if (BeaconOrbitActor != None && !BeaconOrbitActor.bDeleteMe)
    {
        BeaconOrbitActor.Destroy();
        BeaconOrbitActor = None;
    }
    
    if (DirectorMutator != None)
        DirectorMutator.RemoveDirectorRI(Self);
    Destroy();
}

/** Server-side 5 s entry delay; each whole second is pushed to the HUD. */
function TickEntryCountdown(float DeltaTime)
{
    local int Secs;

    // Dying during the delay cancels the entry.  This is the whole point of
    // the delay: the booth can no longer be used to dodge an imminent death.
    if (DirectorPC.Pawn != None && DirectorPC.Pawn.Health > 0)
    {
        bEntrySawPawn = True;
    }
    else if (bEntrySawPawn)
    {
        ClientNotify("Technical Director entry cancelled: you died.");
        AbortPendingEntry();
        return;
    }

    EntryTimeLeft -= DeltaTime;

    Secs = int(EntryTimeLeft + 0.999);
    if (Secs < 1)
        Secs = 1;

    if (Secs != LastEntrySecond)
    {
        LastEntrySecond = Secs;
        ClientNotify("Entering Technical Director booth in " $ Secs $ "...");
    }

    if (EntryTimeLeft <= 0.0)
    {
        if (DirectorMutator == None)
        {
            AbortPendingEntry();
            return;
        }
        bBoothPending = False;
        DirectorMutator.CompleteEntry(Self);
    }
}

function EndDirectorMode()
{
    bBoothPending = False;
    bDirectorActive = False;
    bHealing = False;
    bPendingCycle = False;
    ClearBerserk();
    
    // Clean up beacon orbit actor
    if (BeaconOrbitActor != None && !BeaconOrbitActor.bDeleteMe)
    {
        BeaconOrbitActor.Destroy();
        BeaconOrbitActor = None;
    }
    
    ClientCloseBooth();
    Destroy();
}

/** Reset every transmat slot to its full, uncharged cooldown. */
function ResetCooldowns()
{
    Cooldown1 = GetMaxCooldown(1);
    Cooldown2 = GetMaxCooldown(2);
    Cooldown3 = GetMaxCooldown(3);
    Cooldown4 = GetMaxCooldown(4);
    Cooldown5 = GetMaxCooldown(5);
    Cooldown6 = GetMaxCooldown(6);
    Cooldown7 = GetMaxCooldown(7);
    Cooldown8 = GetMaxCooldown(8);
    Cooldown9 = GetMaxCooldown(9);
}

simulated function float GetCooldown(int Slot)
{
    switch (Slot)
    {
        case 1: return Cooldown1;
        case 2: return Cooldown2;
        case 3: return Cooldown3;
        case 4: return Cooldown4;
        case 5: return Cooldown5;
        case 6: return Cooldown6;
        case 7: return Cooldown7;
        case 8: return Cooldown8;
        case 9: return Cooldown9;
    }
    return 0.0;
}

simulated function float GetMaxCooldown(int Slot)
{
    if (Slot < 1 || Slot > 9)
        return 0.0;

    return FMax(0.0, MaxCooldowns[Slot - 1]);
}

function SetCooldown(int Slot, float Value)
{
    switch (Slot)
    {
        case 1: Cooldown1 = Value; break;
        case 2: Cooldown2 = Value; break;
        case 3: Cooldown3 = Value; break;
        case 4: Cooldown4 = Value; break;
        case 5: Cooldown5 = Value; break;
        case 6: Cooldown6 = Value; break;
        case 7: Cooldown7 = Value; break;
        case 8: Cooldown8 = Value; break;
        case 9: Cooldown9 = Value; break;
    }
}

// ---------------------------------------------------------------------------
// Fighter feed
// ---------------------------------------------------------------------------

/** Point the owning controller at a living teammate (or at itself if None).
 *  If target is a vehicle with driver, create a hidden actor at beacon position
 *  (vehicle + 60 Z) and make it the view target, so camera orbits the beacon
 *  position instead of vehicle center. */
function SetTarget(Pawn NewTarget)
{
    local Vehicle TargetVehicle;
    local Actor NewBeaconActor;

    if (!bDirectorActive || bDeleteMe || DirectorPC == None ||
        DirectorPC.bDeleteMe)
        return;

    // Clean up existing beacon actor
    if (BeaconOrbitActor != None && !BeaconOrbitActor.bDeleteMe)
    {
        BeaconOrbitActor.Destroy();
        BeaconOrbitActor = None;
    }

    CurrentTarget = NewTarget;

    if (NewTarget != None)
    {
        TargetVehicle = Vehicle(NewTarget);
        if (TargetVehicle != None && TargetVehicle.Driver != None)
        {
            // Create hidden actor at beacon position (vehicle + 60 Z)
            NewBeaconActor = Spawn(class'Actor', Self,, TargetVehicle.Location + vect(0,0,60), rot(0,0,0));
            if (NewBeaconActor != None)
            {
                NewBeaconActor.bHidden = True;
                BeaconOrbitActor = NewBeaconActor;
                
                // Make beacon actor the view target so camera orbits beacon position
                DirectorPC.SetViewTarget(BeaconOrbitActor);
                DirectorPC.ClientSetViewTarget(BeaconOrbitActor);
            }
            else
            {
                // Fallback to vehicle
                DirectorPC.SetViewTarget(NewTarget);
                DirectorPC.ClientSetViewTarget(NewTarget);
            }
        }
        else
        {
            // On-foot target or vehicle without driver
            DirectorPC.SetViewTarget(NewTarget);
            DirectorPC.ClientSetViewTarget(NewTarget);
        }

        DirectorPC.bBehindView = True;
        DirectorPC.ClientSetBehindView(True);
    }
    else
    {
        DirectorPC.SetViewTarget(DirectorPC);
        DirectorPC.ClientSetViewTarget(DirectorPC);
        DirectorPC.bBehindView = False;
        DirectorPC.ClientSetBehindView(False);
    }
}

// ---------------------------------------------------------------------------
// Server requests from the client Interaction
// ---------------------------------------------------------------------------

function ServerCycleTarget(int Dir)
{
    local Pawn Next;

    if (Role < ROLE_Authority || !bDirectorActive || bDeleteMe ||
        DirectorMutator == None)
        return;

    Next = DirectorMutator.FindTeammate(DirectorPC, CurrentTarget, Dir);
    if (Next == None)
        return;

    SetTarget(Next);
    ClientSwitchSound();
}

function ServerSetHealing(bool bOn)
{
    if (Role < ROLE_Authority || !bDirectorActive || bDeleteMe)
        return;

    bHealing = bOn;
    if (!bHealing)
        HealAccum = 0.0;
}

function ServerUseAbility(int Slot)
{
    if (Role < ROLE_Authority || !bDirectorActive || bDeleteMe ||
        DirectorMutator == None)
        return;

    DirectorMutator.UseAbility(Self, Slot);
}

function ServerLeaveDirector()
{
    if (Role < ROLE_Authority || !bDirectorActive || bDeleteMe ||
        DirectorMutator == None)
        return;

    DirectorMutator.ExitDirectorMode(Self);
}

// ---------------------------------------------------------------------------
// Server simulation
// ---------------------------------------------------------------------------

event Tick(float DeltaTime)
{
    local Pawn Next;
    local Vehicle TargetVehicle;
    local float HealRate;
    local float PulseInterval;

    Super.Tick(DeltaTime);

    if (Role < ROLE_Authority)
        return;

    // The owning controller is gone (logout/level change that did not call
    // NotifyLogout).  Do not touch stale state.
    if (DirectorPC == None || DirectorPC.bDeleteMe)
    {
        Destroy();
        return;
    }

    // Entry delay: the booth is still offline, so nothing else here applies
    // until CompleteEntry() brings it online.
    if (bBoothPending)
    {
        TickEntryCountdown(DeltaTime);
        return;
    }

    if (!bDirectorActive)
        return;

    // Some gametypes (notably Assault and Onslaught round resets) call
    // GameInfo.RestartPlayer() for every non-spectator PRI.  The Director is
    // still a team member, so they can be handed a fresh pawn while the booth
    // is online.  Suppress it immediately and re-assert the broadcast camera.
    if (DirectorPC != None && DirectorPC.Pawn != None)
        SuppressStrayPawn();

    // Compatibility with respawn-delay mutators (e.g. ut2k4rd/RespawnDelay):
    // they detect fresh deaths by looking for controllers with no pawn in
    // 'Dead' or 'Spectating' state and PRI.bOutOfLives == false.  While the
    // Director is in the booth we must keep bOutOfLives = true so the respawn
    // supervisor skips us.  Vanilla DeathMatch.RestartPlayer() also refuses to
    // spawn a PRI with bOutOfLives.  RespawnDelay clears the flag when a
    // waiting player enters Spectating, so we re-assert it every tick.
    if (DirectorPC != None && DirectorPC.PlayerReplicationInfo != None &&
        !DirectorPC.PlayerReplicationInfo.bOutOfLives)
    {
        DirectorPC.PlayerReplicationInfo.bOutOfLives = True;
    }

    // Roster tally for the HUD counter.  Two recounts a second is cheap for a
    // few dozen controllers and still feels live.
    TeamAccum += DeltaTime;
    if (TeamAccum >= 0.5)
    {
        TeamAccum = 0.0;
        UpdateTeamCounts();
    }

    // Turret list refresh for beacon display.  Every 2 seconds is plenty.
    TurretAccum += DeltaTime;
    if (TurretAccum >= 2.0)
    {
        TurretAccum = 0.0;
        RefreshTurretList();
    }

    // Cooldowns only move while the booth is occupied.  Because the RI is
    // destroyed on exit and recreated with ResetCooldowns() on entry, leaving
    // the booth can never bank progress.
    if (Cooldown1 > 0.0) Cooldown1 = FMax(0.0, Cooldown1 - DeltaTime);
    if (Cooldown2 > 0.0) Cooldown2 = FMax(0.0, Cooldown2 - DeltaTime);
    if (Cooldown3 > 0.0) Cooldown3 = FMax(0.0, Cooldown3 - DeltaTime);
    if (Cooldown4 > 0.0) Cooldown4 = FMax(0.0, Cooldown4 - DeltaTime);
    if (Cooldown5 > 0.0) Cooldown5 = FMax(0.0, Cooldown5 - DeltaTime);
    if (Cooldown6 > 0.0) Cooldown6 = FMax(0.0, Cooldown6 - DeltaTime);
    if (Cooldown7 > 0.0) Cooldown7 = FMax(0.0, Cooldown7 - DeltaTime);
    if (Cooldown8 > 0.0) Cooldown8 = FMax(0.0, Cooldown8 - DeltaTime);
    if (Cooldown9 > 0.0) Cooldown9 = FMax(0.0, Cooldown9 - DeltaTime);

    // Update beacon orbit actor position to track vehicle + 60 Z offset.
    // This keeps the camera orbiting the beacon position (not vehicle center).
    if (BeaconOrbitActor != None && !BeaconOrbitActor.bDeleteMe && CurrentTarget != None)
    {
        TargetVehicle = Vehicle(CurrentTarget);
        if (TargetVehicle != None && TargetVehicle.Driver != None)
        {
            BeaconOrbitActor.SetLocation(TargetVehicle.Location + vect(0,0,60));
        }
        else
        {
            // Target is no longer a vehicle with driver; clean up beacon actor
            BeaconOrbitActor.Destroy();
            BeaconOrbitActor = None;
            // Restore view target to actual target (if still valid)
            if (CurrentTarget != None && !CurrentTarget.bDeleteMe)
            {
                DirectorPC.SetViewTarget(CurrentTarget);
                DirectorPC.ClientSetViewTarget(CurrentTarget);
            }
        }
    }

    // Nanite Med-Surge: configurable HP/sec (default 2), applied in pulses so the
    // displayed health changes smoothly without a per-frame network storm.
    // Pulse interval = 1.0 / NaniteHealRate (e.g., 2 HP/sec -> 0.5s pulse).
    if (bHealing && CurrentTarget != None && CurrentTarget.Health > 0 && DirectorMutator != None)
    {
        HealRate = DirectorMutator.NaniteHealRate;
        if (HealRate <= 0.0)
            HealRate = 0.0;
        else if (HealRate > 199.0)
            HealRate = 199.0;

        if (HealRate > 0.0)
        {
            PulseInterval = 1.0 / HealRate;
            HealAccum += DeltaTime;
            while (HealAccum >= PulseInterval)
            {
                HealAccum -= PulseInterval;
                HealTargetOnePoint();
            }
        }
    }
    else
    {
        HealAccum = 0.0;
    }

    // Stimuli Dose expiration.
    if (BerserkPawn != None)
    {
        BerserkTime -= DeltaTime;
        if (BerserkTime <= 0.0)
            ClearBerserk();
    }

    // Feed-loss detection.  Dead teammates do not immediately yank the view;
    // the booth holds the last frame for one second, then cuts to the next
    // living fighter with a short switch cue.
    if (CurrentTarget == None || CurrentTarget.bDeleteMe ||
        CurrentTarget.Health <= 0)
    {
        if (!bPendingCycle)
        {
            bPendingCycle = True;
            CycleAt = Level.TimeSeconds + 1.0;
        }
        else if (Level.TimeSeconds >= CycleAt)
        {
            // Retry every second until a living teammate exists.  If the team
            // is momentarily wiped, stay on the last frame instead of cutting
            // to an empty camera and chirping the switch cue forever.
            bPendingCycle = False;
            if (DirectorMutator != None)
                Next = DirectorMutator.FindTeammate(DirectorPC, CurrentTarget, 1);
            if (Next != None)
            {
                SetTarget(Next);
                ClientSwitchSound();
            }
        }
    }
    else
    {
        bPendingCycle = False;
    }
}

/**
 * A round reset can hand the Director a pawn even though the booth is active.
 * Remove it again without scoring a death and restore the spectator camera.
 */
function SuppressStrayPawn()
{
    local Pawn Stray;

    if (DirectorPC == None)
        return;

    Stray = DirectorPC.Pawn;
    if (Stray == None)
        return;

    DirectorPC.UnPossess();
    if (Stray != None && !Stray.bDeleteMe)
        Stray.Destroy();

    DirectorPC.GotoState('Spectating');
    DirectorPC.bBehindView = True;
    DirectorPC.ClientSetBehindView(True);
    SetTarget(CurrentTarget);
}

function HealTargetOnePoint()
{
    local int Cap;

    if (CurrentTarget == None || CurrentTarget.Health <= 0)
        return;

    // Standard UT2004 super-health ceiling is 199.  If the fighter is already
    // above that (Painkillers set 300), preserve it instead of clamping down.
    Cap = int(FMax(199.0, float(CurrentTarget.Health)));
    if (CurrentTarget.Health < Cap)
        CurrentTarget.Health = Min(Cap, CurrentTarget.Health + 1);
}

// ---------------------------------------------------------------------------
// Stimuli Dose helper
// ---------------------------------------------------------------------------

function ApplyBerserk(Pawn P)
{
    if (P == None)
        return;

    if (xPawn(P) != None)
    {
        xPawn(P).bBerserk = True;
        if (xPawn(P).Weapon != None)
            xPawn(P).Weapon.StartBerserk();
    }

    BerserkPawn = P;
    BerserkTime = 30.0;
}

function ClearBerserk()
{
    if (xPawn(BerserkPawn) != None)
    {
        xPawn(BerserkPawn).bBerserk = False;
        if (xPawn(BerserkPawn).Weapon != None)
            xPawn(BerserkPawn).Weapon.StopBerserk();
    }

    BerserkPawn = None;
    BerserkTime = 0.0;
}

// ---------------------------------------------------------------------------
// HUD support
// ---------------------------------------------------------------------------

/**
 * Server-authoritative roster tally for the TeamMates HUD counter.
 *
 * Only the director's team is counted, bots included (they own a
 * PlayerReplicationInfo just like humans).  The director is skipped: they are
 * the observer, not a fighter on the feed.  A teammate with no pawn (waiting to
 * respawn) or a dead corpse counts as Dead, which keeps Alive+Dead equal to the
 * full team size.
 */
function UpdateTeamCounts()
{
    local Controller C;
    local int Alive;
    local int Dead;

    Alive = 0;
    Dead = 0;

    for (C = Level.ControllerList; C != None; C = C.NextController)
    {
        if (C.bDeleteMe || C == DirectorPC || C.PlayerReplicationInfo == None)
            continue;
        if (C.PlayerReplicationInfo.bIsSpectator ||
            C.PlayerReplicationInfo.bOnlySpectator)
            continue;
        if (C.PlayerReplicationInfo.Team == None)
            continue;
        if (C.PlayerReplicationInfo.Team.TeamIndex != DirectorTeam)
            continue;

        if (C.Pawn != None && C.Pawn.Health > 0)
            Alive++;
        else
            Dead++;
    }

    TeamAlive = Alive;
    TeamDead = Dead;
}

/** Fill an array with the living pawns on the director's team. */
simulated function GetFriendlyPawns(out array<Pawn> Pawns)
{
    local Pawn P;

    Pawns.Length = 0;

    foreach DynamicActors(class'Pawn', P)
    {
        if (P == None || P.Health <= 0)
            continue;
        if (P.GetTeamNum() != DirectorTeam)
            continue;
        Pawns[Pawns.Length] = P;
    }
}

simulated function ClientSwitchSound()
{
    if (DirectorPC == None)
        DirectorPC = PlayerController(Owner);

    if (DirectorPC != None)
        DirectorPC.ClientPlaySound(Sound'MenuSounds.selectDshort', true, 1.0, SLOT_None);
}

/**
 * Reliable string RPC: draw a DirectorNotify HUD line on the owning client.
 * The wrapper object is built on the client so it is guaranteed to exist when
 * the local message renders (a server-created wrapper would replicate as None).
 */
simulated function ClientNotify(string S)
{
    local DirectorNotifyText T;

    if (DirectorPC == None || DirectorPC.bDeleteMe)
        DirectorPC = PlayerController(Owner);

    if (DirectorPC == None || DirectorPC.bDeleteMe)
        return;

    T = new class'DirectorNotifyText';
    T.Text = S;
    DirectorPC.ReceiveLocalizedMessage(class'DirectorNotify', 1, None, None, T);
}

/**
 * Explicit client teardown.  Actor destruction normally reaches the owning
 * client too, but a reliable RPC guarantees the HUD and key hook disappear
 * immediately on exit instead of waiting for (or missing) that replication.
 */
simulated function ClientCloseBooth(optional string NotifyText)
{
    // Restore the original HUD before cleaning up the Interaction.
    if (DirectorPC == None || DirectorPC.bDeleteMe)
        DirectorPC = PlayerController(Owner);

    if (DirectorPC != None && !DirectorPC.bDeleteMe && OriginalHUDClass != None)
    {
        DirectorPC.myHUD = Spawn(OriginalHUDClass, DirectorPC);
        if (DirectorPC.myHUD != None)
        {
            // Restore the original scoreboard class too
            if (OriginalScoreBoardClass != None)
                DirectorPC.myHUD.SetScoreBoardClass(OriginalScoreBoardClass);
            log("MutTechDirector: ClientCloseBooth - restored original HUD=" $ OriginalHUDClass $ " scoreboard=" $ OriginalScoreBoardClass);
        }
        else
        {
            log("MutTechDirector: ClientCloseBooth - FAILED to restore original HUD=" $ OriginalHUDClass);
        }
        OriginalHUDClass = None;
        OriginalScoreBoardClass = None;
    }

    if (DirectorInteractionRef != None)
    {
        DirectorInteractionRef.Cleanup();
        DirectorInteractionRef = None;
    }

    if (NotifyText != "")
        ClientNotify(NotifyText);
}

defaultproperties
{
    bAlwaysRelevant=False
    bOnlyRelevantToOwner=False
    RemoteRole=ROLE_SimulatedProxy
    NetUpdateFrequency=10.000000
    bAlwaysTick=True
    bStatic=False

    MaxCooldowns[0]=1.000000
    MaxCooldowns[1]=1.000000
    MaxCooldowns[2]=1.000000
    MaxCooldowns[3]=1.000000
    MaxCooldowns[4]=1.000000
    MaxCooldowns[5]=1.000000
    MaxCooldowns[6]=1.000000
    MaxCooldowns[7]=1.000000
    MaxCooldowns[8]=1.000000
}
