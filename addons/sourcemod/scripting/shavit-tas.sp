#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <shavit>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "TAS Style",
	author = "Charles_(hypnos)",
	description = "TAS Style",
	version = "1.9.5",
	url = "https://hyps.dev/"
}

#define RUN 0
#define PAUSED 1
#define BACKWARD 2
#define FORWARD 3

#define AutoStrafeTrigger 1

int gI_Status[MAXPLAYERS+1];
ArrayList gA_Frames[MAXPLAYERS+1];
int gI_IndexCounter[MAXPLAYERS+1];
float gF_IndexCounter[MAXPLAYERS+1];
float gF_CounterSpeed[MAXPLAYERS+1];
bool gB_TASMenu[MAXPLAYERS+1];
float gF_TickRate;
float gF_TASTime[MAXPLAYERS+1];
float gF_TimeScale[MAXPLAYERS+1];
float gF_TimeScaleTicksPassed[MAXPLAYERS+1];
int gI_LastButtons[MAXPLAYERS+1];

bool gB_AutoStrafeEnabled[MAXPLAYERS+1] = {false,...};
bool gB_Strafing[MAXPLAYERS+1];

float flYawBhop[MAXPLAYERS+1];
float gF_TrueVel[MAXPLAYERS+1];
bool gB_DirIsRight[MAXPLAYERS+1];
int gI_StrafeAxis[MAXPLAYERS+1] = {1,...};
float gF_LastAngle[MAXPLAYERS];

bool gB_TAS[MAXPLAYERS + 1];

float gF_SideMove;

public void OnPluginStart()
{
	if(IsSource2013(GetEngineVersion()))
	{
		gF_SideMove = 400.0;
	}
	else
	{
		gF_SideMove = 450.0;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}

	AddCommandListener(CommandListener_PlusRewind, "+rewind");
	AddCommandListener(CommandListener_PlusForward, "+forward");
	AddCommandListener(CommandListener_MinusRewindOrForward, "-rewind");
	AddCommandListener(CommandListener_MinusRewindOrForward, "-forward");
	AddCommandListener(CommandListener_JoinTeam, "jointeam");
	AddCommandListener(CommandListener_TAS, "sm_tas");
	RegConsoleCmd("sm_tasmenu", Command_TASMenu);
	RegConsoleCmd("sm_tashelp", Command_TASHelp);

	gF_TickRate = (1.0 / GetTickInterval());

	RegConsoleCmd("sm_plusone", Command_PlusOne, "TAS adjustment +1 tick");
	RegConsoleCmd("sm_minusone", Command_MinusOne, "TAS adjustment -1 tick");
	
	RegConsoleCmd("+autostrafer", Command_PlusStrafer, "");
	RegConsoleCmd("-autostrafer", Command_MinusStrafer, "");
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle)
{
	char sSpecial[128];
	Shavit_GetStyleStrings(newstyle, sSpecialString, sSpecial, 128);

	if(StrContains(sSpecial, "tas", false) == -1)
	{ //off
		gB_TAS[client] = false;
	}
	else
	{ //on
		gB_TAS[client] = true;
		Shavit_PrintToChat(client, "This is a TAS style. Type !tashelp for more information.");
	}
}

public Action Command_PlusStrafer(int client, int args)
{
	gB_Strafing[client] = true;
	return;
}

public Action Command_MinusStrafer(int client, int args)
{
	gB_Strafing[client] = false;
	return;
}

