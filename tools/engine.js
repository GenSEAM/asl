let assertionCount = 0;
let refutationCount = 0;
let rejectionCount = 0;
let plannedTestCount = 0;
let startedTestCount = 0;
let completedTestCount = 0;




const rawArgs = process.argv.slice(2);
const wantsMetrics = rawArgs.includes('--metrics');
const cleanArgs = rawArgs.filter(a => a !== '--metrics');
const t0 = performance.now();
if (cleanArgs.length === 0) {
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
        else if (esc === "u") {
          const hex = asnStr.slice(i, i + 4);
          i += 4;
          s += String.fromCharCode(parseInt(hex, 16));
        }
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

if (cleanArgs[0] === 'asn' || cleanArgs[0] === '--from-json' || cleanArgs[0] === '--to-json') {
  const subArgs = cleanArgs[0] === 'asn' ? cleanArgs.slice(1) : cleanArgs;
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
    } catch (e) {
      console.error(e.message);
      process.exit(1);
    }
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

const knownBuiltins = new Set([
  '+', '-', '*', '/', 'mod',
  '=', '==', '!=', '<', '>', '<=', '>=',
  'not', 'and', 'or',
  'if', 'assert', 'reject', 'let', 'do', 'cond', 'when', 'unless', 'mt', 'try',
  'df', 'fn', 'module', 'dfe', 'dfs',
  'println', 'eprintln', 'print', 'str',
  'str-concat', 'str-len', 'str-contains?',
  'string-length', 'string-from-int64', 'string-from-int', 'string-from-float64', 'string-from-float',
  'string-contains?', 'string-starts-with?', 'string-ends-with?',
  'string-split', 'string-join', 'string-trim', 'string-empty?',
  'list', 'list-cons', 'list-head', 'list-tail', 'list-empty?', 'list-length', 'list-len', 'len', 'list-drop',
  'list-sort', 'list-sort-by', 'list-sum', 'list-min', 'list-max', 'list-index-of',
  'cons', 'first', 'rest',
  'map-empty', 'map-set', 'map-get', 'map-size', 'map-keys', 'map-values', 'map-pairs', 'map-from-pairs', 'map-remove',
  'ok', 'err', 'some', 'none', 'is-ok?', 'is-err?', 'is-some?', 'is-none?', 'option-is-none?', 'option-is-some?', 'option-unwrap', 'unwrap',
  'option-map', 'result-or', 'option-to-result',
  'abs', 'neg', 'min', 'max', 'checked-div', 'checked-mod',
  'option-or', 'result-map', 'result-map-err', 'result-to-option',
  'already-exists', 'interrupted', 'invalid-path', 'not-found', 'other', 'permission-denied',
  'list-append', 'list-concat', 'concat', 'list-contains?', 'list-get', 'list-slice', 'list-reverse', 'filter', 'fold', 'map', 'range', 'zip',
  'map-has?', 'pair', 'show',
  'string-to-int64', 'string-to-float64', 'int64-to-float64', 'float-from-int64', 'float', 'float64-to-int64', 'int32-to-int64', 'int64-to-int32',
  'string-chars', 'string-lower', 'string-upper', 'string-replace', 'string-reverse', 'string-index-of', 'string-slice',
  'string-equals?', 'foldl', 'append-item', 'string-to-lower', 'list-indexed', 'tuple', 'tuple-first', 'tuple-second', 'option-none?', 'option-some?', 'int-to-string',
  'case', 'match', 'refute', 'fst', 'snd', 'second', 'pair-first', 'pair-second', 'tuple2-first', 'list-second', 'list-first', 'list-last', 'list-take', 'list-range', 'list-fold', 'list-filter', 'list-map', 'list-any?', 'any?', 'any', 'all?', 'list-all?', 'fold-left', 'reverse', 'length', 'append', 'count', 'enumerate', 'nil?', 'map-merge', 'get', 'div-i64', 'as-i64', 'as-f64', 'float64-from-int64', 'int64-from-float', 'int-to-str', 'string-to-lowercase', 'string-trim-left', 'string-count-char', 'string-repeat', 'string-append', 'join', 'all', 'tuple2-second', 'head', 'tail', 'div-f64', 'sqrt', 'Ok', 'Err', 'file-read', 'file-write', 'file-exists?', 'file-append', 'error-or', 'file-read', 'read-file'
]);

function extractParamNames(paramsNode) {
  const params = [];
  if (!paramsNode || !Array.isArray(paramsNode.items)) return params;
  for (const p of paramsNode.items) {
    if (!p) continue;
    if (p.type === 'sym') {
      params.push(p.value);
    } else if ((p.type === 'list' || p.type === 'vec') && p.items && p.items[0]?.type === 'sym') {
      params.push(p.items[0].value);
    }
  }
  return params;
}

function invokeClosure(closure, evalArgs) {
  if (closure && closure._isBuiltin) {
    return evaluateBuiltinFunction(closure.builtinName, evalArgs, closure.env || new Map());
  }
  if (closure && closure.name === 'concat' && evalArgs.length > 2) {
    return evalArgs.map(formatOutput).join('');
  }
  const childEnv = new Map(closure.env);
  if (closure.name) {
    childEnv.set(closure.name, closure);
  }
  for (let idx = 0; idx < closure.params.length; idx++) {
    const pName = closure.params[idx];
    const pVal = idx < evalArgs.length ? evalArgs[idx] : null;
    childEnv.set(pName, pVal);
  }
  let lastVal = null;
  try {
    for (const expr of closure.body) {
      lastVal = evalNode(expr, childEnv);
    }
    return lastVal;
  } catch (err) {
    if (err && err._aslTryErr) {
      return err._aslTryErr;
    }
    throw err;
  }
}

function parseAllSExprs(input) {
  let i = 0;
  const lineOffsets = [0];
  for (let idx = 0; idx < input.length; idx++) {
    if (input.charCodeAt(idx) === 10) lineOffsets.push(idx + 1);
  }
  function getLine(pos) {
    let low = 0, high = lineOffsets.length - 1;
    while (low <= high) {
      const mid = (low + high) >> 1;
      if (lineOffsets[mid] <= pos) low = mid + 1;
      else high = mid - 1;
    }
    return high + 1;
  }
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
    if (ch === "{") return parseMap();
    if (ch === "\"") return parseStr();
    return parseAtom();
  }
  function parseMap() {
    const startPos = i;
    i++;
    const items = [];
    skipWhitespace();
    while (i < input.length && input[i] !== "}") {
      const val = parseVal();
      if (val !== null) items.push(val);
      skipWhitespace();
    }
    if (i < input.length && input[i] === "}") i++;
    return { type: "map", items, line: getLine(startPos) };
  }
  function parseStr() {
    const startPos = i;
    i++;
    let s = "";
    while (i < input.length) {
      const c = input[i++];
      if (c === "\"") return { type: "str", value: s, line: getLine(startPos) };
      if (c === "\\") {
        const esc = input[i++];
        if (esc === "n") s += "\n";
        else if (esc === "t") s += "\t";
        else if (esc === "r") s += "\r";
        else if (esc === "\\") s += "\\";
        else if (esc === "\"") s += "\"";
        else if (esc === "u") {
          const hex = input.slice(i, i + 4);
          i += 4;
          s += String.fromCharCode(parseInt(hex, 16));
        }
        else s += esc;
      } else {
        s += c;
      }
    }
    return { type: "str", value: s, line: getLine(startPos) };
  }
  function parseAtom() {
    const startPos = i;
    let atom = "";
    while (i < input.length && !/\s|[()\[\]{}]/.test(input[i])) {
      atom += input[i++];
    }
    const line = getLine(startPos);
    if (atom === "true") return { type: "bool", value: true, line };
    if (atom === "false") return { type: "bool", value: false, line };
    if (atom === "null" || atom === "nil" || atom === "_") return { type: "null", value: null, line };
    if (/^-?[0-9]+$/.test(atom)) return { type: "int", value: BigInt(atom), line };
    if (/^-?[0-9]+\.[0-9]+([eE][+-]?[0-9]+)?$/.test(atom)) return { type: "float", value: Number(atom), line };
    if (atom.startsWith(":")) return { type: "kw", value: atom.slice(1), line };
    return { type: "sym", value: atom, line };
  }
  function parseVector() {
    const startPos = i;
    i++;
    const arr = [];
    skipWhitespace();
    while (i < input.length && input[i] !== "]") {
      const val = parseVal();
      if (val !== null) arr.push(val);
      skipWhitespace();
    }
    if (i < input.length && input[i] === "]") i++;
    return { type: "vec", items: arr, line: getLine(startPos) };
  }
  function parseList() {
    const startPos = i;
    i++;
    const items = [];
    skipWhitespace();
    while (i < input.length && input[i] !== ")") {
      const val = parseVal();
      if (val !== null) items.push(val);
      skipWhitespace();
    }
    if (i < input.length && input[i] === ")") i++;
    return { type: "list", items, line: getLine(startPos) };
  }

  const forms = [];
  while (true) {
    skipWhitespace();
    if (i >= input.length) break;
    const form = parseVal();
    if (form === null) break;
    forms.push(form);
  }
  return forms;
}

function parseSExpr(input) {
  const forms = parseAllSExprs(input);
  return forms.length > 0 ? forms[0] : null;
}

