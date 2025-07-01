/*
 * shavit's Timer - Checkpoints
 * by: shavit, kidfearless, Nairda, GAMMA CASE, rtldg, sh4hrazad, Ciallo-Ani, olivia
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

#if defined _shavit_checkpoints_included
	#endinput
#endif
#define _shavit_checkpoints_included

enum struct cp_cache_t
{
	float fPosition[3];
	float fAngles[3];
	float fVelocity[3];
	MoveType iMoveType;
	float fGravity;
	float fSpeed;
	float fStamina;
	bool bDucked;
	bool bDucking;
	float fDucktime; // m_flDuckAmount in csgo
	float fDuckSpeed; // m_flDuckSpeed in csgo; doesn't exist in css
	int iFlags;
	timer_snapshot_t aSnapshot;
	char sTargetname[64];
	char sClassname[64];
	ArrayList aFrames;
	int iPreFrames;
	bool bSegmented;
	int iGroundEntity;
	int iSteamID;
	ArrayList aEvents;
	ArrayList aOutputWaits;
	float vecLadderNormal[3];
	// This handle will be deleted when the checkpoint is deleted, or something like that...
	// If you want to keep this (which you probably should) then you'd have
	// to use StringMap.Clone() (owned clone) or CloneHandle() (shared object).
	StringMap customdata;

	bool m_bHasWalkMovedSinceLastJump; // csgo only
	float m_ignoreLadderJumpTime; // csgo only

	float m_lastStandingPos[3]; // css only
	float m_ladderSurpressionTimer[2]; // css only // 0 = duration, 1 = remaining
	float m_lastLadderNormal[3]; // css only
	float m_lastLadderPos[3]; // css only

	// used by player_speedmod
	int m_afButtonDisabled;
	// used by trigger_playermovement
	int m_afButtonForced;
}

/**
 * Called when a player will be teleported with checkpoints.
 *
 * @param client                    Client index that will be teleported to the checkpoint.
 * @param index                     Checkpoint that was teleported to.
 * @param target                    Target index that owns the checkpoint.
 * @return                          Plugin_Continue to allow teleporting, anything else to prevent.
 */
forward Action Shavit_OnTeleportPre(int client, int index, int target);

/**
 * Called when a player has been teleported with checkpoints.
 *
 * @param client                    Client index that has been teleported to the checkpoint.
 * @param index                     Checkpoint that was teleported to.
 * @param target                    Target index that owns the checkpoint.
 * @return                          Unused. Use Shavit_OnTeleportPre if you want to block teleporting.
 */
forward Action Shavit_OnTeleport(int client, int index, int target);

/**
 * Called when a player is saving a checkpoint.
 *
 * @param client                    Client index.
 * @param index                     Checkpoint that was saved to.
 * @param overflow                  Does this checkpoint shift the rest.
 * @param duplicate                 Whether the checkpoint to be saved is a duplicate of others
 * @return                          Plugin_Continue to allow saving, anything else to prevent.
 */
forward Action Shavit_OnSavePre(int client, int index, bool overflow, bool duplicate);

/**
 * Called when a player has saved a checkpoint.
 *
 * @param client                    Client index.
 * @param index                     Checkpoint that was saved to.
 * @param overflow                  Does this checkpoint shift the rest.
 * @param duplicate                 Whether the checkpoint that has been saved is a duplicate of others
 * @return                          Unused. Use Shavit_OnSavePre if you want to block checkpoint saving.
 */
forward Action Shavit_OnSave(int client, int index, bool overflow, bool duplicate);

/**
 * Called when a player deletes a checkpoint.
 *
 * @param client                    Client index.
 * @param index                     Checkpoint that will be deleted.
 * @param cleared                   Whether the checkpoint is being deleted due to all the checkpoints being cleared/reset.
                                    The return value CANNOT be used to block deletion of these.
 *
 * @return                          Plugin_Continue to continue deletion, anything else to prevent.
 */
forward Action Shavit_OnDelete(int client, int index, bool cleared);

/**
 * Called after the checkpoint menu has been made and before it's sent to the client.
 *
 * @param client                    Client index.
 * @param segmented                 If the menu was a segmented menu
 * @param menu                      Handle to the menu so you can .AddItem().
 * @return                          Plugin_Handled or Plugin_Stop to stop the menu.
 */
