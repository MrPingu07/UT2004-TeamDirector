//=============================================================================
// DirectorFeed
//
// Config-backed message source for the typewriter banner in DirectorHUD.
// Holds an array of messages that can be populated from an .ini file.
//=============================================================================
class DirectorFeed extends Object
    config(MutTechDirector);

var config array<string> Messages;

defaultproperties
{
    Messages(0)="TECHNICAL DIRECTOR MODE"
    Messages(1)="PRESS [B] TO EXIT BOOTH"
}