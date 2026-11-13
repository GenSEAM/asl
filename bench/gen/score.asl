(module aslBench/gen/score
  :x [main Row Header ArmStat ScoreOut rowOf headerOf statFor scoreText report! wilson permille pctText isqrt quantile statOf]
  :i [(aslBench/gen/core :a gc)])

; (:m :ref FABLE-LANG-01 :do "aggregates bench/gen trial rows into one table row per model and arm with Wilson 95 percent intervals, and prints the H1 to H4 comparisons only when every arm holds every planned trial")

(schema Row
  (:f key String)
  (:f arm String)
  (:f task String)
  (:f model String)
  (:f rep Int64)
  (:f rawPass Bool)
  (:f healedPass Bool)
  (:f solved Bool)
  (:f calls Int64)
  (:f tokens Int64)
  (:f sysTok Int64)
  (:f firstFail String))

(schema Header
  (:f arms (List String))
  (:f models (List String))
  (:f taskIds (List String))
  (:f reps Int64))

(schema ArmStat
  (:f model String)
  (:f arm String)
  (:f trials Int64)
  (:f expected Int64)
  (:f missing Int64)
  (:f rawPass Int64)
  (:f healedPass Int64)
  (:f solved Int64)
  (:f tokens Int64)
  (:f tokensNoCard Int64)
  (:f repairTurns Int64)
  (:f greens (List Int64))
  (:f stages (List (Pair String Int64))))

(schema ScoreOut
  (:f complete Bool)
  (:f lines (List String))
  (:f stats (List ArmStat))
  (:f error String))

fn rowOf items: (List gc/Sx) -> Row
  (Row :key (gc/kwText items ":key") :arm (gc/kwText items ":arm") :task (gc/kwText items ":task") :model (gc/kwText items ":model")
       :rep (gc/kwInt items ":rep") :rawPass (gc/kwBool items ":rawPass") :healedPass (gc/kwBool items ":healedPass")
       :solved (gc/kwBool items ":solved") :calls (gc/kwInt items ":calls")
       :tokens (+ (gc/kwInt items ":tokInSum") (gc/kwInt items ":tokOutSum")) :sysTok (gc/kwInt items ":sysTok")
       :firstFail (gc/kwText items ":firstFail"))

fn headerOf items: (List gc/Sx) -> Header
  (Header :arms (map gc/sxText (gc/kwList items ":arms")) :models (map gc/sxText (gc/kwList items ":models"))
          :taskIds (map gc/sxText (gc/kwList items ":taskIds")) :reps (gc/kwInt items ":reps"))

fn uniqueStep acc: (List Row) r: Row -> (List Row)
  (if (listAny? (fn [(o Row)] -> Bool (= o.key r.key)) acc) acc (listAppend acc (list r)))

fn stageNames -> (List String)
  (list "ok" "extract" "parse" "check" "execute" "correct" "harness")

fn statFor h: Header rows: (List Row) model: String arm: String -> ArmStat
  (let [(mine (filter (fn [(r Row)] -> Bool (and (= r.model model) (= r.arm arm))) rows))
        (wanted (listFlatMap (fn [(t String)] -> (List String)
                  (map (fn [(i Int64)] -> String (str arm "|" t "|" model "|" (stringFromInt64 i))) (range 1 (+ h.reps 1))))
                  h.taskIds))
        (have (map (fn [(r Row)] -> String r.key) mine))
        (green (filter (fn [(r Row)] -> Bool r.solved) mine))]
    (ArmStat :model model :arm arm :trials (listLength mine) :expected (listLength wanted)
             :missing (listCount (fn [(k String)] -> Bool (not (listContains? have k))) wanted)
             :rawPass (listCount (fn [(r Row)] -> Bool r.rawPass) mine)
             :healedPass (listCount (fn [(r Row)] -> Bool r.healedPass) mine)
             :solved (listLength green)
             :tokens (listSum (map (fn [(r Row)] -> Int64 r.tokens) mine))
             :tokensNoCard (listSum (map (fn [(r Row)] -> Int64 (- r.tokens (* r.calls r.sysTok))) mine))
             :repairTurns (listSum (map (fn [(r Row)] -> Int64 (- r.calls 1)) green))
             :greens (listSort (map (fn [(r Row)] -> Int64 r.tokens) green))
             :stages (map (fn [(s String)] -> (Pair String Int64) (pair s (listCount (fn [(r Row)] -> Bool (= r.firstFail s)) mine))) (stageNames))))

fn tailrec isqrtLoop n: Int64 x: Int64 -> Int64
  (let [(y (/ (+ x (/ n x)) 2))]
    (if (>= y x) x (isqrtLoop n y)))

