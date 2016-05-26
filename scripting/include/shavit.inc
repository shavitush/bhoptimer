/*
 * Shavit's Timer - .inc file
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

#define MAX_STYLES 6
#define MAX_ZONES 7

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
	Style_Forwards = 0,
	Style_Sideways,
	Style_WOnly,
	Style_Scroll,
	Style_400Velocity,
	Style_HSW
};

#if defined USES_STYLE_PROPERTIES
#define STYLE_NONE				(0)
#define STYLE_AUTOBHOP			(1 << 0) // enable autobhop
#define STYLE_BLOCK_W			(1 << 1) // block +forward
#define STYLE_BLOCK_A			(1 << 2) // block +moveleft
#define STYLE_BLOCK_S			(1 << 3) // block +back
#define STYLE_BLOCK_D			(1 << 4) // block +moveright
#define STYLE_EASYBHOP			(1 << 5) // enable easybhop (disable stamina reset)
#define STYLE_VEL_LIMIT			(1 << 6) // allow velocity limits
#define STYLE_BLOCK_USE			(1 << 7) // block +use
#define STYLE_UNRANKED			(1 << 8) // unranked style. no ranking points and no records. (UNTESTED: REPORT ISSUES!)
#define STYLE_NOREPLAY			(1 << 9) // disable replay bot for this style. don't use for unranked styles.
#define STYLE_PRESPEED			(1 << 10) // allow prespeeding regardless of the prespeed setting
#define STYLE_HSW_ONLY			(1 << 11) // force half-sideways

int gI_StyleProperties[MAX_STYLES] =
{
	STYLE_AUTOBHOP|STYLE_EASYBHOP, // Forwards
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_BLOCK_A|STYLE_BLOCK_D, // Sideways
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_BLOCK_A|STYLE_BLOCK_D|STYLE_BLOCK_S, // W-Only
	STYLE_EASYBHOP, // Scroll
	STYLE_VEL_LIMIT, // 400 Velocity
	STYLE_AUTOBHOP|STYLE_EASYBHOP|STYLE_BLOCK_S|STYLE_HSW_ONLY // HSW
};
#endif

#if defined USES_STYLE_VELOCITY_LIMITS
#define VELOCITY_UNLIMITED 0.0

// only applies if STYLE_VEL_LIMIT is defined for a style
// use VELOCITY_UNLIMITED to ignore
float gF_VelocityLimit[MAX_STYLES] =
{
	VELOCITY_UNLIMITED, // Forwards
	VELOCITY_UNLIMITED, // Sideways
	VELOCITY_UNLIMITED, // W-Only
	VELOCITY_UNLIMITED, // Scroll
	400.00, // 400 Velocity
	VELOCITY_UNLIMITED // HSW
};
#endif

#if defined USES_STYLE_NAMES
// style names
char gS_BhopStyles[MAX_STYLES][] =
{
	"Forwards",
	"Sideways",
	"W-Only",
	"Scroll",
	"400 Velocity",
	"Half-Sideways"
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
	"B54CBB"
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
	"HSW"
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
	Zone_NoVelLimit
};

// let's not throw errors k?
stock bool IsValidClient(int client, bool bAlive = false) // when bAlive is false = technical checks, when it's true = gameplay checks
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

// time formatting!
stock void FormatSeconds(float time, char[] newtime, int newtimesize, bool precise = true)
{
	int iTemp = RoundToFloor(time);

	int iHours = 0;

	if(iTemp > 3600)
	{
		iHours = RoundToFloor(iTemp / 3600.0);
		iTemp %= 3600;
	}

	char[] sHours = new char[8];

	if(iHours < 10)
	{
		FormatEx(sHours, 8, "0%d", iHours);
	}

	else
	{
		FormatEx(sHours, 8, "%d", iHours);
	}

	int iMinutes = 0;

	if(iTemp >= 60)
	{
		iMinutes = RoundToFloor(iTemp / 60.0);
		iTemp %= 60;
	}

	char[] sMinutes = new char[8];

	if(iMinutes < 10)
	{
		FormatEx(sMinutes, 8, "0%d", iMinutes);
	}

	else
	{
		FormatEx(sMinutes, 8, "%d", iMinutes);
	}

	float fSeconds = ((iTemp) + time - RoundToFloor(time));

	char[] sSeconds = new char[16];

	if(fSeconds < 10)
	{
		FormatEx(sSeconds, 16, "0%.03f", fSeconds);
	}

	else
	{
		FormatEx(sSeconds, 16, "%.03f", fSeconds);
	}

	if(iHours > 0)
	{
		FormatEx(newtime, newtimesize, "%s:%s:%ss", sHours, sMinutes, sSeconds);
	}

	else if(iMinutes > 0)
	{
		FormatEx(newtime, newtimesize, "%s:%ss", sMinutes, sSeconds);
	}

	else
	{
		if(precise)
		{
			FormatEx(newtime, newtimesize, "%.03fs", fSeconds);
		}

		else
		{
			FormatEx(newtime, newtimesize, "%.01fs", fSeconds);
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
 * @noreturn
 */
forward void Shavit_OnFinish(int client, BhopStyle style, float time, int jumps);

/**
 * Called when there's a new WR on the map.
 *
 * @param client					Client index.
 * @param style						Style the record was done on.
 * @param time						Record time.
 * @param jumps						Jumps amount.
 * @noreturn
 */
forward void Shavit_OnWorldRecord(int client, BhopStyle style, float time, int jumps);

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
 * (re)Starts the timer for a player.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @noreturn
 */
native void Shavit_StartTimer(int client);

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
 * Checks if a mapzone exists.
 *
 * @param type						Mapzone type. (Check "enum MapZones")
 * @return							1 if exists, 0 if doesn't exist.
 */
native int Shavit_ZoneExists(MapZones type);
// ^ I could make it return a boolean instead, but I blame SM 1.7 for not letting me :/. You can use view_as<bool>() though :D

/**
 * Checks if a player is inside a mapzone
 *
 * @param client					Client index.
 * @param type						Mapzone type. (Check "enum MapZones")
 * @return							1 if is in the mapzone, 0 if isn't.
 */
native int Shavit_InsideZone(int client, MapZones type);

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
stock Shavit_PrintToChatAll(const char[] format, any ...)
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
