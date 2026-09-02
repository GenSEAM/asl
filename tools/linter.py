#!/usr/bin/env python3
"""AgentScript Structural Anti-Pattern, Code Smell, and Quality Linter.

Executes quality inspection rules defined in `packages/asl-lint/src/core/lint.asl`.
"""
import sys
import json
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Optional, Tuple, Set

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "grammar"))
sys.path.insert(0, str(ROOT / "checker"))

from parse import parse_file, parse_text, kids, position, tok
from lark import Tree, Token


@dataclass
class LintSmell:
    code: str
    severity: str  # "error" | "warning" | "info"
    file: str
    line: int
    col: int
    message: str
    can_autofix: bool = False


@dataclass
class QualityReport:
    file: str
    total_nodes: int
    max_nesting: int
    error_count: int
    warning_count: int
    score: int
    smells: List[LintSmell]

    @property
    def should_block(self) -> bool:
        return self.error_count > 0 or self.score < 70


def calculate_quality_score(errors: int, warnings: int) -> int:
    """Exact calculation matching packages/asl-lint/src/core/lint.asl."""
    penalty = (errors * 25) + (warnings * 5)
    return 0 if penalty >= 100 else 100 - penalty


class AslLinter:
    def __init__(self, max_allowed_nesting: int = 5):
        self.max_allowed_nesting = max_allowed_nesting

    def lint_file(self, file_path: Path) -> QualityReport:
        content = file_path.read_text()
        tree = parse_file(file_path)
        return self.lint_tree(tree, file_path.name, str(file_path))

    def lint_source(self, source: str, file_name: str = "<stdin>") -> QualityReport:
        tree = parse_text(source)
        return self.lint_tree(tree, file_name, file_name)

    def lint_tree(self, tree: Tree, file_name: str, file_path: str) -> QualityReport:
        smells: List[LintSmell] = []
        node_count = [0]
        max_nesting = [0]

        self._walk_and_check(tree, file_path, smells, node_count, current_nesting=0, max_nesting=max_nesting)

        errors = sum(1 for s in smells if s.severity == "error")
        warnings = sum(1 for s in smells if s.severity == "warning")
        score = calculate_quality_score(errors, warnings)

        return QualityReport(
            file=file_path,
            total_nodes=node_count[0],
            max_nesting=max_nesting[0],
            error_count=errors,
            warning_count=warnings,
            score=score,
            smells=smells,
        )

    def _walk_and_check(
        self,
        node,
        file_path: str,
        smells: List[LintSmell],
        node_count: List[int],
        current_nesting: int,
        max_nesting: List[int],
    ):
        if not isinstance(node, Tree):
            return

        node_count[0] += 1
        data = getattr(node, "data", "")

        # Track cognitive nesting for compound forms
        is_compound = data in ("if_form", "cond_form", "match_form", "let_form", "fn_form")
        new_nesting = current_nesting + (1 if is_compound else 0)
        if new_nesting > max_nesting[0]:
            max_nesting[0] = new_nesting

        line, col = position(node)

        # 1. Excessive cognitive nesting smell
        if is_compound and new_nesting > self.max_allowed_nesting:
            smells.append(
                LintSmell(
                    code="excessive-nesting",
                    severity="warning",
                    file=file_path,
                    line=line,
                    col=col,
                    message=f"Cognitive nesting depth ({new_nesting}) exceeds threshold ({self.max_allowed_nesting})",
                    can_autofix=False,
                )
            )

        # 2. Match form smells: duplicate arms & dead branches
        if data == "match_form":
            self._check_match(node, file_path, smells)

        # 3. Let form smells: unused bindings
        if data == "let_form":
            self._check_let(node, file_path, smells)

        for child in node.children:
            if isinstance(child, Tree):
                self._walk_and_check(child, file_path, smells, node_count, new_nesting, max_nesting)

    def _check_match(self, match_node: Tree, file_path: str, smells: List[LintSmell]):
        arms = [c for c in match_node.children if isinstance(c, Tree) and getattr(c, "data", "") == "match_arm"]
        if not arms:
            return

        wildcard_seen_idx = -1
        arm_bodies: List[Tuple[str, int, int]] = []

        for idx, arm in enumerate(arms):
            line, col = position(arm)
            arm_kids = [k for k in arm.children if isinstance(k, Tree)]
            if len(arm_kids) >= 2:
                pat, body = arm_kids[0], arm_kids[1]
                pat_str = self._tree_to_compact_str(pat).strip()
                body_str = self._tree_to_compact_str(body).strip()

                # Check if this arm is a wildcard
                if pat_str == "_" and wildcard_seen_idx == -1:
                    wildcard_seen_idx = idx

                # Exclude simple literal constants or single identifier returns (standard for enum mappings in ASL)
                if not self._is_simple_leaf(body):
                    arm_bodies.append((body_str, line, col))

        # Check for dead branch (any arm following a wildcard)
        if wildcard_seen_idx != -1 and wildcard_seen_idx < len(arms) - 1:
            dead_arm = arms[wildcard_seen_idx + 1]
            d_line, d_col = position(dead_arm)
            smells.append(
                LintSmell(
                    code="dead-branch",
                    severity="error",
                    file=file_path,
                    line=d_line,
                    col=d_col,
                    message="Pattern match branch is unreachable because a preceding arm matched all cases with wildcard '_'",
                    can_autofix=False,
                )
            )

        # Check for duplicate match arm bodies
        seen_bodies: dict[str, Tuple[int, int]] = {}
        for b_str, l, c in arm_bodies:
            # Only flag non-trivial bodies (length > 3)
            if len(b_str) > 3 and b_str in seen_bodies:
                prev_line, _ = seen_bodies[b_str]
                smells.append(
                    LintSmell(
                        code="duplicate-match-arm",
                        severity="warning",
                        file=file_path,
                        line=l,
                        col=c,
                        message=f"Duplicate match arm body (identical to branch at line {prev_line})",
                        can_autofix=True,
                    )
                )
            else:
                seen_bodies[b_str] = (l, c)

    def _check_let(self, let_node: Tree, file_path: str, smells: List[LintSmell]):
        bindings = [c for c in let_node.children if isinstance(c, Tree) and getattr(c, "data", "") == "binding"]
        body_exprs = [c for c in let_node.children if isinstance(c, Tree) and getattr(c, "data", "") != "binding"]

        declared_names: List[Tuple[str, int, int]] = []
        for b in bindings:
            if b.children:
                var_token = b.children[0]
                var_name = str(var_token)
                line, col = position(var_token)
                if not (var_name.startswith("_") or var_name.startswith("unused-")):
                    declared_names.append((var_name, line, col))

        referenced_identifiers: Set[str] = set()
        for b in bindings:
            if len(b.children) > 1:
                for val_tree in b.children[1:]:
                    self._collect_identifiers(val_tree, referenced_identifiers)
        for body in body_exprs:
            self._collect_identifiers(body, referenced_identifiers)

        for name, line, col in declared_names:
            if name not in referenced_identifiers:
                smells.append(
                    LintSmell(
                        code="unused-binding",
                        severity="warning",
                        file=file_path,
                        line=line,
                        col=col,
                        message=f"Unused variable binding '{name}'; prefix with 'unused-' if deliberately unused",
                        can_autofix=True,
                    )
                )

    def _collect_identifiers(self, node, out_set: Set[str]):
        if isinstance(node, Token):
            out_set.add(str(node))
            return
        if isinstance(node, Tree):
            for child in node.children:
                self._collect_identifiers(child, out_set)

    def _is_simple_leaf(self, node) -> bool:
        if isinstance(node, Token):
            return True
        if isinstance(node, Tree):
            if getattr(node, "data", "") in ("literal", "var", "ident"):
                return True
            if getattr(node, "data", "") == "call":
                head_str = self._tree_to_compact_str(node.children[0]).strip() if node.children else ""
                if head_str in ("+", "-", "*", "/", "mod"):
                    return False
                has_nested_calls = any(isinstance(c, Tree) and getattr(c, "data", "") in ("call", "let_form", "match_form", "if_form") for c in node.children)
                if not has_nested_calls:
                    return True
            kids = [k for k in node.children if not (isinstance(k, Token) and k.type in ("LPAR", "RPAR"))]
            if len(kids) == 1:
                return self._is_simple_leaf(kids[0])
        return False

    def _tree_to_compact_str(self, node) -> str:
        if isinstance(node, Token):
            return str(node)
        return " ".join(self._tree_to_compact_str(c) for c in node.children if c is not None)


