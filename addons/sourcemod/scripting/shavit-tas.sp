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
	version = "1.9.6",
	url = "https://hyps.dev/"
}

#define RUN 0
#define PAUSED 1
#define BACKWARD 2
#define FORWARD 3

ArrayList gA_Frames[MAXPLAYERS+1];
ConVar gCV_AirAccelerate;
EngineVersion g_Game;


bool gB_AutoStrafeEnabled[MAXPLAYERS+1] = {false,...};
bool gB_Strafing[MAXPLAYERS+1];
bool gB_TASMenu[MAXPLAYERS+1];
bool gB_TAS[MAXPLAYERS + 1];

float gF_AirSpeedCap = 30.0;
float gF_CounterSpeed[MAXPLAYERS+1];
float gF_IndexCounter[MAXPLAYERS+1];
float gF_LastAngle[MAXPLAYERS];
float gF_MaxMove;
float gF_Power[MAXPLAYERS + 1] = {1.0, ...};
float gF_SideMove;
float gF_TASTime[MAXPLAYERS+1];
float gF_TickRate;
float gF_TimeScaleTicksPassed[MAXPLAYERS+1];
float gF_TimeScale[MAXPLAYERS+1];

int gI_IndexCounter[MAXPLAYERS+1];
int gI_LastButtons[MAXPLAYERS+1];
int gI_Status[MAXPLAYERS+1];
int gI_SurfaceFrictionOffset;
int gI_Type[MAXPLAYERS + 1];


