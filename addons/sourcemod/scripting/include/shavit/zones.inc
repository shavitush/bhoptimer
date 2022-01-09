/*
 * shavit's Timer - zones.inc file
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

#if defined _shavit_zones_included
	#endinput
#endif
#define _shavit_zones_included

#define MAX_ZONES 64
#define MAX_STAGES 51 // 😐 kind of arbitrary but also some space between this and MAX_ZONES

enum
{
	Zone_Start,
	Zone_End,
	Zone_Respawn,
	Zone_Stop,
	Zone_Slay,
	Zone_Freestyle,
	Zone_CustomSpeedLimit,
	Zone_Teleport,
	Zone_CustomSpawn,
	Zone_Easybhop,
	Zone_Slide,
	Zone_Airaccelerate,
	Zone_Stage,
	Zone_NoTimerGravity,
	Zone_Gravity,
	ZONETYPES_SIZE
};

enum
{
	ZF_ForceRender = (1 << 0),
	ZF_Prebuilt    = (1 << 1), // comes from mod_zone_* entities
};

#if 0
enum struct zone_cache_t
{
	bool bZoneInitialized;
	int iType;
	int iTrack; // 0 - main, 1 - bonus1 etc
	int iEntity;
	int iDatabaseID; // when ZF_Prebuilt, this is the entity's m_iHammerID
	int iFlags;
	int iData;
	float fCorner1[3];
	float fCorner2[3];
	float fDestination[3];
}
#else
enum struct zone_cache_t
{
	bool bZoneInitialized;
	bool bPrebuilt; // comes from mod_zone_* entities
	int iZoneType;
	int iZoneTrack; // 0 - main, 1 - bonus etc
	int iEntityID;
	int iDatabaseID;
	int iZoneFlags;
	int iZoneData;
}
#endif

/**
 * Called when a player enters a zone.
 *
 * @param client                    Client index.
 * @param type                      Zone type.
 * @param track                     Zone track.
 * @param id                        Zone ID.
 * @param entity                    Zone trigger entity index.
 * @param data                      Zone data if any.
 * @noreturn
 */
forward void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data);

/**
 * Called when a player leaves a zone.
 *
 * @param client                    Client index.
 * @param type                      Zone type.
 * @param track                     Zone track.
 * @param id                        Zone ID.
 * @param entity                    Zone trigger entity index.
 * @param data                      Zone data if any.
 * @noreturn
 */
forward void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data);

/**
 * Called when a player leaves a zone.
 *
 * @param client                    Client index.
 * @param stageNumber               Stage number.
 * @param message                   The stage time message that will be printed.
 * @param maxlen                    The buffer size of message.
 * @return                          Plugin_Handled to block the timer from printing msg to the client. Plugin_Continue to let the timer print msg.
 */
forward Action Shavit_OnStageMessage(int client, int stageNumber, char[] message, int maxlen);

/**
 * Retrieve the zone ID for a given stage number.
 * Will return exception if stagenumber doesn't have a zone.
 *
 * @param stage                     Stage number.
 * @param track                     Track number.
 * @return                          Zone ID of stage.
 */
native int Shavit_GetStageZone(int stage, int track=Track_Main);

/**
 * Checks if a mapzone exists.
 *
 * @param type                      Mapzone type.
 * @param track                     Mapzone track, -1 to ignore track.
 * @return                          Boolean value.
 */
native bool Shavit_ZoneExists(int type, int track);

/**
 * Checks if a player is inside a mapzone.
 *
 * @param client                    Client index.
 * @param type                      Mapzone type.
 * @param track                     Mapzone track, -1 to ignore track.
 * @return                          Boolean value.
 */
native bool Shavit_InsideZone(int client, int type, int track);

/**
 * Gets the specified zone's data.
 *
 * @param zoneid                    ID of the zone we query the data of.
 * @return                          Zone data. 0 if none is specified.
 */
native int Shavit_GetZoneData(int zoneid);

/**
 * Gets the specified zone's flags.
 *
 * @param zoneid                    ID of the zone we query the flags of.
 * @return                          Zone flags. 0 if none is specified.
 */
native int Shavit_GetZoneFlags(int zoneid);

/**
 * Deletes all map zones for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map                       Map name.
 * @noreturn
 */
native void Shavit_Zones_DeleteMap(const char[] map);

