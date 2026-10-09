/* Parquet reader (plan R1 H10): thrift compact footer, flat schema of optional or required leaves, dictionary
   pages, DATA_PAGE v1 and v2, RLE/bit-packed hybrid levels and indices, PLAIN, INT32 narrowed by logical Int(8),
   UNCOMPRESSED SNAPPY and ZSTD. Only the requested column chunk of one row group is read into memory. */
#include "thrift.h"
#include "value.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int zstdDecompress(const uint8_t *src, size_t len, uint8_t **outp, size_t *outn, char *err, size_t errlen);
int snappyDecompress(const uint8_t *src, size_t len, uint8_t *dst, size_t want);

enum { PT_INT32 = 1, PT_INT64 = 2, PT_DOUBLE = 5 };
#define MAX_ENC 16
typedef struct { int ptype, codec; int64_t nvals, dictOff, dataOff, compSize; int nenc, encodings[MAX_ENC]; } Chunk;
typedef struct { char name[256]; int ptype, maxDef, int8; } Col;
typedef struct { char *key, *val; } PqKv;
typedef struct { char *path; int64_t size, rows; int ncols, ngroups; Col *cols; int64_t *groupRows; Chunk *chunks; int nkv; PqKv *kv; } Pq;
typedef struct { int type, uncomp, comp, nvals, encoding, v2defLen, v2repLen, v2compressed; } PageHdr;
static int pageHeader(Tr *t, PageHdr *h);

static void pqFree(void *p) {
  Pq *q = p;
  if (!q) return;
  free(q->path); free(q->cols); free(q->groupRows); free(q->chunks);
  if (q->kv) { for (int i = 0; i < q->nkv; i++) { free(q->kv[i].key); free(q->kv[i].val); } free(q->kv); }
  free(q);
}

#define PQERR(...) do { snprintf(err, errlen, __VA_ARGS__); return -1; } while (0)

static int readAt(const char *path, int64_t off, size_t n, uint8_t *dst) {
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  int ok = fseeko(f, off, SEEK_SET) == 0 && fread(dst, 1, n, f) == n;
  fclose(f);
  return ok ? 0 : -1;
}

static void schemaElement(Tr *t, Col *c, int *children, int *repetition) {
  int last = 0, id, ty;
  while (trField(t, &last, &id, &ty)) {
    if (id == 1) c->ptype = (int)trInt(t, ty);
    else if (id == 3) *repetition = (int)trInt(t, ty);
    else if (id == 4 && ty == TT_BINARY) { const uint8_t *s; size_t n = trBinary(t, &s); if (n >= sizeof c->name) n = sizeof c->name - 1; memcpy(c->name, s, n); c->name[n] = 0; }
    else if (id == 5) *children = (int)trInt(t, ty);
    else if (id == 6) { if (trInt(t, ty) == 15) c->int8 = 1; }
    else if (id == 10 && ty == TT_STRUCT) {
      int l2 = 0, i2, t2;
      while (trField(t, &l2, &i2, &t2)) {
        if (i2 == 10 && t2 == TT_STRUCT) {
          int l3 = 0, i3, t3, bits = 0;
          while (trField(t, &l3, &i3, &t3)) { if (i3 == 1) bits = (int)trInt(t, t3); else trSkip(t, t3, 0); }
          if (bits == 8) c->int8 = 1;
        } else trSkip(t, t2, 0);
      }
    } else trSkip(t, ty, 0);
  }
}

static void columnChunk(Tr *t, Chunk *ch) {
  int last = 0, id, ty, eet;
  while (trField(t, &last, &id, &ty)) {
    if (id != 3 || ty != TT_STRUCT) { trSkip(t, ty, 0); continue; }
    int l2 = 0, i2, t2;
    while (trField(t, &l2, &i2, &t2)) {
      switch (i2) {
        case 1: ch->ptype = (int)trInt(t, t2); break;
        case 2: {
          if (t2 != TT_LIST) { trSkip(t, t2, 0); break; }
          size_t k = trList(t, &eet);
          for (size_t e = 0; e < k && !t->err; e++) { int enc = (int)trInt(t, eet); if (ch->nenc < MAX_ENC) ch->encodings[ch->nenc++] = enc; }
          break;
        }
        case 4: ch->codec = (int)trInt(t, t2); break;
        case 5: ch->nvals = trInt(t, t2); break;
        case 7: ch->compSize = trInt(t, t2); break;
        case 9: ch->dataOff = trInt(t, t2); break;
        case 11: ch->dictOff = trInt(t, t2); break;
        default: trSkip(t, t2, 0);
      }
    }
  }
}

