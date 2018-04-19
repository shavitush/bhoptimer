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

#define SHAVIT_VERSION "2.0.2"
#define STYLE_LIMIT 256
#define MAX_ZONES 64

// HUD
#define HUD_NONE				(0)
#define HUD_MASTER				(1 << 0) // master setting
#define HUD_CENTER				(1 << 1) // show hud as hint text
#define HUD_ZONEHUD				(1 << 2) // show start/end zone hud
#define HUD_OBSERVE				(1 << 3) // show the HUD of the player you spectate
#define HUD_SPECTATORS			(1 << 4) // show list of spectators
#define HUD_KEYOVERLAY			(1 << 5) // show a key overlay
#define HUD_HIDEWEAPON			(1 << 6) // hide the player's weapon
#define HUD_TOPLEFT				(1 << 7) // show top left white HUD with WR/PB times
#define HUD_SYNC				(1 << 8) // shows sync at right side of the screen (css only)
#define HUD_TIMELEFT			(1 << 9) // shows time left at right tside of the screen (css only)
#define HUD_2DVEL				(1 << 10) // shows 2d velocity
#define HUD_NOSOUNDS			(1 << 11) // disables sounds on personal best, world record etc

// for reference, not used anymore
// game types
enum ServerGame
{
	Game_CSS = 0,
	Game_CSGO,
	Game_Unknown
};

// status
enum TimerStatus
{
	Timer_Stopped = 0,
	Timer_Running,
	Timer_Paused
};

enum ReplayStatus
{
	Replay_Start = 0,
	Replay_Running,
	Replay_End,
	Replay_Idle
};

enum ReplayBotType
{
	Replay_Central = 0,
	Replay_Legacy
};

enum
{
	sStyleName,
	sShortName,
	sHTMLColor,
	sChangeCommand,
	sClanTag,
	sSpecialString,
	STYLESTRINGS_SIZE
};

enum
{
	bAutobhop,
	bEasybhop,
	bPrespeed,
	fVelocityLimit,
	bEnableBunnyhopping,
	fAiraccelerate,
	fRunspeed,
	fGravityMultiplier,
	fSpeedMultiplier,
	bHalftime,
	fVelocity,
	fBonusVelocity,
	fMinVelocity,
	bBlockW,
	bBlockA,
	bBlockS,
	bBlockD,
	bBlockUse,
	iForceHSW,
	bBlockPLeft,
	bBlockPRight,
	iBlockPStrafe,
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

enum
{
	bTimerEnabled,
	fCurrentTime,
	bClientPaused,
	iJumps,
	bsStyle,
	iStrafes,
	iTotalMeasures,
	iGoodGains,
	fServerTime,
	iSHSWCombination,
	iTimerTrack,
	TIMERSNAPSHOT_SIZE
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

enum(+=1)
{
	Zone_Start = 0,
	Zone_End,
	Zone_Respawn,
	Zone_Stop,
	Zone_Slay,
	Zone_Freestyle,
	Zone_NoVelLimit,
	Zone_Teleport,
	Zone_CustomSpawn,
	Zone_Easybhop,
	Zone_Slide,
	ZONETYPES_SIZE
};

enum
{
	bZoneInitialized,
	iZoneType,
	iZoneTrack, // 0 - main, 1 - bonus
	iEntityID,
	iDatabaseID,
	ZONECACHE_SIZE
};

enum
{
	Track_Main,
	Track_Bonus,
	TRACKS_SIZE
};

stock bool IsValidClient(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

stock bool IsSource2013(EngineVersion ev)
{
	return (ev == Engine_CSS || ev == Engine_TF2);
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
 * Called before shavit-core processes the client's usercmd.
 * Before this is called, safety checks (fake/dead clients) happen.
 * Use this forward in modules that use OnPlayerRunCmd to avoid errors and unintended behavior.
 * If a module conflicts with buttons/velocity/angles being changed in shavit-core, this forward is recommended.
 * This forward will NOT be called if a player's timer is paused.
 * 
 * @param client					Client index.
 * @param buttons					Buttons sent in the usercmd.
 * @param impulse					Impulse sent in the usercmd.
 * @param vel						A vector that contain's the player's desired movement. vel[0] is forwardmove, vel[1] is sidemove.
 * @param angles					The player's requested viewangles. They will not necessarily be applied as SRCDS itself won't accept every value.
 * @param status					The player's timer status.
 * @param track						The player's timer track.
 * @param style						The player's bhop style.
 * @param stylesettings				An array that contains the player's bhop style's settings.
 * @param mouse						Mouse direction (x, y).
 * @return							Plugin_Continue to let shavit-core keep doing what it does, Plugin_Changed to pass different values.
 */
forward Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, any stylesettings[STYLESETTINGS_SIZE], int mouse[2]);

/**
 * Called just before shavit-core adds time to a player's timer.
 * This is the forward you should use to modify the player's timer smoothly.
 * A good example use case is timescaling.
 *
 * @param client					Client index.
 * @param snapshot					A snapshot with the player's current timer. You cannot manipulate it here.
 * @param time						The time to be added to the player's timer.
 * @param stylesettings				An array that contains the player's bhop style's settings.
 * @noreturn
 */
forward void Shavit_OnTimeIncrement(int client, any snapshot[TIMERSNAPSHOT_SIZE], float &time, any stylesettings[STYLESETTINGS_SIZE]);

/**
 * Called just before shavit-core adds time to a player's timer.
 * This is the forward you should use to modify the player's timer smoothly.
 * A good example use case is timescaling.
 *
 * @param client					Client index.
 * @param snapshot					A snapshot with the player's current timer. Read above in shavit.inc for more information.
 * @param time						The time to be added to the player's timer.
 * @param stylesettings				An array that contains the player's bhop style's settings.
 * @noreturn
 */
forward void Shavit_OnTimeIncrementPost(int client, float time, any stylesettings[STYLESETTINGS_SIZE]);

/**
 * Called when a player's timer starts.
 * (WARNING: Will be called every tick when the player stands at the start zone!)
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @return							Plugin_Continue to do nothing or anything else to not start the timer.
 */
forward Action Shavit_OnStart(int client, int track);

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
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void Shavit_OnEnd(int client, int track);

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
forward Action Shavit_OnFinishPre(int client, any snapshot[TIMERSNAPSHOT_SIZE]);

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
 * @noreturn
 */
forward void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime);

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
 * @param track						Timer track.
 * @noreturn
 */
forward void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track);

/**
 * Called when there's a new WR on the map.
 *
 * @param client					Client index.
 * @param style						Style the record was done on.
 * @param time						Record time.
 * @param jumps						Jumps amount.
 * @param strafes					Amount of strafes.
 * @param sync						Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param track						Timer track.
 * @param oldwr						Time of the old WR. 0.0 if there's none.
 * @noreturn
 */
forward void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldwr);