/**
 * Checks if a player is inside a mapzone.
 *
 * @param client                    Client index.
 * @param type                      Mapzone type.
 * @param track                     Mapzone track, -1 to ignore track.
 * @param zoneid                    Reference to variable that will hold the zone's ID.
 * @return                          Boolean value.
 */
native bool Shavit_InsideZoneGetID(int client, int type, int track, int &zoneid);

/**
 * Checks if a player is in the process of creating a mapzone.
 *
 * @param client                    Client index.
 * @return                          Boolean value.
 */
native bool Shavit_IsClientCreatingZone(int client);

/**
 * Retrieve the highest stage number for a given track.
 *
 * @param track                     Track number.
 * @return                          Number of stages.
 */
native int Shavit_GetHighestStage(int track);

/**
 * Retrieve the client's current stage number.
 *
 * @param client                    Client index.
 * @return                          The client's current stage number.
 */
native int Shavit_GetClientLastStage(int client);

/**
 * Returns the zone index for the entity if available.
 *
 * @param entity                    Client index.
 * @return                          -1 if not a zone entity. >=0 for a zone index.
 */
native int Shavit_GetZoneID(int entity);

/**
 * Returns the zone track.
 *
 * @param zoneid                    Zone index.
 * @return                          Zone track.
 */
native int Shavit_GetZoneTrack(int zoneid);

/**
 * Returns the zone type.
 *
 * @param zoneid                    Zone index.
 * @return                          Zone type.
 */
native int Shavit_GetZoneType(int zoneid);

/**
 * Retrieve the WR's stage time.
 *
 * @param track                     Track index.
 * @param style                     Style index.
 * @param stage                     Stage number.
 * @return                          The stage time of the WR run. Can be 0.0 if the WR run didn't hit the stage or if the stage doesn't exist.
 */
native float Shavit_GetStageWR(int track, int style, int stage);

/**
 * Retrieve the client's PB stage time.
 *
 * @param client                    Client index.
 * @param track                     Track index.
 * @param style                     Style index.
 * @param stage                     Stage number.
 * @return                          The stage time of the PB run. Can be 0.0 if the PB run didn't hit the stage or if the stage doesn't exist.
 */
//native float Shavit_GetStagePB(int client, int track, int style, int stage);

//native float Shavit_GetStageWRCP(int track, int style, int stage);
//native float Shavit_GetStagePBCP(int client, int track, int style, int stage);

/**
 * Sets the player's current location as their spawn location for the specified track.
 *
 * @param client                    Client index.
 * @param track                     Timer track.
 * @param anglesonly                Whether to save angles only.
 * @noreturn
 */
native void Shavit_SetStart(int client, int track, bool anglesonly);

/**
 * Deletes the player's current set start position for the specified track.
 *
 * @param client                    Client index.
 * @param track                     Timer track.
 * @noreturn
 */
native void Shavit_DeleteSetStart(int client, int track);

#if 0
native void Shavit_RemoveAllZones();

native int Shavit_GetZoneCount();

native void Shavit_GetZone(int index, any[] zonecache, int size = sizeof(zone_cache_t));

native int Shavit_AddZone(any[] zonecache, int size = sizeof(zone_cache_t));
#endif

public SharedPlugin __pl_shavit_zones =
{
	name = "shavit-zones",
	file = "shavit-zones.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_zones_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetZoneData");
	MarkNativeAsOptional("Shavit_GetZoneFlags");
	MarkNativeAsOptional("Shavit_GetStageZone");
	MarkNativeAsOptional("Shavit_GetStageCount");
	MarkNativeAsOptional("Shavit_InsideZone");
	MarkNativeAsOptional("Shavit_InsideZoneGetID");
	MarkNativeAsOptional("Shavit_IsClientCreatingZone");
	MarkNativeAsOptional("Shavit_ZoneExists");
	MarkNativeAsOptional("Shavit_Zones_DeleteMap");
	MarkNativeAsOptional("Shavit_SetStart");
	MarkNativeAsOptional("Shavit_DeleteSetStart");
	MarkNativeAsOptional("Shavit_GetClientLastStage");
	MarkNativeAsOptional("Shavit_GetZoneTrack");
	MarkNativeAsOptional("Shavit_GetZoneType");
	MarkNativeAsOptional("Shavit_GetZoneID");
}
#endif
