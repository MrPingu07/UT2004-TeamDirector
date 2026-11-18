//=============================================================================
// DirectorFeed
//
// Config-backed message source for the typewriter banner in DirectorHUD,
// plus the live-match token expander that turns placeholders such as
// $MAPNAME and $TOPFRAGGER into values read from replicated match state.
//
// The config file is <UT2004>/System/MutTechDirector.ini, section
// [MutTechDirector.DirectorFeed].  Messages is a dynamic string array, so
// UT2004 expects repeated bare keys:
//
//     Messages=TECHNICAL DIRECTOR MODE
//     Messages=PRESS [B] TO EXIT BOOTH
//
// Do not use Messages(0)=... here; that form is for static arrays and is
// ignored by the dynamic-array config reader.
//
// All token expansion happens on the client, from data the client already
// receives: LevelInfo, GameReplicationInfo and its PRI/Team arrays.  Nothing
// here is authoritative and nothing is sent to the server.
//=============================================================================
class DirectorFeed extends Object
    config(MutTechDirector);

var config array<string> Messages;

// Fallbacks keep every token non-empty so a message never collapses because
// a value is unavailable (no GRI yet, warmup, empty board, etc.).
const FALLBACK_MAP      = "Unknown Arena";
const FALLBACK_SERVER   = "Local Arena";
const FALLBACK_GAMETYPE = "Tournament";
const FALLBACK_NAME     = "Someone";
const FALLBACK_SCORE    = "lots of";
const FALLBACK_TEAM     = "Our Team";
const FALLBACK_GOAL     = "No Limit";
const FALLBACK_STATUS   = "Unknown";

/** Hard ceiling for $RANDOM token ranges (keeps K/M math well inside int). */
const MAX_RANDOM        = 1000000;

/**
 * Replace every supported token in Msg with its live value.
 *
 * The template is uppercased before matching, so token names are effectively
 * case-insensitive.  The finished message is uppercased again so inserted
 * values (player names, server/map/team names) also render in caps.
 * $TOPFRAGGERSCORE is expanded before $TOPFRAGGER because the shorter token
 * is a prefix of the longer one.
 *
 * This is called once per banner cycle by DirectorHUD.PickMessage(), so the
 * whole message is a snapshot: scores cannot change mid-typewriter.
 */
static function string ExpandTokens(string Msg, PlayerController PC)
{
    local GameReplicationInfo GRI;
    local PlayerReplicationInfo Top;
    local PlayerReplicationInfo TopTeam;
    local int LeadIndex;

    if (Msg == "")
        return Msg;

    // The banner is styled as an all-caps broadcast. Uppercase the template
    // before token replacement so token names are matched case-insensitively,
    // then uppercase the finished string so even player/server/map names are
    // rendered in caps. Control/colour characters are left intact by Caps().
    Msg = Caps(Msg);

    GRI = None;
    if (PC != None)
        GRI = PC.GameReplicationInfo;

    Top = FindTopPlayer(GRI, -1);
    TopTeam = FindTopPlayer(GRI, GetDirectorTeam(PC));

    // Longest tokens first.
    if (Top == None)
    {
        ReplaceText(Msg, "$TOPFRAGGERSCORE", FALLBACK_SCORE);
        ReplaceText(Msg, "$TOPFRAGGER", FALLBACK_NAME);
    }
    else
    {
        ReplaceText(Msg, "$TOPFRAGGERSCORE", string(int(Top.Score)));
        ReplaceText(Msg, "$TOPFRAGGER", Top.PlayerName);
    }

    if (TopTeam == None)
        ReplaceText(Msg, "$TOPTEAMFRAGGER", FALLBACK_NAME);
    else
        ReplaceText(Msg, "$TOPTEAMFRAGGER", TopTeam.PlayerName);

    ReplaceText(Msg, "$TOPTEAMNAME", GetTeamName(GRI, PC));
    LeadIndex = GetLeadTeamIndex(GRI);
    ReplaceText(Msg, "$LEADTEAMNAME", GetTeamNameByIndex(GRI, LeadIndex));
    if (LeadIndex < 0)
        ReplaceText(Msg, "$LEADTEAMFRAGGER", FALLBACK_NAME);
    else
        ReplaceText(Msg, "$LEADTEAMFRAGGER",
                    GetPlayerName(FindTopPlayer(GRI, LeadIndex)));
    ReplaceText(Msg, "$MAPNAME", GetMapName(PC));
    ReplaceText(Msg, "$SERVERNAME", GetServerName(GRI));
    ReplaceText(Msg, "$PLAYERCOUNT", string(GetPlayerCount(GRI)));
    ReplaceText(Msg, "$GAMETYPE", GetGameType(PC, GRI));
    ReplaceText(Msg, "$GOALSCORE", GetGoalScoreText(GRI));
    ReplaceText(Msg, "$REDVAL", string(int(GetTeamScore(GRI, 0))));
    ReplaceText(Msg, "$BLUEVAL", string(int(GetTeamScore(GRI, 1))));
    ReplaceText(Msg, "$LEADTEAM", GetLeadTeam(GRI));
    ReplaceText(Msg, "$TOTALFRAGS", string(int(GetTotalScore(GRI))));
    ReplaceText(Msg, "$HIGHESTSCORE", string(GetHighestScore(GRI)));
    ReplaceText(Msg, "$LEADMARGIN", string(GetLeadMargin(GRI)));
    ReplaceText(Msg, "$MATCHSTATUS", GetMatchStatus(GRI));
    ReplaceText(Msg, "$TIMEELAPSED", FormatClock(GetElapsedTime(GRI)));
    ReplaceText(Msg, "$TIMEREMAINING", GetTimeRemaining(GRI));

    // Dynamic $RANDOM<min>_<max> tokens (optionally K/M-scaled).
    Msg = ExpandRandomTokens(Msg);

    // Second pass: force inserted values (usernames, map/server/team names)
    // to uppercase too. The template was already uppercased, so this only
    // affects the dynamic values.
    return Caps(Msg);
}

