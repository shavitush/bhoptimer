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

#define SHAVIT_VERSION "3.0.9a"
#define STYLE_LIMIT 256
#define MAX_ZONES 64
#define MAX_STAGES 51 // 😐 kind of arbitrary but also some space between this and MAX_ZONES

// HUD
#define HUD_NONE				0
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
#define HUD_NOPRACALERT			(1 << 12) // hides practice mode chat alert

#define SHAVIT_LOG_QUERIES 0

// status
enum TimerStatus
{
	Timer_Stopped,
	Timer_Running,
	Timer_Paused
};

enum //ReplayStatus
{
	Replay_Start,
	Replay_Running,
	Replay_End,
	Replay_Idle
};

enum //ReplayBotType
{
	Replay_Central,
	Replay_Looping, // these are the ones that loop styles, tracks, and (eventually) stages...
	Replay_Dynamic, // these are bots that spawn on !replay when the central bot is taken
	Replay_Prop,    // A prop entity that is being used as a replay...
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
	Migration_RemoveWorkshopMaptiers,
	Migration_RemoveWorkshopMapzones,
	Migration_RemoveWorkshopPlayertimes,
	Migration_LastLoginIndex,
	Migration_RemoveCountry,
	Migration_ConvertIPAddresses, // 5
	Migration_ConvertSteamIDsUsers,
	Migration_ConvertSteamIDsPlayertimes,
	Migration_ConvertSteamIDsChat,
	Migration_PlayertimesDateToInt,
	Migration_AddZonesFlagsAndData, // 10
	Migration_AddPlayertimesCompletions,
	Migration_AddCustomChatAccess,
	Migration_AddPlayertimesExactTimeInt,
	Migration_FixOldCompletionCounts, // old completions accidentally started at 2
	Migration_AddPrebuiltToMapZonesTable, // 15
	Migration_AddPlaytime,
	// sorry, this is kind of dumb but it's better than trying to manage which ones have
	// finished and which tables exist etc etc in a transaction or a completion counter...
	Migration_Lowercase_maptiers,
	Migration_Lowercase_mapzones,
	Migration_Lowercase_playertimes,
	Migration_Lowercase_stagetimeswr, // 20
	Migration_Lowercase_startpositions,
	MIGRATIONS_END
};

enum
{
	Zone_Start,
	Zone_End,
	Zone_Respawn,
	Zone_Stop,
	Zone_Slay,
	Zone_Freestyle,
	Zone_CustomSpeedLimit,
	Zone_Teleport,
	Zone_CustomSpawn,
	Zone_Easybhop,
	Zone_Slide,
	Zone_Airaccelerate,
	Zone_Stage,
	ZONETYPES_SIZE
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
	float fZoneOffset[2];
	float fDistanceOffset[2];
	float fAvgVelocity;
	float fMaxVelocity;
	float fTimescale;
	int iZoneIncrement; // convert to array for per zone offsets (?)
	float fTimescaledTicks;

	bool bPracticeMode;

	bool bJumped;
	bool bCanUseAllKeys;
	bool bOnGround;

	int iLastButtons;
	float fLastAngle;
	int iLandingTick;
	MoveType iLastMoveType;
	float fStrafeWarning;
}

enum struct cp_cache_t
{
	float fPosition[3];
	float fAngles[3];
	float fVelocity[3];
	MoveType iMoveType;
	float fGravity;
	float fSpeed;
	float fStamina;
	bool bDucked;
	bool bDucking;
	float fDucktime; // m_flDuckAmount in csgo
	float fDuckSpeed; // m_flDuckSpeed in csgo; doesn't exist in css
	int iFlags;
	timer_snapshot_t aSnapshot;
	char sTargetname[64];
	char sClassname[64];
	ArrayList aFrames;
	int iPreFrames;
	bool bSegmented;
	int iGroundEntity;
	int iSteamID;
	ArrayList aEvents;
	ArrayList aOutputWaits;
	float vecLadderNormal[3];
}

enum struct frame_t
{
	float pos[3];
	float ang[2];
	int buttons;
	// iReplayVersion >= 0x02
	int flags;
	MoveType mt;
	// Everything below is generally NOT loaded into memory for playback
	// iReplayVersion >= 0x06
	int mousexy; // `mousex | (mousey << 16)` // unpack with UnpackSignedShorts
	int vel; // basically `forwardmove | (sidemove << 16)` // unpack with UnpackSignedShorts
}

enum struct frame_cache_t
{
	int iFrameCount;
	float fTime;
	bool bNewFormat;
	int iReplayVersion;
	char sReplayName[MAX_NAME_LENGTH];
	int iPreFrames;
	ArrayList aFrames;
	// iReplayVersion >= 0x05
	int iPostFrames;
	float fTickrate;
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
	public void Query(SQLQueryCallback callback, const char[] query, any data = 0, DBPriority prio = DBPrio_Normal)
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

