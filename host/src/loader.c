/* Module loader per I12: resolve the whole import graph before anything runs; cwd and the importing file's own
   directory are never roots, save a deprecated leading ../ path (D148), which warns and stays inside the root. */
#include "compile.h"
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int exists(const char *p) { return access(p, R_OK) == 0; }
static void parentDir(char *p) { char *s = strrchr(p, '/'); if (s == p) p[1] = 0; else if (s) *s = 0; }

/* :workspace "W" from a config file, read structurally: the value after a :workspace keyword among the top-level
   list's own items, or empty */
static void workspaceOf(const char *dir, char *w, size_t wl) {
  char path[PATH_MAX + 32], err[1024]; Unit u; w[0] = 0;
  snprintf(path, sizeof path, "%s/.asl.config.asn", dir);
  if (readFile(path, &u, err, sizeof err) != 0 || u.n < 1 || u.items[0]->n < 1) return;
  Node *l = u.items[0]->kids[0];
  if (l->kind != N_LIST) return;
  for (int i = 1; i + 1 < l->n; i++)
    if (l->kids[i]->kind == N_KW && !strcmp(symName(l->kids[i]->sym), "workspace") && l->kids[i + 1]->kind == N_STR) {
      snprintf(w, wl, "%s", l->kids[i + 1]->s);
      return;
    }
}

/* Resolve a declared external package only from its configured directory. Relative paths are rooted at the config; :repo is a local-directory alias for :path, not clone/fetch. */
static int declaredDependency(const char *configDir, const char *name, char *dir, size_t dl, char *rev, size_t rl,
                              char *note, size_t nl) {
  char path[PATH_MAX + 32], err[1024]; Unit u;
  if (dl < PATH_MAX) { snprintf(note, nl, " dependency path buffer is too small"); return -1; }
  snprintf(path, sizeof path, "%s/.asl.config.asn", configDir);
  if (readFile(path, &u, err, sizeof err) != 0) {
    snprintf(note, nl, " cannot read package declarations in %s: %.300s", path, err);
    return -1;
  }
  if (u.n < 1 || u.items[0]->n < 1 || u.items[0]->kids[0]->kind != N_LIST) return 0;
  Node *root = u.items[0]->kids[0];
  for (int i = 1; i + 1 < root->n; i++) {
    Node *key = root->kids[i], *value = root->kids[i + 1];
    if (key->kind != N_KW || strcmp(symName(key->sym), "dependencies") ||
        (value->kind != N_LIST && value->kind != N_VEC)) continue;
    for (int j = 0; j < value->n; j++) {
      Node *entry = value->kids[j];
      if (entry->kind != N_LIST || entry->n < 1) continue;
      Node *package = entry->kids[0];
      const char *packageName = package->kind == N_SYM ? symName(package->sym) : package->kind == N_STR ? package->s : "";
      if (strcmp(packageName, name)) continue;
      const char *location = NULL;
      rev[0] = 0;
      for (int k = 1; k + 1 < entry->n; k++) {
        Node *field = entry->kids[k], *v = entry->kids[k + 1];
        if (field->kind != N_KW || v->kind != N_STR) continue;
        const char *fieldName = symName(field->sym);
        if (!strcmp(fieldName, "path") || !strcmp(fieldName, "repo")) location = v->s;
        else if (!strcmp(fieldName, "rev")) snprintf(rev, rl, "%s", v->s);
      }
      if (!location || !*location) {
        snprintf(note, nl, " dependency %s must declare :path or :repo", name);
        return -1;
      }
      char candidate[PATH_MAX];
      int n = location[0] == '/' ? snprintf(candidate, sizeof candidate, "%s", location)
                                 : snprintf(candidate, sizeof candidate, "%s/%s", configDir, location);
      struct stat st;
      if (n < 0 || (size_t)n >= sizeof candidate || !realpath(candidate, dir) || stat(dir, &st) != 0 || !S_ISDIR(st.st_mode)) {
        snprintf(note, nl, " dependency %s directory is unavailable: %s", name, candidate);
        return -1;
      }
      return 1;
    }
  }
  return 0;
}

