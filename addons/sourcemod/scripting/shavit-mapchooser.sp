/*
 * shavit's Timer - mapchooser aaaaaaa
 * by: various alliedmodders(?), SlidyBat, KiD Fearless, mbhound, rtldg, lilac, Sirhephaestus, MicrowavedBunny
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
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

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools_sound>
#include <convar_class>

#include <shavit/core>
#include <shavit/mapchooser>

#include <shavit/maps-folder-stocks>

#undef REQUIRE_PLUGIN
#include <shavit/rankings>

// for MapChange type
#include <mapchooser>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

bool gB_ConfigsExecuted = false;
int gI_Driver = Driver_unknown;
Database g_hDatabase;
char g_cSQLPrefix[32];

bool g_bDebug;

/* ConVars */
Convar g_cvRTVRequiredPercentage;
Convar g_cvRTVAllowSpectators;
Convar g_cvRTVSpectatorCooldown;
Convar g_cvRTVMinimumPoints;
Convar g_cvRTVDelayTime;
Convar g_cvNominateDelayTime;

Convar g_cvHideRTVChat;

Convar g_cvMapListType;
Convar g_cvMatchFuzzyMap;
Convar g_cvHijackMap;

int g_iExcludePrefixesCount;
char g_cExcludePrefixesBuffers[128][12];
Convar g_cvExcludePrefixes;
int g_iAutocompletePrefixesCount;
char g_cAutocompletePrefixesBuffers[128][12];
Convar g_cvAutocompletePrefixes;

Convar g_cvMapVoteStartTime;
Convar g_cvMapVoteDuration;
Convar g_cvMapVoteBlockMapInterval;
Convar g_cvMapVotePrioritizeSpecial;
Convar g_cvMapVoteExtendLimit;
Convar g_cvMapVoteEnableNoVote;
Convar g_cvMapVoteEnableReRoll;
Convar g_cvMapVoteExtendTime;
Convar g_cvMapVoteShowTier;
Convar g_cvMapVoteRunOff;
Convar g_cvMapVoteRunOffPerc;
Convar g_cvMapVoteRevoteTime;
Convar g_cvMapVotePrintToConsole;
Convar g_cvDisplayTimeRemaining;

Convar g_cvNominateMatches;
Convar g_cvEnhancedMenu;

Convar g_cvMapChangeSound;

Convar g_cvMinTier;
Convar g_cvMaxTier;

Convar g_cvAntiSpam;
float g_fLastRtvTime[MAXPLAYERS+1];
float g_fLastNominateTime[MAXPLAYERS+1];

Convar g_cvPrefix;
char g_cPrefix[32];

/* Map arrays */
ArrayList g_aMapList;
ArrayList g_aNominateList;
ArrayList g_aAllMapsList;
ArrayList g_aOldMaps;

/* Map Data */
char g_cMapName[PLATFORM_MAX_PATH];

MapChange g_ChangeTime;

bool g_bWaitingForChange;
bool g_bMapVoteStarted;
bool g_bMapVoteFinished;
float g_fMapStartTime;
float g_fLastMapvoteTime = 0.0;

int g_iExtendCount;
int g_mapFileSerial = -1;

int gI_LastEnhancedMenuPos[MAXPLAYERS+1];

Menu g_hNominateMenu;
Menu g_hEnhancedMenu;

Menu g_aTierMenus[10+1];
bool g_bWaitingForTiers = false;
bool g_bTiersAssigned = false;

Menu g_hVoteMenu;

