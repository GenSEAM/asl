//! The dynamic value model.
//!
//! Everything the language can hold. Int32/Int64 are width-tagged so an Int32
//! input stays Int32 across arithmetic; records are an ordered field map; a Map
//! is a BTreeMap keyed with the language order (codepoint order for strings);
//! enum values are tagged by bare case name.

use crate::ast::{Expr, FnLit, NumericWidth, Param};
use std::collections::BTreeMap;

/// A callable value: a defun, a lambda with its captured lexicain environment,
/// or an enum-case constructor.
#[derive(Debug, Clone)]
pub enum Callable {
    Defun { unit: usize, name: String },
    Lambda(Lambda),
    Case(String),
}

#[derive(Debug, Clone)]
pub struct Lambda {
    pub params: Vec<Param>,
    pub body: Vec<Expr>,
    /// lexical environment captured at definition
    pub captured: Vec<BTreeMap<String, Value>>,
}

#[derive(Debug, Clone)]
pub enum Value {
    Bool(bool),
    Int { v: i64, w: NumericWidth },
    Float(f64),
    Str(String),
    Unit,
    /// Tagged union value: bare case name + payloads (Option/Result/Pair/user).
    Tagged(String, Vec<Value>),
    List(Vec<Value>),
    /// Record: field name -> value, in field order.
    Record(Vec<(String, Value)>),
    Map(BTreeMap<MapKey, Value>),
    Closure(Callable),
}

/// A map key with the language's total order. Only orderable types are legal
/// keys (the checker's map-key-order rule enforces it); Float64 is refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MapKey {
    S(String),
    I(i64),
    B(bool),
    L(Vec<MapKey>),
}

impl MapKey {
    pub fn from_value(v: &Value) -> Option<MapKey> {
        match v {
            Value::Str(s) => Some(MapKey::S(s.clone())),
            Value::Int { v, .. } => Some(MapKey::I(*v)),
            Value::Bool(b) => Some(MapKey::B(*b)),
            Value::List(xs) => {
                let mut ks = vec![];
                for x in xs {
                    ks.push(MapKey::from_value(x)?);
                }
                Some(MapKey::L(ks))
            }
            _ => None, // includes Float64 and all user/enum/record shapes
        }
    }

    /// Stable cross-type ordering for the total order (S < I < B < L).
    fn rank(&self) -> u8 {
        match self {
            MapKey::S(_) => 0,
            MapKey::I(_) => 1,
            MapKey::B(_) => 2,
            MapKey::L(_) => 3,
        }
    }
}

impl Ord for MapKey {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        match (self, other) {
            (MapKey::S(a), MapKey::S(b)) => a.cmp(b), // codepoint order
            (MapKey::I(a), MapKey::I(b)) => a.cmp(b),
            (MapKey::B(a), MapKey::B(b)) => a.cmp(b),
            (MapKey::L(a), MapKey::L(b)) => a.cmp(b),
            (a, b) => a.rank().cmp(&b.rank()),
        }
    }
}
impl PartialOrd for MapKey {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Value {
    pub fn int(v: i64, w: NumericWidth) -> Value {
        Value::Int { v, w }
    }
    /// Holds a NaN somewhere: Float itself, or any container containing one.
    pub fn is_nan_holding(&self) -> bool {
        match self {
            Value::Float(x) => x.is_nan(),
            Value::List(xs) => xs.iter().any(|x| x.is_nan_holding()),
            Value::Record(fs) => fs.iter().any(|(_, v)| v.is_nan_holding()),
            Value::Map(m) => m.values().any(|v| v.is_nan_holding()),
            Value::Tagged(_, ps) => ps.iter().any(|p| p.is_nan_holding()),
            _ => false,
        }
    }
}

/// Structural equality: NaN != NaN even inside containers (runtime.py eq).
pub fn eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Int { v: x, .. }, Value::Int { v: y, .. }) => x == y,
        (Value::Float(x), Value::Float(y)) => x == y,
        (Value::Str(x), Value::Str(y)) => x == y,
        (Value::Unit, Value::Unit) => true,
        (Value::Tagged(t1, a1), Value::Tagged(t2, a2)) => t1 == t2 && eq_lists(a1, a2),
        (Value::List(a), Value::List(b)) => eq_lists(a, b),
        (Value::Record(a), Value::Record(b)) => {
            a.len() == b.len()
                && a.iter().zip(b.iter()).all(|((n1, v1), (n2, v2))| n1 == n2 && eq(v1, v2))
        }
        (Value::Map(a), Value::Map(b)) => {
            a.len() == b.len() && a.iter().all(|(k, v)| b.get(k).map(|w| eq(v, w)).unwrap_or(false))
        }
        (Value::Closure(_), Value::Closure(_)) => false,
        _ => false,
    }
}

