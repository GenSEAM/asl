(module aslBench/gen/cardLab/readProbe
  :x [main]
  :i [(aslBench/gen/core :a gc)
      (asl-json/json :a j)
      (aslGateway/server :a gs)
      (aslGateway/dispatch :a gd)
      (aslGateway/upstream :a gu)
      (aslAgent/providers :a pv)])

; (:m :ref CARD-LAB :do "reading probe over the 30 reference programs in ASL, Python and TypeScript: gen builds the items (two hidden-case calls, one single-token mutant of the same class in all three languages, each proven to fail a hidden case), run asks a model to predict the two results and to locate and fix the mutant line, the fix being graded by the hidden cases")

(schema Item
  (:f task String)
  (:f lang String)
  (:f program String)
  (:f calls (List String))
  (:f wants (List String))
  (:f bug String)
  (:f line Int64)
  (:f mutant String))

(schema Stat
  (:f arm String)
  (:f probe String)
  (:f items Int64)
  (:f a Int64)
  (:f b Int64)
  (:f errs Int64)
  (:f tokIn Int64)
  (:f tokOut Int64))

(schema St
  (:f link gs/GatewayLoop)
  (:f spent Int64)
  (:f stopped String)
  (:f stats (List Stat)))

fn flagValue args: (List String) flag: String -> (Option String)
  (match (listIndexOf args flag)
    ((some i) (listGet args (+ i 1)))
    ((none) (none)))

fn intFlag args: (List String) flag: String dflt: Int64 -> Int64
  (match (flagValue args flag)
    ((some s) (optionOr (stringToInt64 s) dflt))
    ((none) dflt))

fn ! rootOf args: (List String) -> String
  (let [(given (optionOr (flagValue args "--root") (optionOr (envGet "ASL_CLI_ROOT") ".")))]
    (resultOr (realPath given) given))

fn ! workOf args: (List String) -> String
  (let [(given (str (optionOr (envGet "TMPDIR") "/tmp") "/aslBenchGen-read-" (stringFromInt64 (nowNs))))
        (made (dirCreate given))]
    (resultOr (realPath given) given))

fn ! configOf args: (List String) root: String -> gc/Config
  (gc/Config :root root :aslBin (str root "/bin/asl") :work (workOf args)
             :out (optionOr (flagValue args "--out") (str root "/asl/bench/gen/cardLab/results/read.asn"))
             :repairs 0 :maxTokens (intFlag args "--maxTokens" 4000)
             :priceIn (optionOr (gc/usdToMicro (optionOr (flagValue args "--priceIn") "0.15")) 150000)
             :priceOut (optionOr (gc/usdToMicro (optionOr (flagValue args "--priceOut") "0.60")) 600000)
             :capPico (* (optionOr (gc/usdToMicro (optionOr (flagValue args "--maxUsd") "0")) 0) 1000000)
             :checkFirst true)

fn at xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")

fn langs -> (List String)
  (list "asl" "py" "ts")

fn classes -> (List (List String))
  (list (list "lt" "(< " "(<= " " < " " <= " " < " " <= ")
        (list "gt" "(> " "(>= " " > " " >= " " > " " >= ")
        (list "le" "(<= " "(< " " <= " " < " " <= " " < ")
        (list "ge" "(>= " "(> " " >= " " > " " >= " " > ")
        (list "eq" "(= " "(!= " " == " " != " " === " " !== ")
        (list "plus" "(+ " "(- " " + " " - " " + " " - ")
        (list "minus" "(- " "(+ " " - " " + " " - " " + ")
        (list "times" "(* " "(+ " " * " " + " " * " " + ")
        (list "and" "(and " "(or " " and " " or " " && " " || ")
        (list "or" "(or " "(and " " or " " and " " || " " && ")
        (list "zero" " 0" " 1" " 0" " 1" " 0" " 1")
        (list "one" " 1" " 2" " 1" " 2" " 1" " 2")
        (list "true" "true" "false" "True" "False" "true" "false"))

fn fromOf cls: (List String) lang: String -> String
  (at cls (cond ((= lang "asl") 1) ((= lang "py") 3) (else 5)))

