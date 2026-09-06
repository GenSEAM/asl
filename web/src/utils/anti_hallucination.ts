/**
 * Anti-Hallucination Engine, ASL Toolcall Parser & ASN Transpiler
 * Designed for In-Browser AgentScript (ASL / ASN) Agent Runtime.
 * Intercepts native ASL tool calls (:call :tool "write" ...) and ASN vector graphics (:svg ...).
 */

import { asnToSvg } from './asn_svg';

export interface FsmRepairReport {
  originalLength: number;
  repairedLength: number;
  unclosedParens: number;
  unclosedBrackets: number;
  unclosedHtmlTags: string[];
  syntaxRepaired: boolean;
  sanitized: boolean;
  toolKind?: 'html' | 'svg' | 'direct';
  cleanCode: string;
}

export class AntiHallucinationHarness {
  /**
   * Extracts reasoning thoughts from <think>...</think> blocks
   */
  public extractThinking(raw: string): { thinking: string; code: string } {
    const thinkMatch = raw.match(/<think>([\s\S]*?)<\/think>/i);
    if (thinkMatch) {
      const thinking = thinkMatch[1].trim();
      const code = raw.replace(/<think>[\s\S]*?<\/think>/i, '').trim();
      return { thinking, code };
    }
    const unclosedMatch = raw.match(/<think>([\s\S]*)$/i);
    if (unclosedMatch) {
      return { thinking: unclosedMatch[1].trim(), code: '' };
    }
    return { thinking: '', code: raw };
  }

