/*
 * shavit's Timer - replay-playback.inc file
 * by: shavit, rtldg, carnifex, KiD Fearless
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

#if defined _shavit_replay_playback_included
	#endinput
#endif
#define _shavit_replay_playback_included

#include <shavit/replay-file>

enum //ReplayStatus
{
	Replay_Start,
	Replay_Running,
	Replay_End,
	Replay_Idle
};

enum //ReplayBotType
{
	Replay_Central,
	Replay_Looping, // these are the ones that loop styles, tracks, and (eventually) stages...
	Replay_Dynamic, // these are bots that spawn on !replay when the central bot is taken
	Replay_Prop,    // A prop entity that is being used as a replay...
};

/**
 * Called when replay playback starts.
 * Will be called twice for every replay bot unless the replay is canceled before the second call. Use `delay_elapsed` to check for the first & second time.
 *
 * @param ent                       Entity index for the replay.
 * @param type                      The type of replay. Replay_Prop means `ent` is not a fakeclient, but instead a prop.
 * @param delay_elapsed             `false` when the replay bot just spawned but before the start delay has elapsed. `true` when the start delay has elapsed.
 * @noreturn
 */
forward void Shavit_OnReplayStart(int ent, int type, bool delay_elapsed);

/**
 * Called when replay playback ends.
 * Will be called twice for most replay bots unless the replay bot is canceled before it finishes. See `actually_finished`.
 *
 * @param ent                       Entity index for the replay.
 * @param type                      The type of replay. Replay_Prop means `ent` is not a fakeclient, but instead a prop.
 * @param actually_finished         `false` when the replay runs out of frames and is starting the timer to despawn. `true` when the replay bot is about to despawn. `true` will always run.
 * @noreturn
 */
forward void Shavit_OnReplayEnd(int ent, int type, bool actually_finished);

/**
 * Called when all replays files have been loaded.
 *
 * @noreturn
 */
forward void Shavit_OnReplaysLoaded();

/**
 * Deletes all replays for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map                       Map name.
 * @noreturn
 */
native void Shavit_Replay_DeleteMap(const char[] map);

/**
 * Deletes the specified replay file.
 * Replay data will be unloaded if necessary.
 *
 * @param map                       Map display name.
 * @param style                     Bhop style.
 * @param track                     Timer track.
 * @param accountid                 Account ID to validate against, 0 to skip validation.
 * @return                          true if replay existed, false if the steam id didn't match or the file didn't exist.
 */
native bool Shavit_DeleteReplay(const char[] map, int style, int track, int accountid = 0);

/**
 * Retrieves the engine time of the replay bot's first frame.
 *
 * @param entity                    Entity index.
 * @return                          The engine time of the replay bot's first frame.
 */
native float Shavit_GetReplayBotFirstFrameTime(int entity);

/**
 * Retrieve the replay bot's entity index.
 *
 * @param style                     Style you want. -1 if you want the central bot. If no central bot, the first bot it finds it used.
 * @param track                     Track you want. -1 if you want the central bot. If no central bot, the first bot it finds it used.
 * @return                          Client index for the replay bot. -1 if not found.
 */
native int Shavit_GetReplayBotIndex(int style, int track);

/**
 * Retrieve the style being played by the replay bot.
 *
 * @param entity                    Entity index.
 * @return                          Style being played by the replay bot. -1 if the replay bot is idle.
 */
native int Shavit_GetReplayBotStyle(int entity);

/**
 * Retrieve the timer track being played by the replay bot.
 *
 * @param entity                    entity index.
 * @return                          Timer track replayed by the bot. -1 if the replay bot is idle.
 */
native int Shavit_GetReplayBotTrack(int entity);

/**
 * Gets the replay bot type setting of the server.
 *
 * @return                          See ReplayBotType enum.
 */
native int Shavit_GetReplayBotType();

/**
 * Retrieve the replay bot's current played frame.
 *
 * @param entity                    Entity index.
 * @return                          Current played frame.
 */
native int Shavit_GetReplayBotCurrentFrame(int entity);

/**
 * Retrieves the client who started the replay.
 *
 * @param                           Replay entity.
 * @return                          Client index of starter. Can be 0
 */
native int Shavit_GetReplayStarter(int ent);

