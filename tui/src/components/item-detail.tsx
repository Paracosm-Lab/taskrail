import React from 'react';
import { Box, Text } from 'ink';
import type { WorkItem } from '../types.js';
import { costText, heartbeatAge, sanitize, truncate } from '../render-utils.js';

export function ItemDetail({ item }: { item: WorkItem }) {
  return <Box flexDirection="column" marginLeft={4} borderStyle="round" borderColor="green" paddingX={1}>
    <Text>{sanitize(item.title)}</Text>
    {item.spec_url && <Text dimColor>spec: {sanitize(item.spec_url)}</Text>}
    {item.transition_logs?.length ? <Text>history: {item.transition_logs.map((log) => `${sanitize(log.from_stage)}→${sanitize(log.to_stage)} ${sanitize(log.trigger)}`).join(', ')}</Text> : null}
    {item.active_claim && <Text>claim: {sanitize(item.active_claim.agent_type)} {sanitize(item.active_claim.status)} {heartbeatAge(item.active_claim.last_heartbeat_at)}</Text>}
    {item.artifacts?.length ? <Text>artifacts: {item.artifacts.map((artifact) => `${sanitize(artifact.kind)} ${truncate(artifact.summary ?? '', 40)}`).join('; ')}</Text> : null}
    {item.escalation?.human_action_required && <Text color="yellow">human: {sanitize(item.escalation.question ?? item.escalation.reason ?? 'answer required')} (press a)</Text>}
    {item.cost && <Text color="cyan">cost: {costText(item.cost)}</Text>}
  </Box>;
}
