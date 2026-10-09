/* Static types at annotated positions (plan SH unit TC1): fn parameters and returns, let bindings, call arguments
   against the callee's annotations and the fixed builtin signatures, literals, arithmetic (Int and Float never mix),
   Bool conditions, if, cond and mt arm agreement, schema fields and enum constructor fields. A type variable, an
   unresolved type name or a value of unknown origin is unknown and never checked, so every ERR_TYPE_MISMATCH names
   two known, different types. Runs after compilation in check, test, run and eval alike. */
#include "ops.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { K_UNK, K_INT, K_FLOAT, K_BOOL, K_STR, K_KW, K_UNIT, K_BYTES, K_FN, K_ANYREC, K_REC, K_ENUM, K_LIST, K_OPTION, K_RESULT } Kind;
/* K_REC: name is the schema, def and m its definition and owning module; K_ENUM: name is the enums[] index */
typedef struct Ty { Kind k; int name; const struct Ty *a, *b; Def *def; Module *m; } Ty;

static const Ty tyUnk = {K_UNK, 0, NULL, NULL, NULL, NULL}, tyInt = {K_INT, 0, NULL, NULL, NULL, NULL},
  tyFloat = {K_FLOAT, 0, NULL, NULL, NULL, NULL}, tyBool = {K_BOOL, 0, NULL, NULL, NULL, NULL},
  tyStr = {K_STR, 0, NULL, NULL, NULL, NULL}, tyKw = {K_KW, 0, NULL, NULL, NULL, NULL}, tyUnit = {K_UNIT, 0, NULL, NULL, NULL, NULL},
  tyBytes = {K_BYTES, 0, NULL, NULL, NULL, NULL}, tyFn = {K_FN, 0, NULL, NULL, NULL, NULL}, tyAnyRec = {K_ANYREC, 0, NULL, NULL, NULL, NULL};

#define CHUNK_TYS 256
typedef struct Chunk { struct Chunk *next; int n; Ty t[CHUNK_TYS]; } Chunk;
typedef struct { int name; const Ty *t; } Bind;
typedef struct {
  Module *m; Diags *d; Chunk *arena;
  Bind *env; int nenv, capenv;
  const char *ctx;     /* what the current expected type belongs to, for the message */
  int depth;
} Tc;

#define TC_MAX_NEST 1000
#define TC_MAX_PARAMS 256

static int S_SOME, S_NONE, S_OK, S_ERR;
static void initNames(void) {
  if (S_SOME) return;
  S_SOME = intern("some", 4); S_NONE = intern("none", 4); S_OK = intern("ok", 2); S_ERR = intern("err", 3);
}

static const Ty *mk(Tc *c, Kind k, const Ty *a, const Ty *b) {
  if (!c->arena || c->arena->n == CHUNK_TYS) {
    Chunk *ch = calloc(1, sizeof(Chunk));
    if (!ch) exit(70);
    ch->next = c->arena; c->arena = ch;
  }
  Ty *t = &c->arena->t[c->arena->n++];
  t->k = k; t->a = a ? a : &tyUnk; t->b = b ? b : &tyUnk;
  return t;
}
static const Ty *mkRec(Tc *c, Def *df, Module *owner) {
  Ty *t = (Ty *)mk(c, K_REC, NULL, NULL);
  t->name = df->name; t->def = df; t->m = owner;
  return t;
}
static const Ty *mkEnum(Tc *c, int enumId) {
  Ty *t = (Ty *)mk(c, K_ENUM, NULL, NULL);
  t->name = enumId;
  return t;
}

static int isName(Node *n, const char *s) { return n && n->kind == N_SYM && !strcmp(symName(n->sym), s); }
static int endsColon(Node *n) {
  if (!n || n->kind != N_SYM) return 0;
  const char *s = symName(n->sym); size_t l = strlen(s);
  return l > 1 && s[l - 1] == ':';
}
static int stripColon(Node *n) { const char *s = symName(n->sym); return intern(s, strlen(s) - 1); }

/* a schema or enum named sym in module m, else NULL */
static const Ty *declaredTypeIn(Tc *c, Module *m, int sym) {
  Def *df = moduleDef(m, sym);
  if (df && df->kind == DEF_SCHEMA) return mkRec(c, df, m);
  for (int i = 0; i < m->ndefs; i++)
    if (m->defs[i].kind == DEF_CTOR && m->defs[i].enumId >= 0 && enums[m->defs[i].enumId].name == sym) return mkEnum(c, m->defs[i].enumId);
  return NULL;
}
/* m's own schemas and enums, then the prelude module's, as an unqualified name resolves everywhere else */
extern Module *preludeModule;
static const Ty *declaredType(Tc *c, Module *m, int sym) {
  const Ty *d = declaredTypeIn(c, m, sym);
  if (d) return d;
  return preludeModule && m != preludeModule ? declaredTypeIn(c, preludeModule, sym) : NULL;
}

static const Ty *scalarType(const char *s) {
  static const struct { const char *n; const Ty *t; } names[] = {
    {"Int64", &tyInt}, {"I64", &tyInt}, {"Int", &tyInt}, {"Int32", &tyInt}, {"I32", &tyInt},
    {"Float64", &tyFloat}, {"F64", &tyFloat}, {"Float", &tyFloat}, {"Float32", &tyFloat}, {"F32", &tyFloat},
    {"Bool", &tyBool}, {"String", &tyStr}, {"Str", &tyStr}, {"Keyword", &tyKw}, {"Unit", &tyUnit}, {"Bytes", &tyBytes}};
  for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) if (!strcmp(s, names[i].n)) return names[i].t;
  return &tyUnk;
}

