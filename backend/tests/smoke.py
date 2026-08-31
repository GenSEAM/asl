import runtime as _agentscript

def circle(radius):
    return ("circle", radius,)

def rectangle(width, height):
    return ("rectangle", width, height,)

def point():
    return ("point",)

def area(sh):
    _t1 = sh
    if _t1[0] == "circle":
        r = _t1[1]
        _t2 = _agentscript.mul(3.0, _agentscript.mul(r, r))
    elif _t1[0] == "rectangle":
        w = _t1[1]
        h = _t1[2]
        _t2 = _agentscript.mul(w, h)
    elif _t1[0] == "point":
        _t2 = 0.0
    return _t2

def classify(n):
    if (n < 0):
        _t3 = "negative"
    elif _agentscript.eq(n, 0):
        _t3 = "zero"
    else:
        _t3 = "positive"
    return _t3

def sum_list(xs):
    _t4 = xs
    if len(_t4) == 0:
        _t5 = 0
    elif len(_t4) > 0:
        h = _t4[0]
        t = list(_t4[1:])
        _t5 = _agentscript.add(h, sum_list(t))
    return _t5

def safe_div(a, b):
    return (_agentscript.err("division by zero") if _agentscript.eq(b, 0) else _agentscript.ok(_agentscript.div(a, b)))

def parse_double(s):
    _t6 = _agentscript.opt_to_res(_agentscript.to_int(s), "not a number")
    if _t6[0] == "err": return _t6
    n = _t6[1]
    return _agentscript.ok(_agentscript.mul(n, 2))

def describe(r):
    _t7 = r
    if _t7[0] == "ok":
        n = _t7[1]
        _t8 = str(n)
    elif _t7[0] == "err":
        msg = _t7[1]
        _t8 = msg
    return _t8