static int parseFooter(Pq *q, const uint8_t *p, size_t n, char *err, size_t errlen) {
  Tr t = {p, p + n, 0};
  int last = 0, id, ty, nschema = 0, et;
  while (trField(&t, &last, &id, &ty)) {
    if (id == 2 && ty == TT_LIST) {
      size_t k = trList(&t, &et);
      if (k < 2 || k > 4096) PQERR("ERR_PARQUET: schema with %zu elements", k);
      q->cols = calloc(k - 1, sizeof(Col)); nschema = (int)k;
      if (!q->cols) PQERR("ERR_OOM: schema");
      for (size_t i = 0; i < k && !t.err; i++) {
        Col tmp = {{0}, 0, 0, 0}; int children = 0, rep = 0;
        schemaElement(&t, i ? &q->cols[i - 1] : &tmp, &children, &rep);
        if (i == 0) { if (children != (int)k - 1) PQERR("ERR_PARQUET_UNSUPPORTED: nested schema"); continue; }
        if (children) PQERR("ERR_PARQUET_UNSUPPORTED: nested column %s", q->cols[i - 1].name);
        if (rep == 2) PQERR("ERR_PARQUET_UNSUPPORTED: repeated column %s", q->cols[i - 1].name);
        q->cols[i - 1].maxDef = rep == 1;
      }
      q->ncols = nschema - 1;
    } else if (id == 3) q->rows = trInt(&t, ty);
    else if (id == 4 && ty == TT_LIST) {
      if (!q->ncols) PQERR("ERR_PARQUET: row groups before schema");
      size_t g = trList(&t, &et);
      if (g > 65536) PQERR("ERR_PARQUET: %zu row groups", g);
      q->ngroups = (int)g;
      q->groupRows = calloc(g + 1, sizeof(int64_t)); q->chunks = calloc(g * (size_t)q->ncols + 1, sizeof(Chunk));
      if (!q->groupRows || !q->chunks) PQERR("ERR_OOM: row groups");
      for (size_t r = 0; r < g && !t.err; r++) {
        int l2 = 0, i2, t2, seen = 0;
        while (trField(&t, &l2, &i2, &t2)) {
          if (i2 == 1 && t2 == TT_LIST) {
            size_t c = trList(&t, &et);
            if ((int)c != q->ncols) PQERR("ERR_PARQUET: row group %zu has %zu columns, schema %d", r, c, q->ncols);
            for (size_t j = 0; j < c && !t.err; j++) columnChunk(&t, &q->chunks[r * (size_t)q->ncols + j]);
            seen = 1;
          } else if (i2 == 3) q->groupRows[r] = trInt(&t, t2);
          else trSkip(&t, t2, 0);
        }
        if (!seen) PQERR("ERR_PARQUET: row group %zu without columns", r);
      }
    } else if (id == 5 && ty == TT_LIST) {
      int et2;
      size_t nkv = trList(&t, &et2);
      if (nkv > 4096) PQERR("ERR_PARQUET: too many metadata keys");
      q->kv = calloc(nkv + 1, sizeof(PqKv));
      if (!q->kv) PQERR("ERR_OOM: metadata");
      for (size_t i = 0; i < nkv && !t.err; i++) {
        int l2 = 0, i2, t2; char *kstr = NULL, *vstr = NULL;
        while (trField(&t, &l2, &i2, &t2)) {
          if ((i2 == 1 || i2 == 2) && t2 == TT_BINARY) {
            const uint8_t *s; size_t sn = trBinary(&t, &s);
            char *d = malloc(sn + 1);
            if (d) { memcpy(d, s, sn); d[sn] = 0; }
            if (i2 == 1) { free(kstr); kstr = d; } else { free(vstr); vstr = d; }
          } else trSkip(&t, t2, 0);
        }
        if (kstr) { q->kv[q->nkv].key = kstr; q->kv[q->nkv].val = vstr ? vstr : strdup(""); q->nkv++; }
        else free(vstr);
      }
    } else trSkip(&t, ty, 0);
  }
  if (t.err) PQERR("ERR_PARQUET: malformed footer");
  if (!q->ncols) PQERR("ERR_PARQUET: footer without a schema");
  for (int i = 0; i < q->ngroups * q->ncols; i++) {
    Chunk *c = &q->chunks[i];
    int col = i % q->ncols, rg = i / q->ncols;
    int64_t start = c->dictOff > 0 && c->dictOff < c->dataOff ? c->dictOff : c->dataOff;
    if (start < 4 || c->compSize <= 0 || start + c->compSize > q->size - 8) PQERR("ERR_PARQUET: column chunk outside the file");
    if (c->ptype != q->cols[col].ptype) PQERR("ERR_PARQUET: chunk type differs from schema");
    if (c->codec != 0 && c->codec != 1 && c->codec != 6) PQERR("ERR_PARQUET_UNSUPPORTED: column %s row group %d codec %d", q->cols[col].name, rg, c->codec);
    for (int e = 0; e < c->nenc; e++) {
      int enc = c->encodings[e];
      if (enc != 0 && enc != 1 && enc != 2 && enc != 3 && enc != 5 && enc != 8 && enc != 9)
        PQERR("ERR_PARQUET_UNSUPPORTED: column %s row group %d encoding %d", q->cols[col].name, rg, enc);
    }
    for (size_t pos = 0; pos < (size_t)c->compSize;) {
      uint8_t hbuf[128];
      size_t rem = (size_t)c->compSize - pos, toRead = rem < sizeof hbuf ? rem : sizeof hbuf;
      if (readAt(q->path, start + (int64_t)pos, toRead, hbuf) != 0) PQERR("ERR_IO: cannot read column chunk");
      Tr pt = {hbuf, hbuf + toRead, 0}; PageHdr ph;
      if (pageHeader(&pt, &ph) != 0) PQERR("ERR_PARQUET: malformed page header in column %s row group %d", q->cols[col].name, rg);
      size_t hl = (size_t)(pt.p - hbuf);
      if ((uint64_t)ph.comp > (uint64_t)rem - hl) PQERR("ERR_PARQUET: page beyond the column chunk in column %s row group %d", q->cols[col].name, rg);
      if ((ph.type == 0 || ph.type == 3) && ph.encoding != 0 && ph.encoding != 2 && ph.encoding != 8 && ph.encoding != 5 && ph.encoding != 9)
        PQERR("ERR_PARQUET_UNSUPPORTED: column %s row group %d encoding %d", q->cols[col].name, rg, ph.encoding);
      pos += hl + (size_t)ph.comp;
    }
  }
  return 0;
}

