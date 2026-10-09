/* Single-frame zstd decoder per RFC 8878 (plan R1 H9): raw, RLE and compressed blocks, Huffman literals, FSE
   sequences, repeat offsets, window bound, XXH64 content checksum. Dictionaries, skippable frames and multi-frame
   input are ERR_ZSTD_UNSUPPORTED; every malformed input is ERR_ZSTD_CORRUPT, never a crash. */
#include <setjmp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_BLOCK (128 * 1024)
#define MAX_WINDOW_LOG 27

typedef struct { uint8_t sym, nbBits; uint16_t base; } FseCell;
typedef struct { FseCell cell[1 << 9]; int log; int ok; } Fse;
typedef struct { uint8_t sym, nbBits; } HufCell;

typedef struct {
  jmp_buf jb; char *err; size_t errlen;
  uint8_t *out; size_t n, cap, limit;
  uint64_t window;
  HufCell huf[1 << 11]; int hufLog, hufOk;
  Fse ll, of, ml;
  uint32_t rep[3];
  uint8_t lit[MAX_BLOCK]; size_t nlit;
} Z;

static _Noreturn void fail(Z *z, const char *code, const char *msg) {
  snprintf(z->err, z->errlen, "%s: %s", code, msg);
  longjmp(z->jb, 1);
}
#define CORRUPT(z, m) fail(z, "ERR_ZSTD_CORRUPT", m)

static int highBit(uint32_t v) { int b = -1; while (v) { v >>= 1; b++; } return b; }

static void grow(Z *z, size_t more) {
  if (more > z->limit - z->n) CORRUPT(z, "output exceeds the frame content size or 1 GiB");
  if (z->n + more <= z->cap) return;
  size_t c = z->cap ? z->cap : 65536;
  while (c < z->n + more) c *= 2;
  uint8_t *p = realloc(z->out, c);
  if (!p) fail(z, "ERR_OOM", "cannot grow the output buffer");
  z->out = p; z->cap = c;
}

/* ---- forward bit reader (FSE table descriptions) ---- */
typedef struct { const uint8_t *p; size_t len; size_t bit; } Fwd;
static uint32_t fwdRead(Z *z, Fwd *r, int n) {
  uint32_t v = 0;
  for (int i = 0; i < n; i++, r->bit++) {
    if ((r->bit >> 3) >= r->len) CORRUPT(z, "table description truncated");
    v |= (uint32_t)((r->p[r->bit >> 3] >> (r->bit & 7)) & 1) << i;
  }
  return v;
}

/* ---- backward bit reader: bits are consumed from the end; `pos` bits remain ---- */
typedef struct { const uint8_t *p; size_t len; int64_t pos; } Bwd;
static void bwdInit(Z *z, Bwd *r, const uint8_t *p, size_t len) {
  if (len == 0 || p[len - 1] == 0) CORRUPT(z, "bitstream without an end marker");
  r->p = p; r->len = len; r->pos = (int64_t)len * 8 - 8 + highBit(p[len - 1]);
}
/* the n bits below pos, with bits below 0 read as zero */
static uint64_t bwdPeek(const Bwd *r, int n) {
  if (n == 0) return 0;
  int64_t lo = r->pos - n; uint64_t v = 0;
  for (int64_t b = (lo < 0 ? 0 : lo) >> 3; b <= (r->pos - 1) >> 3 && b < (int64_t)r->len; b++) {
    int64_t shift = b * 8 - lo;
    if (shift >= 0) v |= (uint64_t)r->p[b] << shift; else v |= (uint64_t)r->p[b] >> -shift;
  }
  return n >= 64 ? v : v & ((1ull << n) - 1);
}
static uint64_t bwdRead(Bwd *r, int n) { uint64_t v = bwdPeek(r, n); r->pos -= n; return v; }

/* ---- FSE ---- */
static void fseBuild(Z *z, Fse *t, const int16_t *norm, int nsym, int log) {
  int size = 1 << log, high = size - 1, step = (size >> 1) + (size >> 3) + 3, pos = 0;
  uint16_t next[256];
  for (int s = 0; s < nsym; s++) {
    if (norm[s] == -1) { t->cell[high--].sym = (uint8_t)s; next[s] = 1; }
    else next[s] = (uint16_t)norm[s];
  }
  for (int s = 0; s < nsym; s++)
    for (int i = 0; i < norm[s]; i++) {
      t->cell[pos].sym = (uint8_t)s;
      do pos = (pos + step) & (size - 1); while (pos > high);
    }
  if (pos != 0) CORRUPT(z, "FSE table spread does not close");
  for (int u = 0; u < size; u++) {
    int s = t->cell[u].sym; uint32_t x = next[s]++;
    int nb = log - highBit(x);
    t->cell[u].nbBits = (uint8_t)nb; t->cell[u].base = (uint16_t)((x << nb) - (uint32_t)size);
  }
  t->log = log; t->ok = 1;
}

