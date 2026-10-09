/* asl check: the same reader, loader, compiler and type pass as test and run, plus static arity, enum exhaustiveness
   and effect markers (LS1). */
#include "compile.h"
#include <stdio.h>
#include <string.h>

Module **buildProgram(const char *path, int checkMode, int *count, Diags *d) {
  d->checkMode = checkMode;
  Module **mods = loadGraph(path, count, d);
  if (!mods || d->n) return mods;
  for (int i = 0; i < *count; i++) compileModule(mods[i], d);
  /* Type checking normally waits for clean compilation.  An unresolved export is different: the
     type walk can still discover further private-constructor references (notably mt patterns),
     and must not hide them behind the first ERR_NOT_EXPORTED.  Keep the old phase boundary for
     every other compile error. */
  int onlyNotExported = d->n > 0;
  for (int i = 0; i < d->n; i++)
    if (!strstr(d->msgs[i], ": ERR_NOT_EXPORTED ")) onlyNotExported = 0;
  if (!d->n || onlyNotExported) for (int i = 0; i < *count; i++) typeCheckModule(mods[i], d);
  if (checkMode) effectCheckModules(mods, *count, d);
  return mods;
}

void printDiags(Diags *d) {
  fflush(stdout);
  for (int i = 0; i < d->n; i++) fprintf(stderr, "%s\n", d->msgs[i]);
}

int cmdCheck(const char *path) {
  Diags d = {0}; int n = 0;
  buildProgram(path, 1, &n, &d);
  if (d.n) { printDiags(&d); fprintf(stderr, "check failed: %s: %d error(s)\n", path, d.n); return 1; }
  printf("ok %s: %d module(s) checked\n", path, n);
  return 0;
}
