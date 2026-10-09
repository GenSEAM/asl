/* Bytecode compiler: lexical addressing, capture by copy, tail positions marked, unknown symbols diagnosed
   before anything runs (I1); in check mode also static arity (I11) and closed-enum exhaustiveness (I4). */
#include "ops.h"
#include <stdlib.h>
#include <string.h>

Proto **protoTab; int nprotoTab; static int capprotoTab;

typedef struct { int name, slot; Node *lit; int freshBytes; } Local;  /* literal and fresh local Bytes origin, if known */
typedef struct { int name, fromLocal, idx; } Cap;
typedef struct Fc {
  struct Fc *up; Proto *p; Module *m; Diags *d;
  Local loc[1024]; int nloc;
  Cap caps[256]; int ncap;
  int depth;
  int lastBin;          /* code index of the latest OP_BIN_*, for return fusion */
  Node *unconsNode;     /* the match whose (some t) test an enclosing OP_LUNCONS performed (unconsInner) */
  int pushAt, label;    /* code index of the latest push, which a following push joins into OP_PUSHN unless a jump lands
                           between them at label, the latest patched target */
  int topLine;          /* line of the enclosing top-level item, for its (:m :tags (...)) line (D152) */
  int pend[1024]; int npend;  /* names a let binds at or after the value being compiled: not in scope there */
  Def *fnDef;           /* enclosing named fn, for its effect record (LS1); NULL at top level and in eval */
} Fc;

static int S_HOSTSUBJECT, S_TRUE, S_FALSE, S_UNDERSCORE, S_ELSE, S_ARROW, S_IF, S_WHEN, S_UNLESS, S_COND, S_AND, S_OR, S_NOT, S_DO, S_BEGIN,
  S_LET, S_FN, S_LAMBDA, S_MATCH, S_MT, S_ASSERT, S_REFUTE, S_WITH;
static void initSyms(void) {
  if (S_TRUE) return;
  S_HOSTSUBJECT = intern("hostSubject", 11);
  S_TRUE = intern("true", 4); S_FALSE = intern("false", 5); S_UNDERSCORE = intern("_", 1); S_ELSE = intern("else", 4);
  S_ARROW = intern("->", 2); S_IF = intern("if", 2); S_WHEN = intern("when", 4); S_UNLESS = intern("unless", 6);
  S_COND = intern("cond", 4); S_AND = intern("and", 3); S_OR = intern("or", 2); S_NOT = intern("not", 3); S_DO = intern("do", 2);
  S_BEGIN = intern("begin", 5); S_LET = intern("let", 3); S_FN = intern("fn", 2); S_LAMBDA = intern("lambda", 6);
  S_MATCH = intern("match", 5); S_MT = intern("mt", 2); S_ASSERT = intern("assert", 6); S_REFUTE = intern("refute", 6); S_WITH = intern("with", 4);
  KW_SOME = intern("some", 4); KW_NONE = intern("none", 4); KW_OK = intern("ok", 2); KW_ERR = intern("err", 3); KW_PARTIAL = intern("partial", 7);
}

static Proto *newProto(const char *name, const char *file) {
  Proto *p = calloc(1, sizeof(Proto));
  if (!p) exit(70);
  p->name = name; p->file = file;
  if (nprotoTab == capprotoTab) { capprotoTab = capprotoTab ? capprotoTab * 2 : 256; protoTab = realloc(protoTab, sizeof(Proto *) * capprotoTab); if (!protoTab) exit(70); }
  protoTab[nprotoTab++] = p;
  gcRegisterProto(p);
  return p;
}

static void emit(Fc *f, uint32_t w) {
  Proto *p = f->p;
  if (p->ncode == p->capcode) { p->capcode = p->capcode ? p->capcode * 2 : 64; p->code = realloc(p->code, sizeof(uint32_t) * p->capcode); if (!p->code) exit(70); }
  p->code[p->ncode++] = w;
}
static void adj(Fc *f, int delta) { f->depth += delta; if (f->depth > f->p->maxstack) f->p->maxstack = f->depth; }
static int here(Fc *f) { return f->p->ncode; }
static void patch(Fc *f, int at) { f->p->code[at] = (uint32_t)f->p->ncode; f->label = f->p->ncode; }

static int addConst(Fc *f, Val v) {
  Proto *p = f->p;
  if (p->nconsts == p->capconsts) { p->capconsts = p->capconsts ? p->capconsts * 2 : 16; p->consts = realloc(p->consts, sizeof(Val) * p->capconsts); if (!p->consts) exit(70); }
  p->consts[p->nconsts] = v;
  return p->nconsts++;
}
/* a push of a global, local, constant or upvalue (PUSH_* kinds); consecutive pushes share one OP_PUSHN dispatch */
static void emitPush(Fc *f, uint32_t kind, uint32_t idx) {
  static const uint32_t single[] = {OP_GLOBAL, OP_LOCAL, OP_CONST, OP_UPVAL};
  uint32_t *c = f->p->code; int at = f->pushAt, end = here(f);
  if (at >= 0 && f->label != end && idx <= PUSH_INDEX) {
    int many = c[at] == OP_PUSHN; uint32_t n = many ? c[at + 1] : 1;
    /* the first push folded into a PUSHN word packs its own idx as kind<<30|idx too; an
       unchecked idx there would overflow into the kind bits exactly as an unchecked joining
       idx would, so the bound applies before folding, not only to the push being joined */
    if (at + 2 + (int)(many ? n : 0) == end && n < 255 && (many || c[at + 1] <= PUSH_INDEX)) {
      if (!many) {
        uint32_t k = c[at] == OP_GLOBAL ? PUSH_GLOBAL : c[at] == OP_LOCAL ? PUSH_LOCAL : c[at] == OP_CONST ? PUSH_CONST : PUSH_UPVAL;
        c[at + 1] = k << 30 | c[at + 1]; c[at] = OP_PUSHN; emit(f, 0);
        c = f->p->code; c[at + 2] = c[at + 1]; c[at + 1] = 1;
      }
      c[at + 1]++; emit(f, kind << 30 | idx); adj(f, 1);
      return;
    }
  }
  f->pushAt = end; emit(f, single[kind]); emit(f, idx); adj(f, 1);
}
static void emitConst(Fc *f, Val v) { emitPush(f, PUSH_CONST, (uint32_t)addConst(f, v)); }
static void emitUnit(Fc *f) { emit(f, OP_UNIT); adj(f, 1); }

static int findLocal(Fc *f, int name) {
  for (int i = f->nloc - 1; i >= 0; i--) if (f->loc[i].name == name) return f->loc[i].slot;
  return -1;
}
static int findCap(Fc *f, int name) {
  for (int i = 0; i < f->ncap; i++) if (f->caps[i].name == name) return i;
  if (!f->up) return -1;
  int s = findLocal(f->up, name), from = 1;
  if (s < 0) { s = findCap(f->up, name); from = 0; }
  if (s < 0) return -1;
  if (f->ncap == 256) aslError("ERR_LIMIT", "more than 256 captured variables");
  f->caps[f->ncap] = (Cap){name, from, s};
  return f->ncap++;
}
static void bindLocal(Fc *f, int name, int slot) {
  if (f->nloc == 1024) aslError("ERR_LIMIT", "more than 1024 locals in one function");
  f->loc[f->nloc++] = (Local){name, slot, NULL, 0};
}
static Local *findLocalEntry(Fc *f, int name) {
  for (int i = f->nloc - 1; i >= 0; i--) if (f->loc[i].name == name) return &f->loc[i];
  return NULL;
}
static Def *globalDef(Module *m, int name, Module **owner);
static int freshBytesName(Fc *f, int name) {
  Local *l = findLocalEntry(f, name);
  if (l) return l->freshBytes;
  return f->up ? freshBytesName(f->up, name) : 0;
}
/* Only a direct bytesAlloc result or an alias of one is known fresh. Unknown expressions and parameters stay effectful. */
static int freshBytesExpr(Fc *f, Node *n) {
  if (!n) return 0;
  if (n->kind == N_SYM) return freshBytesName(f, n->sym);
  if (n->kind != N_LIST || n->n < 2 || n->kids[0]->kind != N_SYM || strcmp(symName(n->kids[0]->sym), "bytesAlloc")) return 0;
  int name = n->kids[0]->sym; Module *owner = NULL;
  if (findLocal(f, name) >= 0 || findCap(f, name) >= 0 || globalDef(f->m, name, &owner)) return 0;
  return 1;
}

