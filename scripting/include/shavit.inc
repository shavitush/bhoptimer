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

#if !defined _dynamic_included
  #include <dynamic>
#endif

#pragma newdecls required

#define SHAVIT_VERSION "1.5b"
#define STYLE_LIMIT 256
#define MAX_ZONES 8

// for reference, not used anymore
// game types
enum ServerGame(+=1)
{
	Game_CSS = 0,
	Game_CSGO,
	Game_Unknown
};

// old enum was used for style configuration and is now here for reference
enum BhopStyle(+=1)
{
	Style_Default = 0
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

enum
{
	sStyleName,
	sShortName,
	sHTMLColor,
	sChangeCommand,
	STYLESTRINGS_SIZE
};

enum
{
	bAutobhop,
	bEasybhop,
	bPrespeed,
	fVelocityLimit,
	iAiraccelerate,
	fRunspeed,
	fGravityMultiplier,
	fSpeedMultiplier,
	bHalftime,
	bBlockW,
	bBlockA,
	bBlockS,
	bBlockD,
	bBlockUse,
	bForceHSW,
	bBlockPLeft,
	bBlockPRight,
	bBlockPStrafe,
	bUnranked,
	bNoReplay,
	bSync,
	bStrafeCountW,
	bStrafeCountA,
	bStrafeCountS,
	bStrafeCountD,
	fRankingMultiplier,
	iSpecial,
	STYLESETTINGS_SIZE
};

enum
{
	sMessagePrefix,
	sMessageText,
	sMessageWarning,
	sMessageVariable,
	sMessageVariable2,
	sMessageStyle,
	CHATSETTINGS_SIZE
};

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
	Zone_Teleport,
	Zone_CustomSpawn
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
 * Called when the styles configuration finishes loading and it's ready to load everything into the cache.
 *
 * @param styles					Amount of styles loaded.
 * @noreturn
 */
forward void Shavit_OnStyleConfigLoaded(int styles);

/**
 * Called when there's a successful connection to the database.
 *
 * @param db						Database handle.
 * @noreturn
 */
forward void Shavit_OnDatabaseLoaded(Database db);

/**
 * Called when the chat messages configuration finishes loading and it's ready to load everything into the cache.
 *
 * @noreturn
 */
forward void Shavit_OnChatConfigLoaded();

/**
 * Returns the game type the server is running.
 *
 * @return							Game type. (See "enum ServerGame")
 */
#pragma deprecated Use GetEngineVersion() instead.
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
 * Gets the amount of players with over 0 points.
 *
 * @return							Amount of ranked players.
 */
native int Shavit_GetRankedPlayers();

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
* Saves the style settings on `any` references.
*
* @param style						Style index.
* @param StyleSettings				Reference to the settings array.
* @return							SP_ERROR_NONE on success, anything else on failure.
*/
native int Shavit_GetStyleSettings(BhopStyle style, any StyleSettings[STYLESETTINGS_SIZE]);

/**
 * Saves the style related strings on string references.
 *
 * @param style						Style index.
 * @param stringtype				String type to grab.
 * @param StyleStrings				Reference to the string buffer.
 * @param size						Max length for the buffer.
 * @return							SP_ERROR_NONE on success, anything else on failure.
 */
native int Shavit_GetStyleStrings(BhopStyle style, int stringtype, char[] StyleStrings, int size);

/**
 * Retrieves the amount of styles in the server.
 *
 * @return							Amount of styles or -1 if there's an error.
 */
native int Shavit_GetStyleCount();

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
	char[] buffer = new char[300];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, 300, format, 2);
			Shavit_PrintToChat(i, "%s", buffer);
		}
	}
}

public SharedPlugin __pl_shavit =
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
public void __pl_shavit_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_FinishMap");
	MarkNativeAsOptional("Shavit_ForceHUDUpdate");
	MarkNativeAsOptional("Shavit_FormatChat");
	MarkNativeAsOptional("Shavit_GetBhopStyle");
	MarkNativeAsOptional("Shavit_GetChatStrings");
	MarkNativeAsOptional("Shavit_GetClientTime");
	MarkNativeAsOptional("Shavit_GetClientJumps");
	MarkNativeAsOptional("Shavit_GetPlayerPB");
	MarkNativeAsOptional("Shavit_GetPoints");
	MarkNativeAsOptional("Shavit_GetRank");
	MarkNativeAsOptional("Shavit_GetRankForTime");
	MarkNativeAsOptional("Shavit_GetRankedPlayers");
	MarkNativeAsOptional("Shavit_GetReplayBotCurrentFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");
	MarkNativeAsOptional("Shavit_GetStrafeCount");
	MarkNativeAsOptional("Shavit_GetStyleCount");
	MarkNativeAsOptional("Shavit_GetStyleSettings");
	MarkNativeAsOptional("Shavit_GetStyleStrings");
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
