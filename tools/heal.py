"""Autonomous Self-Healing and Zero-Blocker Repair Engine for ASL."""
import re
from dataclasses import dataclass
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "checker"))
from resolve import check_file, Diagnostic


@dataclass
class PatchSuggestion:
    file: str
    rule: str
    description: str
    diff: str
    applied: bool = False


def heal_file(file_path: Path, apply_fix: bool = True) -> list[PatchSuggestion]:
    """Diagnoses rule violations in an ASL source file and applies deterministic AST repairs."""
    file_path = file_path.resolve()
    if not file_path.is_file():
        return []

    roots = [file_path.parent, ROOT / "grammar" / "corpus" / "valid"]
    diags = check_file(file_path, roots)
    if not diags:
        return []

    content = file_path.read_text()
    patches: list[PatchSuggestion] = []
    updated_content = content

    for d in diags:
        # 1. Rule 13: Unexported types referenced in exported schemas
        # "Rule 13: TypeName in exported field Schema.field is declared here and not exported"
        match_r13 = re.search(r"([A-Z][a-zA-Z0-9_-]*)\s+in exported field\s+[A-Z][a-zA-Z0-9_-]*\.[a-z0-9_-]+\s+is declared here and not exported", d.message)
        if d.code == "rule-13" and match_r13:
            missing_type = match_r13.group(1)
            # Find :export [...]
            export_match = re.search(r":export\s*\[(.*?)\]", updated_content, re.DOTALL)
            if export_match:
                current_exports = export_match.group(1)
                if missing_type not in current_exports:
                    new_exports = f"{current_exports.rstrip()} {missing_type}"
                    new_block = f":export [{new_exports.strip()}]"
                    updated_content = updated_content[:export_match.start()] + new_block + updated_content[export_match.end():]
                    patches.append(PatchSuggestion(
                        file=str(file_path),
                        rule="rule-13",
                        description=f"Auto-exported missing type '{missing_type}' referenced by exported schema",
                        diff=f"+ :export [ ... {missing_type} ]",
                        applied=apply_fix
                    ))

        # 2. Arity issues in binary string concats: s/concat with >2 args -> nested s/concat
        if d.code == "arity" and "s/concat" in d.message:
            # Format and balance
            patches.append(PatchSuggestion(
                file=str(file_path),
                rule="arity",
                description="Nested binary s/concat tree needed for string concatenation",
                diff="s/concat(a, b, c) -> (s/concat a (s/concat b c))",
                applied=False
            ))

    if apply_fix and updated_content != content:
        file_path.write_text(updated_content)

    return patches


def machine_diagnostics_report(file_path: Path) -> dict:
    """Emits zero-ambiguity machine-readable diagnostic schema with actionable fix metadata."""
    file_path = file_path.resolve()
    roots = [file_path.parent, ROOT / "grammar" / "corpus" / "valid"]
    diags = check_file(file_path, roots)
    patches = heal_file(file_path, apply_fix=False)

    return {
        "file": str(file_path),
        "valid": len(diags) == 0,
        "diagnostics_count": len(diags),
        "diagnostics": [
            {
                "code": d.code,
                "message": d.message,
                "line": d.line,
                "col": d.col,
                "severity": "error"
            }
            for d in diags
        ],
        "repair_recipes": [
            {
                "rule": p.rule,
                "description": p.description,
                "suggested_diff": p.diff
            }
            for p in patches
        ]
    }
