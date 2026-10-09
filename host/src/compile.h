/* Modules, definitions and the bytecode compiler interface (plan R1 H3 H6). */
#ifndef ASL_COMPILE_H
#define ASL_COMPILE_H
#include "reader.h"
#include "value.h"

enum {
  OP_CONST, OP_LOCAL, OP_UPVAL, OP_GLOBAL, OP_POP, OP_SLIDE, OP_JMP, OP_JF, OP_ANDJ, OP_ORJ, OP_CHKBOOL,
  OP_CALL, OP_TCALL, OP_CALLG, OP_TCALLG, OP_BUILTIN, OP_RET, OP_CLOSURE,
  OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_LT, OP_LE, OP_GT, OP_GE, OP_EQ, OP_NEQ, OP_NOT, OP_NEG,
  OP_MKCTOR, OP_MKREC, OP_FIELD, OP_TESTCTOR, OP_TESTLIT, OP_NOMATCH, OP_ASSERT, OP_REFUTE, OP_UNIT, OP_MKLIST, OP_I2F,
  OP_CHKLIST, OP_TESTCONS, OP_TESTNIL, OP_OPTWRAP, OP_CONS, OP_LTESTCONS, OP_TSELF, OP_PUSHN, OP_LUNCONS, OP_WITH,
#define ARITH_OPS(X) X(ADD) X(SUB) X(MUL) X(DIV) X(MOD) X(LT) X(LE) X(GT) X(GE) X(EQ) X(NEQ)
#define CMP_OPS(X) X(LT) X(LE) X(GT) X(GE) X(EQ) X(NEQ)
#define BIN_ENUM(o) OP_BIN_##o,
#define JBIN_ENUM(o) OP_JBIN_##o,
  ARITH_OPS(BIN_ENUM) CMP_OPS(JBIN_ENUM)
  OP_COUNT
};

/* OP_TSELF moves: an operand kind in bits 30-31, the parameter in bits 27-29, an index below; at most MAX_TSELF_ARGS,
   gathered on the C stack before the parameters are rebound */
enum { MAX_TSELF_ARGS = 8, TSELF_INDEX = (1u << 27) - 1 };
/* OP_PUSHN n, then n words: a PUSH_* kind in bits 30-31 over an index */
enum { PUSH_GLOBAL, PUSH_LOCAL, PUSH_CONST, PUSH_UPVAL, PUSH_INDEX = (1u << 30) - 1 };
enum { DEF_FN, DEF_CTOR, DEF_SCHEMA };
struct Module;
typedef struct EffRef EffRef;
typedef struct Def {
  int name, kind, gidx, arity, enumId;
  int tailrec;
  Node *group;          /* defining top-level item */
  int nfields; int *fields;
  /* schema :default expressions, one slot per field, parallel to fields[]: defaultGidx[i] is the
     global holding a compiled zero-arg thunk when field i has a :default, else -1; defaultExpr[i]
     is that field's default expression node, or NULL. The thunk is compiled in the schema's own
     module (declareListSchema/compileModule), so a default naming a private module fn resolves
     there, not in a constructor call site's importing module. */
  int *defaultGidx; Node **defaultExpr;
  /* LS1 effects, recorded in check mode: marked is fn ! name or name!; effAt is the first effectful builtin the body
     names, lambdas included; refs are the fns it names; effect is the derived flag of a prelude fn */
  int marked, effect;
  Node *effAt; const char *effWhat;
  int nrefs, caprefs; EffRef *refs;
} Def;
struct EffRef { Def *df; struct Module *owner; Node *at; };

typedef struct { int name; int nvariants; int *variants; } EnumDef;

typedef struct Module {
  const char *path;     /* canonical absolute path */
  int name;
  Unit unit;
  int nimports; struct { int alias, path; struct Module *m; Node *at; } *imports;
  int nexports; int *exports;
  int ndefs, capdefs; Def *defs;
  int ntops, captops; Node **tops;   /* top-level expressions, run in order after the whole graph compiles */
  Proto *init;
} Module;

typedef struct { char **msgs; int n, cap; int checkMode; } Diags;

extern Proto **protoTab; extern int nprotoTab;
extern EnumDef *enums; extern int nenums;

void diag(Diags *d, const char *file, Node *at, const char *code, const char *fmt, ...);
Def *moduleDef(Module *m, int name);
void declareModule(Module *m, Diags *d);
/* resolve.c: ERR_EFFECT_UNMARKED for a fn without ! that names an effectful builtin, a fn with !, or an effectful prelude fn */
void effectCheckModules(Module **mods, int n, Diags *d);
void compileModule(Module *m, Diags *d);
Proto *compileExpr(Module *m, Node **forms, int n, Diags *d);
int isFnHeader(Node *g);
Def *defLookup(Module *m, int name, Module **owner); /* a name's definition as the compiler resolves it, or NULL */
int defExported(Module *m, Def *df); /* m's :x lists df, or df's enum when df is a constructor */
/* the enum a constructor name belongs to: its enumId, FAMILY_OPTION for some/none, FAMILY_RESULT for ok/err, NO_FAMILY
   when name is no constructor */
enum { NO_FAMILY = -1, FAMILY_OPTION = -2, FAMILY_RESULT = -3 };
int ctorFamily(Module *m, int name);
/* the enum an mt tests: its first (ctor ...) pattern's, else its first bare constructor name's, else NO_FAMILY */
int matchFamily(Module *m, Node *n);
/* a bare pattern name tests the tag only when it names a constructor of the match's family; any other name binds */
int ctorPattern(Module *m, Node *p, int family);
void notExported(Diags *d, const char *file, Node *at, Module *owner, int member);
/* types.c: ERR_TYPE_MISMATCH where an annotated or literal type meets a known different one; unknown stays unchecked */
void typeCheckModule(Module *m, Diags *d);
void typeCheckForms(Module *m, Node **forms, int n, Diags *d);
/* fn [!] name p: T ... -> R body: parameter names into params (may be NULL), returns arity; *nameAt and *bodyAt index g->kids */
int fnSignature(Node *g, int *nameAt, int *params, int maxParams, int *bodyAt);

/* loader.c; an embedded artifact (embed.c) sets embedMods and embedImports so the graph loads from memory */
typedef struct { const char *path; const unsigned char *src; unsigned long len; } EmbedModule;
typedef struct { const char *importer, *importPath, *resolved; } EmbedImport;
extern const EmbedModule *embedMods; extern int nembedMods;
extern const EmbedImport *embedImports; extern int nembedImports;
Module **loadGraph(const char *entry, int *count, Diags *d);
int moduleExports(Module *m, const char *name);
int hostGetExecutablePath(char *buf, size_t bufsize);

/* check.c: load, declare and compile the whole graph; nonzero diagnostics mean nothing may run */
Module **buildProgram(const char *path, int checkMode, int *count, Diags *d);
void printDiags(Diags *d);

/* builtinTables chain of asl-host (hostBuiltins.c) */
#define BUILTIN_TABLES_WITH(testTable, testCount) {coreBuiltins, &nCoreBuiltins}, {arrayBuiltins, &nArrayBuiltins}, {parquetBuiltins, &nParquetBuiltins}, \
  {sysBuiltins, &nSysBuiltins}, {parallelBuiltins, &nParallelBuiltins}, {sysNetBuiltins, &nSysNetBuiltins}, {testTable, testCount}, \
  {kernelBuiltins, &nKernelBuiltins}

#endif
