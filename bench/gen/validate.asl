(module aslBench/gen/validate
  :x [main Judged FileReport judgeLine reportOf reportLine keptText slowWallMs]
  :i [(aslBench/gen/core :a gc)])

; (:m :ref GENRUN-CROSSWIRE :do "asl run asl/bench/gen/validate.asl [--regrade] [--rows] [--write] RESULTS.asn ...: classifies every trial row of result files written before the link fix, from what the rows hold: crossWired when a reply answers another request (gc/rowVerdict: the entry it defines, prompt token counts that do not grow), infra when the row is an (:infra ...) row or, with --regrade, when a turn recorded as check does not fail at check or parse when graded again, valid otherwise. A link call that passed its 300 s limit cost its trial at least the limit plus the 30 s back-off, and from that trial on answers were read in completion order, so the trusted rows are the valid ones before the first cross-wired row and before the first trial of 330 s or more. Prints one row per file; writes nothing unless --write, which puts the header and the trusted rows in NAME.valid.asn next to the file")

(schema Judged
  (:f index Int64)
  (:f head String)
  (:f key String)
  (:f class String)
  (:f why String)
  (:f wallMs Int64)
  (:f line String))

(schema FileReport
  (:f trials Int64)
  (:f valid Int64)
  (:f crossWired Int64)
  (:f infra Int64)
  (:f callFailed Int64)
  (:f firstBad Int64)
  (:f firstBadKey String)
  (:f firstBadWhy String)
  (:f slowFrom Int64)
  (:f trusted Int64))

fn slowWallMs -> Int64
  330000

fn itemsOf line: String -> (List gc/Sx)
  (match (gc/readForms line)
    ((ok forms) (match (listHead forms) ((some f) (gc/sxItems f)) ((none) (list))))
    ((err _) (list)))

fn headOfLine line: String -> String
  (cond
    ((stringStartsWith? line "(:trial ") ":trial")
    ((stringStartsWith? line "(:run ") ":run")
    ((stringStartsWith? line "(:infra ") ":infra")
    ((stringStartsWith? line "(:callFailed ") ":callFailed")
    (else ""))

; (:m :do "the class of one line without any tool run: a trial row is crossWired or valid, an infra row is infra, every other row keeps an empty class")
fn judgeLine tasks: (List gc/Task) index: Int64 line: String -> Judged
  (let [(head (headOfLine line))]
    (cond
      ((= head ":trial")
        (let [(items (itemsOf line))
              (why (gc/rowVerdict tasks (gc/kwText items ":arm") (gc/kwText items ":task")
                                  (map gc/sxText (gc/kwList items ":replies"))
                                  (map (fn [(v gc/Sx)] -> Int64 (optionOr (stringToInt64 (gc/sxText v)) 0)) (gc/kwList items ":tokIn"))))]
          (Judged :index index :head head :key (gc/kwText items ":key") :class (if (stringEmpty? why) "valid" "crossWired") :why why
                  :wallMs (gc/kwInt items ":wallMs") :line line)))
      ((= head ":infra") (Judged :index index :head head :key (gc/kwText (itemsOf line) ":at") :class "infra" :why "an infra row" :wallMs 0 :line line))
      (else (Judged :index index :head head :key "" :class "" :why "" :wallMs 0 :line line))))

fn firstIndex rows: (List Judged) pick: (fn [Judged] -> Bool) -> Int64
  (match (listFind pick rows)
    ((some r) r.index)
    ((none) 0))

fn trustedBefore r: FileReport -> Int64
  (cond
    ((and (= r.firstBad 0) (= r.slowFrom 0)) 0)
    ((= r.firstBad 0) r.slowFrom)
    ((= r.slowFrom 0) r.firstBad)
    (else (min r.firstBad r.slowFrom)))

fn trusted? cut: Int64 r: Judged -> Bool
  (and (= r.class "valid") (or (= cut 0) (< r.index cut)))

fn reportOf rows: (List Judged) -> FileReport
  (let [(trials (filter (fn [(r Judged)] -> Bool (= r.head ":trial")) rows))
        (bad (listFind (fn [(r Judged)] -> Bool (= r.class "crossWired")) rows))
        (base (FileReport :trials (listLength trials)
                          :valid (listCount (fn [(r Judged)] -> Bool (= r.class "valid")) rows)
                          :crossWired (listCount (fn [(r Judged)] -> Bool (= r.class "crossWired")) rows)
                          :infra (listCount (fn [(r Judged)] -> Bool (= r.class "infra")) rows)
                          :callFailed (listCount (fn [(r Judged)] -> Bool (= r.head ":callFailed")) rows)
                          :firstBad (match bad ((some r) r.index) ((none) 0))
                          :firstBadKey (match bad ((some r) r.key) ((none) ""))
                          :firstBadWhy (match bad ((some r) r.why) ((none) ""))
                          :slowFrom (firstIndex trials (fn [(r Judged)] -> Bool (>= r.wallMs (slowWallMs))))
                          :trusted 0))
        (cut (trustedBefore base))]
    (with base :trusted (listCount (fn [(r Judged)] -> Bool (trusted? cut r)) rows)))

fn indexText i: Int64 -> String
  (if (= i 0) "none" (stringFromInt64 i))

