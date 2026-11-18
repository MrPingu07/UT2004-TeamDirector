# Beacon Fix Documentation

## The Issue

When in Director mode, the Director saw forced native beacons above `DirectorSentinel` turrets displaying:
- "DirectorSentinel" (class name)
- "Health [1000/1000]"
- "Shield [0]"

These followed the exact typography and formatting of regular player team beacons, indicating they were drawn by the native **team beacon system** (`TeamBeaconMaxDist`/`TeamBeaconPlayerInfoMaxDist`), not by the custom HUD code.

## Root Cause

The native engine draws team beacons through **two separate code paths**:

1. **`HUD.DrawVehicleName()`** - Draws vehicle class names above vehicles during spectator overlay
2. **`Pawn.PostRender2D()` → `HUD.DrawCustomBeacon()`** - Called for every pawn with `bScriptPostRender=true` (including vehicles/sentinels) to draw the team beacon texture + name/health text

The `DirectorSentinel` extends `ASVehicle_Sentinel_Floor` → `Vehicle` → `Pawn`, so it has `bScriptPostRender = true`. When the Director spectates, the engine calls `Pawn.PostRender2D()` for each sentinel, which calls `PC.myHUD.DrawCustomBeacon()`, drawing the native beacon with player-style formatting.

Previous attempts to fix this:
- `DirectorHUD.DrawVehicleName()` override - only suppresses vehicle name drawing, not beacon drawing
- `DirectorHUD.DrawCustomBeacon()` override - works but runs AFTER native code decides to call it
- `DirectorSentinel.PostRender()` override - only suppresses the sentinel's own PostRender, not the HUD's beacon drawing

## The Fix

**File: `source/MutTechDirector/Classes/DirectorSentinel.uc`**

Added a single line to `defaultproperties`:
```unrealscript
defaultproperties
{
    VehicleNameString=""
    bNoTeamBeacon=True  // Disable native team beacon system for this sentinel entirely.
}
```

**Why this works**: `bNoTeamBeacon` is a native `Pawn` property (`Engine.Pawn.bNoTeamBeacon`). When `true`, the native C++ code **completely skips** calling `PostRender2D` for this pawn, so `DrawCustomBeacon` is never invoked. This happens at the engine level, before any UnrealScript HUD code runs.

**Supporting changes**:
- `DirectorHUD.DrawCustomBeacon()` - Added debug logging to verify suppression
- `DirectorReplicationInfo.ClientActivateBooth()` - Enhanced logging to verify HUD swap

## Verification

Run with `-log` and enter Director mode. Look for:

| Log | Meaning |
|-----|---------|
| `ClientActivateBooth - swapped to DirectorHUD` | HUD swap successful |
| `[DIR-HUD] DrawCustomBeacon called for ...` | Native beacon still trying (override catches it) |
| **No DrawCustomBeacon logs for sentinels** | `bNoTeamBeacon=True` worked - native skipped entirely ✓ |

## Result

- Director sees **only custom beacons**: "Sentry" / "HP [X/X]" (drawn by `DirectorInteraction.PostRender`)
- Combatants see **LOS-checked custom beacons**: "Sentry" / "HP [X/X]" (drawn by `DirectorTurretBeaconInteraction.PostRender`)
- Native "DirectorSentinel / Health [1000/1000] / Shield [0]" beacons are **completely eliminated**
- Other vehicles (SPMA, Raptor, Goliath) still show native beacons for combatants (unchanged)
- Player nameplates unchanged: "Name" / "HP [X]" / "Shield [X]"