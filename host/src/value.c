/* Values: interning, constructors, structural equality, printing, error exit path. */
#include "value.h"
#include <math.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char *s; size_t n; int id; } Sym;
static Sym *tab; static size_t tabCap;
static char **names; static int nnames, capnames;
int KW_SOME, KW_NONE, KW_OK, KW_ERR, KW_PARTIAL;

static uint64_t hashStr(const char *s, size_t n) {
  uint64_t h = 1469598103934665603ull;
  for (size_t i = 0; i < n; i++) { h ^= (unsigned char)s[i]; h *= 1099511628211ull; }
  return h;
}

int intern(const char *s, size_t n) {
  if ((size_t)nnames * 2 >= tabCap) {
    size_t nc = tabCap ? tabCap * 2 : 1024; Sym *nt = calloc(nc, sizeof(Sym));
    if (!nt) exit(70);
    for (size_t i = 0; i < tabCap; i++) if (tab[i].s) {
      size_t j = hashStr(tab[i].s, tab[i].n) & (nc - 1);
      while (nt[j].s) j = (j + 1) & (nc - 1);
      nt[j] = tab[i];
    }
    free(tab); tab = nt; tabCap = nc;
  }
  size_t j = hashStr(s, n) & (tabCap - 1);
  while (tab[j].s) {
    if (tab[j].n == n && !memcmp(tab[j].s, s, n)) return tab[j].id;
    j = (j + 1) & (tabCap - 1);
  }
  char *c = malloc(n + 1); if (!c) exit(70);
  memcpy(c, s, n); c[n] = 0;
  if (nnames == capnames) { capnames = capnames ? capnames * 2 : 1024; names = realloc(names, sizeof(char *) * capnames); if (!names) exit(70); }
  names[nnames] = c;
  tab[j] = (Sym){c, n, nnames};
  return nnames++;
}

const char *symName(int id) { return id >= 0 && id < nnames ? names[id] : "?"; }
int aslInternShared(const char *s, int64_t n) { return intern(s, (size_t)n); } const char *aslSymNameShared(int id) { return symName(id); }

Val mkCons(Val car, Val cdr) {
  asl_gc_root_push(&car); asl_gc_root_push(&cdr);
  Cons *c = asl_alloc_cons();
  asl_gc_root_pop(2);
  c->car = car; c->cdr = cdr;
  return vobj(T_LIST, c);
}

/* fields are zeroed (Unit); the caller fills them before any further allocation */
Val mkCtor(int ctor, int n) {
  Ctor *c = asl_alloc(O_CTOR, sizeof(Ctor) + sizeof(Val) * (size_t)n);
  c->ctor = ctor; c->n = n;
  return vobj(T_CTOR, c);
}

const char *tagName(Tag t) {
  static const char *n[] = {"Unit", "Bool", "Int", "Float", "Keyword", "String", "List", "Record", "Variant", "Fn", "Builtin", "Bytes", "F64Array", "I64Array", "I8Array", "Handle"};
  return (unsigned)t < sizeof n / sizeof n[0] ? n[t] : "?";
}

/* structural equality; Int versus Float and any other cross-type comparison is ERR_TYPE (I3) */
#define MAX_DATA_DEPTH 10000
static int eqDepth;
static int valEqInner(Val a, Val b);
/* nesting beyond MAX_DATA_DEPTH is ERR_DEPTH, never a C stack overflow */
int valEq(Val a, Val b) {
  if (eqDepth >= MAX_DATA_DEPTH) { eqDepth = 0; aslError("ERR_DEPTH", "= on values nested deeper than %d", MAX_DATA_DEPTH); }
  eqDepth++; int r = valEqInner(a, b); eqDepth--;
  return r;
}

static int valEqInner(Val a, Val b) {
  if (a.tag != b.tag) aslError("ERR_TYPE", "= compares %s with %s", tagName(a.tag), tagName(b.tag));
  switch (a.tag) {
    case T_UNIT: return 1;
    case T_BOOL: case T_INT: return a.u.i == b.u.i;
    case T_FLOAT: return a.u.f == b.u.f;
    case T_KW: return a.aux == b.aux;
    case T_STR: { Str *x = (Str *)a.u.o, *y = (Str *)b.u.o; return x->len == y->len && !memcmp(x->s, y->s, x->len); }
    case T_BYTES: { Arr *x = (Arr *)a.u.o, *y = (Arr *)b.u.o; return x->len == y->len && (!x->len || !memcmp(x->data, y->data, x->len)); }
    case T_LIST: {
      Obj *x = a.u.o, *y = b.u.o;
      while (x && y) { if (!valEq(((Cons *)x)->car, ((Cons *)y)->car)) return 0; x = ((Cons *)x)->cdr.u.o; y = ((Cons *)y)->cdr.u.o; }
      return x == y;
    }
    case T_CTOR: {
      Ctor *x = (Ctor *)a.u.o, *y = (Ctor *)b.u.o;
      if (x->ctor != y->ctor || x->n != y->n) return 0;
      for (int i = 0; i < x->n; i++) if (!valEq(x->f[i], y->f[i])) return 0;
      return 1;
    }
    case T_REC: {
      Rec *x = (Rec *)a.u.o, *y = (Rec *)b.u.o;
      if (x->n != y->n || x->schema != y->schema) return 0;
      for (int i = 0; i < x->n; i++) {
        int k; for (k = 0; k < y->n && y->keys[k] != x->keys[i]; k++) {}
        if (k == y->n || !valEq(x->v[i], y->v[k])) return 0;
      }
      return 1;
    }
    default: return a.u.o == b.u.o;
  }
}

