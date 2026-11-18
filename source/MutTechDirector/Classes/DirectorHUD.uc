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

defaultproperties
{
    bShowScores=False
    bShowStats=False
    bShowWeaponInfo=False
    bShowCrosshair=False
    bShowRadar=False
    bShowVehicleNames=False  // Redundant with DrawVehicleName override, but explicit
}