//! AgentScript runtime for the Rust backend.
//!
//! Map lowers to BTreeMap, not HashMap: the language specifies sorted iteration
//! for map-keys/values/pairs, and an unspecified order would make the backends
//! disagree on identical input — which the differential harness would then report
//! as a transpiler defect rather than as the specification gap it is.
#![allow(dead_code, unused_imports)]
use std::collections::BTreeMap;

// `N` spans Int32, Int64 and Float64, so a numeric helper fixed to one of them is
// a backend narrower than the language it claims to implement.
//
// Every integer operation goes through a `checked_*` even though debug rustc
// would trap on the bare operator: trapping is what the language specifies, and
// tying it to a compilation profile would make `-O` a different language.
pub trait Num: Copy + PartialEq {
    const ZERO: Self;
    /// `None` when the quotient is not representable, which for two's complement
    /// is `MIN / -1` alone.
    fn quot(self, b: Self) -> Option<Self>;
    fn rest(self, b: Self) -> Self;
    fn plus(self, b: Self) -> Self;
    fn minus(self, b: Self) -> Self;
    fn times(self, b: Self) -> Self;
    fn negate(self) -> Self;
    fn magnitude(self) -> Self;
}

macro_rules! int_num {
    ($t:ty) => {
        impl Num for $t {
            const ZERO: $t = 0;
            fn quot(self, b: $t) -> Option<$t> { self.checked_div(b) }
            // `MIN % -1` is 0, which is representable, so the remainder wraps
            // where the quotient traps.
            fn rest(self, b: $t) -> $t { self.wrapping_rem(b) }
            fn plus(self, b: $t) -> $t { self.checked_add(b).expect("overflow in addition") }
            fn minus(self, b: $t) -> $t { self.checked_sub(b).expect("overflow in subtraction") }
            fn times(self, b: $t) -> $t { self.checked_mul(b).expect("overflow in multiplication") }
            fn negate(self) -> $t { self.checked_neg().expect("overflow in negation") }
            fn magnitude(self) -> $t { self.checked_abs().expect("overflow in absolute value") }
        }
    };
}

int_num!(i32);
int_num!(i64);

impl Num for f64 {
    const ZERO: f64 = 0.0;
    fn quot(self, b: f64) -> Option<f64> { Some(self / b) }
    fn rest(self, b: f64) -> f64 { self % b }
    fn plus(self, b: f64) -> f64 { self + b }
    fn minus(self, b: f64) -> f64 { self - b }
    fn times(self, b: f64) -> f64 { self * b }
    fn negate(self) -> f64 { -self }
    fn magnitude(self) -> f64 { self.abs() }
}

pub fn add<T: Num>(a: T, b: T) -> T { a.plus(b) }
pub fn sub<T: Num>(a: T, b: T) -> T { a.minus(b) }
pub fn mul<T: Num>(a: T, b: T) -> T { a.times(b) }
pub fn neg<T: Num>(a: T) -> T { a.negate() }
pub fn abs<T: Num>(a: T) -> T { a.magnitude() }

pub fn div<T: Num>(a: T, b: T) -> T {
    if b == T::ZERO { panic!("division by zero") }
    a.quot(b).expect("overflow in division")
}
pub fn rem<T: Num>(a: T, b: T) -> T {
    if b == T::ZERO { panic!("modulo by zero") }
    a.rest(b)
}
pub fn checked_div<T: Num>(a: T, b: T) -> Option<T> {
    if b == T::ZERO { None } else { a.quot(b) }
}
pub fn checked_rem<T: Num>(a: T, b: T) -> Option<T> {
    if b == T::ZERO { None } else { Some(a.rest(b)) }
}

/// Holds a NaN somewhere. A value that does is not comparable with *itself*,
/// which finds it without knowing T's shape — and T's shape is not available,
/// because `list-sort` is declared over every type.
fn unordered<T: PartialOrd>(x: &T) -> bool { x.partial_cmp(x).is_none() }