typedef struct { char *b; size_t n, cap; } Buf;
static void bput(Buf *b, const char *s, size_t n) {
  if (b->n + n + 1 > b->cap) { while (b->n + n + 1 > b->cap) b->cap = b->cap ? b->cap * 2 : 64; b->b = realloc(b->b, b->cap); if (!b->b) exit(70); }
  memcpy(b->b + b->n, s, n); b->n += n; b->b[b->n] = 0;
}
static void bstr(Buf *b, const char *s) { bput(b, s, strlen(s)); }

/* limit < 0: nesting beyond MAX_DATA_DEPTH is ERR_DEPTH; limit >= 0: deeper parts print as ... (diagnostics) */
static void render(Buf *b, Val v, int repr, int depth, int limit) {
  char tmp[64];
  if (limit >= 0 && depth > limit) { bstr(b, "..."); return; }
  if (depth > MAX_DATA_DEPTH) { free(b->b); aslError("ERR_DEPTH", "printing a value nested deeper than %d", MAX_DATA_DEPTH); }
  switch (v.tag) {
    case T_UNIT: bstr(b, "()"); break;
    case T_BOOL: bstr(b, v.u.i ? "true" : "false"); break;
    case T_INT: snprintf(tmp, sizeof tmp, "%lld", (long long)v.u.i); bstr(b, tmp); break;
    case T_FLOAT: floatRepr(v.u.f, tmp); bstr(b, tmp); break;
    case T_KW: bstr(b, ":"); bstr(b, symName((int)v.aux)); break;
    case T_STR: {
      Str *s = (Str *)v.u.o;
      if (!repr) { bput(b, s->s, s->len); break; }
      bstr(b, "\"");
      for (size_t i = 0; i < s->len; i++) {
        char c = s->s[i];
        if (c == '"' || c == '\\') { bstr(b, "\\"); bput(b, &c, 1); }
        else if (c == '\n') bstr(b, "\\n");
        else if (c == '\t') bstr(b, "\\t");
        else bput(b, &c, 1);
      }
      bstr(b, "\"");
      break;
    }
    case T_LIST: {
      bstr(b, "(");
      for (Obj *x = v.u.o; x; x = ((Cons *)x)->cdr.u.o) { render(b, ((Cons *)x)->car, 1, depth + 1, limit); if (((Cons *)x)->cdr.u.o) bstr(b, " "); }
      bstr(b, ")");
      break;
    }
    case T_CTOR: {
      Ctor *c = (Ctor *)v.u.o;
      bstr(b, "("); bstr(b, symName(c->ctor));
      for (int i = 0; i < c->n; i++) { bstr(b, " "); render(b, c->f[i], 1, depth + 1, limit); }
      bstr(b, ")");
      break;
    }
    case T_REC: {
      Rec *r = (Rec *)v.u.o;
      bstr(b, "{");
      for (int i = 0; i < r->n; i++) { if (i) bstr(b, " "); bstr(b, ":"); bstr(b, symName(r->keys[i])); bstr(b, " "); render(b, r->v[i], 1, depth + 1, limit); }
      bstr(b, "}");
      break;
    }
    case T_FN: case T_BUILTIN: bstr(b, "#<fn>"); break;
    default: snprintf(tmp, sizeof tmp, "#<%s>", tagName(v.tag)); bstr(b, tmp); break;
  }
}

char *valToCStrShort(Val v, int repr) { Buf b = {0}; render(&b, v, repr, 0, 8); if (!b.b) { b.b = malloc(1); if (!b.b) exit(70); b.b[0] = 0; } return b.b; }

char *valToCStrN(Val v, int repr, size_t *n) { Buf b = {0}; render(&b, v, repr, 0, -1); if (!b.b) { b.b = malloc(1); if (!b.b) exit(70); b.b[0] = 0; } *n = b.n; return b.b; }
char *valToCStr(Val v, int repr) { size_t n; return valToCStrN(v, repr, &n); }

/* every byte of the rendering, NUL included: fputs stopped at the first NUL and cut the line short */
void valPrint(FILE *f, Val v, int repr) { size_t n; char *s = valToCStrN(v, repr, &n); fwrite(s, 1, n, f); free(s); }

const char *initModuleName;
char aslErrorMsg[4096];
char aslErrorSite[1024];
void errorSite(const char *file, unsigned line, unsigned col) { snprintf(aslErrorSite, sizeof aslErrorSite, "%s:%u:%u", file ? file : "?", line, col); }
void printErrorSite(void) { if (aslErrorSite[0]) fprintf(stderr, "%s: %s\n", aslErrorSite, aslErrorMsg); }
static jmp_buf *handler;
void aslErrorHandlerSet(void *jb) { handler = jb; } void *aslErrorHandlerGet(void) { return handler; }
void *aslHandlerSlot(void) { return &handler; } char *aslErrorText(void) { return aslErrorMsg; }

_Noreturn void aslError(const char *code, const char *fmt, ...) {
  int n = snprintf(aslErrorMsg, sizeof aslErrorMsg, "%s: ", code);
  va_list ap; va_start(ap, fmt);
  vsnprintf(aslErrorMsg + n, sizeof aslErrorMsg - (size_t)n, fmt, ap);
  va_end(ap);
  aslErrorRethrow();
}

_Noreturn void aslErrorRethrow(void) {
  if (handler) longjmp(*handler, 1);
  printErrorSite();
  fprintf(stderr, "%s\n", aslErrorMsg);
  exit(1);
}
