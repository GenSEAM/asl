# Prefix Heads and Closed Variants: Why S-Expressions and Algebraic Types Suit LLMs
*By GenSEAM | September 2026*

Programming languages designed between 1970 and 2015 share a common design premise: **syntax should optimize for human visual cognition**.

Infix operators (`a + b * c`), indentation-based block hierarchies, implicit type coercion, ternary conditionals, and semicolon delimiters were all chosen to reduce human typing strain and follow natural reading habits.

Large language models do not have eyes, biological working memory, or keyboards. They are autoregressive decoders that compute probability distributions over subword token sequences:

$$P(W) = \prod_{i=1}^n P(w_i \mid w_1, \dots, w_{i-1})$$

When an LLM generates Python, JavaScript, or C++, part of its work goes into resolving lexical ambiguities, tracking invisible indentation, and applying operator precedence.

**AgentScript (ASL)** is designed for model authors first. It combines **single-pass S-expressions**, **closed algebraic variants with exhaustive matching**, and, as a direction still being built, **explicit effect boundaries**. This post argues why that combination suits LLM generation and verification, and says which parts are checked today.

---

## 1. Homoiconicity and Causal Conditioning: Code as a Tree

In conventional compilers, source code goes through several stages: lexing into tokens, parsing into a concrete syntax tree with precedence rules (for example the shunting-yard algorithm), and lowering into an abstract syntax tree.

In AgentScript, the written form is already the tree. This property is known as **homoiconicity**.

```agentscript
(module core/fsm :d "Finite state machine with exhaustive pattern matching." :x [step runTests] :i [])

enum State (idle) (active sessionId: String) (errored code: Int64)

enum Event (start sessionId: String) (finish) (fail code: Int64)

fn step current: State ev: Event -> State
  :d "Deterministic state transition function."
  (mt current
    ((idle)
     (mt ev
       ((start s) (active s))
       ((finish) (idle))
       ((fail c) (errored c))))
    ((active s)
     (mt ev
       ((start _) (errored 101))
       ((finish) (idle))
       ((fail c) (errored c))))
    ((errored c) (errored c)))

fn runTests -> Bool
  (do
    (assert (= (step (idle) (start "s1")) (active "s1")) "idle starts a session")
    (assert (= (step (active "s1") (start "s2")) (errored 101)) "double start errors")
    true)
```

This module passes `asl-host check`, and `asl-host test` executes both assertions.

### The Causal Conditioning Advantage

In infix languages, an operator appears *between* its operands: `operand_A + operand_B`. An autoregressive model generates `operand_A` before it has output the operator that says what `operand_A` is for.

In prefix S-expressions, the form head always precedes its arguments:

$$(f \quad a_1 \quad a_2 \quad \dots \quad a_k)$$

When the model emits the head `f` (for example `mt`, `+`, `filter`, or a user function), that head is already in the causal context for every argument token $a_1 \dots a_k$. Generation of the operands is conditioned on the operation being performed. That is the hypothesis; Section 5 says how we intend to measure its effect.

---

## 2. Balanced Parentheses by Construction: No Precedence to Resolve

Consider the following JavaScript expression:

```javascript
const result = a + b * c > d ? e : f;
```

To read this single line correctly, a model has to apply five precedence levels: multiplication, addition, relational comparison, the ternary conditional, and assignment.

In AgentScript, **operator precedence does not exist**:

```agentscript
(let [(result (if (> (+ a (* b c)) d) e f))]
  result)
```

Evaluation order is given by nesting alone. Every expression opens with `(` and closes with `)`.

### Delimiters as Causal Anchors

A frequent failure in generated Python is the "runaway block": a loop or comprehension that does not end where the model meant it to, because ending a block means emitting less indentation rather than a token.

In ASL, closing a form is always the explicit token `)`, and each bracket kind pairs exactly: `( )` forms, `[ ]` lists, `{ }` records. The stage-0 host rejects a mismatch before running anything (`ERR_READ_UNBALANCED ')' closes '['`).

---

## 3. Closed Variants (`enum`) and Exhaustive `mt`

In dynamic languages, runtime failures such as `AttributeError: 'NoneType' object has no attribute 'val'` or `TypeError: Cannot read properties of undefined` are a common way for an agent's run to go wrong.

AgentScript removes some of these classes by construction:

1. **Closed variants (`enum`):** Cases carry typed payloads, as in `enum State (idle) (active sessionId: String) (errored code: Int64)`. There is no `nil`: absence is `(none)`, and builtins such as `list-head` and `map-get` return `(some v)` or `(none)`.
2. **Exhaustive matching (`mt`):** `asl-host check` verifies that every variant of an enum is covered. Removing the `(errored c)` arm from the module above makes it fail with `ERR_MATCH_NONEXHAUSTIVE match over enum State misses variant(s): errored`.

If an agent adds a variant, the stage-0 host rejects every downstream `mt` that does not handle it, before any code runs. Today that check lives only in `asl-host check`; `asl check`, which verifies delimiter balance only, passes the same file.

---

## 4. Explicit Effect Boundaries

One of the larger reliability hazards of autonomous agents is the **unconstrained side effect**: an agent asked to calculate a metric calls something that writes to disk, changes the environment, or opens a connection.

The design we are building separates the two kinds of function:

* **Pure functions** would have no access to the filesystem, network, clock or process state, so a coordinator could run code from an untrusted subagent in parallel without risk to the workspace.
* **Effectful procedures** would be marked, and would run only inside a granted capability context.

That is a target. Today neither engine enforces it: a function with no marker that calls `println` passes `asl-host check`, and a trailing `!` is an ordinary legal character in a name, not a checked sigil.

---

## 5. Measuring the Claim

The argument above predicts that models produce valid ASL more often on the first try than Python, Rust or TypeScript, and need fewer repair turns. The way to test it is to give models the same specifications in each language, check every output with that language's strictest checker, and record first-pass validity, repair turns and scope errors with the models, the task set and the date. We have not run that comparison with a recorded result, so this post quotes no entropy or validity figures.

### Try It

The stage-0 host is the reference checker. Save the state machine above as `fsm.asl` and run:

```bash
asl/host/out/asl-host check fsm.asl
asl/host/out/asl-host test fsm.asl
```

The first prints `ok`; the second reports two assertions executed. If you find a balanced S-expression that the host reads inconsistently, or a program it accepts that it should reject, open an issue with the file and the host's output.
