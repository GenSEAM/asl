/* Evaluator loop on a heap frame stack: every tail call (self or mutual) reuses its frame, non-tail depth is
   bounded by MAX_FRAMES with ERR_STACK_DEPTH, and no ASL call ever recurses on the C stack (I7). */
#include "gcFloor.h"
#include "ops.h"
#include <string.h>
#include <sys/mman.h>

#define NATIVE_ONLY_TAG 0x80000000u
static int isNativeOnlyCode(uint32_t code) { return (code & NATIVE_ONLY_TAG) != 0; }
static void absentNativeCapability(uint32_t code) {
  aslError("ERR_CAPABILITY_ABSENT", "%s requires native route asl-target-llvm/sysRoute",
           symName((int)(code & ~NATIVE_ONLY_TAG)));
}

typedef struct { Proto *p; Closure *cl; uint32_t *ip; Val *base, *ret; } Frame;

#define STACK_VALS ((size_t)1 << 26)
static Val *stack, *stackEnd, *vmSp;
static Frame *frames; static int fp;

/* asl-host catches floor errors (gc.c, gcFloor.h) through its handlers, as every other error */
static void hostFloorRaise(const char *code, const char *msg) { aslError(code, "%s", msg); }
_Static_assert(sizeof aslErrorMsg <= GC_FLOOR_MSG_MAX, "gc.c keeps a whole finalizer error");
__attribute__((noreturn)) static void hostFloorRethrow(void) { aslErrorRethrow(); } /* the guard's type carries noreturn */
static const GcFloorGuard hostFloorGuard = {aslErrorHandlerGet, aslErrorHandlerSet, hostFloorRethrow, aslErrorMsg, sizeof aslErrorMsg};

