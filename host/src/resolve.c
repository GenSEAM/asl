/* Declarations: module header, fn schema enum definitions, global slots, diagnostics. */
#include "compile.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

Val *globals; int nglobals; static int capglobals;
EnumDef *enums; int nenums; static int capenums;

void diag(Diags *d, const char *file, Node *at, const char *code, const char *fmt, ...) {
  char buf[1024];
  int n = snprintf(buf, sizeof buf, "%s:%d:%d: %s ", file, at ? at->line : 0, at ? at->col + 1 : 0, code);
  va_list ap; va_start(ap, fmt);
  vsnprintf(buf + n, sizeof buf - (size_t)n, fmt, ap);
  va_end(ap);
  if (d->n == d->cap) { d->cap = d->cap ? d->cap * 2 : 16; d->msgs = realloc(d->msgs, sizeof(char *) * d->cap); if (!d->msgs) exit(70); }
  d->msgs[d->n++] = strdup(buf);
}

static int newGlobal(void) {
  if (nglobals == capglobals) { capglobals = capglobals ? capglobals * 2 : 256; globals = realloc(globals, sizeof(Val) * capglobals); if (!globals) exit(70); }
  globals[nglobals] = VUNIT;
  return nglobals++;
}

Def *moduleDef(Module *m, int name) {
  for (int i = 0; i < m->ndefs; i++) if (m->defs[i].name == name) return &m->defs[i];
  return NULL;
}

static Def *addDef(Module *m, Diags *d, Node *at, int name, int kind) {
  if (moduleDef(m, name)) { diag(d, m->path, at, "ERR_DUPLICATE_DEFINITION", "%s", symName(name)); return NULL; }
  if (m->ndefs == m->capdefs) { m->capdefs = m->capdefs ? m->capdefs * 2 : 32; m->defs = realloc(m->defs, sizeof(Def) * m->capdefs); if (!m->defs) exit(70); }
  Def *df = &m->defs[m->ndefs++];
  memset(df, 0, sizeof *df);
  df->name = name; df->kind = kind; df->group = at; df->gidx = kind == DEF_FN ? newGlobal() : -1; df->enumId = -1;
  return df;
}

static int isSym(Node *n, const char *s) { return n && n->kind == N_SYM && !strcmp(symName(n->sym), s); }
static int isTailrecTag(Node *n) {
  if (!n) return 0;
  if (n->kind == N_SYM && !strcmp(symName(n->sym), "tailrec")) return 1;
  if (n->kind == N_KW && !strcmp(symName(n->sym), "tailrec")) return 1;
  return 0;
}
static int symEndsColon(Node *n) { if (!n || n->kind != N_SYM) return 0; const char *s = symName(n->sym); size_t l = strlen(s); return l > 1 && s[l - 1] == ':'; }
static int stripColon(Node *n) { const char *s = symName(n->sym); return intern(s, strlen(s) - 1); }

int fnSignature(Node *g, int *nameAt, int *params, int maxParams, int *bodyAt) {
  int k = 1, n = 0;
  while (k < g->n && (isSym(g->kids[k], "!") || isTailrecTag(g->kids[k]))) k++;
  *nameAt = k;
  int j = k + 1;
  while (j < g->n) {
    Node *t = g->kids[j];
    if (isSym(t, "->")) { j += 2; break; }
    if (t->kind != N_SYM) break;
    if (params && n < maxParams) params[n] = symEndsColon(t) ? stripColon(t) : t->sym;
    n++;
    j += symEndsColon(t) ? 2 : 1;
  }
  *bodyAt = j < g->n ? j : g->n;
  return n;
}

int isFnHeader(Node *g) { return g->kind == N_GROUP && g->n >= 2 && isSym(g->kids[0], "fn"); }

