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
	"nojump",
	"autobhop"
};

static char gS_ZoneForms[5][26] = {
	"box",
	"hook trigger_multiple",
	"hook trigger_teleport",
	"hook func_button",
	"areas and clusters"
};

bool gB_Late = false;
bool gB_YouCanLoadZonesNow = false;
char gS_Map[PLATFORM_MAX_PATH];
char gS_ZonesForMap[PLATFORM_MAX_PATH];
char gS_EngineName[16];
ArrayList gA_Zones = null;

enum struct MapInfoTrack
{
	int tier; // 0 = unknown
	// -1 = unknown | 0 = false | 1 = true | 2 = really hard
	int possible_on_scroll;
	int possible_on_400vel;
	int possible_on_stamina;
}

static char gS_InfoDescripters[][] = {
	"Unknown",
	"False",
	"True",
	"Really hard",
};

int gI_MapInfoTrack[MAXPLAYERS+1];
MapInfoTrack gA_TrackInfo[TRACKS_SIZE];

Convar gCV_Enable = null;
Convar gCV_UseRipext = null;
Convar gCV_ApiUrl = null;
Convar gCV_ApiKey = null;
Convar gCV_Source = null;
Convar gCV_Folder = null;


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
	gB_Late = late;

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
	StrCat(dir, sizeof(dir), "/z");
	CreateDirectory(dir, 1 | 4 | 8 | 32 | 64 | 128 | 256);
	dir[strlen(dir)-1] = 'i';
	CreateDirectory(dir, 1 | 4 | 8 | 32 | 64 | 128 | 256);

	RegPluginLibrary("shavit-zones-json");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");

	gCV_Enable = new Convar("shavit_zones_json_enable", "1", "Whether to enable this or not...", 0, true, 0.0, true, 1.0);
	gCV_UseRipext = new Convar("shavit_zones_json_ripext", "1", "Whether to use ripext or steamworks", 0, true, 0.0, true, 1.0);
	gCV_ApiUrl = new Convar("shavit_zones_json_url", "http://zones-{engine}.srcwr.com/z/{map}.json", "API URL. Will replace `{map}`, `{key}`, and `{engine}` with the mapname, api key, and engine name....\nOther example urls:\n  https://srcwr.github.io/zones-{engine}/z/{map}.json\n  https://sourcejump.net/api/v2/maps/{map}/zones", FCVAR_PROTECTED);
	gCV_ApiKey = new Convar("shavit_zones_json_key", "", "API key that some APIs might require.", FCVAR_PROTECTED);
	gCV_Source = new Convar("shavit_zones_json_src", "http", "A string used by plugins to identify where a zone came from (http, sourcejump, sql, etc)");
	gCV_Folder = new Convar("shavit_zones_json_folder", "0", "Whether to use a local folder for json zones instead of the http URL.\n0 - use HTTP stuff...\n1 - use folder of JSON zones at `addons/sourcemod/data/zones-{engine}/z/{map}.json`");

	Convar.AutoExecConfig();

	RegAdminCmd("sm_dumpzones", Command_DumpZones, ADMFLAG_RCON, "Dumps current map's zones to a json file");
	RegAdminCmd("sm_editmi", Command_EditMapInfo, ADMFLAG_RCON, "Edits current map's info and dumps to a json file");

	if (gB_Late)
	{
		gB_YouCanLoadZonesNow = true;
	}
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

	Shavit_UnloadZones(); // TODO: fuck it......

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

	if (gCV_Folder.BoolValue)
	{
		char path[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, path, sizeof(path), "data/zones-%s/z/%s.json", gS_EngineName, gS_Map);

		JSONArray records = JSONArray.FromFile(path);

		if (records)
		{
			gS_ZonesForMap = gS_Map;
			delete gA_Zones;
			gA_Zones = EatUpZones(records, true, "folder");
			delete records;
			if (gB_YouCanLoadZonesNow)
				LoadCachedZones();
		}

		return;
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
		if (json.HasKey("dest")) json.GetVec("dest", cache.fDestination);

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
	if (!EmptyVector(cache.fCorner1)) obj.Set("point_a", a);
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

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/zones-%s/z/%s.json", gS_EngineName, gS_Map);
	wow.ToFile(path, JSON_SORT_KEYS);
	delete wow;
	Shavit_PrintToChat(client, "Dumped zones to %s", path);

	return Plugin_Handled;
}

int MaybeInt(JSONObject json, const char[] key, int defaultttt=0) // TODO: remove
{
	if (json && json.HasKey(key)) return json.GetInt(key);
	return defaultttt;
}

void JsonToMapInfo(JSONArray arr)
{
	for (int i = 0; i < TRACKS_SIZE; i++)
	{
		JSONObject obj = (arr.Length > i && !arr.IsNull(i)) ? view_as<JSONObject>(arr.Get(i)) : null;
		gA_TrackInfo[i].tier = MaybeInt(obj, "tier", 0);
		gA_TrackInfo[i].possible_on_scroll  = MaybeInt(obj, "possible_on_scroll", -1);
		gA_TrackInfo[i].possible_on_400vel  = MaybeInt(obj, "possible_on_400vel", -1);
		gA_TrackInfo[i].possible_on_stamina = MaybeInt(obj, "possible_on_stamina", -1);
		delete obj;
	}
}

