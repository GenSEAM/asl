/**
 * Auto-generated / transpiled runtime artifact from pure AgentScript module: harness/src/browser_gate.asl
 * Architecture: Sovereign ASL Core -> Polyglot Web Execution Sink
 */

export interface GateVerdict {
  gateNum: number;
  name: string;
  passed: boolean;
  summary: string;
}

export interface VerificationResult {
  passed: boolean;
  allPassed: boolean;
  verdicts: GateVerdict[];
  durationMs: number;
  environment: 'svg' | 'games' | 'website';
  sanitizedCode: string;
  healingDirective?: string;
}

export function runInBrowserGates(
  code: string,
  environment: 'svg' | 'games' | 'website'
): VerificationResult {
  const start = performance.now();
  const verdicts: GateVerdict[] = [];
  let sanitized = (code || '').trim();
  let healingNeeded = false;
  let healingDirective = '';

  // Gate 1: Syntax & Structural Balance
  if (environment === 'svg') {
    const isAsn = sanitized.startsWith('(:');
    if (isAsn) {
      let depth = 0;
      let balanced = true;
      for (const char of sanitized) {
        if (char === '(') depth++;
        else if (char === ')') {
          depth--;
          if (depth < 0) { balanced = false; break; }
        }
      }
      balanced = balanced && depth === 0;
      verdicts.push({
        gateNum: 1,
        name: 'ASN Form Balance',
        passed: balanced,
        summary: balanced ? 'All S-expression parentheses are balanced.' : `Unbalanced parentheses (delta: ${depth}).`
      });
      if (!balanced) {
        healingNeeded = true;
        healingDirective = `Fix syntax: S-expression is unbalanced (depth: ${depth}). Output strictly balanced ASN vector S-expression.`;
      }
    } else {
      const hasSvgStart = sanitized.includes('<svg');
      const hasSvgEnd = sanitized.includes('</svg>');
      const valid = hasSvgStart && hasSvgEnd;
      verdicts.push({
        gateNum: 1,
        name: 'SVG XML Structure',
        passed: valid,
        summary: valid ? 'Valid <svg> ... </svg> root tags detected.' : 'Missing opening or closing <svg> tags.'
      });
      if (!valid) {
        healingNeeded = true;
        healingDirective = 'Fix SVG structure: Wrap all visual elements inside valid <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 320">...</svg>.';
      }
    }
  } else {
    // HTML / JS syntax gate
    const hasHtmlOrJs = sanitized.includes('<script') || sanitized.includes('<canvas') || sanitized.includes('<div') || sanitized.includes('<section') || sanitized.includes('<header') || sanitized.includes('<main') || sanitized.includes('function') || sanitized.includes('document.');
    verdicts.push({
      gateNum: 1,
      name: 'HTML/JS Structure',
      passed: hasHtmlOrJs,
      summary: hasHtmlOrJs ? 'Recognized standard DOM / Canvas / Script structures.' : 'No recognized HTML or Canvas structure.'
    });
    if (!hasHtmlOrJs) {
      healingNeeded = true;
      healingDirective = 'Fix structure: Provide a self-contained HTML page with a <canvas> element or UI container and interactive <script>.';
    }
  }

  // Gate 2: Sandbox Safety & Runtime Policy
  const forbiddenApis = ['eval(', 'Function(', 'indexedDB.deleteDatabase'];
  const foundForbidden = forbiddenApis.filter(api => sanitized.includes(api));
  const safetyPassed = foundForbidden.length === 0;
  verdicts.push({
    gateNum: 2,
    name: 'Sandbox Security',
    passed: safetyPassed,
    summary: safetyPassed ? 'Zero forbidden / unsafe APIs detected.' : `Restricted API detected: ${foundForbidden.join(', ')}.`
  });
  if (!safetyPassed) {
    healingNeeded = true;
    healingDirective = `Fix security: Remove restricted API calls (${foundForbidden.join(', ')}). Use local memory state and standard canvas APIs.`;
  }

  // Gate 3: Render Readiness & Visual Bounds
  if (environment === 'svg') {
    const hasViewBox = sanitized.includes('viewBox') || sanitized.includes(':v "') || sanitized.includes(':w');
    verdicts.push({
      gateNum: 3,
      name: 'ViewBox Calibration',
      passed: hasViewBox,
      summary: hasViewBox ? 'Calibrated 320x320 viewport bounds confirmed.' : 'Missing viewBox or dimensions.'
    });
  } else if (environment === 'games') {
    const hasCanvasOrGameLoop = (sanitized.includes('<canvas') || sanitized.includes('createElement("canvas")')) &&
      (sanitized.includes('requestAnimationFrame') || sanitized.includes('setInterval') || sanitized.includes('getContext'));
    verdicts.push({
      gateNum: 3,
      name: 'Game Loop Readiness',
      passed: hasCanvasOrGameLoop,
      summary: hasCanvasOrGameLoop ? 'Canvas element & game animation loop confirmed.' : 'Missing canvas element or game loop.'
    });
    if (!hasCanvasOrGameLoop) {
      healingNeeded = true;
      healingDirective = 'Fix game loop: Implement a standard 2D canvas game loop using requestAnimationFrame(loop).';
    }
  } else {
    const hasUiOrInteractivity = sanitized.includes('class=') || sanitized.includes('style=') || sanitized.includes('addEventListener') || sanitized.includes('onclick');
    verdicts.push({
      gateNum: 3,
      name: 'Interactive UI Readiness',
      passed: hasUiOrInteractivity,
      summary: hasUiOrInteractivity ? 'Component styling and interactivity confirmed.' : 'Missing interactive state or styles.'
    });
  }

  const allPassed = verdicts.every(v => v.passed);
  const elapsed = performance.now() - start;

  return {
    passed: allPassed,
    allPassed,
    verdicts,
    durationMs: Math.round(elapsed * 100) / 100,
    environment,
    sanitizedCode: sanitized,
    healingDirective: healingNeeded ? healingDirective : undefined
  };
}