/* Player Data */
bool g_bRockTheVote[MAXPLAYERS + 1];
char g_cNominatedMap[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
float g_fSpecTimerStart[MAXPLAYERS+1];

float g_fVoteDelayTime = 5.0;
bool g_bVoteDelayed[MAXPLAYERS+1];

Handle g_hRetryTimer = null;
Handle g_hForward_OnRTV = null;
Handle g_hForward_OnUnRTV = null;
Handle g_hForward_OnSuccesfulRTV = null;

StringMap g_mMapList;
bool gB_Late = false;
EngineVersion gEV_Type = Engine_Unknown;

bool gB_Rankings = false;

enum
{
	MapListZoned,
	MapListFile,
	MapListFolder,
	MapListMixed,
	MapListZonedMixedWithFolder,
	MapListLAST,
}

public Plugin myinfo =
{
	name = "[shavit] MapChooser",
	author = "various alliedmodders(?), SlidyBat, KiD Fearless, mbhound, rtldg, lilac, Sirhephaestus, MicrowavedBunny",
	description = "Automated Map Voting and nominating with Shavit's bhoptimer integration",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetMapsArrayList", Native_GetMapsArrayList);
	CreateNative("Shavit_GetMapsStringMap", Native_GetMapsStringMap);

	g_hForward_OnRTV = CreateGlobalForward("SMC_OnRTV", ET_Event, Param_Cell);
	g_hForward_OnUnRTV = CreateGlobalForward("SMC_OnUnRTV", ET_Event, Param_Cell);
	g_hForward_OnSuccesfulRTV = CreateGlobalForward("SMC_OnSuccesfulRTV", ET_Event);

	RegPluginLibrary("shavit-mapchooser");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("mapchooser.phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("rockthevote.phrases");
	LoadTranslations("nominations.phrases");
	LoadTranslations("plugin.basecommands");

	gEV_Type = GetEngineVersion();

	g_aMapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_aAllMapsList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_aNominateList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_aOldMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	g_mMapList = new StringMap();

	g_cvMapListType = new Convar("smc_maplist_type", "2", "Where the plugin should get the map list from.\n0 - zoned maps from database\n1 - from maplist file (mapcycle.txt)\n2 - from maps folder\n3 - from zoned maps and confirmed by maplist file\n4 - from zoned maps and confirmed by maps folder", _, true, 0.0, true, float(MapListLAST)-1.0);
	g_cvMatchFuzzyMap = new Convar("smc_match_fuzzy", "1", "If set to 1, the plugin will accept partial map matches from the database. Useful for workshop maps, bad for duplicate map names", _, true, 0.0, true, 1.0);
	g_cvHijackMap = new Convar("smc_hijack_sm_map_so_its_faster", "1", "Hijacks sourcemod's built-in sm_map command so it's faster.", 0, true, 0.0, true, 1.0);
	g_cvExcludePrefixes = new Convar("smc_exclude_prefixes", "de_,cs_,as_,ar_,dz_,gd_,lobby_,training1,mg_,gg_,jb_,coop_,aim_,awp_,cp_,ctf_,fy_,dm_,hg_,rp_,ze_,zm_,arena_,pl_,plr_,mvm_,db_,trade_,ba_,mge_,ttt_,ph_,hns_,test_,", "Exclude maps based on these prefixes.\nA good reference: https://developer.valvesoftware.com/wiki/Map_prefixes");
	g_cvAutocompletePrefixes = new Convar("smc_autocomplete_prefixes", "bhop_,surf_,kz_,kz_bhop_,bhop_kz_,xc_,trikz_,jump_,rj_", "Some prefixes that are attempted when using !map");

	g_cvMapVoteBlockMapInterval = new Convar("smc_mapvote_blockmap_interval", "1", "How many maps should be played before a map can be nominated again", _, true, 0.0, false);
	g_cvMapVotePrioritizeSpecial = new Convar("smc_mapvote_prioritize_special", "1", "Whether to prioritize extend, dontchange, and reroll for ties.", _, true, 0.0, true, 1.0);
	g_cvMapVoteEnableNoVote = new Convar("smc_mapvote_enable_novote", "1", "Whether players are able to choose 'No Vote' in map vote", _, true, 0.0, true, 1.0);
	g_cvMapVoteEnableReRoll = new Convar("smc_mapvote_enable_reroll", "0", "Whether players are able to choose 'ReRoll' in map vote", _, true, 0.0, true, 1.0);
	g_cvMapVoteExtendLimit = new Convar("smc_mapvote_extend_limit", "3", "How many times players can choose to extend a single map (0 = block extending, -1 = infinite extending)", _, true, -1.0, false);
	g_cvMapVoteExtendTime = new Convar("smc_mapvote_extend_time", "10", "How many minutes should the map be extended by if the map is extended through a mapvote", _, true, 1.0, false);
	g_cvMapVoteShowTier = new Convar("smc_mapvote_show_tier", "1", "Whether the map tier should be displayed in the map vote", _, true, 0.0, true, 1.0);
	g_cvMapVoteDuration = new Convar("smc_mapvote_duration", "1", "Duration of time in minutes that map vote menu should be displayed for", _, true, 0.1, false);
	g_cvMapVoteStartTime = new Convar("smc_mapvote_start_time", "5", "Time in minutes before map end that map vote starts", _, true, 1.0, false);

	g_cvRTVAllowSpectators = new Convar("smc_rtv_allow_spectators", "1", "Whether spectators should be allowed to RTV", _, true, 0.0, true, 1.0);
	g_cvRTVSpectatorCooldown = new Convar("smc_rtv_spectator_cooldown", "60", "When `smc_rtv_allow_spectators` is `0`, wait this many seconds before removing a spectator's RTV", 0, true, 0.0);
	g_cvRTVMinimumPoints = new Convar("smc_rtv_minimum_points", "-1", "Minimum number of points a player must have before being able to RTV, or -1 to allow everyone", _, true, -1.0, false);
	g_cvRTVDelayTime = new Convar("smc_rtv_delay", "5", "Time in minutes after map start before players should be allowed to RTV", _, true, 0.0, false);
	g_cvNominateDelayTime = new Convar("smc_nominate_delay", "0", "Time in minutes after map start before players should be allowed to nominate", _, true, 0.0, false);
	g_cvRTVRequiredPercentage = new Convar("smc_rtv_required_percentage", "50", "Percentage of players who have RTVed before a map vote is initiated", _, true, 1.0, true, 100.0);
	g_cvHideRTVChat = new Convar("smc_hide_rtv_chat", "1", "Whether to hide 'rtv', 'rockthevote', 'unrtv', 'nextmap', and 'nominate' from chat.");

	g_cvMapVoteRunOff = new Convar("smc_mapvote_runoff", "1", "Hold run off votes if winning choice is less than a certain margin", _, true, 0.0, true, 1.0);
	g_cvMapVoteRunOffPerc = new Convar("smc_mapvote_runoffpercent", "50", "If winning choice has less than this percent of votes, hold a runoff", _, true, 0.0, true, 100.0);
	g_cvMapVoteRevoteTime = new Convar("smc_mapvote_revotetime", "0", "How many minutes after a failed mapvote before rtv is enabled again", _, true, 0.0);
	g_cvMapVotePrintToConsole = new Convar("smc_mapvote_printtoconsole", "1", "Prints map votes that each player makes to console.", _, true, 0.0, true, 1.0);
	g_cvDisplayTimeRemaining = new Convar("smc_display_timeleft", "0", "Display time until vote in chat", _, true, 0.0, true, 1.0);

	g_cvNominateMatches = new Convar("smc_nominate_matches", "1", "Prompts a menu which shows all maps which match argument",  _, true, 0.0, true, 1.0);
	g_cvEnhancedMenu = new Convar("smc_enhanced_menu", "1", "Nominate menu can show maps by alphabetic order and tiers",  _, true, 0.0, true, 1.0);

	g_cvMapChangeSound = new Convar("smc_mapchange_sound", "0", "Play the Dr. Kleiner `3,2,1 Intializing` sound");

	g_cvMinTier = new Convar("smc_min_tier", "0", "The minimum tier to show on the enhanced menu",  _, true, 0.0, true, 10.0);
	g_cvMaxTier = new Convar("smc_max_tier", "10", "The maximum tier to show on the enhanced menu",  _, true, 0.0, true, 10.0);

	g_cvAntiSpam = new Convar("smc_anti_spam", "15.0", "The number of seconds a player needs to wait before rtv/unrtv/nominate/unnominate.", 0, true, 0.0, true, 300.0);

	g_cvPrefix = new Convar("smc_prefix", "[SM] ", "The prefix SMC messages have");
	g_cvPrefix.AddChangeHook(OnConVarChanged);

	Convar.AutoExecConfig();

	RegAdminCmd("sm_forcemapvote", Command_ForceMapVote, ADMFLAG_CHANGEMAP, "Admin command for forcing the end of map vote");
	RegAdminCmd("sm_reloadmaplist", Command_ReloadMaplist, ADMFLAG_CHANGEMAP, "Admin command for forcing maplist to be reloaded");
	RegAdminCmd("sm_reloadmap", Command_ReloadMap, ADMFLAG_CHANGEMAP, "Admin command for reloading current map");
	RegAdminCmd("sm_restartmap", Command_ReloadMap, ADMFLAG_CHANGEMAP, "Admin command for reloading current map");
	RegAdminCmd("sm_mapreload", Command_ReloadMap, ADMFLAG_CHANGEMAP, "Admin command for reloading current map");
	RegAdminCmd("sm_maprestart", Command_ReloadMap, ADMFLAG_CHANGEMAP, "Admin command for reloading current map");

	RegAdminCmd("sm_loadunzonedmap", Command_LoadUnzonedMap, ADMFLAG_CHANGEMAP, "Loads the next map from the maps folder that is unzoned.");

	RegConsoleCmd("sm_nominate", Command_Nominate, "Lets players nominate maps to be on the end of map vote");
	RegConsoleCmd("sm_unnominate", Command_UnNominate, "Removes nominations");
	RegConsoleCmd("sm_rtv", Command_RockTheVote, "Lets players Rock The Vote");
	RegConsoleCmd("sm_unrtv", Command_UnRockTheVote, "Lets players un-Rock The Vote");
	RegConsoleCmd("sm_nomlist", Command_NomList, "Shows currently nominated maps");
	RegConsoleCmd("sm_nominatedmaps", Command_NomList, "Shows currently nominated maps");
	RegConsoleCmd("sm_nominations", Command_NomList, "Shows currently nominated maps");

	RegAdminCmd("sm_smcdebug", Command_Debug, ADMFLAG_RCON);

	AddCommandListener(Command_MapButFaster, "sm_map");

	gB_Rankings = LibraryExists("shavit-rankings");

	if (gB_Late)
	{
		Shavit_OnDatabaseLoaded();

		if (gB_Rankings)
		{
			g_bTiersAssigned = true;
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
}

public void OnMapStart()
{
	GetCurrentMap(g_cMapName, sizeof(g_cMapName));

	SetNextMap(g_cMapName);

	// disable rtv if delay time is > 0
	g_fMapStartTime = GetEngineTime();
	g_fLastMapvoteTime = 0.0;

	g_iExtendCount = 0;

	g_bMapVoteFinished = false;
	g_bMapVoteStarted = false;

	g_aNominateList.Clear();
	for(int i = 1; i <= MaxClients; ++i)
	{
		g_cNominatedMap[i][0] = '\0';
	}
	ClearRTV();

	CreateTimer(0.5, Timer_SpecCooldown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(2.0, Timer_OnMapTimeLeftChanged, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnConfigsExecuted()
{
	gB_ConfigsExecuted = true;
	g_cvPrefix.GetString(g_cPrefix, sizeof(g_cPrefix));
	// reload maplist array
	LoadMapList();
	// cache the nominate menu so that it isn't being built every time player opens it
}

public void OnMapEnd()
{
	gB_ConfigsExecuted = false;
	g_bWaitingForChange = false;

	if(g_cvMapVoteBlockMapInterval.IntValue > 0)
	{
		g_aOldMaps.PushString(g_cMapName);
		if(g_aOldMaps.Length > g_cvMapVoteBlockMapInterval.IntValue)
		{
			g_aOldMaps.Erase(0);
		}
	}

	g_iExtendCount = 0;
	g_bWaitingForTiers = false;
	g_bTiersAssigned = false;

	g_bMapVoteFinished = false;
	g_bMapVoteStarted = false;

	g_aNominateList.Clear();
	for(int i = 1; i <= MaxClients; i++)
	{
		g_cNominatedMap[i][0] = '\0';
	}

	ClearRTV();
}

public void Shavit_OnTierAssigned(const char[] map, int tier)
{
	g_bTiersAssigned = true;

	if (g_bWaitingForTiers)
	{
		g_bWaitingForTiers = false;
		RequestFrame(CreateNominateMenu);
	}
}

public Action Timer_MapChangeSound(Handle timer, any data)
{
	MapChangeDelay();
	return Plugin_Stop;
}

float MapChangeDelay()
{
	if (g_cvMapChangeSound.BoolValue)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i))
			{
				ClientCommand(i, "play vo/k_lab/kl_initializing02");
			}
		}

		return 4.3;
	}

	return 1.0;
}

void StartMapChange(float delay, const char[] map, const char[] reason)
{
	if (g_bWaitingForChange)
	{
		// Could be here if someone !map's during the 1-4s delay before the changelevel... but this simplifies things...
		LogError("StartMapChange called, but already waiting for the map to change. Blocking... (%f, %s, %s)", delay, map, reason);
		return;
	}

	g_bWaitingForChange = true;
	SetNextMap(map);

	DataPack dp;
	CreateDataTimer(delay, Timer_ChangeMap, dp);
	dp.WriteString(map);
	dp.WriteString(reason);
}

int ExplodeCvar(ConVar cvar, char[][] buffers, int maxStrings, int maxStringLength)
{
	char cvarstring[2048];
	cvar.GetString(cvarstring, sizeof(cvarstring));
	LowercaseString(cvarstring);

	while (ReplaceString(cvarstring, sizeof(cvarstring), ",,", ",", true)) {}

	int count = ExplodeString(cvarstring, ",", buffers, maxStrings, maxStringLength);

	for (int i = 0; i < count; i++)
	{
		TrimString(buffers[i]);

		if (buffers[i][0] == 0)
		{
			strcopy(buffers[i], maxStringLength, buffers[--count]);
		}
	}

	return count;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_cvPrefix)
	{
		strcopy(g_cPrefix, sizeof(g_cPrefix), newValue);
	}
}

public Action Timer_SpecCooldown(Handle timer)
{
	if (g_cvRTVAllowSpectators.BoolValue)
	{
		return Plugin_Continue;
	}

	float cooldown = g_cvRTVSpectatorCooldown.FloatValue;
	float now = GetEngineTime();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientConnected(i) || !IsClientInGame(i) || GetClientTeam(i) > CS_TEAM_SPECTATOR)
		{
			g_fSpecTimerStart[i] = 0.0;
			continue;
		}

		if (!g_fSpecTimerStart[i])
		{
			g_fSpecTimerStart[i] = now;
		}

		if (g_bRockTheVote[i] && (now - g_fSpecTimerStart[i]) >= cooldown)
		{
			UnRTVClient(i);
			int needed = CheckRTV();

			if(needed > 0)
			{
				PrintToChatAll("%s%N no longer wants to rock the vote! (%i more votes needed)", g_cPrefix, i, needed);
			}
		}
	}

	return Plugin_Continue;
}