/* alias/member resolves through the importing module's alias table; plain names through its own definitions */
/* then the prelude module's definitions, which come before the C builtins */
extern Module *preludeModule;
extern int nativeOnlyBuiltin(const char *name);
extern int nativeOnlyArity(const char *name);
extern int nativeOnlyEffect(const char *name);
#define NATIVE_ONLY_TAG 0x80000000u
static uint32_t nativeOnlyCode(const char *name) { return NATIVE_ONLY_TAG | (uint32_t)intern(name, strlen(name)); }
static Def *globalDef(Module *m, int name, Module **owner) {
  Def *df = moduleDef(m, name);
  if (df) { *owner = m; return df; }
  const char *s = symName(name), *sl = strchr(s, '/');
  if (sl && sl != s && sl[1]) {
    int alias = intern(s, (size_t)(sl - s));
    for (int i = 0; i < m->nimports; i++)
      if (m->imports[i].alias == alias && m->imports[i].m) {
        *owner = m->imports[i].m;
        return moduleDef(m->imports[i].m, intern(sl + 1, strlen(sl + 1)));
      }
  }
  if (preludeModule && m != preludeModule && (df = moduleDef(preludeModule, name))) { *owner = preludeModule; return df; }
  return NULL;
}
static const Builtin *moduleBuiltin(Module *m, const char *name) { const char *slash = strchr(name, '/'); if (slash && slash != name && slash[1]) { int alias = intern(name, (size_t)(slash - name)); for (int i = 0; i < m->nimports; i++) if (m->imports[i].alias == alias && !strcmp(symName(m->imports[i].path), "sys")) return builtinLookup(slash + 1); return NULL; } return builtinLookup(name); }

static int listedExport(Module *m, int name) {
  for (int i = 0; i < m->nexports; i++) if (m->exports[i] == name) return 1;
  return 0;
}

/* an imported definition is visible qualified only when its module's :x lists it, or for a constructor its enum */
int defExported(Module *m, Def *df) {
  return listedExport(m, df->name) || (df->kind == DEF_CTOR && df->enumId >= 0 && listedExport(m, enums[df->enumId].name));
}

/* ERR_NOT_EXPORTED once per site, since a site may be resolved by more than one pass */
void notExported(Diags *d, const char *file, Node *at, Module *owner, int member) {
  char head[512];
  snprintf(head, sizeof head, "%s:%d:%d: ERR_NOT_EXPORTED ", file, at ? at->line : 0, at ? at->col + 1 : 0);
  for (int i = 0; i < d->n; i++) if (!strncmp(d->msgs[i], head, strlen(head))) return;
  diag(d, file, at, "ERR_NOT_EXPORTED", "module %s does not export %s", owner->name >= 0 ? symName(owner->name) : owner->path, symName(member));
}

/* a bare name no module or prelude definition claims may be an exported enum constructor of a directly imported
   module; one that two imports both define is an error, never a silent pick, and an unexported one ERR_NOT_EXPORTED */
static Def *lookupDef(Fc *f, Node *at, int name, Module **owner) {
  Def *df = globalDef(f->m, name, owner);
  if (df && strchr(symName(name), '/') && *owner != f->m && *owner != preludeModule && !defExported(*owner, df))
    notExported(f->d, f->m->path, at, *owner, df->name);
  if (df || strchr(symName(name), '/')) return df;
  Module *first = NULL, *hiddenIn = NULL; Def *hidden = NULL;
  for (int i = 0; i < f->m->nimports; i++) {
    Module *im = f->m->imports[i].m; Def *c;
    if (!im || im == first || !(c = moduleDef(im, name)) || c->kind != DEF_CTOR) continue;
    if (!defExported(im, c)) { if (!hidden) { hidden = c; hiddenIn = im; } continue; }
    if (df) { diag(f->d, f->m->path, at, "ERR_AMBIGUOUS_SYMBOL", "constructor %s is defined by both %s and %s", symName(name), first->path, im->path); break; }
    df = c; first = im;
  }
  if (!df && hidden) { notExported(f->d, f->m->path, at, hiddenIn, name); *owner = hiddenIn; return hidden; }
  if (df) *owner = first;
  return df;
}

/* lookupDef without diagnostics, for the type pass (types.c); an ambiguous constructor resolves to nothing */
Def *defLookup(Module *m, int name, Module **owner) {
  Def *df = globalDef(m, name, owner);
  if (df || strchr(symName(name), '/')) return df;
  Module *first = NULL;
  for (int i = 0; i < m->nimports; i++) {
    Module *im = m->imports[i].m; Def *c;
    if (!im || im == first || !(c = moduleDef(im, name)) || c->kind != DEF_CTOR || !defExported(im, c)) continue;
    if (df) return NULL;
    df = c; first = im;
  }
  if (df) *owner = first;
  return df;
}

static int isS(Node *n, int sym) { return n && n->kind == N_SYM && n->sym == sym; }
/* LS1: in check mode a fn body records the effectful builtins and the fns it names, lambdas counted for their fn */
static void noteBuiltin(Fc *f, Node *at, Node *call, const Builtin *b) {
  Def *o = f->fnDef;
  if ((!strcmp(b->name, "bytesSet") || !strcmp(b->name, "bytesSetFloat64")) && call && call->n > 1 && freshBytesExpr(f, call->kids[1])) return;
  if (o && f->d->checkMode && b->effect && !o->effAt) { o->effAt = at; o->effWhat = b->name; }
}
static void noteNativeBuiltin(Fc *f, Node *at, const char *name) {
  Def *o = f->fnDef;
  if (o && f->d->checkMode && nativeOnlyEffect(name) && !o->effAt) { o->effAt = at; o->effWhat = name; }
}
static void noteFn(Fc *f, Node *at, Def *df, Module *owner) {
  Def *o = f->fnDef;
  if (!o || !f->d->checkMode) return;
  if (o->nrefs == o->caprefs) { o->caprefs = o->caprefs ? o->caprefs * 2 : 8; o->refs = realloc(o->refs, sizeof(EffRef) * (size_t)o->caprefs); if (!o->refs) exit(70); }
  o->refs[o->nrefs++] = (EffRef){df, owner, at};
}
static int builtinCtorArity(int name) {
  if (name == KW_SOME || name == KW_OK || name == KW_ERR) return 1;
  if (name == KW_NONE) return 0;
  return -1;
}

int ctorFamily(Module *m, int name) {
  Module *owner; Def *df = defLookup(m, name, &owner);
  if (df) return df->kind == DEF_CTOR && df->enumId >= 0 ? df->enumId : NO_FAMILY;
  if (name == KW_SOME || name == KW_NONE) return FAMILY_OPTION;
  if (name == KW_OK || name == KW_ERR) return FAMILY_RESULT;
  return NO_FAMILY;
}

int matchFamily(Module *m, Node *n) {
  for (int bare = 0; bare < 2; bare++)
    for (int i = 2; i < n->n; i++) {
      Node *arm = n->kids[i], *p, *h;
      if (arm->kind != N_LIST || arm->n < 1) continue;
      p = arm->kids[0];
      h = bare ? (p->kind == N_SYM ? p : NULL) : (p->kind == N_LIST && p->n >= 1 && p->kids[0]->kind == N_SYM ? p->kids[0] : NULL);
      int fam = h ? ctorFamily(m, h->sym) : NO_FAMILY;
      if (fam != NO_FAMILY) return fam;
    }
  return NO_FAMILY;
}

int ctorPattern(Module *m, Node *p, int family) {
  return p->kind == N_SYM && family != NO_FAMILY && ctorFamily(m, p->sym) == family;
}

static void expr(Fc *f, Node *n, int tail);
static void compileTops(Module *m, Diags *d);
static int isLiteral(Node *n);

/* a function ending in a binary op returns straight from that op (bit 16 of its operand word); the RET stays for
   any jump that lands after it */
static void emitRet(Fc *f) {
  if (f->p->ncode >= 4 && f->lastBin == f->p->ncode - 4) f->p->code[f->lastBin + 1] |= 1u << 16;
  emit(f, OP_RET);
}