public Action Command_PlusOne(int client, int args)
{
	if(gI_Status[client] == PAUSED)
	{
		int frameSize = GetArraySize(gA_Frames[client]);
		int framenum = gI_IndexCounter[client];
		if(frameSize > 1 && framenum < frameSize-1)
		{
			float fAng[3];
			fAng[0] = GetArrayCell(gA_Frames[client], framenum, 3);
			fAng[1] = GetArrayCell(gA_Frames[client], framenum, 4);
			fAng[2] = 0.0;
			
			float pos2[3];
			pos2[0] = GetArrayCell(gA_Frames[client], framenum, 0);
			pos2[1] = GetArrayCell(gA_Frames[client], framenum, 1);
			pos2[2] = GetArrayCell(gA_Frames[client], framenum, 2);

			float pos[3];
			pos[0] = GetArrayCell(gA_Frames[client], framenum-1, 0);
			pos[1] = GetArrayCell(gA_Frames[client], framenum-1, 1);
			pos[2] = GetArrayCell(gA_Frames[client], framenum-1, 2);

			float fVel[3];
			MakeVectorFromPoints(pos, pos2, fVel);

			for (int i = 0; i < 3; i++)
			{
				fVel[i] *= RoundToFloor(gF_TickRate);
			}

			TeleportEntity(client, pos2, fAng, fVel);

			if(GetArrayCell(gA_Frames[client], framenum, 5) & IN_DUCK)
			{
				SetEntProp(client, Prop_Send, "m_bDucked", true);
				SetEntProp(client, Prop_Send, "m_bDucking", true);
			}
			else
			{
				SetEntProp(client, Prop_Send, "m_bDucked", false);
				SetEntProp(client, Prop_Send, "m_bDucking", false);
			}

			gF_IndexCounter[client] += gF_CounterSpeed[client];
			if(IsRound(gF_IndexCounter[client]))
			{
				gI_IndexCounter[client]++;
			}
			gF_TASTime[client] += GetTickInterval() * gF_CounterSpeed[client];
		}
	}
	else
	{ //TAS Status must be PAUSED to use this function
		Shavit_PrintToChat(client, "sm_plusone can only be used when TAS is Paused!");
	}
	return Plugin_Handled;
}

public Action Command_MinusOne(int client, int args)
{
	if(gI_Status[client] == PAUSED)
	{
		int frameSize = GetArraySize(gA_Frames[client]);
		int framenum = gI_IndexCounter[client];
		if(frameSize > 1 && framenum > 2)
		{
			float fAng[3];
			fAng[0] = GetArrayCell(gA_Frames[client], framenum, 3);
			fAng[1] = GetArrayCell(gA_Frames[client], framenum, 4);
			fAng[2] = 0.0;
			
			float pos2[3];
			pos2[0] = GetArrayCell(gA_Frames[client], framenum, 0);
			pos2[1] = GetArrayCell(gA_Frames[client], framenum, 1);
			pos2[2] = GetArrayCell(gA_Frames[client], framenum, 2);

			float pos[3];
			pos[0] = GetArrayCell(gA_Frames[client], framenum-1, 0);
			pos[1] = GetArrayCell(gA_Frames[client], framenum-1, 1);
			pos[2] = GetArrayCell(gA_Frames[client], framenum-1, 2);

			float fVel[3];
			MakeVectorFromPoints(pos2, pos, fVel);

			for (int i = 0; i < 3; i++)
			{
				fVel[i] *= RoundToFloor(gF_TickRate);
			}

			TeleportEntity(client, pos, fAng, fVel);

			if(GetArrayCell(gA_Frames[client], framenum, 5) & IN_DUCK)
			{
				SetEntProp(client, Prop_Send, "m_bDucked", true);
				SetEntProp(client, Prop_Send, "m_bDucking", true);
			}
			else
			{
				SetEntProp(client, Prop_Send, "m_bDucked", false);
				SetEntProp(client, Prop_Send, "m_bDucking", false);
			}

			gF_IndexCounter[client] -= gF_CounterSpeed[client];
			if(IsRound(gF_IndexCounter[client]))
			{
				gI_IndexCounter[client]--;
			}
			gF_TASTime[client] -= GetTickInterval() * gF_CounterSpeed[client];
		}
	}
	else
	{ //TAS Status must be PAUSED to use this function
		Shavit_PrintToChat(client, "sm_minusone can only be used when TAS is Paused!");
	}
	return Plugin_Handled;
}

public Action Command_TASMenu(int client, int args)
{
	gB_TASMenu[client] = !gB_TASMenu[client];
	return Plugin_Handled;
}

public Action Command_TASHelp(int client, int args)
{
	PrintToChat(client, "TAS Guide:\nRecommended Binds:\nbind mwheelup sm_minusone\nbind mwheeldown sm_plusone\nbind mouse1 +rewind\nbind mouse2 +fastforward\n\nOther Commands:\n+autostrafer - When bound hold to use wigglehack\n!tasmenu - Toggles TAS Menu");
	return Plugin_Handled;
}

public Action CommandListener_TAS(int client, const char[] command, int args)
{
	gB_TASMenu[client] = true;
	return Plugin_Continue;
}

