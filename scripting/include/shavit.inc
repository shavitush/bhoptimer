/*
 * shavit's Timer - .inc file
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

#if defined _shavit_included
	#endinput
#endif
#define _shavit_included

//#pragma newdecls required

#define SHAVIT_VERSION "1.5b"

#define PREFIX "\x04[Timer]\x01"

#define MAX_STYLES 8
#define MAX_ZONES 8

// game types
enum ServerGame(+=1)
{
	Game_CSS = 0,
	Game_CSGO,
	Game_Unknown
};

// bhop styles
// enum - for easier customization of settings
enum BhopStyle(+=1)
{
	Style_Normal = 0,
	Style_Sideways,
	Style_WOnly,
	Style_Scroll,
	Style_400Velocity,
	Style_HSW,
	Style_LowGravity,
	Style_SlowMotion
};

// status
enum TimerStatus(+=1)
{
	Timer_Stopped = 0,
	Timer_Running,
	Timer_Paused
};

enum ReplayStatus(+=1)
{
	Replay_Start = 0,
	Replay_Running,
	Replay_End
};

#if defined USES_STYLE_PROPERTIES
#define STYLE_NONE				(0)
#define STYLE_AUTOBHOP			(1 << 0)	// enable autobhop
#define STYLE_BLOCK_W			(1 << 1)	// block +forward
#define STYLE_BLOCK_A			(1 << 2)	// block +moveleft
#define STYLE_BLOCK_S			(1 << 3)	// block +back
#define STYLE_BLOCK_D			(1 << 4)	// block +moveright
#define STYLE_EASYBHOP			(1 << 5)	// enable easybhop (disable stamina reset)
#define STYLE_VEL_LIMIT			(1 << 6)	// allow velocity limits
#define STYLE_BLOCK_USE			(1 << 7)	// block +use
#define STYLE_UNRANKED			(1 << 8)	// unranked style. no ranking points and no records. (UNTESTED: REPORT ISSUES!)
#define STYLE_NOREPLAY			(1 << 9)	// disable replay bot for this style. don't use for unranked styles
#define STYLE_PRESPEED			(1 << 10)	// allow prespeeding regardless of the prespeed setting
#define STYLE_HSW_ONLY			(1 << 11)	// force half-sideways
#define STYLE_100AA				(1 << 12)	// force 100 airacclerate for the style
#define STYLE_LOWGRAV			(1 << 13)	// 0.6x gravity (standard for low gravity styles)
#define STYLE_SLOWMO			(1 << 14)	// 0.5x speed (standard for slowmo styles)
#define STYLE_SLOWMOTIME		(1 << 15)	// calculation of times will be halved, replays WILL NOT function properly
#define STYLE_MEASURESYNC		(1 << 16)	// measure sync for that style, useless for non-forwards styles like SW

int gI_StyleProperties[MAX_STYLES] =
{
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_MEASURESYNC, // Normal
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_BLOCK_A|STYLE_BLOCK_D, // Sideways
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_BLOCK_A|STYLE_BLOCK_D|STYLE_BLOCK_S, // W-Only
	STYLE_EASYBHOP|STYLE_MEASURESYNC, // Scroll
	STYLE_VEL_LIMIT|STYLE_MEASURESYNC, // 400 Velocity
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_HSW_ONLY|STYLE_MEASURESYNC, // HSW
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_LOWGRAV|STYLE_UNRANKED|STYLE_MEASURESYNC, // Low gravity
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_SLOWMO|STYLE_SLOWMOTIME|STYLE_UNRANKED|STYLE_MEASURESYNC // Slow motion
};
#endif

#if defined USES_STYLE_VELOCITY_LIMITS
#define VELOCITY_UNLIMITED 0.0

// only applies if STYLE_VEL_LIMIT is defined for a style
// use VELOCITY_UNLIMITED to ignore
float gF_VelocityLimit[MAX_STYLES] =
{
	VELOCITY_UNLIMITED, // Normal
	VELOCITY_UNLIMITED, // Sideways
	VELOCITY_UNLIMITED, // W-Only
	VELOCITY_UNLIMITED, // Scroll
	400.00, // 400 Velocity
	VELOCITY_UNLIMITED, // HSW
	VELOCITY_UNLIMITED, // Low gravity
	VELOCITY_UNLIMITED, // Slow motion
};
#endif

#if defined USES_STYLE_NAMES
// style names
char gS_BhopStyles[MAX_STYLES][] =
{
	"Normal",
	"Sideways",
	"W-Only",
	"Scroll",
	"400 Velocity",
	"Half-Sideways",
	"Low Gravity",
	"Slow Motion"
};
#endif

#if defined USES_STYLE_HTML_COLORS
// style HTML colors, for CS:GO HUD
char gS_StyleHTMLColors[MAX_STYLES][] =
{
	"797FD4",
	"B54CB3",
	"9A59F0",
	"279BC2",
	"C9BB8B",
	"B54CBB",
	"DB88C2",
	"C288DB"
};
#endif

#if defined USES_SHORT_STYLE_NAMES
// short names - up to 8 characters please
char gS_ShortBhopStyles[MAX_STYLES][] =
{
	"NM",
	"SW",
	"W",
	"LEGIT",
	"400VEL",
	"HSW",
	"LG",
	"SLOW"
};
#endif

#if defined USES_STYLE_MULTIPLIERS
// ranking system
float gI_RankingMultipliers[MAX_STYLES] =
{
	1.00, // Normal
	1.30, // Sideways
	1.33, // W-Only
	1.30, // Scroll
	1.50, // 400 Velocity
	1.20, // HSW
	0.00, // Low gravity
	0.00 // Slow motion
};
#endif

#if defined USES_CHAT_COLORS
// hardcoded colors
char gS_GlobalColorNames[][] =
{
	"{default}",
	"{team}",
	"{green}"
};

char gS_GlobalColors[][] =
{
	"\x01",
	"\x03",
	"\x04"
};

char gS_CSGOColorNames[][] =
{
	"{blue}",
	"{bluegrey}",
	"{darkblue}",
	"{darkred}",
	"{gold}",
	"{grey}",
	"{grey2}",
	"{lightgreen}",
	"{lightred}",
	"{lime}",
	"{orchid}",
	"{yellow}",
	"{palered}"
};

char gS_CSGOColors[][] =
{
	"\x0B",
	"\x0A",
	"\x0C",
	"\x02",
	"\x10",
	"\x08",
	"\x0D",
	"\x05",
	"\x0F",
	"\x06",
	"\x0E",
	"\x09",
	"\x07"
};
#endif

// map zones
#define MULTIPLEZONES_LIMIT 32

enum MapZones(+=1)
{
	Zone_Start = 0,
	Zone_End,
	Zone_Respawn,
	Zone_Stop,
	Zone_Slay,
	Zone_Freestyle,
	Zone_NoVelLimit,
	Zone_Teleport
};

// let's not throw errors k?
stock bool IsValidClient(int client, bool bAlive = false) // when bAlive is false = technical checks, when it's true = gameplay checks
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

// time formatting!
stock void FormatSeconds(float time, char[] newtime, int newtimesize, bool precise = true)
{
	float fTempTime = time;

	if(fTempTime < 0.0)
	{
		fTempTime = -fTempTime;
	}

	int iRounded = RoundToFloor(fTempTime);
	float fSeconds = (iRounded % 60) + fTempTime - iRounded;

	char[] sSeconds = new char[8];
	FormatEx(sSeconds, 8, precise? "%s%.03f":"%s%.01f", (fSeconds < 0.0)? "-":"", fSeconds);

	if(fTempTime < 60.0)
	{
		strcopy(newtime, newtimesize, sSeconds);
	}

	else
	{
		int iMinutes = (iRounded / 60);

		if(fTempTime < 3600.0)
		{
			FormatEx(newtime, newtimesize, "%s%d:%s%s", (time < 0.0)? "-":"", iMinutes, (fSeconds < 10)? "0":"", sSeconds);
		}

		else
		{
			iMinutes %= 60;
			int iHours = (iRounded / 3600);

			FormatEx(newtime, newtimesize, "%s%d:%s%d:%s%s", (time < 0.0)? "-":"", iHours, (iMinutes < 10)? "0":"", iMinutes, (fSeconds < 10)? "0":"", sSeconds);
		}
	}
}

/**
 * Called when a player's timer starts.
 * (WARNING: Will be called every tick when the player stands at the start zone!)
 *
 * @param client					Client index.
 * @noreturn
 */
