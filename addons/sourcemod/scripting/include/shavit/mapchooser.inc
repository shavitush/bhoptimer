/*
 * shavit's Timer - mapchooser.inc file
 * by: SlidyBat, KiD Fearless, mbhound, rtldg
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

#if defined _shavit_mapchooser_included
	#endinput
#endif
#define _shavit_mapchooser_included

/**
 * Called when a player RTV's.
 * Requires shavit-mapchooser.
 *
 * @param client                    Client index.
 * @noreturn
 */
forward void SMC_OnRTV(int client);

/**
 * Called when a player UNRTV's.
 * Requires shavit-mapchooser.
 *
 * @param client                    Client index.
 * @noreturn
 */
forward void SMC_OnUnRTV(int client);

/**
 * Called when the map changes from an RTV.
 * Requires shavit-mapchooser.
 *
 * @noreturn
 */
forward void SMC_OnSuccesfulRTV();

/**
 * Returns the ArrayList of maps currently on rotation.
 *
 * @return                            The ArrayList of Maps. Don't delete this handle.
 */
native ArrayList Shavit_GetMapsArrayList();

/**
 * Returns the StringMap of maps currently on rotation.
 *
 * @return                            the StringMap of maps. Don't delete this handle.
 */
native StringMap Shavit_GetMapsStringMap();

public SharedPlugin __pl_shavit_mapchooser =
{
	name = "shavit-mapchooser",
	file = "shavit-mapchooser.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_mapchooser_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetMapsArrayList");
	MarkNativeAsOptional("Shavit_GetMapsStringMap");
}
#endif