static void seq(Fc *f, Node **xs, int n, int tail) {
  if (n == 0) { emitUnit(f); return; }
  for (int i = 0; i < n; i++) {
    expr(f, xs[i], tail && i == n - 1);
    if (i < n - 1) { emit(f, OP_POP); adj(f, -1); }
  }
}

/* depth of the Fc chain above f whose let is binding name (0 is f itself), or -1 */
static int pendingAt(Fc *f, int name) {
  for (int k = 0; f; f = f->up, k++) for (int i = 0; i < f->npend; i++) if (f->pend[i] == name) return k;
  return -1;
}

/* a let value naming its own binding or a later one is letrec; D153 keeps the heap acyclic, so it is an error */
static void unknown(Fc *f, Node *at, int name) {
  if (pendingAt(f, name) >= 0) diag(f->d, f->m->path, at, "ERR_LETREC", "%s is bound by this let only after this value; a local fn cannot name itself or a later binding (acyclic heap, D153): make it a top-level fn", symName(name));
  else diag(f->d, f->m->path, at, "ERR_UNKNOWN_SYMBOL", "%s", symName(name));
}

static void symbol(Fc *f, Node *n) {
  int s;
  if (n->sym == S_TRUE || n->sym == S_FALSE) { emitConst(f, vbool(n->sym == S_TRUE)); return; }
  if ((s = findLocal(f, n->sym)) >= 0) { emitPush(f, PUSH_LOCAL, (uint32_t)s); return; }
  if ((s = findCap(f, n->sym)) >= 0) { emitPush(f, PUSH_UPVAL, (uint32_t)s); return; }
  Module *owner; Def *df = lookupDef(f, n, n->sym, &owner);
  if (df && df->kind == DEF_FN) { noteFn(f, n, df, owner); emitPush(f, PUSH_GLOBAL, (uint32_t)df->gidx); return; }
  if ((df && df->kind == DEF_CTOR && df->arity == 0) || n->sym == KW_NONE) {
    emit(f, OP_MKCTOR); emit(f, (uint32_t)(df ? df->name : n->sym)); emit(f, 0); emit(f, 0); adj(f, 1); return;
  }
  const Builtin *b = moduleBuiltin(f->m, symName(n->sym));
  if (b) { noteBuiltin(f, n, NULL, b); Val v = {T_BUILTIN, (uint32_t)builtinIndex(b), {.i = 0}}; emitConst(f, v); return; }
  if (nativeOnlyBuiltin(symName(n->sym))) {
    noteNativeBuiltin(f, n, symName(n->sym));
    Val v = {T_BUILTIN, nativeOnlyCode(symName(n->sym)), {.i = 0}}; emitConst(f, v); return;
  }
  if (df || builtinCtorArity(n->sym) >= 0) diag(f->d, f->m->path, n, "ERR_UNSUPPORTED", "constructor %s used as a value", symName(n->sym));
  else unknown(f, n, n->sym);
  emitUnit(f);
}

static void lambda(Fc *f, Node *n) {
  Fc *c = calloc(1, sizeof(Fc));
  if (!c) exit(70);
  c->up = f; c->m = f->m; c->d = f->d; c->p = newProto("lambda", f->m->path); c->lastBin = c->pushAt = c->label = -1; c->topLine = f->topLine; c->fnDef = f->fnDef;
  int protoIdx = nprotoTab - 1;
  int body = 2;
  if (n->n >= 2 && (n->kids[1]->kind == N_VEC || n->kids[1]->kind == N_LIST)) {
    Node *ps = n->kids[1];
    for (int i = 0; i < ps->n; i++) {
      Node *q = ps->kids[i];
      int name = q->kind == N_SYM ? q->sym : (q->kind == N_LIST && q->n >= 1 && q->kids[0]->kind == N_SYM) ? q->kids[0]->sym : -1;
      if (name < 0) { diag(f->d, f->m->path, q, "ERR_BAD_LAMBDA", "parameter is not a name"); continue; }
      bindLocal(c, name, c->p->nparams++);
    }
  } else diag(f->d, f->m->path, n, "ERR_BAD_LAMBDA", "fn without a parameter vector");
  c->depth = c->p->nparams; c->p->maxstack = c->depth;
  if (body < n->n && isS(n->kids[body], S_ARROW)) body += 2;
  seq(c, n->kids + body, body < n->n ? n->n - body : 0, 1);
  emitRet(c);
  emit(f, OP_CLOSURE); emit(f, (uint32_t)protoIdx);
  emit(f, (uint32_t)c->ncap);
  for (int i = 0; i < c->ncap; i++) { emit(f, (uint32_t)c->caps[i].fromLocal); emit(f, (uint32_t)c->caps[i].idx); }
  adj(f, 1);
  free(c);
}

static void letForm(Fc *f, Node *n, int tail) {
  if (n->n < 2 || (n->kids[1]->kind != N_VEC && n->kids[1]->kind != N_LIST)) { diag(f->d, f->m->path, n, "ERR_BAD_LET", "let without a binding vector"); emitUnit(f); return; }
  Node *bs = n->kids[1]; int nb = 0, saved = f->nloc;
  int pairs = bs->n > 0 && bs->kids[0]->kind == N_LIST;
  for (int i = 0; i < bs->n; i += pairs ? 1 : 2) {
    Node *name, *val;
    if (pairs) { Node *b = bs->kids[i]; if (b->kind != N_LIST || b->n < 2) { diag(f->d, f->m->path, b, "ERR_BAD_LET", "binding is not (name expr)"); continue; } name = b->kids[0]; val = b->kids[b->n - 1]; }
    else { if (i + 1 >= bs->n) { diag(f->d, f->m->path, bs, "ERR_BAD_LET", "odd binding vector"); break; } name = bs->kids[i]; val = bs->kids[i + 1]; }
    if (name->kind != N_SYM) { diag(f->d, f->m->path, name, "ERR_BAD_LET", "binding name is not a symbol"); continue; }
    int np = f->npend;
    for (int j = i; j < bs->n; j += pairs ? 1 : 2) {
      Node *later = pairs ? (bs->kids[j]->kind == N_LIST && bs->kids[j]->n >= 2 ? bs->kids[j]->kids[0] : NULL) : bs->kids[j];
      if (!later || later->kind != N_SYM) continue;
      if (f->npend == (int)(sizeof f->pend / sizeof f->pend[0])) aslError("ERR_LIMIT", "more than 1024 pending let names");
      f->pend[f->npend++] = later->sym;
    }
    int freshBytes = freshBytesExpr(f, val);
    expr(f, val, 0);
    f->npend = np;
    bindLocal(f, name->sym, f->depth - 1); nb++;
    if (isLiteral(val)) f->loc[f->nloc - 1].lit = val;
    f->loc[f->nloc - 1].freshBytes = freshBytes;
  }
  seq(f, n->kids + 2, n->n - 2, tail);
  if (nb) { emit(f, OP_SLIDE); emit(f, (uint32_t)nb); adj(f, -nb); }
  f->nloc = saved;
}

/* operands that are locals or literals are addressed in the instruction word, saving their push dispatches */
static uint32_t operand(Fc *f, Node *x, uint32_t *idx) {
  int s;
  if (x->kind == N_SYM && (s = findLocal(f, x->sym)) >= 0) { *idx = (uint32_t)s; return 1; }
  if (x->kind == N_INT && !x->outOfRange) { *idx = (uint32_t)addConst(f, vint(x->i)); return 2; }
  if (x->kind == N_FLOAT) { *idx = (uint32_t)addConst(f, vfloat(x->f)); return 2; }
  expr(f, x, 0); *idx = 0; return 0;
}

/* OP_BIN pushes the result; OP_JBIN (comparisons only) jumps to a patched target when the result is false and
   returns the patch site */
static int binary(Fc *f, uint32_t op, Node *a, Node *b, int jump) {
  int d0 = f->depth; uint32_t ia, ib;
  uint32_t ka = operand(f, a, &ia), kb = operand(f, b, &ib);
  if (jump < 0) f->lastBin = here(f);
  emit(f, jump >= 0 ? OP_JBIN_LT + (op - OP_LT) : OP_BIN_ADD + (op - OP_ADD)); emit(f, ka << 8 | kb << 12); emit(f, ia); emit(f, ib);
  f->depth = d0;
  if (jump < 0) { adj(f, 1); return -1; }
  int site = here(f); emit(f, 0);
  return site;
}