static Pq *pqOpen(const char *path, char *err, size_t errlen) {
  Pq *q = calloc(1, sizeof(Pq));
  FILE *f = fopen(path, "rb");
  if (!q || !f) { snprintf(err, errlen, "ERR_IO: cannot open %s", path); if (f) fclose(f); free(q); return NULL; }
  uint8_t head[4], tail[8];
  int ok = fseeko(f, 0, SEEK_END) == 0 && (q->size = ftello(f)) >= 12 && fseeko(f, 0, SEEK_SET) == 0 && fread(head, 1, 4, f) == 4 &&
           fseeko(f, q->size - 8, SEEK_SET) == 0 && fread(tail, 1, 8, f) == 8;
  fclose(f);
  if (!ok) { snprintf(err, errlen, "ERR_PARQUET: %s is too short for a parquet file", path); free(q); return NULL; }
  if (memcmp(head, "PAR1", 4) || memcmp(tail + 4, "PAR1", 4)) { snprintf(err, errlen, "ERR_PARQUET: %s has no PAR1 magic", path); free(q); return NULL; }
  uint32_t flen = (uint32_t)tail[0] | (uint32_t)tail[1] << 8 | (uint32_t)tail[2] << 16 | (uint32_t)tail[3] << 24;
  if ((int64_t)flen > q->size - 12 || flen == 0) { snprintf(err, errlen, "ERR_PARQUET: footer length %u outside %s", flen, path); free(q); return NULL; }
  uint8_t *foot = malloc(flen);
  if (!foot || readAt(path, q->size - 8 - flen, flen, foot)) { snprintf(err, errlen, "ERR_IO: cannot read the footer of %s", path); free(foot); free(q); return NULL; }
  q->path = strdup(path);
  int r = parseFooter(q, foot, flen, err, errlen);
  free(foot);
  if (r) { pqFree(q); return NULL; }
  return q;
}

