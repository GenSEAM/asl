/* Command verbs of asl-host (main.c), in libaslhost.a. */
#include "compile.h"
#include <errno.h>
#include <limits.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

int cmdCheck(const char *path);
int cmdRun(const char *path, int mode, int argc, char **argv);
int cmdBuild(int argc, char **argv);
int cmdLegacy(char **argv);

static int cmdParse(const char *path) {
  Unit u; char err[2048];
  if (readFile(path, &u, err, sizeof err) != 0) { fprintf(stderr, "%s\n", err); return 1; }
  int n = 0;
  for (int i = 0; i < u.n; i++) if (u.items[i]->col == 0) n++;
  printf("%d top-level form(s)\n", n);
  return 0;
}

/* test and check take several files, each in its own process so no module state carries over. */
static int eachFile(int argc, char **argv, int check) {
  if (argc == 3) return check ? cmdCheck(argv[2]) : cmdRun(argv[2], 0, 0, NULL);
  /* (:m :why "an inherited ignored SIGCHLD lets the kernel reap children, so waitpid would lose every verdict") */
  int rc = 0; void (*oldChld)(int) = signal(SIGCHLD, SIG_DFL);
  for (int i = 2; i < argc; i++) {
    fflush(NULL); pid_t pid = fork(), w;
    if (pid < 0) { perror("asl-host: fork"); for (int j = i; j < argc; j++) fprintf(stderr, "FAIL %s: not run (could not fork child)\n", argv[j]); if (!rc) rc = 2; break; }
    if (pid == 0) exit(check ? cmdCheck(argv[i]) : cmdRun(argv[i], 0, 0, NULL));
    int st = 0; while ((w = waitpid(pid, &st, 0)) < 0 && errno == EINTR) {}
    if (w < 0) { perror("asl-host: waitpid"); fprintf(stderr, "FAIL %s: child result unavailable\n", argv[i]); if (!rc) rc = 2; continue; }
    int r = WIFEXITED(st) ? WEXITSTATUS(st) : WIFSIGNALED(st) ? 128 + WTERMSIG(st) : 2;
    if (WIFSIGNALED(st)) fprintf(stderr, "FAIL %s: killed by signal %d\n", argv[i], WTERMSIG(st)); else if (!WIFEXITED(st)) fprintf(stderr, "FAIL %s: child ended without an exit status\n", argv[i]);
    if (r && !rc) rc = r;
  }
  if (oldChld != SIG_ERR) signal(SIGCHLD, oldChld);
  return rc;
}

int preludeLocate(char *out);
extern Module *preludeModule;

int cmdLegacy(char **argv) {
  char self[PATH_MAX], path[PATH_MAX + 32], exe[PATH_MAX];
  if (!hostGetExecutablePath(exe, sizeof exe) || !realpath(exe, self)) { fprintf(stderr, "ERR_UNSUPPORTED_SUBCOMMAND: %s (cannot locate this executable)\n", argv[1]); return 2; }
  char *s = strrchr(self, '/'); if (s) *s = 0;
  int n = snprintf(path, sizeof path, "%s/asl-core-legacy", self);
  if (n < 0 || (size_t)n >= sizeof path) { fprintf(stderr, "ERR_PATH_TOO_LONG: %s/asl-core-legacy\n", self); return 2; }
  if (access(path, X_OK) != 0) { fprintf(stderr, "ERR_UNSUPPORTED_SUBCOMMAND: %s (no asl-core-legacy beside %s)\n", argv[1], self); return 2; }
  argv[0] = path;
  execv(path, argv);
  fprintf(stderr, "ERR_EXEC: cannot exec %s\n", path);
  return 2;
}

/* eval sees the prelude: it is loaded, compiled and initialised first. */
static int cmdEval(const char *src) {
  Unit u; char err[2048], pre[PATH_MAX];
  if (!preludeLocate(pre)) { fprintf(stderr, "ERR_IO: prelude.asl not found (set ASL_PRELUDE or install it beside asl-host)\n"); return 1; }
  Diags pd = {0}; int np = 0;
  Module **pm = buildProgram(pre, 0, &np, &pd);
  if (!pm || pd.n) { printDiags(&pd); return 1; }
  if (readSource("<eval>", src, strlen(src), &u, err, sizeof err) != 0) { fprintf(stderr, "%s\n", err); return 1; }
  Module m = {0}; m.path = "<eval>"; m.unit = u; m.name = -1;
  Diags d = {0};
  int nf = 0;
  for (int i = 0; i < u.n; i++) nf += u.items[i]->n;
  Node **forms = malloc(sizeof(Node *) * (size_t)(nf + 1)); int k = 0;
  if (!forms) exit(70);
  for (int i = 0; i < u.n; i++) for (int j = 0; j < u.items[i]->n; j++) forms[k++] = u.items[i]->kids[j];
  Proto *p = compileExpr(&m, forms, nf, &d);
  if (!d.n) typeCheckForms(&m, forms, nf, &d);
  if (d.n) { printDiags(&d); return 1; }
  jmp_buf jb; void *previous = aslErrorHandlerGet();
  aslErrorHandlerSet(&jb);
  if (setjmp(jb)) { fflush(stdout); printErrorSite(); fprintf(stderr, "%s\n", aslErrorMsg); aslErrorHandlerSet(previous); return 1; }
  Val v = vmRunProto(p);
  valPrint(stdout, v, 1); fputc('\n', stdout);
  aslErrorHandlerSet(previous);
  return 0;
}

/* Each call owns its VM frame boundary. A nested verb may catch a runtime error; restore the caller's
   frame and stack before returning across the native ABI. */
int cmdHostVerb(int argc, char **argv) {
  void *stackPointer; int framePointer;
  vmStateSave(&stackPointer, &framePointer);
  Module *previousPrelude = preludeModule;
  const EmbedModule *previousEmbedMods = embedMods; int previousNEmbedMods = nembedMods;
  const EmbedImport *previousEmbedImports = embedImports; int previousNEmbedImports = nembedImports;
  if (embedMods) { embedMods = NULL; nembedMods = 0; embedImports = NULL; nembedImports = 0; }
  int rc = 2;
  if (argc < 2) {
    fprintf(stderr, "usage: asl-host eval EXPR | test FILE... | check FILE... | run FILE [ARGS] | parse FILE | build FILE -o OUT | --version\n");
  } else {
    const char *cmd = argv[1];
    if (!strcmp(cmd, "--version") || !strcmp(cmd, "version")) { printf("asl-host 0.1.0 stage-0\n"); rc = 0; }
    else if (!strcmp(cmd, "eval") && argc >= 3) rc = cmdEval(argv[2]);
    else if (!strcmp(cmd, "test") && argc >= 3) rc = eachFile(argc, argv, 0);
    else if (!strcmp(cmd, "run") && argc >= 3) rc = cmdRun(argv[2], 1, argc - 3, argv + 3);
    else if ((!strcmp(cmd, "check") || !strcmp(cmd, "lint")) && argc >= 3) rc = eachFile(argc, argv, 1);
    else if (!strcmp(cmd, "parse") && argc >= 3) rc = cmdParse(argv[2]);
    else if (!strcmp(cmd, "build")) rc = cmdBuild(argc, argv);
    else rc = cmdLegacy(argv);
  }
  preludeModule = previousPrelude;
  embedMods = previousEmbedMods; nembedMods = previousNEmbedMods;
  embedImports = previousEmbedImports; nembedImports = previousNEmbedImports;
  vmStateRestore(stackPointer, framePointer);
  return rc;
}