forward Action Shavit_OnCheckpointMenuMade(int client, bool segmented, Menu menu);

/**
 * Called before a selection is processed in the main checkpoint menu.
 *
 * @param client                    Client index who selects in the menu
 * @param param2                    Second parameter in the callback, usually the item selected.
 * @param info                      reference copy of the info string used in the callback
 * @param maxlength                 length of the info buffer
 * @param currentCheckpoint         Clients current checkpoint selected
 * @param maxCPs                    Max checkpoints the client can use
 * @param owner                     Client index who owns the current checkpoint
 * @return                          Plugin_Continue to continue the callback. Return Plugin_Stop to prevent the checkpoints menu from reopening.
 */
forward Action Shavit_OnCheckpointMenuSelect(int client, int param2, char[] info, int maxlength, int currentCheckpoint, int maxCPs, int owner);

/**
 * Called when a checkpoint cache is saved.
 *
 * @param client                    The client the checkpoint cache is being saved for.
 * @param cache                     The resulting checkpoint cache structure.
 * @param index                     The resulting checkpoint index for this checkpoint cache. -1 if the cache is being saved as "persistent data" for rejoins/spectating. 0 if not being saved to checkpoints list.
 * @param target                    The target of the checkpoint cache.
 *
 * @noreturn
 */
forward void Shavit_OnCheckpointCacheSaved(int client, cp_cache_t cache, int index, int target);

/**
 * Called when a checkpoint cache is being loaded.
 *
 * @param client                    The client who is loading the checkpoint cache.
 * @param cache                     The cache.
 * @param index                     The checkpoint index for this cache. -1 if the cache is being loaded from "persistent data" for rejoins/spectating. 0 if the cache is being loaded usually by Shavit_LoadCheckpointCache().
 *
 * @noreturn
 */
forward void Shavit_OnCheckpointCacheLoaded(int client, cp_cache_t cache, int index);

/**
 * Gets the total number of CPs that a client has saved
 *
 * @param client                    Client index
 *
 * @return                          Total number of checkpoints
 */
 native int Shavit_GetTotalCheckpoints(int client);

/**
 * Gets CP data for a client at specified index
 *
 * @param client                    Client index
 * @param index                     Index of CP to get
 * @param cpcache                   Buffer to store cp data in sizeof(cp_cache_t)
 * @param size                      Size of the cpcache buffer, e.g sizeof(cp_cache_t)
 *
 * @noreturn
 */
native bool Shavit_GetCheckpoint(int client, int index, any[] cpcache, int size = sizeof(cp_cache_t));

/**
 * Sets checkpoint data at the given index for the given client
 *
 * @param client                    Client index
 * @param index                     Index of CP to set, or -1 to push cp as last. 0 to push cp to first without erasing.
 * @param cpcache                   Buffer to store cp data in sizeof(cp_cache_t)
 * @param size                      Size of the cpcache buffer, e.g sizeof(cp_cache_t)
 * @param cheapCloneHandle          False means we duplicate aFrames, aEvents, and aOutputWaits (ArrayList.Clone). True means we clone the handle (CloneHandle).
 *
 * @noreturn
 */
native void Shavit_SetCheckpoint(int client, int index, any[] cpcache, int size = sizeof(cp_cache_t), bool cheapCloneHandle=true);

/**
 * Teleports client to the checkpoint at given target and index
 *
 * @param client                    Client index to be teleported
 * @param index                     Index of CP to teleport to
 * @param suppress                  Supress checkpoint message
 * @param target                    Player index that owns the checkpoint. 0 to use the client variable.
 *
 * @noreturn
 */
native void Shavit_TeleportToCheckpoint(int client, int index, bool suppress = false, int target=0);

/**
 * Clears all saved checkpoints for the specified client
 *
 * @param client                    Client index
 *
 * @noreturn
 */
native void Shavit_ClearCheckpoints(int client);

/**
 * Saves a new checkpoint and returns the new checkpoint index
 *
 * @param client                    Client index
 *
 * @return                          The new current checkpoint
 */
