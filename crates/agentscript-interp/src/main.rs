//! agentscript-interp: the reference interpreter CLI.
//!
//! `agentscript-interp [--root DIR]... SOURCE [args...]` — parse `SOURCE` (and
//! its transitive imports) with the project's own tree-sitter grammar, evaluate
//! the AST directly, and run a module as a program (`main` + argv + exit).
//! Same search order as to_python.py --root and modules.py: the file's own
//! parent first, then each --root.
//!
//! Exit codes: 0 for a program that ran (or a module with no main); 1 when
//! `main` failed with an IoError (case name written to stderr); 2 for a parse
//! error, missing module, evaluator internal error, or trap (diagnostic on
//! stderr).

mod ast;
mod builtins;
mod cst;
mod eval;
mod io;
mod modules;
mod num;
mod value;

use std::path::{Path, PathBuf};

fn main() {
    let code = run();
    std::process::exit(code);
}

fn run() -> i32 {
    let mut roots: Vec<PathBuf> = vec![];
    let mut positional: Vec<String> = vec![];
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--root" && i + 1 < args.len() {
            roots.push(PathBuf::from(&args[i + 1]));
            i += 2;
        } else {
            positional.push(args[i].clone());
            i += 1;
        }
    }
    if positional.is_empty() {
        eprintln!("usage: agentscript-interp [--root DIR]... SOURCE [args...]");
        return 2;
    }
    let source = PathBuf::from(&positional[0]);
    let prog_args = positional[1..].to_vec();

    let src = match std::fs::read_to_string(&source) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{}: unable to read source: {}", source.display(), e);
            return 2;
        }
    };

    // Syntax-check the root file once and reuse the same parse for the load.
    let tree = match modules::checked_parse(&src, &source.display().to_string()) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };

    let loader = modules::Loader::new(roots);
    let program = match loader.resolve(&source, &tree, &src) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("load error: {}", e);
            return 2;
        }
    };

    let mut interp = match eval::Interp::new(&program, prog_args) {
        Ok(i) => i,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };

    match interp.run_main() {
        Ok(code) => code,
        Err(e) => {
            eprintln!("{}", e);
            2
        }
    }
}
