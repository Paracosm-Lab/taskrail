import React from 'react';
import { Box, Text } from 'ink';
import type { DigestSummary } from '../types.js';
import { costText, sanitize } from '../render-utils.js';

export function DigestView({ digest, error }: { digest?: DigestSummary; error?: string }) {
  return <Box flexDirection="column" marginTop={1} borderStyle="round" borderColor="cyan" paddingX={1}>
    <Text color="cyan" bold>DIGEST 24h</Text>
    {error && <Text color="red">{sanitize(error)}</Text>}
    {digest && <>
      <Text>{sanitize(digest.summary ?? 'No summary returned.')}</Text>
      {Array.isArray(digest.blocked_items) && <Text color="yellow">blocked: {digest.blocked_items.length}</Text>}
      {digest.costs && <Text color="cyan">costs: {costText(digest.costs)}</Text>}
    </>}
    {!digest && !error && <Text dimColor>Loading digest…</Text>}
  </Box>;
}
