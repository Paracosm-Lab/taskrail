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
  const [selectedQueue, setSelectedQueue] = useState<string | undefined>(queue);
  const [queues, setQueues] = useState<string[]>([]);
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
  const [queueSearchOpen, setQueueSearchOpen] = useState(false);
  const [queueSearch, setQueueSearch] = useState('');

  const refresh = useCallback(async () => {
    try {
      const next = await client.dashboard(selectedQueue);
      setState(next);
      setLastGoodState(next);
      setError(undefined);
      setSelectedQueue(next.queue.slug);
      setSelectedIndex((index) => clampIndex(index, filteredItems(next.workItems, next, stageFilter).length));
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      if (lastGoodState) setState(lastGoodState);
    }
  }, [client, selectedQueue, lastGoodState, stageFilter]);

  useEffect(() => {
    void client.queues()
      .then((items) => {
        const slugs = items.map((item) => item.slug).filter(Boolean);
        setQueues(slugs);
        if (!selectedQueue && slugs.length > 0) setSelectedQueue(slugs[0]);
      })
      .catch(() => undefined);
  }, [client, selectedQueue]);

  useEffect(() => {
    const stopStream = client.streamDashboard(
      selectedQueue,
      (next) => {
        setState(next);
        setLastGoodState(next);
        setSelectedQueue(next.queue.slug);
        setError(undefined);
        setSelectedIndex((index) => clampIndex(index, filteredItems(next.workItems, next, stageFilter).length));
      },
      (streamError) => setError(`SSE disconnected: ${streamError.message}`)
    );

    return () => stopStream();
  }, [client, selectedQueue, stageFilter]);

  useEffect(() => {
    void refresh();
    const interval = setInterval(() => void refresh(), Math.max(1, refreshSeconds) * 1000);
    return () => clearInterval(interval);
  }, [refresh, refreshSeconds]);

  const visibleItems = state ? filteredItems(state.workItems, state, stageFilter) : [];
  const selectedItem = visibleItems[selectedIndex];

  useInput((input, key) => {
    if (queueSearchOpen) {
      if (key.escape) {
        setQueueSearchOpen(false);
        setQueueSearch('');
        return;
      }
      if (key.return) {
        const match = filteredQueues(queues, queueSearch)[0];
        if (match) {
          setSelectedQueue(match);
          setMessage(`Queue: ${match}`);
          setStageFilter(undefined);
          setSelectedIndex(0);
          setExpanded(false);
        } else {
          setMessage('No matching queue.');
        }
        setQueueSearchOpen(false);
        setQueueSearch('');
        return;
      }
      if (key.backspace || key.delete) {
        setQueueSearch((value) => value.slice(0, -1));
        return;
      }
      if (input && !key.ctrl && !key.meta) {
        setQueueSearch((value) => value + input);
      }
      return;
    }

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
    if (input === 'n') cycleQueue(1);
    if (input === 'p') cycleQueue(-1);
    if (input === '/') {
      setQueueSearchOpen(true);
      setQueueSearch('');
    }
  });

  function cycleQueue(direction: 1 | -1) {
    if (queues.length <= 1) return;
    const current = selectedQueue ? queues.indexOf(selectedQueue) : -1;
    const start = current >= 0 ? current : 0;
    const nextIndex = (start + direction + queues.length) % queues.length;
    const nextQueue = queues[nextIndex];
    setSelectedQueue(nextQueue);
    setMessage(`Queue: ${nextQueue}`);
    setStageFilter(undefined);
    setSelectedIndex(0);
    setExpanded(false);
  }

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
    if (error) {
      return <Box flexDirection="column">
        <Text color="red">API unreachable: {error}</Text>
        <Text dimColor>Waiting for API; retrying every {Math.max(1, refreshSeconds)}s. Press q to quit.</Text>
      </Box>;
    }
    return <Text color="green">Loading TaskRail TUI…</Text>;
  }

  return <Box flexDirection="column">
    {error && <Text color="red">API unreachable — showing last known state: {error}</Text>}
    {message && <Text color="cyan">{message}</Text>}
    <Header queue={state.queue} itemCount={state.workItems.length} todayCosts={state.todayCosts} />
    <Stages stages={state.stages} workItems={state.workItems} />
    {queueSearchOpen && <Text color="yellow">queue search: /{queueSearch} {filteredQueues(queues, queueSearch).slice(0, 3).join('  ')}</Text>}
    {stageFilter !== undefined && <Text color="yellow">filter: stage {stageFilter + 1} (press 0 to clear)</Text>}
    <WorkItems items={visibleItems} selectedIndex={selectedIndex} expanded={expanded} />
    {answering && <BlockedBar value={answer} onChange={setAnswer} onSubmit={submitAnswer} onCancel={() => setAnswering(false)} />}
    {digestVisible && <DigestView digest={digest} error={digestError} />}
    <CostTicker todayCosts={state.todayCosts} totalCosts={state.totalCosts} />
    <Text dimColor>[j/k] navigate  [Enter] detail  [a] answer  [r] retry  [d] digest  [n/p] queue  [/] jump queue  [q] quit</Text>
  </Box>;
}

function filteredQueues(queues: string[], query: string): string[] {
  if (!query.trim()) return queues;
  const term = query.trim().toLowerCase();
  return queues.filter((queue) => queue.toLowerCase().includes(term));
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