void vmInit(void) {
  gcFloorRaise = hostFloorRaise;
  gcFloorGuard = &hostFloorGuard;
  stack = mmap(NULL, STACK_VALS * sizeof(Val), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
  frames = mmap(NULL, (size_t)MAX_FRAMES * sizeof(Frame), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
  if (stack == MAP_FAILED || frames == MAP_FAILED) aslError("ERR_OOM", "cannot map the evaluator stacks");
  stackEnd = stack + STACK_VALS; vmSp = stack;
  gcStackBase = stack; gcStackTop = &vmSp;
}
void vmStateSave(void **stackPointer, int *framePointer) { *stackPointer = vmSp; *framePointer = fp; } void vmStateRestore(void *stackPointer, int framePointer) { vmSp = stackPointer; fp = framePointer; }
void vmGcRoots(void (*mark)(Val)) {
  for (int i = 0; i < fp; i++) if (frames[i].cl) mark(vobj(T_FN, frames[i].cl));
  for (int i = 0; i < nglobals; i++) mark(globals[i]);
}

static void pushFrame(Proto *p, Closure *cl, Val *base, Val *ret) {
  if (fp >= MAX_FRAMES) aslError("ERR_STACK_DEPTH", "call depth exceeds %d frames in %s", MAX_FRAMES, p->name);
  if (base + p->maxstack + 16 > stackEnd) aslError("ERR_STACK_DEPTH", "value stack exhausted in %s", p->name);
  frames[fp++] = (Frame){p, cl, p->code, base, ret};
}

static _Noreturn void arityErr(const char *name, int want, int got) {
  aslError("ERR_ARITY", "%s expects %d argument(s), got %d", name, want, got);
}


#define SYNC() (vmSp = sp)
#define OPS(X) X(OP_CONST) X(OP_LOCAL) X(OP_UPVAL) X(OP_GLOBAL) X(OP_UNIT) X(OP_POP) X(OP_SLIDE) X(OP_JMP) X(OP_JF) X(OP_ANDJ) X(OP_ORJ) X(OP_CHKBOOL) X(OP_NOT) X(OP_ADD) X(OP_SUB) X(OP_MUL) X(OP_DIV) X(OP_MOD) X(OP_LT) X(OP_LE) X(OP_GT) X(OP_GE) X(OP_EQ) X(OP_NEQ) X(OP_I2F) X(OP_NEG) X(OP_CALLG) X(OP_TCALLG) X(OP_CALL) X(OP_TCALL) X(OP_BUILTIN) X(OP_RET) X(OP_CLOSURE) X(OP_MKCTOR) X(OP_MKREC) X(OP_FIELD) X(OP_TESTCTOR) X(OP_TESTLIT) X(OP_NOMATCH) X(OP_ASSERT) X(OP_REFUTE) X(OP_MKLIST) X(OP_CHKLIST) X(OP_TESTCONS) X(OP_TESTNIL) X(OP_OPTWRAP) X(OP_CONS) X(OP_LTESTCONS) X(OP_TSELF) X(OP_PUSHN) X(OP_LUNCONS) X(OP_WITH)
#define SETOP(o) disp[o] = &&L_##o;


/* runs until the frame pushed at depth `entry` returns */
static Val execute(int entry) {
  Frame *F = &frames[fp - 1];
  uint32_t *ip = F->ip, *code = F->p->code; Val *base = F->base, *sp = vmSp, *consts = F->p->consts;
#define LOADF() (ip = F->ip, base = F->base, code = F->p->code, consts = F->p->consts)
  static void *disp[OP_COUNT];
  if (!disp[0]) {
    for (int i = 0; i < OP_COUNT; i++) disp[i] = &&L_BAD;
    OPS(SETOP)
#define SETBIN(o) disp[OP_BIN_##o] = &&L_OP_BIN_##o;
#define SETJBIN(o) disp[OP_JBIN_##o] = &&L_OP_JBIN_##o;
    ARITH_OPS(SETBIN) CMP_OPS(SETJBIN)
  }
#define NEXT goto *disp[*ip++]
  NEXT;
  {
    {
      L_OP_CONST: *sp++ = consts[*ip++]; NEXT;
      L_OP_LOCAL: *sp++ = base[*ip++]; NEXT;
      L_OP_UPVAL: *sp++ = F->cl->up[*ip++]; NEXT;
      L_OP_GLOBAL: *sp++ = globals[*ip++]; NEXT;
      L_OP_UNIT: *sp++ = VUNIT; NEXT;
      L_OP_PUSHN: {
        uint32_t n = *ip++;
        for (uint32_t i = 0; i < n; i++) {
          uint32_t a = ip[i], idx = a & PUSH_INDEX;
          switch (a >> 30) {
            case PUSH_GLOBAL: *sp++ = globals[idx]; break;
            case PUSH_LOCAL: *sp++ = base[idx]; break;
            case PUSH_CONST: *sp++ = consts[idx]; break;
            default: *sp++ = F->cl->up[idx]; break;
          }
        }
        ip += n;
        NEXT;
      }
      L_OP_POP: sp--; NEXT;
      L_OP_SLIDE: { uint32_t n = *ip++; sp[-1 - (int)n] = sp[-1]; sp -= n; NEXT; }
      L_OP_JMP: ip = code + *ip; NEXT;
      L_OP_JF: {
        Val c = *--sp;
        if (c.tag != T_BOOL) aslError("ERR_TYPE", "condition must be Bool, got %s", tagName(c.tag));
        if (!c.u.i) ip = code + *ip; else ip++;
        NEXT;
      }
      L_OP_ANDJ: L_OP_ORJ: {
        Val c = sp[-1];
        if (c.tag != T_BOOL) aslError("ERR_TYPE", "%s operand must be Bool, got %s", ip[-1] == OP_ANDJ ? "and" : "or", tagName(c.tag));
        if ((ip[-1] == OP_ANDJ) != (c.u.i != 0)) ip = code + *ip; else { ip++; sp--; }
        NEXT;
      }
      L_OP_CHKBOOL: if (sp[-1].tag != T_BOOL) aslError("ERR_TYPE", "and/or operand must be Bool, got %s", tagName(sp[-1].tag)); NEXT;
      L_OP_NOT:
        if (sp[-1].tag != T_BOOL) aslError("ERR_TYPE", "not expects Bool, got %s", tagName(sp[-1].tag));
        sp[-1].u.i = !sp[-1].u.i; NEXT;
      L_OP_ADD: L_OP_SUB: L_OP_MUL: L_OP_DIV: L_OP_MOD: L_OP_LT: L_OP_LE: L_OP_GT: L_OP_GE: L_OP_EQ: L_OP_NEQ:
        sp[-2] = binop(ip[-1], sp[-2], sp[-1]); sp--; NEXT;
#define FETCH2 \
        uint32_t w = *ip++, ia = *ip++, ib = *ip++, kb = (w >> 12) & 15, ka = (w >> 8) & 15; \
        Val y = kb == 1 ? base[ib] : kb == 2 ? consts[ib] : *--sp; \
        Val x = ka == 1 ? base[ia] : ka == 2 ? consts[ia] : *--sp;
#define BIN_HANDLER(o) L_OP_BIN_##o: { FETCH2 *sp++ = binop(OP_##o, x, y); if (w >> 16) goto ret; NEXT; }
#define JBIN_HANDLER(o) L_OP_JBIN_##o: { FETCH2 if (!binop(OP_##o, x, y).u.i) ip = code + *ip; else ip++; NEXT; }
      ARITH_OPS(BIN_HANDLER)
      CMP_OPS(JBIN_HANDLER)
      L_OP_I2F:
        if (sp[-1].tag != T_INT) aslError("ERR_TYPE", "int64ToFloat64 expects Int, got %s", tagName(sp[-1].tag));
        sp[-1] = vfloat((double)sp[-1].u.i); NEXT;
      L_OP_NEG:
        if (sp[-1].tag == T_INT) { if (sp[-1].u.i == INT64_MIN) overflow("-"); sp[-1].u.i = -sp[-1].u.i; }
        else if (sp[-1].tag == T_FLOAT) sp[-1].u.f = -sp[-1].u.f;
        else aslError("ERR_TYPE", "- expects Int or Float, got %s", tagName(sp[-1].tag));
        NEXT;
      L_OP_CALLG: L_OP_TCALLG: {
        uint32_t tail = ip[-1] == OP_TCALLG, g = *ip++, argc = *ip++;
        Closure *cl = (Closure *)globals[g].u.o; Proto *p = cl->p;
        /* a self tail call keeps the frame, its base and its stack bound: only the arguments move */
        if (tail && cl == F->cl && (int)argc == p->nparams) {
          Val *src = sp - argc; for (uint32_t i = 0; i < argc; i++) base[i] = src[i];
          sp = base + argc; ip = code;
          NEXT;
        }
        if ((int)argc != p->nparams) arityErr(p->name, p->nparams, (int)argc);
        if (tail) {
          { Val *src = sp - argc; for (uint32_t i = 0; i < argc; i++) base[i] = src[i]; } sp = base + argc;
          if (base + p->maxstack + 16 > stackEnd) aslError("ERR_STACK_DEPTH", "value stack exhausted in %s", p->name);
          F->p = p; F->cl = cl; ip = code = p->code; consts = p->consts;
        } else {
          F->ip = ip;
          pushFrame(p, cl, sp - argc, sp - argc);
          F = &frames[fp - 1]; LOADF();
        }
        NEXT;
      }
      L_OP_CALL: L_OP_TCALL: {
        uint32_t tail = ip[-1] == OP_TCALL, argc = *ip++;
        Val fn = sp[-(int)argc - 1];
        while (fn.tag == T_CTOR && ((Ctor *)fn.u.o)->ctor == KW_PARTIAL) {
          /* [partial a..] -> [f b.. a..]: splice the bound arguments in front of the given ones */
          Ctor *pc = (Ctor *)fn.u.o; uint32_t k = (uint32_t)pc->n - 1;
          if (sp + k + 16 > stackEnd) aslError("ERR_STACK_DEPTH", "value stack exhausted");
          for (int i = (int)argc - 1; i >= 0; i--) sp[i - (int)argc + (int)k] = sp[i - (int)argc];
          Val *slot = sp - argc - 1;
          slot[0] = pc->f[0];
          for (uint32_t i = 0; i < k; i++) slot[1 + i] = pc->f[1 + i];
          sp += k; argc += k; fn = slot[0];
        }
        if (fn.tag == T_BUILTIN) {
          if (isNativeOnlyCode(fn.aux)) absentNativeCapability(fn.aux);
          const Builtin *b = builtinAt((int)fn.aux);
          if (b->arity >= 0 && b->arity != (int)argc) arityErr(b->name, b->arity, (int)argc);
          SYNC(); Val r = b->fn(sp - argc, (int)argc);
          sp -= argc + 1; *sp++ = r;
          if (tail) goto ret;
          NEXT;
        }
        if (fn.tag != T_FN) aslError("ERR_TYPE", "cannot call a %s", tagName(fn.tag));
        Closure *cl = (Closure *)fn.u.o; Proto *p = cl->p;
        if ((int)argc != p->nparams) arityErr(p->name, p->nparams, (int)argc);
        if (tail) {
          { Val *src = sp - argc; for (uint32_t i = 0; i < argc; i++) base[i] = src[i]; } sp = base + argc;
          if (base + p->maxstack + 16 > stackEnd) aslError("ERR_STACK_DEPTH", "value stack exhausted in %s", p->name);
          F->p = p; F->cl = cl; ip = code = p->code; consts = p->consts;
        } else {
          F->ip = ip;
          pushFrame(p, cl, sp - argc, sp - argc - 1);
          F = &frames[fp - 1]; LOADF();
        }
        NEXT;
      }
      L_OP_BUILTIN: {
        uint32_t code = *ip++; uint32_t argc = *ip++;
        if (isNativeOnlyCode(code)) absentNativeCapability(code);
        const Builtin *b = builtinAt((int)code);
        if (b->arity >= 0 && b->arity != (int)argc) arityErr(b->name, b->arity, (int)argc);
        SYNC(); Val r = b->fn(sp - argc, (int)argc);
        sp -= argc; *sp++ = r;
        NEXT;
      }
      L_OP_RET: ret: {
        Val v = sp[-1];
        sp = F->ret; fp--;
        if (fp == entry) { vmSp = sp; return v; }
        F = &frames[fp - 1]; LOADF();
        *sp++ = v;
        NEXT;
      }
      L_OP_CLOSURE: {
        Proto *p = protoTab[*ip++]; uint32_t n = *ip++;
        SYNC();
        Closure *c = asl_alloc(O_CLOSURE, sizeof(Closure) + sizeof(Val) * n);
        c->p = p; c->n = (int)n;
        for (uint32_t i = 0; i < n; i++) { uint32_t fromLocal = *ip++, idx = *ip++; c->up[i] = fromLocal ? base[idx] : F->cl->up[idx]; }
        *sp++ = vobj(T_FN, c);
        NEXT;
      }
      L_OP_MKCTOR: {
        uint32_t name = *ip++, argc = *ip++, expect = *ip++;
        if (argc != expect) arityErr(symName((int)name), (int)expect, (int)argc);
        SYNC();
        Val v = mkCtor((int)name, (int)argc);
        Ctor *c = (Ctor *)v.u.o;
        for (uint32_t i = 0; i < argc; i++) c->f[i] = sp[(int)i - (int)argc];
        sp -= argc; *sp++ = v;
        NEXT;
      }
      L_OP_MKREC: {
        int schema = (int)*ip++; uint32_t n = *ip++;
        SYNC();
        Rec *r = asl_alloc(O_REC, sizeof(Rec) + sizeof(Val) * n);
        r->schema = schema; r->n = (int)n; r->keys = (int *)ip; ip += n;
        for (uint32_t i = 0; i < n; i++) r->v[i] = sp[(int)i - (int)n];
        sp -= n; *sp++ = vobj(T_REC, r);
        NEXT;
      }
      L_OP_FIELD: {
        int key = (int)*ip++; Val v = sp[-1];
        if (v.tag != T_REC) aslError("ERR_TYPE", ".-%s expects a record, got %s", symName(key), tagName(v.tag));
        Rec *r = (Rec *)v.u.o; int i;
        for (i = 0; i < r->n && r->keys[i] != key; i++) {}
        if (i == r->n) aslError("ERR_FIELD", "record has no field %s", symName(key));
        sp[-1] = r->v[i];
        NEXT;
      }
      L_OP_WITH: {
        uint32_t n = *ip++; const int *keys = (const int *)ip; ip += n;
        if (sp[-(int)n - 1].tag != T_REC) aslError("ERR_TYPE", "with expects a record, got %s", tagName(sp[-(int)n - 1].tag));
        SYNC();
        int m = ((Rec *)sp[-(int)n - 1].u.o)->n;
        Rec *r = asl_alloc(O_REC, sizeof(Rec) + sizeof(Val) * (size_t)m), *s = (Rec *)sp[-(int)n - 1].u.o;
        r->schema = s->schema; r->n = m; r->keys = s->keys;
        for (int i = 0; i < m; i++) r->v[i] = s->v[i];
        for (uint32_t j = 0; j < n; j++) {
          int i;
          for (i = 0; i < m && s->keys[i] != keys[j]; i++) {}
          if (i == m) aslError("ERR_FIELD", "with: record has no field %s", symName(keys[j]));
          r->v[i] = sp[(int)j - (int)n];
        }
        sp -= n; sp[-1] = vobj(T_REC, r);
        NEXT;
      }
      L_OP_TESTCTOR: {
        int name = (int)*ip++; uint32_t k = *ip++, target = *ip++; Val v = sp[-1];
        if (v.tag == T_CTOR && ((Ctor *)v.u.o)->ctor == name) {
          Ctor *c = (Ctor *)v.u.o;
          if ((int)k != c->n) aslError("ERR_ARITY", "pattern (%s) binds %u field(s), value has %d", symName(name), k, c->n);
          for (uint32_t i = 0; i < k; i++) *sp++ = c->f[i];
        } else ip = code + target;
        NEXT;
      }
      L_OP_TESTLIT: {
        Val c = consts[*ip++]; uint32_t target = *ip++; Val v = sp[-1];
        if ((v.tag == T_INT && c.tag == T_FLOAT) || (v.tag == T_FLOAT && c.tag == T_INT)) aslError("ERR_TYPE", "match compares %s with a %s literal", tagName(v.tag), tagName(c.tag));
        if (v.tag != c.tag || !valEq(v, c)) ip = code + target;
        NEXT;
      }
      L_OP_NOMATCH: {
        char *s = valToCStrShort(sp[-1], 1);
        aslError("ERR_MATCH_NONEXHAUSTIVE", "no arm matches %s in %s", s, F->p->name);
      }
      L_OP_ASSERT: {
        Val c = sp[-2], m = sp[-1]; uint32_t line = *ip++, col = *ip++;
        if (initModuleName) { errorSite(F->p->file, line, col); aslError("ERR_ASSERT_AT_INIT", "%s: assertion executed during module initialization", initModuleName); }
        if (c.tag != T_BOOL) { errorSite(F->p->file, line, col); aslError("ERR_TYPE", "assert condition must be Bool, got %s", tagName(c.tag)); }
        assertCount++;
        if (!c.u.i) { char *s = valToCStrShort(m, 0); errorSite(F->p->file, line, col); aslError("ERR_ASSERT", "assertion failed: %s", s); }
        sp -= 2; *sp++ = VUNIT;
        NEXT;
      }
      /* the negative claim: passes only on false, counted apart from asserts */
      L_OP_REFUTE: {
        Val c = sp[-2], m = sp[-1]; uint32_t line = *ip++, col = *ip++;
        if (initModuleName) { errorSite(F->p->file, line, col); aslError("ERR_ASSERT_AT_INIT", "%s: refutation executed during module initialization", initModuleName); }
        if (c.tag != T_BOOL) { errorSite(F->p->file, line, col); aslError("ERR_TYPE", "refute condition must be Bool, got %s", tagName(c.tag)); }
        refuteCount++;
        if (c.u.i) {
          errorSite(F->p->file, line, col);
          if (m.tag == T_UNIT) aslError("ERR_REFUTE", "refutation failed: predicate held true");
          char *s = valToCStrShort(m, 0); aslError("ERR_REFUTE", "refutation failed: %s", s);
        }
        sp -= 2; *sp++ = VUNIT;
        NEXT;
      }
      L_OP_MKLIST: {
        uint32_t n = *ip++;
        SYNC();
        Val acc = VNIL;
        asl_gc_root_push(&acc);
        for (int i = (int)n - 1; i >= 0; i--) acc = mkCons(sp[i - (int)n], acc);
        asl_gc_root_pop(1);
        sp -= n; *sp++ = acc;
        NEXT;
      }
      /* a match on (listHead xs) or (listTail xs) tests the list in place of the Option (compile.c listOptionMatch) */
#define LISTARG(tailPart) if (sp[-1].tag != T_LIST) aslError("ERR_TYPE", "%s expects %s, got %s", (tailPart) ? "listTail" : "listHead", tagName(T_LIST), tagName(sp[-1].tag));
      L_OP_CHKLIST: LISTARG(*ip) ip++; NEXT;
      L_OP_TESTCONS: {
        uint32_t tailPart = *ip++, target = *ip++; LISTARG(tailPart)
        Cons *c = (Cons *)sp[-1].u.o;
        if (c) *sp++ = tailPart ? c->cdr : c->car; else ip = code + target;
        NEXT;
      }
      /* LOCAL then TESTCONS in one dispatch */
      L_OP_LTESTCONS: {
        uint32_t slot = *ip++, tailPart = *ip++, target = *ip++; Val v = base[slot];
        *sp++ = v;
        if (v.tag != T_LIST) aslError("ERR_TYPE", "%s expects %s, got %s", tailPart ? "listTail" : "listHead", tagName(T_LIST), tagName(v.tag));
        Cons *c = (Cons *)v.u.o;
        if (c) *sp++ = tailPart ? c->cdr : c->car; else ip = code + target;
        NEXT;
      }
      /* LTESTCONS on (listHead xs) and then on (listTail xs) for the same xs (compile.c unconsInner): a cons pushes
         xs, its head, xs and its tail */
      L_OP_LUNCONS: {
        uint32_t slot = *ip++, target = *ip++; Val v = base[slot];
        *sp++ = v;
        if (v.tag != T_LIST) aslError("ERR_TYPE", "listHead expects %s, got %s", tagName(T_LIST), tagName(v.tag));
        Cons *c = (Cons *)v.u.o;
        if (c) { sp[0] = c->car; sp[1] = v; sp[2] = c->cdr; sp += 3; } else ip = code + target;
        NEXT;
      }
      L_OP_TESTNIL: { uint32_t tailPart = *ip++; LISTARG(tailPart) if (sp[-1].u.o) ip = code + *ip; else ip++; NEXT; }
      L_OP_OPTWRAP: {
        uint32_t tailPart = *ip++;
        SYNC();
        Val r = mkCtor(sp[-1].u.o ? KW_SOME : KW_NONE, sp[-1].u.o ? 1 : 0);
        if (sp[-1].u.o) ((Ctor *)r.u.o)->f[0] = tailPart ? ((Cons *)sp[-1].u.o)->cdr : ((Cons *)sp[-1].u.o)->car;
        sp[-1] = r;
        NEXT;
      }
      /* (cons x xs) without the builtin call, operands addressed as for OP_BIN: stack operands stay pushed across the
         allocation, so the collector still scans them, and leave after it */
      L_OP_CONS: {
        uint32_t w = *ip++, ia = *ip++, ib = *ip++, kb = (w >> 12) & 15, ka = (w >> 8) & 15, ns = (ka == 0) + (kb == 0);
        Val y = kb == 1 ? base[ib] : kb == 2 ? consts[ib] : sp[-1];
        Val x = ka == 1 ? base[ia] : ka == 2 ? consts[ia] : sp[-(int)ns];
        if (y.tag != T_LIST) aslError("ERR_TYPE", "cons expects %s, got %s", tagName(T_LIST), tagName(y.tag));
        SYNC();
        Cons *c = asl_alloc_cons();
        c->car = x; c->cdr = y;
        sp -= ns; *sp++ = vobj(T_LIST, c);
        NEXT;
      }
      /* a self tail call (compile.c call) moves only the arguments that differ from their parameter, then restarts the
         frame; when a move reads a parameter an earlier move may replace, every value is gathered first */
      L_OP_TSELF: {
        uint32_t w = *ip++, nm = w & 255, ns = (w >> 8) & 255, n = (w >> 16) & 255; Val *src = sp - ns;
#define TSELF_SRC(a) ((a) >> 30 == 1 ? base[(a) & TSELF_INDEX] : (a) >> 30 == 2 ? consts[(a) & TSELF_INDEX] : *src++)
        if (w >> 24) {
          Val tmp[MAX_TSELF_ARGS];
          for (uint32_t i = 0; i < nm; i++) tmp[i] = TSELF_SRC(ip[i]);
          for (uint32_t i = 0; i < nm; i++) base[(ip[i] >> 27) & 7] = tmp[i];
        } else for (uint32_t i = 0; i < nm; i++) base[(ip[i] >> 27) & 7] = TSELF_SRC(ip[i]);
        sp = base + n; ip = code;
        NEXT;
      }
      L_BAD: aslError("ERR_INTERNAL", "bad opcode %u", ip[-1]);
    }
  }
}

Val vmCall(Val fn, int argc, Val *args) {
  if (fn.tag == T_CTOR && ((Ctor *)fn.u.o)->ctor == KW_PARTIAL) {
    Ctor *pc = (Ctor *)fn.u.o; int k = pc->n - 1;
    Val all[64];
    if (k + argc > 64) aslError("ERR_LIMIT", "partial application with more than 64 arguments");
    for (int i = 0; i < k; i++) all[i] = pc->f[1 + i];
    for (int i = 0; i < argc; i++) all[k + i] = args[i];
    return vmCall(pc->f[0], k + argc, all);
  }
  Val *sp = vmSp;
  if (sp + argc + 16 > stackEnd) aslError("ERR_STACK_DEPTH", "value stack exhausted");
  sp[0] = fn;
  for (int i = 0; i < argc; i++) sp[1 + i] = args[i];
  vmSp = sp + 1 + argc;
  if (fn.tag == T_BUILTIN) {
    if (isNativeOnlyCode(fn.aux)) absentNativeCapability(fn.aux);
    const Builtin *b = builtinAt((int)fn.aux);
    if (b->arity >= 0 && b->arity != argc) arityErr(b->name, b->arity, argc);
    Val r = b->fn(sp + 1, argc);
    vmSp = sp;
    return r;
  }
  if (fn.tag != T_FN) aslError("ERR_TYPE", "cannot call a %s", tagName(fn.tag));
  Closure *cl = (Closure *)fn.u.o;
  if (argc != cl->p->nparams) arityErr(cl->p->name, cl->p->nparams, argc);
  int entry = fp;
  pushFrame(cl->p, cl, sp + 1, sp);
  return execute(entry);
}

__attribute__((weak)) void gcMutatorRoots(void (*mark)(Val)) { vmGcRoots(mark); }
__attribute__((weak)) Val aslCall(Val fn, int argc, Val *args) { return vmCall(fn, argc, args); }

Val vmRunProto(Proto *p) {
  int entry = fp;
  pushFrame(p, NULL, vmSp, vmSp);
  return execute(entry);
}