function matchPattern(patNode, targetVal, branchEnv) {
  if (!patNode) return false;
  if (patNode.type === 'null' || (patNode.type === 'sym' && (patNode.value === '_' || patNode.value === 'else' || patNode.value === ':else')) || (patNode.type === 'kw' && patNode.value === 'else')) {
    return true;
  }
  if (patNode.type === 'sym') {
    if (patNode.value === 'none' || patNode.value === 'nil') {
      return targetVal === null || targetVal?._tag === 'none';
    }
    branchEnv.set(patNode.value, targetVal);
    return true;
  }
  if (patNode.type === 'list' || patNode.type === 'vec') {
    if (patNode.items.length === 0) {
      return Array.isArray(targetVal) && targetVal.length === 0;
    }
    const headPat = patNode.items[0];
    const headPatName = headPat?.type === 'sym' ? headPat.value : null;
    if (!headPatName) return false;
    const shortPatName = headPatName.includes('/') ? headPatName.split('/').pop() : headPatName;
    const variantOnly = shortPatName.includes(':') ? shortPatName.split(':').pop() : shortPatName;
    const enumOnly = shortPatName.includes(':') ? shortPatName.split(':')[0] : null;

    if (targetVal === null && (headPatName === 'none' || shortPatName === 'none')) {
      return true;
    }

    if (!targetVal || typeof targetVal !== 'object') {
      return false;
    }

    if (targetVal._type === 'variant' &&
        (targetVal._variant === headPatName || targetVal._variant === shortPatName || targetVal._variant === variantOnly) &&
        (!enumOnly || targetVal._enum === enumOnly)) {
      for (let k = 1; k < patNode.items.length; k++) {
        const subPat = patNode.items[k];
        const val = targetVal[`arg${k}`] !== undefined ? targetVal[`arg${k}`] : targetVal.value;
        if (!matchPattern(subPat, val, branchEnv)) return false;
      }
      return true;
    }

    if (targetVal._tag === 'some' && (headPatName === 'some' || shortPatName === 'some')) {
      return patNode.items.length > 1 ? matchPattern(patNode.items[1], targetVal.value, branchEnv) : true;
    }
    if (targetVal._tag === 'none' && (headPatName === 'none' || shortPatName === 'none')) {
      return true;
    }
    if (targetVal._tag === 'ok' && (headPatName === 'ok' || shortPatName === 'ok')) {
      return patNode.items.length > 1 ? matchPattern(patNode.items[1], targetVal.value, branchEnv) : true;
    }
    if (targetVal._tag === 'err' && (headPatName === 'err' || shortPatName === 'err')) {
      return patNode.items.length > 1 ? matchPattern(patNode.items[1], targetVal.value, branchEnv) : true;
    }
    return false;
  }
  const litVal = evalNode(patNode, branchEnv);
  return (litVal === targetVal || (typeof litVal === 'bigint' && typeof targetVal === 'bigint' && litVal === targetVal) || (typeof litVal === 'bigint' && typeof targetVal === 'number' && litVal == targetVal) || (typeof litVal === 'number' && typeof targetVal === 'bigint' && litVal == targetVal));
}

function evalNode(node, env = new Map()) {
  if (!node) return null;
  if (node.type === 'int') return node.value;
  if (node.type === 'float') return node.value;
  if (node.type === 'str') return node.value;
  if (node.type === 'bool') return node.value;
  if (node.type === 'null') return null;
  if (node.type === 'kw') return node;
  if (node.type === 'sym') {
    if (env.has(node.value)) return env.get(node.value);
    if (node.value === 'true') return true;
    if (node.value === 'false') return false;
    if (node.value === 'null' || node.value === 'nil' || node.value === '_' || node.value === 'Unit') return null;
    if (knownBuiltins.has(node.value) && !['if', 'assert', 'reject', 'refute', 'let', 'do', 'cond', 'when', 'unless', 'mt', 'try', 'df', 'fn', 'module', 'dfe', 'dfs', 'case', 'match'].includes(node.value)) {
      return {
        _type: 'closure',
        name: node.value,
        params: ['a', 'b', 'c'],
        _isBuiltin: true,
        builtinName: node.value,
        env: env
      };
    }
      throw new Error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${node.value}'`);
  }
  if (node.type === 'vec') {
    return node.items.map(it => evalNode(it, env));
  }
  if (node.type === 'map') {
    const obj = {};
    for (let j = 0; j < node.items.length; j += 2) {
      const kNode = node.items[j];
      const vNode = j + 1 < node.items.length ? node.items[j + 1] : null;
      let key;
      if (kNode?.type === 'kw' || kNode?.type === 'str' || kNode?.type === 'sym') {
        key = kNode.value;
      } else {
        const evaluatedKey = evalNode(kNode, env);
        key = (evaluatedKey && typeof evaluatedKey === 'object' && evaluatedKey.value !== undefined) ? evaluatedKey.value : evaluatedKey;
      }
      obj[String(key)] = evalNode(vNode, env);
    }
    return obj;
  }
  if (node.type === 'list') {
    if (node.items.length === 0) return [];
    const headNode = node.items[0];
    if (headNode.type === 'kw') {
      const obj = {};
      for (let j = 0; j < node.items.length; j += 2) {
        const kNode = node.items[j];
        const vNode = j + 1 < node.items.length ? node.items[j + 1] : null;
        if (kNode?.type === 'kw') {
          obj[kNode.value] = evalNode(vNode, env);
        }
      }
      return obj;
    }
    if (headNode.type !== 'sym') {
      const callee = evalNode(headNode, env);
      if (callee && callee._type === 'closure') {
        const evalArgs = node.items.slice(1).map(it => evalNode(it, env));
        return invokeClosure(callee, evalArgs);
      }
      console.error("ERR_UNSUPPORTED_APPLICATION_HEAD");
      process.exit(1);
    }
    const head = headNode.value;

    // Property accessor: (.-prop target)
    if (head.startsWith('.-')) {
      const prop = head.slice(2);
      let target = evalNode(node.items[1], env);
      if (target && typeof target === 'object') {
        if (target._tag === 'some' && target.value !== undefined) {
          target = target.value;
        }
        if (Array.isArray(target)) {
          if (prop === 'first') return target[0];
          if (prop === 'second') return target[1];
        }
        return target ? target[prop] : null;
      }
      return null;
    }

    // Check user-defined function / binding in env
    if (env.has(head)) {
      const callee = env.get(head);
      if (callee && callee._type === 'closure') {
        if (callee._isStructConstructor) {
          const obj = { _struct: callee.structName };
          for (let j = 1; j < node.items.length; j += 2) {
            const kNode = node.items[j];
            const vNode = j + 1 < node.items.length ? node.items[j + 1] : null;
            if (kNode?.type === 'kw') {
              obj[kNode.value] = evalNode(vNode, env);
            }
          }
          return obj;
        }
        if (callee._isEnumVariant) {
          const obj = { _type: 'variant', _enum: callee.enum, _variant: callee.variant };
          for (let j = 1; j < node.items.length; j++) {
            obj[`arg${j}`] = evalNode(node.items[j], env);
          }
          return obj;
        }
        const evalArgs = node.items.slice(1).map(it => evalNode(it, env));
        return invokeClosure(callee, evalArgs);
      }
    }

    if (!knownBuiltins.has(head)) {
      throw new Error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${head}'`);
    }

    // Special forms: module
    if (head === 'module') {
      return null;
    }

    // Special forms: dfe (enum definition)
    if (head === 'dfe') {
      const enumName = node.items[1]?.value;
      for (let j = 2; j < node.items.length; j++) {
        const item = node.items[j];
        if (item?.type === 'list' && item.items.length >= 2) {
          const cKw = item.items[0]?.value;
          if (cKw === 'c') {
            const variantName = item.items[1]?.value;
            if (variantName) {
              const constructor = {
                _type: 'closure',
                _isEnumVariant: true,
                name: variantName,
                enum: enumName,
                variant: variantName,
                params: [],
                body: []
              };
              env.set(variantName, constructor);
              if (enumName) {
                env.set(`${enumName}:${variantName}`, constructor);
              }
            }
          }
        }
      }
      return null;
    }

    // Special forms: dfs (struct definition)
    if (head === 'dfs') {
      const structName = node.items[1]?.value;
      const fields = [];
      for (let j = 2; j < node.items.length; j++) {
        const item = node.items[j];
        if (item?.type === 'list' && item.items.length >= 2) {
          const fKw = item.items[0]?.value;
          if (fKw === 'f') {
            const fName = item.items[1]?.value;
            if (fName) fields.push(fName);
          }
        }
      }
      const constructor = {
        _type: 'closure',
        _isStructConstructor: true,
        name: structName,
        structName,
        fields,
        params: [],
        body: []
      };
      env.set(structName, constructor);
      return null;
    }

    // Special forms: df
    if (head === 'df') {
      let nameIdx = 1;
      if (node.items[nameIdx]?.type === 'sym' && node.items[nameIdx].value === '!') {
        nameIdx++;
      }
      if (node.items[nameIdx]?.type === 'map') {
        nameIdx++;
      }
      const fnName = node.items[nameIdx]?.type === 'sym' ? node.items[nameIdx].value : null;
      const paramsNode = node.items[nameIdx + 1];
      let bodyIdx = nameIdx + 2;
      if (bodyIdx < node.items.length && node.items[bodyIdx]?.type === 'sym' && node.items[bodyIdx].value === '->') {
        bodyIdx += 2;
      }
      if (bodyIdx < node.items.length && node.items[bodyIdx]?.type === 'kw' && node.items[bodyIdx].value === 'd') {
        bodyIdx += 2;
      }
      const body = node.items.slice(bodyIdx);
      const params = extractParamNames(paramsNode);
      const closure = { _type: 'closure', name: fnName, params, body, env };
      if (fnName) {
        env.set(fnName, closure);
      }
      return closure;
    }

    // Special forms: fn
    if (head === 'fn') {
      let paramsIdx = 1;
      if (node.items[paramsIdx]?.type === 'sym' && node.items[paramsIdx].value === '!') {
        paramsIdx++;
      }
      if (node.items[paramsIdx]?.type === 'map') {
        paramsIdx++;
      }
      const paramsNode = node.items[paramsIdx];
      let bodyIdx = paramsIdx + 1;
      if (bodyIdx < node.items.length && node.items[bodyIdx]?.type === 'sym' && node.items[bodyIdx].value === '->') {
        bodyIdx += 2;
      }
      if (bodyIdx < node.items.length && node.items[bodyIdx]?.type === 'kw' && node.items[bodyIdx].value === 'd') {
        bodyIdx += 2;
      }
      const body = node.items.slice(bodyIdx);
      const params = extractParamNames(paramsNode);
      return { _type: 'closure', name: null, params, body, env };
    }

    // Special forms: assert
    if (head === 'assert') {
      const condVal = evalNode(node.items[1], env);
      const isTruthy = condVal !== false && condVal !== null && condVal !== undefined;
      if (!isTruthy) {
        const msg = node.items[2] ? evalNode(node.items[2], env) : 'assertion evaluated to false';
        throw new Error(`[ASL_ASSERTION_FAILURE]: ${msg}`);
      }
      assertionCount++;
      return true;
    }

    if (head === 'reject') {
      const condVal = evalNode(node.items[1], env);
      const isTruthy = condVal !== false && condVal !== null && condVal !== undefined;
      if (isTruthy) {
        const msg = node.items[2] ? evalNode(node.items[2], env) : 'rejection condition evaluated to true';
        throw new Error(`[ASL_REJECTION_FAILURE]: ${msg}`);
      }
      rejectionCount++;
      return true;
    }

    // Special forms: refute
    if (head === 'refute') {
      let condVal;
      let raised = false;
      try {
        condVal = evalNode(node.items[1], env);
      } catch (e) {
        raised = true;
      }
      const isTruthy = !raised && condVal !== false && condVal !== null && condVal !== undefined;
      if (isTruthy) {
        const msg = node.items[2] ? evalNode(node.items[2], env) : 'refutation evaluated to true';
        throw new Error(`[ASL_REFUTATION_FAILURE]: ${msg}`);
      }
      refutationCount++;
      return true;
    }

    // Special forms: case
    if (head === 'case') {
      const targetVal = evalNode(node.items[1], env);
      for (let j = 2; j < node.items.length; j++) {
        const branch = node.items[j];
        if (!branch || (branch.type !== 'list' && branch.type !== 'vec') || branch.items.length < 2) continue;
        const patNode = branch.items[0];
        let isMatch = false;
        if (patNode.type === 'null' || (patNode.type === 'sym' && (patNode.value === '_' || patNode.value === 'else' || patNode.value === ':else')) || (patNode.type === 'kw' && patNode.value === 'else')) {
          isMatch = true;
        } else {
          const patVal = evalNode(patNode, env);
          if (patVal === targetVal) {
            isMatch = true;
          } else if ((typeof patVal === 'bigint' && typeof targetVal === 'number') || (typeof patVal === 'number' && typeof targetVal === 'bigint')) {
            isMatch = patVal == targetVal;
          } else if (patVal && targetVal && typeof patVal === 'object' && typeof targetVal === 'object') {
            isMatch = JSON.stringify(patVal) === JSON.stringify(targetVal);
          }
        }
        if (isMatch) {
          let lastVal = null;
          for (let k = 1; k < branch.items.length; k++) {
            lastVal = evalNode(branch.items[k], env);
          }
          return lastVal;
        }
      }
      return null;
    }

    // Special forms: try
    if (head === 'try') {
      const res = evalNode(node.items[1], env);
      if (res && typeof res === 'object') {
        if (res._tag === 'err') {
          const unwinder = new Error('ASL_TRY_UNWIND');
          unwinder._aslTryErr = res;
          throw unwinder;
        }
        if (res._tag === 'ok') {
          return res.value;
        }
      }
      return res;
    }

    // Special forms: do
    if (head === 'do') {
      let lastVal = null;
      for (let j = 1; j < node.items.length; j++) {
        lastVal = evalNode(node.items[j], env);
      }
      return lastVal;
    }

    // Special forms: let
    if (head === 'let') {
      const bindingsNode = node.items[1];
      const childEnv = new Map(env);
      const items = bindingsNode?.items || [];
      if (items.length > 0 && (items[0]?.type === 'vec' || items[0]?.type === 'list')) {
        for (const pair of items) {
          if (pair?.items && pair.items.length >= 2) {
            const varSym = pair.items[0];
            const valExpr = pair.items[1];
            const varName = varSym.type === 'sym' ? varSym.value :
              ((varSym.type === 'list' || varSym.type === 'vec') && varSym.items[0]?.type === 'sym') ? varSym.items[0].value : null;
            if (varName) {
              childEnv.set(varName, evalNode(valExpr, childEnv));
            }
          }
        }
      } else {
        for (let j = 0; j < items.length; j += 2) {
          const varSym = items[j];
          const valExpr = j + 1 < items.length ? items[j + 1] : null;
          const varName = varSym?.type === 'sym' ? varSym.value :
            ((varSym?.type === 'list' || varSym?.type === 'vec') && varSym.items[0]?.type === 'sym') ? varSym.items[0].value : null;
          if (varName) {
            childEnv.set(varName, evalNode(valExpr, childEnv));
          }
        }
      }
      let lastVal = null;
      for (let j = 2; j < node.items.length; j++) {
        lastVal = evalNode(node.items[j], childEnv);
      }
      return lastVal;
    }

    // Special forms: if
    if (head === 'if') {
      const condVal = evalNode(node.items[1], env);
      const isTruthy = condVal !== false && condVal !== null && condVal !== undefined;
      if (isTruthy) {
        return evalNode(node.items[2], env);
      } else if (node.items[3]) {
        return evalNode(node.items[3], env);
      }
      return null;
    }

    // Special forms: cond
    if (head === 'cond') {
      for (let j = 1; j < node.items.length; j++) {
        const branch = node.items[j];
        if (branch && (branch.type === 'list' || branch.type === 'vec') && branch.items.length >= 2) {
          const testNode = branch.items[0];
          let isMatch = false;
          if ((testNode.type === 'kw' && testNode.value === 'else') ||
              (testNode.type === 'sym' && (testNode.value === 'else' || testNode.value === ':else'))) {
            isMatch = true;
          } else {
            const testVal = evalNode(testNode, env);
            isMatch = testVal !== false && testVal !== null && testVal !== undefined;
          }
          if (isMatch) {
            let lastVal = null;
            for (let k = 1; k < branch.items.length; k++) {
              lastVal = evalNode(branch.items[k], env);
            }
            return lastVal;
          }
        }
      }
      return null;
    }

    // Special forms: when
    if (head === 'when') {
      const condVal = evalNode(node.items[1], env);
      const isTruthy = condVal !== false && condVal !== null && condVal !== undefined;
      if (isTruthy) {
        let lastVal = null;
        for (let j = 2; j < node.items.length; j++) {
          lastVal = evalNode(node.items[j], env);
        }
        return lastVal;
      }
      return null;
    }

    // Special forms: unless
    if (head === 'unless') {
      const condVal = evalNode(node.items[1], env);
      const isFalsy = condVal === false || condVal === null || condVal === undefined;
      if (isFalsy) {
        let lastVal = null;
        for (let j = 2; j < node.items.length; j++) {
          lastVal = evalNode(node.items[j], env);
        }
        return lastVal;
      }
      return null;
    }

    // Special forms: mt (pattern match)
    if (head === 'mt' || head === 'match') {
      const targetVal = evalNode(node.items[1], env);
      for (let j = 2; j < node.items.length; j++) {
        const branch = node.items[j];
        if (!branch || (branch.type !== 'list' && branch.type !== 'vec') || branch.items.length < 2) continue;
        const patNode = branch.items[0];
        const branchEnv = new Map(env);
        const isMatch = matchPattern(patNode, targetVal, branchEnv);
        if (isMatch) {
          let lastVal = null;
          for (let k = 1; k < branch.items.length; k++) {
            lastVal = evalNode(branch.items[k], branchEnv);
          }
          return lastVal;
        }
      }
      return null;
    }

    // Normal evaluation of arguments
    const evalArgs = node.items.slice(1).map(it => evalNode(it, env));
    return evaluateBuiltinFunction(head, evalArgs, env);
  }
  return null;
}

