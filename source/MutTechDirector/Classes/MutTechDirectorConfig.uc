//=============================================================================
// MutTechDirectorConfig
//
// "Configure Mutators" submenu for MutTechDirector.  Opened from the mutator
// list through ConfigMenuClassName.  Same proven GUIPage + moEditBox pattern
// as the Kakutou2k4-Enhanced config page: the boxes read the mutator's class
// defaults, OK writes them back and saves the config, Reset restores 1.0 s.
//=============================================================================
class MutTechDirectorConfig extends GUIPage;

var moEditBox Box1, Box2, Box3, Box4, Box5, Box6, Box7, Box8, Box9;

function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
    Super.InitComponent(MyController, MyOwner);

    Box1 = moEditBox(Controls[4]);
    Box2 = moEditBox(Controls[5]);
    Box3 = moEditBox(Controls[6]);
    Box4 = moEditBox(Controls[7]);
    Box5 = moEditBox(Controls[8]);
    Box6 = moEditBox(Controls[9]);
    Box7 = moEditBox(Controls[10]);
    Box8 = moEditBox(Controls[11]);
    Box9 = moEditBox(Controls[12]);

    Box1.SetText(string(class'MutTechDirector'.default.Cooldown1));
    Box2.SetText(string(class'MutTechDirector'.default.Cooldown2));
    Box3.SetText(string(class'MutTechDirector'.default.Cooldown3));
    Box4.SetText(string(class'MutTechDirector'.default.Cooldown4));
    Box5.SetText(string(class'MutTechDirector'.default.Cooldown5));
    Box6.SetText(string(class'MutTechDirector'.default.Cooldown6));
    Box7.SetText(string(class'MutTechDirector'.default.Cooldown7));
    Box8.SetText(string(class'MutTechDirector'.default.Cooldown8));
    Box9.SetText(string(class'MutTechDirector'.default.Cooldown9));
}

function bool InternalOnClick(GUIComponent Sender)
{
    class'MutTechDirector'.default.Cooldown1 = ClampValue(Box1);
    class'MutTechDirector'.default.Cooldown2 = ClampValue(Box2);
    class'MutTechDirector'.default.Cooldown3 = ClampValue(Box3);
    class'MutTechDirector'.default.Cooldown4 = ClampValue(Box4);
    class'MutTechDirector'.default.Cooldown5 = ClampValue(Box5);
    class'MutTechDirector'.default.Cooldown6 = ClampValue(Box6);
    class'MutTechDirector'.default.Cooldown7 = ClampValue(Box7);
    class'MutTechDirector'.default.Cooldown8 = ClampValue(Box8);
    class'MutTechDirector'.default.Cooldown9 = ClampValue(Box9);
    class'MutTechDirector'.static.StaticSaveConfig();

    Controller.CloseMenu(False);
    return True;
}

/** Sanity: 0 s (always ready) up to two minutes. */
function float ClampValue(moEditBox Box)
{
    local float V;

    if (Box == None)
        return 1.0;

    V = float(Box.GetText());
    if (V < 0.0)
        V = 0.0;
    if (V > 120.0)
        V = 120.0;

    Box.SetText(string(V));
    return V;
}

function bool ResetToDefaults(GUIComponent Sender)
{
    Box1.SetText("1.0");
    Box2.SetText("1.0");
    Box3.SetText("1.0");
    Box4.SetText("1.0");
    Box5.SetText("1.0");
    Box6.SetText("1.0");
    Box7.SetText("1.0");
    Box8.SetText("1.0");
    Box9.SetText("1.0");
    return True;
}

defaultproperties
{
    Begin Object Class=GUIButton Name=DialogBackground
        WinWidth=1.0
        WinHeight=1.0
        WinTop=0
        WinLeft=0
        bAcceptsInput=false
        bNeverFocus=true
        StyleName="ComboListBox"
        bBoundToParent=true
        bScaleToParent=true
    End Object
    Controls(0)=GUIButton'DialogBackground'

    Begin Object Class=GUIButton Name=OkButton
        Caption="OK"
        WinWidth=0.2
        WinHeight=0.04
        WinLeft=0.6
        WinTop=0.9
        OnClick=InternalOnClick
        bBoundToParent=true
    End Object
    Controls(1)=GUIButton'OkButton'

    Begin Object Class=GUILabel Name=DialogText
        Caption="Tournament Technical Director"
        TextAlign=TXTA_Center
        TextColor=(R=220,G=180,B=0,A=255)
        TextFont="UT2HeaderFont"
        WinWidth=1.000000
        WinHeight=20.000000
        WinLeft=0.000000
        WinTop=0.1
        bBoundToParent=true
    End Object
    Controls(2)=GUILabel'DialogText'

    Begin Object Class=GUILabel Name=DialogText2
        Caption="Transmat cooldowns, seconds (0 = always ready) - applies next match"
        TextAlign=TXTA_Center
        TextColor=(R=220,G=180,B=0,A=255)
        TextFont="UT2MenuFont"
        WinWidth=1.000000
        WinHeight=20.000000
        WinLeft=0.000000
        WinTop=0.2
        bBoundToParent=true
    End Object
    Controls(3)=GUILabel'DialogText2'

    Begin Object Class=moEditBox Name=BoxSlot1
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.05
        WinTop=0.3
        Caption="1. Ammunition Requisition"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(4)=moEditBox'BoxSlot1'

    Begin Object Class=moEditBox Name=BoxSlot2
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.55
        WinTop=0.3
        Caption="2. Perimeter Defense"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(5)=moEditBox'BoxSlot2'

    Begin Object Class=moEditBox Name=BoxSlot3
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.05
        WinTop=0.4
        Caption="3. Painkillers"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(6)=moEditBox'BoxSlot3'

    Begin Object Class=moEditBox Name=BoxSlot4
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.55
        WinTop=0.4
        Caption="4. Blindage"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(7)=moEditBox'BoxSlot4'

    Begin Object Class=moEditBox Name=BoxSlot5
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.05
        WinTop=0.5
        Caption="5. Stimuli Dose"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(8)=moEditBox'BoxSlot5'

    Begin Object Class=moEditBox Name=BoxSlot6
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.55
        WinTop=0.5
        Caption="6. SPMA Artillery"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(9)=moEditBox'BoxSlot6'

    Begin Object Class=moEditBox Name=BoxSlot7
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.05
        WinTop=0.6
        Caption="7. Light Vehicle Transmat"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(10)=moEditBox'BoxSlot7'

    Begin Object Class=moEditBox Name=BoxSlot8
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.55
        WinTop=0.6
        Caption="8. Heavy Asset Drop"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(11)=moEditBox'BoxSlot8'

    Begin Object Class=moEditBox Name=BoxSlot9
        WinWidth=0.4
        WinHeight=0.04
        WinLeft=0.05
        WinTop=0.7
        Caption="9. Emergency Recall"
        bReadOnly=false
        bBoundToParent=true
    End Object
    Controls(12)=moEditBox'BoxSlot9'

    Begin Object Class=GUIButton Name=ResetButton
        Caption="Reset to Defaults"
        WinWidth=0.2
        WinHeight=0.04
        WinLeft=0.2
        WinTop=0.9
        OnClick=ResetToDefaults
        bBoundToParent=true
    End Object
    Controls(13)=GUIButton'ResetButton'

    WinLeft=0
    WinTop=0.2
    WinWidth=1
    WinHeight=0.6
    bRequire640x480=True
}
