#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <shavit>
#include <cstrike>

// cvars
ConVar gCV_WorldDamage = null;
ConVar gCV_FragsOnEvents = null;
ConVar gCV_AutoRespawn = null;
ConVar gCV_AutoRespawn_Time = null;
ConVar gCV_SlayOnFinish = null;
ConVar gCV_SlayOnFinish_Time = null;
ConVar gCV_HideDeaths = null;

// cached cvars
bool gB_WorldDamage = false;
int gI_FragsOnEvents = 0;
bool gB_AutoRespawn = false;
float gF_AutoRespawn_Time = 0.5;
bool gB_SlayOnFinish = false;
float gF_SlayOnFinish_Time = 0.1;
bool gB_HideDeaths = false;

public Plugin myinfo =
{
	name = "[shavit] Course Utilities",
	author = "shavit",
	description = "Course maps utilities for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public void OnPluginStart() {
	// Cvars
	gCV_WorldDamage = CreateConVar("shavit_course_world_damage", "0", "Remove world damage from starting zone if map has start and end zones?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_FragsOnEvents = CreateConVar("shavit_course_frags", "0", "Add frag (kill) on death or map finish?\n0 - Disabled\n1 - On both\n2 - On death only\n3 - On finish only", 0, true, 0.0, true, 3.0);
	gCV_AutoRespawn = CreateConVar("shavit_course_autorespawn", "0", "Enable auto-respawn on death?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AutoRespawn_Time = CreateConVar("shavit_course_respawntime", "0.5", "Respawn in time in seconds. Min 0.1", 0, true, 0.1, false);
	gCV_SlayOnFinish = CreateConVar("shavit_course_slayonfinish", "0", "Slay player on finish?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_SlayOnFinish_Time = CreateConVar("shavit_course_slaytime", "0.5", "Slay player on finish time. Min 0.1", 0, true, 0.1, false);
	gCV_HideDeaths = CreateConVar("shavit_course_hidedeaths", "0", "Hide deaths feed?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	// Cvar Hooks
	gCV_WorldDamage.AddChangeHook(OnConVarChanged);
	gCV_FragsOnEvents.AddChangeHook(OnConVarChanged);
	gCV_AutoRespawn.AddChangeHook(OnConVarChanged);
	gCV_AutoRespawn_Time.AddChangeHook(OnConVarChanged);
	gCV_SlayOnFinish.AddChangeHook(OnConVarChanged);
	gCV_SlayOnFinish_Time.AddChangeHook(OnConVarChanged);
	gCV_HideDeaths.AddChangeHook(OnConVarChanged);
	AutoExecConfig(true);
	// Events Hooks
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);	
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gB_WorldDamage = gCV_WorldDamage.BoolValue;
	gI_FragsOnEvents = gCV_FragsOnEvents.IntValue;
	gB_AutoRespawn = gCV_AutoRespawn.BoolValue;
	gF_AutoRespawn_Time = gCV_AutoRespawn_Time.FloatValue;
	gB_SlayOnFinish = gCV_SlayOnFinish.BoolValue;
	gF_SlayOnFinish_Time = gCV_SlayOnFinish_Time.FloatValue;
	gB_HideDeaths = gCV_HideDeaths.BoolValue;
}

public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if(!gB_WorldDamage)
	return Plugin_Continue;
	if(!IsValidClient(victim)) 
	return Plugin_Continue;
	// Check if there is no start zone in map, let it skip.
	if(!Shavit_ZoneExists(Zone_Start, Track_Main) || !Shavit_ZoneExists(Zone_End, Track_Main)) {
		return Plugin_Handled;
	}
	// Check if it is world damage and client is not running timer atm
	if ((attacker == 0 || attacker >= MaxClients) && Shavit_InsideZone(victim, Zone_Start, -1))
	return Plugin_Handled;

	return Plugin_Continue;
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime) {
	if(!IsValidClient(client))
		return;
	if(gB_SlayOnFinish)
		CreateTimer(gF_SlayOnFinish_Time, SlayPlayer, GetClientSerial(client));
	if(gI_FragsOnEvents == 1 || gI_FragsOnEvents == 3)
		FragsPlusOne(client);
}
public Action SlayPlayer(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	if(!IsValidClient(client))
	return;
	ForcePlayerSuicide(client);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if(gB_HideDeaths)
	event.BroadcastDisabled = true;
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsValidClient(client))
	return Plugin_Continue;
	if(gI_FragsOnEvents == 1 || gI_FragsOnEvents == 2)
	FragsPlusOne(client);
	
	if(gB_AutoRespawn && Shavit_ZoneExists(Zone_Start, Track_Main) && Shavit_ZoneExists(Zone_End, Track_Main))
	CreateTimer(gF_AutoRespawn_Time, RespawnDeadPlayer, GetClientSerial(client));
	
	return Plugin_Continue;
}

public Action RespawnDeadPlayer(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	if(!IsValidClient(client))
	return;
	
	CS_RespawnPlayer(client);
}

public void FragsPlusOne(int client) {
	if(!IsValidClient(client)) 
	return;
	int frags = GetClientFrags(client);
	int newfrags = frags + 1;
	SetEntProp(client, Prop_Data, "m_iFrags", newfrags);
}