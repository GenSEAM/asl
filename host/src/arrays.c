#include <stdint.h>
/* Unboxed F64Array I64Array I8Array (plan R1 H8): raw malloc buffers owned by a GC header; elements are Float,
   Int and Int. Callbacks run through aslCall, and every array held across one is rooted. */
#include "value.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

static const char *typeName(Tag t) { return t == T_F64ARR ? "F64Array" : t == T_I64ARR ? "I64Array" : "I8Array"; }
static size_t elemSize(Tag t) { return t == T_F64ARR ? 8 : t == T_I64ARR ? 8 : 1; }

Val mkArray(Tag t, size_t n) {
  if (n > MAX_ARRAY_ELEMENTS || n > (SIZE_MAX - 1) / elemSize(t) || n > (size_t)INT64_MAX / elemSize(t))
    aslError("ERR_RANGE", "%s of %zu elements exceeds the array allocation limit", typeName(t), n);
  gcWillAllocate(n * elemSize(t));
  Arr *a = asl_alloc(O_ARR, sizeof(Arr));
  a->elem = elemSize(t); a->len = n;
  a->data = malloc(n * a->elem + 1);
  if (!a->data) aslError("ERR_OOM", "cannot allocate %s of %zu elements", typeName(t), n);
  gcAccount(&a->h, n * a->elem);
  return vobj(t, a);
}

static Arr *arr(Val v, Tag t, const char *who) {
  if (v.tag != t) aslError("ERR_TYPE", "%s expects %s, got %s", who, typeName(t), tagName(v.tag));
  return (Arr *)v.u.o;
}
static int64_t intArg(Val v, const char *who) {
  if (v.tag != T_INT) aslError("ERR_TYPE", "%s expects Int, got %s", who, tagName(v.tag));
  return v.u.i;
}

static Val getElem(Tag t, Arr *a, size_t i) {
  if (t == T_F64ARR) return vfloat(((double *)a->data)[i]);
  if (t == T_I64ARR) return vint(((int64_t *)a->data)[i]);
  return vint(((int8_t *)a->data)[i]);
}
static void setElem(Tag t, Arr *a, size_t i, Val v, const char *who) {
  if (t == T_F64ARR) {
    if (v.tag != T_FLOAT) aslError("ERR_TYPE", "%s: element must be Float, got %s", who, tagName(v.tag));
    ((double *)a->data)[i] = v.u.f;
  } else {
    if (v.tag != T_INT) aslError("ERR_TYPE", "%s: element must be Int, got %s", who, tagName(v.tag));
    if (t == T_I64ARR) ((int64_t *)a->data)[i] = v.u.i;
    else {
      if (v.u.i < -128 || v.u.i > 127) aslError("ERR_RANGE", "%s: %lld outside I8", who, (long long)v.u.i);
      ((int8_t *)a->data)[i] = (int8_t)v.u.i;
    }
  }
}

static Val len(Tag t, Val *a, const char *who) { return vint((int64_t)arr(a[0], t, who)->len); }

static Val get(Tag t, Val *a, const char *who) {
  Arr *x = arr(a[0], t, who); int64_t i = intArg(a[1], who);
  if (i < 0 || (uint64_t)i >= x->len) aslError("ERR_RANGE", "%s index %lld outside length %zu", who, (long long)i, x->len);
  return getElem(t, x, (size_t)i);
}

static Val slice(Tag t, Val *a, const char *who) {
  Arr *x = arr(a[0], t, who); int64_t s = intArg(a[1], who), e = intArg(a[2], who);
  if (s < 0 || e < s || (uint64_t)e > x->len) aslError("ERR_RANGE", "%s [%lld, %lld) outside length %zu", who, (long long)s, (long long)e, x->len);
  Val r = mkArray(t, (size_t)(e - s));
  x = (Arr *)a[0].u.o;
  memcpy(((Arr *)r.u.o)->data, x->data + (size_t)s * x->elem, (size_t)(e - s) * x->elem);
  return r;
}

static Val concat(Tag t, Val *a, const char *who) {
  if (a[0].tag != T_LIST) aslError("ERR_TYPE", "%s expects (List %s), got %s", who, typeName(t), tagName(a[0].tag));
  size_t n = 0;
  for (Obj *c = a[0].u.o; c; c = ((Cons *)c)->cdr.u.o) n += arr(((Cons *)c)->car, t, who)->len;
  Val r = mkArray(t, n);
  Arr *out = (Arr *)r.u.o; size_t at = 0;
  for (Obj *c = a[0].u.o; c; c = ((Cons *)c)->cdr.u.o) {
    Arr *x = (Arr *)((Cons *)c)->car.u.o;
    memcpy(out->data + at * out->elem, x->data, x->len * x->elem); at += x->len;
  }
  return r;
}

static Val generate(Tag t, Val *a, const char *who) {
  int64_t n = intArg(a[0], who);
  if (n < 0) aslError("ERR_RANGE", "%s: negative length %lld", who, (long long)n);
  Val fn = a[1], r = mkArray(t, (size_t)n);
  asl_gc_root_push(&fn); asl_gc_root_push(&r);
  for (int64_t i = 0; i < n; i++) { Val iv = vint(i); setElem(t, (Arr *)r.u.o, (size_t)i, aslCall(fn, 1, &iv), who); }
  asl_gc_root_pop(2);
  return r;
}