/* reads a normalized-count table description, returns bytes consumed */
static size_t fseRead(Z *z, Fse *t, const uint8_t *p, size_t len, int maxSym, int maxLog) {
  Fwd r = {p, len, 0};
  int log = 5 + (int)fwdRead(z, &r, 4);
  if (log > maxLog) CORRUPT(z, "FSE accuracy log too large");
  int16_t norm[256] = {0};
  int remaining = (1 << log) + 1, threshold = 1 << log, nb = log + 1, s = 0;
  while (remaining > 1) {
    if (s > maxSym) CORRUPT(z, "FSE table has too many symbols");
    int max = (2 * threshold - 1) - remaining, count;
    uint32_t low = fwdRead(z, &r, nb - 1);
    if ((int)low < max) count = (int)low;
    else { count = (int)(low | fwdRead(z, &r, 1) << (nb - 1)); if (count >= threshold) count -= max; }
    count--;
    remaining -= count < 0 ? -count : count;
    norm[s++] = (int16_t)count;
    if (count == 0) {
      for (;;) {
        int rep = (int)fwdRead(z, &r, 2);
        for (int i = 0; i < rep; i++) { if (s > maxSym) CORRUPT(z, "FSE zero run past the alphabet"); norm[s++] = 0; }
        if (rep != 3) break;
      }
    }
    while (remaining < threshold && nb > 1) { nb--; threshold >>= 1; }
  }
  if (remaining != 1) CORRUPT(z, "FSE probabilities do not sum to the table size");
  fseBuild(z, t, norm, s, log);
  return (r.bit + 7) >> 3;
}

static void fseRle(Fse *t, uint8_t sym) { t->cell[0] = (FseCell){sym, 0, 0}; t->log = 0; t->ok = 1; }

static const int16_t LL_DEF[36] = {4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1};
static const int16_t ML_DEF[53] = {1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1};
static const int16_t OF_DEF[29] = {1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1};
static const uint32_t LL_BASE[36] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512,
  1024, 2048, 4096, 8192, 16384, 32768, 65536};
static const uint8_t LL_BITS[36] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
static const uint32_t ML_BASE[53] = {3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
  32, 33, 34, 35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771, 65539};
static const uint8_t ML_BITS[53] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};

