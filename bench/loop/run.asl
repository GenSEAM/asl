(module aslBench/loop/run
  :x [main]
  :i [(aslBench/loop/core :a lc)
      (aslBench/gen/core :a gc)
      (asl-json/json :a j)
      (aslGateway/server :a gs)
      (aslGateway/dispatch :a gd)
      (aslGateway/upstream :a gu)
      (aslAgent/providers :a pv)])

; (:m :ref LOOPBENCH :do "entry points of the whole-loop bench: verify (every task red on its seeded state and green after its reference edits, no model call), pilot (tool loop over plain chat completions through the in-process gateway link, hard spend cap), report (per-arm table from the trial rows)")

fn flagValue args: (List String) flag: String -> (Option String)
  (match (listIndexOf args flag)
    ((none) (none))
    ((some i) (listGet args (+ i 1))))

fn csv text: String -> (List String)
  (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map stringTrim (stringSplit text ",")))

fn intFlag args: (List String) flag: String dflt: Int64 -> Int64
  (match (flagValue args flag)
    ((none) dflt)
    ((some t) (optionOr (stringToInt64 t) dflt)))

fn ! rootOf args: (List String) -> String
  (optionOr (flagValue args "--root") (resultOr (realPath ".") "."))

fn ! workOf args: (List String) -> String
  (let [(d (optionOr (flagValue args "--work") (str (optionOr (envGet "TMPDIR") "/tmp") "/aslLoopBench-" (stringFromInt64 (nowNs)))))
        (made (dirCreate d))]
    (resultOr (realPath d) d))

fn ! cfgOf args: (List String) capMicro: Int64 -> lc/Cfg
  (let [(root (rootOf args))]
    (lc/Cfg :root root :aslBin (str root "/bin/asl") :work (workOf args) :out (optionOr (flagValue args "--out") "")
            :maxTurns (intFlag args "--maxTurns" 16) :maxTokens (intFlag args "--maxTokens" 3000)
            :trialTokens (intFlag args "--trialTokens" 150000) :resultClip (intFlag args "--resultClip" 6000)
            :priceIn (optionOr (gc/usdToMicro (optionOr (flagValue args "--priceIn") "0.15")) 150000)
            :priceOut (optionOr (gc/usdToMicro (optionOr (flagValue args "--priceOut") "0.60")) 600000)
            :capPico (* capMicro 1000000) :loadMax (intFlag args "--loadMax" 24) :loadWaitS (intFlag args "--loadWaitS" 900)))

fn withOut cfg: lc/Cfg out: String -> lc/Cfg
  (with cfg :out out)

fn ! pickTasks root: String args: (List String) -> (Result (List lc/LoopTask) String)
  (match (lc/loadTasks root)
    ((err e) (err e))
    ((ok all)
      (let [(want (csv (optionOr (flagValue args "--tasks") "")))
            (picked (if (listEmpty? want) all (filter (fn [(t lc/LoopTask)] -> Bool (listContains? want t.id)) all)))]
        (if (or (listEmpty? picked) (and (not (listEmpty? want)) (!= (listLength picked) (listLength want))))
          (err "no task selected or an unknown task id in --tasks")
          (ok picked)))))

fn ! verify! args: (List String) -> (Result Int64 String)
  (let [(cfg (cfgOf args 0))
        (langs (csv (optionOr (flagValue args "--langs") "asl,py")))]
    (match (pickTasks cfg.root args)
      ((err e) (err e))
      ((ok tasks)
        (let [(rows (listFlatMap (fn [(t lc/LoopTask)] -> (List Bool)
                                   (map (fn [(lang String)] -> Bool
                                          (let [(r (lc/verifyTask! cfg t lang))]
                                            (do (println (str "(:verify :task " (gc/asnQuote t.id) " :lang " (gc/asnQuote lang) " :ok " (if (pairFirst r) "true" "false")
                                                              " :note " (gc/asnQuote (pairSecond r)) ")"))
                                                (pairFirst r))))
                                        langs))
                                 tasks))
              (bad (listLength (filter (fn [(b Bool)] -> Bool (not b)) rows)))
              (cleaned (if (listContains? args "--keep") false (lc/removeWork! cfg.work)))]
          (do (println (str "(:verified :tasks " (stringFromInt64 (listLength tasks)) " :checks " (stringFromInt64 (listLength rows)) " :failed " (stringFromInt64 bad) ")"))
              (if (= bad 0) (ok 0) (err (str (stringFromInt64 bad) " task halves are not red before and green after"))))))))

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

fn transient? e: String -> Bool
  (or (stringContains? e "http 429") (stringContains? e "http 503") (stringContains? e "http 504") (stringContains? e "cooldown") (stringContains? e "link: "))

