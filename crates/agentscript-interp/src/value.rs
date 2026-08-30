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
