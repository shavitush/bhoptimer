/*
 * shavit's Timer - Core
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

#include <sourcemod>
#include <sdktools>
#include <geoip>

#define USES_STYLE_PROPERTIES
#define USES_STYLE_NAMES
#include <shavit>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma semicolon 1
#pragma dynamic 131072 // let's make stuff faster
#pragma newdecls required // We're at 2015 :D

//#define DEBUG

// game type (CS:S/CS:GO)
ServerGame gSG_Type = Game_Unknown;

// database handle
Database gH_SQL = null;

// forwards
Handle gH_Forwards_Start = null;
Handle gH_Forwards_Stop = null;
Handle gH_Forwards_Finish = null;
Handle gH_Forwards_OnRestart = null;
Handle gH_Forwards_OnPause = null;
Handle gH_Forwards_OnResume = null;

// timer variables
bool gB_TimerEnabled[MAXPLAYERS+1];
float gF_StartTime[MAXPLAYERS+1];
float gF_PauseStartTime[MAXPLAYERS+1];
float gF_PauseTotalTime[MAXPLAYERS+1];
bool gB_ClientPaused[MAXPLAYERS+1];
int gI_Jumps[MAXPLAYERS+1];
BhopStyle gBS_Style[MAXPLAYERS+1];
bool gB_Auto[MAXPLAYERS+1];
bool gB_OnGround[MAXPLAYERS+1];

// late load
bool gB_Late = false;

// zones lateload support
bool gB_Zones = false;

// cvars
ConVar gCV_Autobhop = null;
ConVar gCV_Leftright = null;
ConVar gCV_Restart = null;
ConVar gCV_Pause = null;
ConVar gCV_MySQLPrefix = null;
ConVar gCV_NoStaminaReset = null;
ConVar gCV_AllowTimerWithoutZone = null;

// table prefix
char gS_MySQLPrefix[32];

public Plugin myinfo =
{
	name = "[shavit] Core",
	author = "shavit",
	description = "The core for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// get game type
	CreateNative("Shavit_GetGameType", Native_GetGameType);

	// get database handle
	CreateNative("Shavit_GetDB", Native_GetDB);

	// timer natives
	CreateNative("Shavit_StartTimer", Native_StartTimer);
	CreateNative("Shavit_StopTimer", Native_StopTimer);
	CreateNative("Shavit_FinishMap", Native_FinishMap);
	CreateNative("Shavit_GetTimer", Native_GetTimer);
	CreateNative("Shavit_PauseTimer", Native_PauseTimer);
	CreateNative("Shavit_ResumeTimer", Native_ResumeTimer);
	CreateNative("Shavit_PrintToChat", Native_PrintToChat);

	MarkNativeAsOptional("Shavit_GetGameType");
	MarkNativeAsOptional("Shavit_GetDB");
	MarkNativeAsOptional("Shavit_StartTimer");
	MarkNativeAsOptional("Shavit_StopTimer");
	MarkNativeAsOptional("Shavit_FinishMap");
	MarkNativeAsOptional("Shavit_GetTimer");
	MarkNativeAsOptional("Shavit_PauseTimer");
	MarkNativeAsOptional("Shavit_ResumeTimer");
	MarkNativeAsOptional("Shavit_PrintToChat");

	// prevent errors from shavit-zones
	MarkNativeAsOptional("Shavit_InsideZone");

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_Start = CreateGlobalForward("Shavit_OnStart", ET_Event, Param_Cell);
	gH_Forwards_Stop = CreateGlobalForward("Shavit_OnStop", ET_Event, Param_Cell);
	gH_Forwards_Finish = CreateGlobalForward("Shavit_OnFinish", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnRestart = CreateGlobalForward("Shavit_OnRestart", ET_Event, Param_Cell);
	gH_Forwards_OnPause = CreateGlobalForward("Shavit_OnPause", ET_Event, Param_Cell);
	gH_Forwards_OnResume = CreateGlobalForward("Shavit_OnResume", ET_Event, Param_Cell);

	// game types
	EngineVersion evType = GetEngineVersion();

	if(evType == Engine_CSS)
	{
		gSG_Type = Game_CSS;
	}

	else if(evType == Engine_CSGO)
	{
		gSG_Type = Game_CSGO;
	}

	else
	{
		SetFailState("This plugin was meant to be used in CS:S and CS:GO *only*.");
	}

	// database connections
	SQL_DBConnect();

	// hooks
	HookEvent("player_jump", Player_Jump);
	HookEvent("player_death", Player_Death);
	HookEvent("player_team", Player_Death);
	HookEvent("player_spawn", Player_Death);

	// commands START
	// style
	RegConsoleCmd("sm_style", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_styles", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_diff", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_difficulty", Command_Style, "Choose your bhop style.");

	// timer start
	RegConsoleCmd("sm_s", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_start", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_r", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_restart", Command_StartTimer, "Start your timer.");

	// timer stop
	RegConsoleCmd("sm_stop", Command_StopTimer, "Stop your timer.");

	// timer pause / resume
	RegConsoleCmd("sm_pause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_unpause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_resume", Command_TogglePause, "Toggle pause");

	// autobhop toggle
	RegConsoleCmd("sm_auto", Command_AutoBhop, "Toggle autobhop.");
	RegConsoleCmd("sm_autobhop", Command_AutoBhop, "Toggle autobhop.");
	// commands END

	#if defined DEBUG
	RegConsoleCmd("sm_finishtest", Command_FinishTest);
	#endif

	CreateConVar("shavit_version", SHAVIT_VERSION, "Plugin version.", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	gCV_Autobhop = CreateConVar("shavit_core_autobhop", "1", "Enable autobhop?\nWill be forced to not work if STYLE_AUTOBHOP is not defined for a style!", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gCV_Leftright = CreateConVar("shavit_core_blockleftright", "1", "Block +left/right?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gCV_Restart = CreateConVar("shavit_core_restart", "1", "Allow commands that restart the timer?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gCV_Pause = CreateConVar("shavit_core_pause", "1", "Allow pausing?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gCV_NoStaminaReset = CreateConVar("shavit_core_nostaminareset", "1", "Disables the built-in stamina reset.\nAlso known as 'easybhop'.\nWill be forced to not work if STYLE_EASYBHOP is not defined for a style!", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gCV_AllowTimerWithoutZone = CreateConVar("shavit_core_timernozone", "0", "Allow the timer to start if there's no start zone?", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	gCV_MySQLPrefix = CreateConVar("shavit_core_sqlprefix", "", "MySQL table prefix.\nDO NOT TOUCH OR MODIFY UNLESS YOU KNOW WHAT YOU ARE DOING!!!\nLeave empty unless you have your own prefix for tables.\nRestarting your server is highly recommended after changing this cvar!", FCVAR_PLUGIN);
	gCV_MySQLPrefix.AddChangeHook(OnPrefixChange);

	AutoExecConfig();

	// late
	if(gB_Late)
	{
		OnAdminMenuReady(null);

		for(int i = 1; i <= MaxClients; i++)
		{
			OnClientPutInServer(i);
		}
	}

	gB_Zones = LibraryExists("shavit-zones");
}

public void OnPrefixChange(ConVar cvar, const char[] oldValue, const char[] newValue)
{
	strcopy(gS_MySQLPrefix, 32, newValue);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	Handle hTopMenu = INVALID_HANDLE;

	if(LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		AddToTopMenu(hTopMenu, "Timer Commands", TopMenuObject_Category, CategoryHandler, INVALID_TOPMENUOBJECT);
	}
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		strcopy(buffer, maxlength, "Timer Commands:");
	}

	else if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "Timer Commands");
	}
}

public void OnMapStart()
{
	// cvar forcing
	ConVar cvBhopping = FindConVar("sv_enablebunnyhopping");
	SetConVarBool(cvBhopping, true);

	ConVar cvAA = FindConVar("sv_airaccelerate");
	SetConVarInt(cvAA, 2000);
}

public Action Command_StartTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_Restart.BoolValue)
	{
		if(args != -1)
		{
			char[] sCommand = new char[16];
			GetCmdArg(0, sCommand, 16);

			Shavit_PrintToChat(client, "The command (\x03%s\x01) is disabled.", sCommand);
		}

		return Plugin_Handled;
	}

	if(gCV_AllowTimerWithoutZone || (gB_Zones && Shavit_ZoneExists(Zone_Start)))
	{
		Call_StartForward(gH_Forwards_OnRestart);
		Call_PushCell(client);
		Call_Finish();

		StartTimer(client);
	}

	else
	{
		Shavit_PrintToChat(client, "Your timer will not start as a start zone for the map is not defined.");
	}

	return Plugin_Handled;
}

public Action Command_StopTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	StopTimer(client);

	return Plugin_Handled;
}

public Action Command_TogglePause(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_Pause.BoolValue)
	{
		char[] sCommand = new char[16];
		GetCmdArg(0, sCommand, 16);

		Shavit_PrintToChat(client, "The command (\x03%s\x01) is disabled.", sCommand);

		return Plugin_Handled;
	}

	if(!(GetEntityFlags(client) & FL_ONGROUND))
	{
		Shavit_PrintToChat(client, "You are not allowed to pause when not on ground.");

		return Plugin_Handled;
	}

	if(gB_ClientPaused[client])
	{
		ResumeTimer(client);
	}

	else
	{
		PauseTimer(client);
	}

	return Plugin_Handled;
}

#if defined DEBUG
public Action Command_FinishTest(int client, int args)
{
	Shavit_FinishMap(client);

	return Plugin_Handled;
}
#endif

public Action Command_AutoBhop(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Auto[client] = !gB_Auto[client];

	Shavit_PrintToChat(client, "Autobhop %s\x01.", gB_Auto[client]? "\x04enabled":"\x02disabled");

	return Plugin_Handled;
}

public Action Command_Style(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu m = new Menu(StyleMenu_Handler);
	m.SetTitle("Choose a style:");

	for(int i = 0; i < sizeof(gS_BhopStyles); i++)
	{
		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		m.AddItem(sInfo, gS_BhopStyles[i]);
	}

	// should NEVER happen
	if(m.ItemCount == 0)
	{
		m.AddItem("-1", "Nothing");
	}

	m.ExitButton = true;

	m.Display(client, 20);

	return Plugin_Handled;
}

public int StyleMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		m.GetItem(param2, info, 16);

		BhopStyle style = view_as<BhopStyle>(StringToInt(info));

		ChangeClientStyle(param1, style);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void ChangeClientStyle(int client, BhopStyle style)
{
	if(!IsValidClient(client))
	{
		return;
	}

	gBS_Style[client] = style;

	Shavit_PrintToChat(client, "You have selected to play \x03%s\x01.", gS_BhopStyles[view_as<int>(style)]);

	StopTimer(client);

	if(gCV_AllowTimerWithoutZone.BoolValue || (gB_Zones && Shavit_ZoneExists(Zone_Start)))
	{
		Command_StartTimer(client, -1);
	}
}

public void Player_Jump(Handle event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	if(gB_TimerEnabled[client])
	{
		gI_Jumps[client]++;
	}

	if(gI_StyleProperties[gBS_Style[client]] & STYLE_EASYBHOP && gCV_NoStaminaReset.BoolValue)
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}
}

public void Player_Death(Handle event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	ResumeTimer(client);
	StopTimer(client);
}

public int Native_GetGameType(Handle handler, int numParams)
{
	return view_as<int>(gSG_Type);
}

public int Native_GetDB(Handle handler, int numParams)
{
	SetNativeCellRef(1, gH_SQL);
}

// I can't return booleans :/
public int Native_GetTimer(Handle handler, int numParams)
{
	// 1 - client
	int client = GetNativeCell(1);

	// 2 - time
	float time = CalculateTime(client);
	SetNativeCellRef(2, time);

	// 3 - jumps
	SetNativeCellRef(3, gI_Jumps[client]);

	// 4 - style
	SetNativeCellRef(4, gBS_Style[client]);

	// 5 - enabled?
	SetNativeCellRef(5, gB_TimerEnabled[client]);
}

public int Native_StartTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(!IsFakeClient(client))
	{
		StartTimer(client);

		Call_StartForward(gH_Forwards_Start);
		Call_PushCell(client);
		Call_Finish();
	}
}

public int Native_StopTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	StopTimer(client);

	Call_StartForward(gH_Forwards_Stop);
	Call_PushCell(client);
	Call_Finish();
}

public int Native_FinishMap(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	Call_StartForward(gH_Forwards_Finish);
	Call_PushCell(client);
	Call_PushCell(view_as<int>(gBS_Style[client]));
	Call_PushCell(CalculateTime(client));
	Call_PushCell(gI_Jumps[client]);
	Call_Finish();

	StopTimer(client);
}

public int Native_PauseTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	PauseTimer(client);
}

public int Native_ResumeTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	ResumeTimer(client);
}

public int Native_PrintToChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	int written = 0; // useless?

	char[] buffer = new char[255];
	FormatNativeString(0, 2, 3, 255, written, buffer);

	return PrintToChat(client, "%s%s %s", gSG_Type == Game_CSS? "":" ", PREFIX, buffer);
}

public void StartTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gB_TimerEnabled[client] = true;
	gI_Jumps[client] = 0;
	gF_StartTime[client] = GetEngineTime();
	gF_PauseTotalTime[client] = 0.0;
	gB_ClientPaused[client] = false;
}

public void StopTimer(int client)
{
	if(!IsValidClient(client))
	{
		return;
	}

	gB_TimerEnabled[client] = false;
	gI_Jumps[client] = 0;
	gF_StartTime[client] = 0.0;
	gF_PauseTotalTime[client] = 0.0;
	gB_ClientPaused[client] = false;
}

public void PauseTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gF_PauseStartTime[client] = GetEngineTime();
	gB_ClientPaused[client] = true;

	Call_StartForward(gH_Forwards_OnPause);
	Call_PushCell(client);
	Call_Finish();
}

public void ResumeTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gF_PauseTotalTime[client] += GetEngineTime() - gF_PauseStartTime[client];
	gB_ClientPaused[client] = false;

	Call_StartForward(gH_Forwards_OnResume);
	Call_PushCell(client);
	Call_Finish();
}

public float CalculateTime(int client)
{
	if(!gB_ClientPaused[client])
	{
		return GetEngineTime() - gF_StartTime[client] - gF_PauseTotalTime[client];
	}

	else
	{
		return gF_PauseStartTime[client] - gF_StartTime[client] - gF_PauseTotalTime[client];
	}
}

public void OnClientDisconnect(int client)
{
	StopTimer(client);
}

public void OnClientPutInServer(int client)
{
	gB_Auto[client] = true;

	StopTimer(client);

	gBS_Style[client] = Style_Forwards;

	if(!IsValidClient(client) || IsFakeClient(client) || gH_SQL == null)
	{
		return;
	}

	// SteamID3 is cool, 2015 B O Y S
	char[] sAuthID3 = new char[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32);

	char[] sName = new char[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);

	int iLength = ((strlen(sName) * 2) + 1);
	char[] sEscapedName = new char[iLength]; // dynamic arrays! I love you, SourcePawn 1.7!
	SQL_EscapeString(gH_SQL, sName, sEscapedName, iLength);

	char[] sIP = new char[32];
	GetClientIP(client, sIP, 32);

	char[] sCountry = new char[45];
	GeoipCountry(sIP, sCountry, 45);

	if(StrEqual(sCountry, ""))
	{
		strcopy(sCountry, 45, "Local Area Network");
	}

	// too lazy to calculate if it can go over 256 so let's not take risks and use 512, because #pragma dynamic <3
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "REPLACE INTO %susers (auth, name, country, ip) VALUES ('%s', '%s', '%s', '%s');", gS_MySQLPrefix, sAuthID3, sEscapedName, sCountry, sIP);

	gH_SQL.Query(SQL_InsertUser_Callback, sQuery, GetClientSerial(client));
}

public void SQL_InsertUser_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		int client = GetClientFromSerial(data);

		if(!client)
		{
			LogError("Timer error! Failed to insert a disconnected player's data to the table. Reason: %s", error);
		}

		else
		{
			LogError("Timer error! Failed to insert \"%N\"'s data to the table. Reason: %s", client, error);
		}

		return;
	}
}

public void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		delete gH_SQL;
	}

	if(SQL_CheckConfig("shavit"))
	{
		char[] sError = new char[255];

		if(!(gH_SQL = SQL_Connect("shavit", true, sError, 255)))
		{
			SetFailState("Timer startup failed. Reason: %s", sError);
		}

		// let's not mess with shit and make it non-English characters work properly before we do any stupid crap rite?
		SQL_LockDatabase(gH_SQL);
		SQL_FastQuery(gH_SQL, "SET NAMES 'utf8';");
		SQL_UnlockDatabase(gH_SQL);

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%susers` (`auth` VARCHAR(32) NOT NULL, `name` VARCHAR(32), `country` VARCHAR(45), `ip` VARCHAR(32), PRIMARY KEY (`auth`));", gS_MySQLPrefix);

		// CREATE TABLE IF NOT EXISTS
		gH_SQL.Query(SQL_CreateTable_Callback, sQuery);
	}

	else
	{
		SetFailState("Timer startup failed. Reason: %s", "\"shavit\" is not a specified entry in databases.cfg.");
	}
}

public void SQL_CreateTable_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer error! Users' data table creation failed. Reason: %s", error);

		return;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3])
{
	if(!IsValidClient(client, true))
	{
		return Plugin_Continue;
	}

	bool bOnLadder = (GetEntityMoveType(client) == MOVETYPE_LADDER);

	if(gCV_Leftright.BoolValue && gB_TimerEnabled[client] && (!gB_Zones || !Shavit_InsideZone(client, Zone_Start) && (buttons & IN_LEFT || buttons & IN_RIGHT)))
	{
		StopTimer(client);
		Shavit_PrintToChat(client, "I've stopped your timer for using +left/+right. No cheating!");
	}

	bool bEdit = false;

	// key blocking
	if(!Shavit_InsideZone(client, Zone_Freestyle) && !bOnLadder)
	{
		if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_W && (vel[0] > 0 || buttons & IN_FORWARD))
		{
			bEdit = true;
			vel[0] = 0.0;
			buttons &= ~IN_FORWARD;
		}

		if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_A && (vel[1] > 0 || buttons & IN_MOVELEFT))
		{
			bEdit = true;
			vel[1] = 0.0;
			buttons &= ~IN_MOVELEFT;
		}

		if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_S && (vel[0] < 0 || buttons & IN_BACK))
		{
			bEdit = true;
			vel[0] = 0.0;
			buttons &= ~IN_BACK;
		}

		if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_D && (vel[1] > 0 || buttons & IN_MOVERIGHT))
		{
			bEdit = true;
			vel[1] = 0.0;
			buttons &= ~IN_MOVERIGHT;
		}
	}

	bool bOnGround = GetEntityFlags(client) & FL_ONGROUND || bOnLadder;

	// autobhop
	if(gI_StyleProperties[gBS_Style[client]] & STYLE_AUTOBHOP && gCV_Autobhop.BoolValue && gB_Auto[client] && buttons & IN_JUMP && !bOnGround && GetEntProp(client, Prop_Send, "m_nWaterLevel") <= 1)
	{
		buttons &= ~IN_JUMP;
	}

	// velocity limit
	if(bOnGround && gI_StyleProperties[gBS_Style[client]] & STYLE_VEL_LIMIT && gF_VelocityLimit[gBS_Style[client]] != VELOCITY_UNLIMITED && (!gB_Zones || !Shavit_InsideZone(client, Zone_NoVelLimit)))
	{
		gB_OnGround[client] = true;

		float fSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
		float fScale = gF_VelocityLimit[gBS_Style[client]] / fSpeed_New;

		if(fScale < 1.0)
		{
			ScaleVector(fSpeed, fScale);

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
		}
	}

	else
	{
		gB_OnGround[client] = false;
	}

	if(gB_ClientPaused[client])
	{
		bEdit = true;

		vel = view_as<float>({0.0, 0.0, 0.0});
	}

	return bEdit? Plugin_Changed:Plugin_Continue;
}
