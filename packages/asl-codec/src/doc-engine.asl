(module asl-codec/docEngine
  :d "Structured ASN Documentation Schema and Dual-Target Compiler: Human Markdown vs Token-Dense Agent Stubs."
  :x [DocSymbol
      DocModule
      createDocSymbol
      createDocModule
      compileDocToMarkdown
      extractAgentDocStub
      estimateDocTokenSavings]
  :i [])

(dfs DocSymbol
  (:f name Str "Exported symbol identifier")
  (:f kind Str "Symbol kind: fn, type, macro")
  (:f signature Str "Type signature or argument specification")
  (:f doc Str "Summary description"))

(dfs DocModule
  (:f moduleId Str "Unique module path e.g. asl-bus/wire")
  (:f title Str "Human-readable module title")
  (:f problem Str "Problem addressed by this module")
  (:f solution Str "Architectural solution provided")
  (:f invariants (List Str) "List of enforced invariant rules")
  (:f symbols (List DocSymbol) "List of documented symbols"))

(df createDocSymbol [(name Str) (kind Str) (sig Str) (doc Str)] -> DocSymbol
  :d "Initializes a DocSymbol record."
  (DocSymbol
    :name name
    :kind kind
    :signature sig
    :doc doc))

(df createDocModule [(id Str) (title Str) (prob Str) (sol Str) (invs (List Str)) (syms (List DocSymbol))] -> DocModule
  :d "Initializes a DocModule record."
  (DocModule
    :moduleId id
    :title title
    :problem prob
    :solution sol
    :invariants invs
    :symbols syms))

(df compileDocToMarkdown [(doc DocModule)] -> Str
  :d "Compiles an ASN DocModule into human-readable Markdown documentation."
  (let [(md0 (str "# " (.-title doc) "\n\n"
                  "**Module**: `" (.-moduleId doc) "`\n\n"
                  "## Problem Solved\n"
                  (.-problem doc) "\n\n"
                  "## Solution & Architecture\n"
                  (.-solution doc) "\n\n"
                  "## Architectural Invariants\n"))
        (md1 (foldl (fn [(acc Str) (inv Str)] -> Str
                      (str acc "- " inv "\n"))
                    md0
                    (.-invariants doc)))
        (md2 (str md1 "\n## API Reference\n\n"
                  "| Symbol | Kind | Signature | Description |\n"
                  "|---|---|---|---|\n"))
        (md3 (foldl (fn [(acc Str) (s DocSymbol)] -> Str
                      (str acc "| `" (.-name s) "` | *" (.-kind s) "* | `" (.-signature s) "` | " (.-doc s) " |\n"))
                    md2
                    (.-symbols doc)))]
    md3))

(df extractAgentDocStub [(doc DocModule) (symbolName Str)] -> (Option Str
)  :d "Extracts a compact, token-dense ASN stub for an AI agent, omitting human prose."
  (let [(matches (filter (fn [(s DocSymbol)] -> Bool
                           (= (.-name s) symbolName))
                         (.-symbols doc)))]
    (if (list-empty? matches)
        (none)
        (let [(s (first matches))
              (rules (string-join (.-invariants doc) "; "))]
          (some (str "(:doc-stub :mod \"" (.-moduleId doc) "\""
                     " :sym \"" (.-name s) "\""
                     " :kind \"" (.-kind s) "\""
                     " :sig \"" (.-signature s) "\""
                     " :rules [\"" rules "\"]"
                     " :doc \"" (.-doc s) "\")"))))))

(df estimateDocTokenSavings [(doc DocModule)] -> F64
  :d "Calculates the token reduction percentage of agent ASN stubs compared to full Markdown documentation."
  (let [(fullMd (compileDocToMarkdown doc))
        (mdLen (string-length fullMd))]
    (if (<= mdLen 0)
        0.0
        (let [(stubSample (extractAgentDocStub doc (if (list-empty? (.-symbols doc)) "" (.-name (first (.-symbols doc))))))]
          (mt stubSample
            ((none) 0.0)
            ((some stub)
             (let [(stubLen (string-length stub))
                   (diff (- mdLen stubLen))]
               (if (<= diff 0)
                   0.0
                   (/ (* (floatFromInt64 diff) 100.0) (floatFromInt64 mdLen))))))))))
