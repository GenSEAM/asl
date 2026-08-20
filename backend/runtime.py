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