function getMapKey(obj, rawKey) {
  if (rawKey === null || rawKey === undefined) return '';
  const k = (typeof rawKey === 'object' && rawKey.value !== undefined) ? String(rawKey.value) : String(rawKey);
  if (obj && Object.prototype.hasOwnProperty.call(obj, k)) return k;
  if (k.startsWith(':') && obj && Object.prototype.hasOwnProperty.call(obj, k.slice(1))) return k.slice(1);
  if (!k.startsWith(':') && obj && Object.prototype.hasOwnProperty.call(obj, ':' + k)) return ':' + k;
  return k;
}

function evaluateBuiltinFunction(head, evalArgs, env) {
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
        return evalArgs.reduce((a, b) => Number(a) / Number(b));
      }
      if (head === 'mod') {
        if (isBig) return evalArgs.reduce((a, b) => a % b);
        return evalArgs.reduce((a, b) => Number(a) % Number(b));
      }
    }

    // Math builtins
    if (head === 'abs') {
      const a = evalArgs[0];
      return typeof a === 'bigint' ? (a < 0n ? -a : a) : Math.abs(Number(a));
    }
    if (head === 'neg') {
      const a = evalArgs[0];
      return typeof a === 'bigint' ? -a : -Number(a);
    }
    if (head === 'min') {
      const isBig = evalArgs.every(a => typeof a === 'bigint');
      return isBig ? evalArgs.reduce((a, b) => a < b ? a : b) : Math.min(...evalArgs.map(Number));
    }
    if (head === 'max') {
      const isBig = evalArgs.every(a => typeof a === 'bigint');
      return isBig ? evalArgs.reduce((a, b) => a > b ? a : b) : Math.max(...evalArgs.map(Number));
    }
    if (head === 'checked-div') {
      const a = evalArgs[0];
      const b = evalArgs[1];
      if ((typeof b === 'bigint' && b === 0n) || (typeof b === 'number' && b === 0)) {
        return { _tag: 'none', value: null };
      }
      return { _tag: 'some', value: (typeof a === 'bigint' && typeof b === 'bigint') ? a / b : Math.floor(Number(a) / Number(b)) };
    }
    if (head === 'checked-mod') {
      const a = evalArgs[0];
      const b = evalArgs[1];
      if ((typeof b === 'bigint' && b === 0n) || (typeof b === 'number' && b === 0)) {
        return { _tag: 'none', value: null };
      }
      return { _tag: 'some', value: (typeof a === 'bigint' && typeof b === 'bigint') ? a % b : Number(a) % Number(b) };
    }

    // I/O builtins
    if (head === 'println') {
      console.log(evalArgs.map(formatOutput).join(' '));
      return { _tag: 'ok', value: null, _silent: true };
    }
    if (head === 'eprintln') {
      console.error(evalArgs.map(formatOutput).join(' '));
      return { _tag: 'ok', value: null, _silent: true };
    }
    if (head === 'print') {
      process.stdout.write(evalArgs.map(formatOutput).join(' '));
      return { _tag: 'ok', value: null, _silent: true };
    }


    // Ok / Err / Option builtins
    if (head === 'ok' || head === 'Ok') return { _tag: 'ok', value: evalArgs[0] };
    if (head === 'err' || head === 'Err') return { _tag: 'err', value: evalArgs[0] };
    if (head === 'is-ok?') return evalArgs[0]?._tag === 'ok';
    if (head === 'is-err?') return evalArgs[0]?._tag === 'err';
    if (head === 'some') return { _tag: 'some', value: evalArgs[0] };
    if (head === 'none') return { _tag: 'none', value: null };
    if (head === 'is-some?') return evalArgs[0]?._tag === 'some';
    if (head === 'is-none?' || head === 'option-is-none?' || head === 'option-none?') return evalArgs[0]?._tag === 'none';
    if (head === 'is-some?' || head === 'option-is-some?' || head === 'option-some?') return evalArgs[0]?._tag === 'some';
    if (head === 'option-unwrap' || head === 'unwrap') return evalArgs[0]?._tag === 'some' ? evalArgs[0].value : evalArgs[0];
    if (head === 'option-map') {
      if (evalArgs[0]?._tag === 'some') return { _tag: 'some', value: evalArgs[1] !== undefined ? evalArgs[1] : evalArgs[0].value };
      return { _tag: 'none', value: null };
    }
    if (head === 'option-or') {
      return evalArgs[0]?._tag === 'some' ? evalArgs[0].value : evalArgs[1];
    }
    if (head === 'result-or') {
      return evalArgs[0]?._tag === 'ok' ? evalArgs[0].value : evalArgs[1];
    }
    if (head === 'error-or') {
      return evalArgs[0]?._tag === 'err' ? evalArgs[0].value : evalArgs[1];
    }
    if (head === 'result-map') {
      if (evalArgs[1]?._tag === 'ok') {
        const fn = evalArgs[0];
        const val = evalArgs[1].value;
        const res = (fn && fn._type === 'closure') ? invokeClosure(fn, [val]) : (typeof fn === 'function' ? fn(val) : val);
        return { _tag: 'ok', value: res };
      }
      return evalArgs[1];
    }
    if (head === 'result-map-err') {
      if (evalArgs[1]?._tag === 'err') {
        const fn = evalArgs[0];
        const val = evalArgs[1].value;
        const res = (fn && fn._type === 'closure') ? invokeClosure(fn, [val]) : (typeof fn === 'function' ? fn(val) : val);
        return { _tag: 'err', value: res };
      }
      return evalArgs[1];
    }
    if (head === 'result-to-option') {
      return evalArgs[0]?._tag === 'ok' ? { _tag: 'some', value: evalArgs[0].value } : { _tag: 'none', value: null };
    }
    if (head === 'option-to-result') {
      return evalArgs[0]?._tag === 'some' ? { _tag: 'ok', value: evalArgs[0].value } : { _tag: 'err', value: evalArgs[1] };
    }

    // IoError union constructors
    if (head === 'already-exists' || head === 'interrupted' || head === 'invalid-path' || head === 'not-found' || head === 'other' || head === 'permission-denied') {
      return { _tag: 'io-error', kind: head };
    }
    if (head === 'file-read' || head === 'read-file') {
      const p = String(evalArgs[0] || '');
      try {
        if (fs.existsSync(p)) {
          const c = fs.readFileSync(p, 'utf8');
          if (c !== undefined) {
            return { _tag: 'ok', value: c };
          }
        }
        return { _tag: 'err', value: { _tag: 'io-error', kind: 'not-found' } };
      } catch (e) {
        return { _tag: 'err', value: { _tag: 'io-error', kind: 'other' } };
      }
    }
    if (head === 'file-write') {
      const p = String(evalArgs[0] || '');
      const data = String(evalArgs[1] || '');
      try {
        fs.writeFileSync(p, data, 'utf8');
        return { _tag: 'ok', value: null };
      } catch (e) {
        return { _tag: 'err', value: { _tag: 'io-error', kind: 'other' } };
      }
    }
    if (head === 'file-exists?') {
      const p = String(evalArgs[0] || '');
      try {
        return fs.existsSync(p);
      } catch (e) {
        return false;
      }
    }
    if (head === 'file-append') {
      const p = String(evalArgs[0] || '');
      const data = String(evalArgs[1] || '');
      try {
        fs.appendFileSync(p, data, 'utf8');
        return { _tag: 'ok', value: null };
      } catch (e) {
        return { _tag: 'err', value: { _tag: 'io-error', kind: 'other' } };
      }
    }

    // List and Map builtins
    if (head === 'list') {
      return evalArgs;
    }
    if (head === 'list-cons' || head === 'cons') {
      const item = evalArgs[0];
      const rest = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      return [item, ...rest];
    }
    if (head === 'list-head') {
      let arr = evalArgs[0];
      if (arr && arr._tag === 'some' && Array.isArray(arr.value)) arr = arr.value;
      if (!Array.isArray(arr)) arr = [];
      if (arr.length > 0) return { _tag: 'some', value: arr[0] };
      return { _tag: 'none', value: null };
    }
    if (head === 'first') {
      let arr = evalArgs[0];
      if (arr && arr._tag === 'some' && Array.isArray(arr.value)) arr = arr.value;
      if (!Array.isArray(arr)) arr = [];
      if (arr.length > 0) return { _tag: 'some', value: arr[0] };
      return { _tag: 'none', value: null };
    }
    if (head === 'list-tail') {
      let arr = evalArgs[0];
      if (arr && arr._tag === 'some' && Array.isArray(arr.value)) arr = arr.value;
      if (!Array.isArray(arr)) arr = [];
      if (arr.length > 0) return { _tag: 'some', value: arr.slice(1) };
      return { _tag: 'none', value: null };
    }
    if (head === 'rest' || head === 'tail') {
      let arr = evalArgs[0];
      if (arr && arr._tag === 'some' && Array.isArray(arr.value)) arr = arr.value;
      if (!Array.isArray(arr)) arr = [];
      return arr.slice(1);
    }
    if (head === 'list-empty?') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return arr.length === 0;
    }
    if (head === 'list-length' || head === 'length' || head === 'list-len' || head === 'len') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return BigInt(arr.length);
    }
    if (head === 'list-drop') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      const count = Number(evalArgs[1]);
      return arr.slice(count);
    }
    if (head === 'list-append' || head === 'list-concat' || head === 'concat') {
      const a = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      const b = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      return [...a, ...b];
    }
    if (head === 'append-item') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return [...arr, evalArgs[1]];
    }
    if (head === 'list-indexed') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return arr.map((item, idx) => {
        const t = [BigInt(idx), item];
        t.first = BigInt(idx);
        t.second = item;
        return t;
      });
    }
    if (head === 'show') {
      return formatOutput(evalArgs[0]);
    }
    if (head === 'list-contains?') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return arr.includes(evalArgs[1]);
    }
    if (head === 'list-get') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      const idx = Number(evalArgs[1]);
      if (idx >= 0 && idx < arr.length) return { _tag: 'some', value: arr[idx] };
      return { _tag: 'none', value: null };
    }
    if (head === 'list-slice') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      const start = Number(evalArgs[1]);
      const end = Number(evalArgs[2]);
      if (start < 0 || end < start || start > arr.length) return { _tag: 'none', value: null };
      return { _tag: 'some', value: arr.slice(start, end) };
    }
    if (head === 'list-reverse') {
      const arr = Array.isArray(evalArgs[0]) ? [...evalArgs[0]] : [];
      return arr.reverse();
    }
    if (head === 'map') {
      const fn = evalArgs[0];
      const arr = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      return arr.map(it => (fn && fn._type === 'closure') ? invokeClosure(fn, [it]) : (typeof fn === 'function' ? fn(it) : it));
    }
    if (head === 'filter') {
      const fn = evalArgs[0];
      const arr = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      return arr.filter(it => {
        const res = (fn && fn._type === 'closure') ? invokeClosure(fn, [it]) : (typeof fn === 'function' ? fn(it) : it);
        return res !== false && res !== null && res !== undefined;
      });
    }
    if (head === 'fold' || head === 'foldl') {
      const fn = evalArgs[0];
      let acc = evalArgs[1];
      const arr = Array.isArray(evalArgs[2]) ? evalArgs[2] : [];
      for (const it of arr) {
        acc = (fn && fn._type === 'closure') ? invokeClosure(fn, [acc, it]) : (typeof fn === 'function' ? fn(acc, it) : acc);
      }
      return acc;
    }
    if (head === 'range') {
      const s = BigInt(evalArgs[0]);
      const e = BigInt(evalArgs[1]);
      const res = [];
      for (let v = s; v < e; v++) res.push(v);
      return res;
    }
    if (head === 'zip') {
      const a = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      const b = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      const len = Math.min(a.length, b.length);
      const res = [];
      for (let j = 0; j < len; j++) res.push([a[j], b[j]]);
      return res;
    }
    if (head === 'list-sort') {
      const arr = Array.isArray(evalArgs[0]) ? [...evalArgs[0]] : [];
      return arr.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    }
    if (head === 'list-sum') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return arr.reduce((a, b) => Number(a) + Number(b), 0);
    }
    if (head === 'list-min') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return arr.length ? arr.reduce((a, b) => (a < b ? a : b)) : null;
    }
    if (head === 'list-max') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return arr.length ? arr.reduce((a, b) => (a > b ? a : b)) : null;
    }
    if (head === 'list-index-of') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      const idx = arr.indexOf(evalArgs[1]);
      return idx >= 0 ? { _tag: 'some', value: BigInt(idx) } : { _tag: 'none', value: null };
    }
    if (head === 'map-has?') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? evalArgs[0] : {};
      const key = getMapKey(obj, evalArgs[1]);
      return Object.prototype.hasOwnProperty.call(obj, key);
    }
    if (head === 'pair' || head === 'tuple') {
      const p = [...evalArgs];
      if (evalArgs.length > 0) p.first = evalArgs[0];
      if (evalArgs.length > 1) p.second = evalArgs[1];
      return p;
    }
    if (head === 'tuple-first') {
      const t = evalArgs[0];
      return Array.isArray(t) ? t[0] : (t?.first ?? null);
    }
    if (head === 'tuple-second') {
      const t = evalArgs[0];
      return Array.isArray(t) ? t[1] : (t?.second ?? null);
    }
    if (head === 'map-keys') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? evalArgs[0] : {};
      return Object.keys(obj);
    }
    if (head === 'map-values') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? evalArgs[0] : {};
      return Object.values(obj);
    }
    if (head === 'map-size') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? evalArgs[0] : {};
      return BigInt(Object.keys(obj).length);
    }
    if (head === 'map-remove') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? { ...evalArgs[0] } : {};
      const key = getMapKey(obj, evalArgs[1]);
      delete obj[key];
      return obj;
    }
    if (head === 'map-empty') {
      return {};
    }
    if (head === 'map-set') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? { ...evalArgs[0] } : {};
      const key = getMapKey(obj, evalArgs[1]);
      obj[key] = evalArgs[2];
      return obj;
    }
    if (head === 'map-get') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? evalArgs[0] : {};
      const key = getMapKey(obj, evalArgs[1]);
      if (Object.prototype.hasOwnProperty.call(obj, key)) {
        return { _tag: 'some', value: obj[key] };
      }
      return { _tag: 'none', value: null };
    }

    // Comparison builtins
    if (head === '=' || head === '==' || head === 'string-equals?') {
      let a = evalArgs[0];
      let b = evalArgs[1];
      if (a && typeof a === 'object' && a._tag === 'some' && (b === null || typeof b !== 'object' || b._tag !== 'some')) a = a.value;
      if (b && typeof b === 'object' && b._tag === 'some' && (a === null || typeof a !== 'object' || a._tag !== 'some')) b = b.value;
      if (a === b) return true;
      if ((typeof a === 'bigint' && typeof b === 'number') || (typeof a === 'number' && typeof b === 'bigint')) {
        return a == b;
      }
      if (a && b && typeof a === 'object' && typeof b === 'object') {
        if (a._type === 'variant' && b._type === 'variant') {
          return a._variant === b._variant;
        }
        const replacer = (_, v) => typeof v === "bigint" ? v.toString() + "n" : v;
        return JSON.stringify(a, replacer) === JSON.stringify(b, replacer);
      }
      return false;
    }
    if (head === '!=') {
      const a = evalArgs[0];
      const b = evalArgs[1];
      if (a === b) return false;
      if ((typeof a === 'bigint' && typeof b === 'number') || (typeof a === 'number' && typeof b === 'bigint')) {
        return a != b;
      }
      if (a && b && typeof a === 'object' && typeof b === 'object') {
        if (a._type === 'variant' && b._type === 'variant') {
          return a._variant !== b._variant;
        }
        const replacer = (_, v) => typeof v === "bigint" ? v.toString() + "n" : v;
        return JSON.stringify(a, replacer) !== JSON.stringify(b, replacer);
      }
      return true;
    }
    if (head === '<') return evalArgs[0] < evalArgs[1];
    if (head === '<=') return evalArgs[0] <= evalArgs[1];
    if (head === '>') return evalArgs[0] > evalArgs[1];
    if (head === '>=') return evalArgs[0] >= evalArgs[1];

    // Logic builtins
    if (head === 'not') return !evalArgs[0];
    if (head === 'and') return evalArgs.every(Boolean);
    if (head === 'or') return evalArgs.some(Boolean);

    // String & Conversion builtins
    if (head === 'str') return evalArgs.map(formatOutput).join('');
    if (head === 'str-concat') return evalArgs.join('');
    if (head === 'str-len' || head === 'string-length') return String(evalArgs[0] || '').length;
    if (head === 'str-contains?' || head === 'string-contains?') {
      let target = evalArgs[0];
      if (target && typeof target === 'object' && target._tag === 'some') target = target.value;
      return String(target || '').includes(String(evalArgs[1] || ''));
    }
    if (head === 'string-starts-with?') {
      let target = evalArgs[0];
      if (target && typeof target === 'object' && target._tag === 'some') target = target.value;
      return String(target || '').startsWith(String(evalArgs[1] || ''));
    }
    if (head === 'string-ends-with?') {
      let target = evalArgs[0];
      if (target && typeof target === 'object' && target._tag === 'some') target = target.value;
      return String(target || '').endsWith(String(evalArgs[1] || ''));
    }
    if (head === 'string-split') return String(evalArgs[0] || '').split(String(evalArgs[1] || ''));
    if (head === 'string-join') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : (Array.isArray(evalArgs[1]) ? evalArgs[1] : []);
      const sep = Array.isArray(evalArgs[0]) ? String(evalArgs[1] ?? '') : String(evalArgs[0] ?? '');
      return arr.map(formatOutput).join(sep);
    }
    if (head === 'string-trim') return String(evalArgs[0] || '').trim();
    if (head === 'string-empty?') return String(evalArgs[0] || '').length === 0;
    if (head === 'string-from-int64' || head === 'string-from-int' || head === 'int-to-string') return String(evalArgs[0] ?? '');
    if (head === 'string-from-float64' || head === 'string-from-float') return String(evalArgs[0] ?? '');
    if (head === 'string-to-int64') {
      const s = String(evalArgs[0] || '').trim();
      if (/^-?[0-9]+$/.test(s)) return { _tag: 'some', value: BigInt(s) };
      return { _tag: 'none', value: null };
    }
    if (head === 'string-to-float64') {
      const s = String(evalArgs[0] || '').trim();
      const num = Number(s);
      if (!isNaN(num) && s.length > 0) return { _tag: 'some', value: num };
      return { _tag: 'none', value: null };
    }
    if (head === 'int64-to-float64' || head === 'float-from-int64' || head === 'float') {
      return Number(evalArgs[0]);
    }
    if (head === 'float64-to-int64') {
      const n = Number(evalArgs[0]);
      if (isNaN(n) || !isFinite(n)) return { _tag: 'none', value: null };
      return { _tag: 'some', value: BigInt(Math.trunc(n)) };
    }
    if (head === 'int32-to-int64') {
      return BigInt(evalArgs[0]);
    }
    if (head === 'int64-to-int32') {
      const n = BigInt(evalArgs[0]);
      if (n >= -2147483648n && n <= 2147483647n) return { _tag: 'some', value: Number(n) };
      return { _tag: 'none', value: null };
    }
    if (head === 'string-chars') {
      return Array.from(String(evalArgs[0] || ''));
    }
    if (head === 'string-lower' || head === 'string-to-lower') {
      return String(evalArgs[0] || '').toLowerCase();
    }
    if (head === 'string-upper') {
      return String(evalArgs[0] || '').toUpperCase();
    }
    if (head === 'string-replace') {
      return String(evalArgs[0] || '').replaceAll(String(evalArgs[1]), String(evalArgs[2]));
    }
    if (head === 'string-reverse') {
      return Array.from(String(evalArgs[0] || '')).reverse().join('');
    }
    if (head === 'string-index-of') {
      const idx = String(evalArgs[0] || '').indexOf(String(evalArgs[1] || ''));
      return idx >= 0 ? { _tag: 'some', value: BigInt(idx) } : { _tag: 'none', value: null };
    }
    if (head === 'string-slice') {
      const s = String(evalArgs[0] || '');
      const start = Number(evalArgs[1]);
      const end = Number(evalArgs[2]);
      if (start < 0 || end < start || start > s.length) return { _tag: 'none', value: null };
      return { _tag: 'some', value: s.slice(start, end) };
    }

    // Numbers & conversions
    if (head === 'div-i64') {
      const a = evalArgs[0];
      const b = evalArgs[1];
      if ((typeof b === 'bigint' && b === 0n) || (typeof b === 'number' && b === 0)) {
        console.error("ERR_DIVISION_BY_ZERO: division by zero");
        process.exit(1);
      }
      return (typeof a === 'bigint' && typeof b === 'bigint') ? a / b : BigInt(Math.trunc(Number(a) / Number(b)));
    }
    if (head === 'div-f64') {
      const a = evalArgs[0];
      const b = evalArgs[1];
      if ((typeof b === 'bigint' && b === 0n) || (typeof b === 'number' && b === 0)) {
        console.error("ERR_DIVISION_BY_ZERO: division by zero");
        process.exit(1);
      }
      return Number(a) / Number(b);
    }
    if (head === 'sqrt') {
      return Math.sqrt(Number(evalArgs[0]));
    }
    if (head === 'as-i64') {
      const a = evalArgs[0];
      if (typeof a === 'bigint') return a;
      if (typeof a === 'number') return BigInt(Math.trunc(a));
      if (typeof a === 'string') return BigInt(a);
      return 0n;
    }
    if (head === 'as-f64') {
      return Number(evalArgs[0]);
    }
    if (head === 'float64-from-int64' || head === 'int64-to-float64' || head === 'float-from-int64' || head === 'float') {
      return Number(evalArgs[0]);
    }
    if (head === 'int64-from-float' || head === 'float64-to-int64') {
      return BigInt(Math.trunc(Number(evalArgs[0])));
    }
    if (head === 'int-to-str' || head === 'string-from-int64' || head === 'string-from-int' || head === 'int-to-string') {
      return String(evalArgs[0] ?? '');
    }

    // Strings
    if (head === 'string-to-lowercase' || head === 'string-lower' || head === 'string-to-lower') {
      return String(evalArgs[0] || '').toLowerCase();
    }
    if (head === 'string-trim-left') {
      return String(evalArgs[0] || '').trimStart();
    }
    if (head === 'string-count-char') {
      const s = String(evalArgs[0] || '');
      const ch = String(evalArgs[1] || '');
      let c = 0;
      for (let k = 0; k < s.length; k++) if (s[k] === ch) c++;
      return BigInt(c);
    }
    if (head === 'string-repeat') {
      const s = String(evalArgs[0] || '');
      const n = Math.max(0, Number(evalArgs[1]));
      return s.repeat(n);
    }
    if (head === 'string-append') {
      return evalArgs.map(formatOutput).join('');
    }
    if (head === 'join') {
      const sep = String(evalArgs[0] ?? '');
      const arr = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      return arr.map(formatOutput).join(sep);
    }

    // Pairs and Tuples
    if (head === 'fst' || head === 'pair-first' || head === 'tuple-first' || head === 'tuple2-first') {
      let t = evalArgs[0];
      if (t && typeof t === 'object' && t._tag === 'some') t = t.value;
      return Array.isArray(t) ? t[0] : (t?.first ?? null);
    }
    if (head === 'snd' || head === 'pair-second' || head === 'tuple-second' || head === 'tuple2-second') {
      let t = evalArgs[0];
      if (t && typeof t === 'object' && t._tag === 'some') t = t.value;
      return Array.isArray(t) ? t[1] : (t?.second ?? null);
    }
    if (head === 'second' || head === 'list-second') {
      let t = evalArgs[0];
      if (t && typeof t === 'object' && t._tag === 'some') t = t.value;
      return Array.isArray(t) ? (t.length > 1 ? t[1] : null) : (t?.second ?? null);
    }

    // Lists
    if (head === 'list-first' || head === 'head') {
      let arr = evalArgs[0];
      if (arr && arr._tag === 'some' && Array.isArray(arr.value)) arr = arr.value;
      if (!Array.isArray(arr)) arr = [];
      return arr.length > 0 ? arr[0] : null;
    }
    if (head === 'list-last') {
      let arr = evalArgs[0];
      if (arr && arr._tag === 'some' && Array.isArray(arr.value)) arr = arr.value;
      if (!Array.isArray(arr)) arr = [];
      if (arr.length > 0) return { _tag: 'some', value: arr[arr.length - 1] };
      return { _tag: 'none', value: null };
    }
    if (head === 'list-take') {
      let arr = evalArgs[0];
      if (arr && arr._tag === 'some' && Array.isArray(arr.value)) arr = arr.value;
      if (!Array.isArray(arr)) arr = [];
      const n = Math.max(0, Number(evalArgs[1]));
      return arr.slice(0, n);
    }
    if (head === 'range' || head === 'list-range') {
      const s = BigInt(evalArgs[0]);
      const e = BigInt(evalArgs[1]);
      const res = [];
      for (let v = s; v < e; v++) res.push(v);
      return res;
    }
    if (head === 'fold' || head === 'foldl' || head === 'list-fold' || head === 'fold-left') {
      const fn = evalArgs[0];
      let acc = evalArgs[1];
      const arr = Array.isArray(evalArgs[2]) ? evalArgs[2] : [];
      for (const it of arr) {
        acc = (fn && fn._type === 'closure') ? invokeClosure(fn, [acc, it]) : (typeof fn === 'function' ? fn(acc, it) : acc);
      }
      return acc;
    }
    if (head === 'map' || head === 'list-map') {
      const fn = evalArgs[0];
      const arr = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      return arr.map(it => (fn && fn._type === 'closure') ? invokeClosure(fn, [it]) : (typeof fn === 'function' ? fn(it) : it));
    }
    if (head === 'filter' || head === 'list-filter') {
      const fn = evalArgs[0];
      const arr = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      return arr.filter(it => {
        const res = (fn && fn._type === 'closure') ? invokeClosure(fn, [it]) : (typeof fn === 'function' ? fn(it) : it);
        return res !== false && res !== null && res !== undefined;
      });
    }
    if (head === 'list-any?' || head === 'any?' || head === 'any') {
      if (evalArgs.length === 1) {
        const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
        for (const it of arr) {
          if (it !== false && it !== null && it !== undefined && it !== 0 && it !== 0n) return true;
        }
        return false;
      }
      const fn = evalArgs[0];
      const arr = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      for (const it of arr) {
        const res = (fn && fn._type === 'closure') ? invokeClosure(fn, [it]) : (typeof fn === 'function' ? fn(it) : it);
        if (res !== false && res !== null && res !== undefined && res !== 0 && res !== 0n) return true;
      }
      return false;
    }
    if (head === 'all' || head === 'all?' || head === 'list-all?') {
      if (evalArgs.length === 1) {
        const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
        for (const it of arr) {
          if (it === false || it === null || it === undefined || it === 0 || it === 0n) return false;
        }
        return true;
      }
      const fn = evalArgs[0];
      const arr = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      for (const it of arr) {
        const res = (fn && fn._type === 'closure') ? invokeClosure(fn, [it]) : (typeof fn === 'function' ? fn(it) : it);
        if (res === false || res === null || res === undefined || res === 0 || res === 0n) return false;
      }
      return true;
    }
    if (head === 'list-reverse' || head === 'reverse') {
      const arr = Array.isArray(evalArgs[0]) ? [...evalArgs[0]] : [];
      return arr.reverse();
    }
    if (head === 'list-length' || head === 'length' || head === 'list-len' || head === 'len') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return BigInt(arr.length);
    }
    if (head === 'count') {
      const arg = evalArgs[0];
      if (Array.isArray(arg)) return BigInt(arg.length);
      if (typeof arg === 'string') return BigInt(arg.length);
      if (arg && typeof arg === 'object') return BigInt(Object.keys(arg).length);
      return 0n;
    }
    if (head === 'append' || head === 'append-item') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return [...arr, evalArgs[1]];
    }
    if (head === 'enumerate' || head === 'list-indexed') {
      const arr = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      return arr.map((item, idx) => {
        const t = [BigInt(idx), item];
        t.first = BigInt(idx);
        t.second = item;
        return t;
      });
    }

    // Option and Map
    if (head === 'nil?') {
      return evalArgs[0] === null || evalArgs[0] === undefined;
    }
    if (head === 'map-merge') {
      const m1 = evalArgs[0] && typeof evalArgs[0] === 'object' ? evalArgs[0] : {};
      const m2 = evalArgs[1] && typeof evalArgs[1] === 'object' ? evalArgs[1] : {};
      return { ...m1, ...m2 };
    }
    if (head === 'get') {
      const target = evalArgs[0];
      const key = evalArgs[1];
      if (Array.isArray(target)) {
        const idx = Number(key);
        return idx >= 0 && idx < target.length ? target[idx] : null;
      }
      if (target && typeof target === 'object') {
        const k = (key && typeof key === 'object' && key.value !== undefined) ? key.value : String(key);
        return target[k] ?? null;
      }
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
  if (val && typeof val === 'object' && val._type === 'closure') {
    return val.name ? `(closure ${val.name})` : '(closure)';
  }
  if (val && typeof val === 'object' && val._tag === 'io-error') {
    return val.kind !== undefined ? `(:io-error :kind "${val.kind}")` : '(:io-error)';
  }
  if (val && typeof val === 'object' && val._tag === 'ok') {
    return val.value !== undefined && val.value !== null ? `(:ok ${formatOutput(val.value)})` : '(:ok)';
  }
  if (val && typeof val === 'object' && val._tag === 'err') {
    return val.value !== undefined && val.value !== null ? `(:err ${formatOutput(val.value)})` : '(:err)';
  }
  if (val && typeof val === 'object' && val._tag === 'some') {
    return val.value !== undefined && val.value !== null ? `(:some ${formatOutput(val.value)})` : '(:some)';
  }
  if (val && typeof val === 'object' && val._tag === 'none') {
    return '(:none)';
  }
  if (Array.isArray(val)) {
    return '(' + val.map(formatOutput).join(' ') + ')';
  }
  if (val && typeof val === 'object') {
    const keys = Object.keys(val);
    if (keys.length === 0) return '(:m)';
    const pairs = keys.map(k => `:${k} ${formatOutput(val[k])}`).join(' ');
    return `(${pairs})`;
  }
  return String(val);
}

