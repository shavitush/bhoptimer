/*
 * shavit's Timer - Miscellaneous
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
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#define USES_STYLE_NAMES
#include <shavit>

#undef REQUIRE_EXTENSIONS
#include <dhooks>

#pragma semicolon 1
#pragma dynamic 131072 // let's make stuff faster
#pragma newdecls required // We're at 2015 :D

bool gB_Hide[MAXPLAYERS+1];
bool gB_Late;
int gF_LastFlags[MAXPLAYERS+1];

// cvars
ConVar gCV_GodMode = null;
ConVar gCV_PreSpeed = null;
ConVar gCV_HideTeamChanges = null;
ConVar gCV_RespawnOnTeam = null;
ConVar gCV_RespawnOnRestart = null;
ConVar gCV_StartOnSpawn = null;

// dhooks
Handle gH_GetMaxPlayerSpeed = null;

public Plugin myinfo =
{
	name = "[shavit] Miscellaneous",
	author = "shavit",
	description = "Miscellaneous stuff for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;
}

public void OnPluginStart()
{
	// spectator list
	RegConsoleCmd("sm_specs", Command_Specs, "Show a list of spectators.");
	RegConsoleCmd("sm_spectators", Command_Specs, "Show a list of spectators.");

	// spec
	RegConsoleCmd("sm_spec", Command_Spec, "Moves you to the spectators' team. Usage: sm_spec [target]");
	RegConsoleCmd("sm_spectate", Command_Spec, "Moves you to the spectators' team. Usage: sm_spectate [target]");

	// hide
	RegConsoleCmd("sm_hide", Command_Hide, "Toggle players' hiding.");
	RegConsoleCmd("sm_unhide", Command_Hide, "Toggle players' hiding.");

	// tpto
	RegConsoleCmd("sm_tpto", Command_Teleport, "Teleport to another player. Usage: sm_tpto [target]");
	RegConsoleCmd("sm_goto", Command_Teleport, "Teleport to another player. Usage: sm_goto [target]");

	// hook teamjoins
	AddCommandListener(Command_Jointeam, "jointeam");

	// message
	CreateTimer(600.0, Timer_Message, INVALID_HANDLE, TIMER_REPEAT);

	// hooks
	HookEvent("player_spawn", Player_Spawn);
	HookEvent("player_team", Player_Team, EventHookMode_Pre);

	// let's fix issues with phrases :D
	LoadTranslations("common.phrases");

	// CS:GO weapon cleanup
	if(Shavit_GetGameType() == Game_CSGO)
	{
		ConVar hDeathDropGun = FindConVar("mp_death_drop_gun");

		if(hDeathDropGun != null)
		{
			hDeathDropGun.SetBool(false);
		}

		else
		{
			LogError("idk what's wrong but for some reason, your CS:GO server is missing the \"mp_death_drop_gun\" cvar. go find what's causing it because I dunno");
		}
	}

	// cvars and stuff
	gCV_GodMode = CreateConVar("shavit_misc_godmode", "3", "Enable godmode for players?\n0 - Disabled\n1 - Only prevent fall/world damage.\n2 - Only prevent damage from other players.\n3 - Full godmode.", FCVAR_PLUGIN, true, 0.0, true, 3.0);
	gCV_PreSpeed = CreateConVar("shavit_misc_prespeed", "3", "Stop prespeed in startzone?\n0 - Disabled\n1 - Limit 280 speed.\n2 - Block bhopping in startzone\n3 - Limit 280 speed and block bhopping in startzone.", FCVAR_PLUGIN, true, 0.0, true, 3.0);
	gCV_HideTeamChanges = CreateConVar("shavit_misc_hideteamchanges", "1", "Hide team changes in chat?\n0 - Disabled\n1 - Enabled", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gCV_RespawnOnTeam = CreateConVar("shavit_misc_respawnonteam", "1", "Respawn whenever a player joins a team?\n0 - Disabled\n1 - Enabled", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gCV_RespawnOnRestart = CreateConVar("shavit_misc_respawnonrestart", "1", "Respawn a dead player if he uses the timer restart command?\n0 - Disabled\n1 - Enabled", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	gCV_StartOnSpawn = CreateConVar("shavit_misc_startonspawn", "1", "Restart the timer for a player after he spawns?\n0 - Disabled\n1 - Enabled", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	AutoExecConfig();

	if(LibraryExists("dhooks"))
	{
		Handle hGameData = LoadGameConfigFile("shavit.games");

		if(hGameData != null)
		{
			int iOffset = GameConfGetOffset(hGameData, "GetMaxPlayerSpeed");
			gH_GetMaxPlayerSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, DHook_GetMaxPlayerSpeed);
		}

		delete hGameData;
	}

	// late load
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public Action Command_Jointeam(int client, const char[] command, int args)
{
	char[] arg1 = new char[8];
	GetCmdArg(1, arg1, 8);

	int iTeam = StringToInt(arg1);

	// client is trying to join the same team he's now.
	// i'll let the game handle it.
	if(GetClientTeam(client) == iTeam)
	{
		return Plugin_Continue;
	}

	bool bRespawn = false;

	switch(iTeam)
	{
		case CS_TEAM_T:
		{
			// if T spawns are available in the map
			if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				bRespawn = true;

				CS_SwitchTeam(client, CS_TEAM_T);
			}
		}

		case CS_TEAM_CT:
		{
			// if CT spawns are available in the map
			if(FindEntityByClassname(-1, "info_player_counterterrorist") != -1)
			{
				bRespawn = true;

				CS_SwitchTeam(client, CS_TEAM_CT);
			}
		}

		// if they chose to spectate, i'll force them to join the spectators
		case CS_TEAM_SPECTATOR:
		{
			CS_SwitchTeam(client, CS_TEAM_SPECTATOR);
		}

		default:
		{
			return Plugin_Continue;
		}
	}

	if(bRespawn && gCV_RespawnOnTeam.BoolValue)
	{
		CS_RespawnPlayer(client);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public MRESReturn DHook_GetMaxPlayerSpeed(int pThis, Handle hReturn)
{
	if(IsValidClient(pThis, true))
	{
		DHookSetReturn(hReturn, 250.000);

		return MRES_Override;
	}

	return MRES_Ignored;
}

public Action Timer_Message(Handle Timer)
{
	Shavit_PrintToChatAll("You may write !hide to hide other players.");

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if(!IsValidClient(client, true))
	{
		return Plugin_Continue;
	}

	if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		// I'm horrible so I couldn't make it to not require so many variables :S
		float fTime;
		int iJumps;
		BhopStyle bsStyle;
		bool bStarted;
		Shavit_GetTimer(client, fTime, iJumps, bsStyle, bStarted);

		if(bStarted)
		{
			Shavit_StopTimer(client);
		}
	}

	if(Shavit_InsideZone(client, Zone_Start))
	{
		if((gCV_PreSpeed.IntValue == 2 || gCV_PreSpeed.IntValue == 3) && !(gF_LastFlags[client] & FL_ONGROUND) && (GetEntityFlags(client) & FL_ONGROUND) && buttons & IN_JUMP)
		{
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
			Shavit_PrintToChat(client, "Bhopping in the start zone is not allowed.");
			gF_LastFlags[client] = GetEntityFlags(client);

			return Plugin_Continue;
		}

		if(gCV_PreSpeed.IntValue == 1 || gCV_PreSpeed.IntValue == 3)
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

			float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
			float fScale = 280.0 / fSpeed_New;

			if(fScale < 1.0) // 280 / 281 = below 1 | 280 / 279 = above 1
			{
				fSpeed[0] *= fScale;
				fSpeed[1] *= fScale;

				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
			}
		}
	}

	gF_LastFlags[client] = GetEntityFlags(client);

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	gB_Hide[client] = false;

	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	if(gH_GetMaxPlayerSpeed != null)
	{
		DHookEntity(gH_GetMaxPlayerSpeed, true, client);
	}
}

public Action OnTakeDamage(int victim, int attacker)
{
	switch(gCV_GodMode.IntValue)
	{
		case 0:
		{
			return Plugin_Continue;
		}

		case 1:
		{
			// 0 - world/fall damage
			if(attacker == 0)
			{
				return Plugin_Handled;
			}
		}

		case 2:
		{
			if(IsValidClient(attacker, true))
			{
				return Plugin_Handled;
			}
		}

		// else
		default:
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

// hide
public Action OnSetTransmit(int entity, int client)
{
	if(client != entity && gB_Hide[client])
	{
		if(!IsClientObserver(client))
		{
			return Plugin_Handled;
		}

		else if(GetEntProp(client, Prop_Send, "m_iObserverMode") != 6 && GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") != entity)
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// let's hope this works
	if(IsChatTrigger())
	{
		// hide commands
		return Plugin_Handled;
	}

	// if capitalized !R = run sm_r
	if(StrEqual(sArgs, "!R"))
	{
		// cannot be used as it will not teleport me to anywhere
		// Shavit_StartTimer(client);

		// executing a command will be better at this case
		// also makes life easier for server owners that hardcoded sm_r to be disabled
		FakeClientCommand(client, "sm_r");

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Command_Hide(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Hide[client] = !gB_Hide[client];

	// I use PTC instead of RTC there because I have an sm_hide bind just like many people :)
	Shavit_PrintToChat(client, "You are now %shiding players.", gB_Hide[client]? "":"not ");

	return Plugin_Handled;
}

public Action Command_Spec(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	ChangeClientTeam(client, CS_TEAM_SPECTATOR);

	if(args > 0)
	{
		char[] sArgs = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", iTarget);
	}

	return Plugin_Handled;
}

public Action Command_Teleport(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(args > 0)
	{
		char[] sArgs = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		Teleport(client, GetClientSerial(iTarget));
	}

	else
	{
		Menu m = new Menu(MenuHandler_Teleport);
		m.SetTitle("Teleport to:");

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i, true) || i == client)
			{
				continue;
			}

			char[] serial = new char[16];
			IntToString(GetClientSerial(i), serial, 16);

			char[] sName = new char[MAX_NAME_LENGTH];
			GetClientName(i, sName, MAX_NAME_LENGTH);

			m.AddItem(serial, sName);
		}

		m.ExitButton = true;

		m.Display(client, 60);
	}

	return Plugin_Handled;
}

public int MenuHandler_Teleport(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		if(Teleport(param1, StringToInt(info)) == -1)
		{
			Command_Teleport(param1, 0);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int Teleport(int client, int targetserial)
{
	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "You can teleport only if you are alive.");

		return -1;
	}

	int iTarget = GetClientFromSerial(targetserial);

	if(Shavit_InsideZone(client, Zone_Start) || Shavit_InsideZone(client, Zone_End))
	{
		Shavit_PrintToChat(client, "You cannot teleport inside the start/end zones.");

		return -1;
	}

	if(!iTarget)
	{
		Shavit_PrintToChat(client, "Invalid target.");

		return -1;
	}

	float vecPosition[3];
	GetClientAbsOrigin(iTarget, vecPosition);

	Shavit_StopTimer(client);

	TeleportEntity(client, vecPosition, NULL_VECTOR, NULL_VECTOR);

	return 0;
}

public Action Command_Specs(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client) && !IsClientObserver(client))
	{
		Shavit_PrintToChat(client, "You should be alive or spectate someone to see your/their spectators.");

		return Plugin_Handled;
	}

	int iSpecTarget = client;

	if(IsClientObserver(client))
	{
		iSpecTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	}

	if(args > 0)
	{
		char[] sTarget = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		int iNewTarget = FindTarget(client, sTarget, false, false);

		if(iNewTarget == -1)
		{
			return Plugin_Handled;
		}

		if(!IsPlayerAlive(iNewTarget))
		{
			Shavit_PrintToChat(client, "You can't target a dead player.");

			return Plugin_Handled;
		}

		iSpecTarget = iNewTarget;
	}

	int iCount;
	char[] sSpecs = new char[192];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || !IsClientObserver(i))
		{
			continue;
		}

		if(GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == iSpecTarget)
		{
			iCount++;

			if(iCount == 1)
			{
				FormatEx(sSpecs, 192, "%N", i);
			}

			else
			{
				Format(sSpecs, 192, "%s, %N", sSpecs, i);
			}
		}
	}

	if(iCount > 0)
	{
		Shavit_PrintToChat(client, "\x03%N\x01 has %d spectators: %s", iSpecTarget, iCount, sSpecs);
	}

	else
	{
		Shavit_PrintToChat(client, "No one is spectating \x03%N\x01.", iSpecTarget);
	}

	return Plugin_Handled;
}

public void Shavit_OnWorldRecord(int client, BhopStyle style, float time, int jumps)
{
	char[] sUpperCase = new char[32];
	String_ToUpper(gS_BhopStyles[view_as<int>(style)], sUpperCase, 32);

	for(int x = 1; x <= 3; x++)
	{
		Shavit_PrintToChatAll("\x02NEW %s WR!!!", sUpperCase);
	}
}

public void Shavit_OnRestart(int client)
{
	if(!gCV_RespawnOnRestart.BoolValue)
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
		{
			CS_SwitchTeam(client, CS_TEAM_T);
		}

		else
		{
			CS_SwitchTeam(client, CS_TEAM_CT);
		}

		CreateTimer(0.1, Respawn, client);
	}
}

public void RestartTimer(int client)
{
	if(Shavit_ZoneExists(Zone_Start))
	{
		// I won't be adding a timer restart native, so I'll do this :S
		FakeClientCommand(client, "sm_r");
	}
}

public Action Respawn(Handle Timer, any client)
{
	if(IsValidClient(client) && !IsPlayerAlive(client))
	{
		CS_RespawnPlayer(client);

		RestartTimer(client);
	}

	return Plugin_Handled;
}

public void Player_Spawn(Handle event, const char[] name, bool dontBroadcast)
{
	if(!gCV_StartOnSpawn.BoolValue)
	{
		return;
	}

	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	RestartTimer(client);
}

public Action Player_Team(Handle event, const char[] name, bool dontBroadcast)
{
	if(gCV_HideTeamChanges.BoolValue)
	{
		SetEventBroadcast(event, true);

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

/**
 * From SMLib
 *
 * Converts the whole String to upper case.
 * Only works with alphabetical characters (not ���) because Sourcemod suxx !
 * The Output String can be the same as the Input String.
 *
 * @param input				Input String.
 * @param output			Output String.
 * @param size				Max Size of the Output string
 * @noreturn
 */
stock void String_ToUpper(const char[] input, char[] output, int size)
{
	size--;

	int x = 0;

	while(input[x] != '\0' && x < size)
	{
		output[x] = CharToUpper(input[x]);

		x++;
	}

	output[x] = '\0';
}
