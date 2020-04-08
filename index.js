'use strict';

const path = require('path');
const http = require('http');
const fs = require('fs');
const { exec } = require('child_process');
const ws = require('ws');
const express = require('express');
const SrcdsLogger = require('srcds-log');
const parseLogLine = require('./parser');

let map = null;

const app = express();
const PORT = 3000;

app.use('/', express.static(path.join(__dirname, 'elm-frontend/public')));

const server = http.createServer(app);
const wss = new ws.Server({ server });

wss.on('connection', socket => {
    if (map) {
        socket.send(JSON.stringify({
            command: 'map',
            map
        }));
    }
});

server.listen(PORT, '0.0.0.0', () => console.log(`listening on ${PORT}`)); // eslint-disable-line no-console

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
        console.log('\nCould not parse\n', data); // eslint-disable-line no-console
        return;
    }
    if (result.map && (!map || map.name !== result.map.name)) {
        // console.log('found map, doing magic', result.map.name);
        map = {
            name: result.map.name
        };
        fs.readFile(`./csgo/server/csgo/resource/overviews/${map.name}.txt`, (err, data) => {
            if (err) {
                console.log('Could not read radar data for', map.name, 'because', err); // eslint-disable-line no-console
                return;
            }
            Object.assign(map, data
                .toString('utf8')
                .split('\n')
                .filter(line => line.includes('pos_') || line.includes('scale'))
                .reduce((scale, line) => {
                    const [key, value] = line.trim().replace(/"/g, '').split(/\s+/);
                    scale[key] = value;
                    return scale;
                }, {})
            );
            const mapImagePath = `elm-frontend/public/maps/${map.name}.png`;
            fs.stat(mapImagePath, err => {
                if (err) {
                    exec(`convert csgo/server/csgo/resource/overviews/${map.name}_radar.dds ${mapImagePath}`, (err, stdout, stderr) => {
                        if (err) {
                            console.log('Could not convert dds to png because', stdout, stderr); // eslint-disable-line no-console
                            return;
                        }
                        wss.clients.forEach(client => { // eslint-disable-line max-nested-callbacks
                            if (client.readyState === ws.OPEN) {
                                client.send(JSON.stringify({
                                    command: 'map',
                                    map
                                }));
                            }
                        });
                    });
                    return;
                }
                wss.clients.forEach(client => {
                    if (client.readyState === ws.OPEN) {
                        client.send(JSON.stringify({
                            command: 'map',
                            map
                        }));
                    }
                });
            });
        });
        // return; // don't return, the event still needs to be sent
    }
    wss.clients.forEach(client => {
        if (client.readyState === ws.OPEN) {
            client.send(JSON.stringify(result));
        }
    });
});