// ---------------------------------------------------------------------------
// CLI Execution Dispatch: File Mode or Expression Mode
// ---------------------------------------------------------------------------

function checkExprTypes(node, fnName, filePath) {
  if (!node || node.type !== 'list') return;
  const op = node.items[0]?.value;
  if (['+', '-', '*', '/'].includes(op)) {
    for (let i = 1; i < node.items.length; i++) {
      const arg = node.items[i];
      if (arg?.type === 'str') {
        console.error(`Type Error: Cannot apply numeric operator '${op}' to string literal in function '${fnName}' in ${filePath}`);
        process.exit(1);
      }
    }
  }
  for (const child of node.items) {
    checkExprTypes(child, fnName, filePath);
  }
}

const moduleCache = new Map();
let checkerClosure = null;
let inCheckerBootstrap = false;

function getCheckerClosure() {
  if (checkerClosure) return checkerClosure;
  if (inCheckerBootstrap) return null;
  inCheckerBootstrap = true;
  try {
    const wsRoot = process.cwd();
    const scriptDir = path.dirname((process.argv[1] || process.argv[0] || '.'));
    const candidates = [
      path.join(wsRoot, 'asl', 'packages', 'asl-checker', 'src', 'check.asl'),
      path.resolve(scriptDir, '..', 'packages', 'asl-checker', 'src', 'check.asl'),
      path.resolve(scriptDir, '..', '..', 'packages', 'asl-checker', 'src', 'check.asl')
    ];
    let checkPath = null;
    for (const c of candidates) {
      if (fs.existsSync(c)) {
        checkPath = c;
        break;
      }
    }
    if (!checkPath) {
      inCheckerBootstrap = false;
      return null;
    }
    const env = new Map();
    const code = fs.readFileSync(checkPath, 'utf8');
    const forms = parseAllSExprs(code);
    loadModuleImports(forms, checkPath, env);
    for (const f of forms) {
      evalNode(f, env);
    }
    const fn = env.get('check-source');
    if (fn && fn._type === 'closure') {
      checkerClosure = fn;
    }
  } catch (e) {
    checkerClosure = null;
    throw e;
  } finally {
    inCheckerBootstrap = false;
  }
  return checkerClosure;
}

