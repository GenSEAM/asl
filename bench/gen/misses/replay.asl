(module aslBench/gen/misses/replay
  :x [main Shot Seen shotsOf firstError classOf loadClasses MissClass]
  :i [(aslBench/gen/core :a gc)
      (asl-tools/fleet/run :a fr)])

; (:m :ref MISS-ABSORB :do "offline replay of the generation bench, no model call: every ASL reply the bench graded as failing is rebuilt into its harness and sent through check, then heal, then check and test; one row per reply, then raw pass and pass after absorb per model and per miss class")

(schema Shot
  (:f key String)
  (:f turn Int64)
  (:f model String)
  (:f arm String)
  (:f task String)
  (:f recorded String)
  (:f reply String))

(schema Seen
  (:f shot Shot)
  (:f raw String)
  (:f err String)
  (:f cls String)
  (:f via String)
  (:f after String))

(schema MissClass
  (:f id String)
  (:f prior Bool)
  (:f marks (List String)))

fn shotsOfRow items: (List gc/Sx) -> (List Shot)
  (let [(stages (map gc/sxText (gc/kwList items ":stages")))
        (replies (map gc/sxText (gc/kwList items ":replies")))
        (arm (gc/kwText items ":arm"))]
    (if (not (= (gc/armLang arm) "asl"))
      (list)
      (listFlatMap (fn [(i Int64)] -> (List Shot)
                     (let [(stage (optionOr (listGet stages i) ""))]
                       (if (or (= stage "ok") (stringEmpty? stage))
                         (list)
                         (list (Shot :key (gc/kwText items ":key") :turn i :model (gc/kwText items ":model") :arm arm
                                     :task (gc/kwText items ":task") :recorded stage :reply (optionOr (listGet replies i) ""))))))
                   (range 0 (listLength stages)))))

fn shotsOf text: String -> (Result (List Shot) String)
  (match (gc/readForms text)
    ((err e) (err e))
    ((ok forms)
      (ok (listFlatMap (fn [(f gc/Sx)] -> (List Shot) (if (= (gc/headOf f) ":trial") (shotsOfRow (gc/sxItems f)) (list))) forms))))

fn errorLine? l: String -> Bool
  (or (stringContains? l "ERR_") (or (stringContains? l "error") (stringContains? l "unbound")))

fn firstError out: String -> String
  (gc/clip (stringTrim (optionOr (listHead (filter errorLine? (stringLines out))) (optionOr (listHead (stringLines out)) ""))) 300)

fn classRow items: (List gc/Sx) -> MissClass
  (MissClass :id (gc/kwText items ":id") :prior (gc/kwBool items ":prior") :marks (map gc/sxText (gc/kwList items ":marks")))

fn loadClasses text: String -> (List MissClass)
  (match (gc/readForms text)
    ((err _) (list))
    ((ok forms) (map (fn [(f gc/Sx)] -> MissClass (classRow (gc/sxItems f))) (filter (fn [(f gc/Sx)] -> Bool (= (gc/headOf f) ":class")) forms))))

fn classOf classes: (List MissClass) out: String -> String
  (match (listFind (fn [(c MissClass)] -> Bool (listAny? (fn [(m String)] -> Bool (stringContains? out m)) c.marks)) classes)
    ((some c) c.id)
    ((none) "other"))

; (:m :ref MISS-ABSORB :do "a reply the bench failed at parse or check that checks now was taken by the reader: its class is read off the foreign head it holds")
fn acceptedClass recorded: String text: String stage: String -> String
  (cond
    ((not (or (= recorded "parse") (= recorded "check"))) stage)
    ((stringContains? text "(== ") "eqEq")
    ((stringContains? text "(% ") "percent")
    (else "regraded"))

fn priorClass? classes: (List MissClass) id: String -> Bool
  (match (listFind (fn [(c MissClass)] -> Bool (= c.id id)) classes)
    ((some c) c.prior)
    ((none) false))

fn ! aslChild! bin: String dir: String cmd: String path: String -> fr/Done
  (fr/runOneLimited (fr/job (list "nice" "-n" "10" bin cmd path) dir (fr/childEnv (list (str "ASL_ROOT=" dir)))) (fr/limits 60 16))

fn checkFailed? d: fr/Done -> Bool
  (or (!= d.exit 0) (stringContains? d.out ":status :failed"))

fn parseOut? out: String -> Bool
  (or (stringContains? out ": parse ") (stringContains? out "ERR_UNBALANCED"))

fn ! testStage! bin: String dir: String path: String -> String
  (let [(run (aslChild! bin dir "test" path))]
    (cond
      ((= run.exit 0) "ok")
      ((or (stringContains? run.out "FAILCASE") (stringContains? run.out "ERR_ASSERT")) "correct")
      (else "execute")))

fn ! stageOf! bin: String dir: String path: String -> (Pair String String)
  (let [(chk (aslChild! bin dir "check" path))]
    (if (checkFailed? chk)
      (pair (if (parseOut? chk.out) "parse" "check") chk.out)
      (pair (testStage! bin dir path) "")))

