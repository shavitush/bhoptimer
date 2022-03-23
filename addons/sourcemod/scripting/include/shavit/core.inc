/*
 * shavit's Timer - core.inc file
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

#if defined _shavit_core_included
	#endinput
#endif
#define _shavit_core_included

#define SHAVIT_VERSION "3.2.0a"
#define STYLE_LIMIT 256

#define SHAVIT_LOG_QUERIES 0

#include <shavit/bhopstats-timerified>

// status
enum TimerStatus
{
	Timer_Stopped,
	Timer_Running,
	Timer_Paused
};

enum
{
	CPR_ByConVar = (1 << 0),
	CPR_NoTimer = (1 << 1),
	CPR_InStartZone = (1 << 2),
	CPR_NotOnGround = (1 << 3),
	CPR_Moving = (1 << 4),
	CPR_Duck = (1 << 5), // quack
	CPR_InEndZone = (1 << 6),
};

enum
{
	Track_Main,
	Track_Bonus,
	Track_Bonus_Last = 8,
	TRACKS_SIZE
};

// for Shavit_GetStyleStrings
enum
{
	sStyleName,
	sShortName,
	sHTMLColor,
	sChangeCommand,
	sClanTag,
	sSpecialString,
	sStylePermission
};

// for Shavit_GetChatStrings
enum
{
	sMessagePrefix,
	sMessageText,
	sMessageWarning,
	sMessageVariable,
	sMessageVariable2,
	sMessageStyle
};

enum struct stylestrings_t
{
	char sStyleName[64];
	char sShortName[32];
	char sHTMLColor[32];
	char sChangeCommand[128];
	char sClanTag[32];
	char sSpecialString[128];
	char sStylePermission[64];
}

enum struct chatstrings_t
{
	char sPrefix[64];
	char sText[16];
	char sWarning[16];
	char sVariable[16];
	char sVariable2[16];
	char sStyle[16];
}

enum struct timer_snapshot_t
{
	bool bTimerEnabled;
	// fCurrentTime = (float(iFullTicks)+(iFractionalTicks/10000.0)+fZoneOffset[0])*GetTickInterval()
	float fCurrentTime;
	bool bClientPaused;
	int iJumps;
	int bsStyle;
	int iStrafes;
	int iTotalMeasures;
	int iGoodGains;
	float fServerTime;
	int iSHSWCombination;
	int iTimerTrack;
	int iMeasuredJumps;
	int iPerfectJumps;
	// used as a "tick fraction" basically
	float fZoneOffset[2];
	float fDistanceOffset[2];
	float fAvgVelocity;
	float fMaxVelocity;
	float fTimescale;
	int iZoneIncrement; // convert to array for per zone offsets (?)

	int iFullTicks;
	int iFractionalTicks; // divide this by 10000.0 to get a fraction of a tick. whole ticks are moved to iFullTicks

	bool bPracticeMode;

	bool bJumped;
	bool bCanUseAllKeys;
	bool bOnGround;

	int iLastButtons;
	float fLastAngle;
	int iLandingTick;
	MoveType iLastMoveType;
	float fStrafeWarning;
	float fLastInputVel[2];

	float fplayer_speedmod;
	float fNextFrameTime;

	MoveType iLastMoveTypeTAS;
}

stock void Shavit_LogQuery(const char[] query)
{
	static File hLogFile;

	if (hLogFile == null)
	{
		char sPlugin[PLATFORM_MAX_PATH];
		GetPluginFilename(INVALID_HANDLE, sPlugin, sizeof(sPlugin));
		ReplaceString(sPlugin, PLATFORM_MAX_PATH, ".smx", "");
		ReplaceString(sPlugin, PLATFORM_MAX_PATH, "\\", "/");

		int start = FindCharInString(sPlugin, '/', true);

		char sFilename[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, sFilename, sizeof(sFilename), "logs/%s_sql.log", sPlugin[start+1]);

		hLogFile = OpenFile(sFilename, "a");
	}

	if (hLogFile)
	{
		LogToOpenFileEx(hLogFile, "%s", query);
	}
}

methodmap Database2 < Database
{
	public void Query2(SQLQueryCallback callback, const char[] query, any data = 0, DBPriority prio = DBPrio_Normal)
	{
#if SHAVIT_LOG_QUERIES
		Shavit_LogQuery(query);
#endif
		this.Query(callback, query, data, prio);
	}
}

methodmap Transaction2 < Transaction
{
	public Transaction2()
	{
		return view_as<Transaction2>(new Transaction());
	}

	public int AddQuery2(const char[] query, any data = 0)
	{
#if SHAVIT_LOG_QUERIES
		Shavit_LogQuery(query);
#endif
		return this.AddQuery(query, data);
	}
}

// connects synchronously to the bhoptimer database
// calls errors if needed
stock Database GetTimerDatabaseHandle(bool reuse_persistent_connection=true)
{
	Database db = null;
	char sError[255];

	if(SQL_CheckConfig("shavit"))
	{
		if((db = SQL_Connect("shavit", reuse_persistent_connection, sError, 255)) == null)
		{
			SetFailState("Timer startup failed. Reason: %s", sError);
		}
	}
	else
	{
		db = SQLite_UseDatabase("shavit", sError, 255);
	}

	// support unicode names
	if (!db.SetCharset("utf8mb4"))
	{
		db.SetCharset("utf8");
	}

	return db;
}

stock Database2 GetTimerDatabaseHandle2(bool reuse_persistent_connection=true)
{
	return view_as<Database2>(GetTimerDatabaseHandle(reuse_persistent_connection));
}

// figures out if the database is a mysql database
stock bool IsMySQLDatabase(Database db)
{
	char sDriver[8];
	db.Driver.GetIdentifier(sDriver, 8);

	return StrEqual(sDriver, "mysql", false);
}

stock void LowercaseString(char[] str)
{
	int i, x;
	while ((x = str[i]) != 0)
	{
		if ('A' <= x <= 'Z')
			str[i] += ('a' - 'A');
		++i;
	}
}

// GetMapDisplayName ends up opening every single fucking file to verify it's valid.
// I don't care about that. I just want the stupid fucking mapname string.
// Also this lowercases the string.
stock void LessStupidGetMapDisplayName(const char[] map, char[] displayName, int maxlen)
{
	char temp[PLATFORM_MAX_PATH];
	char temp2[PLATFORM_MAX_PATH];

	strcopy(temp, sizeof(temp), map);
	ReplaceString(temp, sizeof(temp), "\\", "/", true);

	int slashpos = FindCharInString(map, '/', true);
	strcopy(temp2, sizeof(temp2), map[slashpos+1]);

	int ugcpos = StrContains(temp2, ".ugc", true);

	if (ugcpos != -1)
	{
		temp2[ugcpos] = 0;
	}

	LowercaseString(temp2);
	strcopy(displayName, maxlen, temp2);
}

stock void GetLowercaseMapName(char sMap[PLATFORM_MAX_PATH])
{
	GetCurrentMap(sMap, sizeof(sMap));
	LessStupidGetMapDisplayName(sMap, sMap, sizeof(sMap));
}

// retrieves the table prefix defined in configs/shavit-prefix.txt
stock void GetTimerSQLPrefix(char[] buffer, int maxlen)
{
	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}

	char sLine[PLATFORM_MAX_PATH * 2];

	if(fFile.ReadLine(sLine, PLATFORM_MAX_PATH * 2))
	{
		TrimString(sLine);
		strcopy(buffer, maxlen, sLine);
	}

	delete fFile;
}

stock bool IsValidClient(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

stock bool IsSource2013(EngineVersion ev)
{
	return (ev == Engine_CSS || ev == Engine_TF2);
}

stock void IPAddressToString(int ip, char[] buffer, int maxlen)
{
	FormatEx(buffer, maxlen, "%d.%d.%d.%d", ((ip >> 24) & 0xFF), ((ip >> 16) & 0xFF), ((ip >> 8) & 0xFF), (ip & 0xFF));
}

stock int IPStringToAddress(const char[] ip)
{
	char sExplodedAddress[4][4];
	ExplodeString(ip, ".", sExplodedAddress, 4, 4, false);

	int iIPAddress =
			(StringToInt(sExplodedAddress[0]) << 24) |
			(StringToInt(sExplodedAddress[1]) << 16) |
			(StringToInt(sExplodedAddress[2]) << 8) |
			StringToInt(sExplodedAddress[3]);

	return iIPAddress;
}

// time formatting!
stock void FormatSeconds(float time, char[] newtime, int newtimesize, bool precise = true, bool nodecimal = false, bool full_hms = false)
{
	float fTempTime = time;

	if(fTempTime < 0.0)
	{
		fTempTime = -fTempTime;
	}

	int iRounded = RoundToFloor(fTempTime);
	int iSeconds = (iRounded % 60);
	float fSeconds = iSeconds + fTempTime - iRounded;

	char sSeconds[8];

	if (nodecimal)
	{
		FormatEx(sSeconds, 8, "%d", iSeconds);
	}
	else
	{
		FormatEx(sSeconds, 8, precise? "%.3f":"%.1f", fSeconds);
	}

	if (!full_hms && fTempTime < 60.0)
	{
		strcopy(newtime, newtimesize, sSeconds);
		FormatEx(newtime, newtimesize, "%s%s", (time < 0.0) ? "-":"", sSeconds);
	}
	else
	{
		int iMinutes = (iRounded / 60);

		if (!full_hms && fTempTime < 3600.0)
		{
			FormatEx(newtime, newtimesize, "%s%d:%s%s", (time < 0.0)? "-":"", iMinutes, (fSeconds < 10)? "0":"", sSeconds);
		}
		else
		{
			int iHours = (iMinutes / 60);
			iMinutes %= 60;

			FormatEx(newtime, newtimesize, "%s%d:%s%d:%s%s", (time < 0.0)? "-":"", iHours, (iMinutes < 10)? "0":"", iMinutes, (fSeconds < 10)? "0":"", sSeconds);
		}
	}
}

stock void PrettyishTimescale(char[] buffer, int size, float ts, float min, float max, float x)
{
	ts += x;
	ts = (ts < min) ? min : ((ts > max) ? max : ts);

	if (ts == 1.0)
	{
		FormatEx(buffer, size, "1.0");
		return;
	}

	FormatEx(buffer, size, "0.%d", RoundFloat(ts * 10.0));
}

stock bool GuessBestMapName(ArrayList maps, const char input[PLATFORM_MAX_PATH], char output[PLATFORM_MAX_PATH])
{
	if(maps.FindString(input) != -1)
	{
		output = input;
		return true;
	}

	char sCache[PLATFORM_MAX_PATH];

	for(int i = 0; i < maps.Length; i++)
	{
		maps.GetString(i, sCache, PLATFORM_MAX_PATH);

		if(StrContains(sCache, input) != -1)
		{
			output = sCache;
			return true;
		}
	}

	return false;
}

stock void GetTrackName(int client, int track, char[] output, int size)
{
	if (track == Track_Main)
	{
		FormatEx(output, size, "%T", "Track_Main", client);
	}
	else if (track >= Track_Bonus)
	{
		FormatEx(output, size, "%T", "Track_Bonus", client, track);
	}
	else //if (track < Track_Main)
	{
		FormatEx(output, size, "%T", "Track_Unknown", client);
	}
}

stock int GetSpectatorTarget(int client, int fallback = -1)
{
	int target = fallback;

	if(IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if (iObserverMode >= 3 && iObserverMode <= 7)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if (IsValidEntity(iTarget))
			{
				target = iTarget;
			}
		}
	}

	return target;
}

stock float GetAngleDiff(float current, float previous)
{
	float diff = current - previous;
	return diff - 360.0 * RoundToFloor((diff + 180.0) / 360.0);
}

// Steam names are `char[32+1];`. Source engine names are `char[32];` (MAX_PLAYER_NAME_LENGTH).
// This means Source engine names can end up with an invalid unicode sequence at the end.
// This will remove the unicode codepoint if necessary.
/*
	Sourcemod 1.11 will strip the invalid codepoint internally (some relevant links below) but it'd still be nice to just retrive the client's `name` convar so we get the full thing or maybe even grab it from whatever SteamGameServer api stuff makes it available if possible.
	https://github.com/alliedmodders/sourcemod/pull/545
	https://github.com/alliedmodders/sourcemod/issues/1315
	https://github.com/alliedmodders/sourcemod/pull/1544
*/
stock void SanerGetClientName(int client, char[] name)
{
	static EngineVersion ev = Engine_Unknown;

	if (ev == Engine_Unknown)
	{
		ev = GetEngineVersion();
	}

	GetClientName(client, name, 32+1);

	// CSGO doesn't have this problem because `MAX_PLAYER_NAME_LENGTH` is 128...
	if (ev == Engine_CSGO)
	{
		return;
	}

	TrimTrailingInvalidUnicode(name);
}