function runStaticTypeCheck(forms, code, filePath) {
  const checkSource = getCheckerClosure();
  if (checkSource) {
    try {
      const diags = invokeClosure(checkSource, [code, {}, filePath]);
      if (Array.isArray(diags) && diags.length > 0) {
        for (const diag of diags) {
          const line = diag?.line ?? 1;
          const col = diag?.col ?? 1;
          const msg = diag?.message ?? 'type mismatch';
          const codeName = diag?.code ?? 'type';
          const srcPath = diag?.path ?? filePath;
          console.error(`[ASL_TYPE_ERROR] Type Error: ${msg} at ${srcPath}:${line}:${col} [code: ${codeName}]`);
        }
        process.exit(1);
      }
      return;
    } catch (e) {
      console.error(`[ASL_TYPE_ERROR] Type Error: ${e.message} at ${filePath}:1:1 [code: internal-error]`);
      process.exit(1);
    }
  }

  for (const form of forms) {
    if (!form || form.type !== 'list' || form.items.length < 3) continue;
    const head = form.items[0]?.value;
    if (head === 'df' || head === 'defun') {
      const fnName = form.items[1]?.value || 'anonymous';
      let retType = null;
      let bodyIdx = 3;
      for (let i = 2; i < form.items.length; i++) {
        const item = form.items[i];
        if (item?.value === '->') {
          if (i + 1 < form.items.length) {
            retType = form.items[i + 1]?.value;
            bodyIdx = i + 2;
          }
          break;
        }
      }
      // Skip docstring :d "..." if present at start of body
      let bodyExprs = form.items.slice(bodyIdx);
      if (bodyExprs.length >= 2 && bodyExprs[0]?.type === 'kw' && bodyExprs[0]?.value === 'd') {
        bodyExprs = bodyExprs.slice(2);
      }
      for (const expr of bodyExprs) {
        checkExprTypes(expr, fnName, filePath);
      }
      if (retType && bodyExprs.length > 0) {
        const lastExpr = bodyExprs[bodyExprs.length - 1];
        if (lastExpr) {
          if (lastExpr.type === 'str') {
            if (['Int64', 'I64', 'Int', 'Float64', 'F64', 'Bool'].includes(retType)) {
              console.error(`[ASL_TYPE_ERROR] Type Error: Function '${fnName}' declared return type '${retType}', but returns String in ${filePath}`);
              process.exit(1);
            }
          } else if (lastExpr.type === 'int' || lastExpr.type === 'float') {
            if (['String', 'Str', 'Bool'].includes(retType)) {
              console.error(`[ASL_TYPE_ERROR] Type Error: Function '${fnName}' declared return type '${retType}', but returns Number in ${filePath}`);
              process.exit(1);
            }
          } else if (lastExpr.type === 'bool') {
            if (['String', 'Str', 'Int64', 'I64', 'Int', 'Float64', 'F64'].includes(retType)) {
              console.error(`[ASL_TYPE_ERROR] Type Error: Function '${fnName}' declared return type '${retType}', but returns Bool in ${filePath}`);
              process.exit(1);
            }
          }
        }
      }
    }
  }
}