public Action Timer_OnMapTimeLeftChanged(Handle Timer)
{
	DebugPrint("%sOnMapTimeLeftChanged: maplist_length=%i mapvote_started=%s mapvotefinished=%s", g_cPrefix, g_aMapList.Length, g_bMapVoteStarted ? "true" : "false", g_bMapVoteFinished ? "true" : "false");

	int timeleft;
	if (GetMapTimeLeft(timeleft) && g_cvDisplayTimeRemaining.BoolValue)
	{
		if(!g_bMapVoteStarted && !g_bMapVoteFinished)
		{
			int mapvoteTime = timeleft - RoundFloat(g_cvMapVoteStartTime.FloatValue * 60.0) + 3;
			switch(mapvoteTime)
			{
				case (10 * 60), (5 * 60):
				{
					PrintToChatAll("%s%d minutes until map vote", g_cPrefix, mapvoteTime/60);
				}
			}
			switch(mapvoteTime)
			{
				case (10 * 60) - 3:
				{
					PrintToChatAll("%s10 minutes until map vote", g_cPrefix);
				}
				case 60, 30, 5:
				{
					PrintToChatAll("%s%d seconds until map vote", g_cPrefix, mapvoteTime);
				}
			}
		}
	}

	if(g_aMapList.Length && !g_bMapVoteStarted && !g_bMapVoteFinished)
	{
		CheckTimeLeft();
	}

	return Plugin_Continue;
}

public void Shavit_OnCountdownStart()
{
	if (g_cvMapChangeSound.BoolValue)
	{
		CreateTimer(0.6, Timer_MapChangeSound, 0, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void CheckTimeLeft()
{
	int timeleft;
	if(GetMapTimeLeft(timeleft) && timeleft > 0)
	{
		int startTime = RoundFloat(g_cvMapVoteStartTime.FloatValue * 60.0);
		DebugPrint("%sCheckTimeLeft: timeleft=%i startTime=%i", g_cPrefix, timeleft, startTime);

		if(timeleft - startTime <= 0)
		{
			DebugPrint("%sCheckTimeLeft: Initiating map vote ...", g_cPrefix, timeleft, startTime);
			InitiateMapVote(MapChange_MapEnd);
		}
	}
	else
	{
		DebugPrint("%sCheckTimeLeft: GetMapTimeLeft=%s timeleft=%i", g_cPrefix, GetMapTimeLeft(timeleft) ? "true" : "false", timeleft);
	}
}

public void OnClientConnected(int client)
{
	g_fLastRtvTime[client] = 0.0;
	g_fLastNominateTime[client] = 0.0;
	g_fSpecTimerStart[client] = 0.0;
	g_bVoteDelayed[client] = false;
	gI_LastEnhancedMenuPos[client] = 0;
}

public void OnClientDisconnect(int client)
{
	if (g_cNominatedMap[client][0])
	{
		int idx = g_aNominateList.FindString(g_cNominatedMap[client]);

		if (idx != -1)
		{
			g_aNominateList.Erase(idx);
		}
	}

	// clear player data
	g_bRockTheVote[client] = false;
	g_cNominatedMap[client][0] = '\0';
}

public void OnClientDisconnect_Post(int client)
{
	CheckRTV();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!g_cvHideRTVChat.BoolValue)
	{
		return Plugin_Continue;
	}

	if (StrEqual(sArgs, "rtv", false) || StrEqual(sArgs, "rockthevote", false) || StrEqual(sArgs, "unrtv", false) || StrEqual(sArgs, "unnominate", false) || StrContains(sArgs, "nominate", false) == 0 || StrEqual(sArgs, "nextmap", false) || StrEqual(sArgs, "timeleft", false))
	{
		return Plugin_Handled; // block chat but still do _Post
	}

	return Plugin_Continue;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if(StrEqual(sArgs, "rtv", false) || StrEqual(sArgs, "rockthevote", false))
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);

		Command_RockTheVote(client, 0);

		SetCmdReplySource(old);
	}
	else if (StrEqual(sArgs, "unnominate", false))
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);

		Command_UnNominate(client, 0);

		SetCmdReplySource(old);
	}
	else if (StrContains(sArgs, "nominate", false) == 0)
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);

		char mapname[PLATFORM_MAX_PATH];
		BreakString(sArgs[strlen("nominate")], mapname, sizeof(mapname));
		TrimString(mapname);

		if (mapname[0] != 0)
		{
			Command_Nominate_Internal(client, mapname);
		}
		else
		{
			Command_Nominate(client, 0);
		}

		SetCmdReplySource(old);
	}
	else if (StrEqual(sArgs, "unrtv", false))
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);

		Command_UnRockTheVote(client, 0);

		SetCmdReplySource(old);
	}
}

void InitiateMapVote(MapChange when)
{
	g_ChangeTime = when;
	g_bMapVoteStarted = true;

	if (IsVoteInProgress())
	{
		// Can't start a vote, try again in 5 seconds.
		//g_RetryTimer = CreateTimer(5.0, Timer_StartMapVote, _, TIMER_FLAG_NO_MAPCHANGE);

		DataPack data;
		g_hRetryTimer = CreateDataTimer(5.0, Timer_StartMapVote, data, TIMER_FLAG_NO_MAPCHANGE);
		data.WriteCell(when);
		data.Reset();
		return;
	}

	// create menu
	Menu menu = new Menu(Handler_MapVoteMenu, MENU_ACTIONS_ALL);
	menu.VoteResultCallback = Handler_MapVoteFinished;
	menu.Pagination = MENU_NO_PAGINATION;
	menu.SetTitle("Vote Nextmap");

	int maxPageItems = (gEV_Type == Engine_CSGO) ? 8 : 9;
	int mapsToAdd = maxPageItems;
	int mapsAdded = 0;

	bool add_extend = (g_cvMapVoteExtendLimit.IntValue == -1) || (g_cvMapVoteExtendLimit.IntValue > 0 && g_iExtendCount < g_cvMapVoteExtendLimit.IntValue);

	if (add_extend)
	{
		mapsToAdd--;

		if (g_cvMapVoteEnableReRoll.BoolValue)
		{
			mapsToAdd--;
			maxPageItems--;
		}
	}

	if(g_cvMapVoteEnableNoVote.BoolValue)
	{
		mapsToAdd--;
		maxPageItems--;
	}

	char map[PLATFORM_MAX_PATH];
	char mapdisplay[PLATFORM_MAX_PATH + 32];

	StringMap tiersMap = null;
	if (gB_Rankings) tiersMap = Shavit_GetMapTiers();

	int nominateMapsToAdd = (mapsToAdd > g_aNominateList.Length) ? g_aNominateList.Length : mapsToAdd;
	for(int i = 0; i < nominateMapsToAdd; i++)
	{
		g_aNominateList.GetString(i, map, sizeof(map));
		LessStupidGetMapDisplayName(map, mapdisplay, sizeof(mapdisplay));

		if (tiersMap && g_cvMapVoteShowTier.BoolValue)
		{
			int tier = 0;
			tiersMap.GetValue(mapdisplay, tier);
			Format(mapdisplay, sizeof(mapdisplay), "[T%i] %s", tier, mapdisplay);
		}
		else
		{
			strcopy(mapdisplay, sizeof(mapdisplay), map);
		}

		menu.AddItem(map, mapdisplay);
		mapsAdded += 1;
		mapsToAdd--;
	}

	if (g_aMapList.Length < mapsToAdd)
	{
		mapsToAdd = g_aMapList.Length;
	}

	ArrayList used_indices = new ArrayList();

	for(int i = 0; i < mapsToAdd; i++)
	{
		int rand;
		bool duplicate = true;

		for (int x = 0; x < 10; x++) // let's not infinite loop
		{
			rand = GetRandomInt(0, g_aMapList.Length - 1);

			if (used_indices.FindValue(rand) == -1)
			{
				duplicate = false;
				break;
			}
		}

		if (duplicate)
		{
			continue; // unlucky or out of maps
		}

		used_indices.Push(rand);

		g_aMapList.GetString(rand, map, sizeof(map));

		if (StrEqual(map, g_cMapName) || g_aOldMaps.FindString(map) != -1 || g_aNominateList.FindString(map) != -1)
		{
			// don't add current map or recently played
			i--;
			continue;
		}

		if (!GetMapDisplayName(map, mapdisplay, sizeof(mapdisplay)))
		{
			// map is invalid or not found somehow
			--i;
			continue;
		}

		LowercaseString(mapdisplay);

		if (tiersMap && g_cvMapVoteShowTier.BoolValue)
		{
			int tier = 0;
			tiersMap.GetValue(mapdisplay, tier);

			Format(mapdisplay, sizeof(mapdisplay), "[T%i] %s", tier, mapdisplay);
		}

		mapsAdded += 1;
		menu.AddItem(map, mapdisplay);
	}

	delete used_indices;
	delete tiersMap;

	if ((when == MapChange_MapEnd && add_extend) || (when == MapChange_Instant))
	{
		for (int i = 0; i < (maxPageItems-mapsAdded-1); i++)
		{
			menu.AddItem("", "");
		}
	}

	if ((when == MapChange_MapEnd && add_extend))
	{
		if (g_cvMapVoteEnableReRoll.BoolValue)
			menu.AddItem("reroll", "Reroll Maps");
		menu.AddItem("extend", "Extend Current Map");
	}
	else if (when == MapChange_Instant)
	{
		if (g_cvMapVoteEnableReRoll.BoolValue)
			menu.AddItem("reroll", "Reroll Maps");
		menu.AddItem("dontchange", "Don't Change");
	}

	PrintToChatAll("%s%t", g_cPrefix, "Nextmap Voting Started");

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bVoteDelayed[i] = (IsClientInGame(i) && !IsFakeClient(i) && GetClientMenu(i) != MenuSource_None);

		if (g_bVoteDelayed[i])
		{
			PrintToChat(i, "%sYou had a menu open. Waiting %.2fs before accepting input", g_cPrefix, g_fVoteDelayTime);
		}
	}

	CreateTimer(g_fVoteDelayTime+0.1, Timer_VoteDelay, 0, TIMER_FLAG_NO_MAPCHANGE);

	menu.NoVoteButton = g_cvMapVoteEnableNoVote.BoolValue;
	menu.ExitButton = false;
	menu.DisplayVoteToAll(RoundFloat(g_cvMapVoteDuration.FloatValue * 60.0));
}