fn reportLine path: String r: FileReport -> String
  (str "(:validate :file " (gc/asnQuote path) " :trials " (stringFromInt64 r.trials) " :valid " (stringFromInt64 r.valid)
       " :crossWired " (stringFromInt64 r.crossWired) " :infra " (stringFromInt64 r.infra) " :callFailed " (stringFromInt64 r.callFailed)
       " :firstBad " (indexText r.firstBad) " :firstBadKey " (gc/asnQuote r.firstBadKey) " :firstBadWhy " (gc/asnQuote r.firstBadWhy)
       " :slowFrom " (indexText r.slowFrom) " :trusted " (stringFromInt64 r.trusted) ")")

fn keptText rows: (List Judged) -> String
  (let [(cut (trustedBefore (reportOf rows)))]
    (str (stringJoin (map (fn [(r Judged)] -> String r.line)
                          (filter (fn [(r Judged)] -> Bool (or (= r.head ":run") (trusted? cut r))) rows))
                     "\n")
         "\n"))

; (:m :do "with --regrade a valid asl row holding a turn recorded as check is graded again turn by turn; a recorded check that now passes check (ok, correct or execute) was a tool failure at the time, so the row is infra")
fn ! regraded! cfg: gc/Config tasks: (List gc/Task) r: Judged -> Judged
  (let [(items (itemsOf r.line))
        (arm (gc/kwText items ":arm"))
        (stages (map gc/sxText (gc/kwList items ":stages")))
        (replies (map gc/sxText (gc/kwList items ":replies")))
        (dir (str cfg.work "/r" (stringFromInt64 r.index)))]
    (if (or (!= r.class "valid") (or (!= (gc/armLang arm) "asl") (not (listContains? stages "check"))))
      r
      (match (listFind (fn [(t gc/Task)] -> Bool (= t.id (gc/kwText items ":task"))) tasks)
        ((none) r)
        ((some t)
          (let [(made (dirCreate dir))
                (conf (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"aslBenchGenSandbox\")"))
                (now (map (fn [(i Int64)] -> String
                            (if (= (optionOr (listGet stages i) "") "check")
                              (pairFirst (gc/gradeReply! cfg dir arm t (optionOr (listGet replies i) ""))).stage
                              "kept"))
                          (range 0 (listLength stages))))]
            (if (listAny? (fn [(s String)] -> Bool (listContains? (list "ok" "correct" "execute") s)) now)
              (with r :class "infra" :why (str "turns recorded as check grade now as (" (stringJoin now " ") ")"))
              r))))))

fn validName path: String -> String
  (str (if (stringEndsWith? path ".asn") (gc/slice path 0 (- (stringLength path) 4)) path) ".valid.asn")

fn ! validateFile! cfg: gc/Config tasks: (List gc/Task) flags: (List String) path: String -> (Result Int64 String)
  (match (fileReadString path)
    ((err e) (err (str path ": " e)))
    ((ok text)
      (let [(lines (stringLines text))
            (judged (map (fn [(i Int64)] -> Judged (judgeLine tasks (+ i 1) (optionOr (listGet lines i) ""))) (range 0 (listLength lines))))
            (rows (if (listContains? flags "--regrade") (map (fn [(r Judged)] -> Judged (regraded! cfg tasks r)) judged) judged))
            (report (reportOf rows))
            (shown (if (listContains? flags "--rows")
                     (map (fn [(r Judged)] -> Bool
                            (do (println (str "(:row :index " (stringFromInt64 r.index) " :key " (gc/asnQuote r.key) " :class " (gc/asnQuote r.class) " :why " (gc/asnQuote r.why) ")")) true))
                          (filter (fn [(r Judged)] -> Bool (or (= r.class "crossWired") (= r.class "infra"))) rows))
                     (list)))
            (wrote (if (listContains? flags "--write") (match (fileWrite (validName path) (keptText rows)) ((err e) (err e)) ((ok _) (ok 0))) (ok 0)))]
        (do
          (println (reportLine path report))
          (match wrote
            ((err e) (err (str (validName path) ": " e)))
            ((ok _) (ok 0)))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(given (optionOr (envGet "ASL_CLI_ROOT") "."))
        (root (resultOr (realPath given) given))
        (flags (filter (fn [(a String)] -> Bool (stringStartsWith? a "--")) args))
        (paths (filter (fn [(a String)] -> Bool (not (stringStartsWith? a "--"))) args))
        (work (str (optionOr (envGet "TMPDIR") "/tmp") "/aslBenchGen-validate-" (stringFromInt64 (nowNs))))
        (cfg (gc/Config :root root :aslBin (str root "/bin/asl") :work work :out "" :repairs 0 :maxTokens 0 :priceIn 0 :priceOut 0 :capPico 0 :checkFirst true))]
    (cond
      ((listEmpty? paths) (err "usage: asl run asl/bench/gen/validate.asl [--regrade] [--rows] [--write] RESULTS.asn [MORE.asn ...]"))
      ((not (listAll? (fn [(f String)] -> Bool (listContains? (list "--regrade" "--rows" "--write") f)) flags)) (err "unknown flag; flags are --regrade --rows --write"))
      (else
        (match (gc/loadTasks root)
          ((err e) (err e))
          ((ok tasks)
            (let [(made (if (listContains? flags "--regrade") (ok? (dirCreate work)) true))
                  (done (fold (fn [(acc (Result Int64 String)) (p String)] -> (Result Int64 String)
                                (match acc
                                  ((err e) (err e))
                                  ((ok _) (validateFile! cfg tasks flags p))))
                              (ok 0)
                              paths))
                  (cleaned (if (listContains? flags "--regrade") (gc/removeDir! work) true))]
              done))))))