/* RLE/bit-packed hybrid: count values of width bw into out */
static int hybrid(const uint8_t *p, size_t len, int bw, size_t count, uint32_t *out) {
  size_t pos = 0, got = 0, vb = (size_t)(bw + 7) / 8;
  while (got < count) {
    uint64_t h = 0;
    for (int s = 0;; s += 7) { if (pos >= len || s > 35) return -1; uint8_t b = p[pos++]; h |= (uint64_t)(b & 0x7F) << s; if (!(b & 0x80)) break; }
    if (h & 1) {
      uint64_t groups = h >> 1, nbytes = groups * (uint64_t)bw;
      if (nbytes > len - pos) return -1;
      for (uint64_t i = 0; i < groups * 8 && got < count; i++, got++) {
        uint32_t v = 0; uint64_t bit = i * (uint64_t)bw;
        for (int k = 0; k < bw; k++, bit++) v |= (uint32_t)((p[pos + (bit >> 3)] >> (bit & 7)) & 1) << k;
        out[got] = v;
      }
      pos += nbytes;
    } else {
      uint64_t run = h >> 1; uint32_t v = 0;
      if (vb > len - pos) return -1;
      for (size_t k = 0; k < vb; k++) v |= (uint32_t)p[pos + k] << (8 * k);
      pos += vb;
      if (run == 0) return -1;
      for (uint64_t i = 0; i < run && got < count; i++) out[got++] = v;
    }
  }
  return 0;
}

static uint8_t *decompress(int codec, const uint8_t *src, size_t n, size_t want, char *err, size_t errlen) {
  if (codec == 0) {
    if (n != want) { snprintf(err, errlen, "ERR_PARQUET: uncompressed page size mismatch"); return NULL; }
    uint8_t *d = malloc(want + 1);
    if (d) memcpy(d, src, n);
    return d;
  }
  if (codec == 1) {
    uint8_t *d = malloc(want + 1);
    if (d && snappyDecompress(src, n, d, want) != 0) { free(d); snprintf(err, errlen, "ERR_PARQUET: corrupt snappy page"); return NULL; }
    return d;
  }
  if (codec == 6) {
    uint8_t *d; size_t dn;
    if (zstdDecompress(src, n, &d, &dn, err, errlen) != 0) return NULL;
    if (dn != want) { free(d); snprintf(err, errlen, "ERR_PARQUET: zstd page size mismatch"); return NULL; }
    return d;
  }
  snprintf(err, errlen, "ERR_PARQUET_UNSUPPORTED: codec %d", codec);
  return NULL;
}

static int pageHeader(Tr *t, PageHdr *h) {
  int last = 0, id, ty;
  memset(h, 0, sizeof *h); h->v2compressed = 1; h->type = -1;
  while (trField(t, &last, &id, &ty)) {
    if (id == 1) h->type = (int)trInt(t, ty);
    else if (id == 2) h->uncomp = (int)trInt(t, ty);
    else if (id == 3) h->comp = (int)trInt(t, ty);
    else if ((id == 5 || id == 7 || id == 8) && ty == TT_STRUCT) {
      int l2 = 0, i2, t2;
      while (trField(t, &l2, &i2, &t2)) {
        if (i2 == 1) h->nvals = (int)trInt(t, t2);
        else if (id == 5 && i2 == 2) h->encoding = (int)trInt(t, t2);
        else if (id == 7 && i2 == 2) h->encoding = (int)trInt(t, t2);
        else if (id == 8 && i2 == 4) h->encoding = (int)trInt(t, t2);
        else if (id == 8 && i2 == 5) h->v2defLen = (int)trInt(t, t2);
        else if (id == 8 && i2 == 6) h->v2repLen = (int)trInt(t, t2);
        else if (id == 8 && i2 == 7) h->v2compressed = trBool(t, t2);
        else trSkip(t, t2, 0);
      }
    } else trSkip(t, ty, 0);
  }
  return t->err || h->type < 0 || h->uncomp < 0 || h->comp < 0 || h->nvals < 0 ? -1 : 0;
}

