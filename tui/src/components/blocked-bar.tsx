import React from 'react';
import { Box, Text } from 'ink';
import TextInput from 'ink-text-input';

export function BlockedBar({ value, onChange, onSubmit, onCancel }: { value: string; onChange: (value: string) => void; onSubmit: (value: string) => void; onCancel: () => void }) {
  return <Box marginTop={1}>
    <Text color="yellow">Answer: </Text>
    <TextInput value={value} onChange={onChange} onSubmit={onSubmit} />
    <Text dimColor>  Esc cancels</Text>
  </Box>;
}