def lint_paths(paths: List[Path], json_mode: bool = False) -> int:
    """CLI runner for ASL Linter."""
    linter = AslLinter()
    all_reports: List[QualityReport] = []
    total_smells = 0
    total_errors = 0

    asl_files: List[Path] = []
    for p in paths:
        p = p.resolve()
        if p.is_file() and p.suffix in (".asl", ".agentscript"):
            asl_files.append(p)
        elif p.is_dir():
            asl_files.extend(list(p.rglob("*.asl")) + list(p.rglob("*.agentscript")))

    if not asl_files:
        print("No ASL source files found.")
        return 0

    for f in sorted(asl_files):
        try:
            report = linter.lint_file(f)
            all_reports.append(report)
            total_smells += len(report.smells)
            total_errors += report.error_count
        except Exception as e:
            err_smell = LintSmell(code="parse-error", severity="error", file=str(f), line=1, col=1, message=str(e))
            all_reports.append(QualityReport(str(f), 0, 0, 1, 0, 0, [err_smell]))
            total_errors += 1

    if json_mode:
        data = [
            {
                "file": r.file,
                "score": r.score,
                "errorCount": r.error_count,
                "warningCount": r.warning_count,
                "maxNesting": r.max_nesting,
                "smells": [asdict(s) for s in r.smells],
            }
            for r in all_reports
        ]
        print(json.dumps(data, indent=2))
        return 1 if total_errors > 0 else 0

    print("==========================================================================")
    print("           AgentScript Structural Quality & Anti-Pattern Linter           ")
    print("==========================================================================")

    for r in all_reports:
        rel = Path(r.file).name
        status = "FAIL" if r.should_block else "PASS"
        print(f"\n[{status}] {rel} — Quality Score: {r.score}/100 (Errors: {r.error_count}, Warnings: {r.warning_count}, Nesting: {r.max_nesting})")
        for s in r.smells:
            sev_badge = "[ERROR]" if s.severity == "error" else "[WARN]"
            fix_badge = " [auto-fixable]" if s.can_autofix else ""
            print(f"  {sev_badge} {r.file}:{s.line}:{s.col} [{s.code}] {s.message}{fix_badge}")

    print("\n--------------------------------------------------------------------------")
    if total_errors == 0:
        print(f"✓ ALL {len(all_reports)} FILES PASSED QUALITY LINT (0 Blocking Errors)")
        return 0
    else:
        print(f"✗ QUALITY LINT FAILED: {total_errors} Blocking Error(s) Detected")
        return 1


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="AgentScript Structural Quality Linter")
    parser.add_argument("paths", nargs="+", type=Path, help="Paths or directories to lint")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON")
    args = parser.parse_args()
    sys.exit(lint_paths(args.paths, json_mode=args.json))
