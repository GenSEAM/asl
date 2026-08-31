// Package rt is the AgentScript runtime for the Go backend.
//
// Go has neither sum types nor an ordered map, so both are built here. Map
// iteration is sorted by key because the language specifies it: an unspecified
// order would make the backends disagree on identical input, and the
// differential gate would report that as a transpiler defect.
//
// Every builtin lowering in prelude/prelude.json references these helpers by
// bare name; the corpus column rewrites this file's package line to `package
// main` at copy time, so the helpers and the emitted program compile as one
// unit.
package rt

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

// Unit is the one value of the language's unit type.
type Unit struct{}

type Option[T any] struct {
	Present bool
	Value   T
}

func Some[T any](v T) Option[T] { return Option[T]{true, v} }
func None[T any]() Option[T]    { return Option[T]{} }

type Result[T any, E any] struct {
	IsOk  bool
	Value T
	Err   E
}

func Ok[T any, E any](v T) Result[T, E]  { return Result[T, E]{IsOk: true, Value: v} }
func Err[T any, E any](e E) Result[T, E] { return Result[T, E]{Err: e} }

type Pair[A any, B any] struct {
	First  A
	Second B
}

func MkPair[A any, B any](a A, b B) Pair[A, B] { return Pair[A, B]{a, b} }

// ---------- numerics ----------
// One constraint spans Int32, Int64 and Float64, so a numeric helper fixed to
// one of them would be a backend narrower than the language it claims to
// implement. Go generics cannot switch on a type parameter directly, so every
// checked operation converts to `any` and dispatches on the concrete type.

type Number interface {
	~int32 | ~int64 | ~float64
}

const minI64 = int64(-9223372036854775808)
const maxI64 = int64(9223372036854775807)
const minI32 = int32(-2147483648)
const maxI32 = int32(2147483647)

func addI64(a, b int64) int64 {
	c := a + b
	if (a >= 0) == (b >= 0) && (a >= 0) != (c >= 0) {
		panic("overflow in addition")
	}
	return c
}
func subI64(a, b int64) int64 {
	c := a - b
	if (a >= 0) != (b >= 0) && (a >= 0) != (c >= 0) {
		panic("overflow in subtraction")
	}
	return c
}
func mulI64(a, b int64) int64 {
	if a == 0 || b == 0 {
		return 0
	}
	if (a == -1 && b == minI64) || (b == -1 && a == minI64) {
		panic("overflow in multiplication")
	}
	c := a * b
	if c/a != b {
		panic("overflow in multiplication")
	}
	return c
}
func negI64(a int64) int64 {
	if a == minI64 {
		panic("overflow in negation")
	}
	return -a
}
func absI64(a int64) int64 {
	if a == minI64 {
		panic("overflow in absolute value")
	}
	if a < 0 {
		return -a
	}
	return a
}

func addI32(a, b int32) int32 {
	c := a + b
	if (a >= 0) == (b >= 0) && (a >= 0) != (c >= 0) {
		panic("overflow in addition")
	}
	return c
}
func subI32(a, b int32) int32 {
	c := a - b
	if (a >= 0) != (b >= 0) && (a >= 0) != (c >= 0) {
		panic("overflow in subtraction")
	}
	return c
}
func mulI32(a, b int32) int32 {
	if a == 0 || b == 0 {
		return 0
	}
	if (a == -1 && b == minI32) || (b == -1 && a == minI32) {
		panic("overflow in multiplication")
	}
	c := a * b
	if c/a != b {
		panic("overflow in multiplication")
	}
	return c
}
func negI32(a int32) int32 {
	if a == minI32 {
		panic("overflow in negation")
	}
	return -a
}
func absI32(a int32) int32 {
	if a == minI32 {
		panic("overflow in absolute value")
	}
	if a < 0 {
		return -a
	}
	return a
}

