import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { performance } from 'node:perf_hooks';

/**
 * Capability-based sandboxing policy evaluation.
 * Invariants:
 * - workspaceRoot, worktreeRoots, tempDir -> allow-silent (zero prompts)
 * - Traversal (../), root system paths (/etc, ~/.ssh) -> deny-strict ("sandbox escape")
 */
export function checkPermission(action, targetPath, manifest = {}) {
  const normalized = String(targetPath || '').trim();
  const wsRoot = path.resolve(manifest.workspaceRoot || manifest.workspace_root || process.cwd());
  const worktreeRoots = (manifest.worktreeRoots || manifest.worktree_roots || []).map((w) => path.resolve(w));
  const tempDir = path.resolve(manifest.tempDir || manifest.temp_dir || os.tmpdir());
  const isReadOnly = Boolean(manifest.readOnly ?? manifest.read_only);

  // Traversal sequences
  if (
    normalized.includes('../') ||
    normalized.includes('/..') ||
    normalized === '..' ||
    normalized.startsWith('../') ||
    normalized.startsWith('..\\') ||
    normalized.includes('..\\')
  ) {
    return {
      allowed: false,
      silent: false,
      reason: 'sandbox escape: directory traversal rejected',
      code: 'DENY_STRICT',
    };
  }

  // Sensitive system root paths
  const resolved = path.resolve(normalized);
  const dangerousRoots = ['/etc', '/root', '/sys', '/proc', '/dev', '/var/root'];
  const userHome = os.homedir();
  const sshDir = path.join(userHome, '.ssh');

  if (
    dangerousRoots.some((r) => resolved === r || resolved.startsWith(r + path.sep)) ||
    resolved === sshDir || resolved.startsWith(sshDir + path.sep) ||
    normalized.startsWith('~/.ssh') || normalized.includes('.ssh')
  ) {
    return {
      allowed: false,
      silent: false,
      reason: 'sandbox escape: sensitive system path rejected',
      code: 'DENY_STRICT',
    };
  }

  // Read-only check
  if (isReadOnly && (action === 'write' || action === 'delete' || action === 'create')) {
    return {
      allowed: false,
      silent: false,
      reason: 'permission denied: manifest is read-only',
      code: 'DENY_READONLY',
    };
  }

  // Check authorized roots
  const isInside = (dir, root) => dir === root || dir.startsWith(root + path.sep);

  if (isInside(resolved, wsRoot)) {
    return {
      allowed: true,
      silent: true,
      reason: 'path within authorized workspace root',
      code: 'ALLOW_SILENT',
    };
  }

  if (isInside(resolved, tempDir)) {
    return {
      allowed: true,
      silent: true,
      reason: 'path within authorized temp dir',
      code: 'ALLOW_SILENT',
    };
  }

  for (const wt of worktreeRoots) {
    if (isInside(resolved, wt)) {
      return {
        allowed: true,
        silent: true,
        reason: 'path within authorized worktree root',
        code: 'ALLOW_SILENT',
      };
    }
  }

  return {
    allowed: false,
    silent: false,
    reason: 'path outside authorized manifest boundaries',
    code: 'DENY_UNAUTHORIZED',
  };
}

/**
 * Allowed shape resolution adhering to @pcp:d-374e:
 * Questions within one project are answered in one context and collapse to single.
 */
export function allowedShape({ kind, shape = 'single', steps = [], stop = '' }) {
  if (stop === 'plan') return 'single';
  if (kind === 'dev') return shape;

  // QUESTIONS WITHIN ONE PROJECT ARE ANSWERED IN ONE CONTEXT. @pcp:d-374e
  if (kind === 'question') {
    if (!Array.isArray(steps) || steps.length === 0) return shape;
    const distinctProjects = new Set(
      steps
        .map((s) => (s && typeof s.project === 'string' ? s.project.trim() : null))
        .filter(Boolean),
    );
    if (distinctProjects.size >= 2) return shape;
    return 'single';
  }

  if (kind === 'non-dev' && Array.isArray(steps) && steps.length && steps.every((s) => s && s.action)) {
    return shape;
  }
  return 'single';
}

/**
 * Decides frontline triage adhering to @pcp:d-374e and @pcp:d-1a1a.
 */
