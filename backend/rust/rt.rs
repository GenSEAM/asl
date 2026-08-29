//! AgentS runtime for the Rust backend.
//!
//! Map lowers to BTreeMap, not HashMap: the language specifies sorted iteration
//! for map-keys/values/pairs, and an unspecified order would make the backends
//! disagree on identical input — which the differential harness would then report
//! as a transpiler defect rather than as the specification gap it is.
#![allow(dead_code, unused_imports)]
use std::collections::BTreeMap;

pub fn div(a: i64, b: i64) -> i64 {
    if b == 0 { panic!("division by zero") }
    a.checked_div(b).expect("overflow in division")
}
pub fn rem(a: i64, b: i64) -> i64 {
    if b == 0 { panic!("modulo by zero") }
    a % b
}
pub fn checked_div(a: i64, b: i64) -> Option<i64> { if b == 0 { None } else { Some(a / b) } }
pub fn checked_rem(a: i64, b: i64) -> Option<i64> { if b == 0 { None } else { Some(a % b) } }

pub fn str_len(s: &str) -> i64 { s.chars().count() as i64 }
pub fn concat(parts: &[String]) -> String { parts.concat() }
pub fn chars(s: &str) -> Vec<String> { s.chars().map(|c| c.to_string()).collect() }
pub fn str_rev(s: &str) -> String { s.chars().rev().collect() }
pub fn split(s: &str, sep: &str) -> Vec<String> {
    s.split(sep).map(|x| x.to_string()).collect()
}
pub fn str_slice(s: &str, a: i64, b: i64) -> Option<String> {
    let n = s.chars().count() as i64;
    if a < 0 || b < a || b > n { return None }
    Some(s.chars().skip(a as usize).take((b - a) as usize).collect())
}
pub fn str_index_of(s: &str, sub: &str) -> Option<i64> {
    s.find(sub).map(|byte| s[..byte].chars().count() as i64)
}
pub fn fmt_f64(x: f64) -> String { format!("{:?}", x) }
pub fn to_i64(s: &str) -> Option<i64> { s.trim().parse().ok() }
pub fn to_f64(s: &str) -> Option<f64> { s.trim().parse().ok() }
pub fn to_i32(n: i64) -> Option<i32> { i32::try_from(n).ok() }
pub fn f_to_i(x: f64) -> Option<i64> {
    if x.is_nan() || x.is_infinite() { None } else { Some(x.trunc() as i64) }
}

pub fn at<T: Clone>(xs: &[T], i: i64) -> Option<T> {
    if i < 0 { return None }
    xs.get(i as usize).cloned()
}
pub fn tail<T: Clone>(xs: &[T]) -> Option<Vec<T>> {
    if xs.is_empty() { None } else { Some(xs[1..].to_vec()) }
}
pub fn cons<T>(x: T, xs: Vec<T>) -> Vec<T> {
    let mut v = vec![x];
    v.extend(xs);
    v
}
pub fn append<T>(mut a: Vec<T>, b: Vec<T>) -> Vec<T> { a.extend(b); a }
pub fn rev<T>(mut xs: Vec<T>) -> Vec<T> { xs.reverse(); xs }
pub fn list_slice<T: Clone>(xs: &[T], a: i64, b: i64) -> Option<Vec<T>> {
    let n = xs.len() as i64;
    if a < 0 || b < a || b > n { return None }
    Some(xs[a as usize..b as usize].to_vec())
}
pub fn index_of<T: PartialEq>(xs: &[T], x: &T) -> Option<i64> {
    xs.iter().position(|y| y == x).map(|i| i as i64)
}
pub fn sort<T: Ord>(mut xs: Vec<T>) -> Vec<T> { xs.sort(); xs }
// The language's higher-order arguments take their element by value, so the
// helpers do too: a closure written against `&T` here could never be the same
// closure the source declares.
pub fn sort_by<T: Clone, K: Ord, F: Fn(T) -> K>(mut xs: Vec<T>, f: F) -> Vec<T> {
    xs.sort_by_key(|x| f(x.clone()));
    xs
}
// Passing the predicate to a generic function, rather than invoking a closure
// literal inline, is what lets rustc infer an elided parameter type: the bound
// supplies the expected signature the same way the checker's does.
pub fn filter<T: Clone, F: Fn(T) -> bool>(xs: Vec<T>, f: F) -> Vec<T> {
    xs.into_iter().filter(|x| f(x.clone())).collect()
}
pub fn range(a: i64, b: i64) -> Vec<i64> { if a >= b { vec![] } else { (a..b).collect() } }
pub fn zip<A, B>(a: Vec<A>, b: Vec<B>) -> Vec<(A, B)> { a.into_iter().zip(b).collect() }
pub fn sum(xs: Vec<i64>) -> i64 { xs.iter().sum() }
pub fn least<T: Ord + Clone>(xs: &[T]) -> Option<T> { xs.iter().min().cloned() }
pub fn greatest<T: Ord + Clone>(xs: &[T]) -> Option<T> { xs.iter().max().cloned() }