func Add[T Number](a, b T) T {
	switch any(a).(type) {
	case int32:
		return T(addI32(any(a).(int32), any(b).(int32)))
	case int64:
		return T(addI64(any(a).(int64), any(b).(int64)))
	default:
		return T(any(a).(float64) + any(b).(float64))
	}
}
func Sub[T Number](a, b T) T {
	switch any(a).(type) {
	case int32:
		return T(subI32(any(a).(int32), any(b).(int32)))
	case int64:
		return T(subI64(any(a).(int64), any(b).(int64)))
	default:
		return T(any(a).(float64) - any(b).(float64))
	}
}
func Mul[T Number](a, b T) T {
	switch any(a).(type) {
	case int32:
		return T(mulI32(any(a).(int32), any(b).(int32)))
	case int64:
		return T(mulI64(any(a).(int64), any(b).(int64)))
	default:
		return T(any(a).(float64) * any(b).(float64))
	}
}
func Neg[T Number](a T) T {
	switch any(a).(type) {
	case int32:
		return T(negI32(any(a).(int32)))
	case int64:
		return T(negI64(any(a).(int64)))
	default:
		return T(-any(a).(float64))
	}
}
func Abs[T Number](a T) T {
	switch any(a).(type) {
	case int32:
		return T(absI32(any(a).(int32)))
	case int64:
		return T(absI64(any(a).(int64)))
	default:
		return T(math.Abs(any(a).(float64)))
	}
}

func Div[T Number](a, b T) T {
	switch any(a).(type) {
	case int32:
		x, y := any(a).(int32), any(b).(int32)
		if y == 0 {
			panic("division by zero")
		}
		// Go's `/` silently wraps MIN / -1, where the language traps.
		if x == minI32 && y == -1 {
			panic("overflow in division")
		}
		return T(x / y)
	case int64:
		x, y := any(a).(int64), any(b).(int64)
		if y == 0 {
			panic("division by zero")
		}
		if x == minI64 && y == -1 {
			panic("overflow in division")
		}
		return T(x / y)
	default:
		x, y := any(a).(float64), any(b).(float64)
		if y == 0 {
			panic("division by zero")
		}
		return T(x / y)
	}
}

func Rem[T Number](a, b T) T {
	switch any(a).(type) {
	case int32:
		x, y := any(a).(int32), any(b).(int32)
		if y == 0 {
			panic("modulo by zero")
		}
		return T(x % y)
	case int64:
		x, y := any(a).(int64), any(b).(int64)
		if y == 0 {
			panic("modulo by zero")
		}
		return T(x % y)
	default:
		x, y := any(a).(float64), any(b).(float64)
		if y == 0 {
			panic("modulo by zero")
		}
		return T(math.Mod(x, y))
	}
}

func CheckedDiv[T Number](a, b T) Option[T] {
	switch any(a).(type) {
	case int32:
		x, y := any(a).(int32), any(b).(int32)
		if y == 0 {
			return None[T]()
		}
		if x == minI32 && y == -1 {
			return None[T]()
		}
		return Some(T(x / y))
	case int64:
		x, y := any(a).(int64), any(b).(int64)
		if y == 0 {
			return None[T]()
		}
		if x == minI64 && y == -1 {
			return None[T]()
		}
		return Some(T(x / y))
	default:
		x, y := any(a).(float64), any(b).(float64)
		if y == 0 {
			return None[T]()
		}
		return Some(T(x / y))
	}
}

func CheckedRem[T Number](a, b T) Option[T] {
	switch any(a).(type) {
	case int32:
		x, y := any(a).(int32), any(b).(int32)
		if y == 0 {
			return None[T]()
		}
		return Some(T(x % y))
	case int64:
		x, y := any(a).(int64), any(b).(int64)
		if y == 0 {
			return None[T]()
		}
		return Some(T(x % y))
	default:
		x, y := any(a).(float64), any(b).(float64)
		if y == 0 {
			return None[T]()
		}
		return Some(T(math.Mod(x, y)))
	}
}

func Sum[T Number](xs []T) T {
	var z T
	for _, x := range xs {
		z = Add(z, x)
	}
	return z
}

