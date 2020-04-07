'use strict';

document.addEventListener('DOMContentLoaded', () => {

    const wsUrl = "ws://localhost:3000";
    const mainModule = 'Main';

    const app = Elm[mainModule].init({
        node: document.getElementById('haywire'),
        flags: wsUrl
    });

    const modules = ['WebSocket'];

    // use rollup to bundle js dependency
    PortFunnel.subscribe(app, { modules: modules });

    (function() {
        const ports = app.ports;
        const parse = ports.parse;
        const parseReturn = ports.parseReturn;
        if (parse && parseReturn) {
            parse.subscribe(string => {
                let result;
                try {
                    result = JSON.parse(string);
                } catch (err) {
                    result = String(err);
                }
                parseReturn.send(result);
            });
        }
    })();
}, false);
