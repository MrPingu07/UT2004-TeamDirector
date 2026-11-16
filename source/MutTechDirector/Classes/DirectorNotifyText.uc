//=============================================================================
// DirectorNotifyText
//
// Simple string wrapper for passing dynamic text to DirectorNotify via
// ReceiveLocalizedMessage's OptionalObject parameter.
//=============================================================================
class DirectorNotifyText extends Object;

var string Text;

function string GetText()
{
    return Text;
}

defaultproperties
{
}