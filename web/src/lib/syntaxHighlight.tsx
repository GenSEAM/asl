import React from 'react';

// Token types for syntax highlighting
type TokenType =
  | 'head'         // df, dfs, dfe, mt, defun, module, let, if, fn, match
  | 'option'       // :d, :x, :export, :field, :case, :columns, etc.
  | 'type'         // Str, I64, F64, Bool, Option, Result, List, User
  | 'builtin'      // str, println, map, fold, filter, list-get, etc.
  | 'field'        // .-name, .-total, .-x
  | 'string'       // "..."
  | 'number'       // 123, 3.14
  | 'boolean'      // true, false
  | 'effect'       // !
  | 'comment'      // ; comment or # comment or // comment
  | 'punct'        // (, ), [, ], {, }, ->
  | 'keyword'      // for target languages (pub, struct, async, def, etc.)
  | 'plain';

interface Token {
  type: TokenType;
  text: string;
}

const ASL_HEADS = new Set([
  'module', 'defun', 'df', 'defschema', 'dfs', 'defenum', 'dfe',
  'match', 'mt', 'let', 'if', 'cond', 'fn', 'pair', 'list', 'vector', 'map', 'set'
]);

const ASL_TYPES = new Set([
  'Str', 'String', 'I64', 'Int64', 'I32', 'Int32', 'F64', 'Float64', 'F32',
  'Bool', 'Unit', 'List', 'Map', 'Set', 'Option', 'Result', 'Pair'
]);

const ASL_BUILTINS = new Set([
  'str', 'string-length', 'string-slice', 'string-contains?', 'string-starts-with?',
  'string-ends-with?', 'string-join', 'string-split', 'string-trim', 'string-upper', 'string-lower',
  'list-length', 'list-get', 'list-cons', 'list-append', 'list-tail', 'list-sum',
  'map-get', 'map-set', 'map-has?', 'map-remove', 'map-pairs', 'map-keys', 'map-values', 'map-empty',
  'fold', 'map', 'filter', 'range', 'println', 'print', 'eprintln',
  'file-read', 'file-write', 'try', 'ok', 'err', 'some', 'none',
  'make-select', 'and-expr', 'or-expr', 'not-expr', 'col', 'lit-str', 'lit-int', 'lit-bool', 'binary',
  'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'in-op',
  '+', '-', '*', '/', '=', '<', '>', '<=', '>=', 'and', 'or', 'not'
]);