/**
 * Called when an admin deletes a WR.
 *
 * @param style						Style the record was done on.
 * @param id						Record ID. -1 if mass deletion.
 * @param track						Timer track.
 * @noreturn
 */
forward void Shavit_OnWRDeleted(int style, int id, int track);

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
 * Called when the styles configuration finishes loading and it's ready to load everything into the cache.
 *
 * @param styles					Amount of styles loaded.
 * @noreturn
 */
forward void Shavit_OnStyleConfigLoaded(int styles);

/**
 * Called when there's a successful connection to the database.
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
 * Called when a player enters a zone.
 *
 * @param client					Client index.
 * @param type						Zone type.
 * @param track						Zone track.
 * @param id						Zone ID. 0 for native zones.
 * @param entity					Zone entity iD.
 * @noreturn
 */
forward void Shavit_OnEnterZone(int client, int type, int track, int id, int entity);

/**
 * Called when a player leaves a zone.
 *
 * @param client					Client index.
 * @param type						Zone type.
 * @param track						Zone track.
 * @param id						Zone ID. 0 for native zones.
 * @param entity					Zone entity iD.
 * @noreturn
 */
forward void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity);

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
 * @noreturn
 */
forward void Shavit_OnWorstRecord(int client, int style, float time, int jumps, int strafes, float sync, int track);

/**
 * Gets called when a map's tier is assigned.
 * Only called once per map, if the rankings plugin is enabled.
 * The exception is if the admin changes the current map's tier.
 *
 * @param map						Map display name.
 * @param tier						Map's tier.
 * @noreturn
 */
forward void Shavit_OnTierAssigned(const char[] map, int tier);

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
 #pragma deprecated Use Shavit_GetDatabase() instead.
native void Shavit_GetDB(Database &hSQL);

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
 * @noreturn
 */
native void Shavit_RestartTimer(int client, int track);

/**
 * Stops the timer for a player.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @noreturn
 */
