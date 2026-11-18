//=============================================================================
// DirectorHUD
//
// Purpose-built HUD for the Technical Director booth.  Replaces the stock
// XInterface.HudBase while the Director is in the booth so that native C++
// vehicle name drawing AND native team beacon drawing (which cannot be
// suppressed from UnrealScript otherwise) are completely disabled.
// All Director telemetry (hotbar, cheatsheet, TeamMates counter,
// friendly nameplates and turret beacons) continues to be drawn by
// DirectorInteraction.PostRender; this HUD simply provides a clean canvas.
//=============================================================================
class DirectorHUD extends XInterface.HudBase;

const FLICKER_STEP = 0.1666667;
const BLINK_INTERVAL = 0.5;
const TOTAL_CYCLE = 22.0;

var transient float CycleStart;
var transient float LastDrawTime;
var transient string CurrentMessage;
var transient array<int> FeedBag;

/**
 * Override the native vehicle name drawing.  This is the entire point of
 * this HUD: the stock HudBase.DrawVehicleName is called from native C++
 * code during the spectator overlay pass and draws the vehicle's class name
 * (e.g. "DirectorSentinel") above every vehicle.  By overriding it to do
 * nothing, we eliminate the forced vehicle names entirely.
 */
simulated function DrawVehicleName(Canvas C)
{
    // Intentionally empty: suppress all native vehicle name rendering.
    // DirectorInteraction.PostRender draws our custom Sentinel(n) / HP [X/X]
    // beacons for both the Director and combatants.
}

/**
 * Override the native team beacon drawing.  This is called from
 * Pawn.PostRender2D() for every pawn with bScriptPostRender=true
 * (including vehicles/sentinels).  The engine calls:
 *   PC.myHUD.DrawCustomBeacon(Canvas, Pawn, ScreenX, ScreenY)
 * which draws the beacon texture + name/health text.  We override it to
 * do nothing so the Director sees only our custom nameplates/beacons
 * drawn by DirectorInteraction.PostRender.
 */
simulated function DrawCustomBeacon(Canvas C, Pawn P, float ScreenLocX, float ScreenLocY)
{
    // Intentionally empty: suppress ALL native team beacon rendering.
    // DirectorInteraction.PostRender draws:
    //   - Three-line friendly nameplates (Name / HP / Shield) for players
    //   - Two-line turret beacons (Sentinel(n) / HP [X/X]) for sentinels
    // All through Canvas.DrawText with full control over position and style.
    // Log to verify this is being called (or not, if bNoTeamBeacon works).
    log("MutTechDirector: [DIR-HUD] DrawCustomBeacon called for " $ P $ " - SUPPRESSED");
}

/**
 * Override the main HUD drawing function to restore vanilla HUD elements
 * (flag/score counters, F1 match summary, chat feed) while keeping our
 * custom beacon/nameplate drawing in DirectorInteraction.PostRender.
 */
simulated function DrawHud(Canvas C)
{
    // Call Super to restore vanilla HUD elements:
    // - Flag/score counters at top
    // - F1 match summary
    // - Crosshair, weapon info, etc.
    // Our custom elements (hotbar, cheatsheet, TeamMates counter, nameplates)
    // are drawn by DirectorInteraction.PostRender separately.
    Super.DrawHud(C);
}

/**
 * Override the crosshair drawing.  The Director's feed is a clean
 * broadcast camera with no crosshair.
 */
simulated function DrawCrosshair(Canvas C)
{
    // Intentionally empty.
}

/**
 * Override the message drawing.  DirectorNotify handles booth notifications
 * separately via LocalMessage.
 */
simulated function DrawMessage(Canvas C, int i, float PosX, float PosY, out float DX, out float DY)
{
    // Intentionally empty.
}

/**
 * Returns the current phase (0-9) and its start time for a given cycle time T.
 * Phases: 0=flicker(0-1), 1=blink(1-2), 2=type(2-3), 3=blink(3-6), 4=hold(6-11),
 *         5=flicker(11-12), 6=blink(12-13), 7=delete(13-14), 8=blink(14-17), 9=rest(17-22).
 */