export function decideFrontline(parsed, { request = '', projects = [], routeProjects = [] } = {}) {
  const r = { ...parsed };
  const text = String(request || '');

  // Setup actions check (@pcp:d-1a1a)
  const isSetupAction = (act) =>
    act &&
    (act.startsWith('project.') ||
      act === 'git.init' ||
      act === 'git.clone' ||
      act === 'git.branch');

  const steps = Array.isArray(r.steps) ? r.steps : [];
  const allSetupSteps = steps.length > 0 && steps.every((s) => s && isSetupAction(s.action));

  if (r.action && isSetupAction(r.action)) {
    r.disposition = 'admin';
    return r;
  }

  if (allSetupSteps) {
    if (steps.length === 1) {
      r.disposition = 'admin';
      r.action = steps[0].action;
      r.args = steps[0].args;
      return r;
    }
    r.disposition = 'new';
    r.kind = 'non-dev';
    r.shape = 'workflow';
    r.routing = { shape: 'workflow', steps };
    return r;
  }

  // MULTI-QUERY QUESTIONS AND GENERAL ERRANDS COLLAPSE TO ONE TASK. @pcp:d-374e
  const explicitTaskSplit =
    /(?:создай|разбей|сделай).*(?:отдельн\S*|разн\S*)\s+задач\S*|create\s+separate\s+tasks|split\s+(?:into\s+)?tasks/i.test(
      text
    );

  const parts = Array.isArray(r.parts) ? r.parts : [];
  const hasAttachPart = parts.some((p) => p && p.disposition === 'attach');
  const isGeneralOrNonDev =
    r.kind === 'non-dev' || r.project === 'general' || r.kind === 'question';
  const collapseParts = isGeneralOrNonDev && !explicitTaskSplit && !hasAttachPart && parts.length > 1;

  if (collapseParts) {
    r.parts = [{ disposition: 'new', text: text.trim() || 'collapsed errand' }];
  }

  if (r.shape && r.shape !== 'single') {
    r.shape = allowedShape({ kind: r.kind, shape: r.shape, steps: r.steps, stop: r.stop });
  }

  return r;
}

/**
 * Formal AST intent triage and multi-query collapse engine.
 * Encodes @pcp:d-374e and @pcp:d-1a1a.
 */