	public int AddQuery(const char[] query, any data = 0)
	{
#if SHAVIT_LOG_QUERIES
		Shavit_LogQuery(query);
#endif
		return this.AddQuery(query, data);
	}
}

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
	static char to_lowercase_table[256+1] = "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2A\x2B\x2C\x2D\x2E\x2F\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3A\x3B\x3C\x3D\x3E\x3F\x40\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x5B\x5C\x5D\x5E\x5F\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7A\x7B\x7C\x7D\x7E\x7F\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8A\x8B\x8C\x8D\x8E\x8F\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9A\x9B\x9C\x9D\x9E\x9F\xA0\xA1\xA2\xA3\xA4\xA5\xA6\xA7\xA8\xA9\xAA\xAB\xAC\xAD\xAE\xAF\xB0\xB1\xB2\xB3\xB4\xB5\xB6\xB7\xB8\xB9\xBA\xBB\xBC\xBD\xBE\xBF\xC0\xC1\xC2\xC3\xC4\xC5\xC6\xC7\xC8\xC9\xCA\xCB\xCC\xCD\xCE\xCF\xD0\xD1\xD2\xD3\xD4\xD5\xD6\xD7\xD8\xD9\xDA\xDB\xDC\xDD\xDE\xDF\xE0\xE1\xE2\xE3\xE4\xE5\xE6\xE7\xE8\xE9\xEA\xEB\xEC\xED\xEE\xEF\xF0\xF1\xF2\xF3\xF4\xF5\xF6\xF7\xF8\xF9\xFA\xFB\xFC\xFD\xFE\xFF";

	for (int i = 0; str[i] != 0; i++)
	{
		int x = str[i];
		str[i] = to_lowercase_table[x];
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

stock bool ReadMapsFolderHandler(const char path[PLATFORM_MAX_PATH], bool is_stringmap, Handle data, bool lowercase, bool display, bool iter_subfolders, bool use_valve_fs, char[][] exclude_prefixes, int exclude_count)
{
	bool first_iteration = StrEqual(path, "maps");
	DirectoryListing dir = OpenDirectory(path, use_valve_fs);

	if (dir == null)
	{
		return false;
	}

	char buffer[PLATFORM_MAX_PATH];
	FileType type;

	while (dir.GetNext(buffer, sizeof(buffer), type))
	{
		if (type == FileType_Directory)
		{
			if (buffer[0] == '.' && (buffer[1] == 0 || (buffer[1] == '.' && buffer[2] == 0)))
			{
				continue;
			}

			if (iter_subfolders)
			{
				char subfolder[PLATFORM_MAX_PATH];
				FormatEx(subfolder, sizeof(subfolder), "%s/%s", path, buffer);
				ReadMapsFolderHandler(subfolder, is_stringmap, data, lowercase, display, iter_subfolders, use_valve_fs, exclude_prefixes, exclude_count);
			}
		}
		else if (type == FileType_File)
		{
			int length = strlen(buffer);

			if (length < 5 || buffer[length-4] != '.') // a.bsp
			{
				continue;
			}

			if ((buffer[length-3] == 'b' && buffer[length-2] == 's' && buffer[length-1] == 'p') ||
			    (buffer[length-3] == 'u' && buffer[length-2] == 'g' && buffer[length-1] == 'c'))
			{
				buffer[length-4] = 0;

				if (lowercase)
				{
					LowercaseString(buffer);
				}

				bool skip = false;

				for (int i = 0; i < exclude_count; i++)
				{
					if (strncmp(buffer, exclude_prefixes[i], strlen(exclude_prefixes[i]), lowercase) == 0)
					{
						skip = true;
						break;
					}
				}

				if (skip)
				{
					continue;
				}

				if (!display && !first_iteration)
				{
					char temp[PLATFORM_MAX_PATH];
					int skip_this = 5; // strlen("maps/")
					FormatEx(temp, sizeof(temp), "%s/%s", path[skip_this], buffer);
					buffer = temp;
				}

				if (is_stringmap)
				{
					view_as<StringMap>(data).SetValue(buffer, false, false);
				}
				else
				{
					view_as<ArrayList>(data).PushString(buffer);
				}
			}
		}
	}

	delete dir;
	return true;
}

static char empty_excludes[][] = {""};

stock bool ReadMapsFolderStringMap(StringMap data, bool lowercase=true, bool display=false, bool iter_subfolders=true, bool use_valve_fs=true, char[][] exclude_prefixes=empty_excludes, int exclude_count=0)
{
	return ReadMapsFolderHandler("maps", true, data, lowercase, display, iter_subfolders, use_valve_fs, exclude_prefixes, exclude_count);
}

// don't forget to declare your ArrayList like below :)))
//// ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
stock bool ReadMapsFolderArrayList(ArrayList data, bool lowercase=true, bool display=false, bool iter_subfolders=true, bool use_valve_fs=true, char[][] exclude_prefixes=empty_excludes, int exclude_count=0)
{
	return ReadMapsFolderHandler("maps", false, data, lowercase, display, iter_subfolders, use_valve_fs, exclude_prefixes, exclude_count);
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

// Retrieves authid from STEAM_X:Y:Z and [U:1:123]
stock int SteamIDToAuth(const char[] sInput)
{
	char sSteamID[32];
	strcopy(sSteamID, sizeof(sSteamID), sInput);
	ReplaceString(sSteamID, 32, "\"", "");

	if (StrContains(sSteamID, "STEAM_") != -1)
	{
		ReplaceString(sSteamID, 32, "STEAM_", "");

		char parts[3][11];
		ExplodeString(sSteamID, ":", parts, 3, 11);

		// Let X, Y and Z constants be defined by the SteamID: STEAM_X:Y:Z.
		// Using the formula W=Z*2+Y, a SteamID can be converted:
		return StringToInt(parts[2]) * 2 + StringToInt(parts[1]);
	}
	else if (StrContains(sSteamID, "U:1:") != -1)
	{
		ReplaceString(sSteamID, 32, "[", "");
		ReplaceString(sSteamID, 32, "U:1:", "");
		ReplaceString(sSteamID, 32, "]", "");

		return StringToInt(sSteamID);
	}

	return 0;
}

// Can be used to unpack frame_t.mousexy and frame_t.vel
stock void UnpackSignedShorts(int x, int out[2])
{
	out[0] =  ((x        & 0xFFFF) ^ 0x8000) - 0x8000;
	out[1] = (((x >> 16) & 0xFFFF) ^ 0x8000) - 0x8000;
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
 * This is the forward you should use to modify the player's timer smoothly.
 * A good example use case is timescaling.
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
 * @param oldtime					The player's best time on the map before this finish.
 * @param perfs						Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel					Player's average velocity throughout the run.
 * @param maxvel					Player's highest reached velocity.
 * @param timestamp					System time of when player finished.
 * @noreturn
 */
forward void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp);

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
 * @param oldtime					The player's best time on the map before this finish.
 * @param perfs						Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel					Player's average velocity throughout the run.
 * @param maxvel					Player's highest reached velocity.
 * @param timestamp					System time of when player finished.
 * @noreturn
 */
forward void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldwr, float oldtime, float perfs, float avgvel, float maxvel, int timestamp);

/**
 * Called when an admin deletes a WR.
 *
 * @param style						Style the record was done on.
 * @param id						Record ID. -1 if mass deletion.
 * @param track						Timer track.
 * @param accountid					The account ID of the wr holder
 * @param mapname					The map name.
 * @noreturn
 */
forward void Shavit_OnWRDeleted(int style, int id, int track, int accountid, const char[] mapname);

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
 * Called when a player teleports with checkpoints.
 *
 * @param client					Client index.
 * @param index						Checkpoint that was teleported to.
 * @return							Plugin_Continue to allow teleporting, anything else to prevent.
 */
forward Action Shavit_OnTeleport(int client, int index);

/**
 * Called when a saves a checkpoint.
 *
 * @param client					Client index.
 * @param index						Checkpoint that was saved to.
 * @param overflow					Does this checkpoint shift the rest.
 * @return							Plugin_Continue to allow saving, anything else to prevent.
 */
forward Action Shavit_OnSave(int client, int index, bool overflow);

/**
 * Called when a player deletes a checkpoint.
 *
 * @param client					Client index.
 * @param index						Checkpoint that will be deleted.
 * @return							Plugin_Continue to continue deletion, anything else to prevent.
 */
forward Action Shavit_OnDelete(int client, int index);

/**
 * Called when a player enters a zone.
 *
 * @param client					Client index.
 * @param type						Zone type.
 * @param track						Zone track.
 * @param id						Zone ID.
 * @param entity					Zone trigger entity index.
 * @param data						Zone data if any.
 * @noreturn
 */
forward void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data);

