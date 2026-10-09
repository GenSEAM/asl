/* Thrift compact protocol reader: zigzag varints, delta field headers, bounded skip of unknown fields. */
#include "thrift.h"

static uint8_t byte(Tr *t) {
  if (t->p >= t->end) { t->err = 1; return 0; }
  return *t->p++;
}

static uint64_t varint(Tr *t) {
  uint64_t v = 0;
  for (int shift = 0; shift < 64; shift += 7) {
    uint8_t b = byte(t);
    v |= (uint64_t)(b & 0x7F) << shift;
    if (!(b & 0x80)) return v;
  }
  t->err = 1;
  return 0;
}

static int64_t zigzag(Tr *t) { uint64_t v = varint(t); return (int64_t)(v >> 1) ^ -(int64_t)(v & 1); }

int trField(Tr *t, int *last, int *id, int *type) {
  uint8_t h = byte(t);
  if (t->err || h == 0) return 0;
  *type = h & 15;
  int delta = h >> 4;
  *id = delta ? *last + delta : (int)zigzag(t);
  *last = *id;
  return !t->err;
}

int64_t trInt(Tr *t, int type) {
  if (type == TT_BYTE) return (int8_t)byte(t);
  if (type == TT_I16 || type == TT_I32 || type == TT_I64) return zigzag(t);
  t->err = 1;
  return 0;
}

int trBool(Tr *t, int type) {
  if (type == TT_TRUE) return 1;
  if (type == TT_FALSE) return 0;
  t->err = 1;
  return 0;
}

size_t trBinary(Tr *t, const uint8_t **s) {
  uint64_t n = varint(t);
  if (t->err || n > (uint64_t)(t->end - t->p)) { t->err = 1; *s = t->p; return 0; }
  *s = t->p; t->p += n;
  return (size_t)n;
}

size_t trList(Tr *t, int *etype) {
  uint8_t h = byte(t);
  *etype = h & 15;
  uint64_t n = h >> 4;
  if (n == 15) n = varint(t);
  if (n > (uint64_t)(t->end - t->p)) { t->err = 1; return 0; }
  return (size_t)n;
}

void trSkip(Tr *t, int type, int depth) {
  if (depth > 32) { t->err = 1; return; }
  switch (type) {
    case TT_TRUE: case TT_FALSE: return;
    case TT_BYTE: byte(t); return;
    case TT_I16: case TT_I32: case TT_I64: varint(t); return;
    case TT_DOUBLE: for (int i = 0; i < 8; i++) byte(t); return;
    case TT_BINARY: { const uint8_t *s; trBinary(t, &s); return; }
    case TT_LIST: case TT_SET: {
      int et; size_t n = trList(t, &et);
      for (size_t i = 0; i < n && !t->err; i++) { if (et == TT_TRUE || et == TT_FALSE) byte(t); else trSkip(t, et, depth + 1); }
      return;
    }
    case TT_MAP: {
      uint64_t n = varint(t);
      if (!n) return;
      uint8_t kv = byte(t);
      for (uint64_t i = 0; i < n && !t->err; i++) { trSkip(t, kv >> 4, depth + 1); trSkip(t, kv & 15, depth + 1); }
      return;
    }
    case TT_STRUCT: {
      int last = 0, id, ft;
      while (trField(t, &last, &id, &ft)) trSkip(t, ft, depth + 1);
      return;
    }
    default: t->err = 1;
  }
}
