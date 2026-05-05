import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Box, Text, useApp, useInput } from 'ink';
import type { DashboardState, DigestSummary, WorkItem } from './types.js';
import { ApiClient } from './api.js';
import { Header } from './components/header.js';
import { Stages } from './components/stages.js';
import { WorkItems } from './components/work-items.js';
import { CostTicker } from './components/cost-ticker.js';
import { BlockedBar } from './components/blocked-bar.js';
import { DigestView } from './components/digest-view.js';
import { stageIndex } from './render-utils.js';

interface AppProps {
  apiUrl: string;
  queue?: string;
  refreshSeconds: number;
}

export function App({ apiUrl, queue, refreshSeconds }: AppProps) {
  const { exit } = useApp();
  const client = useMemo(() => new ApiClient(apiUrl), [apiUrl]);
  const [state, setState] = useState<DashboardState | undefined>();
  const [lastGoodState, setLastGoodState] = useState<DashboardState | undefined>();
  const [error, setError] = useState<string | undefined>();
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [expanded, setExpanded] = useState(false);
  const [answering, setAnswering] = useState(false);
  const [answer, setAnswer] = useState('');
  const [message, setMessage] = useState<string | undefined>();
  const [digestVisible, setDigestVisible] = useState(false);
  const [digest, setDigest] = useState<DigestSummary | undefined>();
  const [digestError, setDigestError] = useState<string | undefined>();
  const [stageFilter, setStageFilter] = useState<number | undefined>();

  const refresh = useCallback(async () => {
    try {
      const next = await client.dashboard(queue);
      setState(next);
      setLastGoodState(next);
      setError(undefined);
      setSelectedIndex((index) => clampIndex(index, filteredItems(next.workItems, next, stageFilter).length));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      if (lastGoodState) setState(lastGoodState);
    }
  }, [client, queue, lastGoodState, stageFilter]);

  useEffect(() => {
    void refresh();
    const interval = setInterval(() => void refresh(), Math.max(1, refreshSeconds) * 1000);
    return () => clearInterval(interval);
  }, [refresh, refreshSeconds]);

  const visibleItems = state ? filteredItems(state.workItems, state, stageFilter) : [];
  const selectedItem = visibleItems[selectedIndex];

  useInput((input, key) => {
    if (answering) {
      if (key.escape) {
        setAnswering(false);
        setAnswer('');
      }
      return;
    }

    if (input === 'q') exit();
    if (key.downArrow || input === 'j') setSelectedIndex((index) => wrap(index + 1, visibleItems.length));
    if (key.upArrow || input === 'k') setSelectedIndex((index) => wrap(index - 1, visibleItems.length));
    if (key.return) setExpanded((value) => !value);
    if (key.escape) {
      setExpanded(false);
      setDigestVisible(false);
    }
    if (input === 'a' && selectedItem?.status === 'blocked' && selectedItem.escalation?.human_action_required) {
      setAnswering(true);
      setAnswer('');
    }
    if (input === 'r' && selectedItem) {
      void client.retry(selectedItem.id).then(() => {
        setMessage(`Retried #${selectedItem.id}`);
        void refresh();
      }).catch((err) => setMessage(err instanceof Error ? err.message : String(err)));
    }
    if (input === 'd') {
      setDigestVisible((visible) => !visible);
      setDigest(undefined);
      setDigestError(undefined);
      void client.digest('24h').then(setDigest).catch((err) => setDigestError(err instanceof Error ? err.message : String(err)));
    }
    if (/^[1-9]$/.test(input)) setStageFilter(Number(input) - 1);
    if (input === '0') setStageFilter(undefined);
  });

  async function submitAnswer(value: string) {
    if (!selectedItem) return;
    try {
      await client.answer(selectedItem.id, value);
      setMessage(`Answered #${selectedItem.id}`);
      setAnswering(false);
      setAnswer('');
      await refresh();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : String(err));
    }
  }

  if (!state) {
    return <Text color="green">Loading StupidClaw TUI…</Text>;
  }

  return <Box flexDirection="column">
    {error && <Text color="red">API unreachable — showing last known state: {error}</Text>}
    {message && <Text color="cyan">{message}</Text>}
    <Header queue={state.queue} itemCount={state.workItems.length} todayCosts={state.todayCosts} />
    <Stages stages={state.stages} workItems={state.workItems} />
    {stageFilter !== undefined && <Text color="yellow">filter: stage {stageFilter + 1} (press 0 to clear)</Text>}
    <WorkItems items={visibleItems} selectedIndex={selectedIndex} expanded={expanded} />
    {answering && <BlockedBar value={answer} onChange={setAnswer} onSubmit={submitAnswer} onCancel={() => setAnswering(false)} />}
    {digestVisible && <DigestView digest={digest} error={digestError} />}
    <CostTicker todayCosts={state.todayCosts} totalCosts={state.totalCosts} />
    <Text dimColor>[j/k] navigate  [Enter] detail  [a] answer  [r] retry  [d] digest  [q] quit</Text>
  </Box>;
}

function filteredItems(items: WorkItem[], state: DashboardState, stageFilter: number | undefined): WorkItem[] {
  if (stageFilter === undefined) return items;
  return items.filter((item) => stageIndex(state.stages, item.stage_name) === stageFilter);
}

function wrap(value: number, length: number): number {
  if (length <= 0) return 0;
  return (value + length) % length;
}

function clampIndex(value: number, length: number): number {
  if (length <= 0) return 0;
  return Math.min(Math.max(value, 0), length - 1);
}
