import React from 'react';
import { Box, Text } from 'ink';
import type { Stage, WorkItem } from '../types.js';
import { progressBar, stageProgress, truncate } from '../render-utils.js';

export function Stages({ stages, workItems }: { stages: Stage[]; workItems: WorkItem[] }) {
  return <Box flexDirection="column" marginTop={1}>
    <Text bold>STAGES</Text>
    {stageProgress(stages, workItems).map(({ stage, completed, total }) => (
      <Text key={stage.name}>
        {'  '}{truncate(stage.name, 16).padEnd(16)} {truncate(stage.adapter_type ?? '', 12).padEnd(12)} <Text color="green">{progressBar(completed, total)}</Text> {completed}/{total}
      </Text>
    ))}
    {stages.length === 0 && <Text dimColor>  No stages.</Text>}
  </Box>;
}
