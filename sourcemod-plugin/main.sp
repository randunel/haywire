#include <sourcemod>
#include <sdktools>

#define PLUGIN_NAME "Haywire"
#define PLUGIN_AUTHOR "Mihai Ene"
#define PLUGIN_DESCRIPTION "Haywire stats CS:GO plugin"
#define PLUGIN_VERSION "0.2.0"
#define PLUGIN_URL "https://github.com/randunel/sourcemod-haywire"

#define MAX_STEAMID_LENGTH 32
#define MAX_IP_LENGTH 64
#define MAX_MESSAGE_LENGTH 192

public Plugin:myinfo = {
    name = PLUGIN_NAME,
    author = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version = PLUGIN_VERSION,
    url = PLUGIN_URL
};

public OnPluginStart() {
    HookEvents();
}

HookEvents() {
    HookEvent("player_activate", HandleSimpleUserid);
    HookEvent("bomb_pickup", HandleSimpleUserid);
    HookEvent("bomb_abortdefuse", HandleSimpleUserid);
    HookEvent("weapon_outofammo", HandleSimpleUserid);
    HookEvent("weapon_reload", HandleSimpleUserid);
    HookEvent("weapon_zoom", HandleSimpleUserid);
    HookEvent("silencer_detach", HandleSimpleUserid);
    HookEvent("player_spawned", HandleSimpleUserid);
    HookEvent("silencer_off", HandleSimpleUserid);
    HookEvent("silencer_on", HandleSimpleUserid);
    HookEvent("grenade_bounce", HandleSimpleUserid);
    HookEvent("player_footstep", HandleSimpleUserid);
    HookEvent("player_jump", HandleSimpleUserid);
    HookEvent("player_blind", HandleSimpleUserid);
    HookEvent("player_given_c4", HandleSimpleUserid);

    HookEvent("announce_phase_end", HandleSimpleEvent);
    HookEvent("cs_intermission", HandleSimpleEvent);
    HookEvent("buytime_ended", HandleSimpleEvent);
    HookEvent("round_freeze_end", HandleSimpleEvent);
    HookEvent("mb_input_lock_success", HandleSimpleEvent);
    HookEvent("mb_input_lock_cancel", HandleSimpleEvent);
    HookEvent("cs_match_end_restart", HandleSimpleEvent);
    HookEvent("cs_pre_restart", HandleSimpleEvent);

    HookEvent("inferno_startburn", HandleSimpleEntity);
    HookEvent("inferno_expire", HandleSimpleEntity);
    HookEvent("inferno_extinguish", HandleSimpleEntity);

    HookEvent("hegrenade_detonate", HandleUserEntity);
    HookEvent("flashbang_detonate", HandleUserEntity);
    HookEvent("smokegrenade_detonate", HandleUserEntity);
    HookEvent("smokegrenade_expired", HandleUserEntity);
    HookEvent("molotov_detonate", HandleUserEntity); // TEST, it may need custom handler
    HookEvent("decoy_detonate", HandleUserEntity);
    HookEvent("decoy_started", HandleUserEntity);
    HookEvent("decoy_firing", HandleUserEntity);
}

public Action:HandleSimpleUserid(Handle:event, const String:eventName[], bool:dontBroadcast) {
    new player = GetClientOfUserId(GetEventInt(event, "userid"));
    // char steamId[32];
    // new player = GetClientAuthId(GetClientOfUserId(GetEventInt(event, "userid")), AuthId_SteamID64, steamId, sizeof(steamId));

    new Float:playerCoords[3];
    GetClientAbsOrigin(player, Float:playerCoords);
    new Float:playerAngles[3];
    GetClientEyeAngles(player, Float:playerAngles);
    LogToGame("HW->%s->1->%d->%f,%f,%f->%f,%f,%f",
        eventName,
        GetEventInt(event, "userid"),
        playerCoords[0],
        playerCoords[1],
        playerCoords[2],
        playerAngles[0],
        playerAngles[1],
        playerAngles[2]
    );
    return Plugin_Handled;
}

public Action:HandleSimpleEvent(Handle:event, const String:eventName[], bool:dontBroadcast) {
    LogToGame("HW->%s", eventName);
    return Plugin_Handled;
}

public Action:HandleSimpleEntity(Handle:event, const String:eventName[], bool:dontBroadcast) {
    LogToGame("HW->%s->%d->%f,%f,%f",
        GetEventInt(event, "entityid"),
        GetEventFloat(event, "x"),
        GetEventFloat(event, "y"),
        GetEventFloat(event, "z")
    );
    return Plugin_Handled
}

public Action:HandleUserEntity(Handle:event, const String:eventName[], bool:dontBroadcast) {
    new player = GetClientOfUserId(GetEventInt(event, "userid"));
    new entity = GetEventInt(event, "entityid");

    new Float:playerCoords[3];
    GetClientAbsOrigin(player, Float:playerCoords);
    new Float:playerAngles[3];
    GetClientEyeAngles(player, Float:playerAngles);

    LogToGame("HW->%s->1->%d->%f,%f,%f->%f,%f,%f->%d->%f,%f,%f",
        eventName,
        GetEventInt(event, "userid"),
        playerCoords[0],
        playerCoords[1],
        playerCoords[2],
        playerAngles[0],
        playerAngles[1],
        playerAngles[2],
        entity,
        GetEventFloat(event, "x"),
        GetEventFloat(event, "y"),
        GetEventFloat(event, "z")
    );
    return Plugin_Handled
}
