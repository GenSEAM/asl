/**
 * Auto-generated / transpiled runtime artifact from pure AgentScript module: harness/src/anti_hallucination.asl
 * Architecture: Sovereign ASL Core -> Polyglot Web Execution Sink
 */

import { asnToSvg } from './asn_svg';

export interface FsmRepairReport {
  raw: string;
  cleanCode: string;
  thinking: string;
  toolKind: 'html' | 'svg' | 'direct';
  openDelta: number;
  repaired: boolean;
}

export class AntiHallucinationHarness {
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

  public stripMarkdownFences(raw: string): string {
    const { code } = this.extractThinking(raw);
    let text = code.trim();
    const fenceMatch = text.match(/^```[a-zA-Z0-9_\-]*\n?([\s\S]*?)(?:\n?```)?$/);
    if (fenceMatch) {
      text = fenceMatch[1].trim();
    } else {
      text = text.replace(/^```[a-zA-Z0-9_\-]*\n?/gm, '').replace(/\n?```$/gm, '').trim();
    }
    return text;
  }

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
      asnSvg = asnSvg.replace(/(\(:[a-zA-Z]+[^\)]+\))\s*(?:\1\s*){2,}/gi, '$1');
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
            const remainder = rest.slice(i + 1).trim();
            if (remainder.length === 0 || remainder.startsWith(')')) {
              return { code: extracted, toolKind: 'html' };
            }
          }
          extracted += c;
        }
        return { code: extracted, toolKind: 'html' };
      }
    }

    // 4. Compact Positional ASL Toolcall (:call "write" "index.html" "...")
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

    // 6. Multi-Block Markdown (e.g. ```html ... ``` followed by ```javascript ... ```)
    const htmlBlock = text.match(/```(?:html)\n([\s\S]*?)```/i);
    const jsBlock = text.match(/```(?:javascript|js)\n([\s\S]*?)```/i);
    if (htmlBlock && jsBlock) {
      const combined = `${htmlBlock[1].trim()}\n<script>\n${jsBlock[1].trim()}\n</script>`;
      return { code: combined, toolKind: 'html' };
    }

    // 7. Direct HTML or DOCTYPE
    if (text.includes('<!DOCTYPE') || text.includes('<html') || text.includes('<canvas') || text.includes('<div')) {
      return { code: text, toolKind: 'html' };
    }

    return { code: text, toolKind: 'direct' };
  }

  public repairAndNormalize(raw: string): FsmRepairReport {
    const { thinking } = this.extractThinking(raw);
    const { code, toolKind } = this.extractPositionalToolcall(raw);

    let cleanCode = code.trim();
    let openDelta = 0;
    let repaired = false;

    if (toolKind === 'svg' && cleanCode.startsWith('(:svg')) {
      const openCount = (cleanCode.match(/\(/g) || []).length;
      const closeCount = (cleanCode.match(/\)/g) || []).length;
      openDelta = openCount - closeCount;

      if (openDelta > 0) {
        cleanCode += ')'.repeat(openDelta);
        repaired = true;
      }
      const transpiled = asnToSvg(cleanCode);
      if (transpiled.svg) {
        cleanCode = transpiled.svg;
        repaired = true;
      }
    }

    return {
      raw,
      cleanCode,
      thinking,
      toolKind,
      openDelta,
      repaired
    };
  }
}

export const antiHallucinationHarness = new AntiHallucinationHarness();