export function triageRequest(input, workspaceContext = {}) {
  const text = String(input || '').trim();
  const low = text.toLowerCase();
  const currentProject = workspaceContext.projectName || workspaceContext.project_name || 'general';

  // 1. Setup commands (@pcp:d-1a1a)
  const isSetup =
    low.startsWith('git init') ||
    low.startsWith('init ') ||
    low === 'init' ||
    low.startsWith('git clone') ||
    low.startsWith('clone ') ||
    low.startsWith('git branch') ||
    low.startsWith('branch ') ||
    low.startsWith('checkout ') ||
    low.includes('project.init') ||
    low.includes('project.clone') ||
    low.includes('project.branch') ||
    low.includes('setup workspace');

  if (isSetup) {
    return {
      kind: 'setup',
      targetProject: 'general',
      shape: 'single',
      collapsedSingle: false,
      reason: 'setup command routed to workspace setup (@pcp:d-1a1a)',
    };
  }

  // 2. Administrative commands
  const isAdmin =
    low.startsWith('voice.') ||
    low.startsWith('config.') ||
    low.startsWith('cancel') ||
    low.startsWith('drop') ||
    low.startsWith('status') ||
    low === 'help';

  if (isAdmin) {
    return {
      kind: 'admin',
      targetProject: currentProject,
      shape: 'single',
      collapsedSingle: false,
      reason: 'administrative command',
    };
  }

  // Check explicit split
  const explicitSplit =
    /(?:создай|разбей|сделай).*(?:отдельн\S*|разн\S*)\s+задач\S*|разбей\s+(?:на\s+)?задач\S*|create\s+separate\s+tasks|split\s+(?:into\s+)?tasks/i.test(text);

  // Check multi-aspect
  const hasMultiAspect =
    low.includes(' and ') ||
    low.includes(' also ') ||
    low.includes(' plus ') ||
    low.includes(' as well as ') ||
    low.includes(' и ') ||
    low.includes(' также ') ||
    low.includes(' а еще ');

  // 3. Questions (@pcp:d-374e)
  const isQuestion =
    low.includes('?') ||
    low.startsWith('what ') ||
    low.startsWith('how ') ||
    low.startsWith('why ') ||
    low.startsWith('where ') ||
    low.startsWith('who ') ||
    low.startsWith('when ') ||
    low.startsWith('tell me') ||
    low.startsWith('explain') ||
    low.startsWith('summarize') ||
    low.startsWith('расскажи') ||
    low.startsWith('объясни') ||
    low.startsWith('что ') ||
    low.startsWith('как ') ||
    low.startsWith('почему ');

  if (isQuestion) {
    if (hasMultiAspect && explicitSplit) {
      return {
        kind: 'question',
        targetProject: currentProject,
        shape: 'workflow',
        collapsedSingle: false,
        reason: 'explicit split requested for question',
      };
    }
    return {
      kind: 'question',
      targetProject: currentProject,
      shape: 'single',
      collapsedSingle: hasMultiAspect,
      reason: hasMultiAspect
        ? 'informational query collapsed to single task frame (@pcp:d-374e)'
        : 'single informational inquiry',
    };
  }

  // 4. Dev work
  const isDev =
    low.includes('fix ') ||
    low.includes('bug') ||
    low.includes('implement') ||
    low.includes('refactor') ||
    low.includes('compile') ||
    low.includes('build') ||
    low.includes('test') ||
    low.includes('patch') ||
    low.includes('function') ||
    low.includes('class') ||
    low.includes('почини') ||
    low.includes('исправь') ||
    low.includes('напиши код');

  if (isDev) {
    if (explicitSplit) {
      return {
        kind: 'dev',
        targetProject: currentProject,
        shape: 'workflow',
        collapsedSingle: false,
        reason: 'explicit dev split requested',
      };
    }
    return {
      kind: 'dev',
      targetProject: currentProject,
      shape: 'single',
      collapsedSingle: false,
      reason: 'development task frame',
    };
  }

  // 5. Non-dev errands
  if (hasMultiAspect && explicitSplit) {
    return {
      kind: 'non-dev',
      targetProject: currentProject,
      shape: 'workflow',
      collapsedSingle: false,
      reason: 'explicit non-dev split requested',
    };
  }

  return {
    kind: 'non-dev',
    targetProject: currentProject,
    shape: 'single',
    collapsedSingle: hasMultiAspect,
    reason: hasMultiAspect
      ? 'errand collapsed to single task frame (@pcp:d-374e)'
      : 'single errand execution frame',
  };
}

/**
 * Bidirectional Host Capability FFI Bridge
 */
export class HostBridge {
  constructor(options = {}) {
    this.manifest = options.manifest || {
      workspaceRoot: process.cwd(),
      worktreeRoots: [],
      tempDir: os.tmpdir(),
      readOnly: false,
    };
    this.speechInterrupted = false;
    this.speechAbortController = null;
    this.lastInterruptLatencyMs = 0;
    this.callCount = 0;
  }

  /**
   * Primary bidirectional FFI dispatch contract:
   * (df host-call [(capability Str) (action Str) (payload Str)] -> (Result Str Str))
   */
  async hostCall(capability, action, payload = '') {
    this.callCount++;
    const cap = String(capability || '').trim().toLowerCase();
    const act = String(action || '').trim().toLowerCase();

    switch (cap) {
      case 'fs':
        return this.handleFs(act, payload);
      case 'exec':
        return this.handleExec(act, payload);
      case 'audio':
        return this.handleAudio(act, payload);
      case 'llm':
        return this.handleLlm(act, payload);
      default:
        return { ok: false, error: `Unknown host capability: ${capability}` };
    }
  }