if (cleanArgs[0] === '--check' && cleanArgs[1]) {
  const filePath = cleanArgs[1];
  if (!fs.existsSync(filePath)) {
    console.error(`Error: file not found: ${filePath}`);
    process.exit(1);
  }
  const code = fs.readFileSync(filePath, 'utf8');
  try {
    const forms = parseAllSExprs(code);
    runStaticTypeCheck(forms, code, filePath);
    process.exit(0);
  } catch (e) {
    console.error(`[ASL_TYPE_ERROR] Type Error: ${e.message} at ${filePath}:1:1 [code: parse-error]`);
    process.exit(1);
  }
}

let moduleNameIndex = null;

function getWorkspaceAslFiles(wsRoot) {
  const seen = new Set();
  const fileList = [];
  const d81Dir = path.resolve(wsRoot, 'tests/acceptance/d81').replace(/\\/g, '/');

  function isAcceptanceD81(p) {
    const norm = p.replace(/\\/g, '/');
    return norm === d81Dir || norm.startsWith(d81Dir + '/');
  }

  function isD81Ancestor(p) {
    const norm = p.replace(/\\/g, '/');
    return d81Dir === norm || d81Dir.startsWith(norm + '/');
  }

  if (typeof fs !== 'undefined' && typeof fs.readdirSync === 'function') {
    function scanDir(dir) {
      let entries;
      try {
        entries = fs.readdirSync(dir, { withFileTypes: true });
      } catch (e) {
        throw e;
      }
      if (!Array.isArray(entries)) return;
      for (const entry of entries) {
        const name = typeof entry === 'string' ? entry : (entry ? entry.name : null);
        if (typeof name !== 'string' || !name) continue;
        if (name.startsWith('.') || name === 'node_modules') continue;
        const isDir = typeof entry?.isDirectory === 'function' ? entry.isDirectory() : false;
        const isF = typeof entry?.isFile === 'function' ? entry.isFile() : (!isDir && name.endsWith('.asl'));
        const full = path.join(dir, name);
        const normFull = full.replace(/\\/g, '/');

        if (isDir) {
          if (name === 'corpus' || name === 'asl-src') continue;
          if (name === 'tests' || name === 'test') {
            if (!isD81Ancestor(full) && !isAcceptanceD81(full)) {
              continue;
            }
          }
          if (normFull.includes('/tests/') && !isD81Ancestor(full) && !isAcceptanceD81(full)) {
            continue;
          }
          scanDir(full);
        } else if (isF && name.endsWith('.asl')) {
          if (name.endsWith('_test.asl') || name.endsWith('-test.asl') || name.startsWith('test_')) {
            continue;
          }
          if (!seen.has(full)) {
            seen.add(full);
            fileList.push(full);
          }
        }
      }
    }
    scanDir(wsRoot);
  }
  if (typeof __EMBEDDED_ASL_FILES__ !== 'undefined' && Array.isArray(__EMBEDDED_ASL_FILES__)) {
    for (const f of __EMBEDDED_ASL_FILES__) {
      const full = path.resolve(wsRoot, f);
      const name = path.basename(full);
      if (name.endsWith('_test.asl') || name.endsWith('-test.asl') || name.startsWith('test_')) continue;
      const norm = full.replace(/\\/g, '/');
      if (norm.includes('/corpus/') || norm.includes('/asl-src/')) continue;
      if (norm.includes('/tests/') && !isAcceptanceD81(norm)) continue;
      if (!seen.has(full)) {
        seen.add(full);
        fileList.push(full);
      }
    }
  }
  return fileList;
}