/* an annotation as written in module m; alias/Name resolves through m's imports */
static const Ty *parseType(Tc *c, Module *m, Node *t) {
  if (!t) return &tyUnk;
  if (t->kind == N_SYM) {
    const char *s = symName(t->sym), *sl = strchr(s, '/');
    if (sl && sl != s && sl[1]) {
      int alias = intern(s, (size_t)(sl - s));
      for (int i = 0; i < m->nimports; i++)
        if (m->imports[i].alias == alias && m->imports[i].m) {
          int member = intern(sl + 1, strlen(sl + 1));
          const Ty *d = declaredType(c, m->imports[i].m, member);
          if (d && !moduleExports(m->imports[i].m, sl + 1)) notExported(c->d, m->path, t, m->imports[i].m, member);
          return d ? d : &tyUnk;
        }
      return &tyUnk;
    }
    const Ty *d = declaredType(c, m, t->sym);
    return d ? d : scalarType(s);
  }
  if (t->kind == N_LIST && t->n >= 1 && t->kids[0]->kind == N_SYM) {
    Node *h = t->kids[0];
    if (isName(h, "List") && t->n == 2) return mk(c, K_LIST, parseType(c, m, t->kids[1]), NULL);
    if (isName(h, "Option") && t->n == 2) return mk(c, K_OPTION, parseType(c, m, t->kids[1]), NULL);
    if (isName(h, "Result") && t->n == 3) return mk(c, K_RESULT, parseType(c, m, t->kids[1]), parseType(c, m, t->kids[2]));
    if (isName(h, "fn") || isName(h, "Fn")) return &tyFn;
    /* a generic application of a declared record or enum (e.g. (Pair A B)): the params are untracked, so the
       head alone resolves the way a bare symbol would */
    return parseType(c, m, h);
  }
  return &tyUnk;
}

/* 1 unless both types are known and a value of found can never be a want */
static int compat(const Ty *want, const Ty *found) {
  if (want->k == K_UNK || found->k == K_UNK) return 1;
  if ((want->k == K_ANYREC && found->k == K_REC) || (want->k == K_REC && found->k == K_ANYREC)) return 1;
  if (want->k != found->k) return 0;
  switch (want->k) {
    case K_LIST: case K_OPTION: return compat(want->a, found->a);
    case K_RESULT: return compat(want->a, found->a) && compat(want->b, found->b);
    case K_REC: return want->name == found->name;
    case K_ENUM: return enums[want->name].name == enums[found->name].name;
    default: return 1;
  }
}

static const char *tyName(const Ty *t, char *buf, size_t n) {
  char x[256], y[256];
  switch (t->k) {
    case K_INT: snprintf(buf, n, "Int64"); break;
    case K_FLOAT: snprintf(buf, n, "Float64"); break;
    case K_BOOL: snprintf(buf, n, "Bool"); break;
    case K_STR: snprintf(buf, n, "String"); break;
    case K_KW: snprintf(buf, n, "Keyword"); break;
    case K_UNIT: snprintf(buf, n, "Unit"); break;
    case K_BYTES: snprintf(buf, n, "Bytes"); break;
    case K_FN: snprintf(buf, n, "fn"); break;
    case K_ANYREC: snprintf(buf, n, "record"); break;
    case K_REC: snprintf(buf, n, "%s", symName(t->name)); break;
    case K_ENUM: snprintf(buf, n, "%s", symName(enums[t->name].name)); break;
    case K_LIST: snprintf(buf, n, "(List %s)", tyName(t->a, x, sizeof x)); break;
    case K_OPTION: snprintf(buf, n, "(Option %s)", tyName(t->a, x, sizeof x)); break;
    case K_RESULT: snprintf(buf, n, "(Result %s %s)", tyName(t->a, x, sizeof x), tyName(t->b, y, sizeof y)); break;
    default: snprintf(buf, n, "_"); break;
  }
  return buf;
}

static void mismatch(Tc *c, Node *at, const char *what, const Ty *want, const Ty *found) {
  char w[256], f[256];
  diag(c->d, c->m->path, at, "ERR_TYPE_MISMATCH", "%s: expected %s, found %s", what, tyName(want, w, sizeof w), tyName(found, f, sizeof f));
}
/* the found type of a form that does not pass want on to subforms, checked against want */
static const Ty *leaf(Tc *c, Node *at, const Ty *want, const Ty *found) {
  if (!compat(want, found)) mismatch(c, at, c->ctx ? c->ctx : "value", want, found);
  return found;
}

static void bind(Tc *c, int name, const Ty *t) {
  if (c->nenv == c->capenv) {
    c->capenv = c->capenv ? c->capenv * 2 : 64;
    Bind *grown = realloc(c->env, sizeof(Bind) * (size_t)c->capenv);
    if (!grown) exit(70);
    c->env = grown;
  }
  c->env[c->nenv++] = (Bind){name, t};
}
static const Bind *local(Tc *c, int name) {
  for (int i = c->nenv - 1; i >= 0; i--) if (c->env[i].name == name) return &c->env[i];
  return NULL;
}

static int isTag(Node *n) {
  if (!n) return 0;
  if (n->kind == N_SYM && (!strcmp(symName(n->sym), "!") || !strcmp(symName(n->sym), "tailrec"))) return 1;
  if (n->kind == N_KW && !strcmp(symName(n->sym), "tailrec")) return 1;
  return 0;
}

/* fn [!] name p: T q ... -> R: the annotation node of each parameter (NULL when absent) and of the return */
typedef struct { int np; Node *types[TC_MAX_PARAMS]; Node *ret; } Sig;
static void signature(Node *g, Sig *s) {
  int k = 1;
  while (k < g->n && isTag(g->kids[k])) k++;
  s->np = 0; s->ret = NULL;
  for (int j = k + 1; j < g->n;) {
    Node *t = g->kids[j];
    if (isName(t, "->")) { if (j + 1 < g->n) s->ret = g->kids[j + 1]; break; }
    if (t->kind != N_SYM) break;
    int colon = endsColon(t);
    if (s->np < TC_MAX_PARAMS) s->types[s->np] = colon && j + 1 < g->n ? g->kids[j + 1] : NULL;
    s->np++;
    j += colon ? 2 : 1;
  }
}

