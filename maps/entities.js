'use strict';

const MAPS = ['de_dust2'];//, 'de_vertigo', 'de_cbble', 'cs_assault'];

const parallel = require('async/parallel');
const { promisify } = require('util');

const readFile = promisify(require('fs').readFile);
const writeFile = promisify(require('fs').writeFile);

parallel(MAPS
    .map(name => async function task() {
        let entitiesString;
        {
            const buffer = await readFile(`./csgo/server/csgo/maps/${name}.bsp`, 'utf8');
            const startIx = findClosestIndexOf(buffer, buffer.indexOf('"hammerid" "'), -1, '{');
            const endIx = findClosestIndexOf(buffer, buffer.lastIndexOf('"hammerid" "'), 1, '}');
            // console.log(buffer.slice(startIx, startIx + 20).toString('utf8'));
            // console.log(buffer.slice(endIx - 20, endIx + 1).toString('utf8'));
            entitiesString = buffer.slice(startIx, endIx + 1).toString('utf8');
        }

        const entities = entitiesString.slice(1, entitiesString.length - 1).split(/}\s*[\r?\n]*{/)
            .map(group => group
                .split('\n')
                .reduce((entity, line) => {
                    const [left, right] = line.split(/"\s+"/);
                    if (!line) {
                        return entity;
                    }
                    const prop = {};
                    prop[left.slice(1)] = right.slice(0, right.length - 1);
                    return Object.assign(entity, prop);
                }, {})
            );

        await writeFile(`./maps/${name}.entities.json`, JSON.stringify(entities));
    })
);

function findClosestIndexOf(buffer, ix, order, string) {
    let currentIx = ix + order;
    let startIx = 0;

    const strLength = string.length;

    while (!startIx && currentIx > 0) {
        if (buffer.slice(currentIx, currentIx + strLength).toString() === string) {
            startIx = currentIx;
            return startIx;
        }
        currentIx += order;
    }

    throw new Error('Could not find entities start index.');
}