static int isComparison(Fc *f, Node *c) {
  if (c->kind != N_LIST || c->n != 3 || c->kids[0]->kind != N_SYM) return 0;
  int s = c->kids[0]->sym, op = opFor(symName(s));
  return op >= OP_LT && op <= OP_NEQ && findLocal(f, s) < 0 && findCap(f, s) < 0 && !moduleDef(f->m, s);
}

static void ifForm(Fc *f, Node *c, Node *a, Node *b, int negate, int tail) {
  int j1;
  if (!negate && isComparison(f, c)) j1 = binary(f, (uint32_t)opFor(symName(c->kids[0]->sym)), c->kids[1], c->kids[2], 1);
  else {
    expr(f, c, 0);
    if (negate) emit(f, OP_NOT);
    emit(f, OP_JF); j1 = here(f); emit(f, 0); adj(f, -1);
  }
  int d0 = f->depth;
  if (a) expr(f, a, tail); else emitUnit(f);
  emit(f, OP_JMP); int j2 = here(f); emit(f, 0);
  patch(f, j1); f->depth = d0;
  if (b) expr(f, b, tail); else emitUnit(f);
  patch(f, j2);
}

static void whenForm(Fc *f, Node *n, int negate, int tail) {
  if (n->n < 2) { diag(f->d, f->m->path, n, "ERR_ARITY", "%s needs a condition", negate ? "unless" : "when"); emitUnit(f); return; }
  expr(f, n->kids[1], 0);
  if (negate) emit(f, OP_NOT);
  emit(f, OP_JF); int j1 = here(f); emit(f, 0); adj(f, -1);
  int d0 = f->depth;
  seq(f, n->kids + 2, n->n - 2, tail);
  emit(f, OP_JMP); int j2 = here(f); emit(f, 0);
  patch(f, j1); f->depth = d0; emitUnit(f);
  patch(f, j2);
}

/* isS(t, S_ELSE) is the only else recognized here; defense-in-depth, not a gate of its own, since typeCheckModule always runs first and rejects a non-Bool cond test, including through a local-variable call (CHECKER-localCallReturnBool), before OP_JF ever sees one -- U4.condKeywordCheck/U4.condRuntimeBool in run.sh cover the claim this rests on */
static void condForm(Fc *f, Node *n, int tail) {
  int ends[512], ne = 0, d0 = f->depth, closed = 0;
  for (int i = 1; i < n->n && !closed; i++) {
    Node *cl = n->kids[i];
    if (cl->kind != N_LIST || cl->n < 1) { diag(f->d, f->m->path, cl, "ERR_BAD_COND", "cond clause is not (test body)"); continue; }
    Node *t = cl->kids[0];
    f->depth = d0;
    if (isS(t, S_ELSE)) { seq(f, cl->kids + 1, cl->n - 1, tail); closed = 1; break; }
    expr(f, t, 0);
    emit(f, OP_JF); int j = here(f); emit(f, 0); adj(f, -1);
    seq(f, cl->kids + 1, cl->n - 1, tail);
    emit(f, OP_JMP); if (ne < 512) ends[ne++] = here(f); emit(f, 0);
    patch(f, j);
  }
  if (!closed) { f->depth = d0; emitUnit(f); }
  for (int i = 0; i < ne; i++) patch(f, ends[i]);
  f->depth = d0 + 1;
}

static void logic(Fc *f, Node *n, int op) {
  if (n->n == 1) { emitConst(f, vbool(op == OP_ANDJ)); return; }
  int ends[512], ne = 0;
  for (int i = 1; i < n->n; i++) {
    expr(f, n->kids[i], 0);
    if (i < n->n - 1) { emit(f, (uint32_t)op); if (ne < 512) ends[ne++] = here(f); emit(f, 0); adj(f, -1); }
    else emit(f, OP_CHKBOOL);
  }
  for (int i = 0; i < ne; i++) patch(f, ends[i]);
}

static int isLiteralPat(Node *p) {
  return p->kind == N_INT || p->kind == N_FLOAT || p->kind == N_STR || (p->kind == N_KW && p->sym != S_ELSE) || isS(p, S_TRUE) || isS(p, S_FALSE);
}
static Val literalVal(Node *p) {
  switch (p->kind) {
    case N_INT: return vint(p->i);
    case N_FLOAT: return vfloat(p->f);
    case N_STR: return mkStrPerm(p->s, p->len);
    case N_KW: return vkw(p->sym);
    default: return vbool(p->sym == S_TRUE);
  }
}
/* *ctor is the constructor's own name, so alias/member builds and matches the same value as the bare name */
static int ctorArityOf(Fc *f, Node *at, int name, int *enumId, int *ctor) {
  Module *owner; Def *df = lookupDef(f, at, name, &owner);
  *enumId = -1; *ctor = name;
  if (df && df->kind == DEF_CTOR) { *enumId = df->enumId; *ctor = df->name; return df->arity; }
  return builtinCtorArity(name);
}

/* a match on the builtin (listHead xs) or (listTail xs) whose arms are only (some x), none and _ tests the list
   itself, as the native lowering's @listrt.headOr/tailOr helpers do, so a list walk builds no Option per step;
   answers 1 for listHead, 2 for listTail, 0 when the match must see the Option */
static int listOptionMatch(Fc *f, Node *n) {
  Node *s = n->kids[1]; Module *owner;
  if (s->kind != N_LIST || s->n != 2 || s->kids[0]->kind != N_SYM) return 0;
  int h = s->kids[0]->sym; const char *name = symName(h);
  if (strcmp(name, "listHead") && strcmp(name, "listTail")) return 0;
  if (findLocal(f, h) >= 0 || findCap(f, h) >= 0 || defLookup(f->m, h, &owner)) return 0;
  const Builtin *b = moduleBuiltin(f->m, name);
  if (!b || strcmp(b->name, name)) return 0;
  for (int i = 2; i < n->n; i++) {
    Node *arm = n->kids[i], *p;
    if (arm->kind != N_LIST || arm->n < 1) return 0;
    p = arm->kids[0];
    if (isS(p, S_UNDERSCORE) || isS(p, S_ELSE)) continue;
    if ((isS(p, KW_NONE) || (p->kind == N_LIST && p->n == 1 && isS(p->kids[0], KW_NONE))) && !defLookup(f->m, KW_NONE, &owner)) continue;
    if (p->kind == N_LIST && p->n == 2 && isS(p->kids[0], KW_SOME) && p->kids[1]->kind == N_SYM && !defLookup(f->m, KW_SOME, &owner)) continue;
    return 0;
  }
  return name[4] == 'T' ? 2 : 1;
}

/* (mt (listHead xs) ((some x) (mt (listTail xs) ((some t) ...)) ...) ...): the inner match tests the same local list
   slot, so OP_LUNCONS can push both matches' scrutinees and fields at once */
static int unconsInner(Fc *f, Node *in, int slot) {
  if (in->kind != N_LIST || in->n < 3 || in->kids[0]->kind != N_SYM) return 0;
  int h = in->kids[0]->sym;
  if ((h != S_MATCH && h != S_MT) || findLocal(f, h) >= 0 || findCap(f, h) >= 0 || listOptionMatch(f, in) != 2) return 0;
  Node *s = in->kids[1], *p0 = in->kids[2]->kids[0];
  return s->kids[1]->kind == N_SYM && findLocal(f, s->kids[1]->sym) == slot && p0->kind == N_LIST && p0->n == 2;
}

