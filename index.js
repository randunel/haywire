'use strict';

const path = require('path');
const http = require('http');
const ws = require('ws');
const express = require('express');
const SrcdsLogger = require('srcds-log');

const cs = new SrcdsLogger({
    port: 3333,
    address: '10.10.10.107',
    type: 'udp4'
});

const app = express();
const PORT = 3000;

app.use('/', express.static(path.join(__dirname, 'elm-frontend/build')));

const server = http.createServer(app)
const wss = new ws.Server({ server });

wss.on('connection', (socket, req) => {
    console.log('websocket connected from', req.connection.remoteAddress);
    socket.send('hello from node', { asd: 'qq' });
});

cs.on('data', data => {
    const result = parseLogLine(data);
    if (result) {
        wss.clients.forEach(client => {
            if (client.readyState === ws.OPEN) {
                client.send(data);
            }
        });
    } else {
        console.log('Could not parse\n', data);
    }
});

server.listen(PORT, () => console.log(`listening on ${PORT}`));

function parseLogLine(data) {
    if (data.indexOf('HW->') < 0) {
        // TODO: use other parser
        return {};
    }

    const line = new String(data);
    line[Symbol.iterator] = function iterator() {
        return {
            next: function next() {
                if (this._isDone) {
                    this._isDone = false;
                    this._ix = line.indexOf('HW->') + 4;
                    return { done: true };
                }
                const endIx = line.indexOf('->', this._ix)
                if (endIx === -1) {
                    const ix = this._ix;
                    this._isDone = true;
                    this._ix = endIx + 2;
                    return { value: line.substring(ix), done: false };
                }
                const ix = this._ix;
                this._ix = endIx + 2;
                return { value: line.substring(ix, endIx), done: false };
            },
            _ix: line.indexOf('HW->') + 4,
            _isDone: false
        };
    }
    const iterator = line[Symbol.iterator]();
    const command = iterator.next().value;
    const version = iterator.next().value;

    const parser = PARSERS[command];
    if (!parser) {
        return null;
    }
    const result = parser[version]
        .reduce((prev, fn) => Object.assign(prev, fn(iterator)), { command });
    // console.log('result', result);
    return result;
}

const PARSERS = {
    'player_footstep': {
        '1': [ originator ]
    },
    'player_jump': {
        '1': [ originator ]
    },
    'weapon_reload': {
        '1': [ originator ]
    },
    'weapon_zoom': {
        '1': [ originator ]
    },
    'decoy_firing': {
        '1': [ originator, entity('decoy') ]
    }
}

function originator(iterator) {
    const clientId = iterator.next().value;
    const [x, y, z] = iterator.next().value.split(',');
    const [ang0, ang1, ang2] = iterator.next().value.split(',');
    return {
        originator: {
            clientId,
            position: { x, y, z },
            orientation: { ang0, ang1, ang2 }
        }
    }
}

function entity(type) {
    return function parseEntity(iterator) {
        const entityId = iterator.next().value;
        const [x, y, z] = iterator.next().value.split(',');
        return {
            entity: {
                type,
                id,
                position: { x, y, z }
            }
        };
    }
}
