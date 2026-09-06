/**
 * AgentScript Notation (ASN) Vector Graphics Transpiler
 * Transpiles compact ASN S-expressions (:svg, :rc, :circ, :ln, :p, :txt, :g, :grad) to valid SVG XML.
 */

export interface AsnNode {
  type: string;
  props: Record<string, string | number>;
  children?: AsnNode[];
  text?: string;
}

export function asnToSvg(asnSource: string): { svg: string; error?: string } {
  try {
    const trimmed = asnSource.trim();
    if (!trimmed.startsWith('(') || !trimmed.endsWith(')')) {
      return { svg: '', error: 'Input must be a balanced S-expression enclosed in parentheses.' };
    }

    // Basic tokenizer for S-expressions
    const tokens = tokenize(trimmed);
    const ast = parseTokens(tokens);
    const svgXml = renderNode(ast);
    return { svg: svgXml };
  } catch (err: any) {
    return { svg: '', error: err.message || 'Malformed ASN vector expression' };
  }
}

function tokenize(input: string): string[] {
  const tokens: string[] = [];
  let i = 0;
  const len = input.length;

  while (i < len) {
    const ch = input[i];
    if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') {
      i++;
      continue;
    }
    if (ch === ';') {
      while (i < len && input[i] !== '\n') i++;
      continue;
    }
    if (ch === '(' || ch === ')') {
      tokens.push(ch);
      i++;
      continue;
    }
    if (ch === '"') {
      let str = '';
      i++;
      while (i < len && input[i] !== '"') {
        if (input[i] === '\\' && i + 1 < len) {
          str += input[i + 1];
          i += 2;
        } else {
          str += input[i];
          i++;
        }
      }
      i++; // skip closing quote
      tokens.push(`"${str}"`);
      continue;
    }

    let atom = '';
    while (i < len && !' ()\t\n\r"'.includes(input[i])) {
      atom += input[i];
      i++;
    }
    if (atom) tokens.push(atom);
  }
  return tokens;
}

function parseTokens(tokens: string[]): AsnNode {
  let idx = 0;

  function parseExpression(): AsnNode {
    if (tokens[idx] !== '(') {
      throw new Error(`Expected '(' at token ${idx} ('${tokens[idx]}')`);
    }
    idx++; // consume '('

    const tag = tokens[idx++];
    const nodeType = tag.replace(/^:/, '');
    const props: Record<string, string | number> = {};
    const children: AsnNode[] = [];

    while (idx < tokens.length && tokens[idx] !== ')') {
      const tok = tokens[idx];
      if (tok === '(') {
        children.push(parseExpression());
      } else if (tok.startsWith(':')) {
        const key = tok.slice(1);
        idx++;
        if (idx < tokens.length && tokens[idx] !== ')' && !tokens[idx].startsWith('(')) {
          let val = tokens[idx++];
          if (val.startsWith('"') && val.endsWith('"')) {
            props[key] = val.slice(1, -1);
          } else if (/^-?\d+(\.\d+)?$/.test(val)) {
            props[key] = Number(val);
          } else {
            props[key] = val;
          }
        }
      } else {
        idx++;
      }
    }

    if (tokens[idx] === ')') {
      idx++; // consume ')'
    }

    return { type: nodeType, props, children };
  }

  return parseExpression();
}