static void matchForm(Fc *f, Node *n, int tail) {
  if (n->n < 2) { diag(f->d, f->m->path, n, "ERR_BAD_MATCH", "match without a subject"); emitUnit(f); return; }
  int fused = listOptionMatch(f, n), lslot = -1, unconsed = 0;
  if (f->unconsNode == n) { unconsed = 1; f->unconsNode = NULL; }
  if (fused) {
    Node *s = n->kids[1];
    noteBuiltin(f, s->kids[0], s, moduleBuiltin(f->m, symName(s->kids[0]->sym)));
    /* TESTCONS and TESTNIL check the list themselves; a leading catch-all arm needs the check on its own */
    Node *p0 = n->n > 2 && n->kids[2]->n >= 1 ? n->kids[2]->kids[0] : NULL;
    int catchAll = !p0 || isS(p0, S_UNDERSCORE) || isS(p0, S_ELSE);
    /* a local list under a leading (some x) arm: LTESTCONS pushes it and tests it in one dispatch */
    if (!catchAll && p0->kind == N_LIST && p0->n == 2 && s->kids[1]->kind == N_SYM) lslot = findLocal(f, s->kids[1]->sym);
    if (lslot >= 0) adj(f, 1); else expr(f, s->kids[1], 0);
    if (catchAll) { emit(f, OP_CHKLIST); emit(f, (uint32_t)(fused - 1)); }
  } else expr(f, n->kids[1], 0);
  int d0 = f->depth, scrut = d0 - 1, ends[512], ne = 0, open = 1, enumId = -1, used[256], nused = 0, family = matchFamily(f->m, n);
  for (int i = 2; i < n->n && open; i++) {
    Node *arm = n->kids[i];
    if (arm->kind != N_LIST || arm->n < 1) { diag(f->d, f->m->path, arm, "ERR_BAD_MATCH", "arm is not (pattern body)"); continue; }
    Node *p = arm->kids[0];
    int saved = f->nloc, nb = 0, jnext = -1, eid, ctor;
    f->depth = d0;
    if (isS(p, S_UNDERSCORE) || isS(p, S_ELSE)) open = 0;
    else if (p->kind == N_KW && p->sym == S_ELSE) { diag(f->d, f->m->path, p, "ERR_ELSE_KEYWORD", "mt pattern :else is a keyword literal, not the catch-all; use else or _"); continue; }
    else if (fused && (p->kind == N_SYM || p->n == 1)) { emit(f, OP_TESTNIL); emit(f, (uint32_t)(fused - 1)); jnext = here(f); emit(f, 0); }
    else if (fused) {
      adj(f, 1); nb = 1;
      if (p->kids[1]->sym != S_UNDERSCORE) bindLocal(f, p->kids[1]->sym, d0);
      if (unconsed && i == 2) {}  /* the enclosing match's OP_LUNCONS pushed this list and its tail already */
      else {
        if (lslot >= 0 && i == 2 && fused == 1 && arm->n == 2 && unconsInner(f, arm->kids[1], lslot)) {
          emit(f, OP_LUNCONS); emit(f, (uint32_t)lslot); f->unconsNode = arm->kids[1];
        } else {
          if (lslot >= 0 && i == 2) { emit(f, OP_LTESTCONS); emit(f, (uint32_t)lslot); }
          else emit(f, OP_TESTCONS);
          emit(f, (uint32_t)(fused - 1));
        }
        jnext = here(f); emit(f, 0);
      }
    } else if (isLiteralPat(p)) { emit(f, OP_TESTLIT); emit(f, (uint32_t)addConst(f, literalVal(p))); jnext = here(f); emit(f, 0); }
    else if (ctorPattern(f->m, p, family) && ctorArityOf(f, p, p->sym, &eid, &ctor) >= 0) {
      emit(f, OP_TESTCTOR); emit(f, (uint32_t)ctor); emit(f, 0); jnext = here(f); emit(f, 0);
      if (eid >= 0) enumId = eid;
      if (nused < 256) used[nused++] = ctor;
    } else if (p->kind == N_SYM) {
      emit(f, OP_LOCAL); emit(f, (uint32_t)scrut); adj(f, 1); bindLocal(f, p->sym, f->depth - 1); nb = 1; open = 0;
    } else if (p->kind == N_LIST && p->n >= 1 && p->kids[0]->kind == N_SYM) {
      int k = p->n - 1;
      if (ctorArityOf(f, p->kids[0], p->kids[0]->sym, &eid, &ctor) < 0) unknown(f, p->kids[0], p->kids[0]->sym);
      if (eid >= 0) enumId = eid;
      if (nused < 256) used[nused++] = ctor;
      emit(f, OP_TESTCTOR); emit(f, (uint32_t)ctor); emit(f, (uint32_t)k); jnext = here(f); emit(f, 0);
      adj(f, k); nb = k;
      for (int j = 0; j < k; j++) {
        Node *q = p->kids[j + 1];
        if (q->kind != N_SYM) diag(f->d, f->m->path, q, "ERR_BAD_PATTERN", "nested patterns bind names only");
        else if (q->sym != S_UNDERSCORE) bindLocal(f, q->sym, d0 + j);
      }
    } else { diag(f->d, f->m->path, p, "ERR_BAD_PATTERN", "unsupported pattern"); continue; }
    seq(f, arm->kids + 1, arm->n - 1, tail);
    if (nb) { emit(f, OP_SLIDE); emit(f, (uint32_t)nb); adj(f, -nb); }
    emit(f, OP_JMP); if (ne < 512) ends[ne++] = here(f); emit(f, 0);
    if (jnext >= 0) patch(f, jnext);
    f->nloc = saved;
  }
  if (open && fused) { emit(f, OP_OPTWRAP); emit(f, (uint32_t)(fused - 1)); }
  if (open) emit(f, OP_NOMATCH);
  for (int i = 0; i < ne; i++) patch(f, ends[i]);
  f->depth = d0 + 1;
  emit(f, OP_SLIDE); emit(f, 1); adj(f, -1);
  if (f->d->checkMode && open && enumId >= 0) {
    char miss[512]; size_t mn = 0; miss[0] = 0;
    EnumDef *e = &enums[enumId];
    for (int v = 0; v < e->nvariants; v++) {
      int seen = 0;
      for (int u = 0; u < nused; u++) if (used[u] == e->variants[v]) seen = 1;
      if (!seen && mn + strlen(symName(e->variants[v])) + 2 < sizeof miss) mn += (size_t)snprintf(miss + mn, sizeof miss - mn, "%s%s", mn ? " " : "", symName(e->variants[v]));
    }
    if (mn) diag(f->d, f->m->path, n, "ERR_MATCH_NONEXHAUSTIVE", "match over enum %s misses variant(s): %s", symName(e->name), miss);
  }
}

static void arityDiag(Fc *f, Node *at, int name, int want, int got) {
  if (f->d->checkMode && want >= 0 && want != got)
    diag(f->d, f->m->path, at, "ERR_ARITY", "%s expects %d argument(s), got %d", symName(name), want, got);
}

/* D152: an assert or refute condition must depend on a computed value. A condition folds to a constant when it is
   built only from literals, from let names bound directly to literals, and from the operators = != < > <= >= + - * /
   mod not and or; bare (assert false) and (refute true) stay legal failure markers, and a bare non-Bool literal is
   left to the runtime ERR_TYPE, since neither can pass. A fn whose header has a
   ; (:m :tags (hostSubject)) line directly above tests the reader or literal arithmetic itself and may fold. The
   walk is iterative over a heap stack capped at CONST_WALK_MAX nodes, so no condition can exhaust the C stack. */
