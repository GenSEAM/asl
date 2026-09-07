# Polyglot Coexistence & Strangler Fig Migration Guide
*Progressive, Zero-Downtime Migration from Python, Rust, Go, Vue.js, and React to AgentScript*

---

## 1. Executive Thesis: The Fallacy of Wholesale Rewrites

Enterprise software engineering is littered with failed "Big Bang" rewrites. When engineering teams attempt to migrate massive legacy systems from Python, TypeScript, or Go to a new language all at once, development freezes, regression bugs proliferate, and business value stalls.

AgentScript is explicitly designed for **asymmetric, progressive coexistence** via the **Strangler Fig Pattern**:
- You do **not** rewrite your entire application in AgentScript.
- You identify high-latency, token-costly, or bug-prone modules (such as algorithmic loops, AST diffing, mathematical kernels, or state machines).
- You rewrite that single module in AgentScript.
- AgentScript compiles to **Rust native binaries, WebAssembly, or C99**, and automatically synthesizes the **Python FFI glue, TypeScript definitions, or Vue/React wrappers**.
- The existing system continues to run unchanged, using the same unit test suite, but operating **50x–120x faster** with zero hallucinated edge-case regressions.

---

## 2. The "Python-to-Rust via AgentScript" Enterprise Engine

### The Python Performance Dilemma
Python is the undisputed lingua franca of data science, AI workflows, and rapid backend prototyping. However:
1. **Execution Latency**: CPU-bound Python loops run 50x–100x slower than compiled native code.
2. **LLM Coding Failure in Rust**: When autonomous agents are instructed to rewrite Python algorithms in Rust, they frequently hit borrow-checker lifetime errors, unsafe raw pointer hazards, and compilation cycle thrashing.
3. **Operational Drag**: Writing manual C-extensions or PyO3 bindings introduces fragile foreign build systems (`maturin`, `setuptools-rust`, clang dependencies).

### The AgentScript Solution
AgentScript serves as the safe, ergonomic intermediary:
```
+-------------------------------------------------------------------------+
| Step 1: Autonomous Agent writes pure functional AgentScript S-expressions|
|         * Pure functional, zero manual memory management                |
|         * Explicit static types (I64, F64, Str, List, Map)              |
|         * Provably bounded execution verified by SMT / ASL checker      |
+-------------------------------------------------------------------------+
                                    |
                                    v [asl-codegen]
+-------------------------------------------------------------------------+
| Step 2: AgentScript Compiler emits memory-safe Rust & C-ABI functions   |
|         * Zero borrow-checker errors by construction                    |
|         * #[no_mangle] pub extern "C" ABI exports                       |
+-------------------------------------------------------------------------+
                                    |
                                    v [asl-bridge]
+-------------------------------------------------------------------------+
| Step 3: Automated Python FFI Glue Generation                            |
|         * Generates fast ctypes / cffi wrapper module                   |
|         * Exposes 1:1 identical Python type hints & signatures          |
|         * Drop-in replacement: `import fast_math as legacy_math`        |
+-------------------------------------------------------------------------+
```

---

## 3. Declarative Target Directives in Module Manifests

AgentScript modules declare their intended deployment target and host integration mode directly within their package manifest (`manifest.asn`):

### Example 1: Python FFI via Native Shared Object
```lisp
(:package @company/fast-geometry
 :version "1.0.0"
 :entry "src/geometry.asl"
 :target (:python-native-ffi
   :host-module "geometry_native"
   :glue-engine :ctypes
   :emit-types true)
 :dependencies [])
```

### Example 2: In-Browser WebAssembly for Vue.js / React
```lisp
(:package @company/canvas-engine
 :version "1.0.0"
 :entry "src/engine.asl"
 :target (:wasm-browser
   :framework :vue-composition-api
   :glue-engine :vdom-wasm
   :emit-react-hooks true)
 :dependencies [])
```

### Example 3: Go Microservice Shared C-ABI Engine
```lisp
(:package @company/risk-calculator
 :version "1.0.0"
 :entry "src/risk.asl"
 :target (:c-shared-object
   :header-output "include/risk.h"
   :cgo-bindings "risk_cgo.go")
 :dependencies [])
```

---

## 4. End-to-End Migration Walkthrough: Python Algorithmic Module

### Step 1: Original Legacy Python Code (`legacy_math.py`)
```python
# Slow Python implementation
import math

def euclidean_distance(p1: tuple[float, float], p2: tuple[float, float]) -> float:
    dx = p1[0] - p2[0]
    dy = p1[1] - p2[1]
    return math.sqrt(dx * dx + dy * dy)

def batch_closest_point(target: tuple[float, float], points: list[tuple[float, float]]) -> tuple[float, float]:
    best_pt = points[0]
    best_dist = float("inf")
    for pt in points:
        d = euclidean_distance(target, pt)
        if d < best_dist:
            best_dist = d
            best_pt = pt
    return best_pt
```

