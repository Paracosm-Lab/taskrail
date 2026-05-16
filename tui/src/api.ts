import type { CostSummary, DashboardState, DigestSummary, QueueSummary, Stage, WorkItem } from './types.js';

export class ApiClient {
  constructor(private readonly baseUrl: string) {}

  async queues(): Promise<QueueSummary[]> {
    const payload = await this.getJson<{ queues?: QueueSummary[] }>('/api/v1/queues');
    return payload.queues ?? [];
  }

  async dashboard(queueSlug?: string): Promise<DashboardState> {
    const queue = queueSlug ?? await this.defaultQueueSlug();
    const [stagesPayload, workItemsPayload, todayCosts, totalCosts] = await Promise.all([
      this.getJson<{ queue?: QueueSummary; stages?: Stage[] }>(`/api/v1/queues/${encodeURIComponent(queue)}/stages`),
      this.getJson<{ work_items?: WorkItem[] }>(`/api/v1/work_items?${new URLSearchParams({ queue }).toString()}`),
      this.getJson<CostSummary>('/api/v1/costs?period=today'),
      this.getJson<CostSummary>('/api/v1/costs')
    ]);

    return {
      queue: stagesPayload.queue ?? { slug: queue },
      stages: stagesPayload.stages ?? [],
      workItems: workItemsPayload.work_items ?? [],
      todayCosts,
      totalCosts
    };
  }

  async workItem(id: string | number): Promise<WorkItem> {
    return this.getJson<WorkItem>(`/api/v1/work_items/${encodeURIComponent(String(id))}`);
  }

  async digest(since = '24h'): Promise<DigestSummary> {
    return this.getJson<DigestSummary>(`/api/v1/digest?${new URLSearchParams({ since }).toString()}`);
  }

  async answer(id: string | number, answer: string): Promise<WorkItem> {
    return this.postJson<WorkItem>(`/api/v1/work_items/${encodeURIComponent(String(id))}/answer`, { answer });
  }

  async retry(id: string | number): Promise<WorkItem> {
    return this.postJson<WorkItem>(`/api/v1/work_items/${encodeURIComponent(String(id))}/retry`, {});
  }

  streamDashboard(
    queueSlug: string | undefined,
    onUpdate: (state: DashboardState) => void,
    onError: (error: Error) => void
  ): () => void {
    const abortController = new AbortController();
    let reconnectTimer: NodeJS.Timeout | undefined;

    const connect = async () => {
      if (abortController.signal.aborted) return;
      try {
        const query = queueSlug ? `?${new URLSearchParams({ queue: queueSlug }).toString()}` : '';
        const response = await fetch(new URL(`/api/v1/stream${query}`, this.baseUrl), {
          method: 'GET',
          headers: { Accept: 'text/event-stream' },
          signal: abortController.signal
        });
        if (!response.ok) {
          throw new Error(`SSE HTTP ${response.status}: ${await response.text()}`);
        }
        if (!response.body) throw new Error('SSE stream has no body.');
        await this.consumeSse(response.body, onUpdate, abortController.signal);
      } catch (error) {
        if (abortController.signal.aborted) return;
        onError(error instanceof Error ? error : new Error(String(error)));
      }
      if (!abortController.signal.aborted) {
        reconnectTimer = setTimeout(() => void connect(), 1000);
      }
    };

    void connect();

    return () => {
      abortController.abort();
      if (reconnectTimer) clearTimeout(reconnectTimer);
    };
  }

  private async defaultQueueSlug(): Promise<string> {
    const queues = await this.queues();
    const first = queues[0];
    if (!first?.slug) throw new Error('No queues returned by API; pass --queue explicitly.');
    return first.slug;
  }

  private async getJson<T>(path: string): Promise<T> {
    return this.requestJson<T>('GET', path);
  }

  private async postJson<T>(path: string, body: unknown): Promise<T> {
    return this.requestJson<T>('POST', path, body);
  }

  private async requestJson<T>(method: 'GET' | 'POST', path: string, body?: unknown): Promise<T> {
    const response = await fetch(new URL(path, this.baseUrl), {
      method,
      headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${await response.text()}`);
    }
    const contentType = response.headers.get('content-type') ?? '';
    const payload = await response.text();
    if (!contentType.toLowerCase().includes('application/json')) {
      const preview = payload.replace(/\s+/g, ' ').slice(0, 120);
      throw new Error(
        `Expected JSON from ${new URL(path, this.baseUrl).toString()} but got "${contentType || 'unknown'}". ` +
        `Response starts with: ${JSON.stringify(preview)}`
      );
    }
    try {
      return JSON.parse(payload) as T;
    } catch (_error) {
      const preview = payload.replace(/\s+/g, ' ').slice(0, 120);
      throw new Error(
        `Invalid JSON from ${new URL(path, this.baseUrl).toString()}. ` +
        `Response starts with: ${JSON.stringify(preview)}`
      );
    }
  }

  private async consumeSse(
    stream: ReadableStream<Uint8Array>,
    onUpdate: (state: DashboardState) => void,
    signal: AbortSignal
  ): Promise<void> {
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    try {
      while (!signal.aborted) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let boundary = buffer.indexOf('\n\n');
        while (boundary >= 0) {
          const frame = buffer.slice(0, boundary);
          buffer = buffer.slice(boundary + 2);
          this.applySseFrame(frame, onUpdate);
          boundary = buffer.indexOf('\n\n');
        }
      }
    } finally {
      reader.releaseLock();
    }
  }

  private applySseFrame(frame: string, onUpdate: (state: DashboardState) => void) {
    const lines = frame.split('\n');
    const eventName = lines.find((line) => line.startsWith('event:'))?.slice(6).trim();
    if (eventName === 'heartbeat') return;

    const dataLines = lines.filter((line) => line.startsWith('data:')).map((line) => line.slice(5).trimStart());
    if (dataLines.length === 0) return;
    const payload = JSON.parse(dataLines.join('\n')) as {
      queue?: QueueSummary;
      stages?: Stage[];
      work_items?: WorkItem[];
      today_costs?: CostSummary;
      total_costs?: CostSummary;
    };

    onUpdate({
      queue: payload.queue ?? { slug: 'unknown' },
      stages: payload.stages ?? [],
      workItems: payload.work_items ?? [],
      todayCosts: payload.today_costs ?? {},
      totalCosts: payload.total_costs ?? {}
    });
  }
}
