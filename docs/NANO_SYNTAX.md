# ⚡ ASL Nano Specification (Canonical Standard)

**ASL Nano** is the primary, agent-native syntax for AgentScript. Designed specifically for LLM code generation and multi-agent swarms, it eliminates human-centric syntax verbosity while preserving deterministic S-expression structure and full §9 verification.

---

## 1. Syntax Mapping

| Construct | Legacy Verbose | Dense Sugar | **ASL Nano (Canonical)** |
| :--- | :--- | :--- | :--- |
| **Function Definition** | `(defun name [args] -> Ret body)` | `(def name [args] -> Ret body)` | **`(df name [args] -> Ret body)`** |
| **Schema Definition** | `(defschema Name fields...)` | `(schema Name fields...)` | **`(dfs Name fields...)`** |
| **Enum / ADT Definition**| `(defenum Name cases...)` | `(enum Name cases...)` | **`(dfe Name cases...)`** |
| **64-bit Float** | `Float64` | `Num` / `Float` | **`F64`** |
| **64-bit Integer** | `Int64` | `Int` | **`I64`** |
| **String** | `String` | `Str` | **`Str`** |
| **Boolean** | `Bool` | `Bool` | **`Bool`** |
| **Unit** | `Unit` | `Unit` | **`Unit`** |

---

## 2. Example: Autonomous Vector Engine in ASL Nano

```lisp
(module math/vector
  :doc "High-performance vector operations in ASL Nano"
  :export [Point dot-product norm])

(dfs Point
  (:field x F64 "x coordinate")
  (:field y F64 "y coordinate"))

(df dot-product [(a (List F64)) (b (List F64))] -> F64
  :doc "Vector dot product"
  (list-sum (list-zip-with * a b)))

(df norm [(v (List F64))] -> F64
  :doc "Euclidean vector norm"
  (sqrt (dot-product v v)))
```

---

## 3. Backward Compatibility Invariant
All legacy forms (`defun`, `defschema`, `defenum`, `Float64`, `Int64`, `String`) remain 100% valid and verified across all compiler backends (Wasm, TypeScript, Rust, Go, Python, C Interpreter).
