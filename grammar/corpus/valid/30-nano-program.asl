"The Nano projection as a whole program, which was the only shape that reached"

"the former wasm arm: function-mode cases ran five targets and `main` ran six. The"

"import is the point of it — the reference interpreter recognized a module"

"option by the prefix of its text, so `:i` was an option it did not know and"

"every import a Nano module declared was dropped in silence, leaving the alias"

"unbound at its use site while all four transpilers were green."

(module sensor/nanoProgram :x [Reading Verdict judge show main] :i [(core/strings :a s)])

(schema Reading (:f label Str "What the value was read from.") (:f value F32 "The value itself.") (:f seq I32 "How many arguments the run was given."))

(enum Verdict (:c high [(over Num)] "Above the ceiling, by this much.") (:c within [] "At or below the ceiling."))

fn judge r: Reading -> Verdict
  (if (> r.value 10.0) (high (- r.value 10.0)) (within))

fn show r: Reading -> Str
  (mt (judge r) ((high over) (s/concat r.label (str " high by " (stringFromFloat64 over)))) ((within) (s/concat r.label " ok")))

fn ! main args: (List Str) -> (Result Unit IoError)
  (let [(raw (optionOr (listHead args) "0")) (r (Reading :label (s/upper raw) :value (optionOr (stringToFloat64 raw) 0.0) :seq (optionOr (int64ToInt32 (listLength args)) 0)))] (println (show r)) (println (str "count=" (stringFromInt64 (int32ToInt64 r.seq)))) (ok ()))
