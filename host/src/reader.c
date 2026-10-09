/* Stage-0 ASL reader. A top-level item begins at a column-0 token outside any bracket; the tokens up to the next
   such token form one item (N_GROUP), so indented `fn name p: T -> R` headers and their bodies read as one form. */
#include "reader.h"
#include "value.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  const char *file, *src; size_t len, pos; int line, col;
  char *err; size_t errlen;
  int *tagLines, *tagSyms; int ntags, captags;
  int dots;  /* ASL source: name.field and (expr).field read as (.-field ...); off for .asn data */
  int failed;
} Lex;

static void *xalloc(size_t n) {
  void *p = calloc(1, n ? n : 1);
  if (!p) { fprintf(stderr, "ERR_OOM\n"); exit(70); }
  return p;
}
static int lexErr(Lex *L, int line, int col, const char *code, const char *msg) {
  snprintf(L->err, L->errlen, "%s:%d:%d: %s %s", L->file, line, col + 1, code, msg); return -1;
}

static void adv(Lex *L) {
  if (L->src[L->pos] == '\n') { L->line++; L->col = 0; } else L->col++;
  L->pos++;
}

static int isWordChar(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '?' || c == '!';
}

/* a comment at [at, end) that is the whole line and reads (:m ... :tags (w ...) ...) records each w with its line */
static void metaTags(Lex *L, size_t at, size_t end) {
  for (size_t b = at; b > 0 && L->src[b - 1] != '\n'; b--) if (L->src[b - 1] != ' ' && L->src[b - 1] != '\t') return;
  const char *s = L->src; size_t i = at + 1;
  while (i < end && s[i] == ' ') i++;
  if (end - i < 4 || memcmp(s + i, "(:m", 3) != 0 || isWordChar(s[i + 3])) return;
  for (i += 3; i + 5 <= end; i++) {
    if (memcmp(s + i, ":tags", 5) != 0 || (i + 5 < end && isWordChar(s[i + 5]))) continue;
    i += 5;
    while (i < end && s[i] == ' ') i++;
    if (i >= end || s[i] != '(') return;
    for (i++; i < end && s[i] != ')';) {
      if (s[i] == ' ') { i++; continue; }
      size_t w = i;
      while (i < end && isWordChar(s[i])) i++;
      if (i == w) return;
      if (L->ntags == L->captags) {
        L->captags = L->captags ? L->captags * 2 : 8;
        L->tagLines = realloc(L->tagLines, sizeof(int) * (size_t)L->captags); L->tagSyms = realloc(L->tagSyms, sizeof(int) * (size_t)L->captags);
        if (!L->tagLines || !L->tagSyms) exit(70);
      }
      L->tagLines[L->ntags] = L->line; L->tagSyms[L->ntags++] = intern(s + w, i - w);
    }
    return;
  }
}

/* a ; comment in ASL source must be one (:m ...) meta form without :why: prose lives in doc.asn */
static int metaComment(const char *s, size_t at, size_t end) {
  size_t i = at;
  while (i < end && (s[i] == ';' || s[i] == ' ' || s[i] == '\t')) i++;
  if (end - i < 4 || memcmp(s + i, "(:m", 3) != 0 || isWordChar(s[i + 3])) return 0;
  for (size_t j = i; j + 4 <= end; j++) if (!memcmp(s + j, ":why", 4) && (j + 4 == end || !isWordChar(s[j + 4]))) return 0;
  return 1;
}

static void skipWs(Lex *L) {
  while (L->pos < L->len) {
    char c = L->src[L->pos];
    if (c == ';') {
      size_t at = L->pos; int line = L->line, col = L->col;
      while (L->pos < L->len && L->src[L->pos] != '\n') adv(L);
      metaTags(L, at, L->pos);
      if (L->dots && !L->failed && !metaComment(L->src, at, L->pos)) {
        lexErr(L, line, col, "ERR_READ_COMMENT", "free ; comments and (:m :why ...) are retired: move the text to the package doc.asn (asl doc); a comment is one ; (:m ...) meta form");
        L->failed = 1;
      }
    }
    else if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == ',') adv(L);
    else break;
  }
}

static int isDelim(char c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '(' || c == ')' || c == '[' || c == ']' ||
         c == '{' || c == '}' || c == '"' || c == ';' || c == ',';
}