/* Run git without a shell: configured paths may contain shell metacharacters. :rev compares HEAD only, not dirty or untracked working-tree changes. */
static int gitHead(const char *dir, char *head, size_t hl) {
  int fds[2];
  if (pipe(fds) != 0) return -1;
  pid_t pid = fork();
  if (pid < 0) { close(fds[0]); close(fds[1]); return -1; }
  if (pid == 0) {
    close(fds[0]);
    if (dup2(fds[1], STDOUT_FILENO) < 0) _exit(126);
    close(fds[1]);
    int nullfd = open("/dev/null", O_WRONLY);
    if (nullfd >= 0) { dup2(nullfd, STDERR_FILENO); close(nullfd); }
    execlp("git", "git", "-C", dir, "rev-parse", "HEAD", (char *)NULL);
    _exit(127);
  }
  close(fds[1]);
  size_t got = 0; ssize_t n;
  while ((n = read(fds[0], head + got, hl - got - 1)) > 0) {
    got += (size_t)n;
    if (got == hl - 1) break;
  }
  int readError = n < 0;
  close(fds[0]);
  int status = 0; pid_t waited;
  do { waited = waitpid(pid, &status, 0); } while (waited < 0 && errno == EINTR);
  if (readError || waited < 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0 || got == 0 || got == hl - 1) return -1;
  while (got && (head[got - 1] == '\n' || head[got - 1] == '\r')) got--;
  head[got] = 0;
  return got ? 0 : -1;
}

/* a candidate counts only if it exists and its realpath stays under the root it was resolved against */
static int within(const char *cand, const char *root, char *real) {
  char rr[PATH_MAX];
  if (!realpath(cand, real) || !realpath(root, rr)) return 0;
  size_t n = strlen(rr);
  return !strncmp(real, rr, n) && (real[n] == '/' || (n == 1 && rr[0] == '/'));
}

/* D148 module index: every (module NAME ...) header and every manifest.asn (:package NAME ... :dependencies [...])
   under the workspace root, built once per root on the first import the path rules miss. The walk skips dot and
   node_modules directories and never follows a symlink, so nothing outside the root enters it. */
typedef struct { char *name, *path; } IdxMod;
typedef struct { char *name, *base, *dir; char **deps; int ndeps; } IdxPkg;
static struct { char root[PATH_MAX], skippedAt[PATH_MAX]; IdxMod *m; int nm, capm; IdxPkg *p; int np, capp, skipped; } ix;

/* an unreadable directory or manifest leaves the index partial; the count reaches every unresolved-import diagnostic */
static void skip(const char *path) { if (!ix.skipped++) snprintf(ix.skippedAt, sizeof ix.skippedAt, "%s", path); }

static void *grow(void *a, int n, int *cap, size_t sz) {
  if (n < *cap) return a;
  *cap = *cap ? *cap * 2 : 64;
  if (!(a = realloc(a, sz * (size_t)*cap))) exit(70);
  return a;
}

static char *dupStr(const char *s) { char *r = strdup(s); if (!r) exit(70); return r; }

static const char *lastSeg(const char *s) { const char *p = strrchr(s, '/'); return p ? p + 1 : s; }

static int under(const char *path, const char *dir) { size_t n = strlen(dir); return !strncmp(path, dir, n) && path[n] == '/'; }

/* the NAME of a leading (module NAME ...), read from the first 4 KiB of an .asl file */
static int headerName(const char *path, char *name, size_t nl) {
  char buf[4096]; FILE *f = fopen(path, "r");
  if (!f) return 0;
  size_t n = fread(buf, 1, sizeof buf - 1, f); fclose(f); buf[n] = 0;
  const char *s = buf;
  for (;;) {
    while (isspace((unsigned char)*s)) s++;
    if (*s != ';') break;
    while (*s && *s != '\n') s++;
  }
  if (*s++ != '(') return 0;
  while (isspace((unsigned char)*s)) s++;
  if (strncmp(s, "module", 6) || !isspace((unsigned char)s[6])) return 0;
  s += 6;
  while (isspace((unsigned char)*s)) s++;
  size_t k = strcspn(s, " \t\r\n()[]{}\";");
  if (k == 0 || k >= nl || !s[k]) return 0;
  memcpy(name, s, k); name[k] = 0;
  return 1;
}

