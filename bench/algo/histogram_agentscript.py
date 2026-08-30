import runtime as _agentscript

def tally(m, w):
    _t1 = _agentscript.m_get(m, w)
    if _t1[0] == "some":
        n = _t1[1]
        _t2 = _agentscript.m_set(m, w, _agentscript.add(n, 1))
    elif _t1[0] == "none":
        _t2 = _agentscript.m_set(m, w, 1)
    return _t2

def histogram(text):
    words = [_x for _x in text.strip().split(" ") if (lambda w: (not (len(w) == 0)))(_x)]
    counts = _agentscript.fold(tally, {}, words)
    _t3 = _agentscript.greatest([counts[_k] for _k in sorted(counts)])
    if _t3[0] == "none":
        _t4 = {}
    elif _t3[0] == "some":
        top = _t3[1]
        _t4 = _agentscript.m_from([_x for _x in _agentscript.m_pairs(counts) if (lambda p: _agentscript.eq(p[2], top))(_x)])
    return _t4

