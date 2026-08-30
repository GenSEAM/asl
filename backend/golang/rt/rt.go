// Package rt is the AgentScript runtime for the Go backend.
//
// Go has neither sum types nor an ordered map, so both are built here. Map
// iteration is sorted by key because the language specifies it: an unspecified
// order would make the backends disagree on identical input, and the
// differential gate would report that as a transpiler defect.
package rt

import (
	"fmt"
	"sort"
	"strconv"
	"strings"
)

type Option[T any] struct {
	Present bool
	Value   T
}

func Some[T any](v T) Option[T] { return Option[T]{true, v} }
func None[T any]() Option[T]    { var z T; return Option[T]{} }

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

func Div(a, b int64) int64 {
	if b == 0 {
		panic("division by zero")
	}
	return a / b // Go truncates toward zero, as the language specifies
}

func Rem(a, b int64) int64 {
	if b == 0 {
		panic("modulo by zero")
	}
	return a % b
}

func CheckedDiv(a, b int64) Option[int64] {
	if b == 0 {
		return None[int64]()
	}
	return Some(a / b)
}

func CheckedRem(a, b int64) Option[int64] {
	if b == 0 {
		return None[int64]()
	}
	return Some(a % b)
}

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
func FmtF64(x float64) string { return strconv.FormatFloat(x, 'g', -1, 64) }
func ToI64(s string) Option[int64] {
	v, err := strconv.ParseInt(strings.TrimSpace(s), 10, 64)
	if err != nil {
		return None[int64]()
	}
	return Some(v)
}
func ToF64(s string) Option[float64] {
	v, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
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
	if x != x || x > 1.7e308 || x < -1.7e308 {
		return None[int64]()
	}
	return Some(int64(x))
}

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
func Cons[T any](x T, xs []T) []T  { return append([]T{x}, xs...) }
func Append[T any](a, b []T) []T   { return append(append([]T{}, a...), b...) }
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
func Contains[T comparable](xs []T, x T) bool {
	for _, y := range xs {
		if y == x {
			return true
		}
	}
	return false
}
func IndexOf[T comparable](xs []T, x T) Option[int64] {
	for i, y := range xs {
		if y == x {
			return Some(int64(i))
		}
	}
	return None[int64]()
}

type Ordered interface {
	~int | ~int32 | ~int64 | ~float64 | ~string
}

func Sort[T Ordered](xs []T) []T {
	out := append([]T{}, xs...)
	sort.SliceStable(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}
func SortBy[T any, K Ordered](f func(T) K, xs []T) []T {
	out := append([]T{}, xs...)
	sort.SliceStable(out, func(i, j int) bool { return f(out[i]) < f(out[j]) })
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
func Sum(xs []int64) int64 {
	var t int64
	for _, x := range xs {
		t += x
	}
	return t
}
func Least[T Ordered](xs []T) Option[T] {
	if len(xs) == 0 {
		return None[T]()
	}
	m := xs[0]
	for _, x := range xs {
		if x < m {
			m = x
		}
	}
	return Some(m)
}
func Greatest[T Ordered](xs []T) Option[T] {
	if len(xs) == 0 {
		return None[T]()
	}
	m := xs[0]
	for _, x := range xs {
		if x > m {
			m = x
		}
	}
	return Some(m)
}

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
func MKeys[K Ordered, V any](m map[K]V) []K {
	ks := make([]K, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	return Sort(ks)
}
func MValues[K Ordered, V any](m map[K]V) []V {
	out := make([]V, 0, len(m))
	for _, k := range MKeys(m) {
		out = append(out, m[k])
	}
	return out
}
func MPairs[K Ordered, V any](m map[K]V) []Pair[K, V] {
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
func Show(v any) string { return fmt.Sprintf("%v", v) }
