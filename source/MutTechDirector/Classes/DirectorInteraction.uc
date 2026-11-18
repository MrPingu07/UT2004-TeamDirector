//=============================================================================
// DirectorInteraction
//
// Client-side input and plain-text telemetry for MutTechDirector.
//
// This is a normal Engine.Interaction, not a HUD subclass.  It is created by
// DirectorReplicationInfo on the owning client and does two jobs:
//
//   1. consume the raw camera/drop keys while the booth is active, forwarding
//      requests to the server-authoritative RI
//   2. draw the plain-text hotbar (top-left), control cheatsheet (top-right),
//      a live TeamMates Alive/Dead counter (bottom-right) and always-visible
//      friendly nameplates with Canvas.DrawText in PostRender
//
// Zoom is local and intentional: the server never needs to know the camera
// distance, so keeping it in the Interaction avoids network traffic while
// still feeding the stock PlayerController.CalcBehindView() path through
// CameraDist every frame.
//=============================================================================
class DirectorInteraction extends Interaction;

var DirectorReplicationInfo RI;
var PlayerController PC;

/** Raw key state while the booth is active. */
var bool bZoomIn;
var bool bZoomOut;
var bool bHealHeld;

/** Current tactical camera distance in Unreal units (120 .. 1500). */
var float ZoomDistance;

/** Small debounce for clients that report the wheel as an axis. */
var float WheelCooldown;

/**
 * Original TeamBeacon* ranges of the director's PlayerController.  The booth
 * suppresses the native floating beacons (they are range-gated, carry no HP or
 * shield, and cannot be made always-visible from script) in favour of the
 * custom plates, so the user's values must be restored on teardown.
 */
var float SavedBeaconMaxDist;
var float SavedBeaconInfoMaxDist;
var bool bBeaconRangesSaved;

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

event Initialized()
{
    ZoomDistance = 420.0;
    WheelCooldown = 0.0;
}

function Cleanup()
{
    // Make the Interaction inert even if RemoveInteraction() cannot find it
    // (which happens when the Player/InteractionMaster survived a level
    // change but the array was rebuilt).
    bVisible = False;
    bActive = False;

    if (PC != None && !PC.bDeleteMe)
    {
        PC.CameraDistRange.Min = 3.0;
        PC.CameraDistRange.Max = 40.0;

        // Hand the native beacons back to the player on the way out.
        if (bBeaconRangesSaved)
        {
            PC.TeamBeaconMaxDist = SavedBeaconMaxDist;
            PC.TeamBeaconPlayerInfoMaxDist = SavedBeaconInfoMaxDist;
        }
    }
    bBeaconRangesSaved = False;

    if (Master != None)
        Master.RemoveInteraction(Self);

    RI = None;
    PC = None;
    Master = None;
}

/**
 * Player.LocalInteractions survives level travel.  Without this hook an old
 * DirectorInteraction keeps drawing the hotbar and consuming keys in the next
 * match, while its RI points at an actor from the previous level.
 */