func Min[T Number](a, b T) T {
	if Cmp(any(a), any(b)) <= 0 {
		return a
	}
	return b
}
func Max[T Number](a, b T) T {
	if Cmp(any(b), any(a)) >= 0 {
		return b
	}
	return a
}

// ---------- equality and ordering ----------
// Structural equality and a total order, ported from the TypeScript runtime's
// eq/cmp (the pinned reference). A value holding a NaN equals nothing —
// including itself inside a container — and sorts after every value that does
// not, with NaN-holding values tying so a stable sort leaves them in input
// order. The NaN test comes first so the order is transitive.

func hasNaN(v reflect.Value) bool {
	switch v.Kind() {
	case reflect.Float32, reflect.Float64:
		return math.IsNaN(v.Float())
	case reflect.Slice, reflect.Array:
		for i := 0; i < v.Len(); i++ {
			if hasNaN(v.Index(i)) {
				return true
			}
		}
	case reflect.Struct:
		for i := 0; i < v.NumField(); i++ {
			if hasNaN(v.Field(i)) {
				return true
			}
		}
	case reflect.Map:
		for _, k := range v.MapKeys() {
			if hasNaN(k) || hasNaN(v.MapIndex(k)) {
				return true
			}
		}
	case reflect.Ptr:
		if !v.IsNil() {
			return hasNaN(v.Elem())
		}
	case reflect.Interface:
		if !v.IsNil() {
			return hasNaN(v.Elem())
		}
	}
	return false
}

func isIntKind(k reflect.Kind) bool {
	switch k {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return true
	}
	return false
}

func deepEq(a, b reflect.Value) bool {
	if !a.IsValid() || !b.IsValid() {
		return a.IsValid() == b.IsValid()
	}
	if a.Kind() == reflect.Ptr || a.Kind() == reflect.Interface {
		return deepEq(a.Elem(), b.Elem())
	}
	if b.Kind() == reflect.Ptr || b.Kind() == reflect.Interface {
		return deepEq(a.Elem(), b.Elem())
	}
	if isIntKind(a.Kind()) && isIntKind(b.Kind()) {
		return a.Int() == b.Int()
	}
	if (a.Kind() == reflect.Float32 || a.Kind() == reflect.Float64) &&
		(b.Kind() == reflect.Float32 || b.Kind() == reflect.Float64) {
		return a.Float() == b.Float()
	}
	if a.Kind() != b.Kind() {
		return false
	}
	switch a.Kind() {
	case reflect.String:
		return a.String() == b.String()
	case reflect.Bool:
		return a.Bool() == b.Bool()
	case reflect.Slice, reflect.Array:
		if a.Len() != b.Len() {
			return false
		}
		for i := 0; i < a.Len(); i++ {
			if !deepEq(a.Index(i), b.Index(i)) {
				return false
			}
		}
		return true
	case reflect.Map:
		if a.Len() != b.Len() {
			return false
		}
		for _, k := range a.MapKeys() {
			bv := b.MapIndex(k)
			if !bv.IsValid() || !deepEq(a.MapIndex(k), bv) {
				return false
			}
		}
		return true
	case reflect.Struct:
		if a.NumField() != b.NumField() {
			return false
		}
		for i := 0; i < a.NumField(); i++ {
			if !deepEq(a.Field(i), b.Field(i)) {
				return false
			}
		}
		return true
	}
	return false
}

func Eq(a, b any) bool {
	av, bv := reflect.ValueOf(a), reflect.ValueOf(b)
	if hasNaN(av) || hasNaN(bv) {
		return false
	}
	return deepEq(av, bv)
}

