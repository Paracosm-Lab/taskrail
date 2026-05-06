import type { CostSummary, Stage, WorkItem } from './types.js';

const ANSI_PATTERN = /\u001b\[[0-9;?]*[ -/]*[@-~]/g;
const CONTROL_PATTERN = /[\x00-\x1f\x7f]+/g;

export function sanitize(value: unknown): string {
  return String(value ?? '')
    .replace(ANSI_PATTERN, '')
    .replace(CONTROL_PATTERN, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function truncate(value: unknown, maxLength: number): string {
  const text = sanitize(value);
  if (text.length <= maxLength) return text;
  return `${text.slice(0, Math.max(0, maxLength - 1))}…`;
}

export function formatCostCents(value: number | null | undefined): string {
  const cents = Number.isFinite(value) ? Number(value) : 0;
  return `$${(cents / 100).toFixed(2)}`;
}

export function formatTokens(value: number | null | undefined): string {
  const count = Number.isFinite(value) ? Number(value) : 0;
  if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}m`;
  if (count >= 1_000) return `${(count / 1_000).toFixed(1)}k`;
  return String(count);
}

export function stageProgress(stages: Stage[], workItems: WorkItem[]): Array<{ stage: Stage; completed: number; total: number }> {
  return stages.map((stage, index) => {
    const total = workItems.filter((item) => stageIndex(stages, item.stage_name) >= index).length;
    return { stage, completed: total, total };
  });
}

export function stageIndex(stages: Stage[], stageName: string | undefined): number {
  if (!stageName) return -1;
  return stages.findIndex((stage) => stage.name === stageName);
}

export function statusLabel(item: WorkItem): string {
  if (item.status === 'blocked' && item.escalation?.human_action_required) return '⚠ HUMAN';
  if (item.status === 'active' || item.active_claim?.status === 'active') return '● active';
  if (item.status === 'pending') return '◌ pending';
  if (item.status === 'completed') return '✓ completed';
  if (item.status === 'failed') return '✗ failed';
  return sanitize(item.status);
}

export function statusColor(item: WorkItem): 'green' | 'yellow' | 'red' | 'gray' | undefined {
  if (item.status === 'blocked' && item.escalation?.human_action_required) return 'yellow';
  if (item.status === 'active' || item.active_claim?.status === 'active') return 'green';
  if (item.status === 'completed') return 'gray';
  if (item.status === 'failed') return 'red';
  return undefined;
}

export function heartbeatAge(lastHeartbeatAt: string | null | undefined, now = new Date()): string {
  if (!lastHeartbeatAt) return '';
  const timestamp = Date.parse(lastHeartbeatAt);
  if (!Number.isFinite(timestamp)) return '';
  const seconds = Math.max(0, Math.floor((now.getTime() - timestamp) / 1000));
  return `♥ ${seconds}s ago${seconds > 120 ? ' stale' : ''}`;
}

export function progressBar(completed: number, total: number, width = 10): string {
  if (total <= 0) return '░'.repeat(width);
  const filled = Math.max(0, Math.min(width, Math.round((completed / total) * width)));
  return `${'█'.repeat(filled)}${'░'.repeat(width - filled)}`;
}

export function costText(costs: CostSummary): string {
  return `${formatCostCents(costs.total_cost_cents)} | ↑${formatTokens(costs.total_tokens_in)} ↓${formatTokens(costs.total_tokens_out)} tok`;
}
