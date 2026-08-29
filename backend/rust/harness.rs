//! JSON encoding for the differential driver, never for user output.
//!
//! The encoding is recursive because the shapes compose: `(Option (List T))`,
//! `(List (Pair K V))` and `(Result (Option Int64) IoError)` are all reachable
//! from the vocabulary, and a flat per-shape serializer cannot spell any of them.
//! Every case here matches backend/runtime.py's representation, because agreement
//! between the two backends must be about semantics and not about encoding.
#![allow(dead_code)]
use crate::rt;
use std::collections::BTreeMap;

pub fn esc(s: &str) -> String {
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

/// A JSON object key is always a string, so a non-String key is quoted here the
/// same way json.dumps quotes one on the Python side.
fn as_key(encoded: &str) -> String {
    if encoded.starts_with('"') { encoded.to_string() } else { esc(encoded) }
}

pub trait J {
    fn j(&self) -> String;
}

impl J for i32 {
    fn j(&self) -> String { self.to_string() }
}
impl J for i64 {
    fn j(&self) -> String { self.to_string() }
}
impl J for bool {
    fn j(&self) -> String { self.to_string() }
}
// Non-finite floats have no JSON spelling: Rust's {:?} emits NaN and Python's
// json.dumps emits a bare NaN, and neither parses. Both sides render a string.
impl J for f64 {
    fn j(&self) -> String {
        if self.is_nan() {
            "\"nan\"".to_string()
        } else if *self == f64::INFINITY {
            "\"inf\"".to_string()
        } else if *self == f64::NEG_INFINITY {
            "\"-inf\"".to_string()
        } else {
            format!("{:?}", self)
        }
    }
}
impl J for String {
    fn j(&self) -> String { esc(self) }
}
impl J for () {
    fn j(&self) -> String { "null".to_string() }
}
impl<T: J> J for Option<T> {
    fn j(&self) -> String {
        match self {
            Some(v) => format!("[\"some\",{}]", v.j()),
            None => "[\"none\"]".to_string(),
        }
    }
}
impl<T: J, E: J> J for Result<T, E> {
    fn j(&self) -> String {
        match self {
            Ok(v) => format!("[\"ok\",{}]", v.j()),
            Err(e) => format!("[\"err\",{}]", e.j()),
        }
    }
}
impl<A: J, B: J> J for (A, B) {
    fn j(&self) -> String { format!("[\"pair\",{},{}]", self.0.j(), self.1.j()) }
}
impl<T: J> J for Vec<T> {
    fn j(&self) -> String {
        let items: Vec<String> = self.iter().map(|x| x.j()).collect();
        format!("[{}]", items.join(","))
    }
}
impl<K: J, V: J> J for BTreeMap<K, V> {
    fn j(&self) -> String {
        let items: Vec<String> = self
            .iter()
            .map(|(k, v)| format!("{}:{}", as_key(&k.j()), v.j()))
            .collect();
        format!("{{{}}}", items.join(","))
    }
}
// A nullary case is a one-element array on the Python side, IoError included;
// encoding it as a bare string here would make the two disagree on shape alone.
impl J for rt::IoError {
    fn j(&self) -> String { format!("[{}]", esc(self.case())) }
}