/* the declared field types of an enum constructor, positional; NULL where none is written */
static int ctorFieldTypes(Def *df, Node **out, int max) {
  Node *v = df->group; int k = 0;
  if (!v || v->kind != N_LIST) return 0;
  if (v->n >= 3 && v->kids[0]->kind == N_KW) {
    Node *ps = v->kids[2];
    if (ps->kind != N_VEC) return 0;
    int lists = ps->n > 0 && ps->kids[0]->kind == N_LIST;
    if (lists) { for (int j = 0; j < ps->n && k < max; j++) out[k++] = ps->kids[j]->kind == N_LIST && ps->kids[j]->n == 2 ? ps->kids[j]->kids[1] : NULL; }
    else for (int j = 1; j < ps->n && k < max; j += 2) out[k++] = ps->kids[j];
    return k;
  }
  int colons = 0;
  for (int j = 1; j < v->n; j++) if (endsColon(v->kids[j])) colons++;
  for (int j = 1; j < v->n && k < max; j++) {
    if (!colons) out[k++] = v->kids[j];
    else if (endsColon(v->kids[j])) out[k++] = j + 1 < v->n ? v->kids[j + 1] : NULL;
  }
  return k;
}

/* the declared type of a schema field: (:f name Type "doc") in the list form, name: Type in the group form */
static Node *schemaFieldType(Def *df, int field) {
  Node *g = df->group;
  if (!g) return NULL;
  if (g->kind == N_LIST) {
    for (int i = 2; i < g->n; i++) {
      Node *f = g->kids[i];
      if (f->kind == N_LIST && f->n >= 3 && f->kids[0]->kind == N_KW && f->kids[1]->kind == N_SYM && f->kids[1]->sym == field && f->kids[2]->kind != N_STR) return f->kids[2];
    }
    return NULL;
  }
  for (int i = 2; i < g->n; i++) {
    Node *k = g->kids[i];
    if (endsColon(k) && stripColon(k) == field) return i + 1 < g->n ? g->kids[i + 1] : NULL;
    if (k->kind == N_MAP || k->kind == N_LIST)
      for (int j = 0; j < k->n; j++) if (endsColon(k->kids[j]) && stripColon(k->kids[j]) == field) return j + 1 < k->n ? k->kids[j + 1] : NULL;
  }
  return NULL;
}

/* fixed builtin signatures, from the argument checks and results in prelude.c: I Int64, F Float64, B Bool, S String,
   L (List _), N (List Int64), O (Option _), T (Option (List _)), P (Option String), G (Option Float64), J (Option Int64), Y Bytes, _ unknown; params NULL means variadic and unchecked */
static const struct { const char *name, *ret, *params; } builtinSigs[] = {
  {"list", "L", NULL}, {"listLength", "I", "L"}, {"listTail", "T", "L"}, {"listHead", "O", "L"}, {"listEmpty?", "B", "L"},
  {"cons", "L", "_L"}, {"listReverse", "L", "L"}, {"str", "S", NULL}, {"stringLength", "I", "S"},
  {"stringConcat", "S", "SS"}, {"stringSlice", "P", "SII"}, {"stringFromInt64", "S", "I"}, {"stringFromFloat64", "S", "F"},
  {"stringToFloat64", "G", "S"}, {"int64ToFloat64", "F", "I"}, {"float64ToInt64", "J", "F"}, {"floatNan", "F", ""},
  {"floatInf", "F", ""}, {"floatNegInf", "F", ""}, {"bytesLength", "I", "Y"}, {"stringStartsWith?", "B", "SS"},
  {"stringContains?", "B", "SS"}, {"range", "N", "II"}, {"nowNs", "I", ""}, {"monotonicNs", "I", ""}, {"sqrt", "F", "F"}, {"floor", "F", "F"}, {"ceil", "F", "F"}, {"round", "F", "F"}, {"dot", "F", "__"}, {"axpy", "_", "F__"}, {"gemm", "_", "III__"}};
/* Native-route signatures are compile-time knowledge only; no host Builtin or VM entry exists. */
static const struct { const char *name, *ret, *params; int effect; } nativeOnlySigs[] = {
  {"unixSocketPair", "H", "", 1}, {"sockSendFd", "Q", "II", 1}, {"sockRecvFd", "Q", "I", 1}
};
int nativeOnlyBuiltin(const char *name) {
  for (size_t i = 0; i < sizeof nativeOnlySigs / sizeof nativeOnlySigs[0]; i++)
    if (!strcmp(nativeOnlySigs[i].name, name)) return 1;
  return 0;
}
int nativeOnlyArity(const char *name) {
  for (size_t i = 0; i < sizeof nativeOnlySigs / sizeof nativeOnlySigs[0]; i++)
    if (!strcmp(nativeOnlySigs[i].name, name)) return (int)strlen(nativeOnlySigs[i].params);
  return -1;
}
int nativeOnlyEffect(const char *name) {
  for (size_t i = 0; i < sizeof nativeOnlySigs / sizeof nativeOnlySigs[0]; i++)
    if (!strcmp(nativeOnlySigs[i].name, name)) return nativeOnlySigs[i].effect;
  return 0;
}
static const Ty *codeType(Tc *c, char k) {
  switch (k) {
    case 'I': return &tyInt;
    case 'F': return &tyFloat;
    case 'B': return &tyBool;
    case 'S': return &tyStr;
    case 'Y': return &tyBytes;
    case 'L': return mk(c, K_LIST, NULL, NULL);
    case 'O': return mk(c, K_OPTION, NULL, NULL);
    case 'N': return mk(c, K_LIST, &tyInt, NULL);
    case 'T': return mk(c, K_OPTION, mk(c, K_LIST, NULL, NULL), NULL);
    case 'P': return mk(c, K_OPTION, &tyStr, NULL);
    case 'G': return mk(c, K_OPTION, &tyFloat, NULL); case 'J': return mk(c, K_OPTION, &tyInt, NULL);
    case 'H': {
      int pair = -1, name = intern("Pair", 4);
      for (int i = 0; i < nenums; i++) if (enums[i].name == name) { pair = i; break; }
      return mk(c, K_RESULT, pair >= 0 ? mkEnum(c, pair) : &tyUnk, &tyStr);
    }
    case 'Q': return mk(c, K_RESULT, &tyInt, &tyStr);
    default: return &tyUnk;
  }
}

static const Ty *tc(Tc *c, Node *n, const Ty *want, int used);

/* n checked against want, the mismatch named by what */
static const Ty *tcAs(Tc *c, Node *n, const Ty *want, const char *what) {
  const char *saved = c->ctx; c->ctx = what;
  const Ty *t = tc(c, n, want, 1);
  c->ctx = saved;
  return t;
}