static int plain(int ptype, const uint8_t *p, size_t len, size_t n, int64_t *out) {
  size_t w = ptype == PT_INT32 ? 4 : 8;
  if (n > len / w) return -1;
  for (size_t i = 0; i < n; i++) {
    const uint8_t *q = p + i * w;
    if (w == 4) out[i] = (int32_t)((uint32_t)q[0] | (uint32_t)q[1] << 8 | (uint32_t)q[2] << 16 | (uint32_t)q[3] << 24);
    else { uint64_t v = 0; for (int k = 7; k >= 0; k--) v = v << 8 | q[k]; memcpy(&out[i], &v, 8); }
  }
  return 0;
}

static int byteStreamSplit(int ptype, const uint8_t *p, size_t len, size_t n, int64_t *out) {
  size_t w = ptype == PT_INT32 ? 4 : 8;
  if (n > len / w) return -1;
  for (size_t i = 0; i < n; i++) {
    uint64_t v = 0;
    for (int k = (int)w - 1; k >= 0; k--) v = v << 8 | p[(size_t)k * n + i];
    if (w == 4) out[i] = (int32_t)(uint32_t)v;
    else memcpy(&out[i], &v, 8);
  }
  return 0;
}

static uint64_t readUleb128(const uint8_t **p, const uint8_t *end, int *err) {
  uint64_t v = 0;
  for (int s = 0; *p < end && s < 64; s += 7) {
    uint8_t b = *(*p)++;
    v |= (uint64_t)(b & 0x7F) << s;
    if (!(b & 0x80)) return v;
  }
  *err = 1;
  return 0;
}

static int64_t readZz128(const uint8_t **p, const uint8_t *end, int *err) {
  uint64_t v = readUleb128(p, end, err);
  return (int64_t)(v >> 1) ^ -(int64_t)(v & 1);
}

/* DELTA_BINARY_PACKED: deltas wrap modulo 2^64 (2^32 for INT32) as the writer computed them */
static int deltaBinaryPacked(int ptype, const uint8_t *p, size_t len, size_t n, int64_t *out) {
  if (n == 0) return 0;
  const uint8_t *end = p + len; int err = 0;
  uint64_t bs = readUleb128(&p, end, &err), nmb = readUleb128(&p, end, &err), tc = readUleb128(&p, end, &err);
  int64_t cur = readZz128(&p, end, &err);
  if (err || nmb == 0 || bs % nmb != 0 || tc < n) return -1;
  size_t vpm = (size_t)(bs / nmb), got = 1;
  if (vpm == 0) return -1;
  out[0] = cur = ptype == PT_INT32 ? (int32_t)cur : cur;
  while (got < n) {
    int64_t minD = readZz128(&p, end, &err);
    if (err || nmb > (size_t)(end - p)) return -1;
    const uint8_t *bw = p; p += nmb;
    for (size_t mb = 0; mb < nmb && got < n; mb++) {
      if (bw[mb] > 64) return -1;
      size_t mbBytes = (vpm * (size_t)bw[mb] + 7) / 8;
      if (mbBytes > (size_t)(end - p)) return -1;
      for (size_t i = 0; i < vpm && got < n; i++) {
        uint64_t v = 0, bit = i * (uint64_t)bw[mb];
        for (int k = 0; k < bw[mb]; k++, bit++) v |= (uint64_t)((p[bit >> 3] >> (bit & 7)) & 1) << k;
        int64_t d = (int64_t)((uint64_t)minD + v);
        cur = ptype == PT_INT32 ? (int32_t)((uint32_t)cur + (uint32_t)d) : (int64_t)((uint64_t)cur + (uint64_t)d);
        out[got++] = cur;
      }
      p += mbBytes;
    }
  }
  return 0;
}