public Action CommandListener_JoinTeam(int client, const char[] command, int args)
{
	if(gB_TAS[client])
	{
		gI_Status[client] = RUN;
		gF_TASTime[client] = 0.0;
		gI_IndexCounter[client] = 0;
		FakeClientCommandEx(client, "sm_r");
	}
	return Plugin_Continue;
}

public Action CommandListener_PlusRewind(int client, const char[] command, int args)
{
	if(!gB_TAS[client])
	{
		return Plugin_Continue;
	}
	gI_Status[client] = BACKWARD;
	return Plugin_Handled;
}

public Action CommandListener_PlusForward(int client, const char[] command, int args)
{
	if(!gB_TAS[client])
	{
		return Plugin_Continue;
	}
	gI_Status[client] = FORWARD;
	return Plugin_Handled;
}

public Action CommandListener_MinusRewindOrForward(int client, const char[] command, int args)
{
	if(!gB_TAS[client])
	{
		return Plugin_Continue;
	}
	gI_Status[client] = PAUSED;
	return Plugin_Handled;
}

public void OnClientPutInServer(int client)
{
	
	if(gA_Frames[client] != INVALID_HANDLE)
	{
		ClearArray(gA_Frames[client]);
	}
	else
	{
		gA_Frames[client] = CreateArray(11, 0);
	}

	gF_CounterSpeed[client] = 1.0;
	gF_TASTime[client] = 0.0;
	gF_TimeScale[client] = 1.0;
	gI_Status[client] = RUN;
	gB_TASMenu[client] = true;
	gB_AutoStrafeEnabled[client] = false;
	gB_Strafing[client] = false;
}