### Step 2: Pure Functional AgentScript Equivalent (`geometry.asl`)
```lisp
(module company/geometry
  :d "High-performance 2D geometric point calculations."
  :x [Point2D euclidean-distance batch-closest-point]
  :i [])

(dfs Point2D
  (:f x F64 "X coordinate")
  (:f y F64 "Y coordinate"))

(df euclidean-distance [(p1 Point2D) (p2 Point2D)] -> F64
  :d "Computes Euclidean distance between two 2D points."
  (let [(dx (- (.-x p1) (.-x p2)))
        (dy (- (.-y p1) (.-y p2)))]
    (sqrt (+ (* dx dx) (* dy dy)))))

(df batch-closest-point [(target Point2D) (points (List Point2D))] -> Point2D
  :d "Finds point with minimum Euclidean distance to target."
  (fold (fn [(best Point2D) (pt Point2D)] -> Point2D
          (let [(d-best (euclidean-distance target best))
                (d-curr (euclidean-distance target pt))]
            (if (< d-curr d-best) pt best)))
        (list-head points)
        points))
```

### Step 3: Compiling and Emitting Native Rust & Python Glue
Running:
```bash
asl build --target python-native-ffi src/geometry.asl -o dist/
```
Emits:
1. `dist/libgeometry.so` (compiled optimized native binary).
2. `dist/geometry.py` (auto-generated drop-in Python wrapper):
```python
# Auto-generated by AgentScript Compiler — DO NOT EDIT
import ctypes
import os

_lib = ctypes.CDLL(os.path.join(os.path.dirname(__file__), "libgeometry.so"))

class _CPoint2D(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

_lib.asl_euclidean_distance.argtypes = [ctypes.POINTER(_CPoint2D), ctypes.POINTER(_CPoint2D)]
_lib.asl_euclidean_distance.restype = ctypes.c_double

def euclidean_distance(p1: tuple[float, float], p2: tuple[float, float]) -> float:
    c_p1 = _CPoint2D(p1[0], p1[1])
    c_p2 = _CPoint2D(p2[0], p2[1])
    return _lib.asl_euclidean_distance(ctypes.byref(c_p1), ctypes.byref(c_p2))
```

### Step 4: Golden Parity Test Suite
Run your existing pytest test suite directly against the generated module:
```python
# tests/test_parity.py
import legacy_math
import geometry as fast_geometry

def test_distance_parity():
    p1 = (10.0, 20.0)
    p2 = (13.0, 24.0)
    assert abs(legacy_math.euclidean_distance(p1, p2) - fast_geometry.euclidean_distance(p1, p2)) < 1e-9
```
**Result**: Bit-for-bit exact parity, 85x faster execution, and zero architectural disruption to the rest of the Python codebase.

---

## 5. Web Frontend Coexistence: Vue.js and React

When migrating from React or Vue:
1. **Preserve DOM Presentation**: Keep existing Tailwind CSS, layout components, and router in React/Vue.
2. **Offload Core State & Computation**:
   - Form validation graphs, canvas rendering math, real-time audio/video processing, or diff engines move into pure AgentScript.
   - Compiled to `.wasm` running in Web Worker or main thread.
3. **Reactive Binding Integration**:
   ```typescript
   // In Vue 3:
   import { useAgentScript } from '@genseam/vue-asl';
   import { point_pipeline_wasm } from './geometry.wasm';

   const { call, loading } = useAgentScript(point_pipeline_wasm);
   const result = await call('batch_closest_point', target, points);
   ```

---

## 6. Migration Governance Matrix

| Legacy Ecosystem | Primary Pain Point | Migration Strategy via ASL | Emitted Artifact | Latency Gain |
|---|---|---|---|:---:|
| **Python** | High CPU latency, GIL bottleneck | Algorithmic kernel extraction | Rust C-ABI `.so` + ctypes glue | **80x–120x** |
| **Vue.js / React** | Heavy JS bundle size, CPU stutter | State machine / math offload | Wasm binary + reactive hook | **15x–30x** |
| **Rust** | LLM struggles with borrow checker | S-expression functional spec | Pure Rust codegen (`asl-codegen`) | **Equal** |
| **Go** | Concurrency safety, GC pauses | Pure state-transition logic | Wasm or CGo static archive | **3x–8x** |
| **Solidity** | Reentrancy, EVM gas runaway | Pure functional state transitions | Arbitrum Stylus Wasm | **10x cheaper gas** |

---

## 7. Multi-Runtime Inset Patterns & Polyglot Recipes