static const Ty *seqT(Tc *c, Node **xs, int n, const Ty *want, int used) {
  if (n <= 0) return &tyUnk;
  for (int i = 0; i < n - 1; i++) tc(c, xs[i], &tyUnk, 0);
  return tc(c, xs[n - 1], want, used);
}

typedef struct { Node **xs; int n; Node *at; } Arm;
/* every arm yields the value: with a known want each arm is checked against it, otherwise known arm types must agree */
typedef struct { const Ty *first; int agree; } Join;
static void joinArm(Tc *c, Join *j, const Ty *t, Node *at, const Ty *want, const char *form) {
  if (want->k != K_UNK || t->k == K_UNK) return;
  if (!j->first) j->first = t;
  else if (j->agree && !compat(j->first, t)) {
    char what[64]; snprintf(what, sizeof what, "%s branches disagree", form);
    mismatch(c, at, what, j->first, t);
    j->agree = 0;
  }
}
static const Ty *joinResult(Join *j, const Ty *want) {
  if (want->k != K_UNK) return want;
  return j->agree && j->first ? j->first : &tyUnk;
}
static const Ty *armsT(Tc *c, Arm *arms, int na, const Ty *want, int used, const char *form) {
  Join j = {NULL, 1};
  for (int i = 0; i < na; i++)
    joinArm(c, &j, seqT(c, arms[i].xs, arms[i].n, want, used), arms[i].n > 0 ? arms[i].xs[arms[i].n - 1] : arms[i].at, want, form);
  return joinResult(&j, want);
}

static const Ty *symType(Tc *c, Node *n) {
  const char *s = symName(n->sym);
  if (!strcmp(s, "true") || !strcmp(s, "false")) return &tyBool;
  const Bind *b = local(c, n->sym);
  if (b) return b->t;
  Module *owner; Def *df = defLookup(c->m, n->sym, &owner);
  if (df && df->kind == DEF_FN) {
    /* a value naming a global fn carries its return type, so a call through a local bound to it (CHECKER-localCallReturnBool) can still be leaf()-checked in callT */
    Sig sig; signature(df->group, &sig);
    return mk(c, K_FN, parseType(c, owner, sig.ret), NULL);
  }
  if (df && df->kind == DEF_CTOR && df->arity == 0 && df->enumId >= 0) return mkEnum(c, df->enumId);
  if (!df && n->sym == S_NONE) return mk(c, K_OPTION, NULL, NULL);
  if (!df && (builtinLookup(s) || nativeOnlyBuiltin(s))) return &tyFn;
  return &tyUnk;
}

/* the type a constructor pattern or call builds: its enum, Option or Result */
static const Ty *ctorType(Tc *c, int sym, Def *df) {
  if (df && df->kind == DEF_CTOR) return df->enumId >= 0 ? mkEnum(c, df->enumId) : &tyUnk;
  if (sym == S_SOME || sym == S_NONE) return mk(c, K_OPTION, NULL, NULL);
  if (sym == S_OK || sym == S_ERR) return mk(c, K_RESULT, NULL, NULL);
  return &tyUnk;
}
static int isCtorName(Tc *c, int sym, Def **df, Module **owner) {
  *df = defLookup(c->m, sym, owner);
  if (*df && (*df)->kind == DEF_CTOR) return 1;
  if (*df) return 0;
  return sym == S_SOME || sym == S_NONE || sym == S_OK || sym == S_ERR;
}

/* A hidden bare constructor would otherwise look like a binder in the type pass. */
static Def *hiddenCtor(Tc *c, int sym, Module **owner) {
  if (defLookup(c->m, sym, owner) || strchr(symName(sym), '/')) return NULL;
  Def *visible = NULL, *hidden = NULL;
  Module *first = NULL, *hiddenOwner = NULL;
  for (int i = 0; i < c->m->nimports; i++) {
    Module *im = c->m->imports[i].m;
    Def *df;
    if (!im || im == first || !(df = moduleDef(im, sym)) || df->kind != DEF_CTOR) continue;
    if (defExported(im, df)) { visible = df; first = im; }
    else if (!hidden) { hidden = df; hiddenOwner = im; }
  }
  if (visible || !hidden) return NULL;
  *owner = hiddenOwner;
  return hidden;
}

static const Ty *letT(Tc *c, Node *n, const Ty *want, int used) {
  if (n->n < 2 || (n->kids[1]->kind != N_VEC && n->kids[1]->kind != N_LIST)) return &tyUnk;
  Node *bs = n->kids[1]; int saved = c->nenv;
  int pairs = bs->n > 0 && bs->kids[0]->kind == N_LIST;
  for (int i = 0; i < bs->n; i += pairs ? 1 : 2) {
    Node *name, *val, *ann = NULL;
    if (pairs) {
      Node *b = bs->kids[i];
      if (b->kind != N_LIST || b->n < 2) continue;
      name = b->kids[0]; val = b->kids[b->n - 1];
      if (b->n == 3) ann = b->kids[1];
    } else {
      if (i + 1 >= bs->n) break;
      name = bs->kids[i]; val = bs->kids[i + 1];
    }
    if (name->kind != N_SYM) { tc(c, val, &tyUnk, 1); continue; }
    if (ann) {
      const Ty *at = parseType(c, c->m, ann);
      char what[160]; snprintf(what, sizeof what, "let %.120s", symName(name->sym));
      tcAs(c, val, at, what);
      bind(c, name->sym, at);
    } else bind(c, name->sym, tc(c, val, &tyUnk, 1));
  }
  const Ty *t = seqT(c, n->kids + 2, n->n - 2, want, used);
  c->nenv = saved;
  return t;
}