static Node *mk(NodeKind k, int line, int col) {
  Node *n = xalloc(sizeof(Node)); n->kind = k; n->line = line; n->col = col; return n;
}

typedef struct { Node **v; int n, cap; } NodeVec;
static void push(NodeVec *nv, Node *x) {
  if (nv->n == nv->cap) { nv->cap = nv->cap ? nv->cap * 2 : 8; nv->v = realloc(nv->v, sizeof(Node *) * nv->cap); if (!nv->v) exit(70); }
  nv->v[nv->n++] = x;
}

/* number syntax: [+-]?digits, or with .digits and/or [eE][+-]?digits -> Float */
static int classifyNumber(const char *s, size_t n, int *isFloat) {
  size_t i = 0; int digits = 0, fl = 0;
  if (i < n && (s[i] == '-' || s[i] == '+')) i++;
  while (i < n && s[i] >= '0' && s[i] <= '9') { i++; digits++; }
  if (!digits) return 0;
  if (i < n && s[i] == '.') {
    i++; fl = 1; int fd = 0;
    while (i < n && s[i] >= '0' && s[i] <= '9') { i++; fd++; }
    if (!fd) return 0;
  }
  if (i < n && (s[i] == 'e' || s[i] == 'E')) {
    i++; fl = 1; int ed = 0;
    if (i < n && (s[i] == '-' || s[i] == '+')) i++;
    while (i < n && s[i] >= '0' && s[i] <= '9') { i++; ed++; }
    if (!ed) return 0;
  }
  if (i != n) return 0;
  *isFloat = fl;
  return 1;
}

static Node *atom(Lex *L) {
  int line = L->line, col = L->col; size_t st = L->pos;
  while (L->pos < L->len && !isDelim(L->src[L->pos])) adv(L);
  const char *s = L->src + st; size_t n = L->pos - st;
  int fl;
  if (classifyNumber(s, n, &fl)) {
    if (fl) {
      Node *x = mk(N_FLOAT, line, col);
      if (!floatParse(s, n, &x->f)) { lexErr(L, line, col, "ERR_READ_NUMBER", "bad float literal"); return NULL; }
      return x;
    }
    Node *x = mk(N_INT, line, col);
    int neg = s[0] == '-'; size_t i = (s[0] == '-' || s[0] == '+') ? 1 : 0;
    uint64_t acc = 0, lim = neg ? (uint64_t)INT64_MAX + 1 : (uint64_t)INT64_MAX;
    for (; i < n; i++) {
      uint64_t d = (uint64_t)(s[i] - '0');
      if (acc > (lim - d) / 10) { x->outOfRange = 1; return x; }
      acc = acc * 10 + d;
    }
    x->i = neg ? (int64_t)(0 - acc) : (int64_t)acc;
    return x;
  }
  if (n > 1 && s[0] == ':') { Node *x = mk(N_KW, line, col); x->sym = intern(s + 1, n - 1); return x; }
  Node *x = mk(N_SYM, line, col); x->sym = intern(s, n); return x;
}

static int hexVal(char c) {
  return c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
}

/* value of exactly count hex digits at src[at..] (no sign, no space), -1 when one is missing */
static long hexFixed(Lex *L, size_t at, int count) {
  long v = 0;
  for (size_t k = 0; k < (size_t)count; k++) {
    int d = at + k < L->len ? hexVal(L->src[at + k]) : -1;
    if (d < 0) return -1;
    v = v * 16 + d;
  }
  return v;
}

static void putByte(char **buf, size_t *cap, size_t *n, long c) {
  if (*n + 1 >= *cap) { *cap *= 2; *buf = realloc(*buf, *cap); if (!*buf) exit(70); }
  (*buf)[(*n)++] = (char)c;
}

static void putUtf8(char **buf, size_t *cap, size_t *n, long cp) {
  static const long lead[] = {0, 0xC0, 0xE0, 0xF0};
  if (cp < 0x80) { putByte(buf, cap, n, cp); return; }
  int k = cp < 0x800 ? 1 : cp < 0x10000 ? 2 : 3;
  putByte(buf, cap, n, lead[k] | (cp >> (6 * k)));
  for (int sh = 6 * (k - 1); sh >= 0; sh -= 6) putByte(buf, cap, n, 0x80 | ((cp >> sh) & 0x3F));
}

