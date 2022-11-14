/*
 * shavit's Timer - JSON zones for shavit-zones
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

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#include <ripext> // https://github.com/ErikMinekus/sm-ripext
#include <json> // https://github.com/clugg/sm-json
#include <SteamWorks> // HTTP stuff

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

static char gS_ZoneForms[5][26] = {
	"box",
	"hook trigger_multiple",
	"hook trigger_teleport",
	"hook func_button",
	"areas and clusters"
};

bool gB_YouCanLoadZonesNow = false;
char gS_Map[PLATFORM_MAX_PATH];
char gS_ZonesForMap[PLATFORM_MAX_PATH];
char gS_EngineName[16];
ArrayList gA_Zones = null;

Convar gCV_Enable = null;
Convar gCV_UseRipext = null;
Convar gCV_ApiUrl = null;
Convar gCV_ApiKey = null;
Convar gCV_Source = null;


public Plugin myinfo =
{
	name = "[shavit] Map Zones (JSON)",
	author = "rtldg",
	description = "Retrieves map zones for bhoptimer from an HTTP API.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("HTTPRequest.HTTPRequest");
	MarkNativeAsOptional("HTTPRequest.SetHeader");
	MarkNativeAsOptional("HTTPRequest.Get");
	MarkNativeAsOptional("HTTPResponse.Status.get");
	MarkNativeAsOptional("HTTPResponse.Data.get");
	MarkNativeAsOptional("JSONObject.HasKey");
	MarkNativeAsOptional("JSONObject.Get");
	MarkNativeAsOptional("JSONObject.GetInt");
	MarkNativeAsOptional("JSONObject.GetFloat");
	MarkNativeAsOptional("JSONObject.GetString");
	MarkNativeAsOptional("JSONArray.Get");
	MarkNativeAsOptional("JSONArray.Length.get");
	MarkNativeAsOptional("JSONArray.GetFloat");
	MarkNativeAsOptional("SteamWorks_SetHTTPRequestAbsoluteTimeoutMS");

	switch (GetEngineVersion())
	{
		case Engine_CSGO: gS_EngineName = "csgo";
		case Engine_CSS:  gS_EngineName = "cstrike";
		case Engine_TF2:  gS_EngineName = "tf2";
	}

	char dir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, dir, sizeof(dir), "data/zones-%s", gS_EngineName);
	CreateDirectory(dir, 1 | 4 | 8 | 32 | 64 | 128 | 256);
	StrCat(dir, sizeof(dir), "/x");
	CreateDirectory(dir, 1 | 4 | 8 | 32 | 64 | 128 | 256);

	RegPluginLibrary("shavit-zones-json");
	return APLRes_Success;
}

public void OnPluginStart()
{
	gCV_Enable = new Convar("shavit_zones_http_enable", "1", "Whether to enable this or not...", 0, true, 0.0, true, 1.0);
	gCV_UseRipext = new Convar("shavit_zones_http_ripext", "1", "Whether to use ripext or steamworks", 0, true, 0.0, true, 1.0);
	gCV_ApiUrl = new Convar("shavit_zones_http_url", "", "API URL. Will replace `{map}` and `{key}` with the mapname and api key.\nExample sourcejump url:\n  https://sourcejump.net/api/v2/maps/{map}/zones\nExample srcwr url:\n  https://srcwr.github.io/zones/{engine}/{map}.json", FCVAR_PROTECTED);
	gCV_ApiKey = new Convar("shavit_zones_http_key", "", "API key that some APIs might require.", FCVAR_PROTECTED);
	gCV_Source = new Convar("shavit_zones_http_src", "http", "A string used by plugins to identify where a zone came from (http, sourcejump, sql, etc)");
	//gCV_Folder = new Convar("shavit_zones_json_folder", "1", "Whether to use ")

	Convar.AutoExecConfig();

	RegAdminCmd("sm_dumpzones", Command_DumpZones, ADMFLAG_RCON, "Dumps current map's zones to a json file");
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
	if (!gCV_Enable.BoolValue || !gA_Zones)
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

	if (true)
	{
		char path[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, path, sizeof(path), "data/zones-%s/x/%s.json", gS_EngineName, gS_Map);

		JSONArray records = JSONArray.FromFile(path);

		if (records)
		{
			gS_ZonesForMap = gS_Map;
			delete gA_Zones;
			gA_Zones = EatUpZones(records, true, "folder");
			delete records;
			if (gB_YouCanLoadZonesNow)
				LoadCachedZones();
			return;
		}
	}

	char apikey[64], apiurl[512];
	gCV_ApiKey.GetString(apikey, sizeof(apikey));
	gCV_ApiUrl.GetString(apiurl, sizeof(apiurl));

	if (!apiurl[0])
	{
		LogError("Missing API URL");
		return;
	}

	ReplaceString(apiurl, sizeof(apiurl), "{map}", mapname);
	ReplaceString(apiurl, sizeof(apiurl), "{key}", apikey);
	ReplaceString(apiurl, sizeof(apiurl), "{engine}", gS_EngineName);

	DataPack pack = new DataPack();
	pack.WriteString(mapname);

	if (gCV_UseRipext.BoolValue)
	{
		HTTPRequest http = new HTTPRequest(apiurl);
		if (apikey[0])
			http.SetHeader("api-key", "%s", apikey);
		http.SetHeader("map", "%s", mapname);
		http.Get(RequestCallback_Ripext, pack);
		return;
	}

	Handle request;
	if (!(request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, apiurl))
	  || (apikey[0] && !SteamWorks_SetHTTPRequestHeaderValue(request, "api-key", apikey))
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "accept", "application/json")
	  || !(!apikey[0] || SteamWorks_SetHTTPRequestHeaderValue(request, "api-key", apikey))
	  || !SteamWorks_SetHTTPRequestHeaderValue(request, "map", mapname)
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
}

void RequestCallback_Ripext(HTTPResponse response, DataPack pack, const char[] error)
{
	if (response.Status != HTTPStatus_OK || response.Data == null)
	{
		LogError("HTTP API request failed");
		delete pack;
		return;
	}

	handlestuff(pack, response.Data, true);
}

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

void RequestCallback_Steamworks(const char[] data, DataPack pack)
{
	JSON_Array records = view_as<JSON_Array>(json_decode(data));

	if (records)
	{
		handlestuff(pack, records, false);
		json_cleanup(records);
	}
}

enum struct JsonThing
{
	JSONObject objrip;
	JSON_Object objsw;
	bool isrip;

	bool HasKey(const char[] key)
	{
		return this.isrip ? this.objrip.HasKey(key) : this.objsw.HasKey(key);
	}

	int GetInt(const char[] key)
	{
		return this.isrip ? this.objrip.GetInt(key) : this.objsw.GetInt(key);
	}

	float GetFloat(const char[] key)
	{
		return this.isrip ? this.objrip.GetFloat(key) : this.objsw.GetFloat(key);
	}

	bool GetString(const char[] key, char[] buf, int size)
	{
		return this.isrip ? this.objrip.GetString(key, buf, size) : this.objsw.GetString(key, buf, size);
	}

	void GetVec(const char[] key, float vec[3])
	{
		if (this.isrip)
		{
			JSONArray arr = view_as<JSONArray>(this.objrip.Get(key));
			vec[0] = arr.GetFloat(0);
			vec[1] = arr.GetFloat(1);
			vec[2] = arr.GetFloat(2);
		}
		else
		{
			JSON_Array arr = view_as<JSON_Array>(this.objsw.GetObject(key));
			vec[0] = arr.GetFloat(0);
			vec[1] = arr.GetFloat(1);
			vec[2] = arr.GetFloat(2);
		}
	}
}

void handlestuff(DataPack pack, any records, bool ripext)
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
	delete gA_Zones;
	gA_Zones = EatUpZones(records, ripext, source);

	if (gB_YouCanLoadZonesNow)
		LoadCachedZones();
}

ArrayList EatUpZones(any records, bool ripext, const char source[16])
{
	ArrayList zones = new ArrayList(sizeof(zone_cache_t));

	int asdf = ripext ? view_as<JSONArray>(records).Length : view_as<JSON_Array>(records).Length;

	for (int RN = 0; RN < asdf; RN++)
	{
		any data = ripext ?
			view_as<int>(view_as<JSONArray>(records).Get(RN)) :
			view_as<int>(view_as<JSON_Array>(records).GetObject(RN));

		JsonThing json;
		json.objrip = data;
		json.objsw = data;
		json.isrip = ripext;

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

		if (json.HasKey("point_a")) json.GetVec("point_a", cache.fCorner1);
		if (json.HasKey("point_b")) json.GetVec("point_b", cache.fCorner2);
		if (json.HasKey("dest")) json.GetVec("dest", cache.fCorner1);

		if (json.HasKey("form")) cache.iForm = json.GetInt("form");
		if (json.HasKey("target")) json.GetString("target", cache.sTarget, sizeof(cache.sTarget));
		//json.GetString("source", cache.sSource, sizeof(cache.sSource));
		cache.sSource = source;

		zones.PushArray(cache);
	}

	if (!zones.Length)
		delete zones;
	return zones;
}

void FillBoxMinMax(float point1[3], float point2[3], float boxmin[3], float boxmax[3])
{
	for (int i = 0; i < 3; i++)
	{
		float a = point1[i];
		float b = point2[i];

		if (a < b)
		{
			boxmin[i] = a;
			boxmax[i] = b;
		}
		else
		{
			boxmin[i] = b;
			boxmax[i] = a;
		}
	}
}

bool EmptyVector(float vec[3])
{
	return vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0;
}

JSONObject FillYourMom(zone_cache_t cache)
{
	// normalize mins & maxs......................................................
	FillBoxMinMax(cache.fCorner1, cache.fCorner2, cache.fCorner1, cache.fCorner2);
	JSONObject obj = new JSONObject();
	obj.SetString("type", gS_ZoneTypes[cache.iType]);
	obj.SetInt("track", cache.iTrack);
	obj.SetInt("id", cache.iDatabaseID);
	if (cache.iFlags) obj.SetInt("flags", cache.iFlags);
	if (cache.iData) obj.SetInt("data", cache.iData);
	JSONArray a = new JSONArray(), b = new JSONArray(), c = new JSONArray();
	for (int i = 0; i < 3; i++) {
		a.PushFloat(cache.fCorner1[i]);
		b.PushFloat(cache.fCorner2[i]);
		c.PushFloat(cache.fDestination[i]);
	}
	if (!EmptyVector(cache.fCorner1)) obj.Set("point_a", b);
	if (!EmptyVector(cache.fCorner2)) obj.Set("point_b", b);
	if (!EmptyVector(cache.fDestination)) obj.Set("dest", c);
	if (cache.iForm) obj.SetInt("form", cache.iForm);
	if (cache.sTarget[0]) obj.SetString("target", cache.sTarget);
	delete a;
	delete b;
	delete c;
	return obj;
}

public Action Command_DumpZones(int client, int args)
{
	int count = Shavit_GetZoneCount();
	
	if (!count)
	{
		ReplyToCommand(client, "Map doesn't have any zones...");
		return Plugin_Handled;
	}

	JSONArray wow = new JSONArray();

	for (int XXXXXX = 0; XXXXXX < count; XXXXXX++)
	{
		zone_cache_t cache;
		Shavit_GetZone(XXXXXX, cache);
		JSONObject obj = FillYourMom(cache);
		wow.Push(obj);
		delete obj;
	}

	char map[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
	GetLowercaseMapName(map);
	BuildPath(Path_SM, path, sizeof(path), "data/zones-cstrike/x/%s.json", map);
	wow.ToFile(path, JSON_SORT_KEYS);

	return Plugin_Handled;
}