/**
 * Called when a player leaves a zone.
 *
 * @param client					Client index.
 * @param type						Zone type.
 * @param track						Zone track.
 * @param id						Zone ID.
 * @param entity					Zone trigger entity index.
 * @param data						Zone data if any.
 * @noreturn
 */
forward void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data);

/**
 * Called when a player leaves a zone.
 *
 * @param client					Client index.
 * @param stageNumber				Stage number.
 * @param message					The stage time message that will be printed.
 * @param maxlen					The buffer size of message.
 * @return							Plugin_Handled to block the timer from printing msg to the client. Plugin_Continue to let the timer print msg.
 */
forward Action Shavit_OnStageMessage(int client, int stageNumber, char[] message, int maxlen);

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
 * Gets called when the server acknowledges the client's ranking status.
 * It is called after OnClientPostAdminCheck and at forced rank recalculations.
 *
 * @param client					Client index.
 * @param rank						Client's rank. (0 if unranked or unassigned)
 * @param points					Client's points. (0.0 if unranked or unassigned)
 * @param first						True if the forward is called after the initial connection, false if it is caused by recalculation.
 * @noreturn
 */
forward void Shavit_OnRankAssigned(int client, int rank, float points, bool first);

/**
 * Called when replay playback starts.
 * Will be called twice for every replay bot unless the replay is canceled before the second call. Use `delay_elapsed` to check for the first & second time.
 *
 * @param ent						Entity index for the replay.
 * @param type						The type of replay. Replay_Prop means `ent` is not a fakeclient, but instead a prop.
 * @param delay_elapsed             `false` when the replay bot just spawned but before the start delay has elapsed. `true` when the start delay has elapsed.
 * @noreturn
 */
forward void Shavit_OnReplayStart(int ent, int type, bool delay_elapsed);

/**
 * Called when replay playback ends.
 * Will be called twice for most replay bots unless the replay bot is canceled before it finishes. See `actually_finished`.
 *
 * @param client					Entity index for the replay.
 * @param type						The type of replay. Replay_Prop means `ent` is not a fakeclient, but instead a prop.
 * @param actually_finished         `false` when the replay runs out of frames and is starting the timer to despawn. `true` when the replay bot is about to despawn. `true` will always run.
 * @noreturn
 */
forward void Shavit_OnReplayEnd(int ent, int type, bool actually_finished);

/**
 * Called when all replays files have been loaded.
 *
 * @noreturn
 */
forward void Shavit_OnReplaysLoaded();

/**
 * Called when a player finishes a time. Allows you to save a replay even if the run is not a WR.
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
 * @param isbestreplay				If the time is the new replay.
 * @param istoolong					If the time is too long to save a replay if the time is a WR. Note: replays WON'T be full length if this is true.
 * @return							Return Plugin_Changed (or higher) to cause a copy of the replay to be saved. Return Plugin_Continue otherwise.
 */
forward Action Shavit_ShouldSaveReplayCopy(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong);

/**
 * Called when either a WR replay or a copy of a replay has been saved.
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
 * @param isbestreplay				If the time is the new replay.
 * @param istoolong					If the time is too long to save a replay if the time is a WR. Note: replays WON'T be full length if this is true.
 * @param iscopy					If the path points to a copy of the replay.
 * @param replaypath				Path to the saved replay.
 * @noreturn
 */
forward void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, bool iscopy, const char[] replaypath);

/**
 * Called when top left HUD updates.
 *
 * @param client					Client index that recieves the hud.
 * @param target					Target entity that is either the client or what the client is spectating.
 * @param topleft					Reference to the HUD buffer.
 * @param topleftlength				Max length of the topleft buffer.
 * @return							Plugin_Handled or Plugin_Stop to block the HUD message from appearing. Anything else to pass along new values.
 */
forward Action Shavit_OnTopLeftHUD(int client, int target, char[] topleft, int topleftlength);

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
 * Called before the timer finish message is printed to the users.
 *
 * @param client					Client index.
 * @param everyone					Is the message printed to everyone, or just the client?
 * @param snapshot					A snapshot of the client's timer when printing the message.
 * @param overwrite					Modify the database? 0 - no. 1 - brand new record. 2 - new personal best.
 * @param rank						Rank on map.
 * @param message					The finish message.
 * @param maxlen					Buffer size of message.
 * @param message2					A second line of info that is printed on finish.
 * @param maxlen2					Buffer size of message2.
 *
 * @return							Plugin_Handled or Plugin_Stop to stop the message. Anything else to use new values.
 */
forward Action Shavit_OnFinishMessage(int client, bool &everyone, timer_snapshot_t snapshot, int overwrite, int rank, char[] message, int maxlen, char[] message2, int maxlen2);

/**
 * Called when a clients dynamic timescale has been changed.
 *
 * @param client					Client index.
 * @param oldtimescale				The old timescale value
 * @param newtimescale				The new timescale value
 * @noreturn
 */
forward void Shavit_OnTimescaleChanged(int client, float oldtimescale, float newtimescale);

/**
 * Called after the checkpoint menu has been made and before it's sent to the client.
 *
 * @param client					Client index.
 * @param segmented					If the menu was a segmented menu
 * @return							Plugin_Handled or Plugin_Stop to stop the menu.
 */
forward Action Shavit_OnCheckPointMenuMade(int client, bool segmented);

/**
 * Called before a selection is processed in the main checkpoint menu.
 *
 * @param client					Client index.
 * @param param2					Second parameter in the callback, usually the item selected.
 * @param info						reference copy of the info string used in the callback
 * @param maxlength					length of the info buffer
 * @param currentCheckpoint			Clients current checkpoint
 * @param maxCPs					Max checkpoints the client can use
 * @return							Plugin_Continue to continue the callback.
 */
forward Action Shavit_OnCheckpointMenuSelect(int client, int param2, char[] info, int maxlength, int currentCheckpoint, int maxCPs);

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
 * Called after shavit-wr caches the current map's WRs.
 *
 * @noreturn
 */
forward void Shavit_OnWorldRecordsCached();

/**
 * Called when a player RTV's.
 * Requires shavit-mapchooser.
 *
 * @param client					Client index.
 * @noreturn
 */
forward void SMC_OnRTV(int client);

/**
 * Called when a player UNRTV's.
 * Requires shavit-mapchooser.
 *
 * @param client					Client index.
 * @noreturn
 */
forward void SMC_OnUnRTV(int client);

/**
 * Called when the map changes from an RTV.
 * Requires shavit-mapchooser.
 *
 * @noreturn
 */
