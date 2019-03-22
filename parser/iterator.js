'use strict';

module.exports = function createIterator(data) {
    if (typeof data !== 'string') {
        throw new Error('UnexpectedDataType');
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
    return line[Symbol.iterator]();
};
