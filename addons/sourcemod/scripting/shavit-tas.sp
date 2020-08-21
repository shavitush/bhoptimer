#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <shavit>
#include <convar_class>
#include <dhooks>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "[shavit] TAS Style",
	author = "Charles_(hypnos), SilentStrafe by Kamay",
	description = "TAS Style for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://hyps.dev/"
}

// #define REAL_VERSION 2.7 // This real version is for hypnos ;) b/c KiD wants to take away my version number ;(

#define RUN 0
#define PAUSED 1
#define BACKWARD 2
#define FORWARD 3

ArrayList gA_Frames[MAXPLAYERS+1];
//ArrayList gA_PreFrames[MAXPLAYERS+1];

ConVar gCV_AirAccelerate;
EngineVersion g_Game;
Convar gCV_AutoFind_Offset;
ConVar sv_client_predict = null;
MoveType gMT_LastMoveType[MAXPLAYERS+1];

bool gB_AutoStrafeEnabled[MAXPLAYERS+1] = {false,...};
bool gB_SilentStrafe[MAXPLAYERS+1];
bool gB_ProcessFrame[MAXPLAYERS+1];
bool gB_TAS[MAXPLAYERS+1];

float gF_AirSpeedCap = 30.0;
float gF_CounterSpeed[MAXPLAYERS+1];
float gF_IndexCounter[MAXPLAYERS+1];
float gF_LastAngle[MAXPLAYERS];
float gF_MaxMove;
float gF_Power[MAXPLAYERS+1] = {1.0, ...};
float gF_TASTime[MAXPLAYERS+1];
float gF_TickRate;
float gF_Timescale[MAXPLAYERS+1];
float gF_NextFrameTime[MAXPLAYERS+1];

int gI_IndexCounter[MAXPLAYERS+1];
int gI_CPIndex[MAXPLAYERS+1];
int gI_LastButtons[MAXPLAYERS+1];
int gI_Status[MAXPLAYERS+1];
int gI_SurfaceFrictionOffset;
int gI_Type[MAXPLAYERS+1];
int gI_Track[MAXPLAYERS+1];
int gI_PreFrameCount[MAXPLAYERS+1];

enum struct framedata_t
{
	float fPosition[3];
	float fEyeAngles[2];
	int buttons;
	int iFlags;
	MoveType movetype;
	float fVelocity[3];
	bool bDucked;
	bool bDucking;
	float fDuckTime; // m_flDuckAmount in csgo
	float fDuckSpeed; // m_flDuckSpeed in csgo; doesn't exist in css
	float fTime; //Really only used for checkpoints...
}

public void OnPluginStart()
{
	//For Timescale & SupressViewpunch
	LoadDHooks();

	g_Game = GetEngineVersion();
	
	if(g_Game != Engine_CSGO)
	{
		gF_MaxMove = 400.0;
	}
	else
	{
		gF_MaxMove = 450.0;
		ConVar sv_air_max_wishspeed = FindConVar("sv_air_max_wishspeed");
		sv_air_max_wishspeed.AddChangeHook(OnWishSpeedChanged);
		gF_AirSpeedCap = sv_air_max_wishspeed.FloatValue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			ResetTASData(i);
		}
	}

	sv_client_predict = FindConVar("sv_client_predict");
	sv_client_predict.IntValue = -1;

	gCV_AirAccelerate = FindConVar("sv_airaccelerate");
	gCV_AutoFind_Offset = new Convar("tas_find_offsets", "1", "Attempt to autofind offsets", _, true, 0.0, true, 1.0);

	Convar.AutoExecConfig();

	GameData gamedata = new GameData("shavit.games");

	gI_SurfaceFrictionOffset = gamedata.GetOffset("m_surfaceFriction");
	delete gamedata;

	if(gI_SurfaceFrictionOffset == -1)
	{
		LogError("[TAS] Invalid offset supplied, defaulting friction values");
	}
	else
	{
		if(g_Game == Engine_CSGO)
		{		
			gI_SurfaceFrictionOffset = FindSendPropInfo("CBasePlayer", "m_ubEFNoInterpParity") - gI_SurfaceFrictionOffset;
		}
		else if(g_Game == Engine_CSS)
		{
			gI_SurfaceFrictionOffset += FindSendPropInfo("CBasePlayer", "m_szLastPlaceName");
		}
		else
		{
			SetFailState("This plugin is for CSGO/CSS only.");
		}
	}

	AddCommandListener(CommandListener_PlusRewind, "+rewind");
	AddCommandListener(CommandListener_PlusForward, "+forward");
	AddCommandListener(CommandListener_MinusRewindOrForward, "-rewind");
	AddCommandListener(CommandListener_MinusRewindOrForward, "-forward");
	AddCommandListener(CommandListener_TAS, "sm_tas");
	RegConsoleCmd("sm_tasmenu", Command_TASMenu);
	RegConsoleCmd("sm_tashelp", Command_TASHelp);

	gF_TickRate = (1.0 / GetTickInterval());

	RegConsoleCmd("sm_plusone", Command_PlusOne, "TAS adjustment +1 tick");
	RegConsoleCmd("sm_minusone", Command_MinusOne, "TAS adjustment -1 tick");
	
	RegConsoleCmd("+autostrafer", Command_PlusStrafer, "Toggle wigglehack");
	RegConsoleCmd("-autostrafer", Command_MinusStrafer, "Toggle wigglehack");

	RegConsoleCmd("sm_tascpadd", Command_CPAdd, "TAS add checkpoint");
	RegConsoleCmd("sm_tascpdelete", Command_CPDelete, "TAS delete checkpoint");
	RegConsoleCmd("sm_tascptp", Command_CPTP, "TAS teleport to checkpoint");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_SetTASStrafe", Native_SetAutostrafe);
	CreateNative("Shavit_GetTASStrafe", Native_GetAutostrafe);
	CreateNative("Shavit_SetTASStrafeType", Native_SetType);
	CreateNative("Shavit_GetTASStrafeType", Native_GetType);
	CreateNative("Shavit_SetTASStrafePower", Native_SetPower);
	CreateNative("Shavit_GetTASStrafePower", Native_GetPower);

	RegPluginLibrary("shavit-tas");
	return APLRes_Success;
}

