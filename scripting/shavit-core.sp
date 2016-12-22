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
#include <sdkhooks>
#include <sdktools>
#include <geoip>
#include <clientprefs>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#define USES_CHAT_COLORS
#include <shavit>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

// #define DEBUG

// game type (CS:S/CS:GO)
ServerGame gSG_Type = Game_Unknown; // deperecated and here for backwards compatibility
EngineVersion gEV_Type = Engine_Unknown;

// database handle
Database gH_SQL = null;
bool gB_MySQL = false;

// forwards
Handle gH_Forwards_Start = null;
Handle gH_Forwards_Stop = null;
Handle gH_Forwards_Finish = null;
Handle gH_Forwards_OnRestart = null;
Handle gH_Forwards_OnEnd = null;
Handle gH_Forwards_OnPause = null;
Handle gH_Forwards_OnResume = null;
Handle gH_Forwards_OnStyleChanged = null;
Handle gH_Forwards_OnStyleConfigLoaded = null;
Handle gH_Forwards_OnDatabaseLoaded = null;
Handle gH_Forwards_OnChatConfigLoaded = null;

// timer variables
bool gB_TimerEnabled[MAXPLAYERS+1];
float gF_StartTime[MAXPLAYERS+1];
float gF_PauseStartTime[MAXPLAYERS+1];
float gF_PauseTotalTime[MAXPLAYERS+1];
bool gB_ClientPaused[MAXPLAYERS+1];
int gI_Jumps[MAXPLAYERS+1];
BhopStyle gBS_Style[MAXPLAYERS+1];
bool gB_Auto[MAXPLAYERS+1];
int gI_ButtonCache[MAXPLAYERS+1];
int gI_Strafes[MAXPLAYERS+1];
float gF_AngleCache[MAXPLAYERS+1];
int gI_TotalMeasures[MAXPLAYERS+1];
int gI_GoodGains[MAXPLAYERS+1];
bool gB_DoubleSteps[MAXPLAYERS+1];
float gF_StrafeWarning[MAXPLAYERS+1];

float gF_HSW_Requirement = 0.0;
StringMap gSM_StyleCommands = null;

// cookies
Handle gH_StyleCookie = null;
Handle gH_AutoBhopCookie = null;

// late load
bool gB_Late = false;

// modules
bool gB_Zones = false;

// cvars
ConVar gCV_Autobhop = null;
ConVar gCV_LeftRight = null;
ConVar gCV_Restart = null;
ConVar gCV_Pause = null;
ConVar gCV_NoStaminaReset = null;
ConVar gCV_AllowTimerWithoutZone = null;
ConVar gCV_BlockPreJump = null;
ConVar gCV_NoZAxisSpeed = null;

// cached cvars
bool gB_Autobhop = true;
bool gB_LeftRight = true;
bool gB_Restart = true;
bool gB_Pause = true;
bool gB_NoStaminaReset = true;
bool gB_AllowTimerWithoutZone = false;
bool gB_BlockPreJump = true;
bool gB_NoZAxisSpeed = true;

// table prefix
char gS_MySQLPrefix[32];

// server side
ConVar sv_airaccelerate = null;
ConVar sv_autobunnyhopping = null;

// timer settings
bool gB_Registered = false;
int gI_Styles = 0;
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

// chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

