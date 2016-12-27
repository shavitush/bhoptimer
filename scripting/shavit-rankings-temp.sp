#include <sourcemod>
#include <shavit>

// forwards
Handle gH_Forwards_OnRankUpdated = null;

//MySQL settings
Database gH_SQL = null;
bool gB_MySQL = false;
char gS_MySQLPrefix[32];

//Rankings
int gI_PlayerRank[MAXPLAYERS+1];
int gI_PlayerPoints[MAXPLAYERS+1];
int gI_RankedPlayers = 0;
ConVar gCV_TopAmount = null;
int gI_TopAmount = 100;
float gF_PlayerPB[MAXPLAYERS+1];

//Chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

// modules
bool gB_Stats = false;

public Plugin myinfo =
{
	name = "[shavit] Temporary Ranking",
	author = "shavit, theSaint",
	description = "Temporary Ranking system for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetPoints", Native_GetPoints);
	CreateNative("Shavit_GetRank", Native_GetRank);
	CreateNative("Shavit_GetRankedPlayers", Native_GetRankedPlayers);

	RegPluginLibrary("shavit-rankings");

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_OnRankUpdated = CreateGlobalForward("Shavit_OnRankUpdated", ET_Event, Param_Cell);
	
	//Translations
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-rankings.phrases");
	
	//Commands
	RegConsoleCmd("sm_rank", Command_Rank, "Shows your current rank.");
	RegConsoleCmd("sm_prank", Command_Rank, "Shows your current rank. (sm_rank alias)");
	RegConsoleCmd("sm_top", Command_Top, "Shows the top players menu.");
	RegConsoleCmd("sm_ptop", Command_Top, "Shows the top players menu. (sm_top alias)");
	
	//Admin Commands
	RegAdminCmd("sm_recalculate_rankings", Command_Recalculate, ADMFLAG_ROOT, "Recalculates all ranks for all players");
	
	gCV_TopAmount = CreateConVar("shavit_rankings_topamount", "100", "Amount of people to show within the sm_top menu.", 0, true, 1.0, false);
	gCV_TopAmount.AddChangeHook(OnConVarChanged);

	// database connections
	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();	
	
	// modules
	gB_Stats = LibraryExists("shavit-stats");
	
	HookEvent("player_spawned", Event_PlayerSpawned);
	
	UpdateLadders();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gI_TopAmount = gCV_TopAmount.IntValue;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = false;
	}
}

public void Shavit_OnChatConfigLoaded()
{
	for(int i = 0; i < CHATSETTINGS_SIZE; i++)
	{
		Shavit_GetChatStrings(i, gS_ChatStrings[i], 128);
	}
}

public void OnClientAuthorized(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	gI_PlayerPoints[client] = -1;
	gI_PlayerRank[client] = -1;

	if(gH_SQL != null)
	{
		UpdateClientInfo(client);
	}
	
	
}

// --------------------
// NATIVES
// --------------------

public int Native_GetPoints(Handle handler, int numParams)
{
	return gI_PlayerPoints[GetNativeCell(1)];
}

public int Native_GetRank(Handle handler, int numParams)
{
	return gI_PlayerRank[GetNativeCell(1)];
}

public int Native_GetRankedPlayers(Handle handler, int numParams)
{
	return gI_RankedPlayers;
}

// --------------------
// DATABASE CONNECTIONS
// --------------------

public void Shavit_OnDatabaseLoaded(Database db)
{
	gH_SQL = db;
}

void SQL_SetPrefix()
{
	char[] sFile = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}
	
	char[] sLine = new char[PLATFORM_MAX_PATH*2];

	while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
	{
		TrimString(sLine);
		strcopy(gS_MySQLPrefix, 32, sLine);

		break;
	}

	delete fFile;
}