float GetClientVelo(int client)
{
	float vVel[3];
	
	vVel[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
	vVel[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
	
	
	return GetVectorLength(vVel);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsValidClient(client, true) && gB_TAS[client])
	{
		DrawPanel(client);
	
		if(!gB_TAS[client])
		{
			return Plugin_Continue;
		}

		if(Shavit_GetTimerStatus(client) != Timer_Running)
		{
			return Plugin_Continue;
		}
		else if(IsPlayerAlive(client) && !IsFakeClient(client))
		{
			if(gI_Status[client] == RUN)
			{ // Record Frames
				SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", gF_TimeScale[client]);
				float fTimescale = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
				gF_TimeScaleTicksPassed[client] += fTimescale;
				gF_TrueVel[client] = GetClientVelo(client);

				float diff = angles[1] - gF_LastAngle[client];
				if (diff > 180)
				{
					diff -= 360;
				}
				else if(diff < -180)
				{
					diff += 360;
				}
				/*
							AUTO STRAFER START
														*/
				if(buttons & IN_FORWARD && vel[0] <= 50.0)
				{
					vel[0] = 450.0;
				}

				float yaw_change = 0.0;
				if(vel[0] > 50.0)
				{
					yaw_change = 30.0 * FloatAbs(30.0 / vel[0]);
				}

				if (gB_AutoStrafeEnabled[client] == true && Shavit_GetTimerStatus(client) == Timer_Running && gB_TAS[client] && !(GetEntityFlags(client) & FL_ONGROUND) && (GetEntityMoveType(client) != MOVETYPE_NOCLIP) && !(buttons & IN_FORWARD) && !(buttons & IN_BACK) && !(buttons & IN_MOVELEFT) && !(buttons & IN_MOVERIGHT))
				{
					if(diff < 0)
					{
						angles[1] += yaw_change;
						//buttons |= IN_MOVERIGHT;
						vel[1] = gF_SideMove;
					}
					else if(diff > 0)
					{
						angles[1] -= yaw_change;
						//buttons |= IN_MOVELEFT;
						vel[1] = gF_SideMove * -1.0;
					}
				}
				/*
							AUTO STRAFER END
														*/

				/*
							WIGGLEHACK START
														*/
				if (gB_Strafing[client] == true && Shavit_GetTimerStatus(client) == Timer_Running && gB_TAS[client] && !(GetEntityFlags(client) & FL_ONGROUND) && (GetEntityMoveType(client) != MOVETYPE_NOCLIP) && !(buttons & IN_FORWARD) && !(buttons & IN_BACK) && !(buttons & IN_MOVELEFT) && !(buttons & IN_MOVERIGHT))
				{
					if(gF_TimeScaleTicksPassed[client] >= 1.0)
					{
						//Don't subtract 1 from gF_TimeScaleTicksPassed[client] because it happens later and this code won't always run depending on if wiggle hack is on.

						if ((GetEntityFlags(client) & FL_ONGROUND) == 0 && (GetEntityMoveType(client) != MOVETYPE_NOCLIP))
						{
							if (!(gF_TrueVel[client] == 0.0))
							{
								flYawBhop[client] = 0.0;
								float x = 30.0;
								float y = gF_TrueVel[client];
								float z = x/y;
								z = FloatAbs(z);
								flYawBhop[client] = x * z;
							}
						
							if (gB_DirIsRight[client] == true)
							{
								angles[1] += flYawBhop[client];
								//buttons |= ~IN_MOVERIGHT;
								gB_DirIsRight[client] = false;
								vel[gI_StrafeAxis[client]] = gF_SideMove;
							}
							else
							{
								angles[1] -= flYawBhop[client];
								//buttons |= ~IN_MOVELEFT;
								gB_DirIsRight[client] = true;
								vel[gI_StrafeAxis[client]] = gF_SideMove * -1.0;
							}
						}
					}
				}
				/*
							WIGGLEHACK END
														*/

				if(gF_TimeScaleTicksPassed[client] >= 1.0)
				{
					gF_TimeScaleTicksPassed[client] -= 1.0;

					gF_TASTime[client] += GetTickInterval();

					int framenum = GetArraySize(gA_Frames[client])+1;
					if(gI_IndexCounter[client] != framenum-2)
					{
						//UnPaused in diff tick
						framenum = gI_IndexCounter[client]+1;
					}
					ResizeArray(gA_Frames[client], framenum);
					
					float lpos[3];
					float lang[3];
					float vVel[3];

					GetEntPropVector(client, Prop_Send, "m_vecOrigin", lpos);
					GetClientEyeAngles(client, lang);
					GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", vVel);

					SetArrayCell(gA_Frames[client], framenum-1, lpos[0], 0);
					SetArrayCell(gA_Frames[client], framenum-1, lpos[1], 1);
					SetArrayCell(gA_Frames[client], framenum-1, lpos[2], 2);
					SetArrayCell(gA_Frames[client], framenum-1, lang[0], 3);
					SetArrayCell(gA_Frames[client], framenum-1, lang[1], 4);
					SetArrayCell(gA_Frames[client], framenum-1, buttons, 5);
					SetArrayCell(gA_Frames[client], framenum-1, GetEntityFlags(client), 6);
					SetArrayCell(gA_Frames[client], framenum-1, GetEntityMoveType(client), 7);
					SetArrayCell(gA_Frames[client], framenum-1, vVel[0], 8);
					SetArrayCell(gA_Frames[client], framenum-1, vVel[1], 9);
					SetArrayCell(gA_Frames[client], framenum-1, vVel[2], 10);
					gI_IndexCounter[client] = framenum-1;
					gF_IndexCounter[client] = framenum-1.0;
				}
				else if(!(GetEntityFlags(client) & FL_ONGROUND))
				{
					vel[0] = 0.0;
					vel[1] = 0.0;
				}

				// Fix boosters
				if(GetEntityFlags(client) & FL_BASEVELOCITY)
				{
					float vBaseVel[3];
					GetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", vBaseVel);
					
					if(vBaseVel[2] > 0)
					{
						vBaseVel[2] *= 1.0 / GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
					}
					
					SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", vBaseVel);
				}
			}
			else if(gI_Status[client] == PAUSED)
			{
				if(!(gI_LastButtons[client] & IN_JUMP) && (buttons & IN_JUMP))
				{
					gI_Status[client] = RUN;
					ResumePlayer(client);
				}
				else
				{
					vel[0] = 0.0;
					vel[1] = 0.0;
					vel[2] = 0.0;
					int frameSize = GetArraySize(gA_Frames[client]);
					int framenum = gI_IndexCounter[client];
					if(frameSize > 1 && framenum > 1)
					{
						float fAng[3];
						fAng[0] = GetArrayCell(gA_Frames[client], framenum, 3);
						fAng[1] = GetArrayCell(gA_Frames[client], framenum, 4);
						fAng[2] = 0.0;
						
						float pos[3];
						pos[0] = GetArrayCell(gA_Frames[client], framenum, 0);
						pos[1] = GetArrayCell(gA_Frames[client], framenum, 1);
						pos[2] = GetArrayCell(gA_Frames[client], framenum, 2);

						TeleportEntity(client, pos, fAng, view_as<float>({0.0, 0.0, 0.0}));
						//gF_TASTime[client] -= GetTickInterval();

						if(GetArrayCell(gA_Frames[client], framenum, 6) & FL_DUCKING)
						{
							SetEntProp(client, Prop_Send, "m_bDucked", true);
							SetEntProp(client, Prop_Send, "m_bDucking", true);
							buttons |= IN_DUCK;
						}
						else
						{
							SetEntProp(client, Prop_Send, "m_bDucked", false);
							SetEntProp(client, Prop_Send, "m_bDucking", false);
						}

						SetEntityFlags(client, GetArrayCell(gA_Frames[client], framenum, 6));
					}

					if(GetEntityFlags(client) & FL_ONGROUND)
					{
						buttons &= ~IN_JUMP;
					}
				}
			}
			else if(gI_Status[client] == BACKWARD)
			{
				vel[0] = 0.0;
				vel[1] = 0.0;
				vel[2] = 0.0;
				int frameSize = GetArraySize(gA_Frames[client]);
				int framenum = gI_IndexCounter[client];
				if(frameSize > 1 && framenum > 2)
				{
					float fAng[3];
					fAng[0] = GetArrayCell(gA_Frames[client], framenum, 3);
					fAng[1] = GetArrayCell(gA_Frames[client], framenum, 4);
					fAng[2] = 0.0;
					
					float pos2[3];
					pos2[0] = GetArrayCell(gA_Frames[client], framenum, 0);
					pos2[1] = GetArrayCell(gA_Frames[client], framenum, 1);
					pos2[2] = GetArrayCell(gA_Frames[client], framenum, 2);

					float pos[3];
					pos[0] = GetArrayCell(gA_Frames[client], framenum-1, 0);
					pos[1] = GetArrayCell(gA_Frames[client], framenum-1, 1);
					pos[2] = GetArrayCell(gA_Frames[client], framenum-1, 2);

					float fVel[3];
					MakeVectorFromPoints(pos2, pos, fVel);

					for (int i = 0; i < 3; i++)
					{
						fVel[i] *= RoundToFloor(gF_TickRate);
					}

					TeleportEntity(client, pos, fAng, fVel);

					gF_IndexCounter[client] -= gF_CounterSpeed[client];
					if(IsRound(gF_IndexCounter[client]))
					{
						gI_IndexCounter[client]--;
					}
					gF_TASTime[client] -= GetTickInterval() * gF_CounterSpeed[client];
				}
				else if(frameSize > 1)
				{
					gI_Status[client] = PAUSED;
				}
			}
			else if(gI_Status[client] == FORWARD)
			{
				vel[0] = 0.0;
				vel[1] = 0.0;
				vel[2] = 0.0;
				int frameSize = GetArraySize(gA_Frames[client]);
				int framenum = gI_IndexCounter[client];
				if(frameSize > 1 && framenum < frameSize-1)
				{
					float fAng[3];
					fAng[0] = GetArrayCell(gA_Frames[client], framenum, 3);
					fAng[1] = GetArrayCell(gA_Frames[client], framenum, 4);
					fAng[2] = 0.0;
					
					float pos2[3];
					pos2[0] = GetArrayCell(gA_Frames[client], framenum, 0);
					pos2[1] = GetArrayCell(gA_Frames[client], framenum, 1);
					pos2[2] = GetArrayCell(gA_Frames[client], framenum, 2);

					float pos[3];
					pos[0] = GetArrayCell(gA_Frames[client], framenum-1, 0);
					pos[1] = GetArrayCell(gA_Frames[client], framenum-1, 1);
					pos[2] = GetArrayCell(gA_Frames[client], framenum-1, 2);

					float fVel[3];
					MakeVectorFromPoints(pos, pos2, fVel);

					for (int i = 0; i < 3; i++)
					{
						fVel[i] *= RoundToFloor(gF_TickRate);
					}

					TeleportEntity(client, pos2, fAng, fVel);

					gF_IndexCounter[client] += gF_CounterSpeed[client];
					if(IsRound(gF_IndexCounter[client]))
					{
						gI_IndexCounter[client]++;
					}
					gF_TASTime[client] += GetTickInterval() * gF_CounterSpeed[client];
				}
				else if(frameSize > 1)
				{
					gI_Status[client] = PAUSED;
				}
			}
			else
			{
				vel[0] = 0.0;
				vel[1] = 0.0;
				vel[2] = 0.0;
				gI_Status[client] = PAUSED;
			}
		}
	}
	gI_LastButtons[client] = buttons;
	gF_LastAngle[client] = angles[1];
	return Plugin_Continue;
}

bool DrawPanel(int client)
{
	if(!gB_TASMenu[client] || !gB_TAS[client])
		return false;
	Handle hPanel = CreatePanel();

	DrawPanelText(hPanel, "Tool Assisted Speedrun:\n ");
	if(gI_Status[client] == PAUSED)
		DrawPanelItem(hPanel, "Resume");
	else
		DrawPanelItem(hPanel, "Pause");

	if(gI_Status[client] != BACKWARD)
		DrawPanelItem(hPanel, "+rewind");
	else
		DrawPanelItem(hPanel, "-rewind");

	if(gI_Status[client] != FORWARD)
		DrawPanelItem(hPanel, "+fastforward");
	else
		DrawPanelItem(hPanel, "-fastforward");

	char sBuffer[256];
	FormatEx(sBuffer, sizeof(sBuffer), "Timescale: %.01f", gF_TimeScale[client]);
	DrawPanelItem(hPanel, sBuffer);
	/* FormatEx(sBuffer, sizeof(sBuffer), "Edit Speed: %.01f", gF_CounterSpeed[client]);
	DrawPanelItem(hPanel, sBuffer); */

	DrawPanelText(hPanel, " ");

	SetPanelCurrentKey(hPanel, 5);
	FormatEx(sBuffer, sizeof(sBuffer), "Toggle autostrafe %s", gB_AutoStrafeEnabled[client]?"[ON]":"[OFF]");
	DrawPanelItem(hPanel, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "Toggle wigglehack %s", gB_Strafing[client]?"[ON]":"[OFF]");
	DrawPanelItem(hPanel, sBuffer);
	
	DrawPanelText(hPanel, " ");
	DrawPanelText(hPanel, "----------------------------");
	DrawPanelText(hPanel, " ");

	SetPanelCurrentKey(hPanel, 8);
	DrawPanelItem(hPanel, "Restart");
	DrawPanelItem(hPanel, "Exit");
	SendPanelToClient(hPanel, client, Panel_Handler, MENU_TIME_FOREVER);
	return true;
}

public int Panel_Handler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!gB_TAS[param1])
		{
			gB_TASMenu[param1] = false;
			return;
		}
		if(Shavit_GetTimerStatus(param1) == Timer_Running)
		{
			switch(param2)
			{
				case 1:
				{
					if(gI_Status[param1] == PAUSED)
					{
						gI_Status[param1] = RUN;
						ResumePlayer(param1);
					}
					else
					{
						if(Shavit_InsideZone(param1, Zone_Start, -1))
						{
							return;
						}

						gI_Status[param1] = PAUSED;
					}
				}
				case 2:
				{
					if(Shavit_InsideZone(param1, Zone_Start, -1))
						return;

					if(gI_Status[param1] != BACKWARD)
					{
						gI_Status[param1] = BACKWARD;
					}
					else
					{
						//ResumePlayer(param1);
						//gI_Status[param1] = RUN;
						gI_Status[param1] = PAUSED;
					}
				}
				case 3:
				{
					if(Shavit_InsideZone(param1, Zone_Start, -1))
					{
						return;
					}

					if(gI_Status[param1] != FORWARD)
					{
						gI_Status[param1] = FORWARD;
					}
					else
					{
						//ResumePlayer(param1);
						//gI_Status[param1] = RUN;
						gI_Status[param1] = PAUSED;
					}
				}
				/* case 4:
				{
					gF_IndexCounter[param1] = 1.0 * RoundToFloor(gF_IndexCounter[param1]);
					gF_CounterSpeed[param1] += 1.0;
					if(gF_CounterSpeed[param1] >= 4.0)
					{
						gF_CounterSpeed[param1] = 1.0;
					}
				} */
				case 4:
				{
					if(!Shavit_InsideZone(param1, Zone_Start, -1) && gI_Status[param1] == RUN)
					{
						Shavit_PrintToChat(param1, "Timescale can only be updated when paused or inside the start zone!");
						return;
					}

					gF_TimeScale[param1] += 0.1;
					if(gF_TimeScale[param1] >= 1.1)
					{
						gF_TimeScale[param1] = 0.1;
					}
		
					SetEntPropFloat(param1, Prop_Send, "m_flLaggedMovementValue", gF_TimeScale[param1]);
				}
				case 5:
				{
					gB_AutoStrafeEnabled[param1] = !gB_AutoStrafeEnabled[param1];
				}
				case 6:
				{
					gB_Strafing[param1] = !gB_Strafing[param1];
				}
				case 8:
				{
					gI_Status[param1] = RUN;
					gF_TASTime[param1] = 0.0;
					gI_IndexCounter[param1] = 0;
					FakeClientCommandEx(param1, "sm_r"); //TODO: Check track, if bonus use sm_b
				}
				case 9:
				{
					gB_TASMenu[param1] = false;
					Shavit_PrintToChat(param1, "Type !tasmenu to reopen the menu.");
				}
			}
		}
	}
}