//Thanks to KiD Fearless for the Timescale Method
void LoadDHooks()
{
	// totally not ripped from rngfix :)
	Handle gamedataConf = LoadGameConfigFile("shavit.games");

	if(gamedataConf == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	// CreateInterface
	// Thanks SlidyBat and ici
	StartPrepSDKCall(SDKCall_Static);
	if(!PrepSDKCall_SetFromConf(gamedataConf, SDKConf_Signature, "CreateInterface"))
	{
		SetFailState("Failed to get CreateInterface");
	}
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	Handle CreateInterface = EndPrepSDKCall();

	if(CreateInterface == null)
	{
		SetFailState("Unable to prepare SDKCall for CreateInterface");
	}

	char interfaceName[64];

	// ProcessMovement
	if(!GameConfGetKeyValue(gamedataConf, "IGameMovement", interfaceName, sizeof(interfaceName)))
	{
		SetFailState("Failed to get IGameMovement interface name");
	}

	Address IGameMovement = SDKCall(CreateInterface, interfaceName, 0);

	if(!IGameMovement)
	{
		SetFailState("Failed to get IGameMovement pointer");
	}

	int iOffset = GameConfGetOffset(gamedataConf, "ProcessMovement");
	if(iOffset == -1)
	{
		SetFailState("Failed to get ProcessMovement offset");
	}

	int iOffsetRoughLanding = GameConfGetOffset(gamedataConf, "PlayerRoughLandingEffects");
	if(iOffset == -1)
	{
		SetFailState("Failed to get ProcessMovement offset");
	}

	Handle processMovement = DHookCreate(iOffset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_ProcessMovementPre);
	DHookAddParam(processMovement, HookParamType_CBaseEntity);
	DHookAddParam(processMovement, HookParamType_ObjectPtr);
	DHookRaw(processMovement, false, IGameMovement);

	Handle processMovementPost = DHookCreate(iOffset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_ProcessMovementPost);
	DHookAddParam(processMovementPost, HookParamType_CBaseEntity);
	DHookAddParam(processMovementPost, HookParamType_ObjectPtr);
	DHookRaw(processMovementPost, true, IGameMovement);

	Handle playerRoughLandingEffects = DHookCreate(iOffsetRoughLanding, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_PlayerRoughLandingEffects);
	DHookAddParam(playerRoughLandingEffects, HookParamType_Float);
	DHookRaw(playerRoughLandingEffects, false, IGameMovement);

	delete CreateInterface;
	delete gamedataConf;
}

//https://github.com/xen-000/SuppressViewpunch
public MRESReturn DHook_PlayerRoughLandingEffects(Handle hParams)
{
	return MRES_Supercede;
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
		if(GetClientTeam(client) != 1)
		{
			gB_TAS[client] = true;
			Shavit_PrintToChat(client, "This is a TAS style. Type !tashelp for more information.");
			DrawPanel(client);
			ResetTASData(client);
		}
	}
}

public Action Command_PlusStrafer(int client, int args)
{
	gB_SilentStrafe[client] = true;
	return Plugin_Handled;
}

public Action Command_MinusStrafer(int client, int args)
{
	gB_SilentStrafe[client] = false;
	return Plugin_Handled;
}

