"""Minimal AgentS runtime for the Python backend.

Option and Result are tagged tuples rather than classes: they print readably in
test failures, compare structurally for free, and cost no import. The tag is the
same string the language uses, so a failing test shows AgentS vocabulary rather
than backend internals.
"""

NONE = ("none",)


def some(v): return ("some", v)
def ok(v): return ("ok", v)
def err(e): return ("err", e)
def pair(a, b): return ("pair", a, b)

def is_some(o): return o[0] == "some"
def is_ok(r): return r[0] == "ok"

def opt_or(o, d): return o[1] if o[0] == "some" else d
def res_or(r, d): return r[1] if r[0] == "ok" else d
def opt_map(f, o): return some(f(o[1])) if o[0] == "some" else NONE
def res_map(f, r): return ok(f(r[1])) if r[0] == "ok" else r
def res_map_err(f, r): return r if r[0] == "ok" else err(f(r[1]))
def opt_to_res(o, e): return ok(o[1]) if o[0] == "some" else err(e)
def res_to_opt(r): return some(r[1]) if r[0] == "ok" else NONE


class Trap(Exception):
    """A trapping arithmetic error. Distinct from a Result failure: traps are
    programmer errors the language declines to model as values."""


def div(a, b):
    if b == 0:
        raise Trap("division by zero")
    if isinstance(a, int) and isinstance(b, int):
        q = abs(a) // abs(b)
        return q if (a >= 0) == (b >= 0) else -q
    return a / b


def mod(a, b):
    if b == 0:
        raise Trap("modulo by zero")
    return a - div(a, b) * b


def checked_div(a, b): return NONE if b == 0 else some(div(a, b))
def checked_mod(a, b): return NONE if b == 0 else some(mod(a, b))
def eq(a, b): return a == b


def at(xs, i):
    return some(xs[i]) if 0 <= i < len(xs) else NONE


def tail(xs): return some(list(xs[1:])) if xs else NONE
def contains(xs, x): return x in xs
def index_of(xs, x): return some(xs.index(x)) if x in xs else NONE
def least(xs): return some(min(xs)) if xs else NONE
def greatest(xs): return some(max(xs)) if xs else NONE
def zip_(a, b): return [pair(x, y) for x, y in zip(a, b)]


def fold(f, init, xs):
    acc = init
    for x in xs:
        acc = f(acc, x)
    return acc


def str_slice(s, a, b):
    if 0 <= a <= b <= len(s):
        return some(s[a:b])
    return NONE


def list_slice(xs, a, b):
    if 0 <= a <= b <= len(xs):
        return some(list(xs[a:b]))
    return NONE


def str_index_of(s, sub):
    i = s.find(sub)
    return some(i) if i >= 0 else NONE


def to_int(s):
    try:
        return some(int(s.strip()))
    except ValueError:
        return NONE


def to_float(s):
    try:
        return some(float(s.strip()))
    except ValueError:
        return NONE


def to_i32(n): return some(n) if -2**31 <= n < 2**31 else NONE


def f_to_i(x):
    import math
    if math.isnan(x) or math.isinf(x):
        return NONE
    return some(int(x))


# Maps are immutable in the language, so every operation copies.
def m_get(m, k): return some(m[k]) if k in m else NONE
def m_set(m, k, v): return {**m, k: v}
def m_del(m, k): return {i: j for i, j in m.items() if i != k}
def m_pairs(m): return [pair(k, m[k]) for k in sorted(m)]
def m_from(ps): return {p[1]: p[2] for p in ps}


# ---------- I/O ----------
# The error case is chosen from errno, not from the exception class, because the
# Rust runtime has to reach the same case for the same condition and errno is the
# one vocabulary both hosts share. The differential gate compares them.

import os as _os
import sys as _sys

_ERRNO = {2: "not-found", 13: "permission-denied", 17: "already-exists",
          20: "invalid-path", 21: "invalid-path", 4: "interrupted"}

# rt::IoError's cases. `main`'s failure type is fixed on both targets, and this
# host has to reject what the Rust one rejects at compile time.
_IO_ERRORS = ("not-found", "permission-denied", "already-exists",
              "invalid-path", "interrupted", "other")


def _io_err(exc):
    return err((_ERRNO.get(getattr(exc, "errno", None), "other"),))


def read_line():
    try:
        line = _sys.stdin.readline()
    except OSError as exc:
        return _io_err(exc)
    return ok(NONE if line == "" else some(line.rstrip("\n")))


def read_all():
    try:
        return ok(_sys.stdin.read())
    except OSError as exc:
        return _io_err(exc)


def _write(stream, text):
    try:
        stream.write(text)
        stream.flush()
    except OSError as exc:
        return _io_err(exc)
    return ok(None)


def print_out(s): return _write(_sys.stdout, s)
def println(s): return _write(_sys.stdout, s + "\n")
def eprintln(s): return _write(_sys.stderr, s + "\n")


def file_read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return ok(fh.read())
    except OSError as exc:
        return _io_err(exc)


def _file_put(path, text, mode):
    try:
        with open(path, mode, encoding="utf-8") as fh:
            fh.write(text)
    except OSError as exc:
        return _io_err(exc)
    return ok(None)


def file_write(path, text): return _file_put(path, text, "w")
def file_append(path, text): return _file_put(path, text, "a")


def file_exists(path):
    try:
        return ok(_os.path.exists(path))
    except OSError as exc:
        return _io_err(exc)


def main_exit(result):
    """Host entry glue: a program's Result becomes its exit status. `err` prints
    the case name, which is the only part of a failure the language defines.

    The shape is checked, not assumed: rt::main_exit takes a Result<(), IoError>
    and rejects anything else at compile time, so accepting any value here would
    make the two backends disagree about which programs are valid — a `main`
    returning (Result Unit String) printed the first character of its error.
    """
    if not (isinstance(result, tuple) and len(result) == 2
            and result[0] in ("ok", "err")):
        raise TypeError(f"main must return a Result, got {result!r}")
    if result[0] == "ok":
        return 0
    case = result[1]
    if not (isinstance(case, tuple) and len(case) == 1 and case[0] in _IO_ERRORS):
        raise TypeError(f"main must fail with an IoError, got {case!r}")
    _sys.stderr.write(case[0] + "\n")
    return 1