stock bool TrimTrailingInvalidUnicode(char[] outstr)
{
	static int masks[3] = {0xC0, 0xE0, 0xF0};

	int maxidx = strlen(outstr)-1;

	for (int i = 0; (maxidx-i >= 0) && (i < 3); i++)
	{
		if ((outstr[maxidx-i] & masks[i]) == masks[i])
		{
			outstr[maxidx-i] = 0;
			return true;
		}
	}

	return false;
}

// https://forums.alliedmods.net/showthread.php?t=216841
// Trims display string to specified max possible length, and appends "..." if initial string exceeds that length
stock void TrimDisplayString(const char[] str, char[] outstr, int outstrlen, int max_allowed_length)
{
	int count, finallen;
	for(int i = 0; str[i]; i++)
	{
		count += ((str[i] & 0xc0) != 0x80) ? 1 : 0;

		if(count <= max_allowed_length)
		{
			outstr[i] = str[i];
			finallen = i;
		}
	}

	outstr[finallen + 1] = '\0';

	if(count > max_allowed_length)
		Format(outstr, outstrlen, "%s...", outstr);
}

/**
 * Called before shavit-core processes the client's usercmd.
 * Before this is called, safety checks (fake/dead clients) happen.
 * Use this forward in modules that use OnPlayerRunCmd to avoid errors and unintended behavior.
 * If a module conflicts with buttons/velocity/angles being changed in shavit-core, this forward is recommended.
 * This forward will NOT be called if a player's timer is paused.
 *
 * @param client					Client index.
 * @param buttons					Buttons sent in the usercmd.
 * @param impulse					Impulse sent in the usercmd.
 * @param vel						A vector that contains the player's desired movement. vel[0] is forwardmove, vel[1] is sidemove.
 * @param angles					The player's requested viewangles. They will not necessarily be applied as SRCDS itself won't accept every value.
 * @param status					The player's timer status.
 * @param track						The player's timer track.
 * @param style						The player's bhop style.
 * @param mouse						Mouse direction (x, y).
 * @return							Plugin_Continue to let shavit-core keep doing what it does, Plugin_Changed to pass different values.
 */
