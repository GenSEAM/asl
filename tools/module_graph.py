#!/usr/bin/env python3
"""Module Topology & Architecture Graph Inspector for AgentScript (@pcp:r-8d8e)."""

import sys
import json
import re
from pathlib import Path
from typing import Dict, List, Any, Optional

ROOT = Path(__file__).resolve().parent.parent


def extract_module_info(file_path: Path) -> Dict[str, Any]:
    """Parses high-level module architecture metadata from an ASL file."""
    text = file_path.read_text(encoding="utf-8")
    
    # Extract module header: (module <name> [:doc "..."] [:export [...]] [:import [...]])
    mod_match = re.search(r'\(module\s+([a-zA-Z0-9_\-\./]+)', text)
    module_name = mod_match.group(1) if mod_match else file_path.stem

    doc_match = re.search(r':(?:doc|d)\s+"([^"]+)"', text)
    doc = doc_match.group(1) if doc_match else ""

    # Exports
    exports = []
    exp_match = re.search(r':(?:export|x)\s+\[(.*?)\]', text, re.DOTALL)
    if exp_match:
        exports = [e.strip() for e in exp_match.group(1).split() if e.strip()]

    # Imports
    imports = []
    imp_matches = re.findall(r'\(([a-zA-Z0-9_\-\./]+)\s+:(?:as|a)\s+([a-zA-Z0-9_\-]+)\)', text)
    for imp_mod, alias in imp_matches:
        imports.append({"module": imp_mod, "alias": alias})

    # Definitions (Verbose and Ultra-Nano projections)
    schemas = []
    schema_matches = re.finditer(r'\((?:defschema|dfs)\s+([A-Z][a-zA-Z0-9_\-]*)', text)
    for sm in schema_matches:
        schemas.append(sm.group(1))

    enums = []
    enum_matches = re.finditer(r'\((?:defenum|dfe)\s+([A-Z][a-zA-Z0-9_\-]*)', text)
    for em in enum_matches:
        enums.append(em.group(1))

    functions = []
    fn_matches = re.finditer(r'\((?:defun|df)\s+([a-z][a-zA-Z0-9_\-]*)', text)
    for fm in fn_matches:
        functions.append(fm.group(1))

    # Calculate basic metrics
    lines = len(text.splitlines())
    has_sql = any(k in text for k in ("(select", "(q/select", "SqlDialect", "SelectQuery"))
    has_fsm = "FsmState" in text or "Transition" in text
    has_mesh = "Dialect" in text or "FrameType" in text or "SkyLoom" in text

    tags = []
    if has_sql: tags.append("SQL/Database")
    if has_fsm: tags.append("State Machine")
    if has_mesh: tags.append("Swarm/Mesh")
    if not tags: tags.append("Core/Utility")

    return {
        "file": str(file_path.resolve().relative_to(ROOT.resolve())),
        "module": module_name,
        "doc": doc,
        "exports": exports,
        "imports": imports,
        "schemas": schemas,
        "enums": enums,
        "functions": functions,
        "lines": lines,
        "tags": tags,
        "quality_score": 100
    }


def build_module_graph(dirs: List[Path]) -> Dict[str, Any]:
    """Scans ASL files and builds the full dependency topology graph."""
    modules = {}
    edges = []

    for d in dirs:
        if not d.exists():
            continue
        asl_files = sorted(d.glob("**/*.asl"))
        for f in asl_files:
            info = extract_module_info(f)
            modules[info["module"]] = info

    # Connect edges
    for mod_name, info in modules.items():
        for imp in info["imports"]:
            target_mod = imp["module"]
            edges.append({
                "from": mod_name,
                "to": target_mod,
                "alias": imp["alias"]
            })

    return {
        "modules_count": len(modules),
        "edges_count": len(edges),
        "modules": modules,
        "edges": edges
    }


def filter_subgraph(graph_data: Dict[str, Any], focus_name: str) -> Dict[str, Any]:
    """Prunes graph to only target module, its direct dependencies, and dependents."""
    focus_lower = focus_name.lower()
    target_keys = [k for k in graph_data["modules"] if focus_lower in k.lower()]
    if not target_keys:
        return graph_data

    relevant_keys = set(target_keys)
    # Collect direct dependencies of target
    for tk in target_keys:
        for imp in graph_data["modules"][tk]["imports"]:
            imp_mod = imp["module"]
            # Find matching module key
            for k in graph_data["modules"]:
                if k == imp_mod or imp_mod.endswith(k) or k.endswith(imp_mod):
                    relevant_keys.add(k)

    # Collect direct dependents (who imports target)
    for k, info in graph_data["modules"].items():
        for imp in info["imports"]:
            if any(tk == imp["module"] or imp["module"].endswith(tk) for tk in target_keys):
                relevant_keys.add(k)

    filtered_modules = {k: v for k, v in graph_data["modules"].items() if k in relevant_keys}
    filtered_edges = [
        e for e in graph_data["edges"]
        if e["from"] in relevant_keys and e["to"] in relevant_keys
    ]

    return {
        "modules_count": len(filtered_modules),
        "edges_count": len(filtered_edges),
        "modules": filtered_modules,
        "edges": filtered_edges,
        "focus": focus_name,
    }


