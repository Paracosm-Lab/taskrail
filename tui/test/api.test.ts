import assert from 'node:assert/strict';
import test from 'node:test';
import { ApiClient } from '../src/api.js';
import type { DashboardState } from '../src/types.js';

type TestableClient = {
  applySseFrame(frame: string, onUpdate: (state: DashboardState) => void): void;
};

test('ignores SSE heartbeat frames and applies snapshot frames', () => {
  const client = new ApiClient('http://localhost') as unknown as TestableClient;
  const updates: DashboardState[] = [];

  client.applySseFrame('event: heartbeat\ndata: {"event_type":"heartbeat","cursor":"1"}', (state) => updates.push(state));
  assert.equal(updates.length, 0);

  client.applySseFrame(
    'event: snapshot\ndata: {"queue":{"slug":"development"},"stages":[],"work_items":[],"today_costs":{},"total_costs":{}}',
    (state) => updates.push(state)
  );

  assert.equal(updates.length, 1);
  assert.equal(updates[0].queue.slug, 'development');
});