public Action Timer_VoteDelay(Handle timer, any data)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bVoteDelayed[i])
		{
			g_bVoteDelayed[i] = false;

			if (IsClientInGame(i))
			{
				RedrawClientVoteMenu(i);
			}
		}
	}

	return Plugin_Stop;
}

public void Handler_MapVoteFinished(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	if (g_cvMapVoteRunOff.BoolValue && num_items > 1)
	{
		float winningvotes = float(item_info[0][VOTEINFO_ITEM_VOTES]);
		float required = num_votes * (g_cvMapVoteRunOffPerc.FloatValue / 100.0);

		if (winningvotes < required)
		{
			/* Insufficient Winning margin - Lets do a runoff */
			g_hVoteMenu = new Menu(Handler_MapVoteMenu, MENU_ACTIONS_ALL);
			g_hVoteMenu.SetTitle("Runoff Vote Nextmap");
			g_hVoteMenu.VoteResultCallback = Handler_VoteFinishedGeneric;

			char map[PLATFORM_MAX_PATH];
			char info1[PLATFORM_MAX_PATH];
			char info2[PLATFORM_MAX_PATH];

			menu.GetItem(item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof(map), _, info1, sizeof(info1));
			g_hVoteMenu.AddItem(map, info1);
			menu.GetItem(item_info[1][VOTEINFO_ITEM_INDEX], map, sizeof(map), _, info2, sizeof(info2));
			g_hVoteMenu.AddItem(map, info2);

			g_hVoteMenu.ExitButton = true;
			g_hVoteMenu.DisplayVoteToAll(RoundFloat(g_cvMapVoteDuration.FloatValue * 60.0));

			/* Notify */
			float map1percent = float(item_info[0][VOTEINFO_ITEM_VOTES])/ float(num_votes) * 100;
			float map2percent = float(item_info[1][VOTEINFO_ITEM_VOTES])/ float(num_votes) * 100;


			PrintToChatAll("%s%t", g_cPrefix, "Starting Runoff", g_cvMapVoteRunOffPerc.FloatValue, info1, map1percent, info2, map2percent);
			LogMessage("Voting for next map was indecisive, beginning runoff vote");

			return;
		}
	}

	Handler_VoteFinishedGeneric(menu, num_votes, num_clients, client_info, num_items, item_info);
}

public Action Timer_StartMapVote(Handle timer, DataPack data)
{
	if (timer == g_hRetryTimer)
	{
		g_hRetryTimer = null;
	}

	if (!g_aMapList.Length || g_bMapVoteFinished || g_bMapVoteStarted)
	{
		return Plugin_Stop;
	}

	MapChange when = view_as<MapChange>(data.ReadCell());

	InitiateMapVote(when);

	return Plugin_Stop;
}

// If for example a map & extend have the same number of votes, then we want to pick extend.
int PrioritizeSpecialItem(Menu menu, int num_items, const int[][] item_info)
{
	if (!g_cvMapVotePrioritizeSpecial.BoolValue)
	{
		return 0;
	}

	int maxvotes = item_info[0][VOTEINFO_ITEM_VOTES];
	int last_index_with_maxvotes = 0;

	for (int i = 1; i < num_items; ++i)
	{
		if (item_info[i][VOTEINFO_ITEM_VOTES] == maxvotes)
		{
			last_index_with_maxvotes = i;
		}
	}

	if (last_index_with_maxvotes > 0)
	{
		for (int i = 0; i < last_index_with_maxvotes+1; ++i)
		{
			char map[32];
			menu.GetItem(item_info[i][VOTEINFO_ITEM_INDEX], map, sizeof(map));

			if (StrEqual(map, "extend") || StrEqual(map, "dontchange") || StrEqual(map, "reroll"))
			{
				return i;
			}
		}
	}

	return 0;
}