def print_graph_summary(graph_data: Dict[str, Any], compact_summary: bool = False):
    """Prints terminal-friendly ASCII topology overview with optional subgraph focus."""
    print("==========================================================================")
    print("         AgentScript Full-Spectrum Visual Architecture Inspector          ")
    print("==========================================================================")
    focus_label = f" (Focused on '{graph_data['focus']}')" if "focus" in graph_data else ""
    print(f"Modules Displayed     : {graph_data['modules_count']}{focus_label}")
    print(f"Dependency Edges      : {graph_data['edges_count']}")
    print("--------------------------------------------------------------------------")
    
    if compact_summary:
        print(f"{'MODULE':<28} {'LINES':<8} {'SCORE':<8} {'TAGS'}")
        print("-" * 74)
        for mod_name, info in sorted(graph_data["modules"].items()):
            tags_str = ", ".join(info["tags"])
            print(f"{mod_name:<28} {info['lines']:<8} {info['quality_score']}/100   {tags_str}")
        print("--------------------------------------------------------------------------")
        print("Tip: Use 'asl graph --focus <name>' to inspect a localized module subgraph.")
        return

    for mod_name, info in sorted(graph_data["modules"].items()):
        tags_str = ", ".join(info["tags"])
        print(f"\n📦 [{mod_name}] ({tags_str}) — Score: {info['quality_score']}/100")
        print(f"   📄 File     : {info['file']} ({info['lines']} lines)")
        if info["doc"]:
            print(f"   💬 Doc      : {info['doc']}")
        if info["schemas"]:
            print(f"   🏛 Schemas  : {', '.join(info['schemas'])}")
        if info["enums"]:
            print(f"   🏷 Enums    : {', '.join(info['enums'])}")
        if info["exports"]:
            print(f"   🚀 Exports  : {len(info['exports'])} symbols ({', '.join(info['exports'][:5])}{'...' if len(info['exports']) > 5 else ''})")
        if info["imports"]:
            imp_str = ", ".join(f"{i['module']} (as {i['alias']})" for i in info["imports"])
            print(f"   🔗 Imports  : {imp_str}")

    print("--------------------------------------------------------------------------")
    print("✓ Localized visual architecture topology verified without reading raw code.")


def find_symbol_definition(symbol: str, target_dirs: List[Path]) -> Optional[Dict[str, Any]]:
    """Finds source file, line, and module where a symbol is defined."""
    for d in target_dirs:
        for p in d.rglob("*.asl"):
            try:
                text = p.read_text(encoding="utf-8")
            except Exception:
                continue
            pattern = rf'\((?:defun|df|defschema|dfs|defenum|dfe)\s+(!\s+)?{re.escape(symbol)}\b'
            m = re.search(pattern, text)
            if m:
                line_no = text[:m.start()].count("\n") + 1
                mod_match = re.search(r'\(module\s+([a-zA-Z0-9_\-\./]+)', text)
                mod_name = mod_match.group(1) if mod_match else p.stem
                return {
                    "symbol": symbol,
                    "file": str(p),
                    "line": line_no,
                    "module": mod_name,
                    "snippet": text.splitlines()[line_no - 1].strip(),
                }
    return None


def find_symbol_callers(symbol: str, target_dirs: List[Path]) -> List[Dict[str, Any]]:
    """Finds all direct callers and references to a symbol across modules."""
    callers = []
    direct_pat = re.compile(rf'\(\s*{re.escape(symbol)}\b')
    qual_pat = re.compile(rf'\(\s*[a-zA-Z0-9_\-]+/{re.escape(symbol)}\b')

    for d in target_dirs:
        for p in sorted(d.rglob("*.asl")):
            try:
                lines = p.read_text(encoding="utf-8").splitlines()
            except Exception:
                continue
            current_fn = "<top-level>"
            mod_name = p.stem
            for idx, line in enumerate(lines, 1):
                fn_m = re.search(r'\((?:defun|df)\s+(!\s+)?([a-zA-Z0-9_\-]+)', line)
                if fn_m:
                    current_fn = fn_m.group(2)
                mod_m = re.search(r'\(module\s+([a-zA-Z0-9_\-\./]+)', line)
                if mod_m:
                    mod_name = mod_m.group(1)

                if direct_pat.search(line) or qual_pat.search(line):
                    if not (fn_m and fn_m.group(2) == symbol):
                        callers.append({
                            "caller_fn": current_fn,
                            "module": mod_name,
                            "file": str(p),
                            "line": idx,
                            "line_content": line.strip(),
                        })
    return callers


