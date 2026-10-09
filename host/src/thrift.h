/* Thrift compact protocol reader (plan R1 H10), bounds-checked: any overrun sets err and reads zeros. */
#ifndef ASL_THRIFT_H
#define ASL_THRIFT_H
#include <stddef.h>
#include <stdint.h>

enum { TT_STOP = 0, TT_TRUE = 1, TT_FALSE = 2, TT_BYTE = 3, TT_I16 = 4, TT_I32 = 5, TT_I64 = 6, TT_DOUBLE = 7,
  TT_BINARY = 8, TT_LIST = 9, TT_SET = 10, TT_MAP = 11, TT_STRUCT = 12 };

typedef struct { const uint8_t *p, *end; int err; } Tr;

/* next field of the current struct: 0 at STOP, else 1 with *id and *type; *last carries the previous id */
int trField(Tr *t, int *last, int *id, int *type);
int64_t trInt(Tr *t, int type);
int trBool(Tr *t, int type);
size_t trBinary(Tr *t, const uint8_t **s);
size_t trList(Tr *t, int *etype);
void trSkip(Tr *t, int type, int depth);

#endif