fn toOf cls: (List String) lang: String -> String
  (at cls (cond ((= lang "asl") 2) ((= lang "py") 4) (else 6)))

fn replaceFirst text: String from: String to: String -> String
  (match (stringIndexOf text from)
    ((none) text)
    ((some i) (str (gc/slice text 0 i) to (gc/sliceFrom text (+ i (stringLength from))))))

fn lineOfFirst text: String from: String -> Int64
  (match (stringIndexOf text from)
    ((none) 0)
    ((some i) (listLength (stringSplit (gc/slice text 0 i) "\n"))))

fn ! sandbox! work: String name: String -> String
  (let [(dir (str work "/" name))
        (made (dirCreate dir))
        (conf (fileWrite (str dir "/.asl.config.asn") "(:aslConfig :workspace \"aslBenchGenSandbox\")"))]
    dir)

fn ! stageOf! cfg: gc/Config name: String lang: String t: gc/Task code: String -> String
  (let [(g (pairFirst (gc/gradeCode! cfg (sandbox! cfg.work name) lang t t.cases code)))]
    g.stage)

fn ! mutantFails! cfg: gc/Config t: gc/Task cls: (List String) lang: String text: String -> Bool
  (= (stageOf! cfg (str "m-" t.id "-" (at cls 0) "-" lang) lang t (replaceFirst text (fromOf cls lang) (toOf cls lang))) "correct")

fn ! classWorks! cfg: gc/Config t: gc/Task texts: (List String) cls: (List String) -> Bool
  (cond
    ((not (stringContains? (at texts 0) (fromOf cls "asl"))) false)
    ((not (stringContains? (at texts 1) (fromOf cls "py"))) false)
    ((not (stringContains? (at texts 2) (fromOf cls "ts"))) false)
    ((not (mutantFails! cfg t cls "asl" (at texts 0))) false)
    ((not (mutantFails! cfg t cls "py" (at texts 1))) false)
    (else (mutantFails! cfg t cls "ts" (at texts 2))))

fn ! pickClass! cfg: gc/Config t: gc/Task texts: (List String) todo: (List (List String)) -> (List String)
  (match (listHead todo)
    ((none) (list))
    ((some cls)
      (if (classWorks! cfg t texts cls)
        cls
        (pickClass! cfg t texts (listDrop todo 1)))))

fn callsOf lang: String t: gc/Task -> (List (Pair String String))
  (map (fn [(c gc/Case)] -> (Pair String String)
         (let [(parts (stringSplit (gc/exampleLine lang t c) " returns "))]
           (pair (at parts 0) (stringJoin (listDrop parts 1) " returns "))))
       (listTake (filter (fn [(c gc/Case)] -> Bool (!= (gc/headOf c.want) "fails")) t.cases) 2))

fn quoted xs: (List String) -> String
  (str "(" (stringJoin (map (fn [(s String)] -> String (gc/asnQuote s)) xs) " ") ")")

fn itemRow t: gc/Task lang: String text: String cls: (List String) -> String
  (let [(calls (callsOf lang t))
        (has (not (listEmpty? cls)))]
    (str "(:item :task " (gc/asnQuote t.id) " :lang " (gc/asnQuote lang)
         " :calls " (quoted (map (fn [(p (Pair String String))] -> String (pairFirst p)) calls))
         " :wants " (quoted (map (fn [(p (Pair String String))] -> String (pairSecond p)) calls))
         " :bug " (gc/asnQuote (at cls 0))
         " :line " (stringFromInt64 (if has (lineOfFirst text (fromOf cls lang)) 0))
         " :program " (gc/asnQuote text)
         " :mutant " (gc/asnQuote (if has (replaceFirst text (fromOf cls lang) (toOf cls lang)) ""))
         ")"))