static void header(Module *m, Diags *d, Node *h) {
  if (h->n >= 2 && h->kids[1]->kind == N_SYM) m->name = h->kids[1]->sym;
  for (int i = 2; i + 1 < h->n; i += 2) {
    Node *k = h->kids[i], *v = h->kids[i + 1];
    if (k->kind != N_KW) { i--; continue; }
    const char *key = symName(k->sym);
    if (!strcmp(key, "x") && (v->kind == N_VEC || v->kind == N_LIST)) {
      m->exports = malloc(sizeof(int) * (size_t)(v->n + 1)); m->nexports = 0;
      for (int j = 0; j < v->n; j++) if (v->kids[j]->kind == N_SYM) m->exports[m->nexports++] = v->kids[j]->sym;
    } else if (!strcmp(key, "i") && (v->kind == N_VEC || v->kind == N_LIST)) {
      m->imports = calloc((size_t)v->n + 1, sizeof(*m->imports)); m->nimports = 0;
      for (int j = 0; j < v->n; j++) {
        Node *s = v->kids[j];
        int path = -1, alias = -1;
        if (s->kind == N_SYM) path = s->sym;
        else if (s->kind == N_LIST && s->n >= 1 && s->kids[0]->kind == N_SYM) {
          path = s->kids[0]->sym;
          for (int q = 1; q + 1 < s->n; q++)
            if (s->kids[q]->kind == N_KW && (!strcmp(symName(s->kids[q]->sym), "a") || !strcmp(symName(s->kids[q]->sym), "as")) && s->kids[q + 1]->kind == N_SYM) alias = s->kids[q + 1]->sym;
        }
        if (path < 0) { diag(d, m->path, s, "ERR_BAD_IMPORT", "import entry is not a module path"); continue; }
        if (alias < 0) { const char *p = symName(path), *sl = strrchr(p, '/'); alias = sl ? intern(sl + 1, strlen(sl + 1)) : path; }
        m->imports[m->nimports].path = path; m->imports[m->nimports].alias = alias; m->imports[m->nimports].at = s;
        m->imports[m->nimports].m = NULL; m->nimports++;
      }
    }
  }
}

static void declareEnum(Module *m, Diags *d, Node *g, int start) {
  Node *nameN = g->kids[start];
  if (nameN->kind != N_SYM) { diag(d, m->path, nameN, "ERR_BAD_DEFINITION", "enum without a name"); return; }
  if (nenums == capenums) { capenums = capenums ? capenums * 2 : 32; enums = realloc(enums, sizeof(EnumDef) * capenums); if (!enums) exit(70); }
  EnumDef *e = &enums[nenums]; e->name = nameN->sym; e->nvariants = 0; e->variants = malloc(sizeof(int) * (size_t)(g->n + 1));
  int eid = nenums++;
  for (int i = start + 1; i < g->n; i++) {
    Node *v = g->kids[i]; int vname, arity = 0;
    if (v->kind == N_SYM) { if (isSym(v, "|")) continue; vname = v->sym; }
    else if (v->kind == N_LIST && v->n >= 1 && v->kids[0]->kind == N_SYM) {
      vname = v->kids[0]->sym; int colons = 0;
      for (int j = 1; j < v->n; j++) if (symEndsColon(v->kids[j])) colons++;
      arity = colons ? colons : v->n - 1;
    } else continue;
    Def *df = addDef(m, d, v, vname, DEF_CTOR);
    if (!df) continue;
    df->arity = arity; df->enumId = eid;
    e->variants[e->nvariants++] = vname;
  }
}

/* the field count of a constructor's parameter vector, [(name Type) ...] or the flat [name Type ...]; -1 if it is
   neither */
static int ctorFields(Node *ps) {
  if (ps->kind != N_VEC) return -1;
  int lists = 0;
  for (int j = 0; j < ps->n; j++) {
    Node *q = ps->kids[j];
    if (q->kind == N_LIST && q->n == 2 && q->kids[0]->kind == N_SYM) lists++;
    else if (q->kind != N_SYM) return -1;
  }
  if (lists == ps->n) return lists;
  if (lists || ps->n % 2) return -1;
  return ps->n / 2;
}

/* list form: (enum Name (:c variant [params] "doc") ...); anything else inside it is a definition error */
static void declareListEnum(Module *m, Diags *d, Node *l) {
  if (l->n < 2 || l->kids[1]->kind != N_SYM) { diag(d, m->path, l, "ERR_BAD_DEFINITION", "enum without a name"); return; }
  if (l->n < 3) { diag(d, m->path, l, "ERR_BAD_DEFINITION", "enum %s has no constructors", symName(l->kids[1]->sym)); return; }
  if (nenums == capenums) { capenums = capenums ? capenums * 2 : 32; enums = realloc(enums, sizeof(EnumDef) * capenums); if (!enums) exit(70); }
  EnumDef *e = &enums[nenums]; e->name = l->kids[1]->sym; e->nvariants = 0; e->variants = malloc(sizeof(int) * (size_t)(l->n + 1));
  if (!e->variants) exit(70);
  int eid = nenums++;
  for (int i = 2; i < l->n; i++) {
    Node *v = l->kids[i]; int arity;
    if (v->kind != N_LIST || v->n < 3 || v->n > 4 || v->kids[0]->kind != N_KW || strcmp(symName(v->kids[0]->sym), "c") ||
        v->kids[1]->kind != N_SYM || (v->n == 4 && v->kids[3]->kind != N_STR)) {
      diag(d, m->path, v, "ERR_BAD_DEFINITION", "enum variant is not (:c name [params] \"doc\")"); continue;
    }
    if ((arity = ctorFields(v->kids[2])) < 0) {
      diag(d, m->path, v->kids[2], "ERR_BAD_DEFINITION", "constructor %s: parameters are not [(name Type) ...] or [name Type ...]", symName(v->kids[1]->sym));
      continue;
    }
    Def *df = addDef(m, d, v, v->kids[1]->sym, DEF_CTOR);
    if (!df) continue;
    df->arity = arity; df->enumId = eid;
    e->variants[e->nvariants++] = v->kids[1]->sym;
  }
}

