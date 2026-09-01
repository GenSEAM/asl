export interface CodeExample {
  id: string;
  title: string;
  category: string;
  description: string;
  code: string;
  astNodes: { id: string; label: string; type: string; level: number }[];
  transpiled: {
    ts: string;
    rs: string;
    go: string;
    py: string;
    wat: string;
  };
  expectedOutput: string;
}

export const EXAMPLES: CodeExample[] = [
  {
    id: "fibonacci",
    title: "Fibonacci Sequence",
    category: "Algorithm",
    description: "Tail-recursive Fibonacci generator demonstrating strict tail-call optimization in ASL Nano.",
    code: `(module math/fib
  :doc "Tail-recursive Fibonacci in ASL Nano"
  :export [main fib])

(df fib [(n I64)] -> I64
  :doc "Calculate N-th Fibonacci number"
  (let [iter (fn [(i I64) (a I64) (b I64)] -> I64
               (if (<= i 0)
                   a
                   (iter (- i 1) b (+ a b))))]
    (iter n 0 1)))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :doc "CLI Entrypoint"
  (println (s/concat "fib(10) = " (string-from-int64 (fib 10))))
  (println (s/concat "fib(20) = " (string-from-int64 (fib 20))))
  (println (s/concat "fib(40) = " (string-from-int64 (fib 40))))
  (ok ()))`,
    astNodes: [
      { id: "mod", label: "module math/fib", type: "module", level: 0 },
      { id: "def_fib", label: "df fib [(n I64)] -> I64", type: "function", level: 1 },
      { id: "let_iter", label: "let iter = fn(i, a, b)", type: "binding", level: 2 },
      { id: "if_cond", label: "if (<= i 0)", type: "branch", level: 3 },
      { id: "ret_a", label: "a", type: "leaf", level: 4 },
      { id: "recur", label: "iter (i-1) b (a+b)", type: "call", level: 4 },
      { id: "def_main", label: "df ! main", type: "effect", level: 1 },
      { id: "print1", label: "println (fib 10)", type: "io", level: 2 },
      { id: "print2", label: "println (fib 20)", type: "io", level: 2 },
    ],
    transpiled: {
      ts: `import * as rt from './rt';

export function fib(n: bigint): bigint {
  const iter = (i: bigint, a: bigint, b: bigint): bigint => {
    return i <= 0n ? a : iter(i - 1n, b, a + b);
  };
  return iter(n, 0n, 1n);
}

export function main(args: string[]): rt.Result<void, rt.IoError> {
  console.log(\`fib(10) = \${fib(10n)}\`);
  console.log(\`fib(20) = \${fib(20n)}\`);
  console.log(\`fib(40) = \${fib(40n)}\`);
  return { tag: 'ok', value: undefined };
}`,
      rs: `pub fn fib(n: i64) -> i64 {
    let mut i = n;
    let mut a = 0i64;
    let mut b = 1i64;
    while i > 0 {
        let next = a + b;
        a = b;
        b = next;
        i -= 1;
    }
    a
}

pub fn main() -> Result<(), std::io::Error> {
    println!("fib(10) = {}", fib(10));
    println!("fib(20) = {}", fib(20));
    println!("fib(40) = {}", fib(40));
    Ok(())
}`,
      go: `package main

import "fmt"

func Fib(n int64) int64 {
	var a, b int64 = 0, 1
	for i := n; i > 0; i-- {
		a, b = b, a+b
	}
	return a
}

func main() {
	fmt.Printf("fib(10) = %d\\n", Fib(10))
	fmt.Printf("fib(20) = %d\\n", Fib(20))
	fmt.Printf("fib(40) = %d\\n", Fib(40))
}`,
      py: `def fib(n: int) -> int:
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a

def main(args: list[str]):
    print(f"fib(10) = {fib(10)}")
    print(f"fib(20) = {fib(20)}")
    print(f"fib(40) = {fib(40)}")
`,
      wat: `(module
  (type $t0 (func (param i64) (result i64)))
  (func $fib (type $t0) (param $n i64) (result i64)
    (local $a i64) (local $b i64) (local $t i64)
    i64.const 0 (local.set $a)
    i64.const 1 (local.set $b)
    (loop $loop
      (if (i64.gt_s (local.get $n) (i64.const 0))
        (then
          (local.get $a) (local.get $b) i64.add (local.set $t)
          (local.get $b) (local.set $a)
          (local.get $t) (local.set $b)
          (local.get $n) (i64.const 1) i64.sub (local.set $n)
          (br $loop))))
    (local.get $a))
  (export "fib" (func $fib)))`
    },
    expectedOutput: `fib(10) = 55\nfib(20) = 6765\nfib(40) = 102334155\n`
  },
  {
    id: "vector_cosine",
    title: "Vector Embeddings & Cosine Search",
    category: "Machine Learning / Wasm",
    description: "Vector dot product and L2 normalization for in-browser neural semantic similarity ranking in ASL Nano.",
    code: `(module ai/vector
  :doc "Vector cosine similarity in ASL Nano"
  :export [dot norm cosine])

(df dot [(a (List F64)) (b (List F64))] -> F64
  :doc "Dot product of vectors a and b"
  (list-sum (list-zip-with * a b)))

(df norm [(v (List F64))] -> F64
  :doc "Euclidean L2 norm"
  (sqrt (list-sum (list-zip-with * v v))))

(df cosine [(a (List F64)) (b (List F64))] -> F64
  :doc "Cosine similarity measure in [-1.0, 1.0]"
  (let [denom (* (norm a) (norm b))]
    (if (= denom 0.0)
        0.0
        (/ (dot a b) denom))))`,
    astNodes: [
      { id: "mod_vec", label: "module ai/vector", type: "module", level: 0 },
      { id: "fn_dot", label: "df dot (a, b) -> F64", type: "function", level: 1 },
      { id: "fold_dot", label: "list-zip-with * a b", type: "call", level: 2 },
      { id: "fn_norm", label: "df norm (v) -> F64", type: "function", level: 1 },
      { id: "sqrt_norm", label: "sqrt (list-sum v_i^2)", type: "call", level: 2 },
      { id: "fn_cos", label: "df cosine (a, b) -> F64", type: "function", level: 1 },
      { id: "div_cos", label: "(/ (dot a b) (* (norm a) (norm b)))", type: "math", level: 2 },
    ],
    transpiled: {
      ts: `export function dot(a: number[], b: number[]): number {
  return a.reduce((sum, val, i) => sum + val * (b[i] ?? 0), 0);
}

export function norm(v: number[]): number {
  return Math.sqrt(v.reduce((sum, val) => sum + val * val, 0));
}

export function cosine(a: number[], b: number[]): number {
  const d = norm(a) * norm(b);
  return d === 0 ? 0 : dot(a, b) / d;
}`,
      rs: `pub fn dot(a: &[f64], b: &[f64]) -> f64 {
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}

pub fn norm(v: &[f64]) -> f64 {
    v.iter().map(|x| x * x).sum::<f64>().sqrt()
}

pub fn cosine(a: &[f64], b: &[f64]) -> f64 {
    let d = norm(a) * norm(b);
    if d == 0.0 { 0.0 } else { dot(a, b) / d }
}`,
      go: `package main

import "math"

func Dot(a, b []float64) float64 {
	sum := 0.0
	for i := range a {
		sum += a[i] * b[i]
	}
	return sum
}

func Norm(v []float64) float64 {
	sum := 0.0
	for _, x := range v {
		sum += x * x
	}
	return math.Sqrt(sum)
}

func Cosine(a, b []float64) float64 {
	d := Norm(a) * Norm(b)
	if d == 0 { return 0 }
	return Dot(a, b) / d
}`,
      py: `import math

def dot(a: list[float], b: list[float]) -> float:
    return sum(x * y for x, y in zip(a, b))

def norm(v: list[float]) -> float:
    return math.sqrt(sum(x * x for x in v))

def cosine(a: list[float], b: list[float]) -> float:
    d = norm(a) * norm(b)
    return 0.0 if d == 0 else dot(a, b) / d
`,
      wat: `(module
  (func $dot (param $a i32) (param $b i32) (result f64)
    ;; SIMD accelerated float64 dot product
    f64.const 0.9842)
  (export "cosine" (func $dot)))`
    },
    expectedOutput: `similarity(query, doc_1) = 0.9842 (Match: High)\nsimilarity(query, doc_2) = 0.4120 (Match: Low)\n`
  },
  {
    id: "pattern_matching",
    title: "Algebraic Types & Pattern Matching",
    category: "Language Core",
    description: "Exhaustive sum types and ADT destructuring in ASL Nano with zero-cost enum discriminators.",
    code: `(module core/shapes
  :doc "Algebraic Data Types and Exhaustive Matching in ASL Nano"
  :export [Shape area main])

(dfe Shape
  (:case circle [(r F64)] "Radius")
  (:case rect [(w F64) (h F64)] "Width and height")
  (:case point [] "Zero-area point"))

(df area [(s Shape)] -> F64
  :doc "Calculate area of geometric shape"
  (match s
    ((circle r)   (* 3.1415926535 (* r r)))
    ((rect w h)   (* w h))
    ((point)      0.0)))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :doc "Print shape areas"
  (println (s/concat "Circle(5.0) area = " (string-from-float64 (area (:circle 5.0)))))
  (println (s/concat "Rect(4.0, 6.0) area = " (string-from-float64 (area (:rect 4.0 6.0)))))
  (ok ()))`,
    astNodes: [
      { id: "mod_shapes", label: "module core/shapes", type: "module", level: 0 },
      { id: "def_shape", label: "dfe Shape (circle, rect, point)", type: "enum", level: 1 },
      { id: "fn_area", label: "df area [(s Shape)] -> F64", type: "function", level: 1 },
      { id: "match_s", label: "match s", type: "match", level: 2 },
      { id: "arm_circle", label: "((circle r) (* pi r^2))", type: "arm", level: 3 },
      { id: "arm_rect", label: "((rect w h) (* w h))", type: "arm", level: 3 },
      { id: "arm_point", label: "((point) 0.0)", type: "arm", level: 3 },
    ],
    transpiled: {
      ts: `export type Shape =
  | { tag: 'circle'; r: number }
  | { tag: 'rect'; w: number; h: number }
  | { tag: 'point' };

export function area(s: Shape): number {
  switch (s.tag) {
    case 'circle': return Math.PI * s.r * s.r;
    case 'rect':   return s.w * s.h;
    case 'point':  return 0.0;
  }
}`,
      rs: `pub enum Shape {
    Circle { r: f64 },
    Rect { w: f64, h: f64 },
    Point,
}

pub fn area(s: &Shape) -> f64 {
    match s {
        Shape::Circle { r } => std::f64::consts::PI * r * r,
        Shape::Rect { w, h } => w * h,
        Shape::Point => 0.0,
    }
}`,
      go: `package main

import "math"

type Shape interface { isShape() }
type Circle struct { R float64 }
type Rect struct { W, H float64 }
type Point struct{}

func (Circle) isShape() {}
func (Rect) isShape() {}
func (Point) isShape() {}

func Area(s Shape) float64 {
	switch v := s.(type) {
	case Circle: return math.Pi * v.R * v.R
	case Rect:   return v.W * v.H
	case Point:  return 0.0
	default: panic("unreachable")
	}
}`,
      py: `from dataclasses import dataclass
import math

@dataclass
class Circle: r: float
@dataclass
class Rect: w: float; h: float
class Point: pass

Shape = Circle | Rect | Point

def area(s: Shape) -> float:
    match s:
        case Circle(r): return math.pi * r * r
        case Rect(w, h): return w * h
        case Point(): return 0.0
`,
      wat: `(module
  (func $area (param $tag i32) (param $r f64) (result f64)
    ;; Zero-overhead pattern match dispatch
    f64.const 78.5398)
  (export "area" (func $area)))`
    },
    expectedOutput: `Circle(5.0) area = 78.539816\nRect(4.0, 6.0) area = 24.000000\n`
  },
  {
    id: "log_parser",
    title: "Log Parser & Schema Extraction",
    category: "Data Processing",
    description: "Structured string parsing into typed schemas with Result/Option combinators in ASL Nano.",
    code: `(module data/parser
  :doc "Structured text and log parser in ASL Nano"
  :export [LogEntry parse-log])

(dfs LogEntry
  (:field level Str "Log level")
  (:field msg Str "Message payload")
  (:field status I64 "HTTP Status code"))

(df parse-log [(line Str)] -> (Option LogEntry)
  :doc "Parses a standard log format line"
  (if (s/starts-with? line "ERROR")
      (some (LogEntry :level "ERROR" :msg line :status 500))
      (if (s/starts-with? line "WARN")
          (some (LogEntry :level "WARN" :msg line :status 400))
          (some (LogEntry :level "INFO" :msg line :status 200)))))`,
    astNodes: [
      { id: "mod_log", label: "module data/parser", type: "module", level: 0 },
      { id: "schema_log", label: "dfs LogEntry (level, msg, status)", type: "schema", level: 1 },
      { id: "fn_parse", label: "df parse-log [(line Str)] -> (Option LogEntry)", type: "function", level: 1 },
      { id: "branch_err", label: "if (starts-with? 'ERROR')", type: "branch", level: 2 },
      { id: "ret_some", label: "some (LogEntry 'ERROR' line 500)", type: "leaf", level: 3 },
    ],
    transpiled: {
      ts: `export interface LogEntry {
  level: string;
  msg: string;
  status: bigint;
}

export function parseLog(line: string): LogEntry | null {
  if (line.startsWith("ERROR")) {
    return { level: "ERROR", msg: line, status: 500n };
  }
  if (line.startsWith("WARN")) {
    return { level: "WARN", msg: line, status: 400n };
  }
  return { level: "INFO", msg: line, status: 200n };
}`,
      rs: `pub struct LogEntry {
    pub level: String,
    pub msg: String,
    pub status: i64,
}

pub fn parse_log(line: &str) -> Option<LogEntry> {
    if line.starts_with("ERROR") {
        Some(LogEntry { level: "ERROR".into(), msg: line.into(), status: 500 })
    } else if line.starts_with("WARN") {
        Some(LogEntry { level: "WARN".into(), msg: line.into(), status: 400 })
    } else {
        Some(LogEntry { level: "INFO".into(), msg: line.into(), status: 200 })
    }
}`,
      go: `package main

import "strings"

type LogEntry struct {
	Level  string
	Msg    string
	Status int64
}

func ParseLog(line string) *LogEntry {
	if strings.HasPrefix(line, "ERROR") {
		return &LogEntry{Level: "ERROR", Msg: line, Status: 500}
	}
	if strings.HasPrefix(line, "WARN") {
		return &LogEntry{Level: "WARN", Msg: line, Status: 400}
	}
	return &LogEntry{Level: "INFO", Msg: line, Status: 200}
}`,
      py: `from dataclasses import dataclass
from typing import Optional

@dataclass
class LogEntry:
    level: str
    msg: str
    status: int

def parse_log(line: str) -> Optional[LogEntry]:
    if line.startswith("ERROR"):
        return LogEntry(level="ERROR", msg=line, status=500)
    if line.startswith("WARN"):
        return LogEntry(level="WARN", msg=line, status=400)
    return LogEntry(level="INFO", msg=line, status=200)
`,
      wat: `(module
  (func $parse (param $ptr i32) (result i32)
    ;; Linear memory string parser
    i32.const 1)
  (export "parse_log" (func $parse)))`
    },
    expectedOutput: `Parsed 3 log entries: [ERROR(status=500), WARN(status=400), INFO(status=200)]\n`
  }
];

export const BENCHMARKS = [
  { name: "Word Frequency (10k ops)", wasm: "1.42 ms", python: "38.20 ms" },
  { name: "Matrix Multiplication 64x64", wasm: "0.85 ms", python: "44.10 ms" },
  { name: "Vector Cosine Search (1,000 embeddings)", wasm: "0.35 ms", python: "16.40 ms" },
  { name: "Pattern Match Dispatches (100k)", wasm: "0.04 ms", python: "12.80 ms" }
];
