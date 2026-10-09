/* Float formatting per I8: the shortest %.Ne precision (1..17) that round-trips, laid out like python repr. */
#include "value.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void floatRepr(double d, char *out) {
  if (isnan(d)) { strcpy(out, "nan"); return; }
  if (isinf(d)) { strcpy(out, d < 0 ? "-inf" : "inf"); return; }
  char buf[40];
  int p;
  for (p = 1; p <= 17; p++) {
    snprintf(buf, sizeof buf, "%.*e", p - 1, d);
    if (strtod(buf, NULL) == d) break;
  }
  char digits[24]; int nd = 0, exp10, neg = 0;
  const char *s = buf;
  if (*s == '-') { neg = 1; s++; }
  for (; *s && *s != 'e'; s++) if (*s != '.') digits[nd++] = *s;
  exp10 = atoi(s + 1);
  while (nd > 1 && digits[nd - 1] == '0') nd--;
  digits[nd] = 0;
  char *o = out;
  if (neg) *o++ = '-';
  if (exp10 >= -4 && exp10 < 16) {
    int decpt = exp10 + 1;
    if (decpt <= 0) {
      *o++ = '0'; *o++ = '.';
      for (int i = 0; i < -decpt; i++) *o++ = '0';
      memcpy(o, digits, nd); o += nd;
    } else if (decpt >= nd) {
      memcpy(o, digits, nd); o += nd;
      for (int i = 0; i < decpt - nd; i++) *o++ = '0';
      *o++ = '.'; *o++ = '0';
    } else {
      memcpy(o, digits, decpt); o += decpt; *o++ = '.';
      memcpy(o, digits + decpt, nd - decpt); o += nd - decpt;
    }
    *o = 0;
  } else {
    *o++ = digits[0];
    if (nd > 1) { *o++ = '.'; memcpy(o, digits + 1, nd - 1); o += nd - 1; }
    char eb[16]; snprintf(eb, sizeof eb, "e%c%02d", exp10 < 0 ? '-' : '+', exp10 < 0 ? -exp10 : exp10); memcpy(o, eb, strlen(eb) + 1);
  }
}

/* parses a whole string as a double; accepts nan inf -inf for stringToFloat64 */
int floatParse(const char *s, size_t n, double *out) {
  char buf[512];
  if (n == 0 || n >= sizeof buf) return 0;
  memcpy(buf, s, n); buf[n] = 0;
  if (!strcmp(buf, "nan")) { *out = NAN; return 1; }
  if (!strcmp(buf, "inf")) { *out = INFINITY; return 1; }
  if (!strcmp(buf, "-inf")) { *out = -INFINITY; return 1; }
  char *end;
  double d = strtod(buf, &end);
  if (end != buf + n) return 0;
  for (size_t i = 0; i < n; i++) if ((buf[i] >= 'a' && buf[i] <= 'z' && buf[i] != 'e') || (buf[i] >= 'A' && buf[i] <= 'Z' && buf[i] != 'E')) return 0;
  *out = d;
  return 1;
}
