#!/bin/bash
set -e;

if [[ -f 'package.json' ]]; then
    printf 'downloading csgo server'"\n";
else
    printf 'do not execute this file directly, please run'"\n";
    printf '    npm run csgo:download'"\n";
    exit 1;
fi

mkdir -p csgo/steamcmd;

(
    cd csgo/steamcmd;
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -;
)

(
    cd csgo;
    steamcmd/steamcmd.sh +runscript ../steamcmd-script.txt;
)

(
    cd csgo/server/csgo;
    wget "https://mms.alliedmods.net/mmsdrop/1.10/mmsource-1.10.7-git971-linux.tar.gz";
    tar -xf "mmsource-1.10.7-git971-linux.tar.gz";
    wget "https://sm.alliedmods.net/smdrop/1.10/sourcemod-1.10.0-git6478-linux.tar.gz";
    tar -xf "sourcemod-1.10.0-git6478-linux.tar.gz";
)
