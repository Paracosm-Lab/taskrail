import React from 'react';
import { Box, Text } from 'ink';
import type { WorkItem } from '../types.js';
import { heartbeatAge, sanitize, statusColor, statusLabel, truncate } from '../render-utils.js';
import { ItemDetail } from './item-detail.js';

export function WorkItems({ items, selectedIndex, expanded }: { items: WorkItem[]; selectedIndex: number; expanded: boolean }) {
  return <Box flexDirection="column" marginTop={1}>
    <Text bold>WORK ITEMS</Text>
    {items.map((item, index) => {
      const selected = index === selectedIndex;
      const heartbeat = heartbeatAge(item.active_claim?.last_heartbeat_at);
      return <Box key={String(item.id)} flexDirection="column">
        <Text>
          {selected ? '▸' : ' '} #{sanitize(item.id).padEnd(4)} {truncate(item.title, 22).padEnd(22)} {truncate(item.stage_name ?? '', 10).padEnd(10)} <Text color={statusColor(item)}>{statusLabel(item)}</Text>{heartbeat ? `  ${heartbeat}` : ''}
        </Text>
        {selected && expanded && <ItemDetail item={item} />}
      </Box>;
    })}
    {items.length === 0 && <Text dimColor>  No work items.</Text>}
  </Box>;
}
