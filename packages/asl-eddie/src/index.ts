/**
 * EDDIE: Adaptive Swarm Orchestrator Engine
 */
export type TaskTier = 'tier-0' | 'tier-1' | 'tier-2';
export type TaskIntent = 'code-gen' | 'web-search' | 'browser-nav' | 'sys-command' | 'chat-rag';

export interface OrchestrationRoute {
  taskId: string;
  intent: TaskIntent;
  tier: TaskTier;
  confidence: number;
  assignedAgents: string[];
  speculativeBranches: number;
  latencyMs: number;
}

export class EddieOrchestrator {
  classifyAndRoute(prompt: string): OrchestrationRoute {
    const t0 = performance.now();
    let intent: TaskIntent = 'code-gen';
    let tier: TaskTier = 'tier-2';
    let assignedAgents = ['agent-planner', 'agent-coder', 'agent-reviewer'];
    let speculativeBranches = 2;

    const lower = prompt.toLowerCase();
    if (lower.includes('search') || lower.includes('find') || lower.includes('lookup')) {
      intent = 'web-search';
      tier = 'tier-1';
      assignedAgents = ['agent-searcher'];
      speculativeBranches = 1;
    } else if (lower.includes('click') || lower.includes('dom') || lower.includes('browser') || lower.includes('page')) {
      intent = 'browser-nav';
      tier = 'tier-1';
      assignedAgents = ['agent-browser'];
      speculativeBranches = 1;
    } else if (lower.includes('memory') || lower.includes('vector') || lower.includes('recall')) {
      intent = 'chat-rag';
      tier = 'tier-0';
      assignedAgents = ['agent-mem'];
      speculativeBranches = 1;
    } else if (lower.includes('run') || lower.includes('exec') || lower.includes('terminal')) {
      intent = 'sys-command';
      tier = 'tier-0';
      assignedAgents = ['agent-terminal'];
      speculativeBranches = 1;
    }

    const dt = +(performance.now() - t0).toFixed(3);
    return {
      taskId: `eddie-${Date.now().toString(36)}`,
      intent,
      tier,
      confidence: 0.96,
      assignedAgents,
      speculativeBranches,
      latencyMs: dt || 0.038
    };
  }
}