/**
 * Inclusive random integer in [Min, Max].  Resolved on the client like every
 * other token, so each viewer may roll a different number for the same
 * message.  The result is part of the per-cycle snapshot.
 */
static function int RollRange(int Min, int Max)
{
    if (Max < Min)
        return Min;

    return Min + Rand(Max - Min + 1);
}

/**
 * Expand every well-formed $RANDOM<min>_<max> token, with an optional K or M
 * suffix on the maximum.  Examples:
 *
 *     $RANDOM1_9       -> 1..9
 *     $RANDOM25_50     -> 25..50
 *     $RANDOM1_50K     -> 1..50000, printed as a full integer (e.g. 43781)
 *     $RANDOM1_5M      -> 1..5000000, clamped to the hard ceiling below
 *
 * UnrealScript has no regex, so the token is parsed by hand.  Malformed
 * occurrences are left untouched and scanning resumes after them, so one bad
 * token does not prevent later valid tokens from expanding.
 */
static function string ExpandRandomTokens(string Msg)
{
    local int SearchFrom, Pos, i, MinStart, MinVal, MaxVal, Mult;
    local string Token, Suffix;

    SearchFrom = 0;
    while (SearchFrom < Len(Msg))
    {
        Pos = InStr(Right(Msg, Len(Msg) - SearchFrom), "$RANDOM");
        if (Pos < 0)
            break;
        Pos += SearchFrom;

        i = Pos + Len("$RANDOM");

        // Minimum: one or more digits.
        MinStart = i;
        while (i < Len(Msg) && IsDigit(Mid(Msg, i, 1)))
            i++;
        if (i == MinStart || i >= Len(Msg) || Mid(Msg, i, 1) != "_")
        {
            SearchFrom = Pos + 1;
            continue;
        }
        MinVal = ParseDigits(Mid(Msg, MinStart, i - MinStart));
        i++;

        // Maximum: one or more digits.
        MinStart = i;
        while (i < Len(Msg) && IsDigit(Mid(Msg, i, 1)))
            i++;
        if (i == MinStart)
        {
            SearchFrom = Pos + 1;
            continue;
        }
        MaxVal = ParseDigits(Mid(Msg, MinStart, i - MinStart));

        // Optional scale suffix.
        Mult = 1;
        if (i < Len(Msg))
        {
            Suffix = Mid(Msg, i, 1);
            if (Suffix == "K")
            {
                Mult = 1000;
                i++;
            }
            else if (Suffix == "M")
            {
                Mult = 1000000;
                i++;
            }
        }

        // Clamp before multiplying to keep the int arithmetic safe.
        if (MaxVal > MAX_RANDOM / Mult)
            MaxVal = MAX_RANDOM / Mult;
        MaxVal *= Mult;

        if (MaxVal >= MinVal)
        {
            Token = Mid(Msg, Pos, i - Pos);
            ReplaceText(Msg, Token, string(RollRange(MinVal, MaxVal)));
        }

        SearchFrom = Pos + 1;
    }

    return Msg;
}

static function bool IsDigit(string S)
{
    local int C;

    if (Len(S) != 1)
        return False;

    C = Asc(S);
    return C >= 48 && C <= 57;
}