simulated function GetPhaseInfo(float T, out int Phase, out float PhaseStart)
{
    if (T < 1.0)       { Phase = 0; PhaseStart = 0.0;  }
    else if (T < 2.0)  { Phase = 1; PhaseStart = 1.0;  }
    else if (T < 3.0)  { Phase = 2; PhaseStart = 2.0;  }
    else if (T < 6.0)  { Phase = 3; PhaseStart = 3.0;  }
    else if (T < 11.0) { Phase = 4; PhaseStart = 6.0;  }
    else if (T < 12.0) { Phase = 5; PhaseStart = 11.0; }
    else if (T < 13.0) { Phase = 6; PhaseStart = 12.0; }
    else if (T < 14.0) { Phase = 7; PhaseStart = 13.0; }
    else if (T < 17.0) { Phase = 8; PhaseStart = 14.0; }
    else               { Phase = 9; PhaseStart = 17.0; }
}

/**
 * Returns whether the cursor should be visible at the given phase time.
 * FLICKER phases (0,5): 3 blinks in 1s ending OFF (step 1/6s, starts ON).
 * BLINK phases (1,3,6,8): toggles every 0.5s, starts ON.
 * TYPE/DELETE phases (2,7): always ON.
 * HOLD/REST phases (4,9): always OFF.
 */
simulated function bool GetCursorVisible(float PhaseTime, int Phase)
{
    if (Phase == 0 || Phase == 5)
        return (int(PhaseTime / FLICKER_STEP) % 2) == 0;
    if (Phase == 1 || Phase == 3 || Phase == 6 || Phase == 8)
        return (int(PhaseTime / BLINK_INTERVAL) % 2) == 0;
    if (Phase == 2 || Phase == 7)
        return true;
    return false;
}

/**
 * Picks a message from the config-backed shuffle bag (DirectorFeed).
 * No message repeats until all have been shown. Skips empty or too-wide messages.
 */
simulated function string PickMessage(Canvas C)
{
    local int n, i, j, tmp, Tries;
    local string Msg;
    local float W, H;

    C.Font = C.MedFont;
    n = class'DirectorFeed'.default.Messages.Length;
    if (n == 0)
        return "TECHNICAL DIRECTOR MODE";

    for (Tries = 0; Tries < n; Tries++)
    {
        if (FeedBag.Length == 0)
        {
            FeedBag.Length = n;
            for (i = 0; i < n; i++)
                FeedBag[i] = i;
            for (i = n - 1; i > 0; i--)
            {
                j = Rand(i + 1);
                tmp = FeedBag[i];
                FeedBag[i] = FeedBag[j];
                FeedBag[j] = tmp;
            }
        }
        i = FeedBag[FeedBag.Length - 1];
        FeedBag.Length = FeedBag.Length - 1;
        Msg = class'DirectorFeed'.default.Messages[i];
        C.StrLen(Msg, W, H);
        if (Msg != "" && W <= C.ClipX * 0.9)
            return Msg;
    }
    return "TECHNICAL DIRECTOR MODE";
}

/**
 * Custom spectator banner replacing the native "Now Viewing..." banner.
 * Draws a custom banner at the bottom with:
 * - Unreal "U" logo at left margin
 * - Dark transparent horizontal band spanning screen width
 * - Team-colored stripes at top and bottom edges
 * - Custom scrolling text area (3x larger) in the middle with native clipping
 * Chat feed is drawn first via DisplayLocalMessages at its native position.
 */
