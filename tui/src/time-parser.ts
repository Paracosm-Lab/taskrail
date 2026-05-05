export class InvalidTimeWindow extends Error {
  constructor(value: string) {
    super(`invalid time window "${value}"; valid formats: 30m, 2h, 7d, today, yesterday, this-week`);
    this.name = 'InvalidTimeWindow';
  }
}

const DURATION_PATTERN = /^(\d+)([mhd])$/;

export function parseTimeWindow(value: string, now = new Date()): Date {
  const normalized = value.trim().toLowerCase();
  const durationMatch = normalized.match(DURATION_PATTERN);
  if (durationMatch) {
    const amount = Number(durationMatch[1]);
    const unit = durationMatch[2];
    const multiplier = unit === 'm' ? 60_000 : unit === 'h' ? 3_600_000 : 86_400_000;
    return new Date(now.getTime() - amount * multiplier);
  }

  if (normalized === 'today') return utcStartOfDay(now);
  if (normalized === 'yesterday') return new Date(utcStartOfDay(now).getTime() - 86_400_000);
  if (normalized === 'this-week') return utcStartOfWeek(now);

  throw new InvalidTimeWindow(value);
}

function utcStartOfDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function utcStartOfWeek(date: Date): Date {
  const start = utcStartOfDay(date);
  const day = start.getUTCDay();
  const daysSinceMonday = day === 0 ? 6 : day - 1;
  return new Date(start.getTime() - daysSinceMonday * 86_400_000);
}
