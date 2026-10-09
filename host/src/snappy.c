/* Raw snappy block decoder (plan R1 H10), as parquet stores it: varint length, literals and back-copies. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* returns 0 and fills dst (exactly want bytes), or -1 on any malformed input */
int snappyDecompress(const uint8_t *src, size_t len, uint8_t *dst, size_t want) {
  size_t i = 0, n = 0; uint64_t total = 0;
  for (int shift = 0;; shift += 7) {
    if (i >= len || shift > 35) return -1;
    uint8_t b = src[i++];
    total |= (uint64_t)(b & 0x7F) << shift;
    if (!(b & 0x80)) break;
  }
  if (total != want) return -1;
  while (i < len) {
    uint8_t tag = src[i++];
    size_t l, off;
    switch (tag & 3) {
      case 0:
        l = tag >> 2;
        if (l >= 60) {
          size_t k = l - 59; l = 0;
          if (i + k > len) return -1;
          for (size_t j = 0; j < k; j++) l |= (size_t)src[i + j] << (8 * j);
          i += k;
        }
        l += 1;
        if (i + l > len || n + l > want) return -1;
        memcpy(dst + n, src + i, l); i += l; n += l;
        continue;
      case 1:
        if (i + 1 > len) return -1;
        l = 4 + ((tag >> 2) & 7); off = (size_t)(tag >> 5) << 8 | src[i]; i += 1;
        break;
      case 2:
        if (i + 2 > len) return -1;
        l = 1 + (tag >> 2); off = src[i] | (size_t)src[i + 1] << 8; i += 2;
        break;
      default:
        if (i + 4 > len) return -1;
        l = 1 + (tag >> 2); off = src[i] | (size_t)src[i + 1] << 8 | (size_t)src[i + 2] << 16 | (size_t)src[i + 3] << 24; i += 4;
        break;
    }
    if (off == 0 || off > n || n + l > want) return -1;
    for (size_t j = 0; j < l; j++) dst[n + j] = dst[n + j - off];
    n += l;
  }
  return n == want ? 0 : -1;
}
