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

const knownBuiltins = new Set([
  '+', '-', '*', '/', 'mod',
  '=', '!=', '<', '>', '<=', '>=',
  'not', 'and', 'or',
  'if', 'assert', 'let', 'do', 'cond', 'mt',
  'df', 'fn', 'module',
  'println', 'eprintln', 'print', 'str',
  'str-concat', 'str-len', 'str-contains?',
  'string-from-int64', 'string-from-float64',
  'string-contains?', 'string-starts-with?', 'string-ends-with?',
  'string-split', 'string-join', 'string-trim', 'string-empty?',
  'list', 'list-cons', 'list-head', 'list-tail', 'list-empty?', 'list-length', 'list-drop',
  'list-sort', 'list-sort-by', 'list-sum', 'list-min', 'list-max', 'list-index-of',
  'cons', 'first', 'rest',
  'map-empty', 'map-set', 'map-get', 'map-size', 'map-keys', 'map-values', 'map-pairs', 'map-from-pairs', 'map-remove',
  'ok', 'err', 'some', 'none', 'is-ok?', 'is-err?', 'is-some?', 'is-none?',
  'option-map', 'result-or', 'option-to-result',
  'abs', 'neg', 'min', 'max', 'checked-div', 'checked-mod',
  'option-or', 'result-map', 'result-map-err', 'result-to-option',
  'already-exists', 'interrupted', 'invalid-path', 'not-found', 'other', 'permission-denied',
  'list-append', 'list-contains?', 'list-get', 'list-slice', 'list-reverse', 'filter', 'fold', 'map', 'range', 'zip',
  'map-has?', 'pair',
  'string-to-int64', 'string-to-float64', 'int64-to-float64', 'float64-to-int64', 'int32-to-int64', 'int64-to-int32',
  'string-chars', 'string-lower', 'string-upper', 'string-replace', 'string-reverse', 'string-index-of', 'string-slice'
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
  for (const expr of closure.body) {
    lastVal = evalNode(expr, childEnv);
  }
  return lastVal;
}

function parseAllSExprs(input) {
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
      const val = parseVal();
      if (val !== null) arr.push(val);
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
      const val = parseVal();
      if (val !== null) items.push(val);
      skipWhitespace();
    }
    if (i < input.length && input[i] === ")") i++;
    return { type: "list", items };
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
    if (node.value === 'null' || node.value === 'nil' || node.value === '_') return null;
    console.error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${node.value}'`);
    process.exit(1);
  }
  if (node.type === 'vec') {
    return node.items.map(it => evalNode(it, env));
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
      const target = evalNode(node.items[1], env);
      if (target && typeof target === 'object') {
        return target[prop];
      }
      return null;
    }

    // Check user-defined function / binding in env
    if (env.has(head)) {
      const callee = env.get(head);
      if (callee && callee._type === 'closure') {
        const evalArgs = node.items.slice(1).map(it => evalNode(it, env));
        return invokeClosure(callee, evalArgs);
      }
    }

    if (!knownBuiltins.has(head)) {
      console.error(`ERR_UNBOUND_SYMBOL: unknown builtin or function '${head}'`);
      process.exit(1);
    }

    // Special forms: module
    if (head === 'module') {
      return null;
    }

    // Special forms: df
    if (head === 'df') {
      let nameIdx = 1;
      if (node.items[nameIdx]?.type === 'sym' && node.items[nameIdx].value === '!') {
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
      const paramsNode = node.items[1];
      let bodyIdx = 2;
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
        console.error("ERR_ASSERTION_FAILED: assertion evaluated to false");
        process.exit(1);
      }
      return true;
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

    // Normal evaluation of arguments
    const evalArgs = node.items.slice(1).map(it => evalNode(it, env));

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
    if (head === 'ok') return { _tag: 'ok', value: evalArgs[0] };
    if (head === 'err') return { _tag: 'err', value: evalArgs[0] };
    if (head === 'is-ok?') return evalArgs[0]?._tag === 'ok';
    if (head === 'is-err?') return evalArgs[0]?._tag === 'err';
    if (head === 'some') return { _tag: 'some', value: evalArgs[0] };
    if (head === 'none') return { _tag: 'none', value: null };
    if (head === 'is-some?') return evalArgs[0]?._tag === 'some';
    if (head === 'is-none?') return evalArgs[0]?._tag === 'none';
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

    // List and Map builtins
    if (head === 'list-append') {
      const a = Array.isArray(evalArgs[0]) ? evalArgs[0] : [];
      const b = Array.isArray(evalArgs[1]) ? evalArgs[1] : [];
      return [...a, ...b];
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
    if (head === 'fold') {
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
      return arr.indexOf(evalArgs[1]);
    }
    if (head === 'map-has?') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? evalArgs[0] : {};
      return Object.prototype.hasOwnProperty.call(obj, String(evalArgs[1]));
    }
    if (head === 'pair') {
      return [evalArgs[0], evalArgs[1]];
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
      return Object.keys(obj).length;
    }
    if (head === 'map-remove') {
      const obj = evalArgs[0] && typeof evalArgs[0] === 'object' ? { ...evalArgs[0] } : {};
      delete obj[String(evalArgs[1])];
      return obj;
    }

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

    // String & Conversion builtins
    if (head === 'str') return evalArgs.map(formatOutput).join('');
    if (head === 'str-concat') return evalArgs.join('');
    if (head === 'str-len' || head === 'string-length') return String(evalArgs[0] || '').length;
    if (head === 'str-contains?' || head === 'string-contains?') return String(evalArgs[0] || '').includes(String(evalArgs[1] || ''));
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
    if (head === 'int64-to-float64') {
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
    if (head === 'string-lower') {
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

if (rawArgs.length >= 1 && fs.existsSync(rawArgs[0]) && !rawArgs[0].startsWith('(')) {
  const filePath = rawArgs[0];
  const code = fs.readFileSync(filePath, 'utf8');
  try {
    const forms = parseAllSExprs(code);
    const rootEnv = new Map();
    let lastResult = null;
    for (const form of forms) {
      lastResult = evalNode(form, rootEnv);
    }
    if (rootEnv.has('main')) {
      const mainFn = rootEnv.get('main');
      if (mainFn && mainFn._type === 'closure') {
        lastResult = invokeClosure(mainFn, []);
      }
    }
    if (lastResult !== null && lastResult !== undefined && !lastResult?._silent) {
      console.log(formatOutput(lastResult));
    }
    process.exit(0);
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}

const expr = rawArgs.join(' ').trim();
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
  if (!knownBuiltins.has(head)) {
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
  process.exit(0);
} catch (e) {
  console.error(e.message);
  process.exit(1);
}