/* ---- Huffman ---- */
static size_t hufRead(Z *z, const uint8_t *p, size_t len) {
  if (len < 1) CORRUPT(z, "Huffman tree description truncated");
  uint8_t w[256]; int nw = 0; size_t used;
  int h = p[0];
  if (h >= 128) {
    nw = h - 127; used = 1 + (size_t)(nw + 1) / 2;
    if (used > len) CORRUPT(z, "Huffman direct weights truncated");
    for (int i = 0; i < nw; i++) w[i] = (uint8_t)(i % 2 == 0 ? p[1 + i / 2] >> 4 : p[1 + i / 2] & 15);
  } else {
    used = 1 + (size_t)h;
    if (h == 0 || used > len) CORRUPT(z, "Huffman FSE weights truncated");
    Fse t; size_t hd = fseRead(z, &t, p + 1, (size_t)h, 255, 6);
    if (hd >= (size_t)h) CORRUPT(z, "Huffman weight stream empty");
    Bwd r; bwdInit(z, &r, p + 1 + hd, (size_t)h - hd);
    uint32_t s1 = (uint32_t)bwdRead(&r, t.log), s2 = (uint32_t)bwdRead(&r, t.log);
    if (r.pos < 0) CORRUPT(z, "Huffman weight stream too short");
    for (;;) {
      if (nw >= 255) CORRUPT(z, "too many Huffman weights");
      w[nw++] = t.cell[s1].sym; s1 = t.cell[s1].base + (uint32_t)bwdRead(&r, t.cell[s1].nbBits);
      if (r.pos < 0) { if (nw >= 255) CORRUPT(z, "too many Huffman weights"); w[nw++] = t.cell[s2].sym; break; }
      if (nw >= 255) CORRUPT(z, "too many Huffman weights");
      w[nw++] = t.cell[s2].sym; s2 = t.cell[s2].base + (uint32_t)bwdRead(&r, t.cell[s2].nbBits);
      if (r.pos < 0) { if (nw >= 255) CORRUPT(z, "too many Huffman weights"); w[nw++] = t.cell[s1].sym; break; }
    }
  }
  uint32_t sum = 0;
  for (int i = 0; i < nw; i++) { if (w[i] > 11) CORRUPT(z, "Huffman weight above 11"); if (w[i]) sum += 1u << (w[i] - 1); }
  if (sum == 0) CORRUPT(z, "Huffman weights all zero");
  int maxBits = highBit(sum) + 1;
  uint32_t rest = (1u << maxBits) - sum;
  if (maxBits > 11 || (rest & (rest - 1))) CORRUPT(z, "Huffman weights do not complete a tree");
  w[nw++] = (uint8_t)(highBit(rest) + 1);
  uint32_t start[13] = {0}, cnt[13] = {0};
  for (int i = 0; i < nw; i++) cnt[w[i]]++;
  for (int k = 1, acc = 0; k <= maxBits; k++) { start[k] = (uint32_t)acc; acc += (int)(cnt[k] << (k - 1)); }
  for (int i = 0; i < nw; i++) {
    if (!w[i]) continue;
    uint32_t n = 1u << (w[i] - 1);
    for (uint32_t j = 0; j < n; j++) z->huf[start[w[i]] + j] = (HufCell){(uint8_t)i, (uint8_t)(maxBits + 1 - w[i])};
    start[w[i]] += n;
  }
  z->hufLog = maxBits; z->hufOk = 1;
  return used;
}

static void hufStream(Z *z, const uint8_t *p, size_t len, uint8_t *dst, size_t n) {
  Bwd r; bwdInit(z, &r, p, len);
  for (size_t i = 0; i < n; i++) {
    HufCell c = z->huf[bwdPeek(&r, z->hufLog)];
    dst[i] = c.sym; r.pos -= c.nbBits;
    if (r.pos < 0) CORRUPT(z, "Huffman stream overrun");
  }
  if (r.pos != 0) CORRUPT(z, "Huffman stream not fully consumed");
}

/* ---- literals section, returns bytes consumed ---- */
static size_t literals(Z *z, const uint8_t *p, size_t len) {
  if (len < 1) CORRUPT(z, "literals header truncated");
  int type = p[0] & 3, sf = (p[0] >> 2) & 3;
  size_t regen, comp = 0, hdr;
  if (type < 2) {
    if (sf == 0 || sf == 2) { hdr = 1; regen = p[0] >> 3; }
    else if (sf == 1) { hdr = 2; if (len < 2) CORRUPT(z, "literals header truncated"); regen = (p[0] >> 4) + ((size_t)p[1] << 4); }
    else { hdr = 3; if (len < 3) CORRUPT(z, "literals header truncated"); regen = (p[0] >> 4) + ((size_t)p[1] << 4) + ((size_t)p[2] << 12); }
    if (regen > MAX_BLOCK) CORRUPT(z, "literals larger than a block");
    if (type == 0) { if (hdr + regen > len) CORRUPT(z, "raw literals truncated"); memcpy(z->lit, p + hdr, regen); z->nlit = regen; return hdr + regen; }
    if (hdr + 1 > len) CORRUPT(z, "RLE literals truncated");
    memset(z->lit, p[hdr], regen); z->nlit = regen; return hdr + 1;
  }
  hdr = sf < 2 ? 3 : sf == 2 ? 4 : 5;
  if (len < hdr) CORRUPT(z, "literals header truncated");
  uint64_t v = 0;
  for (size_t i = 0; i < hdr; i++) v |= (uint64_t)p[i] << (8 * i);
  int bits = sf < 2 ? 10 : sf == 2 ? 14 : 18, streams = sf == 0 ? 1 : 4;
  regen = (size_t)(v >> 4) & ((1u << bits) - 1); comp = (size_t)(v >> (4 + bits)) & ((1u << bits) - 1);
  if (regen > MAX_BLOCK) CORRUPT(z, "literals larger than a block");
  if (hdr + comp > len) CORRUPT(z, "compressed literals truncated");
  const uint8_t *q = p + hdr; size_t ql = comp;
  if (type == 2) { size_t t = hufRead(z, q, ql); q += t; ql -= t; }
  else if (!z->hufOk) CORRUPT(z, "treeless literals without a previous Huffman table");
  if (streams == 1) hufStream(z, q, ql, z->lit, regen);
  else {
    if (ql < 6) CORRUPT(z, "Huffman jump table truncated");
    size_t s1 = q[0] | (size_t)q[1] << 8, s2 = q[2] | (size_t)q[3] << 8, s3 = q[4] | (size_t)q[5] << 8;
    if (6 + s1 + s2 + s3 > ql) CORRUPT(z, "Huffman jump table beyond the literals");
    size_t s4 = ql - 6 - s1 - s2 - s3, each = (regen + 3) / 4;
    if (each * 3 > regen) CORRUPT(z, "literals too short for four streams");
    const uint8_t *b = q + 6;
    hufStream(z, b, s1, z->lit, each);
    hufStream(z, b + s1, s2, z->lit + each, each);
    hufStream(z, b + s1 + s2, s3, z->lit + 2 * each, each);
    hufStream(z, b + s1 + s2 + s3, s4, z->lit + 3 * each, regen - 3 * each);
  }
  z->nlit = regen;
  return hdr + comp;
}

