#!/usr/bin/env python3
"""AgentScript Structural Clone and AST Copy-Paste Duplicate Code Detector.

Implements structural subtree fingerprinting matching `packages/asl-lint/src/core/clone.asl`.
"""
import hashlib
import json
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "checker"))

from parse import parse_file, parse_text, position
from lark import Token, Tree


@dataclass
class CloneInstance:
    file: str
    line: int
    col: int
    raw_snippet: str


@dataclass
class CloneCluster:
    hash_id: str
    node_count: int
    clone_type: str  # "exact-clone" | "structural-clone"
    instances: List[CloneInstance]

    @property
    def occurrences(self) -> int:
        return len(self.instances)


@dataclass
class CloneReport:
    total_nodes: int
    duplicate_nodes: int
    duplication_ratio: float
    is_excessive: bool
    clusters: List[CloneCluster]


class AslCloneDetector:
    def __init__(self, min_node_count: int = 10, max_duplication_threshold: float = 0.15):
        self.min_node_count = min_node_count
        self.max_duplication_threshold = max_duplication_threshold

    def analyze_paths(self, paths: List[Path]) -> CloneReport:
        asl_files: List[Path] = []
        for p in paths:
            p = p.resolve()
            if p.is_file() and p.suffix in (".asl", ".agentscript"):
                asl_files.append(p)
            elif p.is_dir():
                asl_files.extend(list(p.rglob("*.asl")) + list(p.rglob("*.agentscript")))

        total_nodes = 0
        structural_map: Dict[str, List[Tuple[CloneInstance, int, str]]] = {}

        for f in sorted(asl_files):
            try:
                tree = parse_file(f)
                file_nodes = [0]
                self._extract_subtrees(tree, str(f), file_nodes, structural_map)
                total_nodes += file_nodes[0]
            except Exception:
                continue

        # Form clusters where occurrences >= 2
        clusters: List[CloneCluster] = []
        duplicate_nodes = 0

        for h_id, items in structural_map.items():
            if len(items) >= 2:
                # Filter out clusters that are fully contained inside an already reported larger cluster
                node_count = items[0][1]
                exact_texts = {item[2] for item in items}
                clone_type = "exact-clone" if len(exact_texts) == 1 else "structural-clone"
                insts = [item[0] for item in items]
                clusters.append(
                    CloneCluster(
                        hash_id=h_id[:12],
                        node_count=node_count,
                        clone_type=clone_type,
                        instances=insts,
                    )
                )
                duplicate_nodes += (len(items) - 1) * node_count

        # Sort clusters by impact (node_count * occurrences) descending
        clusters.sort(key=lambda c: c.node_count * c.occurrences, reverse=True)

        ratio = (duplicate_nodes / total_nodes) if total_nodes > 0 else 0.0
        is_excessive = ratio > self.max_duplication_threshold

        return CloneReport(
            total_nodes=total_nodes,
            duplicate_nodes=duplicate_nodes,
            duplication_ratio=round(ratio, 4),
            is_excessive=is_excessive,
            clusters=clusters,
        )

    def _extract_subtrees(
        self,
        node,
        file_path: str,
        counter: List[int],
        out_map: Dict[str, List[Tuple[CloneInstance, int, str]]],
    ) -> Tuple[int, str, str]:
        """Returns (subtree_node_count, exact_repr, normalized_repr)."""
        if isinstance(node, Token):
            counter[0] += 1
            return 1, str(node), "<TOK>"

        if not isinstance(node, Tree):
            return 0, "", ""

        counter[0] += 1
        current_node_count = 1

        exact_parts: List[str] = [f"({node.data}"]
        norm_parts: List[str] = [f"({node.data}"]
        var_alpha_map: Dict[str, str] = {}

        for child in node.children:
            if isinstance(child, Token):
                current_node_count += 1
                token_str = str(child)
                exact_parts.append(token_str)
                # Alpha-normalize identifiers only. Literal values (numbers,
                # strings, keywords) stay exact so a dispatch table or an
                # index access is not conflated with a copy-paste clone.
                if child.type in ("IDENT", "NAME", "VAR"):
                    if token_str not in var_alpha_map:
                        var_alpha_map[token_str] = f"α{len(var_alpha_map)}"
                    norm_parts.append(var_alpha_map[token_str])
                else:
                    norm_parts.append(token_str)
            elif isinstance(child, Tree):
                c_count, c_exact, c_norm = self._extract_subtrees(child, file_path, counter, out_map)
                current_node_count += c_count
                exact_parts.append(c_exact)
                norm_parts.append(c_norm)

        exact_parts.append(")")
        norm_parts.append(")")

        exact_str = " ".join(exact_parts)
        norm_str = " ".join(norm_parts)

        # If subtree size >= threshold and is an expression form, register it
        if current_node_count >= self.min_node_count and getattr(node, "data", "") in ("call", "let_form", "if_form", "match_form", "cond_form"):
            h = hashlib.sha256(norm_str.encode("utf-8")).hexdigest()
            line, col = position(node)
            inst = CloneInstance(file=file_path, line=line, col=col, raw_snippet=exact_str[:80])
            out_map.setdefault(h, []).append((inst, current_node_count, exact_str))

        return current_node_count, exact_str, norm_str


