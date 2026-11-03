(module asl-forms/bench/parenBench
  :x [main Pop Outcome collect drawIdx walk outcomeOf permille rateText evenPick civilDate esc optValue stepRng0 classRows statRows fixResult]
  :i [(asl-forms/indent :a ind) (asl-forms/gate :a g) (asl-forms/bench/parenMutants :a pm)])

; (:m :ref PAREN-BENCH :do "re-measures indentation-guided repair (asl-forms/indent guide) on seeded one-closer mutants of the tracked .asl top-level forms: bench mutants prints the restore rate per mutation class, bench baseline sets the older (:fix) repair beside it on the same mutants; census is in parenCensus.asl; bench numbers go to results.lock.asn with method, scope and date")
(schema Pop (:f segs (List String)) (:f files Int64) (:f total Int64))

(schema Outcome (:f kind String) (:f dyck String) (:f res String) (:f mutated String) (:f orig String))

fn ! collect files: (List String) acc: (List String) nFiles: Int64 nSegs: Int64 -> Pop
  (match (listHead files)
    ((none) (Pop :segs (listReverse acc) :files nFiles :total nSegs))
    ((some p)
     (match (fileReadString p)
       ((err _) (collect (listDrop files 1) acc nFiles nSegs))
       ((ok t)
        (let [(ss (pm/segments t))
              (el (filter pm/eligible? ss))]
          (collect (listDrop files 1)
                   (fold (fn [(a (List String)) (s String)] -> (List String) (cons s a)) acc el)
                   (+ nFiles 1) (+ nSegs (listLength ss))))))))

fn drawIdx k: Int64 total: Int64 s: Int64 acc: (List Int64) -> (Pair (List Int64) Int64)
  (if (<= k 0)
    (pair (listSort acc) s)
    (let [(d (pm/draw s total))]
      (drawIdx (- k 1) total (pairSecond d) (cons (pairFirst d) acc))))

fn outcomeOf seg: String m: pm/Mutant -> Outcome
  (let [(g (ind/guide m.text))]
    (Outcome :kind m.kind
             :dyck (if (pm/balanced? m.text) "dyckBlind" "dyckCatches")
             :res (cond ((= g.text seg) "restored") ((pm/balanced? g.text) "balancedOther") (else "unbalanced"))
             :mutated m.text :orig seg))

; (:m :ref PAREN-BENCH :do "one pass over the eligible segments in order; each drawn index mutates that segment once, repeats allowed, a draw whose mutation does not exist (under two trail closers, no other line to move to) counts as attempted only")
fn walk segs: (List String) idx: Int64 want: (List Int64) s: Int64 acc: (List Outcome) -> (Pair (List Outcome) Int64)
  (match (listHead want)
    ((none) (pair (listReverse acc) s))
    ((some w)
     (if (= w idx)
       (let [(seg (optionOr (listHead segs) ""))
             (mm (pm/mutate seg s))]
         (walk segs idx (listDrop want 1) (pairSecond mm)
               (match (pairFirst mm)
                 ((none) acc)
                 ((some m) (cons (outcomeOf seg m) acc)))))
       (walk (listDrop segs 1) (+ idx 1) want s acc))))

fn permille r: Int64 of: Int64 -> Int64
  (if (= of 0) 0 (/ (+ (* r 2000) of) (* of 2)))

fn rateText p: Int64 -> String
  (str (/ p 1000) "." (if (< (mod p 1000) 100) (if (< (mod p 1000) 10) "00" "0") "") (mod p 1000))

fn civilDate ns: Int64 -> String
  (let [(z (+ (/ ns 86400000000000) 719468))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (- doe (- (/ doe 1460) (- (/ doe 36524) (/ doe 146096)))) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)))]
    (str y "-" (if (< m 10) "0" "") m "-" (if (< d 10) "0" "") d))

fn countBy keys: (List String) -> (List (Pair String Int64))
  (mapPairs (fold (fn [(m (Map String Int64)) (k String)] -> (Map String Int64) (mapSet m k (+ 1 (mapGetOr m k 0)))) (mapEmpty) keys))

fn optValue args: (List String) flag: String -> (Option String)
  (match (listHead args)
    ((none) (none))
    ((some a) (if (= a flag) (listGet args 1) (optValue (listDrop args 1) flag))))

fn optInt args: (List String) flag: String dflt: Int64 -> Int64
  (optionOr (stringToInt64 (optionOr (optValue args flag) "")) dflt)

fn ! fileList args: (List String) -> (List String)
  (match (optValue args "--files")
    ((some p) (match (fileReadString p) ((ok t) (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines t))) ((err _) (list))))
    ((none) (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (processRun "git ls-files '*.asl'").stdout))))

fn countOf rows: (List Outcome) pred: (fn [Outcome] -> Bool) -> Pair Int64 Int64
  (let [(sel (filter pred rows))]
    (pair (listLength (filter (fn [(o Outcome)] -> Bool (= o.res "restored")) sel)) (listLength sel)))

fn classRow name: String rows: (List Outcome) pred: (fn [Outcome] -> Bool) -> String
  (let [(c (countOf rows pred))]
    (str "(:class " name " :restored " (pairFirst c) " :of " (pairSecond c) " :rate " (rateText (permille (pairFirst c) (pairSecond c))) ")"))

fn statRows rows: (List Outcome) -> (List String)
  (map (fn [(p (Pair String Int64))] -> String (str "(:stat " (pairFirst p) " :n " (pairSecond p) ")"))
       (countBy (map (fn [(o Outcome)] -> String (str "\"" o.kind "\" \"" o.dyck "\" \"" o.res "\"")) rows)))

