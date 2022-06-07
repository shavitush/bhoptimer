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


#pragma semicolon 1
#pragma newdecls required


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

	gCV_Enable = new Convar("shavit_zones_http_enable", "1", "description", 0, true, 0.0, true, 1.0);
	gCV_ApiUrl = new Convar("shavit_zones_http_url", "", "description", FCVAR_PROTECTED);
	gCV_ApiKey = new Convar("shavit_zones_http_key", "", "description", FCVAR_PROTECTED);
	gCV_Source = new Convar("shavit_zones_http_src", "http", "description");

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
		LogError("Missing HTTP url");
		return;
	}

	StrCat(apiurl, sizeof(apiurl), mapname);

	DataPack pack = new DataPack();
	pack.WriteString(mapname);

#if USE_RIPEXT
	HTTPRequest http = new HTTPRequest(apiurl);
	if (apikey[0])
		http.SetHeader("api-key", "%s", apikey);
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
	if (response.Status != HTTPStatus_OK)
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
	handlestuff(pack, view_as<JSON_Array>(json_decode(data)));
}
#endif

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

	char source[16];
	gCV_Source.GetString(source, sizeof(source));

	if (records == null)
	{
		LogError("JSON Handle is NULL");
		return;
	}

	gS_ZonesForMap = mapname;

	if (!StrEqual(mapname, gS_Map))
	{
#if !USE_RIPEXT
		json_cleanup(records);
#endif
		return;
	}

	gA_Zones.Clear();

	for (int i = 0; i < records.Length; i++)
	{
#if USE_RIPEXT
		JSONObject json = view_as<JSONObject>(records.Get(i));
#else
		JSON_Object json = records.GetObject(i);
#endif

		zone_cache_t cache;
		cache.iType = json.GetInt("type");
		cache.iTrack = json.GetInt("track");
		//cache.iEntity
		cache.iDatabaseID = json.GetInt("databaseid");
		cache.iFlags = json.GetInt("flags");
		cache.iData = json.GetInt("data");
		cache.fCorner1[0] = json.GetFloat("corner1_x");
		cache.fCorner1[1] = json.GetFloat("corner1_y");
		cache.fCorner1[2] = json.GetFloat("corner1_z");
		cache.fCorner2[0] = json.GetFloat("corner2_x");
		cache.fCorner2[1] = json.GetFloat("corner2_y");
		cache.fCorner2[2] = json.GetFloat("corner2_z");
		cache.fDestination[0] = json.GetFloat("dest_x");
		cache.fDestination[1] = json.GetFloat("dest_y");
		cache.fDestination[2] = json.GetFloat("dest_z");
		cache.iForm = json.GetInt("form");
		json.GetString("target", cache.sTarget, sizeof(cache.sTarget));
		//json.GetString("source", cache.sSource, sizeof(cache.sSource));
		cache.sSource = source;

		gA_Zones.PushArray(cache);
	}

#if USE_RIPEXT
	// the records handle is closed by ripext post-callback
#else
	json_cleanup(records);
#endif

	if (gB_YouCanLoadZonesNow)
		LoadCachedZones();
}
