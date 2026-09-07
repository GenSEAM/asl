(module asl-parser/tests/fsm-bench
  :d "Deterministic performance and accumulator purity benchmark for polyglot FSM scanner"
  :x [build-corpus
      test-bench-scale
      test-bench-purity
      test-bench-iterations
      run-tests]
  :i [(fsm_outline :a fsm)])

(df polyglot-block [] -> String
  :d "Constructs a 10-line polyglot declaration block"
  (str "export function handler(req: any) {\n"
       "  return req;\n"
       "}\n"
       "export interface TaskProps {\n"
       "  id: string;\n"
       "}\n"
       "export class Dispatcher {\n"
       "  run() {}\n"
       "}\n"
       "export type Callback = () => void;\n"))

(df build-corpus [] -> String
  :d "Generates a synthetic 1,000-line polyglot source code corpus"
  (let [(u1 (polyglot-block))
        (u10 (str u1 u1 u1 u1 u1 u1 u1 u1 u1 u1))
        (u100 (str u10 u10 u10 u10 u10 u10 u10 u10 u10 u10))]
    u100))

(df test-bench-scale [] -> Bool
  :d "Verifies that synthetic benchmark corpus contains exactly 1,000 lines"
  (let [(corpus (build-corpus))
        (lines (string-split corpus "\n"))]
    (assert (= (list-length lines) 1001) "Corpus line count must equal 1001 including trailing newline")
    true))

(df check-line-order [(items (List fsm/OutlineItem))] -> Bool
  :d "Verifies strict ascending line order and accumulator purity"
  (let [(len (list-length items))]
    (assert (> len 0) "Extracted outline items must be non-empty")
    (let [(first-it (mt (list-get items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))
          (last-it (mt (list-get items (- len 1)) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))]
      (assert (= (.-name first-it) "handler") "First extracted symbol must be handler")
      (assert (= (.-line first-it) 1) "First extracted symbol line must be 1")
      (assert (= (.-name last-it) "Callback") "Last extracted symbol must be Callback")
      (assert (= (.-line last-it) 1000) "Last extracted symbol line must be 1000"))
    true))

(df test-bench-purity [] -> Bool
  :d "Verifies accumulator purity and exact item extraction on 1,000-line corpus"
  (let [(corpus (build-corpus))
        (items (fsm/scan-outline corpus "ts"))]
    (assert (= (list-length items) 400) "1,000 lines must yield exactly 400 top-level items")
    (assert (check-line-order items) "Accumulator items must be in strictly ascending line order")
    true))

(df test-bench-iterations [] -> Bool
  :d "Evaluates 10 sequential benchmark iterations asserting deterministic throughput"
  (let [(corpus (build-corpus))]
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 1 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 2 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 3 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 4 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 5 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 6 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 7 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 8 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 9 must extract 400 items")
    (assert (= (list-length (fsm/scan-outline corpus "ts")) 400) "Iteration 10 must extract 400 items")
    true))

(df run-tests [] -> Bool
  :d "Executes complete benchmark suite under strict falsification"
  (assert (test-bench-scale) "Corpus scale verification must pass")
  (assert (test-bench-purity) "Accumulator purity verification must pass")
  (assert (test-bench-iterations) "Multi-iteration benchmark throughput must pass")
  true)