/* decodes one column chunk into raw 8-byte cells (int64 or double bits); returns count or -1 */
static int64_t readChunk(Pq *q, int col, int rg, int64_t **outp, char *err, size_t errlen) {
  Chunk *c = &q->chunks[(size_t)rg * (size_t)q->ncols + (size_t)col];
  Col *cd = &q->cols[col];
  int64_t start = c->dictOff > 0 && c->dictOff < c->dataOff ? c->dictOff : c->dataOff, want = q->groupRows[rg];
  if (want < 0 || want > ((int64_t)1 << 31) || c->nvals != want) PQERR("ERR_PARQUET: chunk value count %lld differs from %lld rows", (long long)c->nvals, (long long)want);
  uint8_t *buf = malloc((size_t)c->compSize);
  int64_t *out = malloc(sizeof(int64_t) * (size_t)(want + 1)), *dict = NULL, got = 0, ndict = 0;
  uint32_t *idx = NULL;
  if (!buf || !out || readAt(q->path, start, (size_t)c->compSize, buf)) { free(buf); free(out); PQERR("ERR_IO: cannot read column chunk"); }
  size_t pos = 0; int rc = -1;
  while (got < want) {
    Tr t = {buf + pos, buf + c->compSize, 0}; PageHdr h;
    if (pos >= (size_t)c->compSize || pageHeader(&t, &h)) { snprintf(err, errlen, "ERR_PARQUET: malformed page header"); goto done; }
    pos = (size_t)(t.p - buf);
    if ((uint64_t)h.comp > (uint64_t)c->compSize - pos) { snprintf(err, errlen, "ERR_PARQUET: page beyond the column chunk"); goto done; }
    const uint8_t *pd = buf + pos; pos += (size_t)h.comp;
    if (h.type == 2) {
      uint8_t *d = decompress(c->codec, pd, (size_t)h.comp, (size_t)h.uncomp, err, errlen);
      if (!d) goto done;
      free(dict); dict = malloc(sizeof(int64_t) * ((size_t)h.nvals + 1)); ndict = h.nvals;
      int bad = !dict || plain(cd->ptype, d, (size_t)h.uncomp, (size_t)h.nvals, dict);
      free(d);
      if (bad) { snprintf(err, errlen, "ERR_PARQUET: dictionary page truncated"); goto done; }
      continue;
    }
    if (h.type != 0 && h.type != 3) continue;
    if (h.nvals > want - got) { snprintf(err, errlen, "ERR_PARQUET: page values beyond the row group"); goto done; }
    uint8_t *d; const uint8_t *vals; size_t vlen, nonNull = (size_t)h.nvals;
    uint32_t *lv = malloc(sizeof(uint32_t) * ((size_t)h.nvals + 1));
    if (!lv) { snprintf(err, errlen, "ERR_OOM: levels"); goto done; }
    if (h.type == 0) {
      d = decompress(c->codec, pd, (size_t)h.comp, (size_t)h.uncomp, err, errlen);
      if (!d) { free(lv); goto done; }
      vals = d; vlen = (size_t)h.uncomp;
      if (cd->maxDef) {
        if (vlen < 4) { free(d); free(lv); snprintf(err, errlen, "ERR_PARQUET: definition levels truncated"); goto done; }
        uint32_t dl = (uint32_t)vals[0] | (uint32_t)vals[1] << 8 | (uint32_t)vals[2] << 16 | (uint32_t)vals[3] << 24;
        if (dl > vlen - 4 || hybrid(vals + 4, dl, 1, (size_t)h.nvals, lv)) { free(d); free(lv); snprintf(err, errlen, "ERR_PARQUET: bad definition levels"); goto done; }
        vals += 4 + dl; vlen -= 4 + dl;
      }
    } else {
      size_t lev = (size_t)h.v2defLen + (size_t)h.v2repLen;
      if (h.v2defLen < 0 || h.v2repLen != 0 || lev > (size_t)h.comp || lev > (size_t)h.uncomp) { free(lv); snprintf(err, errlen, "ERR_PARQUET: bad v2 level lengths"); goto done; }
      if (cd->maxDef && hybrid(pd, (size_t)h.v2defLen, 1, (size_t)h.nvals, lv)) { free(lv); snprintf(err, errlen, "ERR_PARQUET: bad definition levels"); goto done; }
      d = h.v2compressed ? decompress(c->codec, pd + lev, (size_t)h.comp - lev, (size_t)h.uncomp - lev, err, errlen)
                         : decompress(0, pd + lev, (size_t)h.comp - lev, (size_t)h.comp - lev, err, errlen);
      if (!d) { free(lv); goto done; }
      vals = d; vlen = h.v2compressed ? (size_t)h.uncomp - lev : (size_t)h.comp - lev;
    }
    if (cd->maxDef) { nonNull = 0; for (int i = 0; i < h.nvals; i++) nonNull += lv[i] == 1; }
    free(lv);
    if (nonNull != (size_t)h.nvals) { free(d); snprintf(err, errlen, "ERR_PARQUET_NULL: column %s has null values", cd->name); goto done; }
    int bad;
    if (h.encoding == 0) bad = plain(cd->ptype, vals, vlen, nonNull, out + got);
    else if (h.encoding == 5) bad = (cd->ptype != PT_INT32 && cd->ptype != PT_INT64) || deltaBinaryPacked(cd->ptype, vals, vlen, nonNull, out + got);
    else if (h.encoding == 9) bad = byteStreamSplit(cd->ptype, vals, vlen, nonNull, out + got);
    else if (h.encoding == 2 || h.encoding == 8) {
      bad = !dict || vlen < 1 || vals[0] > 32;
      if (!bad) {
        free(idx); idx = malloc(sizeof(uint32_t) * (nonNull + 1));
        bad = !idx || hybrid(vals + 1, vlen - 1, vals[0], nonNull, idx);
        for (size_t i = 0; !bad && i < nonNull; i++) { if (idx[i] >= (uint32_t)ndict) bad = 1; else out[got + (int64_t)i] = dict[idx[i]]; }
      }
    } else { free(d); snprintf(err, errlen, "ERR_PARQUET_UNSUPPORTED: encoding %d", h.encoding); goto done; }
    free(d);
    if (bad) { snprintf(err, errlen, "ERR_PARQUET: corrupt data page"); goto done; }
    got += h.nvals;
  }
  rc = 0;
done:
  free(buf); free(dict); free(idx);
  if (rc) { free(out); return -1; }
  *outp = out;
  return got;
}

