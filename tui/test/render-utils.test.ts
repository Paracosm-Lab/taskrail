import assert from 'node:assert/strict';
import test from 'node:test';
import { formatCostCents, heartbeatAge, stageProgress, statusLabel, truncate } from '../src/render-utils.js';
import type { Stage, WorkItem } from '../src/types.js';

test('computes stage progress from stage ordering and work item stages', () => {
  const stages: Stage[] = [
    { name: 'ingest_signals', adapter_type: 'haiku' },
    { name: 'cluster_failures', adapter_type: 'sonnet' },
    { name: 'draft_runbook', adapter_type: 'opus' }
  ];
  const workItems: WorkItem[] = [
    { id: '1', title: 'done', status: 'completed', stage_name: 'draft_runbook' },
    { id: '2', title: 'active', status: 'pending', stage_name: 'cluster_failures' },
    { id: '3', title: 'new', status: 'pending', stage_name: 'ingest_signals' }
  ];

  assert.deepEqual(stageProgress(stages, workItems), [
    { stage: stages[0], completed: 3, total: 3 },
    { stage: stages[1], completed: 2, total: 2 },
    { stage: stages[2], completed: 1, total: 1 }
  ]);
});

test('formats status labels and stale heartbeat ages for work item rows', () => {
  assert.equal(statusLabel({ id: '1', title: 'Run', status: 'active' }), '● active');
  assert.equal(statusLabel({ id: '2', title: 'Blocked', status: 'blocked', escalation: { human_action_required: true } }), '⚠ HUMAN');
  assert.equal(heartbeatAge('2026-05-05T13:58:59.000Z', new Date('2026-05-05T14:00:00.000Z')), '♥ 61s ago');
  assert.equal(heartbeatAge('2026-05-05T13:57:59.000Z', new Date('2026-05-05T14:00:00.000Z')), '♥ 121s ago stale');
});

test('sanitizes and truncates terminal text and formats dollars', () => {
  assert.equal(truncate('Safe\nFake Section\u001b[31m', 20), 'Safe Fake Section');
  assert.equal(truncate('A'.repeat(25), 10), 'AAAAAAAAA…');
  assert.equal(formatCostCents(47), '$0.47');
  assert.equal(formatCostCents(undefined), '$0.00');
});