static void indexManifest(const char *dir, const char *path) {
  char err[1024]; Unit u;
  if (readFile(path, &u, err, sizeof err) != 0) { skip(path); return; }
  if (u.n < 1 || u.items[0]->n < 1) return;
  Node *l = u.items[0]->kids[0];
  if (l->kind != N_LIST || l->n < 2 || l->kids[0]->kind != N_KW || strcmp(symName(l->kids[0]->sym), "package")) return;
  ix.p = grow(ix.p, ix.np, &ix.capp, sizeof(IdxPkg));
  IdxPkg *p = &ix.p[ix.np++];
  memset(p, 0, sizeof *p);
  p->dir = dupStr(dir); p->base = dupStr(lastSeg(dir));
  if (l->kids[1]->kind == N_SYM) p->name = dupStr(symName(l->kids[1]->sym));
  else if (l->kids[1]->kind == N_STR) p->name = dupStr(l->kids[1]->s);
  for (int i = 2; i + 1 < l->n; i++) {
    Node *k = l->kids[i], *v = l->kids[i + 1];
    if (k->kind != N_KW || strcmp(symName(k->sym), "dependencies") || (v->kind != N_VEC && v->kind != N_LIST)) continue;
    if (!(p->deps = calloc((size_t)v->n + 1, sizeof(char *)))) exit(70);
    for (int j = 0; j < v->n; j++)
      if (v->kids[j]->kind == N_STR) p->deps[p->ndeps++] = dupStr(v->kids[j]->s);
      else if (v->kids[j]->kind == N_SYM) p->deps[p->ndeps++] = dupStr(symName(v->kids[j]->sym));
  }
}

static void walk(char *path, size_t len, int depth) {
  DIR *d = depth < 64 ? opendir(path) : NULL;
  if (!d) { skip(path); return; }
  for (struct dirent *e; (e = readdir(d));) {
    size_t el = strlen(e->d_name);
    if (e->d_name[0] == '.' || !strcmp(e->d_name, "node_modules")) continue;
    if (len + el + 2 > PATH_MAX) { skip(path); continue; }
    path[len] = '/'; memcpy(path + len + 1, e->d_name, el + 1);
    int type = e->d_type; struct stat st;
    if (type == DT_UNKNOWN && lstat(path, &st) == 0) type = S_ISDIR(st.st_mode) ? DT_DIR : S_ISREG(st.st_mode) ? DT_REG : DT_LNK;
    char name[512];
    if (type == DT_DIR) walk(path, len + 1 + el, depth + 1);
    else if (type == DT_REG && el > 4 && !strcmp(e->d_name + el - 4, ".asl") && headerName(path, name, sizeof name)) {
      ix.m = grow(ix.m, ix.nm, &ix.capm, sizeof(IdxMod));
      ix.m[ix.nm].name = dupStr(name); ix.m[ix.nm++].path = dupStr(path);
    } else if (type == DT_REG && !strcmp(e->d_name, "manifest.asn")) {
      char file[PATH_MAX]; snprintf(file, sizeof file, "%s", path);
      path[len] = 0; indexManifest(path, file);
    }
    path[len] = 0;
  }
  closedir(d);
}

static void ensureIndex(const char *root) {
  if (ix.root[0] && !strcmp(ix.root, root)) return;
  snprintf(ix.root, sizeof ix.root, "%s", root);
  ix.nm = ix.np = ix.skipped = 0;
  char path[PATH_MAX]; snprintf(path, sizeof path, "%s", root);
  walk(path, strlen(path), 0);
}

/* candidate modules for one import, deduplicated by path; the first 8 are kept for the diagnostic */
typedef struct { const char *path[8], *name[8]; int n; } Cands;

static void addCand(Cands *c, const char *path, const char *name) {
  for (int i = 0; i < c->n && i < 8; i++) if (!strcmp(c->path[i], path)) return;
  if (c->n < 8) { c->path[c->n] = path; c->name[c->n] = name; }
  c->n++;
}

static const char *declaredAt(const char *path) {
  for (int i = 0; i < ix.nm; i++) if (!strcmp(ix.m[i].path, path)) return ix.m[i].name;
  return "?";
}