forward Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, int mouse[2]);

/**
 * Called just before shavit-core adds time to a player's timer.
 *
 * @param client					Client index.
 * @param snapshot					A snapshot with the player's current timer. You cannot manipulate it here.
 * @param time						The time to be added to the player's timer.
 * @noreturn
 */
forward void Shavit_OnTimeIncrement(int client, timer_snapshot_t snapshot, float &time);

/**
 * Called just before shavit-core adds time to a player's timer.
 * This is the forward you should use to modify the player's timer smoothly.
 * A good example use case is timescaling.
 *
 * @param client					Client index.
 * @param snapshot					A snapshot with the player's current timer. Read above in shavit.inc for more information.
 * @param time						The time to be added to the player's timer.
 * @noreturn
 */
forward void Shavit_OnTimeIncrementPost(int client, float time);

/**
 * Called when a player's timer is about to start.
 * (WARNING: Will be called every tick when the player stands at the start zone!)
 *
 * @param client                    Client index.
 * @param track                     Timer track.
 * @return                          Plugin_Continue to do nothing or anything else to not start the timer.
 */
forward Action Shavit_OnStartPre(int client, int track);

/**
 * Called when a player's timer starts.
 * (WARNING: Will be called every tick when the player stands at the start zone!)
 *
 * @param client                    Client index.
 * @param track                     Timer track.
 * @return                          Unused.
 */
