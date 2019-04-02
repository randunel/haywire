'use strict';

const haywireIterator = require('./iterator');

const PARSERS = {
    'bullet_impact': {
        '1': [userCoords('originator'), coordinates('impact')]
    },
    'buytime_ended': {
        '1': []
    },
    'cs_pre_restart': {
        '1': []
    },
    'decoy_firing': {
        '1': [userCoords('originator'), entity('decoy')]
    },
    'flashbang_detonate': {
        '1': [userCoords('originator'), entity('flashbang_detonate')]
    },
    'grenade_bounce': {
        '1': [userCoords('originator')]
    },
    'hegrenade_detonate': {
        '1': [userCoords('originator'), entity('hegrenade_detonate')]
    },
    'molotov_detonate': {
        '1': [userCoords('originator'), entity('molotov_detonate')]
    },
    'player_activate': {
        '1': [userCoords('originator')]
    },
    'player_blind': {
        '1': [userCoords('originator')]
    },
    'player_death': {
        '1': [userCoords('victim'), userCoords('attacker')]
    },
    'player_footstep': {
        '1': [userCoords('originator')]
    },
    'player_hurt': {
        '1': [userCoords('victim'), userCoords('attacker'), int('health')]
    },
    'player_jump': {
        '1': [userCoords('originator')]
    },
    'player_spawn': {
        '1': [userCoords('originator')]
    },
    'round_freeze_end': {
        '1': []
    },
    'smokegrenade_detonate': {
        '1': [userCoords('originator'), entity('smokegrenade_detonate')]
    },
    'smokegrenade_expired': {
        '1': [userCoords('originator'), entity('smokegrenade_expired')]
    },
    'weapon_reload': {
        '1': [userCoords('originator')]
    },
    'weapon_zoom': {
        '1': [userCoords('originator')]
    }
};

module.exports = function parseLogLine(data) {
    if (data.indexOf('HW->') < 0) {
        // TODO: use other parser
        const err = new Error('NonHaywireData');
        err.details = {
            data
        };
        return { result: null, err };
    }

    const iterator = haywireIterator(data);
    const command = iterator.next().value;
    const version = iterator.next().value;

    const parser = PARSERS[command];
    if (!parser) {
        const err = new Error('ParserNotImplemented');
        err.details = {
            command,
            version
        };
        return { result: null, err };
    }
    const result = parser[version]
        .reduce((prev, fn) => Object.assign(prev, fn(iterator)), { command });
    // console.log('result', result);
    return { result };
};

function userCoords(type) {
    return function parseUserCoords(iterator) {
        const clientId = iterator.next().value;
        const [x, y, z] = iterator.next().value.split(',');
        const [ang0, ang1, ang2] = iterator.next().value.split(',');

        const result = {};
        result[type] = {
            clientId,
            position: { x, y, z },
            orientation: { ang0, ang1, ang2 }
        };
        return result;
    };
}

function entity(type) {
    return function parseEntity(iterator) {
        const id = iterator.next().value;
        const [x, y, z] = iterator.next().value.split(',');
        return {
            entity: {
                type,
                id,
                position: { x, y, z }
            }
        };
    };
}

function coordinates(type) {
    return function parseCoordinates(iterator) {
        const [x, y, z] = iterator.next().value.split(',');
        const result = {};
        result[type] = {
            position: { x, y, z }
        };
        return result;
    };
}

function int(type) {
    return function parseInt(iterator) {
        const number = iterator.next().value;
        const result = {};
        result[type] = number;
        return result;
    };
}
