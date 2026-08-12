/**
 * AgentS-Core v0.1 — tree-sitter grammar.
 * Normative source: AGENT_SPEC_CORE.md
 *
 * This is the tooling grammar (axis 2): it yields a typed AST, error recovery,
 * editor highlighting, and structural search via tree-sitter queries, which
 * ast-grep also consumes. The Lark grammar in ../agents.lark covers the
 * constrained-decoding path; grammar/validate.py checks both accept and reject
 * the same corpus.
 *
 * Divergence note vs. Lark: tree-sitter's keyword extraction makes form heads
 * genuinely reserved, whereas Lark/Earley can re-lex them as identifiers from
 * context. Core never binds a variable named `let` or `match`, so the two agree
 * on every well-formed program — but `ok`, `err`, `some`, `none`, `pair` and
 * `list` are BOTH pattern heads and ordinary builtins (§6.6, §6.5), so they get
 * explicit expression rules below rather than relying on that.
 */

module.exports = grammar({
  name: 'agents',

  word: $ => $.ident,

  extras: $ => [/\s/, $.comment],

  rules: {
    source_file: $ => repeat($._toplevel),

    _toplevel: $ => choice($.defschema, $.defun),

    // ---------- declarations ----------

    defschema: $ => seq(
      '(', 'defschema', field('name', $.type_name), repeat1($.field), ')'
    ),

    field: $ => seq(
      '(', ':field',
      field('name', $.ident),
      field('type', $._type),
      field('doc', $.string),
      repeat($.field_opt), ')'
    ),

    field_opt: $ => choice(
      seq(':default', field('default', $._literal)),
      seq(':json', field('json_name', $.string)),
    ),

    defun: $ => seq(
      '(', 'defun',
      field('name', $.ident),
      field('params', $.params),
      '->',
      field('return_type', $._type),
      repeat1(field('body', $._expr)), ')'
    ),

    params: $ => seq('[', repeat($.param), ']'),
    param: $ => seq(
      '(', field('name', $.ident), field('type', $._type), ')'
    ),

    // ---------- types ----------

    _type: $ => choice($.type_name, $.type_app),
    type_app: $ => seq('(', $.type_name, repeat1($._type), ')'),

    // ---------- expressions ----------

    _expr: $ => choice(
      $._literal,
      $.ident,
      $.operator,
      $.let_form,
      $.if_form,
      $.cond_form,
      $.match_form,
      $.try_form,
      $.fn_form,
      $.constructor_call,
      $.ctor,
      $.field_access,
      $.call,
    ),

    let_form: $ => seq(
      '(', 'let', '[', repeat($.binding), ']', repeat1(field('body', $._expr)), ')'
    ),
    binding: $ => seq(
      '(', field('name', $.ident), field('value', $._expr), ')'
    ),

    if_form: $ => seq(
      '(', 'if',
      field('condition', $._expr),
      field('consequence', $._expr),
      field('alternative', $._expr), ')'
    ),

    cond_form: $ => seq('(', 'cond', repeat1($.cond_clause), $.else_clause, ')'),
    cond_clause: $ => seq(
      '(', field('condition', $._expr), repeat1(field('body', $._expr)), ')'
    ),
    else_clause: $ => seq('(', ':else', repeat1(field('body', $._expr)), ')'),

    match_form: $ => seq(
      '(', 'match', field('subject', $._expr), repeat1($.match_arm), ')'
    ),
    match_arm: $ => seq(
      '(', field('pattern', $._pattern), repeat1(field('body', $._expr)), ')'
    ),

    try_form: $ => seq('(', 'try', field('body', $._expr), ')'),

    fn_form: $ => seq(
      '(', 'fn',
      field('params', $.params),
      '->',
      field('return_type', $._type),
      repeat1(field('body', $._expr)), ')'
    ),

    // §6.5/§6.6 builtins whose heads double as pattern heads.
    constructor_call: $ => choice(
      seq('(', 'ok', $._expr, ')'),
      seq('(', 'err', $._expr, ')'),
      seq('(', 'some', $._expr, ')'),
      seq('(', 'none', ')'),
      seq('(', 'pair', $._expr, $._expr, ')'),
      seq('(', 'list', repeat($._expr), ')'),
    ),

    // A PascalCase head is record construction (§4.1).
    ctor: $ => seq('(', field('type', $.type_name), repeat($.ctor_arg), ')'),
    ctor_arg: $ => seq(field('key', $.keyword), field('value', $._expr)),

    field_access: $ => seq(
      '(', field('field', $.field_ref), field('target', $._expr), ')'
    ),

    call: $ => seq(
      '(', field('callee', $._expr), repeat(field('argument', $._expr)), ')'
    ),

    // ---------- patterns ----------

    _pattern: $ => choice(
      $.ok_pattern,
      $.err_pattern,
      $.some_pattern,
      $.none_pattern,
      $.list_pattern,
      $.cons_pattern,
      $.pair_pattern,
      $._literal,
      $.ident,
      $.wildcard,
    ),

    ok_pattern: $ => seq('(', 'ok', $._pattern, ')'),
    err_pattern: $ => seq('(', 'err', $._pattern, ')'),
    some_pattern: $ => seq('(', 'some', $._pattern, ')'),
    none_pattern: $ => seq('(', 'none', ')'),
    list_pattern: $ => seq('(', 'list', ')'),
    cons_pattern: $ => seq('(', 'cons', $._pattern, $._pattern, ')'),
    pair_pattern: $ => seq('(', 'pair', $._pattern, $._pattern, ')'),

    // ---------- terminals ----------

    _literal: $ => choice($.float, $.int, $.string, $.bool, $.unit),

    // float before int so "1.5" is not lexed as int "1" followed by ".5"
    float: $ => token(prec(2, /-?[0-9]+\.[0-9]+/)),
    int: $ => token(prec(1, /-?[0-9]+/)),
    string: $ => /"([^"\\]|\\.)*"/,
    bool: $ => choice('true', 'false'),
    unit: $ => '()',

    operator: $ => choice('!=', '<=', '>=', '+', '*', '/', '=', '<', '>', '-'),

    type_name: $ => /[A-Z][A-Za-z0-9]*/,
    ident: $ => /[a-z][a-z0-9]*(-[a-z0-9]+)*[?!]?/,
    keyword: $ => /:[a-z][a-z0-9]*(-[a-z0-9]+)*/,
    field_ref: $ => /\.-[a-z][a-z0-9]*(-[a-z0-9]+)*/,
    wildcard: $ => '_',

    comment: $ => token(seq(';', /[^\n]*/)),
  },
});
