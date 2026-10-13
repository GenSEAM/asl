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
* Cosine similarity between a query $\mathbf{q}$ and a candidate $\mathbf{v}$:
$$\text{sim}(\mathbf{q}, \mathbf{v}) = \frac{\mathbf{q} \cdot \mathbf{v}}{\|\mathbf{q}\| \|\mathbf{v}\|}$$
When vectors are stored at unit length, the similarity is the dot product alone.

One measurement on today's interpreter: on 2026-09-24, `asl-host test` on a file that builds 10,000 384-dimensional `F64Array` vectors and takes each one's dot product with a query finished in 0.26 s wall time (`/usr/bin/time`, Apple M1 Pro, construction included). The same scan over 1,000 vectors finished in 0.02 s.

---

## 2. Recall in Plain AgentScript

The stage-0 host binds `F64Array` builtins (`f64-array-generate`, `f64-array-get`, `f64-array-len`, `f64-array-sum`), which are enough for an in-process scan. It has no `sqrt` builtin yet, so the sample assumes unit-length vectors. It passes `asl-host check` and `asl-host test` (3 assertions):

```asl
(module probe/p13eTest :d "In-process recall over unit-length F64 arrays" :x [dot topMatch runTests] :i [])

schema VectorItem
  id: String
  vector: F64Array

fn dot a: F64Array b: F64Array -> Float64
  (f64-array-sum (f64-array-generate (f64-array-len a) (fn [i] (* (f64-array-get a i) (f64-array-get b i)))))

fn topMatch query: F64Array items: (List VectorItem) -> (Option String)
  (mt (list-head (list-sort-by (fn [it] (- 0.0 (dot query (.-vector it)))) items))
    ((some best) (some (.-id best)))
    ((none) (none)))

fn unit x: Float64 y: Float64 -> F64Array
  (f64-array-generate 2 (fn [i] (if (= i 0) x y)))

fn runTests -> Bool
  (let [(items (list {:id "east" :vector (unit 1.0 0.0)} {:id "north" :vector (unit 0.0 1.0)}))]
    (do
      (assert (= (dot (unit 0.6 0.8) (unit 0.6 0.8)) 1.0) "unit vector")
      (assert (= (topMatch (unit 0.8 0.6) items) (some "east")) "nearest is east")
      (assert (= (topMatch (unit 0.6 0.8) (list)) (none)) "empty store")
      true))
```

The repository also carries a fuller store in `asl/packages/asl-mem/src/store.asl` (vector items, dimension validation, normalization, a flat slab layout). Its math suite, `asl/packages/asl-mem/tests/mathTest.asl`, passes 27 assertions under `./bin/asl test`, which runs the lenient asl-core engine; the strict host does not load it yet, because its helper `asl/packages/asl-mem/src/math.asl` calls names the host does not bind (`bytesAlloc`, `bytesGetF64`, `list-map` and others). Moving that store onto the host builtins shown above is open work.

---

## 3. Git-Native Persistence: Memory Versioned With the Code

The weakness of a hosted vector database is **temporal decoupling**: a convention stored there is global, mutable and blind to Git branches.

This workspace keeps its agent memory as ASN ledgers under `.asl/mem/`, tracked in Git: on 2026-09-24, `git ls-files .asl/mem` listed 545 files, among them tasks, decisions, audits, receipts, reviews and `notes.asn`. That gives three properties today:
1. **Memory as Repository Data:** plans, decisions and findings are plain S-expression files next to the code they describe.
2. **Branch-Aware Context:** checking out a branch checks out the memory written on it.
3. **Reproducible Runs:** a clone carries the same memory, with no API keys, database or network tunnel.

Recall over these ledgers is text search today: the `(:query)` op searches symbols and text, and `(:note :action query)` searches `notes.asn`. We are building embedding recall on top: vectors stored as versioned ASN beside the ledgers and scanned in process as in section 2. No embedding index is stored in the repository yet.

---

## 4. Summary

Agent memory does not need to be a remote service. Kept as versioned files and scanned in process, it:
* **Moves with the code:** memory follows `git checkout`, merge and revert.
* **Needs no infrastructure:** no API keys, no daemon, no hosted index.
* **Is cheap at working-set size:** a 10,000-vector dot-product scan took 0.26 s on the stage-0 interpreter in the measurement above, and compiled array kernels are the direction for bringing that down.