/* \n \t \r \\ \" \xHH (one byte) \uXXXX \u{1-6 hex} (scalar value, no surrogate); else ERR_BAD_ESCAPE at the backslash.
   On success L->pos is on the escape's last byte. */
static int escape(Lex *L, char **buf, size_t *cap, size_t *n) {
  int line = L->line, col = L->col; adv(L);
  char e = L->src[L->pos], msg[80]; long cp = -1; size_t end = L->pos;
  if (e == 'n' || e == 't' || e == 'r' || e == '\\' || e == '"') { putByte(buf, cap, n, e == 'n' ? '\n' : e == 't' ? '\t' : e == 'r' ? '\r' : e); return 0; }
  if (e == 'x') {
    if ((cp = hexFixed(L, L->pos + 1, 2)) < 0) return lexErr(L, line, col, "ERR_BAD_ESCAPE", "\\x needs exactly 2 hex digits");
    while (L->pos < end + 2) adv(L);
    putByte(buf, cap, n, cp); return 0;
  }
  if (e != 'u') {
    if (e > ' ' && e < 127) snprintf(msg, sizeof msg, "unknown escape \\%c", e);
    else snprintf(msg, sizeof msg, "unknown escape before byte 0x%02X", (unsigned)(unsigned char)e);
    return lexErr(L, line, col, "ERR_BAD_ESCAPE", msg);
  }
  if (L->pos + 1 < L->len && L->src[L->pos + 1] == '{') {
    int digits = 0; end = L->pos + 2; cp = 0;
    for (; end < L->len && hexVal(L->src[end]) >= 0 && digits < 7; end++, digits++) cp = cp * 16 + hexVal(L->src[end]);
    if (digits < 1 || digits > 6 || end >= L->len || L->src[end] != '}')
      return lexErr(L, line, col, "ERR_BAD_ESCAPE", "\\u{...} needs 1 to 6 hex digits and a closing }");
  } else if ((cp = hexFixed(L, L->pos + 1, 4)) < 0) return lexErr(L, line, col, "ERR_BAD_ESCAPE", "\\u needs 4 hex digits or {1 to 6 hex digits}");
  else end = L->pos + 4;
  if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
    snprintf(msg, sizeof msg, "\\u code point 0x%lX is a surrogate or above 0x10FFFF", cp);
    return lexErr(L, line, col, "ERR_BAD_ESCAPE", msg);
  }
  while (L->pos < end) adv(L);
  putUtf8(buf, cap, n, cp); return 0;
}

static Node *string(Lex *L) {
  int line = L->line, col = L->col; adv(L);
  size_t cap = 16, n = 0; char *buf = xalloc(cap);
  for (;;) {
    if (L->pos >= L->len) { free(buf); lexErr(L, line, col, "ERR_READ_UNBALANCED", "unterminated string"); return NULL; }
    char c = L->src[L->pos];
    if (c == '"') { adv(L); break; }
    if (c == '\\' && L->pos + 1 < L->len) {
      if (escape(L, &buf, &cap, &n) < 0) { free(buf); return NULL; }
    } else putByte(&buf, &cap, &n, (unsigned char)c);
    adv(L);
  }
  buf[n] = 0; Node *x = mk(N_STR, line, col); x->s = buf; x->len = n; return x;
}

static char closer(char open) { return open == '(' ? ')' : open == '[' ? ']' : '}'; }