forward void Shavit_OnStart(int client);

/**
 * Called when a player uses the restart command.
 *
 * @param client					Client index.
 * @noreturn
 */
forward void Shavit_OnRestart(int client);

/**
 * Called when a player uses the !end command.
 *
 * @param client					Client index.
 * @noreturn
 */
forward void Shavit_OnEnd(int client);

/**
 * Called when a player's timer stops. (stop =/= finish a map)
 *
 * @param client					Client index.
 * @noreturn
 */
forward void Shavit_OnStop(int client);

/**
 * Called when a player finishes a map. (touches the end zone)
 *
 * @param client					Client index.
 * @param style						Style the record was done on.
 * @param time						Record time.
 * @param jumps						Jumps amount.
 * @param strafes					Amount of strafes.
 * @param sync						Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @noreturn
 */
forward void Shavit_OnFinish(int client, BhopStyle style, float time, int jumps, int strafes, float sync);

/**
 * Like Shavit_OnFinish, but after the insertion query was called.
 * Called from shavit-wr
 *
 * @param client					Client index.
 * @param style						Style the record was done on.
 * @param time						Record time.
 * @param jumps						Jumps amount.
 * @param strafes					Amount of strafes.
 * @param sync						Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param rank						Rank on map.
 * @param overwrite					1 - brand new record. 2 - update.
 * @noreturn
 */