forward void SMC_OnSuccesfulRTV();

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
 * Sets the player's current location as their spawn location for the specified track.
 *
 * @param client					Client index.
 * @param track 					Timer track.
 * @param anglesonly 				Whether to save angles only.
 * @noreturn
 */
native void Shavit_SetStart(int client, int track, bool anglesonly);

/**
 * Deletes the player's current set start position for the specified track.
 *
 * @param client					Client index.
 * @param track 					Timer track.
 * @noreturn
 */
native void Shavit_DeleteSetStart(int client, int track);

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
 * @param bypass					Bypass call to Shavit_OnStopPre?
 * @return							True if the operation went through.
 */
native bool Shavit_StopTimer(int client, bool bypass = true);

/**
 * Deletes all map records for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map						Map name.
 * @noreturn
 */
native void Shavit_WR_DeleteMap(const char[] map);

/**
 * Deletes all map zones for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map						Map name.
 * @noreturn
 */
native void Shavit_Zones_DeleteMap(const char[] map);

/**
 * Deletes all replays for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map						Map name.
 * @noreturn
 */
native void Shavit_Replay_DeleteMap(const char[] map);

/**
 * Deletes tier setting for the specified map.
 * Points recalculation will run right after this is finished.
 *
 * @param map						Map name.
 * @noreturn
 */
native void Shavit_Rankings_DeleteMap(const char[] map);

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
 * Retrieve the zone ID for a given stage number.
 * Will return exception if stagenumber doesn't have a zone.
 *
 * @param stage                     Stage number.
 * @param track                     Track number.
 * @return                          Zone ID of stage.
 */
native int Shavit_GetStageZone(int stage, int track=Track_Main);

/**
 * Retrieve the highest stage number for a given track.
 *
 * @param track						Track number.
 * @return 							Number of stages.
 */
native int Shavit_GetHighestStage(int track);

/**
 * Retrieve the client's current stage number.
 *
 * @param client                    Client index.
 * @return                          The client's current stage number.
 */
native int Shavit_GetClientLastStage(int client);

/**
 * Retrieve the WR's stage time.
 *
 * @param track                     Track index.
 * @param style                     Style index.
 * @param stage                     Stage number.
 * @return                          The stage time of the WR run. Can be 0.0 if the WR run didn't hit the stage or if the stage doesn't exist.
 */
native float Shavit_GetStageWR(int track, int style, int stage);

/**
 * Retrieve the client's PB stage time.
 *
 * @param client                    Client index.
 * @param track                     Track index.
 * @param style                     Style index.
 * @param stage                     Stage number.
 * @return                          The stage time of the PB run. Can be 0.0 if the PB run didn't hit the stage or if the stage doesn't exist.
 */
//native float Shavit_GetStagePB(int client, int track, int style, int stage);

//native float Shavit_GetStageWRCP(int track, int style, int stage);
//native float Shavit_GetStagePBCP(int client, int track, int style, int stage);

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
 * Retrieves the world record for the given style/track.
 *
 * @param style						Style to get the WR for.
 * @param track						Timer track.
 * @return							World record for the specified settings.
 */
native float Shavit_GetWorldRecord(int style, int track);

/**
 * Reloads WR leaderboards cache for the current map.
 *
 * @noreturn
 */
native void Shavit_ReloadLeaderboards();

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
 * Retrieves the best time of a player.
 *
 * @param client					Client index.
 * @param style						Style to get the PB for.
 * @param track						Timer track.
 * @return							Floating number of the player's best time for given style/track.
 */
native float Shavit_GetClientPB(int client, int style, int track);

/**
 * Sets the cached pb directly for the given client, style and track.
 *
 * @param client					Client index.
 * @param style						Style to get the PB for.
 * @param track						Timer track.
 * @param time						Time to set
 * @noreturn
 */
native void Shavit_SetClientPB(int client, int style, int track, float time);

/**
 * Retrieves the completions of a player.
 *
 * @param client					Client index.
 * @param style						Style to get the Completions for.
 * @param track						Timer track.
 * @return							Number of the player's Completions for given style/track.
 */
native int Shavit_GetClientCompletions(int client, int style, int track);

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
 * Checks if a player is inside a mapzone.
 *
 * @param client					Client index.
 * @param type						Mapzone type.
 * @param track						Mapzone track, -1 to ignore track.
 * @return							Boolean value.
 */
native bool Shavit_InsideZone(int client, int type, int track);

/**
 * Gets the specified zone's data.
 *
 * @param zoneid					ID of the zone we query the data of.
 * @return							Zone data. 0 if none is specified.
 */
native int Shavit_GetZoneData(int zoneid);

/**
 * Gets the specified zone's flags.
 *
 * @param zoneid					ID of the zone we query the flags of.
 * @return							Zone flags. 0 if none is specified.
 */
native int Shavit_GetZoneFlags(int zoneid);

/**
 * Checks if a player is inside a mapzone.
 *
 * @param client					Client index.
 * @param type						Mapzone type.
 * @param track						Mapzone track, -1 to ignore track.
 * @param zoneid					Reference to variable that will hold the zone's ID.
 * @return							Boolean value.
 */
native bool Shavit_InsideZoneGetID(int client, int type, int track, int &zoneid);

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

/**
 * Deletes the specified replay file.
 * Replay data will be unloaded if necessary.
 *
 * @param map						Map display name.
 * @param style						Bhop style.
 * @param track						Timer track.
 * @param accountid					Account ID to validate against, 0 to skip validation.
 * @return							true if replay existed, false if the steam id didn't match or the file didn't exist.
 */
native bool Shavit_DeleteReplay(const char[] map, int style, int track, int accountid = 0);

/**
 * Retrieves the engine time of the replay bot's first frame.
 *
 * @param entity					Entity index.
 * @return							The engine time of the replay bot's first frame.
 */
native float Shavit_GetReplayBotFirstFrameTime(int entity);

/**
 * Retrieve the replay bot's entity index.
 *
 * @param style						Style you want. -1 if you want the central bot. If no central bot, the first bot it finds it used.
 * @param track						Track you want. -1 if you want the central bot. If no central bot, the first bot it finds it used.
 * @return							Client index for the replay bot. -1 if not found.
 */
native int Shavit_GetReplayBotIndex(int style, int track);

/**
 * Retrieve the style being played by the replay bot.
 *
 * @param entity					Entity index.
 * @return							Style being played by the replay bot. -1 if the replay bot is idle.
 */
native int Shavit_GetReplayBotStyle(int entity);

/**
 * Retrieve the timer track being played by the replay bot.
 *
 * @param entity					entity index.
 * @return							Timer track replayed by the bot. -1 if the replay bot is idle.
 */
