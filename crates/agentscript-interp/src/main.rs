//! agentscript-interp: the reference interpreter CLI.
//!
//! `agentscript-interp [--root DIR]... SOURCE [args...]` — parse `SOURCE` (and
//! its transitive imports) with the project's own tree-sitter grammar, evaluate
//! the AST directly, and run a module as a program (`main` + argv + exit).
//! Same search order as to_python.py --root and modules.py: the file's own
//! parent first, then each --root.
//!
//! Function mode: `agentscript-interp [--root DIR]... --call NAME SOURCE
//! --arg '<json array>'...` evaluates the top-level `defun` NAME with each
//! `--arg`'s values (one per argument, typed from the declared signature) and
//! prints `[r1,r2,...]` on stdout in the differential harness's canonical JSON.
//! This is the interpreter's arm of differential.py's function mode.
//!
//! Exit codes: 0 for a program that ran (or a module with no main, or a
//! successful call); 1 when `main` failed with an IoError (case name written to
//! stderr); 2 for a parse error, missing module, evaluator internal error, or
//! trap (diagnostic on stderr).

mod ast;
mod builtins;
mod cst;
mod eval;
mod io;
mod modules;
mod num;
mod value;

use crate::ast::{NumericWidth, Param, Type};
use crate::value::Value;
use std::path::{Path, PathBuf};

fn main() {
    let code = run();
    std::process::exit(code);
}

fn run() -> i32 {
    let mut roots: Vec<PathBuf> = vec![];
    let mut positional: Vec<String> = vec![];
    let mut call_name: Option<String> = None;
    let mut call_args: Vec<String> = vec![];
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--root" if i + 1 < args.len() => {
                roots.push(PathBuf::from(&args[i + 1]));
                i += 2;
            }
            "--call" if i + 1 < args.len() => {
                call_name = Some(args[i + 1].clone());
                i += 2;
            }
            "--arg" if i + 1 < args.len() => {
                call_args.push(args[i + 1].clone());
                i += 2;
            }
            _ => {
                positional.push(args[i].clone());
                i += 1;
            }
        }
    }
    if positional.is_empty() {
        eprintln!("usage: agentscript-interp [--root DIR]... [--call NAME [--arg JSON]...] SOURCE [args...]");
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

    let argv_for_interp = if call_name.is_some() { vec![] } else { prog_args.clone() };
    let mut interp = match eval::Interp::new(&program, argv_for_interp) {
        Ok(i) => i,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };

    match call_name {
        Some(name) => run_call(&mut interp, &program, &name, &call_args),
        None => match interp.run_main() {
            Ok(code) => code,
            Err(e) => {
                eprintln!("{}", e);
                2
            }
        },
    }
}

/// A differential argument value, built from the declared parameter type so the
/// integer width the function's own signature pins is preserved.
fn build_arg(ty: &Type, js: &serde_json::Value) -> Result<Value, String> {
    match ty {
        Type::Int32 | Type::Int64 => {
            let n = js.as_i64().ok_or_else(|| format!("{:?} arg: not an Int", ty))?;
            let w = if matches!(ty, Type::Int32) { NumericWidth::I32 } else { NumericWidth::I64 };
            Ok(Value::int(n, w))
        }
        Type::Float64 => {
            let x = js.as_f64().ok_or_else(|| "Float64 arg: not a Float".to_string())?;
            Ok(Value::Float(x))
        }
        Type::Named(n) if n == "String" => {
            let s = js.as_str().ok_or_else(|| "String arg: not a String".to_string())?;
            Ok(Value::Str(s.to_string()))
        }
        Type::Named(n) if n == "Bool" => {
            let b = js.as_bool().ok_or_else(|| "Bool arg: not a Bool".to_string())?;
            Ok(Value::Bool(b))
        }
        other => Err(format!("{:?} is not an admissible differential input type", other)),
    }
}

fn run_call(interp: &mut eval::Interp, program: &ast::Program, name: &str, cases: &[String]) -> i32 {
    let root = program.units.len() - 1;
    let def = match program.units[root].1.find_defun(name) {
        Some(d) => d,
        None => {
            eprintln!("no defun {} in root unit", name);
            return 2;
        }
    };
    if cases.is_empty() {
        eprintln!("--call {} needs at least one --arg", name);
        return 2;
    }
    let mut out: Vec<String> = vec![];
    for case_js in cases {
        let arr: serde_json::Value = match serde_json::from_str(case_js) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("bad --arg json: {}", e);
                return 2;
            }
        };
        let arr = match arr.as_array() {
            Some(a) => a,
            None => {
                eprintln!("--arg must be a JSON array");
                return 2;
            }
        };
        if def.params.len() != arr.len() {
            eprintln!(
                "{}: declared {} param(s), case supplies {}",
                name,
                def.params.len(),
                arr.len()
            );
            return 2;
        }
        let mut vals: Vec<Value> = vec![];
        for (p, v) in def.params.iter().zip(arr.iter()) {
            match build_arg(&p.ty, v) {
                Ok(val) => vals.push(val),
                Err(e) => {
                    eprintln!("{}", e);
                    return 2;
                }
            }
        }
        match interp.call_entry(root, name, vals) {
            Ok(v) => out.push(value::to_json(&v)),
            Err(e) => {
                eprintln!("{}", e);
                return 2;
            }
        }
    }
    println!("[{}]", out.join(","));
    0
}

