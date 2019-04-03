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
    HookEvent("player_spawn", HandleSimpleUserid);
    HookEvent("silencer_off", HandleSimpleUserid);
    HookEvent("silencer_on", HandleSimpleUserid);
    HookEvent("player_footstep", HandleSimpleUserid);
    HookEvent("player_jump", HandleSimpleUserid);
    HookEvent("player_blind", HandleSimpleUserid);
    HookEvent("player_given_c4", HandleSimpleUserid);

    HookEvent("bomb_beginplant", HandleUserBombsite);
    HookEvent("bomb_abortplant", HandleUserBombsite);
    HookEvent("bomb_planted", HandleUserBombsite);
    HookEvent("bomb_defused", HandleUserBombsite);
    HookEvent("bomb_exploded", HandleUserBombsite);

    HookEvent("bomb_begindefuse", HandleUserHaskit);

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
    HookEvent("bomb_beep", HandleSimpleEntity);

    HookEvent("bomb_dropped", HandleUserEntity);
    HookEvent("hegrenade_detonate", HandleUserEntity);
    HookEvent("flashbang_detonate", HandleUserEntity);
    HookEvent("grenade_bounce", HandleUserEntity);
    HookEvent("smokegrenade_detonate", HandleUserEntity);
    HookEvent("smokegrenade_expired", HandleUserEntity);
    HookEvent("molotov_detonate", HandleUserEntity); // TEST, it may need custom handler
    HookEvent("decoy_detonate", HandleUserEntity);
    HookEvent("decoy_started", HandleUserEntity);
    HookEvent("decoy_firing", HandleUserEntity);

    HookEvent("player_hurt", HandleUserAttackerHealth);

    HookEvent("player_death", HandleUserAttacker);

    HookEvent("player_shoot", HandleUserWeaponMode); // does not work

    HookEvent("bullet_impact", HandleUserCoordinates);
}

public Action:HandleUserAttacker(Handle:event, const String:eventName[], bool:dontBroadcast) {
    new player = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    // char steamId[32];
    // new player = GetClientAuthId(GetClientOfUserId(GetEventInt(event, "userid")), AuthId_SteamID64, steamId, sizeof(steamId));

    new Float:playerCoords[3];
    GetClientAbsOrigin(player, Float:playerCoords);
    new Float:playerAngles[3];
    GetClientEyeAngles(player, Float:playerAngles);
    new Float:attackerCoords[3];
    GetClientAbsOrigin(attacker, Float:attackerCoords);
    new Float:attackerAngles[3];
    GetClientEyeAngles(attacker, Float:attackerAngles);
    LogToGame("HW->%s->1->%d->%f,%f,%f->%f,%f,%f->%d->%f,%f,%f->%f,%f,%f",
        eventName,
        GetEventInt(event, "userid"),
        playerCoords[0],
        playerCoords[1],
        playerCoords[2],
        playerAngles[0],
        playerAngles[1],
        playerAngles[2],
        GetEventInt(event, "attacker"),
        attackerCoords[0],
        attackerCoords[1],
        attackerCoords[2],
        attackerAngles[0],
        attackerAngles[1],
        attackerAngles[2]
    );
    return Plugin_Handled;
}