/* a file rule: dir/mid/P.asl as a candidate when it exists inside the root */
static void addFile(Cands *c, const char *dir, const char *mid, const char *P) {
  char f[PATH_MAX], real[PATH_MAX]; int n = snprintf(f, sizeof f, "%s/%s%s.asl", dir, mid, P);
  if (n >= 0 && (size_t)n < sizeof f && exists(f) && within(f, ix.root, real)) addCand(c, dupStr(real), declaredAt(real));
}

static void byLastSeg(Cands *c, const char *dir, const char *seg) {
  for (int i = 0; i < ix.nm; i++)
    if ((!dir || under(ix.m[i].path, dir)) && !strcmp(lastSeg(ix.m[i].name), seg)) addCand(c, ix.m[i].path, ix.m[i].name);
}

static int pkgNamed(const IdxPkg *p, const char *n) { return (p->name && !strcmp(p->name, n)) || !strcmp(p->base, n); }

enum { RES_MISSING, RES_OK, RES_DEPRECATED, RES_AMBIGUOUS, RES_TOOLONG };

/* resolved when exactly one candidate stands; several make the import ambiguous */
static int settle(Cands *c, char *out) {
  if (c->n == 1) { int n = snprintf(out, PATH_MAX, "%s", c->path[0]); return (n >= 0 && (size_t)n < PATH_MAX) ? RES_OK : RES_TOOLONG; }
  return c->n ? RES_AMBIGUOUS : RES_MISSING;
}

/* " ambiguous: NAME at PATH, ..." or " not declared[; candidates: ...]", then any index gap */
static void describe(Cands *c, int r, char *note, size_t nl) {
  size_t k = (size_t)snprintf(note, nl, "%s", r == RES_AMBIGUOUS ? " ambiguous: " : c->n ? " not declared; candidates: " : " not declared");
  size_t rl = strlen(ix.root);
  for (int i = 0; i < c->n && i < 8 && k + 1 < nl; i++)
    k += (size_t)snprintf(note + k, nl - k, "%s%s at %s", i ? ", " : "", c->name[i], c->path[i] + (under(c->path[i], ix.root) ? rl + 1 : 0));
  if (c->n > 8 && k + 1 < nl) k += (size_t)snprintf(note + k, nl - k, ", and %d more", c->n - 8);
  if (ix.skipped && k + 1 < nl) snprintf(note + k, nl - k, "; the index skipped %d unreadable path(s), first %.256s", ix.skipped, ix.skippedAt);
}

/* An import names a declared module (D148). In order: a name ws/rest qualified by the nearest workspace resolves
   inside it alone (rest.asl, src/rest.asl, then the declared name); root/P.asl and root/first/src/rest.asl; a package path first/rest resolves in the package named first
   (manifest :package or directory); a bare name resolves in the importing package, then in its manifest
   :dependencies; then the declared name across the root. A leading ../ run is deprecated: it resolves against the
   importer's directory, inside the root, until its suites migrate to module names. note receives the candidates. */
