/*
 * shavit's Timer - replay-recorder.inc file
 * by: shavit, rtldg,
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

#if defined _shavit_replay_recorder_included
	#endinput
#endif
#define _shavit_replay_recorder_included

/**
 * Called when a player finishes a time. Allows you to save a replay even if the run is not a WR.
 * To save replay to additional paths, call `Shavit_AlsoSaveReplayTo()`
 *
 * @param client                    Client index.
 * @param style                     Style the record was done on.
 * @param time                      Record time.
 * @param jumps                     Jumps amount.
 * @param strafes                   Amount of strafes.
 * @param sync                      Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param track                     Timer track.
 * @param oldtime                   The player's best time on the map before this finish.
 * @param perfs                     Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel                    Player's average velocity throughout the run.
 * @param maxvel                    Player's highest reached velocity.
 * @param timestamp                 System time of when player finished.
 * @param isbestreplay              If the time is the new replay.
 * @param istoolong                 If the time is too long to save a replay if the time is a WR. Note: replays WON'T be full length if this is true.
 *
 * @noreturn
 */
forward void Shavit_AddAdditionalReplayPathsHere(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong);

/**
 * Called when either a WR replay or a copy of a replay has been saved.
 * NOTE: Can be called with a delay after a run is finished due to asynchronous replay saving through extensions.
 *
 * @param client                    Client index. Can be 0 if the replay was saved asynchronously & the client disconnected super duper quick...
 * @param style                     Style the record was done on.
 * @param time                      Record time.
 * @param jumps                     Jumps amount.
 * @param strafes                   Amount of strafes.
 * @param sync                      Sync percentage (0.0 to 100.0) or -1.0 when not measured.
 * @param track                     Timer track.
 * @param oldtime                   The player's best time on the map before this finish.
 * @param perfs                     Perfect jump percentage (0.0 to 100.0) or 100.0 when not measured.
 * @param avgvel                    Player's average velocity throughout the run.
 * @param maxvel                    Player's highest reached velocity.
 * @param timestamp                 System time of when player finished.
 * @param isbestreplay              If the time is the new replay.
 * @param istoolong                 If the time is too long to save a replay if the time is a WR. Note: replays WON'T be full length if this is true.
 * @param replaypaths               ArrayList of the paths the replay was saved to.  If isbestreplay&&!istoolong then the 0th index will be the WR path.
 * @param frames                	ArrayList of the player's frames in the replay.
 * @param preframes                	The number of preframes in the replay.
 * @param postframes                The number of postframes in the replay.
 * @param name                		Player's name at the time of the replay.
 *
 * @noreturn
 */
forward void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isbestreplay, bool istoolong, ArrayList replaypaths, ArrayList frames, int preframes, int postframes, const char[] name);

/**
 * Retrieves a client's frame count.
 *
 * @param client                    Client Index.
 *
 * @return                          Current number of frames.
 */
native int Shavit_GetClientFrameCount(int client);

/*
 * returns the number of preframes in the players current run.
 *
 * @param client                    Client index
 *
 * @return                          Preframe count
 */
native int Shavit_GetPlayerPreFrames(int client);

/*
 * Sets player's preframe length.
 *
 * @param client                    Client index
 * @param PreFrame                  PreFrame length
 * @param TimerPreFrame             Timer start frame length
 *
 * @noreturn
 */
native void Shavit_SetPlayerPreFrames(int client, int PreFrame);

/**
 * Sets a player's replay recording frames from a provided ArrayList.
 * To be used by save states/TAS etc.
 *
 * @param client                    Client index.
 * @param data                      ArrayList with proper replay data.
 * @param cheapCloneHandle          False means we duplicate the frames (ArrayList.Clone). True means we clone the handle to the frames (CloneHandle).
 *
 * @noreturn
 */
native void Shavit_SetReplayData(int client, ArrayList data, bool cheapCloneHandle=false);

/**
 * Saves a player's replay recording frames (if exists) into an ArrayList.
 * To be used by save states/TAS etc.
 *
 * @param client                    Client index.
 * @param cheapCloneHandle          False means we duplicate the frames (Arraylist.Clone). True means we clone the handle to the frames (CloneHandle). This is going to be used for peristent-data in shavit-misc so we don't allocate duplicate memory needlessly.
 *
 * @return                          ArrayList with proper replay data, or null if the player has no recorded data. Delete this handle when you're done with it.
 */
native ArrayList Shavit_GetReplayData(int client, bool cheapCloneHandle=false);

/**
 * Hijack the replay data so that this view angle will be used for the next ticks.
 * Use case is to make segmented runs look smoother.
 *
 * @param client                    Client index.
 * @param pitch                     Vertical view angle.
 * @param yaw                       Horizontal view angle.
 * @param ticks                     The number of ticks to hijack angles for. -1 will calculate the number of ticks based on the client's latency.
 * @param keeponstart               Whether to continue hijacking angles even after someone restarts.
 *
 * @noreturn
 */
native void Shavit_HijackAngles(int client, float pitch, float yaw, int ticks = -1, bool keeponstart = false);

/**
 * If you want to save a replay to an additional path, then call this inside of `Shavit_AddAdditionalReplayPathsHere()`.
 *
 * @param path                      The additional path to save the replay to.
 */
native void Shavit_AlsoSaveReplayTo(const char[] path);

public SharedPlugin __pl_shavit_replay_recorder =
{
	name = "shavit-replay-recorder",
	file = "shavit-replay-recorder.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_shavit_replay_recorder_SetNTVOptional()
{
	MarkNativeAsOptional("Shavit_GetClientFrameCount");
	MarkNativeAsOptional("Shavit_GetPlayerPreFrames");
	MarkNativeAsOptional("Shavit_SetPlayerPreFrames");
	MarkNativeAsOptional("Shavit_GetReplayData");
	MarkNativeAsOptional("Shavit_HijackAngles");
	MarkNativeAsOptional("Shavit_SetReplayData");
	MarkNativeAsOptional("Shavit_AlsoSaveReplayTo");
}
#endif
