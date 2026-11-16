//=============================================================================
// DirectorNotify
//
// On-screen notification for the Technical Director.  Sent via
// PlayerController.ReceiveLocalizedMessage so it appears as a clean HUD line
// (never in chat) at a dedicated screen position, replacing the previous
// notification instantly.
//=============================================================================
class DirectorNotify extends LocalMessage;

var localized string DefaultLabel;

static function string GetString(
	optional int Switch,
	optional PlayerReplicationInfo RelatedPRI_1,
	optional PlayerReplicationInfo RelatedPRI_2,
	optional Object OptionalObject
	)
{
	// Switch < 0 = clear pulse (empty string, removes the HUD line)
	if (Switch < 0)
		return "";

	// Message text is passed via OptionalObject as a DirectorNotifyText wrapper
	if (OptionalObject != None && DirectorNotifyText(OptionalObject) != None)
		return DirectorNotifyText(OptionalObject).Text;

	return Default.DefaultLabel;
}

static function float GetLifeTime(int Switch)
{
	return 3.0; // stays on screen long enough to read
}

defaultproperties
{
	bIsSpecial=True
	bIsUnique=True
	bIsConsoleMessage=False
	bFadeMessage=True
	bBeep=False

	Lifetime=5.0
	FontSize=2
	PosX=0.500000
	PosY=0.180000
	DrawPivot=DP_MiddleMiddle
	StackMode=SM_None
	DrawColor=(R=255,G=255,B=100,A=255)
}