public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	
	if(g_Game != Engine_CSGO)
	{
		gF_SideMove = 400.0;
		gF_MaxMove = 400.0;
	}
	else
	{
		gF_SideMove = 450.0;
		gF_MaxMove = 450.0;
		ConVar sv_air_max_wishspeed = FindConVar("sv_air_max_wishspeed");
		sv_air_max_wishspeed.AddChangeHook(OnWishSpeedChanged);
		gF_AirSpeedCap = sv_air_max_wishspeed.FloatValue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}

	gCV_AirAccelerate = FindConVar("sv_airaccelerate");

	GameData gamedata = new GameData("tas.games");

	gI_SurfaceFrictionOffset = gamedata.GetOffset("m_surfaceFriction");
	delete gamedata;

	if(gI_SurfaceFrictionOffset <= 0)
	{
		LogError("[TAS] Invalid offset supplied, defaulting friction values");
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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_SetTASStrafe", Native_SetAutostrafe);
	CreateNative("Shavit_GetTASStrafe", Native_GetAutostrafe);
	CreateNative("Shavit_SetTASStrafeType", Native_SetType);
	CreateNative("Shavit_GetTASStrafeType", Native_GetType);
	CreateNative("Shavit_SetTASStrafePower", Native_SetPower);
	CreateNative("Shavit_GetTASStrafePower", Native_GetPower);

	RegPluginLibrary("tas");
	return APLRes_Success;
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
		DrawPanel(client);
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
		int iFrameSize = GetArraySize(gA_Frames[client]);
		int iFrameNumber = gI_IndexCounter[client];
		if(iFrameSize > 1 && iFrameNumber < iFrameSize-1)
		{
			float fAngle[3];
			fAngle[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 3);
			fAngle[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 4);
			fAngle[2] = 0.0;
			
			float fPosition2[3];
			fPosition2[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 0);
			fPosition2[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 1);
			fPosition2[2] = GetArrayCell(gA_Frames[client], iFrameNumber, 2);

			float fPosition[3];
			fPosition[0] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 0);
			fPosition[1] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 1);
			fPosition[2] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 2);

			float fVelocity[3];
			MakeVectorFromPoints(fPosition, fPosition2, fVelocity);

			for (int i = 0; i < 3; i++)
			{
				fVelocity[i] *= RoundToFloor(gF_TickRate);
			}

			TeleportEntity(client, fPosition2, fAngle, fVelocity);

			if(GetArrayCell(gA_Frames[client], iFrameNumber, 5) & IN_DUCK)
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
		int iFrameSize = GetArraySize(gA_Frames[client]);
		int iFrameNumber = gI_IndexCounter[client];
		if(iFrameSize > 1 && iFrameNumber > 2)
		{
			float fAngle[3];
			fAngle[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 3);
			fAngle[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 4);
			fAngle[2] = 0.0;
			
			float fPosition2[3];
			fPosition2[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 0);
			fPosition2[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 1);
			fPosition2[2] = GetArrayCell(gA_Frames[client], iFrameNumber, 2);

			float fPosition[3];
			fPosition[0] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 0);
			fPosition[1] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 1);
			fPosition[2] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 2);

			float fVelocity[3];
			MakeVectorFromPoints(fPosition2, fPosition, fVelocity);

			for (int i = 0; i < 3; i++)
			{
				fVelocity[i] *= RoundToFloor(gF_TickRate);
			}

			TeleportEntity(client, fPosition, fAngle, fVelocity);

			if(GetArrayCell(gA_Frames[client], iFrameNumber, 5) & IN_DUCK)
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
	if(gB_TASMenu[client])
	{
		DrawPanel(client);
	}
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
	DrawPanel(client);
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
	gI_Type[client] = Type_SurfOverride;
	gF_Power[client] = 1.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsValidClient(client, true) && gB_TAS[client])
	{

		if(!gB_TAS[client])
		{
			return Plugin_Continue;
		}

		DrawPanel(client);

		if(Shavit_GetTimerStatus(client) != Timer_Running)
		{
			return Plugin_Continue;
		}
		else if(IsPlayerAlive(client) && !IsFakeClient(client))
		{
			if(gI_Status[client] == RUN)
			{ // Record Frames
				//SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", gF_TimeScale[client]);
				float fTimescale = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
				gF_TimeScaleTicksPassed[client] += fTimescale;

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
						Huge amounts of credit to Kamay for this code!
						https://steamcommunity.com/id/xutaxkamay/
																		*/
				if (gB_Strafing[client] == true && Shavit_GetTimerStatus(client) == Timer_Running && gB_TAS[client] && !(GetEntityFlags(client) & FL_ONGROUND) && (GetEntityMoveType(client) != MOVETYPE_NOCLIP) && !(buttons & IN_FORWARD) && !(buttons & IN_BACK) && !(buttons & IN_MOVELEFT) && !(buttons & IN_MOVERIGHT))
				{
					if(gF_TimeScaleTicksPassed[client] >= 1.0)
					{
						//Don't subtract 1 from gF_TimeScaleTicksPassed[client] because it happens later and this code won't always run depending on if wiggle hack is on.
						bool bOnGround = !(buttons & IN_JUMP) && (GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") != -1);
						
						if (IsPlayerAlive(client) && !bOnGround && !(GetEntityMoveType(client) & MOVETYPE_LADDER) && (GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1))
						{
							if(!!(buttons & (IN_FORWARD | IN_BACK)))
							{
								return Plugin_Continue;
							}

							if(!!(buttons & (IN_MOVERIGHT | IN_MOVELEFT)))
							{
								if(gI_Type[client] == Type_Override)
								{
									return Plugin_Continue;
								}
								else if(gI_Type[client] == Type_SurfOverride && IsSurfing(client))
								{
									return Plugin_Continue;
								}
							}

							float fFowardMove, fSideMove;
							float fMaxSpeed = GetEntPropFloat(client, Prop_Data, "m_flMaxspeed");
							float fSurfaceFriction = 1.0;
							if(gI_SurfaceFrictionOffset > 0)
							{
								fSurfaceFriction = GetEntDataFloat(client, gI_SurfaceFrictionOffset);
								if(!(fSurfaceFriction == 0.25 || fSurfaceFriction == 1.0))
								{
									FindNewFrictionOffset(client);
								}
							}


							float fVelocity[3], flVelocity2D[2];

							GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);

							flVelocity2D[0] = fVelocity[0];
							flVelocity2D[1] = fVelocity[1];

							// PrintToChat(client, "%f", SquareRoot(flVelocity2D[0] * flVelocity2D[0] + flVelocity2D[1] * flVelocity2D[1]));

							GetIdealMovementsInAir(angles[1], flVelocity2D, fMaxSpeed, fSurfaceFriction, fFowardMove, fSideMove);

							float flAngleDifference = AngleNormalize(angles[1] - gF_LastAngle[client]);
							float flCurrentAngles = FloatAbs(flAngleDifference);


							// Right
							if (flAngleDifference < 0.0)
							{
								float flMaxDelta = GetMaxDeltaInAir(flVelocity2D, fMaxSpeed, fSurfaceFriction, true);
								vel[1] = gF_MaxMove;

								if (flCurrentAngles <= flMaxDelta * gF_Power[client])
								{
									vel[0] = fFowardMove * gF_MaxMove;
									vel[1] = fSideMove * gF_MaxMove;
								}
							}
							else if (flAngleDifference > 0.0)
							{
								float flMaxDelta = GetMaxDeltaInAir(flVelocity2D, fMaxSpeed, fSurfaceFriction, false);
								vel[1] = -gF_MaxMove;

								if (flCurrentAngles <= flMaxDelta * gF_Power[client])
								{
									vel[0] = fFowardMove * gF_MaxMove;
									vel[1] = fSideMove * gF_MaxMove;
								}
							}
							else
							{
								vel[0] = fFowardMove * gF_MaxMove;
								vel[1] = fSideMove * gF_MaxMove;
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

					int iFrameNumber = GetArraySize(gA_Frames[client])+1;
					if(gI_IndexCounter[client] != iFrameNumber-2)
					{
						//UnPaused in diff tick
						iFrameNumber = gI_IndexCounter[client]+1;
					}
					ResizeArray(gA_Frames[client], iFrameNumber);
					
					float fPosition[3];
					float fEyeAngles[3];
					float fVelocity[3];

					GetEntPropVector(client, Prop_Send, "m_vecOrigin", fPosition);
					GetClientEyeAngles(client, fEyeAngles);
					GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fVelocity);

					SetArrayCell(gA_Frames[client], iFrameNumber-1, fPosition[0], 0);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, fPosition[1], 1);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, fPosition[2], 2);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, fEyeAngles[0], 3);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, fEyeAngles[1], 4);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, buttons, 5);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, GetEntityFlags(client), 6);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, GetEntityMoveType(client), 7);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, fVelocity[0], 8);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, fVelocity[1], 9);
					SetArrayCell(gA_Frames[client], iFrameNumber-1, fVelocity[2], 10);
					gI_IndexCounter[client] = iFrameNumber-1;
					gF_IndexCounter[client] = iFrameNumber-1.0;
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
					int iFrameSize = GetArraySize(gA_Frames[client]);
					int iFrameNumber = gI_IndexCounter[client];
					if(iFrameSize > 1 && iFrameNumber > 1)
					{
						float fAngle[3];
						fAngle[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 3);
						fAngle[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 4);
						fAngle[2] = 0.0;
						
						float fPosition[3];
						fPosition[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 0);
						fPosition[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 1);
						fPosition[2] = GetArrayCell(gA_Frames[client], iFrameNumber, 2);

						TeleportEntity(client, fPosition, fAngle, view_as<float>({0.0, 0.0, 0.0}));
						//gF_TASTime[client] -= GetTickInterval();

						if(GetArrayCell(gA_Frames[client], iFrameNumber, 6) & FL_DUCKING)
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

						SetEntityFlags(client, GetArrayCell(gA_Frames[client], iFrameNumber, 6));
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
				int iFrameSize = GetArraySize(gA_Frames[client]);
				int iFrameNumber = gI_IndexCounter[client];
				if(iFrameSize > 1 && iFrameNumber > 2)
				{
					float fAngle[3];
					fAngle[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 3);
					fAngle[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 4);
					fAngle[2] = 0.0;
					
					float fPosition2[3];
					fPosition2[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 0);
					fPosition2[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 1);
					fPosition2[2] = GetArrayCell(gA_Frames[client], iFrameNumber, 2);

					float fPosition[3];
					fPosition[0] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 0);
					fPosition[1] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 1);
					fPosition[2] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 2);

					float fVelocity[3];
					MakeVectorFromPoints(fPosition2, fPosition, fVelocity);

					for (int i = 0; i < 3; i++)
					{
						fVelocity[i] *= RoundToFloor(gF_TickRate);
					}

					TeleportEntity(client, fPosition, fAngle, fVelocity);

					gF_IndexCounter[client] -= gF_CounterSpeed[client];
					if(IsRound(gF_IndexCounter[client]))
					{
						gI_IndexCounter[client]--;
					}
					gF_TASTime[client] -= GetTickInterval() * gF_CounterSpeed[client];
				}
				else if(iFrameSize > 1)
				{
					gI_Status[client] = PAUSED;
				}
			}
			else if(gI_Status[client] == FORWARD)
			{
				vel[0] = 0.0;
				vel[1] = 0.0;
				vel[2] = 0.0;
				int iFrameSize = GetArraySize(gA_Frames[client]);
				int iFrameNumber = gI_IndexCounter[client];
				if(iFrameSize > 1 && iFrameNumber < iFrameSize-1)
				{
					float fAngle[3];
					fAngle[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 3);
					fAngle[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 4);
					fAngle[2] = 0.0;
					
					float fPosition2[3];
					fPosition2[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 0);
					fPosition2[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 1);
					fPosition2[2] = GetArrayCell(gA_Frames[client], iFrameNumber, 2);

					float fPosition[3];
					fPosition[0] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 0);
					fPosition[1] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 1);
					fPosition[2] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 2);

					float fVelocity[3];
					MakeVectorFromPoints(fPosition, fPosition2, fVelocity);

					for (int i = 0; i < 3; i++)
					{
						fVelocity[i] *= RoundToFloor(gF_TickRate);
					}

					TeleportEntity(client, fPosition2, fAngle, fVelocity);

					gF_IndexCounter[client] += gF_CounterSpeed[client];
					if(IsRound(gF_IndexCounter[client]))
					{
						gI_IndexCounter[client]++;
					}
					gF_TASTime[client] += GetTickInterval() * gF_CounterSpeed[client];
				}
				else if(iFrameSize > 1)
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
	SendPanelToClient(hPanel, client, Panel_Handler, 1);

	delete hPanel;
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
					{
						return;
					}

					if(gI_Status[param1] != BACKWARD)
					{
						gI_Status[param1] = BACKWARD;
					}
					else
					{
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
		
					//SetEntPropFloat(param1, Prop_Send, "m_flLaggedMovementValue", gF_TimeScale[param1]);
					Shavit_SetClientTimescale(param1, gF_TimeScale[param1]);
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
					delete menu;
				}
			}
		}
	}
}