native int Shavit_SaveCheckpoint(int client);

/**
 * Gets the current checkpoint index.
 *
 * @param client                    Client index
 *
 * @return                          The current checkpoint
 */
native int Shavit_GetCurrentCheckpoint(int client);

/**
 * Sets the current checkpoint index.
 *
 * @param client                    Client index
 * @param index                     New index to use
 *
 * @noreturn
 */
native void Shavit_SetCurrentCheckpoint(int client, int index);

/**
 * Gets how many times the client has teleported to checkpoints.
 *
 * @param client                    Client index
 *
 * @return                          The number of times the client has teleported to checkpoints.
 */
native int Shavit_GetTimesTeleported(int client);

/**
 * Sets the number of times the client has teleported to checkpoints.
 * This is useful to have if you intend to implement a plugin to save "persistent data" between map changes".
 *
 * @param client                    Client index
 * @param count                     Teleport count
 * @noreturn
 */
native void Shavit_SetTimesTeleported(int client, int count);

/**
 * Checks whether the client has savestate data.
 *
 * @param client                    Client index
 *
 * @return                          Whether a savestate or rejoin-savestate data exists for the client.
 */
native bool Shavit_HasSavestate(int client);

/**
 * Loads a cp_cache_t on a player. AKA teleports players.
 *
 * @param client                    Client index
 * @param cache                     Input cp_cache_t
 * @param index                     -1 if you want the cp_cache_t to be loaded as "persistent data". 0 if not. greater-than-zero if you know what you're doing and intentionally want to spoof the cp_cache_t as a checkpoint index for some reason... I recommend looking at shavit-checkpoints.sp to see how "index" and "isPersistentData" are used to see what kind of difference there is.
 * @param size                      sizeof(cp_cache_t) to mostly ensure the calling plugin has a matching cp_cache_t.
 * @param force                     Forcibly load the cp_cache_t without checking the style access for a player.
 *
 * @return                          Returns whether the checkpoint cache was able to be loaded.
 */
native bool Shavit_LoadCheckpointCache(int client, any[] cache, int index, int size = sizeof(cp_cache_t), bool force = false);

/**
 * Saves a cp_cache_t from a player.
 *
 * @param saver                     The client saving the checkpoint.
 * @param target                    The target the checkpoint cache is being saved from.
 * @param cache                     Output cp_cache_t
 * @param index                     -1 if you want the cp_cache_t to be saved as "persistent data". 0 if not. greater-than-zero if you what you're doing and intentionally want to spoof the cp_cache_t creation as a checkpoint index for some reason... I recommend looking at shavit-checkpoints.sp to see how "index" and "isPersistentData" are used to see what kind of difference there is.
 * @param size                      sizeof(cp_cache_t) to mostly ensure the calling plugin has a matching cp_cache_t.
 * @param saveReplay                Whether or not replay frames will be saved.
 *
 * @noreturn
 */
native void Shavit_SaveCheckpointCache(int saver, int target, any[] cache, int index, int size = sizeof(cp_cache_t), bool saveReplay = false);

public SharedPlugin __pl_shavit_checkpoints =
{
	name = "shavit-checkpoints",
	file = "shavit-checkpoints.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_checkpoints_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetTotalCheckpoints");

	MarkNativeAsOptional("Shavit_GetCheckpoint");
	MarkNativeAsOptional("Shavit_SetCheckpoint");

	MarkNativeAsOptional("Shavit_TeleportToCheckpoint");
	MarkNativeAsOptional("Shavit_ClearCheckpoints");
	MarkNativeAsOptional("Shavit_SaveCheckpoint");

	MarkNativeAsOptional("Shavit_GetCurrentCheckpoint");
	MarkNativeAsOptional("Shavit_SetCurrentCheckpoint");

	MarkNativeAsOptional("Shavit_GetTimesTeleported");
	MarkNativeAsOptional("Shavit_SetTimesTeleported");

	MarkNativeAsOptional("Shavit_HasSavestate");

	MarkNativeAsOptional("Shavit_LoadCheckpointCache");
	MarkNativeAsOptional("Shavit_SaveCheckpointCache");
}
#endif