JSONObject MapInfoToJson(MapInfoTrack info)
{
	JSONObject json = new JSONObject();
	if (info.tier > 0) json.SetInt("tier", info.tier);
	if (info.possible_on_scroll > -1) json.SetInt("possible_on_scroll", info.possible_on_scroll);
	if (info.possible_on_400vel > -1) json.SetInt("possible_on_400vel", info.possible_on_400vel);
	if (info.possible_on_stamina > -1) json.SetInt("possible_on_stamina", info.possible_on_stamina);
	if (json.Size < 1) delete json;
	return json;
}

int MenuHandler_MapInfo(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		int track = gI_MapInfoTrack[param1];

		if (StrEqual(info, "save"))
		{
			JSONArray arr = new JSONArray();
			JSONObject empty = new JSONObject();

			for (int i, empties; i < TRACKS_SIZE; i++)
			{
				JSONObject obj = MapInfoToJson(gA_TrackInfo[i]);

				if (!obj)
				{
					++empties;
					continue;
				}

				for (; empties; --empties)
					arr.Push(empty);
				arr.Push(obj);
				delete obj;
			}

			delete empty;

			if (!arr.Length)
			{
				delete arr;
				Shavit_PrintToChat(param1, "Empty map info array... doing nothing");
				return 0;
			}

			char path[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, path, sizeof(path), "data/zones-%s/i/%s.json", gS_EngineName, gS_Map);
			arr.ToFile(path);
			char buff[512];
			arr.ToString(buff, sizeof(buff));
			PrintToServer("%s", buff);
			delete arr;
			Shavit_PrintToChat(param1, "Wrote mapinfo to %s", path);

			return 0;
		}
		else if (StrEqual(info, "back2main"))
		{
			gI_MapInfoTrack[param1] = 0;
		}
		else if (StrEqual(info, "trackiter"))
		{
			gI_MapInfoTrack[param1] = (track + 1) % TRACKS_SIZE;
		}
		else if (StrEqual(info, "tier"))
		{
			gA_TrackInfo[track].tier = (gA_TrackInfo[track].tier + 1) % 11; // hardcode 10 lol
		}
		else if (StrEqual(info, "scroll"))
		{
			gA_TrackInfo[track].possible_on_scroll += 1;
			if (gA_TrackInfo[track].possible_on_scroll > 2)
				gA_TrackInfo[track].possible_on_scroll = -1;
		}
		else if (StrEqual(info, "400vel"))
		{
			gA_TrackInfo[track].possible_on_400vel += 1;
			if (gA_TrackInfo[track].possible_on_400vel > 2)
				gA_TrackInfo[track].possible_on_400vel = -1;
		}
		else if (StrEqual(info, "stamina"))
		{
			gA_TrackInfo[track].possible_on_stamina += 1;
			if (gA_TrackInfo[track].possible_on_stamina > 2)
				gA_TrackInfo[track].possible_on_stamina = -1;
		}

		CreateMapInfoMenu(param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void CreateMapInfoMenu(int client)
{
	Menu menu = new Menu(MenuHandler_MapInfo);
	menu.SetTitle("Map info\n ");

	char display[128];
	int track = gI_MapInfoTrack[client];
	int tier = gA_TrackInfo[track].tier;

	menu.AddItem("save", "Save\n ");
	menu.AddItem("back2main", "Back to Main track",
		track > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	GetTrackName(client, track, display, sizeof(display), true);
	Format(display, sizeof(display), "Track: %s\n ", display);
	menu.AddItem("trackiter", display);

	FormatEx(display, sizeof(display), "Track Tier: %d%s", tier, tier < 1 ? " (unknown)" : "");
	menu.AddItem("tier", display);

	FormatEx(display, sizeof(display), "Possible on Scroll:  %s", gS_InfoDescripters[1 + gA_TrackInfo[track].possible_on_scroll]);
	menu.AddItem("scroll", display);
	FormatEx(display, sizeof(display), "Possible on 400vel:  %s", gS_InfoDescripters[1 + gA_TrackInfo[track].possible_on_400vel]);
	menu.AddItem("400vel", display);
	FormatEx(display, sizeof(display), "Possible on Stamina: %s\n ", gS_InfoDescripters[1 + gA_TrackInfo[track].possible_on_stamina]);
	menu.AddItem("stamina", display);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public Action Command_EditMapInfo(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "You're not real");
		return Plugin_Handled;
	}

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "data/zones-%s/i/%s.json", gS_EngineName, gS_Map);

	JSONArray arr = JSONArray.FromFile(path);
	if (!arr) arr = new JSONArray();
	JsonToMapInfo(arr);
	delete arr;

	int empty[MAXPLAYERS+1];
	gI_MapInfoTrack = empty;

	CreateMapInfoMenu(client);

	return Plugin_Handled;
}
