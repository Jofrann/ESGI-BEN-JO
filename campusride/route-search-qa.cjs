// Pure route-matching regression checks; no database or browser access.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const source = fs.readFileSync(path.join(__dirname, 'widget.jsx'), 'utf8');
const normalization = source.match(/const norm=([^;]+);/)[1];
const matching = source.match(/function matchedRoute\([\s\S]*?\n}/)[0];
const matchedRoute = new Function(`const norm=${normalization};${matching};return matchedRoute;`)();
const trip = {
  starting_point: 'Beaulieu',
  stops: [{ place: 'Duchesse Anne' }, { place: 'Joliverie' }],
  end_point: 'ESGI Nantes',
};

assert.deepEqual(matchedRoute(trip, '', ''), {
  from: 'Beaulieu', to: 'ESGI Nantes', intermediate: false,
});
assert.equal(matchedRoute(trip, 'JOLIVÉRIE', 'ESGI').intermediate, true);
assert.equal(matchedRoute(trip, 'Joliverie', 'Beaulieu'), null);
assert.equal(matchedRoute(trip, 'ESGI', ''), null);
assert.equal(matchedRoute(trip, 'Beaulieu', 'Duchesse').to, 'Duchesse Anne');
assert.equal(matchedRoute(trip, '', 'Joliverie').from, 'Beaulieu');
assert.equal(matchedRoute(trip, 'Duchesse', 'Joliverie').to, 'Joliverie');
assert.equal(matchedRoute(trip, 'Inconnu', ''), null);

console.log('Route matching: 8 ordered route / stop cases passed.');