#define CONST_WALK_MAX (1 << 20)
static int isLiteral(Node *n) {
  return n->kind == N_INT || n->kind == N_FLOAT || n->kind == N_STR || n->kind == N_KW ||
         (n->kind == N_SYM && (n->sym == S_TRUE || n->sym == S_FALSE));
}
static int isFoldingOp(Fc *f, Node *h) {
  if (h->kind != N_SYM || findLocal(f, h->sym) >= 0 || findCap(f, h->sym) >= 0) return 0;
  if (h->sym == S_NOT || h->sym == S_AND || h->sym == S_OR) return 1;
  return opFor(symName(h->sym)) >= 0 && !moduleDef(f->m, h->sym);
}
/* 1 constant, 0 depends on a computed value, -1 larger than CONST_WALK_MAX nodes */
static int foldsToConstant(Fc *f, Node *cond) {
  Node **stk = NULL; int sp = 0, cap = 0, r = 1;
  for (Node *x = cond; x; x = sp ? stk[--sp] : NULL) {
    Local *l;
    if (isLiteral(x) || (x->kind == N_SYM && (l = findLocalEntry(f, x->sym)) && l->lit)) continue;
    int from, to;
    if (x->kind == N_LIST && x->n >= 2 && isFoldingOp(f, x->kids[0])) { from = 1; to = x->n; }
    else if ((x->kind == N_VEC || x->kind == N_MAP) && x->n >= 1) { from = 0; to = x->n; }
    else { r = 0; break; }
    if (sp + (to - from) > CONST_WALK_MAX) { r = -1; break; }
    if (sp + (to - from) > cap) {
      while (cap < sp + (to - from)) cap = cap ? cap * 2 : 32;
      Node **grown = realloc(stk, sizeof(Node *) * (size_t)cap);
      if (!grown) exit(70);
      stk = grown;
    }
    for (int i = from; i < to; i++) stk[sp++] = x->kids[i];
  }
  free(stk);
  return r;
}
static int hostSubject(Fc *f) {
  Unit *u = &f->m->unit;
  for (int i = 0; i < u->ntags; i++) if (u->tagLines[i] == f->topLine - 1 && u->tagSyms[i] == S_HOSTSUBJECT) return 1;
  return 0;
}
static void constantAssert(Fc *f, int isAssert, Node *cond) {
  const char *name = isAssert ? "assert" : "refute";
  if (cond->kind == N_SYM && cond->sym == (isAssert ? S_FALSE : S_TRUE)) return;
  if (cond->kind == N_SYM && (cond->sym == S_TRUE || cond->sym == S_FALSE)) {
    diag(f->d, f->m->path, cond, "ERR_CONSTANT_ASSERT", "%s %s can never fail; test a computed value (D152)", name, symName(cond->sym));
    return;
  }
  /* a bare Int Float String or Keyword can never pass: the runtime rejects it as ERR_TYPE */
  if (cond->kind == N_INT || cond->kind == N_FLOAT || cond->kind == N_STR || cond->kind == N_KW) return;
  int r = foldsToConstant(f, cond);
  if (r < 0) diag(f->d, f->m->path, cond, "ERR_DEPTH", "%s condition larger than %d nodes", name, CONST_WALK_MAX);
  else if (r && f->topLine > 0 && hostSubject(f)) return;
  else if (r) diag(f->d, f->m->path, cond, "ERR_CONSTANT_ASSERT", "%s condition folds to a constant; test a computed value (D152)", name);
}

static void args(Fc *f, Node *n) { for (int i = 1; i < n->n; i++) expr(f, n->kids[i], 0); }

/* (with x :k v ...): a copy of record x with the named fields replaced */
static void withForm(Fc *f, Node *n) {
  int argc = n->n - 1, keys[256], nk = 0;
  if (argc < 3 || argc % 2 == 0) { diag(f->d, f->m->path, n, "ERR_ARITY", "with takes a record and :field value pairs"); emitUnit(f); return; }
  expr(f, n->kids[1], 0);
  for (int i = 2; i + 1 < n->n; i += 2) {
    Node *k = n->kids[i];
    if (k->kind != N_KW) { diag(f->d, f->m->path, k, "ERR_BAD_WITH", "with takes :field value pairs after the record"); continue; }
    int dup = 0;
    for (int j = 0; j < nk; j++) dup |= keys[j] == k->sym;
    if (dup) { diag(f->d, f->m->path, k, "ERR_BAD_WITH", "with names field %s twice", symName(k->sym)); continue; }
    if (nk == 256) { diag(f->d, f->m->path, k, "ERR_LIMIT", "with replaces at most 256 fields"); break; }
    keys[nk++] = k->sym; expr(f, n->kids[i + 1], 0);
  }
  emit(f, OP_WITH); emit(f, (uint32_t)nk);
  for (int i = 0; i < nk; i++) emit(f, (uint32_t)keys[i]);
  adj(f, -nk);
}

static void call(Fc *f, Node *n, int tail) {
  Node *h = n->kids[0]; int argc = n->n - 1;
  if (h->kind == N_SYM && findLocal(f, h->sym) < 0 && findCap(f, h->sym) < 0) {
    int s = h->sym; const char *name = symName(s); int op;
    if (s == S_IF) { if (n->n < 3 || n->n > 4) { diag(f->d, f->m->path, n, "ERR_ARITY", "if takes 2 or 3 operands"); emitUnit(f); return; } ifForm(f, n->kids[1], n->kids[2], n->n == 4 ? n->kids[3] : NULL, 0, tail); return; }
    if (s == S_WHEN || s == S_UNLESS) { whenForm(f, n, s == S_UNLESS, tail); return; }
    if (s == S_COND) { condForm(f, n, tail); return; }
    if (s == S_AND) { logic(f, n, OP_ANDJ); return; }
    if (s == S_OR) { logic(f, n, OP_ORJ); return; }
    if (s == S_NOT) { if (argc != 1) { diag(f->d, f->m->path, n, "ERR_ARITY", "not takes 1 operand"); emitUnit(f); return; } expr(f, n->kids[1], 0); emit(f, OP_NOT); return; }
    if (s == S_DO || s == S_BEGIN) { seq(f, n->kids + 1, argc, tail); return; }
    if (s == S_LET) { letForm(f, n, tail); return; }
    if (s == S_WITH && !moduleDef(f->m, s)) { withForm(f, n); return; }
    if (s == S_FN || s == S_LAMBDA) { lambda(f, n); return; }
    if (s == S_MATCH || s == S_MT) { matchForm(f, n, tail); return; }
    if (s == S_ASSERT || s == S_REFUTE) {
      if (argc < 1 || argc > 2) { diag(f->d, f->m->path, n, "ERR_ARITY", "%s takes a condition and an optional message", name); emitUnit(f); return; }
      constantAssert(f, s == S_ASSERT, n->kids[1]);
      expr(f, n->kids[1], 0);
      if (argc == 2) expr(f, n->kids[2], 0); else emitUnit(f);
      /* the source line and column follow, so a failing assert or refute names its site */
      emit(f, s == S_ASSERT ? OP_ASSERT : OP_REFUTE); emit(f, (uint32_t)n->line); emit(f, (uint32_t)(n->col + 1)); adj(f, -1); return;
    }
    if (name[0] == '.' && name[1] == '-' && name[2]) {
      if (argc != 1) { diag(f->d, f->m->path, n, "ERR_ARITY", "%s takes 1 operand", name); emitUnit(f); return; }
      expr(f, n->kids[1], 0); emit(f, OP_FIELD); emit(f, (uint32_t)intern(name + 2, strlen(name + 2))); return;
    }
    if ((op = opFor(name)) >= 0 && !moduleDef(f->m, s)) {
      if (argc == 1 && op == OP_SUB) { expr(f, n->kids[1], 0); emit(f, OP_NEG); return; }
      if (argc == 1 && (op == OP_ADD || op == OP_MUL)) { expr(f, n->kids[1], 0); return; }
      if (argc < 2 || (argc > 2 && op != OP_ADD && op != OP_MUL)) {
        diag(f->d, f->m->path, n, "ERR_ARITY", "%s takes 2 operands, got %d", name, argc);
        args(f, n); for (int i = 0; i < argc; i++) { emit(f, OP_POP); adj(f, -1); }
        emitUnit(f); return;
      }
      binary(f, (uint32_t)op, n->kids[1], n->kids[2], -1);
      for (int i = 3; i <= argc; i++) { expr(f, n->kids[i], 0); emit(f, (uint32_t)op); adj(f, -1); }
      return;
    }
    Module *owner; Def *df = lookupDef(f, h, s, &owner);
    if (df && df->kind == DEF_FN) {
      noteFn(f, h, df, owner);
      arityDiag(f, n, s, df->arity, argc);
      /* a self tail call of a top-level fn rebinds its parameters in place, reading local and literal arguments
         straight from their slots */
      if (tail && !f->up && df == f->fnDef && argc == f->p->nparams && argc <= MAX_TSELF_ARGS) {
        int d0 = f->depth, ns = 0, nm = 0, gather = 0; uint32_t at[MAX_TSELF_ARGS];
        for (int i = 0; i < argc; i++) {
          uint32_t idx, k = operand(f, n->kids[i + 1], &idx);
          ns += !k;
          if (k == 1 && idx == (uint32_t)i) continue;  /* the parameter passes itself on: no move */
          if (k == 1 && idx < (uint32_t)argc) gather = 1;  /* reads a parameter a move may already have replaced */
          if (idx > TSELF_INDEX) aslError("ERR_LIMIT", "%s: self call operand index %u exceeds %u", f->p->name, idx, (unsigned)TSELF_INDEX);
          at[nm++] = k << 30 | (uint32_t)i << 27 | idx;
        }
        emit(f, OP_TSELF); emit(f, (uint32_t)(nm | ns << 8 | argc << 16 | gather << 24));
        for (int i = 0; i < nm; i++) emit(f, at[i]);
        f->depth = d0; adj(f, 1); return;
      }
      args(f, n); emit(f, tail ? OP_TCALLG : OP_CALLG); emit(f, (uint32_t)df->gidx); emit(f, (uint32_t)argc); adj(f, 1 - argc); return;
    }
    int ca = df && df->kind == DEF_CTOR ? df->arity : builtinCtorArity(s);
    if (ca >= 0 && (!df || df->kind == DEF_CTOR)) {
      arityDiag(f, n, s, ca, argc);
      args(f, n); emit(f, OP_MKCTOR); emit(f, (uint32_t)(df ? df->name : s)); emit(f, (uint32_t)argc); emit(f, (uint32_t)ca); adj(f, 1 - argc); return;
    }
    if (df && df->kind == DEF_SCHEMA) {
      int keys[256], nk = 0;
      for (int i = 1; i + 1 < n->n && nk < 256; i += 2) {
        if (n->kids[i]->kind != N_KW) { diag(f->d, f->m->path, n->kids[i], "ERR_BAD_CONSTRUCTOR", "%s takes :field value pairs", name); break; }
        keys[nk++] = n->kids[i]->sym; expr(f, n->kids[i + 1], 0);
      }
      if (argc % 2) diag(f->d, f->m->path, n, "ERR_BAD_CONSTRUCTOR", "%s: odd field list", name);
      if (df->nfields > 0) {
        for (int fi = 0; fi < df->nfields && nk < 256; fi++) {
          int fsym = df->fields[fi];
          int found = 0;
          for (int ki = 0; ki < nk; ki++) if (keys[ki] == fsym) { found = 1; break; }
          if (found) continue;
          /* the default lives in the schema's own module: call its precompiled thunk rather than
             inlining the expression here, so a private module fn it names resolves there, not
             in this constructor call site's (possibly importing) module */
          if (df->defaultGidx && df->defaultGidx[fi] >= 0) {
            keys[nk++] = fsym;
            emit(f, OP_CALLG); emit(f, (uint32_t)df->defaultGidx[fi]); emit(f, 0); adj(f, 1);
          }
        }
      }
      emit(f, OP_MKREC); emit(f, (uint32_t)s); emit(f, (uint32_t)nk);
      for (int i = 0; i < nk; i++) emit(f, (uint32_t)keys[i]);
      adj(f, 1 - nk); return;
    }
    const Builtin *b = moduleBuiltin(f->m, name);
    if (b) noteBuiltin(f, h, n, b);
    if (!b && nativeOnlyBuiltin(name)) noteNativeBuiltin(f, h, name);
    if (b && argc == 1 && !strcmp(name, "int64ToFloat64")) { expr(f, n->kids[1], 0); emit(f, OP_I2F); return; }
    if (b && argc == 2 && !strcmp(b->name, "cons")) {
      /* local and literal operands are addressed in the instruction, as for OP_BIN */
      int d0 = f->depth; uint32_t ia, ib, ka = operand(f, n->kids[1], &ia), kb = operand(f, n->kids[2], &ib);
      emit(f, OP_CONS); emit(f, ka << 8 | kb << 12); emit(f, ia); emit(f, ib);
      f->depth = d0; adj(f, 1); return;
    }
    if (b) {
      arityDiag(f, n, s, b->arity, argc);
      args(f, n); emit(f, OP_BUILTIN); emit(f, (uint32_t)builtinIndex(b)); emit(f, (uint32_t)argc); adj(f, 1 - argc); return;
    }
    if (nativeOnlyBuiltin(name)) {
      arityDiag(f, n, s, nativeOnlyArity(name), argc);
      args(f, n); emit(f, OP_BUILTIN); emit(f, nativeOnlyCode(name)); emit(f, (uint32_t)argc); adj(f, 1 - argc); return;
    }
    unknown(f, h, s);
    args(f, n); for (int i = 0; i < argc; i++) { emit(f, OP_POP); adj(f, -1); }
    emitUnit(f);
    return;
  }
  expr(f, h, 0); args(f, n);
  emit(f, tail ? OP_TCALL : OP_CALL); emit(f, (uint32_t)argc); adj(f, -argc);
}

