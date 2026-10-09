/* Operators of the evaluator (vm.c, with compile.c and types.c for the names): operator names and the binary
   arithmetic and comparisons, inlined so the VM dispatch keeps its own copy. Native code runs the same semantics as
   emitted IR (asl-target-llvm/rtOps), so the native runtime (abi.c) no longer includes this. */
#ifndef ASL_OPS_H
#define ASL_OPS_H
#include "compile.h"
#include <math.h>
#include <string.h>

/* operator name to OP_ADD..OP_NEQ, -1 when s is not an operator */
static inline int opFor(const char *s) {
  static const struct { const char *n; int op; } t[] = {{"+", OP_ADD}, {"-", OP_SUB}, {"*", OP_MUL}, {"/", OP_DIV}, {"mod", OP_MOD},
    {"<", OP_LT}, {"<=", OP_LE}, {">", OP_GT}, {">=", OP_GE}, {"=", OP_EQ}, {"==", OP_EQ}, {"!=", OP_NEQ}, {"not=", OP_NEQ}};
  for (size_t i = 0; i < sizeof t / sizeof t[0]; i++) if (!strcmp(s, t[i].n)) return t[i].op;
  return -1;
}

static inline _Noreturn void typeErr2(const char *op, Val a, Val b) {
  aslError("ERR_TYPE", "%s expects two Int or two Float, got %s and %s", op, tagName(a.tag), tagName(b.tag));
}

static inline int cmpVals(int op, Val a, Val b) {
  int c;
  if (a.tag == T_INT && b.tag == T_INT) c = a.u.i < b.u.i ? -1 : a.u.i > b.u.i;
  else if (a.tag == T_FLOAT && b.tag == T_FLOAT) {
    double x = a.u.f, y = b.u.f;
    switch (op) { case OP_LT: return x < y; case OP_LE: return x <= y; case OP_GT: return x > y; default: return x >= y; }
  } else if (a.tag == T_STR && b.tag == T_STR) {
    Str *x = (Str *)a.u.o, *y = (Str *)b.u.o; size_t m = x->len < y->len ? x->len : y->len;
    c = memcmp(x->s, y->s, m); if (!c) c = x->len < y->len ? -1 : x->len > y->len;
  } else if (a.tag == T_KW && b.tag == T_KW) {
    c = strcmp(symName((int)a.aux), symName((int)b.aux));
  } else typeErr2(op == OP_LT ? "<" : op == OP_LE ? "<=" : op == OP_GT ? ">" : ">=", a, b);
  switch (op) { case OP_LT: return c < 0; case OP_LE: return c <= 0; case OP_GT: return c > 0; default: return c >= 0; }
}

static inline _Noreturn void overflow(const char *op) { aslError("ERR_INT_OVERFLOW", "Int %s leaves int64", op); }

static inline __attribute__((always_inline)) Val binop(uint32_t op, Val a, Val b) {
  if (a.tag == T_INT && b.tag == T_INT) {
    switch (op) {
      case OP_ADD: { int64_t r; if (__builtin_add_overflow(a.u.i, b.u.i, &r)) overflow("+"); return vint(r); }
      case OP_SUB: { int64_t r; if (__builtin_sub_overflow(a.u.i, b.u.i, &r)) overflow("-"); return vint(r); }
      case OP_MUL: { int64_t r; if (__builtin_mul_overflow(a.u.i, b.u.i, &r)) overflow("*"); return vint(r); }
      case OP_DIV: case OP_MOD:
        if (b.u.i == 0) aslError("ERR_DIV_ZERO", "%s by zero", op == OP_DIV ? "division" : "mod");
        if (b.u.i == -1) { if (op == OP_MOD) return vint(0); if (a.u.i == INT64_MIN) overflow("/"); return vint(-a.u.i); } /* INT64_MIN / -1 overflows; mod is exact 0 */
        if (op == OP_DIV) { int64_t q = a.u.i / b.u.i; return vint(a.u.i % b.u.i != 0 && ((a.u.i < 0) != (b.u.i < 0)) ? q - 1 : q); } /* floor division */
        { int64_t r = a.u.i % b.u.i; return vint(r != 0 && ((r < 0) != (b.u.i < 0)) ? r + b.u.i : r); } /* floor mod: sign of the divisor */
      case OP_LT: return vbool(a.u.i < b.u.i);
      case OP_LE: return vbool(a.u.i <= b.u.i);
      case OP_GT: return vbool(a.u.i > b.u.i);
      case OP_GE: return vbool(a.u.i >= b.u.i);
      case OP_EQ: return vbool(a.u.i == b.u.i);
      default: return vbool(a.u.i != b.u.i);
    }
  }
  if (a.tag == T_FLOAT && b.tag == T_FLOAT) {
    double x = a.u.f, y = b.u.f;
    switch (op) {
      case OP_ADD: return vfloat(x + y);
      case OP_SUB: return vfloat(x - y);
      case OP_MUL: return vfloat(x * y);
      case OP_DIV: return vfloat(x / y);
      case OP_MOD: { double r = fmod(x, y); return vfloat(r == 0 ? copysign(0.0, y) : (r < 0) != (y < 0) ? r + y : r); } /* floor mod: fmod moved to the divisor's sign; NaN and inf as fmod gives them */
      case OP_LT: return vbool(x < y);
      case OP_LE: return vbool(x <= y);
      case OP_GT: return vbool(x > y);
      case OP_GE: return vbool(x >= y);
      case OP_EQ: return vbool(x == y);
      default: return vbool(x != y);
    }
  }
  if (op == OP_EQ) return vbool(valEq(a, b));
  if (op == OP_NEQ) return vbool(!valEq(a, b));
  if (op >= OP_LT && op <= OP_GE) return vbool(cmpVals((int)op, a, b));
  static const char *names[] = {"+", "-", "*", "/", "mod"};
  typeErr2(names[op - OP_ADD], a, b);
}

#endif