native int Shavit_GetReplayBotTrack(int entity);

/**
 * Gets the replay bot type setting of the server.
 *
 * @return							See ReplayBotType enum.
 */
native int Shavit_GetReplayBotType();

/**
 * Retrieve the replay bot's current played frame.
 *
 * @param entity						Entity index.
 * @return							Current played frame.
 */
native int Shavit_GetReplayBotCurrentFrame(int entity);

/**
 * Retrieves the client who started the replay.
 *
 * @param ent						Replay entity.
 * @return							Client index of starter. Can be 0
 */
native int Shavit_GetReplayStarter(int ent);

/**
 * Retrieves the replay's buttons for its current tick.
 * Really, this is only useful for things like replay props.
 *
 * @param ent						Replay entity.
 * @param anglediff                 The angle difference between the previous and current y angles.
 *
 * @return							buttons
 */
native int Shavit_GetReplayButtons(int ent, float& anglediff);

/**
 * Retrieves a replay's frame count.
 *
 * @param style						Style.
 * @param track						Track.
 * @return							Frame count.
 */
native int Shavit_GetReplayFrameCount(int style, int track);

/**
 * Retrieves a replay's pre-run frame count.
 *
 * @param style						Style.
 * @param track						Track.
 * @return							Frame count.
 */
native int Shavit_GetReplayPreFrames(int style, int track);

/**
 * Retrieves a replay's post-run frame count.
 *
 * @param style						Style.
 * @param track						Track.
 * @return							Frame count.
 */
native int Shavit_GetReplayPostFrames(int style, int track);

/**
 * Retrieves the frame count from the currently running replay bot's frame_cache_t.
 *
 * @param bot						Replay bot entity.
 * @return							Frame count.
 */
native int Shavit_GetReplayCacheFrameCount(int bot);

/**
 * Retrieves the pre-run frame count from the currently running replay bot's frame_cache_t.
 *
 * @param bot						Replay bot entity.
 * @return							Frame count.
 */
native int Shavit_GetReplayCachePreFrames(int bot);

/**
 * Retrieves the post-run frame count from the currently running replay bot's frame_cache_t.
 *
 * @param bot						Replay bot entity.
 * @return							Frame count.
 */
native int Shavit_GetReplayCachePostFrames(int bot);

/**
 * Retrieves the replay data for the given style and track.
 *
 * @param style						Style.
 * @param track						Track.
 * @param cheapCloneHandle			False means we duplicate the frames (ArrayList.Clone). True means we clone the handle to the frames (CloneHandle).
 * @return							ArrayList with proper replay data, or null if there is no recorded data.
 */
native ArrayList Shavit_GetReplayFrames(int style, int track, bool cheapCloneHandle=false);

/**
 * Retrieves a client's frame count.
 *
 * @param client					Client Index.
 * @return							Current number of frames.
 */
native int Shavit_GetClientFrameCount(int client);

/**
 * Retrieves a replay's total length in seconds.
 *
 * @param style						Style.
 * @param track						Track.
 * @return							Replay length.
 */
native float Shavit_GetReplayLength(int style, int track);

/**
 * Retrieves the replay's total length in seconds from the currently running replay bot's frame_cache_t.
 *
 * @param bot						Replay bot entity.
 * @return							Replay length.
 */
native float Shavit_GetReplayCacheLength(int bot);

/**
 * Retrieves an actively playing replay's time.
 *
 * @param entity					Entity index.
 * @return							The bot's current time in the replay.
 */
native float Shavit_GetReplayTime(int entity);

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
 * Retrieves a replay holder's name from an active replay bot.
 *
 * @param bot                       Bot.
 * @param buffer                    Buffer string.
 * @param length                    String length.
 * @noreturn
 */
native void Shavit_GetReplayCacheName(int bot, char[] buffer, int length);

/**
 * Hijack the replay data so that this view angle will be used for the next tick.
 * Use case is to make segmented runs look smoother.
 *
 * @param client					Client index.
 * @param pitch						Vertical view angle.
 * @param yaw						Horizontal view angle.
 * @noreturn
 */
native void Shavit_HijackAngles(int client, float pitch, float yaw, int ticks);

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
 * @param steamid					Target Steam account ID to use.
 * @noreturn
 */
native void Shavit_OpenStatsMenu(int client, int steamid);

/**
 * Retrieves the amount of #1 records a player has.
 * Requires shavit-rankings.
 *
 * @param client					Client index.
 * @param track						Track to retrieve WRs from. -1 to use all tracks. All bonus tracks are combined.
 * @param style						Style to retrieve WRs from. -1 to use all styles.
 * @param usecvars					Whether to depend on the value of `shavit_stats_mvprankones` and `shavit_stats_mvprankones_maintrack`.
 * @return                          The number of WRs.
 */
native int Shavit_GetWRCount(int client, int track = -1, int style = -1, bool usecvars = true);

/**
 * Retrieves the number of players who hold #1 records.
 * Requires shavit-rankings.
 *
 * @param track						Track to retrieve WRs from. -1 to use all tracks. All bonus tracks are combined.
 * @param style						Style to retrieve WRs from. -1 to use all styles.
 * @param usecvars					Whether to depend on the value of `shavit_stats_mvprankones` and `shavit_stats_mvprankones_maintrack`.
 * @return                          The number of WR holders. 0 if none.
 */
native int Shavit_GetWRHolders(int track = -1, int style = -1, bool usecvars = true);

/**
 * Retrieves the player's rank based on how many #1 records they hold.
 * Requires shavit-rankings.
 * Only works with MySQL 8.0+ or with MariaDB 10.2+.
 *
 * @param client					Client index.
 * @param track						Track to retrieve WRs from. -1 to use all tracks. All bonus tracks are combined.
 * @param style						Style to retrieve WRs from. -1 to use all styles.
 * @param usecvars					Whether to depend on the value of `shavit_stats_mvprankones` and `shavit_stats_mvprankones_maintrack`.
 * @return                          The rank. 0 if none, or not supported.
 */
native int Shavit_GetWRHolderRank(int client, int track = -1, int style = -1, bool usecvars = true);

/*
 * Gets a value from the style config for the given style
 * e.g. Shavit_GetStyleSetting(Shavit_GetBhopStyle(client), "TAS", sBuffer, 2);
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
 * @noreturn
 */
native void Shavit_LoadSnapshot(int client, any[] snapshot, int size = sizeof(timer_snapshot_t));

/**
 * Sets a player's replay recording frames from a provided ArrayList.
 * To be used by save states/TAS etc.
 *
 * @param client					Client index.
 * @param data						ArrayList with proper replay data.
 * @param cheapCloneHandle			False means we duplicate the frames (ArrayList.Clone). True means we clone the handle to the frames (CloneHandle).
 * @noreturn
 */
