/*
 * shavit's Timer - HTTP API module for shavit-zones
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

#include <sourcemod>
#include <convar_class>

#include <shavit/core>
#include <shavit/zones>

#define USE_RIPEXT 1
#if USE_RIPEXT
#include <ripext> // https://github.com/ErikMinekus/sm-ripext
#else
#include <json> // https://github.com/clugg/sm-json
#include <SteamWorks> // HTTP stuff
#endif

#undef REQUIRE_PLUGIN


// todo: defines for JSON_Array & JSONArray?
// todo: or even compile this including both and have cvar determine whether ripext or not is used?

#pragma semicolon 1
#pragma newdecls required


static char gS_ZoneTypes[ZONETYPES_SIZE][18] = {
	"start",
	"end",
	"respawn",
	"stop",
	"slay",
	"freestyle",
	"customspeedlimit",
	"teleport",
	"customspawn",
	"easybhop",
	"slide",
	"airaccel",
	"stage",
	"notimergravity",
	"gravity",
	"speedmod",
};


bool gB_YouCanLoadZonesNow = false;
char gS_Map[PLATFORM_MAX_PATH];
char gS_ZonesForMap[PLATFORM_MAX_PATH];
ArrayList gA_Zones = null;

Convar gCV_Enable = null;
Convar gCV_ApiUrl = null;
Convar gCV_ApiKey = null;
Convar gCV_Source = null;


public Plugin myinfo =
{
	name = "[shavit] Map Zones (HTTP API)",
	author = "rtldg, KiD Fearless",
	description = "Retrieves map zones for bhoptimer from an HTTP API.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("shavit-zones-http");
	return APLRes_Success;
}

public void OnPluginStart()
{
	gA_Zones = new ArrayList(sizeof(zone_cache_t));

	gCV_Enable = new Convar("shavit_zones_http_enable", "1", "Whether to enable this or not...", 0, true, 0.0, true, 1.0);
	gCV_ApiUrl = new Convar("shavit_zones_http_url", "", "API URL. Will replace `{map}` and `{key}` with the mapname and api key.\nExample sourcejump url:\n  https://sourcejump.net/api/v2/maps/{map}/zones", FCVAR_PROTECTED);
	gCV_ApiKey = new Convar("shavit_zones_http_key", "", "API key that some APIs might require.", FCVAR_PROTECTED);
	gCV_Source = new Convar("shavit_zones_http_src", "http", "A string used by plugins to identify where a zone came from (http, sourcejump, sql, etc)");

	Convar.AutoExecConfig();
}

public void OnMapEnd()
{
	gB_YouCanLoadZonesNow = false;
}

public void OnConfigsExecuted()
{
	GetLowercaseMapName(gS_Map);

	if (!StrEqual(gS_Map, gS_ZonesForMap))
	{
		RetrieveZones(gS_Map);
	}
}

public void Shavit_LoadZonesHere()
{
	gB_YouCanLoadZonesNow = true;

	if (StrEqual(gS_Map, gS_ZonesForMap))
	{
		LoadCachedZones();
	}
}

void LoadCachedZones()
{
	if (!gCV_Enable.BoolValue)
		return;

	for (int i = 0; i < gA_Zones.Length; i++)
	{
		zone_cache_t cache;
		gA_Zones.GetArray(i, cache);
		Shavit_AddZone(cache);
	}
}

void RetrieveZones(const char[] mapname)
{
	if (!gCV_Enable.BoolValue)
		return;

	char apikey[64], apiurl[333];
	gCV_ApiKey.GetString(apikey, sizeof(apikey));
	gCV_ApiUrl.GetString(apiurl, sizeof(apiurl));

	if (!apiurl[0])
	{
		LogError("Missing API URL");
		return;
	}

	ReplaceString(apiurl, sizeof(apiurl), "{map}", mapname);
	ReplaceString(apiurl, sizeof(apiurl), "{key}", apikey);

	DataPack pack = new DataPack();
	pack.WriteString(mapname);

#if USE_RIPEXT
	HTTPRequest http = new HTTPRequest(apiurl);
	if (apikey[0])
		http.SetHeader("api-key", "%s", apikey);
	http.SetHeader("map", "%s", mapname);
	http.Get(RequestCallback_Ripext, pack);
#else
	Handle request;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, apiurl))
	  || (apikey[0] && !SteamWorks_SetHTTPRequestHeaderValue(request, "api-key", apikey))
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "accept", "application/json")
	  || !SteamWorks_SetHTTPRequestContextValue(request, pack)
	  || !SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(request, 4000)
	//|| !SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(request, true)
	  || !SteamWorks_SetHTTPCallbacks(request, RequestCompletedCallback_Steamworks)
	  || !SteamWorks_SendHTTPRequest(request)
	)
	{
		CloseHandle(request);
		LogError("failed to setup & send HTTP request");
		return;
	}
#endif
}

#if USE_RIPEXT
void RequestCallback_Ripext(HTTPResponse response, DataPack pack, const char[] error)
{
	if (response.Status != HTTPStatus_OK || response.Data == null)
	{
		LogError("HTTP API request failed");
		delete pack;
		return;
	}

	handlestuff(pack, view_as<JSONArray>(response.Data));
}
#else
public void RequestCompletedCallback_Steamworks(Handle request, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, DataPack pack)
{
	if (bFailure || !bRequestSuccessful || eStatusCode != k_EHTTPStatusCode200OK)
	{
		pack.Reset();
		char mapname[PLATFORM_MAX_PATH];
		pack.ReadString(mapname, sizeof(mapname));
		delete pack;
		LogError("HTTP API failed for '%s'. statuscode=%d", mapname, eStatusCode);
		return;
	}

	SteamWorks_GetHTTPResponseBodyCallback(request, RequestCallback_Steamworks, pack);
}

void RequestCallback_Steamworks(const char[] data, DataPack pack, int datalen)
{
	JSON_Array records = view_as<JSON_Array>(json_decode(data));

	if (records)
	{
		handlestuff(pack, records);
		json_cleanup(records);
	}
}
#endif

#if USE_RIPEXT
void ReadVec(const char[] key, JSONObject json, float vec[3])
#else
void ReadVec(const char[] key, JSON_Object json, float vec[3])
#endif
{
	if (json.HasKey(key))
	{
#if USE_RIPEXT
			JSONArray arr = view_as<JSONArray>(json.Get(key));
#else
			JSON_Array arr = view_as<JSON_Array>(json.GetObject(key));
#endif
			vec[0] = arr.GetFloat(0);
			vec[1] = arr.GetFloat(1);
			vec[2] = arr.GetFloat(2);
	}
}

#if USE_RIPEXT
void handlestuff(DataPack pack, JSONArray records)
#else
void handlestuff(DataPack pack, JSON_Array records)
#endif
{
	pack.Reset();
	char mapname[PLATFORM_MAX_PATH];
	pack.ReadString(mapname, sizeof(mapname));
	delete pack;

	if (!StrEqual(mapname, gS_Map))
	{
		return;
	}

	char source[16];
	gCV_Source.GetString(source, sizeof(source));
	if (!source[0]) source = "http";

	gS_ZonesForMap = mapname;

	gA_Zones.Clear();

	for (int RN = 0; RN < records.Length; RN++)
	{
#if USE_RIPEXT
		JSONObject json = view_as<JSONObject>(records.Get(RN));
#else
		JSON_Object json = records.GetObject(RN);
#endif

		char buf[32];
		zone_cache_t cache;

		json.GetString("type", buf, sizeof(buf));
		cache.iType = -1;

		for (int i = 0; i < ZONETYPES_SIZE; i++)
		{
			if (StrEqual(buf, gS_ZoneTypes[i]))
			{
				cache.iType = i;
			}
		}

		if (cache.iType == -1)
		{
			//PrintToServer("");
			continue;
		}

		cache.iTrack = json.GetInt("track");
		//cache.iEntity
		cache.iDatabaseID = json.GetInt("id");
		if (json.HasKey("flags")) cache.iFlags = json.GetInt("flags");
		if (json.HasKey("data")) cache.iData = json.GetInt("data");

		if (cache.iType == Zone_Stage)
			if (json.HasKey("index")) cache.iData = json.GetInt("index");

		ReadVec("point_a", json, cache.fCorner1);
		ReadVec("point_b", json, cache.fCorner2);
		ReadVec("dest", json, cache.fDestination);

		if (json.HasKey("form")) cache.iForm = json.GetInt("form");
		json.GetString("target", cache.sTarget, sizeof(cache.sTarget));
		//json.GetString("source", cache.sSource, sizeof(cache.sSource));
		cache.sSource = source;

		gA_Zones.PushArray(cache);
	}

	if (gB_YouCanLoadZonesNow)
		LoadCachedZones();
}