public void ResumePlayer(int client)
{
	int frameSize = GetArraySize(gA_Frames[client]);
	int framenum = gI_IndexCounter[client];
	if(frameSize > 1 && framenum > 1)
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

		float fAng[3];
		fAng[0] = GetArrayCell(gA_Frames[client], framenum, 3);
		fAng[1] = GetArrayCell(gA_Frames[client], framenum, 4);
		fAng[2] = 0.0;
		
		float pos2[3];
		pos2[0] = GetArrayCell(gA_Frames[client], framenum, 0);
		pos2[1] = GetArrayCell(gA_Frames[client], framenum, 1);
		pos2[2] = GetArrayCell(gA_Frames[client], framenum, 2);

		float pos[3];
		pos[0] = GetArrayCell(gA_Frames[client], framenum-1, 0);
		pos[1] = GetArrayCell(gA_Frames[client], framenum-1, 1);
		pos[2] = GetArrayCell(gA_Frames[client], framenum-1, 2);
		
		float fVel[3];
		fVel[0] = GetArrayCell(gA_Frames[client], framenum, 8);
		fVel[1] = GetArrayCell(gA_Frames[client], framenum, 9);
		fVel[2] = GetArrayCell(gA_Frames[client], framenum, 10);

		TeleportEntity(client, pos2, fAng, fVel);

		if(GetArrayCell(gA_Frames[client], framenum, 6) & FL_DUCKING)
		{
			SetEntProp(client, Prop_Send, "m_bDucked", true);
			SetEntProp(client, Prop_Send, "m_bDucking", true);
		}
		else
		{
			SetEntProp(client, Prop_Send, "m_bDucked", false);
			SetEntProp(client, Prop_Send, "m_bDucking", false);
		}

		SetEntityFlags(client, GetArrayCell(gA_Frames[client], framenum, 6));
	}
}