fn classRows rows: (List Outcome) -> (List String)
  (list (classRow "missingCloser" rows (fn [(o Outcome)] -> Bool (= o.kind "delete")))
        (classRow "extraCloser" rows (fn [(o Outcome)] -> Bool (= o.kind "insert")))
        (classRow "movedCloserDyckBlind" rows (fn [(o Outcome)] -> Bool (and (= o.kind "move") (= o.dyck "dyckBlind"))))
        (classRow "movedCloserUnbalanced" rows (fn [(o Outcome)] -> Bool (and (= o.kind "move") (= o.dyck "dyckCatches"))))
        (classRow "all" rows (fn [(o Outcome)] -> Bool true)))

; (:m :ref PAREN-BENCH :do "the baseline sample is every step-th mutant, so it spans files instead of taking the first ones; limit 80 matches the older measurement M5")
fn evenPick rows: (List Outcome) limit: Int64 -> (List Outcome)
  (let [(n (listLength rows)) (step (if (> limit 0) (max 1 (/ n limit)) 1))]
    (listTake (filter (fn [(o Outcome)] -> Bool true) (pickStep rows 0 step (list))) limit))

fn pickStep rows: (List Outcome) i: Int64 step: Int64 acc: (List Outcome) -> (List Outcome)
  (match (listHead rows)
    ((none) (listReverse acc))
    ((some o) (pickStep (listDrop rows 1) (+ i 1) step (if (= (mod i step) 0) (cons o acc) acc))))

fn fixResult o: Outcome -> String
  (let [(r (g/aslRepair o.mutated false))]
    (cond
      ((= r.status "unique") (if (= r.text o.orig) "restored" "wrongRepair"))
      ((= r.status "ambiguous") "ambiguous")
      ((= r.status "none") "saysBalanced")
      (else "unrepairable")))

fn baselineRows sample: (List Outcome) -> (List String)
  (let [(keyed (map (fn [(o Outcome)] -> String (str "\"" o.kind "\" \"" o.dyck "\" \"fix=" (fixResult o) "\" \"guided=" o.res "\"")) sample))
        (fixed (map fixResult sample))
        (n (listLength sample))]
    (listAppend
      (map (fn [(p (Pair String Int64))] -> String (str "(:pair " (pairFirst p) " :n " (pairSecond p) ")")) (countBy keyed))
      (list (str "(:baseline :mutants " n
                 " :fixRestored " (listLength (filter (fn [(r String)] -> Bool (= r "restored")) fixed))
                 " :fixAmbiguous " (listLength (filter (fn [(r String)] -> Bool (= r "ambiguous")) fixed))
                 " :fixWrong " (listLength (filter (fn [(r String)] -> Bool (= r "wrongRepair")) fixed))
                 " :fixUnrepairable " (listLength (filter (fn [(r String)] -> Bool (= r "unrepairable")) fixed))
                 " :fixSaysBalanced " (listLength (filter (fn [(r String)] -> Bool (= r "saysBalanced")) fixed))
                 " :guidedRestored " (listLength (filter (fn [(o Outcome)] -> Bool (= o.res "restored")) sample))
                 ")"))))

fn esc s: String -> String
  (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"")

fn ! lockHeader id: String args: (List String) method: String nFiles: Int64 -> String
  (str "(:benchLock :id " id " :label \"" (esc (optionOr (optValue args "--label") "")) "\" :date \"" (civilDate (nowNs)) "\" :method \"" (esc method)
       "\" :scope \"seed " (optInt args "--seed" 7) ", " nFiles " tracked .asl files at the working tree; " (esc (stringTrim (processRun "uname -sm").stdout)) "\")\n")

fn ! emit lines: (List String) args: (List String) id: String method: String nFiles: Int64 -> Unit
  (do
    (map (fn [(l String)] -> Unit (println l)) lines)
    (match (optValue args "--lock")
      ((none) ())
      ((some p)
       (let [(prior (match (fileReadString p) ((ok t) t) ((err _) "")))]
         (match (fileWrite p (str prior (lockHeader id args method nFiles) (stringJoin lines "\n") "\n"))
           ((ok _) ())
           ((err e) (eprintln (str "cannot write " p ": " e))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(mode (optionOr (listHead args) "mutants"))
        (seed (optInt args "--seed" 7))
        (count (optInt args "--count" 20000))
        (files (fileList args))
        (pop (collect files (list) 0 0))
        (nEl (listLength pop.segs))
        (dr (drawIdx count nEl (stepRng0 seed) (list)))
        (res (walk pop.segs 0 (pairFirst dr) (pairSecond dr) (list)))
        (rows (pairFirst res))
        (head (str "(:parenBench :mode " mode " :seed " seed " :count " count " :files " pop.files " :segments " pop.total " :eligible " nEl " :mutants " (listLength rows) ")"))]
    (cond
      ((= nEl 0) (err "no eligible segments: pass --files PATHLIST or run from a git checkout"))
      ((= mode "baseline")
       (do (emit (cons head (baselineRows (evenPick rows (optInt args "--limit" 80)))) args "parenBaseline"
                 "asl-forms/bench/parenBench baseline: the older repair (asl-forms/gate aslRepair, what (:fix :file F) answers) and indentation-guided repair (asl-forms/indent guide) on an even spread of the seeded one-closer mutants of tracked .asl top-level forms" pop.files)
           (ok 0)))
      (else
        (do (emit (cons head (listAppend (classRows rows) (statRows rows))) args "parenRestore"
                  "asl-forms/bench/parenBench mutants: seeded 32-bit LCG; each tracked .asl file split into column-0 segments, kept when balanced, 4+ lines and unchanged by indentation guide; count draws with replacement, each deletes, duplicates or moves one line-trail closer; restored means guide returns the original segment byte for byte" pop.files)
            (ok 0)))))

fn stepRng0 seed: Int64 -> Int64
  (pm/stepRng (pm/stepRng seed))