public void ResumePlayer(int client)
{
	int iFrameSize = GetArraySize(gA_Frames[client]);
	int iFrameNumber = gI_IndexCounter[client];
	if(iFrameSize > 1 && iFrameNumber > 1)
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

		float fAngle[3];
		fAngle[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 3);
		fAngle[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 4);
		fAngle[2] = 0.0;
		
		float fPosition2[3];
		fPosition2[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 0);
		fPosition2[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 1);
		fPosition2[2] = GetArrayCell(gA_Frames[client], iFrameNumber, 2);

		float fPosition[3];
		fPosition[0] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 0);
		fPosition[1] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 1);
		fPosition[2] = GetArrayCell(gA_Frames[client], iFrameNumber-1, 2);
		
		float fVelocity[3];
		fVelocity[0] = GetArrayCell(gA_Frames[client], iFrameNumber, 8);
		fVelocity[1] = GetArrayCell(gA_Frames[client], iFrameNumber, 9);
		fVelocity[2] = GetArrayCell(gA_Frames[client], iFrameNumber, 10);

		TeleportEntity(client, fPosition2, fAngle, fVelocity);

		if(GetArrayCell(gA_Frames[client], iFrameNumber, 6) & FL_DUCKING)
		{
			SetEntProp(client, Prop_Send, "m_bDucked", true);
			SetEntProp(client, Prop_Send, "m_bDucking", true);
		}
		else
		{
			SetEntProp(client, Prop_Send, "m_bDucked", false);
			SetEntProp(client, Prop_Send, "m_bDucking", false);
		}

		SetEntityFlags(client, GetArrayCell(gA_Frames[client], iFrameNumber, 6));
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
		//SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", gF_TimeScale[client]);
		Shavit_SetClientTimescale(client, gF_TimeScale[client]);
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

