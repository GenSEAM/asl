"""Project configuration loader, multi-target builder, and hot-reload file watcher."""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BACKENDS = {
    "ts": "to_typescript.py",
    "rs": "to_rust.py",
    "go": "to_go.py",
    "py": "to_python.py",
    "interp": "agentscript-interp"
}


def load_project_config(dir_path: Path | None = None) -> tuple[Path, dict]:
    """Finds and loads asl.json or asex.json in dir_path or its parents."""
    cur = (dir_path or Path.cwd()).resolve()
    while True:
        for name in ["asl.json", "asex.json"]:
            cand = cur / name
            if cand.is_file():
                try:
                    return cand, json.loads(cand.read_text())
                except Exception as exc:
                    raise ValueError(f"Failed to parse {cand}: {exc}")
        if cur.parent == cur:
            break
        cur = cur.parent
    raise FileNotFoundError("No asl.json or asex.json found in current or parent directories.")


def build_single_target(src_file: Path, target: str, out_file: Path | None = None) -> tuple[bool, str, float]:
    """Builds a source file to a given target. Returns (success, message, duration_ms)."""
    t0 = time.perf_counter()
    src_file = src_file.resolve()
    if not src_file.is_file():
        return False, f"File not found: {src_file}", 0.0

    if target == "wasm":
        import tempfile
        sys.path.insert(0, str(ROOT / "backend"))
        from to_rust import ToRust
        roots = [ROOT / "grammar" / "corpus" / "modules"]
        try:
            rs_src = ToRust().transpile(src_file.read_text(), path=src_file, roots=roots)
            with tempfile.TemporaryDirectory(dir="/tmp") as d:
                (Path(d) / "rt.rs").write_text((ROOT / "backend" / "rust" / "rt.rs").read_text())
                (Path(d) / "main.rs").write_text(rs_src)
                out_wasm = Path(d) / "out.wasm"
                is_prog = "pub fn main_(" in rs_src or "fn main()" in rs_src
                target_flag = ["--target", "wasm32-wasip1"] if is_prog else ["--target", "wasm32-unknown-unknown", "--crate-type=cdylib"]
                c = subprocess.run(["rustup", "run", "stable", "rustc", *target_flag,
                                    "-O", "--edition", "2021", "main.rs", "-o", str(out_wasm)],
                                   cwd=d, capture_output=True, text=True)
                dt = (time.perf_counter() - t0) * 1000.0
                if c.returncode != 0:
                    return False, f"rustc error: {c.stderr.strip()}", dt
                wasm_bytes = out_wasm.read_bytes()
                if out_file:
                    out_file.parent.mkdir(parents=True, exist_ok=True)
                    out_file.write_bytes(wasm_bytes)
                return True, "OK (wasm)", dt
        except Exception as exc:
            dt = (time.perf_counter() - t0) * 1000.0
            return False, str(exc), dt

    if target in ("native-rs", "native"):
        from tools.native_codegen import native_emit_rust
        try:
            rs_src = native_emit_rust(src_file.read_text(), path=src_file)
            dt = (time.perf_counter() - t0) * 1000.0
            if out_file:
                out_file.parent.mkdir(parents=True, exist_ok=True)
                out_file.write_text(rs_src)
            return True, "OK (native-rs)", dt
        except Exception as exc:
            dt = (time.perf_counter() - t0) * 1000.0
            return False, str(exc), dt

    if target in BACKENDS:
        script = ROOT / "backend" / BACKENDS[target]
        run = subprocess.run([sys.executable, str(script), str(src_file),
                             "--root", str(ROOT / "grammar" / "corpus" / "modules")],
                             capture_output=True, text=True)
        dt = (time.perf_counter() - t0) * 1000.0
        if run.returncode == 0:
            if out_file:
                out_file.parent.mkdir(parents=True, exist_ok=True)
                out_file.write_text(run.stdout)
            return True, f"OK ({target})", dt
        return False, run.stderr.strip(), dt

    dt = (time.perf_counter() - t0) * 1000.0
    return False, f"Unknown target: {target}", dt