forward void Shavit_OnFinish_Post(int client, BhopStyle style, float time, int jumps, int strafes, float sync, int rank, int overwrite);

/**
 * Called when there's a new WR on the map.
 *
 * @param client					Client index.
 * @param style						Style the record was done on.
 * @param time						Record time.
 * @param jumps						Jumps amount.
 * @param strafes					Amount of strafes.
 * @param sync						Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @noreturn
 */
forward void Shavit_OnWorldRecord(int client, BhopStyle style, float time, int jumps, int strafes, float sync);

/**
 * Called when an admin deletes a WR.
 *
 * @param style						Style the record was done on.
 * @param id						Record ID. -1 if mass deletion.
 * @noreturn
 */
forward void Shavit_OnWRDeleted(BhopStyle style, int id);

/**
 * Called when a player's timer paused.
 *
 * @param client					Client index.
 * @noreturn
 */
forward void Shavit_OnPause(int client);

/**
 * Called when a player's timer resumed.
 *
 * @param client					Client index.
 * @noreturn
 */
forward void Shavit_OnResume(int client);

/**
 * Called when a player's rank has updated or was just looked up.
 * Will be called on initial rank lookup.
 *
 * @param client					Client index.
 * @noreturn
 */
forward void Shavit_OnRankUpdated(int client);

/**
 * Called when a player changes his bhopstyle.
 *
 * @param client					Client index.
 * @param oldstyle					Old bhop style.
 * @param newstyle					New bhop style.
 * @noreturn
 */
forward void Shavit_OnStyleChanged(int client, BhopStyle oldstyle, BhopStyle newstyle);

/**
 * Returns the game type the server is running.
 *
 * @return							Game type. (See "enum ServerGame")
 */
native ServerGame Shavit_GetGameType();

/**
 * Returns the database handle the timer is using.
 *
 * @param hSQL						Handle to store the database on.
 * @noreturn
 */
native void Shavit_GetDB(Database &hSQL);

/**
 * Starts the timer for a player.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @noreturn
 */
native void Shavit_StartTimer(int client);

/**
 * Restarts the timer for a player.
 * Will work as if the player just used sm_r.
 *
 * @param client					Client index.
 * @noreturn
 */
native void Shavit_RestartTimer(int client);

/**
 * Stops the timer for a player.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @noreturn
 */
native void Shavit_StopTimer(int client);

/**
 * Finishes the map for a player, with his current timer stats.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @noreturn
 */
native void Shavit_FinishMap(int client);

/**
 * Stores the player's timer stats on variables
 *
 * @param client					Client index.
 * @param time						Time passed since the player started.
 * @param jumps						How many times the player jumped since he started.
 * @param style						Style, check "enum BhopStyle"
 * @param started					Timer started?
 * @noreturn
 */
native void Shavit_GetTimer(int client, float &time, int &jumps, BhopStyle &style, bool &started);

/**
 * Retrieve a client's current time.
 *
 * @param client					Client index.
 * @return                          Current time.
 */
native float Shavit_GetClientTime(int client);

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
 * @return                          Bhop style.
 */
native BhopStyle Shavit_GetBhopStyle(int client);

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
 * Retrieve strafe sync since timer start.
 * Will return 0.0 if timer isn't running or -1.0 when not measured.
 *
 * @param client					Client index.
 * @return                          Amount of strafes since timer start.
 */
native float Shavit_GetSync(int client);

/**
 * Saves the WR time for the current map on a variable.
 *
 * @param style						Style to get the WR for.
 * @param time						Reference to the time variable. 0.0 will be returned if no records.
 * @noreturn
 */
native void Shavit_GetWRTime(BhopStyle style, float &time);

