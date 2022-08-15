/*
 * shavit's Timer - weapon stocks
 * by: shavit, psychonic, Kxnrl, rtldg
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

#if defined _shavit_weapon_stocks_included
	#endinput
#endif
#define _shavit_weapon_stocks_included

// based on code by Kxnrl in SurfTimer
//  which is based on code by splewis from csgo-deathmatch?
//  https://github.com/Maxximou5/csgo-deathmatch/pull/24/commits/207cbfe3f1b9a1082c4a710841c190bb753485dc#diff-2c9694977d0a3fe527ca8b484add6a58f53bab303e5dcaa583cb2917ec04d89cR3122-R3130
// https://github.com/surftimer/SurfTimer/commit/134887a29a396e01a721a78ab69e81a80593411a#diff-0b2bae39ae9de87ea2952bfd12c8777c7301e06ce683acc518229704cf024c33R4894-R4910
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

// based on testsuite code from psychonic
// https://github.com/alliedmodders/sourcemod/blob/c5701503185d7e1cb8411c7347abdd31eee75c4e/plugins/testsuite/entpropelements.sp#L88-L96
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