forward Action Shavit_OnStart(int client, int track);

/**
 * Called when a player uses the restart command.
 *
 * @param client                    Client index.
 * @param track                     Timer track.
 * @return                          Plugin_Continue to do nothing or anything else to not restart.
 */
forward Action Shavit_OnRestartPre(int client, int track);

/**
 * Called when a player uses the restart command.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void Shavit_OnRestart(int client, int track);

/**
 * Called when a player uses the !end command.
 *
 * @param client                    Client index.
 * @param track                     Timer track.
 * @return                          Plugin_Continue to do nothing or anything else to not goto the end.
 */
forward Action Shavit_OnEndPre(int client, int track);

/**
 * Called when a player uses the !end command.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void Shavit_OnEnd(int client, int track);

/**
 * Called before a player's timer is stopped. (stop =/= finish a map)
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @return							False to prevent the timer from stopping.
 */
forward bool Shavit_OnStopPre(int client, int track);

/**
 * Called when a player's timer stops. (stop =/= finish a map)
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void Shavit_OnStop(int client, int track);

/**
 * Called before a player finishes a map.
 *
 * @param client					Client index.
 * @param snapshot					A snapshot of the player's timer.
 * @return							Plugin_Continue to do nothing, Plugin_Changed to change the variables or anything else to stop the timer from finishing.
 */
forward Action Shavit_OnFinishPre(int client, timer_snapshot_t snapshot);

/**
 * Called when a player finishes a map. (touches the end zone)
 *
 * @param client					Client index.
 * @param style						Style the record was done on.
 * @param time						Record time.
 * @param jumps						Jumps amount.
 * @param strafes					Amount of strafes.
 * @param sync						Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param track						Timer track.
 * @param oldtime					The player's best time on the map before this finish.
 * @param perfs						Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel					Player's average velocity throughout the run.
 * @param maxvel					Player's highest reached velocity.
 * @param timestamp					System time of when player finished.
 * @noreturn
 */
forward void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp);


/**
 * Called when a player's timer paused.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void Shavit_OnPause(int client, int track);

/**
 * Called when a player's timer resumed.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void Shavit_OnResume(int client, int track);

/**
 * Called when a player tries to change their bhopstyle.
 *
 * @param client                    Client index.
 * @param oldstyle                  Old bhop style.
 * @param newstyle                  New bhop style.
 * @param track                     Timer track.
 * @return                          Plugin_Continue to do nothing. Anything else to block.
 */
forward Action Shavit_OnStyleCommandPre(int client, int oldstyle, int newstyle, int track);

/**
 * Called when a player changes their bhopstyle.
 * Note: Doesn't guarantee that the player is in-game or connected.
 *
 * @param client					Client index.
 * @param oldstyle					Old bhop style.
 * @param newstyle					New bhop style.
 * @param track						Timer track.
 * @param manual					Was the change manual, or assigned automatically?
 * @noreturn
 */
forward void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual);

/**
 * Called when a player changes their bhop track.
 *
 * @param client					Client index.
 * @param oldtrack					Old bhop track.
 * @param newtrack					New bhop track.
 * @noreturn
 */
forward void Shavit_OnTrackChanged(int client, int oldtrack, int newtrack);

/**
 * Called when the styles configuration finishes loading and it's ready to load everything into the cache.
 *
 * @param styles					Amount of styles loaded.
 * @noreturn
 */
forward void Shavit_OnStyleConfigLoaded(int styles);

/**
 * Called when there's a successful connection to the database and it is ready to be used.
 * Called through shavit-core after migrations have been applied, and after the attempt to create the default `users` table.
 *
 * @noreturn
 */
forward void Shavit_OnDatabaseLoaded();

/**
 * Called when the chat messages configuration finishes loading and it's ready to load everything into the cache.
 *
 * @noreturn
 */
forward void Shavit_OnChatConfigLoaded();

/**
 * Called when a player gets the worst record in the server for the style.
 * Note: Will be only called for ranked styles.
 *
 * @param client					Client index.
 * @param style						Style the record was done on.
 * @param time						Record time.
 * @param jumps						Jumps amount.
 * @param strafes					Amount of strafes.
 * @param sync						Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param track						Timer track.
 * @param oldtime					The player's best time on the map before this finish.
 * @param perfs						Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel					Player's average velocity throughout the run.
 * @param maxvel					Player's highest reached velocity.
 * @param timestamp					System time of when player finished.
 * @noreturn
 */
forward void Shavit_OnWorstRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp);

/**
 * Called before clan tag variables are processed.
 *
 * @param client					Client index.
 * @param clantag					Reference to the clan tag buffer.
 * @param clantaglength				Max length of the customtag buffer.
 * @return							Plugin_Handled or Plugin_Stop to block the clan tag from changing. Anything else to pass along new values.
 */
forward Action Shavit_OnClanTagChangePre(int client, char[] clantag, int clantaglength);

/**
 * Called after clan tags are changed.
 *
 * @param client					Client index.
 * @param customtag					Reference to the custom clan tag buffer.
 * @param customtaglength			Max length of the customtag buffer.
 * @noreturn
 */