/// The language's sort order: a value holding a NaN sorts after every value that
/// does not, and NaN-holding values tie with one another so a stable sort leaves
/// them in input order.
///
/// The NaN test comes first rather than as a fallback for an incomparable pair,
/// which is what makes this a transitive order: `[0.0, nan]` compares Less than
/// `[0.5]` on its first element while `[nan]` compares Greater, so a rule that
/// asked `partial_cmp` first would sort two values that tie with each other onto
/// opposite sides of a third — and Rust's sort detects that and panics.
fn nan_last<T: PartialOrd>(a: &T, b: &T) -> std::cmp::Ordering {
    use std::cmp::Ordering;
    match (unordered(a), unordered(b)) {
        (true, true) => Ordering::Equal,
        (true, false) => Ordering::Greater,
        (false, true) => Ordering::Less,
        // Neither holds a NaN, so the partial order is total over the two.
        (false, false) => a.partial_cmp(b).expect("incomparable values in a sort"),
    }
}
fn sorts_before<T: PartialOrd>(a: &T, b: &T) -> bool {
    nan_last(a, b) == std::cmp::Ordering::Less
}
// Selection follows the same order as the sort, so `min` is the head of
// `list-sort` and not a separate rule: keep the first unless the second sorts
// strictly before it.
pub fn min<T: PartialOrd>(a: T, b: T) -> T { if sorts_before(&b, &a) { b } else { a } }
pub fn max<T: PartialOrd>(a: T, b: T) -> T { if sorts_before(&a, &b) { b } else { a } }

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
pub fn fmt_f64(x: f64) -> String {
    // string-from-float64 has one meaning, and Rust's Debug spells three things
    // differently from Python's repr: NaN's case, an unsigned exponent, and an
    // exponent under two digits. Everything else already round-trips shortest.
    if x.is_nan() { return "nan".to_string() }
    let s = format!("{:?}", x);
    match s.split_once('e') {
        Some((mantissa, exp)) => {
            let (sign, digits) = match exp.strip_prefix('-') {
                Some(d) => ("-", d),
                None => ("+", exp),
            };
            format!("{}e{}{:0>2}", mantissa, sign, digits)
        }
        None => s,
    }
}
// The width is in the signature, not left to inference: an integer literal with
// nothing else constraining it falls back to i32 in Rust, so `{0}.to_string()`
// and `({0} as f64)` stopped compiling the moment the argument was a literal
// outside i32 — including Int64::MIN, which is a value the language has.
pub fn fmt_i64(n: i64) -> String { n.to_string() }
pub fn i_to_f(n: i64) -> f64 { n as f64 }
pub fn to_i64(s: &str) -> Option<i64> { s.trim().parse().ok() }
pub fn to_f64(s: &str) -> Option<f64> { s.trim().parse().ok() }
pub fn to_i32(n: i64) -> Option<i32> { i32::try_from(n).ok() }
pub fn f_to_i(x: f64) -> Option<i64> {
    // `as` saturates rather than failing, so the range decides before the cast:
    // 1e30 would otherwise answer i64::MAX and call that a conversion. NaN and
    // both infinities fall out of the same two comparisons.
    let t = x.trunc();
    if t >= -9223372036854775808.0 && t < 9223372036854775808.0 {
        Some(t as i64)
    } else {
        None
    }
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
pub fn sort<T: PartialOrd>(mut xs: Vec<T>) -> Vec<T> {
    xs.sort_by(nan_last);
    xs
}
// The language's higher-order arguments take their element by value, so the
// helpers do too: a closure written against `&T` here could never be the same
// closure the source declares.
pub fn sort_by<T: Clone, K: PartialOrd, F: Fn(T) -> K>(mut xs: Vec<T>, f: F) -> Vec<T> {
    xs.sort_by(|a, b| nan_last(&f(a.clone()), &f(b.clone())));
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
pub fn sum<T: Num>(xs: Vec<T>) -> T { xs.into_iter().fold(T::ZERO, Num::plus) }
pub fn least<T: PartialOrd + Clone>(xs: &[T]) -> Option<T> {
    xs.iter().cloned().reduce(|a, b| if sorts_before(&b, &a) { b } else { a })
}
pub fn greatest<T: PartialOrd + Clone>(xs: &[T]) -> Option<T> {
    xs.iter().cloned().reduce(|a, b| if sorts_before(&a, &b) { b } else { a })
}

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
