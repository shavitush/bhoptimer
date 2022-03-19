/*
 * shavit's Timer - Checkpoints
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
	StringMap customdata;
}

/**
 * Called when a player teleports with checkpoints.
 *
 * @param client                    Client index.
 * @param index                     Checkpoint that was teleported to.
 * @return                          Plugin_Continue to allow teleporting, anything else to prevent.
 */
forward Action Shavit_OnTeleportPre(int client, int index);

/**
 * Called when a player teleports with checkpoints.
 *
 * @param client                    Client index.
 * @param index                     Checkpoint that was teleported to.
 * @return                          Unused. Use Shavit_OnTeleportPre if you want to block teleporting.
 */
forward Action Shavit_OnTeleport(int client, int index);

/**
 * Called when a player saves a checkpoint.
 *
 * @param client                    Client index.
 * @param index                     Checkpoint that was saved to.
 * @param overflow                  Does this checkpoint shift the rest.
 * @return                          Plugin_Continue to allow saving, anything else to prevent.
 */
forward Action Shavit_OnSavePre(int client, int index, bool overflow);

/**
 * Called when a player saves a checkpoint.
 *
 * @param client                    Client index.
 * @param index                     Checkpoint that was saved to.
 * @param overflow                  Does this checkpoint shift the rest.
 * @return                          Unused. Use Shavit_OnSavePre if you want to block checkpoint saving.
 */
forward Action Shavit_OnSave(int client, int index, bool overflow);

/**
 * Called when a player deletes a checkpoint.
 *
 * @param client                    Client index.
 * @param index                     Checkpoint that will be deleted.
 * @return                          Plugin_Continue to continue deletion, anything else to prevent.
 */
forward Action Shavit_OnDelete(int client, int index);

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
 * @param client                    Client index.
 * @param param2                    Second parameter in the callback, usually the item selected.
 * @param info                      reference copy of the info string used in the callback
 * @param maxlength                 length of the info buffer
 * @param currentCheckpoint         Clients current checkpoint
 * @param maxCPs                    Max checkpoints the client can use
 * @return                          Plugin_Continue to continue the callback. Return Plugin_Stop to prevent the checkpoints menu from reopening.
 */
forward Action Shavit_OnCheckpointMenuSelect(int client, int param2, char[] info, int maxlength, int currentCheckpoint, int maxCPs);

/**
 * Called when a checkpoint cache is saved.
 *
 * @param client                    The client the checkpoint cache is being saved for.
 * @param cache                     The resulting checkpoint cache structure.
 * @param index                     The resulting checkpoint index for this checkpoint cache. -1 if the cache is being saved as "persistent data" for rejoins/spectating.
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
 * @param index                     The checkpoint index for this cache. -1 if the cache is being loaded from "persistent data" for rejoins/spectating.
 *
 * @noreturn
 */
forward void Shavit_OnCheckpointCacheLoaded(int client, cp_cache_t cache, int index);

/**
 * Called when a checkpoint cache is being deleted.
 *
 * @param cache                     The cache.
 *
 * @noreturn
 */
forward void Shavit_OnCheckpointCacheDeleted(cp_cache_t cache);

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
 * Teleports client to the checkpoint at given index
 *
 * @param client                    Client index
 * @param index                     Index of CP to teleport to
 * @param suppress                  Supress checkpoint message
 *
 * @noreturn
 */
native void Shavit_TeleportToCheckpoint(int client, int index, bool suppress = false);

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
 * Checks whether the client has savestate data.
 *
 * @param client                    Client index
 *
 * @return                          Whether a savestate or rejoin-savestate data exists for the client.
 */
native bool Shavit_HasSavestate(int client);

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

	MarkNativeAsOptional("Shavit_HasSavestate");
}
#endif
