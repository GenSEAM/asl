/**
 * Auto-generated / transpiled runtime artifact from pure AgentScript module: vdom/src/asn_svg.asl
 * Architecture: Sovereign ASL Core -> Polyglot Web Execution Sink
 */

export interface SvgResult {
  svg: string;
  success: boolean;
  errorMsg?: string;
}

export interface AsnNode {
  type: string;
  props: Record<string, any>;
  children: AsnNode[];
}

export function tokenizeAsn(code: string): string[] {
  const tokens: string[] = [];
  let cur = '';
  let inStr = false;
  let esc = false;

  for (let i = 0; i < code.length; i++) {
    const c = code[i];
    if (esc) {
      cur += c;
      esc = false;
      continue;
    }
    if (c === '\\') {
      cur += c;
      esc = true;
      continue;
    }
    if (c === '"') {
      inStr = !inStr;
      cur += c;
      if (!inStr) {
        tokens.push(cur);
        cur = '';
      }
      continue;
    }
    if (inStr) {
      cur += c;
      continue;
    }

    if (c === '(' || c === ')') {
      if (cur.trim()) tokens.push(cur.trim());
      tokens.push(c);
      cur = '';
    } else if (/\s/.test(c)) {
      if (cur.trim()) tokens.push(cur.trim());
      cur = '';
    } else {
      cur += c;
    }
  }
  if (cur.trim()) tokens.push(cur.trim());
  return tokens;
}

export function parseAsnSExpr(tokens: string[]): AsnNode {
  let idx = 0;

  function parseExpression(): AsnNode {
    if (tokens[idx] !== '(') {
      throw new Error(`Expected '(' at token ${idx} ('${tokens[idx]}')`);
    }
    idx++;

    const tag = tokens[idx++];
    const nodeType = (tag || '').replace(/^:/, '');
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
      idx++;
    }

    return { type: nodeType, props, children };
  }

  return parseExpression();
}

export function renderNode(node: AsnNode): string {
  const p = node.props;
  const opacity = p.o !== undefined ? `opacity="${p.o}"` : '';

  switch (node.type) {
    case 'svg': {
      const w = p.w || 320;
      const h = p.h || 320;
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
      const fill = p.f || p.fill || 'none';
      const stroke = p.s || p.stroke || 'none';
      const sw = p.sw || p['stroke-width'] || 1;
      return `<rect x="${p.x ?? 0}" y="${p.y ?? 0}" width="${p.w ?? 100}" height="${p.h ?? 100}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" ${rAttr} ${opacity} />`;
    }
    case 'circ':
    case 'circle': {
      const fill = p.f || p.fill || 'none';
      const stroke = p.s || p.stroke || 'none';
      const sw = p.sw || p['stroke-width'] || 1;
      return `<circle cx="${p.cx ?? 160}" cy="${p.cy ?? 160}" r="${p.r ?? 50}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" ${opacity} />`;
    }
    case 'ln':
    case 'line': {
      const stroke = p.s || p.stroke || '#38bdf8';
      const sw = p.sw || p['stroke-width'] || 2;
      return `<line x1="${p.x1 ?? 0}" y1="${p.y1 ?? 0}" x2="${p.x2 ?? 100}" y2="${p.y2 ?? 100}" stroke="${stroke}" stroke-width="${sw}" stroke-linecap="round" ${opacity} />`;
    }
    case 'p':
    case 'path': {
      const fill = p.f || p.fill || 'none';
      const stroke = p.s || p.stroke || (fill !== 'none' ? 'none' : '#38bdf8');
      const sw = p.sw || p['stroke-width'] || 2;
      return `<path d="${p.d || ''}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" ${opacity} />`;
    }
    case 'poly':
    case 'polygon': {
      const pts = p.pts || p.points || '';
      const fill = p.f || p.fill || (p.s || p.stroke ? 'none' : 'rgba(56, 189, 248, 0.2)');
      const stroke = p.s || p.stroke || (fill !== 'none' ? 'none' : '#38bdf8');
      const sw = p.sw || p['stroke-width'] || 1;
      return `<polygon points="${pts}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" ${opacity} />`;
    }
    case 'txt':
    case 'text': {
      const text = p.text || p.t || '';
      const anchor = p.align === 'center' || p.align === 'middle' ? 'middle' : p.align === 'right' || p.align === 'end' ? 'end' : (p.align || 'start');
      return `<text x="${p.x ?? 20}" y="${p.y ?? 30}" fill="${p.f || '#ffffff'}" font-size="${p.sz || 14}" font-family="${p.family || 'system-ui, sans-serif'}" font-weight="${p.weight || 'normal'}" text-anchor="${anchor}" ${opacity}>${text}</text>`;
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

export function asnToSvg(rawAsn: string): SvgResult {
  try {
    let clean = (rawAsn || '').trim();
    if (!clean.startsWith('(:svg')) {
      const svgIdx = clean.indexOf('(:svg');
      if (svgIdx !== -1) {
        clean = clean.slice(svgIdx);
      } else {
        return { svg: '', success: false, errorMsg: 'No (:svg tag found in input' };
      }
    }

    const tokens = tokenizeAsn(clean);
    if (tokens.length === 0) {
      return { svg: '', success: false, errorMsg: 'Empty token stream' };
    }

    const root = parseAsnSExpr(tokens);
    const svg = renderNode(root);
    return { svg, success: true };
  } catch (err: any) {
    return { svg: '', success: false, errorMsg: err?.message || 'Failed to transpile ASN to SVG' };
  }
}