static const Ty *lambdaT(Tc *c, Node *n, const Ty *want) {
  int saved = c->nenv, body = 2;
  if (n->n >= 2 && (n->kids[1]->kind == N_VEC || n->kids[1]->kind == N_LIST)) {
    Node *ps = n->kids[1];
    for (int i = 0; i < ps->n; i++) {
      Node *q = ps->kids[i];
      if (q->kind == N_SYM) bind(c, q->sym, &tyUnk);
      else if (q->kind == N_LIST && q->n >= 1 && q->kids[0]->kind == N_SYM) bind(c, q->kids[0]->sym, q->n == 2 ? parseType(c, c->m, q->kids[1]) : &tyUnk);
    }
  }
  const Ty *rt = &tyUnk;
  if (body < n->n && isName(n->kids[body], "->")) { if (body + 1 < n->n) rt = parseType(c, c->m, n->kids[body + 1]); body += 2; }
  const char *savedCtx = c->ctx; c->ctx = "return of fn";
  seqT(c, n->kids + body, body < n->n ? n->n - body : 0, rt, 1);
  c->ctx = savedCtx;
  c->nenv = saved;
  /* a lambda value carries its own declared (or unknown) return type, same reason as the symType DEF_FN case above */
  return leaf(c, n, want, mk(c, K_FN, rt, NULL));
}

static int isLiteralPat(Node *p) {
  return p->kind == N_INT || p->kind == N_FLOAT || p->kind == N_STR || (p->kind == N_KW && strcmp(symName(p->sym), "else")) || isName(p, "true") || isName(p, "false");
}
static const Ty *literalType(Node *p) {
  switch (p->kind) {
    case N_INT: return &tyInt;
    case N_FLOAT: return &tyFloat;
    case N_STR: return &tyStr;
    case N_KW: return &tyKw;
    default: return &tyBool;
  }
}
/* a pattern's constructor against the subject: only the kind counts, since mt tests constructors by name */
static void patternKind(Tc *c, Node *at, const Ty *subject, const Ty *ctor) {
  if (subject->k == K_UNK || ctor->k == K_UNK || subject->k == ctor->k) return;
  if (subject->k == K_ANYREC || subject->k == K_REC) return;
  mismatch(c, at, "mt pattern", subject, ctor);
}

/* the arm ((err e) (err e)) with the Result constructor err, as ip/desugarTry and astConverter lower x? */
static int errPropagation(Tc *c, Node *arm) {
  Def *df; Module *owner;
  if (arm->n != 2) return 0;
  Node *p = arm->kids[0], *b = arm->kids[1];
  if (p->kind != N_LIST || p->n != 2 || b->kind != N_LIST || b->n != 2) return 0;
  if (p->kids[0]->kind != N_SYM || p->kids[0]->sym != S_ERR || isCtorName(c, S_ERR, &df, &owner) == 0 || df) return 0;
  if (b->kids[0]->kind != N_SYM || b->kids[0]->sym != S_ERR || local(c, S_ERR)) return 0;
  return p->kids[1]->kind == N_SYM && b->kids[1]->kind == N_SYM && p->kids[1]->sym == b->kids[1]->sym && !isName(p->kids[1], "_");
}

static const Ty *matchT(Tc *c, Node *n, const Ty *want, int used) {
  if (n->n < 2) return &tyUnk;
  const Ty *st = tc(c, n->kids[1], &tyUnk, 1);
  Join jn = {NULL, 1}; int open = 1, family = matchFamily(c->m, n);
  int i = 2;
  for (; i < n->n && open; i++) {
    Node *arm = n->kids[i];
    if (arm->kind != N_LIST || arm->n < 2) {
      diag(c->d, c->m->path, arm, "ERR_INVALID_MT_ARM", "mt arm has an invalid pattern head");
      continue;
    }
    Node *p = arm->kids[0]; Def *df; Module *owner;
    int saved = c->nenv;
    if (isName(p, "_") || isName(p, "else")) open = 0;
    else if (p->kind == N_KW && !strcmp(symName(p->sym), "else")) { diag(c->d, c->m->path, p, "ERR_ELSE_KEYWORD", "mt pattern :else is a keyword literal, not the catch-all; use else or _"); continue; }
    else if (isLiteralPat(p)) {
      const Ty *lt = literalType(p);
      if (st->k >= K_INT && st->k <= K_KW && !compat(st, lt)) mismatch(c, p, "mt pattern", st, lt);
    } else if (ctorPattern(c->m, p, family) && isCtorName(c, p->sym, &df, &owner)) patternKind(c, p, st, ctorType(c, p->sym, df));
    else if (p->kind == N_SYM) {
      if ((df = hiddenCtor(c, p->sym, &owner))) {
        notExported(c->d, c->m->path, p, owner, df->name);
        patternKind(c, p, st, ctorType(c, p->sym, df));
      } else {
        const char *name = symName(p->sym); Module *patternOwner; Def *patternDef = defLookup(c->m, p->sym, &patternOwner);
        int formHead = !strcmp(name, "do") || !strcmp(name, "begin") || !strcmp(name, "if") || !strcmp(name, "cond") ||
          !strcmp(name, "let") || !strcmp(name, "match") || !strcmp(name, "mt") || !strcmp(name, "when") ||
          !strcmp(name, "unless") || !strcmp(name, "fn") || !strcmp(name, "lambda") || !strcmp(name, "assert") ||
          !strcmp(name, "refute") || !strcmp(name, "and") || !strcmp(name, "or") || !strcmp(name, "not");
        if ((patternDef && patternDef->kind != DEF_CTOR) || (!patternDef && builtinLookup(name)) || formHead) {
          diag(c->d, c->m->path, arm, "ERR_INVALID_MT_ARM", "mt arm has an invalid pattern head");
          continue;
        }
        bind(c, p->sym, st); open = 0;
      }
    }
    else if (p->kind == N_LIST && p->n >= 1 && p->kids[0]->kind == N_SYM) {
      int ctor = p->kids[0]->sym, k = p->n - 1;
      Node *ft[TC_MAX_PARAMS]; int nft = 0; const Ty *known[2] = {&tyUnk, &tyUnk};
      if (isCtorName(c, ctor, &df, &owner)) {
        patternKind(c, p->kids[0], st, ctorType(c, ctor, df));
        if (df && df->kind == DEF_CTOR) nft = ctorFieldTypes(df, ft, TC_MAX_PARAMS);
        else if (ctor == S_SOME && st->k == K_OPTION) known[0] = st->a;
        else if (ctor == S_OK && st->k == K_RESULT) known[0] = st->a;
        else if (ctor == S_ERR && st->k == K_RESULT) known[0] = st->b;
      } else {
        if ((df = hiddenCtor(c, ctor, &owner)))
          notExported(c->d, c->m->path, p->kids[0], owner, df->name);
        else
          diag(c->d, c->m->path, arm, "ERR_INVALID_MT_ARM", "mt arm has an invalid pattern head");
        continue;
      }
      for (int j = 0; j < k; j++) {
        Node *q = p->kids[j + 1];
        if (q->kind != N_SYM || isName(q, "_")) continue;
        const Ty *t = j < nft ? parseType(c, owner, ft[j]) : j < 2 ? known[j] : &tyUnk;
        bind(c, q->sym, t);
      }
    } else {
      diag(c->d, c->m->path, arm, "ERR_INVALID_MT_ARM", "mt arm has an invalid pattern head");
      continue;
    }
    /* arm bodies are checked now, with the pattern's names in scope; ((err e) (err e)), the try lowering, propagates
       the error and takes no part in the arm agreement */
    if (errPropagation(c, arm)) { tc(c, arm->kids[1], &tyUnk, 0); c->nenv = saved; continue; }
    const Ty *t = seqT(c, arm->kids + 1, arm->n - 1, want, used);
    c->nenv = saved;
    joinArm(c, &jn, t, arm->n > 1 ? arm->kids[arm->n - 1] : arm, want, "mt");
  }
  /* a catch-all binder arm or _/else closes the match (compile.c's matchForm stops compiling there too, D152-
     adjacent: any arm the writer put after it can never run, and silently got no diagnostic until now */
  for (; !open && i < n->n; i++) {
    Node *arm = n->kids[i];
    if (arm->kind != N_LIST || arm->n < 1) continue;
    diag(c->d, c->m->path, arm, "ERR_UNREACHABLE_ARM", "mt arm is unreachable: an earlier arm already binds everything");
  }
  return joinResult(&jn, want);
}