/* a field's :default keyword expression node, or NULL when the field declares none */
static Node *fieldDefaultNode(Node *f) {
  for (int ki = 2; ki + 1 < f->n; ki++) {
    if (f->kids[ki]->kind == N_KW && (!strcmp(symName(f->kids[ki]->sym), "default") || !strcmp(symName(f->kids[ki]->sym), ":default")))
      return f->kids[ki + 1];
  }
  return NULL;
}

/* list form: (schema Name (:f field Type "doc") ...) */
static void declareListSchema(Module *m, Diags *d, Node *l) {
  if (l->n < 2 || l->kids[1]->kind != N_SYM) { diag(d, m->path, l, "ERR_BAD_DEFINITION", "schema without a name"); return; }
  Def *df = addDef(m, d, l, l->kids[1]->sym, DEF_SCHEMA);
  if (!df) return;
  df->fields = malloc(sizeof(int) * (size_t)(l->n + 1)); df->nfields = 0;
  df->defaultGidx = malloc(sizeof(int) * (size_t)(l->n + 1));
  df->defaultExpr = malloc(sizeof(Node *) * (size_t)(l->n + 1));
  for (int i = 2; i < l->n; i++) {
    Node *f = l->kids[i];
    if (f->kind == N_LIST && f->n >= 2 && f->kids[0]->kind == N_KW && f->kids[1]->kind == N_SYM) {
      Node *defExpr = fieldDefaultNode(f);
      int fi = df->nfields++;
      df->fields[fi] = f->kids[1]->sym;
      df->defaultExpr[fi] = defExpr;
      df->defaultGidx[fi] = defExpr ? newGlobal() : -1;
    }
    else if (f->kind != N_STR && f->kind != N_KW) diag(d, m->path, f, "ERR_BAD_DEFINITION", "schema field is not (:f name Type)");
  }
}

static void addTop(Module *m, Node *x) {
  if (m->ntops == m->captops) { m->captops = m->captops ? m->captops * 2 : 8; m->tops = realloc(m->tops, sizeof(Node *) * m->captops); if (!m->tops) exit(70); }
  m->tops[m->ntops++] = x;
}

static void declareSchema(Module *m, Diags *d, Node *g, int start) {
  Node *nameN = g->kids[start];
  if (nameN->kind != N_SYM) { diag(d, m->path, nameN, "ERR_BAD_DEFINITION", "schema without a name"); return; }
  Def *df = addDef(m, d, g, nameN->sym, DEF_SCHEMA);
  if (!df) return;
  df->fields = malloc(sizeof(int) * 64); df->nfields = 0;
  df->defaultGidx = malloc(sizeof(int) * 64); df->defaultExpr = malloc(sizeof(Node *) * 64);
  /* field names are the name: tokens, at item level or inside one brace or list body; this
     shorthand has no :default syntax, so every slot stays -1/NULL */
  for (int i = start + 1; i < g->n; i++) {
    Node *k = g->kids[i];
    if (symEndsColon(k) && df->nfields < 64) { int fi = df->nfields++; df->fields[fi] = stripColon(k); df->defaultExpr[fi] = NULL; df->defaultGidx[fi] = -1; }
    else if (k->kind == N_MAP || k->kind == N_LIST)
      for (int j = 0; j < k->n; j++) if (symEndsColon(k->kids[j]) && df->nfields < 64) { int fi = df->nfields++; df->fields[fi] = stripColon(k->kids[j]); df->defaultExpr[fi] = NULL; df->defaultGidx[fi] = -1; }
  }
}

