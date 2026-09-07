"The Nano projection, written the way an agent under a token budget writes it:"
"every declaration head in its short spelling, every option keyword in its short"
"spelling, and every type alias in a position a backend has to emit. No corpus"
"fixture had ever been Nano-spelled, so `check_corpus` and the differential gate"
"had only ever seen verbose source — and three of the four backends were"
"printing the alias verbatim, so `pub v: I64`, `readonly v: I64` and `v I64`"
"reached rustc, tsc and go vet, which reject all three. Python hid it by"
"emitting no types at all."
"`F32` is the case that matters most: it is a reserved width Core does not have,"
"recorded in prelude.json as resolving to Float64 and carrying none of a narrower"
"width's semantics. It must transpile as Float64 on every target, not as some"
"per-backend guess at a 32-bit float."

(module sensor/nano
  :d "Grade a run of sensor readings against a window, spelled in Nano."
  :x [Sample Window Grade Trend readings mean-of sample-of grade-of label-of
      trend-of trend-label summarise widen blank]
  :i [(core/strings :a s)])

(dfs Sample
  (:f id Str "Identifier the readings were taken under.")
  (:f count Int "How many readings the sample summarises.")
  (:f mean Num "Arithmetic mean of the readings.")
  (:f drift F32 "Spread between the extreme readings.")
  (:f settled Bool "Whether the sample held any reading at all."))

(schema Window
  (:f low F64 "Lower bound a settled mean must not fall below.")
  (:f high Float "Upper bound a settled mean must not exceed."))

(dfe Grade
  (:c steady [] "Mean inside the window, spread small.")
  (:c drifting [(by F32)] "Mean inside the window, spread too large.")
  (:c out-of-range [(mean Num)] "Mean outside the window."))

(enum Trend
  (:c rising [] "The last reading exceeds the first.")
  (:c falling [] "The last reading falls below the first.")
  (:c flat [] "First and last readings agree."))

(df readings [(csv Str)] -> (List Num)
  :d "Parse a comma-separated feed. A token that is not a number is dropped, so
      an empty feed is an empty run and not a run of one zero."
  (map (fn [t] (option-or (string-to-float64 t) 0.0))
       (filter (fn [t] (is-some? (string-to-float64 t)))
               (string-split csv ","))))

(df mean-of [(xs (List Num))] -> Num
  :d "Arithmetic mean. An empty run has a mean of zero by convention, which is
      what lets every caller below take a total function."
  (if (= (list-length xs) 0)
      0.0
      (/ (list-sum xs) (int64-to-float64 (list-length xs)))))

(df sample-of [(id Str) (xs (List F64))] -> Sample
  :d "Summarise a run of readings into one sample."
  (let [(m (mean-of xs))]
    (Sample :id (s/upper id)
            :count (list-length xs)
            :mean m
            :drift (- (option-or (list-max xs) m) (option-or (list-min xs) m))
            :settled (not (list-empty? xs)))))

(df grade-of [(w Window) (sm Sample)] -> Grade
  :d "Grade a sample against a window."
  (cond
    ((or (< (.-mean sm) (.-low w)) (> (.-mean sm) (.-high w)))
     (out-of-range (.-mean sm)))
    ((> (.-drift sm) 1.0) (drifting (.-drift sm)))
    (:else (steady))))

(df label-of [(g Grade)] -> Str
  :d "A one-word label for a grade, with the offending magnitude where there is one."
  (mt g
    ((steady)         "steady")
    ((drifting by)    (s/concat "drifting:" (string-from-float64 by)))
    ((out-of-range m) (s/concat "out:" (string-from-float64 m)))))

(def trend-of [(xs (List Float))] -> Trend
  :d "Compare the first reading with the last."
  (let [(head (option-or (list-head xs) 0.0))
        (tail (option-or (list-head (list-reverse xs)) 0.0))]
    (cond
      ((> tail head) (rising))
      ((< tail head) (falling))
      (:else (flat)))))

(def trend-label [(t Trend)] -> Str
  :d "A one-word label for a trend."
  (mt t
    ((rising)  "rising")
    ((falling) "falling")
    ((flat)    "flat")))

(df summarise [(id Str) (csv Str)] -> Str
  :d "The whole pipeline over one feed: parse, summarise, grade, label, and name
      the trend."
  (let [(xs (readings csv))
        (sm (sample-of id xs))
        (w (Window :low 0.0 :high 100.0))]
    (string-join (list (.-id sm)
                       (string-from-int64 (.-count sm))
                       (string-from-float64 (.-mean sm))
                       (label-of (grade-of w sm))
                       (trend-label (trend-of xs)))
                 "|")))

(df widen [(n I32)] -> I64
  :d "The narrow integer alias in a signature, widened to the default one."
  (int32-to-int64 n))

(df blank [] -> Unit
  :d "The unit value. Its alias is its own spelling, which is still a spelling a
      backend has to resolve rather than print."
  ())