bool IsRound(float num)
{
	return RoundToFloor(num) == num;
}

public void Shavit_OnRestart(int client, int track)
{
	if(gB_TAS[client])
	{
		gI_Status[client] = RUN;
		gF_TASTime[client] = 0.0;
		gI_IndexCounter[client] = 0;
	}
}


public Action Shavit_OnStart(int client)
{
	if(gI_Status[client] == RUN && gB_TAS[client])
	{
		gF_TASTime[client] = 0.0;
		gI_IndexCounter[client] = 0;
		ClearArray(gA_Frames[client]);
	}
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity)
{
	if(gB_TAS[client])
	{
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", gF_TimeScale[client]);
	}
}

public void Shavit_OnFinish_Post(int client)
{
	if(gB_TAS[client])
	{
		gI_Status[client] = RUN;
		gF_TASTime[client] = 0.0;
		gI_IndexCounter[client] = 0;
	}
}

public Action Shavit_OnFinishPre(int client, timer_snapshot_t snapshot)
{
	if(gB_TAS[client])
	{
		//Edit time to equal the gF_TASTime[client]
		snapshot.fCurrentTime = gF_TASTime[client];

		//Overwrite Replay Data with gA_Frames[client]
		Shavit_SetReplayData(client, view_as<ArrayList>(gA_Frames[client]));
	}
	return Plugin_Changed;
}

public void Shavit_OnTimeIncrement(int client, timer_snapshot_t snapshot, float &time, stylesettings_t stylesettings)
{
	//Update Time on each tick
	if(gB_TAS[client])
	{
		time = gF_TASTime[client] - snapshot.fCurrentTime;
	}
}