public Plugin myinfo =
{
	name = "[shavit] Core",
	author = "shavit",
	description = "The core for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
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
	CreateNative("Shavit_GetClientTime", Native_GetClientTime);
	CreateNative("Shavit_GetClientJumps", Native_GetClientJumps);
	CreateNative("Shavit_GetBhopStyle", Native_GetBhopStyle);
	CreateNative("Shavit_GetTimerStatus", Native_GetTimerStatus);
	CreateNative("Shavit_PauseTimer", Native_PauseTimer);
	CreateNative("Shavit_ResumeTimer", Native_ResumeTimer);
	CreateNative("Shavit_PrintToChat", Native_PrintToChat);
	CreateNative("Shavit_RestartTimer", Native_RestartTimer);
	CreateNative("Shavit_GetStrafeCount", Native_GetStrafeCount);
	CreateNative("Shavit_GetSync", Native_GetSync);
	CreateNative("Shavit_GetStyleCount", Native_GetStyleCount);
	CreateNative("Shavit_GetStyleSettings", Native_GetStyleSettings);
	CreateNative("Shavit_GetStyleStrings", Native_GetStyleStrings);
	CreateNative("Shavit_GetChatStrings", Native_GetChatStrings);

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
	gH_Forwards_Finish = CreateGlobalForward("Shavit_OnFinish", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnRestart = CreateGlobalForward("Shavit_OnRestart", ET_Event, Param_Cell);
	gH_Forwards_OnEnd = CreateGlobalForward("Shavit_OnEnd", ET_Event, Param_Cell);
	gH_Forwards_OnPause = CreateGlobalForward("Shavit_OnPause", ET_Event, Param_Cell);
	gH_Forwards_OnResume = CreateGlobalForward("Shavit_OnResume", ET_Event, Param_Cell);
	gH_Forwards_OnStyleChanged = CreateGlobalForward("Shavit_OnStyleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnStyleConfigLoaded = CreateGlobalForward("Shavit_OnStyleConfigLoaded", ET_Event, Param_Cell);
	gH_Forwards_OnDatabaseLoaded = CreateGlobalForward("Shavit_OnDatabaseLoaded", ET_Event, Param_Cell);
	gH_Forwards_OnChatConfigLoaded = CreateGlobalForward("Shavit_OnChatConfigLoaded", ET_Event);

	LoadTranslations("shavit-core.phrases");

	// game types
	gEV_Type = GetEngineVersion();

	if(gEV_Type == Engine_CSS)
	{
		gSG_Type = Game_CSS;
		gF_HSW_Requirement = 399.00;
	}

	else if(gEV_Type == Engine_CSGO)
	{
		gSG_Type = Game_CSGO;
		gF_HSW_Requirement = 449.00;

		sv_autobunnyhopping = FindConVar("sv_autobunnyhopping");
		sv_autobunnyhopping.BoolValue = false;
	}

	else
	{
		SetFailState("This plugin was meant to be used in CS:S and CS:GO *only*.");
	}

	// database connections
	SQL_SetPrefix();
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
	gH_StyleCookie = RegClientCookie("shavit_style", "Style cookie", CookieAccess_Protected);

	// timer start
	RegConsoleCmd("sm_s", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_start", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_r", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_restart", Command_StartTimer, "Start your timer.");

	// teleport to end
	RegConsoleCmd("sm_end", Command_TeleportEnd, "Teleport to endzone.");

	// timer stop
	RegConsoleCmd("sm_stop", Command_StopTimer, "Stop your timer.");

	// timer pause / resume
	RegConsoleCmd("sm_pause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_unpause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_resume", Command_TogglePause, "Toggle pause");

	// autobhop toggle
	RegConsoleCmd("sm_auto", Command_AutoBhop, "Toggle autobhop.");
	RegConsoleCmd("sm_autobhop", Command_AutoBhop, "Toggle autobhop.");
	gH_AutoBhopCookie = RegClientCookie("shavit_autobhop", "Autobhop cookie", CookieAccess_Protected);

	// doublestep fixer
	AddCommandListener(Command_DoubleStep, "+ds");
	AddCommandListener(Command_DoubleStep, "-ds");

	// style commands
	gSM_StyleCommands = new StringMap();
	// commands END

	#if defined DEBUG
	RegConsoleCmd("sm_finishtest", Command_FinishTest);
	#endif

	CreateConVar("shavit_version", SHAVIT_VERSION, "Plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);

	gCV_Autobhop = CreateConVar("shavit_core_autobhop", "1", "Enable autobhop?\nWill be forced to not work if STYLE_AUTOBHOP is not defined for a style!", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gCV_LeftRight = CreateConVar("shavit_core_blockleftright", "1", "Block +left/right?", 0, true, 0.0, true, 1.0);
	gCV_Restart = CreateConVar("shavit_core_restart", "1", "Allow commands that restart the timer?", 0, true, 0.0, true, 1.0);
	gCV_Pause = CreateConVar("shavit_core_pause", "1", "Allow pausing?", 0, true, 0.0, true, 1.0);
	gCV_NoStaminaReset = CreateConVar("shavit_core_nostaminareset", "1", "Disables the built-in stamina reset.\nAlso known as 'easybhop'.\nWill be forced to not work if STYLE_EASYBHOP is not defined for a style!", 0, true, 0.0, true, 1.0);
	gCV_AllowTimerWithoutZone = CreateConVar("shavit_core_timernozone", "0", "Allow the timer to start if there's no start zone?", 0, true, 0.0, true, 1.0);
	gCV_BlockPreJump = CreateConVar("shavit_core_blockprejump", "1", "Prevents jumping in the start zone.", 0, true, 0.0, true, 1.0);
	gCV_NoZAxisSpeed = CreateConVar("shavit_core_nozaxisspeed", "1", "Don't start timer if vertical speed exists (btimes style).", 0, true, 0.0, true, 1.0);

	gCV_Autobhop.AddChangeHook(OnConVarChanged);
	gCV_LeftRight.AddChangeHook(OnConVarChanged);
	gCV_Restart.AddChangeHook(OnConVarChanged);
	gCV_Pause.AddChangeHook(OnConVarChanged);
	gCV_NoStaminaReset.AddChangeHook(OnConVarChanged);
	gCV_AllowTimerWithoutZone.AddChangeHook(OnConVarChanged);
	gCV_BlockPreJump.AddChangeHook(OnConVarChanged);
	gCV_NoZAxisSpeed.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	sv_airaccelerate = FindConVar("sv_airaccelerate");
	sv_airaccelerate.Flags &= ~FCVAR_NOTIFY;

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

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gB_Autobhop = gCV_Autobhop.BoolValue;
	gB_LeftRight = gCV_LeftRight.BoolValue;
	gB_Restart = gCV_Restart.BoolValue;
	gB_Pause = gCV_Pause.BoolValue;
	gB_NoStaminaReset = gCV_NoStaminaReset.BoolValue;
	gB_AllowTimerWithoutZone = gCV_AllowTimerWithoutZone.BoolValue;
	gB_BlockPreJump = gCV_BlockPreJump.BoolValue;
	gB_NoZAxisSpeed = gCV_NoZAxisSpeed.BoolValue;
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
	// styles
	if(!LoadStyles())
	{
		SetFailState("Could not load the styles configuration file. Make sure it exists (addons/sourcemod/configs/shavit-styles.cfg) and follows the proper syntax!");
	}

	else
	{
		Call_StartForward(gH_Forwards_OnStyleConfigLoaded);
		Call_PushCell(gI_Styles);
		Call_Finish();
	}

	// messages
	if(!LoadMessages())
	{
		SetFailState("Could not load the chat messages configuration file. Make sure it exists (addons/sourcemod/configs/shavit-messages.cfg) and follows the proper syntax!");
	}

	else
	{
		Call_StartForward(gH_Forwards_OnChatConfigLoaded);
		Call_Finish();
	}

	// cvar forcing
	FindConVar("sv_enablebunnyhopping").BoolValue = true;
}

public Action Command_StartTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gB_Restart)
	{
		if(args != -1)
		{
			char[] sCommand = new char[16];
			GetCmdArg(0, sCommand, 16);

			Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings[sMessageVariable], sCommand, gS_ChatStrings[sMessageText]);
		}

		return Plugin_Handled;
	}

	if(gB_AllowTimerWithoutZone || (gB_Zones && Shavit_ZoneExists(Zone_Start)))
	{
		Call_StartForward(gH_Forwards_OnRestart);
		Call_PushCell(client);
		Call_Finish();

		StartTimer(client);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "StartZoneUndefined", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
	}

	return Plugin_Handled;
}

public Action Command_TeleportEnd(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(gB_Zones && Shavit_ZoneExists(Zone_End))
	{
		Shavit_StopTimer(client);
		
		Call_StartForward(gH_Forwards_OnEnd);
		Call_PushCell(client);
		Call_Finish();
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "EndZoneUndefined", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
	}

	return Plugin_Handled;
}

public Action Command_StopTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Shavit_StopTimer(client);

	return Plugin_Handled;
}

public Action Command_TogglePause(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(Shavit_InsideZone(client, Zone_Start))
	{
		Shavit_PrintToChat(client, "%T", "PauseStartZone", client, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if(!gB_Pause)
	{
		char[] sCommand = new char[16];
		GetCmdArg(0, sCommand, 16);

		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings[sMessageVariable], sCommand, gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if((GetEntityFlags(client) & FL_ONGROUND) == 0)
	{
		Shavit_PrintToChat(client, "%T", "PauseNotOnGround", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if(gB_ClientPaused[client])
	{
		ResumeTimer(client);
		Shavit_PrintToChat(client, "%T", "MessageUnpause", client, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
	}

	else
	{
		PauseTimer(client);
		Shavit_PrintToChat(client, "%T", "MessagePause", client, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
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

	if(gB_Auto[client])
	{
		Shavit_PrintToChat(client, "%T", "AutobhopEnabled", client, gS_ChatStrings[sMessageVariable2], gS_ChatStrings[sMessageText]);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "AutobhopDisabled", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
	}

	char[] sAutoBhop = new char[4];
	IntToString(view_as<int>(gB_Auto[client]), sAutoBhop, 4);

	SetClientCookie(client, gH_AutoBhopCookie, sAutoBhop);

	return Plugin_Handled;
}

public Action Command_DoubleStep(int client, const char[] command, int args)
{
	gB_DoubleSteps[client] = (command[0] == '+');

	return Plugin_Handled;
}

public Action Command_Style(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu m = new Menu(StyleMenu_Handler);
	m.SetTitle("%T", "StyleMenuTitle", client);

	for(int i = 0; i < gI_Styles; i++)
	{
		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		if(gA_StyleSettings[i][bUnranked])
		{
			char[] sDisplay = new char[64];
			FormatEx(sDisplay, 64, "%T %s", "StyleUnranked", client, gS_StyleStrings[i][sStyleName]);
			m.AddItem(sInfo, sDisplay);
		}

		else
		{
			m.AddItem(sInfo, gS_StyleStrings[i][sStyleName]);
		}
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

void ChangeClientStyle(int client, BhopStyle style)
{
	if(!IsValidClient(client))
	{
		return;
	}

	Call_StartForward(gH_Forwards_OnStyleChanged);
	Call_PushCell(client);
	Call_PushCell(gBS_Style[client]);
	Call_PushCell(style);
	Call_Finish();

	gBS_Style[client] = style;
	UpdateAutoBhop(client);

	Shavit_PrintToChat(client, "%T", "StyleSelection", client, gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText]);

	if(gA_StyleSettings[style][bUnranked])
	{
		Shavit_PrintToChat(client, "%T", "UnrankedWarning", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
	}

	StopTimer(client);

	if(gB_AllowTimerWithoutZone || (gB_Zones && Shavit_ZoneExists(Zone_Start)))
	{
		Call_StartForward(gH_Forwards_OnRestart);
		Call_PushCell(client);
		Call_Finish();
	}

	char[] sStyle = new char[4];
	IntToString(view_as<int>(style), sStyle, 4);

	SetClientCookie(client, gH_StyleCookie, sStyle);
}

public void Player_Jump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(gB_TimerEnabled[client])
	{
		gI_Jumps[client]++;
	}

	if(gB_NoStaminaReset && gA_StyleSettings[gBS_Style[client]][bEasybhop])
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}

	if(view_as<float>(gA_StyleSettings[gBS_Style[client]][fGravityMultiplier]) != 1.0)
	{
		SetEntityGravity(client, view_as<float>(gA_StyleSettings[gBS_Style[client]][fGravityMultiplier]));
	}

	if(view_as<float>(gA_StyleSettings[gBS_Style[client]][fSpeedMultiplier]) != 1.0)
	{
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", view_as<float>(gA_StyleSettings[gBS_Style[client]][fSpeedMultiplier]));
	}
}

public void Player_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

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

public int Native_GetTimer(Handle handler, int numParams)
{
	// 1 - client
	int client = GetNativeCell(1);

	// 2 - time
	float time = CalculateTime(client);
	SetNativeCellRef(2, time);
	SetNativeCellRef(3, gI_Jumps[client]);
	SetNativeCellRef(4, gBS_Style[client]);
	SetNativeCellRef(5, gB_TimerEnabled[client]);
}

public int Native_GetClientTime(Handle handler, int numParams)
{
	// 1 - client
	int client = GetNativeCell(1);

	// 2 - time
	return view_as<int>(CalculateTime(client));
}

public int Native_GetClientJumps(Handle handler, int numParams)
{
	return gI_Jumps[GetNativeCell(1)];
}

public int Native_GetBhopStyle(Handle handler, int numParams)
{
	return view_as<int>(gBS_Style[GetNativeCell(1)]);
}

public int Native_GetTimerStatus(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(!gB_TimerEnabled[client])
	{
		return view_as<int>(Timer_Stopped);
	}

	else if(gB_ClientPaused[client])
	{
		return view_as<int>(Timer_Paused);
	}

	return view_as<int>(Timer_Running);
}

public int Native_StartTimer(Handle handler, int numParams)
{
	StartTimer(GetNativeCell(1));
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
	Call_PushCell(gI_Strafes[client]);
	Call_PushCell((gA_StyleSettings[gBS_Style[client]][bSync])? (gI_GoodGains[client] == 0)? 0.0:(gI_GoodGains[client] / float(gI_TotalMeasures[client]) * 100.0):-1.0);
	Call_Finish();

	StopTimer(client);
}

public int Native_PauseTimer(Handle handler, int numParams)
{
	PauseTimer(GetNativeCell(1));
}

public int Native_ResumeTimer(Handle handler, int numParams)
{
	ResumeTimer(GetNativeCell(1));
}

public int Native_PrintToChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	static int written = 0; // useless?

	char[] buffer = new char[300];
	FormatNativeString(0, 2, 3, 300, written, buffer);
	Format(buffer, 300, "%s %s%s", gS_ChatStrings[sMessagePrefix], gS_ChatStrings[sMessageText], buffer);

	if(gEV_Type == Engine_CSS)
	{
		Handle hSayText2 = StartMessageOne("SayText2", client);

		if(hSayText2 != null)
		{
			BfWriteByte(hSayText2, client);
			BfWriteByte(hSayText2, true);
			BfWriteString(hSayText2, buffer);
		}

		EndMessage();
	}

	else
	{
		PrintToChat(client, " %s", buffer);
	}

	return;
}

public int Native_RestartTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	Call_StartForward(gH_Forwards_OnRestart);
	Call_PushCell(client);
	Call_Finish();

	StartTimer(client);

	return;
}

public int Native_GetStrafeCount(Handle handler, int numParams)
{
	return gI_Strafes[GetNativeCell(1)];
}

public int Native_GetSync(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>((gA_StyleSettings[gBS_Style[client]][bSync])? (gI_GoodGains[client] == 0)? 0.0:(gI_GoodGains[client] / float(gI_TotalMeasures[client]) * 100.0):-1.0);
}

public int Native_GetStyleCount(Handle handler, int numParams)
{
	return (gI_Styles > 0)? gI_Styles:-1;
}

public int Native_GetStyleSettings(Handle handler, int numParams)
{
	return SetNativeArray(2, gA_StyleSettings[GetNativeCell(1)], STYLESETTINGS_SIZE);
}

public int Native_GetStyleStrings(Handle handler, int numParams)
{
	return SetNativeString(3, gS_StyleStrings[GetNativeCell(1)][GetNativeCell(2)], GetNativeCell(4));
}

public int Native_GetChatStrings(Handle handler, int numParams)
{
	return SetNativeString(2, gS_ChatStrings[GetNativeCell(1)], GetNativeCell(3));
}

void StartTimer(int client)
{
	if(!IsValidClient(client, true) || GetClientTeam(client) < 2 || IsFakeClient(client))
	{
		return;
	}

	float fSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

	if(!gB_NoZAxisSpeed || gA_StyleSettings[gBS_Style[client]][bPrespeed] || fSpeed[2] == 0.0 || SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)) <= 280.0)
	{
		gF_StartTime[client] = GetEngineTime();
		gB_TimerEnabled[client] = true;
		gI_Strafes[client] = 0;
		gI_Jumps[client] = 0;
		gI_TotalMeasures[client] = 0;
		gI_GoodGains[client] = 0;

		Call_StartForward(gH_Forwards_Start);
		Call_PushCell(client);
		Call_Finish();
	}

	gF_PauseTotalTime[client] = 0.0;
	gB_ClientPaused[client] = false;

	SetEntityGravity(client, gA_StyleSettings[gBS_Style[client]][fGravityMultiplier]);
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", gA_StyleSettings[gBS_Style[client]][fSpeedMultiplier]);
}

void StopTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gB_TimerEnabled[client] = false;
	gI_Jumps[client] = 0;
	gF_StartTime[client] = 0.0;
	gF_PauseTotalTime[client] = 0.0;
	gB_ClientPaused[client] = false;
	gI_Strafes[client] = 0;
	gI_TotalMeasures[client] = 0;
	gI_GoodGains[client] = 0;
}

void PauseTimer(int client)
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

void ResumeTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gF_PauseTotalTime[client] += (GetEngineTime() - gF_PauseStartTime[client]);
	gB_ClientPaused[client] = false;

	Call_StartForward(gH_Forwards_OnResume);
	Call_PushCell(client);
	Call_Finish();
}

float CalculateTime(int client)
{
	float time = 0.0;

	if(!gB_ClientPaused[client])
	{
		time = (GetEngineTime() - gF_StartTime[client] - gF_PauseTotalTime[client]);
	}

	else
	{
		time = (gF_PauseStartTime[client] - gF_StartTime[client] - gF_PauseTotalTime[client]);
	}

	if(gA_StyleSettings[gBS_Style[client]][bHalftime])
	{
		time /= 2.0;
	}

	return time;
}

public void OnClientDisconnect(int client)
{
	StopTimer(client);
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	char[] sCookie = new char[4];
	GetClientCookie(client, gH_AutoBhopCookie, sCookie, 4);
	gB_Auto[client] = (strlen(sCookie) > 0)? view_as<bool>(StringToInt(sCookie)):true;

	GetClientCookie(client, gH_StyleCookie, sCookie, 4);
	gBS_Style[client] = view_as<BhopStyle>(StringToInt(sCookie));
	UpdateAutoBhop(client);
}

public void OnClientPutInServer(int client)
{
	StopTimer(client);

	if(IsFakeClient(client))
	{
		return;
	}

	gB_Auto[client] = true;
	gB_DoubleSteps[client] = false;
	gF_StrafeWarning[client] = 0.0;
	gBS_Style[client] = view_as<BhopStyle>(0);
	UpdateAutoBhop(client);

	if(AreClientCookiesCached(client))
	{
		OnClientCookiesCached(client);
	}

	if(gH_SQL == null)
	{
		return;
	}

	SDKHook(client, SDKHook_PreThink, PreThink);

	char[] sAuthID3 = new char[32];

	if(!GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
	{
		KickClient(client, "%T", "VerificationFailed", client);

		return;
	}

	char[] sName = new char[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);

	int iLength = ((strlen(sName) * 2) + 1);
	char[] sEscapedName = new char[iLength]; // dynamic arrays! I love you, SourcePawn 1.7!
	gH_SQL.Escape(sName, sEscapedName, iLength);

	char[] sIP = new char[64];
	GetClientIP(client, sIP, 64);

	char[] sCountry = new char[128];

	if(!GeoipCountry(sIP, sCountry, 128))
	{
		strcopy(sCountry, 128, "Local Area Network");
	}

	int points = 0;
	if (LibraryExists("shavit-rankings"))
	{
		points = Shavit_GetPoints(client);
	}
	
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "REPLACE INTO %susers (auth, name, country, ip, lastlogin, points) VALUES ('%s', '%s', '%s', '%s', %d , %i);", gS_MySQLPrefix, sAuthID3, sEscapedName, sCountry, sIP, GetTime(), points);

	gH_SQL.Query(SQL_InsertUser_Callback, sQuery, GetClientSerial(client));
}

public void SQL_InsertUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		int client = GetClientFromSerial(data);

		if(client == 0)
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

bool LoadStyles()
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-styles.cfg");

	Dynamic dStylesConfig = Dynamic();

	if(!dStylesConfig.ReadKeyValues(sPath))
	{
		dStylesConfig.Dispose();

		return false;
	}

	gI_Styles = dStylesConfig.MemberCount;

	for(int i = 0; i < gI_Styles; i++)
	{
		Dynamic dStyle = dStylesConfig.GetDynamicByIndex(i);
		dStyle.GetString("name", gS_StyleStrings[i][sStyleName], 128);
		dStyle.GetString("shortname", gS_StyleStrings[i][sShortName], 128);
		dStyle.GetString("htmlcolor", gS_StyleStrings[i][sHTMLColor], 128);
		dStyle.GetString("command", gS_StyleStrings[i][sChangeCommand], 128);

		gA_StyleSettings[i][bAutobhop] = dStyle.GetBool("autobhop", true);
		gA_StyleSettings[i][bEasybhop] = dStyle.GetBool("easybhop", true);
		gA_StyleSettings[i][bPrespeed] = dStyle.GetBool("prespeed", false);
		gA_StyleSettings[i][fVelocityLimit] = dStyle.GetFloat("velocity_limit", 0.0);
		gA_StyleSettings[i][iAiraccelerate] = dStyle.GetInt("airaccelerate", 1000);
		gA_StyleSettings[i][fRunspeed] = dStyle.GetFloat("runspeed", 260.00);
		gA_StyleSettings[i][fGravityMultiplier] = dStyle.GetFloat("gravity", 1.0);
		gA_StyleSettings[i][fSpeedMultiplier] = dStyle.GetFloat("speed", 1.0);
		gA_StyleSettings[i][bHalftime] = dStyle.GetBool("halftime", false);
		gA_StyleSettings[i][bBlockW] = dStyle.GetBool("block_w", false);
		gA_StyleSettings[i][bBlockA] = dStyle.GetBool("block_a", false);
		gA_StyleSettings[i][bBlockS] = dStyle.GetBool("block_s", false);
		gA_StyleSettings[i][bBlockD] = dStyle.GetBool("block_d", false);
		gA_StyleSettings[i][bBlockUse] = dStyle.GetBool("block_use", false);
		gA_StyleSettings[i][bForceHSW] = dStyle.GetBool("force_hsw", false);
		gA_StyleSettings[i][bBlockPLeft] = dStyle.GetBool("block_pleft", false);
		gA_StyleSettings[i][bBlockPRight] = dStyle.GetBool("block_pright", false);
		gA_StyleSettings[i][bBlockPStrafe] = dStyle.GetBool("block_pstrafe", false);
		gA_StyleSettings[i][bUnranked] = dStyle.GetBool("unranked", false);
		gA_StyleSettings[i][bNoReplay] = dStyle.GetBool("noreplay", false);
		gA_StyleSettings[i][bSync] = dStyle.GetBool("sync", true);
		gA_StyleSettings[i][bStrafeCountW] = dStyle.GetBool("strafe_count_w", false);
		gA_StyleSettings[i][bStrafeCountA] = dStyle.GetBool("strafe_count_a", true);
		gA_StyleSettings[i][bStrafeCountS] = dStyle.GetBool("strafe_count_s", false);
		gA_StyleSettings[i][bStrafeCountD] = dStyle.GetBool("strafe_count_d", true);
		gA_StyleSettings[i][fRankingMultiplier] = dStyle.GetFloat("rankingmultiplier", 1.00);
		gA_StyleSettings[i][iSpecial] = dStyle.GetInt("special", 0);

		if(!gB_Registered && strlen(gS_StyleStrings[i][sChangeCommand]) > 0)
		{
			char[][] sStyleCommands = new char[32][32];
			int iCommands = ExplodeString(gS_StyleStrings[i][sChangeCommand], ";", sStyleCommands, 32, 32, false);

			char[] sDescription = new char[128];
			FormatEx(sDescription, 128, "Change style to %s.", gS_StyleStrings[i][sStyleName]);

			for(int x = 0; x < iCommands; x++)
			{
				TrimString(sStyleCommands[x]);
				StripQuotes(sStyleCommands[x]);

				char[] sCommand = new char[32];
				FormatEx(sCommand, 32, "sm_%s", sStyleCommands[x]);

				gSM_StyleCommands.SetValue(sCommand, i);

				RegConsoleCmd(sCommand, Command_StyleChange, sDescription);
			}
		}
	}

	gB_Registered = true;

	dStylesConfig.Dispose(true);

	return true;
}

public Action Command_StyleChange(int client, int args)
{
	char[] sCommand = new char[128];
	GetCmdArg(0, sCommand, 128);

	BhopStyle style = Style_Default;

	if(gSM_StyleCommands.GetValue(sCommand, style))
	{
		ChangeClientStyle(client, style);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

bool LoadMessages()
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-messages.cfg");

	Dynamic dMessagesConfig = Dynamic();

	if(!dMessagesConfig.ReadKeyValues(sPath))
	{
		dMessagesConfig.Dispose();

		return false;
	}

	Dynamic dMessage = dMessagesConfig.GetDynamic((gEV_Type == Engine_CSS)? "CS:S":"CS:GO");
	dMessage.GetString("prefix", gS_ChatStrings[sMessagePrefix], 128);
	dMessage.GetString("text", gS_ChatStrings[sMessageText], 128);
	dMessage.GetString("warning", gS_ChatStrings[sMessageWarning], 128);
	dMessage.GetString("variable", gS_ChatStrings[sMessageVariable], 128);
	dMessage.GetString("variable2", gS_ChatStrings[sMessageVariable2], 128);
	dMessage.GetString("style", gS_ChatStrings[sMessageStyle], 128);

	dMessagesConfig.Dispose(true);

	for(int i = 0; i < CHATSETTINGS_SIZE; i++)
	{
		for(int x = 0; x < sizeof(gS_GlobalColorNames); x++)
		{
			ReplaceString(gS_ChatStrings[i], 128, gS_GlobalColorNames[x], gS_GlobalColors[x]);
		}

		for(int x = 0; x < sizeof(gS_CSGOColorNames); x++)
		{
			ReplaceString(gS_ChatStrings[i], 128, gS_CSGOColorNames[x], gS_CSGOColors[x]);
		}

		ReplaceString(gS_ChatStrings[i], 128, "{RGB}", "\x07");
		ReplaceString(gS_ChatStrings[i], 128, "{RGBA}", "\x08");
	}

	return true;
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

void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		delete gH_SQL;
	}

	char[] sError = new char[255];

	if(SQL_CheckConfig("shavit")) // can't be asynced as we have modules that require this database connection instantly
	{
		gH_SQL = SQL_Connect("shavit", true, sError, 255);

		if(gH_SQL == null)
		{
			SetFailState("Timer startup failed. Reason: %s", sError);
		}
	}

	else
	{
		gH_SQL = SQLite_UseDatabase("shavit", sError, 255);
	}

	// support unicode names
	gH_SQL.SetCharset("utf8");

	Call_StartForward(gH_Forwards_OnDatabaseLoaded);
	Call_PushCell(gH_SQL);
	Call_Finish();

	char[] sDriver = new char[8];
	gH_SQL.Driver.GetIdentifier(sDriver, 8);
	gB_MySQL = StrEqual(sDriver, "mysql", false);

	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "CREATE TABLE IF NOT EXISTS `%susers` (`auth` VARCHAR(32) NOT NULL, `name` VARCHAR(32), `country` VARCHAR(128), `ip` VARCHAR(64), `lastlogin` %s NOT NULL DEFAULT -1, `points` FLOAT NOT NULL DEFAULT 0, PRIMARY KEY (`auth`));", gS_MySQLPrefix, gB_MySQL? "INT":"INTEGER");

	// CREATE TABLE IF NOT EXISTS
	gH_SQL.Query(SQL_CreateTable_Callback, sQuery);
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Users' data table creation failed. Reason: %s", error);

		return;
	}

	char[] sQuery = new char[64];
	FormatEx(sQuery, 64, "SELECT lastlogin FROM %susers LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration1_Callback, sQuery, 0, DBPrio_High);

	FormatEx(sQuery, 64, "SELECT points FROM %susers LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration2_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_TableMigration1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[128];
		FormatEx(sQuery, 128, "ALTER TABLE `%susers` ADD %s;", gS_MySQLPrefix, gB_MySQL? "(`lastlogin` INT NOT NULL DEFAULT -1)":"COLUMN `lastlogin` INTEGER NOT NULL DEFAULT -1");
		gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);
	}
}

