import React from 'react';
import { Box, Text } from 'ink';
import type { CostSummary, QueueSummary } from '../types.js';
import { formatCostCents, sanitize } from '../render-utils.js';

const ASCII = String.raw` _____ _              _     _  _____ _
/  ___| |            (_)   | |/  __ \ |
\ ` + '`' + String.raw`--.| |_ _   _ _ __ _  __| || /  \/ | __ ___      __
 ` + '`' + String.raw`--. \ __| | | | '_ \| |/ _` + '`' + String.raw` || |   | |/ _` + '`' + String.raw` \ \ /\ / /
/\__/ / |_| |_| | |_) | | (_| || \__/\ | (_| |\ V  V /
\____/ \__|\__,_| .__/|_|\__,_| \____/_|\__,_| \_/\_/
                | |
                |_|`;

export function Header({ queue, itemCount, todayCosts }: { queue: QueueSummary; itemCount: number; todayCosts: CostSummary }) {
  const slug = sanitize(queue.slug || queue.name || 'queue');
  return <Box flexDirection="column">
    <Text color="greenBright">{ASCII}</Text>
    <Text color="greenBright">{slug} queue ▸ {itemCount} items ▸ {formatCostCents(todayCosts.total_cost_cents)} today</Text>
  </Box>;
}