/**
 * Retrieves the replay's buttons for its current tick.
 * Really, this is only useful for things like replay props.
 *
 * @param                           Replay entity.
 * @param anglediff                 The angle difference between the previous and current y angles.
 *
 * @return                          buttons
 */
native int Shavit_GetReplayButtons(int ent, float& anglediff);

/**
 * Retrieves the replay's entity flags for its current tick.
 * @param                           Replay entity.
 * @return                          Entity flags
 */
native int Shavit_GetReplayEntityFlags(int ent);

/**
 * Retrieves a replay's frame count.
 *
 * @param style                     Style.
 * @param track                     Track.
 * @return                          Frame count.
 */
native int Shavit_GetReplayFrameCount(int style, int track);

/**
 * Retrieves a replay's pre-run frame count.
 *
 * @param style                     Style.
 * @param track                     Track.
 * @return                          Frame count.
 */
native int Shavit_GetReplayPreFrames(int style, int track);

/**
 * Retrieves a replay's post-run frame count.
 *
 * @param style                     Style.
 * @param track                     Track.
 * @return                          Frame count.
 */
native int Shavit_GetReplayPostFrames(int style, int track);

/**
 * Retrieves the frame count from the currently running replay bot's frame_cache_t.
 *
 * @param bot                       Replay bot entity.
 * @return                          Frame count.
 */
native int Shavit_GetReplayCacheFrameCount(int bot);

/**
 * Retrieves the pre-run frame count from the currently running replay bot's frame_cache_t.
 *
 * @param bot                       Replay bot entity.
 * @return                          Frame count.
 */
native int Shavit_GetReplayCachePreFrames(int bot);

/**
 * Retrieves the post-run frame count from the currently running replay bot's frame_cache_t.
 *
 * @param bot                       Replay bot entity.
 * @return                          Frame count.
 */
native int Shavit_GetReplayCachePostFrames(int bot);

/**
 * Retrieves the replay data for the given style and track.
 *
 * @param style                     Style.
 * @param track                     Track.
 * @param cheapCloneHandle          False means we duplicate the frames (ArrayList.Clone). True means we clone the handle to the frames (CloneHandle).
 *
 * @return                          ArrayList with proper replay data, or null if there is no recorded data. Delete this handle when you're done with it.
 */
native ArrayList Shavit_GetReplayFrames(int style, int track, bool cheapCloneHandle=false);

/**
 * Retrieves a replay's total length in seconds.
 *
 * @param style                     Style.
 * @param track                     Track.
 * @return                          Replay length.
 */
native float Shavit_GetReplayLength(int style, int track);

/**
 * Retrieves the replay's total length in seconds from the currently running replay bot's frame_cache_t.
 *
 * @param bot                       Replay bot entity.
 * @return                          Replay length.
 */
native float Shavit_GetReplayCacheLength(int bot);

/**
 * Retrieves an actively playing replay's time.
 *
 * @param entity                    Entity index.
 * @return                          The bot's current time in the replay.
 */
native float Shavit_GetReplayTime(int entity);

/**
 * Retrieves a replay holder's name.
 *
 * @param style                     Style.
 * @param track                     Track.
 * @param buffer                    Buffer string.
 * @param length                    String length.
 * @noreturn
 */
native void Shavit_GetReplayName(int style, int track, char[] buffer, int length);

/**
 * Retrieves a replay holder's name from an active replay bot.
 *
 * @param bot                       Bot.
 * @param buffer                    Buffer string.
 * @param length                    String length.
 * @noreturn
 */
native void Shavit_GetReplayCacheName(int bot, char[] buffer, int length);

/**
 * Retrieves the folder path where the replay files are saved.
 *
 * @param buffer                    Buffer string.
 * @param length                    String length.
 * @noreturn
 */
native void Shavit_GetReplayFolderPath(char[] buffer, int length);

/**
 * Checks if there's loaded replay data for a bhop style or not.
 *
 * @param style                     Style.
 * @param track                     Track.
 * @return                          Boolean value of if there's loaded replay data.
 */
native bool Shavit_IsReplayDataLoaded(int style, int track);

/**
 * Checks if the given entity is a replay bot (fakeclient) or replay prop.
 *
 * @param                           The entity index to check.
 */
