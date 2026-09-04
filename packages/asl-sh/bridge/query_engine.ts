/**
 * Stream Query, Grep & Structured Filter Engine (@pcp:d-446d)
 *
 * Implements in-buffer regex/glob search with context windows (proc_grep)
 * and structured jq/yq path queries (proc_query) over JSON/YAML stream outputs.
 */

import { RingBuffer, SliceResult } from "./ring_buffer.js";

export interface GrepOptions {
  /** Number of context lines before each match (like grep -B) */
  beforeContext?: number;
  /** Number of context lines after each match (like grep -A) */
  afterContext?: number;
  /** Number of context lines both before and after (like grep -C) */
  context?: number;
  /** Case-insensitive matching */
  caseInsensitive?: boolean;
  /** Invert match (select non-matching lines, like grep -v) */
  invertMatch?: boolean;
  /** Maximum number of matches to return */
  maxMatches?: number;
}

export interface GrepMatch {
  lineIndex: number; // 0-based
  lineNumber: number; // 1-based
  line: string;
  contextBefore: string[];
  contextAfter: string[];
}

export interface GrepResult {
  matches: GrepMatch[];
  totalMatches: number;
  hasMore: boolean;
}

function getLinesFromInput(input: RingBuffer | string[] | string): string[] {
  if (input instanceof RingBuffer) {
    return input.getLines();
  } else if (Array.isArray(input)) {
    return input;
  } else if (typeof input === "string") {
    return input.split("\n");
  }
  return [];
}

/**
 * Searches buffer lines matching pattern with surrounding context windows.
 */
export function grepStream(
  input: RingBuffer | string[] | string,
  pattern: string | RegExp,
  options: GrepOptions = {}
): GrepResult {
  const lines = getLinesFromInput(input);
  const beforeCtx = options.beforeContext ?? options.context ?? 0;
  const afterCtx = options.afterContext ?? options.context ?? 0;
  const maxMatches = options.maxMatches ?? 1000;
  const invert = options.invertMatch ?? false;

  let regex: RegExp;
  if (pattern instanceof RegExp) {
    const flags = options.caseInsensitive && !pattern.flags.includes("i")
      ? pattern.flags + "i"
      : pattern.flags;
    regex = new RegExp(pattern.source, flags);
  } else {
    const flags = options.caseInsensitive ? "i" : "";
    // Escape string if not regex
    const escaped = pattern.replace(/[-\/\\^$*+?.()|[\]{}]/g, "\\$&");
    regex = new RegExp(escaped, flags);
  }

  const matches: GrepMatch[] = [];
  let totalMatches = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const isMatch = regex.test(line);
    const selected = invert ? !isMatch : isMatch;

    if (selected) {
      totalMatches++;
      if (matches.length < maxMatches) {
        const startBefore = Math.max(0, i - beforeCtx);
        const contextBefore = lines.slice(startBefore, i);

        const endAfter = Math.min(lines.length, i + 1 + afterCtx);
        const contextAfter = lines.slice(i + 1, endAfter);

        matches.push({
          lineIndex: i,
          lineNumber: i + 1,
          line,
          contextBefore,
          contextAfter,
        });
      }
    }
  }

  return {
    matches,
    totalMatches,
    hasMore: totalMatches > matches.length,
  };
}

/**
 * Extracts and parses JSON from text if embedded or wrapped.
 */
function extractJson(raw: string): unknown {
  const trimmed = raw.trim();
  // Try direct parse
  try {
    return JSON.parse(trimmed);
  } catch {}

  // Find balanced {...} or [...] blocks across text
  for (let i = 0; i < trimmed.length; i++) {
    const ch = trimmed[i];
    if (ch === "{" || ch === "[") {
      const openChar = ch;
      const closeChar = ch === "{" ? "}" : "]";
      let depth = 0;
      let inString = false;
      let escape = false;

      for (let j = i; j < trimmed.length; j++) {
        const c = trimmed[j];
        if (escape) {
          escape = false;
          continue;
        }
        if (c === "\\") {
          escape = true;
          continue;
        }
        if (c === '"') {
          inString = !inString;
          continue;
        }
        if (!inString) {
          if (c === openChar) depth++;
          else if (c === closeChar) {
            depth--;
            if (depth === 0) {
              const candidate = trimmed.slice(i, j + 1);
              try {
                const parsed = JSON.parse(candidate);
                if (typeof parsed === "object" && parsed !== null) {
                  return parsed;
                }
              } catch {}
              break;
            }
          }
        }
      }
    }
  }

  // Check if lines are newline-delimited JSON (NDJSON)
  const lines = trimmed.split("\n").map((l) => l.trim()).filter(Boolean);
  if (lines.length > 1) {
    const parsedLines: unknown[] = [];
    let allValid = true;
    for (const l of lines) {
      try {
        parsedLines.push(JSON.parse(l));
      } catch {
        allValid = false;
        break;
      }
    }
    if (allValid && parsedLines.length > 0) {
      return parsedLines;
    }
  }

  return null;
}