/**
 * Saves the WR's record ID for the current map on a variable.
 * Unused in base plugins, as of pre-1.4b.
 *
 * @param style						Style to get the WR for.
 * @param time						Reference to the time variable. 0.0 will be returned if no records.
 * @noreturn
 */
native void Shavit_GetWRRecordID(BhopStyle style, int &recordid);

/**
 * Saves the WR's player name on the map on a variable.
 *
 * @param style						Style to get the WR for.
 * @param wrname					Reference to the name variable.
 * @param wrmaxlength				Max length for the string.
 * @noreturn
 */
native void Shavit_GetWRName(BhopStyle style, char[] wrname, int wrmaxlength);

/**
 * Saves the player's personal best time on a variable.
 *
 * @param client					Client index.
 * @param style						Style to get the PB for.
 * @param time						Reference to the time variable. 0.0 will be returned if no personal record.
 * @noreturn
 */
native void Shavit_GetPlayerPB(int client, BhopStyle style, float &time);

/**
 * Get the amount of records on the current map/style.
 *
 * @param style						Bhop style.
 * @return							Amount of records.
 */
native int Shavit_GetRecordAmount(BhopStyle style);

/**
 * Calculate potential rank for a given style and time.
 *
 * @param style						Bhop style.
 * @param time						Time to check for.
 * @return							Amount of records.
 */
native int Shavit_GetRankForTime(BhopStyle style, float time);

/**
 * Checks if a mapzone exists.
 *
 * @param type						Mapzone type. (Check "enum MapZones")
 * @return							Boolean value.
 */
native bool Shavit_ZoneExists(MapZones type);

/**
 * Checks if a player is inside a mapzone
 *
 * @param client					Client index.
 * @param type						Mapzone type. (Check "enum MapZones")
 * @return							Boolean value.
 */
native bool Shavit_InsideZone(int client, MapZones type);

/**
 * Checks if a player is in the process of creating a mapzone.
 *
 * @param client					Client index.
 * @return							Boolean value.
 */
native bool Shavit_IsClientCreatingZone(int client);

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
 * @noreturn
 */
native void Shavit_ResumeTimer(int client);

/**
 * Retrieve the engine time of the replay bot's first frame.
 *
 * @param style						Bhop style.
 * @param time						Reference to save the time on.
 * @noreturn
 */
native void Shavit_GetReplayBotFirstFrame(BhopStyle style, float &time);

/**
 * Retrieve the replay bot's client index.
 *
 * @param style						Bhop style.
 * @return							Client index for the replay bot.
 */
native int Shavit_GetReplayBotIndex(BhopStyle style);

/**
 * Retrieve the replay bot's current played frame.
 *
 * @param style						Bhop style.
 * @return							Current played frame.
 */
native int Shavit_GetReplayBotCurrentFrame(BhopStyle style);

/**
 * Checks if there's loaded replay data for a bhop style or not.
 *
 * @param style						Bhop style.
 * @return							Boolean value of if there's loaded replay data.
 */
native bool Shavit_IsReplayDataLoaded(BhopStyle style);

/**
 * Gets player points.
 *
 * @param client					Client index.
 * @return							Points. 0.0 if unranked and -1.0 if lookup is due.
 */
native float Shavit_GetPoints(int client);

/**
 * Gets player rank.
 *
 * @param client					Client index.
 * @return							Rank. 0 if unranked and -1 if lookup is due.
 */
native int Shavit_GetRank(int client);

/**
 * Gets ranking values for the current map.
 * See CalculatePoints() in shavit-rankings.
 *
 * @param points					Reference to map points. -1.0 if not set.
 * @param idealtime					Reference to ideal time. 0.0 if not set.
 * @noreturn
 */
native void Shavit_GetMapValues(float &points, float &idealtime);

/**
 * Gets ranking values for a given map.
 * See CalculatePoints() in shavit-rankings.
 *
 * @param map						Map to get values from.
 * @param points					Reference to map points. -1.0 if not set.
 * @param idealtime					Reference to ideal time. 0.0 if not set.
 * @noreturn
 */
native void Shavit_GetGivenMapValues(const char[] map, float &points, float &idealtime);

/**
 * Gets the amount of players with over 0 points.
 *
 * @return							Amount of ranked players.
 */
native int Shavit_GetRankedPlayers();

/**
 * Calculates points for given time, style, ideal time and points for the ideal time.
 *
 * @param time						Time.
 * @param idealtime					Ideal time.
 * @param style						Bhop style.
 * @param mappoints					Points for the ideal time
 * @return							Calculated poiints.
 */
native float Shavit_CalculatePoints(float time, BhopStyle style, float idealtime, float mappoints);