public void Handler_VoteFinishedGeneric(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];

	int item = PrioritizeSpecialItem(menu, num_items, item_info);

	menu.GetItem(item_info[item][VOTEINFO_ITEM_INDEX], map, sizeof(map), _, displayName, sizeof(displayName));

	//PrintToChatAll("#1 vote was %s (%s)", map, (g_ChangeTime == MapChange_Instant) ? "instant" : "map end");

	if(StrEqual(map, "extend"))
	{
		g_iExtendCount++;

		int time;
		if(GetMapTimeLimit(time))
		{
			if(time > 0)
			{
				ExtendMapTimeLimit(g_cvMapVoteExtendTime.IntValue * 60);
			}
		}

		PrintToChatAll("%s%t", g_cPrefix, "Current Map Extended", RoundToFloor(float(item_info[item][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has finished. The current map has been extended.");

		// We extended, so we'll have to vote again.
		g_bMapVoteStarted = false;
		g_fLastMapvoteTime = GetEngineTime();

		ClearRTV();
	}
	else if(StrEqual(map, "dontchange"))
	{
		PrintToChatAll("%s%t", g_cPrefix, "Current Map Stays", RoundToFloor(float(item_info[item][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has finished. 'No Change' was the winner");

		g_bMapVoteFinished = false;
		g_bMapVoteStarted = false;
		g_fLastMapvoteTime = GetEngineTime();

		ClearRTV();
	}
	else if (StrEqual(map, "reroll"))
	{

		PrintToChatAll("%s%t", g_cPrefix, "ReRolling Maps", RoundToFloor(float(item_info[item][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has restarted. Reroll complete.");

		g_bMapVoteStarted = false;
		g_fLastMapvoteTime = GetEngineTime();
		ClearRTV();

		InitiateMapVote(g_ChangeTime);
	}
	else
	{
		int percentage_of_votes = RoundToFloor(float(item_info[item][VOTEINFO_ITEM_VOTES])/float(num_votes)*100);
		DoMapChangeAfterMapVote(map, displayName, percentage_of_votes, num_votes);
	}
}

void DoMapChangeAfterMapVote(char map[PLATFORM_MAX_PATH], char displayName[PLATFORM_MAX_PATH], int percentage_of_votes, int num_votes)
{
	if(g_ChangeTime == MapChange_MapEnd)
	{
		SetNextMap(map);
	}
	else if(g_ChangeTime == MapChange_Instant)
	{
		int needed, rtvcount, total;
		GetRTVStuff(total, needed, rtvcount);

		if(needed <= 0)
		{
			Call_StartForward(g_hForward_OnSuccesfulRTV);
			Call_Finish();
		}

		StartMapChange(MapChangeDelay(), map, "RTV Mapvote");
	}

	g_bMapVoteStarted = false;
	g_bMapVoteFinished = true;

	PrintToChatAll("%s%t", g_cPrefix, "Nextmap Voting Finished", displayName, percentage_of_votes, num_votes);
	LogAction(-1, -1, "Voting for next map has finished. Nextmap: %s.", map);
}

public int Handler_MapVoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			if (g_cvMapVotePrintToConsole.BoolValue)
			{
				char map[PLATFORM_MAX_PATH];
				menu.GetItem(param2, map, sizeof(map));

				PrintToConsoleAll("%N voted for %s", param1, map);
			}
		}

		case MenuAction_DrawItem:
		{
			if (g_bVoteDelayed[param1])
			{
				return ITEMDRAW_DISABLED;
			}

			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param2, map, sizeof(map));

			if (map[0] == 0)
			{
				return ITEMDRAW_DISABLED;
			}
		}

		case MenuAction_Cancel: // comes up for novote
		{
			if (g_bVoteDelayed[param1])
			{
				g_bVoteDelayed[param1] = false;
				RedrawClientVoteMenu(param1);
				return 0;
			}
		}

		case MenuAction_End:
		{
			delete menu;
		}

		case MenuAction_Display:
		{
			Panel panel = view_as<Panel>(param2);
			panel.SetTitle("Vote Nextmap");
		}

		case MenuAction_DisplayItem:
		{
			if (menu.ItemCount - 1 == param2)
			{
				char map[PLATFORM_MAX_PATH], buffer[255];
				menu.GetItem(param2, map, sizeof(map));

				if (strcmp(map, "extend", false) == 0)
				{
					FormatEx(buffer, sizeof(buffer), "%T", "Extend Map", param1);
					return RedrawMenuItem(buffer);
				}
				else if (strcmp(map, "novote", false) == 0)
				{
					FormatEx(buffer, sizeof(buffer), "%T", "No Vote", param1);
					return RedrawMenuItem(buffer);
				}
				else if (strcmp(map, "dontchange", false) == 0)
				{
					FormatEx(buffer, sizeof(buffer), "%T", "Dont Change", param1);
					return RedrawMenuItem(buffer);
				}
			}
		}

		case MenuAction_VoteCancel:
		{
			// If we receive 0 votes, pick at random.
			if(param1 == VoteCancel_NoVotes)
			{
				int count = menu.ItemCount;
				char map[PLATFORM_MAX_PATH];
				char displayName[PLATFORM_MAX_PATH];
				menu.GetItem(0, map, sizeof(map));

				// Make sure the first map in the menu isn't one of the special items.
				// This would mean there are no real maps in the menu, because the special items are added after all maps. Don't do anything if that's the case.
				if (strcmp(map, "extend", false) != 0 && strcmp(map, "dontchange", false) != 0 && strcmp(map, "reroll", false) != 0)
				{
					// Get a random map from the list.

					// Make sure it's not one of the special items.
					do
					{
						int item = GetRandomInt(0, count - 1);
						menu.GetItem(item, map, sizeof(map), _, displayName, sizeof(displayName));
					}
					while (strcmp(map, "extend", false) == 0 || strcmp(map, "dontchange", false) == 0 || strcmp(map, "reroll", false) == 0);

					DoMapChangeAfterMapVote(map, displayName, 0, 0);
				}
			}
			else
			{
				// We were actually cancelled. I guess we do nothing.
			}

			g_bMapVoteStarted = false;
		}
	}

	return 0;
}

public void Shavit_OnDatabaseLoaded()
{
	GetTimerSQLPrefix(g_cSQLPrefix, sizeof(g_cSQLPrefix));
	g_hDatabase = Shavit_GetDatabase(gI_Driver);

	if (gB_ConfigsExecuted)
	{
		switch (g_cvMapListType.IntValue)
		{
			case MapListZoned, MapListMixed, MapListZonedMixedWithFolder:
			{
				RequestFrame(LoadMapList);
			}
		}
	}
}

void RemoveExcludesFromArrayList(ArrayList list, bool lowercase, char[][] exclude_prefixes, int exclude_count)
{
	int length = list.Length;

	for (int i = 0; i < length; i++)
	{
		char buffer[PLATFORM_MAX_PATH];
		list.GetString(i, buffer, sizeof(buffer));

		for (int x = 0; x < exclude_count; x++)
		{
			if (strncmp(buffer, exclude_prefixes[x], strlen(exclude_prefixes[x]), lowercase) == 0)
			{
				list.SwapAt(i, --length);
				break;
			}
		}
	}

	list.Resize(length);
}

void LoadMapList()
{
	g_mMapList.Clear();

	g_iExcludePrefixesCount = ExplodeCvar(g_cvExcludePrefixes, g_cExcludePrefixesBuffers, sizeof(g_cExcludePrefixesBuffers), sizeof(g_cExcludePrefixesBuffers[]));

	GetTimerSQLPrefix(g_cSQLPrefix, sizeof(g_cSQLPrefix));

	switch(g_cvMapListType.IntValue)
	{
		case MapListZoned:
		{
			if (g_hDatabase == null)
			{
				return;
			}

			g_aMapList.Clear();

			char buffer[512];

			FormatEx(buffer, sizeof(buffer), "SELECT DISTINCT `map` FROM `%smapzones` WHERE `type` = 1 AND `track` = 0 ORDER BY `map`", g_cSQLPrefix);
			QueryLog(g_hDatabase, LoadZonedMapsCallback, buffer, _, DBPrio_High);
		}
		case MapListFolder:
		{
			g_aMapList.Clear();
			ReadMapsFolderArrayList(g_aMapList, true, false, true, true, g_cExcludePrefixesBuffers, g_iExcludePrefixesCount);
			CreateNominateMenu();
		}
		case MapListFile:
		{
			ReadMapList(g_aMapList, g_mapFileSerial, "default", MAPLIST_FLAG_CLEARARRAY);
			RemoveExcludesFromArrayList(g_aMapList, false, g_cExcludePrefixesBuffers, g_iExcludePrefixesCount);
			CreateNominateMenu();
		}
		case MapListMixed, MapListZonedMixedWithFolder:
		{
			if (g_hDatabase == null)
			{
				return;
			}

			g_aMapList.Clear();

			if (g_cvMapListType.IntValue == MapListMixed)
			{
				ReadMapList(g_aAllMapsList, g_mapFileSerial, "default", MAPLIST_FLAG_CLEARARRAY);
				RemoveExcludesFromArrayList(g_aAllMapsList, false, g_cExcludePrefixesBuffers, g_iExcludePrefixesCount);
			}
			else
			{
				g_aAllMapsList.Clear();
				ReadMapsFolderArrayList(g_aAllMapsList, true, false, true, true, g_cExcludePrefixesBuffers, g_iExcludePrefixesCount);
			}

			char buffer[512];
			FormatEx(buffer, sizeof(buffer), "SELECT DISTINCT `map` FROM `%smapzones` WHERE `type` = 1 AND `track` = 0 ORDER BY `map`", g_cSQLPrefix);
			QueryLog(g_hDatabase, LoadZonedMapsCallbackMixed, buffer, _, DBPrio_High);
		}
	}
}

public void LoadZonedMapsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("[shavit-mapchooser] - (LoadMapZonesCallback) - %s", error);
		return;
	}

	char map[PLATFORM_MAX_PATH];
	char map2[PLATFORM_MAX_PATH];
	while(results.FetchRow())
	{
		results.FetchString(0, map, sizeof(map));
		FindMapResult res = FindMap(map, map2, sizeof(map2));

		if (res == FindMap_Found || (g_cvMatchFuzzyMap.BoolValue && res == FindMap_FuzzyMatch))
		{
			g_aMapList.PushString(map2);
		}
	}

	CreateNominateMenu();
}

public void LoadZonedMapsCallbackMixed(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("[shavit-mapchooser] - (LoadMapZonesCallbackMixed) - %s", error);
		return;
	}

	char map[PLATFORM_MAX_PATH];

	StringMap all_maps = new StringMap();

	for (int i = 0; i < g_aAllMapsList.Length; ++i)
	{
		g_aAllMapsList.GetString(i, map, sizeof(map));
		LessStupidGetMapDisplayName(map, map, sizeof(map));
		all_maps.SetValue(map, i, true);
	}

	int resultlength, mapsadded;
	while(results.FetchRow())
	{
		resultlength++;
		results.FetchString(0, map, sizeof(map));//db mapname
		LowercaseString(map);

		int index;
		if (all_maps.GetValue(map, index))
		{
			g_aMapList.PushString(map);
			mapsadded++;
		}
	}

	PrintToServer("Shavit-Mapchooser Query callback. Number of returned results: %i, Maps added to g_aMapList:%i, g_aAllMapsList.Length:%i, all_maps:%i", resultlength, mapsadded, g_aAllMapsList.Length, all_maps.Size);
	delete all_maps;

	CreateNominateMenu();
}

bool SMC_FindMap(const char[] mapname, char[] output, int maxlen)
{
	int length = g_aMapList.Length;
	for(int i = 0; i < length; i++)
	{
		char entry[PLATFORM_MAX_PATH];
		g_aMapList.GetString(i, entry, sizeof(entry));

		if(StrContains(entry, mapname) != -1)
		{
			strcopy(output, maxlen, entry);
			return true;
		}
	}

	return false;
}

void SMC_NominateMatches(int client, const char[] mapname)
{
	Menu subNominateMenu = new Menu(NominateMenuHandler);
	subNominateMenu.SetTitle("Nominate\nMaps matching \"%s\"\n ", mapname);
	bool isCurrentMap = false;
	bool isOldMap = false;
	char map[PLATFORM_MAX_PATH];
	char oldMapName[PLATFORM_MAX_PATH];
	StringMap tiersMap = null;
	if (gB_Rankings) tiersMap = Shavit_GetMapTiers();
	int min = GetConVarInt(g_cvMinTier);
	int max = GetConVarInt(g_cvMaxTier);

	int length = g_aMapList.Length;
	for(int i = 0; i < length; i++)
	{
		char entry[PLATFORM_MAX_PATH];
		g_aMapList.GetString(i, entry, sizeof(entry));

		if(StrContains(entry, mapname) != -1)
		{
			if(StrEqual(entry, g_cMapName))
			{
				isCurrentMap = true;
				continue;
			}

			int idx = g_aOldMaps.FindString(entry);
			if(idx != -1)
			{
				isOldMap = true;
				oldMapName = entry;
				continue;
			}

			map = entry;
			char mapdisplay[PLATFORM_MAX_PATH];
			LessStupidGetMapDisplayName(entry, mapdisplay, sizeof(mapdisplay));

			if (tiersMap)
			{
				int tier = 0;
				tiersMap.GetValue(mapdisplay, tier);

				if (!(min <= tier <= max))
				{
					continue;
				}

				Format(mapdisplay, sizeof(mapdisplay), "%s | T%i", mapdisplay, tier);
			}

			subNominateMenu.AddItem(entry, mapdisplay);
		}
	}

	delete tiersMap;

	switch (subNominateMenu.ItemCount)
	{
		case 0:
		{
			if (isCurrentMap)
			{
				ReplyToCommand(client, "%s%t", g_cPrefix, "Can't Nominate Current Map");
			}
			else if (isOldMap)
			{
				ReplyToCommand(client, "%s%s %t", g_cPrefix, oldMapName, "Recently Played");
			}
			else
			{
				ReplyToCommand(client, "%s%t", g_cPrefix, "Map was not found", mapname);
			}

			if (subNominateMenu != INVALID_HANDLE)
			{
				CloseHandle(subNominateMenu);
			}
		}
		case 1:
		{
			Nominate(client, map);

			if (subNominateMenu != INVALID_HANDLE)
			{
				CloseHandle(subNominateMenu);
			}
		}
		default:
		{
			subNominateMenu.Display(client, MENU_TIME_FOREVER);
		}
	}
}

bool IsRTVEnabled()
{
	float time = GetEngineTime();

	if(g_fLastMapvoteTime != 0.0)
	{
		if(time - g_fLastMapvoteTime > g_cvMapVoteRevoteTime.FloatValue * 60)
		{
			return true;
		}
	}
	else if(time - g_fMapStartTime > g_cvRTVDelayTime.FloatValue * 60)
	{
		return true;
	}
	return false;
}

void ClearRTV()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		g_bRockTheVote[i] = false;
	}
}

/* Timers */
public Action Timer_ChangeMap(Handle timer, DataPack data)
{
	char reason[PLATFORM_MAX_PATH];
	char map[PLATFORM_MAX_PATH];

	data.Reset();
	data.ReadString(map, sizeof(map));
	data.ReadString(reason, sizeof(reason));

	//LogError("Timer_ChangeMap(%s, %s)", map, reason);
	ForceChangeLevel(map, reason);
	return Plugin_Stop;
}

/* Commands */
public Action Command_ForceMapVote(int client, int args)
{
	if(g_bMapVoteStarted || g_bMapVoteFinished)
	{
		ReplyToCommand(client, "%sMap vote already %s", g_cPrefix, (g_bMapVoteStarted) ? "initiated" : "finished");
	}
	else
	{
		InitiateMapVote(MapChange_Instant);
	}

	return Plugin_Handled;
}

public Action Command_ReloadMaplist(int client, int args)
{
	LoadMapList();

	return Plugin_Handled;
}

public Action Command_Nominate(int client, int args)
{
	if (g_bMapVoteStarted || g_bMapVoteFinished)
	{
		ReplyToCommand(client, "%sMap vote already %s", g_cPrefix, (g_bMapVoteStarted) ? "initiated" : "finished");
		return Plugin_Handled;
	}

	if(args < 1)
	{
		if (g_cvEnhancedMenu.BoolValue)
		{
			OpenEnhancedMenu(client);
		}
		else
		{
			OpenNominateMenu(client);
		}
		return Plugin_Handled;
	}

	char mapname[PLATFORM_MAX_PATH];
	GetCmdArg(1, mapname, sizeof(mapname));
	return Command_Nominate_Internal(client, mapname);
}

public Action Command_Nominate_Internal(int client, char mapname[PLATFORM_MAX_PATH])
{
	if (g_bMapVoteStarted || g_bMapVoteFinished)
	{
		ReplyToCommand(client, "%sMap vote already %s", g_cPrefix, (g_bMapVoteStarted) ? "initiated" : "finished");
		return Plugin_Handled;
	}

	LowercaseString(mapname);

	if (g_cvNominateMatches.BoolValue)
	{
		SMC_NominateMatches(client, mapname);
	}
	else
	{
		if(SMC_FindMap(mapname, mapname, sizeof(mapname)))
		{
			if(StrEqual(mapname, g_cMapName))
			{
				ReplyToCommand(client, "%s%t", "Can't Nominate Current Map");
				return Plugin_Handled;
			}

			int idx = g_aOldMaps.FindString(mapname);
			if(idx != -1)
			{
				ReplyToCommand(client, "%s%s %t", g_cPrefix, mapname, "Recently Played");
				return Plugin_Handled;
			}

			ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
			Nominate(client, mapname);
			SetCmdReplySource(old);
		}
		else
		{
			ReplyToCommand(client, "%s%t", g_cPrefix, "Map was not found", mapname);
		}
	}

	return Plugin_Handled;
}

public Action Command_UnNominate(int client, int args)
{
	if (g_bMapVoteStarted || g_bMapVoteFinished)
	{
		ReplyToCommand(client, "%sMap vote already %s", g_cPrefix, (g_bMapVoteStarted) ? "initiated" : "finished");
		return Plugin_Handled;
	}

	if (g_fLastNominateTime[client] && (GetEngineTime() - g_fLastNominateTime[client]) < g_cvAntiSpam.FloatValue)
	{
		ReplyToCommand(client, "%sStop spamming", g_cPrefix);
		return Plugin_Handled;
	}

	if (!CheckCommandAccess(client, "sm_map", ADMFLAG_CHANGEMAP))
	{
		g_fLastNominateTime[client] = GetEngineTime();
	}

	if(g_cNominatedMap[client][0] == '\0')
	{
		ReplyToCommand(client, "%sYou haven't nominated a map", g_cPrefix);
		return Plugin_Handled;
	}

	int idx = g_aNominateList.FindString(g_cNominatedMap[client]);
	if(idx != -1)
	{
		ReplyToCommand(client, "%sSuccessfully removed nomination for '%s'", g_cPrefix, g_cNominatedMap[client]);
		g_aNominateList.Erase(idx);
		g_cNominatedMap[client][0] = '\0';
	}

	return Plugin_Handled;
}

public int SlowSortThatSkipsFolders(int index1, int index2, Handle array, Handle stupidgarbage)
{
	char a[PLATFORM_MAX_PATH], b[PLATFORM_MAX_PATH];
	ArrayList list = view_as<ArrayList>(array);
	list.GetString(index1, a, sizeof(a));
	list.GetString(index2, b, sizeof(b));
	return strcmp(a[FindCharInString(a, '/', true)+1], b[FindCharInString(b, '/', true)+1], true);
}

void CreateNominateMenu()
{
	if (gB_Rankings && !g_bTiersAssigned)
	{
		g_bWaitingForTiers = true;
		return;
	}

	int min = GetConVarInt(g_cvMinTier);
	int max = GetConVarInt(g_cvMaxTier);

	if (max < min)
	{
		int temp = max;
		max = min;
		min = temp;
		SetConVarInt(g_cvMinTier, min);
		SetConVarInt(g_cvMaxTier, max);
	}

	delete g_hNominateMenu;
	g_hNominateMenu = new Menu(NominateMenuHandler);

	g_hNominateMenu.SetTitle("Nominate");
	StringMap tiersMap = null;
	if (gB_Rankings) tiersMap = Shavit_GetMapTiers();

	g_aMapList.SortCustom(SlowSortThatSkipsFolders);

	int length = g_aMapList.Length;
	for(int i = 0; i < length; ++i)
	{
		int style = ITEMDRAW_DEFAULT;
		char mapname[PLATFORM_MAX_PATH];
		g_aMapList.GetString(i, mapname, sizeof(mapname));

		if(StrEqual(mapname, g_cMapName))
		{
			style = ITEMDRAW_DISABLED;
		}

		int idx = g_aOldMaps.FindString(mapname);
		if(idx != -1)
		{
			style = ITEMDRAW_DISABLED;
		}

		char mapdisplay[PLATFORM_MAX_PATH];
		LessStupidGetMapDisplayName(mapname, mapdisplay, sizeof(mapdisplay));
		g_mMapList.SetValue(mapdisplay, true);

		if (tiersMap)
		{
			int tier = 0;
			tiersMap.GetValue(mapdisplay, tier);

			if (!(min <= tier <= max))
			{
				continue;
			}

			Format(mapdisplay, sizeof(mapdisplay), "%s | T%d", mapdisplay, tier);
		}

		g_hNominateMenu.AddItem(mapname, mapdisplay, style);
	}

	delete tiersMap;

	if (g_cvEnhancedMenu.BoolValue)
	{
		CreateTierMenus();
	}
}

void CreateEnhancedMenu()
{
	delete g_hEnhancedMenu;

	g_hEnhancedMenu = new Menu(EnhancedMenuHandler);
	g_hEnhancedMenu.ExitButton = true;

	g_hEnhancedMenu.SetTitle("Nominate");
	g_hEnhancedMenu.AddItem("Alphabetic", "Alphabetic");

	for(int i = GetConVarInt(g_cvMinTier); i <= GetConVarInt(g_cvMaxTier); ++i)
	{
		int count = GetMenuItemCount(g_aTierMenus[i]);

		if (count > 0)
		{
			char tierDisplay[32];
			FormatEx(tierDisplay, sizeof(tierDisplay), "Tier %i (%d)", i, count);

			char tierString[16];
			IntToString(i, tierString, sizeof(tierString));
			g_hEnhancedMenu.AddItem(tierString, tierDisplay);
		}
	}
}

void CreateTierMenus()
{
	int min = GetConVarInt(g_cvMinTier);
	int max = GetConVarInt(g_cvMaxTier);

	InitTierMenus(min,max);
	StringMap tiersMap = null;
	if (gB_Rankings) tiersMap = Shavit_GetMapTiers();

	int length = g_aMapList.Length;
	for(int i = 0; i < length; ++i)
	{
		int style = ITEMDRAW_DEFAULT;
		char mapname[PLATFORM_MAX_PATH];
		g_aMapList.GetString(i, mapname, sizeof(mapname));

		char mapdisplay[PLATFORM_MAX_PATH];
		LessStupidGetMapDisplayName(mapname, mapdisplay, sizeof(mapdisplay));

		int mapTier = 0;

		if (tiersMap)
		{
			tiersMap.GetValue(mapdisplay, mapTier);
		}

		if(StrEqual(mapname, g_cMapName))
		{
			style = ITEMDRAW_DISABLED;
		}

		int idx = g_aOldMaps.FindString(mapname);
		if(idx != -1)
		{
			style = ITEMDRAW_DISABLED;
		}

		Format(mapdisplay, sizeof(mapdisplay), "%s | T%i", mapdisplay, mapTier);

		if (min <= mapTier <= max)
		{
			AddMenuItem(g_aTierMenus[mapTier], mapname, mapdisplay, style);
		}
	}

	delete tiersMap;

	CreateEnhancedMenu();
}

void InitTierMenus(int min, int max)
{
	for (int i = 0; i < sizeof(g_aTierMenus); i++)
	{
		delete g_aTierMenus[i];
	}

	for(int i = min; i <= max; i++)
	{
		Menu TierMenu = new Menu(NominateMenuHandler);
		TierMenu.SetTitle("Nominate\nTier \"%i\" Maps\n ", i);
		TierMenu.ExitBackButton = true;
		g_aTierMenus[i] = TierMenu;
	}
}

void OpenNominateMenu(int client)
{
	if (g_cvEnhancedMenu.BoolValue)
	{
		g_hNominateMenu.ExitBackButton = true;
	}
	g_hNominateMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenEnhancedMenu(int client, int pos = 0)
{
	gI_LastEnhancedMenuPos[client] = 0;
	g_hEnhancedMenu.DisplayAt(client, pos, MENU_TIME_FOREVER);
}

void OpenNominateMenuTier(int client, int tier)
{
	DisplayMenu(g_aTierMenus[tier], client, MENU_TIME_FOREVER);
}

public int MapsMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char map[PLATFORM_MAX_PATH];
		menu.GetItem(param2, map, sizeof(map));

		ShowActivity2(param1, g_cPrefix, "%t", "Changing map", map);
		LogAction(param1, -1, "\"%L\" changed map to \"%s\"", param1, map);

		StartMapChange(MapChangeDelay(), map, "sm_map (MapsMenuHandler)");
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int NominateMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char mapname[PLATFORM_MAX_PATH];
		menu.GetItem(param2, mapname, sizeof(mapname));

		Nominate(param1, mapname);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack && GetConVarBool(g_cvEnhancedMenu))
	{
		OpenEnhancedMenu(param1, gI_LastEnhancedMenuPos[param1]);
	}
	else if (action == MenuAction_End)
	{
		if (menu != g_hNominateMenu && menu != INVALID_HANDLE)
		{
			for (int i = 0; i < sizeof(g_aTierMenus); i++)
			{
				if (g_aTierMenus[i] == menu)
				{
					return 0;
				}
			}

			CloseHandle(menu);
		}
	}

	return 0;
}

public int EnhancedMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char option[PLATFORM_MAX_PATH];
		menu.GetItem(param2, option, sizeof(option));
		gI_LastEnhancedMenuPos[client] = GetMenuSelectionPosition();

		if (StrEqual(option , "Alphabetic"))
		{
			OpenNominateMenu(client);
		}
		else
		{
			OpenNominateMenuTier(client, StringToInt(option));
		}
	}

	return 0;
}