/** Parse an all-digit string; callers have already validated the characters. */
static function int ParseDigits(string S)
{
    local int i, Value;

    for (i = 0; i < Len(S); i++)
        Value = Value * 10 + (Asc(Mid(S, i, 1)) - Asc("0"));

    return Value;
}

// ---------------------------------------------------------------------------
// Map, server and mode
// ---------------------------------------------------------------------------

/** Display title of the map, or the map filename when the title is untitled. */
static function string GetMapName(PlayerController PC)
{
    local string S;
    local int Dot;

    if (PC == None || PC.Level == None)
        return FALLBACK_MAP;

    if (PC.Level.Title != "" && PC.Level.Title != PC.Level.Default.Title)
        return PC.Level.Title;

    // string(Level) is "DM-Rankin.LevelInfo0"; keep the part before the dot.
    S = string(PC.Level);
    Dot = InStr(S, ".");
    if (Dot >= 0)
        S = Left(S, Dot);

    if (S == "")
        return FALLBACK_MAP;

    return S;
}

static function string GetServerName(GameReplicationInfo GRI)
{
    if (GRI == None || GRI.ServerName == "")
        return FALLBACK_SERVER;
    return GRI.ServerName;
}

/** Replicated game-mode name, with a standalone fallback. */
static function string GetGameType(PlayerController PC, GameReplicationInfo GRI)
{
    if (GRI != None && GRI.GameName != "")
        return GRI.GameName;

    if (PC != None && PC.Level != None && PC.Level.Game != None &&
        PC.Level.Game.GameName != "")
        return PC.Level.Game.GameName;

    return FALLBACK_GAMETYPE;
}

/** Non-spectators in GRI.PRIArray: bots included, dead players included. */
static function int GetPlayerCount(GameReplicationInfo GRI)
{
    local int i;
    local int Count;

    if (GRI == None)
        return 0;

    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        if (GRI.PRIArray[i] != None && !GRI.PRIArray[i].bOnlySpectator)
            Count++;
    }

    return Count;
}

// ---------------------------------------------------------------------------
// Standings helpers
// ---------------------------------------------------------------------------

/** Team index of the Director, or -1 when no valid team is available. */
static function int GetDirectorTeam(PlayerController PC)
{
    if (PC == None || PC.PlayerReplicationInfo == None ||
        PC.PlayerReplicationInfo.Team == None)
        return -1;

    return PC.PlayerReplicationInfo.Team.TeamIndex;
}

/**
 * Highest-scoring non-spectator.  Pass TeamIndex = -1 for the global leader,
 * or a team index to restrict the search to that team.
 *
 * Ties keep the first entry encountered in PRIArray.
 */
static function PlayerReplicationInfo FindTopPlayer(GameReplicationInfo GRI, int TeamIndex)
{
    local int i;
    local PlayerReplicationInfo PRI;
    local PlayerReplicationInfo Best;

    if (GRI == None)
        return None;

    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        PRI = GRI.PRIArray[i];
        if (PRI == None || PRI.bOnlySpectator)
            continue;

        if (TeamIndex >= 0)
        {
            if (PRI.Team == None || PRI.Team.TeamIndex != TeamIndex)
                continue;
        }

        if (Best == None || PRI.Score > Best.Score)
            Best = PRI;
    }

    return Best;
}

static function int GetHighestScore(GameReplicationInfo GRI)
{
    local PlayerReplicationInfo Top;

    Top = FindTopPlayer(GRI, -1);
    if (Top == None)
        return 0;

    return int(Top.Score);
}

/** Highest score minus second-highest; 0 with fewer than two combatants. */
static function int GetLeadMargin(GameReplicationInfo GRI)
{
    local int i;
    local int Count;
    local float Hi;
    local float Second;
    local PlayerReplicationInfo PRI;

    if (GRI == None)
        return 0;

    Hi = -1.0;
    Second = -1.0;
    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        PRI = GRI.PRIArray[i];
        if (PRI == None || PRI.bOnlySpectator)
            continue;

        Count++;
        if (PRI.Score > Hi)
        {
            Second = Hi;
            Hi = PRI.Score;
        }
        else if (PRI.Score > Second)
        {
            Second = PRI.Score;
        }
    }

    if (Count < 2 || Hi <= 0.0)
        return 0;

    return Max(0, int(Hi - Second));
}

static function float GetTeamScore(GameReplicationInfo GRI, int TeamIndex)
{
    if (GRI == None || TeamIndex < 0 || TeamIndex > 1)
        return 0.0;
    if (GRI.Teams[TeamIndex] == None)
        return 0.0;
    return GRI.Teams[TeamIndex].Score;
}

