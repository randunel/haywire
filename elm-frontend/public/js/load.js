'use strict';

function loadHaywire(node, wsUrl) {
    const mainModule = 'Main';

    const app = Elm[mainModule].init({
        node,
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
}
