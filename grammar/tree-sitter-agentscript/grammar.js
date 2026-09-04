/**
 * AgentScript v0.2 — tree-sitter grammar.
 * Normative source: AGENT_SPEC_CORE.md
 *
 * This is the tooling grammar (axis 2): it yields a typed AST, error recovery,
 * editor highlighting, and structural search via tree-sitter queries, which
 * ast-grep also consumes. The Lark grammar in ../agentscript.lark covers the
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

// BEGIN GENERATED PROJECTION — prelude/generate.py from prelude/prelude.json.
// Head and option-keyword spellings. Each is significant only in the
// position its rule admits, so a record key written `:x` stays a keyword.
const HEAD = {
  defun: ['defun', 'def', 'df'],
  defschema: ['defschema', 'schema', 'dfs'],
  defenum: ['defenum', 'enum', 'dfe'],
  match: ['match', 'mt'],
};

const OPT = {
  ':doc': [':doc', ':d'],
  ':export': [':export', ':x'],
  ':import': [':import', ':i'],
  ':as': [':as', ':a'],
  ':field': [':field', ':f'],
  ':case': [':case', ':c'],
};
// END GENERATED PROJECTION

module.exports = grammar({
  name: 'agentscript',

  word: $ => $.ident,

  extras: $ => [/\s/],

  rules: {
    source_file: $ => repeat($._toplevel),

    _toplevel: $ => choice($.module_decl, $.defschema, $.defun, $.defenum, $.note, $.tag_node),

    // A bare string at top level is a note bound to nothing — the only comment
    // mechanism. Only the body position accepted one, so a file banner had
    // nowhere to live (PCP l-a250). `;` line comments are retired.
    note: $ => $.string,

    // ---------- module header (v0.2) ----------

    module_decl: $ => seq(
      '(', 'module', field('path', $.mod_path), repeat($.module_opt), ')'
    ),
    module_opt: $ => choice(
      seq(choice(...OPT[':doc']), field('doc', $.string)),
      seq(choice(...OPT[':export']), '[', repeat(field('export', choice($.ident, $.type_name))), ']'),
      seq(choice(...OPT[':import']), '[', repeat($.import_spec), ']'),
      $.tag_node,
    ),
    import_spec: $ => seq(
      '(', field('path', $.mod_path), choice(...OPT[':as']), field('alias', $.ident), ')'
    ),

    // Type variables are bound explicitly, so a name is a type variable because
    // it was declared one, never because of how it is spelled.
    type_params: $ => seq('{', repeat(field('param', $.type_name)), '}'),

    // ---------- declarations ----------

    // §4.1's `:json-case` pins the wire spelling of every field at the
    // declaration. It is normative and neither grammar accepted it, so the form
    // the specification defines could not be written.
    defschema: $ => seq(
      '(', choice(...HEAD.defschema),
      optional(field('type_params', $.type_params)),
      field('name', $.type_name), repeat($.schema_opt), repeat1($.field), ')'
    ),
    schema_opt: $ => choice(
      seq(':json-case', field('json_case', $.ident)),
      $.tag_node,
    ),

    defenum: $ => seq(
      '(', choice(...HEAD.defenum),
      optional(field('type_params', $.type_params)),
      field('name', $.type_name), repeat($.tag_node), repeat1($.enum_case), ')'
    ),
    enum_case: $ => seq(
      '(', choice(...OPT[':case']),
      field('name', $.ident),
      '[', repeat($.param), ']',
      field('doc', $.string),
      repeat($.tag_node), ')'
    ),

    field: $ => seq(
      '(', choice(...OPT[':field']),
      field('name', $.ident),
      field('type', $._type),
      field('doc', $.string),
      repeat($.field_opt), ')'
    ),

    field_opt: $ => choice(
      seq(':default', field('default', $._literal)),
      seq(':json', field('json_name', $.string)),
      $.tag_node,
    ),

    // `!` marks a declaration that touches the world; mandatory on the
    // signature because the signature is the module surface.
    defun: $ => seq(
      '(', choice(...HEAD.defun),
      optional(field('effect', '!')),
      optional(field('type_params', $.type_params)),
      field('name', $.ident),
      field('params', $.params),
      '->',
      field('return_type', $._type),
      optional(seq(choice(...OPT[':doc']), field('doc', $.string))),
      repeat($.tag_node),
      repeat1(field('body', $._expr)), ')'
    ),

    params: $ => seq('[', repeat($.param), ']'),
    param: $ => seq(
      '(', field('name', $.ident), field('type', $._type), ')'
    ),

    // ---------- types ----------

    _type: $ => choice($.type_name, $.qualified_type, $.type_app),
    type_app: $ => seq('(', choice($.type_name, $.qualified_type), repeat1($._type), ')'),

    // ---------- expressions ----------

    _expr: $ => choice(
      $._literal,
      $.ident,
      $.qualified,
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
      '(', choice(...HEAD.match), field('subject', $._expr), repeat1($.match_arm), ')'
    ),
    match_arm: $ => seq(
      '(', field('pattern', $._pattern), repeat1(field('body', $._expr)), ')'
    ),

    try_form: $ => seq('(', 'try', field('body', $._expr), ')'),

    // Lambda annotations are optional where the callee's signature fixes them;
    // `params` stays strict because a named declaration is the module surface.
    fn_form: $ => seq(
      '(', 'fn',
      optional(field('effect', '!')),
      field('params', $.fn_params),
      optional(seq('->', field('return_type', $._type))),
      repeat($.tag_node),
      repeat1(field('body', $._expr)), ')'
    ),

    fn_params: $ => seq('[', repeat($.fn_param), ']'),
    fn_param: $ => choice(
      field('name', $.ident),
      seq('(', field('name', $.ident), field('type', $._type), ')')
    ),

    // ---------- metadata tags (decoupled meta) ----------

    tag_node: $ => seq(
      '(', choice(':tag', '@tag'), repeat($.tag_field), ')'
    ),
    tag_field: $ => choice(
      $.keyword,
      $._literal,
      $.ident,
      $.qualified,
      $.tag_vector,
    ),
    tag_vector: $ => seq('[', repeat(choice($.keyword, $._literal, $.ident, $.qualified)), ']'),

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
    ctor: $ => seq('(', field('type', choice($.type_name, $.qualified_type)),
                   repeat($.ctor_arg), ')'),
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
      $.enum_pattern,
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
    // A defenum case used as a pattern; its arity is a semantic check.
    enum_pattern: $ => seq(
      '(', field('case', choice($.ident, $.qualified)), repeat($._pattern), ')'
    ),

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
    // alias/member. Bare "/" stays the division operator: it is separator-
    // delimited, a qualified name never is.
    qualified: $ => /[a-z][a-z0-9]*(-[a-z0-9]+)*\/[a-z][a-z0-9]*(-[a-z0-9]+)*[?!]?/,
    // The uppercase tail keeps an imported type disjoint from qualified,
    // mod_path and type_name, so it is one token wherever it can appear.
    qualified_type: $ => /[a-z][a-z0-9]*(-[a-z0-9]+)*\/[A-Z][A-Za-z0-9]*/,
    mod_path: $ => /[a-z][a-z0-9]*(-[a-z0-9]+)*(\/[a-z][a-z0-9]*(-[a-z0-9]+)*)*/,
    ident: $ => /[a-z][a-z0-9]*(-[a-z0-9]+)*[?!]?/,
    keyword: $ => /:[a-z][a-z0-9]*(-[a-z0-9]+)*/,
    field_ref: $ => /\.-[a-z][a-z0-9]*(-[a-z0-9]+)*/,
    wildcard: $ => '_',
  },
});