void Nominate(int client, const char mapname[PLATFORM_MAX_PATH])
{
	if (GetEngineTime() - g_fMapStartTime < g_cvNominateDelayTime.FloatValue * 60)
	{
		ReplyToCommand(client, "%sNominate has not been enabled yet", g_cPrefix);
		return;
	}

	if (g_fLastNominateTime[client] && (GetEngineTime() - g_fLastNominateTime[client]) < g_cvAntiSpam.FloatValue)
	{
		ReplyToCommand(client, "%sStop spamming", g_cPrefix);
		return;
	}

	if (!CheckCommandAccess(client, "sm_map", ADMFLAG_CHANGEMAP))
	{
		g_fLastNominateTime[client] = GetEngineTime();
	}

	int idx = g_aNominateList.FindString(mapname);
	if(idx != -1)
	{
		ReplyToCommand(client, "%s%t", g_cPrefix, "Map Already Nominated");
		return;
	}

	if (!MapValidOrYell(client, mapname)) return;

	if(g_cNominatedMap[client][0] != '\0')
	{
		RemoveString(g_aNominateList, g_cNominatedMap[client]);
	}

	g_aNominateList.PushString(mapname);
	g_cNominatedMap[client] = mapname;
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));

	PrintToChatAll("%s%t", g_cPrefix, "Map Nominated", name, mapname);
}