static size_t seqTable(Z *z, Fse *t, int mode, const uint8_t *p, size_t len, const int16_t *def, int ndef, int defLog, int maxSym, int maxLog) {
  switch (mode) {
    case 0: fseBuild(z, t, def, ndef, defLog); return 0;
    case 1: if (len < 1) CORRUPT(z, "RLE sequence table truncated"); if (p[0] > maxSym) CORRUPT(z, "RLE symbol out of range"); fseRle(t, p[0]); return 1;
    case 2: return fseRead(z, t, p, len, maxSym, maxLog);
    default: if (!t->ok) CORRUPT(z, "repeat sequence table without a previous table"); return 0;
  }
}

static void compressedBlock(Z *z, const uint8_t *p, size_t len) {
  size_t used = literals(z, p, len);
  p += used; len -= used;
  if (len < 1) CORRUPT(z, "sequences header truncated");
  size_t nseq = p[0], h = 1;
  if (nseq >= 128) {
    if (nseq < 255) { if (len < 2) CORRUPT(z, "sequences header truncated"); nseq = ((nseq - 128) << 8) + p[1]; h = 2; }
    else { if (len < 3) CORRUPT(z, "sequences header truncated"); nseq = p[1] + ((size_t)p[2] << 8) + 0x7F00; h = 3; }
  }
  size_t lit = 0;
  if (nseq == 0) {
    if (h != len) CORRUPT(z, "bytes after an empty sequences section");
  } else {
    if (h >= len) CORRUPT(z, "sequences modes truncated");
    int modes = p[h++];
    if (modes & 3) CORRUPT(z, "reserved sequence mode bits set");
    h += seqTable(z, &z->ll, modes >> 6, p + h, len - h, LL_DEF, 36, 6, 35, 9);
    h += seqTable(z, &z->of, (modes >> 4) & 3, p + h, len - h, OF_DEF, 29, 5, 31, 8);
    h += seqTable(z, &z->ml, (modes >> 2) & 3, p + h, len - h, ML_DEF, 53, 6, 52, 9);
    if (h >= len) CORRUPT(z, "sequence bitstream missing");
    Bwd r; bwdInit(z, &r, p + h, len - h);
    uint32_t sl = (uint32_t)bwdRead(&r, z->ll.log), so = (uint32_t)bwdRead(&r, z->of.log), sm = (uint32_t)bwdRead(&r, z->ml.log);
    for (size_t i = 0; i < nseq; i++) {
      int oc = z->of.cell[so].sym, mc = z->ml.cell[sm].sym, lc = z->ll.cell[sl].sym;
      if (oc > 31 || mc > 52 || lc > 35) CORRUPT(z, "sequence code out of range");
      uint32_t ofv = (1u << oc) + (uint32_t)bwdRead(&r, oc);
      uint32_t ml = ML_BASE[mc] + (uint32_t)bwdRead(&r, ML_BITS[mc]);
      uint32_t ll = LL_BASE[lc] + (uint32_t)bwdRead(&r, LL_BITS[lc]);
      uint32_t off;
      if (ofv > 3) { off = ofv - 3; z->rep[2] = z->rep[1]; z->rep[1] = z->rep[0]; z->rep[0] = off; }
      else {
        int idx = (int)ofv - 1 + (ll == 0);
        if (idx == 0) off = z->rep[0];
        else {
          off = idx == 3 ? z->rep[0] - 1 : z->rep[idx];
          if (idx > 1) z->rep[2] = z->rep[1];
          z->rep[1] = z->rep[0]; z->rep[0] = off;
        }
      }
      if (i + 1 < nseq) {
        sl = z->ll.cell[sl].base + (uint32_t)bwdRead(&r, z->ll.cell[sl].nbBits);
        sm = z->ml.cell[sm].base + (uint32_t)bwdRead(&r, z->ml.cell[sm].nbBits);
        so = z->of.cell[so].base + (uint32_t)bwdRead(&r, z->of.cell[so].nbBits);
      }
      if (r.pos < 0) CORRUPT(z, "sequence bitstream overrun");
      if (ll > z->nlit - lit) CORRUPT(z, "sequence uses more literals than decoded");
      grow(z, (size_t)ll + ml);
      memcpy(z->out + z->n, z->lit + lit, ll); z->n += ll; lit += ll;
      if (off == 0 || off > z->n || off > z->window) CORRUPT(z, "match offset beyond the window");
      uint8_t *d = z->out + z->n; const uint8_t *s = d - off;
      for (uint32_t k = 0; k < ml; k++) d[k] = s[k];
      z->n += ml;
    }
    if (r.pos != 0) CORRUPT(z, "sequence bitstream not fully consumed");
  }
  grow(z, z->nlit - lit);
  memcpy(z->out + z->n, z->lit + lit, z->nlit - lit); z->n += z->nlit - lit;
}