/**
 * Force an HUD update for a player. Requires shavit-hud.
 *
 * @param client					Client index.
 * @param spectators                Should also update it for the player's spectators?
 * @error                           Error code 200 if client isn't valid.
 * @return                          Amount of players that had their HUD updated (client + spectators) or -1 on error.
 */
native int Shavit_ForceHUDUpdate(int client, bool spectators);

/**
 * Formats chats exactly like the chat handler does.
 * Takes team, alive status, rank and all those stuff into account.
 * Called from shavit-chat
 *
 * @param client					Client index.
 * @param message					Message to use.
 * @param team						Simulate a team chat message?
 * @param buffer					Buffer to store the formatted line on.
 * @param maxlen					Length of 'buffer'
 * @error                           Error code 200 if client isn't valid.
 * @return							-1 on error, SP_ERROR_NONE on success.
 */
native int Shavit_FormatChat(int client, const char[] message, const bool team, char[] buffer, int maxlen);

/**
 * Opens the stats menu for a client.
 *
 * @param client					Client index.
 * @param authid					Target SteamID3 to use.
 * @noreturn
 */
native void Shavit_OpenStatsMenu(int client, const char[] authid);

/**
 * Retrieves the amount of #1 records a player has.
 * Result will depend on the value of `shavit_stats_mvprankones`.
 * Called from shavit-stats.
 *
 * @param client					Client index.
 * @noreturn
 */
native int Shavit_GetWRCount(int client);

/**
 * Use this native when printing anything in chat if it's related to the timer.
 * This native will auto-assign colors and a chat prefix.
 *
 * @param client					Client index.
 * @param format					Formattiing rules.
 * @param any						Variable number of format parameters.
 * @return							PrintToChat()
 */
native int Shavit_PrintToChat(int client, const char[] format, any ...);

// same as Shavit_PrintToChat() but loops through the whole server
// code stolen from the base halflife.inc file
stock void Shavit_PrintToChatAll(const char[] format, any ...)
{
	char[] buffer = new char[255];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			// SetGlobalTransTarget(i); when we're out of beta
			VFormat(buffer, 255, format, 2);
			Shavit_PrintToChat(i, "%s", buffer);
		}
	}
}

public SharedPlugin __pl_shavit =
{
	name = "shavit",
	file = "shavit-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_CalculatePoints");
	MarkNativeAsOptional("Shavit_FinishMap");
	MarkNativeAsOptional("Shavit_ForceHUDUpdate");
	MarkNativeAsOptional("Shavit_FormatChat");
	MarkNativeAsOptional("Shavit_GetBhopStyle");
	MarkNativeAsOptional("Shavit_GetClientTime");
	MarkNativeAsOptional("Shavit_GetClientJumps");
	MarkNativeAsOptional("Shavit_GetGivenMapValues");
	MarkNativeAsOptional("Shavit_GetMapValues");
	MarkNativeAsOptional("Shavit_GetPlayerPB");
	MarkNativeAsOptional("Shavit_GetPoints");
	MarkNativeAsOptional("Shavit_GetRank");
	MarkNativeAsOptional("Shavit_GetRankForTime");
	MarkNativeAsOptional("Shavit_GetRankedPlayers");
	MarkNativeAsOptional("Shavit_GetReplayBotCurrentFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");
	MarkNativeAsOptional("Shavit_GetStrafeCount");
	MarkNativeAsOptional("Shavit_GetSync");
	MarkNativeAsOptional("Shavit_GetTimer");
	MarkNativeAsOptional("Shavit_GetTimerStatus");
	MarkNativeAsOptional("Shavit_GetWRCount");
	MarkNativeAsOptional("Shavit_GetWRName");
	MarkNativeAsOptional("Shavit_GetWRRecordID");
	MarkNativeAsOptional("Shavit_GetWRTime");
	MarkNativeAsOptional("Shavit_InsideZone");
	MarkNativeAsOptional("Shavit_IsClientCreatingZone");
	MarkNativeAsOptional("Shavit_IsReplayDataLoaded");
	MarkNativeAsOptional("Shavit_OpenStatsMenu");
	MarkNativeAsOptional("Shavit_PauseTimer");
	MarkNativeAsOptional("Shavit_PrintToChat");
	MarkNativeAsOptional("Shavit_RestartTimer");
	MarkNativeAsOptional("Shavit_ResumeTimer");
	MarkNativeAsOptional("Shavit_StartTimer");
	MarkNativeAsOptional("Shavit_StopTimer");
	MarkNativeAsOptional("Shavit_ZoneExists");
}
#endif