/*
		WIGGLEHACK START
		Huge amounts of credit to Kamay for this code!
		https://steamcommunity.com/id/xutaxkamay/
														*/

// doesn't exist in css so we have to cache the value
public void OnWishSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gF_AirSpeedCap = StringToFloat(newValue);
}

float AngleNormalize(float fAngle)
{
	if (fAngle > 180.0)
		fAngle -= 360.0;
	else if (fAngle < -180.0)
		fAngle += 360.0;

	return fAngle;
}

float Vec2DToYaw(float vec[2])
{
	float fYaw = 0.0;

	if (vec[0] != 0.0 || vec[1] != 0.0)
	{
		float vecNormalized[2];

		float flLength = SquareRoot(vec[0] * vec[0] + vec[1] * vec[1]);

		vecNormalized[0] = vec[0] / flLength;
		vecNormalized[1] = vec[1] / flLength;

		// Credits to Valve.
		fYaw = ArcTangent2(vecNormalized[1], vecNormalized[0]) * (180.0 / FLOAT_PI);
		fYaw = AngleNormalize(fYaw);
	}

	return fYaw;
}

void Solve2DMovementsVars(float vecWishDir[2], float vecForward[2], float vecRight[2], float &fForwardMove, float &fSideMove)
{

	float v = vecWishDir[0];
	float w = vecWishDir[1];
	float a = vecForward[0];
	float c = vecRight[0];
	float e = vecForward[1];
	float f = vecRight[1];

	float fDivide = (c * e - a * f);
	if(fDivide == 0.0)
	{
		fForwardMove = gF_MaxMove;
		fSideMove = 0.0;
	}
	else
	{
		fForwardMove = (c * w - f * v) / fDivide;
		fSideMove = (e * v - a * w) / fDivide;
	}
}