pub fn eq_lists(a: &[Value], b: &[Value]) -> bool {
    a.len() == b.len() && a.iter().zip(b.iter()).all(|(x, y)| eq(x, y))
}

fn esc_json(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// A JSON object key is always a string, so a non-String key (an Int or Bool
/// map key) is quoted the same way json.dumps quotes one on the Python side.
fn as_key(encoded: &str) -> String {
    if encoded.starts_with('"') { encoded.to_string() } else { esc_json(encoded) }
}

fn key_to_json(k: &MapKey) -> String {
    match k {
        MapKey::S(s) => esc_json(s),
        MapKey::I(i) => i.to_string(),
        MapKey::B(b) => b.to_string(),
        MapKey::L(ks) => {
            let items: Vec<String> = ks.iter().map(key_to_json).collect();
            format!("[{}]", items.join(","))
        }
    }
}

/// Canonical JSON for the differential harness, mirroring harness.rs `J` (which
/// mirrors runtime.py): non-finite floats are names, prelude tags keep their
/// canonical shape, a Map's keys are quoted and sorted by BTreeMap. The other
/// arms' outputs are only compared after json.loads, so exact float spelling is
/// irrelevant; only the value and the shape must agree.
pub fn to_json(v: &Value) -> String {
    use Value::*;
    match v {
        Bool(b) => b.to_string(),
        Int { v, .. } => v.to_string(),
        Float(x) => {
            if x.is_nan() {
                "\"nan\"".to_string()
            } else if *x == f64::INFINITY {
                "\"inf\"".to_string()
            } else if *x == f64::NEG_INFINITY {
                "\"-inf\"".to_string()
            } else {
                format!("{:?}", x)
            }
        }
        Str(s) => esc_json(s),
        Unit => "null".to_string(),
        Tagged(t, ps) => match t.as_str() {
            "some" => format!("[\"some\",{}]", to_json(&ps[0])),
            "none" => "[\"none\"]".to_string(),
            "ok" => format!("[\"ok\",{}]", to_json(&ps[0])),
            "err" => format!("[\"err\",{}]", to_json(&ps[0])),
            "pair" => format!("[\"pair\",{},{}]", to_json(&ps[0]), to_json(&ps[1])),
            // A bare case (e.g. an IoError) is `[case]`; a user tag with payloads
            // has no harness analogue and never appears as a differential input.
            _ if ps.is_empty() => format!("[{}]", esc_json(t)),
            _ => format!(
                "[\"{}\",{}]",
                t,
                ps.iter().map(to_json).collect::<Vec<_>>().join(",")
            ),
        },
        List(xs) => {
            let items: Vec<String> = xs.iter().map(to_json).collect();
            format!("[{}]", items.join(","))
        }
        Record(fs) => {
            let items: Vec<String> =
                fs.iter().map(|(n, val)| format!("{}:{}", as_key(&esc_json(n)), to_json(val))).collect();
            format!("{{{}}}", items.join(","))
        }
        Map(m) => {
            let items: Vec<String> = m
                .iter()
                .map(|(k, val)| format!("{}:{}", as_key(&key_to_json(k)), to_json(val)))
                .collect();
            format!("{{{}}}", items.join(","))
        }
        Closure(_) => "null".to_string(),
    }
}