native bool Shavit_IsReplayEntity(int ent);

/**
 * Sets the sReplayName value in the bot's frame_cache_t.
 * Useful for `Shavit_StartReplayFromFile` and family.
 *
 * @param bot                       The replay bot entity.
 * @param name                      The name to use.
 */
native void Shavit_SetReplayCacheName(int bot, char[] name);

/**
 * Starts a replay given a style and track.
 *
 * @param style                     Bhop style.
 * @param track                     Timer track.
 * @param delay                     Delay until starting. If -1.0, then uses shavit_replay_delay
 * @param client                    Client index.
 * @param bot                       Bot to play on. Should be of type Replay_Central or Replay_Dynamic. -1 to create new replay bot.
 * @param type                      ReplayBotType. Replay_Prop needs `bot` to be -1.
 * @param ignorelimit               Ignore cvar limit for dynamic bots.
 * @return                          Replay entity. 0 is returned if couldn't be created.
 */
native int Shavit_StartReplay(int style, int track, float delay, int client, int bot, int type, bool ignorelimit);

/**
 * Starts a replay with a given set of frames.
 * Useful for playing a replay downloaded from a global WR database...
 *
 * @param style                     Bhop style.
 * @param track                     Timer track.
 * @param delay                     Delay until starting. If -1.0, then uses shavit_replay_delay
 * @param client                    Client index.
 * @param bot                       Bot to play on. Should be of type Replay_Central or Replay_Dynamic. -1 to create new replay bot.
 * @param type                      ReplayBotType. Replay_Prop needs `bot` to be -1.
 * @param ignorelimit               Ignore cvar limit for dynamic bots.
 * @param cache                     frame_cache_t filled with replay info and frames.
 * @param size                      sizeof(frame_cache_t). Used to throw errors at you if you don't recompile plugins.
 * @return                          Replay entity. 0 is returned if couldn't be created.
 */
native int Shavit_StartReplayFromFrameCache(int style, int track, float delay, int client, int bot, int type, bool ignorelimit, any[] cache, int size = sizeof(frame_cache_t));

/**
 * Starts a replay from a replay file.
 * Useful for playing a replay downloaded from a global WR database...
 *
 * @param style                     Bhop style.
 * @param track                     Timer track.
 * @param delay                     Delay until starting. If -1.0, then uses shavit_replay_delay
 * @param client                    Client index.
 * @param bot                       Bot to play on. Should be of type Replay_Central or Replay_Dynamic. -1 to create new replay bot.
 * @param type                      ReplayBotType. Replay_Prop needs `bot` to be -1.
 * @param ignorelimit               Ignore cvar limit for dynamic bots.
 * @param path                      File path to replay
 * @return                          Replay entity. 0 is returned if couldn't be created.
 */
native int Shavit_StartReplayFromFile(int style, int track, float delay, int client, int bot, int type, bool ignorelimit, const char[] path);

/**
 * Reloads a specific replay into the replay bot cache.
 * Note: Not guaranteed to work with legacy replay bots.
 *
 * @param style                     Replay style.
 * @param track                     Replay track.
 * @param restart                   Restart the playback of the replay bot if it's playing?
 * @param path                      Path to the replay file. Use `BuildPath(Path_SM, ...)` to generate one. Leave as empty to use default.
 * @return                          Was the replay loaded?
 */
native bool Shavit_ReloadReplay(int style, int track, bool restart, char[] path = "");

/**
 * Reloads all of the replays for the map.
 *
 * @param restart                   Restart the playback of the replay bots?
 * @return                          Amount of loaded replays.
 */
native int Shavit_ReloadReplays(bool restart);

/**
 * Gets time from replay frame that is closest to client.
 *
 * @param client                    Client index.
 * @param outlength                 Fills this variable with the total length of the replay that's being compared to.
 *
 * @return                          Replay time.
 */
native float Shavit_GetClosestReplayTime(int client, float &outlength=0.0);

/**
 * Gets the style the client is getting the closest replay time from.
 *
 * @param client                    Client index.
 *
 * @return                          style
 */
native int Shavit_GetClosestReplayStyle(int client);