simulated function DrawSpectatingHud(Canvas C)
{
    local float BannerHeight;
    local float BannerY;
    local float BannerX;
    local float BannerWidth;
    local float StripeWidth;
    local float LogoSize;
    local float LogoX;
    local float LogoY;
    local color TeamColor;
    local color StripeColor;
    local float TextYPos;
    local int TeamNum;
    local Pawn TargetPawn;
    local PlayerReplicationInfo TargetPRI;

    // Typewriter + cursor locals
    local float CycleElapsed, PhaseStart, PhaseTime;
    local int Phase, L, Shown, Start;
    local float FullWidth, AnchorX, SliceX, CursorX, PH, Dummy;
    local bool CursorVisible;
    local byte OldStyle;

    // Team score counter locals
    local GameReplicationInfo GRI;
    local string RedScore, BlueScore;
    local float RedW, BlueW, DashW, TLogoSize, TLogoY, TScoreY, TGap, TTotalW, TStartX;
    local HUD MyHUD;
    
    // First, draw the native chat feed at its native position (bottom of screen)
    DisplayLocalMessages(C);
    
    // Don't draw our custom banner if no valid target or not spectating a teammate
    if (PlayerOwner == None || PlayerOwner.ViewTarget == None)
        return;
    
    TargetPawn = Pawn(PlayerOwner.ViewTarget);
    if (TargetPawn == None || TargetPawn.Health <= 0)
        return;
    
    TargetPRI = TargetPawn.PlayerReplicationInfo;
    if (TargetPRI == None)
        return;
    
    TeamNum = TargetPawn.GetTeamNum();
    
    // Team color for stripes and text
    if (TeamNum == 0)
    {
        // Red team
        StripeColor.R = 255; StripeColor.G = 0;   StripeColor.B = 0;   StripeColor.A = 255;
        TeamColor.R = 255; TeamColor.G = 100; TeamColor.B = 100; TeamColor.A = 255;
    }
    else
    {
        // Blue team
        StripeColor.R = 51;  StripeColor.G = 102; StripeColor.B = 255; StripeColor.A = 255;
        TeamColor.R = 100; TeamColor.G = 150; TeamColor.B = 255; TeamColor.A = 255;
    }
    
    // Banner dimensions (80px fixed height)
    BannerHeight = 80.0;
    BannerY = C.ClipY - BannerHeight;
    BannerX = 0.0;
    BannerWidth = C.ClipX;
    
    // Dark transparent band (80% opacity black)
    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(0, 0, 0, 204);
    C.SetPos(0, BannerY);
    C.DrawTileStretched(material'InterfaceContent.SquareBoxA', C.ClipX, BannerHeight);
    C.Style = ERenderStyle.STY_Normal;
    
    // Team-colored stripes at top and bottom of banner (3px each)
    StripeWidth = 3.0;
    C.SetDrawColor(StripeColor.R, StripeColor.G, StripeColor.B, 255);
    C.SetPos(0, BannerY);
    C.DrawTileStretched(material'InterfaceContent.SquareBoxA', C.ClipX, 3.0);
    C.SetPos(0, BannerY + BannerHeight - 3.0);
    C.DrawTileStretched(material'InterfaceContent.SquareBoxA', C.ClipX, 3.0);
    
    // Stock spectator HUD logo (LastManStanding.LMSLogoSmall) at left, scaled to banner
    // Matches HudBDeathMatch/HudCDeathmatch: logo height = BannerHeight + 16, drawn 8px above banner top
    LogoSize = BannerHeight + 16.0;  // 96px for 80px banner
    LogoX = 0.0;
    LogoY = BannerY - 8.0;
    
    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(255, 255, 255, 255);
    C.SetPos(LogoX, LogoY);
    C.DrawTile(
        material'LastManStanding.LMSLogoSmall',
        LogoSize * 2.0,  // width = 2 * height (256/128 aspect)
        LogoSize,
        0, 0,
        256, 128
    );
    C.Style = ERenderStyle.STY_Normal;
    
    // Team score counter at top center (hidden during F1)
    MyHUD = PlayerOwner.myHUD;
    if (PlayerOwner != None && MyHUD != None && !MyHUD.bShowScoreBoard)
    {
        GRI = PlayerOwner.GameReplicationInfo;
        if (GRI != None && ArrayCount(GRI.Teams) >= 2)
        {
            RedScore = "$" $ GRI.Teams[0].Score;
            BlueScore = "$" $ GRI.Teams[1].Score;
            
            C.Font = C.MedFont;
            C.StrLen(RedScore, RedW, PH);
            C.StrLen(BlueScore, BlueW, PH);
            C.StrLen(" - ", DashW, PH);
            
            // Team logos from InterfaceContent.HUD.SkinA (same as stock HUD)
            // Red logo: U=979..611, V=900..1023 (flipped horizontally)
            // Blue logo: U=611..979, V=900..1023
            TLogoSize = 32.0;
            TLogoY = 16.0;
            TScoreY = TLogoY + (TLogoSize - PH) * 0.5;
            TGap = 16.0;
            
            // Total width: red logo + gap + red score + dash + blue score + gap + blue logo
            TTotalW = TLogoSize * 2.0 + TGap * 4.0 + RedW + DashW + BlueW;
            TStartX = (C.ClipX - TTotalW) * 0.5;
            
            // Red team logo (left)
            C.Style = ERenderStyle.STY_Alpha;
            C.SetDrawColor(255, 255, 255, 255);
            C.SetPos(TStartX, TLogoY);
            C.DrawTile(
                Texture'InterfaceContent.HUD.SkinA',
                TLogoSize, TLogoSize,
                979, 900,
                611 - 979, 1023 - 900  // negative U = flipped
            );
            
            // Red score
            C.SetDrawColor(255, 80, 80, 255);
            C.SetPos(TStartX + TLogoSize + TGap, TScoreY);
            C.DrawText(RedScore);
            
            // Dash
            C.SetDrawColor(255, 255, 255, 255);
            C.SetPos(TStartX + TLogoSize + TGap + RedW + TGap, TScoreY);
            C.DrawText(" - ");
            
            // Blue score
            C.SetDrawColor(100, 150, 255, 255);
            C.SetPos(TStartX + TLogoSize + TGap + RedW + TGap + DashW + TGap, TScoreY);
            C.DrawText(BlueScore);
            
            // Blue team logo (right)
            C.SetPos(TStartX + TTotalW - TLogoSize, TLogoY);
            C.DrawTile(
                Texture'InterfaceContent.HUD.SkinA',
                TLogoSize, TLogoSize,
                611, 900,
                979 - 611, 1023 - 900
            );
            C.Style = ERenderStyle.STY_Normal;
        }
    }
    
    // Typewriter + blinking cursor banner (centered, no horizontal motion)

    // Center text vertically in banner
    C.Font = C.MedFont;
    C.StrLen("X", Dummy, PH);  // PH = line height for MedFont
    TextYPos = BannerY + (BannerHeight - PH) * 0.5;

    CycleElapsed = Level.TimeSeconds - CycleStart;
    if (CurrentMessage == "" || CycleElapsed >= TOTAL_CYCLE
        || Level.TimeSeconds - LastDrawTime > 0.5)
    {
        CycleStart = Level.TimeSeconds;
        CurrentMessage = PickMessage(C);
    }
    LastDrawTime = Level.TimeSeconds;
    CycleElapsed = Level.TimeSeconds - CycleStart;

    GetPhaseInfo(CycleElapsed, Phase, PhaseStart);
    PhaseTime = FMax(0.0, CycleElapsed - PhaseStart);
    CursorVisible = GetCursorVisible(PhaseTime, Phase);

    C.Font = C.MedFont;
    C.StrLen(CurrentMessage, FullWidth, PH);
    AnchorX = (C.ClipX - FullWidth) * 0.5;
    L = Len(CurrentMessage);

    if (Phase == 2)
        Shown = Min(L, int(PhaseTime * L));
    else if (Phase == 7)
        Shown = L - Min(L, int(PhaseTime * L));
    else if (Phase >= 3 && Phase <= 6)
        Shown = L;
    else
        Shown = 0;
    Start = (L - Shown) / 2;

    if (Shown > 0)
    {
        C.StrLen(Left(CurrentMessage, Start), SliceX, Dummy);
        SliceX += AnchorX;
        C.SetDrawColor(TeamColor.R, TeamColor.G, TeamColor.B, 255);
        C.SetPos(SliceX, TextYPos);
        C.DrawText(Mid(CurrentMessage, Start, Shown), false);
    }

    if (CursorVisible)
    {
        C.StrLen(Left(CurrentMessage, Start + Shown), CursorX, Dummy);
        CursorX += AnchorX;
        OldStyle = C.Style;
        C.Style = ERenderStyle.STY_Alpha;
        C.SetDrawColor(TeamColor.R, TeamColor.G, TeamColor.B, 255);
        C.SetPos(CursorX, TextYPos);
        C.DrawTileStretched(material'InterfaceContent.SquareBoxA', 8.0, PH);
        C.Style = OldStyle;
    }

}
defaultproperties
{
    bShowScores=False
    bShowStats=False
    bShowWeaponInfo=False
    bShowCrosshair=False
    bShowRadar=False
    bShowVehicleNames=False  // Redundant with DrawVehicleName override, but explicit
    // Match HudBDeathMatch so console chat (DisplayMessages) sits above the banner
    ConsoleMessagePosX=0.005000
    // Align chat bottom (last message) with TeamMates counter Dead line (ClipY - 14 - 6*LineH)
    ConsoleMessagePosY=0.910000
}