//! Numeric semantics — ported from backend/runtime.py and backend/rust/rt.rs.
//!
//! Int32 and Int64 are siblings: arithmetic is trapping at the operand's own
//! width (Int32 traps at the 2^31 boundary). An out-of-width literal is an error
//! (checked before evaluation). `mod MIN -1 == 0` because the remainder is
//! computed from the unchecked quotient.

use crate::ast::NumericWidth;

pub const INT64_MIN: i64 = i64::MIN;
pub const INT64_MAX: i64 = i64::MAX;
pub const INT32_MIN: i64 = -(1 << 31);
pub const INT32_MAX: i64 = (1 << 31) - 1;

/// The result of a trapping integer operation.
pub type Trap<T> = Result<T, String>;

pub fn trunc_div(a: i64, b: i64) -> i64 {
    let q = a.wrapping_div(b); // MIN / -1 wraps to MIN; checked_div handles it
    q
}

/// Integer addition at the given width; traps out of width.
pub fn iadd(a: i64, b: i64, w: NumericWidth) -> Trap<i64> {
    let r = a.checked_add(b).ok_or("integer overflow")?;
    check_width(r, w)
}
pub fn isub(a: i64, b: i64, w: NumericWidth) -> Trap<i64> {
    let r = a.checked_sub(b).ok_or("integer overflow")?;
    check_width(r, w)
}
pub fn imul(a: i64, b: i64, w: NumericWidth) -> Trap<i64> {
    let r = a.checked_mul(b).ok_or("integer overflow")?;
    check_width(r, w)
}
pub fn ineg(a: i64, w: NumericWidth) -> Trap<i64> {
    let r = a.checked_neg().ok_or("integer overflow")?;
    check_width(r, w)
}
pub fn iabs(a: i64, w: NumericWidth) -> Trap<i64> {
    let r = a.checked_abs().ok_or("integer overflow")?;
    check_width(r, w)
}

/// Check an Int64-holding value fits the declared width. For Int64 this is
/// always true; for Int32 it traps when outside [INT32_MIN, INT32_MAX].
pub fn check_width(v: i64, w: NumericWidth) -> Trap<i64> {
    match w {
        NumericWidth::I32 => {
            if v < INT32_MIN || v > INT32_MAX {
                Err("int32 overflow".to_string())
            } else {
                Ok(v)
            }
        }
        _ => Ok(v),
    }
}

/// Integer division, truncating toward zero; traps on a zero divisor and on a
/// quotient outside the type (MIN / -1 is 2^63, unrepresentable).
pub fn idiv(a: i64, b: i64, w: NumericWidth) -> Trap<i64> {
    if b == 0 {
        return Err("division by zero".to_string());
    }
    let q = a.checked_div(b).ok_or("overflow in division")?;
    check_width(q, w)
}

/// Integer remainder; the sign follows the dividend. `MIN mod -1 == 0`.
pub fn imod(a: i64, b: i64) -> Trap<i64> {
    if b == 0 {
        return Err("modulo by zero".to_string());
    }
    // Computed from the unchecked quotient so MIN mod -1 is 0.
    let q = trunc_div(a, b);
    Ok(a.wrapping_sub(q.wrapping_mul(b)))
}

pub fn checked_div(a: i64, b: i64, w: NumericWidth) -> Option<i64> {
    if b == 0 {
        return None;
    }
    let q = a.checked_div(b)?;
    if w == NumericWidth::I32 {
        if q < INT32_MIN || q > INT32_MAX {
            return None;
        }
    }
    Some(q)
}

pub fn checked_mod(a: i64, b: i64) -> Option<i64> {
    if b == 0 {
        return None;
    }
    imod(a, b).ok()
}

/// Parse an integer literal's digits (sign included) into i64 at the declared
/// width. An out-of-width literal is an error.
pub fn parse_int_lit(digits: &str, w: NumericWidth) -> Trap<i64> {
    let v: i64 = digits.parse::<i64>().map_err(|_| {
        format!("literal {} is out of range for Int64", digits)
    })?;
    check_width(v, w)
}

/// The fallback width for an unsuffixed integer literal: Int64.
pub const DEFAULT_INT_WIDTH: NumericWidth = NumericWidth::I64;

/// `string-to-int64`: strip, then reject non-ASCII and `_` before parsing.
/// Rust's parse() accepts unicode digits Python's gate rejects, so the gate is
/// ported. The value must fit Int64.
pub fn to_int(s: &str) -> Option<i64> {
    let text = s.trim();
    if !is_parsable(text) {
        return None;
    }
    let n: i64 = text.parse().ok()?;
    Some(n)
}

/// `string-to-float64`, with the same parse guard.
pub fn to_float(s: &str) -> Option<f64> {
    let text = s.trim();
    if !is_parsable(text) {
        return None;
    }
    text.parse().ok()
}

/// `_parsable`: ASCII-only and no digit-group underscore.
pub fn is_parsable(text: &str) -> bool {
    text.is_ascii() && !text.contains('_')
}

/// `int64-to-int32`: range check.
pub fn to_i32(n: i64) -> Option<i64> {
    if n < INT32_MIN || n > INT32_MAX {
        None
    } else {
        Some(n)
    }
}

/// `float64-to-int64`: range before truncation. NaN and both infinities fall
/// out of the same two comparisons; Int64::MAX is not representable, so the
/// upper bound is INT64_MAX + 1.
pub fn f_to_i(x: f64) -> Option<i64> {
    let t = x.trunc();
    if t >= INT64_MIN as f64 && t < 9223372036854775808.0 {
        Some(t as i64)
    } else {
        None
    }
}

/// The language's `fmt_f64`, ported verbatim from rt.rs: NaN case, signed
/// exponent, exponent padded to two digits.
pub fn fmt_f64(x: f64) -> String {
    if x.is_nan() {
        return "nan".to_string();
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fmt_f64_pins_exponent_digits() {
        // Python repr(1e16) == "1e+16" — exponent padded to two digits.
        assert_eq!(fmt_f64(1e16), "1e+16");
        assert_eq!(fmt_f64(-0.0), "-0.0");
        assert_eq!(fmt_f64(f64::NAN), "nan");
    }

    #[test]
    fn min_div_minus_one_traps() {
        let r = idiv(i64::MIN, -1, NumericWidth::I64);
        assert!(r.is_err(), "MIN / -1 is unrepresentable and must trap");
    }

    #[test]
    fn min_mod_minus_one_is_zero() {
        // mod computes from the unchecked quotient so MIN mod -1 == 0.
        assert_eq!(imod(i64::MIN, -1), Ok(0));
    }

    #[test]
    fn int32_boundary_traps() {
        // 2147483647 + 1 overflows Int32: a trap, not a widening to Int64
        // (l-4d92). The same operands stay in range at Int64.
        assert!(iadd(INT32_MAX, 1, NumericWidth::I32).is_err());
        assert_eq!(iadd(INT32_MAX, 1, NumericWidth::I64), Ok(2147483648));
    }

    #[test]
    fn parsable_rejects_hostile_input() {
        // Rust's bare parse() accepts unicode digits Python's guard rejects.
        assert!(!is_parsable("١٢٣"));
        assert!(!is_parsable("1_000"));
        assert!(is_parsable("123"));
    }
}
