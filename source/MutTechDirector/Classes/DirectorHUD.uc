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
 * Custom spectator banner replacing the native "Now Viewing..." banner.
 * Draws a custom banner at the bottom with:
 * - Unreal "U" logo at left margin
 * - Dark transparent horizontal band spanning screen width
 * - Team-colored stripes at top and bottom edges
 * - Custom scrolling text area (3x larger) in the middle
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
    local float LoopX;
    local float SavedOrgX;
    local float SavedOrgY;
    local float SavedClipX;
    local float SavedClipY;
    
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
    
    // Banner dimensions - keep at bottom
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
    
    // Unreal "U" logo at LEFT margin (front layer)
    LogoSize = 48.0;
    LogoX = 16.0;  // Left margin
    LogoY = BannerY + (BannerHeight - LogoSize) * 0.5;
    
    // Draw Unreal "U" logo
    C.Style = ERenderStyle.STY_Alpha;
    C.SetDrawColor(255, 255, 255, 255);
    C.SetPos(LogoX, LogoY);
    C.DrawTile(
        Texture'InterfaceContent.Logos.Logo',  // UT2004/Unreal logo texture
        48.0, 48.0,
        0, 0,
        256, 256
    );
    C.Style = ERenderStyle.STY_Normal;
    
    // Custom scrolling text area (3x larger text)
    if (TeamNum == 0)
        TeamName = "RED";
    else
        TeamName = "BLUE";
    ScrollText = "TECHNICAL DIRECTOR MODE  |  SPECTATING: " $ TargetPRI.PlayerName $ "  |  TEAM: " $ TeamName $ "  |  PRESS [B] TO EXIT BOOTH";
    
    // Scrolling text animation - use larger font (3x bigger via MedFont instead of SmallFont)
    C.Font = C.MedFont;  // 3x larger than SmallFont
    C.StrLen(ScrollText, TextWidth, TextHeight);
    
    // Scrolling text animation
    ScrollSpeed = 80.0; // pixels per second
    ScrollOffset = (Level.TimeSeconds * 80.0) % (TextWidth + C.ClipX);
    
    TextX = C.ClipX - (Level.TimeSeconds * 80.0 % (TextWidth + C.ClipX));
    TextYPos = BannerY + (BannerHeight - TextHeight) * 0.5;
    
    // Draw scrolling text using native canvas clipping for smooth ticker effect
    // Save original canvas state
    SavedOrgX = C.OrgX;
    SavedOrgY = C.OrgY;
    SavedClipX = C.ClipX;
    SavedClipY = C.ClipY;
    
    // Set clipping region to banner area
    C.SetOrigin(BannerX, BannerY);
    C.SetClip(BannerWidth, BannerHeight);
    
    C.SetDrawColor(TeamColor.R, TeamColor.G, TeamColor.B, 255);
    
    // Primary copy: scrolls within clipped region
    C.SetPos(TextX - BannerX, TextYPos - BannerY);
    C.DrawText(ScrollText, false);
    
    // Loop copy: immediately after primary for seamless scrolling
    LoopX = TextX + TextWidth;
    C.SetPos(LoopX - BannerX, TextYPos - BannerY);
    C.DrawText(ScrollText, false);
    
    // Restore canvas state
    C.SetOrigin(SavedOrgX, SavedOrgY);
    C.SetClip(SavedClipX, SavedClipY);
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