public Action Command_RockTheVote(int client, int args)
{
	if(!IsRTVEnabled())
	{
		ReplyToCommand(client, "%s%t", g_cPrefix, "RTV Not Allowed");
	}
	else if(g_bMapVoteStarted)
	{
		ReplyToCommand(client, "%s%t", g_cPrefix, "RTV Started");
	}
	else if(g_bRockTheVote[client])
	{
		int needed, rtvcount, total;
		GetRTVStuff(total, needed, rtvcount);
		ReplyToCommand(client, "%sYou have already RTVed, if you want to un-RTV use the command sm_unrtv (%i more %s needed)", g_cPrefix, needed, (needed == 1) ? "vote" : "votes");
	}
	else if(g_cvRTVMinimumPoints.IntValue != -1 && Shavit_GetPoints(client) <= g_cvRTVMinimumPoints.FloatValue)
	{
		ReplyToCommand(client, "%sYou must be a higher rank to RTV!", g_cPrefix);
	}
	else
	{
		if (GetClientTeam(client) == CS_TEAM_SPECTATOR && !g_cvRTVAllowSpectators.BoolValue)
		{
			if ((GetEngineTime() - g_fSpecTimerStart[client]) >= g_cvRTVSpectatorCooldown.FloatValue)
			{
				ReplyToCommand(client, "%sSpectators have been blocked from RTVing", g_cPrefix);
				return Plugin_Handled;
			}
		}

		if (g_fLastRtvTime[client] && (GetEngineTime() - g_fLastRtvTime[client]) < g_cvAntiSpam.FloatValue)
		{
			ReplyToCommand(client, "%sStop spamming", g_cPrefix);
			return Plugin_Handled;
		}

		if (!CheckCommandAccess(client, "sm_map", ADMFLAG_CHANGEMAP))
		{
			g_fLastRtvTime[client] = GetEngineTime();
		}

		RTVClient(client);
		CheckRTV(client);
	}

	return Plugin_Handled;
}

int CheckRTV(int client = 0)
{
	if (g_bWaitingForChange)
		return 0;

	int needed, rtvcount, total;
	GetRTVStuff(total, needed, rtvcount);
	char name[MAX_NAME_LENGTH];

	if(client != 0)
	{
		GetClientName(client, name, sizeof(name));
	}
	if(needed > 0)
	{
		if(client != 0)
		{
			PrintToChatAll("%s%t", g_cPrefix, "RTV Requested", name, rtvcount, total);
		}
	}
	else
	{
		if(g_bMapVoteFinished)
		{
			char map[PLATFORM_MAX_PATH];
			GetNextMap(map, sizeof(map));

			if(client != 0)
			{
				PrintToChatAll("%s%N wants to rock the vote! Map will now change to %s ...", g_cPrefix, client, map);
			}
			else
			{
				PrintToChatAll("%sRTV vote now majority, map changing to %s ...", g_cPrefix, map);
			}

			StartMapChange(MapChangeDelay(), map, "rtv after map vote");
		}
		else
		{
			if(client != 0)
			{
				PrintToChatAll("%s%N wants to rock the vote! Map vote will now start ...", g_cPrefix, client);
			}
			else
			{
				PrintToChatAll("%sRTV vote now majority, map vote starting ...", g_cPrefix);
			}

			InitiateMapVote(MapChange_Instant);
		}
	}

	return needed;
}

public Action Command_UnRockTheVote(int client, int args)
{
	if(!IsRTVEnabled())
	{
		ReplyToCommand(client, "%sRTV has not been enabled yet", g_cPrefix);
	}
	else if(g_bMapVoteStarted || (g_bMapVoteFinished && g_ChangeTime != MapChange_MapEnd))
	{
		ReplyToCommand(client, "%sMap vote already %s", g_cPrefix, (g_bMapVoteStarted) ? "initiated" : "finished");
	}
	else if(g_bRockTheVote[client])
	{
		if (g_fLastRtvTime[client] && (GetEngineTime() - g_fLastRtvTime[client]) < g_cvAntiSpam.FloatValue)
		{
			ReplyToCommand(client, "%sStop spamming", g_cPrefix);
			return Plugin_Handled;
		}

		if (!CheckCommandAccess(client, "sm_map", ADMFLAG_CHANGEMAP))
		{
			g_fLastRtvTime[client] = GetEngineTime();
		}

		UnRTVClient(client);

		int needed, rtvcount, total;
		GetRTVStuff(total, needed, rtvcount);

		if(needed > 0)
		{
			PrintToChatAll("%s%N no longer wants to rock the vote! (%i more votes needed)", g_cPrefix, client, needed);
		}
	}

	return Plugin_Handled;
}