/**
 * Sets the style to grab the closest replay time from.
 *
 * @param client                    Client index.
 * @param style                     Style blah.
 *
 * @param                           Style to grab replay time from. -1 to use the client's current style.
 *
 * @noreturn
 */
native void Shavit_SetClosestReplayStyle(int client, int style);

/**
 * Gets velocity from replay frame that is closest to client.
 *
 * @param client                    Client index.
 * @param threeD                    true for 3D velocity difference. false for 2D velocity difference.
 *
 * @return                          Velocity difference from closest replay position.
 */
native float Shavit_GetClosestReplayVelocityDifference(int client, bool threeD);

/**
 * Gets the replay status
 *
 * @param                           Replay bot (or prop) entity
 *
 * @return                          Replay's status
 */
native int Shavit_GetReplayStatus(int ent);

/*
 * Used to find a looping replay bot from the loop config name.
 *
 * @param name                      Looping bot config name. An example is "Other Styles" from the default set of looping bots in shavit-replay.cfg
 *
 * @return                          The client index of the looping replay bot. -1 if could not find the config name. 0 if could not find the replay bot client.
 */
native int Shavit_GetLoopingBotByName(const char[] name);

/*
 * Retrieves the playback speed of the replay bot.
 *
 * @param bot
 *
 * @return                          Should be 0.5, 1.0, or 2.0.
 */
native float Shavit_GetReplayPlaybackSpeed(int bot);


public SharedPlugin __pl_shavit_replay_playback =
{
	name = "shavit-replay-playback",
	file = "shavit-replay-playback.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_replay_playback_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_DeleteReplay");
	MarkNativeAsOptional("Shavit_GetReplayBotCurrentFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrameTime");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");
	MarkNativeAsOptional("Shavit_GetReplayBotStyle");
	MarkNativeAsOptional("Shavit_GetReplayBotTrack");
	MarkNativeAsOptional("Shavit_GetReplayBotType");
	MarkNativeAsOptional("Shavit_GetReplayStarter");
	MarkNativeAsOptional("Shavit_GetReplayFrameCount");
	MarkNativeAsOptional("Shavit_GetReplayFrames");
	MarkNativeAsOptional("Shavit_GetReplayLength");
	MarkNativeAsOptional("Shavit_GetReplayName");
	MarkNativeAsOptional("Shavit_GetReplayCacheName");
	MarkNativeAsOptional("Shavit_GetReplayStatus");
	MarkNativeAsOptional("Shavit_GetReplayTime");
	MarkNativeAsOptional("Shavit_IsReplayDataLoaded");
	MarkNativeAsOptional("Shavit_ReloadReplay");
	MarkNativeAsOptional("Shavit_ReloadReplays");
	MarkNativeAsOptional("Shavit_Replay_DeleteMap");
	MarkNativeAsOptional("Shavit_StartReplay");
	MarkNativeAsOptional("Shavit_GetClosestReplayTime");
	MarkNativeAsOptional("Shavit_GetClosestReplayVelocityDifference");
	MarkNativeAsOptional("Shavit_IsReplayEntity");
	MarkNativeAsOptional("Shavit_GetReplayButtons");
	MarkNativeAsOptional("Shavit_GetReplayEntityFlags");
	MarkNativeAsOptional("Shavit_GetClosestReplayStyle");
	MarkNativeAsOptional("Shavit_SetClosestReplayStyle");
	MarkNativeAsOptional("Shavit_GetReplayCacheFrameCount");
	MarkNativeAsOptional("Shavit_GetReplayCacheLength");
	MarkNativeAsOptional("Shavit_StartReplayFromFrameCache");
	MarkNativeAsOptional("Shavit_StartReplayFromFile");
	MarkNativeAsOptional("Shavit_GetReplayPreFrames");
	MarkNativeAsOptional("Shavit_GetReplayPostFrames");
	MarkNativeAsOptional("Shavit_GetReplayCachePreFrames");
	MarkNativeAsOptional("Shavit_GetReplayCachePostFrames");
	MarkNativeAsOptional("Shavit_GetLoopingBotByName");
	MarkNativeAsOptional("Shavit_SetReplayCacheName");
	MarkNativeAsOptional("Shavit_GetReplayFolderPath");
	MarkNativeAsOptional("Shavit_GetReplayPlaybackSpeed");
}
#endif
