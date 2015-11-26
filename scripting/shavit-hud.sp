/*
 * shavit's Timer - HUD
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
#include <shavit>

#pragma semicolon 1
#pragma dynamic 131072 // let's make stuff faster
#pragma newdecls required // We're at 2015 :D

// game type (CS:S/CS:GO)
ServerGame gSG_Type = Game_Unknown;

bool gB_Replay = false;

bool gB_ZoneHUD[MAXPLAYERS+1] = {true, ...};
bool gB_HUD[MAXPLAYERS+1] = {true, ...};

int gI_StartCycle = 0;

char gS_Start[][] = 
{
	"ff0000",
	"ff4000",
	"ff7f00",
	"ffbf00",
	"ffff00",
	"00ff00",
	"00ff80",
	"00ffff",
	"0080ff",
	"0000ff"
};

int gI_EndCycle = 0;

char gS_End[][] = 
{
	"ff0000",
	"ff4000",
	"ff7f00",
	"ffaa00",
	"ffd400",
	"ffff00",
	"bba24e",
	"77449c"
};

public Plugin myinfo = 
{
	name = "[shavit] HUD",
	author = "shavit",
	description = "HUD for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	gSG_Type = Shavit_GetGameType();
}

public void OnPluginStart()
{
	// prevent errors in case the replay bot isn't loaded
	gB_Replay = LibraryExists("shavit-replay");
	
	CreateTimer(0.1, UpdateHUD_Timer, INVALID_HANDLE, TIMER_REPEAT);
	
	RegConsoleCmd("sm_togglehud", Command_ToggleHUD, "Toggle the timer's HUD");
	RegConsoleCmd("sm_hud", Command_ToggleHUD, "Toggle the timer's HUD");
	
	RegConsoleCmd("sm_zonehud", Command_ToggleZoneHUD, "Toggle the timer's flashing zone HUD");
}

public void OnClientPutInServer(int client)
{
	gB_HUD[client] = true;
}

public Action Command_ToggleHUD(int client, int args)
{
	gB_HUD[client] = !gB_HUD[client];
	
	ReplyToCommand(client, "%s HUD %s\x01.", PREFIX, gB_HUD[client]? "\x04enabled":(gSG_Type == Game_CSGO? "\x02disabled":"\x05disabled"));
	
	return Plugin_Handled;
}

public Action Command_ToggleZoneHUD(int client, int args)
{
	gB_ZoneHUD[client] = !gB_ZoneHUD[client];
	
	ReplyToCommand(client, "%s Zone HUD %s\x01.", PREFIX, gB_ZoneHUD[client]? "\x04enabled":(gSG_Type == Game_CSGO? "\x02disabled":"\x05disabled"));
	
	return Plugin_Handled;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
	}
}

public void OnConfigsExecuted()
{
	if(gSG_Type == Game_CSS)
	{
		// causes an error :/
		// FindConVar("sv_hudhint_sound").SetBool(false);

		ConVar sv_hudhint_sound = FindConVar("sv_hudhint_sound");
		sv_hudhint_sound.SetBool(false);
	}
}

public Action UpdateHUD_Timer(Handle Timer)
{
	gI_StartCycle++;
	
	if(gI_StartCycle > 9)
	{
		gI_StartCycle = 0;
	}
	
	gI_EndCycle++;
	
	if(gI_EndCycle > 7)
	{
		gI_EndCycle = 0;
	}
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || !gB_HUD[i])
		{
			continue;
		}

		UpdateHUD(i);
	}

	return Plugin_Continue;
}

public void UpdateHUD(int client)
{
	int target = client;

	if(IsClientObserver(client))
	{
		if(GetEntProp(client, Prop_Send, "m_iObserverMode") >= 3)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(IsValidClient(iTarget, true))
			{
				target = iTarget;
			}
		}
	}
	
	char sHintText[256];
	
	if(gB_ZoneHUD[client] && gSG_Type == Game_CSGO && Shavit_InsideZone(target, Zone_Start))
	{
		FormatEx(sHintText, 256, "<font size=\"45\" color=\"#%s\">Start Zone</font>", gS_Start[gI_StartCycle]);
		
		PrintHintText(client, sHintText);
	}
	
	else if(gB_ZoneHUD[client] && gSG_Type == Game_CSGO && Shavit_InsideZone(target, Zone_End))
	{
		FormatEx(sHintText, 256, "<font size=\"45\" color=\"#%s\">End Zone</font>", gS_End[gI_EndCycle]);
		
		PrintHintText(client, sHintText);
	}
	
	else if(!IsFakeClient(target))
	{
		float fTime;
		int iJumps;
		BhopStyle bsStyle;
		bool bStarted;
		Shavit_GetTimer(target, fTime, iJumps, bsStyle, bStarted);
	
		float fWR;
		Shavit_GetWRTime(bsStyle, fWR);
	
		float fSpeed[3];
		GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
		
		float fPB;
		Shavit_GetPlayerPB(target, bsStyle, fPB);
		
		char sPB[32];
		FormatSeconds(fPB, sPB, 32);
		
		char sTime[32];
		FormatSeconds(fTime, sTime, 32, false);
	
		if(gSG_Type == Game_CSGO)
		{
			FormatEx(sHintText, 256, "<font face='Stratum2'>");
			
			if(bStarted)
			{
				char sColor[8];
	
				if(fTime < fWR || fWR == 0.0)
				{
					strcopy(sColor, 8, "00FF00");
				}
	
				else if(fPB != 0.0 && fTime < fPB)
				{
					strcopy(sColor, 8, "FFA500");
				}
	
				else
				{
					strcopy(sColor, 8, "FF0000");
				}
	
				Format(sHintText, 256, "%sTime: <font color='#%s'>%s</font>", sHintText, sColor, sTime);
			}
			
			Format(sHintText, 256, "%s\nStyle: <font color='%s</font>", sHintText, bsStyle == Style_Forwards? "#797FD4'>Forwards":"#B54CB3'>Sideways");
			
			if(fPB > 0.00)
			{
				Format(sHintText, 256, "%s\tPB: %s", sHintText, sPB);
			}
	
			Format(sHintText, 256, "%s\nSpeed: %.02f%s", sHintText, fSpeed_New, fSpeed_New < 10? "\t":"");
	
			if(bStarted)
			{
				Format(sHintText, 256, "%s\tJumps: %d", sHintText, iJumps);
			}
	
			Format(sHintText, 256, "%s\nPlayer: <font color='#BF6821'>%N</font>", sHintText, target);
	
			Format(sHintText, 256, "%s</font>", sHintText);
		}
	
		else
		{
			if(bStarted)
			{
				FormatEx(sHintText, 256, "Time: %s", sTime);
				
				Format(sHintText, 256, "%s\nStyle: %s", sHintText, bsStyle == Style_Forwards? "Forwards":"Sideways");
			}
			
			else
			{
				FormatEx(sHintText, 256, "Style: %s", bsStyle == Style_Forwards? "Forwards":"Sideways");
			}
			
			if(fPB > 0.00)
			{
				Format(sHintText, 256, "%s\tPB: %s", sHintText, sPB);
			}
	
			Format(sHintText, 256, "%s\nSpeed: %.02f%s", sHintText, fSpeed_New, fSpeed_New < 10? "\t":"");
	
			if(bStarted)
			{
				Format(sHintText, 256, "%s\tJumps: %d", sHintText, iJumps);
			}
	
			Format(sHintText, 256, "%s\nPlayer: %N", sHintText, target);
		}
		
		PrintHintText(client, sHintText);
	}
	
	else if(gB_Replay)
	{
		BhopStyle bsStyle = (target == Shavit_GetReplayBotIndex(Style_Forwards)? Style_Forwards:Style_Sideways);
		
		/* will work on this when I find enough time
		float fBotStart;
		Shavit_GetReplayBotFirstFrame(bsStyle, fBotStart);
		
		float fTime = GetEngineTime() - fBotStart;
		
		char sTime[32];
		FormatSeconds(fTime, sTime, 32, false);*/
		
		float fSpeed[3];
		GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
	
		if(gSG_Type == Game_CSGO)
		{
			FormatEx(sHintText, 256, "<font face='Stratum2'>");
			Format(sHintText, 256, "%s\t<font color='#5F8BC9'>- Replay Bot -</font>", sHintText);
			Format(sHintText, 256, "%s\nStyle: <font color='%s</font>", sHintText, bsStyle == Style_Forwards? "#797FD4'>Forwards":"#B54CB3'>Sideways");
			Format(sHintText, 256, "%s\nSpeed: %.02f", sHintText, fSpeed_New);
			Format(sHintText, 256, "%s</font>", sHintText);
		}
	
		else
		{
			FormatEx(sHintText, 256, "\t- Replay Bot -", sHintText);
			Format(sHintText, 256, "%s\nStyle: %s", sHintText, bsStyle == Style_Forwards? "Forwards":"Sideways");
			Format(sHintText, 256, "%s\nSpeed: %.02f", sHintText, fSpeed_New);
		}
		
		PrintHintText(client, sHintText);
	}
}