#define MAX_NEST 1000
static int nest;
static void exprInner(Fc *f, Node *n, int tail);
/* source nesting is bounded so the recursive compiler never exhausts the C stack */
static void expr(Fc *f, Node *n, int tail) {
  if (nest >= MAX_NEST) {
    if (nest++ == MAX_NEST) diag(f->d, f->m->path, n, "ERR_DEPTH", "expression nested deeper than %d", MAX_NEST);
    nest--; emitUnit(f); return;
  }
  nest++; exprInner(f, n, tail); nest--;
}

static void exprInner(Fc *f, Node *n, int tail) {
  switch (n->kind) {
    case N_INT:
      if (n->outOfRange) diag(f->d, f->m->path, n, "ERR_INT_RANGE", "integer literal outside int64");
      emitConst(f, vint(n->i)); return;
    case N_FLOAT: emitConst(f, vfloat(n->f)); return;
    case N_STR: emitConst(f, mkStrPerm(n->s, n->len)); return;
    case N_KW: emitConst(f, vkw(n->sym)); return;
    case N_SYM: symbol(f, n); return;
    case N_VEC:
      for (int i = 0; i < n->n; i++) expr(f, n->kids[i], 0);
      emit(f, OP_MKLIST); emit(f, (uint32_t)n->n); adj(f, 1 - n->n); return;
    case N_MAP: {
      int nk = 0; int *keys = malloc(sizeof(int) * (size_t)(n->n / 2 + 1));
      if (!keys) exit(70);
      for (int i = 0; i + 1 < n->n; i += 2) {
        if (n->kids[i]->kind != N_KW) { diag(f->d, f->m->path, n->kids[i], "ERR_BAD_RECORD", "record key is not a keyword"); continue; }
        keys[nk++] = n->kids[i]->sym; expr(f, n->kids[i + 1], 0);
      }
      emit(f, OP_MKREC); emit(f, (uint32_t)-1); emit(f, (uint32_t)nk);
      for (int i = 0; i < nk; i++) emit(f, (uint32_t)keys[i]);
      free(keys); adj(f, 1 - nk); return;
    }
    case N_LIST:
      if (n->n == 0) { emitUnit(f); return; }
      call(f, n, tail); return;
    default: diag(f->d, f->m->path, n, "ERR_BAD_FORM", "unexpected form"); emitUnit(f); return;
  }
}

static Proto *body(Module *m, Diags *d, Def *df, const char *name, int *params, int np, Node **forms, int nf, int topLine) {
  Fc *f = calloc(1, sizeof(Fc));
  if (!f) exit(70);
  f->m = m; f->d = d; f->p = newProto(name, m->path); f->lastBin = f->pushAt = f->label = -1; f->topLine = topLine; f->fnDef = df;
  for (int i = 0; i < np; i++) bindLocal(f, params[i], i);
  f->p->nparams = np; f->depth = np; f->p->maxstack = np;
  seq(f, forms, nf, 1);
  emitRet(f);
  Proto *p = f->p; free(f);
  return p;
}