// Tokenizer for AgentScript (ASL)
function tokenizeAsl(code: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  const len = code.length;

  while (i < len) {
    const ch = code[i];

    // Whitespace
    if (/\s/.test(ch)) {
      let start = i;
      while (i < len && /\s/.test(code[i])) i++;
      tokens.push({ type: 'plain', text: code.slice(start, i) });
      continue;
    }

    // Line comment
    if (ch === ';') {
      let start = i;
      while (i < len && code[i] !== '\n') i++;
      tokens.push({ type: 'comment', text: code.slice(start, i) });
      continue;
    }

    // String literal
    if (ch === '"') {
      let start = i;
      i++; // skip opening quote
      while (i < len && code[i] !== '"') {
        if (code[i] === '\\' && i + 1 < len) {
          i += 2; // skip escaped character
        } else {
          i++;
        }
      }
      if (i < len && code[i] === '"') i++; // include closing quote
      tokens.push({ type: 'string', text: code.slice(start, i) });
      continue;
    }

    // Punctuation & Delimiters
    if (ch === '(' || ch === ')' || ch === '[' || ch === ']' || ch === '{' || ch === '}') {
      tokens.push({ type: 'punct', text: ch });
      i++;
      continue;
    }

    // Effect sigil (!)
    if (ch === '!' && (i + 1 >= len || /[\s()\[\]]/.test(code[i + 1]))) {
      tokens.push({ type: 'effect', text: '!' });
      i++;
      continue;
    }

    // Arrow ->
    if (ch === '-' && i + 1 < len && code[i + 1] === '>') {
      tokens.push({ type: 'punct', text: '->' });
      i += 2;
      continue;
    }

    // Field accessor (.-name)
    if (ch === '.' && i + 1 < len && code[i + 1] === '-') {
      let start = i;
      i += 2;
      while (i < len && /[a-zA-Z0-9_-]/.test(code[i])) i++;
      tokens.push({ type: 'field', text: code.slice(start, i) });
      continue;
    }

    // Option / Keyword (:name)
    if (ch === ':') {
      let start = i;
      i++;
      while (i < len && /[a-zA-Z0-9_/-]/.test(code[i])) i++;
      tokens.push({ type: 'option', text: code.slice(start, i) });
      continue;
    }

    // Number literal
    if (/[0-9]/.test(ch) || (ch === '-' && i + 1 < len && /[0-9]/.test(code[i + 1]))) {
      let start = i;
      if (ch === '-') i++;
      while (i < len && /[0-9.]/.test(code[i])) i++;
      tokens.push({ type: 'number', text: code.slice(start, i) });
      continue;
    }

    // General symbol / identifier
    let start = i;
    while (i < len && !/[\s()\[\]{}"'`,;]/.test(code[i])) {
      i++;
    }
    const word = code.slice(start, i);

    if (ASL_HEADS.has(word)) {
      tokens.push({ type: 'head', text: word });
    } else if (word === 'true' || word === 'false') {
      tokens.push({ type: 'boolean', text: word });
    } else if (ASL_TYPES.has(word) || /^[A-Z][a-zA-Z0-9]*$/.test(word)) {
      tokens.push({ type: 'type', text: word });
    } else if (ASL_BUILTINS.has(word)) {
      tokens.push({ type: 'builtin', text: word });
    } else {
      tokens.push({ type: 'plain', text: word });
    }
  }

  return tokens;
}

// Fallback highlighter for other common languages (SQL, Python, Rust, TS, Bash, JSON)
function tokenizeGeneric(code: string, language: string): Token[] {
  const lang = language.toLowerCase();
  const tokens: Token[] = [];
  let i = 0;
  const len = code.length;

  const SQL_KEYWORDS = new Set([
    'select', 'from', 'where', 'join', 'inner', 'left', 'right', 'full', 'outer', 'on',
    'group', 'by', 'order', 'asc', 'desc', 'limit', 'offset', 'and', 'or', 'not', 'in',
    'like', 'is', 'null', 'create', 'table', 'insert', 'into', 'update', 'set', 'delete',
    'having', 'as', 'values', 'distinct', 'union', 'all'
  ]);

  const PROG_KEYWORDS = new Set([
    'def', 'return', 'class', 'import', 'export', 'from', 'fn', 'pub', 'struct', 'enum',
    'impl', 'let', 'mut', 'const', 'var', 'function', 'interface', 'type', 'async', 'await',
    'if', 'else', 'for', 'while', 'match', 'package', 'func'
  ]);

  while (i < len) {
    const ch = code[i];

    // Whitespace
    if (/\s/.test(ch)) {
      let start = i;
      while (i < len && /\s/.test(code[i])) i++;
      tokens.push({ type: 'plain', text: code.slice(start, i) });
      continue;
    }

    // Comments
    if (ch === '#' || (ch === '/' && i + 1 < len && code[i + 1] === '/') || (ch === '-' && i + 1 < len && code[i + 1] === '-')) {
      let start = i;
      while (i < len && code[i] !== '\n') i++;
      tokens.push({ type: 'comment', text: code.slice(start, i) });
      continue;
    }

    // Strings
    if (ch === '"' || ch === "'" || ch === '`') {
      const quote = ch;
      let start = i;
      i++;
      while (i < len && code[i] !== quote) {
        if (code[i] === '\\' && i + 1 < len) i += 2;
        else i++;
      }
      if (i < len && code[i] === quote) i++;
      tokens.push({ type: 'string', text: code.slice(start, i) });
      continue;
    }

    // Numbers
    if (/[0-9]/.test(ch)) {
      let start = i;
      while (i < len && /[0-9.a-fA-Fx_]/.test(code[i])) i++;
      tokens.push({ type: 'number', text: code.slice(start, i) });
      continue;
    }

    // Word
    if (/[a-zA-Z_$]/.test(ch)) {
      let start = i;
      while (i < len && /[a-zA-Z0-9_$-]/.test(code[i])) i++;
      const word = code.slice(start, i);
      const lower = word.toLowerCase();

      if (lang === 'sql' && SQL_KEYWORDS.has(lower)) {
        tokens.push({ type: 'keyword', text: word });
      } else if (PROG_KEYWORDS.has(lower)) {
        tokens.push({ type: 'keyword', text: word });
      } else if (lower === 'true' || lower === 'false' || lower === 'null') {
        tokens.push({ type: 'boolean', text: word });
      } else if (/^[A-Z][a-zA-Z0-9]*$/.test(word)) {
        tokens.push({ type: 'type', text: word });
      } else {
        tokens.push({ type: 'plain', text: word });
      }
      continue;
    }

    tokens.push({ type: 'punct', text: ch });
    i++;
  }

  return tokens;
}

// React Token Formatter with Tailwind Theme Classes
export const HighlightedCode: React.FC<{ code: string; language: string }> = ({ code, language }) => {
  const normLang = (language || 'text').trim().toLowerCase();
  const isAsl = normLang === 'agentscript' || normLang === 'asl' || normLang === 'agp' || normLang === 'asn';

  const tokens = isAsl ? tokenizeAsl(code) : tokenizeGeneric(code, normLang);

  return (
    <>
      {tokens.map((token, idx) => {
        switch (token.type) {
          case 'head':
            return (
              <span key={idx} className="text-purple-400 font-bold dark:text-purple-300">
                {token.text}
              </span>
            );
          case 'keyword':
            return (
              <span key={idx} className="text-purple-400 font-semibold dark:text-purple-300">
                {token.text}
              </span>
            );
          case 'option':
            return (
              <span key={idx} className="text-teal-400 font-medium dark:text-teal-300">
                {token.text}
              </span>
            );
          case 'type':
            return (
              <span key={idx} className="text-amber-300 font-semibold dark:text-amber-200">
                {token.text}
              </span>
            );
          case 'builtin':
            return (
              <span key={idx} className="text-sky-400 dark:text-sky-300">
                {token.text}
              </span>
            );
          case 'field':
            return (
              <span key={idx} className="text-emerald-400 font-medium dark:text-emerald-300">
                {token.text}
              </span>
            );
          case 'string':
            return (
              <span key={idx} className="text-emerald-300 dark:text-emerald-400">
                {token.text}
              </span>
            );
          case 'number':
            return (
              <span key={idx} className="text-orange-400 dark:text-orange-300">
                {token.text}
              </span>
            );
          case 'boolean':
            return (
              <span key={idx} className="text-orange-400 font-semibold dark:text-orange-300">
                {token.text}
              </span>
            );
          case 'effect':
            return (
              <span key={idx} className="text-rose-400 font-extrabold dark:text-rose-300">
                {token.text}
              </span>
            );
          case 'comment':
            return (
              <span key={idx} className="text-ink-3/80 italic dark:text-ink-3">
                {token.text}
              </span>
            );
          case 'punct':
            return (
              <span key={idx} className="text-ink-3/70 dark:text-ink-3">
                {token.text}
              </span>
            );
          case 'plain':
          default:
            return <span key={idx} className="text-ink dark:text-ink">{token.text}</span>;
        }
      })}
    </>
  );
};
