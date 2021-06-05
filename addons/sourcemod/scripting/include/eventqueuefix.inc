#if defined _eventqueuefix_included
	#endinput
#endif
#define _eventqueuefix_included

public SharedPlugin __pl_eventqueuefix = 
{
    name = "eventqueuefix",
    file = "eventqueuefix.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

enum struct event_t
{
	char target[64];
	char targetInput[64];
	char variantValue[64];
	float delay;
	int activator;
	int caller;
	int outputID;
}

enum struct eventpack_t
{
	ArrayList playerEvents;
	ArrayList outputWaits;
}

enum struct entity_t
{
	int caller;
	float waitTime;
}

/*
 * Gets the current pending events for a client.
 *
 * @param client					Client index.
 * @param eventpack					Struct containg arrays for pending events and trigger cooldowns.
 *
 * @return 							True if successful, false otherwise.
 */
native bool GetClientEvents(int client, any[] eventpack);

/*
 * Sets the current pending events for a client.
 *
 * @param client					Client index.
 * @param eventpack					Struct containg arrays for pending events and trigger cooldowns.
 *
 * @return 							True if successful, false otherwise.
 */
native bool SetClientEvents(int client, any[] eventpack);

/*
 * Clears the current pending events for a client.
 *
 * @param client					Client index.
 *
 * @return 							True if successful, false otherwise.
 */
native bool ClearClientEvents(int client);

/*
 * Sets the current timescale for a client.
 *
 * @param client					Client index.
 * @param timescale					Timescale.
 *
 * @return 							True if successful, false otherwise.
 */
native bool SetEventsTimescale(int client, float timescale);

/*
 * Pauses or unpauses events for a given client.
 *
 * @param client					Client index.
 * @param paused					Pause state.
 *
 * @return 							True if action was successful, false otherwise.
 */
native bool SetClientEventsPaused(int client, bool paused);

/*
 * Check if events is paused 
 *
 * @param client					Client index.
 *
 * @return 							True if events are paused for client, false otherwise. Will throw native error if client is invalid. 
 */
native bool IsClientEventsPaused(int client);

#if !defined REQUIRE_PLUGIN
public void __pl_eventqueuefix_SetNTVOptional()
{
	MarkNativeAsOptional("GetClientEvents");
	MarkNativeAsOptional("SetClientEvents");
	MarkNativeAsOptional("ClearClientEvents");
	MarkNativeAsOptional("SetEventsTimescale");
	MarkNativeAsOptional("SetClientEventsPaused");
	MarkNativeAsOptional("IsClientEventsPaused");
}
#endif