static int tailrecShadowDepth;
static int tailrecPatternShadows(Module *m, Node *p, int targetSym, int family) {
  Module *owner; Def *df;
  if (p->kind == N_SYM) return p->sym == targetSym && !ctorPattern(m, p, family);
  if (p->kind != N_LIST || p->n < 1 || p->kids[0]->kind != N_SYM) return 0;
  df = defLookup(m, p->kids[0]->sym, &owner);
  if (!(df && df->kind == DEF_CTOR) && builtinCtorArity(p->kids[0]->sym) < 0) return 0;
  int shadows = 0;
  for (int i = 1; i < p->n; i++)
    if (p->kids[i]->kind == N_SYM && p->kids[i]->sym == targetSym) shadows++;
  return shadows;
}
static void checkTailrecNode(Module *m, Diags *d, int targetSym, Node *n, int tail) {
  if (!n) return;
  if (n->kind == N_GROUP) {
    for (int i = 0; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], tail && (i == n->n - 1));
    return;
  }
  if (n->kind == N_VEC || n->kind == N_MAP) {
    for (int i = 0; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], 0);
    return;
  }
  if (n->kind != N_LIST || n->n == 0) return;

  Node *h = n->kids[0];
  if (h->kind != N_SYM) {
    for (int i = 0; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], 0);
    return;
  }

  int s = h->sym;
  if (s == S_IF) {
    if (n->n >= 2) checkTailrecNode(m, d, targetSym, n->kids[1], 0);
    if (n->n >= 3) checkTailrecNode(m, d, targetSym, n->kids[2], tail);
    if (n->n >= 4) checkTailrecNode(m, d, targetSym, n->kids[3], tail);
    return;
  }
  if (s == S_WHEN || s == S_UNLESS) {
    if (n->n >= 2) checkTailrecNode(m, d, targetSym, n->kids[1], 0);
    for (int i = 2; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], tail && (i == n->n - 1));
    return;
  }
  if (s == S_COND) {
    for (int i = 1; i < n->n; i++) {
      Node *cl = n->kids[i];
      if (cl->kind != N_LIST || cl->n < 1) continue;
      Node *t = cl->kids[0];
      if (isS(t, S_ELSE)) {
        for (int j = 1; j < cl->n; j++)
          checkTailrecNode(m, d, targetSym, cl->kids[j], tail && (j == cl->n - 1));
      } else {
        checkTailrecNode(m, d, targetSym, t, 0);
        for (int j = 1; j < cl->n; j++)
          checkTailrecNode(m, d, targetSym, cl->kids[j], tail && (j == cl->n - 1));
      }
    }
    return;
  }
  if (s == S_DO || s == S_BEGIN) {
    for (int i = 1; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], tail && (i == n->n - 1));
    return;
  }
  if (s == S_LET) {
    int priorShadowDepth = tailrecShadowDepth;
    if (n->n >= 2) {
      Node *bs = n->kids[1];
      if (bs->kind == N_VEC || bs->kind == N_LIST) {
        int pairs = bs->n > 0 && bs->kids[0]->kind == N_LIST;
        for (int i = 0; i < bs->n; i += pairs ? 1 : 2) {
          Node *binding = pairs ? bs->kids[i] : (i + 1 < bs->n ? bs->kids[i] : NULL);
          Node *name = binding && binding->kind == N_LIST && binding->n > 0 ? binding->kids[0] : binding;
          Node *val = pairs ? (bs->kids[i]->kind == N_LIST && bs->kids[i]->n >= 2 ? bs->kids[i]->kids[bs->kids[i]->n - 1] : NULL)
                            : (i + 1 < bs->n ? bs->kids[i + 1] : NULL);
          if (val) checkTailrecNode(m, d, targetSym, val, 0);
          if (name && name->kind == N_SYM && name->sym == targetSym) tailrecShadowDepth++;
        }
      }
    }
    for (int i = 2; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], tail && (i == n->n - 1));
    tailrecShadowDepth = priorShadowDepth;
    return;
  }
  if (s == S_MATCH || s == S_MT) {
    if (n->n >= 2) checkTailrecNode(m, d, targetSym, n->kids[1], 0);
    int family = matchFamily(m, n);
    for (int i = 2; i < n->n; i++) {
      Node *arm = n->kids[i];
      if (arm->kind != N_LIST || arm->n < 1) continue;
      int priorShadowDepth = tailrecShadowDepth;
      tailrecShadowDepth += tailrecPatternShadows(m, arm->kids[0], targetSym, family);
      for (int j = 1; j < arm->n; j++)
        checkTailrecNode(m, d, targetSym, arm->kids[j], tail && (j == arm->n - 1));
      tailrecShadowDepth = priorShadowDepth;
    }
    return;
  }
  if (s == S_FN || s == S_LAMBDA) {
    int priorShadowDepth = tailrecShadowDepth;
    if (n->n >= 2 && (n->kids[1]->kind == N_VEC || n->kids[1]->kind == N_LIST)) {
      Node *params = n->kids[1];
      for (int i = 0; i < params->n; i++) {
        Node *q = params->kids[i];
        if ((q->kind == N_SYM && q->sym == targetSym) || (q->kind == N_LIST && q->n && q->kids[0]->kind == N_SYM && q->kids[0]->sym == targetSym)) tailrecShadowDepth++;
      }
    }
    for (int i = 2; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], 0);
    tailrecShadowDepth = priorShadowDepth;
    return;
  }
  if (s == S_AND || s == S_OR) {
    for (int i = 1; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], 0);
    return;
  }
  if (s == targetSym && tailrecShadowDepth == 0) {
    if (!tail) {
      diag(d, m->path, n, "ERR_NOT_TAIL", "self-call in tailrec fn %s is not in tail position", symName(targetSym));
    }
    for (int i = 1; i < n->n; i++)
      checkTailrecNode(m, d, targetSym, n->kids[i], 0);
    return;
  }
  for (int i = 1; i < n->n; i++)
    checkTailrecNode(m, d, targetSym, n->kids[i], 0);
}

static void checkTailrecForms(Module *m, Diags *d, int targetSym, int *params, int nparams, Node **forms, int n) {
  tailrecShadowDepth = 0;
  for (int i = 0; i < nparams; i++)
    if (params[i] == targetSym) tailrecShadowDepth++;
  for (int i = 0; i < n; i++)
    checkTailrecNode(m, d, targetSym, forms[i], i == n - 1);
  tailrecShadowDepth = 0;
}

/* compiles one schema's pending :default expressions as zero-arg thunks, in this module's own
   scope, so a private module fn a default names resolves here and not at some importer's call site */
static void compileSchemaDefaults(Module *m, Diags *d, Def *df) {
  for (int fi = 0; fi < df->nfields; fi++) {
    if (df->defaultGidx[fi] < 0) continue;
    Node *e = df->defaultExpr[fi];
    Proto *p = body(m, d, NULL, symName(df->fields[fi]), NULL, 0, &e, 1, e->line);
    Closure *c = asl_alloc_perm(O_CLOSURE, sizeof(Closure));
    c->p = p; c->n = 0;
    globals[df->defaultGidx[fi]] = vobj(T_FN, c);
  }
}

void compileModule(Module *m, Diags *d) {
  initSyms();
  for (int i = 0; i < m->ndefs; i++) {
    Def *df = &m->defs[i];
    if (df->kind == DEF_SCHEMA) { compileSchemaDefaults(m, d, df); continue; }
    if (df->kind != DEF_FN) continue;
    Node *g = df->group; int params[256], nameAt, bodyAt;
    int np = fnSignature(g, &nameAt, params, 256, &bodyAt);
    if (np > 256) { diag(d, m->path, g, "ERR_LIMIT", "more than 256 parameters"); continue; }
    if (df->tailrec) {
      checkTailrecForms(m, d, df->name, params, np, g->kids + bodyAt, g->n - bodyAt);
    }
    Proto *p = body(m, d, df, symName(df->name), params, np, g->kids + bodyAt, g->n - bodyAt, g->line);
    Closure *c = asl_alloc_perm(O_CLOSURE, sizeof(Closure));
    c->p = p; c->n = 0;
    globals[df->gidx] = vobj(T_FN, c);
  }
  compileTops(m, d);
}

/* top-level expressions become one proto that runs them in order and discards their values */
static void compileTops(Module *m, Diags *d) {
  if (!m->ntops) return;
  Fc *f = calloc(1, sizeof(Fc));
  if (!f) exit(70);
  f->m = m; f->d = d; f->p = newProto("toplevel", m->path); f->lastBin = f->pushAt = f->label = -1;
  for (int i = 0; i < m->ntops; i++) { f->topLine = m->tops[i]->line; expr(f, m->tops[i], 0); emit(f, OP_POP); adj(f, -1); }
  emitUnit(f); emit(f, OP_RET);
  m->init = f->p; free(f);
}

Proto *compileExpr(Module *m, Node **forms, int n, Diags *d) {
  initSyms();
  return body(m, d, NULL, "eval", NULL, 0, forms, n, 0);
}
