"The Nano projection as a whole program, which is the only shape that reaches"
"the wasm arm: function-mode cases run five targets and `main` runs six. The"
"import is the point of it — the reference interpreter recognized a module"
"option by the prefix of its text, so `:i` was an option it did not know and"
"every import a Nano module declared was dropped in silence, leaving the alias"
"unbound at its use site while all four transpilers were green."

(module sensor/nano-program
  :d "Grade the reading named on the command line and print the verdict."
  :x [Reading Verdict judge show]
  :i [(core/strings :a s)])

(dfs Reading
  (:f label Str "What the value was read from.")
  (:f value F32 "The value itself.")
  (:f seq I32 "How many arguments the run was given."))

(dfe Verdict
  (:c high [(over Num)] "Above the ceiling, by this much.")
  (:c within [] "At or below the ceiling."))

(df judge [(r Reading)] -> Verdict
  :d "Judge one reading against a fixed ceiling."
  (if (> (.-value r) 10.0)
      (high (- (.-value r) 10.0))
      (within)))

(df show [(r Reading)] -> Str
  :d "Render a reading and its verdict on one line."
  (mt (judge r)
    ((high over) (s/concat (.-label r) (str " high by " (string-from-float64 over))))
    ((within)    (s/concat (.-label r) " ok"))))

(df ! main [(args (List Str))] -> (Result Unit IoError)
  :d "Read one value from the command line, judge it, and report the run size."
  (let [(raw (option-or (list-head args) "0"))
        (r (Reading :label (s/upper raw)
                    :value (option-or (string-to-float64 raw) 0.0)
                    :seq (option-or (int64-to-int32 (list-length args)) 0)))]
    (try (println (show r)))
    (println (str "count=" (string-from-int64 (int32-to-int64 (.-seq r)))))))