static int isFieldStart(char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'; }

/* length of one field name at s (a field start then word chars), 0 when none */
static size_t fieldLen(const char *s, size_t n) {
  if (!n || !isFieldStart(s[0])) return 0;
  size_t i = 1;
  while (i < n && isWordChar(s[i])) i++;
  return i;
}

/* (.-field base) */
static Node *fieldOf(Node *base, const char *f, size_t n) {
  char buf[256];
  if (n + 2 >= sizeof buf) return NULL;
  buf[0] = '.'; buf[1] = '-'; memcpy(buf + 2, f, n);
  Node *h = mk(N_SYM, base->line, base->col); h->sym = intern(buf, n + 2);
  Node *x = mk(N_LIST, base->line, base->col); x->n = 2; x->kids = xalloc(sizeof(Node *) * 2);
  x->kids[0] = h; x->kids[1] = base; return x;
}

/* .f.g... at s[0..n) applied to base, or NULL when s is not a whole field chain */
static Node *fieldChain(Node *base, const char *s, size_t n) {
  size_t i = 0;
  while (i < n) {
    if (s[i] != '.') return NULL;
    size_t k = fieldLen(s + i + 1, n - i - 1);
    if (!k || (i + 1 + k < n && s[i + 1 + k] != '.')) return NULL;
    if (!(base = fieldOf(base, s + i + 1, k))) return NULL;
    i += 1 + k;
  }
  return base;
}

/* a name token a.b.c (a may be alias/name) as (.-c (.-b a)); the token itself when it is no such chain */
static Node *dotName(Node *x) {
  const char *s = symName(x->sym); size_t n = strlen(s);
  const char *dot = memchr(s, '.', n);
  if (!dot || dot == s || !isFieldStart(s[0])) return x;
  for (const char *p = s; p < dot; p++) if (!isWordChar(*p) && *p != '/') return x;
  Node *base = mk(N_SYM, x->line, x->col); base->sym = intern(s, (size_t)(dot - s));
  Node *c = fieldChain(base, dot, n - (size_t)(dot - s));
  return c ? c : x;
}

/* inside a (module ...) header names are dotted package paths, never field access */
static int inModuleForm(Node *outer, NodeVec *kids) {
  return outer->kind == N_LIST && kids->n >= 1 && kids->v[0]->kind == N_SYM && !strcmp(symName(kids->v[0]->sym), "module");
}

/* the postfix .f.g after a closing ')', consumed from the source, applied to x */
static Node *postfixFields(Lex *L, Node *x) {
  size_t st = L->pos;
  if (st + 1 >= L->len || L->src[st] != '.' || !isFieldStart(L->src[st + 1])) return x;
  size_t e = st;
  while (e < L->len && !isDelim(L->src[e])) e++;
  Node *c = fieldChain(x, L->src + st, e - st);
  if (!c) { lexErr(L, L->line, L->col, "ERR_READ_FIELD", "a postfix field chain is .name(.name)* after ')'"); return NULL; }
  while (L->pos < e) adv(L);
  return c;
}

/* a string right after :d or :doc as a direct kid of a module, schema, enum or fn form is a retired docstring */
static int docHead(Node *head, int idx) {
  if (head->kind != N_SYM) return 0;
  const char *h = symName(head->sym);
  if (!strcmp(h, "module") || !strcmp(h, "fn") || !strcmp(h, "df") || !strcmp(h, "defn")) return idx >= 1;
  if (!strcmp(h, "schema") || !strcmp(h, "enum")) return idx == 2;
  return 0;
}

static int retiredDoc(Lex *L, NodeVec *kids, Node *x, int group) {
  int n = (int)kids->n;
  if (!L->dots || x->kind != N_STR || n < 2) return 0;
  Node *k = kids->v[n - 1];
  if (k->kind != N_KW || (strcmp(symName(k->sym), "d") && strcmp(symName(k->sym), "doc"))) return 0;
  if (group ? !(kids->v[0]->kind == N_SYM && !strcmp(symName(kids->v[0]->sym), "fn")) : !docHead(kids->v[0], n - 1)) return 0;
  lexErr(L, k->line, k->col, "ERR_READ_DOC", ":d docstrings are retired: move the text to the package doc.asn (asl doc)");
  return 1;
}

/* iterative datum reader with an explicit bracket stack, so nesting depth never touches the C stack */
static Node *datum(Lex *L) {
  typedef struct { Node *node; NodeVec kids; char open; } Open;
  Open *stk = NULL; int sp = 0, cap = 0;
  for (;;) {
    skipWs(L);
    if (L->failed) { free(stk); return NULL; }
    if (L->pos >= L->len) {
      if (sp == 0) return NULL;
      Open *o = &stk[sp - 1];
      char msg[96]; snprintf(msg, sizeof msg, "unclosed '%c' at end of file", o->open);
      lexErr(L, o->node->line, o->node->col, "ERR_READ_UNBALANCED", msg); free(stk); return NULL;
    }
    char c = L->src[L->pos]; Node *done = NULL;
    if (c == '(' || c == '[' || c == '{') {
      if (sp == cap) { cap = cap ? cap * 2 : 16; stk = realloc(stk, sizeof(Open) * cap); if (!stk) exit(70); }
      stk[sp].node = mk(c == '(' ? N_LIST : c == '[' ? N_VEC : N_MAP, L->line, L->col);
      stk[sp].kids = (NodeVec){0}; stk[sp].open = c; sp++; adv(L); continue;
    } else if (c == ')' || c == ']' || c == '}') {
      if (sp == 0) { lexErr(L, L->line, L->col, "ERR_READ_UNBALANCED", c == ')' ? "unmatched ')'" : c == ']' ? "unmatched ']'" : "unmatched '}'"); free(stk); return NULL; }
      Open *o = &stk[sp - 1];
      if (closer(o->open) != c) {
        char msg[96]; snprintf(msg, sizeof msg, "'%c' closes '%c' opened at %d:%d", c, o->open, o->node->line, o->node->col);
        lexErr(L, L->line, L->col, "ERR_READ_UNBALANCED", msg); free(stk); return NULL;
      }
      adv(L); done = o->node; done->n = o->kids.n; done->kids = o->kids.v; sp--;
      if (L->dots && c == ')' && !(sp > 0 && inModuleForm(stk[0].node, &stk[0].kids)) && !(done = postfixFields(L, done))) { free(stk); return NULL; }
    } else if (c == '"') {
      done = string(L); if (!done) { free(stk); return NULL; }
    } else {
      done = atom(L); if (!done) { free(stk); return NULL; }
      if (L->dots && done->kind == N_SYM && !strncmp(symName(done->sym), ".-", 2) && symName(done->sym)[2]) {
        char msg[200]; const char *f = symName(done->sym) + 2;
        snprintf(msg, sizeof msg, "(%.80s x) is retired: write x.%.80s, or (expr).%.80s for an expression", symName(done->sym), f, f);
        lexErr(L, done->line, done->col, "ERR_READ_FIELD", msg); free(stk); return NULL;
      }
      if (L->dots && done->kind == N_SYM && !(sp > 0 && inModuleForm(stk[0].node, &stk[0].kids))) done = dotName(done);
    }
    if (sp == 0) { free(stk); return done; }
    if (stk[sp - 1].open == '(' && retiredDoc(L, &stk[sp - 1].kids, done, 0)) { free(stk); return NULL; }
    push(&stk[sp - 1].kids, done);
  }
}

int readSource(const char *file, const char *src, size_t len, Unit *out, char *err, size_t errlen) {
  size_t fl = strlen(file);
  Lex L = {.file = file, .src = src, .len = len, .line = 1, .err = err, .errlen = errlen, .dots = !(fl >= 4 && !strcmp(file + fl - 4, ".asn"))};
  NodeVec items = {0}, cur = {0}; int curLine = 0, curCol = 0, haveCur = 0; err[0] = 0;
  for (;;) {
    skipWs(&L); if (L.failed) return -1; if (L.pos >= L.len) break;
    int startCol = L.col, line = L.line, col = L.col;
    Node *d = datum(&L); if (!d) return -1;
    if (startCol == 0 || !haveCur) {
      if (haveCur) { Node *g = mk(N_GROUP, curLine, curCol); g->n = cur.n; g->kids = cur.v; push(&items, g); }
      cur = (NodeVec){0}; haveCur = 1; curLine = line; curCol = col;
    }
    if (retiredDoc(&L, &cur, d, 1)) return -1;
    push(&cur, d);
  }
  if (haveCur) { Node *g = mk(N_GROUP, curLine, curCol); g->n = cur.n; g->kids = cur.v; push(&items, g); }
  out->file = file; out->items = items.v; out->n = items.n;
  out->tagLines = L.tagLines; out->tagSyms = L.tagSyms; out->ntags = L.ntags; return 0;
}

int readFile(const char *path, Unit *out, char *err, size_t errlen) {
  size_t n; char *src = slurpFile(path, &n);
  if (!src) { snprintf(err, errlen, "%s: ERR_IO cannot read file", path); return -1; }
  return readSource(path, src, n, out, err, errlen);
}