  /**
   * Synchronous hostCall for lightweight in-memory dispatch
   */
  hostCallSync(capability, action, payload = '') {
    this.callCount++;
    const cap = String(capability || '').trim().toLowerCase();
    const act = String(action || '').trim().toLowerCase();

    switch (cap) {
      case 'fs': {
        const parsed = this.parsePayload(payload);
        const targetPath = parsed.path || payload;
        const perm = checkPermission(act === 'write' ? 'write' : 'read', targetPath, this.manifest);
        if (!perm.allowed) {
          return { ok: false, error: perm.reason };
        }
        if (act === 'read') {
          if (!fs.existsSync(targetPath)) return { ok: false, error: 'File not found' };
          const content = fs.readFileSync(targetPath, 'utf8');
          return { ok: true, value: content };
        }
        if (act === 'write') {
          fs.writeFileSync(targetPath, parsed.content || '', 'utf8');
          return { ok: true, value: 'ok' };
        }
        if (act === 'list') {
          if (!fs.existsSync(targetPath)) return { ok: false, error: 'Directory not found' };
          const files = fs.readdirSync(targetPath);
          return { ok: true, value: JSON.stringify(files) };
        }
        return { ok: false, error: `Unsupported fs action: ${action}` };
      }
      case 'audio': {
        if (act === 'interrupt') {
          const t0 = performance.now();
          this.speechInterrupted = true;
          if (this.speechAbortController) {
            this.speechAbortController.abort();
            this.speechAbortController = null;
          }
          this.lastInterruptLatencyMs = performance.now() - t0;
          return { ok: true, value: `interrupted in ${this.lastInterruptLatencyMs.toFixed(3)}ms` };
        }
        if (act === 'speak') {
          this.speechInterrupted = false;
          return { ok: true, value: 'spoken' };
        }
        if (act === 'vad_status') {
          return { ok: true, value: 'inactive' };
        }
        return { ok: false, error: `Unsupported audio action: ${action}` };
      }
      case 'llm': {
        if (act === 'complete') {
          return { ok: true, value: `LLM response for: ${payload}` };
        }
        return { ok: false, error: `Unsupported llm action: ${action}` };
      }
      default:
        return { ok: false, error: `Sync dispatch not supported for ${capability}` };
    }
  }

  parsePayload(payload) {
    if (typeof payload === 'object' && payload !== null) return payload;
    try {
      return JSON.parse(payload);
    } catch {
      return { path: payload };
    }
  }

  async handleFs(action, payload) {
    const parsed = this.parsePayload(payload);
    const targetPath = parsed.path || payload;
    const perm = checkPermission(action === 'write' ? 'write' : 'read', targetPath, this.manifest);
    if (!perm.allowed) {
      return { ok: false, error: perm.reason };
    }

    try {
      if (action === 'read') {
        const content = await fs.promises.readFile(targetPath, 'utf8');
        return { ok: true, value: content };
      }
      if (action === 'write') {
        await fs.promises.writeFile(targetPath, parsed.content || '', 'utf8');
        return { ok: true, value: 'ok' };
      }
      if (action === 'list') {
        const entries = await fs.promises.readdir(targetPath);
        return { ok: true, value: JSON.stringify(entries) };
      }
      return { ok: false, error: `Unsupported fs action: ${action}` };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  }

  async handleExec(action, payload) {
    const parsed = this.parsePayload(payload);
    const command = parsed.command || payload;
    const timeout = parsed.timeout || 10000;

    return new Promise((resolve) => {
      const parts = command.split(' ');
      const proc = spawn(parts[0], parts.slice(1), {
        timeout,
        env: { ...process.env, PYTHONUNBUFFERED: '1' },
      });

      let stdout = '';
      let stderr = '';

      proc.stdout?.on('data', (d) => { stdout += d.toString(); });
      proc.stderr?.on('data', (d) => { stderr += d.toString(); });

      proc.on('close', (code) => {
        if (code === 0) {
          resolve({ ok: true, value: stdout });
        } else {
          resolve({ ok: false, error: stderr || `Process exited with code ${code}` });
        }
      });

      proc.on('error', (err) => {
        resolve({ ok: false, error: err.message });
      });
    });
  }

  async handleAudio(action, payload) {
    if (action === 'interrupt') {
      const t0 = performance.now();
      this.speechInterrupted = true;
      if (this.speechAbortController) {
        this.speechAbortController.abort();
        this.speechAbortController = null;
      }
      this.lastInterruptLatencyMs = performance.now() - t0;
      return {
        ok: true,
        value: `interrupted in ${this.lastInterruptLatencyMs.toFixed(3)}ms`,
      };
    }

    if (action === 'speak') {
      this.speechInterrupted = false;
      this.speechAbortController = new AbortController();
      return { ok: true, value: 'playback_started' };
    }

    if (action === 'vad_status') {
      return { ok: true, value: 'listening' };
    }

    return { ok: false, error: `Unsupported audio action: ${action}` };
  }

  async handleLlm(action, payload) {
    if (action === 'complete') {
      return { ok: true, value: `LLM answer to: ${payload}` };
    }
    if (action === 'stream') {
      return { ok: true, value: `LLM stream started` };
    }
    return { ok: false, error: `Unsupported llm action: ${action}` };
  }
}