native void Shavit_StopTimer(int client);

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
 * Stores the player's timer stats on variables
 *
 * @param client					Client index.
 * @param time						Time passed since the player started.
 * @param jumps						How many times the player jumped since he started.
 * @param style						Style, check "enum BhopStyle"
 * @param started					Timer started?
 * @noreturn
 */
#pragma deprecated Use different natives or Shavit_SaveSnapshot instead.
native void Shavit_GetTimer(int client, float &time, int &jumps, int &style, bool &started);

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
 * @param track						Timer track.
 * @noreturn
 */
native void Shavit_GetWRTime(int style, float &time, int track);

/**
 * Saves the WR's record ID for the current map on a variable.
 * Unused in base plugins, as of pre-1.4b.
 *
 * @param style						Style to get the WR for.
 * @param time						Reference to the time variable. 0.0 will be returned if no records.
 * @param track						Timer track.
 * @noreturn
 */
native void Shavit_GetWRRecordID(int style, int &recordid, int track);

/**
 * Saves the WR's player name on the map on a variable.
 *
 * @param style						Style to get the WR for.
 * @param wrname					Reference to the name variable.
 * @param wrmaxlength				Max length for the string.
 * @param track						Timer track.
 * @noreturn
 */
native void Shavit_GetWRName(int style, char[] wrname, int wrmaxlength, int track);

/**
 * Saves the player's personal best time on a variable.
 *
 * @param client					Client index.
 * @param style						Style to get the PB for.
 * @param time						Reference to the time variable. 0.0 will be returned if no personal record.
 * @param track						Timer track.
 * @noreturn
 */
native void Shavit_GetPlayerPB(int client, int style, float &time, int track);

/**
 * Get the amount of records on the current map/style on a track.
 *
 * @param style						Style.
 * @param track						Timer track.
 * @return							Amount of records.
 */
native int Shavit_GetRecordAmount(int style, int track);

/**
 * Calculate potential rank for a given style and time.
 *
 * @param style						Style.
 * @param time						Time to check for.
 * @param track						Timer track.
 * @return							Map rank.
 */
native int Shavit_GetRankForTime(int style, float time, int track);

/**
 * Retrieves the time of a record from a specified rank.
 *
 * @param style						Style.
 * @param rank						Rank to retrieve the time from.
 * @param track						Timer track.
 * @return							Record time. 0.0 if none.
 */
native float Shavit_GetTimeForRank(int style, int rank, int track);

/**
 * Checks if a mapzone exists.
 *
 * @param type						Mapzone type.
 * @param track						Mapzone track, -1 to ignore track.
 * @return							Boolean value.
 */
native bool Shavit_ZoneExists(int type, int track);

/**
 * Checks if a player is inside a mapzone
 *
 * @param client					Client index.
 * @param type						Mapzone type.
 * @param track						Mapzone track, -1 to ignore track.
 * @return							Boolean value.
 */
native bool Shavit_InsideZone(int client, int type, int track);

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
 * Retrieves the engine time of the replay bot's first frame.
 *
 * @param style						Style.
 * @param time						Reference to save the time on.
 * @noreturn
 */
native void Shavit_GetReplayBotFirstFrame(int style, float &time);

/**
 * Retrieve the replay bot's client index.
 *
 * @param style						Style.
 * @return							Client index for the replay bot.
 */
native int Shavit_GetReplayBotIndex(int style);

/**
 * Retrieve the style being played by the replay bot.
 *
 * @param client					Client index.
 * @return							Style being played by the replay bot. -1 if it's a central replay bot that's idle.
 */
native int Shavit_GetReplayBotStyle(int client);

/**
 * Retrieve the timer track being played by the replay bot.
 *
 * @param client					Client index.
 * @return							Timer track replayed by the bot. -1 if it's not a bot.
 */
native int Shavit_GetReplayBotTrack(int client);

/**
 * Gets the replay bot type setting of the server.
 *
 * @return							See ReplayBotType enum.
 */
native ReplayBotType Shavit_GetReplayBotType();

/**
 * Retrieve the replay bot's current played frame.
 *
 * @param style						Style.
 * @return							Current played frame.
 */
native int Shavit_GetReplayBotCurrentFrame(int style);

/**
 * Retrieves a replay's frame count.
 *
 * @param style						Style.
 * @param track						Track.
 * @noreturn
 */
native int Shavit_GetReplayFrameCount(int style, int track);

/**
 * Retrieves a replay's total length in seconds.
 *
 * @param style						Style.
 * @param track						Track.
 * @noreturn
 */