event NotifyLevelChange()
{
    Cleanup();
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

function Tick(float DeltaTime)
{
    local float Radius;

    if (RI == None || RI.bDeleteMe)
    {
        Cleanup();
        return;
    }
    if (!RI.bDirectorActive)
        return;

    if (PC == None || PC.bDeleteMe)
        PC = RI.DirectorPC;
    if (PC == None || PC.bDeleteMe)
    {
        Cleanup();
        return;
    }

    // CalcBehindView() multiplies CameraDist by the target's default
    // CollisionRadius.  Widen the stock 3..40 clamp so 120..1500 world units
    // stays reachable even for small pawns.
    PC.CameraDistRange.Min = 1.0;
    PC.CameraDistRange.Max = 400.0;

    // Kill the native floating team beacons for this player only.  The engine
    // treats 0 as "off" (see PlayerController.SetBeaconVisibility), and our own
    // always-visible plates replace them.
    if (!bBeaconRangesSaved)
    {
        SavedBeaconMaxDist = PC.TeamBeaconMaxDist;
        SavedBeaconInfoMaxDist = PC.TeamBeaconPlayerInfoMaxDist;
        bBeaconRangesSaved = True;
    }
    PC.TeamBeaconMaxDist = 0.0;
    PC.TeamBeaconPlayerInfoMaxDist = 0.0;

    if (bZoomIn)
        ZoomDistance -= 950.0 * DeltaTime;
    if (bZoomOut)
        ZoomDistance += 950.0 * DeltaTime;

    ZoomDistance = FClamp(ZoomDistance, 120.0, 1500.0);

    Radius = 40.0;
    if (RI.CurrentTarget != None)
        Radius = FMax(1.0, RI.CurrentTarget.Default.CollisionRadius);

    PC.CameraDist = FClamp(ZoomDistance / Radius, 1.0, 400.0);

    if (RI.CurrentTarget != None)
        PC.bBehindView = True;
}

// ---------------------------------------------------------------------------
// Raw input
// ---------------------------------------------------------------------------

function bool KeyEvent(out EInputKey Key, out EInputAction Action, FLOAT Delta)
{
    if (RI == None || RI.bDeleteMe)
    {
        Cleanup();
        return False;
    }
    if (!RI.bDirectorActive)
        return False;

    if (PC == None || PC.bDeleteMe)
        PC = RI.DirectorPC;
    if (PC == None || PC.bDeleteMe)
    {
        Cleanup();
        return False;
    }

    if (Action == IST_Press)
    {
        switch (Key)
        {
            case IK_MouseWheelUp:
                RI.ServerCycleTarget(-1);
                return True;

            case IK_MouseWheelDown:
                RI.ServerCycleTarget(1);
                return True;

            case IK_1:
                RI.ServerUseAbility(1);
                return True;
            case IK_2:
                RI.ServerUseAbility(2);
                return True;
            case IK_3:
                RI.ServerUseAbility(3);
                return True;
            case IK_4:
                RI.ServerUseAbility(4);
                return True;
            case IK_5:
                RI.ServerUseAbility(5);
                return True;
            case IK_6:
                RI.ServerUseAbility(6);
                return True;
            case IK_7:
                RI.ServerUseAbility(7);
                return True;
            case IK_8:
                RI.ServerUseAbility(8);
                return True;
            case IK_9:
                RI.ServerUseAbility(9);
                return True;

            case IK_Space:
                if (!bHealHeld)
                {
                    bHealHeld = True;
                    RI.ServerSetHealing(True);
                }
                return True;

            case IK_LeftMouse:
                bZoomIn = True;
                return True;

            case IK_RightMouse:
                bZoomOut = True;
                return True;
        }
    }
    else if (Action == IST_Release)
    {
        switch (Key)
        {
            case IK_Space:
                if (bHealHeld)
                {
                    bHealHeld = False;
                    RI.ServerSetHealing(False);
                }
                return True;

            case IK_LeftMouse:
                bZoomIn = False;
                return True;

            case IK_RightMouse:
                bZoomOut = False;
                return True;
        }
    }
    else if (Action == IST_Axis && Key == IK_MouseW)
    {
        // Some input configurations deliver the wheel as an analog axis.
        if (PC != None && PC.Level.TimeSeconds >= WheelCooldown)
        {
            if (Delta > 0.0)
            {
                RI.ServerCycleTarget(-1);
                WheelCooldown = PC.Level.TimeSeconds + 0.15;
                return True;
            }
            if (Delta < 0.0)
            {
                RI.ServerCycleTarget(1);
                WheelCooldown = PC.Level.TimeSeconds + 0.15;
                return True;
            }
        }
    }

    return False;
}

// ---------------------------------------------------------------------------
// Plain-text telemetry
// ---------------------------------------------------------------------------

function PostRender(Canvas C)
{
    local color Green;
    local color Cyan;
    local color White;
    local color Dim;
    local color TeamColor;
    local color PlateColor;
    local float LineH;
    local float XL;
    local float YL;
    local float X;
    local float Y;
    local int i;
    local int TeamTotal;
    local float RatioA;
    local float RatioD;
    local string NameText;
    local string Status;
    local color StatusColor;
    local string L1;
    local string L2;
    local string L3;
    local string L4;
    local string L5;
    local array<Pawn> Pawns;
    local Pawn P;
    local Vehicle V;
    local Vehicle CheckV;
    local Pawn DriverP;
    local bool bIsSentry;
    local bool bHasDriver;
    local bool bIsHighlighted;
    local int NumLines;
    local vector Head;
    local vector Screen;
    local vector CamLoc;
    local rotator CamRot;
    local string DisplayName;
    local string PlateText;

    // Two-pass rendering: first pass collects data, second pass draws
    // highlighted on top of non-highlighted
    local array<Pawn> HighlightedPawns;
    local array<Pawn> NormalPawns;
    local int Pass;

    if (RI == None || RI.bDeleteMe)
    {
        Cleanup();
        return;
    }
    if (!RI.bDirectorActive)
        return;

    if (PC == None || PC.bDeleteMe)
        PC = RI.DirectorPC;
    if (PC == None || PC.bDeleteMe)
    {
        Cleanup();
        return;
    }

    Green.R = 70;  Green.G = 255;  Green.B = 110; Green.A = 255;
    Cyan.R = 60;   Cyan.G = 230;  Cyan.B = 255; Cyan.A = 255;
    White.R = 235; White.G = 240; White.B = 250; White.A = 255;
    Dim.R = 165;   Dim.G = 175;   Dim.B = 185;  Dim.A = 255;

    if (C.SmallFont != None)
        C.Font = C.SmallFont;
    C.FontScaleX = 1.0;
    C.FontScaleY = 1.0;

    C.StrLen("Mg", XL, YL);
    if (YL < 10.0)
        YL = 12.0;
    LineH = YL + 2.0;

    // -- top-left: transmat logistics hotbar -------------------------------
    X = 24.0;
    Y = 24.0;

    DrawLine(C, X, Y, "[TECHNICAL DIRECTOR LOGISTICS]", White);
    Y += LineH;

    NameText = "[Jump] Nanite Med-Surge";
    Status = "[HOLD]";
    StatusColor = Dim;
    if (RI.bHealing)
    {
        Status = "[BEAM]";
        StatusColor = Green;
    }
    DrawLine(C, X, Y, NameText, White);
    C.StrLen(NameText, XL, YL);
    DrawLine(C, X + XL + 10.0, Y, Status, StatusColor);
    Y += LineH;

    for (i = 1; i <= 9; i++)
    {
        NameText = "[" $ i $ "] " $ SlotName(i);
        Status = SlotStatus(i);
        StatusColor = SlotColor(i);

        DrawLine(C, X, Y, NameText, White);
        C.StrLen(NameText, XL, YL);
        DrawLine(C, X + XL + 10.0, Y, Status, StatusColor);
        Y += LineH;
    }

    // -- top-right: booth controls cheatsheet ------------------------------
    L1 = "[Wheel] Cycle Fighter Feed";
    L2 = "[Hold Fire/AltFire] Zoom Cam";
    L3 = "[Hold Jump] Heal";
    L4 = "[1-9] Transmat Drop";
    L5 = "[B] Toggle Booth";

    DrawLine(C, C.ClipX - 24.0 - TextWidth(C, L1), 24.0, L1, Dim);
    DrawLine(C, C.ClipX - 24.0 - TextWidth(C, L2), 24.0 + LineH, L2, Dim);
    DrawLine(C, C.ClipX - 24.0 - TextWidth(C, L3), 24.0 + (2.0 * LineH), L3, Dim);
    DrawLine(C, C.ClipX - 24.0 - TextWidth(C, L4), 24.0 + (3.0 * LineH), L4, Dim);
    DrawLine(C, C.ClipX - 24.0 - TextWidth(C, L5), 24.0 + (4.0 * LineH), L5, Dim);

    // -- lower-right: live TeamMates roster counter ------------------------
    // Keeps the old cheatsheet uplift so the block clears the chat area and
    // the "Now spectating..." banner drawn along the bottom of the screen.
    TeamTotal = RI.TeamAlive + RI.TeamDead;
    StatusColor = Dim;
    PlateColor = Dim;
    if (TeamTotal > 0)
    {
        RatioA = float(RI.TeamAlive) / float(TeamTotal);
        RatioD = float(RI.TeamDead) / float(TeamTotal);

        // Alive: good when high.  Dead is the mirror image of the same scale,
        // so a healthy roster reads green on both lines and a wiped one red.
        StatusColor = RatioColor(RatioA);
        PlateColor = RatioColor(1.0 - RatioD);
    }

    DrawLine(C, C.ClipX - 24.0 - TextWidth(C, "TeamMates"),
        C.ClipY - 14.0 - (8.0 * LineH), "TeamMates", Cyan);
    NameText = "Alive: " $ RI.TeamAlive;
    DrawLine(C, C.ClipX - 24.0 - TextWidth(C, NameText),
        C.ClipY - 14.0 - (7.0 * LineH), NameText, StatusColor);

    NameText = "Dead: " $ RI.TeamDead;
    DrawLine(C, C.ClipX - 24.0 - TextWidth(C, NameText),
        C.ClipY - 14.0 - (6.0 * LineH), NameText, PlateColor);

    // -- always-visible friendly nameplates / vehicle beacons ------------------
    // No FastTrace / occlusion test: the booth sees the whole arena through
    // the broadcast feed, exactly as requested.
    C.GetCameraLocation(CamLoc, CamRot);
    RI.GetFriendlyPawns(Pawns);

    // First pass: collect valid pawns into highlighted/normal arrays
    HighlightedPawns.Length = 0;
    NormalPawns.Length = 0;

    for (i = 0; i < Pawns.Length; i++)
    {
        P = Pawns[i];
        if (P == None || P.Health <= 0)
            continue;

        // Skip driver pawns that are inside vehicles (they're hidden, we draw the vehicle instead)
        if (P.DrivenVehicle != None)
            continue;

        Head = P.Location + vect(0,0,60);

        // Skip anything behind the camera.
        if ((Head - CamLoc) Dot vector(CamRot) <= 0.0)
            continue;

        Screen = C.WorldToScreen(Head);
        if (Screen.X < 0.0 || Screen.X > C.ClipX ||
            Screen.Y < 0.0 || Screen.Y > C.ClipY)
            continue;

        // Determine display name and drawing style based on pawn type:
        // - Player (on foot): 3 lines (Name / HP / Shield)
        // - Vehicle with driver: 3 lines (DriverName / HP / Shield)
        // - Sentry (DirectorSentinel): 2 lines (Sentry / HP [X/X])
        // - Other vehicle (empty): 2 lines (VehicleName / HP [X/X])

        V = Vehicle(P);
        bIsSentry = (DirectorSentinel(P) != None);

        if (V != None)
        {
            DriverP = V.Driver;
            bHasDriver = (DriverP != None);

            if (bHasDriver)
            {
                // Fallback chain for vehicle drivers:
                // 1. Driver pawn's PRI (usually None when in vehicle - UnPossessed clears it)
                // 2. Driver pawn's Controller's PRI (usually None - controller possesses vehicle)
                // 3. Driver pawn's DrivenVehicle PRI (vehicle gets controller's PRI when possessed)
                // 4. Driver pawn's Name (fallback to class name like "2k4xPawn")
                if (DriverP.PlayerReplicationInfo != None)
                    DisplayName = DriverP.PlayerReplicationInfo.PlayerName;
                else if (DriverP.Controller != None && DriverP.Controller.PlayerReplicationInfo != None)
                    DisplayName = DriverP.Controller.PlayerReplicationInfo.PlayerName;
                else if (DriverP.DrivenVehicle != None && DriverP.DrivenVehicle.PlayerReplicationInfo != None)
                    DisplayName = DriverP.DrivenVehicle.PlayerReplicationInfo.PlayerName;
                else
                    DisplayName = string(DriverP.Name);
                NumLines = 3;  // DriverName / HP / Shield
            }
            else if (bIsSentry)
            {
                // Sentinels are never drivable, always show
                DisplayName = "Sentry";
                NumLines = 2;  // Sentry / HP [X/X]
            }
            else
            {
                // Empty non-sentry vehicle - hide it entirely
                continue;
            }
        }
        else
        {
            // Player on foot
            bHasDriver = False;
            if (P.PlayerReplicationInfo != None)
                DisplayName = P.PlayerReplicationInfo.PlayerName;
            else if (P.Controller != None && P.Controller.PlayerReplicationInfo != None)
                DisplayName = P.Controller.PlayerReplicationInfo.PlayerName;
            else
                DisplayName = string(P.Name);
            NumLines = 3;  // Name / HP / Shield
        }

        // Check if this pawn (or its driver, if vehicle) is the current target
        CheckV = Vehicle(P);
        if (CheckV != None && CheckV.Driver != None)
        {
            bIsHighlighted = (CheckV.Driver == RI.CurrentTarget);
        }
        else
        {
            bIsHighlighted = (P == RI.CurrentTarget);
        }

        // Team colours.  Red team is the warm palette, blue team the cool one;
        // the fighter currently on the broadcast feed uses the brighter
        // "selected" variant of its team colour.
        if (P.GetTeamNum() == 0)
        {
            TeamColor.R = 255; TeamColor.G = 0;   TeamColor.B = 0;   TeamColor.A = 255;
            if (bIsHighlighted)
            {
                TeamColor.R = 255; TeamColor.G = 153; TeamColor.B = 51;
            }
        }
        else
        {
            TeamColor.R = 51;  TeamColor.G = 102; TeamColor.B = 255; TeamColor.A = 255;
            if (bIsHighlighted)
            {
                TeamColor.R = 51;  TeamColor.G = 204; TeamColor.B = 255;
            }
        }

        // Store pawn data for two-pass rendering
        if (bIsHighlighted)
            HighlightedPawns[HighlightedPawns.Length] = P;
        else
            NormalPawns[NormalPawns.Length] = P;
    }

    // Second pass: draw normal first, then highlighted on top
    for (Pass = 0; Pass < 2; Pass++)
    {
        if (Pass == 0)
        {
            for (i = 0; i < NormalPawns.Length; i++)
            {
                P = NormalPawns[i];
            }
        }
        else
        {
            for (i = 0; i < HighlightedPawns.Length; i++)
            {
                P = HighlightedPawns[i];
            if (P == None)
                continue;

            Head = P.Location + vect(0,0,60);

            // Skip anything behind the camera.
            if ((Head - CamLoc) Dot vector(CamRot) <= 0.0)
                continue;

            Screen = C.WorldToScreen(Head);
            if (Screen.X < 0.0 || Screen.X > C.ClipX ||
                Screen.Y < 0.0 || Screen.Y > C.ClipY)
                continue;

            // Determine NumLines for this pawn
            V = Vehicle(P);
            bIsSentry = (DirectorSentinel(P) != None);

            if (V != None)
            {
                DriverP = V.Driver;
                bHasDriver = (DriverP != None);
                if (bHasDriver)
                    NumLines = 3;
                else if (bIsSentry)
                    NumLines = 2;
                else
                    continue; // empty non-sentry - skip
            }
            else
            {
                NumLines = 3; // Player on foot
            }

            // Check highlight again (CurrentTarget might have changed since first pass)
            CheckV = Vehicle(P);
            if (CheckV != None && CheckV.Driver != None)
            {
                bIsHighlighted = (CheckV.Driver == RI.CurrentTarget);
            }
            else
            {
                bIsHighlighted = (P == RI.CurrentTarget);
            }

            // Team colours
            if (P.GetTeamNum() == 0)
            {
                TeamColor.R = 255; TeamColor.G = 0;   TeamColor.B = 0;   TeamColor.A = 255;
                if (bIsHighlighted)
                {
                    TeamColor.R = 255; TeamColor.G = 153; TeamColor.B = 51;
                }
            }
            else
            {
                TeamColor.R = 51;  TeamColor.G = 102; TeamColor.B = 255; TeamColor.A = 255;
                if (bIsHighlighted)
                {
                    TeamColor.R = 51;  TeamColor.G = 204; TeamColor.B = 255;
                }
            }

            // Draw based on type - with screen bounds check to prevent wrapping
            if (NumLines == 3)
            {
                // 3 lines: Name / HP / Shield
                PlateText = DisplayName;
                C.StrLen(PlateText, XL, YL);
                if (Screen.X - XL * 0.5 >= 0.0 && Screen.X + XL * 0.5 <= C.ClipX)
                    DrawLine(C, Screen.X - XL * 0.5, Screen.Y - 3.0 * LineH, PlateText, TeamColor);

                PlateText = "HP [" $ P.Health $ "]";
                C.StrLen(PlateText, XL, YL);
                if (Screen.X - XL * 0.5 >= 0.0 && Screen.X + XL * 0.5 <= C.ClipX)
                    DrawLine(C, Screen.X - XL * 0.5, Screen.Y - 2.0 * LineH, PlateText, TeamColor);

                PlateText = "Shield [" $ int(P.ShieldStrength) $ "]";
                C.StrLen(PlateText, XL, YL);
                if (Screen.X - XL * 0.5 >= 0.0 && Screen.X + XL * 0.5 <= C.ClipX)
                    DrawLine(C, Screen.X - XL * 0.5, Screen.Y - LineH, PlateText, TeamColor);
            }
            else
            {
                // 2 lines: Sentry/VehicleName / HP [X/X]
                PlateText = DisplayName;
                C.StrLen(PlateText, XL, YL);
                if (Screen.X - XL * 0.5 >= 0.0 && Screen.X + XL * 0.5 <= C.ClipX)
                    DrawLine(C, Screen.X - XL * 0.5, Screen.Y - 2.0 * LineH, PlateText, TeamColor);

                PlateText = "HP [" $ P.Health $ "/" $ int(P.HealthMax) $ "]";
                C.StrLen(PlateText, XL, YL);
                if (Screen.X - XL * 0.5 >= 0.0 && Screen.X + XL * 0.5 <= C.ClipX)
                    DrawLine(C, Screen.X - XL * 0.5, Screen.Y - LineH, PlateText, TeamColor);
            }
        }
    }
    }
    }

// ---------------------------------------------------------------------------
// Hotbar helpers
// ---------------------------------------------------------------------------

function string SlotName(int Slot)
{
    switch (Slot)
    {
        case 1: return "Ammunition Requisition";
        case 2: return "Perimeter Defense";
        case 3: return "Painkillers";
        case 4: return "Blindage";
        case 5: return "Stimuli Dose";
        case 6: return "SPMA Artillery";
        case 7: return "Light Vehicle Transmat";
        case 8: return "Heavy Asset Drop";
        case 9: return "Emergency Recall";
    }
    return "";
}

function string SlotStatus(int Slot)
{
    local float Left;

    Left = RI.GetCooldown(Slot);
    if (Left <= 0.01)
        return "[READY]";

    return "[" $ int(Left + 0.999) $ "s]";
}

function color SlotColor(int Slot)
{
    local color Green;
    local color Yellow;
    local color Red;
    local float Left;
    local float Max;

    Green.R = 70;  Green.G = 255;  Green.B = 110; Green.A = 255;
    Yellow.R = 255; Yellow.G = 220; Yellow.B = 60; Yellow.A = 255;
    Red.R = 255;   Red.G = 72;    Red.B = 72;   Red.A = 255;

    Left = RI.GetCooldown(Slot);
    if (Left <= 0.01)
        return Green;

    Max = RI.GetMaxCooldown(Slot);
    if (Max <= 0.0 || Left > Max * 0.5)
        return Red;

    return Yellow;
}

function DrawLine(Canvas C, float X, float Y, string S, color Col)
{
    C.DrawColor = Col;
    C.SetPos(X, Y);
    C.DrawText(S);
}

/** Width of S in the Canvas' current font, for right-aligned drawing. */
function float TextWidth(Canvas C, string S)
{
    local float XL;
    local float YL;

    C.StrLen(S, XL, YL);
    return XL;
}

/**
 * Shared band scale used by the TeamMates counter.
 *   0-25%  red     (bad)
 *   25-50% yellow
 *   50-75% orange
 *   75-100% green  (good)
 * "Dead" feeds 1 - ratio through the same scale, which inverts it.
 */
function color RatioColor(float R)
{
    local color Col;

    Col.A = 255;

    if (R <= 0.25)
    {
        Col.R = 255; Col.G = 72;  Col.B = 72;
    }
    else if (R <= 0.50)
    {
        Col.R = 255; Col.G = 220; Col.B = 60;
    }
    else if (R <= 0.75)
    {
        Col.R = 255; Col.G = 140; Col.B = 40;
    }
    else
    {
        Col.R = 70;  Col.G = 255; Col.B = 110;
    }

    return Col;
}

defaultproperties
{
    bVisible=True
    bActive=True
    bRequiresTick=True
    ZoomDistance=420.000000
}