forward void Shavit_OnClanTagChangePost(int client, char[] customtag, int customtaglength);

/**
 * Called when a time offset is calculated
 *
 * @param client					Client index.
 * @param zonetype					Zone type (Zone_Start or Zone_End).
 * @param offset					Time offset from the given zone.
 * @param distance					Distance used in time offset.
 * @noreturn
 */
forward void Shavit_OnTimeOffsetCalculated(int client, int zonetype, float offset, float distance);

/**
 * Called when a client's dynamic timescale has been changed.
 * For the client's total timescale value, see the comments next to `Shavit_GetClientTimescale()`.
 *
 * @param client					Client index.
 * @param oldtimescale				The old timescale value
 * @param newtimescale				The new timescale value
 * @noreturn
 */
forward void Shavit_OnTimescaleChanged(int client, float oldtimescale, float newtimescale);

/**
 * Called before a sound is played by shavit-sounds.
 *
 * @param client					Index of the client that triggered the sound event.
 * @param sound						Reference to the sound that will be played.
 * @param maxlength					Length of the sound buffer, always PLATFORM_MAX_PATH.
 * @param clients					Reference to the array of clients to receive the sound, maxsize of MaxClients.
 * @param count						Reference to the number of clients to receive the sound.
 * @return							Plugin_Handled or Plugin_Stop to block the sound from being played. Anything else to continue the operation.
 */
forward Action Shavit_OnPlaySound(int client, char[] sound, int maxlength, int[] clients, int &count);

/**
 * Called before the server & timer handle the ProcessMovement method.
 *
 * @param client					Client Index.
 * @noreturn
 */
forward void Shavit_OnProcessMovement(int client);

/**
 * Called After the server handles the ProcessMovement method, but before the timer handles the method.
 *
 * @param client					Client Index.
 * @noreturn
 */
forward void Shavit_OnProcessMovementPost(int client);

/**
 * Called from shavit-timelimit when the 5 second map change countdown starts.
 *
 * @noreturn
 */
forward void Shavit_OnCountdownStart();

/**
 * Returns bhoptimer's database handle.
 * Call within Shavit_OnDatabaseLoaded. Safety is not guaranteed anywhere else!
 *
 * @return							Database handle.
 */
native Database Shavit_GetDatabase();

/**
 * Starts the timer for a player.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
native void Shavit_StartTimer(int client, int track);

/**
 * Restarts the timer for a player.
 * Will work as if the player just used sm_r.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @param force                     True to force the player to restart. False to call into Shavit_OnRestartPre and Shavit_OnStopPre first.
 * @return                          True on restart and False if a callback blocked the restart.
 */
native bool Shavit_RestartTimer(int client, int track, bool force=true);

/**
 * Stops the timer for a player.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @param bypass					Bypass call to Shavit_OnStopPre?
 * @return							True if the operation went through.
 */
native bool Shavit_StopTimer(int client, bool bypass = true);

/**
 * Changes a player's bhop style.
 *
 * @param client					Client index.
 * @param style						Style.
 * @param force						Ignore style permissions. This being true will bypass the `inaccessible` style setting as well.
 * @param manual					Is it a manual style change? (Was it caused by user interaction?)
 * @param noforward					Bypasses the call to `Shavit_OnStyleChanged`.
 * @return							False if failed due to lack of access, true otherwise.
 */
native bool Shavit_ChangeClientStyle(int client, int style, bool force = false, bool manual = false, bool noforward = false);

/**
 * Finishes the map for a player, with their current timer stats.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
native void Shavit_FinishMap(int client, int track);

/**
 * Retrieve a client's current time.
 *
 * @param client					Client index.
 * @return                          Current time.
 */
native float Shavit_GetClientTime(int client);

/**
 * Retrieve the client's track. (Track_Main/Track_Bonus etc..)
 *
 * @param client					Client index.
 * @return                          Timer track.
 */
native int Shavit_GetClientTrack(int client);

/**
 * Retrieve client jumps since timer start.
 *
 * @param client					Client index.
 * @return                          Current amount of jumps, 0 if timer is inactive.
 */
native int Shavit_GetClientJumps(int client);

/**
 * Retrieve a client's bhopstyle
 *
 * @param client					Client index.
 * @return                          Style.
 */
native int Shavit_GetBhopStyle(int client);

/**
 * Retrieve a client's timer status
 *
 * @param client					Client index.
 * @return                          See TimerStatus enum.
 */
native TimerStatus Shavit_GetTimerStatus(int client);

/**
 * Retrieve the amount of strafes done since the timer started.
 * Will return 0 if timer isn't running.
 *
 * @param client					Client index.
 * @return                          Amount of strafes since timer start.
 */
native int Shavit_GetStrafeCount(int client);

/**
 * Retrieve the perfect jumps percentage for the player.
 * Will return 100.0 if no jumps were measured.
 *
 * @param client					Client index.
 * @return                          Perfect jump percentage.
 */
native float Shavit_GetPerfectJumps(int client);

/**
 * Retrieve strafe sync since timer start.
 * Will return 0.0 if timer isn't running or -1.0 when not measured.
 *
 * @param client					Client index.
 * @return                          Amount of strafes since timer start.
 */
native float Shavit_GetSync(int client);

/**
 * Pauses a player's timer.
 *
 * @param client					Client index.
 * @noreturn
 */
native void Shavit_PauseTimer(int client);

