(module aslBench/gen/run
  :x [main]
  :i [(aslBench/gen/core :a gc)
      (aslBench/gen/score :a sc)
      (asl-json/json :a j)
      (aslGateway/server :a gs)
      (aslGateway/dispatch :a gd)
      (aslGateway/upstream :a gu)
      (aslAgent/providers :a pv)])

; (:m :ref FABLE-LANG-01 :do "entry points of the generation-baseline bench: verify (references in every arm, no model call), dry (fake model), pilot (plain chat completions through the in-process gateway link, hard budget stop), report, cards, prompt")

(schema Plan
  (:f mode String)
  (:f fake Bool)
  (:f models (List String))
  (:f arms (List String))
  (:f tasks (List gc/Task))
  (:f reps Int64)
  (:f seed Int64)
  (:f cfg gc/Config)
  (:f cards (List gc/Card))
  (:f trials (List gc/Trial))
  (:f existing String)
  (:f spentBefore Int64)
  (:f priceNote String))

fn flagValue args: (List String) flag: String -> (Option String)
  (match (listIndexOf args flag)
    ((some i) (listGet args (+ i 1)))
    ((none) (none)))

fn hasFlag args: (List String) flag: String -> Bool
  (listContains? args flag)

fn csv text: String -> (List String)
  (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map stringTrim (stringSplit text ",")))

fn intFlag args: (List String) flag: String dflt: Int64 -> Int64
  (match (flagValue args flag)
    ((some s) (optionOr (stringToInt64 s) dflt))
    ((none) dflt))

