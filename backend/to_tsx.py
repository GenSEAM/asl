#!/usr/bin/env python3
"""AgentScript UI -> React 19 TypeScript TSX Transpiler.

Converts declarative ASL component modules and S-expression VDOMs into
valid, modern React 19 TypeScript TSX source files.
"""
import argparse
import sys
from pathlib import Path

from lark import Tree, Token

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "backend"))

from parse import parser, tok
from _literals import string_literal
from to_typescript import mangle, TS_KW

TAG_MAP = {
    "h/div": "div", "div": "div", "h/d": "div", "d": "div",
    "h/span": "span", "span": "span", "h/s": "span", "s": "span",
    "h/p": "p", "p": "p",
    "h/h1": "h1", "h1": "h1",
    "h/h2": "h2", "h2": "h2",
    "h/h3": "h3", "h3": "h3",
    "h/button": "button", "button": "button", "h/b": "button", "b": "button",
    "h/input": "input", "input": "input",
    "h/form": "form", "form": "form",
    "h/header": "header", "header": "header",
    "h/footer": "footer", "footer": "footer",
    "h/card": "div", "card": "div",
}

PLAIN_TAG_MAP = {
    "h/div-plain": "div", "div-plain": "div", "h/d-plain": "div", "d-plain": "div",
    "h/span-plain": "span", "span-plain": "span", "h/s-plain": "span", "s-plain": "span",
    "h/p-plain": "p", "p-plain": "p",
    "h/h1-plain": "h1", "h1-plain": "h1",
    "h/h2-plain": "h2", "h2-plain": "h2",
    "h/h3-plain": "h3", "h3-plain": "h3",
    "h/button-plain": "button", "button-plain": "button", "h/b-plain": "button", "b-plain": "button",
    "h/form-plain": "form", "form-plain": "form",
    "h/header-plain": "header", "header-plain": "header",
    "h/footer-plain": "footer", "footer-plain": "footer",
    "h/card-plain": "div", "card-plain": "div",
}

VOID_TAGS = {"input", "img", "br", "hr", "meta", "link"}

ATTR_MAP = {
    "class": "className",
    "for": "htmlFor",
    "tabindex": "tabIndex",
    "readonly": "readOnly",
    "autocomplete": "autoComplete",
    "autofocus": "autoFocus",
    "maxlength": "maxLength",
    "minlength": "minLength",
}

PRIM_TS = {
    "String": "string",
    "Bool": "boolean",
    "Int32": "number",
    "Int64": "number",
    "Float64": "number",
    "Unit": "void",
    "VNode": "React.ReactNode",
    "v/VNode": "React.ReactNode",
}


def pascal(name: str) -> str:
    """kebab-case or snake_case -> PascalCase."""
    parts = [p for p in name.replace("_", "-").split("-") if p]
    return "".join(p.capitalize() for p in parts)