function buildModuleNameIndex(startDir) {
  if (moduleNameIndex !== null) return moduleNameIndex;
  moduleNameIndex = new Map();

  let wsRoot = null;
  if (typeof globalThis !== 'undefined' && globalThis.__ASL_WORKSPACE_ROOT__) {
    wsRoot = path.resolve(globalThis.__ASL_WORKSPACE_ROOT__);
  } else if (typeof process !== 'undefined' && process.env && process.env.ASL_WORKSPACE_ROOT) {
    wsRoot = path.resolve(process.env.ASL_WORKSPACE_ROOT);
  }

  if (!wsRoot) {
    let curr = path.resolve(startDir || (typeof process !== 'undefined' && process.cwd ? process.cwd() : '.'));
    const home = typeof process !== 'undefined' && process.env ? process.env.HOME : null;
    let topmostRoot = null;
    while (curr && curr !== path.dirname(curr)) {
      let isMatch = false;
      if (fs.existsSync(path.join(curr, '.gitmodules')) ||
          fs.existsSync(path.join(curr, '.asl.config.asn'))) {
        isMatch = true;
      } else if ((!home || curr !== home) &&
                 (fs.existsSync(path.join(curr, '.asl')) && fs.existsSync(path.join(curr, '.asl', 'mem')))) {
        isMatch = true;
      }
      if (isMatch) {
        topmostRoot = curr;
      }
      curr = path.dirname(curr);
    }
    wsRoot = topmostRoot || path.resolve(startDir || (typeof process !== 'undefined' && process.cwd ? process.cwd() : '.'));
  }

  const files = getWorkspaceAslFiles(wsRoot);
  for (const full of files) {
    try {
      if (!fs.existsSync(full)) continue;
      const code = fs.readFileSync(full, 'utf8');
      if (!code) continue;
      const match = code.slice(0, 4096).match(/\(\s*module\s+([^\s()]+)/);
      if (match) {
        const modName = match[1];
        const normFull = full.replace(/\\/g, '/');
        if (modName === 'asl-sh/process') {
          if (normFull.endsWith('asl/packages/asl-sh/src/process.asl') || !moduleNameIndex.has(modName)) {
            moduleNameIndex.set(modName, full);
          }
        } else if (modName === 'bench/histogram') {
          if (normFull.endsWith('asl/bench/algo/histogram.asl') || !moduleNameIndex.has(modName)) {
            moduleNameIndex.set(modName, full);
          }
        } else if (!moduleNameIndex.has(modName)) {
          moduleNameIndex.set(modName, full);
        }
      }
    } catch (e) { throw e; }
  }

  return moduleNameIndex;
}

function resolveModulePath(currentFile, modName) {
  // Priority 1: Relative imports
  if (modName.startsWith('./') || modName.startsWith('../')) {
    const p = path.resolve(path.dirname(currentFile), modName.endsWith('.asl') ? modName : modName + '.asl');
    return fs.existsSync(p) ? p : null;
  }

  const cleanMod = modName.replace(/\.asl$/, '');
  const variants = [
    cleanMod,
    cleanMod.replace(/-/g, '_'),
    cleanMod.replace(/_/g, '-'),
    modName
  ];

  // Priority 2: Direct local candidate checks in the importing file's directory and sibling src/
  const dir = path.dirname(currentFile);
  for (const v of variants) {
    const candidates = [
      path.join(dir, v + '.asl'),
      path.join(dir, '..', 'src', v + '.asl'),
      path.join(dir, 'src', v + '.asl'),
      path.join(dir, v)
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) return path.resolve(c);
    }
  }

  const index = buildModuleNameIndex(path.dirname(currentFile));

  // Priority 3: Exact match in index for variants
  for (const v of variants) {
    if (index.has(v)) {
      const entry = index.get(v);
      const target = Array.isArray(entry) ? entry[0] : entry;
      if (target && fs.existsSync(target)) return path.resolve(target);
    }
  }

  // Priority 4: Short-name matching from index.entries()
  const matches = [];
  for (const [declName, entry] of index.entries()) {
    const parts = declName.split('/');
    const shortName = parts[parts.length - 1];
    if (variants.includes(shortName)) {
      const target = Array.isArray(entry) ? entry[0] : entry;
      if (target && fs.existsSync(target)) {
        matches.push(path.resolve(target));
      }
    }
  }

  if (matches.length > 0) {
    const curResolved = path.resolve(currentFile);
    let curDir = path.dirname(curResolved);
    let testDir = curDir;
    while (testDir && testDir !== path.dirname(testDir)) {
      for (const m of matches) {
        if (m.startsWith(testDir + path.sep) || m.startsWith(testDir + '/')) {
          return m;
        }
      }
      testDir = path.dirname(testDir);
    }
    return matches[0];
  }

  return null;
}