static int resolveImport(const char *importer, const char *P, char *out, char *note, size_t nl) {
  if (strlen(P) >= PATH_MAX) return RES_TOOLONG;
  int ups = 0; note[0] = 0;
  while (!strncmp(P + 3 * ups, "../", 3)) ups++;
  const char *Q = P + 3 * ups;
  for (const char *seg = Q;;) {
    const char *e = strchr(seg, '/'); size_t n = e ? (size_t)(e - seg) : strlen(seg);
    if (n == 0 || (n == 1 && seg[0] == '.') || (n == 2 && seg[0] == '.' && seg[1] == '.')) {
      snprintf(note, nl, " has an empty, . or .. segment after its leading ../ run");
      return RES_MISSING;
    }
    if (!e) break;
    seg = e + 1;
  }
  char real[PATH_MAX];
  char dir[PATH_MAX], cfg[PATH_MAX + 32], nearest[PATH_MAX] = "", outer[PATH_MAX] = "", pkg[PATH_MAX] = "";
  snprintf(dir, sizeof dir, "%s", importer);
  parentDir(dir);
  for (;;) {
    snprintf(cfg, sizeof cfg, "%s/.asl.config.asn", dir);
    if (exists(cfg)) { if (!nearest[0]) snprintf(nearest, sizeof nearest, "%s", dir); snprintf(outer, sizeof outer, "%s", dir); }
    snprintf(cfg, sizeof cfg, "%s/manifest.asn", dir);
    if (!pkg[0] && exists(cfg)) snprintf(pkg, sizeof pkg, "%s", dir);
    if (!strcmp(dir, "/")) break;
    parentDir(dir);
  }
  if (!nearest[0] || !realpath(outer, real)) { snprintf(note, nl, " has no .asl.config.asn above its importer"); return RES_MISSING; }
  snprintf(outer, sizeof outer, "%s", real);
  if (!pkg[0] || !under(pkg, outer)) snprintf(pkg, sizeof pkg, "%s", nearest);
  if (ups) {
    snprintf(dir, sizeof dir, "%s", importer);
    parentDir(dir);
    for (int i = 0; i < ups; i++) parentDir(dir);
    int n = snprintf(out, PATH_MAX, "%s/%s.asl", dir, Q);
    if (n < 0 || (size_t)n >= PATH_MAX) return RES_TOOLONG;
    if (!exists(out) || !within(out, outer, real)) { snprintf(note, nl, " names no file inside the workspace root"); return RES_MISSING; }
    char name[512];
    snprintf(note, nl, "%s", headerName(real, name, sizeof name) ? name : "no module header");
    return RES_DEPRECATED;
  }
  const char *sl = strchr(P, '/');
  char first[PATH_MAX]; const char *rest = sl ? sl + 1 : "";
  int fn = snprintf(first, sizeof first, "%.*s", sl ? (int)(sl - P) : (int)strlen(P), P);
  if (fn < 0 || (size_t)fn >= sizeof first) return RES_TOOLONG;
  char w[256]; workspaceOf(nearest, w, sizeof w);
  Cands c = {0};
  if (w[0] && !strcmp(w, first)) {
    int n = snprintf(out, PATH_MAX, "%s/%s.asl", nearest, rest);
    if (n >= 0 && (size_t)n < PATH_MAX && exists(out) && within(out, nearest, real)) return RES_OK;
    n = snprintf(out, PATH_MAX, "%s/src/%s.asl", nearest, rest);
    if (n >= 0 && (size_t)n < PATH_MAX && exists(out) && within(out, nearest, real)) return RES_OK;
    ensureIndex(outer);
    for (int i = 0; i < ix.nm; i++) if (under(ix.m[i].path, nearest) && !strcmp(ix.m[i].name, P)) addCand(&c, ix.m[i].path, ix.m[i].name);
    int r = settle(&c, out);
    if (r == RES_MISSING) byLastSeg(&c, nearest, lastSeg(P));
    if (r != RES_OK && r != RES_TOOLONG) describe(&c, r, note, nl);
    return r;
  }
  if (sl) {
    char dependencyDir[PATH_MAX], expected[256], actual[256];
    int dep = declaredDependency(nearest, first, dependencyDir, sizeof dependencyDir, expected, sizeof expected, note, nl);
    if (dep < 0) return RES_MISSING;
    if (dep > 0) {
      if (expected[0]) {
        if (gitHead(dependencyDir, actual, sizeof actual) != 0) {
          snprintf(note, nl, " cannot verify pinned revision %s for dependency %s at %s", expected, first, dependencyDir);
          return RES_MISSING;
        }
        if (strcmp(expected, actual)) {
          snprintf(note, nl, " dependency %s revision mismatch: expected %s, actual %s", first, expected, actual);
          return RES_MISSING;
        }
      }
      int n = snprintf(out, PATH_MAX, "%s/src/%s.asl", dependencyDir, rest);
      if (n >= 0 && (size_t)n < PATH_MAX && exists(out) && within(out, dependencyDir, real)) return RES_OK;
      n = snprintf(out, PATH_MAX, "%s/%s.asl", dependencyDir, rest);
      if (n >= 0 && (size_t)n < PATH_MAX && exists(out) && within(out, dependencyDir, real)) return RES_OK;
      snprintf(note, nl, " has no module %s inside declared dependency %s", rest, first);
      return RES_MISSING;
    }
  }
  if (sl) {
    int n = snprintf(out, PATH_MAX, "%s/%s.asl", outer, P);
    if (n >= 0 && (size_t)n < PATH_MAX && exists(out)) {
      if (within(out, outer, real)) return RES_OK;
      snprintf(note, nl, " names a path that leaves the workspace root");
      return RES_MISSING;
    }
    n = snprintf(out, PATH_MAX, "%s/%s/src/%s.asl", outer, first, rest);
    if (n < 0 || (size_t)n >= PATH_MAX) return RES_TOOLONG;
    if (exists(out) && within(out, outer, real)) return RES_OK;
  }
  ensureIndex(outer);
  int r;
  if (sl) {
    for (int i = 0; i < ix.np; i++)
      if (pkgNamed(&ix.p[i], first)) { addFile(&c, ix.p[i].dir, "src/", rest); addFile(&c, ix.p[i].dir, "", rest); }
    if ((r = settle(&c, out)) != RES_MISSING) goto done;
  } else {
    addFile(&c, pkg, "src/", P); addFile(&c, pkg, "", P);
    if (!c.n) byLastSeg(&c, pkg, P);
    if ((r = settle(&c, out)) != RES_MISSING) goto done;
    for (int i = 0; i < ix.np; i++) {
      if (strcmp(ix.p[i].dir, pkg)) continue;
      for (int j = 0; j < ix.p[i].ndeps; j++)
        for (int k = 0; k < ix.np; k++)
          if (pkgNamed(&ix.p[k], ix.p[i].deps[j])) { addFile(&c, ix.p[k].dir, "src/", P); byLastSeg(&c, ix.p[k].dir, P); }
    }
    if ((r = settle(&c, out)) != RES_MISSING) goto done;
  }
  if (!sl) addFile(&c, outer, "", P);
  for (int i = 0; i < ix.nm; i++) if (!strcmp(ix.m[i].name, P)) addCand(&c, ix.m[i].path, ix.m[i].name);
  if (c.n > 1) {
    Cands local = {0};
    for (int i = 0; i < ix.nm; i++) if (!strcmp(ix.m[i].name, P) && under(ix.m[i].path, pkg)) addCand(&local, ix.m[i].path, ix.m[i].name);
    if (local.n == 1) c = local;
  }
  if ((r = settle(&c, out)) != RES_MISSING) goto done;
  byLastSeg(&c, NULL, lastSeg(P));
  describe(&c, RES_MISSING, note, nl);
  if (sl) {
    int knownPackage = 0;
    for (int i = 0; i < ix.np; i++) if (pkgNamed(&ix.p[i], first)) { knownPackage = 1; break; }
    size_t used = strlen(note);
    if (!knownPackage && used < nl) snprintf(note + used, nl - used,
                            "\n  hint: declare an external package with (:dependencies ((%s :path \"/path/to/package\")))", first);
  }
  return RES_MISSING;
done:
  if (r == RES_AMBIGUOUS) describe(&c, r, note, nl);
  return r;
}

