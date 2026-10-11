(module sensor/nanoProgram :x [Reading Verdict judge show main] :i [(core/strings :a s)])

(schema Reading (:f label Str "What the value was read from.") (:f value F32 "The value itself.") (:f seq I32 "How many arguments the run was given."))

(enum Verdict (:c high [(over Num)] "Above the ceiling, by this much.") (:c within [] "At or below the ceiling."))

fn judge r: Reading -> Verdict
  (if (> r.value 10.0) (high (- r.value 10.0)) (within))

fn show r: Reading -> Str
  (mt (judge r) ((high over) (s/concat r.label (str " high by " (stringFromFloat64 over)))) ((within) (s/concat r.label " ok")))

fn ! main args: (List Str) -> (Result Unit IoError)
  (let [(raw (optionOr (listHead args) "0")) (r (Reading :label (s/upper raw) :value (optionOr (stringToFloat64 raw) 0.0) :seq (optionOr (int64ToInt32 (listLength args)) 0)))] (println (show r)) (println (str "count=" (stringFromInt64 (int32ToInt64 r.seq)))) (ok ()))