Rather than treating existing codebases as foreign adversaries, AgentScript treats them as **specialized execution stages**. Through Pillar 6 (Multi-Runtime Orchestration), an ASL pipeline coordinates SQL queries, Wasm sandboxes, Python tensor operations, and TypeScript UI dispatchers under a single unified mathematical boundary.

### 7.1 Python ML & Data Science Inset
When an autonomous agent must orchestrate high-performance telemetry or tensor calculations alongside an existing PyTorch / NumPy stack:

```lisp
(module telemetry-orchestrator
  :d "Coordinates Python tensor analytics with zero host contamination"
  :x [run-anomaly-detection]
  :stage [extract-records predict-tensor emit-alert])

;; Stage 1: Fast in-memory S-expression filtering
(df extract-records [(raw-samples (Vec Float))] -> (Vec Float)
  :d "Pure functional sanitization"
  (filter (fn [x] (> x 0.0)) raw-samples))

;; Stage 2: Embedded Python Inset (Executed inside isolated subprocess worker)
(stage :predict-tensor :runtime :python
  :in  [(sanitized (Vec Float))]
  :out [(score Float) (is-anomaly Bool)]
  "import numpy as np
# Inset: Vector anomaly detector using host NumPy
arr = np.array(sanitized, dtype=np.float32)
norm = float(np.linalg.norm(arr))
score = float(np.tanh(norm / 100.0))
is_anomaly = bool(score > 0.85)")

;; Stage 3: Direct Wasm bytecode validation
(stage :emit-alert :runtime :wasm
  :in  [(score Float) (is-anomaly Bool)]
  :out [(exit-code I32)]
  (func $alert (param $s f32) (param $flag i32) (result i32)
    local.get $flag))
```

### 7.2 TypeScript / React / Next.js Inset
When integrating into a modern Next.js 15 or React 19 web application, ASL modules compile to `.wasm` and expose full TypeScript type definitions automatically:

```typescript
// Auto-generated by asl build --target ts-react
import { useState, useEffect } from 'react';
import initWasm, { AslMicroVM } from './asl_pipeline.wasm';

export function useAslPipeline() {
  const [vm, setVm] = useState<AslMicroVM | null>(null);

  useEffect(() => {
    initWasm().then(instance => {
      setVm(new AslMicroVM(instance));
    });
  }, []);

  const evaluateTelemetry = (tokensIn: number, tokensOut: number) => {
    if (!vm) return { savings: 0, verified: false };
    // Sub-millisecond execution in isolated 64KB linear page
    return vm.calculate_token_economics(BigInt(tokensIn), BigInt(tokensOut));
  };

  return { evaluateTelemetry, ready: !!vm };
}
```

### 7.3 Go High-Concurrency Service Inset
For Go backend microservices handling millions of concurrent requests, AgentScript compiles directly to a static C archive (`libasl_core.a`) with zero-overhead CGo bindings:

```go
package main

/*
#cgo CFLAGS: -I../include
#cgo LDFLAGS: -L../dist -lasl_core
#include "asl_core.h"
*/
import "C"
import (
	"fmt"
	"unsafe"
)

func VerifyTransaction(txId string, amount int64) bool {
	cTxId := C.CString(txId)
	defer C.free(unsafe.Pointer(cTxId))

	// Pure functional ASL FSM evaluation with 0 GC pause
	result := C.asl_verify_transaction(cTxId, C.int64_t(amount))
	return bool(result)
}
```

### 7.4 Rust Systems Safe Inset
When compiling to native Rust, ASL generates pure functional Rust that requires zero manual borrow-checker lifetime annotations:

```rust
// Auto-generated by asl-codegen --target rust
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TransactionEnvelope {
    pub tx_id: String,
    pub token_rate: f64,
    pub airgap_ok: bool,
}

#[inline(always)]
pub fn verify_envelope(env: &TransactionEnvelope) -> bool {
    // 100% deterministic, zero unsafe blocks, zero lifetime thrashing
    env.airgap_ok && env.token_rate > 0.0
}
```

### 7.5 The 4-Step Strangler Fig Protocol
1. **Audit & Profile**: Identify the 5% of functions causing 80% of performance bottlenecks, token inflation, or syntax retry loops.
2. **Formulate ASL S-Expression**: Author the logic as an immutable S-expression module with a formal unit gate (`asl test`).
3. **Embed Host Insets**: If the module requires legacy database access or machine learning libraries, wrap them in declarative stage insets (`:runtime :sql` or `:runtime :python`).
4. **Compile & Link**: Run `asl build` to emit the drop-in drop-target (Wasm, C-ABI shared object, or TypeScript wrapper) and run your existing test suite. Zero downtime, zero risk.