native float Shavit_GetReplayLength(int style, int track);

/**
 * Retrieves an actively playing replay's time.
 *
 * @param style						Style.
 * @param track						Track. (ignored for non-central bots)
 * @noreturn
 */
native float Shavit_GetReplayTime(int style, int track);

/**
 * Retrieves a replay holder's name.
 *
 * @param style						Style.
 * @param track						Track.
 * @param buffer					Buffer string.
 * @param length					String length.
 * @noreturn
 */
native void Shavit_GetReplayName(int style, int track, char[] buffer, int length);

/**
 * Checks if there's loaded replay data for a bhop style or not.
 *
 * @param style						Style.
 * @param track						Track.
 * @return							Boolean value of if there's loaded replay data.
 */
native bool Shavit_IsReplayDataLoaded(int style, int track);

/**
 * Gets player points.
 *
 * @param client					Client index.
 * @return							Points. 0.0 if unranked.
 */
native float Shavit_GetPoints(int client);

/**
 * Gets player rank.
 *
 * @param client					Client index.
 * @return							Rank. 0 if unranked.
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
native int Shavit_GetStyleSettings(int style, any StyleSettings[STYLESETTINGS_SIZE]);

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
 * Gets the HUD settings of a player.
 * See the HUD_* defines for information.
 *
 * @param client					Client index.
 * @return                          HUD settings.
 */
native int Shavit_GetHUDSettings(int client);

/**
 * Sets practice mode on a client.
 * Practice mode means that the client's records will not be saved, just like unranked mode, but for ranked styles.
 * Intended to be used by checkpoints.
 *
 * @param client					Client index.
 * @param practice					Enable or disable practice modce.
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
 * See the enumeration that ends with TIMERSNAPSHOT_SIZE.
 *
 * @param client					Client index.
 * @param snapshot					Full snapshot of the client's timer.
 * @noreturn
 */
native void Shavit_SaveSnapshot(int client, any snapshot[TIMERSNAPSHOT_SIZE]);

/**
 * Restores the client's timer from a snapshot.
 *
 * @param client					Client index.
 * @param snapshot					Full snapshot of the client's timer.
 * @noreturn
 */
native void Shavit_LoadSnapshot(int client, any snapshot[TIMERSNAPSHOT_SIZE]);

/**
 * Sets a player's replay recording frames from a provided ArrayList.
 * To be used by save states/TAS etc.
 *
 * @param client					Client index.
 * @param data						ArrayList with proper replay data.
 * @noreturn
 */
native void Shavit_SetReplayData(int client, ArrayList data);

/**
 * Saves a player's replay recording frames (if exists) into an ArrayList.
 * To be used by save states/TAS etc.
 *
 * @param client					Client index.
 * @return							ArrayList with proper replay data, or null if the player has no recorded data.
 */
native ArrayList Shavit_GetReplayData(int client);

/**
 * Reloads a specific replay into the replay bot cache.
 * Note: Not guaranteed to work with legacy replay bots.
 *
 * @param style						Replay style.
 * @param track						Replay track.
 * @param restart					Restart the playback of the replay bot if it's playing?
 * @param path						Path to the replay file. Use `BuildPath(Path_SM, ...)` to generate one. Leave as empty to use default.
 * @return							Was the replay loaded?
 */
native bool Shavit_ReloadReplay(int style, int track, bool restart, char[] path = "");

/**
 * Reloads all of the replays for the map.
 * Note: Not guaranteed to work with legacy replay bots.
 *
 * @param restart					Restart the playback of the replay bots?
 * @return							Amount of loaded replays.
 */
native int Shavit_ReloadReplays(bool restart);

/**
 * Use this native to stop the chat tick sound that happens in CS:S.
 * Call it before each Shavit_PrintToChat() or Shavit_PrintToChatAll().
 *
 * @noreturn
 */
native void Shavit_StopChatSound();

/**
 * Marks a map as if it has built-in zones/buttons.
 *
 * @noreturn
 */
native void Shavit_MarkKZMap();

/**
 * Lets us know if the map was marked as a KZ map.
 * KZ map: a map with built-in zones/buttons.
 * Does not necessarily mean that the map was designed for KZ gameplay.
 *
 * @return							Boolean value.
 */
native bool Shavit_IsKZMap();

/**
 * Gets the map tier for a specified map.
 * Use the map's display name.
 *
 * @param map						Map to get the tier of.
 * @return							Map tier. 0 if no results were found.
 */