static const Ty *numericOperand(Tc *c, Node *at, const char *op, const Ty *t) {
  if (t->k == K_UNK || t->k == K_INT || t->k == K_FLOAT) return t;
  char what[64], f[256]; snprintf(what, sizeof what, "operand of %s", op);
  diag(c->d, c->m->path, at, "ERR_TYPE_MISMATCH", "%s: expected Int64 or Float64, found %s", what, tyName(t, f, sizeof f));
  return NULL;
}

/* (with x :k v ...) has x's type; x must be a record and each :k a field of its schema */
static const Ty *withT(Tc *c, Node *n, const Ty *want) {
  if (n->n < 4 || n->n % 2) { for (int i = 1; i < n->n; i++) tc(c, n->kids[i], &tyUnk, 1); return &tyUnk; }
  const Ty *t = tcAs(c, n->kids[1], &tyAnyRec, "record of with");
  char what[200];
  for (int i = 2; i + 1 < n->n; i += 2) {
    Node *k = n->kids[i], *ft = NULL; int known = 0;
    if (k->kind != N_KW) { tc(c, n->kids[i + 1], &tyUnk, 1); continue; }
    if (t->k == K_REC && t->def) {
      for (int j = 0; j < t->def->nfields; j++) known |= t->def->fields[j] == k->sym;
      if (!known) diag(c->d, c->m->path, k, "ERR_FIELD", "with: %s has no field %s", symName(t->name), symName(k->sym));
      ft = known ? schemaFieldType(t->def, k->sym) : NULL;
    }
    snprintf(what, sizeof what, "field %.80s of with", symName(k->sym));
    tcAs(c, n->kids[i + 1], ft ? parseType(c, t->m, ft) : &tyUnk, what);
  }
  return leaf(c, n, want, t->k == K_REC ? t : &tyUnk);
}

static const Ty *operatorT(Tc *c, Node *n, int op, const Ty *want) {
  const char *name = symName(n->kids[0]->sym); int argc = n->n - 1;
  if (argc == 1 && (op == OP_SUB || op == OP_ADD || op == OP_MUL)) {
    const Ty *t = numericOperand(c, n->kids[1], name, tc(c, n->kids[1], &tyUnk, 1));
    return leaf(c, n, want, t ? t : &tyUnk);
  }
  if (argc < 2 || (argc > 2 && op != OP_ADD && op != OP_MUL)) {
    for (int i = 1; i < n->n; i++) tc(c, n->kids[i], &tyUnk, 1);
    return &tyUnk;
  }
  char what[64]; snprintf(what, sizeof what, "operand of %s", name);
  if (op == OP_EQ || op == OP_NEQ) {
    for (int i = 1; i < n->n; i++) tc(c, n->kids[i], &tyUnk, 1);
    return leaf(c, n, want, &tyBool);
  }
  if (op >= OP_LT && op <= OP_GE) {
    const Ty *ts[2]; int ok = 1;
    for (int i = 0; i < 2; i++) {
      ts[i] = tc(c, n->kids[i + 1], &tyUnk, 1);
      if (ts[i]->k != K_UNK && ts[i]->k != K_INT && ts[i]->k != K_FLOAT && ts[i]->k != K_STR && ts[i]->k != K_KW) {
        char f[256];
        diag(c->d, c->m->path, n->kids[i + 1], "ERR_TYPE_MISMATCH", "%s: expected Int64, Float64, String or Keyword, found %s", what, tyName(ts[i], f, sizeof f));
        ok = 0;
      }
    }
    if (ok && !compat(ts[0], ts[1])) mismatch(c, n->kids[2], what, ts[0], ts[1]);
    return leaf(c, n, want, &tyBool);
  }
  const Ty *num = NULL; int bad = 0;
  for (int i = 1; i < n->n; i++) {
    const Ty *t = numericOperand(c, n->kids[i], name, tc(c, n->kids[i], &tyUnk, 1));
    if (!t) { bad = 1; continue; }
    if (t->k == K_UNK) continue;
    if (!num) num = t;
    else if (num->k != t->k) { mismatch(c, n->kids[i], what, num, t); bad = 1; }
  }
  return leaf(c, n, want, num && !bad ? num : &tyUnk);
}