/**
 * Resumes a player's timer.
 *
 * @param client					Client index.
 * @param teleport					Should the player be teleported to their location prior to saving?
 * @noreturn
 */
native void Shavit_ResumeTimer(int client, bool teleport = false);

/**
 * Gets a players zone offset.
 *
 * @param client					Client index.
 * @param teleport					Zone type (Zone_Start or Zone_End).
 * @return							Zone offset fraction if any for the given zone type.
 */
native float Shavit_GetZoneOffset(int client, int zonetype);

/**
 * Gets distance of a players distance offset given a zone.
 *
 * @param client					Client index.
 * @param teleport					Zone type  (Zone_Start or Zone_End).
 * @return 							Distance offset if any for the given zone type/
 */
native float Shavit_GetDistanceOffset(int client, int zonetype);

/*
 * Gets a value from the style config for the given style
 * e.g. Shavit_GetStyleSetting(Shavit_GetBhopStyle(client), "TAS", sBuffer, sizeof(sBuffer));
 *
 * @param style						Style index.
 * @param key						Style key to retreive.
 * @param value						Value buffer to store the return value in.
 * @param maxlength					Max length of the value buffer, cannot exceed 256.
 *
 * @return 							True if key was found, false otherwise.
 */
native bool Shavit_GetStyleSetting(int style, const char[] key, char[] value, int maxlength);

/*
 * Gets an int value from the style config for the given style. Returns 0 if key is not found.
 * e.g. Shavit_GetStyleSettingInt(Shavit_GetBhopStyle(client), "TAS");
 *
 * @param style						Style index.
 * @param key						Style key to retreive.
 *
 * @return 							Integer value if found, 0 if key is missing.
 */
native int Shavit_GetStyleSettingInt(int style, const char[] key);

/*
 * Gets the bool value from the style config for the given style. Returns false if key is not found.
 * e.g. if(Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), "TAS"))
 *
 * @param style						Style index.
 * @param key						Style key to retreive.
 *
 * @return 							bool value if found, false if key is missing.
 */
native bool Shavit_GetStyleSettingBool(int style, const char[] key);

/*
 * Gets a float value from the style config for the given style. Returns 0.0 if key is not found
 * e.g. Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "speed");
 *
 * @param style						Style index.
 * @param key						Style key to retreive.
 *
 * @return 							Float value if found, 0.0 if key is missing.
 */
native float Shavit_GetStyleSettingFloat(int style, const char[] key);

/*
 * Checks if the given key exists for that style
 * e.g. Shavit_HasStyleSetting(Shavit_GetBhopStyle(client), "tas");
 *
 * @param style						Style index.
 * @param key						Style key to retreive.
 *
 * @return 							True if found.
 */
native bool Shavit_HasStyleSetting(int style, const char[] key);

/*
 * Set the style setting to the given float value
 *
 * @param style						Style index.
 * @param key						Style key to set.
 * @param value						Value to set the style key to.
 * @param replace					Should the value be set if the given key already exists.
 *
 * @return 							True on success, false on failure.
 */
native bool Shavit_SetStyleSettingFloat(int style, const char[] key, float value, bool replace = true);

/*
 * Set the style setting to the given bool value
 *
 * @param style						Style index.
 * @param key						Style key to set.
 * @param value						Value to set the style key to.
 * @param replace					Should the value be set if the given key already exists.
 *
 * @return 							True on success, false on failure.
 */
native bool Shavit_SetStyleSettingBool(int style, const char[] key, bool value, bool replace = true);

/*
 * Set the style setting to the given int value
 *
 * @param style						Style index.
 * @param key						Style key to set.
 * @param value						Value to set the style key to.
 * @param replace					Should the value be set if the given key already exists.
 *
 * @return 							True on success, false on failure.
 */
native bool Shavit_SetStyleSettingInt(int style, const char[] key, int value, bool replace = true);

/**
 * Saves the style related strings on string references.
 *
 * @param style						Style index.
 * @param stringtype				String type to grab.
 * @param StyleStrings				Reference to the string buffer.
 * @param size						Max length for the buffer.
 * @return							SP_ERROR_NONE on success, anything else on failure.
 */
native int Shavit_GetStyleStrings(int style, int stringtype, char[] StyleStrings, int size);

/**
 * Saves the style related strings on string references.
 *
 * @param style                     Style index.
 * @param strings                   Reference to a stylestrings_t.
 * @param size                      Max length for the buffer.
 * @return                          SP_ERROR_NONE on success, anything else on failure.
 */
native int Shavit_GetStyleStringsStruct(int style, any[] strings, int size = sizeof(stylestrings_t));

/**
 * Retrieves the amount of styles in the server.
 *
 * @return							Amount of styles or -1 if there's an error.
 */
native int Shavit_GetStyleCount();

/**
 * Gets an array with style IDs in their configured menu ordering as specified in the styles config.
 *
 * @param arr						Reference to array to fill with style IDs.
 * @param size						Array size.
 * @noreturn
 */
native void Shavit_GetOrderedStyles(int[] arr, int size);

/**
 * Saves chat related strings on string references.
 *
 * @param stringtype				String type to grab.
 * @param ChatStrings				Reference to the string buffer.
 * @param size						Max length for the buffer.
 * @return							SP_ERROR_NONE on success, anything else on failure.
 */
native int Shavit_GetChatStrings(int stringtype, char[] ChatStrings, int size);