const EmbedModule *embedMods; int nembedMods;
const EmbedImport *embedImports; int nembedImports;

/* embedded artifact: the source recorded at build time, never the disk */
static int readModule(const char *path, Unit *u, char *err, size_t errlen) {
  if (!embedMods) return readFile(path, u, err, errlen);
  for (int i = 0; i < nembedMods; i++)
    if (!strcmp(embedMods[i].path, path)) return readSource(path, (const char *)embedMods[i].src, embedMods[i].len, u, err, errlen);
  snprintf(err, errlen, "%s: ERR_IO module not embedded", path);
  return -1;
}

/* embedded artifact: the resolution recorded at build time */
static int resolveEmbedded(const char *importer, const char *P, char *real) {
  for (int i = 0; i < nembedImports; i++)
    if (!strcmp(embedImports[i].importer, importer) && !strcmp(embedImports[i].importPath, P)) { snprintf(real, PATH_MAX, "%s", embedImports[i].resolved); return 1; }
  return 0;
}

int moduleExports(Module *m, const char *name) {
  int id = intern(name, strlen(name));
  for (int i = 0; i < m->nexports; i++) if (m->exports[i] == id) return 1;
  return 0;
}

/* The prelude (asl/prelude/prelude.asl): one ASL module whose definitions every other module sees after its own
   and before the C builtins. Found at $ASL_PRELUDE, else as prelude.asl beside the real path of this executable
   (build.sh copies it there); an embedded artifact carries it as module 1. */