fn parentDir path: String -> String
  (let [(parts (stringSplit path "/"))]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! rootOf args: (List String) -> String
  (let [(given (optionOr (flagValue args "--root") (optionOr (envGet "ASL_CLI_ROOT") ".")))]
    (resultOr (realPath given) given))

fn ! workOf args: (List String) -> String
  (let [(given (optionOr (flagValue args "--work") (str (optionOr (envGet "TMPDIR") "/tmp") "/aslBenchGen-" (stringFromInt64 (nowNs)))))
        (made (dirCreate given))]
    (resultOr (realPath given) given))

fn dryBehaviours -> (List String)
  (list "good" "fixed" "never" "noBlock" "parse" "heal" "execute" "correct")

fn dryPlan tasks: (List gc/Task) -> (List (Pair String String))
  (map (fn [(i Int64)] -> (Pair String String)
         (pair (match (listGet tasks i) ((some t) t.id) ((none) ""))
               (optionOr (listGet (dryBehaviours) (mod i (listLength (dryBehaviours)))) "good")))
       (range 0 (listLength tasks)))

fn shardOf args: (List String) -> (Pair Int64 Int64)
  (let [(parts (stringSplit (optionOr (flagValue args "--shard") "0/1") "/"))
        (i (optionOr (stringToInt64 (optionOr (listHead parts) "0")) 0))
        (n (optionOr (stringToInt64 (optionOr (listGet parts 1) "1")) 1))]
    (if (or (< n 1) (or (< i 0) (>= i n))) (pair 0 1) (pair i n)))

fn ! plan! args: (List String) mode: String -> (Result Plan String)
  (let [(root (rootOf args))
        (fake (or (= mode "dry") (hasFlag args "--dryRun")))
        (models (csv (optionOr (flagValue args "--model") (if (= mode "dry") "fake" ""))))
        (arms (csv (optionOr (flagValue args "--arms") (stringJoin (gc/allArms) ","))))
        (taskFilter (csv (optionOr (flagValue args "--tasks") "")))
        (reps (intFlag args "--n" (if (= mode "dry") 1 5)))
        (seed (intFlag args "--seed" 1))
        (capText (optionOr (flagValue args "--maxUsd") (optionOr (flagValue args "--cap-usd") (if (= mode "dry") "1" ""))))
        (shard (shardOf args))
        (priced (and (some? (flagValue args "--priceIn")) (some? (flagValue args "--priceOut"))))]
    (cond
      ((listEmpty? models) (err "pilot needs --model ALIAS[,ALIAS]"))
      ((not (listAll? gc/armKnown? arms)) (err (str "unknown arm in --arms; arms are " (stringJoin (gc/allArms) ","))))
      ((stringEmpty? capText) (err "pilot needs --maxUsd N (alias --cap-usd): the budget stop is mandatory"))
      ((< reps 1) (err "--n must be at least 1"))
      (else
        (match (gc/usdToMicro capText)
          ((none) (err "--maxUsd is not a non-negative decimal number"))
          ((some capMicro)
            (match (gc/usdToMicro (optionOr (flagValue args "--priceIn") "0.15"))
              ((none) (err "--priceIn is not a non-negative decimal number (USD per million input tokens)"))
              ((some priceIn)
                (match (gc/usdToMicro (optionOr (flagValue args "--priceOut") "0.60"))
                  ((none) (err "--priceOut is not a non-negative decimal number (USD per million output tokens)"))
                  ((some priceOut)
                    (match (gc/loadTasks root)
                      ((err e) (err e))
                      ((ok allTasks)
                        (match (gc/loadCards root)
                          ((err e) (err e))
                          ((ok cards)
                            (let [(picked (if (listEmpty? taskFilter)
                                            (if (= mode "dry") (listTake allTasks 8) allTasks)
                                            (filter (fn [(t gc/Task)] -> Bool (listContains? taskFilter t.id)) allTasks)))
                                  (work (workOf args))
                                  (out (optionOr (flagValue args "--out")
                                                 (if fake
                                                   (str work "/trials.asn")
                                                   (str root "/asl/bench/gen/results/" (gc/dateOf (nowNs)) "/trials"
                                                        (if (= (pairSecond shard) 1) "" (str ".shard" (stringFromInt64 (pairFirst shard)))) ".asn"))))
                                  (cfg (gc/Config :root root :aslBin (str root "/bin/asl") :work work :out out :repairs (intFlag args "--repairs" 3)
                                                  :maxTokens (intFlag args "--maxTokens" 1200) :priceIn priceIn :priceOut priceOut
                                                  :capPico (* capMicro 1000000) :checkFirst true))
                                  (existing (resultOr (fileReadString out) ""))
                                  (trials (filter (fn [(tr gc/Trial)] -> Bool (= (mod tr.idx (pairSecond shard)) (pairFirst shard)))
                                                  (gc/planTrials models arms picked reps seed)))]
                              (cond
                                ((!= (listLength picked) (if (listEmpty? taskFilter) (listLength picked) (listLength taskFilter))) (err "unknown task id in --tasks"))
                                ((listEmpty? picked) (err "no tasks selected"))
                                (else
                                  (match (gc/priorSpend existing)
                                    ((err e) (err e))
                                    ((ok spent)
                                      (ok (Plan :mode mode :fake fake :models models :arms arms :tasks picked :reps reps :seed seed :cfg cfg :cards cards
                                                :trials trials :existing existing :spentBefore spent
                                                :priceNote (if priced "prices from --priceIn and --priceOut" "default prices 0.15 and 0.60 USD per million tokens, the assumption of asl/bench/harness/config.example.asn")))))))))))))))))))))

fn jpath v: j/Json keys: (List String) -> j/Json
  (match (listHead keys)
    ((none) v)
    ((some k)
      (match v
        ((j/jarr xs)
          (match (listHead xs)
            ((some x) (jpath x (listDrop keys 1)))
            ((none) (j/jnull))))
        (_
          (match (j/jsonGet v k)
            ((some x) (jpath x (listDrop keys 1)))
            ((none) (j/jnull)))))))

fn jtext v: j/Json -> String
  (match v
    ((j/jstr s) s)
    (_ ""))

fn jcount v: j/Json -> Int64
  (match v
    ((j/jint i) i)
    (_ 0))

fn message role: String content: String -> j/Json
  (j/jobj (list (pair "role" (j/jstr role)) (pair "content" (j/jstr content))))

fn failed text: String -> gc/Reply
  (gc/Reply :text "" :tokIn 0 :tokOut 0 :served "" :error text)

fn replyOf text: String -> gc/Reply
  (match (j/jsonParse text)
    ((err e) (failed (str "the gateway reply is not JSON: " (gc/clip e 200))))
    ((ok js)
      (let [(tokIn (jcount (jpath js (list "usage" "prompt_tokens"))))
            (tokOut (jcount (jpath js (list "usage" "completion_tokens"))))]
        (if (<= (+ tokIn tokOut) 0)
          (failed "the gateway reply carries no usage counts, so the budget cannot be tracked")
          (gc/Reply :text (jtext (jpath js (list "choices" "0" "message" "content"))) :tokIn tokIn :tokOut tokOut
                    :served (jtext (jpath js (list "model"))) :error "")))))

fn ! liveCall! l: gs/GatewayLoop r: gc/Req -> (Pair gs/GatewayLoop gc/Reply)
  (let [(msgs (listAppend (list (message "system" r.system))
                          (map (fn [(p (Pair String String))] -> j/Json (message (pairFirst p) (pairSecond p))) r.messages)))
        (body (pv/pyJsonDumps (j/jobj (list (pair "model" (j/jstr r.model)) (pair "intent" (j/jstr "code")) (pair "messages" (j/jarr msgs))
                                            (pair "max_tokens" (j/jint r.maxTokens)) (pair "temperature" (j/jfloat 0.2))))))
        (headers (list (pair "Content-Type" "application/json") (pair "Accept" "application/json") (pair "X-ASL-Consumer" "benchGen")
                       (pair "Content-Length" (stringFromInt64 (bytesLength (stringToBytes body))))))
        (out (gs/linkSend! l "POST" "/v1/chat/completions" headers body 300000))]
    (pair (pairFirst out)
          (match (pairSecond out)
            ((err e) (failed (str "link: " (gc/clip e 300))))
            ((ok raw)
              (match (pv/parseCurlResponse raw)
                ((err e) (failed (str "unreadable response: " (gc/clip e 200))))
                ((ok resp)
                  (let [(code (pairFirst (pairFirst resp)))
                        (text (pairSecond (pairSecond resp)))]
                    (if (or (< code 200) (>= code 300))
                      (failed (str "http " (stringFromInt64 code) ": " (gc/clip text 300)))
                      (replyOf text)))))))))

fn ! versions! cfg: gc/Config -> (List (Pair String String))
  (list (pair "python3" (gc/toolVersion! (list "python3" "--version")))
        (pair "node" (gc/toolVersion! (list "node" "--version")))
        (pair "tsc" (gc/toolVersion! (list "tsc" "--version")))
        (pair "asl" (gc/toolVersion! (list cfg.aslBin "version"))))

fn versionOf versions: (List (Pair String String)) name: String -> String
  (match (listFind (fn [(p (Pair String String))] -> Bool (= (pairFirst p) name)) versions)
    ((some p) (pairSecond p))
    ((none) "absent"))

fn missingTool arms: (List String) versions: (List (Pair String String)) -> String
  (cond
    ((and (listContains? arms "py") (= (versionOf versions "python3") "absent")) "python3")
    ((and (listContains? arms "ts") (= (versionOf versions "tsc") "absent")) "tsc")
    ((and (listContains? arms "ts") (= (versionOf versions "node") "absent")) "node")
    (else ""))

fn ! finish! p: Plan rs: gc/RunState -> (Result Int64 String)
  (do
    (println (str "(:run :status " (if (stringEmpty? rs.stopped) ":done" ":stopped") " :reason " (gc/asnQuote rs.stopped)
                  " :planned " (stringFromInt64 (listLength p.trials)) " :ran " (stringFromInt64 rs.done) " :resumed " (stringFromInt64 rs.skipped)
                  " :spentUsd " (gc/asnQuote (gc/usdText rs.spent)) " :capUsd " (gc/asnQuote (gc/usdText p.cfg.capPico))
                  " :out " (gc/asnQuote p.cfg.out) " :work " (gc/asnQuote p.cfg.work) ")"))
    (if (stringEmpty? rs.stopped) (ok 0) (err (str "run stopped: " rs.stopped))))

fn ! experiment! args: (List String) mode: String -> (Result Int64 String)
  (match (plan! args mode)
    ((err e) (err e))
    ((ok p)
      (let [(versions (versions! p.cfg))
            (sig (gc/planSig p.models p.arms p.tasks p.reps p.cfg.repairs p.cfg.maxTokens p.seed))
            (lacking (missingTool p.arms versions))]
        (cond
          ((not (stringEmpty? lacking)) (err (str "arm blocked: " lacking " is not on PATH")))
          ((and (not (stringEmpty? p.existing)) (not (stringContains? p.existing (str ":planSig " (gc/asnQuote sig)))))
            (err (str p.cfg.out " holds rows of a different plan; pass another --out")))
          (else
            (let [(made (dirCreate (parentDir p.cfg.out)))
                  (wrote (fileAppend p.cfg.out
                           (if (stringEmpty? p.existing)
                             (str (gc/headerRow (if p.fake (str p.mode " fake model") p.mode) p.models p.arms p.tasks p.reps p.seed p.cfg p.cards versions
                                                (gc/dateOf (nowNs)) p.priceNote) "\n")
                             "")))]
              (match wrote
                ((err e) (err e))
                ((ok _)
                  (if p.fake
                    (finish! p (pairSecond (gc/runAll! p.cfg p.cards p.trials p.existing p.spentBefore (gc/fakeCaller p.cfg.root (dryPlan p.tasks)) 0)))
                    (match (gs/linkOpen! (gu/envMapFromList (envList)) (optionOr (envGet "HOME") "") p.cfg.root (gd/builtinFamilies))
                      ((err e) (err (str "gateway link: " e)))
                      ((ok l) (finish! p (pairSecond (gc/runAll! p.cfg p.cards p.trials p.existing p.spentBefore liveCall! l))))))))))))))

fn ! verifyOne! cfg: gc/Config t: gc/Task arm: String -> (Option String)
  (let [(lang (gc/armLang arm))
        (dir (str cfg.work "/v-" arm "-" t.id))
        (made (dirCreate dir))
        (conf (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"aslBenchGenSandbox\")"))]
    (match (fileReadString (str cfg.root "/asl/bench/gen/ref/" t.id "." lang))
      ((err e) (some (str "no reference: " e)))
      ((ok refText)
        (let [(code (gc/toArm arm refText))]
          (cond
            ((and (= arm "aslParen") (stringContains? code "[")) (some "the paren spelling still holds a square bracket"))
            ((and (= arm "aslWrapFn") (listAny? (fn [(l String)] -> Bool (stringStartsWith? l "fn ")) (stringLines code))) (some "the wrapped spelling still holds a bare fn line"))
            (else
              (let [(g (pairFirst (gc/gradeCode! cfg dir arm t (listAppend t.examples t.cases) code)))]
                (if (= g.stage "ok") (none) (some (str "stage " g.stage ": " (gc/clip g.output 600)))))))))))

fn familyCount tasks: (List gc/Task) family: String -> Int64
  (listCount (fn [(t gc/Task)] -> Bool (= t.family family)) tasks)

fn ! cardDrift! root: String cards: (List gc/Card) -> (List String)
  (match (fileReadString (str root "/asl/llms.txt"))
    ((err e) (list (str "asl/llms.txt: " e)))
    ((ok llms)
      (listFlatMap (fn [(arm String)] -> (List String)
                     (match (gc/cardFor arm llms)
                       ((err e) (list (str "card " arm ": " e)))
                       ((ok text) (if (= text (gc/cardOf cards arm).text) (list) (list (str "card " arm " differs from its derivation from asl/llms.txt; rerun cards --write and recount tokens"))))))
                   (gc/allArms))))

fn ! verify! args: (List String) -> (Result Int64 String)
  (let [(root (rootOf args))
        (arms (csv (optionOr (flagValue args "--arms") (stringJoin (gc/allArms) ","))))
        (taskFilter (csv (optionOr (flagValue args "--tasks") "")))]
    (match (gc/loadTasks root)
      ((err e) (err e))
      ((ok allTasks)
        (match (gc/loadCards root)
          ((err e) (err e))
          ((ok cards)
            (let [(work (workOf args))
                  (cfg (gc/Config :root root :aslBin (str root "/bin/asl") :work work :out "" :repairs 0 :maxTokens 0 :priceIn 0 :priceOut 0 :capPico 0 :checkFirst false))
                  (tasks (if (listEmpty? taskFilter) allTasks (filter (fn [(t gc/Task)] -> Bool (listContains? taskFilter t.id)) allTasks)))
                  (shape (listAppend
                           (if (= (listLength allTasks) 30) (list) (list (str "expected 30 tasks, found " (stringFromInt64 (listLength allTasks)))))
                           (listAppend
                             (listFlatMap (fn [(f String)] -> (List String)
                                            (if (= (familyCount allTasks f) 10) (list) (list (str "family " f " holds " (stringFromInt64 (familyCount allTasks f)) " tasks, expected 10"))))
                                          (list "A" "B" "C"))
                             (cardDrift! root cards))))
                  (fails (listFlatMap (fn [(t gc/Task)] -> (List String)
                                        (listFlatMap (fn [(arm String)] -> (List String)
                                                       (match (verifyOne! cfg t arm)
                                                         ((none) (do (println (str "(:verify :task " (gc/asnQuote t.id) " :arm " (gc/asnQuote arm) " :status :passed)")) (list)))
                                                         ((some why) (do (println (str "(:verify :task " (gc/asnQuote t.id) " :arm " (gc/asnQuote arm) " :status :failed :why " (gc/asnQuote why) ")")) (list (str t.id "/" arm))))))
                                                     arms))
                                      tasks))
                  (bad (listAppend shape fails))]
              (do
                (println (str "(:verify :status " (if (listEmpty? bad) ":passed" ":failed") " :tasks " (stringFromInt64 (listLength tasks)) " :arms " (stringFromInt64 (listLength arms))
                              " :checked " (stringFromInt64 (* (listLength tasks) (listLength arms))) " :failed " (stringFromInt64 (listLength fails))
                              " :defects (" (stringJoin (map gc/asnQuote bad) " ") "))"))
                (if (listEmpty? bad)
                  (do (gc/removeDir! work) (ok 0))
                  (err (str "verify failed; work dir kept at " work))))))))))

fn ! cards! args: (List String) -> (Result Int64 String)
  (let [(root (rootOf args))]
    (match (fileReadString (str root "/asl/llms.txt"))
      ((err e) (err e))
      ((ok llms)
        (fold (fn [(acc (Result Int64 String)) (arm String)] -> (Result Int64 String)
                (match acc
                  ((err e) (err e))
                  ((ok n)
                    (match (gc/cardFor arm llms)
                      ((err e) (err e))
                      ((ok text)
                        (let [(path (str root "/asl/bench/gen/cards/" arm ".txt"))
                              (wrote (if (hasFlag args "--write") (fileWrite path text) (fileAppend path "")))
                              (onDisk (resultOr (fileReadString path) ""))]
                          (do
                            (println (str "(:card :arm " (gc/asnQuote arm) " :file " (gc/asnQuote (str "cards/" arm ".txt")) " :sha256 " (gc/asnQuote (gc/sha256Of text))
                                          " :bytes " (stringFromInt64 (stringLength text)) " :matchesFile " (if (= onDisk text) "true" "false") ")"))
                            (ok (+ n 1)))))))))
              (ok 0)
              (gc/allArms)))))

fn ! prompt! args: (List String) -> (Result Int64 String)
  (let [(root (rootOf args))
        (arm (optionOr (flagValue args "--arm") "asl"))]
    (match (gc/loadTask root (optionOr (flagValue args "--task") "gcd"))
      ((err e) (err e))
      ((ok t)
        (match (gc/loadCards root)
          ((err e) (err e))
          ((ok cards)
            (do
              (println (str "--- system (" arm ") ---\n" (gc/cardOf cards arm).text "\n--- user ---\n" (gc/userPrompt arm t)))
              (ok 0)))))))

fn usage -> String
  (str "usage: asl run asl/bench/gen/run.asl verify [--arms A,B] [--tasks T,U]\n"
       "       asl run asl/bench/gen/run.asl dry [--arms A,B] [--tasks T,U] [--n N] [--repairs K] [--maxUsd N]\n"
       "       asl run asl/bench/gen/run.asl pilot --model ALIAS[,ALIAS] --maxUsd N [--priceIn P --priceOut P] [--seed S] [--n 5] [--repairs 3] [--arms ..] [--tasks ..] [--shard I/N] [--out FILE] [--dryRun]\n"
       "       asl run asl/bench/gen/run.asl report TRIALS.asn [MORE.asn ...]\n"
       "       asl run asl/bench/gen/run.asl cards [--write]\n"
       "       asl run asl/bench/gen/run.asl prompt --arm ARM --task ID")

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))]
    (cond
      ((= cmd "verify") (verify! args))
      ((= cmd "dry")
        (match (experiment! args "dry")
          ((err e) (err e))
          ((ok _) (ok 0))))
      ((= cmd "pilot") (experiment! args "pilot"))
      ((= cmd "report") (sc/report! (filter (fn [(a String)] -> Bool (not (stringStartsWith? a "--"))) (listDrop args 1))))
      ((= cmd "cards") (cards! args))
      ((= cmd "prompt") (prompt! args))
      (else (err (usage)))))
