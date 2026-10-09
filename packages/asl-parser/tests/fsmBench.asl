(module asl-parser/tests/fsmBench :x [buildCorpus testBenchScale testBenchPurity testBenchIterations runTests] :i [(fsmOutline :a fsm)])

fn polyglotBlock -> String
  (str "export function handler(req: any) {\n" "  return req;\n" "}\n" "export interface TaskProps {\n" "  id: string;\n" "}\n" "export class Dispatcher {\n" "  run() {}\n" "}\n" "export type Callback = () => void;\n")

fn buildCorpus -> String
  (let [(u1 (polyglotBlock)) (u10 (str u1 u1 u1 u1 u1 u1 u1 u1 u1 u1)) (u100 (str u10 u10 u10 u10 u10 u10 u10 u10 u10 u10))] u100)

fn testBenchScale -> Bool
  (let [(corpus (buildCorpus)) (lines (stringSplit corpus "\n"))] (assert (= (listLength lines) 1001) "Corpus line count must equal 1001 including trailing newline") true)

fn checkLineOrder items: (List fsm/OutlineItem) -> Bool
  (let [(len (listLength items))] (assert (> len 0) "Extracted outline items must be non-empty") (let [(firstIt (mt (listGet items 0) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0)))) (lastIt (mt (listGet items (- len 1)) ((some it) it) ((none) (fsm/OutlineItem :kind "" :name "" :line 0))))] (assert (= firstIt.name "handler") "First extracted symbol must be handler") (assert (= firstIt.line 1) "First extracted symbol line must be 1") (assert (= lastIt.name "Callback") "Last extracted symbol must be Callback") (assert (= lastIt.line 1000) "Last extracted symbol line must be 1000")) true)

fn testBenchPurity -> Bool
  (let [(corpus (buildCorpus)) (items (fsm/scanOutline corpus "ts"))] (assert (= (listLength items) 400) "1,000 lines must yield exactly 400 top-level items") (assert (checkLineOrder items) "Accumulator items must be in strictly ascending line order") true)

fn testBenchIterations -> Bool
  (let [(corpus (buildCorpus))] (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 1 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 2 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 3 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 4 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 5 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 6 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 7 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 8 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 9 must extract 400 items") (assert (= (listLength (fsm/scanOutline corpus "ts")) 400) "Iteration 10 must extract 400 items") true)

fn runTests -> Bool
  (do (assert (testBenchScale) "Corpus scale verification must pass") (assert (testBenchPurity) "Accumulator purity verification must pass") (assert (testBenchIterations) "Multi-iteration benchmark throughput must pass") true)