fn ! liveOnce! l: gs/GatewayLoop r: gc/Req -> (Pair gs/GatewayLoop gc/Reply)
  (let [(msgs (listAppend (list (message "system" r.system))
                          (map (fn [(p (Pair String String))] -> j/Json (message (pairFirst p) (pairSecond p))) r.messages)))
        (body (pv/pyJsonDumps (j/jobj (list (pair "model" (j/jstr r.model)) (pair "intent" (j/jstr "code")) (pair "messages" (j/jarr msgs))
                                            (pair "max_tokens" (j/jint r.maxTokens)) (pair "temperature" (j/jfloat 0.2))))))
        (headers (list (pair "Content-Type" "application/json") (pair "Accept" "application/json") (pair "X-ASL-Consumer" "benchLoop")
                       (pair "Content-Length" (stringFromInt64 (bytesLength (stringToBytes body))))))
        (sent (gs/linkSend! l "POST" "/v1/chat/completions" headers body 300000))]
    (pair (pairFirst sent)
          (match (pairSecond sent)
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

fn ! liveRetry! l: gs/GatewayLoop r: gc/Req tries: Int64 -> (Pair gs/GatewayLoop gc/Reply)
  (let [(res (liveOnce! l r))
        (rep (pairSecond res))]
    (cond
      ((stringContains? rep.error "ERR_EMPTY_LENGTH")
        (pair (pairFirst res) (gc/Reply :text "" :tokIn 1 :tokOut r.maxTokens :served "truncatedAtMaxTokens" :error "")))
      ((and (> tries 1) (transient? rep.error))
        (do (sleepMs 20000) (liveRetry! (pairFirst res) r (- tries 1))))
      (else res)))

fn ! liveCall! l: gs/GatewayLoop r: gc/Req -> (Pair gs/GatewayLoop gc/Reply)
  (liveRetry! l r 5)

fn planTrials models: (List String) arms: (List String) tasks: (List lc/LoopTask) reps: Int64 -> (List lc/Trial)
  (listFlatMap (fn [(m String)] -> (List lc/Trial)
    (listFlatMap (fn [(t lc/LoopTask)] -> (List lc/Trial)
      (listFlatMap (fn [(a String)] -> (List lc/Trial)
        (map (fn [(r Int64)] -> lc/Trial (lc/Trial :arm a :task t :model m :rep r)) (range 1 (+ reps 1))))
        arms))
      tasks))
    models)

fn priorSpend existing: String -> Int64
  (match (gc/readForms existing)
    ((err _) 0)
    ((ok forms) (listSum (map (fn [(f gc/Sx)] -> Int64 (if (= (gc/headOf f) ":trial") (gc/kwInt (gc/sxItems f) ":costPico") 0)) forms))))

fn ! pilot! args: (List String) -> (Result Int64 String)
  (let [(models (csv (optionOr (flagValue args "--model") "")))
        (arms (csv (optionOr (flagValue args "--arms") "py,aslA,aslB")))
        (reps (intFlag args "--n" 1))
        (capText (optionOr (flagValue args "--maxUsd") ""))]
    (cond
      ((listEmpty? models) (err "pilot needs --model ALIAS[,ALIAS]"))
      ((not (listAll? lc/armKnown? arms)) (err (str "unknown arm in --arms; arms are " (stringJoin (lc/allArms) ","))))
      ((stringEmpty? capText) (err "pilot needs --maxUsd N: the spend cap is mandatory"))
      (else
        (match (gc/usdToMicro capText)
          ((none) (err "--maxUsd is not a non-negative decimal number"))
          ((some capMicro)
            (let [(cfg0 (cfgOf args capMicro))
                  (cfg (if (stringEmpty? cfg0.out)
                         (withOut cfg0 (str cfg0.root "/asl/bench/loop/results/" (gc/dateOf (nowNs)) "/trials.asn"))
                         cfg0))]
              (match (pickTasks cfg.root args)
                ((err e) (err e))
                ((ok tasks)
                  (let [(existing (resultOr (fileReadString cfg.out) ""))
                        (trials (planTrials models arms tasks reps))
                        (made (dirCreate (gc/slice cfg.out 0 (- (stringLength cfg.out) (stringLength (optionOr (listLast (stringSplit cfg.out "/")) ""))))))
                        (wrote (if (stringEmpty? existing)
                                 (fileAppend cfg.out (str (lc/headerRow cfg.root "pilot" models arms tasks reps cfg (gc/dateOf (nowNs))
                                                                        (optionOr (flagValue args "--note") "")) "\n"))
                                 (ok ())))]
                    (match wrote
                      ((err e) (err e))
                      ((ok _)
                        (match (gs/linkOpen! (gu/envMapFromList (envList)) (optionOr (envGet "HOME") "") cfg.root (gd/builtinFamilies))
                          ((err e) (err (str "gateway link: " e)))
                          ((ok l)
                            (let [(rs (pairSecond (lc/runAll! cfg trials existing (priorSpend existing) liveCall! l)))]
                              (do (println (str "(:run :status " (if (stringEmpty? rs.stopped) ":done" ":stopped") " :reason " (gc/asnQuote rs.stopped)
                                                " :planned " (stringFromInt64 (listLength trials)) " :ran " (stringFromInt64 rs.done)
                                                " :resumed " (stringFromInt64 rs.skipped) " :spentUsd " (gc/asnQuote (gc/usdText rs.spent))
                                                " :capUsd " (gc/asnQuote (gc/usdText cfg.capPico)) " :out " (gc/asnQuote cfg.out) " :work " (gc/asnQuote cfg.work) ")"))
                                  (if (stringEmpty? rs.stopped) (ok 0) (err (str "run stopped: " rs.stopped))))))))))))))))))

fn rowsOf text: String -> (List (List gc/Sx))
  (match (gc/readForms text)
    ((err _) (list))
    ((ok forms) (map gc/sxItems (filter (fn [(f gc/Sx)] -> Bool (= (gc/headOf f) ":trial")) forms))))

fn armLine rows: (List (List gc/Sx)) arm: String -> String
  (let [(mine (filter (fn [(r (List gc/Sx))] -> Bool (= (gc/kwText r ":arm") arm)) rows))
        (n (listLength mine))
        (solved (filter (fn [(r (List gc/Sx))] -> Bool (gc/kwBool r ":solved")) mine))
        (sumOf (fn [(k String) (rs (List (List gc/Sx)))] -> Int64 (listSum (map (fn [(r (List gc/Sx))] -> Int64 (gc/kwInt r k)) rs))))
        (tokAll (+ (sumOf ":tokInSum" mine) (sumOf ":tokOutSum" mine)))
        (tokSolved (+ (sumOf ":tokInSum" solved) (sumOf ":tokOutSum" solved)))
        (k (listLength solved))]
    (str "(:arm " (gc/asnQuote arm) " :trials " (stringFromInt64 n) " :solved " (stringFromInt64 k)
         " :tokensAll " (stringFromInt64 tokAll)
         " :tokensPerSolved " (stringFromInt64 (if (> k 0) (/ tokAll k) 0))
         " :tokensOfSolvedMean " (stringFromInt64 (if (> k 0) (/ tokSolved k) 0))
         " :outTokens " (stringFromInt64 (sumOf ":tokOutSum" mine))
         " :turnsMean10 " (stringFromInt64 (if (> n 0) (/ (* 10 (sumOf ":turns" mine)) n) 0))
         " :filesRead " (stringFromInt64 (sumOf ":filesRead" mine)) " :bytesRead " (stringFromInt64 (sumOf ":bytesRead" mine))
         " :wallSec " (stringFromInt64 (/ (sumOf ":wallMs" mine) 1000))
         " :costUsd " (gc/asnQuote (gc/usdText (sumOf ":costPico" mine))) ")"))

fn ! report! args: (List String) -> (Result Int64 String)
  (match (fileReadString (optionOr (flagValue args "--in") ""))
    ((err e) (err (str "report needs --in FILE: " e)))
    ((ok text)
      (let [(rows (rowsOf text))
            (arms (filter (fn [(a String)] -> Bool (listAny? (fn [(r (List gc/Sx))] -> Bool (= (gc/kwText r ":arm") a)) rows)) (lc/allArms)))]
        (do (println (str "(:report :trials " (stringFromInt64 (listLength rows)) " :note \"tokensPerSolved is all tokens of the arm over its solved trials; turnsMean10 is ten times the mean turn count\")"))
            (println (stringJoin (map (fn [(a String)] -> String (armLine rows a)) arms) "\n"))
            (ok 0)))))

fn usage -> String
  "usage: asl run asl/bench/loop/run.asl verify [--tasks IDS] [--langs asl,py] | pilot --model ALIAS --maxUsd N [--arms py,aslA,aslB,pyB] [--tasks IDS] [--n 1] [--out FILE] [--priceIn USD --priceOut USD] | report --in FILE"

fn ! main args: (List String) -> (Result Int64 String)
  (match (listHead args)
    ((none) (do (println (usage)) (ok 2)))
    ((some cmd)
      (cond
        ((= cmd "verify") (verify! args))
        ((= cmd "pilot") (pilot! args))
        ((= cmd "report") (report! args))
        (else (do (println (usage)) (ok 2))))))