fn ! seeShot! bin: String root: String work: String classes: (List MissClass) n: Int64 s: Shot -> Seen
  (match (gc/extractCode s.reply)
    ((none) (Seen :shot s :raw "extract" :err "no complete fenced code block" :cls "extract" :via "none" :after "extract"))
    ((some code)
      (match (gc/loadTask root s.task)
        ((err e) (Seen :shot s :raw "harness" :err e :cls "harness" :via "none" :after "harness"))
        ((ok t)
          (let [(dir (str work "/s" (stringFromInt64 n)))
                (made (dirCreate dir))
                (path (str dir "/cand.asl"))
                (text (gc/aslHarness "cand" (pairFirst (gc/normaliseAsl s.arm code)) t t.cases))
                (wrote (fileWrite path text))
                (kept (fileWrite (str dir "/raw.asl") text))
                (raw (stageOf! bin dir path))
                (rawOut (fileWrite (str dir "/raw.out") (pairSecond raw)))
                (rawStage (pairFirst raw))
                (cls (if (or (= rawStage "parse") (= rawStage "check")) (classOf classes (pairSecond raw)) rawStage))]
            (if (not (or (= rawStage "parse") (= rawStage "check")))
              (Seen :shot s :raw rawStage :err "" :cls (acceptedClass s.recorded text rawStage) :via "accept" :after rawStage)
              (let [(healed (aslChild! bin dir "heal" path))
                    (receipt (fileWrite (str dir "/heal.out") healed.out))
                    (after (stageOf! bin dir path))
                    (left (fileWrite (str dir "/after.out") (pairSecond after)))]
                (Seen :shot s :raw rawStage :err (firstError (pairSecond raw)) :cls cls :via "heal" :after (pairFirst after)))))))))

fn seenRow n: Int64 v: Seen -> String
  (str "(:shot :n " (stringFromInt64 n) " :key " (gc/asnQuote v.shot.key) " :turn " (stringFromInt64 v.shot.turn)
       " :model " (gc/asnQuote v.shot.model) " :arm " (gc/asnQuote v.shot.arm) " :task " (gc/asnQuote v.shot.task)
       " :recorded " (gc/asnQuote v.shot.recorded) " :raw " (gc/asnQuote v.raw) " :class " (gc/asnQuote v.cls)
       " :via " (gc/asnQuote v.via) " :after " (gc/asnQuote v.after) " :err " (gc/asnQuote v.err) ")")

; (:m :ref MISS-ABSORB :do "the denominator is the bench's own grade of the reply, parse or check, so a reply the reader now accepts stays in it and counts as absorbed when it passes its cases")
fn syntaxRaw? v: Seen -> Bool
  (or (= v.shot.recorded "parse") (= v.shot.recorded "check"))

fn countOf p: (fn [Seen] -> Bool) xs: (List Seen) -> Int64
  (listLength (filter p xs))

fn distinct xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn tallyRow tag: String name: String xs: (List Seen) -> String
  (let [(syn (filter syntaxRaw? xs))
        (green (countOf (fn [(v Seen)] -> Bool (= v.after "ok")) syn))]
    (str "(:" tag " " (gc/asnQuote name) " :failingReplies " (stringFromInt64 (listLength xs)) " :syntaxOrPrior " (stringFromInt64 (listLength syn))
         " :passAfterAbsorb " (stringFromInt64 green)
         " :percent " (stringFromInt64 (if (listEmpty? syn) 0 (/ (* 100 green) (listLength syn)))) ")"))

fn summary classes: (List MissClass) seen: (List Seen) -> (List String)
  (let [(models (distinct (map (fn [(v Seen)] -> String v.shot.model) seen)))
        (ids (distinct (map (fn [(v Seen)] -> String v.cls) seen)))
        (first (filter (fn [(v Seen)] -> Bool (= v.shot.turn 0)) seen))
        (prior (filter (fn [(v Seen)] -> Bool (and (syntaxRaw? v) (priorClass? classes v.cls))) seen))]
    (listAppend
      (map (fn [(m String)] -> String (tallyRow "model" m (filter (fn [(v Seen)] -> Bool (= v.shot.model m)) seen))) models)
      (listAppend
        (map (fn [(m String)] -> String (tallyRow "modelFirstTurn" m (filter (fn [(v Seen)] -> Bool (= v.shot.model m)) first))) models)
        (listAppend
          (map (fn [(c String)] -> String (tallyRow "class" c (filter (fn [(v Seen)] -> Bool (= v.cls c)) seen))) ids)
          (list (tallyRow "total" "priorClasses" prior) (tallyRow "total" "all" seen))))))

fn flagValue args: (List String) flag: String dflt: String -> String
  (match (listIndexOf args flag)
    ((some i) (optionOr (listGet args (+ i 1)) dflt))
    ((none) dflt))

fn ! readShots! paths: (List String) -> (List Shot)
  (listFlatMap (fn [(p String)] -> (List Shot)
                 (match (fileReadString p)
                   ((err _) (list))
                   ((ok text) (match (shotsOf text) ((ok xs) xs) ((err _) (list))))))
               paths)

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (flagValue args "--root" "."))
        (work (flagValue args "--work" ""))
        (results (flagValue args "--results" ""))
        (bin (flagValue args "--asl" (str root "/bin/asl")))
        (limit (optionOr (stringToInt64 (flagValue args "--limit" "100000")) 100000))
        (classes (match (fileReadString (str root "/asl/bench/gen/misses/catalogue.asn")) ((ok t) (loadClasses t)) ((err _) (list))))]
    (if (or (stringEmpty? work) (or (stringEmpty? results) (not (stringContains? work "aslBenchGen"))))
      (err "usage: replay --results DIR --work /tmp/aslBenchGen-X [--root R] [--asl BIN] [--limit N]")
      (match (dirList results)
        ((err e) (err e))
        ((ok names)
          (let [(made (dirCreate work))
                (paths (map (fn [(n String)] -> String (str results "/" n)) (listSort (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asn")) names))))
                (shots (listTake (readShots! paths) limit))
                (seen (map (fn [(p (Pair Int64 Shot))] -> Seen
                             (let [(v (seeShot! bin root work classes (pairFirst p) (pairSecond p)))
                                   (said (println (seenRow (pairFirst p) v)))]
                               v))
                           (zip (range 0 (listLength shots)) shots)))
                (rows (summary classes seen))
                (printed (map (fn [(r String)] -> Bool (do (println r) true)) rows))]
            (ok 0))))))
