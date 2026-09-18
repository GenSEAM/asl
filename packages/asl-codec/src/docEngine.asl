(module asl-codec/docEngine :doc "Structured ASN Documentation Schema and Dual-Target Compiler: Human Markdown vs Token-Dense Agent Stubs." :export [DocSymbol DocModule createDocSymbol createDocModule compileDocToMarkdown extractAgentDocStub estimateDocTokenSavings])

schema DocSymbol { name: Str "Exported symbol identifier" kind: Str "Symbol kind: fn, type, macro" signature: Str "Type signature or argument specification" doc: Str "Summary description" }

schema DocModule { moduleId: Str "Unique module path e.g. asl-bus/wire" title: Str "Human-readable module title" problem: Str "Problem addressed by this module" solution: Str "Architectural solution provided" invariants: (List Str) "List of enforced invariant rules" symbols: (List DocSymbol) "List of documented symbols" }

fn createDocSymbol name: Str kind: Str sig: Str doc: Str -> DocSymbol
  DocSymbol :name name :kind kind :signature sig :doc doc

fn createDocModule id: Str title: Str prob: Str sol: Str invs: List syms: List -> DocModule
  DocModule :moduleId id :title title :problem prob :solution sol :invariants invs :symbols syms

fn compileDocToMarkdown doc: DocModule -> Str
  let md0 = (str "# " (.-title doc) "\n\n**Module**: `" (.-moduleId doc) "`\n\n## Problem Solved\n" (.-problem doc) "\n\n## Solution & Architecture\n" (.-solution doc) "\n\n## Architectural Invariants\n")
  let md1 = (foldl (fn [(acc Str) (inv Str)] -> Str (str acc "- " inv "\n")) md0 (.-invariants doc))
  let md2 = (str md1 "\n## API Reference\n\n| Symbol | Kind | Signature | Description |\n|---|---|---|---|\n")
  let md3 = (foldl (fn [(acc Str) (s DocSymbol)] -> Str (str acc "| `" (.-name s) "` | *" (.-kind s) "* | `" (.-signature s) "` | " (.-doc s) " |\n")) md2 (.-symbols doc))
  md3

fn extractAgentDocStub doc: DocModule symbolName: Str -> (Option Str)
  let matches = (filter (fn [(s DocSymbol)] -> Bool (= (.-name s) symbolName)) (.-symbols doc))
  if (list-empty? matches) (none) (let s = (first matches) in (let rules = (string-join (.-invariants doc) "; ") in (some (str "(:doc-stub :mod \"" (.-moduleId doc) "\" :sym \"" (.-name s) "\" :kind \"" (.-kind s) "\" :sig \"" (.-signature s) "\" :rules [\"" rules "\"] :doc \"" (.-doc s) "\")"))))

fn estimateDocTokenSavings doc: DocModule -> F64
  let fullMd = (compileDocToMarkdown doc)
  let mdLen = (string-length fullMd)
  if (<= mdLen 0) 0.0 (let stubSample = (extractAgentDocStub doc (if (list-empty? (.-symbols doc)) "" (.-name (first (.-symbols doc))))) in (match stubSample ((none) 0.0) ((some stub) (let stubLen = (string-length stub) in (let diff = (- mdLen stubLen) in (if (<= diff 0) 0.0 (/ (* (float-from-int64 diff) 100.0) (float-from-int64 mdLen))))))))
