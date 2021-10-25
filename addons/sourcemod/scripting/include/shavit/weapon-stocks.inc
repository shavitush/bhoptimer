
#if defined _shavit_weapon_stocks_included
	#endinput
#endif
#define _shavit_weapon_stocks_included

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