static void argsUnknown(Tc *c, Node *n, int from) { for (int i = from; i < n->n; i++) tc(c, n->kids[i], &tyUnk, 1); }

/* CHECKER-localCallReturnBool: a call through a local fn-valued variable (the bound Ty from symType/lambdaT may
   carry a known return type) is otherwise argsUnknown with its result always &tyUnk, so a non-Bool return used as
   a cond test (or anywhere else a Ty is wanted) was never checked and only trapped later at runtime by OP_JF */
static const Ty *fnReturn(const Ty *t) { return t->k == K_FN && t->a ? t->a : &tyUnk; }

static const Ty *callT(Tc *c, Node *n, const Ty *want, int used) {
  Node *h = n->kids[0]; int argc = n->n - 1;
  if (h->kind != N_SYM || local(c, h->sym)) {
    if (h->kind != N_SYM) tc(c, h, &tyUnk, 1);
    argsUnknown(c, n, 1);
    const Bind *lb = h->kind == N_SYM ? local(c, h->sym) : NULL;
    return leaf(c, n, want, lb ? fnReturn(lb->t) : &tyUnk);
  }
  int s = h->sym, op; const char *name = symName(s);
  if (!strcmp(name, "if")) {
    if (argc < 2 || argc > 3) { argsUnknown(c, n, 1); return &tyUnk; }
    tcAs(c, n->kids[1], &tyBool, "if condition");
    if (argc == 2) { tc(c, n->kids[2], &tyUnk, 0); return leaf(c, n, want, &tyUnit); }
    Arm arms[2] = {{n->kids + 2, 1, n->kids[2]}, {n->kids + 3, 1, n->kids[3]}};
    return armsT(c, arms, 2, want, used, "if");
  }
  if (!strcmp(name, "when") || !strcmp(name, "unless")) {
    if (argc >= 1) tcAs(c, n->kids[1], &tyBool, "when condition");
    seqT(c, n->kids + 2, n->n - 2, &tyUnk, 0);
    return &tyUnk;
  }
  if (!strcmp(name, "cond")) {
    Arm *arms = malloc(sizeof(Arm) * (size_t)n->n);
    if (!arms) exit(70);
    int na = 0;
    for (int i = 1; i < n->n; i++) {
      Node *cl = n->kids[i];
      if (cl->kind != N_LIST || cl->n < 1) continue;
      Node *t = cl->kids[0];
      int isElse = isName(t, "else");
      if (!isElse) tcAs(c, t, &tyBool, "cond test");
      arms[na++] = (Arm){cl->kids + 1, cl->n - 1, cl};
      if (isElse) break;
    }
    const Ty *t = armsT(c, arms, na, want, used, "cond");
    free(arms);
    return t;
  }
  if (!strcmp(name, "and") || !strcmp(name, "or")) {
    for (int i = 1; i < n->n; i++) tcAs(c, n->kids[i], &tyBool, name[0] == 'a' ? "and operand" : "or operand");
    return leaf(c, n, want, &tyBool);
  }
  if (!strcmp(name, "not")) {
    if (argc != 1) { argsUnknown(c, n, 1); return &tyUnk; }
    tcAs(c, n->kids[1], &tyBool, "not operand");
    return leaf(c, n, want, &tyBool);
  }
  if (!strcmp(name, "do") || !strcmp(name, "begin")) return seqT(c, n->kids + 1, argc, want, used);
  if (!strcmp(name, "let")) return letT(c, n, want, used);
  if (!strcmp(name, "fn") || !strcmp(name, "lambda")) return lambdaT(c, n, want);
  if (!strcmp(name, "match") || !strcmp(name, "mt")) return matchT(c, n, want, used);
  if (!strcmp(name, "assert") || !strcmp(name, "refute")) {
    int isAssert = name[0] == 'a', trap = argc >= 1 && isName(n->kids[1], isAssert ? "false" : "true");
    if (argc >= 1) tcAs(c, n->kids[1], &tyBool, isAssert ? "assert condition" : "refute condition");
    argsUnknown(c, n, 2);
    return trap ? &tyUnk : leaf(c, n, want, &tyUnit);
  }
  if (name[0] == '.' && name[1] == '-' && name[2]) {
    if (argc != 1) { argsUnknown(c, n, 1); return &tyUnk; }
    char what[160]; snprintf(what, sizeof what, "operand of %.120s", name);
    const Ty *t = tcAs(c, n->kids[1], &tyAnyRec, what);
    Node *ft = t->k == K_REC ? schemaFieldType(t->def, intern(name + 2, strlen(name + 2))) : NULL;
    return leaf(c, n, want, ft ? parseType(c, t->m, ft) : &tyUnk);
  }
  if (!strcmp(name, "with") && !moduleDef(c->m, s)) return withT(c, n, want);
  if ((op = opFor(name)) >= 0 && !moduleDef(c->m, s)) return operatorT(c, n, op, want);
  Module *owner = c->m; Def *df = defLookup(c->m, s, &owner);
  char what[200];
  if (df && df->kind == DEF_FN) {
    Sig sig; signature(df->group, &sig);
    /* a wrong argument count is ERR_ARITY; its arguments do not line up with the parameters */
    for (int i = 1; i <= argc; i++) {
      Node *tn = argc == sig.np && i - 1 < TC_MAX_PARAMS ? sig.types[i - 1] : NULL;
      snprintf(what, sizeof what, "argument %d of %.120s", i, name);
      tcAs(c, n->kids[i], parseType(c, owner, tn), what);
    }
    return leaf(c, n, want, parseType(c, owner, sig.ret));
  }
  if (df && df->kind == DEF_CTOR) {
    Node *ft[TC_MAX_PARAMS]; int nft = ctorFieldTypes(df, ft, TC_MAX_PARAMS);
    for (int i = 1; i <= argc; i++) {
      snprintf(what, sizeof what, "field %d of %.120s", i, name);
      tcAs(c, n->kids[i], argc == df->arity && i - 1 < nft ? parseType(c, owner, ft[i - 1]) : &tyUnk, what);
    }
    return leaf(c, n, want, ctorType(c, s, df));
  }
  if (!df && (s == S_SOME || s == S_OK || s == S_ERR) && argc == 1) {
    int isOpt = s == S_SOME, isErr = s == S_ERR;
    Kind k = isOpt ? K_OPTION : K_RESULT;
    const Ty *inner = want->k == k ? (isErr ? want->b : want->a) : &tyUnk;
    snprintf(what, sizeof what, "argument of %s", name);
    const Ty *t = tcAs(c, n->kids[1], inner, what);
    const Ty *found = isOpt ? mk(c, K_OPTION, t, NULL) : isErr ? mk(c, K_RESULT, NULL, t) : mk(c, K_RESULT, t, NULL);
    return want->k == k ? found : leaf(c, n, want, found);
  }
  if (!df && s == S_NONE && argc == 0) return leaf(c, n, want, mk(c, K_OPTION, NULL, NULL));
  if (df && df->kind == DEF_SCHEMA) {
    for (int i = 1; i + 1 < n->n; i += 2) {
      Node *k = n->kids[i];
      if (k->kind != N_KW) { argsUnknown(c, n, i); break; }
      Node *ft = schemaFieldType(df, k->sym);
      snprintf(what, sizeof what, "field :%.60s of %.60s", symName(k->sym), name);
      tcAs(c, n->kids[i + 1], ft ? parseType(c, owner, ft) : &tyUnk, what);
    }
    return leaf(c, n, want, mkRec(c, df, owner));
  }
  if (!df && builtinLookup(name)) {
    for (size_t b = 0; b < sizeof builtinSigs / sizeof builtinSigs[0]; b++) {
      if (strcmp(builtinSigs[b].name, name)) continue;
      const char *ps = builtinSigs[b].params;
      for (int i = 1; i <= argc; i++) {
        snprintf(what, sizeof what, "argument %d of %.120s", i, name);
        tcAs(c, n->kids[i], ps && strlen(ps) == (size_t)argc ? codeType(c, ps[i - 1]) : &tyUnk, what);
      }
      return leaf(c, n, want, codeType(c, builtinSigs[b].ret[0]));
    }
  }
  if (!df && nativeOnlyBuiltin(name)) {
    for (size_t b = 0; b < sizeof nativeOnlySigs / sizeof nativeOnlySigs[0]; b++) {
      if (strcmp(nativeOnlySigs[b].name, name)) continue;
      const char *ps = nativeOnlySigs[b].params;
      for (int i = 1; i <= argc; i++) {
        snprintf(what, sizeof what, "argument %d of %.120s", i, name);
        tcAs(c, n->kids[i], ps && strlen(ps) == (size_t)argc ? codeType(c, ps[i - 1]) : &tyUnk, what);
      }
      return leaf(c, n, want, codeType(c, nativeOnlySigs[b].ret[0]));
    }
  }
  argsUnknown(c, n, 1);
  return &tyUnk;
}