native void Shavit_SetReplayData(int client, ArrayList data, bool cheapCloneHandle=false);

/**
 * Saves a player's replay recording frames (if exists) into an ArrayList.
 * To be used by save states/TAS etc.
 *
 * @param client					Client index.
 * @param cheapCloneHandle			False means we duplicate the frames (Arraylist.Clone). True means we clone the handle to the frames (CloneHandle). This is going to be used for peristent-data in shavit-misc so we don't allocate duplicate memory needlessly.
 * @return							ArrayList with proper replay data, or null if the player has no recorded data.
 */
native ArrayList Shavit_GetReplayData(int client, bool cheapCloneHandle=false);

/**
 * Checks if the given entity is a replay bot (fakeclient) or replay prop.
 *
 * @param ent						The entity index to check.
 */
native bool Shavit_IsReplayEntity(int ent);

/**
 * Sets the sReplayName value in the bot's frame_cache_t.
 * Useful for `Shavit_StartReplayFromFile` and family.
 *
 * @param bot                       The replay bot entity.
 * @param name                      The name to use.
 */
native void Shavit_SetReplayCacheName(int bot, char[] name);

/**
 * Starts a replay given a style and track. 
 *
 * @param style						Bhop style.
 * @param track						Timer track.
 * @param delay						Delay until starting. If -1.0, then uses shavit_replay_delay
 * @param client					Client index.
 * @param bot						Bot to play on. Should be of type Replay_Central or Replay_Dynamic. -1 to create new replay bot.
 * @param type						ReplayBotType. Replay_Prop needs `bot` to be -1.
 * @param ignorelimit				Ignore cvar limit for dynamic bots.
 * @return							Replay entity. 0 is returned if couldn't be created.
 */
native int Shavit_StartReplay(int style, int track, float delay, int client, int bot, int type, bool ignorelimit);

/**
 * Starts a replay with a given set of frames.
 * Useful for playing a replay downloaded from a global WR database...
 *
 * @param style						Bhop style.
 * @param track						Timer track.
 * @param delay						Delay until starting. If -1.0, then uses shavit_replay_delay
 * @param client					Client index.
 * @param bot						Bot to play on. Should be of type Replay_Central or Replay_Dynamic. -1 to create new replay bot.
 * @param type						ReplayBotType. Replay_Prop needs `bot` to be -1.
 * @param ignorelimit				Ignore cvar limit for dynamic bots.
 * @param cache						frame_cache_t filled with replay info and frames.
 * @param size						sizeof(frame_cache_t). Used to throw errors at you if you don't recompile plugins.
 * @return							Replay entity. 0 is returned if couldn't be created.
 */
native int Shavit_StartReplayFromFrameCache(int style, int track, float delay, int client, int bot, int type, bool ignorelimit, any[] cache, int size = sizeof(frame_cache_t));

/**
 * Starts a replay from a replay file.
 * Useful for playing a replay downloaded from a global WR database...
 *
 * @param style						Bhop style.
 * @param track						Timer track.
 * @param delay						Delay until starting. If -1.0, then uses shavit_replay_delay
 * @param client					Client index.
 * @param bot						Bot to play on. Should be of type Replay_Central or Replay_Dynamic. -1 to create new replay bot.
 * @param type						ReplayBotType. Replay_Prop needs `bot` to be -1.
 * @param ignorelimit				Ignore cvar limit for dynamic bots.
 * @param path						File path to replay
 * @return							Replay entity. 0 is returned if couldn't be created.
 */
native int Shavit_StartReplayFromFile(int style, int track, float delay, int client, int bot, int type, bool ignorelimit, const char[] path);

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
 *
 * @param restart					Restart the playback of the replay bots?
 * @return							Amount of loaded replays.
 */
native int Shavit_ReloadReplays(bool restart);

/**
 * Gets time from replay frame that is closest to client.
 *
 * @param 				Client index.
 * @return				Replay time.
 */
native float Shavit_GetClosestReplayTime(int client);

/**
 * Gets the style the client is getting the closest replay time from.
 *
 * @param				Client index.
 * @return				style
 */
native int Shavit_GetClosestReplayStyle(int client);

/**
 * Sets the style to grab the closest replay time from.
 *
 * @param				Client index.
 * @param				Style to grab replay time from. -1 to use the client's current style.
 * @noreturn
 */
native void Shavit_SetClosestReplayStyle(int client, int style);

/**
 * Gets velocity from replay frame that is closest to client.
 *
 * @param				Client index.
 * @param				true for 3D velocity difference. false for 2D velocity difference.
 * @return				Velocity difference from closest replay position.
 */
native float Shavit_GetClosestReplayVelocityDifference(int client, bool threeD);

/**
 * Use this native to stop the click sound that plays upon chat messages.
 * Call it before each Shavit_PrintToChat().
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
 * @param map						Map to get the tier of. Using "" will get the current map's tier.
 * @return							Map tier. 0 if no results were found.
 */
native int Shavit_GetMapTier(const char[] map = "");

/**
 * Gets a StringMap that contains all the cached map tiers.
 * The returned StringMap must be deleted from memory after use!
 *
 * @return							StringMap with {const char[]: map, int: tier} structure.
 */
native StringMap Shavit_GetMapTiers();

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
 * Gets the total number of CPs that a client has saved
 *
 * @param client					Client index
 *
 * @return							Total number of checkpoints
 */
 native int Shavit_GetTotalCheckpoints(int client);

/**
 * Gets CP data for a client at specified index
 *
 * @param client					Client index
 * @param index						Index of CP to get
 * @param cpcache					Buffer to store cp data in sizeof(cp_cache_t)
 * @param size						Size of the cpcache buffer, e.g sizeof(cp_cache_t)
 *
 * @noreturn
 */
native bool Shavit_GetCheckpoint(int client, int index, any[] cpcache, int size = sizeof(cp_cache_t));

/**
 * Sets checkpoint data at the given index for the given client
 *
 * @param client					Client index
 * @param index						Index of CP to set, or -1 to push cp as last
 * @param cpcache					Buffer to store cp data in sizeof(cp_cache_t)
 * @param size						Size of the cpcache buffer, e.g sizeof(cp_cache_t)
 * @param cpcache					Buffer with cp data
 *
 * @noreturn
 */
native void Shavit_SetCheckpoint(int client, int index, any[] cpcache, int size = sizeof(cp_cache_t));

/**
 * Teleports client to the checkpoint at given index
 *
 * @param client					Client index
 * @param index						Index of CP to teleport to
 * @param suppress					Supress checkpoint message
 *
 * @noreturn
 */
