#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <shavit>
#include <cstrike>

#undef REQUIRE_PLUGIN
// for MapChange type
#include <mapchooser>

#define PLUGIN_VERSION "1.0.4.7"


Database g_hDatabase;
char g_cSQLPrefix[32];


#if defined DEBUG
bool g_bDebug;
#endif

/* ConVars */
ConVar g_cvRTVRequiredPercentage;
ConVar g_cvRTVAllowSpectators;
ConVar g_cvRTVMinimumPoints;
ConVar g_cvRTVDelayTime;

ConVar g_cvMapListType;
ConVar g_cvMatchFuzzyMap;

ConVar g_cvMapVoteStartTime;
ConVar g_cvMapVoteDuration;
ConVar g_cvMapVoteBlockMapInterval;
ConVar g_cvMapVoteExtendLimit;
ConVar g_cvMapVoteEnableNoVote;
ConVar g_cvMapVoteExtendTime;
ConVar g_cvMapVoteShowTier;
ConVar g_cvMapVoteRunOff;
ConVar g_cvMapVoteRunOffPerc;
ConVar g_cvMapVoteRevoteTime;
ConVar g_cvDisplayTimeRemaining;

ConVar g_cvNominateMatches;
ConVar g_cvEnhancedMenu;

ConVar g_cvMinTier;
ConVar g_cvMaxTier;


/* Map arrays */
ArrayList g_aMapList;
ArrayList g_aNominateList;
ArrayList g_aAllMapsList;
ArrayList g_aOldMaps;

/* Map Data */
char g_cMapName[PLATFORM_MAX_PATH];

MapChange g_ChangeTime;

bool g_bMapVoteStarted;
bool g_bMapVoteFinished;
float g_fMapStartTime;
float g_fLastMapvoteTime = 0.0;

int g_iExtendCount;

Menu g_hNominateMenu;
Menu g_hEnhancedMenu;

ArrayList g_aTierMenus;

Menu g_hVoteMenu;

