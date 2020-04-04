#!/bin/bash
set -e;

if [[ -f 'package.json' ]]; then
    printf 'running csgo server'"\n";
else
    printf 'do not execute this file directly, please run'"\n";
    printf '    npm run csgo:download'"\n";
    exit 1;
fi

if [[ -f '../.env' ]]; then
    printf 'missing file .env, see .env.example'"\n";
    exit 1;
fi

(
    cd csgo/server;
    source ../../.env;
    ./srcds_run +sv_setsteamaccount "$CSGO_SERVER_TOKEN" -game csgo -console -usercon +game_type 0 +game_mode 0 +mapgroup mg_active +map de_dust2 +sv_hibernate_when_empty 0 +bot_join_after_player 0 +log on +logaddress_add 10.10.10.171:3333 +sv_logfile 0 +sv_logecho 0 +mp_maxmoney 16000 +mp_startmoney 16000 +mp_afterroundmoney 16000
)