/* ---- builtins ---- */
static Pq *handle(Val v, const char *who) {
  if (v.tag != T_HANDLE || strcmp(((Handle *)v.u.o)->kind, "parquet")) aslError("ERR_TYPE", "%s expects a ParquetHandle, got %s", who, tagName(v.tag));
  return ((Handle *)v.u.o)->p;
}
static const char *strArg(Val v, const char *who) {
  if (v.tag != T_STR) aslError("ERR_TYPE", "%s expects String, got %s", who, tagName(v.tag));
  return ((Str *)v.u.o)->s;
}
static int colIndex(Pq *q, Val name, const char *who) {
  const char *s = strArg(name, who);
  for (int i = 0; i < q->ncols; i++) if (!strcmp(q->cols[i].name, s)) return i;
  aslError("ERR_PARQUET", "%s: no column %s", who, s);
}

/* (:m :why "Pq payload is native memory holding no Val" :ref D153) */
static Val bOpen(Val *a, int n) {
  (void)n; char err[512];
  Pq *q = pqOpen(strArg(a[0], "parquetOpen"), err, sizeof err);
  if (!q) return mkResult(0, mkStr(err, strlen(err)));
  Handle *h = asl_alloc(O_HANDLE, sizeof(Handle));
  h->kind = "parquet"; h->p = q; h->fin = pqFree;
  return mkResult(1, vobj(T_HANDLE, h));
}
static Val bGroups(Val *a, int n) { (void)n; return vint(handle(a[0], "parquetNumRowGroups")->ngroups); }
static Val bRows(Val *a, int n) { (void)n; return vint(handle(a[0], "parquetNumRows")->rows); }
static Val bColType(Val *a, int n) {
  (void)n; Pq *q = handle(a[0], "parquetColumnType"); Col *c = &q->cols[colIndex(q, a[1], "parquetColumnType")];
  const char *s = c->ptype == PT_INT64 ? "int64" : c->ptype == PT_DOUBLE ? "double" : c->ptype == PT_INT32 ? (c->int8 ? "int8" : "int32") : "other";
  return mkStr(s, strlen(s));
}