fn ! genTask! cfg: gc/Config t: gc/Task -> (Result String String)
  (let [(texts (map (fn [(l String)] -> String (stringTrim (resultOr (fileReadString (str cfg.root "/asl/bench/gen/ref/" t.id "." l)) ""))) (langs)))]
    (if (listAny? (fn [(s String)] -> Bool (stringEmpty? s)) texts)
      (err (str t.id ": a reference program is missing in asl/bench/gen/ref"))
      (let [(cls (pickClass! cfg t texts (classes)))]
        (do
          (println (str "(:gen :task " (gc/asnQuote t.id) " :bug " (gc/asnQuote (at cls 0)) ")"))
          (ok (stringJoin (map (fn [(i Int64)] -> String (itemRow t (at (langs) i) (at texts i) cls)) (range 0 3)) "\n"))))))

fn ! gen! args: (List String) -> (Result Int64 String)
  (let [(root (rootOf args))
        (cfg (configOf args root))
        (out (optionOr (flagValue args "--items") (str root "/asl/bench/gen/cardLab/readItems.asn")))]
    (match (gc/loadTasks root)
      ((err e) (err e))
      ((ok tasks)
        (match (fold (fn [(acc (Result (List String) String)) (t gc/Task)] -> (Result (List String) String)
                       (match acc
                         ((err e) (err e))
                         ((ok rows)
                           (match (genTask! cfg t)
                             ((err e) (err e))
                             ((ok row) (ok (listAppend rows (list row))))))))
                     (ok (list))
                     tasks)
          ((err e) (err e))
          ((ok rows)
            (match (fileWrite out (str "(:readItems :id \"CARD-LAB\" :date " (gc/asnQuote (gc/dateOf (nowNs)))
                                       " :method \"asl run asl/bench/gen/cardLab/readProbe.asl gen: calls are the first two graded cases that do not fail; the mutant replaces the first occurrence of the first class of classes whose pattern occurs in all three references and whose three mutants all compile and fail a graded case\")\n"
                                       (stringJoin rows "\n") "\n"))
              ((err e) (err e))
              ((ok _)
                (do
                  (gc/removeDir! cfg.work)
                  (ok 0)))))))))

fn itemOf row: (List gc/Sx) -> Item
  (Item :task (gc/kwText row ":task") :lang (gc/kwText row ":lang") :program (gc/kwText row ":program")
        :calls (map (fn [(v gc/Sx)] -> String (gc/sxText v)) (gc/kwList row ":calls"))
        :wants (map (fn [(v gc/Sx)] -> String (gc/sxText v)) (gc/kwList row ":wants"))
        :bug (gc/kwText row ":bug") :line (gc/kwInt row ":line") :mutant (gc/kwText row ":mutant"))

fn ! loadItems path: String -> (Result (List Item) String)
  (match (fileReadString path)
    ((err e) (err e))
    ((ok text)
      (match (gc/readForms text)
        ((err e) (err (str path ": " e)))
        ((ok forms)
          (ok (map (fn [(f gc/Sx)] -> Item (itemOf (gc/sxItems f)))
                   (filter (fn [(f gc/Sx)] -> Bool (= (gc/headOf f) ":item")) forms)))))))

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

