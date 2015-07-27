/*
 * shavit's Timer - HUD
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
#include <sdktools>
#include <shavit>

#pragma semicolon 1
#pragma dynamic 131072 // let's make stuff faster
#pragma newdecls required // We're at 2015 :D

// game type (CS:S/CS:GO)
ServerGame gSG_Type = Game_Unknown;

public Plugin myinfo = 
{
	name = "[shavit] HUD",
	author = "shavit",
	description = "HUD for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public void OnPluginStart()
{
	gSG_Type = Shavit_GetGameType();

	CreateTimer(0.1, UpdateHUD_Timer, INVALID_HANDLE, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
	if(gSG_Type == Game_CSS)
	{
		FindConVar("sv_hudhint_sound 0").SetBool(false);
	}
}

public Action UpdateHUD_Timer(Handle Timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
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

	bool bSpectating;

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

	float fTime;
	int iJumps;
	BhopStyle bsStyle;
	bool bStarted;
	Shavit_GetTimer(target, fTime, iJumps, bsStyle, bStarted);

	float fWR;
	Shavit_GetWRTime(bsStyle, fWR);

	//PrintToChat(client, "Time: %.02f WR: %.02f", fTime, fWR);

	char sHintText[256];

	if(gSG_Type == Game_CSGO)
	{
		FormatEx(sHintText, 256, "<font size='18'>");

		float fPB;
		Shavit_GetPlayerPB(target, bsStyle, fPB);
		char sPB[32];
		FormatSeconds(fPB, sPB, 32);
		Format(sHintText, 256, "%sPB: %s\t", sHintText, sPB);
		
		if(fPB != 0.0)
		{
			Format(sHintText, 256, "%s\t", sHintText);
		}

		if(bStarted)
		{
			char sTime[32];
			FormatSeconds(fTime, sTime, 32, false);

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

		float fSpeed[3];
		GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));

		Format(sHintText, 256, "%s\nSpeed: %.02f", sHintText, fSpeed_New);

		if(bStarted)
		{
			Format(sHintText, 256, "%s\tJumps: %d", sHintText, iJumps);
		}
		
		Format(sHintText, 256, "%s\nStyle: <font color='%s</font>", sHintText, bsStyle == Style_Forwards? "#797FD4'>Forwards":"#B54CB3'>Sideways");

		if(!bSpectating)
		{
			Format(sHintText, 256, "%s\tPlayer: <font color='#BF6821'>%N</font>", sHintText, target);
		}

		Format(sHintText, 256, "%s</font>", sHintText);
	}

	else
	{
		float fPB;
		Shavit_GetPlayerPB(target, bsStyle, fPB);
		char sPB[32];
		FormatSeconds(fPB, sPB, 32);
		Format(sHintText, 256, "%sPB: %s\t", sHintText, sPB);

		if(bStarted)
		{
			char sTime[32];
			FormatSeconds(fTime, sTime, 32);

			Format(sHintText, 256, "%sTime: %s", sHintText, sTime);
		}

		float fSpeed[3];
		GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));

		Format(sHintText, 256, "%s\nSpeed: %.02f", sHintText, fSpeed_New);

		if(bStarted)
		{
			Format(sHintText, 256, "%s\tJumps: %d", sHintText, iJumps);
		}

		Format(sHintText, 256, "%s\nStyle: %s", sHintText, bsStyle == Style_Forwards? "Forwards":"Sideways");

		if(!bSpectating)
		{
			Format(sHintText, 256, "%s\tPlayer: %N", sHintText, target);
		}
	}

	PrintHintText(client, sHintText);
}