/* ---- XXH64 ---- */
static const uint64_t P1 = 11400714785074694791ull, P2 = 14029467366897019727ull, P3 = 1609587929392839161ull,
  P4 = 9650029242287828579ull, P5 = 2870177450012600261ull;
static uint64_t rotl(uint64_t x, int r) { return (x << r) | (x >> (64 - r)); }
static uint64_t rd64(const uint8_t *p) { uint64_t v = 0; for (int i = 7; i >= 0; i--) v = v << 8 | p[i]; return v; }
static uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static uint64_t round64(uint64_t acc, uint64_t in) { return rotl(acc + in * P2, 31) * P1; }
static uint64_t merge64(uint64_t acc, uint64_t v) { return (acc ^ round64(0, v)) * P1 + P4; }
static uint64_t xxh64(const uint8_t *p, size_t n) {
  const uint8_t *end = p + n; uint64_t h;
  if (n >= 32) {
    uint64_t v1 = P1 + P2, v2 = P2, v3 = 0, v4 = 0 - P1;
    for (; p + 32 <= end; p += 32) { v1 = round64(v1, rd64(p)); v2 = round64(v2, rd64(p + 8)); v3 = round64(v3, rd64(p + 16)); v4 = round64(v4, rd64(p + 24)); }
    h = rotl(v1, 1) + rotl(v2, 7) + rotl(v3, 12) + rotl(v4, 18);
    h = merge64(h, v1); h = merge64(h, v2); h = merge64(h, v3); h = merge64(h, v4);
  } else h = P5;
  h += (uint64_t)n;
  for (; p + 8 <= end; p += 8) h = rotl(h ^ round64(0, rd64(p)), 27) * P1 + P4;
  if (p + 4 <= end) { h = rotl(h ^ (uint64_t)rd32(p) * P1, 23) * P2 + P3; p += 4; }
  for (; p < end; p++) h = rotl(h ^ (uint64_t)*p * P5, 11) * P1;
  h ^= h >> 33; h *= P2; h ^= h >> 29; h *= P3; h ^= h >> 32;
  return h;
}

