/*
 * shavit's Timer - misc.inc file
 * by: EvanIMK, rtldg
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

#if defined _shavit_misc_included
	#endinput
#endif
#define _shavit_misc_included

/**
 * Checks if a player is hiding players
 *
 * @param client                    Client index.
 * @return                          Boolean value.
 */
native bool Shavit_IsClientUsingHide(int client);

/**
 * Called before clan tag variables are processed.
 *
 * @param client					Client index.
 * @param clantag					Reference to the clan tag buffer.
 * @param clantaglength				Max length of the customtag buffer.
 * @return							Plugin_Handled or Plugin_Stop to block the clan tag from changing. Anything else to pass along new values.
 */
forward Action Shavit_OnClanTagChangePre(int client, char[] clantag, int clantaglength);

/**
 * Called after clan tags are changed.
 *
 * @param client					Client index.
 * @param customtag					Reference to the custom clan tag buffer.
 * @param customtaglength			Max length of the customtag buffer.
 * @noreturn
 */
forward void Shavit_OnClanTagChangePost(int client, char[] customtag, int customtaglength);

public SharedPlugin __pl_shavit_misc =
{
	name = "shavit-misc",
	file = "shavit-misc.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_misc_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_IsClientUsingHide");
}
#endif