func cmpInts(a, b int64) int {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

func cmpFloats(a, b float64) int {
	an, bn := math.IsNaN(a), math.IsNaN(b)
	if an && bn {
		return 0
	}
	if an {
		return 1
	}
	if bn {
		return -1
	}
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

func deepCmp(a, b reflect.Value) int {
	if !a.IsValid() || !b.IsValid() {
		if !a.IsValid() && !b.IsValid() {
			return 0
		}
		if !a.IsValid() {
			return -1
		}
		return 1
	}
	if a.Kind() == reflect.Ptr || a.Kind() == reflect.Interface {
		return deepCmp(a.Elem(), b.Elem())
	}
	if b.Kind() == reflect.Ptr || b.Kind() == reflect.Interface {
		return deepCmp(a.Elem(), b.Elem())
	}
	if isIntKind(a.Kind()) && isIntKind(b.Kind()) {
		return cmpInts(a.Int(), b.Int())
	}
	if (a.Kind() == reflect.Float32 || a.Kind() == reflect.Float64) &&
		(b.Kind() == reflect.Float32 || b.Kind() == reflect.Float64) {
		return cmpFloats(a.Float(), b.Float())
	}
	if a.Kind() != b.Kind() {
		return cmpInts(int64(a.Kind()), int64(b.Kind()))
	}
	switch a.Kind() {
	case reflect.String:
		return cmpInts(int64(strings.Compare(a.String(), b.String())), 0)
	case reflect.Bool:
		return cmpInts(b2i(a.Bool()), b2i(b.Bool()))
	case reflect.Slice, reflect.Array:
		n := a.Len()
		if b.Len() < n {
			n = b.Len()
		}
		for i := 0; i < n; i++ {
			if c := deepCmp(a.Index(i), b.Index(i)); c != 0 {
				return c
			}
		}
		return cmpInts(int64(a.Len()), int64(b.Len()))
	case reflect.Map:
		aks := a.MapKeys()
		bks := b.MapKeys()
		// Keys are orderable in this language; compare smallest key first.
		as, bs := make([]string, 0, len(aks)), make([]string, 0, len(bks))
		for _, k := range aks {
			as = append(as, k.String())
		}
		for _, k := range bks {
			bs = append(bs, k.String())
		}
		sort.Strings(as)
		sort.Strings(bs)
		n := len(as)
		if len(bs) < n {
			n = len(bs)
		}
		for i := 0; i < n; i++ {
			if c := strings.Compare(as[i], bs[i]); c != 0 {
				return cmpInts(int64(c), 0)
			}
		}
		return cmpInts(int64(len(as)), int64(len(bs)))
	case reflect.Struct:
		n := a.NumField()
		if b.NumField() < n {
			n = b.NumField()
		}
		for i := 0; i < n; i++ {
			if c := deepCmp(a.Field(i), b.Field(i)); c != 0 {
				return c
			}
		}
		return cmpInts(int64(a.NumField()), int64(b.NumField()))
	}
	return 0
}

func b2i(b bool) int64 {
	if b {
		return 1
	}
	return 0
}

func Cmp(a, b any) int {
	return deepCmp(reflect.ValueOf(a), reflect.ValueOf(b))
}

// ---------- strings ----------

func StrLen(s string) int64 { return int64(len([]rune(s))) }
func Concat(xs ...string) string { return strings.Join(xs, "") }
func Chars(s string) []string {
	out := []string{}
	for _, r := range s {
		out = append(out, string(r))
	}
	return out
}
func StrRev(s string) string {
	r := []rune(s)
	for i, j := 0, len(r)-1; i < j; i, j = i+1, j-1 {
		r[i], r[j] = r[j], r[i]
	}
	return string(r)
}
func Split(s, sep string) []string { return strings.Split(s, sep) }
func StrSlice(s string, a, b int64) Option[string] {
	r := []rune(s)
	n := int64(len(r))
	if a < 0 || b < a || b > n {
		return None[string]()
	}
	return Some(string(r[a:b]))
}
func StrIndexOf(s, sub string) Option[int64] {
	i := strings.Index(s, sub)
	if i < 0 {
		return None[int64]()
	}
	return Some(int64(len([]rune(s[:i]))))
}
func StrContains(s, sub string) bool   { return strings.Contains(s, sub) }
func StrStartsWith(s, p string) bool   { return strings.HasPrefix(s, p) }
func StrEndsWith(s, p string) bool     { return strings.HasSuffix(s, p) }
func StrJoin(xs []string, sep string) string { return strings.Join(xs, sep) }
func StrUpper(s string) string         { return strings.ToUpper(s) }
func StrLower(s string) string         { return strings.ToLower(s) }
func StrTrim(s string) string          { return strings.TrimSpace(s) }
func StrReplace(s, f, t string) string { return strings.ReplaceAll(s, f, t) }
func FmtI64(n int64) string            { return strconv.FormatInt(n, 10) }

// FmtF64 is Python's repr of a float, re-rendered under its exponent
// thresholds. Go's shortest round-trip digits agree with Python's repr; only
// the exponent cutoff differs ('g' switches at 21, Python at 16 and -5), and
// nan/inf/-0.0 have their own spellings here.
func FmtF64(x float64) string {
	if math.IsNaN(x) {
		return "nan"
	}
	if math.IsInf(x, 1) {
		return "inf"
	}
	if math.IsInf(x, -1) {
		return "-inf"
	}
	if x == 0 && math.Signbit(x) {
		return "-0.0"
	}
	neg := false
	v := x
	if v < 0 {
		neg = true
		v = -v
	}
	s := strconv.FormatFloat(v, 'g', -1, 64)
	var digits string
	var exp10 int
	if i := strings.IndexAny(s, "eE"); i >= 0 {
		mant := s[:i]
		var e int
		fmt.Sscanf(s[i+1:], "%d", &e)
		if dp := strings.IndexByte(mant, '.'); dp >= 0 {
			d, f := mant[:dp], mant[dp+1:]
			digits = d + f
			exp10 = len(d) - 1 + e
		} else {
			digits = mant
			exp10 = len(mant) - 1 + e
		}
	} else {
		if dp := strings.IndexByte(s, '.'); dp >= 0 {
			d, f := s[:dp], s[dp+1:]
			digits = d + f
			exp10 = len(d) - 1
		} else {
			digits = s
			exp10 = len(s) - 1
		}
	}
	first := strings.IndexAny(digits, "123456789")
	if first > 0 {
		digits = digits[first:]
		exp10 -= first
	} else if first < 0 {
		digits = "0"
		exp10 = 0
	}
	digits = strings.TrimRight(digits, "0")
	if digits == "" {
		digits = "0"
	}
	sign := ""
	if neg {
		sign = "-"
	}
	if exp10 >= 16 || exp10 <= -5 {
		mant := digits
		if len(digits) > 1 {
			mant = digits[:1] + "." + digits[1:]
		}
		esign := "+"
		eabs := exp10
		if exp10 < 0 {
			esign = "-"
			eabs = -exp10
		}
		return sign + mant + "e" + esign + fmt.Sprintf("%02d", eabs)
	}
	if exp10 >= 0 {
		if len(digits) <= exp10+1 {
			return sign + digits + strings.Repeat("0", exp10+1-len(digits)) + ".0"
		}
		return sign + digits[:exp10+1] + "." + digits[exp10+1:]
	}
	return sign + "0." + strings.Repeat("0", -exp10-1) + digits
}

func parsable(text string) bool {
	if strings.Contains(text, "_") {
		return false
	}
	for i := 0; i < len(text); i++ {
		if text[i] >= 128 {
			return false
		}
	}
	return true
}

func NegZero() float64 { return math.Copysign(0.0, -1.0) }

func ToI64(s string) Option[int64] {
	t := strings.TrimSpace(s)
	if !parsable(t) {
		return None[int64]()
	}
	v, err := strconv.ParseInt(t, 10, 64)
	if err != nil {
		return None[int64]()
	}
	return Some(v)
}
func ToF64(s string) Option[float64] {
	t := strings.TrimSpace(s)
	if !parsable(t) {
		return None[float64]()
	}
	low := strings.ToLower(t)
	if low == "nan" || low == "+nan" || low == "-nan" {
		return Some(math.NaN())
	}
	if low == "inf" || low == "+inf" || low == "infinity" || low == "+infinity" {
		return Some(math.Inf(1))
	}
	if low == "-inf" || low == "-infinity" {
		return Some(math.Inf(-1))
	}
	v, err := strconv.ParseFloat(t, 64)
	if err != nil {
		return None[float64]()
	}
	return Some(v)
}
func ToI32(n int64) Option[int32] {
	if n < -2147483648 || n > 2147483647 {
		return None[int32]()
	}
	return Some(int32(n))
}
func FToI(x float64) Option[int64] {
	t := math.Trunc(x)
	if t >= -9223372036854775808.0 && t < 9223372036854775808.0 {
		return Some(int64(t))
	}
	return None[int64]()
}

// ---------- lists ----------

func ListOf[T any](xs ...T) []T { return xs }

func At[T any](xs []T, i int64) Option[T] {
	if i < 0 || i >= int64(len(xs)) {
		return None[T]()
	}
	return Some(xs[i])
}
func Tail[T any](xs []T) Option[[]T] {
	if len(xs) == 0 {
		return None[[]T]()
	}
	return Some(append([]T{}, xs[1:]...))
}
func Cons[T any](x T, xs []T) []T { return append([]T{x}, xs...) }
func Append[T any](a, b []T) []T  { return append(append([]T{}, a...), b...) }
func Rev[T any](xs []T) []T {
	out := append([]T{}, xs...)
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}
func ListSlice[T any](xs []T, a, b int64) Option[[]T] {
	n := int64(len(xs))
	if a < 0 || b < a || b > n {
		return None[[]T]()
	}
	return Some(append([]T{}, xs[a:b]...))
}
func Contains[T any](xs []T, x T) bool {
	for _, y := range xs {
		if Eq(y, x) {
			return true
		}
	}
	return false
}
func IndexOf[T any](xs []T, x T) Option[int64] {
	for i, y := range xs {
		if Eq(y, x) {
			return Some(int64(i))
		}
	}
	return None[int64]()
}
func Sort[T any](xs []T) []T {
	out := append([]T{}, xs...)
	sort.SliceStable(out, func(i, j int) bool { return Cmp(out[i], out[j]) < 0 })
	return out
}
func SortBy[T any, K any](f func(T) K, xs []T) []T {
	out := append([]T{}, xs...)
	sort.SliceStable(out, func(i, j int) bool { return Cmp(f(out[i]), f(out[j])) < 0 })
	return out
}
func Map[A any, B any](f func(A) B, xs []A) []B {
	out := make([]B, 0, len(xs))
	for _, x := range xs {
		out = append(out, f(x))
	}
	return out
}
func Filter[T any](p func(T) bool, xs []T) []T {
	out := []T{}
	for _, x := range xs {
		if p(x) {
			out = append(out, x)
		}
	}
	return out
}
func Fold[A any, B any](f func(B, A) B, init B, xs []A) B {
	acc := init
	for _, x := range xs {
		acc = f(acc, x)
	}
	return acc
}
func Range(a, b int64) []int64 {
	out := []int64{}
	for i := a; i < b; i++ {
		out = append(out, i)
	}
	return out
}
func Zip[A any, B any](a []A, b []B) []Pair[A, B] {
	n := len(a)
	if len(b) < n {
		n = len(b)
	}
	out := make([]Pair[A, B], 0, n)
	for i := 0; i < n; i++ {
		out = append(out, Pair[A, B]{a[i], b[i]})
	}
	return out
}
func Least[T any](xs []T) Option[T] {
	if len(xs) == 0 {
		return None[T]()
	}
	m := xs[0]
	for _, x := range xs[1:] {
		if Cmp(x, m) < 0 {
			m = x
		}
	}
	return Some(m)
}
func Greatest[T any](xs []T) Option[T] {
	if len(xs) == 0 {
		return None[T]()
	}
	m := xs[0]
	for _, x := range xs[1:] {
		if Cmp(x, m) > 0 {
			m = x
		}
	}
	return Some(m)
}

// ---------- maps ----------

func MEmpty[K comparable, V any]() map[K]V { return map[K]V{} }
func MGet[K comparable, V any](m map[K]V, k K) Option[V] {
	if v, ok := m[k]; ok {
		return Some(v)
	}
	return None[V]()
}
func MSet[K comparable, V any](m map[K]V, k K, v V) map[K]V {
	out := make(map[K]V, len(m)+1)
	for a, b := range m {
		out[a] = b
	}
	out[k] = v
	return out
}
func MDel[K comparable, V any](m map[K]V, k K) map[K]V {
	out := make(map[K]V, len(m))
	for a, b := range m {
		if a != k {
			out[a] = b
		}
	}
	return out
}
func MHas[K comparable, V any](m map[K]V, k K) bool {
	_, ok := m[k]
	return ok
}
func MKeys[K comparable, V any](m map[K]V) []K {
	ks := make([]K, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	return Sort(ks)
}
func MValues[K comparable, V any](m map[K]V) []V {
	out := make([]V, 0, len(m))
	for _, k := range MKeys(m) {
		out = append(out, m[k])
	}
	return out
}
func MPairs[K comparable, V any](m map[K]V) []Pair[K, V] {
	out := make([]Pair[K, V], 0, len(m))
	for _, k := range MKeys(m) {
		out = append(out, Pair[K, V]{k, m[k]})
	}
	return out
}
func MFrom[K comparable, V any](ps []Pair[K, V]) map[K]V {
	out := make(map[K]V, len(ps))
	for _, p := range ps {
		out[p.First] = p.Second
	}
	return out
}

// ---------- option and result ----------

func OptOr[T any](o Option[T], d T) T {
	if o.Present {
		return o.Value
	}
	return d
}
func ResOr[T any, E any](r Result[T, E], d T) T {
	if r.IsOk {
		return r.Value
	}
	return d
}
func OptMap[A any, B any](f func(A) B, o Option[A]) Option[B] {
	if o.Present {
		return Some(f(o.Value))
	}
	return None[B]()
}
func ResMap[A any, B any, E any](f func(A) B, r Result[A, E]) Result[B, E] {
	if r.IsOk {
		return Ok[B, E](f(r.Value))
	}
	return Err[B, E](r.Err)
}
func ResMapErr[T any, E any, F any](f func(E) F, r Result[T, E]) Result[T, F] {
	if r.IsOk {
		return Ok[T, F](r.Value)
	}
	return Err[T, F](f(r.Err))
}
func OptToRes[T any, E any](o Option[T], e E) Result[T, E] {
	if o.Present {
		return Ok[T, E](o.Value)
	}
	return Err[T, E](e)
}
func ResToOpt[T any, E any](r Result[T, E]) Option[T] {
	if r.IsOk {
		return Some(r.Value)
	}
	return None[T]()
}

// Thrown carries an `err` out of a `try`. A defun containing a `try` catches
// exactly this and returns the value as its own err, so the propagation never
// escapes the function that declared the Result.
type Thrown struct {
	Value any
}

func Unwrap[T any, E any](r Result[T, E]) T {
	if r.IsOk {
		return r.Value
	}
	panic(Thrown{r.Err})
}

// ---------- I/O ----------

// IoError is the closed failure union `main` may terminate on, mirroring the
// Python and Rust runtimes. Every I/O helper derives a case from the host's
// errno via ErrnoToIoError; only the differential gate proves the three agree.
type IoError struct {
	Tag string
}

func NotFound() IoError          { return IoError{"not-found"} }
func PermissionDenied() IoError  { return IoError{"permission-denied"} }
func AlreadyExists() IoError     { return IoError{"already-exists"} }
func InvalidPath() IoError       { return IoError{"invalid-path"} }
func Interrupted() IoError       { return IoError{"interrupted"} }
func Other() IoError             { return IoError{"other"} }

func (e IoError) caseName() string { return e.Tag }

// ErrnoToIoError maps a host error to the closed union. The table is identical
// to the Python runtime's errno map: EINVAL and ENAMETOOLONG fall to `other`,
// exactly as they do on both duals. The Go arm runs native darwin/linux only,
// so the errno numbers are the Unix numbers the table shares.
func ErrnoToIoError(err error) IoError {
	var e syscall.Errno
	if errors.As(err, &e) {
		switch e {
		case syscall.ENOENT:
			return NotFound()
		case syscall.EACCES:
			return PermissionDenied()
		case syscall.EEXIST:
			return AlreadyExists()
		case syscall.ENOTDIR, syscall.EISDIR:
			return InvalidPath()
		case syscall.EINTR:
			return Interrupted()
		}
	}
	return Other()
}

var stdinReader = bufio.NewReader(os.Stdin)
var stdinErr error

func trimNL(s string) string {
	s = strings.TrimSuffix(s, "\n")
	return strings.TrimSuffix(s, "\r")
}

func ReadLine() Result[Option[string], IoError] {
	if stdinErr != nil {
		return Err[Option[string], IoError](ErrnoToIoError(stdinErr))
	}
	s, err := stdinReader.ReadString('\n')
	if err != nil {
		if err == io.EOF {
			if s == "" {
				return Ok[Option[string], IoError](None[string]())
			}
			return Ok[Option[string], IoError](Some(trimNL(s)))
		}
		stdinErr = err
		return Err[Option[string], IoError](ErrnoToIoError(err))
	}
	return Ok[Option[string], IoError](Some(trimNL(s)))
}

func ReadAll() Result[string, IoError] {
	if stdinErr != nil {
		return Err[string, IoError](ErrnoToIoError(stdinErr))
	}
	rest, err := stdinReader.ReadString(0)
	if err != nil && err != io.EOF {
		stdinErr = err
		return Err[string, IoError](ErrnoToIoError(err))
	}
	return Ok[string, IoError](rest)
}

func PrintOut(s string) Result[Unit, IoError] {
	if _, err := os.Stdout.WriteString(s); err != nil {
		return Err[Unit, IoError](ErrnoToIoError(err))
	}
	return Ok[Unit, IoError](Unit{})
}
func Println(s string) Result[Unit, IoError] {
	if _, err := fmt.Fprintln(os.Stdout, s); err != nil {
		return Err[Unit, IoError](ErrnoToIoError(err))
	}
	return Ok[Unit, IoError](Unit{})
}
func Eprintln(s string) Result[Unit, IoError] {
	if _, err := fmt.Fprintln(os.Stderr, s); err != nil {
		return Err[Unit, IoError](ErrnoToIoError(err))
	}
	return Ok[Unit, IoError](Unit{})
}

func FileRead(path string) Result[string, IoError] {
	b, err := os.ReadFile(path)
	if err != nil {
		return Err[string, IoError](ErrnoToIoError(err))
	}
	return Ok[string, IoError](string(b))
}
func FileWrite(path, text string) Result[Unit, IoError] {
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		return Err[Unit, IoError](ErrnoToIoError(err))
	}
	return Ok[Unit, IoError](Unit{})
}
func FileAppend(path, text string) Result[Unit, IoError] {
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return Err[Unit, IoError](ErrnoToIoError(err))
	}
	defer f.Close()
	if _, err := f.WriteString(text); err != nil {
		return Err[Unit, IoError](ErrnoToIoError(err))
	}
	return Ok[Unit, IoError](Unit{})
}

func FileExistsRes(path string) Result[bool, IoError] {
	_, err := os.Stat(path)
	if err == nil {
		return Ok[bool, IoError](true)
	}
	if os.IsNotExist(err) {
		return Ok[bool, IoError](false)
	}
	return Err[bool, IoError](ErrnoToIoError(err))
}

// MainExit turns a program's Result into its exit status, mirroring the other
// runtimes: `err` prints the case name to stderr — the only part of a failure
// the language defines — and exits 1.
func MainExit(r Result[Unit, IoError]) int {
	if r.IsOk {
		return 0
	}
	_, _ = fmt.Fprintln(os.Stderr, r.Err.caseName())
	return 1
}
