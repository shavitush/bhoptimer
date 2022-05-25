/*
 * shavit's Timer - chat.inc file
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

#if defined _shavit_chat_included
	#endinput
#endif
#define _shavit_chat_included

/*
 * Retrieves the player's chatrank trimmed and without colors.
 *
 * @param client                    Client index
 * @param buf                       Buffer to put the put the chatrank into
 * @param buflen                    Size of buf
 * @param includename               Include {name} in result.
 * @noreturn
 */
native void Shavit_GetPlainChatrank(int client, char[] buf, int buflen, bool includename=false);

public SharedPlugin __pl_shavit_chat =
{
	name = "shavit-chat",
	file = "shavit-chat.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_chat_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetPlainChatrank");
}
#endif