def build_project(project_dir: Path | None = None) -> tuple[int, list[dict]]:
    """Builds all targets configured in asl.json."""
    config_file, cfg = load_project_config(project_dir)
    base_dir = config_file.parent
    entry_val = cfg.get("entry", "src/main.asl")
    entry = base_dir / entry_val
    if not entry.exists():
        # Fallback between .asl and .agentscript extensions
        alt_ext = ".asl" if entry.suffix == ".agentscript" else ".agentscript"
        alt_path = entry.with_suffix(alt_ext)
        if alt_path.exists():
            entry = alt_path
        elif (base_dir / "src" / "main.asl").exists():
            entry = base_dir / "src" / "main.asl"
        elif (base_dir / "src" / "main.agentscript").exists():
            entry = base_dir / "src" / "main.agentscript"
    targets = cfg.get("targets", ["wasm"])

    results = []
    has_err = False

    if isinstance(targets, list):
        # Legacy list format: ["wasm", "ts"]
        for t in targets:
            out = base_dir / "dist" / f"main.{t}"
            ok, msg, dt = build_single_target(entry, t, out)
            results.append({"target": t, "output": str(out), "ok": ok, "message": msg, "duration_ms": dt})
            if not ok:
                has_err = True
    elif isinstance(targets, dict):
        # Rich object format: {"wasm": {"output": "dist/main.wasm"}, "ts": {...}}
        for t, opt in targets.items():
            out_path = base_dir / opt["output"] if isinstance(opt, dict) and "output" in opt else base_dir / "dist" / f"main.{t}"
            ok, msg, dt = build_single_target(entry, t, out_path)
            results.append({"target": t, "output": str(out_path), "ok": ok, "message": msg, "duration_ms": dt})
            if not ok:
                has_err = True

    return (1 if has_err else 0), results


def get_tree_mtimes(watch_dirs: list[Path]) -> dict[str, float]:
    """Returns dict of filepath -> mtime for all watched files."""
    mtimes = {}
    for d in watch_dirs:
        if d.is_file():
            try:
                mtimes[str(d)] = d.stat().st_mtime
            except OSError:
                pass
        elif d.is_dir():
            for root, _, files in os.walk(d):
                for f in files:
                    if f.endswith((".agentscript", ".asl", ".as", ".json")):
                        p = Path(root) / f
                        try:
                            mtimes[str(p)] = p.stat().st_mtime
                        except OSError:
                            pass
    return mtimes


def watch_project(project_dir: Path | None = None, poll_interval: float = 0.3, max_cycles: int | None = None):
    """Watches source files and recompiles all targets on change."""
    config_file, cfg = load_project_config(project_dir)
    base_dir = config_file.parent
    watch_paths = [base_dir / p for p in cfg.get("watch", ["src", "asl.json", "asex.json"])]
    watch_paths = [p for p in watch_paths if p.exists()]
    if not watch_paths:
        watch_paths = [base_dir / "src"]

    print(f"👀 ASL Watch Mode active for '{cfg.get('name', base_dir.name)}'")
    print(f"   Config:  {config_file}")
    print(f"   Watching: {', '.join(str(p.relative_to(base_dir)) for p in watch_paths)}")
    print("   Press Ctrl+C to exit.\n")

    # Initial build
    code, res = build_project(project_dir)
    now = time.strftime("%H:%M:%S")
    for r in res:
        status = "✓" if r["ok"] else "✗"
        print(f"[{now}] {status} [{r['target']}] -> {r['output']} ({r['duration_ms']:.1f}ms)")

    last_mtimes = get_tree_mtimes(watch_paths)
    cycles = 0

    try:
        while True:
            time.sleep(poll_interval)
            cycles += 1
            if max_cycles and cycles >= max_cycles:
                break
            cur_mtimes = get_tree_mtimes(watch_paths)
            if cur_mtimes != last_mtimes:
                # Changes detected!
                changed = [f for f, mt in cur_mtimes.items() if f not in last_mtimes or last_mtimes[f] != mt]
                last_mtimes = cur_mtimes
                now = time.strftime("%H:%M:%S")
                print(f"\n[{now}] Change detected in {len(changed)} file(s), recompiling...")
                code, res = build_project(project_dir)
                for r in res:
                    status = "✓" if r["ok"] else "✗"
                    print(f"[{now}] {status} [{r['target']}] -> {r['output']} ({r['duration_ms']:.1f}ms)")
    except KeyboardInterrupt:
        print("\nStopped watch mode.")