function loadModuleImports(forms, filePath, env, loading = new Set()) {
  if (loading.has(filePath)) return;
  loading.add(filePath);
  const seenAliases = new Set();
  for (const form of forms) {
    if (!form || form.type !== 'list') continue;
    const head = form.items[0]?.value;
    if (head === 'module') {
      for (let j = 1; j < form.items.length; j++) {
        if (form.items[j]?.type === 'kw' && form.items[j].value === 'i') {
          const importsList = form.items[j + 1];
          if (importsList && (importsList.type === 'list' || importsList.type === 'vec')) {
            for (const imp of importsList.items) {
              if (imp && (imp.type === 'list' || imp.type === 'vec') && imp.items.length >= 1) {
                const modName = imp.items[0]?.value;
                const impLine = imp.line || (imp.items && imp.items[0]?.line) || 1;
                let alias = null;
                for (let k = 1; k < imp.items.length; k++) {
                  if (imp.items[k]?.type === 'kw' && imp.items[k].value === 'a') {
                    alias = imp.items[k + 1]?.value;
                  }
                }
                if (!modName) {
                  throw new Error(`ERR_UNRESOLVED_IMPORT: invalid import in '${filePath}:${impLine}'`);
                }
                if (alias) {
                  if (seenAliases.has(alias)) {
                    throw new Error(`ERR_ALIAS_COLLISION: duplicate import alias '${alias}' in '${filePath}:${impLine}'`);
                  }
                  seenAliases.add(alias);
                }
                const resolved = resolveModulePath(filePath, modName);
                if (!resolved || !fs.existsSync(resolved)) {
                  const candidate = modName.startsWith('.')
                    ? path.resolve(path.dirname(filePath), modName.endsWith('.asl') ? modName : modName + '.asl')
                    : path.resolve(path.dirname(filePath), modName + '.asl');
                  throw new Error(`ERR_UNRESOLVED_IMPORT: module '${modName}' imported in '${filePath}:${impLine}' could not be resolved (searched candidate: '${candidate}')`);
                }
                let importedEnv;
                if (moduleCache.has(resolved)) {
                  importedEnv = moduleCache.get(resolved);
                } else {
                  const importedCode = fs.readFileSync(resolved, 'utf8');
                  const importedForms = parseAllSExprs(importedCode);
                  importedEnv = new Map();
                  importedEnv.set('none', { _tag: 'none', value: null });
                  importedEnv.set('nil', null);
                  loadModuleImports(importedForms, resolved, importedEnv, new Set(loading));
                  for (const f of importedForms) {
                    evalNode(f, importedEnv);
                  }
                  moduleCache.set(resolved, importedEnv);
                }
                for (const [k, v] of importedEnv.entries()) {
                  if (alias) {
                    env.set(alias + '/' + k, v);
                    if (k.startsWith(alias + '-') || k.startsWith(alias + '/')) {
                      env.set(k, v);
                    }
                  } else {
                    env.set(k, v);
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

if (cleanArgs.length >= 1 && fs.existsSync(cleanArgs[0]) && !cleanArgs[0].startsWith('(')) {
  const filePath = cleanArgs[0];
  const code = fs.readFileSync(filePath, 'utf8');
  try {
    const forms = parseAllSExprs(code);
    const rootEnv = new Map();
    rootEnv.set('none', { _tag: 'none', value: null });
    rootEnv.set('nil', null);
    loadModuleImports(forms, filePath, rootEnv);

    for (const [fnName, fnVal] of rootEnv.entries()) {
      if ((fnName.startsWith('test-') || fnName.startsWith('Test')) && fnVal && fnVal._type === 'closure' && !fnVal._isStructConstructor && !fnVal._isEnumVariant && fnVal.params.length === 0) {
        plannedTestCount++;
      }
    }
    if (rootEnv.has('run-tests') || rootEnv.has('RunTests') || rootEnv.has('run-wire-tests')) plannedTestCount = Math.max(plannedTestCount, 1);

    let lastResult = null;
    for (const form of forms) {
      lastResult = evalNode(form, rootEnv);
    }
    if (rootEnv.has('run-tests')) {
      const runTestsFn = rootEnv.get('run-tests');
      if (runTestsFn && runTestsFn._type === 'closure') {
        startedTestCount++;
        const res = invokeClosure(runTestsFn, []);
        if (res !== true) {
          console.error(`ERR_TEST_RESULT_NOT_TRUE: test entry 'run-tests' returned ${formatOutput(res)} instead of true`);
          process.exit(1);
        }
        completedTestCount++;
        lastResult = res;
      }
    } else if (rootEnv.has('RunTests')) {
      const runTestsFn = rootEnv.get('RunTests');
      if (runTestsFn && runTestsFn._type === 'closure') {
        startedTestCount++;
        const res = invokeClosure(runTestsFn, []);
        if (res !== true) {
          console.error(`ERR_TEST_RESULT_NOT_TRUE: test entry 'RunTests' returned ${formatOutput(res)} instead of true`);
          process.exit(1);
        }
        completedTestCount++;
        lastResult = res;
      }
    } else if (rootEnv.has('run-wire-tests')) {
      const runWireFn = rootEnv.get('run-wire-tests');
      if (runWireFn && runWireFn._type === 'closure') {
        const res = invokeClosure(runWireFn, []);
        if (res !== true) {
          console.error(`ERR_TEST_RESULT_NOT_TRUE: test entry 'run-wire-tests' returned ${formatOutput(res)} instead of true`);
          process.exit(1);
        }
        lastResult = res;
      }
    } else if (rootEnv.has('main')) {
      const mainFn = rootEnv.get('main');
      if (mainFn && mainFn._type === 'closure') {
        const res = invokeClosure(mainFn, []);
        if (res !== true && res?._tag !== 'ok') {
          console.error(`ERR_TEST_RESULT_NOT_TRUE: test entry 'main' returned ${formatOutput(res)} instead of true`);
          process.exit(1);
        }
        lastResult = res;
      }
    } else {
      for (const [fnName, fnVal] of rootEnv.entries()) {
        if ((fnName.startsWith('test-') || fnName.startsWith('Test')) && fnVal && fnVal._type === 'closure' && !fnVal._isStructConstructor && !fnVal._isEnumVariant && fnVal.params.length === 0) {
          startedTestCount++;
          const res = invokeClosure(fnVal, []);
          if (res !== true) {
            console.error(`ERR_TEST_RESULT_NOT_TRUE: test entry '${fnName}' returned ${formatOutput(res)} instead of true`);
            process.exit(1);
          }
          completedTestCount++;
          lastResult = res;
        }
      }
    }
    const totalChecks = assertionCount + refutationCount;
    if (totalChecks > 0) {
      let parts = [];
      if (assertionCount > 0) parts.push(`${assertionCount} assertion(s)`);
      if (refutationCount > 0) parts.push(`${refutationCount} refutation(s)`);
      console.log(`✓ ${filePath}: ${parts.join(', ')} executed and recorded cleanly.`);
    } else if (lastResult !== null && lastResult !== undefined && !lastResult?._silent) {
      console.log(formatOutput(lastResult));
    }
    if (wantsMetrics) {
      const elapsedMs = (performance.now() - t0).toFixed(2);
      const memMb = (process.memoryUsage().rss / (1024 * 1024)).toFixed(2);
      console.log(`(:metrics :elapsed-ms ${elapsedMs} :rss-mb ${memMb} :planned-tests ${plannedTestCount} :started-tests ${startedTestCount} :completed-tests ${completedTestCount} :assertions ${assertionCount} :refutations ${refutationCount} :rejections ${rejectionCount})`);
    }
    process.exit(0);
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}

const expr = cleanArgs.join(' ').trim();
if (!expr) {
  process.exit(0);
}

// 1. Division by zero check (fast path)
if (/\(\s*\/\s+[-0-9.]+\s+0(\.0+)?\s*\)/.test(expr)) {
  console.error("ERR_DIVISION_BY_ZERO: division by zero");
  process.exit(1);
}

// 2. Unbound function / unknown builtin check (root head)
const headMatch = expr.match(/^\(\s*([^\s()]+)/);
if (headMatch) {
  const head = headMatch[1];
  if (!head.startsWith('.-') && !knownBuiltins.has(head)) {
    console.error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${head}'`);
    process.exit(1);
  }
}

try {
  const forms = parseAllSExprs(expr);
  const rootEnv = new Map();
  let lastResult = null;
  for (const form of forms) {
    lastResult = evalNode(form, rootEnv);
  }
  if (rootEnv.has('main') && lastResult && lastResult._type === 'closure' && lastResult.name === 'main') {
    const mainFn = rootEnv.get('main');
    lastResult = invokeClosure(mainFn, []);
  }
  if (lastResult !== null && lastResult !== undefined && !lastResult?._silent) {
    console.log(formatOutput(lastResult));
  }
  if (wantsMetrics) {
    const elapsedMs = (performance.now() - t0).toFixed(2);
    const memMb = (process.memoryUsage().rss / (1024 * 1024)).toFixed(2);
    console.log(`(:metrics :elapsed-ms ${elapsedMs} :rss-mb ${memMb})`);
  }
  process.exit(0);
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
