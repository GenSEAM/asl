/* Stage-0 ASL reader (plan R1 H1, invariants I6 I10). One reader serves every subcommand. */
#ifndef ASL_READER_H
#define ASL_READER_H
#include <stdint.h>
#include <stddef.h>

typedef enum { N_LIST, N_VEC, N_MAP, N_SYM, N_KW, N_INT, N_FLOAT, N_STR, N_GROUP } NodeKind;

typedef struct Node {
  NodeKind kind;
  int line, col;
  int n;               /* children of LIST VEC MAP GROUP */
  struct Node **kids;
  int sym;             /* interned id for SYM and KW (KW without the colon) */
  const char *s; size_t len; /* STR contents after escapes */
  int64_t i; double f;
  int outOfRange;      /* INT literal outside int64: parse accepts it, compile rejects it */
} Node;

/* tagLines[i] and tagSyms[i]: one word of a whole-line `; (:m ... :tags (w ...))` comment and its line
   (asl/grammar/meta.asn); the checker honours hostSubject above a fn (D152) */
typedef struct { const char *file; Node **items; int n; int *tagLines, *tagSyms; int ntags; } Unit;

/* returns 0 on success; on a lexical or balance error writes "file:line:col: CODE message" to err */
int readSource(const char *file, const char *src, size_t len, Unit *out, char *err, size_t errlen);
int readFile(const char *path, Unit *out, char *err, size_t errlen);

#endif