float GetThetaAngleInAir(float fVelocity[2], float fAirAccelerate, float fMaxSpeed, float fSurfaceFriction, float fFrameTime)
{

	float fAccelerationSpeed = fAirAccelerate * fMaxSpeed * fSurfaceFriction * fFrameTime;

	float fWantedDotProduct = gF_AirSpeedCap - fAccelerationSpeed;

	if (fWantedDotProduct > 0.0)
	{
		float fVelLength2D = SquareRoot(fVelocity[0] * fVelocity[0] + fVelocity[1] * fVelocity[1]);
		if(fVelLength2D == 0.0)
		{
			return 90.0;
		}
		float flCosTheta = fWantedDotProduct / fVelLength2D;

		if (flCosTheta > 1.0)
		{
			flCosTheta = 1.0;
		}
		else if(flCosTheta < -1.0)
		{
			flCosTheta = -1.0;
		}


		float fTheta = ArcCosine(flCosTheta) * (180.0 / FLOAT_PI);

		return fTheta;
	}
	else
	{
		return 90.0;
	}
}

float SimulateAirAccelerate(float fVelocity[2], float fWishedDirection[2], float fAirAccelerate, float fMaxSpeed, float fSurfaceFriction, float fFrameTime, float fVelocityOutput[2])
{
	float fCapWishSpeed = fMaxSpeed;

	// Cap speed
	if(fCapWishSpeed > gF_AirSpeedCap)
	{
		fCapWishSpeed = gF_AirSpeedCap;
	}

	// Determine veer amount
	float flCurrentSpeed = fVelocity[0] * fWishedDirection[0] + fVelocity[1] * fWishedDirection[1];

	// See how much to add
	float fAddSpeed = fCapWishSpeed - flCurrentSpeed;

	// If not adding any, done.
	if(fAddSpeed <= 0.0)
	{
		return;
	}

	// Determine acceleration speed after acceleration
	float fAccelerationSpeed = fAirAccelerate * fMaxSpeed * fFrameTime * fSurfaceFriction;

	// Cap it
	if(fAccelerationSpeed > fAddSpeed)
	{
		fAccelerationSpeed = fAddSpeed;
	}

	fVelocityOutput[0] = fVelocity[0] + fAccelerationSpeed * fWishedDirection[0];
	fVelocityOutput[1] = fVelocity[1] + fAccelerationSpeed * fWishedDirection[1];
}