public void SQL_AlterTable1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Table alteration 1 (core) failed. Reason: %s", error);

		return;
	}
}

public void SQL_TableMigration2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[128];
		FormatEx(sQuery, 128, "ALTER TABLE `%susers` ADD %s;", gS_MySQLPrefix, gB_MySQL? "(`points` FLOAT NOT NULL DEFAULT 0)":"COLUMN `points` FLOAT NOT NULL DEFAULT 0");
		gH_SQL.Query(SQL_AlterTable2_Callback, sQuery);
	}
}

public void SQL_AlterTable2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Table alteration 2 (core) failed. Reason: %s", error);

		return;
	}
}

public void PreThink(int client)
{
	if(IsPlayerAlive(client))
	{
		sv_airaccelerate.IntValue = gA_StyleSettings[gBS_Style[client]][iAiraccelerate];
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if(!IsPlayerAlive(client) || IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	if(gB_ClientPaused[client])
	{
		buttons = 0;
		vel = view_as<float>({0.0, 0.0, 0.0});

		return Plugin_Changed;
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	bool bInStart = Shavit_InsideZone(client, Zone_Start);

	if(gB_TimerEnabled[client] && !gB_ClientPaused[client])
	{
		char[] sCheatDetected = new char[64];

		// +left/right block
		if(gB_LeftRight && (!gB_Zones || !bInStart && ((gA_StyleSettings[gBS_Style[client]][bBlockPLeft] &&
			(buttons & IN_LEFT) > 0) || (gA_StyleSettings[gBS_Style[client]][bBlockPRight] && (buttons & IN_RIGHT) > 0))))
		{
			FormatEx(sCheatDetected, 64, "%T", "LeftRightCheat", client);
			StopTimer_Cheat(client, sCheatDetected);
		}

		// +strafe block
		if(gA_StyleSettings[gBS_Style[client]][bBlockPStrafe] &&
			((vel[0] > 0.0 && (buttons & IN_FORWARD) == 0) || (vel[0] < 0.0 && (buttons & IN_BACK) == 0) ||
			(vel[1] > 0.0 && (buttons & IN_MOVERIGHT) == 0) || (vel[1] < 0.0 && (buttons & IN_MOVELEFT) == 0)))
		{
			float fTime = GetEngineTime();

			if(gF_StrafeWarning[client] < fTime)
			{
				FormatEx(sCheatDetected, 64, "%T", "Inconsistencies", client);
				StopTimer_Cheat(client, sCheatDetected);
			}

			gF_StrafeWarning[client] = fTime + 0.20;
		}
	}

	// key blocking
	if(!Shavit_InsideZone(client, Zone_Freestyle))
	{
		// block E
		if(gA_StyleSettings[gBS_Style[client]][bBlockUse] && (buttons & IN_USE) > 0)
		{
			buttons &= ~IN_USE;
		}

		if(iGroundEntity == -1)
		{
			if(gA_StyleSettings[gBS_Style[client]][bBlockW] && ((buttons & IN_FORWARD) > 0 || vel[0] > 0.0))
			{
				vel[0] = 0.0;
				buttons &= ~IN_FORWARD;
			}

			if(gA_StyleSettings[gBS_Style[client]][bBlockA] && ((buttons & IN_MOVELEFT) > 0 || vel[1] < 0.0))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVELEFT;
			}

			if(gA_StyleSettings[gBS_Style[client]][bBlockS] && ((buttons & IN_BACK) > 0 || vel[0] < 0.0))
			{
				vel[0] = 0.0;
				buttons &= ~IN_BACK;
			}

			if(gA_StyleSettings[gBS_Style[client]][bBlockD] && ((buttons & IN_MOVERIGHT) > 0 || vel[1] > 0.0))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVERIGHT;
			}

			// HSW
			if(gA_StyleSettings[gBS_Style[client]][bForceHSW] && ((vel[0] < gF_HSW_Requirement && vel[0] > -gF_HSW_Requirement) ||
				!((vel[0] > 0 || (buttons & IN_FORWARD) > 0) && ((vel[1] < 0 || (buttons & IN_MOVELEFT) > 0) || (vel[1] > 0 || (buttons & IN_MOVERIGHT) > 0)))))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVELEFT;
				buttons &= ~IN_MOVERIGHT;
			}
		}
	}

	if(gA_StyleSettings[gBS_Style[client]][bStrafeCountW] && !gA_StyleSettings[gBS_Style[client]][bBlockW] &&
		(gI_ButtonCache[client] & IN_FORWARD) == 0 && (buttons & IN_FORWARD) > 0)
	{
		gI_Strafes[client]++;
	}

	if(gA_StyleSettings[gBS_Style[client]][bStrafeCountA] && !gA_StyleSettings[gBS_Style[client]][bBlockA] && (gI_ButtonCache[client] & IN_MOVELEFT) == 0 &&
		(buttons & IN_MOVELEFT) > 0 && (gA_StyleSettings[gBS_Style[client]][bForceHSW] || ((buttons & IN_FORWARD) == 0 && (buttons & IN_BACK) == 0)))
	{
		gI_Strafes[client]++;
	}

	if(gA_StyleSettings[gBS_Style[client]][bStrafeCountS] && !gA_StyleSettings[gBS_Style[client]][bBlockS] &&
		(gI_ButtonCache[client] & IN_BACK) == 0 && (buttons & IN_BACK) > 0)
	{
		gI_Strafes[client]++;
	}

	if(gA_StyleSettings[gBS_Style[client]][bStrafeCountD] && !gA_StyleSettings[gBS_Style[client]][bBlockD] && (gI_ButtonCache[client] & IN_MOVERIGHT) == 0 &&
		(buttons & IN_MOVERIGHT) > 0 && (gA_StyleSettings[gBS_Style[client]][bForceHSW] || ((buttons & IN_FORWARD) == 0 && (buttons & IN_BACK) == 0)))
	{
		gI_Strafes[client]++;
	}

	if(gA_StyleSettings[gBS_Style[client]][bAutobhop] && gB_Autobhop && gB_Auto[client])
	{
		bool bInWater = (GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2);
		bool bOnLadder = (GetEntityMoveType(client) == MOVETYPE_LADDER);

		if((buttons & IN_JUMP) > 0 && iGroundEntity == -1 && !bOnLadder && !bInWater)
		{
			buttons &= ~IN_JUMP;
		}

		else if(gB_DoubleSteps[client] && (iGroundEntity != -1 || bOnLadder || bInWater))
		{
			buttons |= IN_JUMP;
		}
	}

	else if(gB_DoubleSteps[client])
	{
		buttons |= IN_JUMP;
	}

	if(bInStart && gB_BlockPreJump && !gA_StyleSettings[gBS_Style[client]][bPrespeed] && (vel[2] > 0 || (buttons & IN_JUMP) > 0))
	{
		vel[2] = 0.0;
		buttons &= ~IN_JUMP;
	}

	// velocity limit
	if(iGroundEntity != -1 && view_as<float>(gA_StyleSettings[gBS_Style[client]][fVelocityLimit] > 0.0) &&
	(!gB_Zones || !Shavit_InsideZone(client, Zone_NoVelLimit)))
	{
		float fSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = (SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));

		if(fSpeed_New > 0.0)
		{
			float fScale = view_as<float>(gA_StyleSettings[gBS_Style[client]][fVelocityLimit]) / fSpeed_New;

			if(fScale < 1.0)
			{
				ScaleVector(fSpeed, fScale);
				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
			}
		}
	}

	float fAngle = (angles[1] - gF_AngleCache[client]);

	while(fAngle > 180.0)
	{
		fAngle -= 360.0;
	}

	while(fAngle < -180.0)
	{
		fAngle += 360.0;
	}

	if(iGroundEntity == -1 && (GetEntityFlags(client) & FL_INWATER) == 0 && fAngle != 0.0)
	{
		float fAbsVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);

		if(SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)) > 0.0)
		{
			float fTempAngle = angles[1];

			float fAngles[3];
			GetVectorAngles(fAbsVelocity, fAngles);

			if(fTempAngle < 0.0)
			{
				fTempAngle += 360.0;
			}

			float fDirectionAngle = (fTempAngle - fAngles[1]);

			if(fDirectionAngle < 0.0)
			{
				fDirectionAngle = -fDirectionAngle;
			}

			if(fDirectionAngle < 22.5 || fDirectionAngle > 337.5)
			{
				gI_TotalMeasures[client]++;

				if((fAngle > 0.0 && vel[1] < 0.0) || (fAngle < 0.0 && vel[1] > 0.0))
				{
					gI_GoodGains[client]++;
				}
			}

			else if((fDirectionAngle > 67.5 && fDirectionAngle < 112.5) || (fDirectionAngle > 247.5 && fDirectionAngle < 292.5))
			{
				gI_TotalMeasures[client]++;

				if(vel[0] != 0.0)
				{
					gI_GoodGains[client]++;
				}
			}
		}
	}

	gI_ButtonCache[client] = buttons;
	gF_AngleCache[client] = angles[1];

	return Plugin_Continue;
}

void StopTimer_Cheat(int client, const char[] message)
{
	Shavit_StopTimer(client);
	Shavit_PrintToChat(client, "%T", "CheatTimerStop", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText], message);
}

void UpdateAutoBhop(int client)
{
	if(sv_autobunnyhopping != null)
	{
		sv_autobunnyhopping.ReplicateToClient(client, (gA_StyleSettings[gBS_Style[client]][bAutobhop] && gB_Autobhop && gB_Auto[client])? "1":"0");
	}
}
