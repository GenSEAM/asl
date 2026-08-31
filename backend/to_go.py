#!/usr/bin/env python3
"""AgentScript -> Go.

Lowering rules come from prelude/prelude.json, as for every backend. This file
owns only the special forms and the type mapping.

Go is a statement language with no expression-position `if`/`match`, and it
does not infer a generic call's type arguments from its expected/return type
(the way Rust and TypeScript do), so every emitted value has to be typed
explicitly where it is consumed: temp variables for control flow, composite
literals, a nullary `None`/`ListOf`, a generic `Ok`/`Err`, a `map-empty`, and a
nullary generic enum constructor. That is why this transpiler carries a type
environment rather than letting the target infer it (plan D2/D3/D4).

A program's transitive imports are linked into this one output file, each name
prefixed by the module path that DEFINES it (the flat single-package
equivalent of Rust's nested `pub mod`): an alias is module-local, so keying on
it would give one definition as many names as its importers invent.
"""
import argparse
import json
import sys
from pathlib import Path

from lark import Tree, Token

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "grammar"))

from modules import closure, declared_path, imports  # noqa: E402
from parse import FORM_KW, parser  # noqa: E402

sys.path.insert(0, str(ROOT / "prelude"))

from vocab import parse_signature, unions  # noqa: E402

PRELUDE = json.loads((ROOT / "prelude" / "prelude.json").read_text())
LOWER = {b["name"]: b["go"] for b in PRELUDE["builtins"]}

PRIM = {"Bool": "bool", "Int32": "int32", "Int64": "int64", "Int": "int64",
        "Float64": "float64", "String": "string", "Unit": "Unit",
        "IoError": "IoError"}

GO_RESERVED = {
    "break", "case", "chan", "const", "continue", "default", "defer", "else",
    "fallthrough", "for", "func", "go", "goto", "if", "import", "interface",
    "map", "package", "range", "return", "select", "struct", "switch", "type",
    "var", "bool", "byte", "complex64", "complex128", "error", "float32",
    "float64", "int", "int8", "int16", "int32", "int64", "rune", "string",
    "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "true", "false",
    "iota", "nil", "append", "cap", "clear", "close", "complex", "copy",
    "delete", "imag", "len", "make", "max", "min", "new", "panic", "print",
    "println", "real", "recover", "any", "comparable", "main",
}


def mangle(n: str) -> str:
    if n.endswith("?"):
        n = "is-" + n[:-1]
    if n.endswith("!"):
        n = n[:-1] + "-mut"
    m = n.replace("-", "_")
    return m + "_" if m in GO_RESERVED else m


def pascal(n: str) -> str:
    return "".join(p.capitalize() for p in n.replace("_", "-").split("-"))


def go_mod(mod_path: str) -> str:
    return "_".join(mangle(seg) for seg in mod_path.split("/"))


def has_try(n) -> bool:
    if isinstance(n, Tree):
        return n.data == "try_form" or any(has_try(c) for c in n.children)
    return False


# ---------- types ----------
# Types are dicts: {"con": name, "args": [...]} / {"var": name} / {"fn": ...}.

def ty_var(name):
    return {"var": name}


def ty_con(name, args=None):
    return {"con": name, "args": args or []}


def render(t, env) -> str:
    if t is None:
        return "any"
    if isinstance(t, str):
        return t
    if "var" in t:
        n = t["var"]
        if n in env:
            if is_ty_var(env[n]) and env[n]["var"] == n:
                return n
            return render(env[n], env)
        return "any"
    if "fn" in t:
        params = ", ".join(render(p, env) for p in t["fn"]["params"])
        return f"func({params}) {render(t['fn']['ret'], env)}"
    name = t["con"]
    args = [render(a, env) for a in t["args"]]
    if name in PRIM:
        return PRIM[name]
    if name == "List":
        return f"[]{args[0]}" if args else "[]any"
    if name == "Option":
        return f"Option[{args[0]}]" if args else "Option[any]"
    if name == "Result":
        return f"Result[{args[0]}, {args[1]}]" if len(args) > 1 else "Result[any, any]"
    if name == "Pair":
        return f"Pair[{args[0]}, {args[1]}]" if len(args) > 1 else "Pair[any, any]"
    if name == "Map":
        return f"map[{args[0]}]{args[1]}" if len(args) > 1 else "map[any]any"
    if name == "IoError":
        return "IoError"
    return name + (f"[{', '.join(args)}]" if args else "")


def is_ty_var(t):
    return isinstance(t, dict) and "var" in t


def resolve(t, subs):
    seen = set()
    while is_ty_var(t) and t["var"] in subs:
        if t["var"] in seen:
            break
        seen.add(t["var"])
        t = subs[t["var"]]
    return t


def unify(a, b, subs):
    a, b = resolve(a, subs), resolve(b, subs)
    if is_ty_var(a) and is_ty_var(b) and a["var"] == b["var"]:
        return
    if is_ty_var(a):
        subs[a["var"]] = b
        return
    if is_ty_var(b):
        subs[b["var"]] = a
        return
    if "fn" in a or "fn" in b:
        if "fn" in a and "fn" in b:
            for x, y in zip(a["fn"]["params"], b["fn"]["params"]):
                unify(x, y, subs)
            unify(a["fn"]["ret"], b["fn"]["ret"], subs)
        return
    if ("con" in a) != ("con" in b) or a.get("con") != b.get("con") \
            or len(a.get("args", [])) != len(b.get("args", [])):
        raise RuntimeError(f"cannot unify {a} with {b}")
    for x, y in zip(a["args"], b["args"]):
        unify(x, y, subs)


def substitute(t, subs):
    if not isinstance(t, dict):
        return t
    t = resolve(t, subs)
    if is_ty_var(t):
        return t
    if "fn" in t:
        return {"fn": {"params": [substitute(p, subs) for p in t["fn"]["params"]],
                       "ret": substitute(t["fn"]["ret"], subs)}}
    return {"con": t["con"], "args": [substitute(a, subs) for a in t["args"]]}


# ---- builtin signature cache ----
def _sig_to_dict(spec):
    if "con" in spec:
        return {"con": spec["con"], "args": [_sig_to_dict(a) for a in spec["args"]]}
    if "var" in spec:
        return {"var": spec["var"]}
    if "fn" in spec:
        return {"fn": {"params": [_sig_to_dict(a) for a in spec["fn"]],
                       "ret": _sig_to_dict(spec["ret"])}}
    raise AssertionError(spec)


PRELUDE_BY_NAME = {b["name"]: b for b in PRELUDE["builtins"]}
COMPILED_SIG = {}
for _b in PRELUDE["builtins"]:
    _args, _var, _ret = parse_signature(_b["type"])
    COMPILED_SIG[_b["name"]] = ([_sig_to_dict(a) for a in _args], _var, _sig_to_dict(_ret))


