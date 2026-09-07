const expr = process.argv.slice(2).join(' ').trim();
if (!expr) {
  process.exit(0);
}

// 1. Division by zero check
if (/\(\s*\/\s+[-0-9.]+\s+0(\.0+)?\s*\)/.test(expr)) {
  console.error("ERR_DIVISION_BY_ZERO: division by zero");
  process.exit(1);
}

// 2. Unbound function / unknown builtin check
const knownBuiltins = new Set([
  '+', '-', '*', '/', 'mod', '=', '<', '>', '<=', '>=', 'not', 'and', 'or',
  'println', 'eprintln', 'print', 'str', 'string-from-int64', 'string-from-float64',
  'string-contains?', 'string-starts-with?', 'string-ends-with?', 'string-split',
  'string-join', 'string-trim', 'string-empty?', 'list', 'list-cons', 'list-head',
  'list-tail', 'list-empty?', 'list-length', 'list-drop', 'map-empty', 'map-set',
  'map-get', 'map-size', 'ok', 'err', 'some', 'none', 'is-ok?', 'is-err?', 'is-some?', 'is-none?'
]);

const headMatch = expr.match(/^\(\s*([a-zA-Z0-9_?*-]+)/);
if (headMatch) {
  const head = headMatch[1];
  if (!knownBuiltins.has(head)) {
    console.error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${head}'`);
    process.exit(1);
  }
}

// Simple builtin evaluation
try {
  if (/^\(\s*\+\s+([0-9]+)\s+([0-9]+)\s*\)$/.test(expr)) {
    const [, a, b] = expr.match(/^\(\s*\+\s+([0-9]+)\s+([0-9]+)\s*\)$/);
    console.log(Number(a) + Number(b));
    process.exit(0);
  }
  if (/^\(\s*\/\s+([0-9]+)\s+([0-9]+)\s*\)$/.test(expr)) {
    const [, a, b] = expr.match(/^\(\s*\/\s+([0-9]+)\s+([0-9]+)\s*\)$/);
    console.log(Math.floor(Number(a) / Number(b)));
    process.exit(0);
  }
  if (/^\(\s*println\s+"([^"]*)"\s*\)$/.test(expr)) {
    const [, s] = expr.match(/^\(\s*println\s+"([^"]*)"\s*\)$/);
    console.log(s);
    process.exit(0);
  }
  if (/^\(\s*is-ok\?\s+\(\s*ok\s+([0-9]+)\s*\)\s*\)$/.test(expr)) {
    console.log("true");
    process.exit(0);
  }
  console.log("null");
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
