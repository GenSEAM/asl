//! Builds the generated AgentScript tree-sitter parser.
//!
//! The grammar's `src/` is gitignored: it is regenerated from grammar.js by the
//! tree-sitter CLI (a repo dev-dependency, shelled to by validate.py). This
//! build step copies that generated `src/` into OUT_DIR, compiles parser.c with
//! cc, and regenerates it if it is missing or older than grammar.js.
//!
//! `src/` and grammar.js are the normative pair: a stale parser.c silently
//! enforces an older language, so the regeneration check here mirrors what
//! validate.py shells out to. Node is required; a build without it fails loudly
//! rather than silently using a stale parser.
use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::SystemTime;

fn mtime(p: &Path) -> Option<SystemTime> {
    std::fs::metadata(p).ok()?.modified().ok()
}

fn grammar_root() -> PathBuf {
    // workspace root: build.rs lives in crates/agentscript-ts/ and the grammar
    // is two levels up.
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join("grammar")
        .join("tree-sitter-agentscript")
}

fn main() {
    let root = grammar_root();
    let src = root.join("src");
    let grammar_js = root.join("grammar.js");

    let parser_c = src.join("parser.c");
    let grammar_time = mtime(&grammar_js);
    let parser_time = mtime(&parser_c);
    let needs_regenerate = !parser_c.exists()
        || (grammar_time.is_some()
            && parser_time.is_some()
            && grammar_time.unwrap() > parser_time.unwrap());

    if needs_regenerate {
        let cli = env::var("TREE_SITTER_CLI")
            .unwrap_or_else(|_| "node_modules/.bin/tree-sitter".to_string());
        let status = Command::new(cli)
            .arg("generate")
            .current_dir(&root)
            .status()
            .expect("failed to spawn tree-sitter CLI (is node installed?)");
        assert!(status.success(), "tree-sitter generate failed");
    }

    let generated_src = Path::new(&env::var("OUT_DIR").unwrap()).join("ts-src");
    let _ = std::fs::remove_dir_all(&generated_src);
    std::fs::create_dir_all(generated_src.join("tree_sitter")).unwrap();
    std::fs::copy(src.join("parser.c"), generated_src.join("parser.c")).unwrap();
    for entry in std::fs::read_dir(src.join("tree_sitter")).unwrap() {
        let name = entry.unwrap().file_name();
        std::fs::copy(src.join("tree_sitter").join(&name),
                      generated_src.join("tree_sitter").join(&name)).unwrap();
    }

    cc::Build::new()
        .file(generated_src.join("parser.c"))
        .include(&generated_src)
        .warnings(false)
        .compile("agentscript_parser");

    println!("cargo:rerun-if-changed={}", grammar_js.display());
}
