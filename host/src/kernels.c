/* Float64 array kernels without callbacks: dot, axpy, and gemm (plan CC6).
   Written with restrict pointers and simple loops so clang auto-vectorises. */
#include "value.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>



static Arr *arrF64(Val v, const char *who) {
  if (v.tag != T_F64ARR) aslError("ERR_TYPE", "%s expects F64Array, got %s", who, tagName(v.tag));
  return (Arr *)v.u.o;
}

static Val bDot(Val *a, int n) {
  (void)n;
  Arr *x = arrF64(a[0], "dot");
  Arr *y = arrF64(a[1], "dot");
  if (x->len != y->len)
    aslError("ERR_SHAPE", "dot: array lengths differ (%zu vs %zu)", x->len, y->len);
  if (x->len == 0) return vfloat(0.0);
  const double *restrict px = (const double *)x->data;
  const double *restrict py = (const double *)y->data;
  double sum = 0.0;
  for (size_t i = 0; i < x->len; i++) {
    sum += px[i] * py[i];
  }
  return vfloat(sum);
}

static Val bAxpy(Val *a, int n) {
  (void)n;
  if (a[0].tag != T_FLOAT || a[1].tag != T_F64ARR || a[2].tag != T_F64ARR) {
    aslError("ERR_TYPE", "axpy expects (Float, F64Array, F64Array)");
  }
  double alpha = a[0].u.f;
  Arr *x = (Arr *)a[1].u.o;
  Arr *y = (Arr *)a[2].u.o;
  if (x->len != y->len)
    aslError("ERR_SHAPE", "axpy: array lengths differ (%zu vs %zu)", x->len, y->len);
  Val res = mkArray(T_F64ARR, x->len);
  Arr *out = (Arr *)res.u.o;
  if (x->len == 0) return res;
  const double *restrict px = (const double *)x->data;
  const double *restrict py = (const double *)y->data;
  double *restrict po = (double *)out->data;
  for (size_t i = 0; i < x->len; i++) {
    po[i] = alpha * px[i] + py[i];
  }
  return res;
}

static Val bGemm(Val *args, int argc) {
  (void)argc;
  if (args[0].tag != T_INT || args[1].tag != T_INT || args[2].tag != T_INT ||
      args[3].tag != T_F64ARR || args[4].tag != T_F64ARR) {
    aslError("ERR_TYPE", "gemm expects (m: Int, n: Int, k: Int, a: F64Array, b: F64Array)");
  }
  int64_t m = args[0].u.i;
  int64_t n = args[1].u.i;
  int64_t k = args[2].u.i;
  Arr *a = (Arr *)args[3].u.o;
  Arr *b = (Arr *)args[4].u.o;

  if (m < 0 || n < 0 || k < 0)
    aslError("ERR_RANGE", "gemm: negative matrix dimensions (m=%lld, n=%lld, k=%lld)",
             (long long)m, (long long)n, (long long)k);
  if (m > 0 && k > 0 && (size_t)m > (SIZE_MAX / sizeof(double)) / (size_t)k)
    aslError("ERR_RANGE", "gemm: m * k exceeds addressable range");
  if (k > 0 && n > 0 && (size_t)k > (SIZE_MAX / sizeof(double)) / (size_t)n)
    aslError("ERR_RANGE", "gemm: k * n exceeds addressable range");
  if (m > 0 && n > 0 && (size_t)m > (SIZE_MAX / sizeof(double)) / (size_t)n)
    aslError("ERR_RANGE", "gemm: m * n exceeds addressable range");

  size_t need_a = (size_t)m * (size_t)k;
  size_t need_b = (size_t)k * (size_t)n;
  size_t need_c = (size_t)m * (size_t)n;

  if (a->len != need_a)
    aslError("ERR_SHAPE", "gemm: array A length %zu does not match m*k = %zu", a->len, need_a);
  if (b->len != need_b)
    aslError("ERR_SHAPE", "gemm: array B length %zu does not match k*n = %zu", b->len, need_b);

  Val res = mkArray(T_F64ARR, need_c);
  Arr *c = (Arr *)res.u.o;
  if (need_c == 0) return res;
  memset(c->data, 0, need_c * sizeof(double));
  if (k == 0) return res;

  const double *restrict pa = (const double *)a->data;
  const double *restrict pb = (const double *)b->data;
  double *restrict pc = (double *)c->data;

  size_t sm = (size_t)m, sn = (size_t)n, sk = (size_t)k;
  for (size_t i = 0; i < sm; i++) {
    for (size_t p = 0; p < sk; p++) {
      double a_ip = pa[i * sk + p];
      for (size_t j = 0; j < sn; j++) {
        pc[i * sn + j] += a_ip * pb[p * sn + j];
      }
    }
  }
  return res;
}

const Builtin kernelBuiltins[] = {
  {"dot", bDot, 2, 0},
  {"axpy", bAxpy, 3, 0},
  {"gemm", bGemm, 5, 0},
};
const int nKernelBuiltins = (int)(sizeof kernelBuiltins / sizeof kernelBuiltins[0]);

/* a native binary's call of one of these by name (asl-target-llvm builtinTableSym); referencing it links this table */
Val asl_rt_builtin_kernel(const char *name, int64_t argc, Val *argv) { return builtinCallIn(kernelBuiltins, nKernelBuiltins, name, argc, argv); }