/**
 * Saves chat related strings on string references.
 *
 * @param strings                   Reference to a chatstrings_t.
 * @param size                      Size of chatstrings_t.
 * @return                          SP_ERROR_NONE on success, anything else on failure.
 */
native int Shavit_GetChatStringsStruct(any[] strings, int size = sizeof(chatstrings_t));

/**
 * Sets practice mode on a client.
 * Practice mode means that the client's records will not be saved, just like unranked mode, but for ranked styles.
 * Intended to be used by checkpoints.
 *
 * @param client					Client index.
 * @param practice					Enable or disable practice mode.
 * @param alert						Alert the client about practice mode?
 * @noreturn
 */
native void Shavit_SetPracticeMode(int client, bool practice, bool alert);

/**
 * Gets a client's practice mode status.
 *
 * @param client					Client index.
 * @return							Practice mode status.
 */
native bool Shavit_IsPracticeMode(int client);

/**
 * Save a client's timer into a snapshot.
 * See the timer_snapshot_t enum struct.
 *
 * @param client					Client index.
 * @param snapshot					Full snapshot of the client's timer.
 * @param size						Size of the snapshot buffer, e.g sizeof(timer_snapshot_t)
 * @noreturn
 */
native void Shavit_SaveSnapshot(int client, any[] snapshot, int size = sizeof(timer_snapshot_t));

/**
 * Restores the client's timer from a snapshot.
 *
 * @param client					Client index.
 * @param snapshot					Full snapshot of the client's timer.
 * @param size						Size of the snapshot buffer, e.g sizeof(timer_snapshot_t)
 * @return                          Success boolean
 */
native bool Shavit_LoadSnapshot(int client, any[] snapshot, int size = sizeof(timer_snapshot_t));

/**
 * Use this native to stop the click sound that plays upon chat messages.
 * Call it before each Shavit_PrintToChat().
 *
 * @noreturn
 */
native void Shavit_StopChatSound();

/**
 * Marks a map track as if it has built-in zones/buttons.
 *
 * @noreturn
 */
native void Shavit_MarkKZMap(int track);

/**
 * Lets us know if the map track was marked as a KZ map.
 * KZ map: a map with built-in zones/buttons.
 * Does not necessarily mean that the map was designed for KZ gameplay.
 *
 * @return							Boolean value.
 */
native bool Shavit_IsKZMap(int track);

/**
 * Retrieves style access for a player.
 *
 * @param client					Client index.
 * @param style						Style.
 * @return							Boolean value.
 */
native bool Shavit_HasStyleAccess(int client, int style);

/**
 * Determines whether a client's timer is paused or not.
 *
 * @param client					Client index.
 * @return							Boolean value.
 */
native bool Shavit_IsPaused(int client);

/**
 * Determines whether a client is able to pause their timer or not.
 *
 * @param client					Client index.
 * @return							Flags which are reasons to allow pausing or not, see CPR enum. 0 if toggling pause is allowed.
 */
native int Shavit_CanPause(int client);

/**
 * Use this native when printing anything in chat if it's related to the timer.
 * This native will auto-assign colors and a chat prefix.
 *
 * @param client					Client index.
 * @param format					Formatting rules.
 * @param any						Variable number of format parameters.
 * @return							PrintToChat()
 */
native int Shavit_PrintToChat(int client, const char[] format, any ...);

/**
 * Use this native when printing anything in chat if it's related to the timer.
 * This native will auto-assign colors and a chat prefix.
 *
 * @param format					Formatting rules.
 * @param any						Variable number of format parameters.
 * @noreturn
 */
native void Shavit_PrintToChatAll(const char[] format, any ...);

/**
 * Logs an entry to bhoptimer's log file.
 * (addons/sourcemod/logs/shavit.log)
 *
 * @param format					Formatting rules.
 * @param any						Variable number of format parameters.
 * @noreturn
 */
native void Shavit_LogMessage(const char[] format, any ...);

/**
 * Gets the average velocity of a player.
 * Average calculation: avg += (vel - avg) / frames
 *
 * @param client					Client index
 * @return							Client's average velocity
 */
native float Shavit_GetAvgVelocity(int client);

/**
 * Gets the max velocity of a player.
 *
 * @param client					Client index
 * @return							Client's highest velocity
 */
native float Shavit_GetMaxVelocity(int client);

/**
 * Sets the average velocity of a player.
 *
 * @param client					Client index
 * @param vel						Average velocity
 * @noreturn
 */
native void Shavit_SetAvgVelocity(int client, float vel);

/**
 * Gets the max velocity of a player.
 *
 * @param client					Client index
 * @param vel						Max velocity
 * @noreturn
 */
native void Shavit_SetMaxVelocity(int client, float vel);

/**
 * Sets the client's dynamic timescale (timer_snapshot_t.fTimescale)
 * Note: Values above 1.0 won't scale into the replay bot.
 * Timescale is limited to four decimal places. timescale >= 0.0001
 *
 * timer_countdown_timescale = fTimescale * style_timescale;
 * m_flLaggedMovementValue = fTimescale * style_timescale * style_speed * current_player_speedmod;
 * Eventqueuefix_timescale = fTimescale * style_timescale * style_speed;
 * See `UpdateLaggedMovement()` in shavit-core.sp for more info.
 *
 * @param client					Client index
 * @param scale						New timescale
 *
 * @noreturn
 */
native void Shavit_SetClientTimescale(int client, float scale);