Module *preludeModule;

int preludeLocate(char *out) {
  const char *env = getenv("ASL_PRELUDE");
  if (env && *env) return realpath(env, out) != NULL;
  char exe[PATH_MAX + 64], self[PATH_MAX];
  if (hostGetExecutablePath(exe, sizeof exe) && realpath(exe, self)) {
    char *slash = strrchr(self, '/');
    if (slash) {
      *slash = 0;
      int n = snprintf(exe, sizeof exe, "%s/prelude.asl", self); if (n > 0 && (size_t)n < sizeof exe && realpath(exe, out)) return 1;
      n = snprintf(exe, sizeof exe, "%s/../asl/prelude/prelude.asl", self); if (n > 0 && (size_t)n < sizeof exe && realpath(exe, out)) return 1;
      n = snprintf(exe, sizeof exe, "%s/../prelude/prelude.asl", self); if (n > 0 && (size_t)n < sizeof exe && realpath(exe, out)) return 1;
    }
  }
  return realpath("asl/prelude/prelude.asl", out) != NULL;
}

Module **loadGraph(const char *entry, int *count, Diags *d) {
  char abs[PATH_MAX], err[2048], pre[PATH_MAX];
  if (embedMods) snprintf(abs, sizeof abs, "%s", entry);
  else if (!realpath(entry, abs)) { diag(d, entry, NULL, "ERR_IO", "cannot open file"); return NULL; }
  if (embedMods) { if (nembedMods < 2) { diag(d, entry, NULL, "ERR_IO", "artifact embeds no prelude"); return NULL; } snprintf(pre, sizeof pre, "%s", embedMods[1].path); }
  else if (!preludeLocate(pre)) { diag(d, entry, NULL, "ERR_IO", "prelude.asl not found (set ASL_PRELUDE or install it beside asl-host)"); return NULL; }
  Module **mods = NULL; int n = 0, cap = 0;
  #define ADD(pathStr) do { \
    if (n == cap) { cap = cap ? cap * 2 : 16; mods = realloc(mods, sizeof(Module *) * cap); if (!mods) exit(70); } \
    Module *m_ = calloc(1, sizeof(Module)); if (!m_) exit(70); m_->path = strdup(pathStr); m_->name = -1; mods[n++] = m_; } while (0)
  ADD(abs);
  if (strcmp(abs, pre)) ADD(pre);
  preludeModule = mods[n - 1];
  for (int i = 0; i < n; i++) {
    Module *m = mods[i];
    if (readModule(m->path, &m->unit, err, sizeof err) != 0) {
      if (d->n == d->cap) { d->cap = d->cap ? d->cap * 2 : 16; d->msgs = realloc(d->msgs, sizeof(char *) * d->cap); if (!d->msgs) exit(70); }
      d->msgs[d->n++] = strdup(err);
      *count = n; return NULL;
    }
    declareModule(m, d);
    for (int j = 0; j < m->nimports; j++) {
      char cand[PATH_MAX], real[PATH_MAX], note[768];
      const char *P = symName(m->imports[j].path); if (!strcmp(P, "sys")) continue;
      int r = RES_OK; note[0] = 0;
      if (embedMods ? !resolveEmbedded(m->path, P, real) : ((r = resolveImport(m->path, P, cand, note, sizeof note)) != RES_OK && r != RES_DEPRECATED) || !realpath(cand, real)) {
        diag(d, m->path, m->imports[j].at, r == RES_TOOLONG ? "ERR_PATH_TOO_LONG" : "ERR_UNRESOLVED_IMPORT", "%s%s", P, note);
        continue;
      }
      if (r == RES_DEPRECATED)
        fprintf(stderr, "%s:%d:%d: WARN_DEPRECATED_IMPORT %s resolves against the importer's directory; import the declared module %s\n",
                m->path, m->imports[j].at ? m->imports[j].at->line : 0, m->imports[j].at ? m->imports[j].at->col + 1 : 0, P, note);
      int k;
      for (k = 0; k < n && strcmp(mods[k]->path, real); k++) {}
      if (k == n) ADD(real);
      m->imports[j].m = mods[k];
    }
  }
  #undef ADD
  *count = n;
  return mods;
}
