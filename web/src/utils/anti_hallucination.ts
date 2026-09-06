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
   * Parses native ASL toolcalls and ASN S-expressions:
   * 1. Direct ASN Vector Graphics: (:svg :w 800 :h 500 (:rc ...) (:circ ...))
   * 2. ASL Toolcall: (:call :tool "write" :path "..." :content "...")
   * 3. Positional ASN: (:c :html "...") or (:c :svg "...")
   */
  public extractPositionalToolcall(raw: string): { code: string; toolKind: 'html' | 'svg' | 'direct' } {
    const trimmed = raw.trim();

    // 1. Native ASN Vector Graphics (:svg :w ... :h ... ...)
    if (trimmed.startsWith('(:svg')) {
      let balanced = trimmed;
      const openCount = (balanced.match(/\(/g) || []).length;
      const closeCount = (balanced.match(/\)/g) || []).length;
      if (openCount > closeCount) {
        balanced += ')'.repeat(openCount - closeCount);
      }
      const transpiled = asnToSvg(balanced);
      if (transpiled.svg) {
        return { code: transpiled.svg, toolKind: 'svg' };
      }
    }

    // 2. ASL Write Toolcall (:call :tool "write" ... :content "...")
    const contentIdx = trimmed.indexOf(':content ');
    if (contentIdx !== -1 && (trimmed.startsWith('(:call') || trimmed.startsWith('(:c '))) {
      let inner = trimmed.slice(contentIdx + 9).trim();
      if (inner.startsWith('"')) inner = inner.slice(1);
      if (inner.endsWith('")')) inner = inner.slice(0, -2);
      else if (inner.endsWith('"')) inner = inner.slice(0, -1);
      inner = inner.replace(/\\"/g, '"').replace(/\\n/g, '\n');
      return { code: inner, toolKind: 'html' };
    }

    // 3. Compact Positional ASL Toolcall (:call "write" "index.html" "...") or (:c :w "..." "...")
    const posWriteMatch = trimmed.match(/^\(:c(?:all)?\s+(?::w|"write")\s+(?:"[^"]+"|[^\s]+)\s+([\s\S]*)\)$/i);
    if (posWriteMatch) {
      let inner = posWriteMatch[1].trim();
      if ((inner.startsWith('"') && inner.endsWith('"')) || (inner.startsWith('`') && inner.endsWith('`'))) {
        inner = inner.slice(1, -1).replace(/\\"/g, '"').replace(/\\n/g, '\n');
      }
      return { code: inner, toolKind: 'html' };
    }

    // 4. Positional HTML (:c :html ...)
    const htmlAsnMatch = trimmed.match(/^\(:c(?:all)?\s+:html\s+([\s\S]*)\)$/i);
    if (htmlAsnMatch) {
      let inner = htmlAsnMatch[1].trim();
      if ((inner.startsWith('"') && inner.endsWith('"')) || (inner.startsWith('`') && inner.endsWith('`'))) {
        inner = inner.slice(1, -1).replace(/\\"/g, '"').replace(/\\n/g, '\n');
      }
      return { code: inner, toolKind: 'html' };
    }

    // 5. Positional SVG (:c :svg ...)
    const svgAsnMatch = trimmed.match(/^\(:c(?:all)?\s+:svg\s+([\s\S]*)\)$/i);
    if (svgAsnMatch) {
      let inner = svgAsnMatch[1].trim();
      if (inner.startsWith('(:svg')) {
        const transpiled = asnToSvg(inner);
        if (transpiled.svg) return { code: transpiled.svg, toolKind: 'svg' };
      }
      if ((inner.startsWith('"') && inner.endsWith('"')) || (inner.startsWith('`') && inner.endsWith('`'))) {
        inner = inner.slice(1, -1).replace(/\\"/g, '"');
      }
      return { code: inner, toolKind: 'svg' };
    }

    return { code: trimmed, toolKind: 'direct' };
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

    // 1. Strip markdown code fence markers if model echoed them
    if (code.startsWith('```asl') || code.startsWith('```asn') || code.startsWith('```lisp')) {
      code = code.replace(/^```[a-z]*\n?/i, '');
      syntaxRepaired = true;
    } else if (code.startsWith('```html')) {
      code = code.slice(7);
      syntaxRepaired = true;
    } else if (code.startsWith('```svg') || code.startsWith('```xml')) {
      code = code.slice(6);
      syntaxRepaired = true;
    } else if (code.startsWith('```')) {
      code = code.slice(3);
      syntaxRepaired = true;
    }

    if (code.endsWith('```')) {
      code = code.slice(0, -3);
      syntaxRepaired = true;
    }
    code = code.trim();

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