fn ! chatOnce! l: gs/GatewayLoop model: String system: String user: String maxTokens: Int64 -> (Pair gs/GatewayLoop gc/Reply)
  (let [(body (pv/pyJsonDumps (j/jobj (list (pair "model" (j/jstr model)) (pair "intent" (j/jstr "code"))
                                            (pair "messages" (j/jarr (list (message "system" system) (message "user" user))))
                                            (pair "max_tokens" (j/jint maxTokens)) (pair "temperature" (j/jfloat 0.2))))))
        (headers (list (pair "Content-Type" "application/json") (pair "Accept" "application/json") (pair "X-ASL-Consumer" "benchGenRead")
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

fn ! chat! l: gs/GatewayLoop model: String system: String user: String maxTokens: Int64 tries: Int64 -> (Pair gs/GatewayLoop gc/Reply)
  (let [(out (chatOnce! l model system user maxTokens))
        (rep (pairSecond out))]
    (cond
      ((stringContains? rep.error "ERR_EMPTY_LENGTH")
        (pair (pairFirst out) (gc/Reply :text "" :tokIn 1 :tokOut maxTokens :served "truncatedAtMaxTokens" :error "")))
      ((and (> tries 1) (transient? rep.error))
        (do (sleepMs 30000) (chat! (pairFirst out) model system user maxTokens (- tries 1))))
      (else out)))

fn stopAt st: St why: String -> St
  (St :link st.link :spent st.spent :stopped why :stats st.stats)

fn advance st: St l: gs/GatewayLoop cost: Int64 -> St
  (St :link l :spent (+ st.spent cost) :stopped st.stopped :stats st.stats)

fn addStat st: St s: Stat -> St
  (St :link st.link :spent st.spent :stopped st.stopped :stats (listAppend st.stats (list s)))

fn ! ask! cfg: gc/Config model: String st: St system: String user: String -> (Pair St gc/Reply)
  (if (or (not (stringEmpty? st.stopped)) (> (+ st.spent (gc/callCost cfg 1500 cfg.maxTokens)) cfg.capPico))
    (pair (stopAt st "the next call could pass --maxUsd") (failed "skipped"))
    (let [(out (chat! st.link model system user cfg.maxTokens 4))
          (rep (pairSecond out))]
      (pair (advance st (pairFirst out) (gc/callCost cfg rep.tokIn rep.tokOut)) rep)))

fn langOf arm: String -> String
  (cond
    ((= arm "py") "py")
    ((= arm "ts") "ts")
    (else "asl"))

fn langName lang: String -> String
  (cond
    ((= lang "py") "Python")
    ((= lang "ts") "TypeScript")
    (else "ASL"))

fn systemFor arm: String cards: (List gc/Card) cardArm: String -> String
  (cond
    ((= arm "aslNoCard") "The program is written in ASL.")
    ((= arm "aslCard") (gc/cardOf cards cardArm).text)
    (else (gc/cardOf cards arm).text))

fn predictPrompt it: Item t: gc/Task -> String
  (str "Program (" (langName it.lang) "):\n```\n" it.program "\n```\n\n"
       "Notation of a call and its result, from two visible examples:\n"
       (stringJoin (map (fn [(c gc/Case)] -> String (gc/exampleLine it.lang t c)) t.examples) "\n") "\n\n"
       "What do these two calls return?\n1. " (at it.calls 0) "\n2. " (at it.calls 1) "\n\n"
       "Reply with exactly two lines and nothing else, each value in the notation of the results above:\nA1: <value>\nA2: <value>\n")

fn numbered text: String -> String
  (let [(lines (stringLines text))]
    (stringJoin (map (fn [(i Int64)] -> String (str (stringFromInt64 (+ i 1)) "| " (at lines i))) (range 0 (listLength lines))) "\n"))

fn bugPrompt it: Item t: gc/Task -> String
  (str "This " (langName it.lang) " program should do the following. " t.statement "\n\n"
       "Exactly one line is wrong: a single token was changed. The program with line numbers:\n"
       (numbered it.mutant) "\n\n"
       "Reply with exactly two lines and nothing else:\nLINE: <number of the wrong line>\nFIX: <the corrected line, without its number>\n")

fn answerLine reply: String tag: String -> String
  (match (listFind (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) tag)) (stringLines reply))
    ((none) "")
    ((some l) (stringTrim (gc/sliceFrom (stringTrim l) (stringLength tag)))))

fn norm s: String -> String
  (stringReplace (stringReplace (stringReplace (stringTrim s) " " "") "'" "\"") "`" "")

fn digitsOf s: String -> String
  (stringJoin (filter (fn [(c String)] -> Bool (stringContains? "0123456789" c)) (stringChars s)) "")

fn indentLen line: String i: Int64 -> Int64
  (if (= (gc/charAt line i) " ") (indentLen line (+ i 1)) i)

fn bareFix fix: String said: Int64 -> String
  (let [(prefix (str (stringFromInt64 said) "| "))]
    (stringTrim (if (stringStartsWith? fix prefix) (gc/sliceFrom fix (stringLength prefix)) fix)))

fn replaceLine lines: (List String) k: Int64 fix: String -> String
  (stringJoin (map (fn [(i Int64)] -> String
                     (if (= i (- k 1))
                       (str (gc/slice (at lines i) 0 (indentLen (at lines i) 0)) fix)
                       (at lines i)))
                   (range 0 (listLength lines)))
              "\n")

fn boolText b: Bool -> String
  (if b "true" "false")

fn one b: Bool -> Int64
  (if b 1 0)

fn rowTail rep: gc/Reply -> String
  (str " :tokIn " (stringFromInt64 rep.tokIn) " :tokOut " (stringFromInt64 rep.tokOut) " :error " (gc/asnQuote rep.error)
       " :reply " (gc/asnQuote (gc/clip rep.text 600)) ")\n")

fn ! predict! cfg: gc/Config model: String st: St it: Item t: gc/Task arm: String system: String -> St
  (let [(out (ask! cfg model st system (predictPrompt it t)))
        (s2 (pairFirst out))
        (rep (pairSecond out))]
    (if (= rep.error "skipped")
      s2
      (let [(ok1 (= (norm (answerLine rep.text "A1:")) (norm (at it.wants 0))))
            (ok2 (= (norm (answerLine rep.text "A2:")) (norm (at it.wants 1))))
            (wrote (fileAppend cfg.out (str "(:read :task " (gc/asnQuote it.task) " :arm " (gc/asnQuote arm) " :probe \"predict\" :ok1 " (boolText ok1)
                                            " :ok2 " (boolText ok2) (rowTail rep))))]
        (addStat s2 (Stat :arm arm :probe "predict" :items 2 :a (+ (one ok1) (one ok2)) :b 0
                          :errs (one (not (stringEmpty? rep.error))) :tokIn rep.tokIn :tokOut rep.tokOut)))))

fn ! bug! cfg: gc/Config model: String st: St it: Item t: gc/Task arm: String system: String -> St
  (if (stringEmpty? it.bug)
    st
    (let [(out (ask! cfg model st system (bugPrompt it t)))
          (s2 (pairFirst out))
          (rep (pairSecond out))]
      (if (= rep.error "skipped")
        s2
        (let [(lines (stringLines it.mutant))
              (said (optionOr (stringToInt64 (digitsOf (answerLine rep.text "LINE:"))) 0))
              (fix (bareFix (answerLine rep.text "FIX:") said))
              (lineOk (= said it.line))
              (usable (and (>= said 1) (<= said (listLength lines)) (not (stringEmpty? fix))))
              (fixOk (if usable (= (stageOf! cfg (str "f-" it.task "-" arm) it.lang t (replaceLine lines said fix)) "ok") false))
              (wrote (fileAppend cfg.out (str "(:read :task " (gc/asnQuote it.task) " :arm " (gc/asnQuote arm) " :probe \"bug\" :bug " (gc/asnQuote it.bug)
                                              " :lineOk " (boolText lineOk) " :fixOk " (boolText fixOk) (rowTail rep))))]
          (addStat s2 (Stat :arm arm :probe "bug" :items 1 :a (one lineOk) :b (one fixOk)
                            :errs (one (not (stringEmpty? rep.error))) :tokIn rep.tokIn :tokOut rep.tokOut))))))

fn arms -> (List String)
  (list "py" "ts" "aslCard" "aslNoCard")

fn ! cell! cfg: gc/Config model: String cards: (List gc/Card) cardArm: String items: (List Item) st: St t: gc/Task arm: String -> St
  (match (listFind (fn [(it Item)] -> Bool (and (= it.task t.id) (= it.lang (langOf arm)))) items)
    ((none) st)
    ((some it)
      (let [(system (systemFor arm cards cardArm))]
        (bug! cfg model (predict! cfg model st it t arm system) it t arm system))))

fn sumOf stats: (List Stat) pick: (fn [Stat] -> Int64) -> Int64
  (listSum (map pick stats))

fn summaryRow stats: (List Stat) arm: String probe: String -> String
  (let [(mine (filter (fn [(s Stat)] -> Bool (and (= s.arm arm) (= s.probe probe))) stats))]
    (str "(:readSummary :arm " (gc/asnQuote arm) " :probe " (gc/asnQuote probe)
         " :calls " (stringFromInt64 (listLength mine))
         " :items " (stringFromInt64 (sumOf mine (fn [(s Stat)] -> Int64 s.items)))
         (if (= probe "predict") " :correct " " :lineOk ") (stringFromInt64 (sumOf mine (fn [(s Stat)] -> Int64 s.a)))
         (if (= probe "predict") "" (str " :fixOk " (stringFromInt64 (sumOf mine (fn [(s Stat)] -> Int64 s.b)))))
         " :callErrors " (stringFromInt64 (sumOf mine (fn [(s Stat)] -> Int64 s.errs)))
         " :tokIn " (stringFromInt64 (sumOf mine (fn [(s Stat)] -> Int64 s.tokIn)))
         " :tokOut " (stringFromInt64 (sumOf mine (fn [(s Stat)] -> Int64 s.tokOut))) ")"))

fn ! finish! cfg: gc/Config st: St -> (Result Int64 String)
  (let [(rows (listFlatMap (fn [(arm String)] -> (List String) (list (summaryRow st.stats arm "predict") (summaryRow st.stats arm "bug"))) (arms)))
        (tail (str (stringJoin rows "\n") "\n(:readRun :status " (if (stringEmpty? st.stopped) ":done" ":stopped") " :reason " (gc/asnQuote st.stopped)
                   " :spentUsd " (gc/asnQuote (gc/usdText st.spent)) " :capUsd " (gc/asnQuote (gc/usdText cfg.capPico)) ")\n"))
        (wrote (fileAppend cfg.out tail))
        (cleaned (gc/removeDir! cfg.work))]
    (do
      (println tail)
      (ok 0)))

fn ! run! args: (List String) -> (Result Int64 String)
  (let [(root (rootOf args))
        (cfg (configOf args root))
        (model (optionOr (flagValue args "--model") ""))
        (cardArm (optionOr (flagValue args "--card") "aslCardMin"))
        (only (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit (optionOr (flagValue args "--tasks") "") ",")))]
    (cond
      ((stringEmpty? model) (err "run needs --model ALIAS"))
      ((<= cfg.capPico 0) (err "run needs --maxUsd N: the budget stop is mandatory"))
      (else
        (match (loadItems (optionOr (flagValue args "--items") (str root "/asl/bench/gen/cardLab/readItems.asn")))
          ((err e) (err e))
          ((ok items)
            (match (gc/loadCardsFor root (list cardArm))
              ((err e) (err e))
              ((ok cards)
                (match (gc/loadTasks root)
                  ((err e) (err e))
                  ((ok allTasks)
                    (match (gs/linkOpen! (gu/envMapFromList (envList)) (optionOr (envGet "HOME") "") root (gd/builtinFamilies))
                      ((err e) (err (str "gateway link: " e)))
                      ((ok l)
                        (let [(tasks (if (listEmpty? only) allTasks (filter (fn [(t gc/Task)] -> Bool (listContains? only t.id)) allTasks)))
                              (head (fileWrite cfg.out (str "(:readRun :id \"CARD-LAB\" :model " (gc/asnQuote model) " :card " (gc/asnQuote cardArm)
                                                            " :cardTokens " (stringFromInt64 (gc/cardOf cards cardArm).tokens)
                                                            " :arms " (quoted (arms)) " :tasks " (stringFromInt64 (listLength tasks))
                                                            " :maxTokens " (stringFromInt64 cfg.maxTokens) " :temperature \"0.2\""
                                                            " :capUsd " (gc/asnQuote (gc/usdText cfg.capPico)) " :date " (gc/asnQuote (gc/dateOf (nowNs))) ")\n")))
                              (st (fold (fn [(acc St) (t gc/Task)] -> St
                                          (fold (fn [(inner St) (arm String)] -> St (cell! cfg model cards cardArm items inner t arm)) acc (arms)))
                                        (St :link l :spent 0 :stopped "" :stats (list))
                                        tasks))]
                          (finish! cfg st)))))))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))]
    (cond
      ((= cmd "gen") (gen! args))
      ((= cmd "run") (run! args))
      (else (err "usage: asl run asl/bench/gen/cardLab/readProbe.asl gen [--items FILE]\n       asl run asl/bench/gen/cardLab/readProbe.asl run --model ALIAS --maxUsd N [--priceIn P --priceOut P] [--card ARM] [--tasks T,U] [--maxTokens N] [--items FILE] [--out FILE]"))))
