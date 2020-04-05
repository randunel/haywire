'use strict';

const haywireIterator = require('./iterator');

const PARSERS = {
    'ammo_pickup': {
        '1': [userCoords('originator')]
    },
    'bullet_impact': {
        '1': [userCoords('originator'), coordinates('impact')]
    },
    'buytime_ended': {
        '1': []
    },
    'bomb_abortplant': {
        '1': [userCoords('originator')]
    },
    'bomb_beep': {
        '1': []
    },
    'bomb_begindefuse': {
        '1': [userCoords('originator')]
    },
    'bomb_beginplant': {
        '1': [userCoords('originator')]
    },
    'bomb_exploded': {
        '1': []
    },
    'bomb_pickup': {
        '1': [userCoords('originator')]
    },
    'bomb_planted': {
        '1': [userCoords('originator')]
    },
    'bomb_defused': {
        '1': [userCoords('originator')]
    },
    'bomb_dropped': {
        '1': [userCoords('originator')]
    },
    'cs_pre_restart': {
        '1': [name('map')]
    },
    'cs_win_panel_round': {
        '1': [name('map')]
    },
    'cs_win_panel_match': {
        '1': [name('map')]
    },
    'decoy_detonate': {
        '1': [userCoords('originator'), entity('decoy')]
    },
    'decoy_firing': {
        '1': [userCoords('originator'), entity('decoy')]
    },
    'decoy_started': {
        '1': [userCoords('originator'), entity('decoy')]
    },
    'enter_bombzone': {
        '1': [userCoords('originator')]
    },
    'enter_buyzone': {
        '1': [userCoords('originator')]
    },
    'enter_rescue_zone': {
        '1': [userCoords('originator')]
    },
    'exit_bombzone': {
        '1': [userCoords('originator')]
    },
    'exit_buyzone': {
        '1': [userCoords('originator')]
    },
    'exit_rescue_zone': {
        '1': [userCoords('originator')]
    },
    'hostage_hurt': {
        '1': [userCoords('originator')]
    },
    'inferno_startburn': {
        '1': [entity('inferno')]
    },
    'inferno_expire': {
        '1': [entity('inferno')]
    },
    'flashbang_detonate': {
        '1': [userCoords('originator'), entity('flashbang_detonate')]
    },
    'grenade_bounce': {
        '1': [userCoords('originator'), entity('grenade_bounce')]
    },
    'grenade_thrown': {
        '1': [userCoords('originator')]
    },
    'hegrenade_detonate': {
        '1': [userCoords('originator'), entity('hegrenade_detonate')]
    },
    'item_equip': {
        '1': [userCoords('originator')]
    },
    'item_pickup': {
        '1': [userCoords('originator')]
    },
    'item_purchase': {
        '1': [userCoords('originator')]
    },
    'item_remove': {
        '1': [userCoords('originator')]
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
        '1': [userCoords('victim'), team('victim'), userCoords('attacker'), team('attacker'), name('victim')]
    },
    'player_falldamage': {
        '1': [userCoords('originator')]
    },
    'player_footstep': {
        '1': [userCoords('originator')]
    },
    'player_given_c4': {
        '1': [userCoords('originator')]
    },
    'player_hurt': {
        '1': [userCoords('victim'), team('victim'), userCoords('attacker'), team('attacker'), healthArmour('remaining'), healthArmour('damage'), int('hitbox'), name('victim')]
    },
    'player_jump': {
        '1': [userCoords('originator')]
    },
    'player_radio': {
        '1': [userCoords('originator')]
    },
    'player_spawned': {
        '1': [userCoords('originator')]
    },
    'round_announce_match_start': {
        '1': [name('map')]
    },
    'round_announce_warmup': {
        '1': [name('map')]
    },
    'round_end': {
        '1': [name('map')]
    },
    'round_freeze_end': {
        '1': [name('map')]
    },
    'round_poststart': {
        '1': [name('map')]
    },
    'smokegrenade_detonate': {
        '1': [userCoords('originator'), entity('smokegrenade_detonate')]
    },
    'smokegrenade_expired': {
        '1': [userCoords('originator'), entity('smokegrenade_expired')]
    },
    'weapon_fire': {
        '1': [userCoords('originator')]
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
        .reduce((prev, fn) => mergeDeep(prev, fn(iterator)), { command });
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
            coordinates: { x, y, z },
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
                coordinates: { x, y, z }
            }
        };
    };
}

function coordinates(type) {
    return function parseCoordinates(iterator) {
        const [x, y, z] = iterator.next().value.split(',');
        const result = {};
        result[type] = {
            coordinates: { x, y, z }
        };
        return result;
    };
}

function healthArmour(type) {
    return function parseHA(iterator) {
        const [health, armour] = iterator.next().value.split(',');
        const result = {};
        result[type] = { health, armour };
        return result;
    };
}

function team(type) {
    return function parseInt(iterator) {
        const team = iterator.next().value;
        const result = {};
        result[type] = { team };
        return result;
    };
}

function name(type) {
    return function parseInt(iterator) {
        const name = iterator.next().value;
        const result = {};
        result[type] = { name };
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

function isObject(item) {
    return (item && typeof item === 'object' && !Array.isArray(item));
}

function mergeDeep(target, ...sources) {
    if (!sources.length) {
        return target;
    }

    const source = sources.shift();

    if (isObject(target) && isObject(source)) {
        for (const key in source) {
            if (isObject(source[key])) {
                if (!target[key]) {
                    Object.assign(target, { [key]: {} });
                }
                mergeDeep(target[key], source[key]);
            } else {
                Object.assign(target, { [key]: source[key] });
            }
        }
    }

    return mergeDeep(target, ...sources);
}
