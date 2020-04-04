#!/bin/bash
set -e;

if [[ -f 'package.json' ]]; then
    printf 'updating static maps'"\n";
else
    printf 'do not execute this file directly, please run'"\n";
    printf '    npm run maps:update'"\n";
    exit 1;
fi

convert csgo/server/csgo/resource/overviews/de_dust2_radar.dds elm-frontend/public/maps/de_dust2.png