/**
 * Gets the clients dynamic timescale (timer_snapshot_t.fTimescale).
 *
 * timer_countdown_timescale = fTimescale * style_timescale;
 * m_flLaggedMovementValue = fTimescale * style_timescale * style_speed * current_player_speedmod;
 * Eventqueuefix_timescale = fTimescale * style_timescale * style_speed;
 * See `UpdateLaggedMovement()` in shavit-core.sp for more info.
 *
 * @param client					Client index
 *
 * @return							Client's dynamic timescale
 */
native float Shavit_GetClientTimescale(int client);

/**
 * Something to be used by the checkpoint plugin to trigger updating laggedmovement.
 *
 * @param client                    Client index
 * @param user_timescale            Whether to use fTimescale as a multiplier for laggedmovement too.
 *
 * @noreturn
 */
native void Shavit_UpdateLaggedMovement(int client, bool user_timescale=true);

/**
 * Check if there are client cookies to retrieve. **NATIVE CURRENTLY USED ONLY FOR HUD**.
 *
 * @param client                    Client index
 *
 * @return                          True if there are client cookies retrieved and set to client.
 */
native bool Shavit_Core_CookiesRetrieved(int client);

/**
 * When using the timer's timescale_tas stuff, this returns whether the current frame should be recorded by replay plugins.
 *
 * @param client                    Client index
 *
 * @return                          True if the current frame should be recorded.
 */
native bool Shavit_ShouldProcessFrame(int client);

/**
 * Stops the player's timer and teleports them to the end zone.
 *
 * @param client
 * @param track
 *
 * @noreturn
 */
native void Shavit_GotoEnd(int client, int track);

public SharedPlugin __pl_shavit_core =
{
	name = "shavit",
	file = "shavit-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_core_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_CanPause");
	MarkNativeAsOptional("Shavit_ChangeClientStyle");
	MarkNativeAsOptional("Shavit_FinishMap");
	MarkNativeAsOptional("Shavit_FormatChat");
	MarkNativeAsOptional("Shavit_GetBhopStyle");
	MarkNativeAsOptional("Shavit_GetChatStrings");
	MarkNativeAsOptional("Shavit_GetChatStringsStruct");
	MarkNativeAsOptional("Shavit_GetClientJumps");
	MarkNativeAsOptional("Shavit_GetClientTime");
	MarkNativeAsOptional("Shavit_GetClientTrack");
	MarkNativeAsOptional("Shavit_GetDatabase");
	MarkNativeAsOptional("Shavit_GetOrderedStyles");
	MarkNativeAsOptional("Shavit_GetPerfectJumps");
	MarkNativeAsOptional("Shavit_GetStrafeCount");
	MarkNativeAsOptional("Shavit_GetStyleCount");
	MarkNativeAsOptional("Shavit_GetStyleSetting");
	MarkNativeAsOptional("Shavit_GetStyleSettingInt");
	MarkNativeAsOptional("Shavit_GetStyleSettingFloat");
	MarkNativeAsOptional("Shavit_GetStyleSettingBool");
	MarkNativeAsOptional("Shavit_HasStyleSetting");
	MarkNativeAsOptional("Shavit_GetStyleStrings");
	MarkNativeAsOptional("Shavit_GetStyleStringsStruct");
	MarkNativeAsOptional("Shavit_GetSync");
	MarkNativeAsOptional("Shavit_GetZoneOffset");
	MarkNativeAsOptional("Shavit_GetDistanceOffset");
	MarkNativeAsOptional("Shavit_GetTimerStatus");
	MarkNativeAsOptional("Shavit_HasStyleAccess");
	MarkNativeAsOptional("Shavit_IsKZMap");
	MarkNativeAsOptional("Shavit_IsPaused");
	MarkNativeAsOptional("Shavit_IsPracticeMode");
	MarkNativeAsOptional("Shavit_LoadSnapshot");
	MarkNativeAsOptional("Shavit_MarkKZMap");
	MarkNativeAsOptional("Shavit_PauseTimer");
	MarkNativeAsOptional("Shavit_PrintToChat");
	MarkNativeAsOptional("Shavit_PrintToChatAll");
	MarkNativeAsOptional("Shavit_RestartTimer");
	MarkNativeAsOptional("Shavit_ResumeTimer");
	MarkNativeAsOptional("Shavit_SaveSnapshot");
	MarkNativeAsOptional("Shavit_SetPracticeMode");
	MarkNativeAsOptional("Shavit_StartTimer");
	MarkNativeAsOptional("Shavit_StopChatSound");
	MarkNativeAsOptional("Shavit_StopTimer");
	MarkNativeAsOptional("Shavit_GetClientTimescale");
	MarkNativeAsOptional("Shavit_SetClientTimescale");
	MarkNativeAsOptional("Shavit_GetTimesTeleported");
	MarkNativeAsOptional("Shavit_SetStyleSetting");
	MarkNativeAsOptional("Shavit_SetStyleSettingFloat");
	MarkNativeAsOptional("Shavit_SetStyleSettingBool");
	MarkNativeAsOptional("Shavit_SetStyleSettingInt");
	MarkNativeAsOptional("Shavit_Core_CookiesRetrieved");
	MarkNativeAsOptional("Shavit_ShouldProcessFrame");
	MarkNativeAsOptional("Shavit_GotoEnd");
	MarkNativeAsOptional("Shavit_UpdateLaggedMovement");

	__pl_shavit_bhopstats_SetNTVOptional();
}
#endif