/** Display name of the Director's own team; Red/Blue when TeamName is blank. */
static function string GetTeamName(GameReplicationInfo GRI, PlayerController PC)
{
    return GetTeamNameByIndex(GRI, GetDirectorTeam(PC));
}

/**
 * Display name for an explicit team slot: GRI.Teams[i].TeamName, or Red/Blue
 * when that name is blank.  TeamIndex < 0 means no single leader (tie or no
 * replicated teams) and returns "Neither", matching $LEADTEAM.
 */
static function string GetTeamNameByIndex(GameReplicationInfo GRI, int TeamIndex)
{
    if (TeamIndex < 0)
        return "Neither";

    if (GRI == None || TeamIndex > 1 || GRI.Teams[TeamIndex] == None)
        return FALLBACK_TEAM;

    if (GRI.Teams[TeamIndex].TeamName != "")
        return GRI.Teams[TeamIndex].TeamName;

    if (TeamIndex == 0)
        return "Red";

    return "Blue";
}

/** Index of the team with the higher score, or -1 when tied/unavailable. */
static function int GetLeadTeamIndex(GameReplicationInfo GRI)
{
    local float Red;
    local float Blue;

    if (GRI == None)
        return -1;

    Red = GetTeamScore(GRI, 0);
    Blue = GetTeamScore(GRI, 1);

    if (Red > Blue)
        return 0;
    if (Blue > Red)
        return 1;

    return -1;
}

static function string GetLeadTeam(GameReplicationInfo GRI)
{
    local int TeamIndex;

    TeamIndex = GetLeadTeamIndex(GRI);
    if (TeamIndex == 0)
        return "Red";
    if (TeamIndex == 1)
        return "Blue";

    return "Neither";
}

/** PlayerName of a PRI, or the standard non-empty fallback. */
static function string GetPlayerName(PlayerReplicationInfo PRI)
{
    if (PRI == None)
        return FALLBACK_NAME;
    return PRI.PlayerName;
}

/** Combined scoreboard points of every non-spectator. */
static function float GetTotalScore(GameReplicationInfo GRI)
{
    local int i;
    local float Total;

    if (GRI == None)
        return 0.0;

    for (i = 0; i < GRI.PRIArray.Length; i++)
    {
        if (GRI.PRIArray[i] != None && !GRI.PRIArray[i].bOnlySpectator)
            Total += GRI.PRIArray[i].Score;
    }

    return Total;
}

static function string GetGoalScoreText(GameReplicationInfo GRI)
{
    if (GRI == None || GRI.GoalScore <= 0)
        return FALLBACK_GOAL;
    return string(GRI.GoalScore);
}

// ---------------------------------------------------------------------------
// Match state and clock
// ---------------------------------------------------------------------------

/**
 * Warmup / Live / Overtime / Concluded.
 *
 * GameReplicationInfo has no overtime or sudden-death flag: those live on the
 * server-side GameInfo.  A begun match with an expired clock and no winner is
 * therefore reported as Overtime.
 */
static function string GetMatchStatus(GameReplicationInfo GRI)
{
    if (GRI == None)
        return FALLBACK_STATUS;

    if (!GRI.bMatchHasBegun)
        return "Warmup";

    if (GRI.bStopCountDown || GRI.Winner != None)
        return "Concluded";

    if (GRI.TimeLimit > 0 && GRI.RemainingTime <= 0)
        return "Overtime";

    return "Live";
}

static function int GetElapsedTime(GameReplicationInfo GRI)
{
    if (GRI == None)
        return 0;
    return GRI.ElapsedTime;
}

static function string GetTimeRemaining(GameReplicationInfo GRI)
{
    if (GRI == None)
        return FALLBACK_STATUS;

    if (!GRI.bMatchHasBegun)
        return "Warmup";

    if (GRI.TimeLimit <= 0)
        return FALLBACK_GOAL;

    if (GRI.RemainingTime <= 0)
        return "Overtime";

    return FormatClock(GRI.RemainingTime);
}

/** Minutes without leading zero, seconds always two digits: 0:07, 12:34. */
static function string FormatClock(int Seconds)
{
    local int Minutes;
    local int Rest;

    if (Seconds < 0)
        Seconds = 0;

    Minutes = Seconds / 60;
    Rest = Seconds % 60;

    if (Rest < 10)
        return string(Minutes) $ ":0" $ string(Rest);

    return string(Minutes) $ ":" $ string(Rest);
}

defaultproperties
{
    Messages(0)="TECHNICAL DIRECTOR MODE"
    Messages(1)="PRESS [B] TO EXIT BOOTH"
}