/* Player Data */
bool g_bRockTheVote[MAXPLAYERS + 1];
char g_cNominatedMap[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

Handle g_hRetryTimer = null;
Handle g_hForward_OnRTV = null;
Handle g_hForward_OnUnRTV = null;
Handle g_hForward_OnSuccesfulRTV = null;

enum
{
	MapListZoned,
	MapListFile,
	MapListFolder,
	MapListMixed
}

public Plugin myinfo =
{
	name = "shavit - MapChooser",
	author = "SlidyBat",
	description = "Automated Map Voting and nominating with Shavit timer integration",
	version = PLUGIN_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_hForward_OnRTV = CreateGlobalForward("SMC_OnRTV", ET_Event, Param_Cell);
	g_hForward_OnUnRTV = CreateGlobalForward("SMC_OnUnRTV", ET_Event, Param_Cell);
	g_hForward_OnSuccesfulRTV = CreateGlobalForward("SMC_OnSuccesfulRTV", ET_Event);

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("mapchooser.phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("rockthevote.phrases");
	LoadTranslations("nominations.phrases");

	g_aMapList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_aAllMapsList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_aNominateList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_aOldMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	g_aTierMenus = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	
	g_cvMapListType = CreateConVar("smc_maplist_type", "1", "Where the plugin should get the map list from. 0 = zoned maps from database, 1 = from maplist file (mapcycle.txt), 2 = from maps folder, 3 = from zoned maps and confirmed by maplist file", _, true, 0.0, true, 3.0);
	g_cvMatchFuzzyMap = CreateConVar("smc_match_fuzzy", "1", "If set to 1, the plugin will accept partial map matches from the database. Useful for workshop maps, bad for duplicate map names", _, true, 0.0, true, 1.0);
	
	g_cvMapVoteBlockMapInterval = CreateConVar("smc_mapvote_blockmap_interval", "1", "How many maps should be played before a map can be nominated again", _, true, 0.0, false);
	g_cvMapVoteEnableNoVote = CreateConVar("smc_mapvote_enable_novote", "1", "Whether players are able to choose 'No Vote' in map vote", _, true, 0.0, true, 1.0);
	g_cvMapVoteExtendLimit = CreateConVar("smc_mapvote_extend_limit", "3", "How many times players can choose to extend a single map (0 = block extending)", _, true, 0.0, false);
	g_cvMapVoteExtendTime = CreateConVar("smc_mapvote_extend_time", "10", "How many minutes should the map be extended by if the map is extended through a mapvote", _, true, 1.0, false);
	g_cvMapVoteShowTier = CreateConVar("smc_mapvote_show_tier", "1", "Whether the map tier should be displayed in the map vote", _, true, 0.0, true, 1.0);
	g_cvMapVoteDuration = CreateConVar("smc_mapvote_duration", "1", "Duration of time in minutes that map vote menu should be displayed for", _, true, 0.1, false);
	g_cvMapVoteStartTime = CreateConVar("smc_mapvote_start_time", "5", "Time in minutes before map end that map vote starts", _, true, 1.0, false);
	
	g_cvRTVAllowSpectators = CreateConVar("smc_rtv_allow_spectators", "1", "Whether spectators should be allowed to RTV", _, true, 0.0, true, 1.0);
	g_cvRTVMinimumPoints = CreateConVar("smc_rtv_minimum_points", "-1", "Minimum number of points a player must have before being able to RTV, or -1 to allow everyone", _, true, -1.0, false);
	g_cvRTVDelayTime = CreateConVar("smc_rtv_delay", "5", "Time in minutes after map start before players should be allowed to RTV", _, true, 0.0, false);
	g_cvRTVRequiredPercentage = CreateConVar("smc_rtv_required_percentage", "50", "Percentage of players who have RTVed before a map vote is initiated", _, true, 1.0, true, 100.0);

	g_cvMapVoteRunOff = CreateConVar("smc_mapvote_runoff", "1", "Hold run of votes if winning choice is less than a certain margin", _, true, 0.0, true, 1.0);
	g_cvMapVoteRunOffPerc = CreateConVar("smc_mapvote_runoffpercent", "50", "If winning choice has less than this percent of votes, hold a runoff", _, true, 0.0, true, 100.0);
	g_cvMapVoteRevoteTime = CreateConVar("smc_mapvote_revotetime", "0", "How many minutes after a failed mapvote before rtv is enabled again", _, true, 0.0);
	g_cvDisplayTimeRemaining = CreateConVar("smc_display_timeleft", "1", "Display remaining messages in chat", _, true, 0.0, true, 1.0);

	g_cvNominateMatches = CreateConVar("smc_nominate_matches", "1", "Prompts a menu which shows all maps which match argument",  _, true, 0.0, true, 1.0);
	g_cvEnhancedMenu = CreateConVar("smc_enhanced_menu", "1", "Nominate menu can show maps by alphabetic order and tiers",  _, true, 0.0, true, 1.0);

	g_cvMinTier = CreateConVar("smc_min_tier", "0", "The minimum tier to show on the enhanced menu",  _, true, 0.0, true, 10.0);
	g_cvMaxTier = CreateConVar("smc_max_tier", "10", "The maximum tier to show on the enhanced menu",  _, true, 0.0, true, 10.0);

	AutoExecConfig();
	
	RegAdminCmd("sm_extendmap", Command_Extend, ADMFLAG_RCON, "Admin command for extending map");
	RegAdminCmd("sm_forcemapvote", Command_ForceMapVote, ADMFLAG_RCON, "Admin command for forcing the end of map vote");
	RegAdminCmd("sm_reloadmaplist", Command_ReloadMaplist, ADMFLAG_CHANGEMAP, "Admin command for forcing maplist to be reloaded");
	
	RegConsoleCmd("sm_nominate", Command_Nominate, "Lets players nominate maps to be on the end of map vote");
	RegConsoleCmd("sm_unnominate", Command_UnNominate, "Removes nominations");
	RegConsoleCmd("sm_rtv", Command_RockTheVote, "Lets players Rock The Vote");
	RegConsoleCmd("sm_unrtv", Command_UnRockTheVote, "Lets players un-Rock The Vote");
	RegConsoleCmd("sm_nomlist", Command_NomList, "Shows currently nominated maps");
	
	#if defined DEBUG
	RegConsoleCmd("sm_smcdebug", Command_Debug);
	#endif
}

public void OnMapStart()
{
	GetCurrentMap(g_cMapName, sizeof(g_cMapName));

	SetNextMap(g_cMapName);
	
	// disable rtv if delay time is > 0
	g_fMapStartTime = GetGameTime();
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
	
	
	CreateTimer(2.0, Timer_OnMapTimeLeftChanged, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnConfigsExecuted()
{
	// reload maplist array
	LoadMapList();
	// cache the nominate menu so that it isn't being built every time player opens it
}

public void OnMapEnd()
{
	if(g_cvMapVoteBlockMapInterval.IntValue > 0)
	{
		g_aOldMaps.PushString(g_cMapName);
		if(g_aOldMaps.Length > g_cvMapVoteBlockMapInterval.IntValue)
		{
			g_aOldMaps.Erase(0);
		}
	}
	
	g_iExtendCount = 0;
	
									
	g_bMapVoteFinished = false;
	g_bMapVoteStarted = false;
	
	g_aNominateList.Clear();
	for(int i = 1; i <= MaxClients; i++)
	{
		g_cNominatedMap[i][0] = '\0';
	}
	
	ClearRTV();
}

public Action Timer_OnMapTimeLeftChanged(Handle Timer)
{
	#if defined DEBUG
	if(g_bDebug)
	{
		DebugPrint("[SMC] OnMapTimeLeftChanged: maplist_length=%i mapvote_started=%s mapvotefinished=%s", g_aMapList.Length, g_bMapVoteStarted ? "true" : "false", g_bMapVoteFinished ? "true" : "false");
	}
	#endif
	
	int timeleft;
	if(GetMapTimeLeft(timeleft))
	{
		if(!g_bMapVoteStarted && !g_bMapVoteFinished)
		{
			int mapvoteTime = timeleft - RoundFloat(g_cvMapVoteStartTime.FloatValue * 60.0);
			switch(mapvoteTime)
			{
				case (10 * 60) - 3:
				{
					PrintToChatAll("[SMC] 10 minutes until map vote");
				}
				case (5 * 60) - 3:
				{
					PrintToChatAll("[SMC] 5 minutes until map vote");
				}
				case 60 - 3:
				{
					PrintToChatAll("[SMC] 1 minute until map vote");
				}
				case 30 - 3:
				{
					PrintToChatAll("[SMC] 30 seconds until map vote");
				}
				case 5 - 3:
				{
					PrintToChatAll("[SMC] 5 seconds until map vote");
				}
			}
		}
		else if(g_bMapVoteFinished && g_cvDisplayTimeRemaining.BoolValue)
		{
			switch(timeleft)
			{
				case (30 * 60) - 3:
				{
					PrintToChatAll("[SMC] 30 minutes remaining");
				}
				case (20 * 60) - 3:
				{
					PrintToChatAll("[SMC] 20 minutes remaining");
				}
				case (10 * 60) - 3:
				{
					PrintToChatAll("[SMC] 10 minutes remaining");
				}
				case (5 * 60) - 3:
				{
					PrintToChatAll("[SMC] 5 minutes remaining");
				}
				case 60 - 3:
				{
					PrintToChatAll("[SMC] 1 minute remaining");
				}
				case 10 - 3:
				{
					PrintToChatAll("[SMC] 10 seconds remaining");
				}
				case 5 - 3:
				{
					PrintToChatAll("[SMC] 5 seconds remaining");
				}
				case 3 - 3:
				{
					PrintToChatAll("[SMC] 3 seconds remaining");
				}
				case 2 - 3:
				{
					PrintToChatAll("[SMC] 2 seconds remaining");
				}
				case 1 - 3:
				{
					PrintToChatAll("[SMC] 1 seconds remaining");
				}
			}
		}
	}
	
	if(g_aMapList.Length && !g_bMapVoteStarted && !g_bMapVoteFinished)
	{
		CheckTimeLeft();
	}
}

void CheckTimeLeft()
{
	int timeleft;
	if(GetMapTimeLeft(timeleft) && timeleft > 0)
	{
		int startTime = RoundFloat(g_cvMapVoteStartTime.FloatValue * 60.0);
		#if defined DEBUG
		if(g_bDebug)
		{
			DebugPrint("[SMC] CheckTimeLeft: timeleft=%i startTime=%i", timeleft, startTime);
		}
		#endif
		
		if(timeleft - startTime <= 0)
		{
			#if defined DEBUG
			if(g_bDebug)
			{
				DebugPrint("[SMC] CheckTimeLeft: Initiating map vote ...", timeleft, startTime);
			}
			#endif
		
			InitiateMapVote(MapChange_MapEnd);
		}
	}
	#if defined DEBUG
	else
	{
		if(g_bDebug)
		{
			DebugPrint("[SMC] CheckTimeLeft: GetMapTimeLeft=%s timeleft=%i", GetMapTimeLeft(timeleft) ? "true" : "false", timeleft);
		}
	}
	#endif
}

public void OnClientDisconnect(int client)
{
	// clear player data
	g_bRockTheVote[client] = false;
	g_cNominatedMap[client][0] = '\0';
	
	CheckRTV();
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if(StrEqual(sArgs, "rtv", false) || StrEqual(sArgs, "rockthevote", false))
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		Command_RockTheVote(client, 0);
		
		SetCmdReplySource(old);
	}
	else if(StrEqual(sArgs, "nominate", false))
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		Command_Nominate(client, 0);
		
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
	
	int mapsToAdd = 8;
	if(g_cvMapVoteExtendLimit.IntValue > 0 && g_iExtendCount < g_cvMapVoteExtendLimit.IntValue)
	{
		mapsToAdd--;
	}
	
	if(g_cvMapVoteEnableNoVote.BoolValue)
	{
		mapsToAdd--;
	}
	
	char map[PLATFORM_MAX_PATH];
	char mapdisplay[PLATFORM_MAX_PATH + 32];
	
	int nominateMapsToAdd = (mapsToAdd > g_aNominateList.Length) ? g_aNominateList.Length : mapsToAdd;
	for(int i = 0; i < nominateMapsToAdd; i++)
	{
		g_aNominateList.GetString(i, map, sizeof(map));
		GetMapDisplayName(map, mapdisplay, sizeof(mapdisplay));	
		
		if(g_cvMapVoteShowTier.BoolValue)
		{
			int tier = Shavit_GetMapTier(mapdisplay);
			
			
			Format(mapdisplay, sizeof(mapdisplay), "[T%i] %s", tier, mapdisplay);
		}
		else
		{
			strcopy(mapdisplay, sizeof(mapdisplay), map);
		}
		
		menu.AddItem(map, mapdisplay);
		
		mapsToAdd--;
	}
	
	for(int i = 0; i < mapsToAdd; i++)
	{
		int rand = GetRandomInt(0, g_aMapList.Length - 1);
		g_aMapList.GetString(rand, map, sizeof(map));
		
		GetMapDisplayName(map, mapdisplay, sizeof(mapdisplay));		
		
		if(StrEqual(map, g_cMapName))
		{
			// don't add current map to vote
			i--;
			continue;
		}
		
		int idx = g_aOldMaps.FindString(map);
		if(idx != -1)
		{
			// map already played recently, get another map
			i--;
			continue;
		}
		
		if(g_cvMapVoteShowTier.BoolValue)
		{
			int tier = Shavit_GetMapTier(mapdisplay);
			
			Format(mapdisplay, sizeof(mapdisplay), "[T%i] %s", tier, mapdisplay);
		}

		
		menu.AddItem(map, mapdisplay);
	}
	
	if(when == MapChange_MapEnd && g_cvMapVoteExtendLimit.IntValue > 0 && g_iExtendCount < g_cvMapVoteExtendLimit.IntValue)
	{
		menu.AddItem("extend", "Extend Map");
	}
	else if(when == MapChange_Instant)
	{
		menu.AddItem("dontchange", "Don't Change");
	}
	
	menu.NoVoteButton = g_cvMapVoteEnableNoVote.BoolValue;
	menu.ExitButton = false;
	menu.DisplayVoteToAll(RoundFloat(g_cvMapVoteDuration.FloatValue * 60.0));
	
	PrintToChatAll("[SMC] %t", "Nextmap Voting Started");
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
			
			
			PrintToChatAll("[SM] %t", "Starting Runoff", g_cvMapVoteRunOffPerc.FloatValue, info1, map1percent, info2, map2percent);
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

public void Handler_VoteFinishedGeneric(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	char map[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];
	
	menu.GetItem(item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof(map), _, displayName, sizeof(displayName));

	PrintToChatAll("#1 vote was %s (%s)", map, (g_ChangeTime == MapChange_Instant) ? "instant" : "map end");
 
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

		PrintToChatAll("[SMC] %t", "Current Map Extended", RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has finished. The current map has been extended.");
		
		// We extended, so we'll have to vote again.
		g_bMapVoteStarted = false;
		g_fLastMapvoteTime = GetGameTime();
		
		ClearRTV();
	}
	else if(StrEqual(map, "dontchange"))
	{
		PrintToChatAll("[SMC] %t", "Current Map Stays", RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has finished. 'No Change' was the winner");

		g_bMapVoteFinished = false;
		g_bMapVoteStarted = false;
		g_fLastMapvoteTime = GetGameTime();
		
		ClearRTV();
	}
	else
	{
		if(g_ChangeTime == MapChange_MapEnd)
		{
			SetNextMap(map);
		}
		else if(g_ChangeTime == MapChange_Instant)
		{
			if(GetRTVVotesNeeded() <= 0)
			{
				Call_StartForward(g_hForward_OnSuccesfulRTV);
				Call_Finish();
			}

			DataPack data;
			CreateDataTimer(2.0, Timer_ChangeMap, data);
			data.WriteString(map);
			ClearRTV();
		}
		
		g_bMapVoteStarted = false;
		g_bMapVoteFinished = true;
		
		PrintToChatAll("[SMC] %t", "Nextmap Voting Finished", displayName, RoundToFloor(float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
		LogAction(-1, -1, "Voting for next map has finished. Nextmap: %s.", map);
	}	
}

public int Handler_MapVoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
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
					Format(buffer, sizeof(buffer), "Extend Map");
					return RedrawMenuItem(buffer);
				}
				else if (strcmp(map, "novote", false) == 0)
				{
					Format(buffer, sizeof(buffer), "No Vote");
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
				menu.GetItem(0, map, sizeof(map));
				
				// Make sure the first map in the menu isn't one of the special items.
				// This would mean there are no real maps in the menu, because the special items are added after all maps. Don't do anything if that's the case.
				if(strcmp(map, "extend", false) != 0 && strcmp(map, "dontchange", false) != 0)
				{
					// Get a random map from the list.
					
					// Make sure it's not one of the special items.
					do
					{
						int item = GetRandomInt(0, count - 1);
						menu.GetItem(item, map, sizeof(map));
					}
					while(strcmp(map, "extend", false) == 0 || strcmp(map, "dontchange", false) == 0);
					
					SetNextMap(map);
					PrintToChatAll("[SMC] %t", "Nextmap Voting Finished", map, 0, 0);
					LogAction(-1, -1, "Voting for next map has finished. Nextmap: %s.", map);
					g_bMapVoteFinished = true;
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

// extends map while also notifying players and setting plugin data
void ExtendMap(int time = 0)
{
	if(time == 0)
	{
		time = RoundFloat(g_cvMapVoteExtendTime.FloatValue * 60);
	}

	ExtendMapTimeLimit(time);
	PrintToChatAll("[SMC] The map was extended for %.1f minutes", time / 60.0);
	
	g_bMapVoteStarted = false;
	g_bMapVoteFinished = false;
}

void LoadMapList()
{
	g_aMapList.Clear();
	g_aAllMapsList.Clear();
	

	switch(g_cvMapListType.IntValue)
	{
		case MapListZoned:
		{
			delete g_hDatabase;
			SQL_SetPrefix();
			
			char buffer[512];
			g_hDatabase = SQL_Connect("shavit", true, buffer, sizeof(buffer));

			Format(buffer, sizeof(buffer), "SELECT `map` FROM `%smapzones` WHERE `type` = 1 AND `track` = 0 ORDER BY `map`", g_cSQLPrefix);
			g_hDatabase.Query(LoadZonedMapsCallback, buffer, _, DBPrio_High);
		}
		case MapListFolder:
		{
			LoadFromMapsFolder(g_aMapList);
			CreateNominateMenu();
		}
		case MapListFile:
		{
			ReadMapList(g_aMapList, _, "default");
			CreateNominateMenu();
		}
		case MapListMixed:
		{
			delete g_hDatabase;
			SQL_SetPrefix();

			ReadMapList(g_aAllMapsList, _, "default");

			char buffer[512];
			g_hDatabase = SQL_Connect("shavit", true, buffer, sizeof(buffer));
			Format(buffer, sizeof(buffer), "SELECT `map` FROM `%smapzones` WHERE `type` = 1 AND `track` = 0 ORDER BY `map`", g_cSQLPrefix);
			g_hDatabase.Query(LoadZonedMapsCallbackMixed, buffer, _, DBPrio_High);
		}
	}

	
}

public void LoadZonedMapsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("[SMC] - (LoadMapZonesCallback) - %s", error);
		return;	
	}

	char map[PLATFORM_MAX_PATH];
	char map2[PLATFORM_MAX_PATH];
	while(results.FetchRow())
	{	
		results.FetchString(0, map, sizeof(map));
		
		
		if((FindMap(map, map2, sizeof(map2)) == FindMap_Found) || (g_cvMatchFuzzyMap.BoolValue && FindMap(map, map2, sizeof(map2)) == FindMap_FuzzyMatch))
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
		LogError("[SMC] - (LoadMapZonesCallbackMixed) - %s", error);
		return;	
	}

	char map[PLATFORM_MAX_PATH];
	char map2[PLATFORM_MAX_PATH];
	char buffer[PLATFORM_MAX_PATH];
	while(results.FetchRow())
	{	
		results.FetchString(0, map, sizeof(map));//db mapname
		
		for (int i = 0; i < g_aAllMapsList.Length; ++i)
		{
			g_aAllMapsList.GetString(i, buffer, sizeof(buffer));//maplistmapname
			GetMapDisplayName(buffer, map2, sizeof(map2));//get's the displayname of the map

			if (StrEqual(map, map2, false))
			{	
				g_aMapList.PushString(buffer); 
			}
		}
	}
	
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
	subNominateMenu.SetTitle("Nominate Menu\nMaps matching \"%s\"\n ", mapname);
	bool isCurrentMap = false;
	bool isOldMap = false;
	char map[PLATFORM_MAX_PATH];
	char oldMapName[PLATFORM_MAX_PATH];
	
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
			char mapdisplay[PLATFORM_MAX_PATH + 32];
			GetMapDisplayName(entry, mapdisplay, sizeof(mapdisplay));
	
			int tier = Shavit_GetMapTier(mapdisplay);
	
			Format(mapdisplay, sizeof(mapdisplay), "%s | T%i", mapdisplay, tier);
			
			subNominateMenu.AddItem(entry, mapdisplay);
		}
    }
    
	switch (subNominateMenu.ItemCount) 
	{
    	case 0:
    	{
    		if (isCurrentMap) 
    		{
				ReplyToCommand(client, "[SMC] %t", "Can't Nominate Current Map");
			}
			else if (isOldMap) 
			{
				ReplyToCommand(client, "[SMC] %s %t", oldMapName, "Recently Played");
			}
			else 
			{
				ReplyToCommand(client, "[SMC] %t", "Map was not found", mapname);	
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
	float time = GetGameTime();

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
	char map[PLATFORM_MAX_PATH];
	data.Reset();
	data.ReadString(map, sizeof(map));
	
	ForceChangeLevel(map, "RTV Mapvote");
}

/* Commands */
public Action Command_Extend(int client, int args)
{
	int extendtime;
	if(args > 0)
	{
		char sArg[8];
		GetCmdArg(1, sArg, sizeof(sArg));
		extendtime = RoundFloat(StringToFloat(sArg) * 60);
	}
	else
	{
		extendtime = RoundFloat(g_cvMapVoteExtendTime.FloatValue * 60.0);
	}
	
	ExtendMap(extendtime);
	
	return Plugin_Handled;
}

public Action Command_ForceMapVote(int client, int args)
{
	if(g_bMapVoteStarted || g_bMapVoteFinished)
	{
		ReplyToCommand(client, "[SMC] Map vote already %s", (g_bMapVoteStarted) ? "initiated" : "finished");
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

	if (g_cvNominateMatches.BoolValue)
	{
		SMC_NominateMatches(client, mapname);
	}
	else {
		if(SMC_FindMap(mapname, mapname, sizeof(mapname)))
		{
			if(StrEqual(mapname, g_cMapName))
			{
				ReplyToCommand(client, "[SMC] %t", "Can't Nominate Current Map");
				return Plugin_Handled;
			}
			
			int idx = g_aOldMaps.FindString(mapname);
			if(idx != -1)
			{
				ReplyToCommand(client, "[SMC] %s %t", mapname, "Recently Played");
				return Plugin_Handled;
			}
		
			ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
			Nominate(client, mapname);
			SetCmdReplySource(old);
		}
		else
		{
			ReplyToCommand(client, "[SMC] %t", "Map was not found", mapname);
		}
	}
	
	return Plugin_Handled;
}

public Action Command_UnNominate(int client, int args)
{
	if(g_cNominatedMap[client][0] == '\0')
	{
		ReplyToCommand(client, "[SMC] You haven't nominated a map");
		return Plugin_Handled;
	}

	int idx = g_aNominateList.FindString(g_cNominatedMap[client]);
	if(idx != -1)
	{
		ReplyToCommand(client, "[SMC] Successfully removed nomination for '%s'", g_cNominatedMap[client]);
		g_aNominateList.Erase(idx);
		g_cNominatedMap[client][0] = '\0';
	}

	return Plugin_Handled;
}

void CreateNominateMenu()
{
	delete g_hNominateMenu;
	g_hNominateMenu = new Menu(NominateMenuHandler);
	
	g_hNominateMenu.SetTitle("Nominate Menu");
	
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
		
		char mapdisplay[PLATFORM_MAX_PATH + 32];
		GetMapDisplayName(mapname, mapdisplay, sizeof(mapdisplay));


		int tier = Shavit_GetMapTier(mapdisplay);

		Format(mapdisplay, sizeof(mapdisplay), "%s | T%i", mapdisplay, tier);
		
		g_hNominateMenu.AddItem(mapname, mapdisplay, style);
	}

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
	
	g_hEnhancedMenu.SetTitle("Nominate Menu");	
	g_hEnhancedMenu.AddItem("Alphabetic", "Alphabetic");

	for(int i = GetConVarInt(g_cvMinTier); i <= GetConVarInt(g_cvMaxTier); ++i)
	{
		if (GetMenuItemCount(g_aTierMenus.Get(i-GetConVarInt(g_cvMinTier))) > 0) 
		{
			char tierDisplay[PLATFORM_MAX_PATH + 32];

			Format(tierDisplay, sizeof(tierDisplay), "Tier %i", i);

			char tierString[PLATFORM_MAX_PATH + 32];
			Format(tierString, sizeof(tierString), "%i", i);
			g_hEnhancedMenu.AddItem(tierString, tierDisplay);
		}
	}
}

void CreateTierMenus()
{
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

	InitTierMenus(min,max);

	int length = g_aMapList.Length;
	for(int i = 0; i < length; ++i)
	{
		int style = ITEMDRAW_DEFAULT;
		char mapname[PLATFORM_MAX_PATH];
		g_aMapList.GetString(i, mapname, sizeof(mapname));
		
		char mapdisplay[PLATFORM_MAX_PATH + 32];
		GetMapDisplayName(mapname, mapdisplay, sizeof(mapdisplay));
		
		int mapTier = Shavit_GetMapTier(mapdisplay);

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
			AddMenuItem(g_aTierMenus.Get(mapTier-min), mapname, mapdisplay, style);
		}
	}

	CreateEnhancedMenu();
}

void InitTierMenus(int min, int max) 
{
	g_aTierMenus.Clear();

	for(int i = min; i <= max; i++)
	{
		Menu TierMenu = new Menu(NominateMenuHandler);
		TierMenu.SetTitle("Nominate Menu\nTier \"%i\" Maps\n ", i);
		TierMenu.ExitBackButton = true;

		g_aTierMenus.Push(TierMenu);
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

void OpenEnhancedMenu(int client)
{
	g_hEnhancedMenu.Display(client, MENU_TIME_FOREVER);
}

void OpenNominateMenuTier(int client, int tier) 
{
	DisplayMenu(g_aTierMenus.Get(tier-GetConVarInt(g_cvMinTier)), client, MENU_TIME_FOREVER);
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
		OpenEnhancedMenu(param1);
	}
	else if (action == MenuAction_End) 
	{
		if (menu != g_hNominateMenu && menu != INVALID_HANDLE && FindValueInArray(g_aTierMenus, menu) == -1) 
		{
			CloseHandle(menu);
		}
	}
}

public int EnhancedMenuHandler(Menu menu, MenuAction action, int client, int param2) 
{
	if (action == MenuAction_Select) 
	{
		char option[PLATFORM_MAX_PATH];
		menu.GetItem(param2, option, sizeof(option));

		if (StrEqual(option , "Alphabetic")) 
		{
			OpenNominateMenu(client);
		}
		else 
		{
			OpenNominateMenuTier(client, StringToInt(option));
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack) 
	{
		OpenEnhancedMenu(client);
	}
}

void Nominate(int client, const char mapname[PLATFORM_MAX_PATH])
{
	int idx = g_aNominateList.FindString(mapname);
	if(idx != -1)
	{
		ReplyToCommand(client, "[SMC] %t", "Map Already Nominated");
		return;
	}
	
	if(g_cNominatedMap[client][0] != '\0')
	{
		RemoveString(g_aNominateList, g_cNominatedMap[client]);
	}
	
	g_aNominateList.PushString(mapname);
	g_cNominatedMap[client] = mapname;
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	
	PrintToChatAll("[SMC] %t", "Map Nominated", name, mapname);
}

public Action Command_RockTheVote(int client, int args)
{
	if(!IsRTVEnabled())
	{
		ReplyToCommand(client, "[SMC] %t", "RTV Not Allowed");
	}
	else if(g_bMapVoteStarted)
	{
		ReplyToCommand(client, "[SMC] %t", "RTV Started");
	}
	else if(g_bRockTheVote[client])
	{
		int needed = GetRTVVotesNeeded();
		ReplyToCommand(client, "[SMC] You have already RTVed, if you want to un-RTV use the command sm_unrtv (%i more %s needed)", needed, (needed == 1) ? "vote" : "votes");
	}
	else if(g_cvRTVMinimumPoints.IntValue != -1 && Shavit_GetPoints(client) <= g_cvRTVMinimumPoints.FloatValue)
	{
		ReplyToCommand(client, "[SMC] You must be a higher rank to RTV!");
	}
	else if(GetClientTeam(client) == CS_TEAM_SPECTATOR && !g_cvRTVAllowSpectators.BoolValue)
	{
		ReplyToCommand(client, "[SMC] Spectators have been blocked from RTVing");
	}
	else
	{
		RTVClient(client);
		CheckRTV(client);
	}
	
	return Plugin_Handled;
}

void CheckRTV(int client = 0)
{
	int needed = GetRTVVotesNeeded();
	int rtvcount = GetRTVCount();
	int total = GetRTVTotalNeeded();
	char name[MAX_NAME_LENGTH];
	
	if(client != 0)
	{
		GetClientName(client, name, sizeof(name));
	}
	if(needed > 0)
	{
		if(client != 0)
		{
			PrintToChatAll("[SMC] %t", "RTV Requested", name, rtvcount, total);
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
				PrintToChatAll("[SMC] %N wants to rock the vote! Map will now change to %s ...", client, map);
			}
			else
			{
				PrintToChatAll("[SMC] RTV vote now majority, map changing to %s ...", map);
			}

			SetNextMap(map);
			ChangeMapDelayed(map);
		}
		else
		{
			if(client != 0)
			{
				PrintToChatAll("[SMC] %N wants to rock the vote! Map vote will now start ...", client);
			}
			else
			{
				PrintToChatAll("[SMC] RTV vote now majority, map vote starting ...");
			}
			
			InitiateMapVote(MapChange_Instant);
		}
	}
}

public Action Command_UnRockTheVote(int client, int args)
{
	if(!IsRTVEnabled())
	{
		ReplyToCommand(client, "[SMC] RTV has not been enabled yet");
	}
	else if(g_bMapVoteStarted || g_bMapVoteFinished)
	{
		ReplyToCommand(client, "[SMC] Map vote already %s", (g_bMapVoteStarted) ? "initiated" : "finished");
	}
	else if(g_bRockTheVote[client])
	{
		UnRTVClient(client);
		
		int needed = GetRTVVotesNeeded();
		if(needed > 0)
		{
			PrintToChatAll("[SMC] %N no longer wants to rock the vote! (%i more votes needed)", client, needed);
		}
	}

	return Plugin_Handled;
}

public Action Command_NomList(int client, int args)
{
	if(g_aNominateList.Length < 1)
	{
		ReplyToCommand(client, "[SMC] No Maps Nominated");
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
}

#if defined DEBUG
public Action Command_Debug(int client, int args)
{
	if(IsSlidy(client))
	{
		g_bDebug = !g_bDebug;
		ReplyToCommand(client, "[SMC] Debug mode: %s", g_bDebug ? "ENABLED" : "DISABLED");
		
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}
#endif

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
stock void SQL_SetPrefix()
{
	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");
	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}

	char sLine[PLATFORM_MAX_PATH*2];
	while(fFile.ReadLine(sLine, sizeof(sLine)))
	{
		TrimString(sLine);
		strcopy(g_cSQLPrefix, sizeof(g_cSQLPrefix), sLine);

		break;
	}

	delete fFile;	
}

stock void RemoveString(ArrayList array, const char[] target)
{
	int idx = array.FindString(target);
	if(idx != -1)
	{
		array.Erase(idx);
	}
}

stock bool LoadFromMapsFolder(ArrayList list)
{
	//from yakmans maplister plugin
	DirectoryListing mapdir = OpenDirectory("maps/");
	if(mapdir == null)
		return false;
	
	char name[PLATFORM_MAX_PATH];
	FileType filetype;
	int namelen;
	
	while(mapdir.GetNext(name, sizeof(name), filetype))
	{
		if(filetype != FileType_File)
			continue;
				
		namelen = strlen(name) - 4;
		if(StrContains(name, ".bsp", false) != namelen)
			continue;
				
		name[namelen] = '\0';
			
		list.PushString(name);
	}

	delete mapdir;

	return true;
}

stock void ChangeMapDelayed(const char[] map, float delay = 2.0)
{
	DataPack data;
	CreateDataTimer(delay, Timer_ChangeMap, data);
	data.WriteString(map);
}

stock int GetRTVVotesNeeded()
{
	int total = 0;
	int rtvcount = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			// dont count players that can't vote
			if(!g_cvRTVAllowSpectators.BoolValue && IsClientObserver(i))
			{
				continue;
			}
			
			if(g_cvRTVMinimumPoints.IntValue != -1 && Shavit_GetPoints(i) <= g_cvRTVMinimumPoints.FloatValue)
			{
				continue;
			}
		
			total++;
			if(g_bRockTheVote[i])
			{
				rtvcount++;
			}
		}
	}
	
	int Needed = RoundToFloor(total * (g_cvRTVRequiredPercentage.FloatValue / 100));
	
	// always clamp to 1, so if rtvcount is 0 it never initiates RTV
	if(Needed < 1)
	{
		Needed = 1;
	}
	
	return Needed - rtvcount;
}

stock int GetRTVCount()
{
	int rtvcount = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			// dont count players that can't vote
			if(!g_cvRTVAllowSpectators.BoolValue && IsClientObserver(i))
			{
				continue;
			}
			
			if(g_cvRTVMinimumPoints.IntValue != -1 && Shavit_GetPoints(i) <= g_cvRTVMinimumPoints.FloatValue)
			{
				continue;
			}
			
			if(g_bRockTheVote[i])
			{
				rtvcount++;
			}
		}
	}
	
	return rtvcount;
}

stock int GetRTVTotalNeeded()
{
	int total = 0;
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			// dont count players that can't vote
			if(!g_cvRTVAllowSpectators.BoolValue && IsClientObserver(i))
			{
				continue;
			}
			
			if(g_cvRTVMinimumPoints.IntValue != -1 && Shavit_GetPoints(i) <= g_cvRTVMinimumPoints.FloatValue)
			{
				continue;
			}
		
			total++;
		}
	}
	
	int Needed = RoundToFloor(total * (g_cvRTVRequiredPercentage.FloatValue / 100));
	
	// always clamp to 1, so if rtvcount is 0 it never initiates RTV
	if(Needed < 1)
	{
		Needed = 1;
	}
	return Needed;
}

stock void DebugPrint(const char[] message, any ...)
{		
	char buffer[256];
	VFormat(buffer, sizeof(buffer), message, 2);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		// STEAM_1:1:159678344 (SlidyBat)
		if(GetSteamAccountID(i) == 319356689)
		{
			PrintToChat(i, buffer);
			return;
		}
	}
}