native void Shavit_TeleportToCheckpoint(int client, int index, bool suppress = false);

/**
 * Clears all saved checkpoints for the specified client
 *
 * @param client					Client index
 *
 * @noreturn
 */
native void Shavit_ClearCheckpoints(int client);

/**
 * Opens checkpoint menu for a client
 *
 * @param client					Client index
 *
 * @noreturn
 */
native void Shavit_OpenCheckpointMenu(int client);

/**
 * Sets the clients dynamic timescale. -1.0 to use the timescale of the client's style.
 * Note: Values above 1.0 won't scale into the replay bot.
 *
 * @param client					Client index
 * @param scale						New timescale
 *
 * @noreturn
 */
native void Shavit_SetClientTimescale(int client, float scale);

/**
 * Gets the clients dynamic timescale, or -1.0 if unset.
 *
 * @param client					Client index
 *
 * @return							Client's dynamic timescale
 */
native float Shavit_GetClientTimescale(int client);

/**
 * Gets the replay status
 *
 * @param ent						Replay bot (or prop) entity
 *
 * @return							Replay's status
 */
native int Shavit_GetReplayStatus(int ent);

/**
 * Saves a new checkpoint and returns the new checkpoint index
 *
 * @param client					Client index
 *
 * @return							The new current checkpoint
 */
native int Shavit_SaveCheckpoint(int client);

/**
 * Gets the current checkpoint index.
 *
 * @param client					Client index
 *
 * @return							The current checkpoint
 */
native int Shavit_GetCurrentCheckpoint(int client);

/**
 * Sets the current checkpoint index.
 *
 * @param client					Client index
 * @param index						New index to use
 *
 * @noreturn
 */
native void Shavit_SetCurrentCheckpoint(int client, int index);

/**
 * Gets how many times the client has teleported to checkpoints.
 *
 * @param client					Client index
 *
 * @return							The number of times the client has teleported to checkpoints.
 */
native int Shavit_GetTimesTeleported(int client);

/*
 * returns the number of preframes in the players current run.
 *
 * @param client					Client index
 *
 * @return 							Preframe count
 */
native int Shavit_GetPlayerPreFrames(int client);

/*
 * Sets player's preframe length.
 *
 * @param client					Client index
 * @param PreFrame					PreFrame length
 * @param TimerPreFrame				Timer start frame length
 *
 * @noreturn
 */
native void Shavit_SetPlayerPreFrames(int client, int PreFrame);

/*
 * Retrieves the player's chatrank trimmed and without colors.
 *
 * @param client					Client index
 * @param buf						Buffer to put the put the chatrank into
 * @param buflen					Size of buf
 * @param includename				Include {name} in result.
 * @noreturn
 */
native void Shavit_GetPlainChatrank(int client, char[] buf, int buflen, bool includename=false);

/*
 * Calculates how many points a time will give.
 * Used to minimize number of SQL queries.
 * Requires shavit-rankings.
 *
 * @param track                     The track the time is from.
 * @param style                     The style the time is from.
 * @param tier                      The map tier. -1 to use the current map's tier.
 * @param time                      The time you want to calculate the points for.
 * @param wr                        WR.
 *
 * @return                          The number of points the time would give.
 */
native float Shavit_GuessPointsForTime(int track, int style, int tier, float time, float wr);

/*
 * Used to delete a WR. Used to ensure Shavit_OnWRDeleted is ran.
 *
 * @param style						Record style.
 * @param track						Record track.
 * @param map						Record map.
 * @param accountid					-1 if recordid is -1. Otherwise you need the WR holder's Steam account ID. ([U:1:x])
 * @param recordid					-1 to pull ID & accountid from the database.
 * @param delete_sql				If this function should delete the record from the database. False might be useful if you're deleting things in bulk like sm_wipeplayer does.
 * @param update_cache				If this function should update the WR cache & record info. False might be useful if you're deleting things in bulk like sm_wipeplayer does.
 * @noreturn
 */
native void Shavit_DeleteWR(int style, int track, const char[] map, int accountid, int recordid, bool delete_sql, bool update_cache);

/*
 * Used to find a looping replay bot from the loop config name.
 *
 * @param name                      Looping bot config name. An example is "Other Styles" from the default set of looping bots in shavit-replay.cfg
 *
 * @return                          The client index of the looping replay bot. -1 if could not find the config name. 0 if could not find the replay bot client.
 */
native int Shavit_GetLoopingBotByName(const char[] name);