public Action Command_PlusOne(int client, int args)
{
	if(gI_Status[client] == PAUSED)
	{
		int iFrameSize = gA_Frames[client].Length - gI_PreFrameCount[client];
		int iFrameNumber = gI_IndexCounter[client] + gI_PreFrameCount[client];
		if(iFrameSize > 1 && iFrameNumber < iFrameSize - 1 + gI_PreFrameCount[client])
		{
			framedata_t frame;
			gA_Frames[client].GetArray(iFrameNumber, frame);

			framedata_t frame2;
			gA_Frames[client].GetArray(iFrameNumber-1, frame2);

			float fVelocity[3];
			MakeVectorFromPoints(frame2.fPosition, frame.fPosition, fVelocity);

			for (int i = 0; i < 3; i++)
			{
				fVelocity[i] *= gF_TickRate;
			}

			float fAngles[3];
			fAngles[0] = frame.fEyeAngles[0];
			fAngles[1] = frame.fEyeAngles[1];
			fAngles[2] = 0.0;

			TeleportEntity(client, frame.fPosition, fAngles, fVelocity);

			SetEntProp(client, Prop_Send, "m_bDucked", frame.bDucked);
			SetEntProp(client, Prop_Send, "m_bDucking", frame.bDucking);

			if(g_Game == Engine_CSGO)
			{
				SetEntPropFloat(client, Prop_Send, "m_flDuckAmount", frame.fDuckTime);
				SetEntPropFloat(client, Prop_Send, "m_flDuckSpeed", frame.fDuckSpeed);
			}
			else
			{
				SetEntPropFloat(client, Prop_Send, "m_flDucktime", frame.fDuckTime);
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
		int iFrameSize = gA_Frames[client].Length - gI_PreFrameCount[client];
		int iFrameNumber = gI_IndexCounter[client] + gI_PreFrameCount[client];
		if(iFrameSize > 1 && iFrameNumber > 2 + gI_PreFrameCount[client])
		{
			framedata_t frame;
			gA_Frames[client].GetArray(iFrameNumber, frame);

			framedata_t frame2;
			gA_Frames[client].GetArray(iFrameNumber-1, frame2);

			float fVelocity[3];
			MakeVectorFromPoints(frame.fPosition, frame2.fPosition, fVelocity);

			for (int i = 0; i < 3; i++)
			{
				fVelocity[i] *= gF_TickRate;
			}

			float fAngles[3];
			fAngles[0] = frame.fEyeAngles[0];
			fAngles[1] = frame.fEyeAngles[1];
			fAngles[2] = 0.0;

			TeleportEntity(client, frame2.fPosition, fAngles, fVelocity);

			SetEntProp(client, Prop_Send, "m_bDucked", frame2.bDucked);
			SetEntProp(client, Prop_Send, "m_bDucking", frame2.bDucking);

			if(g_Game == Engine_CSGO)
			{
				SetEntPropFloat(client, Prop_Send, "m_flDuckAmount", frame2.fDuckTime);
				SetEntPropFloat(client, Prop_Send, "m_flDuckSpeed", frame2.fDuckSpeed);
			}
			else
			{
				SetEntPropFloat(client, Prop_Send, "m_flDucktime", frame2.fDuckTime);
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
	DrawPanel(client);
	return Plugin_Handled;
}

public Action Command_TASHelp(int client, int args)
{
	Shavit_PrintToChat(client, "TAS Guide:");
	Shavit_PrintToChat(client, "Recommended Binds:");
	Shavit_PrintToChat(client, "bind mwheelup sm_minusone");
	Shavit_PrintToChat(client, "bind mwheeldown sm_plusone");
	Shavit_PrintToChat(client, "bind mouse1 +rewind");
	Shavit_PrintToChat(client, "bind mouse2 +fastforward");
	Shavit_PrintToChat(client, "Other Commands:");
	Shavit_PrintToChat(client, "+autostrafer - When bound hold to use wigglehack");
	Shavit_PrintToChat(client, "!tascpadd, !tascpdelete, !tascptp - Manage TAS Checkpoint");
	Shavit_PrintToChat(client, "!tasmenu - Toggles TAS Menu");
	return Plugin_Handled;
}

public Action Command_CPAdd(int client, int args)
{
	if(!gB_TAS[client])
	{
		return Plugin_Handled;
	}

	gI_CPIndex[client] = gI_IndexCounter[client];
	return Plugin_Handled;
}

public Action Command_CPDelete(int client, int args)
{
	if(!gB_TAS[client] && gI_CPIndex[client] != 0)
	{
		return Plugin_Handled;
	}

	gI_CPIndex[client] = 0;
	return Plugin_Handled;
}

public Action Command_CPTP(int client, int args)
{
	if(!gB_TAS[client] || gI_CPIndex[client] == 0)
	{
		return Plugin_Handled;
	}

	if(gI_CPIndex[client] >= gA_Frames[client].Length)
	{
		gI_CPIndex[client] = 0;
		return Plugin_Handled;
	}

	gI_Status[client] = PAUSED;
	gI_IndexCounter[client] = gI_CPIndex[client];

	int iFrameNumber = gI_IndexCounter[client] + gI_PreFrameCount[client];

	framedata_t frame;
	gA_Frames[client].GetArray(iFrameNumber, frame);

	float fAngles[3];
	fAngles[0] = frame.fEyeAngles[0];
	fAngles[1] = frame.fEyeAngles[1];
	fAngles[2] = 0.0;

	gF_TASTime[client] = frame.fTime;

	TeleportEntity(client, frame.fPosition, fAngles, view_as<float>({0.0, 0.0, 0.0}));

	return Plugin_Handled;
}

public Action CommandListener_TAS(int client, const char[] command, int args)
{
	DrawPanel(client);
	return Plugin_Continue;
}

public Action CommandListener_PlusRewind(int client, const char[] command, int args)
{
	if(!gB_TAS[client])
	{
		return Plugin_Handled;
	}
	gI_Status[client] = BACKWARD;
	return Plugin_Handled;
}

public Action CommandListener_PlusForward(int client, const char[] command, int args)
{
	if(!gB_TAS[client] || Shavit_GetTimerStatus(client) != Timer_Running)
	{
		return Plugin_Handled;
	}
	gI_Status[client] = FORWARD;
	return Plugin_Handled;
}

public Action CommandListener_MinusRewindOrForward(int client, const char[] command, int args)
{
	if(!gB_TAS[client] || Shavit_GetTimerStatus(client) != Timer_Running)
	{
		return Plugin_Handled;
	}
	gI_Status[client] = PAUSED;
	return Plugin_Handled;
}


//Thanks to KiD Fearless for the timescale method
public MRESReturn DHook_ProcessMovementPre(Handle hParams)
{
	int client = DHookGetParam(hParams, 1);
	if(!gB_TAS[client])
	{
		gB_ProcessFrame[client] = true;
		return MRES_Ignored;
	}

	if(gF_NextFrameTime[client] <= 0.0)
	{
		gF_NextFrameTime[client] += (1.0 - gF_Timescale[client]);
		gMT_LastMoveType[client] = GetEntityMoveType(client);
		gB_ProcessFrame[client] = (gF_NextFrameTime[client] <= 0.0);
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
		Shavit_SetClientTimescale(client, 1.0);
		return MRES_Ignored;
	}
	else
	{
		gF_NextFrameTime[client] -= gF_Timescale[client];
		SetEntityMoveType(client, MOVETYPE_NONE);
		gB_ProcessFrame[client] = (gF_NextFrameTime[client] <= 0.0);

		return MRES_Ignored;
	}
}

public MRESReturn DHook_ProcessMovementPost(Handle hParams)
{
	int client = DHookGetParam(hParams, 1);

	if(gB_TAS[client])
	{
		SetEntityMoveType(client, gMT_LastMoveType[client]);
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", gF_Timescale[client]);
		Shavit_SetClientTimescale(client, gF_Timescale[client]);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(gB_TAS[client] && IsValidClient(client, true))
	{
		//DrawPanel(client);
		
		if(Shavit_GetTimerStatus(client) != Timer_Running && (gI_Status[client] == RUN || gI_Status[client] == PAUSED))
		{
			gI_Status[client] = RUN; //in the event they fastfowarded into the endzone and paused on the edge of the zone.
			return Plugin_Continue;
		}
		else
		{
			if(gI_Status[client] == RUN)
			{
				// Record Frames
				if(sv_client_predict != null)
				{
					sv_client_predict.ReplicateToClient(client, "-1"); //Fix bug
				}

				float fDifference = AngleNormalize(angles[1] - gF_LastAngle[client]);
				/*
							AUTO STRAFER START
														*/
				if((buttons & IN_FORWARD) > 0 && vel[0] <= 50.0)
				{
					vel[0] = gF_MaxMove;
				}

				float fYawChange = 0.0;
				if(vel[0] > 50.0)
				{
					fYawChange = gF_AirSpeedCap * FloatAbs(gF_AirSpeedCap / vel[0]);
				}

				if((GetEntityFlags(client) & FL_ONGROUND) == 0 && (GetEntityMoveType(client) != MOVETYPE_NOCLIP)
					&& (buttons & IN_FORWARD) == 0 && (buttons & IN_BACK) == 0 && (buttons & IN_MOVELEFT) == 0 && (buttons & IN_MOVERIGHT) == 0)
				{

					if (gB_AutoStrafeEnabled[client])
					{
						if(fDifference < 0.0)
						{
							angles[1] += fYawChange;
							//buttons |= IN_MOVERIGHT;
							vel[1] = gF_MaxMove;
						}
						else if(fDifference > 0.0)
						{
							angles[1] -= fYawChange;
							//buttons |= IN_MOVELEFT;
							vel[1] = -gF_MaxMove;
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
					if (gB_SilentStrafe[client])
					{
						if(gB_ProcessFrame[client])
						{
							static int s_iOnGroundCount[MAXPLAYERS+1] = {1, ...};

							if(GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") != -1)
							{
								s_iOnGroundCount[client]++;
							}
							else
							{
								s_iOnGroundCount[client] = 0;
							}
							
							if (IsPlayerAlive(client) && s_iOnGroundCount[client] <= 1 && !(GetEntityMoveType(client) & MOVETYPE_LADDER) && (GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1))
							{
								if((buttons & (IN_MOVERIGHT | IN_MOVELEFT)) != 0)
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
									if(gCV_AutoFind_Offset.BoolValue && s_iOnGroundCount[client] == 0 && !(fSurfaceFriction == 0.25 || fSurfaceFriction == 1.0))
									{
										FindNewFrictionOffset(client);
									}
								}


								float fVelocity[3], fVelocity2D[2];

								GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVelocity);

								fVelocity2D[0] = fVelocity[0];
								fVelocity2D[1] = fVelocity[1];

								GetIdealMovementsInAir(angles[1], fVelocity2D, fMaxSpeed, fSurfaceFriction, fFowardMove, fSideMove);

								float fCurrentAngleDifference = AngleNormalize(angles[1] - gF_LastAngle[client]);
								float fCurrentAngles = FloatAbs(fCurrentAngleDifference);


								// Right
								if (fCurrentAngleDifference < 0.0)
								{
									float fMaxDelta = GetMaxDeltaInAir(fVelocity2D, fMaxSpeed, fSurfaceFriction, true);
									vel[1] = gF_MaxMove;

									if (fCurrentAngles <= fMaxDelta * gF_Power[client])
									{
										vel[0] = fFowardMove * gF_MaxMove;
										vel[1] = fSideMove * gF_MaxMove;
									}
								}
								else if (fCurrentAngleDifference > 0.0)
								{
									float fMaxDelta = GetMaxDeltaInAir(fVelocity2D, fMaxSpeed, fSurfaceFriction, false);
									vel[1] = -gF_MaxMove;

									if (fCurrentAngles <= fMaxDelta * gF_Power[client])
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
				}

				if(gB_ProcessFrame[client])
				{
					gF_TASTime[client] += GetTickInterval();

					int iFrameNumber = gA_Frames[client].Length + 1;
					if(gI_IndexCounter[client] + gI_PreFrameCount[client] != iFrameNumber-2)
					{
						//UnPaused in different tick
						iFrameNumber = gI_IndexCounter[client] + 1 + gI_PreFrameCount[client];
					}
					gA_Frames[client].Resize(iFrameNumber);

					framedata_t frame;

					frame.fTime = gF_TASTime[client];

					float fAngles[3];
					GetClientEyeAngles(client, fAngles);
					frame.fEyeAngles[0] = fAngles[0];
					frame.fEyeAngles[1] = fAngles[1];

					GetEntPropVector(client, Prop_Send, "m_vecOrigin", frame.fPosition);
					GetEntPropVector(client, Prop_Data, "m_vecVelocity", frame.fVelocity);
					frame.buttons = buttons;
					frame.iFlags = GetEntityFlags(client);
					frame.movetype = GetEntityMoveType(client);

					frame.bDucked = GetEntProp(client, Prop_Data, "m_bDucked") != 0;
					frame.bDucking = GetEntProp(client, Prop_Data, "m_bDucking") != 0;
					if(g_Game == Engine_CSGO)
					{
						frame.fDuckTime = GetEntPropFloat(client, Prop_Data, "m_flDuckAmount");
						frame.fDuckSpeed = GetEntPropFloat(client, Prop_Data, "m_flDuckSpeed");
					}
					else
					{
						frame.fDuckTime = GetEntPropFloat(client, Prop_Data, "m_flDucktime");
					}

					gA_Frames[client].SetArray(iFrameNumber-1, frame);

					gI_IndexCounter[client] = iFrameNumber - 1 - gI_PreFrameCount[client];
					gF_IndexCounter[client] = iFrameNumber - 1.0 - view_as<float>(gI_PreFrameCount[client]);
				}

				// Fix boosters
				// Credit to bTimes 2.0 by blacky ;)
				if((GetEntityFlags(client) & FL_BASEVELOCITY) > 0)
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
				if(sv_client_predict != null)
				{
					sv_client_predict.ReplicateToClient(client, "0"); //Fix bug
				}

				if((gI_LastButtons[client] & IN_JUMP) == 0 && (buttons & IN_JUMP))
				{
					gI_Status[client] = RUN;
					ResumePlayer(client);
				}
				else
				{
					vel[0] = 0.0;
					vel[1] = 0.0;
					vel[2] = 0.0;
					int iFrameSize = gA_Frames[client].Length - gI_PreFrameCount[client];
					int iFrameNumber = gI_IndexCounter[client] + gI_PreFrameCount[client];
					if(iFrameSize > 1 && iFrameNumber > 1)
					{
						framedata_t frame;
						gA_Frames[client].GetArray(iFrameNumber, frame);

						float fAngles[3];
						fAngles[0] = frame.fEyeAngles[0];
						fAngles[1] = frame.fEyeAngles[1];
						fAngles[2] = 0.0;

						TeleportEntity(client, frame.fPosition, fAngles, view_as<float>({0.0, 0.0, 0.0}));
						gF_TASTime[client] = frame.fTime;

						if((frame.iFlags & FL_DUCKING) > 0)
						{
							buttons |= IN_DUCK;
						}
						
						SetEntProp(client, Prop_Send, "m_bDucked", frame.bDucked);
						SetEntProp(client, Prop_Send, "m_bDucking", frame.bDucking);

						if(g_Game == Engine_CSGO)
						{
							SetEntPropFloat(client, Prop_Send, "m_flDuckAmount", frame.fDuckTime);
							SetEntPropFloat(client, Prop_Send, "m_flDuckSpeed", frame.fDuckSpeed);
						}
						else
						{
							SetEntPropFloat(client, Prop_Send, "m_flDucktime", frame.fDuckTime);
						}

						SetEntityFlags(client, frame.iFlags);
					}

					if((GetEntityFlags(client) & FL_ONGROUND) > 0)
					{
						buttons &= ~IN_JUMP;
					}
				}
			}
			else if(gI_Status[client] == BACKWARD)
			{
				if(sv_client_predict != null)
				{
					sv_client_predict.ReplicateToClient(client, "0"); //Fix bug
				}

				if(Shavit_GetTimerStatus(client) != Timer_Running)
				{
					if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
					{
						gI_Status[client] = RUN;
						Shavit_PrintToChat(client, "Please disable noclip before rewinding!");
						return Plugin_Continue;
					}

					Shavit_StartTimer(client, gI_Track[client]);
				}
				vel[0] = 0.0;
				vel[1] = 0.0;
				vel[2] = 0.0;
				int iFrameSize = gA_Frames[client].Length - gI_PreFrameCount[client];
				int iFrameNumber = gI_IndexCounter[client] + gI_PreFrameCount[client];
				if(iFrameSize > 1 && iFrameNumber > 2 + gI_PreFrameCount[client])
				{
					framedata_t frame;
					gA_Frames[client].GetArray(iFrameNumber, frame);

					framedata_t frame2;
					gA_Frames[client].GetArray(iFrameNumber-1, frame2);

					float fVelocity[3];
					MakeVectorFromPoints(frame.fPosition, frame2.fPosition, fVelocity);

					for (int i = 0; i < 3; i++)
					{
						fVelocity[i] *= gF_TickRate;
					}

					float fAngles[3];
					fAngles[0] = frame.fEyeAngles[0];
					fAngles[1] = frame.fEyeAngles[1];
					fAngles[2] = 0.0;

					TeleportEntity(client, frame2.fPosition, fAngles, fVelocity);

					gF_IndexCounter[client] -= gF_CounterSpeed[client];
					if(IsRound(gF_IndexCounter[client]))
					{
						gI_IndexCounter[client]--;
					}
					gF_TASTime[client] = frame2.fTime;
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
				int iFrameSize = gA_Frames[client].Length - gI_PreFrameCount[client];
				int iFrameNumber = gI_IndexCounter[client] + gI_PreFrameCount[client];
				if(iFrameSize > 1 && iFrameNumber < iFrameSize - 1 + gI_PreFrameCount[client])
				{
					framedata_t frame;
					gA_Frames[client].GetArray(iFrameNumber, frame);

					framedata_t frame2;
					gA_Frames[client].GetArray(iFrameNumber-1, frame2);

					float fVelocity[3];
					MakeVectorFromPoints(frame2.fPosition, frame.fPosition, fVelocity);

					for (int i = 0; i < 3; i++)
					{
						fVelocity[i] *= gF_TickRate;
					}

					float fAngles[3];
					fAngles[0] = frame.fEyeAngles[0];
					fAngles[1] = frame.fEyeAngles[1];
					fAngles[2] = 0.0;

					TeleportEntity(client, frame.fPosition, fAngles, fVelocity);

					gF_IndexCounter[client] += gF_CounterSpeed[client];
					if(IsRound(gF_IndexCounter[client]))
					{
						gI_IndexCounter[client]++;
					}
					gF_TASTime[client] = frame.fTime;
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
	if(!gB_TAS[client])
	{
		Shavit_PrintToChat(client, "TASMenu can only be used when playing a TAS style!");
		return false;
	}
	Panel panel = new Panel();
	panel.SetTitle("Tool Assisted Speedrun:");

	if(gI_Status[client] == PAUSED)
	{
		panel.DrawItem("Resume");
	}
	else
	{
		panel.DrawItem("Pause");
	}

	if(gI_Status[client] != BACKWARD)
	{
		panel.DrawItem("+rewind");
	}
	else
	{
		panel.DrawItem("-rewind");
	}

	if(gI_Status[client] != FORWARD)
	{
		panel.DrawItem("+fastforward");
	}
	else
	{
		panel.DrawItem("-fastforward");
	}

	char sBuffer[256];
	FormatEx(sBuffer, sizeof(sBuffer), "Timescale: %.01f", gF_Timescale[client]);
	panel.DrawItem(sBuffer);
	/* FormatEx(sBuffer, sizeof(sBuffer), "Edit Speed: %.01f", gF_CounterSpeed[client]);
	panel.DrawItem(sBuffer); */

	panel.DrawText(" ");

	panel.CurrentKey = 5;
	FormatEx(sBuffer, sizeof(sBuffer), "Toggle autostrafe %s", gB_AutoStrafeEnabled[client]?"[ON]":"[OFF]");
	panel.DrawItem(sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "Toggle wigglehack %s", gB_SilentStrafe[client]?"[ON]":"[OFF]");
	panel.DrawItem(sBuffer);
	
	panel.DrawText(" ");
	panel.DrawText("----------------------------");
	panel.DrawText(" ");

	panel.CurrentKey = 8;
	panel.DrawItem("Restart");
	panel.DrawItem("Exit");
	panel.Send(client, PanelHandler, MENU_TIME_FOREVER);

	delete panel;
	return true;
}

public int PanelHandler(Handle menu, MenuAction action, int client, int selection)
{
	if(action == MenuAction_Select)
	{
		if(!gB_TAS[client])
		{
			return 0;
		}

		switch(selection)
		{
			case 1:
			{
				if(Shavit_GetTimerStatus(client) == Timer_Running)
				{
					if(gI_Status[client] == PAUSED)
					{
						gI_Status[client] = RUN;
						ResumePlayer(client);
					}
					else
					{
						if(Shavit_InsideZone(client, Zone_Start, -1) && gI_Status[client] == RUN)
						{
							DrawPanel(client);
							return 0;
						}

						gI_Status[client] = PAUSED;
					}
				}
			}
			case 2:
			{
				if(Shavit_InsideZone(client, Zone_Start, -1) && gI_Status[client] == RUN)
				{

					DrawPanel(client);
					return 0;
				}

				if(gI_Status[client] != BACKWARD)
				{
					gI_Status[client] = BACKWARD;
				}
				else
				{
					gI_Status[client] = PAUSED;
				}
			}
			case 3:
			{
				if(Shavit_GetTimerStatus(client) == Timer_Running)
				{
					if(Shavit_InsideZone(client, Zone_Start, -1) && gI_Status[client] == RUN)
					{
						DrawPanel(client);
						return 0;
					}

					if(gI_Status[client] != FORWARD)
					{
						gI_Status[client] = FORWARD;
					}
					else
					{
						gI_Status[client] = PAUSED;
					}
				}
			}
			/* case 4:
			{
				gF_IndexCounter[client] = 1.0 * RoundToFloor(gF_IndexCounter[client]);
				gF_CounterSpeed[client] += 1.0;
				if(gF_CounterSpeed[client] >= 4.0)
				{
					gF_CounterSpeed[client] = 1.0;
				}
			} */
			case 4:
			{
				if(!Shavit_InsideZone(client, Zone_Start, -1) && gI_Status[client] == RUN)
				{
					Shavit_PrintToChat(client, "Timescale can only be updated when paused or inside the start zone!");
					DrawPanel(client);
					return 0;
				}

				gF_Timescale[client] += 0.1;
				if(gF_Timescale[client] >= 1.1)
				{
					gF_Timescale[client] = 0.1;
				}
			}
			case 5:
			{
				gB_AutoStrafeEnabled[client] = !gB_AutoStrafeEnabled[client];
			}
			case 6:
			{
				gB_SilentStrafe[client] = !gB_SilentStrafe[client];
			}
			case 8:
			{
				gI_Status[client] = RUN;

				FakeClientCommand(client, "sm_r");
				/* idk why but this causes a crash???
				gF_TASTime[client] = 0.0;
				gI_IndexCounter[client] = 0;
				Shavit_RestartTimer(client, Shavit_GetClientTrack(client)); */
			}
			case 9:
			{
				Shavit_PrintToChat(client, "Type !tasmenu to reopen the menu.");
			}
		}
	}
	DrawPanel(client);
	return 0;
}

void ResumePlayer(int client)
{
	int iFrameSize = gA_Frames[client].Length - gI_PreFrameCount[client];
	int iFrameNumber = gI_IndexCounter[client] + gI_PreFrameCount[client];
	if(iFrameSize > 1 && iFrameNumber > 1 + gI_PreFrameCount[client])
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

		framedata_t frame;
		gA_Frames[client].GetArray(iFrameNumber, frame);

		float fAngles[3];
		fAngles[0] = frame.fEyeAngles[0];
		fAngles[1] = frame.fEyeAngles[1];
		fAngles[2] = 0.0;

		TeleportEntity(client, frame.fPosition, fAngles, frame.fVelocity);

		
		SetEntProp(client, Prop_Send, "m_bDucked", frame.bDucked);
		SetEntProp(client, Prop_Send, "m_bDucking", frame.bDucking);

		if(g_Game == Engine_CSGO)
		{
			SetEntPropFloat(client, Prop_Send, "m_flDuckAmount", frame.fDuckTime);
			SetEntPropFloat(client, Prop_Send, "m_flDuckSpeed", frame.fDuckSpeed);
		}
		else
		{
			SetEntPropFloat(client, Prop_Send, "m_flDucktime", frame.fDuckTime);
		}

		SetEntityFlags(client, frame.iFlags);
	}
}

bool IsRound(float num)
{
	return RoundToFloor(num) == num;
}

void ResetTASData(int client)
{
	if(gA_Frames[client] != INVALID_HANDLE)
	{
		gA_Frames[client].Clear();
	}
	else
	{
		gA_Frames[client] = new ArrayList(sizeof(framedata_t));
	}

	gF_CounterSpeed[client] = 1.0;
	gF_TASTime[client] = 0.0;
	gF_Timescale[client] = 1.0;
	gI_Status[client] = RUN;
	gB_AutoStrafeEnabled[client] = false;
	gB_SilentStrafe[client] = false;
	gI_Type[client] = Type_SurfOverride;
	gF_Power[client] = 1.0;
	gI_CPIndex[client] = 0;
}

public Action Shavit_OnStart(int client, int track)
{
	gI_Track[client] = track;

	if(gB_TAS[client] && IsValidClient(client, true))
	{
		if(gI_Status[client] == PAUSED)
		{
			gI_Status[client] = RUN;
		}
		if(gI_Status[client] == RUN)
		{
			timer_snapshot_t snapshot;
			Shavit_SaveSnapshot(client, snapshot);

			framedata_t frame;
			gA_Frames[client].GetArray(gI_IndexCounter[client] + gI_PreFrameCount[client], frame);

			if(gA_Frames[client] != INVALID_HANDLE && frame.fTime > 0.01 && snapshot.fCurrentTime == 0.0)
			{
				gF_TASTime[client] = frame.fTime;
			}
			else
			{
				gF_TASTime[client] = 0.0;
				gI_IndexCounter[client] = 0;
				gI_CPIndex[client] = 0;
				gA_Frames[client].Clear();

				ArrayList frames = Shavit_GetReplayData(client);
				gI_PreFrameCount[client] = Shavit_GetPlayerPreFrame(client);
				frames.Resize(gI_PreFrameCount[client]);

				for(int i = 0; i < frames.Length; i++)
				{
					gA_Frames[client].Resize(i + 1);

					framedata_t newframe;

					newframe.fTime = 0.0;

					newframe.fEyeAngles[0] = frames.Get(i, 3);
					newframe.fEyeAngles[1] = frames.Get(i, 4);

					newframe.fPosition[0] = frames.Get(i, 0);
					newframe.fPosition[1] = frames.Get(i, 1);
					newframe.fPosition[2] = frames.Get(i, 2);
					
					//GetEntPropVector(client, Prop_Data, "m_vecVelocity", frame.fVelocity);
					newframe.buttons = frames.Get(i, 5);
					newframe.iFlags = frames.Get(i, 6);
					newframe.movetype = frames.Get(i, 7);

					// Timer Replays do not track duck info. Doesn't matter since it's just preframes.
					newframe.bDucked = false;
					newframe.bDucking = false;
					newframe.fDuckTime = 0.0;
					if(g_Game == Engine_CSGO)
					{
						newframe.fDuckSpeed = 0.0;
					}

					gA_Frames[client].SetArray(i, newframe);
				}

				delete frames;
			}
		}
	}
	return Plugin_Continue;
}

public void Shavit_OnFinish_Post(int client)
{
	if(gB_TAS[client])
	{
		gI_Status[client] = RUN;
	}
}

public Action Shavit_OnFinishPre(int client, timer_snapshot_t snapshot)
{
	if(gB_TAS[client])
	{
		//Edit time to equal the gF_TASTime[client]
		snapshot.fCurrentTime = gF_TASTime[client];

		//Overwrite Replay Data with gA_Frames[client]
		Shavit_SetReplayData(client, gA_Frames[client]);
		Shavit_SetPlayerPreFrame(client, gI_PreFrameCount[client]);
		return Plugin_Changed;
	}
	return Plugin_Continue;
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
	{
		fAngle -= 360.0;
	}
	else if(fAngle < -180.0)
	{
		fAngle += 360.0;
	}

	return fAngle;
}

float Vec2DToYaw(float vec[2])
{
	float fYaw = 0.0;

	if (vec[0] != 0.0 || vec[1] != 0.0)
	{
		float vecNormalized[2];

		float fLength = SquareRoot(vec[0] * vec[0] + vec[1] * vec[1]);

		vecNormalized[0] = vec[0] / fLength;
		vecNormalized[1] = vec[1] / fLength;

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
		float fCosTheta = fWantedDotProduct / fVelLength2D;

		if (fCosTheta > 1.0)
		{
			fCosTheta = 1.0;
		}
		else if(fCosTheta < -1.0)
		{
			fCosTheta = -1.0;
		}


		float fTheta = ArcCosine(fCosTheta) * (180.0 / FLOAT_PI);

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
	float fCurrentSpeed = fVelocity[0] * fWishedDirection[0] + fVelocity[1] * fWishedDirection[1];

	// See how much to add
	float fAddSpeed = fCapWishSpeed - fCurrentSpeed;

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

	float fTemp[3], vBestLeft3D[3], vBestRight3D[3];

	fTemp[0] = 0.0;
	fTemp[1] = fBestYawLeft;
	fTemp[2] = 0.0;

	GetAngleVectors(fTemp, vBestLeft3D, NULL_VECTOR, NULL_VECTOR);

	fTemp[0] = 0.0;
	fTemp[1] = fBestYawRight;
	fTemp[2] = 0.0;

	GetAngleVectors(fTemp, vBestRight3D, NULL_VECTOR, NULL_VECTOR);

	float vBestRight[2], vBestLeft[2];

	vBestRight[0] = vBestRight3D[0];
	vBestRight[1] = vBestRight3D[1];

	vBestLeft[0] = vBestLeft3D[0];
	vBestLeft[1] = vBestLeft3D[1];

	float fCalculateVelocityLeft[2], fCalculateVelocityRight[2];

	// Simulate air accelerate function in order to get the new max gain possible on both side.
	SimulateAirAccelerate(fVelocity, vBestLeft, fAirAccelerate, fMaxSpeed, fFrameTime, fSurfaceFriction, fCalculateVelocityLeft);
	SimulateAirAccelerate(fVelocity, vBestRight, fAirAccelerate, fMaxSpeed, fFrameTime, fSurfaceFriction, fCalculateVelocityRight);

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

	float vForwardWantedDirection3D[3], vRightWantedDirection3D[3];
	float vForwardWantedDirection[2], vRightWantedDirection[2];

	TemporaryAngle[0] = 0.0;
	TemporaryAngle[1] = fYawWantedDirection;
	TemporaryAngle[2] = 0.0;

	// Convert our yaw wanted direction to vectors.
	GetAngleVectors(TemporaryAngle, vForwardWantedDirection3D, vRightWantedDirection3D, NULL_VECTOR);

	vForwardWantedDirection[0] = vForwardWantedDirection3D[0];
	vForwardWantedDirection[1] = vForwardWantedDirection3D[1];

	vRightWantedDirection[0] = vRightWantedDirection3D[0];
	vRightWantedDirection[1] = vRightWantedDirection3D[1];

	// Solve the movement variables from our wanted direction and the best gain direction.
	Solve2DMovementsVars(vBestVectorDirection, vForwardWantedDirection, vRightWantedDirection, fForwardMove, fSideMove);

	float fLengthMovements = SquareRoot(fForwardMove * fForwardMove + fSideMove * fSideMove);

	if(fLengthMovements != 0.0)
	{
		fForwardMove /= fLengthMovements;
		fSideMove /= fLengthMovements;
	}
}

void FindNewFrictionOffset(int client)
{
	if(g_Game == Engine_CSGO)
	{
		int iStartingOffset = FindSendPropInfo("CBasePlayer", "m_ubEFNoInterpParity");
		for(int i = 16; i >= -128; --i)
		{
			float fFriction = GetEntDataFloat(client, iStartingOffset + i);
			if(fFriction == 0.25 || fFriction == 1.0)
			{
				gI_SurfaceFrictionOffset = iStartingOffset - i;
				LogError("[TAS] Current friction offset is out of date. Please update to new offset: %i", i * -1);
			}
		}
	}
	else
	{
		int iStartingOffset = FindSendPropInfo("CBasePlayer", "m_szLastPlaceName");
		for(int i = 1; i <= 128; ++i)
		{
			float fFriction = GetEntDataFloat(client, iStartingOffset + i);
			if(fFriction == 0.25 || fFriction == 1.0)
			{
				gI_SurfaceFrictionOffset = iStartingOffset + i;
				LogError("[TAS] Current friction offset is out of date. Please update to new offset: %i", i);
			}
		}
	}
}

public any Native_SetAutostrafe(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool value = GetNativeCell(2);
	gB_SilentStrafe[client] = value;
	
	return 0;
}

public any Native_GetAutostrafe(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	return gB_SilentStrafe[client];
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