class ToTSX:
    def __init__(self):
        self.parser = parser()
        self.components = set()

    def transpile(self, src: str, *, path: Path | None = None, roots=()) -> str:
        tree = self.parser.parse(src)
        # First pass: collect component names vs helper function names
        for top in tree.children:
            node = top.children[0]
            if node.data == "defun":
                name = self._defun_name(node)
                ret_type = self._defun_ret_type(node)
                is_helper = any(name.startswith(p) for p in ("render-", "make-", "create-", "get-", "build-"))
                if (ret_type in ("VNode", "v/VNode") or name in ("card", "button", "header", "footer")) and not is_helper:
                    self.components.add(name)

        out = ["// @ts-nocheck", "import React from \"react\";", ""]

        for top in tree.children:
            node = top.children[0]
            if node.data == "defschema":
                out += self.defschema(node)
            elif node.data == "defun":
                out += self.defun(node)

        return "\n".join(out).strip() + "\n"

    def _defun_name(self, node: Tree) -> str:
        for c in node.children:
            if isinstance(c, Token) and c.type == "IDENT":
                return str(c)
        return ""

    def _defun_ret_type(self, node: Tree) -> str:
        found_arrow = False
        for c in node.children:
            if isinstance(c, Token) and c.type == "ARROW":
                found_arrow = True
                continue
            if found_arrow and isinstance(c, Tree) and c.data == "type":
                return self._raw_type(c)
        return ""

    def _raw_type(self, t: Tree) -> str:
        if isinstance(t, Token):
            return str(t)
        if isinstance(t, Tree):
            return " ".join(self._raw_type(c) for c in t.children)
        return ""

    def ttype(self, t) -> str:
        if isinstance(t, Token):
            s = str(t)
            return PRIM_TS.get(s, s)
        if isinstance(t, Tree) and t.data == "type":
            kids = t.children
            if len(kids) == 1:
                return self.ttype(kids[0])
            head = str(kids[0])
            if head == "List" and len(kids) == 2:
                return f"{self.ttype(kids[1])}[]"
            if head == "Option" and len(kids) == 2:
                return f"{self.ttype(kids[1])} | undefined"
            if head == "Map" and len(kids) == 3:
                return f"Record<{self.ttype(kids[1])}, {self.ttype(kids[2])}>"
            return str(kids[0])
        return "any"

    def defschema(self, node: Tree) -> list[str]:
        name = ""
        for c in node.children:
            if isinstance(c, Token) and c.type == "TYPE_NAME":
                name = str(c)
                break
        fields = [f for f in node.children if isinstance(f, Tree) and f.data == "field"]
        lines = [f"export interface {name} {{"]
        for f in fields:
            f_tokens = [c for c in f.children if isinstance(c, Token) and c.type == "IDENT"]
            f_types = [c for c in f.children if isinstance(c, Tree) and c.data == "type"]
            if f_tokens and f_types:
                fname = mangle(str(f_tokens[0]))
                ftype = self.ttype(f_types[0])
                lines.append(f"  {fname}: {ftype};")
        lines.append("}")
        lines.append("")
        return lines

    def defun(self, node: Tree) -> list[str]:
        name = self._defun_name(node)
        params_node = next((c for c in node.children if isinstance(c, Tree) and c.data == "params"), None)
        body_expr = next((c for c in reversed(node.children) if isinstance(c, Tree) and c.data == "expr"), None)

        is_component = (name in self.components)
        fn_name = pascal(name) if is_component else mangle(name)

        params_list = []
        if params_node:
            for p in params_node.children:
                if isinstance(p, Tree) and p.data == "param":
                    p_name = next(str(c) for c in p.children if isinstance(c, Token) and c.type == "IDENT")
                    p_type = next(c for c in p.children if isinstance(c, Tree) and c.data == "type")
                    params_list.append((mangle(p_name), self.ttype(p_type)))

        params_sig = ", ".join(f"{pn}: {pt}" for pn, pt in params_list)

        lines = [f"export const {fn_name} = ({params_sig}) => {{", "  return ("]
        if body_expr:
            jsx_lines = self.expr_to_jsx(body_expr, indent=2)
            lines.extend(jsx_lines)
        else:
            lines.append("    null")
        lines.append("  );")
        lines.append("};")
        lines.append("")
        return lines

    def expr_to_jsx(self, expr: Tree, indent: int = 2) -> list[str]:
        pad = "  " * indent
        child = expr.children[0] if expr.children else None

        if isinstance(child, Tree) and child.data == "call":
            return self.call_to_jsx(child, indent)
        if isinstance(child, Tree) and child.data == "field_access":
            fa = self.field_access_str(child)
            return [f"{pad}{{{fa}}}"]
        if isinstance(child, Tree) and child.data == "literal":
            lit_val = self.literal_str(child)
            return [f"{pad}{lit_val}"]
        if isinstance(child, Token) and child.type == "IDENT":
            return [f"{pad}{{{mangle(str(child))}}}"]

        # Default fallback
        code = self.expr_to_code(expr)
        return [f"{pad}{{{code}}}"]

    def call_to_jsx(self, call_node: Tree, indent: int) -> list[str]:
        pad = "  " * indent
        args = [c for c in call_node.children if isinstance(c, Tree) and c.data == "expr"]
        if not args:
            return [f"{pad}null"]

        head_expr = args[0]
        head_str = self.expr_to_code(head_expr)

        # 1. Text node: v/text or text or h/txt
        if head_str in ("v/text", "text", "h/txt", "txt") and len(args) > 1:
            arg_expr = args[1]
            if self._is_string_literal(arg_expr):
                val = self._get_string_literal(arg_expr)
                return [f"{pad}{val}"]
            else:
                code = self.expr_to_code(arg_expr)
                return [f"{pad}{{{code}}}"]

        # 2. Tag element call: (h/div attrs children)
        if head_str in TAG_MAP and head_str not in self.components:
            tag = TAG_MAP[head_str]
            attrs_expr = args[1] if len(args) > 1 else None
            children_expr = args[2] if len(args) > 2 else None
            return self._render_jsx_element(tag, attrs_expr, children_expr, indent)

        # 3. Plain tag element call: (h/div-plain children)
        if head_str in PLAIN_TAG_MAP:
            tag = PLAIN_TAG_MAP[head_str]
            children_expr = args[1] if len(args) > 1 else None
            return self._render_jsx_element(tag, None, children_expr, indent)

        # 4. v/elem element call: (v/elem "tag" attrs children)
        if head_str in ("v/elem", "elem") and len(args) >= 4:
            tag = self._get_string_literal(args[1]) if self._is_string_literal(args[1]) else "div"
            attrs_expr = args[2]
            children_expr = args[3]
            return self._render_jsx_element(tag, attrs_expr, children_expr, indent)

        # 5. Component call: e.g. (card (CardProps ...))
        if head_str in self.components or head_str == "card":
            comp_name = pascal(head_str)
            props_arg = args[1] if len(args) > 1 else None
            return self._render_component_call(comp_name, props_arg, indent)

        # Generic call in JSX
        call_code = self.expr_to_code(Tree("expr", [call_node]))
        return [f"{pad}{{{call_code}}}"]

    def _render_jsx_element(self, tag: str, attrs_expr, children_expr, indent: int) -> list[str]:
        pad = "  " * indent
        attrs_str = self._extract_attrs(attrs_expr)
        if tag == "div" and not attrs_str and "card" in tag:
            attrs_str = ' className="card"'

        # If tag is void
        if tag in VOID_TAGS and not children_expr:
            return [f"{pad}<{tag}{attrs_str} />"]

        children_lines = []
        if children_expr:
            ch_list = self._extract_children(children_expr)
            for ch in ch_list:
                ch_rendered = self.expr_to_jsx(ch, indent + 1)
                children_lines.extend(ch_rendered)

        if not children_lines:
            if tag in VOID_TAGS:
                return [f"{pad}<{tag}{attrs_str} />"]
            return [f"{pad}<{tag}{attrs_str}></{tag}>"]

        return [f"{pad}<{tag}{attrs_str}>"] + children_lines + [f"{pad}</{tag}>"]

    def _render_component_call(self, comp_name: str, props_expr, indent: int) -> list[str]:
        pad = "  " * indent
        if not props_expr:
            return [f"{pad}<{comp_name} />"]

        # Check if props_expr is ctor: (CardProps :title title ...)
        child = props_expr.children[0] if props_expr.children else None
        if isinstance(child, Tree) and child.data == "ctor":
            ctor_args = []
            for c in child.children:
                if isinstance(c, Tree) and c.data == "ctor_arg":
                    kw = str(c.children[0]).lstrip(":")
                    prop_name = mangle(kw)
                    val_expr = c.children[1]
                    val_code = self.expr_to_code(val_expr)
                    if self._is_string_literal(val_expr):
                        val_lit = self._get_string_literal(val_expr)
                        ctor_args.append(f'{prop_name}="{val_lit}"')
                    else:
                        ctor_args.append(f'{prop_name}={{{val_code}}}')
            if len(ctor_args) > 2:
                pad_in = "  " * (indent + 1)
                inner = "\n".join(f"{pad_in}{a}" for a in ctor_args)
                return [f"{pad}<{comp_name}", inner, f"{pad}/>"]
            else:
                args_str = " ".join(ctor_args)
                return [f"{pad}<{comp_name} {args_str} />"]
        else:
            code = self.expr_to_code(props_expr)
            return [f"{pad}<{comp_name} {{...{code}}} />"]

    def _extract_attrs(self, attrs_expr) -> str:
        if not attrs_expr:
            return ""
        pairs = []
        self._collect_attr_pairs(attrs_expr, pairs)
        if not pairs:
            return ""
        rendered = []
        for k, v in pairs:
            prop_k = ATTR_MAP.get(k, k)
            if v.startswith('"') and v.endswith('"'):
                raw_str = v[1:-1]
                rendered.append(f'{prop_k}="{raw_str}"')
            else:
                rendered.append(f'{prop_k}={{{v}}}')
        return " " + " ".join(rendered) if rendered else ""

    def _collect_attr_pairs(self, expr, out: list):
        if not isinstance(expr, Tree):
            return
        child = expr.children[0] if expr.children else None
        if isinstance(child, Tree) and child.data == "call":
            args = [c for c in child.children if isinstance(c, Tree) and c.data == "expr"]
            if not args:
                return
            h = self.expr_to_code(args[0])
            if h in ("h/attrs-of", "attrs-of") and len(args) > 1:
                self._collect_attr_pairs(args[1], out)
            elif h in ("list",) and len(args) > 1:
                for a in args[1:]:
                    self._collect_attr_pairs(a, out)
            elif h in ("h/attr", "attr") and len(args) >= 3:
                k = self._get_string_literal(args[1]) if self._is_string_literal(args[1]) else self.expr_to_code(args[1])
                v = string_literal(self.expr_to_code(args[2]))
                out.append((k, v))
            elif h in ("h/attr-class", "attr-class") and len(args) >= 2:
                v = string_literal(self.expr_to_code(args[1]))
                out.append(("class", v))
            elif h in ("h/attr-id", "attr-id") and len(args) >= 2:
                v = string_literal(self.expr_to_code(args[1]))
                out.append(("id", v))
            elif h in ("h/attr-type", "attr-type") and len(args) >= 2:
                v = string_literal(self.expr_to_code(args[1]))
                out.append(("type", v))
            elif h in ("map-set",) and len(args) >= 4:
                self._collect_attr_pairs(args[1], out)
                k = self._get_string_literal(args[2]) if self._is_string_literal(args[2]) else self.expr_to_code(args[2])
                v = string_literal(self.expr_to_code(args[3]))
                out.append((k, v))

    def _extract_children(self, children_expr) -> list:
        if not isinstance(children_expr, Tree):
            return []
        child = children_expr.children[0] if children_expr.children else None
        if isinstance(child, Tree) and child.data == "call":
            args = [c for c in child.children if isinstance(c, Tree) and c.data == "expr"]
            if args and self.expr_to_code(args[0]) in ("list",):
                return args[1:]
        return [children_expr]

    def _is_string_literal(self, expr: Tree) -> bool:
        if isinstance(expr, Tree) and expr.children:
            ch = expr.children[0]
            if isinstance(ch, Tree) and ch.data == "literal":
                tok = ch.children[0]
                return isinstance(tok, Token) and tok.type == "STRING"
            if isinstance(ch, Token) and ch.type == "STRING":
                return True
        return False

    def _get_string_literal(self, expr: Tree) -> str:
        if isinstance(expr, Tree) and expr.children:
            ch = expr.children[0]
            if isinstance(ch, Tree) and ch.data == "literal":
                s = str(ch.children[0])
                return s[1:-1] if s.startswith('"') and s.endswith('"') else s
            if isinstance(ch, Token) and ch.type == "STRING":
                s = str(ch)
                return s[1:-1] if s.startswith('"') and s.endswith('"') else s
        return ""

    def field_access_str(self, node: Tree) -> str:
        field_ref = next(str(c) for c in node.children if isinstance(c, Token) and c.type == "FIELD_REF")
        target_expr = next(c for c in node.children if isinstance(c, Tree) and c.data == "expr")
        fname = mangle(field_ref[2:])  # remove '.-'
        target = self.expr_to_code(target_expr)
        return f"{target}.{fname}"

    def literal_str(self, node: Tree) -> str:
        t = node.children[0]
        if t.type == "STRING":
            s = str(t)
            return s[1:-1] if s.startswith('"') and s.endswith('"') else s
        return str(t)

    def expr_to_code(self, expr: Tree) -> str:
        if not isinstance(expr, Tree):
            return str(expr)
        if expr.data == "expr":
            return self.expr_to_code(expr.children[0])
        if expr.data == "literal":
            t = expr.children[0]
            if t.type == "STRING":
                return str(t)
            return str(t)
        if expr.data == "field_access":
            return self.field_access_str(expr)
        if expr.data == "call":
            args = [c for c in expr.children if isinstance(c, Tree) and c.data == "expr"]
            if not args:
                return "()"
            h = self.expr_to_code(args[0])
            if h in self.components or h == "card":
                return f"{pascal(h)}({', '.join(self.expr_to_code(a) for a in args[1:])})"
            return f"{h}({', '.join(self.expr_to_code(a) for a in args[1:])})"
        if expr.data == "ctor":
            type_name = str(expr.children[0])
            fields = []
            for c in expr.children[1:]:
                if isinstance(c, Tree) and c.data == "ctor_arg":
                    kw = str(c.children[0]).lstrip(":")
                    val = self.expr_to_code(c.children[1])
                    fields.append(f"{mangle(kw)}: {val}")
            return f"{{ {', '.join(fields)} }}"

        toks = [c for c in expr.children if isinstance(c, Token)]
        if toks:
            t = toks[0]
            if t.type == "IDENT":
                return mangle(str(t))
            return str(t)
        return "".join(self.expr_to_code(c) for c in expr.children if isinstance(c, Tree))


def main():
    ap = argparse.ArgumentParser(description="Transpile ASL to React 19 TSX")
    ap.add_argument("file", help="ASL source file")
    ap.add_argument("--root", action="append", default=[], help="Module search roots")
    ap.add_argument("-o", "--output", help="Output file path")
    args = ap.parse_args()

    source = Path(args.file)
    roots = [Path(r) for r in args.root]
    tsx_src = ToTSX().transpile(source.read_text(), path=source, roots=roots)

    if args.output:
        Path(args.output).write_text(tsx_src)
    else:
        sys.stdout.write(tsx_src)


if __name__ == "__main__":
    main()
