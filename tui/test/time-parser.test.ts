import assert from 'node:assert/strict';
import test from 'node:test';
import { parseTimeWindow } from '../src/time-parser.js';

test('parses minute hour and day durations relative to now', () => {
  const now = new Date('2026-05-05T14:00:00.000Z');

  assert.equal(parseTimeWindow('30m', now).toISOString(), '2026-05-05T13:30:00.000Z');
  assert.equal(parseTimeWindow('2h', now).toISOString(), '2026-05-05T12:00:00.000Z');
  assert.equal(parseTimeWindow('7d', now).toISOString(), '2026-04-28T14:00:00.000Z');
});

test('parses UTC named windows', () => {
  const now = new Date('2026-05-05T14:00:00.000Z');

  assert.equal(parseTimeWindow('today', now).toISOString(), '2026-05-05T00:00:00.000Z');
  assert.equal(parseTimeWindow('yesterday', now).toISOString(), '2026-05-04T00:00:00.000Z');
  assert.equal(parseTimeWindow('this-week', now).toISOString(), '2026-05-04T00:00:00.000Z');
});

test('raises a usage hint for invalid windows', () => {
  assert.throws(
    () => parseTimeWindow('last-hour', new Date('2026-05-05T14:00:00.000Z')),
    /valid formats: 30m, 2h, 7d, today, yesterday, this-week/
  );
});