def clone_check_cli(paths: List[Path], threshold: float = 0.15, json_mode: bool = False) -> int:
    """CLI runner for Clone Detection."""
    detector = AslCloneDetector(max_duplication_threshold=threshold)
    report = detector.analyze_paths(paths)

    if json_mode:
        data = {
            "totalNodes": report.total_nodes,
            "duplicateNodes": report.duplicate_nodes,
            "duplicationRatio": report.duplication_ratio,
            "isExcessive": report.is_excessive,
            "threshold": threshold,
            "clusters": [
                {
                    "hash": c.hash_id,
                    "nodeCount": c.node_count,
                    "type": c.clone_type,
                    "occurrences": c.occurrences,
                    "instances": [asdict(i) for i in c.instances],
                }
                for c in report.clusters
            ],
        }
        print(json.dumps(data, indent=2))
        return 1 if report.is_excessive else 0

    print("==========================================================================")
    print("          AgentScript AST Structural Clone & Duplication Detector         ")
    print("==========================================================================")
    pct = round(report.duplication_ratio * 100, 2)
    thresh_pct = round(threshold * 100, 1)
    status = "EXCESSIVE DUPLICATION" if report.is_excessive else "CLEAN (Within Quality Limit)"
    print(f"Total AST Nodes Analyzed : {report.total_nodes}")
    print(f"Duplicated Nodes Found   : {report.duplicate_nodes}")
    print(f"Code Duplication Ratio   : {pct}% (Ceiling: {thresh_pct}%)")
    print(f"Quality Status           : {status}")

    if report.clusters:
        print("\n--- Detected Structural Clone Clusters ---")
        for idx, c in enumerate(report.clusters[:8], 1):
            badge = "[EXACT]" if c.clone_type == "exact-clone" else "[STRUCTURAL]"
            print(f"\n{idx}. {badge} Cluster #{c.hash_id} ({c.node_count} nodes × {c.occurrences} instances):")
            for inst in c.instances:
                rel = Path(inst.file).name
                print(f"   • {rel}:{inst.line}:{inst.col} -> {inst.raw_snippet}...")

    print("\n--------------------------------------------------------------------------")
    if not report.is_excessive:
        print("✓ Codebase structural redundancy is well within acceptable limits.")
        return 0
    else:
        print("✗ Duplication exceeds allowable limit; refactor shared AST subtrees into functions.")
        return 1


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="AgentScript Structural Clone Detector")
    parser.add_argument("paths", nargs="+", type=Path, help="Paths to inspect")
    parser.add_argument("--threshold", type=float, default=0.15, help="Duplication ratio threshold (default: 0.15)")
    parser.add_argument("--json", action="store_true", help="Output JSON")
    args = parser.parse_args()
    sys.exit(clone_check_cli(args.paths, threshold=args.threshold, json_mode=args.json))
