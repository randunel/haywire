'use strict';

const path = require('path');
const http = require('http');
const ws = require('ws');
const express = require('express');
const SrcdsLogger = require('srcds-log');
const parseLogLine = require('./parser');

const app = express();
const PORT = 3000;

app.use('/', express.static(path.join(__dirname, 'elm-frontend/public')));

const server = http.createServer(app);
const wss = new ws.Server({ server });

wss.on('connection', (socket, req) => {
    console.log('websocket connected from', req.connection.remoteAddress);
    socket.send('hello from node', { asd: 'qq' });
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
        console.log('\nCould not parse\n', data);
        return;
    }
    wss.clients.forEach(client => {
        if (client.readyState === ws.OPEN) {
            client.send(JSON.stringify(result));
        }
    });
});