  /**
   * Cleans code blocks and extracts raw content from potential markdown wrappers and thinking blocks
   */
  public stripMarkdownFences(raw: string): string {
    const { code } = this.extractThinking(raw);
    let text = code.trim();
    // Strip leading code fence markers (e.g. ```asn, ```asl, ```html, ```svg, ```)
    const fenceMatch = text.match(/^```[a-zA-Z0-9_\-]*\n?([\s\S]*?)(?:\n?```)?$/);
    if (fenceMatch) {
      text = fenceMatch[1].trim();
    } else {
      // Strip standalone fences if present
      text = text.replace(/^```[a-zA-Z0-9_\-]*\n?/gm, '').replace(/\n?```$/gm, '').trim();
    }
    return text;
  }

  /**
   * Parses native ASL toolcalls and ASN S-expressions:
   * 1. Direct ASN Vector Graphics: (:svg :w 800 :h 500 (:rc ...) (:circ ...))
   * 2. ASL Toolcall: (:call :tool "write" :path "..." :content "...")
   * 3. Positional ASN: (:c :html "...") or (:c :svg "...")
   */
  public extractPositionalToolcall(raw: string): { code: string; toolKind: 'html' | 'svg' | 'direct' } {
    let text = this.stripMarkdownFences(raw);

    // 1. Native ASN Vector Graphics (:svg :w ... :h ... ...)
    const svgIdx = text.indexOf('(:svg');
    if (svgIdx !== -1) {
      let depth = 0;
      let inStr = false;
      let esc = false;
      let endIdx = -1;
      for (let i = svgIdx; i < text.length; i++) {
        const c = text[i];
        if (esc) { esc = false; continue; }
        if (c === '\\') { esc = true; continue; }
        if (c === '"') { inStr = !inStr; continue; }
        if (inStr) continue;
        if (c === '(') depth++;
        else if (c === ')') {
          depth--;
          if (depth === 0) {
            endIdx = i + 1;
            break;
          }
        }
      }

      let asnSvg = endIdx !== -1 ? text.slice(svgIdx, endIdx) : text.slice(svgIdx);
      if (depth > 0) {
        asnSvg += ')'.repeat(depth);
      }
      const transpiled = asnToSvg(asnSvg.trim());
      if (transpiled.svg) {
        return { code: transpiled.svg, toolKind: 'svg' };
      }
    }

    // 2. Direct SVG XML (<svg ... </svg>)
    const directSvgMatch = text.match(/<svg[\s\S]*?<\/svg>/i);
    if (directSvgMatch) {
      return { code: directSvgMatch[0], toolKind: 'svg' };
    }

    // 3. ASL Write Toolcall (:call :tool "write" ... :content "...")
    const contentIdx = text.indexOf(':content ');
    if (contentIdx !== -1 && (text.includes('(:call') || text.includes('(:c '))) {
      let rest = text.slice(contentIdx + 9).trim();
      if (rest.startsWith('"')) {
        let extracted = '';
        let esc = false;
        for (let i = 1; i < rest.length; i++) {
          const c = rest[i];
          if (esc) {
            if (c === 'n') extracted += '\n';
            else if (c === '"') extracted += '"';
            else if (c === '\\') extracted += '\\';
            else extracted += '\\' + c;
            esc = false;
            continue;
          }
          if (c === '\\') {
            esc = true;
            continue;
          }
          if (c === '"') {
            // End of string argument
            return { code: extracted, toolKind: 'html' };
          }
          extracted += c;
        }
        return { code: extracted, toolKind: 'html' };
      }
    }


    // 4. Compact Positional ASL Toolcall (:call "write" "index.html" "...") or (:c :w "..." "...")
    const posWriteMatch = text.match(/^\(:c(?:all)?\s+(?::w|"write")\s+(?:"[^"]+"|[^\s]+)\s+([\s\S]*)\)$/i);
    if (posWriteMatch) {
      let inner = posWriteMatch[1].trim();
      if ((inner.startsWith('"') && inner.endsWith('"')) || (inner.startsWith('`') && inner.endsWith('`'))) {
        inner = inner.slice(1, -1).replace(/\\"/g, '"').replace(/\\n/g, '\n');
      }
      return { code: inner, toolKind: 'html' };
    }

    // 5. Positional HTML (:c :html ...)
    const htmlAsnMatch = text.match(/^\(:c(?:all)?\s+:html\s+([\s\S]*)\)$/i);
    if (htmlAsnMatch) {
      let inner = htmlAsnMatch[1].trim();
      if ((inner.startsWith('"') && inner.endsWith('"')) || (inner.startsWith('`') && inner.endsWith('`'))) {
        inner = inner.slice(1, -1).replace(/\\"/g, '"').replace(/\\n/g, '\n');
      }
      return { code: inner, toolKind: 'html' };
    }

    // 6. Direct HTML or DOCTYPE
    if (text.includes('<!DOCTYPE') || text.includes('<html') || text.includes('<canvas') || text.includes('<div')) {
      return { code: text, toolKind: 'html' };
    }

    return { code: text, toolKind: 'direct' };
  }

  /**
   * Balances delimiters and tags in real time from raw ASL/SLM token stream
   */
  public repairAndNormalize(rawCode: string): FsmRepairReport {
    let { code, toolKind } = this.extractPositionalToolcall(rawCode);
    let unclosedParens = 0;
    let unclosedBrackets = 0;
    const unclosedHtmlTags: string[] = [];
    let syntaxRepaired = false;
    let sanitized = false;

    // Additional check: if code is still an unparsed (:svg ...), transpile it now
    if (code.startsWith('(:svg')) {
      const openCount = (code.match(/\(/g) || []).length;
      const closeCount = (code.match(/\)/g) || []).length;
      if (openCount > closeCount) {
        code += ')'.repeat(openCount - closeCount);
      }
      const transpiled = asnToSvg(code);
      if (transpiled.svg) {
        code = transpiled.svg;
        toolKind = 'svg';
        syntaxRepaired = true;
      }
    }


    // 2. FSM Delimiter Check for ASL S-expression parens and brackets
    const parenStack: string[] = [];
    let inString = false;
    let escape = false;

    for (let i = 0; i < code.length; i++) {
      const char = code[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (char === '\\') {
        escape = true;
        continue;
      }
      if (char === '"' || char === '`') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (char === '(') {
        parenStack.push('(');
      } else if (char === ')') {
        if (parenStack.length > 0 && parenStack[parenStack.length - 1] === '(') {
          parenStack.pop();
        }
      } else if (char === '[') {
        parenStack.push('[');
      } else if (char === ']') {
        if (parenStack.length > 0 && parenStack[parenStack.length - 1] === '[') {
          parenStack.pop();
        }
      }
    }

    // Repair unclosed brackets/parens
    while (parenStack.length > 0) {
      const open = parenStack.pop();
      if (open === '(') {
        code += ')';
        unclosedParens++;
        syntaxRepaired = true;
      } else if (open === '[') {
        code += ']';
        unclosedBrackets++;
        syntaxRepaired = true;
      }
    }

    // 3. HTML / SVG Tag Balancer (if extracted code is HTML/SVG)
    const isHtmlOrSvg = code.includes('<html') || code.includes('<svg') || code.includes('<div') || code.includes('<!DOCTYPE');
    if (isHtmlOrSvg) {
      const tagStack: string[] = [];
      const tagRegex = /<\/?([a-zA-Z0-9\-]+)(?:\s+[^>]*?)?(\/?)>/g;
      let match;
      const selfClosing = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr', 'circle', 'rect', 'line', 'path', 'stop']);

      while ((match = tagRegex.exec(code)) !== null) {
        const fullTag = match[0];
        const tagName = match[1].toLowerCase();
        const isClosing = fullTag.startsWith('</');
        const isExplicitSelfClose = match[2] === '/' || fullTag.endsWith('/>');

        if (selfClosing.has(tagName) || isExplicitSelfClose) {
          continue;
        }

        if (isClosing) {
          if (tagStack.length > 0 && tagStack[tagStack.length - 1] === tagName) {
            tagStack.pop();
          }
        } else {
          tagStack.push(tagName);
        }
      }

      // Close open tags in reverse order
      while (tagStack.length > 0) {
        const tagToClose = tagStack.pop()!;
        code += `</${tagToClose}>`;
        unclosedHtmlTags.push(tagToClose);
        syntaxRepaired = true;
      }
    }

    // 4. Action Firewall: strip dangerous network exploits in local sandbox
    const dangerousPatterns = [
      /document\.cookie/gi,
      /window\.localStorage/gi,
      /fetch\s*\(\s*['"]http/gi,
      /XMLHttpRequest/gi
    ];

    for (const pattern of dangerousPatterns) {
      if (pattern.test(code)) {
        code = code.replace(pattern, '/* [FIREWALL BLOCKED] */ undefined');
        sanitized = true;
      }
    }

    return {
      originalLength: rawCode.length,
      repairedLength: code.length,
      unclosedParens,
      unclosedBrackets,
      unclosedHtmlTags,
      syntaxRepaired,
      sanitized,
      toolKind,
      cleanCode: code
    };
  }
}

export const antiHallucinationHarness = new AntiHallucinationHarness();
