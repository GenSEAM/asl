/* asl build (plan R1 H11, decision Q5): the artifact is a C stub holding every module source of the checked graph
   and its import resolutions, linked by /usr/bin/cc against libaslhost.a beside this executable; the linker
   ad-hoc signs it. The artifact runs the I5 entry reading no module from disk: exported runTests as asl test
   does, otherwise main as asl run does. */
#include "compile.h"
#include <limits.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
int cmdRun(const char *path, int mode, int argc, char **argv);

int embedMain(const EmbedModule *mods, int nmods, const EmbedImport *imps, int nimps, int argc, char **argv) {
  gcInit(); vmInit();
  embedMods = mods; nembedMods = nmods; embedImports = imps; nembedImports = nimps;
  return cmdRun(mods[0].path, 2, argc - 1, argv + 1);
}

static void cString(FILE *f, const char *s) {
  fputc('"', f);
  for (; *s; s++) {
    unsigned char c = (unsigned char)*s;
    if (c == '"' || c == '\\') fprintf(f, "\\%c", c);
    else if (c < 32 || c > 126) fprintf(f, "\\%03o", c);
    else fputc(c, f);
  }
  fputc('"', f);
}

static int writeStub(const char *stub, Module **mods, int n, char *err, size_t errlen) {
  FILE *f = fopen(stub, "w");
  if (!f) { snprintf(err, errlen, "cannot write %s", stub); return -1; }
  fprintf(f, "typedef struct { const char *path; const unsigned char *src; unsigned long len; } EmbedModule;\n"
             "typedef struct { const char *importer, *importPath, *resolved; } EmbedImport;\n"
             "int embedMain(const EmbedModule *, int, const EmbedImport *, int, int, char **);\n");
  int nimps = 0; long *lens = calloc((size_t)n + 1, sizeof(long));
  if (!lens) { fclose(f); snprintf(err, errlen, "out of memory"); return -1; }
  for (int i = 0; i < n; i++) {
    FILE *s = fopen(mods[i]->path, "rb");
    if (!s) { fclose(f); free(lens); snprintf(err, errlen, "cannot read %s", mods[i]->path); return -1; }
    fprintf(f, "static const unsigned char s%d[] = {", i);
    long len = 0; int c;
    while ((c = fgetc(s)) != EOF) { fprintf(f, "%s%d", len % 32 ? "," : len ? ",\n" : "", c); len++; }
    fclose(s); lens[i] = len;
    fprintf(f, "%s};\n", len ? "" : "0");
    for (int j = 0; j < mods[i]->nimports; j++) if (strcmp(symName(mods[i]->imports[j].path), "sys")) nimps++;
  }
  fprintf(f, "static const EmbedModule mods[] = {\n");
  for (int i = 0; i < n; i++) { fprintf(f, "  {"); cString(f, mods[i]->path); fprintf(f, ", s%d, %ldul},\n", i, lens[i]); }
  free(lens);
  fprintf(f, "};\nstatic const EmbedImport imps[] = {\n");
  for (int i = 0; i < n; i++)
    for (int j = 0; j < mods[i]->nimports; j++) { if (!strcmp(symName(mods[i]->imports[j].path), "sys")) continue;
      fprintf(f, "  {"); cString(f, mods[i]->path); fputs(", ", f); cString(f, symName(mods[i]->imports[j].path));
      fputs(", ", f); cString(f, mods[i]->imports[j].m->path); fputs("},\n", f);
    }
  fprintf(f, "%s};\nint main(int argc, char **argv) { return embedMain(mods, %d, imps, %d, argc, argv); }\n", nimps ? "" : "  {0, 0, 0}\n", n, nimps);
  if (fclose(f) != 0) { snprintf(err, errlen, "cannot write %s", stub); return -1; }
  return 0;
}

int cmdBuild(int argc, char **argv) {
  const char *in = NULL, *out = NULL;
  for (int i = 2; i < argc; i++) {
    if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
    else in = argv[i];
  }
  if (!in || !out) { fprintf(stderr, "usage: asl build FILE -o OUT\n"); return 2; }
  Diags d = {0}; int n = 0;
  Module **mods = buildProgram(in, 1, &n, &d);
  if (!mods || d.n) { printDiags(&d); fprintf(stderr, "build: %s fails check; %s not written\n", in, out); return 1; }
  char exe[PATH_MAX], self[PATH_MAX], lib[PATH_MAX + 16], dir[] = "/tmp/aslBuildXXXXXX", stub[64], part[PATH_MAX + 16], err[PATH_MAX + 64];
  if (!hostGetExecutablePath(exe, sizeof exe) || !realpath(exe, self)) { fprintf(stderr, "ERR_BUILD: cannot locate this executable\n"); return 1; }
  const char *sanitizeEnv = getenv("ASL_BUILD_SANITIZE"); int sanitize = !strcmp(strrchr(self, '/') + 1, "asl-host-asan") || (sanitizeEnv && !strcmp(sanitizeEnv, "1"));
  *strrchr(self, '/') = 0;
  snprintf(lib, sizeof lib, "%s/%s", self, sanitize ? "libaslhost-asan.a" : "libaslhost.a");
  if (access(lib, R_OK) != 0) { fprintf(stderr, "ERR_BUILD: %s missing; run asl/host/build.sh\n", lib); return 1; }
  if (!mkdtemp(dir)) { fprintf(stderr, "ERR_BUILD: cannot create a temporary directory\n"); return 1; }
  snprintf(stub, sizeof stub, "%s/stub.c", dir);
  snprintf(part, sizeof part, "%s.part%d", out, (int)getpid());
  int rc = 1;
  if (writeStub(stub, mods, n, err, sizeof err) != 0) fprintf(stderr, "ERR_BUILD: %s\n", err);
  else {
    const char *cc = getenv("CC"); if (!cc || !*cc) cc = "cc";
    char *plainArgs[] = {(char *)cc, "-O2", "-o", part, stub, lib, "-lm", NULL}; char *sanitizedArgs[] = {(char *)cc, "-O1", "-g", "-fno-omit-frame-pointer", "-fsanitize=address,undefined", "-o", part, stub, lib, "-lm", NULL}; char **ccArgs = sanitize ? sanitizedArgs : plainArgs;
    pid_t pid; int st = 0;
    if (posix_spawnp(&pid, ccArgs[0], NULL, NULL, ccArgs, environ) != 0 || waitpid(pid, &st, 0) != pid) fprintf(stderr, "ERR_BUILD: cannot run %s\n", cc);
    else if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) fprintf(stderr, "ERR_BUILD: %s failed for %s\n", cc, in);
    else if (rename(part, out) != 0) fprintf(stderr, "ERR_BUILD: cannot write %s\n", out);
    else { rc = 0; printf("built %s: %d module(s) embedded\n", out, n); }
  }
  if (rc) unlink(part);
  unlink(stub); rmdir(dir);
  return rc;
}
