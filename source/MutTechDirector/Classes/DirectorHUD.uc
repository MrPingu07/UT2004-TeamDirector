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
 * Override the main HUD drawing function to prevent the stock HUD from
 * drawing anything we don't want (crosshair, spectated player info, etc.).
 * DirectorInteraction handles all Director-specific drawing via its own
 * PostRender (which runs separately from the HUD's DrawHud).
 */
simulated function DrawHud(Canvas C)
{
    // Intentionally empty: we want a completely clean slate.
    // The DirectorInteraction attached to the DirectorPC will draw:
    //   - Top-left hotbar
    //   - Top-right cheatsheet
    //   - Bottom-right TeamMates counter
    //   - Friendly nameplates (Name / HP / Shield)
    //   - Turret beacons (Sentinel(n) / HP [X/X])
    // All through Canvas.DrawText with full control over position and style.
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
 * Custom spectator banner replacing the native "Now Viewing..." banner.
 * Draws a custom banner at the bottom with:
 * - UT2004 logo (front layer)
 * - Dark transparent horizontal band spanning screen width
 * - Team-colored stripes at top and bottom edges
 * - Custom scrolling text area in the middle
 */
simulated function DrawSpectatingHud(Canvas C)
{
    local float BannerHeight;
    local float BannerY;
    local float StripeWidth;
    local float LogoSize;
    local float LogoX;
    local float LogoY;
    local color TeamColor;
    local color BandColor;
    local color StripeColor;
    local string ScrollText;
    local float TextX;
    local float TextYPos;
    local float TextWidth;
    local float TextHeight;
    local float ScrollSpeed;
    local float ScrollOffset;
    local int TeamNum;
    local string TeamName;
    local Pawn TargetPawn;
    local PlayerReplicationInfo TargetPRI;
    local float TextY;
    
    // Don't draw if no valid target or not spectating a teammate
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
    
    // Banner dimensions
    BannerHeight = 80.0;
    BannerY = C.ClipY - BannerHeight;
    
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
    
    // UT2004 logo (centered, front layer)
    LogoSize = 64.0;
    LogoX = (C.ClipX - 64.0) * 0.5;
    LogoY = BannerY + (80.0 - 64.0) * 0.5;
    
    // Draw logo
    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(255, 255, 255, 255);
    C.SetPos(LogoX, LogoY);
    C.DrawTile(
        Texture'InterfaceContent.Logos.Logo',
        64.0, 64.0,
        0, 0,
        256, 256
    );
    C.Style = ERenderStyle.STY_Normal;
    
    // Custom scrolling text area
    if (TeamNum == 0)
        TeamName = "RED";
    else
        TeamName = "BLUE";
    ScrollText = "TECHNICAL DIRECTOR MODE  |  SPECTATING: " $ TargetPRI.PlayerName $ "  |  TEAM: " $ TeamName $ "  |  PRESS [B] TO EXIT BOOTH";
    
    // Scrolling text animation
    C.Font = C.SmallFont;
    C.StrLen(ScrollText, TextWidth, TextHeight);
    
    TextX = C.ClipX - (Level.TimeSeconds * 80.0 % (TextWidth + C.ClipX));
    TextYPos = BannerY + (BannerHeight - TextHeight) * 0.5;
    
    // Draw scrolling text (clipped to banner area)
    // Only draw when text is fully within screen bounds to prevent wrapping
    C.SetDrawColor(TeamColor.R, TeamColor.G, TeamColor.B, 255);
    
    // Only draw when text is fully within screen bounds (prevents wrapping)
    if (TextX >= 0 && TextX + TextWidth <= C.ClipX)
    {
        C.SetPos(TextX, TextYPos);
        C.DrawText(ScrollText, false);
    }
    
    // Draw second copy for seamless looping - only when fully in bounds
    if (TextX + TextWidth + 50 >= 0 && TextX + TextWidth + 50 + TextWidth <= C.ClipX)
    {
        C.SetPos(TextX + TextWidth + 50, TextYPos);
        C.DrawText(ScrollText, false);
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
}