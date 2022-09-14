/*
 * shavit's Timer - Replay Bot Routing
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

#include <sdktools_trace>
#include <sdktools>
#include <dhooks>
#include <shavit/replay-playback>
#include <shavit/core>
#include <clientprefs>
#include <shavit/chat>

#pragma newdecls required
#pragma semicolon 1

Handle gH_RouteArray[MAXPLAYERS + 1] = { INVALID_HANDLE, ... };
Handle gH_ReplayRouteArray           = INVALID_HANDLE;

Handle gH_RouteCookie;

bool gB_RoundEnd = false;
bool gB_Late;
bool gB_ReplayRoute[MAXPLAYERS + 1] = { true, ... };
int gI_BlueGlowSprite;

chatstrings_t gS_ChatStrings;

public Plugin myinfo =
{
    name        = "[shavit] Replay Routes",
    author      = "MSWS",
    description = "Displays replay route",
    version     = SHAVIT_VERSION,
    url         = "https://github.com/shavitush/bhoptimer"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    gB_Late = late;
    return APLRes_Success;
}

public void OnPluginStart() {
    LoadTranslations("shavit-replay.phrases");
    HookEvent("round_end", Event_OnRoundEnd);
    HookEvent("round_start", Event_OnRoundStart, EventHookMode_PostNoCopy);

    gH_RouteCookie = RegClientCookie("shavit_replay_route", "Display replay route", CookieAccess_Protected);

    RegConsoleCmd("sm_replayroute", Command_ReplayRoute, "Toggles viewing replay route");

    if (gB_Late) {
        Shavit_OnChatConfigLoaded();
        for (int i = 1; i <= MaxClients; i++)
            if (IsClientConnected(i) && IsClientInGame(i))
                OnClientPutInServer(i);
    }
}

public void OnMapStart() {
    gI_BlueGlowSprite   = PrecacheModel("sprites/blueglow1.vmt");
    gH_ReplayRouteArray = CreateArray(3);

    CreateTimer(2.0, Timer_Record, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd() {
    delete gH_ReplayRouteArray;
}

public Action Command_ReplayRoute(int client, int args) {
    gB_ReplayRoute[client] = !gB_ReplayRoute[client];
    Shavit_PrintToChat(client, "%T", gB_ReplayRoute[client] ? "ReplayRouteEnabled" : "ReplayRouteDisabled", client, gB_ReplayRoute[client] ? gS_ChatStrings.sVariable : gS_ChatStrings.sWarning, gS_ChatStrings.sText);
    SetClientCookie(client, gH_RouteCookie, gB_ReplayRoute[client] ? "1" : "0");
    return Plugin_Handled;
}

public void OnClientCookiesCached(int client) {
    char sSetting[8];
    GetClientCookie(client, gH_RouteCookie, sSetting, sizeof(sSetting));

    if (strlen(sSetting) == 0) {
        SetClientCookie(client, gH_RouteCookie, "1");
        gB_ReplayRoute[client] = true;
        return;
    }
    gB_ReplayRoute[client] = view_as<bool>(StringToInt(sSetting));
}

public void OnClientPutInServer(int client) {
    if (!IsValidReplayClient(client))
        return;
    gH_RouteArray[client] = CreateArray(3);
}

public Action Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast) {
    gB_RoundEnd = false;
    return Plugin_Continue;
}

public Action Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast) {
    gB_RoundEnd = true;
    return Plugin_Continue;
}

public Action Timer_Record(Handle timer) {
    if (gB_RoundEnd)
        return Plugin_Continue;

    SetReplayRoute();

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidReplayClient(i))
            continue;
        // set route
        if (gH_RouteArray[i] == INVALID_HANDLE)
            continue;
        // route
        float origin[3];
        float ground_origin[3];
        GetClientAbsOrigin(i, origin);

        if (GetEntityFlags(i) & FL_ONGROUND)
            origin[2] += 10;
        GetGroundOrigin(i, ground_origin);
        if (FloatAbs(origin[2] - ground_origin[2]) < 66.0) {
            origin = ground_origin;
            origin[2] += 15;
        }
        PushArrayArray(gH_RouteArray[i], origin, 3);
    }
    return Plugin_Continue;
}

public void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldwr, float oldtime, float perfs, float avgvel, float maxvel, int timestamp) {
    SetupRouteArrays(client);
}

public void SetupRouteArrays(int client) {
    if (gH_RouteArray[client] == INVALID_HANDLE || gH_ReplayRouteArray == INVALID_HANDLE)
        return;

    ClearArray(gH_ReplayRouteArray);
    for (int i = 0; i < GetArraySize(gH_RouteArray[client]); i++) {
        float beam_org[3];
        GetArrayArray(gH_RouteArray[client], i, beam_org, 3);
        PushArrayArray(gH_ReplayRouteArray, beam_org, 3);
    }
    ClearArray(gH_RouteArray[client]);
}

public void Shavit_OnReplayEnd(int entity, int type, bool actual) {
    if (!actual)
        return;
    if (entity != Shavit_GetReplayBotIndex(0, 0))
        return;
    SetupRouteArrays(entity);
}

public void SetReplayRoute() // https://bitbucket.org/kztimerglobalteam/kztimerglobal/
{
    Handle hReplayRouteArray;
    if (gH_ReplayRouteArray != INVALID_HANDLE && GetArraySize(gH_ReplayRouteArray) > 2)
        hReplayRouteArray = gH_ReplayRouteArray;
    else {
        int index = Shavit_GetReplayBotIndex(0, 0);
        if (index != -1 && gH_RouteArray[index] != INVALID_HANDLE)
            hReplayRouteArray = gH_RouteArray[index];
        else
            return;
    }

    // set beam points
    Handle hTmpArray;
    hTmpArray = CreateArray(3);
    for (int i = 0; i < GetArraySize(hReplayRouteArray); i++) {
        float fBeamOrigin[3];
        GetArrayArray(hReplayRouteArray, i, fBeamOrigin, 3);
        for (int client = 1; client <= MaxClients; client++) {
            if (!IsValidReplayClient(client) || !gB_ReplayRoute[client] || IsFakeClient(client))
                continue;
            float fClientOrigin[3];
            GetClientAbsOrigin(client, fClientOrigin);
            float distance = GetVectorDistance(fClientOrigin, fBeamOrigin, true);
            if (distance >= 9000000.0) // 3000^2
                continue;
            TE_SetupGlowSprite(fBeamOrigin, gI_BlueGlowSprite, 3.5, 0.17, 100);
            TE_SendToClient(client);
            PushArrayArray(hTmpArray, fBeamOrigin, 3);
        }
    }
    delete hTmpArray;
}

stock bool IsValidReplayClient(int client) {
    return (client >= 1 && client <= MaxClients && IsValidEntity(client) && IsClientConnected(client) && IsClientInGame(client));
}

stock void GetGroundOrigin(int client, float pos[3]) {
    float fOrigin[3], result[3];
    GetClientAbsOrigin(client, fOrigin);
    TraceClientGroundOrigin(client, result, 100.0);
    pos    = fOrigin;
    pos[2] = result[2];
}

stock int TraceClientGroundOrigin(int client, float result[3], float offset) {
    float temp[2][3];
    GetClientEyePosition(client, temp[0]);
    temp[1] = temp[0];
    temp[1][2] -= offset;
    float mins[] = { -16.0, -16.0, 0.0 };
    float maxs[] = { 16.0, 16.0, 60.0 };
    Handle trace = TR_TraceHullFilterEx(temp[0], temp[1], mins, maxs, MASK_PLAYERSOLID, TraceEntityFilterPlayer);
    if (TR_DidHit(trace)) {
        TR_GetEndPosition(result, trace);
        CloseHandle(trace);
        return 1;
    }
    CloseHandle(trace);
    return 0;
}

public bool TraceEntityFilterPlayer(int entity, int contentsMask) {
    return entity > MaxClients || !entity;
}

public void Shavit_OnChatConfigLoaded() {
    Shavit_GetChatStringsStruct(gS_ChatStrings);
}