pub fn m_get<K: Ord, V: Clone>(m: &BTreeMap<K, V>, k: &K) -> Option<V> { m.get(k).cloned() }
pub fn m_set<K: Ord, V>(mut m: BTreeMap<K, V>, k: K, v: V) -> BTreeMap<K, V> {
    m.insert(k, v);
    m
}
pub fn m_del<K: Ord, V>(mut m: BTreeMap<K, V>, k: &K) -> BTreeMap<K, V> { m.remove(k); m }
pub fn m_pairs<K: Ord + Clone, V: Clone>(m: &BTreeMap<K, V>) -> Vec<(K, V)> {
    m.iter().map(|(k, v)| (k.clone(), v.clone())).collect()
}
pub fn m_from<K: Ord, V>(ps: Vec<(K, V)>) -> BTreeMap<K, V> { ps.into_iter().collect() }

// ---------- I/O ----------
// The case is chosen from errno where one exists, and from ErrorKind otherwise,
// because the Python runtime reaches its case from errno and the two have to
// agree for the same condition. The differential gate compares them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IoError {
    NotFound,
    PermissionDenied,
    AlreadyExists,
    InvalidPath,
    Interrupted,
    Other,
}

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
}

fn io_err(e: std::io::Error) -> IoError {
    match e.raw_os_error() {
        Some(2) => IoError::NotFound,
        Some(13) => IoError::PermissionDenied,
        Some(17) => IoError::AlreadyExists,
        Some(20) | Some(21) => IoError::InvalidPath,
        Some(4) => IoError::Interrupted,
        _ => match e.kind() {
            std::io::ErrorKind::NotFound => IoError::NotFound,
            std::io::ErrorKind::PermissionDenied => IoError::PermissionDenied,
            std::io::ErrorKind::AlreadyExists => IoError::AlreadyExists,
            std::io::ErrorKind::Interrupted => IoError::Interrupted,
            _ => IoError::Other,
        },
    }
}

pub fn read_line() -> Result<Option<String>, IoError> {
    let mut s = String::new();
    match std::io::BufRead::read_line(&mut std::io::stdin().lock(), &mut s) {
        Ok(0) => Ok(None),
        Ok(_) => Ok(Some(s.trim_end_matches('\n').to_string())),
        Err(e) => Err(io_err(e)),
    }
}

pub fn read_all() -> Result<String, IoError> {
    let mut s = String::new();
    std::io::Read::read_to_string(&mut std::io::stdin(), &mut s)
        .map(|_| s)
        .map_err(io_err)
}

fn write_to<W: std::io::Write>(mut w: W, text: &str) -> Result<(), IoError> {
    w.write_all(text.as_bytes()).map_err(io_err)?;
    w.flush().map_err(io_err)
}

pub fn print_out(s: &str) -> Result<(), IoError> { write_to(std::io::stdout(), s) }
pub fn println(s: &str) -> Result<(), IoError> { write_to(std::io::stdout(), &format!("{}\n", s)) }
pub fn eprintln(s: &str) -> Result<(), IoError> { write_to(std::io::stderr(), &format!("{}\n", s)) }

pub fn file_read(path: &str) -> Result<String, IoError> {
    std::fs::read_to_string(path).map_err(io_err)
}

pub fn file_write(path: &str, text: &str) -> Result<(), IoError> {
    std::fs::write(path, text).map_err(io_err)
}

pub fn file_append(path: &str, text: &str) -> Result<(), IoError> {
    let mut f = std::fs::OpenOptions::new()
        .create(true).append(true).open(path).map_err(io_err)?;
    write_to(&mut f, text)
}

pub fn file_exists(path: &str) -> Result<bool, IoError> {
    Ok(std::path::Path::new(path).exists())
}

/// Host entry glue: a program's Result becomes its exit status. `err` prints the
/// case name, which is the only part of a failure the language defines.
pub fn main_exit(r: Result<(), IoError>) -> i32 {
    match r {
        Ok(()) => 0,
        Err(e) => { let _ = eprintln(e.case()); 1 }
    }
}
