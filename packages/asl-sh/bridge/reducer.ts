/**
 * Pure ASL Stream Reducer Bridge (@pcp:d-446d)
 *
 * Implements stream token reduction matching packages/asl-sh/src/reducer.asl:
 * - ANSI stripping
 * - Carriage return (\r) spinner and download bar collapsing
 * - Consecutive duplicate-line suppression with repeat markers
 * - Head/tail retention windowing with eviction markers
 * - Semantic diagnostic extraction (rustc, tsc, python, pytest, generic)
 */

export interface ReductionConfig {
  /** Maximum lines retained at stream head (default 500) */
  headLimit?: number;
  /** Maximum lines retained at stream tail (default 1500) */
  tailLimit?: number;
  /** Whether consecutive duplicate lines are collapsed with repeat markers */
  dedupRepeats?: boolean;
}

export interface Diagnostic {
  kind: "rustc" | "tsc" | "python" | "pytest" | "generic";
  severity: "error" | "warning" | "failure";
  message: string;
  file: string;
  line: number;
  col: number;
  raw: string[];
}

export interface DiagnosticSummary {
  errors: number;
  warnings: number;
  failures: number;
  diagnostics: Diagnostic[];
}

export interface ReducedStream {
  rawLineCount: number;
  reducedLineCount: number;
  evictedLineCount: number;
  lines: string[];
  text: string;
  diagnostics: DiagnosticSummary;
}

export const DEFAULT_REDUCTION_CONFIG: Required<ReductionConfig> = {
  headLimit: 500,
  tailLimit: 1500,
  dedupRepeats: true,
};

// ANSI strip matching ansi.asl
const ANSI_REGEX = /\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?\x07|\x1b[()][AB012]/g;

export function stripAnsi(text: string): string {
  return text.replace(ANSI_REGEX, "");
}

/**
 * Simulates terminal carriage return overwrites matching ansi.asl
 */
export function collapseCrSegment(prev: string, curr: string): string {
  if (curr.length >= prev.length) {
    return curr;
  }
  return curr + prev.slice(curr.length);
}

export function collapseCrLine(line: string): string {
  if (!line.includes("\r")) {
    return line;
  }
  const segments = line.split("\r");
  return segments.reduce((prev, curr) => collapseCrSegment(prev, curr), "");
}

export function collapseCr(text: string): string {
  const norm = text.replace(/\r\n/g, "\n");
  if (!norm.includes("\r")) {
    return norm;
  }
  return norm
    .split("\n")
    .map((line) => collapseCrLine(line))
    .join("\n");
}

export function cleanTerminalText(text: string): string {
  return collapseCr(stripAnsi(text));
}

/**
 * Suppresses consecutive duplicate lines with repeat markers matching reducer.asl
 */
export function dedupLines(lines: string[]): string[] {
  if (lines.length <= 1) {
    return lines;
  }

  const result: string[] = [];
  let prev = lines[0];
  let repeatCount = 1;
  result.push(prev);

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (line === prev) {
      repeatCount++;
    } else {
      if (repeatCount > 1) {
        result.push(`  ... [repeated ${repeatCount - 1} more times] ...`);
      }
      prev = line;
      repeatCount = 1;
      result.push(line);
    }
  }

  if (repeatCount > 1) {
    result.push(`  ... [repeated ${repeatCount - 1} more times] ...`);
  }

  return result;
}

/**
 * Head/Tail windowing matching reducer.asl
 */
export function windowLines(
  lines: string[],
  headLimit: number,
  tailLimit: number
): { lines: string[]; evicted: number } {
  const total = lines.length;
  const capacity = headLimit + tailLimit;

  if (total <= capacity) {
    return { lines, evicted: 0 };
  }

  const evicted = total - capacity;
  const marker = `... [${evicted} lines evicted from buffer] ...`;
  const headPart = headLimit > 0 ? lines.slice(0, headLimit) : [];
  const tailPart = tailLimit > 0 ? lines.slice(total - tailLimit) : [];

  return {
    lines: [...headPart, marker, ...tailPart],
    evicted,
  };
}

/**
 * Parses file:line:col or file:line string
 */
function parseFileLoc(locStr: string): { file: string; line: number; col: number } {
  const parts = locStr.split(":");
  if (parts.length >= 3) {
    const file = parts[0].trim();
    const line = parseInt(parts[1].trim(), 10) || 0;
    const col = parseInt(parts[2].trim(), 10) || 0;
    return { file, line, col };
  } else if (parts.length === 2) {
    const file = parts[0].trim();
    const line = parseInt(parts[1].trim(), 10) || 0;
    return { file, line, col: 0 };
  }
  return { file: locStr.trim(), line: 0, col: 0 };
}

/**
 * Diagnostic extraction matching diagnostics.asl
 */