/* returns 0 and a malloc'd buffer, or -1 with err set */
int zstdDecompress(const uint8_t *src, size_t len, uint8_t **outp, size_t *outn, char *err, size_t errlen) {
  Z *z = calloc(1, sizeof(Z));
  if (!z) { snprintf(err, errlen, "ERR_OOM: decoder state"); return -1; }
  z->err = err; z->errlen = errlen; z->limit = (size_t)1 << 30;
  z->rep[0] = 1; z->rep[1] = 4; z->rep[2] = 8;
  z->out = malloc(64); z->cap = 64;
  if (!z->out) { free(z); snprintf(err, errlen, "ERR_OOM: output buffer"); return -1; }
  if (setjmp(z->jb)) { free(z->out); free(z); return -1; }
  if (len < 4) CORRUPT(z, "shorter than a frame magic");
  uint32_t magic = rd32(src);
  if ((magic & 0xFFFFFFF0u) == 0x184D2A50u) fail(z, "ERR_ZSTD_UNSUPPORTED", "skippable frame");
  if (magic != 0xFD2FB528u) CORRUPT(z, "bad frame magic");
  size_t at = 4;
  if (at >= len) CORRUPT(z, "frame header truncated");
  int fhd = src[at++], fcsFlag = fhd >> 6, single = (fhd >> 5) & 1, checksum = (fhd >> 2) & 1, dictFlag = fhd & 3;
  if (fhd & 8) CORRUPT(z, "reserved frame header bit set");
  if (!single) {
    if (at >= len) CORRUPT(z, "window descriptor truncated");
    int wd = src[at++], wlog = 10 + (wd >> 3);
    if (wlog > MAX_WINDOW_LOG) CORRUPT(z, "window larger than 128 MiB");
    uint64_t base = 1ull << wlog;
    z->window = base + (base >> 3) * (uint64_t)(wd & 7);
  }
  int dsize = dictFlag == 0 ? 0 : dictFlag == 1 ? 1 : dictFlag == 2 ? 2 : 4;
  if (at + (size_t)dsize > len) CORRUPT(z, "dictionary id truncated");
  uint32_t dict = 0;
  for (int i = 0; i < dsize; i++) dict |= (uint32_t)src[at + (size_t)i] << (8 * i);
  at += (size_t)dsize;
  if (dict) fail(z, "ERR_ZSTD_UNSUPPORTED", "frame needs a dictionary");
  int fsize = fcsFlag == 0 ? (single ? 1 : 0) : fcsFlag == 1 ? 2 : fcsFlag == 2 ? 4 : 8;
  if (at + (size_t)fsize > len) CORRUPT(z, "frame content size truncated");
  uint64_t fcs = 0; int haveFcs = fsize > 0;
  for (int i = 0; i < fsize; i++) fcs |= (uint64_t)src[at + (size_t)i] << (8 * i);
  if (fsize == 2) fcs += 256;
  at += (size_t)fsize;
  if (single) z->window = fcs;
  if (haveFcs) { if (fcs > z->limit) CORRUPT(z, "content size above 1 GiB"); z->limit = (size_t)fcs; }
  uint64_t blockMax = z->window < MAX_BLOCK ? z->window : MAX_BLOCK;
  for (;;) {
    if (at + 3 > len) CORRUPT(z, "block header truncated");
    uint32_t bh = src[at] | (uint32_t)src[at + 1] << 8 | (uint32_t)src[at + 2] << 16;
    at += 3;
    int last = bh & 1, type = (bh >> 1) & 3; size_t size = bh >> 3;
    if (size > blockMax) CORRUPT(z, "block larger than the block maximum");
    if (type == 3) CORRUPT(z, "reserved block type");
    if (type == 1) {
      if (at + 1 > len) CORRUPT(z, "RLE block truncated");
      grow(z, size); memset(z->out + z->n, src[at], size); z->n += size; at += 1;
    } else {
      if (at + size > len) CORRUPT(z, "block truncated");
      if (type == 0) { grow(z, size); memcpy(z->out + z->n, src + at, size); z->n += size; }
      else compressedBlock(z, src + at, size);
      at += size;
    }
    if (last) break;
  }
  if (haveFcs && z->n != fcs) CORRUPT(z, "decoded size differs from the frame content size");
  if (checksum) {
    if (at + 4 > len) CORRUPT(z, "content checksum truncated");
    if (rd32(src + at) != (uint32_t)xxh64(z->out, z->n)) CORRUPT(z, "content checksum mismatch");
    at += 4;
  }
  if (at != len) {
    if (len - at >= 4 && (rd32(src + at) == 0xFD2FB528u || (rd32(src + at) & 0xFFFFFFF0u) == 0x184D2A50u)) fail(z, "ERR_ZSTD_UNSUPPORTED", "more than one frame");
    CORRUPT(z, "trailing bytes after the frame");
  }
  *outp = z->out; *outn = z->n;
  free(z);
  return 0;
}
