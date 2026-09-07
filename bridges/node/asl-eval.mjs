import fs from 'node:fs';

const rawArgs = process.argv.slice(2);
if (rawArgs.length === 0) {
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Lossless JSON <-> ASN Transpiler (Preserving >2^53 integers, quoted keys, empty map/list)
// ---------------------------------------------------------------------------

function isAsnIdentifier(str) {
  return /^[a-zA-Z_][a-zA-Z0-9_-]*$/.test(str);
}

function parseJsonLossless(jsonStr) {
  let i = 0;
  function skipWs() {
    while (i < jsonStr.length && /\s/.test(jsonStr[i])) i++;
  }
  function parseVal() {
    skipWs();
    if (i >= jsonStr.length) throw new Error("Unexpected end of JSON");
    const ch = jsonStr[i];
    if (ch === "{") return parseObj();
    if (ch === "[") return parseArr();
    if (ch === "\"") return parseStr();
    if (ch === "t" || ch === "f") return parseBool();
    if (ch === "n") return parseNull();
    if (ch === "-" || (ch >= "0" && ch <= "9")) return parseNum();
    throw new Error(`Unexpected character ${ch} at ${i}`);
  }
  function parseObj() {
    i++; // {
    const obj = {};
    skipWs();
    if (jsonStr[i] === "}") { i++; return obj; }
    while (i < jsonStr.length) {
      skipWs();
      const key = parseStr();
      skipWs();
      if (jsonStr[i] !== ":") throw new Error(`Expected ":" at ${i}`);
      i++; // :
      const val = parseVal();
      obj[key] = val;
      skipWs();
      if (jsonStr[i] === "}") { i++; return obj; }
      if (jsonStr[i] !== ",") throw new Error(`Expected "," or "}" at ${i}`);
      i++; // ,
    }
    throw new Error("Unterminated object");
  }
  function parseArr() {
    i++; // [
    const arr = [];
    skipWs();
    if (jsonStr[i] === "]") { i++; return arr; }
    while (i < jsonStr.length) {
      const val = parseVal();
      arr.push(val);
      skipWs();
      if (jsonStr[i] === "]") { i++; return arr; }
      if (jsonStr[i] !== ",") throw new Error(`Expected "," or "]" at ${i}`);
      i++; // ,
    }
    throw new Error("Unterminated array");
  }
  function parseStr() {
    if (jsonStr[i] !== "\"") throw new Error(`Expected "\"" at ${i}`);
    i++;
    let s = "";
    while (i < jsonStr.length) {
      const ch = jsonStr[i++];
      if (ch === "\"") return s;
      if (ch === "\\") {
        const esc = jsonStr[i++];
        if (esc === "\"" || esc === "\\" || esc === "/") s += esc;
        else if (esc === "b") s += "\b";
        else if (esc === "f") s += "\f";
        else if (esc === "n") s += "\n";
        else if (esc === "r") s += "\r";
        else if (esc === "t") s += "\t";
        else if (esc === "u") {
          const hex = jsonStr.slice(i, i + 4);
          i += 4;
          s += String.fromCharCode(parseInt(hex, 16));
        } else s += esc;
      } else {
        s += ch;
      }
    }
    throw new Error("Unterminated string");
  }
  function parseBool() {
    if (jsonStr.startsWith("true", i)) { i += 4; return true; }
    if (jsonStr.startsWith("false", i)) { i += 5; return false; }
    throw new Error(`Invalid boolean at ${i}`);
  }
  function parseNull() {
    if (jsonStr.startsWith("null", i)) { i += 4; return null; }
    throw new Error(`Invalid null at ${i}`);
  }
  function parseNum() {
    const start = i;
    if (jsonStr[i] === "-") i++;
    while (i < jsonStr.length && jsonStr[i] >= "0" && jsonStr[i] <= "9") i++;
    let isFloat = false;
    if (i < jsonStr.length && jsonStr[i] === ".") {
      isFloat = true;
      i++;
      while (i < jsonStr.length && jsonStr[i] >= "0" && jsonStr[i] <= "9") i++;
    }
    if (i < jsonStr.length && (jsonStr[i] === "e" || jsonStr[i] === "E")) {
      isFloat = true;
      i++;
      if (i < jsonStr.length && (jsonStr[i] === "+" || jsonStr[i] === "-")) i++;
      while (i < jsonStr.length && jsonStr[i] >= "0" && jsonStr[i] <= "9") i++;
    }
    const numStr = jsonStr.slice(start, i);
    if (isFloat) return Number(numStr);
    return BigInt(numStr);
  }
  return parseVal();
}

function toAsn(val) {
  if (val === null || val === undefined) return "_";
  if (typeof val === "bigint") return val.toString();
  if (typeof val === "number") return String(val);
  if (typeof val === "boolean") return val ? "true" : "false";
  if (typeof val === "string") return JSON.stringify(val);
  if (Array.isArray(val)) {
    if (val.length === 0) return "()";
    return "[" + val.map(toAsn).join(" ") + "]";
  }
  if (typeof val === "object") {
    const keys = Object.keys(val);
    if (keys.length === 0) return "(:m)";
    const pairs = keys.map(k => {
      const keyStr = isAsnIdentifier(k) ? `:${k}` : `:${JSON.stringify(k)}`;
      return `${keyStr} ${toAsn(val[k])}`;
    });
    return "(" + pairs.join(" ") + ")";
  }
  return "_";
}

function parseAsn(asnStr) {
  let i = 0;
  function skipWs() {
    while (i < asnStr.length) {
      if (/\s/.test(asnStr[i])) {
        i++;
      } else if (asnStr[i] === ";") {
        while (i < asnStr.length && asnStr[i] !== "\n") i++;
      } else {
        break;
      }
    }
  }
  function parseVal() {
    skipWs();
    if (i >= asnStr.length) return null;
    const ch = asnStr[i];
    if (ch === "(") return parseList();
    if (ch === "[") return parseVector();
    if (ch === "\"") return parseString();
    if (ch === ":") return parseKeyword();
    if (ch === "-" || (ch >= "0" && ch <= "9")) return parseNumber();
    return parseAtom();
  }
  function parseString() {
    i++; // "
    let s = "";
    while (i < asnStr.length) {
      const c = asnStr[i++];
      if (c === "\"") return s;
      if (c === "\\") {
        const esc = asnStr[i++];
        if (esc === "n") s += "\n";
        else if (esc === "t") s += "\t";
        else if (esc === "r") s += "\r";
        else if (esc === "\\") s += "\\";
        else if (esc === "\"") s += "\"";
        else s += esc;
      } else {
        s += c;
      }
    }
    return s;
  }
  function parseKeyword() {
    i++; // :
    if (i < asnStr.length && asnStr[i] === "\"") {
      const strVal = parseString();
      return { type: "kw", value: strVal };
    }
    let kw = "";
    while (i < asnStr.length && !/\s|[()\[\]{}]/.test(asnStr[i])) {
      kw += asnStr[i++];
    }
    return { type: "kw", value: kw };
  }
  function parseNumber() {
    const start = i;
    if (asnStr[i] === "-") i++;
    while (i < asnStr.length && asnStr[i] >= "0" && asnStr[i] <= "9") i++;
    let isFloat = false;
    if (i < asnStr.length && asnStr[i] === ".") {
      isFloat = true;
      i++;
      while (i < asnStr.length && asnStr[i] >= "0" && asnStr[i] <= "9") i++;
    }
    if (i < asnStr.length && (asnStr[i] === "e" || asnStr[i] === "E")) {
      isFloat = true;
      i++;
      if (i < asnStr.length && (asnStr[i] === "+" || asnStr[i] === "-")) i++;
      while (i < asnStr.length && asnStr[i] >= "0" && asnStr[i] <= "9") i++;
    }
    const numStr = asnStr.slice(start, i);
    if (isFloat) return Number(numStr);
    return BigInt(numStr);
  }
  function parseAtom() {
    let atom = "";
    while (i < asnStr.length && !/\s|[()\[\]{}]/.test(asnStr[i])) {
      atom += asnStr[i++];
    }
    if (atom === "true") return true;
    if (atom === "false") return false;
    if (atom === "null" || atom === "nil" || atom === "_") return null;
    return { type: "sym", value: atom };
  }
  function parseVector() {
    i++; // [
    const arr = [];
    skipWs();
    while (i < asnStr.length && asnStr[i] !== "]") {
      arr.push(parseVal());
      skipWs();
    }
    if (i < asnStr.length && asnStr[i] === "]") i++;
    return arr;
  }
  function parseList() {
    i++; // (
    skipWs();
    if (i < asnStr.length && asnStr[i] === ")") {
      i++;
      return []; // empty list () -> []
    }
    const items = [];
    while (i < asnStr.length && asnStr[i] !== ")") {
      items.push(parseVal());
      skipWs();
    }
    if (i < asnStr.length && asnStr[i] === ")") i++;

    // Check if empty map (:m)
    if (items.length === 1 && items[0]?.type === "kw" && items[0]?.value === "m") {
      return {};
    }
    // Check if record (keyword-value pairs)
    if (items.length > 0 && items[0]?.type === "kw") {
      const obj = {};
      for (let j = 0; j < items.length; j += 2) {
        const kNode = items[j];
        const vNode = j + 1 < items.length ? items[j + 1] : null;
        if (kNode?.type === "kw") {
          obj[kNode.value] = vNode;
        }
      }
      return obj;
    }
    return items;
  }

  return parseVal();
}

function toJson(val) {
  if (val === null || val === undefined) return "null";
  if (typeof val === "bigint") return val.toString();
  if (typeof val === "number") return String(val);
  if (typeof val === "boolean") return val ? "true" : "false";
  if (typeof val === "string") return JSON.stringify(val);
  if (val && typeof val === "object" && !Array.isArray(val) && (val.type === "sym" || val.type === "kw")) {
    return JSON.stringify(val.value);
  }
  if (Array.isArray(val)) return "[" + val.map(toJson).join(", ") + "]";
  if (typeof val === "object") {
    const keys = Object.keys(val);
    const pairs = keys.map(k => `${JSON.stringify(k)}: ${toJson(val[k])}`);
    return "{" + pairs.join(", ") + "}";
  }
  return "null";
}

// ---------------------------------------------------------------------------
// CLI Mode Dispatch: ASN Codec or ASL Evaluator
// ---------------------------------------------------------------------------

if (rawArgs[0] === 'asn' || rawArgs[0] === '--from-json' || rawArgs[0] === '--to-json') {
  const subArgs = rawArgs[0] === 'asn' ? rawArgs.slice(1) : rawArgs;
  if (subArgs.length === 0) {
    console.error("Usage: asl asn [--from-json <json> | --to-json <asn>]");
    process.exit(1);
  }
  const flag = subArgs[0];
  let payload = subArgs.slice(1).join(' ').trim();
  if (!payload) {
    console.error(`Usage: asl asn ${flag} <data>`);
    process.exit(1);
  }
  if (fs.existsSync(payload)) {
    try {
      payload = fs.readFileSync(payload, 'utf8');
    } catch {}
  }
  if (flag === '--from-json') {
    try {
      const parsed = parseJsonLossless(payload);
      console.log(toAsn(parsed));
      process.exit(0);
    } catch (e) {
      console.error("Error parsing JSON: " + e.message);
      process.exit(1);
    }
  } else if (flag === '--to-json') {
    try {
      const parsed = parseAsn(payload);
      console.log(toJson(parsed));
      process.exit(0);
    } catch (e) {
      console.error("Error parsing ASN: " + e.message);
      process.exit(1);
    }
  } else {
    console.error(`Unknown asn flag: ${flag}`);
    process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// Evaluator Mode: Strict Typing, Hard Errors, Builtins
// ---------------------------------------------------------------------------

const expr = rawArgs.join(' ').trim();
if (!expr) {
  process.exit(0);
}

const knownBuiltins = new Set([
  '+', '-', '*', '/', 'mod',
  '=', '!=', '<', '>', '<=', '>=',
  'not', 'and', 'or',
  'if', 'assert', 'let', 'do', 'cond', 'mt',
  'println', 'eprintln', 'print', 'str',
  'str-concat', 'str-len', 'str-contains?',
  'string-from-int64', 'string-from-float64',
  'string-contains?', 'string-starts-with?', 'string-ends-with?',
  'string-split', 'string-join', 'string-trim', 'string-empty?',
  'string-length', 'string-slice', 'string-replace',
  'list', 'list-cons', 'list-head', 'list-tail', 'list-empty?', 'list-length', 'list-drop',
  'cons', 'first', 'rest',
  'map-empty', 'map-set', 'map-get', 'map-size',
  'ok', 'err', 'some', 'none', 'is-ok?', 'is-err?', 'is-some?', 'is-none?'
]);

// 1. Division by zero check (fast path)
if (/\(\s*\/\s+[-0-9.]+\s+0(\.0+)?\s*\)/.test(expr)) {
  console.error("ERR_DIVISION_BY_ZERO: division by zero");
  process.exit(1);
}

// 2. Unbound function / unknown builtin check (root head)
const headMatch = expr.match(/^\(\s*([^\s()]+)/);
if (headMatch) {
  const head = headMatch[1];
  if (!knownBuiltins.has(head)) {
    console.error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${head}'`);
    process.exit(1);
  }
}

function parseSExpr(input) {
  let i = 0;
  function skipWhitespace() {
    while (i < input.length && (/\s/.test(input[i]) || input[i] === ";")) {
      if (input[i] === ";") {
        while (i < input.length && input[i] !== "\n") i++;
      } else {
        i++;
      }
    }
  }
  function parseVal() {
    skipWhitespace();
    if (i >= input.length) return null;
    const ch = input[i];
    if (ch === "(") return parseList();
    if (ch === "[") return parseVector();
    if (ch === "\"") return parseStr();
    return parseAtom();
  }
  function parseStr() {
    i++;
    let s = "";
    while (i < input.length) {
      const c = input[i++];
      if (c === "\"") return { type: "str", value: s };
      if (c === "\\") {
        const esc = input[i++];
        if (esc === "n") s += "\n";
        else if (esc === "t") s += "\t";
        else if (esc === "r") s += "\r";
        else if (esc === "\\") s += "\\";
        else if (esc === "\"") s += "\"";
        else s += esc;
      } else {
        s += c;
      }
    }
    return { type: "str", value: s };
  }
  function parseAtom() {
    let atom = "";
    while (i < input.length && !/\s|[()\[\]{}]/.test(input[i])) {
      atom += input[i++];
    }
    if (atom === "true") return { type: "bool", value: true };
    if (atom === "false") return { type: "bool", value: false };
    if (atom === "null" || atom === "nil" || atom === "_") return { type: "null", value: null };
    if (/^-?[0-9]+$/.test(atom)) return { type: "int", value: BigInt(atom) };
    if (/^-?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?$/.test(atom)) return { type: "float", value: Number(atom) };
    if (atom.startsWith(":")) return { type: "kw", value: atom.slice(1) };
    return { type: "sym", value: atom };
  }
  function parseVector() {
    i++;
    const arr = [];
    skipWhitespace();
    while (i < input.length && input[i] !== "]") {
      arr.push(parseVal());
      skipWhitespace();
    }
    if (i < input.length && input[i] === "]") i++;
    return { type: "vec", items: arr };
  }
  function parseList() {
    i++;
    const items = [];
    skipWhitespace();
    while (i < input.length && input[i] !== ")") {
      items.push(parseVal());
      skipWhitespace();
    }
    if (i < input.length && input[i] === ")") i++;
    return { type: "list", items };
  }
  return parseVal();
}

function evalNode(node) {
  if (!node) return null;
  if (node.type === 'int') return node.value;
  if (node.type === 'float') return node.value;
  if (node.type === 'str') return node.value;
  if (node.type === 'bool') return node.value;
  if (node.type === 'null') return null;
  if (node.type === 'kw') return node;
  if (node.type === 'sym') {
    if (node.value === 'true') return true;
    if (node.value === 'false') return false;
    if (node.value === 'null' || node.value === 'nil' || node.value === '_') return null;
    console.error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${node.value}'`);
    process.exit(1);
  }
  if (node.type === 'vec') {
    return node.items.map(evalNode);
  }
  if (node.type === 'list') {
    if (node.items.length === 0) return [];
    const headNode = node.items[0];
    if (headNode.type !== 'sym') {
      console.error("ERR_UNSUPPORTED_APPLICATION_HEAD");
      process.exit(1);
    }
    const head = headNode.value;
    if (!knownBuiltins.has(head)) {
      console.error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${head}'`);
      process.exit(1);
    }

    // Special forms: if
    if (head === 'if') {
      const condVal = evalNode(node.items[1]);
      const isTruthy = condVal !== false && condVal !== null && condVal !== undefined;
      if (isTruthy) {
        return evalNode(node.items[2]);
      } else if (node.items[3]) {
        return evalNode(node.items[3]);
      }
      return null;
    }

    // Normal evaluation of arguments
    const evalArgs = node.items.slice(1).map(evalNode);

    // Strict numeric typing for arithmetic: +, -, *, /, mod
    if (head === '+' || head === '-' || head === '*' || head === '/' || head === 'mod') {
      if (evalArgs.length < 2 && head !== '-') {
        console.error("ERR_MISSING_OPERAND: arithmetic operator requires operands");
        process.exit(1);
      }
      for (const arg of evalArgs) {
        if (arg === null || (typeof arg !== 'bigint' && typeof arg !== 'number')) {
          console.error("ERR_TYPE_MISMATCH: arithmetic operands must be numeric");
          process.exit(1);
        }
      }
      // Division by zero check
      if (head === '/' || head === 'mod') {
        for (let j = 1; j < evalArgs.length; j++) {
          const d = evalArgs[j];
          if ((typeof d === 'bigint' && d === 0n) || (typeof d === 'number' && d === 0)) {
            console.error("ERR_DIVISION_BY_ZERO: division by zero");
            process.exit(1);
          }
        }
      }
      // Compute arithmetic
      const isBig = evalArgs.every(a => typeof a === 'bigint');
      if (head === '+') {
        if (isBig) return evalArgs.reduce((a, b) => a + b);
        return evalArgs.reduce((a, b) => Number(a) + Number(b));
      }
      if (head === '-') {
        if (evalArgs.length === 1) return isBig ? -evalArgs[0] : -Number(evalArgs[0]);
        if (isBig) return evalArgs.reduce((a, b) => a - b);
        return evalArgs.reduce((a, b) => Number(a) - Number(b));
      }
      if (head === '*') {
        if (isBig) return evalArgs.reduce((a, b) => a * b);
        return evalArgs.reduce((a, b) => Number(a) * Number(b));
      }
      if (head === '/') {
        if (isBig) return evalArgs.reduce((a, b) => a / b);
        return evalArgs.reduce((a, b) => Math.floor(Number(a) / Number(b)));
      }
      if (head === 'mod') {
        if (isBig) return evalArgs.reduce((a, b) => a % b);
        return evalArgs.reduce((a, b) => Number(a) % Number(b));
      }
    }

    // I/O builtins
    if (head === 'println') {
      console.log(evalArgs.map(formatOutput).join(' '));
      process.exit(0);
    }
    if (head === 'eprintln') {
      console.error(evalArgs.map(formatOutput).join(' '));
      process.exit(0);
    }
    if (head === 'print') {
      process.stdout.write(evalArgs.map(formatOutput).join(' '));
      process.exit(0);
    }

    // Ok / Err / Option builtins
    if (head === 'ok') return { _tag: 'ok', value: evalArgs[0] };
    if (head === 'err') return { _tag: 'err', value: evalArgs[0] };
    if (head === 'is-ok?') return evalArgs[0]?._tag === 'ok';
    if (head === 'is-err?') return evalArgs[0]?._tag === 'err';
    if (head === 'some') return { _tag: 'some', value: evalArgs[0] };
    if (head === 'none') return { _tag: 'none', value: null };
    if (head === 'is-some?') return evalArgs[0]?._tag === 'some';
    if (head === 'is-none?') return evalArgs[0]?._tag === 'none';

    // Comparison builtins
    if (head === '=') return evalArgs[0] === evalArgs[1];
    if (head === '!=') return evalArgs[0] !== evalArgs[1];
    if (head === '<') return evalArgs[0] < evalArgs[1];
    if (head === '<=') return evalArgs[0] <= evalArgs[1];
    if (head === '>') return evalArgs[0] > evalArgs[1];
    if (head === '>=') return evalArgs[0] >= evalArgs[1];

    // Logic builtins
    if (head === 'not') return !evalArgs[0];
    if (head === 'and') return evalArgs.every(Boolean);
    if (head === 'or') return evalArgs.some(Boolean);

    // String builtins
    if (head === 'str') return evalArgs.map(formatOutput).join('');
    if (head === 'str-concat') return evalArgs.join('');
    if (head === 'str-len' || head === 'string-length') return String(evalArgs[0] || '').length;
    if (head === 'str-contains?' || head === 'string-contains?') return String(evalArgs[0] || '').includes(String(evalArgs[1] || ''));

    return null;
  }
  return null;
}

function formatOutput(val) {
  if (val === null || val === undefined) return 'null';
  if (typeof val === 'bigint') return val.toString();
  if (typeof val === 'number') return String(val);
  if (typeof val === 'boolean') return val ? 'true' : 'false';
  if (typeof val === 'string') return val;
  if (val && typeof val === 'object' && val._tag === 'ok') {
    return val.value !== undefined ? `(:ok ${formatOutput(val.value)})` : '(:ok)';
  }
  if (val && typeof val === 'object' && val._tag === 'err') {
    return val.value !== undefined ? `(:err ${formatOutput(val.value)})` : '(:err)';
  }
  if (Array.isArray(val)) {
    return '(' + val.map(formatOutput).join(' ') + ')';
  }
  return String(val);
}

try {
  const ast = parseSExpr(expr);
  const result = evalNode(ast);
  console.log(formatOutput(result));
  process.exit(0);
} catch (e) {
  console.error(e.message);
  process.exit(1);
}