function renderNode(node: AsnNode): string {
  const p = node.props;
  const opacity = p.o !== undefined ? `opacity="${p.o}"` : '';

  switch (node.type) {
    case 'svg': {
      const w = p.w || 800;
      const h = p.h || 500;
      const v = p.v || `0 0 ${w} ${h}`;
      const inner = (node.children || []).map(renderNode).join('\n  ');
      return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${v}" width="100%" height="100%" preserveAspectRatio="xMidYMid meet">\n  ${inner}\n</svg>`;
    }
    case 'def':
    case 'defs': {
      const inner = (node.children || []).map(renderNode).join('\n    ');
      return `<defs>\n    ${inner}\n  </defs>`;
    }
    case 'grad':
    case 'linearGradient': {
      const id = p.id || 'g';
      const x1 = p.x1 ?? '0%';
      const y1 = p.y1 ?? '0%';
      const x2 = p.x2 ?? '100%';
      const y2 = p.y2 ?? '100%';
      const inner = (node.children || []).map(renderNode).join('\n      ');
      return `<linearGradient id="${id}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}">\n      ${inner}\n    </linearGradient>`;
    }
    case 'rgrad':
    case 'radialGradient': {
      const id = p.id || 'rg';
      const cx = p.cx ?? '50%';
      const cy = p.cy ?? '50%';
      const r = p.r ?? '50%';
      const inner = (node.children || []).map(renderNode).join('\n      ');
      return `<radialGradient id="${id}" cx="${cx}" cy="${cy}" r="${r}">\n      ${inner}\n    </radialGradient>`;
    }
    case 'stop': {
      const offset = p.offset || p.off || '0%';
      const col = p.col || p.c || '#ffffff';
      const stopOp = p.o !== undefined ? `stop-opacity="${p.o}"` : '';
      return `<stop offset="${offset}" stop-color="${col}" ${stopOp} />`;
    }
    case 'rc':
    case 'rect': {
      const rx = p.rx ?? p.r ?? 0;
      const ry = p.ry ?? p.r ?? rx;
      const rAttr = rx ? `rx="${rx}" ry="${ry}"` : '';
      return `<rect x="${p.x ?? 0}" y="${p.y ?? 0}" width="${p.w ?? 100}" height="${p.h ?? 100}" fill="${p.f || 'none'}" stroke="${p.s || 'none'}" stroke-width="${p.sw || 1}" ${rAttr} ${opacity} />`;
    }
    case 'circ':
    case 'circle': {
      return `<circle cx="${p.cx ?? 50}" cy="${p.cy ?? 50}" r="${p.r ?? 20}" fill="${p.f || 'none'}" stroke="${p.s || 'none'}" stroke-width="${p.sw || 1}" ${opacity} />`;
    }
    case 'ln':
    case 'line': {
      return `<line x1="${p.x1 ?? 0}" y1="${p.y1 ?? 0}" x2="${p.x2 ?? 100}" y2="${p.y2 ?? 100}" stroke="${p.s || '#38bdf8'}" stroke-width="${p.sw || 2}" stroke-linecap="round" ${opacity} />`;
    }
    case 'p':
    case 'path': {
      return `<path d="${p.d || ''}" fill="${p.f || 'none'}" stroke="${p.s || 'none'}" stroke-width="${p.sw || 2}" stroke-linecap="round" stroke-linejoin="round" ${opacity} />`;
    }
    case 'poly':
    case 'polygon': {
      const pts = p.points || p.pts || '';
      return `<polygon points="${pts}" fill="${p.f || 'none'}" stroke="${p.s || 'none'}" stroke-width="${p.sw || 1}" ${opacity} />`;
    }
    case 'txt':
    case 'text': {
      const text = p.text || p.t || '';
      const anchor = p.align === 'center' || p.align === 'middle' ? 'middle' : p.align === 'right' || p.align === 'end' ? 'end' : (p.align || 'start');
      return `<text x="${p.x ?? 20}" y="${p.y ?? 30}" fill="${p.f || '#ffffff'}" font-size="${p.sz || 14}" font-family="${p.family || 'system-ui, -apple-system, sans-serif'}" font-weight="${p.weight || 'normal'}" text-anchor="${anchor}" ${opacity}>${text}</text>`;
    }
    case 'g': {
      const tr = p.tr || p.transform ? `transform="${p.tr || p.transform}"` : '';
      const idAttr = p.id ? `id="${p.id}"` : '';
      const inner = (node.children || []).map(renderNode).join('\n    ');
      return `<g ${idAttr} ${tr} ${opacity}>\n    ${inner}\n  </g>`;
    }
    default:
      return '';
  }
}

