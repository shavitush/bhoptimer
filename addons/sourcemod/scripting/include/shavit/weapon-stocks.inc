/*
 * shavit's Timer - weapon stocks
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

#if defined _shavit_weapon_stocks_included
	#endinput
#endif
#define _shavit_weapon_stocks_included

stock int GiveSkinnedWeapon(int client, const char[] classname)
{
	int target_team = 0;
	int current_team = 0;

	if (StrContains(classname, "usp") != -1)
	{
		target_team = 3;
	}
	else if (StrContains(classname, "glock") != -1)
	{
		target_team = 2;
	}

	if (target_team != 0)
	{
		current_team = GetEntProp(client, Prop_Send, "m_iTeamNum");

		if (current_team != target_team)
		{
			SetEntProp(client, Prop_Send, "m_iTeamNum", target_team);
		}
	}

	int weapon = GivePlayerItem(client, classname);

	if (current_team != target_team)
	{
		SetEntProp(client, Prop_Send, "m_iTeamNum", current_team);
	}

	return weapon;
}

stock void RemoveAllWeapons(int client)
{
	int weapon = -1, max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < max; i++)
	{
		if ((weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i)) == -1)
			continue;

		if (RemovePlayerItem(client, weapon))
		{
			AcceptEntityInput(weapon, "Kill");
		}
	}
}

stock void SetMaxWeaponAmmo(int client, int weapon, bool setClip1)
{
	static EngineVersion engine = Engine_Unknown;

	if (engine == Engine_Unknown)
	{
		engine = GetEngineVersion();
	}

	int iAmmo = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");

	if (iAmmo < 0)
	{
		return;
	}

	SetEntProp(client, Prop_Send, "m_iAmmo", 255, 4, iAmmo);

	if (engine == Engine_CSGO)
	{
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 255);
	}

	if (setClip1)
	{
		int amount = GetEntProp(weapon, Prop_Send, "m_iClip1") + 1;

		if (HasEntProp(weapon, Prop_Send, "m_bBurstMode") && GetEntProp(weapon, Prop_Send, "m_bBurstMode"))
		{
			amount += 2;
		}

		SetEntProp(weapon, Prop_Data, "m_iClip1", amount);
	}
}
