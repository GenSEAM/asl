# Why Disemvoweling Breaks BPE: How Naive Token Optimization Hurts Coding Agents
*By GenSEAM | September 2026*

When designing domain languages and interfaces for autonomous AI coding agents, the natural instinct of engineers is to optimize for raw string brevity.

If context windows are expensive and attention degrades with sequence length, shouldn't we shorten every identifier to the minimum possible number of characters? Why write `cleanTerminalText` when you can write `ctermtxt` or `clnTerm`?

In practice this compression rarely saves tokens and often costs correctness. Micro-shortened identifiers split into rare subword fragments, invite synonym guessing, and make text edits ambiguous.

Here is why character-level disemvoweling is an anti-pattern, and the naming rule AgentScript adopted instead.

---

## 1. The Physics of BPE: Why `ctermtxt` and `nrml` Break Down

Byte-Pair Encoding (BPE) tokenizers do not process code as arbitrary characters. They segment text into statistically frequent subword chunks learned from large natural language and code corpora.

Whole words split along the words. We measured the identifiers in this post with tiktoken 0.12.0 on 2026-09-24 (o200k_base and cl100k_base, each identifier encoded alone):

```text
o200k_base
"cleanTerminalText"   -> ["clean", "Terminal", "Text"]   3 tokens
"clean-terminal-text" -> ["clean", "-terminal", "-text"] 3 tokens
"ctermtxt"            -> ["ct", "erm", "txt"]            3 tokens
"cleanTerm"           -> ["clean", "Term"]               2 tokens
"clnTerm"             -> ["cl", "n", "Term"]             3 tokens
"normal"              -> ["normal"]                      1 token
"nrml"                -> ["nr", "ml"]                    2 tokens

cl100k_base
"ctermtxt"            -> ["cter", "mt", "xt"]            3 tokens
"wrk"                 -> ["wr", "k"]                     2 tokens
"work"                -> ["work"]                        1 token
```

Three observations follow:
1. **No token savings**: `ctermtxt` costs the same three tokens as `cleanTerminalText`; `clnTerm` costs one more than `cleanTerm`; `nrml` costs one more than `normal`. Dropping letters bought nothing on either tokenizer.
2. **Rare fragments**: the whole-word forms split into common words (`clean`, `Terminal`, `Text`), while the shortened forms split into fragments such as `ct`, `erm`, `nr` and `ml` that carry no stable meaning of their own.
3. **Copy errors**: a model reproducing a rare letter sequence has more plausible neighbours to slip into (`ctermtxt`, `ctermtext`, `ctrmtxt`), and each slip is an unknown symbol and a repair turn.

---

## 2. The Dual Collision: Homonyms vs. Synonyms

Compilers care about **homonym collisions**: two different entities sharing one name, such as an abbreviation `st` that could mean `state` or `status`.

For agents generating code from parametric memory, **synonym collisions** matter as much. If a codebase allows both `cleanTerm` and `clnTerm` for one concept, the model has to guess which spelling this codebase chose, and a wrong guess costs a full loop:
1. The agent writes `(clnTerm buffer)`.
2. The stage-0 host stops before running anything: `asl/host/out/asl-host check` reports `ERR_UNKNOWN_SYMBOL clnTerm`.
3. The agent inspects the failure, searches for the right name, patches, and re-runs.

The one-token "saving" is paid back many times over by that repair turn.

The AgentScript builtins follow one spelling per concept: `list-length`, `string-contains?`, `is-some?`. Short aliases such as `len`, `head` or `includes?` are not bound on the host and fail with `ERR_UNKNOWN_SYMBOL`. For user-defined names, one canonical spelling is a convention we adopt, not something either engine enforces: on 2026-09-24 both engines accept `snake_case`, `is-` prefixes and a trailing `!` alike.

---

## 3. The Naming Rule: Whole Words, Measured Cheapest Wins

AgentScript's adopted naming rule is short: **identifiers are camelCase whole words; among names that carry the meaning, the measured cheapest wins.**

Two parts do the work:
- **Whole words** keep every fragment a common token and every name a readable phrase. Established abbreviations with high corpus frequency (`cfg`, `ctx`, `msg`) stay acceptable when they tokenize as cheaply as the word; invented ones do not.
- **Measured cheapest** settles ties by running a tokenizer, not by counting characters. Where two names carry the same meaning, keep the one that costs fewer tokens.

Why camelCase rather than kebab-case? It is cheaper, but by a few percent, not by tens. Rewriting every camelCase identifier outside string literals in 2,964 git-tracked `.asl` and `.asn` files (169,852 identifiers) to kebab-case and counting tokens gave a camelCase saving of 1.90 percent on o200k_base and 1.68 percent on cl100k_base (measured 2026-09-22, recorded in `.asl/mem/principles.asn` as CamelCaseCorpusSaving). Large per-identifier savings quoted for single long names do not carry over to a corpus, because most identifiers are short and much of the text is string literals.

The rule also bounds length by meaning rather than by a morpheme count: a longer name earns its extra words when removing them would change what a caller has to know (a safety condition, a fallback path, a lifecycle phase). A word that only describes the implementation belongs in the docstring.

| Identifier | Verdict | Reason |
| :--- | :--- | :--- |
| `boxedTypeIfRecursive` | Keep | Dropping `IfRecursive` hides the condition under which boxing happens. |
| `dialectParamPrefix` | Keep | Dropping `dialect` collides with generic query parameter prefixes. |
| `calculateAndFormatOutput` | Shorten | Describes the implementation; `formatOutput`, or two functions. |

---

## 4. Edit-Anchor Uniqueness and Search Precision

Beyond token counts lies a hard physical constraint: **how agents actually change files**.

Most coding agents do not edit by AST offsets. They search with `grep` and apply string replacements that must match exactly once:
```text
<<<<<<< SEARCH
(let [(t (getText node))]
=======
(let [(text (getText node))]
>>>>>>> REPLACE
```

If an identifier is hyper-terse (`t`, `st`, `p`):
1. **Substring collisions**: `t` matches inside comments, keywords, and strings.
2. **Ambiguous replacements**: the edit tool rejects a search block that is not unique.
3. **Search pollution**: searching for `st` returns pages of false positives and spends the agent's context.

A whole-word name like `cleanTerm` is word-boundary distinct and cheap to search. Token economics and edit accuracy point the same way.

---

## 5. Summary

1. **Do not disemvowel**: on the measured examples it saves no tokens and produces rare fragments.
2. **One spelling per concept**: builtins already have one; for project names it is a review convention.
3. **camelCase whole words, measured cheapest wins**: a small corpus-level saving (1.90 percent on o200k_base), plus names that search and edit cleanly.
4. **Length follows meaning**: extra words are justified by what callers must know, not by what the function does inside.

- Read the companion analysis in [Token Economy & Structural Compression](/blog/token-economy-and-structural-compression).
