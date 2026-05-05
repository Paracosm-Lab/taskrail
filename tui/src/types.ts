export interface QueueSummary {
  name?: string;
  slug: string;
}

export interface Stage {
  name: string;
  adapter_type?: string;
  completion_criteria?: string[];
}

export interface ClaimSummary {
  agent_type?: string;
  status?: string;
  async_execution?: boolean;
  external_id?: string;
  last_heartbeat_at?: string;
  heartbeat_message?: string;
}

export interface EscalationSummary {
  target?: string;
  reason?: string;
  question?: string;
  human_action_required?: boolean;
}

export interface ArtifactSummary {
  id?: string | number;
  kind?: string;
  summary?: string;
}

export interface TransitionLogSummary {
  from_stage?: string;
  to_stage?: string;
  trigger?: string;
  created_at?: string;
}

export interface WorkItemCost {
  total_cost_cents?: number | null;
  total_tokens_in?: number | null;
  total_tokens_out?: number | null;
}

export interface WorkItem {
  id: string | number;
  title: string;
  spec_url?: string;
  status: string;
  stage_name?: string;
  active_claim?: ClaimSummary | null;
  escalation?: EscalationSummary | null;
  artifacts?: ArtifactSummary[];
  transition_logs?: TransitionLogSummary[];
  cost?: WorkItemCost;
}

export interface CostSummary {
  total_cost_cents?: number | null;
  total_tokens_in?: number | null;
  total_tokens_out?: number | null;
  total_duration_ms?: number | null;
}

export interface DigestSummary {
  summary?: string;
  blocked_items?: WorkItem[];
  recent_transitions?: TransitionLogSummary[];
  costs?: CostSummary;
  [key: string]: unknown;
}

export interface DashboardState {
  queue: QueueSummary;
  stages: Stage[];
  workItems: WorkItem[];
  todayCosts: CostSummary;
  totalCosts: CostSummary;
}
