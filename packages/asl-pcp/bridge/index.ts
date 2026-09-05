/**
 * Project Constitution Protocol (PCP) TypeScript Bridge
 * TypeScript supervisor/agent helper for loading .pcp or constitution.asn
 * files into the AgentScript PCP engine (@pcp:d-8d4c).
 */

import * as fs from 'fs';
import * as path from 'path';

export type ShortcodeType = 'p-dec' | 'p-crit' | 'p-law' | 'p-req';

export interface Shortcode {
  kind: ShortcodeType;
  code: string;
}

export interface PcpRule {
  code: string;
  title: string;
  why: string;
  status: string;
}

export interface Ledger {
  rules: PcpRule[];
  shortcodes: string[];
}

export interface ScanResult {
  module: string;
  referenced: string[];
  missing: string[];
}

/**
 * Normalizes shortcode reference by stripping @pcp: or @ prefixes.
 */
export function normalizeShortcode(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.startsWith('@pcp:')) {
    return trimmed.slice(5);
  }
  if (trimmed.startsWith('@')) {
    return trimmed.slice(1);
  }
  return trimmed;
}

/**
 * Checks if a shortcode string matches standard format (e.g. d-1eed, c-099a, l-a250, r-8d8e).
 */
export function isValidShortcode(code: string): boolean {
  return /^[dclr]-[0-9a-fA-F]{4}$/.test(code);
}

/**
 * Parses shortcode string into a structured Shortcode object.
 */
export function parseShortcode(code: string): Shortcode | null {
  const norm = normalizeShortcode(code);
  if (!isValidShortcode(norm)) {
    return null;
  }
  const prefix = norm[0];
  let kind: ShortcodeType;
  switch (prefix) {
    case 'd':
      kind = 'p-dec';
      break;
    case 'c':
      kind = 'p-crit';
      break;
    case 'l':
      kind = 'p-law';
      break;
    case 'r':
      kind = 'p-req';
      break;
    default:
      return null;
  }
  return { kind, code: norm };
}

/**
 * Scans source text for all PCP shortcode references (@pcp:... or bare shortcodes).
 */
export function scanReferences(text: string): string[] {
  const matches = text.match(/@pcp:[dclr]-[0-9a-fA-F]{4}|\b[dclr]-[0-9a-fA-F]{4}\b/g) || [];
  const set = new Set<string>();
  for (const m of matches) {
    set.add(normalizeShortcode(m));
  }
  return Array.from(set);
}

/**
 * Escapes string for ASN table format.
 */
export function escapeAsnString(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');
}

/**
 * Encodes a Ledger into an ASN tabular constitution representation.
 */
export function encodeConstitutionAsn(ledger: Ledger): string {
  const rows = ledger.rules.map(
    (r) =>
      `  ["${escapeAsnString(r.code)}" "${escapeAsnString(r.title)}" "${escapeAsnString(r.why)}" "${escapeAsnString(r.status)}"]`
  );
  return `([:code :title :why :status]\n [\n${rows.join('\n')}\n ])\n`;
}

/**
 * Parses an ASN tabular constitution document into a Ledger.
 */
export function parseConstitutionAsn(content: string): Ledger {
  const stringRegex = /"([^"\\]*(?:\\.[^"\\]*)*)"/g;
  const matches: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = stringRegex.exec(content)) !== null) {
    const unescaped = m[1]
      .replace(/\\"/g, '"')
      .replace(/\\n/g, '\n')
      .replace(/\\\\/g, '\\');
    matches.push(unescaped);
  }

  const rules: PcpRule[] = [];
  const shortcodes: string[] = [];

  for (let i = 0; i + 3 < matches.length; i += 4) {
    const code = matches[i];
    const title = matches[i + 1];
    const why = matches[i + 2];
    const status = matches[i + 3];

    rules.push({ code, title, why, status });
    shortcodes.push(code);
  }

  return { rules, shortcodes };
}

/**
 * Queries a rule by shortcode from the ledger.
 */
export function queryRule(ledger: Ledger, code: string): PcpRule | null {
  const norm = normalizeShortcode(code);
  return ledger.rules.find((r) => r.code === norm) || null;
}

/**
 * Checks for constitutional invariant violations.
 */
export function checkInvariants(ledger: Ledger, active: string[]): string[] {
  const normActive = active.map(normalizeShortcode);
  const violations: string[] = [];

  for (const code of normActive) {
    const rule = queryRule(ledger, code);
    if (!rule) {
      violations.push(`unknown:${code}`);
    } else if (rule.status === 'retired') {
      violations.push(`retired:${code}`);
    } else if (rule.status === 'deprecated') {
      violations.push(`deprecated:${code}`);
    }
  }

  for (const rule of ledger.rules) {
    if (rule.status === 'active' && rule.code.startsWith('l-')) {
      if (!normActive.includes(rule.code)) {
        violations.push(`missing-invariant:${rule.code}`);
      }
    }
  }

  return violations;
}

/**
 * Verifies that a module references valid rules and complies with invariants.
 */
export function verifyModule(ledger: Ledger, moduleName: string, refs: string[]): ScanResult {
  const normRefs = refs.map(normalizeShortcode);
  const missing: string[] = [];

  for (const ref of normRefs) {
    if (!ledger.shortcodes.includes(ref)) {
      missing.push(`unregistered:${ref}`);
    }
  }

  for (const rule of ledger.rules) {
    if (rule.status === 'active' && rule.code.startsWith('l-')) {
      if (!normRefs.includes(rule.code)) {
        missing.push(`missing-invariant:${rule.code}`);
      }
    }
  }

  return {
    module: moduleName,
    referenced: normRefs,
    missing,
  };
}

/**
 * Asynchronously loads a constitution.asn or .pcp file into a Ledger.
 */
export async function loadConstitutionFile(filePath: string): Promise<Ledger> {
  const resolved = path.resolve(filePath);
  const content = await fs.promises.readFile(resolved, 'utf-8');
  return parseConstitutionAsn(content);
}

/**
 * Asynchronously saves a Ledger to a constitution.asn file.
 */
export async function saveConstitutionFile(filePath: string, ledger: Ledger): Promise<void> {
  const resolved = path.resolve(filePath);
  const content = encodeConstitutionAsn(ledger);
  await fs.promises.writeFile(resolved, content, 'utf-8');
}