native int Shavit_GetMapTier(const char[] map);

/**
 * Gets a StringMap that contains all the cached map tiers.
 * The returned StringMap must be deleted from memory after use!
 *
 * @return							StringMap with {const char[]: map, int: tier} structure.
 */
native StringMap Shavit_GetMapTiers();

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
 * Logs an entry to bhoptimer's log file.
 * (addons/sourcemod/logs/shavit.log)
 *
 * @param format					Formatting rules.
 * @param any						Variable number of format parameters.
 * @noreturn
 */
native void Shavit_LogMessage(const char[] format, any ...);

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
	MarkNativeAsOptional("Shavit_GetClientJumps");
	MarkNativeAsOptional("Shavit_GetClientTime");
	MarkNativeAsOptional("Shavit_GetClientTrack");
	MarkNativeAsOptional("Shavit_GetDatabase");
	MarkNativeAsOptional("Shavit_GetDB");
	MarkNativeAsOptional("Shavit_GetHUDSettings");
	MarkNativeAsOptional("Shavit_GetMapTier");
	MarkNativeAsOptional("Shavit_GetMapTiers");
	MarkNativeAsOptional("Shavit_GetPlayerPB");
	MarkNativeAsOptional("Shavit_GetPoints");
	MarkNativeAsOptional("Shavit_GetRank");
	MarkNativeAsOptional("Shavit_GetRankedPlayers");
	MarkNativeAsOptional("Shavit_GetRankForTime");
	MarkNativeAsOptional("Shavit_GetRecordAmount");
	MarkNativeAsOptional("Shavit_GetReplayBotCurrentFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");
	MarkNativeAsOptional("Shavit_GetReplayBotStyle");
	MarkNativeAsOptional("Shavit_GetReplayBotTrack");
	MarkNativeAsOptional("Shavit_GetReplayBotType");
	MarkNativeAsOptional("Shavit_GetReplayData");
	MarkNativeAsOptional("Shavit_GetReplayFrameCount");
	MarkNativeAsOptional("Shavit_GetReplayLength");
	MarkNativeAsOptional("Shavit_GetReplayName");
	MarkNativeAsOptional("Shavit_GetReplayTime");
	MarkNativeAsOptional("Shavit_GetStrafeCount");
	MarkNativeAsOptional("Shavit_GetStyleCount");
	MarkNativeAsOptional("Shavit_GetStyleSettings");
	MarkNativeAsOptional("Shavit_GetStyleStrings");
	MarkNativeAsOptional("Shavit_GetSync");
	MarkNativeAsOptional("Shavit_GetTimeForRank");
	MarkNativeAsOptional("Shavit_GetTimer");
	MarkNativeAsOptional("Shavit_GetTimerStatus");
	MarkNativeAsOptional("Shavit_GetWRCount");
	MarkNativeAsOptional("Shavit_GetWRName");
	MarkNativeAsOptional("Shavit_GetWRRecordID");
	MarkNativeAsOptional("Shavit_GetWRTime");
	MarkNativeAsOptional("Shavit_InsideZone");
	MarkNativeAsOptional("Shavit_IsClientCreatingZone");
	MarkNativeAsOptional("Shavit_IsKZMap");
	MarkNativeAsOptional("Shavit_IsPracticeMode");
	MarkNativeAsOptional("Shavit_IsReplayDataLoaded");
	MarkNativeAsOptional("Shavit_LoadSnapshot");
	MarkNativeAsOptional("Shavit_MarkKZMap");
	MarkNativeAsOptional("Shavit_OpenStatsMenu");
	MarkNativeAsOptional("Shavit_PauseTimer");
	MarkNativeAsOptional("Shavit_PrintToChat");
	MarkNativeAsOptional("Shavit_ReloadReplay");
	MarkNativeAsOptional("Shavit_ReloadReplays");
	MarkNativeAsOptional("Shavit_RestartTimer");
	MarkNativeAsOptional("Shavit_ResumeTimer");
	MarkNativeAsOptional("Shavit_SaveSnapshot");
	MarkNativeAsOptional("Shavit_SetPracticeMode");
	MarkNativeAsOptional("Shavit_SetReplayData");
	MarkNativeAsOptional("Shavit_StartTimer");
	MarkNativeAsOptional("Shavit_StopChatSound");
	MarkNativeAsOptional("Shavit_StopTimer");
	MarkNativeAsOptional("Shavit_ZoneExists");
}
#endif