fn isqrt n: Int64 -> Int64
  (if (< n 2) n (isqrtLoop n n))

fn wilson k: Int64 n: Int64 -> (Pair Int64 Int64)
  (if (<= n 0)
    (pair 0 1000)
    (let [(half (/ (* 196 (isqrt (+ (/ (* (* k (- n k)) 1000000) n) 960400))) 100))
          (center (+ (* k 1000) 1921))
          (denom (+ (* n 1000) 3842))]
      (pair (max 0 (/ (* (- center half) 1000) denom))
            (min 1000 (/ (+ (* (+ center half) 1000) (- denom 1)) denom)))))

fn permille k: Int64 n: Int64 -> Int64
  (if (<= n 0) 0 (/ (+ (* k 1000) (/ n 2)) n))

fn pctText p: Int64 -> String
  (let [(a (abs p))]
    (str (if (< p 0) "-" "") (stringFromInt64 (/ a 10)) "." (stringFromInt64 (mod a 10))))

fn quantile xs: (List Int64) pct: Int64 -> Int64
  (optionOr (listGet xs (/ (+ (* pct (- (listLength xs) 1)) 50) 100)) 0)

fn rateText k: Int64 n: Int64 -> String
  (let [(w (wilson k n))]
    (str "(:n " (stringFromInt64 k) " :pct " (gc/asnQuote (pctText (permille k n)))
         " :ci95 (" (gc/asnQuote (pctText (pairFirst w))) " " (gc/asnQuote (pctText (pairSecond w))) "))"))

fn perSolved total: Int64 solved: Int64 -> String
  (if (<= solved 0) "\"n/a\"" (stringFromInt64 (/ total solved)))

fn armLine s: ArmStat -> String
  (str "(:arm " (gc/asnQuote s.arm) " :model " (gc/asnQuote s.model)
       " :trials " (stringFromInt64 s.trials) " :expected " (stringFromInt64 s.expected) " :missing " (stringFromInt64 s.missing)
       " :rawPass " (rateText s.rawPass s.trials)
       " :healedPass " (rateText s.healedPass s.trials) " :healApplies " (if (= (gc/armLang s.arm) "asl") "true" "false")
       " :solved " (rateText s.solved s.trials)
       " :tokToGreenQ (" (stringFromInt64 (quantile s.greens 25)) " " (stringFromInt64 (quantile s.greens 50)) " " (stringFromInt64 (quantile s.greens 75)) ")"
       " :tokPerSolved " (perSolved s.tokens s.solved) " :tokPerSolvedNoCard " (perSolved s.tokensNoCard s.solved)
       " :repairTurnsPerSolved " (if (<= s.solved 0) "\"n/a\"" (gc/asnQuote (pctText (/ (* s.repairTurns 10) s.solved))))
       " :firstFail (" (stringJoin (map (fn [(p (Pair String Int64))] -> String (str "(:stage " (gc/asnQuote (pairFirst p)) " :n " (stringFromInt64 (pairSecond p)) ")"))
                                        (filter (fn [(p (Pair String Int64))] -> Bool (> (pairSecond p) 0)) s.stages)) " ") "))")

fn statOf stats: (List ArmStat) model: String arm: String -> (Option ArmStat)
  (listFind (fn [(s ArmStat)] -> Bool (and (= s.model model) (= s.arm arm))) stats)

fn h1Line model: String asl: ArmStat base: ArmStat -> String
  (let [(diff (- (permille asl.healedPass asl.trials) (permille base.rawPass base.trials)))]
    (str "(:compare :h \"H1\" :model " (gc/asnQuote model) " :aslHealedPass1 " (gc/asnQuote (pctText (permille asl.healedPass asl.trials)))
         " :vs " (gc/asnQuote base.arm) " :rawPass1 " (gc/asnQuote (pctText (permille base.rawPass base.trials)))
         " :diffPoints " (gc/asnQuote (pctText diff)) " :threshold \"-15.0\" :refuted " (if (< diff -150) "true" "false") ")"))

fn h2Line model: String asl: ArmStat base: ArmStat -> String
  (if (or (<= asl.solved 0) (or (<= base.solved 0) (<= base.tokensNoCard 0)))
    (str "(:compare :h \"H2\" :model " (gc/asnQuote model) " :vs " (gc/asnQuote base.arm) " :ratio \"n/a\" :refuted " (if (<= asl.solved 0) "true" "false") " :note \"an arm solved nothing\")")
    (let [(ratio (/ (* (* asl.tokensNoCard base.solved) 100) (* asl.solved base.tokensNoCard)))]
      (str "(:compare :h \"H2\" :model " (gc/asnQuote model) " :aslTokPerSolvedNoCard " (stringFromInt64 (/ asl.tokensNoCard asl.solved))
           " :vs " (gc/asnQuote base.arm) " :tokPerSolvedNoCard " (stringFromInt64 (/ base.tokensNoCard base.solved))
           " :ratioPct " (stringFromInt64 ratio) " :thresholdPct 150 :refuted " (if (> ratio 150) "true" "false") ")")))