export function extractDiagnostics(lines: string[]): Diagnostic[] {
  const diagnostics: Diagnostic[] = [];

  let inPythonTb = false;
  let pythonTbLines: string[] = [];
  let pythonTbFile = "";
  let pythonTbLine = 0;

  let pendingRustc: Diagnostic | null = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Python Traceback tracking
    if (line.startsWith("Traceback (most recent call last):")) {
      inPythonTb = true;
      pythonTbLines = [line];
      pythonTbFile = "";
      pythonTbLine = 0;
      continue;
    }

    if (inPythonTb) {
      pythonTbLines.push(line);
      const fileMatch = line.match(/File "([^"]+)", line (\d+)/);
      if (fileMatch) {
        pythonTbFile = fileMatch[1];
        pythonTbLine = parseInt(fileMatch[2], 10);
      }
      // If end of traceback line: ExceptionName: message or non-indented error
      if (!line.startsWith(" ") && !line.startsWith("\t") && pythonTbLines.length > 1) {
        diagnostics.push({
          kind: "python",
          severity: "error",
          message: line.trim() || "Python Traceback",
          file: pythonTbFile,
          line: pythonTbLine,
          col: 0,
          raw: [...pythonTbLines],
        });
        inPythonTb = false;
        pythonTbLines = [];
      }
      continue;
    }

    // Rustc diagnostics: error[E0308]: ... or warning: ...
    const rustcErrMatch = line.match(/^(error(?:\[[^\]]+\])?|warning(?:\[[^\]]+\])?):\s*(.*)$/);
    if (rustcErrMatch) {
      if (pendingRustc) {
        diagnostics.push(pendingRustc);
      }
      const sev = rustcErrMatch[1].startsWith("error") ? "error" : "warning";
      pendingRustc = {
        kind: "rustc",
        severity: sev,
        message: line,
        file: "",
        line: 0,
        col: 0,
        raw: [line],
      };
      continue;
    }

    // Check rustc location pointer: --> src/main.rs:10:5
    if (pendingRustc && line.trimStart().startsWith("-->")) {
      pendingRustc.raw.push(line);
      const locStr = line.replace(/^\s*-->\s*/, "").trim();
      const loc = parseFileLoc(locStr);
      pendingRustc.file = loc.file;
      pendingRustc.line = loc.line;
      pendingRustc.col = loc.col;
      diagnostics.push(pendingRustc);
      pendingRustc = null;
      continue;
    }

    // TypeScript tsc diagnostic: file.ts(10,5): error TS2322: ... or file.ts:10:5 - error TS2322: ...
    if (line.includes(" - error TS") || line.includes(" - warning TS")) {
      const isErr = line.includes(" - error TS");
      const marker = isErr ? " - error TS" : " - warning TS";
      const halves = line.split(marker);
      const loc = parseFileLoc(halves[0].trim());
      diagnostics.push({
        kind: "tsc",
        severity: isErr ? "error" : "warning",
        message: `TS${halves[1].trim()}`,
        file: loc.file,
        line: loc.line,
        col: loc.col,
        raw: [line],
      });
      continue;
    }

    // Pytest diagnostics: FAILED tests/test_app.py::test_case - ...
    if (line.startsWith("FAILED ") || line.startsWith("ERROR ")) {
      const isFailed = line.startsWith("FAILED ");
      const leadLen = isFailed ? 7 : 6;
      const body = line.slice(leadLen).trim();
      const dashParts = body.split(" - ");
      const target = dashParts[0].trim();
      const msg = dashParts.length > 1 ? dashParts.slice(1).join(" - ").trim() : body;
      const file = target.split("::")[0].trim();
      diagnostics.push({
        kind: "pytest",
        severity: isFailed ? "failure" : "error",
        message: msg,
        file,
        line: 0,
        col: 0,
        raw: [line],
      });
      continue;
    }

    // Generic fatal errors
    if (line.startsWith("fatal: ") || line.startsWith("[ERROR] ")) {
      diagnostics.push({
        kind: "generic",
        severity: "error",
        message: line,
        file: "",
        line: 0,
        col: 0,
        raw: [line],
      });
      continue;
    }
  }

  if (pendingRustc) {
    diagnostics.push(pendingRustc);
  }

  if (inPythonTb && pythonTbLines.length > 0) {
    diagnostics.push({
      kind: "python",
      severity: "error",
      message: "Python Traceback",
      file: pythonTbFile,
      line: pythonTbLine,
      col: 0,
      raw: pythonTbLines,
    });
  }

  return diagnostics;
}

export function summarizeDiagnostics(diagnostics: Diagnostic[]): DiagnosticSummary {
  let errors = 0;
  let warnings = 0;
  let failures = 0;

  for (const d of diagnostics) {
    if (d.severity === "error") errors++;
    else if (d.severity === "warning") warnings++;
    else if (d.severity === "failure") failures++;
  }

  return { errors, warnings, failures, diagnostics };
}

/**
 * Full stream reduction matching reducer.asl reduce-stream
 */
export function reduceStream(rawText: string, config: ReductionConfig = {}): ReducedStream {
  const cfg: Required<ReductionConfig> = {
    headLimit: config.headLimit ?? DEFAULT_REDUCTION_CONFIG.headLimit,
    tailLimit: config.tailLimit ?? DEFAULT_REDUCTION_CONFIG.tailLimit,
    dedupRepeats: config.dedupRepeats ?? DEFAULT_REDUCTION_CONFIG.dedupRepeats,
  };

  const cleaned = cleanTerminalText(rawText);
  const rawLines = cleaned.split("\n");
  const rawLineCount = rawLines.length;

  const diagnostics = extractDiagnostics(rawLines);
  const summary = summarizeDiagnostics(diagnostics);

  const processedLines = cfg.dedupRepeats ? dedupLines(rawLines) : rawLines;
  const windowRes = windowLines(processedLines, cfg.headLimit, cfg.tailLimit);

  const finalLines = windowRes.lines;
  const evictedLineCount = windowRes.evicted;
  const reducedLineCount = finalLines.length;
  const finalText = finalLines.join("\n");

  return {
    rawLineCount,
    reducedLineCount,
    evictedLineCount,
    lines: finalLines,
    text: finalText,
    diagnostics: summary,
  };
}

export function reduceText(rawText: string): ReducedStream {
  return reduceStream(rawText, DEFAULT_REDUCTION_CONFIG);
}
