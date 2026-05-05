import React from 'react';
import { Box, Text } from 'ink';
import type { CostSummary } from '../types.js';
import { formatCostCents, formatTokens } from '../render-utils.js';

export function CostTicker({ todayCosts, totalCosts }: { todayCosts: CostSummary; totalCosts: CostSummary }) {
  return <Box marginTop={1}>
    <Text color="cyan">COSTS  {formatCostCents(todayCosts.total_cost_cents)} today  |  {formatCostCents(totalCosts.total_cost_cents)} total  |  ↑{formatTokens(totalCosts.total_tokens_in)} ↓{formatTokens(totalCosts.total_tokens_out)} tok</Text>
  </Box>;
}