/**
 * Recursive deep property search helper (..key)
 */
function deepFind(obj: unknown, key: string, acc: unknown[] = []): unknown[] {
  if (!obj || typeof obj !== "object") return acc;

  if (Array.isArray(obj)) {
    for (const item of obj) {
      deepFind(item, key, acc);
    }
  } else {
    const record = obj as Record<string, unknown>;
    if (key in record) {
      acc.push(record[key]);
    }
    for (const val of Object.values(record)) {
      deepFind(val, key, acc);
    }
  }
  return acc;
}

/**
 * Evaluates a jq/yq style path expression against structured data or JSON text.
 * Examples:
 *   "."
 *   ".name"
 *   ".users[0].email"
 *   ".items[*].id"
 *   "..id"
 */
export function queryStructured(input: RingBuffer | string | object, pathExpr: string): unknown {
  let data: unknown;
  if (input instanceof RingBuffer) {
    const text = input.getText("stdout") || input.getText("all");
    data = extractJson(text);
  } else if (typeof input === "string") {
    data = extractJson(input);
  } else {
    data = input;
  }

  if (data === null || data === undefined) {
    return undefined;
  }

  const expr = pathExpr.trim();
  if (!expr || expr === ".") {
    return data;
  }

  // Handle deep search (e.g. ..id)
  if (expr.startsWith("..")) {
    const targetKey = expr.slice(2);
    return deepFind(data, targetKey);
  }

  // Tokenize path segments: .foo, .bar, [0], [*], etc.
  const normalized = expr.startsWith(".") ? expr.slice(1) : expr;
  // Regex to match identifiers or bracketed index/keys: ([^.[\]]+)|(?:\[(\d+|\*)\])
  const segments: Array<{ key: string; isIndex: boolean; isWildcard: boolean }> = [];
  const tokenRegex = /([a-zA-Z0-9_-]+)|(?:\[(?:(\d+)|(\*))\])/g;

  let match: RegExpExecArray | null;
  while ((match = tokenRegex.exec(normalized)) !== null) {
    if (match[1] !== undefined) {
      segments.push({ key: match[1], isIndex: false, isWildcard: false });
    } else if (match[2] !== undefined) {
      segments.push({ key: match[2], isIndex: true, isWildcard: false });
    } else if (match[3] !== undefined) {
      segments.push({ key: "*", isIndex: true, isWildcard: true });
    }
  }

  let current: unknown = data;

  for (let i = 0; i < segments.length; i++) {
    if (current === null || current === undefined) {
      return undefined;
    }

    const seg = segments[i];

    if (seg.isWildcard) {
      if (!Array.isArray(current)) {
        return undefined;
      }
      const remainingSegments = segments.slice(i + 1);
      if (remainingSegments.length === 0) {
        return current;
      }
      // Map remaining path over all items
      const subPath = remainingSegments
        .map((s) => (s.isIndex ? `[${s.key}]` : `.${s.key}`))
        .join("");
      return current.map((item) => queryStructured(item as object, subPath));
    } else if (seg.isIndex) {
      const idx = parseInt(seg.key, 10);
      if (!Array.isArray(current) || idx < 0 || idx >= current.length) {
        return undefined;
      }
      current = current[idx];
    } else {
      if (typeof current !== "object") {
        return undefined;
      }
      current = (current as Record<string, unknown>)[seg.key];
    }
  }

  return current;
}

/**
 * Bounded windowed slicing over ring buffer or string array (proc_slice).
 */
export function sliceStream(
  input: RingBuffer | string[] | string,
  offset = 0,
  limit = 100,
  channel: "stdout" | "stderr" | "all" = "all"
): SliceResult {
  if (input instanceof RingBuffer) {
    return input.slice(offset, offset + limit, channel);
  }

  const lines = getLinesFromInput(input);
  const total = lines.length;
  const start = Math.max(0, offset);
  const end = Math.min(total, start + limit);
  const sliced = lines.slice(start, end);

  return {
    lines: sliced,
    startLine: start,
    endLine: end,
    totalLines: total,
    evictedCount: 0,
    hasMore: end < total,
    channel,
  };
}