Action SetSQLInfo()
{
	if(gH_SQL == null)
	{
		Shavit_GetDB(gH_SQL);

		CreateTimer(0.5, CheckForSQLInfo);
	}

	else
	{
		SQL_DBConnect();

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		char[] sDriver = new char[8];
		gH_SQL.Driver.GetIdentifier(sDriver, 8);
		gB_MySQL = StrEqual(sDriver, "mysql", false);

	}
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

// ----------------
// CLIENTS COMMANDS
// ----------------


public Action Command_Rank(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	int target = client;

	if(args > 0)
	{
		char[] sTarget = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		target = FindTarget(client, sTarget, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	if(gI_PlayerRank[target] <= 0)
	{
		Shavit_PrintToChat(client, "%T", "Unranked", client, gS_ChatStrings[sMessageVariable2], target, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
		
		return Plugin_Handled;
	}
	
	Shavit_PrintToChat(client, "%T", "Rank", client, gS_ChatStrings[sMessageVariable2], target, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gI_PlayerRank[target], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gI_RankedPlayers, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gI_PlayerPoints[target], gS_ChatStrings[sMessageText]);

	return Plugin_Handled;
}

public Action Command_Top(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	return ShowTopMenu(client);
}

Action ShowTopMenu(int client)
{
	char[] sQuery = new char[192];
	FormatEx(sQuery, 192, "SELECT name, points, auth FROM %susers WHERE points > 0 ORDER BY points DESC LIMIT %d;", gS_MySQLPrefix, gI_TopAmount);

	gH_SQL.Query(SQL_ShowTopMenu_Callback, sQuery, GetClientSerial(client));

	return Plugin_Handled;
}

public void SQL_ShowTopMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error on ShowTopMenu. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Menu m = new Menu(MenuHandler_TopMenu);
	m.SetTitle("%T", "TopMenuTitle", client, gI_TopAmount);

	if(results.RowCount == 0)
	{
		char[] sRankItem = new char[64];
		FormatEx(sRankItem, 64, "%T", "TopNoResults", client);
		m.AddItem("-1", sRankItem);
	}

	else
	{
		int count = 0;

		while(results.FetchRow())
		{
			char[] sName = new char[MAX_NAME_LENGTH];
			results.FetchString(0, sName, MAX_NAME_LENGTH);

			int iRank = ++count;

			char[] sDisplay = new char[64];

			if(gB_MySQL)
			{
				char[] sPoints = new char[16];
				results.FetchString(1, sPoints, 16);

				FormatEx(sDisplay, 64, "%T", "TopMenuClients", client, iRank, sName, sPoints);
			}

			else
			{
				FormatEx(sDisplay, 64, "%T", "TopMenuClients", client, iRank, sName, results.FetchFloat(1));
			}

			char[] sAuthID = new char[32];
			results.FetchString(2, sAuthID, 32);

			m.AddItem(sAuthID, sDisplay);
		}
	}

	m.ExitButton = true;

	m.Display(client, 20);
}

public int MenuHandler_TopMenu(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select && gB_Stats)
	{
		char[] sInfo = new char[32];
		m.GetItem(param2, sInfo, 32);

		if(StringToInt(sInfo) != -1)
		{
			Shavit_OpenStatsMenu(param1, sInfo);
		}
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

// -----------------------
// ONSHAVITFINISH
// -----------------------

public void Shavit_OnFinish_Post(int client, BhopStyle style, float time, int jumps, int strafes, float sync)
{
	
	//TODO : We should also check if beating his PB will give him better WR Rank; 
	
	if ((gF_PlayerPB[client] > time) && (style == Style_Default)) //Since we dont need to update ladderboards if he didnt beat his personalbest
	{
		UpdateLadders();
		
		CreateTimer(1.5,TimerForUpdateClientInfo,client);
	}
}

void UpdateClientInfo(int client)
{
	char[] sAuthID3 = new char[32];
		
	if(GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
	{
		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "SELECT COUNT(*) rank, points FROM %susers WHERE points >= (SELECT points FROM %susers WHERE auth = '%s' LIMIT 1) ORDER BY points DESC LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, sAuthID3);

		DBResultSet results = SQL_Query(gH_SQL, sQuery);
			
		if(results.FetchRow() && results.FetchInt(1) > 0)
		{
			gI_PlayerRank[client] = results.FetchInt(0);
			gI_PlayerPoints[client] = results.FetchInt(1);
		}	
		else
		{
				gI_PlayerRank[client] = 0;
				gI_PlayerPoints[client] = 0;
		}	
		
		Shavit_GetPlayerPB(client, Style_Default, gF_PlayerPB[client]);
				
		delete results;
	}
}

public Action TimerForUpdateClientInfo(Handle timer, any client)
{
	UpdateClientInfo(client);
	return Plugin_Handled;
}

public Action Event_PlayerSpawned(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(IsValidClient(client))
	{
		//SetEntProp(client, Prop_Data, "m_iScore", gI_PlayerPoints[client]);
		SetEntProp(client, Prop_Data, "m_iDeaths", gI_PlayerRank[client]);
	}
	
	return Plugin_Handled;
}

// -----------------------
// UPDATE LADDERS
// -----------------------

void UpdatePointsInUsers()
{
	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "UPDATE %susers u LEFT JOIN (SELECT auth,SUM(points) sumpoints  FROM  %splayertimes GROUP BY auth) p ON u.auth=p.auth SET u.points = p.sumpoints WHERE p.sumpoints > 0;", gS_MySQLPrefix, gS_MySQLPrefix);
	
	SQL_Query(gH_SQL, sQuery);
}


void UpdatePointsInPlayerTimes()
{
	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "SELECT id,map,time,points FROM %splayertimes WHERE style=0 ORDER BY map,time ASC;", gS_MySQLPrefix);
	//PrintToConsole(0, "STEP 1: %s" , sQuery);
	
	DBResultSet results = SQL_Query(gH_SQL, sQuery);

	if(results == null)
	{	
		return;
	}
	
	char[] prevMap = new char[64];
	int rank = 0;

	while(results.FetchRow())
	{
		char[] currentMap = new char[64];
		int points = 0;
		
		
		int id = results.FetchInt(0);
		results.FetchString(1, currentMap, 64);
		int prevPoints = results.FetchInt(3);
		
		if (StrEqual(currentMap, prevMap)) rank++;
		else rank = 1;
		
		if (rank == 1) points = 100;
		else if (rank == 2) points = 70;
		else if (rank == 3) points = 50;
		else if (rank == 4 || rank == 5) points = 30;
		else if (rank > 5 && rank <= 10) points = 20;
		else if (rank > 10 && rank <= 20) points = 10;
		else if (rank > 20 && rank <= 30) points = 8;
		else if (rank > 30 && rank <= 50) points = 5;
		else if (rank > 50 && rank <= 100) points = 3;
		else if (rank > 100 && rank <= 500) points = 2;
		else if (rank > 500) points = 1;
		else points = 0;
		
		if (prevPoints != points)
		{
			//PrintToConsole(0, "%s, rank %i , points %i, id %i ", currentMap, rank, points, id);
			SetPointsInPlayerTimes(points, id);
		}
		strcopy(prevMap, 64, currentMap);
	}
	
	delete results;
}

void SetPointsInPlayerTimes(int points, int id)
{
	if(!gB_MySQL)
	{
		return;
	}

	char[] sQuery = new char[128];
	FormatEx(sQuery, 128, "UPDATE %splayertimes SET points=%i WHERE id=%i;", gS_MySQLPrefix, points, id);

	gH_SQL.Query(SQL_SetPointsInPlayerTimes_Callback, sQuery);
}

public void SQL_SetPointsInPlayerTimes_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! SetPointsInPlayerTimes Failed. Reason: %s", error);

		return;
	}
}

void UpdateRankedPlayers()
{
	char[] sQuery = new char[128];
	FormatEx(sQuery, 128, "SELECT COUNT(*) FROM %susers WHERE points > 0.0 LIMIT 1;", gS_MySQLPrefix);
	
	DBResultSet results = SQL_Query(gH_SQL, sQuery);
	
	if(results == null)
	{
		return;
	}

	if(results.FetchRow())
	{
		gI_RankedPlayers = results.FetchInt(0);
	}
	
	delete results;
}

void UpdateLadders()
{
	CreateTimer(0.5 ,TimerForPointsInPlayerTimes);
	CreateTimer(1.0 ,TimerForPointsInUsers);

	// It shouldn't be done like that, we should do it somewhere else
	// where we could check if player Stats actually updated
	// We need this in shavit-chat
	for (int client = 0; client < MAXPLAYERS+1 ; client++ )
	{
		if (IsValidClient(client))
		{
			Call_StartForward(gH_Forwards_OnRankUpdated);
			Call_PushCell(client);
			Call_Finish();	
		}
	}
}


//------------------
// MISC
//------------------

public Action Command_Recalculate(int client, int args)
{
	//PrintToConsole(client, "client = %i", client);
	UpdatePointsInPlayerTimes();
	CreateTimer(15.0 ,TimerForPointsInUsers);
		
	for (int i = 0; i < MAXPLAYERS+1 ; i++ )
	{
		if (IsValidClient(i))
		{
			Call_StartForward(gH_Forwards_OnRankUpdated);
			Call_PushCell(i);
			Call_Finish();	
		}
	}
	return Plugin_Handled;
}

public Action TimerForPointsInUsers(Handle timer)
{
	UpdatePointsInUsers();
	UpdateRankedPlayers();
	return Plugin_Handled;
}

public Action TimerForPointsInPlayerTimes(Handle timer)
{
	UpdatePointsInPlayerTimes();
	return Plugin_Handled;
}

// SELECT *,(SELECT COUNT(*)+1 from playertimes p2 WHERE p1.map = p2.map AND style=0 and p2.time < p1.time) rank FROM playertimes p1 WHERE style=0 ORDER BY map,time ASC;