public Action Command_NomList(int client, int args)
{
	if(g_aNominateList.Length < 1)
	{
		ReplyToCommand(client, "%sNo Maps Nominated", g_cPrefix);
		return Plugin_Handled;
	}

	Menu nomList = new Menu(Null_Callback);
	nomList.SetTitle("Nominated Maps");
	for(int i = 0; i < g_aNominateList.Length; ++i)
	{
		char buffer[PLATFORM_MAX_PATH];
		g_aNominateList.GetString(i, buffer, sizeof(buffer));

		nomList.AddItem(buffer, buffer, ITEMDRAW_DISABLED);
	}

	nomList.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int Null_Callback(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void FindUnzonedMapCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("[shavit-mapchooser] - (FindUnzonedMapCallback) - %s", error);
		return;
	}

	StringMap mapList = new StringMap();

	g_iExcludePrefixesCount = ExplodeCvar(g_cvExcludePrefixes, g_cExcludePrefixesBuffers, sizeof(g_cExcludePrefixesBuffers), sizeof(g_cExcludePrefixesBuffers[]));

	ReadMapsFolderStringMap(mapList, true, true, true, true, g_cExcludePrefixesBuffers, g_iExcludePrefixesCount);

	char buffer[PLATFORM_MAX_PATH];

	while (results.FetchRow())
	{
		results.FetchString(0, buffer, sizeof(buffer));
		mapList.SetValue(buffer, true, true);
	}

	delete results;

	StringMapSnapshot snapshot = mapList.Snapshot();
	bool foundMap = false;

	for (int i = 0; i < snapshot.Length; i++)
	{
		snapshot.GetKey(i, buffer, sizeof(buffer));

		bool hasZones = false;
		mapList.GetValue(buffer, hasZones);

		if (!hasZones && !StrEqual(g_cMapName, buffer, false))
		{
			foundMap = true;
			break;
		}
	}

	delete snapshot;
	delete mapList;

	if (foundMap)
	{
		Shavit_PrintToChatAll("Loading unzoned map %s", buffer);
		StartMapChange(1.0, buffer, "sm_loadunzonedmap");
	}
}

public Action Command_LoadUnzonedMap(int client, int args)
{
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT DISTINCT map FROM %smapzones;", g_cSQLPrefix);
	QueryLog(g_hDatabase, FindUnzonedMapCallback, sQuery, 0, DBPrio_Normal);
	return Plugin_Handled;
}

public Action Command_ReloadMap(int client, int args)
{
	PrintToChatAll("%sReloading current map..", g_cPrefix);
	StartMapChange(MapChangeDelay(), g_cMapName, "sm_reloadmap");
	return Plugin_Handled;
}

bool MapValidOrYell(int client, const char[] map)
{
	if (!IsMapValid(map))
	{
		ReplyToCommand(client, "%sInvalid map :(", g_cPrefix);
		return false;
	}
	return true;
}

public Action BaseCommands_Command_Map_Menu(int client, int args)
{
	char map[PLATFORM_MAX_PATH];
	Menu menu = new Menu(MapsMenuHandler);

	StringMap tiersMap = null;
	if (gB_Rankings) tiersMap = Shavit_GetMapTiers();
	ArrayList maps;

	if (args < 1)
	{
		maps = g_aMapList;

		menu.SetTitle("%T\n ", "Choose Map", client);
	}
	else
	{
		maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
		ReadMapsFolderArrayList(maps);

		GetCmdArg(1, map, sizeof(map));
		LowercaseString(map);
		ReplaceString(map, sizeof(map), "\\", "/", true);

		menu.SetTitle("Maps matching \"%s\"\n ", map);
	}

	int length = maps.Length;
	for(int i = 0; i < length; i++)
	{
		char entry[PLATFORM_MAX_PATH];
		maps.GetString(i, entry, sizeof(entry));

		if (args < 1 || StrContains(entry, map) != -1)
		{
			char mapdisplay[PLATFORM_MAX_PATH];
			LessStupidGetMapDisplayName(entry, mapdisplay, sizeof(mapdisplay));

			if (tiersMap)
			{
				int tier = 0;
				tiersMap.GetValue(mapdisplay, tier);
				Format(mapdisplay, sizeof(mapdisplay), "%s | T%i", mapdisplay, tier);
			}

			menu.AddItem(entry, mapdisplay);
		}
	}

	if (args >= 1)
	{
		delete maps;
	}

	delete tiersMap;

	switch (menu.ItemCount)
	{
		case 0:
		{
			ReplyToCommand(client, "%s%t", g_cPrefix, "Map was not found", map);
			delete menu;
		}
		case 1:
		{
			menu.GetItem(0, map, sizeof(map));
			delete menu;

			if (!MapValidOrYell(client, map)) return Plugin_Handled;

			ShowActivity2(client, g_cPrefix, "%t", "Changing map", map);
			LogAction(client, -1, "\"%L\" changed map to \"%s\"", client, map);

			StartMapChange(MapChangeDelay(), map, "sm_map (BaseCommands_Command_Map_Menu)");
		}
		default:
		{
			menu.Display(client, MENU_TIME_FOREVER);
		}
	}

	return Plugin_Handled;
}

public Action BaseCommands_Command_Map(int client, int args)
{
	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];
	GetCmdArg(1, map, sizeof(map));
	LowercaseString(map);
	ReplaceString(map, sizeof(map), "\\", "/", true);

	g_iAutocompletePrefixesCount = ExplodeCvar(g_cvAutocompletePrefixes, g_cAutocompletePrefixesBuffers, sizeof(g_cAutocompletePrefixesBuffers), sizeof(g_cAutocompletePrefixesBuffers[]));

	StringMap maps = new StringMap();
	ReadMapsFolderStringMap(maps);

	int temp;
	bool foundMap;
	char buffer[PLATFORM_MAX_PATH];

	for (int i = -1; i < g_iAutocompletePrefixesCount; i++)
	{
		char prefix[12];

		if (i > -1)
		{
			prefix = g_cAutocompletePrefixesBuffers[i];
		}

		FormatEx(buffer, sizeof(buffer), "%s%s", prefix, map);

		if ((foundMap = maps.GetValue(buffer, temp)) != false)
		{
			map = buffer;
			break;
		}
	}

	if (!foundMap)
	{
		// do a smaller

		StringMapSnapshot snapshot = maps.Snapshot();
		int length = snapshot.Length;

		for (int i = 0; i < length; i++)
		{
			snapshot.GetKey(i, buffer, sizeof(buffer));

			if (StrContains(buffer, map, true) != -1)
			{
				foundMap = true;
				map = buffer;
				break;
			}
		}

		delete snapshot;
	}

	delete maps;

	if (!foundMap)
	{
		ReplyToCommand(client, "%s%t", g_cPrefix, "Map was not found", map);
		return Plugin_Handled;
	}

	if (!MapValidOrYell(client, map)) return Plugin_Handled;

	LessStupidGetMapDisplayName(map, displayName, sizeof(displayName));

	ShowActivity2(client, g_cPrefix, "%t", "Changing map", displayName);
	LogAction(client, -1, "\"%L\" changed map to \"%s\"", client, map);

	StartMapChange(MapChangeDelay(), map, "sm_map (BaseCommands_Command_Map)");

	return Plugin_Handled;
}

public Action Command_MapButFaster(int client, const char[] command, int args)
{
	if (!g_cvHijackMap.BoolValue || !CheckCommandAccess(client, "sm_map", ADMFLAG_CHANGEMAP))
	{
		return Plugin_Continue;
	}

	if (client == 0)
	{
		if (args < 1)
		{
			ReplyToCommand(client, "[SM] Usage: sm_map <map>");
			return Plugin_Stop;
		}

		BaseCommands_Command_Map(client, args);
	}
	else
	{
		BaseCommands_Command_Map_Menu(client, args);
	}

	return Plugin_Stop;
}

public Action Command_Debug(int client, int args)
{
	g_bDebug = !g_bDebug;
	ReplyToCommand(client, "%sDebug mode: %s", g_cPrefix, g_bDebug ? "ENABLED" : "DISABLED");
	return Plugin_Handled;
}

void RTVClient(int client)
{
	g_bRockTheVote[client] = true;
	Call_StartForward(g_hForward_OnRTV);
	Call_PushCell(client);
	Call_Finish();
}

void UnRTVClient(int client)
{
	g_bRockTheVote[client] = false;
	Call_StartForward(g_hForward_OnUnRTV);
	Call_PushCell(client);
	Call_Finish();
}

/* Stocks */
stock void RemoveString(ArrayList array, const char[] target)
{
	int idx = array.FindString(target);
	if(idx != -1)
	{
		array.Erase(idx);
	}
}

void GetRTVStuff(int& total_needed, int& remaining_needed, int& rtvcount)
{
	float now = GetEngineTime();

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			// dont count players that can't vote
			if(!g_cvRTVAllowSpectators.BoolValue && IsClientObserver(i) && (now - g_fSpecTimerStart[i]) >= g_cvRTVSpectatorCooldown.FloatValue)
			{
				continue;
			}

			if(g_cvRTVMinimumPoints.IntValue != -1 && Shavit_GetPoints(i) <= g_cvRTVMinimumPoints.FloatValue)
			{
				continue;
			}

			total_needed++;

			if(g_bRockTheVote[i])
			{
				rtvcount++;
			}
		}
	}

	total_needed = RoundToCeil(total_needed * (g_cvRTVRequiredPercentage.FloatValue / 100));

	// always clamp to 1, so if rtvcount is 0 it never initiates RTV
	if (total_needed < 1)
	{
		total_needed = 1;
	}

	remaining_needed = total_needed - rtvcount;
}

void DebugPrint(const char[] message, any ...)
{
	if (!g_bDebug)
	{
		return;
	}

	char buffer[256];
	VFormat(buffer, sizeof(buffer), message, 2);

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && CheckCommandAccess(i, "sm_smcdebug", ADMFLAG_RCON))
		{
			PrintToChat(i, buffer);
		}
	}
}

public any Native_GetMapsArrayList(Handle plugin, int numParams)
{
	return g_aMapList;
}

public any Native_GetMapsStringMap(Handle plugin, int numParams)
{
	return g_mMapList;
}