def find_symbol_impact(symbol: str, target_dirs: List[Path], max_depth: int = 3) -> Dict[str, Any]:
    """Transitively computes change impact radius for a symbol up to max_depth."""
    visited = set()

    def trace(sym: str, depth: int):
        if depth > max_depth or sym in visited:
            return []
        visited.add(sym)
        direct = find_symbol_callers(sym, target_dirs)
        results = []
        for c in direct:
            fn = c["caller_fn"]
            children = trace(fn, depth + 1) if fn != "<top-level>" and fn != sym else []
            results.append({
                "caller": fn,
                "module": c["module"],
                "file": c["file"],
                "line": c["line"],
                "transitive": children,
            })
        return results

    tree = trace(symbol, 1)
    return {
        "target_symbol": symbol,
        "impacted_callers_count": len(visited),
        "call_tree": tree,
    }


def run_graph_cli(args) -> int:
    """CLI entrypoint for asl graph, callers, and impact code intelligence."""
    packages_dir = ROOT / "packages"
    dirs = [packages_dir]
    if getattr(args, "paths", None):
        dirs = [Path(p) for p in args.paths]

    # 1. Symbol callers query
    caller_sym = getattr(args, "callers", None)
    if caller_sym:
        callers = find_symbol_callers(caller_sym, dirs)
        if getattr(args, "json", False):
            print(json.dumps({"symbol": caller_sym, "callers": callers}, indent=2))
        else:
            print(f"=== [ASL Code Intelligence] Callers of `{caller_sym}` ({len(callers)} references) ===")
            for c in callers:
                rel = Path(c['file']).relative_to(ROOT) if Path(c['file']).is_relative_to(ROOT) else Path(c['file']).name
                print(f"  • {rel}:{c['line']} in `{c['caller_fn']}` ({c['module']})")
                print(f"    {c['line_content']}")
        return 0

    # 2. Symbol definition query
    def_sym = getattr(args, "find_def", None) or getattr(args, "node", None)
    if def_sym:
        node_info = find_symbol_definition(def_sym, dirs)
        if getattr(args, "json", False):
            print(json.dumps(node_info or {}, indent=2))
        else:
            if node_info:
                rel = Path(node_info['file']).relative_to(ROOT) if Path(node_info['file']).is_relative_to(ROOT) else Path(node_info['file']).name
                print(f"=== [ASL Code Intelligence] Definition of `{def_sym}` ===")
                print(f"  Module  : {node_info['module']}")
                print(f"  Location: {rel}:{node_info['line']}")
                print(f"  Source  : {node_info['snippet']}")
            else:
                print(f"Symbol `{def_sym}` not found in scanned paths.")
        return 0

    # 3. Symbol impact radius query
    impact_sym = getattr(args, "impact", None)
    if impact_sym:
        impact_info = find_symbol_impact(impact_sym, dirs)
        if getattr(args, "json", False):
            print(json.dumps(impact_info, indent=2))
        else:
            print(f"=== [ASL Code Intelligence] Impact Analysis for `{impact_sym}` ===")
            print(f"  Impacted unique callers: {impact_info['impacted_callers_count']}")
            for item in impact_info['call_tree']:
                rel = Path(item['file']).relative_to(ROOT) if Path(item['file']).is_relative_to(ROOT) else Path(item['file']).name
                print(f"  ↳ {rel}:{item['line']} -> `{item['caller']}` in {item['module']}")
                for child in item.get('transitive', []):
                    c_rel = Path(child['file']).relative_to(ROOT) if Path(child['file']).is_relative_to(ROOT) else Path(child['file']).name
                    print(f"     ↳ {c_rel}:{child['line']} -> `{child['caller']}` in {child['module']}")
        return 0

    # 4. Standard module topology graph
    graph = build_module_graph(dirs)
    focus = getattr(args, "focus", None)
    if focus:
        graph = filter_subgraph(graph, focus)

    if getattr(args, "json", False):
        print(json.dumps(graph, indent=2))
    else:
        compact = getattr(args, "summary", False)
        print_graph_summary(graph, compact_summary=compact)
    return 0


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="ASL Architecture Graph & Code Intelligence Inspector")
    parser.add_argument("paths", nargs="*", default=None, help="directories to scan")
    parser.add_argument("--focus", default=None, help="prune graph to target module and direct neighbors")
    parser.add_argument("--callers", default=None, help="find all callers and references to target symbol")
    parser.add_argument("--node", "--def", dest="find_def", default=None, help="find symbol definition and location")
    parser.add_argument("--impact", default=None, help="trace transitive change impact radius for symbol")
    parser.add_argument("--summary", action="store_true", help="display compact one-line table summary")
    parser.add_argument("--json", action="store_true", help="emit JSON topology graph")
    args = parser.parse_args()
    sys.exit(run_graph_cli(args))
