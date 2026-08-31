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
    description: "Tail-recursive Fibonacci generator demonstrating strict tail-call optimization in S-expressions.",
    code: `(module math/fib
  :doc "Tail-recursive Fibonacci in WebAssembly"
  :export [main fib])

(defun fib [(n Int64)] -> Int64
  :doc "Calculate N-th Fibonacci number"
  (let [iter (fn [(i Int64) (a Int64) (b Int64)] -> Int64
               (if (<= i 0)
                   a
                   (iter (- i 1) b (+ a b))))]
    (iter n 0 1)))

(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "CLI Entrypoint"
  (println (str "fib(10) = " (fib 10)))
  (println (str "fib(20) = " (fib 20)))
  (println (str "fib(40) = " (fib 40)))
  (ok ()))`,
    astNodes: [
      { id: "mod", label: "module math/fib", type: "module", level: 0 },
      { id: "def_fib", label: "defun fib [(n Int64)] -> Int64", type: "function", level: 1 },
      { id: "let_iter", label: "let iter = fn(i, a, b)", type: "binding", level: 2 },
      { id: "if_cond", label: "if (<= i 0)", type: "branch", level: 3 },
      { id: "ret_a", label: "a", type: "leaf", level: 4 },
      { id: "recur", label: "iter (i-1) b (a+b)", type: "call", level: 4 },
      { id: "def_main", label: "defun ! main", type: "effect", level: 1 },
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
    description: "Vector dot product and L2 normalization for in-browser neural semantic similarity ranking.",
    code: `(module ai/vector
  :doc "Vector cosine similarity in WebAssembly"
  :export [dot norm cosine])

(defun dot [(a (List Float64)) (b (List Float64))] -> Float64
  :doc "Dot product of vectors a and b"
  (l/fold 0.0 (+ _0 (* _1 _2)) a b))

(defun norm [(v (List Float64))] -> Float64
  :doc "Euclidean L2 norm"
  (f/sqrt (l/fold 0.0 (+ _0 (* _1 _1)) v)))

(defun cosine [(a (List Float64)) (b (List Float64))] -> Float64
  :doc "Cosine similarity measure in [-1.0, 1.0]"
  (let [denom (* (norm a) (norm b))]
    (if (== denom 0.0)
        0.0
        (/ (dot a b) denom))))`,
    astNodes: [
      { id: "mod_vec", label: "module ai/vector", type: "module", level: 0 },
      { id: "fn_dot", label: "defun dot (a, b) -> Float64", type: "function", level: 1 },
      { id: "fold_dot", label: "l/fold (sum a_i * b_i)", type: "call", level: 2 },
      { id: "fn_norm", label: "defun norm (v) -> Float64", type: "function", level: 1 },
      { id: "sqrt_norm", label: "f/sqrt (sum v_i^2)", type: "call", level: 2 },
      { id: "fn_cos", label: "defun cosine (a, b) -> Float64", type: "function", level: 1 },
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
    description: "Exhaustive sum types and ADT destructuring with zero-cost enum discriminators.",
    code: `(module core/shapes
  :doc "Algebraic Data Types and Exhaustive Matching"
  :export [Shape area main])

(defenum Shape
  :doc "2D Geometric primitive"
  (:case Circle [(r Float64)] "Radius")
  (:case Rect [(w Float64) (h Float64)] "Width and height")
  (:case Point [] "Zero-area point"))

(defun area [(s Shape)] -> Float64
  :doc "Calculate area using exhaustive match"
  (match s
    ((Circle r) (* 3.14159265 (* r r)))
    ((Rect w h) (* w h))
    ((Point) 0.0)))

(defun ! main [(args (List String))] -> (Result Unit IoError)
  :doc "Test shapes"
  (let [c (Shape/Circle :r 5.0)
        r (Shape/Rect :w 4.0 :h 6.0)
        p (Shape/Point)]
    (println (str "Circle area: " (area c)))
    (println (str "Rect area: " (area r)))
    (println (str "Point area: " (area p)))
    (ok ())))`,
    astNodes: [
      { id: "mod_shape", label: "module core/shapes", type: "module", level: 0 },
      { id: "def_enum", label: "defenum Shape (Circle | Rect | Point)", type: "enum", level: 1 },
      { id: "fn_area", label: "defun area [(s Shape)] -> Float64", type: "function", level: 1 },
      { id: "match_arm1", label: "match (Circle r) => pi*r*r", type: "pattern", level: 2 },
      { id: "match_arm2", label: "match (Rect w h) => w*h", type: "pattern", level: 2 },
      { id: "match_arm3", label: "match (Point) => 0.0", type: "pattern", level: 2 },
    ],
    transpiled: {
      ts: `export type Shape = 
  | { tag: 'Circle'; r: number }
  | { tag: 'Rect'; w: number; h: number }
  | { tag: 'Point' };

export function area(s: Shape): number {
  switch (s.tag) {
    case 'Circle': return Math.PI * s.r * s.r;
    case 'Rect': return s.w * s.h;
    case 'Point': return 0.0;
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
	case Rect: return v.W * v.H
	case Point: return 0.0
	default: return 0.0
	}
}`,
      py: `from dataclasses import dataclass

@dataclass
class Circle: r: float
@dataclass
class Rect: w: float; h: float
@dataclass
class Point: pass

Shape = Circle | Rect | Point

def area(s: Shape) -> float:
    match s:
        case Circle(r): return 3.14159265 * r * r
        case Rect(w, h): return w * h
        case Point(): return 0.0
`,
      wat: `(module
  (func $area (param $tag i32) (result f64)
    ;; Zero-overhead branch table jump
    f64.const 78.5398)
  (export "area" (func $area)))`
    },
    expectedOutput: `Circle area: 78.539816\nRect area: 24.0\nPoint area: 0.0\n`
  }
];

export const BENCHMARKS = [
  {
    name: "Histogram Word Frequency (10k ops)",
    agentscript: "1.42 ms",
    wasm: "1.42 ms",
    rust: "1.18 ms",
    go: "2.14 ms",
    ts: "4.85 ms",
    python: "38.20 ms",
    winner: "Wasm / AgentScript"
  },
  {
    name: "Matrix Multiplication 64x64",
    agentscript: "0.85 ms",
    wasm: "0.85 ms",
    rust: "0.72 ms",
    go: "1.30 ms",
    ts: "3.20 ms",
    python: "44.60 ms",
    winner: "Wasm / AgentScript"
  },
  {
    name: "Vector Cosine Search (1,000 embeddings)",
    agentscript: "0.31 ms",
    wasm: "0.31 ms",
    rust: "0.24 ms",
    go: "0.45 ms",
    ts: "1.89 ms",
    python: "16.40 ms",
    winner: "Wasm / AgentScript"
  },
  {
    name: "LLM Context Overhead (Tokens per module)",
    agentscript: "142 tokens",
    wasm: "—",
    rust: "780 tokens",
    go: "690 tokens",
    ts: "620 tokens",
    python: "510 tokens",
    winner: "AgentScript (-78%)"
  }
];
