//! I/O builtins and the IoError mapping, ported from rt.rs io_err/read_* and
//! runtime.py.
//!
//! The case is chosen from ErrorKind (not raw_os_error), folding
//! NotADirectory | IsADirectory into invalid-path, exactly as rt.rs does. Writes
//! flush. `read-line` returns (some line) without the trailing newline and
//! (none) at EOF.

use crate::eval::Err;
use crate::value::Value;
use std::io::{BufRead, Read, Write};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IoError {
    NotFound,
    PermissionDenied,
    AlreadyExists,
    InvalidPath,
    Interrupted,
    Other,
}

/// The six IoError case names, in declaration order. Single source of truth
/// for the CST prelude seeding (cst.rs) and the evaluator's case resolution
/// (eval.rs).
pub const IO_ERROR_CASES: &[&str] = &[
    "not-found", "permission-denied", "already-exists",
    "invalid-path", "interrupted", "other",
];

impl IoError {
    pub fn case(&self) -> &'static str {
        match self {
            IoError::NotFound => "not-found",
            IoError::PermissionDenied => "permission-denied",
            IoError::AlreadyExists => "already-exists",
            IoError::InvalidPath => "invalid-path",
            IoError::Interrupted => "interrupted",
            IoError::Other => "other",
        }
    }
    pub fn from(e: std::io::Error) -> IoError {
        use std::io::ErrorKind::*;
        match e.kind() {
            NotFound => IoError::NotFound,
            PermissionDenied => IoError::PermissionDenied,
            AlreadyExists => IoError::AlreadyExists,
            NotADirectory | IsADirectory => IoError::InvalidPath,
            Interrupted => IoError::Interrupted,
            _ => IoError::Other,
        }
    }
}

fn err_value(e: IoError) -> Value {
    Value::Tagged("err".to_string(), vec![Value::Tagged(e.case().to_string(), vec![])])
}

fn ok_unit() -> Value {
    Value::Tagged("ok".to_string(), vec![Value::Unit])
}

pub fn read_line() -> Result<Value, Err> {
    let mut s = String::new();
    match std::io::stdin().lock().read_line(&mut s) {
        Ok(0) => Ok(Value::Tagged("ok".to_string(), vec![Value::Tagged("none".to_string(), vec![])])),
        Ok(_) => {
            let line = s.trim_end_matches('\n').to_string();
            Ok(Value::Tagged("ok".to_string(), vec![
                Value::Tagged("some".to_string(), vec![Value::Str(line)])]))
        }
        Err(e) => Ok(err_value(IoError::from(e))),
    }
}

pub fn read_all() -> Result<Value, Err> {
    let mut s = String::new();
    match std::io::stdin().read_to_string(&mut s) {
        Ok(_) => Ok(Value::Tagged("ok".to_string(), vec![Value::Str(s)])),
        Err(e) => Ok(err_value(IoError::from(e))),
    }
}

fn write_to<W: Write>(mut w: W, text: &str, nl: &str) -> Result<Value, Err> {
    let r = w.write_all(format!("{}{}", text, nl).as_bytes()).and_then(|_| w.flush());
    match r {
        Ok(_) => Ok(ok_unit()),
        Err(e) => Ok(err_value(IoError::from(e))),
    }
}

pub fn write_out(text: &str, nl: &str) -> Result<Value, Err> {
    write_to(std::io::stdout(), text, nl)
}
pub fn write_err(text: &str, nl: &str) -> Result<Value, Err> {
    write_to(std::io::stderr(), text, nl)
}

pub fn file_read(path: &str) -> Result<Value, Err> {
    match std::fs::read_to_string(path) {
        Ok(s) => Ok(Value::Tagged("ok".to_string(), vec![Value::Str(s)])),
        Err(e) => Ok(err_value(IoError::from(e))),
    }
}

pub fn file_write(path: &str, text: &str) -> Result<Value, Err> {
    match std::fs::write(path, text) {
        Ok(_) => Ok(ok_unit()),
        Err(e) => Ok(err_value(IoError::from(e))),
    }
}

pub fn file_append(path: &str, text: &str) -> Result<Value, Err> {
    let r = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .and_then(|mut f| f.write_all(text.as_bytes()).and_then(|_| f.flush()));
    match r {
        Ok(_) => Ok(ok_unit()),
        Err(e) => Ok(err_value(IoError::from(e))),
    }
}

pub fn file_exists(path: &str) -> Result<Value, Err> {
    Ok(Value::Tagged("ok".to_string(), vec![Value::Bool(std::path::Path::new(path).exists())]))
}