public Action:HandleUserAttackerHealth(Handle:event, const String:eventName[], bool:dontBroadcast) {
    new player = GetClientOfUserId(GetEventInt(event, "userid"));
    new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
    new health = GetEventInt(event, "health");
    new armor = GetEventInt(event, "armor");
    new dmg_health = GetEventInt(event, "dmg_health");
    new dmg_armor = GetEventInt(event, "dmg_armor");
    new hitgroup = GetEventInt(event, "hitgroup");
    // char steamId[32];
    // new player = GetClientAuthId(GetClientOfUserId(GetEventInt(event, "userid")), AuthId_SteamID64, steamId, sizeof(steamId));

    new Float:playerCoords[3];
    GetClientAbsOrigin(player, Float:playerCoords);
    new Float:playerAngles[3];
    GetClientEyeAngles(player, Float:playerAngles);
    new Float:attackerCoords[3];
    GetClientAbsOrigin(attacker, Float:attackerCoords);
    new Float:attackerAngles[3];
    GetClientEyeAngles(attacker, Float:attackerAngles);
    LogToGame("HW->%s->1->%d->%f,%f,%f->%f,%f,%f->%d->%f,%f,%f->%f,%f,%f->%d,%d->%d,%d->%d",
        eventName,
        GetEventInt(event, "userid"),
        playerCoords[0],
        playerCoords[1],
        playerCoords[2],
        playerAngles[0],
        playerAngles[1],
        playerAngles[2],
        GetEventInt(event, "attacker"),
        attackerCoords[0],
        attackerCoords[1],
        attackerCoords[2],
        attackerAngles[0],
        attackerAngles[1],
        attackerAngles[2],
        health,
        armor,
        dmg_health,
        dmg_armor,
        hitgroup
    );
    return Plugin_Handled;
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
    LogToGame("HW->%s->1", eventName);
    return Plugin_Handled;
}

public Action:HandleSimpleEntity(Handle:event, const String:eventName[], bool:dontBroadcast) {
    LogToGame("HW->%s->1->%d->%f,%f,%f",
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

public Action:HandleUserWeaponMode(Handle:event, const String:eventName[], bool:dontBroadcast) {
    new player = GetClientOfUserId(GetEventInt(event, "userid"));
    new weapon = GetEventInt(event, "weapon");
    new mode = GetEventInt(event, "mode");

    new Float:playerCoords[3];
    GetClientAbsOrigin(player, Float:playerCoords);
    new Float:playerAngles[3];
    GetClientEyeAngles(player, Float:playerAngles);

    LogToGame("HW->%s->1->%d->%f,%f,%f->%f,%f,%f->%d,%d->%f,%f,%f",
        eventName,
        GetEventInt(event, "userid"),
        playerCoords[0],
        playerCoords[1],
        playerCoords[2],
        playerAngles[0],
        playerAngles[1],
        playerAngles[2],
        weapon,
        mode,
        GetEventFloat(event, "x"),
        GetEventFloat(event, "y"),
        GetEventFloat(event, "z")
    );
    return Plugin_Handled
}

public Action:HandleUserBombsite(Handle:event, const String:eventName[], bool:dontBroadcast) {
    new player = GetClientOfUserId(GetEventInt(event, "userid"));
    new entity = GetEventInt(event, "site");

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

public Action:HandleUserHaskit(Handle:event, const String:eventName[], bool:dontBroadcast) {
    new player = GetClientOfUserId(GetEventInt(event, "userid"));
    new hasKit = GetEventInt(event, "haskit");

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
        hasKit,
        GetEventFloat(event, "x"),
        GetEventFloat(event, "y"),
        GetEventFloat(event, "z")
    );
    return Plugin_Handled
}

public Action:HandleUserCoordinates(Handle:event, const String:eventName[], bool:dontBroadcast) {
    new player = GetClientOfUserId(GetEventInt(event, "userid"));

    new Float:playerCoords[3];
    GetClientAbsOrigin(player, Float:playerCoords);
    new Float:playerAngles[3];
    GetClientEyeAngles(player, Float:playerAngles);

    LogToGame("HW->%s->1->%d->%f,%f,%f->%f,%f,%f->%f,%f,%f",
        eventName,
        GetEventInt(event, "userid"),
        playerCoords[0],
        playerCoords[1],
        playerCoords[2],
        playerAngles[0],
        playerAngles[1],
        playerAngles[2],
        GetEventFloat(event, "x"),
        GetEventFloat(event, "y"),
        GetEventFloat(event, "z")
    );
    return Plugin_Handled
}