static Val sum(Tag t, Val *a, const char *who) {
  Arr *x = arr(a[0], t, who);
  if (t == T_F64ARR) {
    /* Neumaier-compensated, the algorithm of CPython 3.12+ sum(), which the U6 reference values come from */
    double s = 0.0, c = 0.0;
    for (size_t i = 0; i < x->len; i++) {
      double v = ((double *)x->data)[i], u = s + v;
      c += fabs(s) >= fabs(v) ? (s - u) + v : (v - u) + s;
      s = u;
    }
    if (c != 0.0 && isfinite(c)) s += c;
    return vfloat(s);
  }
  int64_t s = 0;
  for (size_t i = 0; i < x->len; i++) if (__builtin_add_overflow(s, getElem(t, x, i).u.i, &s)) aslError("ERR_INT_OVERFLOW", "%s leaves int64", who);
  return vint(s);
}

static Val countEq(Tag t, Val *a, const char *who) {
  Arr *x = arr(a[0], t, who); int64_t k = 0;
  if (t == T_F64ARR) {
    if (a[1].tag != T_FLOAT) aslError("ERR_TYPE", "%s expects Float, got %s", who, tagName(a[1].tag));
    for (size_t i = 0; i < x->len; i++) k += ((double *)x->data)[i] == a[1].u.f;
  } else {
    int64_t v = intArg(a[1], who);
    for (size_t i = 0; i < x->len; i++) k += getElem(t, x, i).u.i == v;
  }
  return vint(k);
}

/* fold f init xs: acc = f(acc, x) left to right; scan keeps every acc, out[i] = f(out[i-1], xs[i]), out[-1] = init */
static Val foldScan(Tag t, Val *a, int keep, const char *who) {
  Val fn = a[0], acc = a[1], xs = a[2], out = VUNIT;
  size_t n = arr(xs, t, who)->len;
  asl_gc_root_push(&fn); asl_gc_root_push(&acc); asl_gc_root_push(&xs); asl_gc_root_push(&out);
  if (keep) out = mkArray(t, n);
  for (size_t i = 0; i < n; i++) {
    Val args[2] = {acc, getElem(t, (Arr *)xs.u.o, i)};
    acc = aslCall(fn, 2, args);
    if (keep) setElem(t, (Arr *)out.u.o, i, acc, who);
  }
  asl_gc_root_pop(4);
  if (keep) return out;
  if (t != T_F64ARR && acc.tag != T_INT) aslError("ERR_TYPE", "%s: accumulator must be Int, got %s", who, tagName(acc.tag));
  return acc;
}

#define OPS(P, T) \
  static Val P##Len(Val *a, int n) { (void)n; return len(T, a, #P "ArrayLen"); } \
  static Val P##Get(Val *a, int n) { (void)n; return get(T, a, #P "ArrayGet"); } \
  static Val P##Slice(Val *a, int n) { (void)n; return slice(T, a, #P "ArraySlice"); } \
  static Val P##Concat(Val *a, int n) { (void)n; return concat(T, a, #P "ArrayConcat"); } \
  static Val P##Generate(Val *a, int n) { (void)n; return generate(T, a, #P "ArrayGenerate"); } \
  static Val P##Sum(Val *a, int n) { (void)n; return sum(T, a, #P "ArraySum"); } \
  static Val P##CountEq(Val *a, int n) { (void)n; return countEq(T, a, #P "ArrayCountEq"); } \
  static Val P##Fold(Val *a, int n) { (void)n; return foldScan(T, a, 0, #P "ArrayFold"); } \
  static Val P##Scan(Val *a, int n) { (void)n; return foldScan(T, a, 1, #P "ArrayScan"); }
OPS(f64, T_F64ARR)
OPS(i64, T_I64ARR)
OPS(i8, T_I8ARR)

#define ROWS(P) \
  {#P "ArrayLen", P##Len, 1, 0}, {#P "ArrayGet", P##Get, 2, 0}, {#P "ArraySlice", P##Slice, 3, 0}, \
  {#P "ArrayConcat", P##Concat, 1, 0}, {#P "ArrayGenerate", P##Generate, 2, 0}, {#P "ArraySum", P##Sum, 1, 0}, \
  {#P "ArrayCountEq", P##CountEq, 2, 0}, {#P "ArrayFold", P##Fold, 3, 0}, {#P "ArrayScan", P##Scan, 3, 0},
const Builtin arrayBuiltins[] = { ROWS(f64) ROWS(i64) ROWS(i8) };
const int nArrayBuiltins = (int)(sizeof arrayBuiltins / sizeof arrayBuiltins[0]);

/* a native binary's call of one of these by name (asl-target-llvm builtinTableSym); referencing it links this table */
Val asl_rt_builtin_array(const char *name, int64_t argc, Val *argv) { return builtinCallIn(arrayBuiltins, nArrayBuiltins, name, argc, argv); }
