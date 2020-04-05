'use strict';

const path = require('path');
const http = require('http');
const ws = require('ws');
const express = require('express');
const SrcdsLogger = require('srcds-log');
const parseLogLine = require('./parser');

const fs = require('fs');
// const d2Entities = JSON.parse(fs.readFileSync('./maps/de_dust2.entities.json'));
const map = fs.readFileSync('./csgo/server/csgo/resource/overviews/de_dust2.txt')
    .toString('utf8')
    .split('\n')
    .filter(line => line.includes('pos_') || line.includes('scale'))
    .reduce((scale, line) => {
        const [key, value] = line.trim().replace(/"/g, '').split(/\s+/);
        scale[key] = value;
        return scale;
    }, {});
map.name = 'de_dust2';

const app = express();
const PORT = 3000;

app.use('/', express.static(path.join(__dirname, 'elm-frontend/public')));

const server = http.createServer(app);
const wss = new ws.Server({ server });

wss.on('connection', (socket, req) => {
    console.log('websocket connected from', req.connection.remoteAddress);
    socket.send('hello from node', { asd: 'qq' });
    socket.send(JSON.stringify({
        command: 'map',
        map
    }));
    // d2Entities.filter(entity => entity.origin)
    //     .map(entity => {
    //         const [x, y, z] = entity.origin.split(' ');
    //         return {
    //             command: 'initialEntitySetup',
    //             entity: {
    //                 type: entity.targetname || 'me-unknown',
    //                 id: entity.hammerid,
    //                 coordinates: { x, y, z }
    //             }
    //         }
    //     })
    //     .forEach(cmd => socket.send(JSON.stringify(cmd)));
});

server.listen(PORT, '0.0.0.0', () => console.log(`listening on ${PORT}`));

const cs = new SrcdsLogger({
    port: 3333,
    address: '0.0.0.0',
    type: 'udp4'
});

cs.on('data', data => {
    const { result, err } = parseLogLine(data);
    if (err) {
        if (err.message === 'NonHaywireData') {
            return;
        }
        console.log('\nCould not parse\n', data);
        return;
    }
    // if (result.command === 'player_death') {
    //     console.log(result);
    // }
    wss.clients.forEach(client => {
        if (client.readyState === ws.OPEN) {
            client.send(JSON.stringify(result));
        }
    });
});