// The idea is to get the maximum angle
float GetMaxDeltaInAir(float fVelocity[2], float fMaxSpeed, float fSurfaceFriction, bool bLeft)
{
	float fFrameTime = GetTickInterval();
	float fAirAccelerate = gCV_AirAccelerate.FloatValue;

	float fTheta = GetThetaAngleInAir(fVelocity, fAirAccelerate, fMaxSpeed, fSurfaceFriction, fFrameTime);

	// Convert velocity 2D to angle.
	float fYawVelocity = Vec2DToYaw(fVelocity);

	// Get the best yaw direction on the right.
	float fBestYawRight = AngleNormalize(fYawVelocity + fTheta);

	// Get the best yaw direction on the left.
	float fBestYawLeft = AngleNormalize(fYawVelocity - fTheta);

	float fTemp[3], VectorBestLeft3D[3], VectorBestRight3D[3];

	fTemp[0] = 0.0;
	fTemp[1] = fBestYawLeft;
	fTemp[2] = 0.0;

	GetAngleVectors(fTemp, VectorBestLeft3D, NULL_VECTOR, NULL_VECTOR);

	fTemp[0] = 0.0;
	fTemp[1] = fBestYawRight;
	fTemp[2] = 0.0;

	GetAngleVectors(fTemp, VectorBestRight3D, NULL_VECTOR, NULL_VECTOR);

	float vecBestRight[2], vecBestLeft[2];

	vecBestRight[0] = VectorBestRight3D[0];
	vecBestRight[1] = VectorBestRight3D[1];

	vecBestLeft[0] = VectorBestLeft3D[0];
	vecBestLeft[1] = VectorBestLeft3D[1];

	float fCalculateVelocityLeft[2], fCalculateVelocityRight[2];

	// Simulate air accelerate function in order to get the new max gain possible on both side.
	SimulateAirAccelerate(fVelocity, vecBestLeft, fAirAccelerate, fMaxSpeed, fFrameTime, fSurfaceFriction, fCalculateVelocityLeft);
	SimulateAirAccelerate(fVelocity, vecBestRight, fAirAccelerate, fMaxSpeed, fFrameTime, fSurfaceFriction, fCalculateVelocityRight);

	float fNewBestYawLeft = Vec2DToYaw(fCalculateVelocityLeft);
	float fNewBestYawRight = Vec2DToYaw(fCalculateVelocityRight);

	// Then get the difference in order to find the maximum angle.
	if (bLeft)
	{
		return FloatAbs(AngleNormalize(fYawVelocity - fNewBestYawLeft));
	}
	else
	{
		return FloatAbs(AngleNormalize(fYawVelocity - fNewBestYawRight));
	}

	// Do an estimate otherwhise.
	// return FloatAbs(AngleNormalize(fNewBestYawLeft - fNewBestYawRight) / 2.0);
}

