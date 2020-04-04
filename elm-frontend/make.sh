#!/bin/bash
set -e;

if [[ -f 'package.json' ]]; then
    printf 'compiling and updating elm-frontend public files'"\n";
else
    printf 'do not execute this file directly, please run'"\n";
    printf '    npm run elm:make'"\n";
    exit 1;
fi

if [[ -f '../.env' ]]; then
    printf 'missing file .env, see .env.example'"\n";
    exit 1;
fi

(
    cd elm-frontend;
    elm-app make src/Main.elm --output=public/elm.js;
)