static Val readAs(Val *a, Tag t, const char *who) {
  Pq *q = handle(a[0], who); int col = colIndex(q, a[1], who);
  if (a[2].tag != T_INT || a[2].u.i < 0 || a[2].u.i >= q->ngroups) aslError("ERR_RANGE", "%s: row group outside 0..%d", who, q->ngroups - 1);
  Col *c = &q->cols[col];
  if ((t == T_F64ARR && c->ptype != PT_DOUBLE) || (t == T_I64ARR && c->ptype != PT_INT64) || (t == T_I8ARR && !(c->ptype == PT_INT32 && c->int8)))
    aslError("ERR_TYPE", "%s: column %s is not of that type", who, c->name);
  char err[512]; int64_t *raw;
  gcWillAllocate((size_t)q->groupRows[a[2].u.i] * 8);
  int64_t m = readChunk(q, col, (int)a[2].u.i, &raw, err, sizeof err);
  if (m < 0) aslError("ERR_PARQUET", "%s: %s", who, err);
  Arr *r = asl_alloc(O_ARR, sizeof(Arr));
  r->len = (size_t)m; r->elem = t == T_I8ARR ? 1 : 8;
  if (t == T_I8ARR) {
    r->data = malloc((size_t)m + 1);
    if (!r->data) aslError("ERR_OOM", "%s", who);
    for (int64_t i = 0; i < m; i++) {
      if (raw[i] < -128 || raw[i] > 127) { long long bad = (long long)raw[i]; free(raw); aslError("ERR_RANGE", "%s: %lld outside Int(8)", who, bad); }
      ((int8_t *)r->data)[i] = (int8_t)raw[i];
    }
    free(raw);
  } else r->data = (unsigned char *)raw;
  gcAccount(&r->h, (size_t)m * r->elem);
  return vobj(t, r);
}
static Val bF64(Val *a, int n) { (void)n; return readAs(a, T_F64ARR, "parquetReadF64"); }
static Val bI64(Val *a, int n) { (void)n; return readAs(a, T_I64ARR, "parquetReadI64"); }
static Val bI8(Val *a, int n) { (void)n; return readAs(a, T_I8ARR, "parquetReadI8"); }
static Val bKvMeta(Val *a, int n) {
  (void)n;
  Pq *q = handle(a[0], "parquetKvMetadata");
  const char *k = strArg(a[1], "parquetKvMetadata");
  for (int i = 0; i < q->nkv; i++)
    if (!strcmp(q->kv[i].key, k)) { const char *v = q->kv[i].val ? q->kv[i].val : ""; return mkResult(1, mkStr(v, strlen(v))); }
  return mkResult(0, mkStr("key not found", 13));
}

const Builtin parquetBuiltins[] = {
  {"parquetOpen", bOpen, 1, 1}, {"parquetNumRowGroups", bGroups, 1, 0}, {"parquetNumRows", bRows, 1, 0}, {"parquetColumnType", bColType, 2, 0},
  {"parquetReadF64", bF64, 3, 1}, {"parquetReadI64", bI64, 3, 1}, {"parquetReadI8", bI8, 3, 1}, {"parquetKvMetadata", bKvMeta, 2, 1},
};
const int nParquetBuiltins = (int)(sizeof parquetBuiltins / sizeof parquetBuiltins[0]);