static const Ty *tcInner(Tc *c, Node *n, const Ty *want, int used) {
  switch (n->kind) {
    case N_INT: return leaf(c, n, want, &tyInt);
    case N_FLOAT: return leaf(c, n, want, &tyFloat);
    case N_STR: return leaf(c, n, want, &tyStr);
    case N_KW: return leaf(c, n, want, &tyKw);
    case N_SYM: return leaf(c, n, want, symType(c, n));
    case N_VEC: {
      const Ty *ew = want->k == K_LIST ? want->a : &tyUnk, *e = NULL; int same = 1;
      for (int i = 0; i < n->n; i++) {
        const Ty *t = tc(c, n->kids[i], ew, 1);
        if (t->k == K_UNK) same = 0;
        else if (!e) e = t;
        else if (!compat(e, t)) same = 0;
      }
      const Ty *found = mk(c, K_LIST, same && e ? e : NULL, NULL);
      return want->k == K_LIST ? found : leaf(c, n, want, found);
    }
    case N_MAP:
      for (int i = 1; i < n->n; i += 2) tc(c, n->kids[i], &tyUnk, 1);
      return leaf(c, n, want, &tyAnyRec);
    case N_LIST:
      if (n->n == 0) return leaf(c, n, want, &tyUnit);
      return callT(c, n, want, used);
    default: return &tyUnk;
  }
}

static const Ty *tc(Tc *c, Node *n, const Ty *want, int used) {
  if (c->depth >= TC_MAX_NEST) return &tyUnk;
  c->depth++;
  const Ty *t = tcInner(c, n, want, used);
  c->depth--;
  return t;
}

static void release(Tc *c) {
  while (c->arena) { Chunk *next = c->arena->next; free(c->arena); c->arena = next; }
  free(c->env);
}

void typeCheckModule(Module *m, Diags *d) {
  initNames();
  Tc c = {0}; c.m = m; c.d = d;
  for (int i = 0; i < m->ndefs; i++) {
    Def *df = &m->defs[i];
    if (df->kind != DEF_FN) continue;
    Node *g = df->group; int params[TC_MAX_PARAMS], nameAt, bodyAt;
    int np = fnSignature(g, &nameAt, params, TC_MAX_PARAMS, &bodyAt);
    if (np > TC_MAX_PARAMS) continue;
    Sig sig; signature(g, &sig);
    c.nenv = 0;
    for (int p = 0; p < np; p++) {
      if (!sig.types[p]) diag(d, m->path, g->kids[nameAt], "ERR_UNTYPED_PARAM", "function %s parameter %s has no type annotation", symName(df->name), symName(params[p]));
      bind(&c, params[p], parseType(&c, m, sig.types[p]));
    }
    char what[160]; snprintf(what, sizeof what, "return of %.120s", symName(df->name));
    c.ctx = what;
    seqT(&c, g->kids + bodyAt, g->n - bodyAt, parseType(&c, m, sig.ret), 1);
    c.ctx = NULL;
  }
  c.nenv = 0;
  for (int i = 0; i < m->ntops; i++) tc(&c, m->tops[i], &tyUnk, 0);
  release(&c);
}

void typeCheckForms(Module *m, Node **forms, int n, Diags *d) {
  initNames();
  Tc c = {0}; c.m = m; c.d = d;
  seqT(&c, forms, n, &tyUnk, 1);
  release(&c);
}
