/* asl test and asl run: the I5 entry protocol. Nothing runs unless the whole graph loads and compiles (I1). */
#include "compile.h"
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static Def *entryDef(Module *m, const char *name) {
  if (!moduleExports(m, name)) return NULL;
  Def *df = moduleDef(m, intern(name, strlen(name)));
  return df && df->kind == DEF_FN ? df : NULL;
}

static Val argList(int argc, char **argv) {
  Val acc = VNIL;
  asl_gc_root_push(&acc);
  for (int i = argc - 1; i >= 0; i--) { Val s = mkStr(argv[i], strlen(argv[i])); acc = mkCons(s, acc); }
  asl_gc_root_pop(1);
  return acc;
}

/* imports before importers, each module once, iteratively so a deep import chain never touches the C stack */
static void runInits(Module **mods, int n, int testMode) {
  Module **stk = malloc(sizeof(Module *) * (size_t)(n + 1)); int *next = calloc((size_t)n + 1, sizeof(int)), *state = calloc((size_t)n + 1, sizeof(int)), sp = 0;
  if (!stk || !next || !state) aslError("ERR_OOM", "module order");
  for (int r = 0; r < n; r++) {
    if (state[r]) continue;
    stk[sp++] = mods[r]; state[r] = 1;
    while (sp) {
      Module *m = stk[sp - 1]; int mi = 0;
      while (mods[mi] != m) mi++;
      if (next[mi] < m->nimports) {
        if (!strcmp(symName(m->imports[next[mi]].path), "sys")) { next[mi]++; continue; } Module *c = m->imports[next[mi]++].m; int ci = 0;
        while (mods[ci] != c) ci++;
        if (!state[ci]) { state[ci] = 1; stk[sp++] = c; }
        continue;
      }
      sp--;
      if (m->init) {
        if (testMode) initModuleName = symName(m->name);
        vmRunProto(m->init);
        initModuleName = NULL;
      }
    }
  }
  free(stk); free(next); free(state);
}

static int isCtor(Val v, int name) { return v.tag == T_CTOR && ((Ctor *)v.u.o)->ctor == name; }

/* mode 0 = test, 1 = run, 2 = test when the entry exports runTests and run otherwise (a built artifact) */
int cmdRun(const char *path, int mode, int argc, char **argv) {
  Diags d = {0}; int n = 0;
  Module **mods = buildProgram(path, 0, &n, &d);
  if (!mods || d.n) {
    printDiags(&d);
    fprintf(stderr, "FAIL %s: %d load error(s) (after %ld asserts)\n", path, d.n, assertCount);
    return 1;
  }
  Module *m = mods[0];
  if (mode == 2) mode = entryDef(m, "runTests") ? 0 : 1;
  jmp_buf jb; void *previous = aslErrorHandlerGet();
  aslErrorHandlerSet(&jb);
  if (setjmp(jb)) {
    initModuleName = NULL;
    fflush(stdout);
    printErrorSite();
    fprintf(stderr, "FAIL %s: %s (after %ld asserts)\n", path, aslErrorMsg, assertCount);
    aslErrorHandlerSet(previous);
    return 1;
  }
  runInits(mods, n, mode == 0);
  int exitCode = 0;
  Def *rt = mode == 0 ? entryDef(m, "runTests") : NULL;
  Def *mn = rt ? NULL : entryDef(m, "main");
  if (!rt && !mn) aslError("ERR_NO_ENTRY", "%s exports neither %smain", path, mode == 0 ? "runTests nor " : "");
  if (rt) {
    if (rt->arity != 0) aslError("ERR_ARITY", "runTests must take no arguments");
    Val r = vmCall(globals[rt->gidx], 0, NULL);
    if (r.tag != T_BOOL || !r.u.i) { char *s = valToCStrShort(r, 1); aslError("ERR_TEST_FAILED", "runTests returned %s, not true", s); }
  } else {
    Val args = argList(mode == 1 ? argc : 0, argv);
    asl_gc_root_push(&args);
    Val r = mn->arity == 0 ? vmCall(globals[mn->gidx], 0, NULL) : vmCall(globals[mn->gidx], 1, &args);
    asl_gc_root_pop(1);
    if (mode == 1 && r.tag == T_INT) {
      int64_t code = r.u.i;
      if (code < 0 || code > 255) aslError("ERR_RANGE", "main returned %lld, exit codes are 0..255", (long long)code);
      exitCode = (int)code;
    } else {
      if (!isCtor(r, KW_OK)) { char *s = valToCStrShort(r, 1); aslError(mode == 0 ? "ERR_TEST_FAILED" : "ERR_MAIN_FAILED", "main returned %s, not (ok ...)", s); }
      Ctor *ok = (Ctor *)r.u.o;
      if (mode == 1 && ok->n == 1 && ok->f[0].tag == T_INT) {
        int64_t code = ok->f[0].u.i;
        if (code < 0 || code > 255) aslError("ERR_RANGE", "main returned (ok %lld), exit codes are 0..255", (long long)code);
        exitCode = (int)code;
      }
    }
  }
  if (mode == 0) {
    if (assertCount + refuteCount <= 0) aslError("ERR_TEST_FAILED", "zero assertions executed");
    if (refuteCount) printf("%s: %ld assertion(s) executed, %ld refutation(s) executed (%ld passed)\n", path, assertCount, refuteCount, assertCount + refuteCount);
    else printf("%s: %ld assertion(s) executed (%ld passed)\n", path, assertCount, assertCount);
  }
  aslErrorHandlerSet(previous);
  return exitCode;
}
