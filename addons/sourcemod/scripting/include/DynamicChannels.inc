#if defined _DynamicChannels_included_
  #endinput
#endif
#define _DynamicChannels_included_

/**
 * Provides a game_text channel for plugins to use that will prevent conflict with map channels.
 * The group number is a way of sharing the same game_text channel between certain function calls/plugins
 * (NEW WITH V2.0!!!) The channel that each group number returns can change mid-session if the map changes a game_text channel, so call GetDynamicChannel() frequently and do not store it long term
 * For more help, see ExamplePlugin.sp and README.md at https://github.com/Vauff/DynamicChannels
 *
 * @param group		Integer value of the group you want to get a game_text channel for. Must be between 0-5.
 * @return			The integer value of the assigned game_text channel.
 */
native int GetDynamicChannel(int group);

public SharedPlugin __pl_DynamicChannels = {
	name = "DynamicChannels",
	file = "DynamicChannels.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_DynamicChannels_SetNTVOptional() {
	MarkNativeAsOptional("GetDynamicChannel");
}
#endif