class ToGo:
    def __init__(self):
        self.parser = parser()
        self.enums: dict[str, tuple[str, list[str], list[dict]]] = {}
        for cases in unions().values():
            for case in cases:
                self.enums[case] = ("IoError", [], [])
        self.schema_params: dict[str, list[str]] = {}
        self.schema_fields: dict[str, dict[str, dict]] = {}
        self.schema_boxed: dict[str, set[str]] = {}
        self.prefix = ""
        self.local: dict[str, str] = {}
        self.alias_prefix: dict[str, str] = {}
        self.scope: list[set[str]] = []
        self.tstack: list[dict[str, dict]] = []
        self.genv: dict[str, dict] = {}
        self.fun_sigs: dict[str, tuple] = {}
        self.tmp = 0

    def fresh(self):
        self.tmp += 1
        return f"t{self.tmp}"

    @staticmethod
    def kids(n):
        return [k for k in n.children if not (isinstance(k, Token) and k.type in FORM_KW)]

    @staticmethod
    def tok(n):
        return str(n) if isinstance(n, Token) else str(n.children[0])

    @staticmethod
    def type_param_names(n) -> list[str]:
        for k in n.children:
            if isinstance(k, Tree) and k.data == "type_params":
                return [str(t) for t in k.children]
        return []

    def push_scope(self, names=()):
        self.scope.append(set(names))

    def pop_scope(self):
        self.scope.pop()

    def bound(self, name) -> bool:
        return any(name in frame for frame in self.scope)

    def resolve(self, name: str) -> str:
        if self.bound(name):
            return mangle(name)
        return self.local.get(name, mangle(name))

    def qual(self, text: str) -> str:
        alias, _, member = text.partition("/")
        return self.alias_prefix.get(alias, "") + mangle(member)

    def qual_type(self, text: str) -> str:
        alias, _, member = text.partition("/")
        return self.alias_prefix.get(alias, "") + member

    def local_type(self, name: str) -> str:
        if name in self.local:
            return self.local[name]
        return name

    def tvar_lookup(self, name):
        for frame in reversed(self.tstack):
            if name in frame:
                return frame[name]
        return None

    def used_in(self, name, *nodes) -> bool:
        for node in nodes:
            if node is None:
                continue
            for tk in node.scan_values(lambda v: isinstance(v, Token)):
                if isinstance(tk, Token) and str(tk) == name and tk.type == "IDENT":
                    return True
        return False

    # ---------- node_type ----------

    def node_type(self, node) -> dict:
        if isinstance(node, Tree) and node.data == "type":
            node = node.children[0] if len(node.children) == 1 else node
        if isinstance(node, Token):
            s = str(node)
            if getattr(node, "type", None) == "QUALIFIED_TYPE":
                return ty_con(self.qual_type(s))
            if s in PRIM:
                return ty_con(s)
            if s in self.genv:
                return ty_var(s)
            return ty_con(self.local_type(s))
        head_tok = self.tok(node.children[0])
        is_qual = (isinstance(node.children[0], Token)
                   and node.children[0].type == "QUALIFIED_TYPE")
        if is_qual:
            head = self.qual_type(head_tok)
        elif head_tok in self.genv:
            return ty_var(head_tok)
        else:
            head = self.local_type(head_tok)
        args = [self.node_type(a) for a in node.children[1:]]
        return ty_con(head, args)

    # ---------- entry ----------

    def transpile(self, src: str, *, path=None, roots=()):
        tree = self.parser.parse(src)
        entry = self.host_entry(tree)
        out = ["package main"]
        if entry:
            out.append('import "os"')
        for mod_path, unit, prefix in self.link(tree, path, roots):
            self.enter(unit, prefix)
            out += self.unit(unit)
        if entry:
            out += entry
        return "\n".join(out) + "\n"

    def link(self, tree, path, roots):
        search = [*([Path(path).parent] if path is not None else []),
                  *(Path(r) for r in roots)]
        deps = closure(tree, search) if search else []
        seen = {}
        for mod_path, _ in deps:
            key = go_mod(mod_path)
            if seen.setdefault(key, mod_path) != mod_path:
                raise ValueError(f"module paths {seen[key]} and {mod_path} mangle alike")
        return ([(m, t, go_mod(m) + "_") for m, t in deps]
                + [(declared_path(tree) or "", tree, "")])

    def enter(self, tree, prefix):
        self.prefix = prefix
        self.alias_prefix = {a: go_mod(m) + "_" for a, m in imports(tree).items()}
        self.local = self.unit_names(tree, prefix)
        self.fun_sigs.update(self.collect_sigs(tree))
        self.unit_enums(tree)
        self.scope = []

    def unit_names(self, tree, prefix) -> dict:
        names = {}
        for top in tree.children:
            node = top.children[0]
            if node.data == "defun":
                names[self.decl_name(node)] = prefix + mangle(self.decl_name(node))
            elif node.data == "defschema":
                nm = self.decl_name(node)
                names[nm] = prefix + nm
                self.schema_params[prefix + nm] = self.type_param_names(node)
            elif node.data == "defenum":
                names[self.decl_name(node)] = prefix + self.decl_name(node)
                for c in node.children:
                    if isinstance(c, Tree) and c.data == "enum_case":
                        case = self.tok(self.kids(c)[0])
                        names[case] = prefix + pascal(case)
        return names

    def decl_name(self, node) -> str:
        kids = [k for k in self.kids(node)
                if not (isinstance(k, Tree) and k.data in ("type_params", "doc_opt"))]
        return self.tok(kids[0])

    def collect_sigs(self, tree):
        funs = {}
        for top in tree.children:
            node = top.children[0]
            if node.data != "defun":
                continue
            tps = self.type_param_names(node)
            k = [x for x in self.kids(node)
                 if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt"))]
            emitted = self.prefix + mangle(self.tok(k[0]))
            ps = [p for p in k[1].children if isinstance(p, Tree) and p.data == "param"]
            self.genv = {tp: ty_var(tp) for tp in tps}
            params = [self.node_type(self.kids(p)[1]) for p in ps]
            ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
            ret = self.node_type(k[ti])
            funs[emitted] = (tps, params, ret)
        self.genv = {}
        return funs

    def unit_enums(self, tree):
        for top in tree.children:
            node = top.children[0]
            if node.data != "defenum":
                continue
            tps = self.type_param_names(node)
            emitted = self.local_type(self.decl_name(node))
            for c in node.children:
                if not (isinstance(c, Tree) and c.data == "enum_case"):
                    continue
                case = self.tok(self.kids(c)[0])
                ps = [p for p in c.children if isinstance(p, Tree) and p.data == "param"]
                self.genv = {tp: ty_var(tp) for tp in tps}
                tys = [self.node_type(self.kids(p)[1]) for p in ps]
                self.enums[case] = (emitted, tps, tys)
        self.genv = {}

    def unit(self, tree):
        out = []
        for top in tree.children:
            node = top.children[0]
            if node.data == "defenum":
                out += self.defenum(node)
        for top in tree.children:
            node = top.children[0]
            if node.data == "defschema":
                self.defschema(node, out)
        for top in tree.children:
            node = top.children[0]
            if node.data == "defun":
                out += self.defun(node)
        return out

    def host_entry(self, tree):
        for top in tree.children:
            node = top.children[0]
            if node.data != "defun":
                continue
            k = [x for x in self.kids(node)
                 if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt"))]
            if str(k[0]) == "main":
                return ["", "func main() {",
                        "    os.Exit(MainExit(main_(os.Args[1:])))",
                        "}"]
        return []

    # ---------- declarations ----------

    def generics(self, tps):
        return "[" + ", ".join(tp + " any" for tp in tps) + "]" if tps else ""

    def type_args(self, tps):
        return "[" + ", ".join(tps) + "]" if tps else ""

    def mentions_name(self, node, name) -> bool:
        for s in node.scan_values(lambda tk: isinstance(tk, Token) and tk.type == "TYPE_NAME"):
            if str(s) == name:
                return True
        return False

    def defschema(self, n, out):
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        tps = self.type_param_names(n)
        emitted = self.local_type(name)
        fields = [f for f in n.children if isinstance(f, Tree) and f.data == "field"]
        boxed = set()
        field_tys = {}
        self.genv = {tp: ty_var(tp) for tp in tps}
        lines = [f"type {emitted}{self.generics(tps)} struct {{"]
        for f in fields:
            fk = self.kids(f)
            fn = mangle(self.tok(fk[0]))
            n_t = self.node_type(fk[1])
            field_tys[fn] = n_t
            if self.mentions_name(fk[1], name):
                boxed.add(fn)
                lines.append(f"    {fn} *{render(n_t, self.genv)}")
            else:
                lines.append(f"    {fn} {render(n_t, self.genv)}")
        self.genv = {}
        self.schema_fields[emitted] = field_tys
        self.schema_boxed[emitted] = boxed
        out += lines + ["}", ""]

    def defenum(self, n):
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        name = self.tok(k[0])
        tps = self.type_param_names(n)
        emitted = self.local_type(name)
        gt = self.generics(tps)
        t_args = self.type_args(tps)
        lines = [f"type {emitted}{gt} struct {{",
                 "    Tag  string",
                 "    Args []any",
                 "}", ""]
        for c in n.children:
            if not (isinstance(c, Tree) and c.data == "enum_case"):
                continue
            case = self.tok(self.kids(c)[0])
            ps = [p for p in c.children if isinstance(p, Tree) and p.data == "param"]
            self.genv = {tp: ty_var(tp) for tp in tps}
            tys = [self.node_type(self.kids(p)[1]) for p in ps]
            self.genv = {}
            ctor = self.local[case]
            params = ", ".join(f"a{i} {render(t, {tp: ty_var(tp) for tp in tps})}"
                               for i, t in enumerate(tys))
            args = ", ".join(f"a{i}" for i in range(len(tys)))
            ret = f"{emitted}{t_args}"
            lines.append(f"func {ctor}{gt}({params}) {ret} {{")
            if tys:
                lines.append(
                    f"    return {emitted}{t_args}{{Tag: \"{case}\", Args: []any{{{args}}}}}")
            else:
                lines.append(f"    return {emitted}{t_args}{{Tag: \"{case}\"}}")
            lines.append("}")
            lines.append("")
        return lines

    def defun(self, n):
        k = [x for x in self.kids(n)
             if not (isinstance(x, Tree) and x.data in ("type_params", "doc_opt"))]
        name = mangle(self.tok(k[0]))
        tps = self.type_param_names(n)
        ps = [p for p in k[1].children if isinstance(p, Tree) and p.data == "param"]
        ti = next(i for i, x in enumerate(k) if isinstance(x, Tree) and x.data == "type")
        ret = self.node_type(k[ti])
        emitted = self.prefix + name
        self.genv = {tp: ty_var(tp) for tp in tps}
        self.push_scope([self.tok(self.kids(p)[0]) for p in ps])
        self.tstack.append({mangle(self.tok(self.kids(p)[0])): self.node_type(self.kids(p)[1])
                            for p in ps})
        args = ", ".join(
            f"{mangle(self.tok(self.kids(p)[0]))} {render(self.node_type(self.kids(p)[1]), self.genv)}"
            for p in ps)
        retgo = render(ret, self.genv)
        guarded = has_try(n)
        body = k[ti + 1:]
        if guarded:
            ego = render(ret["args"][1], self.genv) if ret.get("con") == "Result" else "any"
            tgo = render(ret["args"][0], self.genv) if ret.get("con") == "Result" else "any"
            lines = [f"func {emitted}{self.generics(tps)}({args}) (ret {retgo}) {{",
                     "    defer func() {",
                     "        if r := recover(); r != nil {",
                     "            if t, ok := r.(Thrown); ok {",
                     f"                ret = Err[{tgo}, {ego}](t.Value.({ego}))",
                     "                return",
                     "            }",
                     "            panic(r)",
                     "        }",
                     "    }()"]
            lines += self.block(body, 1, ret)
            lines += ["}", ""]
        else:
            lines = [f"func {emitted}{self.generics(tps)}({args}) {retgo} {{"]
            lines += self.block(body, 1, ret)
            lines += ["}", ""]
        self.tstack.pop()
        self.pop_scope()
        self.genv = {}
        return lines

    # ---------- statements ----------

    def block(self, exprs, ind, expected=None):
        pad = "    " * ind
        lines = []
        for e in exprs[:-1]:
            code = self.expr(e, lines, ind, None)
            lines.append(f"{pad}_ = {code};")
        if exprs:
            code = self.expr(exprs[-1], lines, ind, expected)
            lines.append(f"{pad}return {code};")
        else:
            lines.append(f"{pad}return Unit{{}};")
        return lines

    def sequence(self, body, stmts, ind, expected):
        pad = "    " * ind
        for e in body[:-1]:
            code = self.expr(e, stmts, ind, None)
            stmts.append(f"{pad}_ = {code};")
        return self.expr(body[-1], stmts, ind, expected) if body else "Unit{}"

    # ---------- expressions ----------

    def expr(self, n, stmts, ind, expected):
        if isinstance(n, Tree) and n.data in ("expr", "literal"):
            return self.expr(n.children[0], stmts, ind, expected)
        if isinstance(n, Token):
            return self.atom(n, expected)
        if n.data == "let_form":
            return self.let_form(n, stmts, ind, expected)
        if n.data == "if_form":
            return self.if_form(n, stmts, ind, expected)
        if n.data == "cond_form":
            return self.cond_form(n, stmts, ind, expected)
        if n.data == "match_form":
            return self.match_form(n, stmts, ind, expected)
        if n.data == "try_form":
            return f"Unwrap({self.expr(self.kids(n)[0], stmts, ind, None)})"
        if n.data == "fn_form":
            return self.fn_form(n, stmts, ind, expected)
        if n.data == "field_access":
            return self.field_access(n, stmts, ind)
        if n.data == "ctor":
            return self.ctor(n, stmts, ind, expected)
        if n.data == "call":
            return self.call(n, stmts, ind, expected)
        raise NotImplementedError(f"form not lowered to Go: {n.data}")

    def let_form(self, n, stmts, ind, expected=None):
        pad = "    " * ind
        bindings = [b for b in self.kids(n) if isinstance(b, Tree) and b.data == "binding"]
        body = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "binding")]
        self.push_scope()
        self.tstack.append({})
        for idx, b in enumerate(bindings):
            bk = self.kids(b)
            nm = self.tok(bk[0])
            vtype = self.infer(bk[1])
            code = self.expr(bk[1], stmts, ind, vtype)
            self.tstack[-1][mangle(nm)] = vtype
            self.scope[-1].add(nm)
            rem = bindings[idx + 1:] + body
            if self.used_in(nm, *rem):
                stmts.append(f"{pad}{mangle(nm)} := {code};")
            else:
                stmts.append(f"{pad}_ = {code};")
        value = self.sequence(body, stmts, ind, expected) if body else "Unit{}"
        self.tstack.pop()
        self.pop_scope()
        return value

    def if_form(self, n, stmts, ind, expected):
        c, a, b = self.kids(n)
        cv = self.expr(c, stmts, ind, None)
        res_t = expected if expected is not None else self.infer(a)
        pad = "    " * ind
        sa, sb = [], []
        va = self.expr(a, sa, ind + 1, res_t)
        vb = self.expr(b, sb, ind + 1, res_t)
        # A value otherwise unused needs a temp Go can report as used.
        t = self.fresh()
        stmts.append(f"{pad}var {t} {render(res_t, self.genv)}")
        stmts.append(f"{pad}if {cv} {{")
        stmts += [("    " + x) for x in sa] + [f"{pad}    {t} = {va}"]
        stmts.append(f"{pad}}} else {{")
        stmts += [("    " + x) for x in sb] + [f"{pad}    {t} = {vb}"]
        stmts.append(f"{pad}}}")
        return t

    def cond_form(self, n, stmts, ind, expected):
        clauses = [c for c in self.kids(n) if isinstance(c, Tree)]
        res_t = expected if expected is not None else self.infer(clauses[-1])
        pad = "    " * ind
        t = self.fresh()
        stmts.append(f"{pad}var {t} {render(res_t, self.genv)}")
        blocks = []
        for cl in clauses:
            ck = self.kids(cl)
            if cl.data == "cond_clause":
                cv = self.expr(ck[0], stmts, ind, None)
                inner = []
                v = self.sequence(ck[1:], inner, ind + 1, res_t)
                blocks.append((cv, inner, v))
            else:
                inner = []
                v = self.sequence(ck, inner, ind + 1, res_t)
                blocks.append((None, inner, v))
        for i, (cond, inner, v) in enumerate(blocks):
            if i == 0:
                header = f"{pad}if {cond} {{" if cond else f"{pad}{{"
            else:
                header = f"{pad}}} else if {cond} {{" if cond else f"{pad}}} else {{"
            stmts.append(header)
            stmts += [("    " + x) for x in inner] + [f"{pad}    {t} = {v}"]
        stmts.append(f"{pad}}}")
        return t

    # ---------- match ----------

    def match_form(self, n, stmts, ind, expected):
        mk = self.kids(n)
        raw_subj_code = self.expr(mk[0], stmts, ind, None)
        subj_t = self.infer(mk[0])
        pad = "    " * ind
        subj_var = self.fresh()
        stmts.append(f"{pad}{subj_var} := {raw_subj_code};")
        subj_code = subj_var
        arms = [a for a in mk[1:] if isinstance(a, Tree) and a.data == "match_arm"]
        res_t = expected if expected is not None else self.infer(arms[-1])
        t = self.fresh()
        stmts.append(f"{pad}var {t} {render(res_t, self.genv)}")
        if any(self._pat_head(self.unwrap_pat(self.kids(a)[0])) in ("cons", "list")
               for a in arms):
            return self.finish_list_match(n, arms, subj_code, subj_t, res_t, t, stmts, ind)
        if all(self.enum_case_look(self.unwrap_pat(self.kids(a)[0])) is not None for a in arms):
            return self.finish_switch_match(n, arms, subj_code, subj_t, res_t, t, stmts, ind)
        # ok/err/some/none/pair and nested-case arms: an if/else chain.
        blocks = []
        for arm in arms:
            ak = self.kids(arm)
            cond, binds = self.condition(ak[0], subj_code, subj_t)
            body_nodes = ak[1:]
            self.push_scope(list(binds.keys()))
            self.tstack.append({mangle(nm): bt for nm, (bcode, bt) in binds.items()})
            inner = []
            v = self.sequence(body_nodes, inner, ind + 1, res_t)
            self.tstack.pop()
            self.pop_scope()
            blocks.append((cond, binds, body_nodes, inner, v))
        for i, (cond, binds, body_nodes, inner, v) in enumerate(blocks):
            if i == 0:
                stmts.append(f"{pad}if {cond} {{" if cond else f"{pad}{{")
            else:
                stmts.append(f"{pad}}} else {'if ' + str(cond) + ' {' if cond else '{'}")
            for nm in binds:
                bind_expr, bind_ty = binds[nm]
                if self.used_in(nm, *body_nodes):
                    stmts.append(f"{'    ' * (ind + 1)}{mangle(nm)} := {bind_expr};")
                else:
                    stmts.append(f"{'    ' * (ind + 1)}_ = {bind_expr};")
            stmts += [("    " + x) for x in inner] + [f"{pad}    {t} = {v}"]
        stmts.append(f"{pad}}}")
        return t

    def finish_switch_match(self, n, arms, subj_code, subj_t, res_t, t, stmts, ind):
        pad = "    " * ind
        stmts.append(f"{pad}switch {subj_code}.Tag {{")
        body_pad = "    " * (ind + 1)
        for arm in arms:
            ak = self.kids(arm)
            pat = self.unwrap_pat(self.kids(arm)[0])
            head = self._pat_head(pat)
            bare = head.partition("/")[2] if "/" in head else head
            en, tps, tys = self.enums[bare]
            # Each arm's payload types are the enum's declaration with its type
            # params substituted by the subject's own instantiation.
            subs = {}
            if subj_t is not None and subj_t.get("con") == en and len(subj_t.get("args", [])) == 0 \
                    and not tps:
                pass
            elif subj_t is not None and subj_t.get("con") == en:
                for i, tp in enumerate(tps):
                    if i < len(subj_t.get("args", [])):
                        subs[tp] = subj_t["args"][i]
            stmts.append(f"{pad}case \"{bare}\":")
            body_nodes = ak[1:]
            bind_names = []
            for i, (sp, ty) in enumerate(zip(self._sub_pats(pat), tys)):
                leaf = self._pat_leaf(sp)
                if leaf is None or leaf == "_":
                    continue
                st = substitute(ty, subs)
                rendered_st = render(st, self.genv)
                if self.used_in(leaf, *body_nodes):
                    stmts.append(f"{body_pad}{mangle(leaf)} := {subj_code}.Args[{i}].({rendered_st})")
                else:
                    stmts.append(f"{body_pad}_ = {subj_code}.Args[{i}].({rendered_st})")
                bind_names.append((leaf, st))
            self.push_scope([x for x, _ in bind_names])
            self.tstack.append({mangle(k): v for k, v in bind_names})
            inner = []
            v = self.sequence(body_nodes, inner, ind + 1, res_t)
            self.tstack.pop()
            self.pop_scope()
            stmts += [("    " + x) for x in inner] + [f"{body_pad}{t} = {v}"]
        stmts.append(f"{pad}}}")
        return t

    def finish_list_match(self, n, arms, subj_code, subj_t, res_t, t, stmts, ind):
        pad = "    " * ind
        elem_t = subj_t["args"][0] if subj_t is not None and subj_t.get("con") == "List" \
            else ty_con("any")
        first = True
        blocks = []
        for arm in arms:
            ak = self.kids(arm)
            pat = self.unwrap_pat(self.kids(arm)[0])
            cond_parts, binds = self.slice_pattern(pat, subj_code, elem_t)
            body_nodes = ak[1:]
            self.push_scope(list(binds.keys()))
            self.tstack.append({mangle(x): bt for x, (bcode, bt) in binds.items()})
            inner = []
            v = self.sequence(body_nodes, inner, ind + 1, res_t)
            self.tstack.pop()
            self.pop_scope()
            blocks.append((cond_parts, binds, body_nodes, inner, v))
        for i, (cond_parts, binds, body_nodes, inner, v) in enumerate(blocks):
            if i == 0:
                stmts.append(f"{pad}if {cond_parts} {{" if cond_parts else f"{pad}{{")
            else:
                stmts.append(f"{pad}}} else {'if ' + str(cond_parts) + ' {' if cond_parts else '{'}")
            for x, (bcode, bt) in binds.items():
                if self.used_in(x, *body_nodes):
                    stmts.append(f"{'    ' * (ind + 1)}{mangle(x)} := {bcode};")
                else:
                    stmts.append(f"{'    ' * (ind + 1)}_ = {bcode};")
            stmts += [("    " + x) for x in inner] + [f"{'    ' * (ind + 1)}{t} = {v}"]
        stmts.append(f"{pad}}}")
        return t

    def slice_pattern(self, pat, subj, elem_t):
        """A cons/list pattern to a Go condition and binder defs on the slice."""
        head = self._pat_head(pat)
        if head == "list":
            return f"len({subj}) == 0", {}
        node = pat
        heads = []
        tail = None
        i = 0
        while True:
            mk = self.unwrap_pat(node)
            nh = self._pat_head(mk)
            if nh == "cons":
                h = self._pat_leaf(mk.children[1])
                heads.append(h)
                node = self.unwrap_pat(mk.children[2])
                i += 1
            elif nh == "list":
                # exact-length list: heads bound, but no tail binder
                binds = {}
                for j, h in enumerate(heads):
                    if h is not None and h != "_":
                        binds[h] = (f"{subj}[{j}]", elem_t)
                return f"len({subj}) == {i}", binds
            else:
                tail = self._pat_leaf(node)
                break
        conds = [f"len({subj}) >= {i}"]
        binds = {}
        for j, h in enumerate(heads):
            if h is not None and h != "_":
                binds[h] = (f"{subj}[{j}]", elem_t)
        if tail is not None and tail != "_":
            binds[tail] = (f"{subj}[{i}:]", ty_con("List", [elem_t]))
        return " && ".join(conds), binds

    def condition(self, pat, subj, subj_t):
        """(condition, binds: name -> (bind_expr, type)) for a non-list arm."""
        pat = self.unwrap_pat(pat)
        toks = pat.children if isinstance(pat, Tree) else []
        head = self._pat_head(pat)
        if head is not None and "/" in head:
            head = head.partition("/")[2]

        def payload_field():
            pass

        if head in ("ok", "err"):
            cond = subj + ".IsOk" if head == "ok" else f"!{subj}.IsOk"
            val = subj + ".Value" if head == "ok" else subj + ".Err"
            pt = None
            if subj_t is not None and subj_t.get("con") == "Result":
                pt = subj_t["args"][0] if head == "ok" else subj_t["args"][1]
            return self._payload_arm(toks, val, cond, pt)
        if head == "some":
            cond = subj + ".Present"
            pt = subj_t["args"][0] if subj_t is not None and subj_t.get("con") == "Option" \
                else ty_con("any")
            return self._payload_arm(toks, subj + ".Value", cond, pt)
        if head == "none":
            return f"!{subj}.Present", {}
        if head == "pair":
            a, b = toks[1], toks[2]
            pa = subj_t["args"][0] if subj_t is not None and subj_t.get("con") == "Pair" \
                else ty_con("any")
            pb = subj_t["args"][1] if subj_t is not None and subj_t.get("con") == "Pair" \
                else ty_con("any")
            c1, b1 = self.condition(a, subj + ".First", pa)
            c2, b2 = self.condition(b, subj + ".Second", pb)
            conds = [x for x in [c1, c2] if x] or ["true"]
            return " && ".join(conds), {**b1, **b2}
        if head in self.enums and self._is_case_applied(pat):
            en, tps, tys = self.enums[head]
            cond = f'{subj}.Tag == "{head}"'
            binds = {}
            for i, sp in enumerate(self._sub_pats(pat)):
                leaf = self._pat_leaf(sp)
                if leaf is not None and leaf != "_":
                    ty = tys[i] if i < len(tys) else ty_con("any")
                    binds[leaf] = (f"{subj}.Args[{i}].({render(ty, self.genv)})", ty)
            return cond, binds
        if isinstance(pat, Tree) and pat.data == "literal":
            val = self.expr(pat, [], 0, subj_t)
            return f"Eq({subj}, {val})", {}
        if isinstance(pat, Token) and pat.type in ("INT", "FLOAT", "STRING", "BOOL"):
            val = self.atom(pat)
            return f"Eq({subj}, {val})", {}
        # bare binder, wildcard, or a bare case-less name
        leaf = self._pat_leaf(pat)
        if leaf is None or leaf == "_":
            return None, {}
        return None, {leaf: (subj, subj_t or ty_con("any"))}

    def _payload_arm(self, toks, val, cond, pt):
        if len(toks) > 1 and isinstance(toks[1], Tree):
            sub = self.unwrap_pat(toks[1])
            shead = self._pat_head(sub)
            bhead = shead.partition("/")[2] if shead and "/" in shead else shead
            if bhead in self.enums and self._is_case_applied(sub):
                c, b = self.condition(sub, val, pt)
                return f"{cond} && {c}", b
        leaf = self._pat_leaf(toks[1]) if len(toks) > 1 else None
        if leaf is None or leaf == "_":
            return cond, {}
        return cond, {leaf: (val, pt or ty_con("any"))}

    def enum_case_look(self, pat):
        head = self._pat_head(pat)
        if head is None:
            return None
        bare = head.partition("/")[2] if "/" in head else head
        if bare in self.enums and self._is_case_applied(pat):
            return self.enums[bare]
        return None

    def _sub_pats(self, pat):
        return [p for p in pat.children[1:] if isinstance(p, Tree)]

    @staticmethod
    def unwrap_pat(pat):
        while isinstance(pat, Tree) and pat.data in ("pattern", "enum_pattern", "literal") \
                and len(pat.children) == 1 and isinstance(pat.children[0], Tree):
            pat = pat.children[0]
        return pat

    @staticmethod
    def _pat_head(pat):
        toks = pat.children if isinstance(pat, Tree) else []
        return str(toks[0]) if toks and isinstance(toks[0], Token) else None

    @staticmethod
    def _is_case_applied(p):
        return isinstance(p, Tree) and p.data == "enum_pattern"

    def _pat_leaf(self, p):
        while isinstance(p, Tree) and len(p.children) == 1:
            p = p.children[0]
        if isinstance(p, Token) and p.type not in ("INT", "FLOAT", "STRING", "BOOL", "WILDCARD"):
            return str(p)
        return None

    # ---------- fn / access / ctor / call ----------

    def fn_form(self, n, stmts, ind, expected):
        if has_try(n):
            raise NotImplementedError("`try` inside `fn` is not lowered to Go: the deferred "
                                      "recover would attach to an unrelated frame")
        k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
        params_node = k[0]
        fns = [p for p in params_node.children if isinstance(p, Tree) and p.data == "fn_param"]
        exp_params, exp_ret = None, None
        if expected is not None and "fn" in expected:
            exp_params = expected["fn"]["params"]
            exp_ret = expected["fn"]["ret"]
        items, names, typs = [], [], []
        for i, p in enumerate(fns):
            pk = self.kids(p)
            name = str(pk[0])
            names.append(name)
            if len(pk) > 1 and isinstance(pk[1], Tree) and pk[1].data == "type":
                t = self.node_type(pk[1])
            elif exp_params and i < len(exp_params):
                t = exp_params[i]
            else:
                t = ty_con("any")
            if is_ty_var(t):
                t = ty_con("any")
            typs.append(t)
            items.append(f"{mangle(name)} {render(t, self.genv)}")
        ret = None
        body_start = 1
        for i, x in enumerate(k[1:], start=1):
            if isinstance(x, Tree) and x.data == "type":
                ret = self.node_type(x)
                body_start = i + 1
                break
        pad = "    " * ind
        self.push_scope(names)
        self.tstack.append({mangle(x): t for x, t in zip(names, typs)})
        # Return type: an explicit annotation wins; otherwise infer it from the
        # body (which resolves a fresh parameter-less return variable), falling
        # back to the caller's expected return only when both are concrete.
        if ret is None:
            body_exprs = [e for e in k[body_start:] if isinstance(e, Tree)]
            if body_exprs:
                body_t = self.infer(body_exprs[-1])
                if isinstance(body_t, dict) and "con" in body_t:
                    ret = body_t
        ret_str = render(ret, self.genv) if ret is not None else None
        if (ret_str is None or ret_str == "any") and exp_ret is not None \
                and isinstance(exp_ret, dict) and "con" in exp_ret:
            ret = exp_ret
            ret_str = render(exp_ret, self.genv)
        if ret_str is None:
            ret_str = "any"
        body = self.fn_block(k[body_start:], ind + 1, ret)
        self.tstack.pop()
        self.pop_scope()
        return f"func({', '.join(items)}) {ret_str} {{\n" + "\n".join(body) + f"\n{pad}}}"

    def fn_block(self, exprs, ind, expected=None):
        pad = "    " * ind
        lines = []
        for e in exprs[:-1]:
            code = self.expr(e, lines, ind, None)
            lines.append(f"{pad}_ = {code};")
        if exprs:
            code = self.expr(exprs[-1], lines, ind, expected)
            lines.append(f"{pad}return {code};")
        else:
            lines.append(f"{pad}return Unit{{}};")
        return lines

    def field_access(self, n, stmts, ind):
        fld = self.tok(n.children[0])[2:]
        subject = n.children[1]
        subj_code = self.expr(subject, stmts, ind, None)
        st = self.infer(subject)
        emitted = st.get("con") if isinstance(st, dict) and "con" in st else None
        # rt's Pair exposes capitalised First/Second; record fields are mangled.
        if emitted == "Pair":
            selector = "First" if fld == "first" else "Second"
        else:
            selector = mangle(fld)
        code = f"({subj_code}).{selector}"
        if emitted and fld in self.schema_boxed.get(emitted, set()):
            code = f"(*{code})"
        return code

    def ctor(self, n, stmts, ind, expected):
        head = n.children[0]
        if isinstance(head, Token) and head.type == "QUALIFIED_TYPE":
            name = self.qual_type(str(head))
        else:
            name = self.resolve(str(head))
        field_tys = self.schema_fields.get(name, {})
        given_codes = {}
        given_ts = {}
        for a in n.children[1:]:
            if isinstance(a, Tree) and a.data == "ctor_arg":
                fld = self.tok(a.children[0])[1:]
                ft = field_tys.get(fld)
                given_codes[fld] = self.expr(a.children[1], stmts, ind, ft)
                given_ts[fld] = self.infer(a.children[1])
        tps = self.schema_params.get(name, [])
        subs = {}
        for fld, ft in field_tys.items():
            if fld in given_ts:
                try:
                    unify(ft, given_ts[fld], subs)
                except RuntimeError:
                    pass
        inst = ""
        if tps:
            parts = [render(resolve(ty_var(tp), subs), self.genv) if tp in subs else "any"
                     for tp in tps]
            inst = "[" + ", ".join(parts) + "]"
        boxed = self.schema_boxed.get(name, set())
        # Addressability: Go cannot take the address of a function call, so a
        # boxed (self-referential) field's value is hoisted to a temp.
        tmp_names = {}
        pad = "    " * ind
        for fld in given_codes:
            if fld in boxed:
                t = self.fresh()
                stmts.append(f"{pad}{t} := {given_codes[fld]};")
                tmp_names[fld] = t
        fields = []
        order = list(field_tys.keys()) if field_tys else list(given_codes.keys())
        for f in order:
            if f not in given_codes:
                continue
            val = given_codes[f]
            if f in boxed:
                val = f"(&{tmp_names[f]})"
            fields.append(f"{mangle(f)}: {val}")
        return f"{name}{inst}{{{', '.join(fields)}}}"

    def call(self, n, stmts, ind, expected):
        head = n.children[0]
        if isinstance(head, Tree):
            head = head.children[0]
        name = str(head)
        args = n.children[1:]
        # compute each argument's expected type from the callee signature
        arg_exp = self.arg_expected(head, args)
        arg_codes = [self.expr(a, stmts, ind, ae)
                     for a, ae in zip(args, arg_exp)]
        # Builtins are keyed by their raw name (the bare `/` division operator
        # is itself a key and must not be read as a qualified-name separator).
        if name in LOWER:
            if name == "list":
                return self.list_call(args, arg_codes, expected)
            return self.low_call(name, arg_codes, expected, n)
        if "/" in name:
            _, _, member = name.partition("/")
            if member in self.enums:
                alias, _, _ = name.partition("/")
                return f"{self.alias_prefix.get(alias, '') + pascal(member)}({', '.join(arg_codes)})"
            return f"{self.qual(name)}({', '.join(arg_codes)})"
        # enum-case constructor (a case name used as a function)
        if not self.bound(name) and name in self.enums and name in self.local:
            ctor = self.local[name]
            en, tps, _ = self.enums[name]
            inst = self.enum_inst_from_expected(expected, tps) if tps else ""
            return f"{ctor}{inst}({', '.join(arg_codes)})"
        if name in self.local:
            return f"{self.local[name]}({', '.join(arg_codes)})"
        return f"{mangle(name)}({', '.join(arg_codes)})"

    def list_call(self, args, arg_codes, expected):
        elem = self.list_elem(expected)
        if elem is None and args:
            elem = self.infer(args[0])
            if is_ty_var(elem):
                elem = None
        if elem is None or render(elem, self.genv) == "any":
            if arg_codes:
                first_t = self.infer(args[0]) if args else None
                if first_t and not is_ty_var(first_t):
                    return f"ListOf[{render(first_t, self.genv)}]({', '.join(arg_codes)})"
                return f"ListOf({', '.join(arg_codes)})"
            return "ListOf[any]()"
        return f"ListOf[{render(elem, self.genv)}]({', '.join(arg_codes)})"

    def enum_inst_from_expected(self, expected, tps):
        parts = []
        for tp in tps:
            if tp in self.genv:
                parts.append(render(self.genv[tp], self.genv))
            else:
                parts.append("any")
        return "[" + ", ".join(parts) + "]"

    def arg_expected(self, head, args):
        name = str(head)
        if name in COMPILED_SIG:
            params, var, ret = COMPILED_SIG[name]
            if var and len(args) > len(params) and params:
                params = params + [params[-1]] * (len(args) - len(params))
            inst_params, _ = self._instantiate_sig(params, ret, args)
            if len(inst_params) < len(args):
                inst_params = inst_params + [None] * (len(args) - len(inst_params))
            return inst_params[:len(args)]
        if "/" in name:
            emitted = self.qual(name)
        elif name in self.local:
            emitted = self.local[name]
        else:
            return [None] * len(args)
        sig = self.fun_sigs.get(emitted)
        if not sig:
            return [None] * len(args)
        _tps, params, _ret = sig
        inst_params, _ = self._instantiate_sig(params, _ret, args)
        if len(inst_params) < len(args):
            inst_params = inst_params + [None] * (len(args) - len(inst_params))
        return inst_params[:len(args)]

    def _instantiate_sig(self, params, ret, args):
        subs = {}
        pinned = [i for i, p in enumerate(params)
                  if not (isinstance(p, dict) and "fn" in p)]
        followed = [i for i in range(len(params)) if i not in pinned]
        for i in pinned:
            if i < len(args):
                try:
                    unify(params[i], self.infer(args[i]), subs)
                except RuntimeError:
                    pass
        for i in followed:
            if i < len(args):
                try:
                    exp_fn = substitute(params[i], subs)
                    unify(exp_fn, self.infer(args[i], exp_fn), subs)
                except RuntimeError:
                    pass
        for i in pinned:
            if i < len(args):
                try:
                    exp_p = substitute(params[i], subs)
                    unify(exp_p, self.infer(args[i], exp_p), subs)
                except RuntimeError:
                    pass
        return [substitute(p, subs) for p in params], substitute(ret, subs)

    def low_call(self, bare, arg_codes, expected, n=None):
        if bare in ("ok", "err", "none", "list", "map-empty"):
            return self.special_typed(bare, arg_codes, expected, n)
        tpl = LOWER[bare]
        arg_list = ", ".join(arg_codes)
        return tpl.replace("{*}", arg_list) if "{*}" in tpl else tpl.format(*arg_codes)

    def special_typed(self, bare, arg_codes, expected, n=None):
        if bare == "ok":
            t, e = self.result_args(expected)
            if (t is None or t == ty_con("any")) and n is not None:
                nk = n.children[1:]
                if nk:
                    t = self.infer(nk[0])
            return f"Ok[{render(t, self.genv)}, {render(e, self.genv)}]({arg_codes[0]})"
        if bare == "err":
            t, e = self.result_args(expected)
            if (e is None or e == ty_con("IoError") or e == ty_con("any")) and n is not None:
                nk = n.children[1:]
                if nk:
                    e = self.infer(nk[0])
            return f"Err[{render(t, self.genv)}, {render(e, self.genv)}]({arg_codes[0]})"
        if bare == "none":
            return f"None[{render(self.option_t(expected), self.genv)}]()"
        if bare == "list":
            return self.list_call(n.children[1:] if n else [], arg_codes, expected)
        if bare == "map-empty":
            k, v = self.map_kv(expected)
            return f"MEmpty[{render(k, self.genv)}, {render(v, self.genv)}]()"
        raise NotImplementedError(bare)

    def result_args(self, expected):
        if expected is not None and expected.get("con") == "Result" and len(expected["args"]) >= 2:
            return expected["args"][0], expected["args"][1]
        return ty_con("any"), ty_con("IoError")

    def option_t(self, expected):
        return expected["args"][0] if expected is not None and expected.get("con") == "Option" \
            else ty_con("any")

    def list_elem(self, expected):
        return expected["args"][0] if expected is not None and expected.get("con") == "List" \
            else ty_con("any")

    def map_kv(self, expected):
        if expected is not None and expected.get("con") == "Map" and len(expected["args"]) >= 2:
            return expected["args"][0], expected["args"][1]
        return ty_con("any"), ty_con("any")

    def atom(self, tok, expected=None):
        s = str(tok)
        if tok.type == "BOOL":
            return "true" if s == "true" else "false"
        if tok.type == "INT":
            if expected is not None and isinstance(expected, dict) and expected.get("con") == "Int32":
                return f"int32({s})"
            return f"int64({s})"
        if tok.type == "FLOAT":
            if s == "-0.0":
                return "NegZero()"
            return s
        if tok.type in ("QUALIFIED", "QUALIFIED_TYPE"):
            return self.qual(s)
        if tok.type == "IDENT":
            return self.resolve(s)
        return s

    # ---------- inference ----------

    def infer(self, n, expected=None):
        if isinstance(n, Tree) and n.data in ("expr", "literal"):
            return self.infer(n.children[0], expected)
        if isinstance(n, Token):
            if n.type == "INT":
                return ty_con("Int64")
            if n.type == "FLOAT":
                return ty_con("Float64")
            if n.type == "STRING":
                return ty_con("String")
            if n.type == "BOOL":
                return ty_con("Bool")
            if n.type == "UNIT":
                return ty_con("Unit")
            if n.type in ("QUALIFIED", "QUALIFIED_TYPE"):
                t = self.tvar_lookup(self.qual(n))
                if t is not None:
                    return t
                emitted = self.qual(n)
                if emitted in self.fun_sigs:
                    _tps, params, ret = self.fun_sigs[emitted]
                    return {"fn": {"params": params, "ret": ret}}
                return ty_con("any")
            s = str(n)
            t = self.tvar_lookup(s)
            if t is not None:
                return t
            if s in self.local:
                emitted = self.local[s]
                if emitted in self.fun_sigs:
                    _tps, params, ret = self.fun_sigs[emitted]
                    return {"fn": {"params": params, "ret": ret}}
            return ty_con("any")
        head = n.children[0] if n.children else None
        if n.data == "call":
            return self.infer_call(n)
        if n.data == "ctor":
            h = n.children[0]
            if isinstance(h, Tree):
                h = h.children[0]
            name = self.qual_type(str(h)) if (isinstance(h, Token)
                                              and h.type == "QUALIFIED_TYPE") else self.resolve(str(h))
            return ty_con(name, [ty_con("any") for _ in self.schema_params.get(name, [])])
        if n.data == "field_access":
            fld = self.tok(n.children[0])[2:]
            st = self.infer(n.children[1])
            emitted = st.get("con") if isinstance(st, dict) and "con" in st else None
            return self.schema_fields.get(emitted, {}).get(fld, ty_con("any"))
        if n.data == "if_form":
            return self.infer(self.kids(n)[1], expected)
        if n.data == "cond_form":
            cls = [c for c in self.kids(n) if isinstance(c, Tree)]
            last = cls[-1]
            ck = self.kids(last)
            return self.infer(ck[-1], expected) if ck else ty_con("Unit")
        if n.data == "match_form":
            subj_t = self.infer(self.kids(n)[0])
            arms = [a for a in self.kids(n)[1:] if isinstance(a, Tree) and a.data == "match_arm"]
            res = None
            subs = {}
            for a in arms:
                ak = self.kids(a)
                if ak and len(ak) > 1:
                    _, binds = self.condition(ak[0], "x", subj_t)
                    self.tstack.append({mangle(k): bt for k, (bcode, bt) in binds.items()})
                    at = self.infer(ak[-1], expected)
                    self.tstack.pop()
                    if res is None:
                        res = at
                    else:
                        try:
                            unify(res, at, subs)
                        except RuntimeError:
                            pass
            return substitute(res, subs) if res is not None else ty_con("Unit")
        if n.data == "try_form":
            r = self.infer(self.kids(n)[0])
            return r["args"][0] if r is not None and r.get("con") == "Result" and r["args"] \
                else ty_con("any")
        if n.data == "fn_form":
            exp_params = expected["fn"]["params"] if expected is not None and isinstance(expected, dict) and "fn" in expected else []
            k = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "type_params")]
            params_node = k[0]
            fns = [p for p in params_node.children if isinstance(p, Tree) and p.data == "fn_param"]
            params = []
            param_names = []
            for i, p in enumerate(fns):
                pk = self.kids(p)
                pname = str(pk[0])
                param_names.append(pname)
                if len(pk) > 1 and isinstance(pk[1], Tree) and pk[1].data == "type":
                    params.append(self.node_type(pk[1]))
                elif exp_params and i < len(exp_params):
                    params.append(exp_params[i])
                else:
                    # an untyped param is a fresh variable so it can be unified
                    # with (rather than masking) the concrete element type
                    params.append(ty_var(self.fresh()))
            ret = None
            body_start = 1
            for i, x in enumerate(k[1:], start=1):
                if isinstance(x, Tree) and x.data == "type":
                    ret = self.node_type(x)
                    body_start = i + 1
                    break
            if ret is None:
                body_exprs = [e for e in k[body_start:] if isinstance(e, Tree)]
                if body_exprs:
                    self.tstack.append({mangle(pname): ptype for pname, ptype in zip(param_names, params)})
                    ret = self.infer(body_exprs[-1])
                    self.tstack.pop()
            if ret is None:
                ret = ty_var(self.fresh())
            return {"fn": {"params": params, "ret": ret}}
        if n.data == "let_form":
            body = [x for x in self.kids(n) if not (isinstance(x, Tree) and x.data == "binding")]
            return self.infer(body[-1]) if body else ty_con("Unit")
        return ty_con("any")

    def infer_call(self, n):
        head = n.children[0]
        if isinstance(head, Tree):
            head = head.children[0]
        name = str(head)
        args = n.children[1:]
        if name in COMPILED_SIG:
            params, var, ret = COMPILED_SIG[name]
            if var and len(args) > len(params) and params:
                params = params + [params[-1]] * (len(args) - len(params))
            _, inst_ret = self._instantiate_sig(params, ret, args)
            return inst_ret
        bare = name.partition("/")[2] if (("/" in name) and name != "/") else name
        if bare in COMPILED_SIG:
            params, var, ret = COMPILED_SIG[bare]
            if var and len(args) > len(params) and params:
                params = params + [params[-1]] * (len(args) - len(params))
            _, inst_ret = self._instantiate_sig(params, ret, args)
            return inst_ret
        if "/" in name:
            emitted = self.qual(name)
        else:
            emitted = self.local.get(name, name)
        if emitted in self.fun_sigs:
            tps, params, ret = self.fun_sigs[emitted]
            _, inst_ret = self._instantiate_sig(params, ret, args)
            return inst_ret
        if bare in self.enums and name in self.local:
            en, tps, _ = self.enums[bare]
            return ty_con(en, [self.genv[tp] if tp in self.genv else ty_con("any")
                               for tp in tps] or [])
        return ty_con("any")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--root", action="append", default=[],
                    help="source root for module resolution; repeatable.")
    args = ap.parse_args()
    source = Path(args.file)
    sys.stdout.write(ToGo().transpile(source.read_text(), path=source,
                                      roots=[Path(r) for r in args.root]))
