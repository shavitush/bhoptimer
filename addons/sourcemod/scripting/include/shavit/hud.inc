/*
 * shavit's Timer - hud.inc file
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

#if defined _shavit_hud_included
	#endinput
#endif
#define _shavit_hud_included

#define HUD_NONE                0
#define HUD_MASTER              (1 << 0) // master setting
#define HUD_CENTER              (1 << 1) // show hud as hint text
#define HUD_ZONEHUD             (1 << 2) // show start/end zone hud
#define HUD_OBSERVE             (1 << 3) // show the HUD of the player you spectate
#define HUD_SPECTATORS          (1 << 4) // show list of spectators
#define HUD_KEYOVERLAY          (1 << 5) // show a key overlay
#define HUD_HIDEWEAPON          (1 << 6) // hide the player's weapon
#define HUD_TOPLEFT             (1 << 7) // show top left white HUD with WR/PB times
#define HUD_SYNC                (1 << 8) // shows sync at right side of the screen (css only)
#define HUD_TIMELEFT            (1 << 9) // shows time left at right tside of the screen (css only)
#define HUD_2DVEL               (1 << 10) // shows 2d velocity
#define HUD_NOSOUNDS            (1 << 11) // disables sounds on personal best, world record etc
#define HUD_NOPRACALERT         (1 << 12) // hides practice mode chat alert
#define HUD_USP                 (1 << 13) // makes you spawn with a USP
#define HUD_GLOCK               (1 << 14) // makes you spawn with a Glock

// HUD2 - these settings will *disable* elements for the main hud
#define HUD2_TIME               (1 << 0)
#define HUD2_SPEED              (1 << 1)
#define HUD2_JUMPS              (1 << 2)
#define HUD2_STRAFE             (1 << 3)
#define HUD2_SYNC               (1 << 4)
#define HUD2_STYLE              (1 << 5)
#define HUD2_RANK               (1 << 6)
#define HUD2_TRACK              (1 << 7)
#define HUD2_SPLITPB            (1 << 8)
#define HUD2_MAPTIER            (1 << 9)
#define HUD2_TIMEDIFFERENCE     (1 << 10)
#define HUD2_PERFS              (1 << 11)
#define HUD2_TOPLEFT_RANK       (1 << 12)
#define HUD2_VELOCITYDIFFERENCE (1 << 13)
#define HUD2_USPSILENCER        (1 << 14) // spawns usps with a silencer on (only used in CSS)
#define HUD2_GLOCKBURST         (1 << 15) // spawns glocks with burst

#define HUD_DEFAULT             (HUD_MASTER|HUD_CENTER|HUD_ZONEHUD|HUD_OBSERVE|HUD_TOPLEFT|HUD_SYNC|HUD_TIMELEFT|HUD_2DVEL|HUD_SPECTATORS)
#define HUD_DEFAULT2            (HUD2_PERFS)

/**
 * Called when top left HUD updates.
 *
 * @param client                    Client index that recieves the hud.
 * @param target                    Target entity that is either the client or what the client is spectating.
 * @param topleft                   Reference to the HUD buffer.
 * @param topleftlength             Max length of the topleft buffer.
 * @return                          Plugin_Handled or Plugin_Stop to block the HUD message from appearing. Anything else to pass along new values.
 */
forward Action Shavit_OnTopLeftHUD(int client, int target, char[] topleft, int topleftlength);

/**
 * Force an HUD update for a player. Requires shavit-hud.
 *
 * @param client                    Client index.
 * @param spectators                Should also update it for the player's spectators?
 * @error                           Error code 200 if client isn't valid.
 * @return                          Amount of players that had their HUD updated (client + spectators) or -1 on error.
 */
native int Shavit_ForceHUDUpdate(int client, bool spectators);

/**
 * Gets the HUD settings of a player.
 * See the HUD_* defines for information.
 *
 * @param client                    Client index.
 * @return                          HUD settings.
 */
native int Shavit_GetHUDSettings(int client);

/**
 * Gets the HUD2 settings of a player.
 * See the HUD2_* defines for information.
 *
 * @param client                    Client index.
 * @return                          HUD settings.
 */
native int Shavit_GetHUD2Settings(int client);

public SharedPlugin __pl_shavit_hud =
{
	name = "shavit-hud",
	file = "shavit-hud.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_hud_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_ForceHUDUpdate");
	MarkNativeAsOptional("Shavit_GetHUDSettings");
	MarkNativeAsOptional("Shavit_GetHUD2Settings");
}
#endif
