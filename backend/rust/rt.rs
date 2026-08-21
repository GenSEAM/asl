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
pub fn sort_by<T, K: Ord, F: Fn(&T) -> K>(f: F, mut xs: Vec<T>) -> Vec<T> {
    xs.sort_by_key(|x| f(x));
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
