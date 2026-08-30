//! Pure value-shaping helpers shared by the evaluator's builtin dispatch.
//! No closures, no evaluation; everything here maps values to values.

use crate::value::{MapKey, Value};
use std::collections::BTreeMap;

pub fn str_chars_vec(s: &str) -> Vec<Value> {
    s.chars().map(|c| Value::Str(c.to_string())).collect()
}

/// `string-slice`: half-open char slice, or none when out of range.
pub fn str_slice(s: &str, a: i64, b: i64) -> Value {
    let n = s.chars().count() as i64;
    if a < 0 || b < a || b > n {
        return Value::Tagged("none".to_string(), vec![]);
    }
    let out: String = s.chars().skip(a as usize).take((b - a) as usize).collect();
    Value::Tagged("some".to_string(), vec![Value::Str(out)])
}

pub fn str_index_of(s: &str, sub: &str) -> Value {
    match s.find(sub) {
        Some(byte) => {
            let idx = s[..byte].chars().count() as i64;
            Value::Tagged("some".to_string(), vec![Value::int(idx, crate::ast::NumericWidth::I64)])
        }
        None => Value::Tagged("none".to_string(), vec![]),
    }
}

pub fn list_slice(xs: &[Value], a: i64, b: i64) -> Value {
    let n = xs.len() as i64;
    if a < 0 || b < a || b > n {
        return Value::Tagged("none".to_string(), vec![]);
    }
    Value::Tagged("some".to_string(), vec![Value::List(xs[a as usize..b as usize].to_vec())])
}

pub fn at(xs: &[Value], i: i64) -> Value {
    if i < 0 {
        return Value::Tagged("none".to_string(), vec![]);
    }
    match xs.get(i as usize) {
        Some(v) => Value::Tagged("some".to_string(), vec![v.clone()]),
        None => Value::Tagged("none".to_string(), vec![]),
    }
}

pub fn tail(xs: &[Value]) -> Value {
    if xs.is_empty() {
        Value::Tagged("none".to_string(), vec![])
    } else {
        Value::Tagged("some".to_string(), vec![Value::List(xs[1..].to_vec())])
    }
}

pub fn m_get(m: &BTreeMap<MapKey, Value>, k: &MapKey) -> Value {
    match m.get(k) {
        Some(v) => Value::Tagged("some".to_string(), vec![v.clone()]),
        None => Value::Tagged("none".to_string(), vec![]),
    }
}

pub fn m_set(m: &BTreeMap<MapKey, Value>, k: MapKey, v: Value) -> BTreeMap<MapKey, Value> {
    let mut out = m.clone();
    out.insert(k, v);
    out
}

pub fn m_del(m: &BTreeMap<MapKey, Value>, k: &MapKey) -> BTreeMap<MapKey, Value> {
    let mut out = m.clone();
    out.remove(k);
    out
}

pub fn m_from(ps: &[Value]) -> Result<BTreeMap<MapKey, Value>, String> {
    let mut out = BTreeMap::new();
    for p in ps {
        match p {
            Value::Tagged(t, args) if t == "pair" && args.len() == 2 => {
                match MapKey::from_value(&args[0]) {
                    Some(k) => {
                        out.insert(k, args[1].clone());
                    }
                    None => return Err("map key is not orderable".to_string()),
                }
            }
            _ => return Err("map-from-pairs: not a pair".to_string()),
        }
    }
    Ok(out)
}
