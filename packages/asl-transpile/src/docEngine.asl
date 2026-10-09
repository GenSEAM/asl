(module asl-transpile/docEngine
  :x [DocSymbol DocModule createDocSymbol createDocModule compileDocToMarkdown extractAgentDocStub estimateDocTokenSavings]
  :i [])

(schema DocSymbol
  (:f name Str)
  (:f kind Str)
  (:f signature Str)
  (:f doc Str))

(schema DocModule
  (:f moduleId Str)
  (:f title Str)
  (:f problem Str)
  (:f solution Str)
  (:f invariants (List Str))
  (:f symbols (List DocSymbol)))

fn createDocSymbol name: Str kind: Str sig: Str doc: Str -> DocSymbol
  (DocSymbol :name name :kind kind :signature sig :doc doc)

fn createDocModule id: Str title: Str prob: Str sol: Str invs: (List Str) syms: (List DocSymbol) -> DocModule
  (DocModule :moduleId id :title title :problem prob :solution sol :invariants invs :symbols syms)

fn compileDocToMarkdown doc: DocModule -> Str
  (let [(md0 (str "# " doc.title "\n\n**Module**: `" doc.moduleId "`\n\n## Problem Solved\n" doc.problem "\n\n## Solution & Architecture\n" doc.solution "\n\n## Architectural Invariants\n"))
        (md1 (fold (fn [(acc Str) (inv Str)] -> Str (str acc "- " inv "\n")) md0 doc.invariants))
        (md2 (str md1 "\n## API Reference\n\n| Symbol | Kind | Signature | Description |\n|---|---|---|---|\n"))
        (md3 (fold (fn [(acc Str) (s DocSymbol)] -> Str (str acc "| `" s.name "` | *" s.kind "* | `" s.signature "` | " s.doc " |\n")) md2 doc.symbols))]
    md3)

fn extractAgentDocStub doc: DocModule symbolName: Str -> (Option Str)
  (let [(matches (filter (fn [(s DocSymbol)] -> Bool (= s.name symbolName)) doc.symbols))]
    (if (listEmpty? matches)
      (none)
      (mt (listHead matches)
        ((none) (none))
        ((some s)
          (let [(rules (stringJoin doc.invariants "; "))]
            (some (str "(:doc-stub :mod \"" doc.moduleId "\" :sym \"" s.name "\" :kind \"" s.kind "\" :sig \"" s.signature "\" :rules [\"" rules "\"] :doc \"" s.doc "\")")))))))

fn estimateDocTokenSavings doc: DocModule -> Float64
  (let [(fullMd (compileDocToMarkdown doc))
        (mdLen (stringLength fullMd))]
    (if (<= mdLen 0)
      0.0
      (let [(firstSym (if (listEmpty? doc.symbols) "" (optionOr (listHead doc.symbols) (DocSymbol :name "" :kind "" :signature "" :doc "")).name))
            (stubSample (extractAgentDocStub doc firstSym))]
        (mt stubSample
          ((none) 0.0)
          ((some stub)
            (let [(stubLen (stringLength stub))
                  (diff (- mdLen stubLen))]
              (if (<= diff 0)
                0.0
                (/ (* (int64ToFloat64 diff) 100.0) (int64ToFloat64 mdLen)))))))))
