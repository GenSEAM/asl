//! AgentScript runtime for the Rust backend.
//!
//! Map lowers to BTreeMap, not HashMap: the language specifies sorted iteration
//! for map-keys/values/pairs, and an unspecified order would make the backends
//! disagree on identical input — which the differential harness would then report
//! as a transpiler defect rather than as the specification gap it is.
#![allow(dead_code, unused_imports)]
use std::collections::BTreeMap;

/// `/` and `mod` are single forms over both integers and floats (§6.1), but Rust
/// has no overloading, so the numeric kind is selected by this trait. The
/// specification says "traps on a zero divisor" without qualifying it to
/// integers, so the float impl traps too — IEEE-754 would otherwise return an
/// infinity here and the backends would silently disagree.
pub trait Num: Copy + PartialEq {
    fn zero() -> Self;
    fn divide(self, b: Self) -> Self;
    fn remainder(self, b: Self) -> Self;
}
impl Num for i64 {
    fn zero() -> Self { 0 }
    fn divide(self, b: Self) -> Self { self.checked_div(b).expect("overflow in division") }
    fn remainder(self, b: Self) -> Self { self % b }
}
impl Num for i32 {
    fn zero() -> Self { 0 }
    fn divide(self, b: Self) -> Self { self.checked_div(b).expect("overflow in division") }
    fn remainder(self, b: Self) -> Self { self % b }
}
impl Num for f64 {
    fn zero() -> Self { 0.0 }
    fn divide(self, b: Self) -> Self { self / b }
    fn remainder(self, b: Self) -> Self { self % b }
}

pub fn div<T: Num>(a: T, b: T) -> T {
    if b == T::zero() { panic!("division by zero") }
    a.divide(b)
}
pub fn rem<T: Num>(a: T, b: T) -> T {
    if b == T::zero() { panic!("modulo by zero") }
    a.remainder(b)
}
pub fn checked_div<T: Num>(a: T, b: T) -> Option<T> {
    if b == T::zero() { None } else { Some(a.divide(b)) }
}
pub fn checked_rem<T: Num>(a: T, b: T) -> Option<T> {
    if b == T::zero() { None } else { Some(a.remainder(b)) }
}

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
// The closure takes T by value, matching every other higher-order builtin: the
// backend emits closures from the declared AgentScript parameter type, which is
// owned. Requiring a reference here made `list-sort-by` uncompilable.
pub fn sort_by<T: Clone, K: Ord, F: Fn(T) -> K>(f: F, mut xs: Vec<T>) -> Vec<T> {
    xs.sort_by_key(|x| f(x.clone()));
    xs
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
// Every effectful operation returns Result<_, String>. A host error that reached
// the caller as a panic would be exactly the invisible failure the boundary
// exists to remove, so io::Error is converted at the boundary and never escapes.

/// Built-in record, so `.-exit-code` needs no special case in the transpiler.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProcessResult {
    pub exit_code: i64,
    pub stdout: String,
    pub stderr: String,
}

fn as_err<T, E: std::fmt::Display>(r: Result<T, E>) -> Result<T, String> {
    r.map_err(|e| e.to_string())
}

pub fn read_line() -> Result<Option<String>, String> {
    use std::io::BufRead;
    let mut buf = String::new();
    let n = as_err(std::io::stdin().lock().read_line(&mut buf))?;
    if n == 0 { return Ok(None) }
    Ok(Some(buf.trim_end_matches('\n').to_string()))
}

pub fn read_all() -> Result<String, String> {
    use std::io::Read;
    let mut buf = String::new();
    as_err(std::io::stdin().read_to_string(&mut buf))?;
    Ok(buf)
}

pub fn print_(s: String) -> Result<(), String> {
    use std::io::Write;
    let mut out = std::io::stdout();
    as_err(out.write_all(s.as_bytes()))?;
    as_err(out.flush())
}

pub fn println(s: String) -> Result<(), String> { print_(s + "\n") }

pub fn eprintln(s: String) -> Result<(), String> {
    use std::io::Write;
    as_err(std::io::stderr().write_all((s + "\n").as_bytes()))
}

pub fn file_read(path: String) -> Result<String, String> {
    as_err(std::fs::read_to_string(path))
}

pub fn file_write(path: String, s: String) -> Result<(), String> {
    as_err(std::fs::write(path, s))
}

pub fn file_exists(path: String) -> bool { std::path::Path::new(&path).exists() }

pub fn env_get(name: String) -> Option<String> { std::env::var(name).ok() }

pub fn args() -> Vec<String> { std::env::args().skip(1).collect() }

/// `argv` is a list, never a shell string, so nothing is re-parsed by a shell
/// and there is no quoting to get wrong.
pub fn process_run(cmd: String, argv: Vec<String>, stdin: String)
    -> Result<ProcessResult, String>
{
    use std::io::Write;
    use std::process::{Command, Stdio};
    let mut child = as_err(Command::new(&cmd)
        .args(&argv)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn())?;
    {
        let pipe = child.stdin.as_mut().ok_or("stdin unavailable")?;
        as_err(pipe.write_all(stdin.as_bytes()))?;
    }
    let out = as_err(child.wait_with_output())?;
    Ok(ProcessResult {
        // A signal-terminated child has no code; -1 is reported rather than
        // trapping, because the language models failure as a value.
        exit_code: out.status.code().unwrap_or(-1) as i64,
        stdout: as_err(String::from_utf8(out.stdout))?,
        stderr: as_err(String::from_utf8(out.stderr))?,
    })
}

/// Report an entry point's `Err` and exit non-zero. Entry-point failure lives in
/// the runtime so generated code never has to name a std path itself.
pub fn fail(message: String) -> ! {
    let _ = eprintln(message);
    std::process::exit(1)
}

// ---------- trapping arithmetic ----------
// §3: for Int32/Int64 "wrapping is an error not a behavior". Rust's `+` traps in
// debug and WRAPS in release, so the specification held only for unoptimised
// builds. Routing through checked_* makes the behaviour a property of the
// language rather than of the build profile.
pub trait Arith: Copy {
    fn plus(self, b: Self) -> Self;
    fn minus(self, b: Self) -> Self;
    fn times(self, b: Self) -> Self;
    fn negate(self) -> Self;
    fn magnitude(self) -> Self;
}
macro_rules! int_arith {
    ($($t:ty),*) => {$(
        impl Arith for $t {
            fn plus(self, b: Self) -> Self { self.checked_add(b).expect("integer overflow") }
            fn minus(self, b: Self) -> Self { self.checked_sub(b).expect("integer overflow") }
            fn times(self, b: Self) -> Self { self.checked_mul(b).expect("integer overflow") }
            fn negate(self) -> Self { self.checked_neg().expect("integer overflow") }
            fn magnitude(self) -> Self { self.checked_abs().expect("integer overflow") }
        }
    )*};
}
int_arith!(i32, i64);
impl Arith for f64 {
    fn plus(self, b: Self) -> Self { self + b }
    fn minus(self, b: Self) -> Self { self - b }
    fn times(self, b: Self) -> Self { self * b }
    fn negate(self) -> Self { -self }
    fn magnitude(self) -> Self { self.abs() }
}

pub fn add<T: Arith>(a: T, b: T) -> T { a.plus(b) }
pub fn sub<T: Arith>(a: T, b: T) -> T { a.minus(b) }
pub fn mul<T: Arith>(a: T, b: T) -> T { a.times(b) }
pub fn neg<T: Arith>(a: T) -> T { a.negate() }
pub fn absv<T: Arith>(a: T) -> T { a.magnitude() }
