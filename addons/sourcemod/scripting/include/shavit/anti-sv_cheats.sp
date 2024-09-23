/*
 * Anti-sv_cheats and anti- cheat-command stuff
 * by: rtldg
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
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


// This code annoys everyone but admins would sometimes set sv_cheats 1 and then
// forget to toggle it back off when they were done playing around so then people
// would join and teleport into the endzone and set dumb times.  And now we're here...
// Just add some aliases to your autoexec:
//   alias cheats "sm_rcon shavit_core_disable_sv_cheats 0 ; sm_rcon sv_cheats 1"
//   alias cheat  "sm_rcon shavit_core_disable_sv_cheats 0 ; sm_rcon sv_cheats 1"


Convar gCV_DisableSvCheats = null;

#if !DEBUG
ConVar sv_cheats = null;

char gS_CheatCommands[][] = {
	"ent_create",
	"ent_orient",
	"ent_pause",
	"ent_fire",

	"ent_remove",
	"ent_remove_all",

	"ent_setname",
	"ent_setpos",

	"ent_teleport",

	"firetarget",

	"setpos",
	"setpos_exact",
	"setpos_player",

	// can be used to kill other players
	"explode",
	"explodevector",
	"kill",
	"killvector",

	"give",
};
#endif

void Anti_sv_cheats_cvars()
{
	gCV_DisableSvCheats = new Convar("shavit_core_disable_sv_cheats", "1", "Force sv_cheats to 0.", 0, true, 0.0, true, 1.0);

#if !DEBUG
	sv_cheats = FindConVar("sv_cheats");
	sv_cheats.AddChangeHook(sv_cheats_hook);

	for (int i = 0; i < sizeof(gS_CheatCommands); i++)
	{
		AddCommandListener(Command_Cheats, gS_CheatCommands[i]);
	}
#endif
}

void Anti_sv_cheats_OnConfigsExecuted()
{
	if (gCV_DisableSvCheats.BoolValue)
	{
#if !DEBUG
		sv_cheats.SetInt(0);
#endif
	}
}

void Remove_sv_cheat_Impluses(int client, int &impulse)
{
#if !DEBUG
	if (impulse && sv_cheats.BoolValue && !(GetUserFlagBits(client) & ADMFLAG_ROOT))
	{
		switch (impulse)
		{
			// Likely incomplete list of the most cheaty impulses...
			// 76 = spawn npc
			// 81 = something cubemap
			// 82 = create jeep
			// 83 = create airboat
			// 102 = something node
			// 195 = something node
			// 196 = something node
			// 197 = something node
			// 202 = something bloodsplat
			// 203 = remove entity
			case 76, 81, 82, 83, 102, 195, 196, 197, 202, 203:
			{
				impulse = 0;
			}
		}
	}
#endif
}

#if !DEBUG
public void sv_cheats_hook(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (gCV_DisableSvCheats.BoolValue)
	{
		sv_cheats.SetInt(0);
	}
}

public Action Command_Cheats(int client, const char[] command, int args)
{
	if (!sv_cheats.BoolValue || client == 0)
	{
		return Plugin_Continue;
	}

	if (StrContains(command, "kill") != -1 || StrContains(command, "explode") != -1)
	{
		bool bVector = StrContains(command, "vector") != -1;
		bool bKillOther = args > (bVector ? 3 : 0);

		if (!bKillOther)
		{
			return Plugin_Continue;
		}
	}

	if (!(GetUserFlagBits(client) & ADMFLAG_ROOT))
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}
#endif