fn surfaceLine h: String model: String variant: ArmStat asl: ArmStat -> String
  (str "(:compare :h " (gc/asnQuote h) " :model " (gc/asnQuote model) " :arm " (gc/asnQuote variant.arm)
       " :rawPass1 " (gc/asnQuote (pctText (permille variant.rawPass variant.trials)))
       " :aslRawPass1 " (gc/asnQuote (pctText (permille asl.rawPass asl.trials)))
       " :diffPoints " (gc/asnQuote (pctText (- (permille variant.rawPass variant.trials) (permille asl.rawPass asl.trials))))
       " :effectPoints \"10.0\" :note \"point difference only; the paired Holm test of the protocol is not computed here\")")

fn compareLines stats: (List ArmStat) model: String -> (List String)
  (match (statOf stats model "asl")
    ((none) (list))
    ((some asl)
      (listAppend
        (listFlatMap (fn [(arm String)] -> (List String)
                       (match (statOf stats model arm)
                         ((none) (list))
                         ((some base) (list (h1Line model asl base) (h2Line model asl base)))))
                     (list "py" "ts"))
        (listAppend
          (match (statOf stats model "aslParen") ((none) (list)) ((some v) (list (surfaceLine "H3" model v asl))))
          (match (statOf stats model "aslWrapFn") ((none) (list)) ((some v) (list (surfaceLine "H4" model v asl))))))))

fn refusedLine stats: (List ArmStat) -> String
  (str "(:score :status :refused :reason \"an arm has missing or surplus trials, so no comparison is printed\" :incomplete ("
       (stringJoin (map (fn [(s ArmStat)] -> String
                          (str "(:model " (gc/asnQuote s.model) " :arm " (gc/asnQuote s.arm) " :have " (stringFromInt64 s.trials)
                               " :expected " (stringFromInt64 s.expected) " :missing " (stringFromInt64 s.missing) ")"))
                        (filter (fn [(s ArmStat)] -> Bool (or (> s.missing 0) (!= s.trials s.expected))) stats)) " ")
       "))")

fn scoreText text: String -> ScoreOut
  (match (gc/readForms text)
    ((err e) (ScoreOut :complete false :lines (list) :stats (list) :error (str "results are unreadable: " e)))
    ((ok forms)
      (match (listFind (fn [(f gc/Sx)] -> Bool (= (gc/headOf f) ":run")) forms)
        ((none) (ScoreOut :complete false :lines (list) :stats (list) :error "results hold no (:run ...) header row"))
        ((some head)
          (let [(h (headerOf (gc/sxItems head)))
                (rows (fold uniqueStep (list) (map (fn [(f gc/Sx)] -> Row (rowOf (gc/sxItems f))) (filter (fn [(f gc/Sx)] -> Bool (= (gc/headOf f) ":trial")) forms))))
                (stats (listFlatMap (fn [(m String)] -> (List ArmStat) (map (fn [(a String)] -> ArmStat (statFor h rows m a)) h.arms)) h.models))
                (complete (and (not (listEmpty? stats)) (listAll? (fn [(s ArmStat)] -> Bool (and (= s.missing 0) (= s.trials s.expected))) stats)))]
            (ScoreOut :complete complete
                      :lines (listAppend (map armLine stats)
                                         (if complete
                                           (listFlatMap (fn [(m String)] -> (List String) (compareLines stats m)) h.models)
                                           (list (refusedLine stats))))
                      :stats stats :error ""))))))

fn ! readAll! paths: (List String) -> (Result String String)
  (fold (fn [(acc (Result String String)) (p String)] -> (Result String String)
          (match acc
            ((err e) (err e))
            ((ok text)
              (match (fileReadString p)
                ((err e) (err e))
                ((ok more) (ok (str text more "\n")))))))
        (ok "")
        paths)

fn ! report! paths: (List String) -> (Result Int64 String)
  (match (readAll! paths)
    ((err e) (err e))
    ((ok text)
      (let [(out (scoreText text))]
        (if (not (stringEmpty? out.error))
          (err out.error)
          (do
            (println (stringJoin out.lines "\n"))
            (if out.complete (ok 0) (err "score refused: an arm has missing trials")))))))

fn ! main args: (List String) -> (Result Int64 String)
  (if (listEmpty? args)
    (err "usage: asl run asl/bench/gen/score.asl TRIALS.asn [MORE.asn ...]")
    (report! args))