public SharedPlugin __pl_shavit =
{
	name = "shavit",
	// SM bug? commented until it's fixed
	// file = "shavit-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_CanPause");
	MarkNativeAsOptional("Shavit_ChangeClientStyle");
	MarkNativeAsOptional("Shavit_DeleteReplay");
	MarkNativeAsOptional("Shavit_DeleteWR");
	MarkNativeAsOptional("Shavit_FinishMap");
	MarkNativeAsOptional("Shavit_ForceHUDUpdate");
	MarkNativeAsOptional("Shavit_FormatChat");
	MarkNativeAsOptional("Shavit_GetBhopStyle");
	MarkNativeAsOptional("Shavit_GetChatStrings");
	MarkNativeAsOptional("Shavit_GetChatStringsStruct");
	MarkNativeAsOptional("Shavit_GetClientCompletions");
	MarkNativeAsOptional("Shavit_GetClientJumps");
	MarkNativeAsOptional("Shavit_GetClientPB");
	MarkNativeAsOptional("Shavit_GetClientTime");
	MarkNativeAsOptional("Shavit_GetClientTrack");
	MarkNativeAsOptional("Shavit_GetDatabase");
	MarkNativeAsOptional("Shavit_GetHUDSettings");
	MarkNativeAsOptional("Shavit_GetMapTier");
	MarkNativeAsOptional("Shavit_GetMapTiers");
	MarkNativeAsOptional("Shavit_GetOrderedStyles");
	MarkNativeAsOptional("Shavit_GetPerfectJumps");
	MarkNativeAsOptional("Shavit_GetPoints");
	MarkNativeAsOptional("Shavit_GetRank");
	MarkNativeAsOptional("Shavit_GetRankedPlayers");
	MarkNativeAsOptional("Shavit_GetRankForTime");
	MarkNativeAsOptional("Shavit_GetRecordAmount");
	MarkNativeAsOptional("Shavit_GetReplayBotCurrentFrame");
	MarkNativeAsOptional("Shavit_GetClientFrameCount");
	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrameTime");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");
	MarkNativeAsOptional("Shavit_GetReplayBotStyle");
	MarkNativeAsOptional("Shavit_GetReplayBotTrack");
	MarkNativeAsOptional("Shavit_GetReplayBotType");
	MarkNativeAsOptional("Shavit_GetReplayStarter");
	MarkNativeAsOptional("Shavit_GetReplayData");
	MarkNativeAsOptional("Shavit_GetReplayFrameCount");
	MarkNativeAsOptional("Shavit_GetReplayFrames");
	MarkNativeAsOptional("Shavit_GetReplayLength");
	MarkNativeAsOptional("Shavit_GetReplayName");
	MarkNativeAsOptional("Shavit_GetReplayCacheName");
	MarkNativeAsOptional("Shavit_GetReplayStatus");
	MarkNativeAsOptional("Shavit_GetReplayTime");
	MarkNativeAsOptional("Shavit_GetStageZone");
	MarkNativeAsOptional("Shavit_GetStageCount");
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
	MarkNativeAsOptional("Shavit_GetTimeForRank");
	MarkNativeAsOptional("Shavit_GetTimerStatus");
	MarkNativeAsOptional("Shavit_GetWorldRecord");
	MarkNativeAsOptional("Shavit_GetWRCount");
	MarkNativeAsOptional("Shavit_GetWRHolders");
	MarkNativeAsOptional("Shavit_GetWRHolderRank");
	MarkNativeAsOptional("Shavit_GetWRName");
	MarkNativeAsOptional("Shavit_GetWRRecordID");
	MarkNativeAsOptional("Shavit_GetZoneData");
	MarkNativeAsOptional("Shavit_GetZoneFlags");
	MarkNativeAsOptional("Shavit_HasStyleAccess");
	MarkNativeAsOptional("Shavit_HijackAngles");
	MarkNativeAsOptional("Shavit_InsideZone");
	MarkNativeAsOptional("Shavit_InsideZoneGetID");
	MarkNativeAsOptional("Shavit_IsClientCreatingZone");
	MarkNativeAsOptional("Shavit_IsKZMap");
	MarkNativeAsOptional("Shavit_IsPaused");
	MarkNativeAsOptional("Shavit_IsPracticeMode");
	MarkNativeAsOptional("Shavit_IsReplayDataLoaded");
	MarkNativeAsOptional("Shavit_LoadSnapshot");
	MarkNativeAsOptional("Shavit_MarkKZMap");
	MarkNativeAsOptional("Shavit_OpenStatsMenu");
	MarkNativeAsOptional("Shavit_PauseTimer");
	MarkNativeAsOptional("Shavit_PrintToChat");
	MarkNativeAsOptional("Shavit_PrintToChatAll");
	MarkNativeAsOptional("Shavit_Rankings_DeleteMap");
	MarkNativeAsOptional("Shavit_ReloadLeaderboards");
	MarkNativeAsOptional("Shavit_ReloadReplay");
	MarkNativeAsOptional("Shavit_ReloadReplays");
	MarkNativeAsOptional("Shavit_Replay_DeleteMap");
	MarkNativeAsOptional("Shavit_RestartTimer");
	MarkNativeAsOptional("Shavit_ResumeTimer");
	MarkNativeAsOptional("Shavit_SaveSnapshot");
	MarkNativeAsOptional("Shavit_SetClientPB");
	MarkNativeAsOptional("Shavit_SetPracticeMode");
	MarkNativeAsOptional("Shavit_SetReplayData");
	MarkNativeAsOptional("Shavit_StartReplay");
	MarkNativeAsOptional("Shavit_StartTimer");
	MarkNativeAsOptional("Shavit_SetStart");
	MarkNativeAsOptional("Shavit_DeleteSetStart");
	MarkNativeAsOptional("Shavit_StopChatSound");
	MarkNativeAsOptional("Shavit_StopTimer");
	MarkNativeAsOptional("Shavit_WR_DeleteMap");
	MarkNativeAsOptional("Shavit_ZoneExists");
	MarkNativeAsOptional("Shavit_Zones_DeleteMap");
	MarkNativeAsOptional("Shavit_GetTotalCheckpoints");
	MarkNativeAsOptional("Shavit_GetCheckpoint");
	MarkNativeAsOptional("Shavit_SetCheckpoint");
	MarkNativeAsOptional("Shavit_TeleportToCheckpoint");
	MarkNativeAsOptional("Shavit_ClearCheckpoints");
	MarkNativeAsOptional("Shavit_OpenCheckpointMenu");
	MarkNativeAsOptional("Shavit_GetClientTimescale");
	MarkNativeAsOptional("Shavit_SetClientTimescale");
	MarkNativeAsOptional("Shavit_SaveCheckpoint");
	MarkNativeAsOptional("Shavit_GetCurrentCheckpoint");
	MarkNativeAsOptional("Shavit_SetCurrentCheckpoint");
	MarkNativeAsOptional("Shavit_GetTimesTeleported");
	MarkNativeAsOptional("Shavit_GetPlayerPreFrames");
	MarkNativeAsOptional("Shavit_SetPlayerPreFrames");
	MarkNativeAsOptional("Shavit_GetClosestReplayTime");
	MarkNativeAsOptional("Shavit_SetStyleSetting");
	MarkNativeAsOptional("Shavit_SetStyleSettingFloat");
	MarkNativeAsOptional("Shavit_SetStyleSettingBool");
	MarkNativeAsOptional("Shavit_SetStyleSettingInt");
	MarkNativeAsOptional("Shavit_GetPlainChatrank");
	MarkNativeAsOptional("Shavit_GetClosestReplayVelocityDifference");
	MarkNativeAsOptional("Shavit_IsReplayEntity");
	MarkNativeAsOptional("Shavit_GetReplayButtons");
	MarkNativeAsOptional("Shavit_GetClosestReplayStyle");
	MarkNativeAsOptional("Shavit_SetClosestReplayStyle");
	MarkNativeAsOptional("Shavit_GetReplayCacheFrameCount");
	MarkNativeAsOptional("Shavit_GetReplayCacheLength");
	MarkNativeAsOptional("Shavit_StartReplayFromFrameCache");
	MarkNativeAsOptional("Shavit_StartReplayFromFile");
	MarkNativeAsOptional("Shavit_GetClientLastStage");
	MarkNativeAsOptional("Shavit_GetStageWR");
	MarkNativeAsOptional("Shavit_GetStagePB");
	MarkNativeAsOptional("Shavit_GetReplayPreFrames");
	MarkNativeAsOptional("Shavit_GetReplayPostFrames");
	MarkNativeAsOptional("Shavit_GetReplayCachePreFrames");
	MarkNativeAsOptional("Shavit_GetReplayCachePostFrames");
	MarkNativeAsOptional("Shavit_GetLoopingBotByName");
	MarkNativeAsOptional("Shavit_SetReplayCacheName");
	MarkNativeAsOptional("Shavit_GuessPointsForTime");
}
#endif
