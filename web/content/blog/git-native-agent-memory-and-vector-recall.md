# Git-Native Agent Memory: Versioned Ledgers and In-Process Vector Recall
*By GenSEAM | September 2026*

Autonomous agents cannot act effectively without persistent memory. When a coding agent explores a large codebase, inspects test failures or checks architectural invariants, it has to keep what it learned across subagent delegations and session boundaries.

The contemporary approach to agent memory relies on **cloud vector databases over HTTP**:

```text
Agent Execution Loop:
1. Agent generates an observation.
2. HTTP POST to an external vector DB (Pinecone, Qdrant, Weaviate).
3. A subagent queries context -> HTTP embedding search.
4. Payload parsed from JSON -> injected into the agent prompt.
```

This architecture has three failure modes:

1. **A Network Round Trip per Lookup:** every recall pays the network, and a swarm of subagents making several lookups per step pays it many times over.
2. **Epistemic Desynchronization:** a hosted vector store keeps its state outside version control. When a developer rolls back a commit, switches branches or merges a PR, the store still holds knowledge of code that no longer exists.
3. **External Dependencies:** a network partition or an API rate limit in the store stalls the agent loop.

We have not benchmarked a hosted vector database against local recall, so this post makes no latency comparison with one. The argument is about where memory lives and what it is versioned with.

---

## 1. The Arithmetic of Working-Set Recall

Agent working memory (observations, decisions, symbol contracts) is small next to what vector databases are built for, and a linear scan is a reasonable starting point.

Consider a 384-dimensional dense embedding (the size of `all-MiniLM-L6-v2` and similar local embedding models):
* A vector of 384 `Float32` elements occupies **1,536 bytes**.
* 10,000 such vectors occupy **15.36 MB**.
* Cosine similarity between a query `q` and a candidate `v` is `dot(q, v) / (|q| * |v|)`. When vectors are stored at unit length, it is the dot product alone.

One measurement on today's interpreter: on 2026-10-14 we ran `asl-host test` on a file that builds 10,000 384-dimensional `F64Array` vectors and takes each one's dot product with a query. Over five runs on a 4-core Linux cloud VM (Intel Xeon, 2.8 GHz), timed as whole-process wall time from Python's `subprocess.run`, the median was 0.37 s, vector construction and host start-up included. The same scan over 1,000 vectors took a median of 0.05 s.

---

## 2. Recall in Plain AgentScript

The stage-0 host binds unboxed `F64Array` builtins (`f64ArrayGenerate`, `f64ArrayGet`, `f64ArrayLen`, `f64ArraySum`, among others) and `sqrt`, which is enough for an in-process cosine scan. This sample passes `asl-host check` and `asl-host test` (3 assertions):

```asl
(module probe/p13eTest :x [dot cosine topMatch runTests] :i [])

schema VectorItem
  id: String
  vector: F64Array

fn dot a: F64Array b: F64Array -> Float64
  (f64ArraySum (f64ArrayGenerate (f64ArrayLen a) (fn [i] (* (f64ArrayGet a i) (f64ArrayGet b i)))))

fn cosine a: F64Array b: F64Array -> Float64
  (/ (dot a b) (* (sqrt (dot a a)) (sqrt (dot b b))))

fn topMatch query: F64Array items: (List VectorItem) -> (Option String)
  (mt (listHead (listSortBy (fn [it] (- 0.0 (cosine query it.vector))) items))
    ((some best) (some best.id))
    ((none) (none)))

fn vec2 x: Float64 y: Float64 -> F64Array
  (f64ArrayGenerate 2 (fn [i] (if (= i 0) x y)))

fn runTests -> Bool
  (let [(items (list {:id "east" :vector (vec2 2.0 0.0)} {:id "north" :vector (vec2 0.0 5.0)}))]
    (do
      (assert (= (cosine (vec2 3.0 4.0) (vec2 6.0 8.0)) 1.0) "parallel vectors")
      (assert (= (topMatch (vec2 4.0 3.0) items) (some "east")) "nearest is east")
      (assert (= (topMatch (vec2 3.0 4.0) (list)) (none)) "empty store")
      true))
```

The repository also carries a fuller store in `asl/packages/asl-mem/src/store.asl` (vector items, dimension validation, normalization, a flat slab layout). Its math suite, `asl/packages/asl-mem/tests/mathTest.asl`, passes on the strict host (27 assertions, 2026-10-14). That store keeps vectors as `(List F64)`; moving it onto the unboxed `F64Array` builtins shown above is open work.

---

## 3. Git-Native Persistence: Memory Versioned With the Code

The weakness of a hosted vector database is **temporal decoupling**: a convention stored there is global, mutable and blind to Git branches.

The toolbelt keeps agent memory as ASN ledgers under `.asl/mem/` in the repository it works on, so the ledgers can be tracked in Git like any other file. The `(:mem)` op lists, gets and queries rows there, and `(:mem :op put ...)` stages a row change through the same buffer as `(:edit)`, written only by `(:flush)`. Paths outside `.asl/mem` are rejected with `ERR_BOUNDARY_VIOLATION`. Tracked in Git, that gives three properties:
1. **Memory as Repository Data:** plans, decisions and findings are plain S-expression files next to the code they describe.
2. **Branch-Aware Context:** checking out a branch checks out the memory written on it.
3. **Reproducible Runs:** a clone carries the same memory, with no API keys, database or network tunnel.

Recall over these ledgers is text search today: `(:mem :op query :text ...)` matches rows, `(:query)` searches code and, with `:in text`, memories and docs, and `(:note :action query)` searches working notes. We are building embedding recall on top: vectors stored as versioned ASN beside the ledgers and scanned in process as in section 2. No embedding index is stored in the repository yet.

---

## 4. Summary

Agent memory does not need to be a remote service. Kept as versioned files and scanned in process, it:
* **Moves with the code:** memory follows `git checkout`, merge and revert.
* **Needs no infrastructure:** no API keys, no daemon, no hosted index.
* **Is cheap at working-set size:** a 10,000-vector dot-product scan took 0.37 s on the stage-0 interpreter in the measurement above, and compiled array kernels are the direction for bringing that down.