void declareModule(Module *m, Diags *d) {
  for (int i = 0; i < m->unit.n; i++) {
    Node *g = m->unit.items[i];
    if (g->n == 1 && g->kids[0]->kind == N_LIST && g->kids[0]->n >= 1 && isSym(g->kids[0]->kids[0], "module")) { header(m, d, g->kids[0]); continue; }
    if (isFnHeader(g)) {
      int k, body, arity = fnSignature(g, &k, NULL, 0, &body);
      if (k >= g->n || g->kids[k]->kind != N_SYM) { diag(d, m->path, g, "ERR_BAD_DEFINITION", "fn without a name"); continue; }
      Def *df = addDef(m, d, g, g->kids[k]->sym, DEF_FN);
      const char *nm = symName(g->kids[k]->sym); size_t nl = strlen(nm);
      if (df) {
        df->arity = arity; df->marked = nl > 1 && nm[nl - 1] == '!';
        for (int m_idx = 1; m_idx < k; m_idx++) {
          if (isTailrecTag(g->kids[m_idx])) df->tailrec = 1;
          if (isSym(g->kids[m_idx], "!")) df->marked = 1;
        }
      }
      continue;
    }
    if (g->n >= 2 && isSym(g->kids[0], "enum")) { declareEnum(m, d, g, 1); continue; }
    if (g->n >= 2 && isSym(g->kids[0], "schema")) { declareSchema(m, d, g, 1); continue; }
    /* every other item is an expression run after the whole graph compiles, a list-form schema or enum, or an
       error: nothing at top level is silently skipped */
    for (int k = 0; k < g->n; k++) {
      Node *x = g->kids[k];
      if (x->kind == N_SYM) { diag(d, m->path, x, "ERR_UNSUPPORTED_TOPLEVEL", "top-level item starting with %s", symName(x->sym)); break; }
      Node *h = x->kind == N_LIST && x->n ? x->kids[0] : NULL;
      if (h && isSym(h, "schema")) declareListSchema(m, d, x);
      else if (h && isSym(h, "enum")) declareListEnum(m, d, x);
      else if (h && h->kind == N_SYM && (isSym(h, "def") || isSym(h, "defn") || isSym(h, "defun") || isSym(h, "df") || isSym(h, "dfs") ||
                                          isSym(h, "defenum") || isSym(h, "defschema") || isSym(h, "fn") || isSym(h, "module")))
        diag(d, m->path, x, "ERR_UNSUPPORTED_TOPLEVEL", "list-form (%s ...) at top level", symName(h->sym));
      else addTop(m, x);
    }
  }
}

/* LS1: a prelude fn stands for a builtin and carries no !; it is effectful when its body names an effectful builtin
   or an effectful prelude fn (fixpoint). Every other fn needs ! once it names an effectful builtin, a fn with !, or an
   effectful prelude fn; the diagnostic points at the first such name. Only the actual prelude module is exempt. */
extern Module *preludeModule;
static int refEffect(EffRef *r) { return r->owner == preludeModule ? r->df->effect : r->df->marked; }
static int before(Node *a, Node *b) { return !b || a->line < b->line || (a->line == b->line && a->col < b->col); }

void effectCheckModules(Module **mods, int n, Diags *d) {
  Module *pm = preludeModule;
  if (pm) {
    for (int i = 0; i < pm->ndefs; i++) pm->defs[i].effect = pm->defs[i].kind == DEF_FN && (pm->defs[i].effAt || pm->defs[i].marked);
    for (int changed = 1; changed;) {
      changed = 0;
      for (int i = 0; i < pm->ndefs; i++) {
        Def *df = &pm->defs[i];
        if (df->kind != DEF_FN || df->effect) continue;
        for (int j = 0; j < df->nrefs; j++) if (refEffect(&df->refs[j])) { df->effect = 1; changed = 1; break; }
      }
    }
  }
  for (int k = 0; k < n; k++) {
    Module *m = mods[k];
    if (m == pm) continue;
    for (int i = 0; i < m->ndefs; i++) {
      Def *df = &m->defs[i];
      if (df->kind != DEF_FN || df->marked) continue;
      Node *at = df->effAt; const char *what = df->effWhat;
      for (int j = 0; j < df->nrefs; j++)
        if (refEffect(&df->refs[j]) && before(df->refs[j].at, at)) { at = df->refs[j].at; what = symName(df->refs[j].at->sym); }
      if (at) diag(d, m->path, at, "ERR_EFFECT_UNMARKED", "fn %s names effectful %s: mark it (fn ! %s ...) or rename it %s!", symName(df->name), what, symName(df->name), symName(df->name));
    }
  }
}
