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
    return await response.json() as T;
  }
}
