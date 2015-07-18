/*
 * shavit's Timer - Miscellaneous
 * by: shavit
 *
 * This file is part of Shavit's Timer.
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
int gI_GodMode = 3;
ConVar gCV_PreSpeed = null;
int gI_PreSpeed = 3;

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
	RegConsoleCmd("sm_spectate", Command_Spec, "Moves you to the spectators' team. Usage: sm_spec [target]");

	// hide
	RegConsoleCmd("sm_hide", Command_Hide, "Toggle players' hiding.");
	RegConsoleCmd("sm_unhide", Command_Hide, "Toggle players' hiding.");

	// message
	CreateTimer(600.0, Timer_Message, INVALID_HANDLE, TIMER_REPEAT);
	
	// hooks
	HookEvent("player_spawn", Player_Spawn);

	// let's fix issues with phrases :D
	LoadTranslations("common.phrases");
	
	// CS:GO weapon cleanup
	if(Shavit_GetGameType() == Game_CSGO)
	{
		Handle hDeathDropGun = FindConVar("mp_death_drop_gun");
		
		if(hDeathDropGun != null)
		{
			SetConVarBool(hDeathDropGun, false);
		}
		
		else
		{
			LogError("idk what's wrong but for some reason, your CS:GO server is missing the \"mp_death_drop_gun\" cvar. go find what's causing it because I dunno");
		}
	}
	
	// cvars and stuff
	gCV_GodMode = CreateConVar("shavit_misc_godmode", "3", "Enable godmode for players? \n0 - Disabled\n1 - Only prevent fall/world damage.\n2 - Only prevent damage from other players.\n3 - Full godmode.");
	HookConVarChange(gCV_GodMode, OnConVarChanged);
	gCV_PreSpeed = CreateConVar("shavit_misc_prespeed", "3", "Stop prespeed in startzone? \n0 - Disabled\n1 - Limit 280 speed.\n2 - Block bhopping in startzone\n3 - Limit 280 speed and block bhopping in startzone.");
	HookConVarChange(gCV_PreSpeed, OnConVarChanged);
	
	AutoExecConfig();
	gI_GodMode = GetConVarInt(gCV_GodMode);
	gI_PreSpeed = GetConVarInt(gCV_PreSpeed);
	
	if(LibraryExists("dhooks"))
	{
		Handle hGameData = LoadGameConfigFile("shavit.games");
		
		if(hGameData != null)
		{
			int iOffset = GameConfGetOffset(hGameData, "GetMaxPlayerSpeed");
			gH_GetMaxPlayerSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, DHook_GetMaxPlayerSpeed);
		}
		
		CloseHandle(hGameData);
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

public void OnConVarChanged(ConVar cvar, const char[] sOld, const char[] sNew)
{
	// using an if() statement just incase I'll add more cvars.
	if(cvar == gCV_GodMode)
	{
		gI_GodMode = StringToInt(sNew);
	}
	else if(cvar == gCV_PreSpeed)
	{
		gI_PreSpeed = StringToInt(sNew);
	}
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
	PrintToChatAll("%s You may write !hide to hide other players.", PREFIX);

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
		if((gI_PreSpeed == 2 || gI_PreSpeed == 3) && !(gF_LastFlags[client] & FL_ONGROUND) && (GetEntityFlags(client) & FL_ONGROUND) && buttons & IN_JUMP)
		{
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>{0.0, 0.0, 0.0});
			PrintToChat(client, "%s Bhopping in the start zone is not allowed", PREFIX);
			gF_LastFlags[client] = GetEntityFlags(client);
			return Plugin_Continue;
		}

		if(gI_PreSpeed == 1 || gI_PreSpeed == 3)
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

			float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
			float fScale = FloatDiv(280.0, fSpeed_New);
			
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
	switch(gI_GodMode)
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
		default: return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

// hide
public Action OnSetTransmit(int entity, int client)
{
	if(IsClientObserver(client))
	{
		return Plugin_Continue;
	}

	if(gB_Hide[client] && client != entity)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// hide commands
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	// let's hope this works
	if(IsChatTrigger())
	{
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
	PrintToChat(client, "%s You are now %shiding players.", PREFIX, gB_Hide[client]? "":"not ");

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
		char sArgs[MAX_TARGET_LENGTH];
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

public Action Command_Specs(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client) && !IsClientObserver(client))
	{
		ReplyToCommand(client, "%s You should be alive or spectate someone to see your/their spectators.", PREFIX);

		return Plugin_Handled;
	}

	int iSpecTarget = client;

	if(IsClientObserver(client))
	{
		iSpecTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	}

	if(args > 0)
	{
		char sTarget[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		int iNewTarget = FindTarget(client, sTarget, false, false);

		if(iNewTarget == -1)
		{
			return Plugin_Handled;
		}

		if(!IsPlayerAlive(iNewTarget))
		{
			ReplyToCommand(client, "%s You can't target a dead player.", PREFIX);

			return Plugin_Handled;
		}

		iSpecTarget = iNewTarget;
	}

	int iCount;
	char sSpecs[256];

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
				FormatEx(sSpecs, 256, "%N", i);
			}

			else
			{
				Format(sSpecs, 256, "%s, %N", sSpecs);
			}
		}
	}

	if(iCount > 0)
	{
		ReplyToCommand(client, "%s \x03%N\x01 has %d spectators: %s", PREFIX, iSpecTarget, iCount, sSpecs);
	}

	else
	{
		ReplyToCommand(client, "%s No one is spectating \x03%N\x01.", PREFIX, iSpecTarget);
	}

	return Plugin_Handled;
}

public void Shavit_OnWorldRecord(int client, BhopStyle style, float time, int jumps)
{
	for(int i = 1; i <= 3; i++)
	{
		PrintToChatAll(" \x02NEW %s WR!!!", style == Style_Forwards? "FORWARDS":"SIDEWAYS");
	}
}

public void Shavit_OnRestart(int client)
{
	if(!IsPlayerAlive(client))
	{
		if(GetClientTeam(client) <= 1)
		{
			if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				ChangeClientTeam(client, CS_TEAM_T);
			}
			
			else
			{
				ChangeClientTeam(client, CS_TEAM_CT);
			}
			
			CreateTimer(0.1, Respawn, client);
		}
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
	int userid = GetEventInt(event, "userid");
	int client = GetClientOfUserId(userid);

	RestartTimer(client);
}
