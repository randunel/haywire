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
    elm-app make src/Main.elm --optimize --output=public/js/haywire.js;
)

(
    ./node_modules/.bin/uglifyjs ./elm-frontend/public/js/haywire.js --compress "pure_funcs=[F2,F3,F4,F5,F6,F7,F8,F9,A2,A3,A4,A5,A6,A7,A8,A9],pure_getters,keep_fargs=false,unsafe_comps,unsafe" | ./node_modules/.bin/uglifyjs --mangle --output=./elm-frontend/public/js/haywire.js
)