void GetIdealMovementsInAir(float fYawWantedDirection, float fVelocity[2], float fMaxSpeed, float fSurfaceFriction, float &fForwardMove, float &fSideMove, bool bPreferRight = true)
{
	float fAirAccelerate = gCV_AirAccelerate.FloatValue;
	float fFrameTime = GetTickInterval();
	float fYawVelocity = Vec2DToYaw(fVelocity);

	// Get theta angle
	float fTheta = GetThetaAngleInAir(fVelocity, fAirAccelerate, fMaxSpeed, fSurfaceFriction, fFrameTime);

	// Get the best yaw direction on the right.
	float fBestYawRight = AngleNormalize(fYawVelocity + fTheta);

	// Get the best yaw direction on the left.
	float fBestYawLeft = AngleNormalize(fYawVelocity - fTheta);

	float vBestLeftDirection[3], vBestRightDirection[3];
	float TemporaryAngle[3];

	TemporaryAngle[0] = 0.0;
	TemporaryAngle[1] = fBestYawRight;
	TemporaryAngle[2] = 0.0;

	GetAngleVectors(TemporaryAngle, vBestRightDirection, NULL_VECTOR, NULL_VECTOR);

	TemporaryAngle[0] = 0.0;
	TemporaryAngle[1] = fBestYawLeft;
	TemporaryAngle[2] = 0.0;

	GetAngleVectors(TemporaryAngle, vBestLeftDirection, NULL_VECTOR, NULL_VECTOR);

	// Our wanted direction.
	float vBestVectorDirection[2];

	// Let's follow the most the wanted direction now with max possible gain.
	float fYawDifference = AngleNormalize(fYawWantedDirection - fYawVelocity);

	if (fYawDifference > 0.0)
	{
		vBestVectorDirection[0] = vBestRightDirection[0];
		vBestVectorDirection[1] = vBestRightDirection[1];
	}
	else if(fYawDifference < 0.0)
	{
		vBestVectorDirection[0] = vBestLeftDirection[0];
		vBestVectorDirection[1] = vBestLeftDirection[1];
	}
	else
	{
		// Going straight.
		if (bPreferRight)
		{
			vBestVectorDirection[0] = vBestRightDirection[0];
			vBestVectorDirection[1] = vBestRightDirection[1];
		}
		else
		{
			vBestVectorDirection[0] = vBestLeftDirection[0];
			vBestVectorDirection[1] = vBestLeftDirection[1];
		}
	}

	float vecForwardWantedDir3D[3], vecRightWantedDir3D[3];
	float vecForwardWantedDir[2], vecRightWantedDir[2];

	TemporaryAngle[0] = 0.0;
	TemporaryAngle[1] = fYawWantedDirection;
	TemporaryAngle[2] = 0.0;

	// Convert our yaw wanted direction to vectors.
	GetAngleVectors(TemporaryAngle, vecForwardWantedDir3D, vecRightWantedDir3D, NULL_VECTOR);

	vecForwardWantedDir[0] = vecForwardWantedDir3D[0];
	vecForwardWantedDir[1] = vecForwardWantedDir3D[1];

	vecRightWantedDir[0] = vecRightWantedDir3D[0];
	vecRightWantedDir[1] = vecRightWantedDir3D[1];

	// Solve the movement variables from our wanted direction and the best gain direction.
	Solve2DMovementsVars(vBestVectorDirection, vecForwardWantedDir, vecRightWantedDir, fForwardMove, fSideMove);

	float fLengthMovements = SquareRoot(fForwardMove * fForwardMove + fSideMove * fSideMove);

	if(fLengthMovements != 0.0)
	{
		fForwardMove /= fLengthMovements;
		fSideMove /= fLengthMovements;
	}
}

void FindNewFrictionOffset(int client)
{
	for(int i = 1; i <= 128; ++i)
	{
		float friction = GetEntDataFloat(client, gI_SurfaceFrictionOffset + i);
		if(friction == 0.25 || friction == 1.0)
		{
			gI_SurfaceFrictionOffset += i;

			LogError("[TAS] Current friction offset is out of date. Please update to new offset: %i", gI_SurfaceFrictionOffset);
			break;
		}
	}
}

public any Native_SetAutostrafe(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool value = GetNativeCell(2);
	gB_Strafing[client] = value;
	
	return 0;
}

public any Native_GetAutostrafe(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	return gB_Strafing[client];
}

public any Native_SetType(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int value = GetNativeCell(2);
	gI_Type[client] = value;

	return 0;
}

public any Native_GetType(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	return gI_Type[client];
}

public any Native_SetPower(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	float value = GetNativeCell(2);
	gF_Power[client] = value;

	return 0;
}

public any Native_GetPower(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gF_Power[client];
}

// stocks
// taken from shavit's oryx
stock bool IsSurfing(int client)
{
	float fPosition[3];
	GetClientAbsOrigin(client, fPosition);

	float fEnd[3];
	fEnd = fPosition;
	fEnd[2] -= 64.0;

	float fMins[3];
	GetEntPropVector(client, Prop_Send, "m_vecMins", fMins);

	float fMaxs[3];
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", fMaxs);

	Handle hTR = TR_TraceHullFilterEx(fPosition, fEnd, fMins, fMaxs, MASK_PLAYERSOLID, TRFilter_NoPlayers, client);

	if(TR_DidHit(hTR))
	{
		float fNormal[3];
		TR_GetPlaneNormal(hTR, fNormal);

		delete hTR;

		// If the plane normal's Z axis is 0.7 or below (alternatively, -0.7 when upside-down) then it's a surf ramp.
		// https://mxr.alliedmods.net/hl2sdk-css/source/game/server/physics_main.cpp#1059

		return (-0.7 <= fNormal[2] <= 0.7);
	}

	delete hTR;

	return false;
}

public bool TRFilter_NoPlayers(int entity, int mask, any data)
{
	return (entity != view_as<int>(data) || (entity < 1 || entity > MaxClients));
}
/*
		WIGGLEHACK END
							*/
