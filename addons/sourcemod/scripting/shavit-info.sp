/*
 * shavit's Timer - Server info
 * by: rtldg
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
#include <convar_class>

#undef REQUIRE_PLUGIN
#include <shavit>

#pragma newdecls required
#pragma semicolon 1

Handle gH_Myself = null;
EngineVersion gEV_Type;

char gS_CVARS[][] =
{
	"sv_hibernate_postgame_delay",
	"sv_hibernate_punt_tv_clients",
	"sv_hibernate_when_empty",
	"bot_join_after_player",
	"tf_bot_join_after_player",
	"bot_auto_vacate",
	"bot_dont_shoot",

	"mp_warmuptime",
	"mp_do_warmup_period",
	"mp_freezetime",
	"mp_ignore_round_win_conditions",
	"mp_timelimit",
	"mp_roundtime",
	"mp_roundtime_defuse",
	"mp_round_restart_delay",
	"mp_match_end_restart",
	"mp_match_end_changelevel",

	"sv_cheats",
	"sv_gravity",

	"mp_death_drop_grenade",
	"mp_death_drop_defuser",

	"sv_clamp_unsafe_velocities",
	"sv_accelerate",
	"sv_friction",
	"sv_accelerate_use_weapon_speed",
	"sv_ladder_scale_speed",
	"sv_timebetweenducks",

	"mp_autokick",
	"mp_autoteambalance",
	"mp_limitteams",

	"shavit_chat_rankings",
	"shavit_chat_customchat",
	"shavit_chat_colon",
	"shavit_core_restart",
	"shavit_core_pause",
	"shavit_core_timernozone",
	"shavit_core_blockprejump",
	"shavit_core_nozaxisspeed",
	"shavit_core_velocityteleport",
	"shavit_core_defaultstyle",
	"shavit_core_nochatsound",
	"shavit_core_simplerladders",
	"shavit_core_useoffsets",
	"shavit_core_timeinmessages",
	"shavit_hud_gradientstepsize",
	"shavit_hud_ticksperupdate",
	"shavit_hud_speclist",
	"shavit_hud_csgofix",
	"shavit_hud_specnamesymbollength",
	"shavit_hud_default",
	"shavit_hud2_default",
	"shavit_misc_godmode",
	"shavit_misc_prespeed",
	"shavit_misc_hideteamchanges",
	"shavit_misc_respawnonteam",
	"shavit_misc_respawnonrestart",
	"shavit_misc_startonspawn",
	"shavit_misc_prestrafelimit",
	"shavit_misc_hideradar",
	"shavit_misc_tpcmds",
	"shavit_misc_noweapondrops",
	"shavit_misc_noblock",
	"shavit_misc_noblood",
	"shavit_misc_autorespawn",
	"shavit_misc_createspawnpoints",
	"shavit_misc_disableradio",
	"shavit_misc_scoreboard",
	"shavit_misc_weaponcommands",
	"shavit_misc_playeropacity",
	"shavit_misc_staticprestrafe",
	"shavit_misc_noclipme",
	"shavit_misc_advertisementinterval",
	"shavit_misc_checkpoints",
	"shavit_misc_removeragdolls",
	"shavit_misc_clantag",
	"shavit_misc_dropall",
	"shavit_misc_resettargetname",
	"shavit_misc_restorestates",
	"shavit_misc_jointeamhook",
	"shavit_misc_speclist",
	"shavit_misc_maxcp_seg",
	"shavit_misc_hidechatcmds",
	"shavit_misc_persistdata",
	"shavit_misc_stoptimerwarning",
	"shavit_misc_wrmessages",
	"shavit_misc_bhopsounds",
	"shavit_misc_restrictnoclip",
	"shavit_misc_botfootsteps",
	"shavit_rankings_pointspertier",
	"shavit_rankings_weighting",
	"shavit_rankings_llrecalc",
	"shavit_rankings_mvprankones",
	"shavit_rankings_mvprankones_maintrack",
	"shavit_rankings_default_tier",
	"shavit_replay_enabled",
	"shavit_replay_delay",
	"shavit_replay_timelimit",
	"shavit_replay_defaultteam",
	"shavit_replay_centralbot",
	"shavit_replay_dynamicbotlimit",
	"shavit_replay_allowpropbots",
	"shavit_replay_botshooting",
	"shavit_replay_botplususe",
	"shavit_replay_botweapon",
	"shavit_replay_pbcanstop",
	"shavit_replay_pbcooldown",
	"shavit_replay_preruntime",
	"shavit_replay_prerun_always",
	"shavit_replay_timedifference_cheap",
	"shavit_replay_timedifference_search",
	"shavit_replay_timedifference",
	"shavit_replay_timedifference_tick",
	"shavit_sounds_minimumworst",
	"shavit_sounds_enabled",
	"shavit_timelimit_config",
	"shavit_timelimit_default",
	"shavit_timelimit_dynamic",
	"shavit_timelimit_forcemapend",
	"shavit_timelimit_minimumtimes",
	"shavit_timelimit_playertime",
	"shavit_timelimit_style",
	"shavit_timelimit_gamestartfix",
	"shavit_timelimit_enabled",
	"shavit_wr_recordlimit",
	"shavit_wr_recentlimit",
	"shavit_zones_interval",
	"shavit_zones_teleporttostart",
	"shavit_zones_teleporttoend",
	"shavit_zones_usecustomsprite",
	"shavit_zones_height",
	"shavit_zones_offset",
	"shavit_zones_enforcetracks",
	"shavit_zones_box_offset",
};



char gS_EXTS[][] =
{
	"dhooks.ext",
	"closestpos.ext",
};

char gS_FILES[][] =
{
	"configs/shavit-advertisements.cfg",
	"configs/shavit-chat.cfg",
	"configs/shavit-chatsettings.cfg",
	"configs/shavit-messages.cfg",
	"configs/shavit-prefix.txt",
	"configs/shavit-replay.cfg",
	"configs/shavit-sounds.cfg",
	"configs/shavit-styles.cfg",
	"configs/shavit-zones.cfg",
	"gamedata/shavit.games.txt",
	"translations/shavit-chat.phrases.txt",
	"translations/shavit-common.phrases.txt",
	"translations/shavit-core.phrases.txt",
	"translations/shavit-hud.phrases.txt",
	"translations/shavit-misc.phrases.txt",
	"translations/shavit-rankings.phrases.txt",
	"translations/shavit-replay.phrases.txt",
	"translations/shavit-stats.phrases.txt",
	"translations/shavit-wr.phrases.txt",
	"translations/shavit-zones.phrases.txt",
};

public Plugin myinfo =
{
	name = "[shavit] Server info",
	author = "rtldg",
	description = "Dumps server & plugin info to a file so people can help debug errors easier.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public void OnPluginStart()
{
	gH_Myself = GetMyHandle();
	gEV_Type = GetEngineVersion();

	RegAdminCmd("sm_dumpserverinfo", Command_DumpServerInfo, ADMFLAG_RCON, "Dumps server info to a log file so people can help debug errors easier.");
}

void DumpCvarToKv(KeyValues kv, const char[] name)
{
	ConVar cvar = FindConVar(name);
	char value[128] = "*missing*";

	if (cvar)
	{
		cvar.GetString(value, sizeof(value));
	}

	kv.SetString(name, value);
}

void DumpFileToKv(KeyValues kv, const char[] name)
{
	char buffer[269];
	BuildPath(Path_SM, buffer, sizeof(buffer), "%s", name);

	kv.JumpToKey(name, true);

	int size = FileSize(buffer);
	kv.SetNum("exists", size != -1);

	if (size != -1)
	{
		kv.SetNum("size", size);

		int timestamp = GetFileTime(buffer, FileTime_LastChange);
		kv.SetNum("modification_timestamp", timestamp);
		FormatTime(buffer, sizeof(buffer), "%Y-%m-%d %T %z", timestamp);
		kv.SetString("modification_datetime", buffer);
	}

	kv.GoBack();
}

void DumpPluginToKv(KeyValues kv, Handle plugin)
{
	char filename[269];
	char buffer[269];

	GetPluginFilename(plugin, filename, sizeof(filename));
	kv.JumpToKey(filename, true);

	if (GetPluginInfo(plugin, PlInfo_Name, buffer, sizeof(buffer)))
		kv.SetString("name", buffer);
	if (GetPluginInfo(plugin, PlInfo_Author, buffer, sizeof(buffer)))
		kv.SetString("author", buffer);
	if (GetPluginInfo(plugin, PlInfo_Description, buffer, sizeof(buffer)))
		kv.SetString("description", buffer);
	if (GetPluginInfo(plugin, PlInfo_Version, buffer, sizeof(buffer)))
		kv.SetString("version", buffer);
	if (GetPluginInfo(plugin, PlInfo_URL, buffer, sizeof(buffer)))
		kv.SetString("url", buffer);

	BuildPath(Path_SM, buffer, sizeof(buffer), "plugins/%s", filename);
	int timestamp = GetFileTime(buffer, FileTime_LastChange);
	kv.SetNum("modification_timestamp", timestamp);
	FormatTime(buffer, sizeof(buffer), "%Y-%m-%d %T %z", timestamp);
	kv.SetString("modification_datetime", buffer);

	kv.SetNum("isdumpingplugin", gH_Myself == plugin);

	kv.GoBack();
}

void DumpExtensionToKv(KeyValues kv, const char[] ext)
{
	char buffer[269];
	kv.JumpToKey(ext, true);
	int status = GetExtensionFileStatus(ext, buffer, sizeof(buffer));
	kv.SetNum("status", status);
	if (status != 1)
		kv.SetString("error", buffer);
	kv.GoBack();
}

Action Command_DumpServerInfo(int client, int args)
{
	char buffer[269];

	KeyValues kv = new KeyValues("serverinfo");
	kv.SetNum("timestamp", GetTime());
	FormatTime(buffer, sizeof(buffer), "%Y-%m-%d %T %z");
	kv.SetString("datetime", buffer);

	kv.SetString("engineversion", gEV_Type == Engine_CSGO ? "csgo" : (gEV_Type == Engine_CSS ? "css" : "tf2"));

	kv.JumpToKey("convars", true);
	for (int i = 0; i < sizeof(gS_CVARS); i++)
	{
		DumpCvarToKv(kv, gS_CVARS[i]);
	}
	kv.GoBack();

	kv.JumpToKey("files", true);
	for (int i = 0; i < sizeof(gS_FILES); i++)
	{
		DumpFileToKv(kv, gS_FILES[i]);
	}
	kv.GoBack();

	kv.JumpToKey("plugins", true);
	Handle iter = GetPluginIterator();
	do {
		DumpPluginToKv(kv, ReadPlugin(iter));
	} while (MorePlugins(iter));
	kv.GoBack();

	kv.JumpToKey("extensions", true);
	for (int i = 0; i < sizeof(gS_EXTS); i++)
	{
		DumpExtensionToKv(kv, gS_EXTS[i]);
	}
	kv.GoBack();

	kv.ExportToFile("test.log");

	return Plugin_Handled;
}
