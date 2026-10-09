(module asl/agentLoop/exec
  :x [Val Receipt ExecEnv ExecOut
      vStr vInt vBool vStrs vPair vNone vRecs
      makeExecEnv execOp! execGateOp! intentReceipt execNoteOp hideHarnessEntries hiddenTouched harnessTouched opWords
      formatOpReceipt formatGateRun gateTail gateOutcome escapeAsn pyStr truthyVal
      opShapes acceptedOpsForMode terminalForms undeclaredAnswer collectProseStrings
      recGet recSet serVal serRec kvToVal aslRunner! hiddenEnv! rawRequiredBytes noteMaxChars deliverables]
  :i [(asl/agentLoop/core :a c)
      (asl/agentLoop/aslOps :a o)
      (asl/agentLoop/txn :a t)
      (asl/agentLoop/gitOps :a g)
      (asl/agentLoop/runOps :a r)
      (asl/agentLoop/reply :a rp)
      (asl/agentLoop/plan :a p)
      (asl/agentLoop/claims :a cl)])

enum Val
  (vStr text: String)
  (vInt n: Int64)
  (vBool b: Bool)
  (vStrs xs: (List String))
  (vPair first: Int64 second: Int64)
  (vNone)
  (vRecs recs: (List (List (Pair String Val))))

(schema ExecEnv
  (:f root String)
  (:f repoRoot String)
  (:f mode String)
  (:f owns (List String))
  (:f writesPersisted Bool)
  (:f defaultBase String)
  (:f gates (List String))
  (:f effects (List (Pair String String)))
  (:f hiddenRaw String)
  (:f hiddenValues (List (Pair String String)))
  (:f readCap Int64)
  (:f runTimeout Int64)
  (:f deadlineAt (Option Float64))
  (:f session String)
  (:f env (Option (List String))))

(schema ExecOut
  (:f rec (List (Pair String Val)))
  (:f procs r/Procs))

fn makeExecEnv root: String repoRoot: String mode: String owns: (List String) writesPersisted: Bool defaultBase: String gates: (List String) effects: (List (Pair String String)) hiddenRaw: String hiddenValues: (List (Pair String String)) readCap: Int64 runTimeout: Int64 deadlineAt: (Option Float64) session: String env: (Option (List String)) -> ExecEnv
  (ExecEnv :root root :repoRoot repoRoot :mode mode :owns owns :writesPersisted writesPersisted :defaultBase defaultBase
    :gates gates :effects effects :hiddenRaw hiddenRaw :hiddenValues hiddenValues :readCap readCap :runTimeout runTimeout
    :deadlineAt deadlineAt :session session :env env)

; (:m :adopted NormativeAndEmpiricalAreNotMixed)
fn rawRequiredBytes -> Int64
  400

; (:m :adopted NormativeAndEmpiricalAreNotMixed)
fn noteMaxChars -> Int64
  2400

fn gateTailLines -> Int64
  20

fn gateTailChars -> Int64
  2000

fn gitNoteChars -> Int64
  600

fn deliverables -> (List String)
  (list "findings" "patch" "plan" "verdict")

fn gitOpNames -> (List String)
  (list "gitDiff" "gitLog" "gitShow")

fn aslOpNames -> (List String)
  (list "write" "edit" "read" "check" "diff" "flush" "discard" "query" "q" "test" "tree" "fix" "tools" "help" "observe"
        "outline" "intel" "search" "research" "crawl")


fn recGet rec: (List (Pair String Val)) k: String -> (Option Val)
  (mt (listHead (filter (fn [p] (= (pairFirst p) k)) rec))
    ((some p) (some (pairSecond p)))
    ((none) (none)))

fn recSet rec: (List (Pair String Val)) k: String v: Val -> (List (Pair String Val))
  (if (listAny? (fn [p] (= (pairFirst p) k)) rec)
    (map (fn [p] (if (= (pairFirst p) k) (pair k v) p)) rec)
    (listAppend rec (list (pair k v))))

fn has? rec: (List (Pair String Val)) k: String -> Bool
  (some? (recGet rec k))

fn vs k: String v: String -> (Pair String Val)
  (pair k (vStr v))

fn serVal v: Val -> String
  (mt v
    ((vStr s) (c/serString s))
    ((vInt n) (stringFromInt64 n))
    ((vBool b) (if b "true" "false"))
    ((vStrs xs) (str "(" (stringJoin (map c/serString xs) " ") ")"))
    ((vPair a b) (str "(" (stringFromInt64 a) " " (stringFromInt64 b) ")"))
    ((vNone) "none")
    ((vRecs rs) (str "(" (stringJoin (map serRec rs) " ") ")")))

fn serRec rec: (List (Pair String Val)) -> String
  (str "(r" (c/joinAll (map (fn [p] (str " (" (pairFirst p) " " (serVal (pairSecond p)) ")")) rec)) ")")

fn pyStr v: Val -> String
  (mt v
    ((vStr s) s)
    ((vInt n) (stringFromInt64 n))
    ((vBool b) (if b "True" "False"))
    ((vStrs xs) (str "[" (stringJoin (map g/pyRepr xs) ", ") "]"))
    ((vPair a b) (str "[" (stringFromInt64 a) ", " (stringFromInt64 b) "]"))
    ((vNone) "None")
    ((vRecs rs) (str "[" (stringJoin (map (fn [x] "{...}") rs) ", ") "]")))

fn truthyVal v: Val -> Bool
  (mt v
    ((vStr s) (not (stringEmpty? s)))
    ((vInt n) (!= n 0))
    ((vBool b) b)
    ((vStrs xs) (not (listEmpty? xs)))
    ((vPair _ _) true)
    ((vNone) false)
    ((vRecs rs) (not (listEmpty? rs))))

fn truthyField rec: (List (Pair String Val)) k: String -> Bool
  (mt (recGet rec k) ((some v) (truthyVal v)) ((none) false))

fn notNone rec: (List (Pair String Val)) k: String -> Bool
  (mt (recGet rec k) ((some v) (mt v ((vNone) false) (_ true))) ((none) false))

fn fieldStr rec: (List (Pair String Val)) k: String dflt: String -> String
  (mt (recGet rec k) ((some v) (pyStr v)) ((none) dflt))

fn fromAsl v: o/RVal -> Val
  (mt v
    ((o/rStr s) (vStr s))
    ((o/rInt n) (vInt n))
    ((o/rBool b) (vBool b))
    ((o/rList xs) (vStrs xs))
    ((o/rPair a b) (vPair a b))
    ((o/rNone) (vNone)))

fn fromTxn v: t/RVal -> Val
  (mt v
    ((t/rStr s) (vStr s))
    ((t/rInt n) (vInt n))
    ((t/rBool b) (vBool b))
    ((t/rList xs) (vStrs xs))
    ((t/rNone) (vNone)))

fn fromGit v: g/RVal -> Val
  (mt v
    ((g/rStr s) (vStr s))
    ((g/rInt n) (vInt n))
    ((g/rBool b) (vBool b))
    ((g/rNull) (vNone))
    ((g/rPair a b) (vPair a b)))

fn fromRun v: r/RVal -> Val
  (mt v
    ((r/rStr s) (vStr s))
    ((r/rInt n) (vInt n))
    ((r/rBool b) (vBool b))
    ((r/rList xs) (vStrs xs)))

fn mapRec rec: (List (Pair String T)) conv: (fn [T] -> Val) -> (List (Pair String Val))
  (map (fn [p] (pair (pairFirst p) (conv (pairSecond p)))) rec)


fn kvToVal v: c/KvVal -> Val
  (mt v
    ((c/kvStr s) (vStr s))
    ((c/kvInt d) (mt (stringToInt64 d) ((some n) (vInt n)) ((none) (vStr d)))))

fn kvText v: c/KvVal -> String
  (mt v ((c/kvStr s) s) ((c/kvInt d) (pyStr (kvToVal (c/kvInt d)))))

fn opGet op: (List (Pair String c/KvVal)) k: String -> (Option c/KvVal)
  (c/dictGet op k)

fn opStr op: (List (Pair String c/KvVal)) k: String dflt: String -> String
  (mt (opGet op k) ((some v) (kvText v)) ((none) dflt))

fn opTruthy op: (List (Pair String c/KvVal)) k: String -> Bool
  (mt (opGet op k) ((some v) (truthyVal (kvToVal v))) ((none) false))

fn opFirst op: (List (Pair String c/KvVal)) keys: (List String) dflt: String -> String
  (mt (listHead (filter (fn [k] (opTruthy op k)) keys))
    ((some k) (opStr op k ""))
    ((none) dflt))

fn opIsStr op: (List (Pair String c/KvVal)) k: String -> Bool
  (mt (opGet op k) ((some v) (mt v ((c/kvStr _) true) ((c/kvInt _) false))) ((none) true))

fn opVal op: (List (Pair String c/KvVal)) k: String dflt: Val -> Val
  (mt (opGet op k) ((some v) (kvToVal v)) ((none) dflt))


fn isCont b: Int64 -> Bool
  (and (>= b 128) (< b 192))

fn cpCount bs: Bytes n: Int64 i: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (cpCount bs n (+ i 1) (if (isCont (bytesGet bs i)) acc (+ acc 1))))

fn cpLen s: String -> Int64
  (let [bs (stringToBytes s)] (cpCount bs (bytesLength bs) 0 0))

fn cpIndex bs: Bytes n: Int64 i: Int64 k: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((isCont (bytesGet bs i)) (cpIndex bs n (+ i 1) k))
    ((<= k 0) i)
    (else (cpIndex bs n (+ i 1) (- k 1))))

fn cpTake s: String k: Int64 -> String
  (let [bs (stringToBytes s)] (c/sliceOf s 0 (cpIndex bs (bytesLength bs) 0 k)))

fn cpTail s: String k: Int64 -> String
  (let [len (cpLen s)
        bs (stringToBytes s)]
    (if (<= len k) s (c/sliceOf s (cpIndex bs (bytesLength bs) 0 (- len k)) (bytesLength bs))))


fn escapeAsn s: String -> String
  (c/escapeAsn s)

fn escVal v: Val -> String
  (mt v ((vNone) "") (_ (c/escapeAsn (pyStr v))))

fn escField rec: (List (Pair String Val)) k: String -> String
  (mt (recGet rec k) ((some v) (escVal v)) ((none) ""))

fn strItems v: Val -> (List String)
  (mt v ((vStrs xs) xs) ((vStr s) (stringChars s)) (_ (list)))

fn quotedList v: Val -> String
  (stringJoin (map (fn [x] (str "\"" (c/escapeAsn x) "\"")) (strItems v)) " ")

fn itemAt v: Val i: Int64 -> String
  (mt v
    ((vPair a b) (stringFromInt64 (if (= i 0) a b)))
    ((vStrs xs) (optionOr (listGet xs i) "None"))
    (_ "None"))

fn gateTail gate: (List (Pair String Val)) -> String
  (let [out (if (truthyField gate "stdout") (fieldStr gate "stdout" "") "")
        errText (if (truthyField gate "stderr") (fieldStr gate "stderr" "") "")
        combined (g/pyStrip (str out "\n" errText))
        ls (g/pySplitLines combined false)
        n (listLength ls)
        last (optionOr (listSlice ls (max 0 (- n (gateTailLines))) n) (list))]
    (cpTail (stringJoin last "\n") (gateTailChars)))

fn gateOutcome gate: (List (Pair String Val)) -> String
  (if (truthyField gate "timeout")
    (str ":timeout true :seconds " (fieldStr gate "seconds" "None"))
    (str ":exit " (fieldStr gate "exit" "None")))

fn formatGateRun gate: (List (Pair String Val)) -> String
  (let [n (if (notNone gate "n") (str ":n " (fieldStr gate "n" "") " ") "")]
    (str "(" n ":cmd \"" (escField gate "cmd") "\" " (gateOutcome gate) " :tail \"" (c/escapeAsn (gateTail gate)) "\")"))

fn capped s: String cap: Int64 cut: Int64 tail: String -> String
  (if (> (cpLen s) cap) (str (cpTake s cut) tail) s)

fn gateRunsOf v: Val -> (List (List (Pair String Val)))
  (mt v ((vRecs rs) rs) (_ (list)))

fn formatOpReceipt rec: (List (Pair String Val)) readCap: Int64 -> String
  (let [op (fieldStr rec "op" "")
        isGit (listContains? (gitOpNames) op)
        contentCap (cond
                     ((listContains? (list "read" "outline" "intel") op) (+ readCap 200))
                     (isGit (+ readCap (gitNoteChars)))
                     (else 2000))
        diffCap (if isGit (+ readCap (gitNoteChars)) 2000)
        field (fn [k] (optionOr (recGet rec k) (vNone)))
        parts (list
                (str "(:receipt :id \"" (fieldStr rec "id" "") "\" :op \"" op "\" :status :" (fieldStr rec "status" "ok"))
                (if (truthyField rec "file") (str " :file \"" (escField rec "file") "\"") "")
                (if (truthyField rec "path") (str " :path \"" (escField rec "path") "\"") "")
                (if (truthyField rec "seenTurn") (str " :turn " (fieldStr rec "seenTurn" "")) "")
                (if (notNone rec "totalLines")
                  (str " :lines (" (itemAt (field "lines") 0) " " (itemAt (field "lines") 1) ") :totalLines " (fieldStr rec "totalLines" "")
                    " :totalChars " (fieldStr rec "totalChars" "None"))
                  "")
                (if (truthyField rec "span") (str " :lines (" (itemAt (field "span") 0) " " (itemAt (field "span") 1) ")") "")
                (if (= op "note")
                  (str " :chars " (fieldStr rec "chars" "0") (if (truthyField rec "cap") (str " :cap " (fieldStr rec "cap" "")) ""))
                  "")
                (if (and (= op "intent") (truthyField rec "deliver")) (str " :deliver :" (fieldStr rec "deliver" "")) "")
                (if (notNone rec "content")
                  (str " :content \"" (c/escapeAsn (capped (fieldStr rec "content" "") contentCap contentCap "\n... [truncated]")) "\"")
                  "")
                (if (notNone rec "hits")
                  (str " :hits (" (capped (fieldStr rec "hits" "") 2000 2000 " ... [truncated]") ")")
                  "")
                (if (notNone rec "diff")
                  (str " :diff \"" (c/escapeAsn (capped (fieldStr rec "diff" "") diffCap 2000 "\n... [truncated]")) "\"")
                  "")
                (if (and (not (listContains? (list "write" "edit" "flush") op))
                         (and (truthyField rec "stdout")
                              (and (not (notNone rec "content")) (and (not (notNone rec "hits")) (not (notNone rec "diff"))))))
                  (str " :out \"" (c/escapeAsn (capped (g/pyStrip (fieldStr rec "stdout" "")) 2000 2000 "\n... [truncated]")) "\"")
                  "")
                (if (truthyField rec "owns") (str " :owns (" (quotedList (field "owns")) ")") "")
                (if (truthyField rec "flushed") (str " :flushed (" (quotedList (field "flushed")) ")") "")
                (if (truthyField rec "error") (str " :error :" (lstripColons (fieldStr rec "error" ""))) "")
                (if (truthyField rec "message") (str " :message \"" (escField rec "message") "\"") "")
                (if (truthyField rec "warning") (str " :warning \"" (escField rec "warning") "\"") "")
                (if (notNone rec "line") (str " :line " (fieldStr rec "line" "")) "")
                (if (notNone rec "arrived") (str " :arrived \"" (escField rec "arrived") "\"") "")
                (if (notNone rec "hint") (str " :hint \"" (escField rec "hint") "\"") "")
                (if (notNone rec "balance") (str " :balance \"" (escField rec "balance") "\"") "")
                (if (truthyField rec "nearest") (str " :nearest \"" (escField rec "nearest") "\"") "")
                (if (truthyField rec "terminal") (str " :terminal (" (quotedList (field "terminal")) ")") "")
                (if (truthyField rec "gateRuns") (str " :gates (" (stringJoin (map formatGateRun (gateRunsOf (field "gateRuns"))) " ") ")") "")
                (if (and (= op "run") (has? rec "exit")) (str " :cmd \"" (escField rec "cmd") "\" :exit " (fieldStr rec "exit" "")) "")
                (if (= op "manage")
                  (str " :action :" (fieldStr rec "action" "") (if (has? rec "exit") (str " :exit " (fieldStr rec "exit" "")) ""))
                  "")
                (if (truthyField rec "restored") (str " :restored (" (quotedList (field "restored")) ")") "")
                ")")]
    (c/joinAll parts))

fn lstripColons s: String -> String
  (if (stringStartsWith? s ":") (lstripColons (c/sliceOf s 1 (stringLength s))) s)


fn opShapes -> (List (Pair String String))
  (list
    (pair "write" "(:step :op \"write\" :file f :content :raw|s)")
    (pair "edit" "(:step :op \"edit\" :file f :old :raw|s :new :raw|s)")
    (pair "read" "(:step :op \"read\" :file f [:symbol name] [:anchor s] [:start n :end m])")
    (pair "query" "(:step :op \"query\" :query s [:in code|text|all] [:limit n])")
    (pair "outline" "(:step :op \"outline\" :file f)")
    (pair "check" "(:step :op \"check\" :file f)")
    (pair "diff" "(:step :op \"diff\")")
    (pair "flush" "(:step :op \"flush\")")
    (pair "discard" "(:step :op \"discard\")")
    (pair "test" "(:step :op \"test\" :file f)")
    (pair "tree" "(:step :op \"tree\" :path p)")
    (pair "fix" "(:step :op \"fix\" :file f)")
    (pair "txn" "(:txn :owns (f ...) ...)")
    (pair "tools" "(:step :op \"tools\")")
    (pair "help" "(:step :op \"help\" :name op)")
    (pair "findings" "(:findings (:claim s :file f))")
    (pair "evidence" "(:evidence (:receipt id [:exit n]))")
    (pair "escalate" "(:escalate :reason s)")
    (pair "done" "(:done [:commit s])")
    (pair "gitDiff" "(:step :op \"gitDiff\" :path p :base rev [:start n :end m])")
    (pair "gitLog" "(:step :op \"gitLog\" :path p :limit n [:start n :end m])")
    (pair "gitShow" "(:step :op \"gitShow\" :rev rev :path p [:start n :end m])")
    (pair "gate" "(:step :op \"gate\" [:n i])")
    (pair "run" "(:step :op \"run\" :argv \"cmd\")")
    (pair "delete" "(:step :op \"delete\" :file f)")
    (pair "manage" "(:step :op \"manage\" :action spawn|poll|tail|send|kill|list :id name [:cmd c] [:text s])")
    (pair "note" "(:step :op \"note\" :text s)")
    (pair "observe" "(:step :op \"observe\" :dim callers|status|coverage|tokenCost|memory|session [:symbol s] [:path p] [:spec p])")
    (pair "search" "(:step :op \"search\" :query s [:limit n])")
    (pair "research" "(:step :op \"research\" :topic s [:depth flash|deep|exhaustive])")
    (pair "crawl" "(:step :op \"crawl\" :url u [:distill text|asn] [:limit n])"))

fn scoutMutating -> (List String)
  (list "write" "edit" "flush" "discard" "fix" "txn" "gate" "run" "manage" "delete")

fn acceptedOpsForMode mode: String effects: (List (Pair String String)) -> (List String)
  (let [local (map pairFirst (filter (fn [p] (= (pairSecond p) "local")) effects))]
    (cond
      ((= mode "scout") (filter (fn [o] (and (not (listContains? (scoutMutating) o)) (!= o "step"))) local))
      ((= mode "auto") (filter (fn [o] (!= o "step")) local))
      (else (filter (fn [o] (and (!= o "findings") (!= o "step"))) local))))

fn dedupe xs: (List String) -> (List String)
  (listReverse (fold (fn [acc x] (if (listContains? acc x) acc (cons x acc))) (list) xs))

fn terminalForms mode: String -> (List String)
  (if (= mode "auto")
    (dedupe (listAppend (c/terminalForms "implement") (c/terminalForms "scout")))
    (c/terminalForms mode))

fn undeclaredAnswer unknown: String mode: String effects: (List (Pair String String)) -> (List (Pair String Val))
  (let [nearest (c/nearestOp unknown (acceptedOpsForMode mode effects))]
    (if (stringEmpty? nearest)
      (list (pair "terminal" (vStrs (terminalForms mode))))
      (list (vs "nearest" nearest))))

; (:m :tags (claims))
fn collectProseStrings formText: String inEvidence: Bool out: (List String) useOld: Bool planOn: Bool -> (List String)
  (listAppend out
    (cl/collectProseStringsInner formText inEvidence (if useOld (cl/oldStructuralKeys) (cl/newStructuralKeys)) planOn (list)))


fn isWs c: String -> Bool
  (c/isSpace c)

fn isWord c: String -> Bool
  (c/isWordByte c)

fn wsEnd s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isWs (c/ch s i))) (wsEnd s n (+ i 1)) i)

fn wordEnd s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (isWord (c/ch s i))) (wordEnd s n (+ i 1)) i)

fn indexFrom s: String needle: String i: Int64 -> (Option Int64)
  (if (> i (stringLength s))
    (none)
    (mt (stringIndexOf (c/sliceOf s i (stringLength s)) needle)
      ((some k) (some (+ i k)))
      ((none) (none))))

fn wordAfterKey s: String key: String i: Int64 -> (Option String)
  (mt (indexFrom s key i)
    ((none) (none))
    ((some at)
      (let [n (stringLength s)
            w (wsEnd s n (+ at (stringLength key)))
            lead (and (< w n) (or (= (c/ch s w) ":") (= (c/ch s w) "\"")))
            e1 (if lead (wordEnd s n (+ w 1)) w)
            e0 (wordEnd s n w)]
        (cond
          ((= w (+ at (stringLength key))) (wordAfterKey s key (+ at 1)))
          ((and lead (> e1 (+ w 1))) (some (c/sliceOf s (+ w 1) e1)))
          ((> e0 w) (some (c/sliceOf s w e0)))
          (else (wordAfterKey s key (+ at 1)))))))

fn quotedEnd s: String n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) -1)
    ((= (c/ch s j) "\"") j)
    ((= (c/ch s j) "\\") (if (and (< (+ j 1) n) (!= (c/ch s (+ j 1)) "\n")) (quotedEnd s n (+ j 2)) -1))
    (else (quotedEnd s n (+ j 1))))

fn quotedAfterKey s: String key: String i: Int64 -> (Option String)
  (mt (indexFrom s key i)
    ((none) (none))
    ((some at)
      (let [n (stringLength s)
            w (wsEnd s n (+ at (stringLength key)))
            e (if (and (> w (+ at (stringLength key))) (and (< w n) (= (c/ch s w) "\""))) (quotedEnd s n (+ w 1)) -1)]
        (if (>= e 0) (some (c/sliceOf s (+ w 1) e)) (quotedAfterKey s key (+ at 1))))))


; (:m :tags (leon))
fn intentReceipt op: (List (Pair String c/KvVal)) rid: String -> (List (Pair String Val))
  (let [form (if (opTruthy op "form") (opStr op "form" "") "")
        deliver (optionOr (wordAfterKey form ":deliver" 0) "")]
    (if (not (listContains? (deliverables) deliver))
      (list (vs "id" rid) (vs "op" "intent") (vs "status" "rejected") (vs "error" "ERR_INVALID_ARG")
        (vs "message" (str ":deliver is one of " (stringJoin (deliverables) ", ") ", not '" deliver "'")))
      (list (vs "id" rid) (vs "op" "intent") (vs "status" "ok") (vs "deliver" deliver)
        (vs "why" (mt (quotedAfterKey form ":why" 0) ((some w) (c/asnUnescape w)) ((none) "")))
        (vs "kind" (optionOr (wordAfterKey form ":kind" 0) "")))))

fn needsConfirmRec rid: String opName: String -> (List (Pair String Val))
  (list (vs "id" rid) (vs "op" opName) (vs "status" "needsConfirm") (pair "needsConfirm" (vBool true))
    (vs "message" (str "not executed: '" opName "' is an outward effect that needs the principal's confirmation; the run goes on")))

fn nodeAtom n: p/SexpNode -> (Option String)
  (mt n ((p/sexpAtom a) (some a)) (_ (none)))

fn nodeStr n: p/SexpNode -> (Option String)
  (mt n ((p/sexpStr s) (some s)) (_ (none)))

fn execNoteOp op: (List (Pair String c/KvVal)) rid: String -> (List (Pair String Val))
  (let [answer (c/noteStep (opStr op "form" "") (noteMaxChars))
        items (mt (p/planTree answer)
                ((ok nodes) (mt (listHead nodes) ((some nd) (mt nd ((p/sexpList xs) xs) (_ (list)))) ((none) (list))))
                ((err _) (list)))
        status (optionOr (mt (listGet items 1) ((some x) (nodeAtom x)) ((none) (none))) "")
        chars (mt (listGet items 2) ((some x) (mt (nodeAtom x) ((some a) (stringToInt64 a)) ((none) (none)))) ((none) (none)))
        text (mt (listGet items 3) ((some x) (nodeStr x)) ((none) (none)))
        slot (mt (listGet items 4) ((some x) (nodeStr x)) ((none) (none)))]
    (if (or (!= (listLength items) 5)
            (or (not (listContains? (list "ok" "rejected" "missing") status)) (or (none? chars) (or (none? text) (none? slot)))))
      (list (vs "id" rid) (vs "op" "note") (vs "status" "rejected") (vs "error" "ERR_CORE_HOST_MALFORMED")
        (vs "message" (cpTake (str "expected (note status chars text slot), got " answer) 200)))
      (let [k (optionOr chars 0)
            head (list (vs "id" rid) (vs "op" "note") (pair "chars" (vInt k)))]
        (cond
          ((= status "ok") (listAppend head (list (vs "status" "ok") (vs "noteText" (optionOr text "")) (vs "noteSlot" (optionOr slot "")))))
          ((= status "rejected")
            (listAppend head (list (vs "status" "rejected") (vs "error" "ERR_NOTE_TOO_LONG") (pair "cap" (vInt (noteMaxChars)))
                               (vs "message" (str "the note is " (stringFromInt64 k) " chars, over the cap of " (stringFromInt64 (noteMaxChars)) "; the note is unchanged")))))
          (else (listAppend head (list (vs "status" "rejected") (vs "error" "ERR_MISSING_ARG") (vs "message" "note needs :text s; the note is unchanged"))))))))


fn ! cwd! -> String
  (resultOr (realPath ".") ".")

fn ! absRoot! root: String -> String
  (let [r (if (stringEmpty? root) "." root)]
    (g/pyNormpath (if (stringStartsWith? r "/") r (str (cwd!) "/" r))))

; (:m :effect proc :tags (owns))
fn opWords op: (List (Pair String c/KvVal)) -> (List String)
  (let [named (map (fn [k] (opStr op k "")) (filter (fn [k] (opTruthy op k)) (list "file" "path" "scope")))
        split (fold (fn [acc k]
                      (if (opTruthy op k)
                        (let [v (opStr op k "")]
                          (listAppend acc (mt (rp/shlexSplit v) ((ok ws) ws) ((err _) (list v)))))
                        acc))
                (list) (list "argv" "cmd"))]
    (listAppend named split))

fn namesVar w: String name: String i: Int64 -> Bool
  (mt (indexFrom w "$" i)
    ((none) false)
    ((some at)
      (let [n (stringLength w)
            s0 (+ at 1)
            s1 (if (and (< s0 n) (= (c/ch w s0) "{")) (+ s0 1) s0)
            hit (fn [s] (and (= (c/sliceOf w s (min n (+ s (stringLength name)))) name)
                             (let [e (+ s (stringLength name))] (or (>= e n) (not (isWord (c/ch w e)))))))]
        (or (hit s1) (or (and (!= s1 s0) (hit s0)) (namesVar w name (+ at 1)))))))

fn ! hiddenTouched op: (List (Pair String c/KvVal)) env: ExecEnv -> Bool
  (let [names (r/hiddenVars env.hiddenRaw)
        words (opWords op)]
    (if (or (listEmpty? names) (listEmpty? words))
      false
      (or (listAny? (fn [nm] (listAny? (fn [w] (namesVar w nm 0)) words)) names)
          (let [dirs (filter (fn [d] (not (stringEmpty? d)))
                       (map (fn [nm] (mt (listHead (filter (fn [p] (= (pairFirst p) nm)) env.hiddenValues))
                                       ((some p) (pairSecond p)) ((none) "")))
                         names))
                root (absRoot! env.root)]
            (and (not (listEmpty? dirs)) (listAny? (fn [w] (c/hiddenPath w dirs root)) words))))))

fn ! harnessTouched op: (List (Pair String c/KvVal)) root: String -> Bool
  (let [words (opWords op)
        abs (absRoot! root)]
    (and (not (listEmpty? words)) (listAny? (fn [w] (c/harnessPath w abs)) words)))

fn joinRel base: String e: String -> String
  (cond
    ((stringStartsWith? e "/") e)
    ((or (stringEmpty? base) (stringEndsWith? base "/")) (str base e))
    (else (str base "/" e)))

fn quotedRun s: String n: Int64 i: Int64 acc: (List String) -> (Pair (List String) Int64)
  (let [w (wsEnd s n i)]
    (if (and (< w n) (= (c/ch s w) "\""))
      (let [e (quotedEnd s n (+ w 1))]
        (if (>= e 0)
          (quotedRun s n (+ e 1) (cons (c/sliceOf s (+ w 1) e) acc))
          (pair (listReverse acc) i)))
      (pair (listReverse acc) i)))

fn entriesMatch s: String i: Int64 -> (Option (List Int64))
  (mt (indexFrom s ":entries (" i)
    ((none) (none))
    ((some at)
      (let [n (stringLength s)
            g2 (+ at 10)
            run (quotedRun s n g2 (list))
            e2 (pairSecond run)
            w (wsEnd s n e2)]
        (if (and (< w n) (= (c/ch s w) ")"))
          (some (list at e2 (+ w 1)))
          (entriesMatch s (+ at 1))))))

fn ! hideHarnessEntries rec: (List (Pair String Val)) path: String root: String -> (List (Pair String Val))
  (let [out (if (truthyField rec "stdout") (fieldStr rec "stdout" "") "")]
    (mt (entriesMatch out 0)
      ((none) rec)
      ((some m)
        (let [at (optionOr (listGet m 0) 0)
              e2 (optionOr (listGet m 1) 0)
              e3 (optionOr (listGet m 2) 0)
              n (stringLength out)
              entries (pairFirst (quotedRun out n (+ at 10) (list)))
              abs (absRoot! root)
              kept (filter (fn [e] (not (c/harnessPath (joinRel path (c/asnUnescape e)) abs))) entries)
              text (str (c/sliceOf out 0 (+ at 10)) (stringJoin (map (fn [e] (str "\"" e "\"")) kept) " ")
                     (c/sliceOf out e2 e3) (c/sliceOf out e3 n))]
          (recSet rec "stdout" (vStr text))))))


fn allDigits s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [ch] (and (>= ch "0") (<= ch "9"))) (stringChars s)))

fn ! stepTimeout! env: ExecEnv -> Int64
  (o/stepTimeout env.runTimeout env.deadlineAt (o/nowMono))

fn ! execGateOp! n: (Option c/KvVal) env: ExecEnv newId: (fn [] -> String) -> (List (Pair String Val))
  (let [rid (newId)
        gates env.gates
        count (listLength gates)]
    (if (listEmpty? gates)
      (list (vs "id" rid) (vs "op" "gate") (vs "status" "rejected") (vs "error" "ERR_NO_GATES") (vs "message" "this run declares no :gates"))
      (let [all (mt n ((none) true) ((some v) (mt v ((c/kvStr s) (stringEmpty? s)) ((c/kvInt _) false))))
            i (mt n
                ((none) 0)
                ((some v) (mt v
                            ((c/kvInt d) (optionOr (stringToInt64 d) 0))
                            ((c/kvStr s) (if (allDigits s) (optionOr (stringToInt64 s) 0) 0)))))]
        (if (and (not all) (or (< i 1) (> i count)))
          (list (vs "id" rid) (vs "op" "gate") (vs "status" "rejected") (vs "error" "ERR_GATE_INDEX")
            (vs "message" (str ":n " (mt n ((some v) (kvText v)) ((none) "")) " names no gate; the declared gates are 1 to " (stringFromInt64 count))))
          (let [picked (if all
                         (map (fn [k] (pair (+ k 1) (optionOr (listGet gates k) ""))) (range 0 count))
                         (list (pair i (optionOr (listGet gates (- i 1)) ""))))
                withIds (map (fn [pk] (pair (newId) (pairSecond pk))) picked)
                runs (g/runGates! withIds env.root (stepTimeout! env) (none))
                recs (map (fn [k] (listAppend (mapRec (optionOr (listGet runs k) (list)) fromGit)
                                    (list (pair "n" (vInt (pairFirst (optionOr (listGet picked k) (pair 0 ""))))))))
                       (range 0 (min (listLength picked) (listLength runs))))
                passed (listAll? (fn [rr] (= (recGet rr "exit") (some (vInt 0)))) recs)]
            (list (vs "id" rid) (vs "op" "gate") (vs "status" (if passed "ok" "failed")) (pair "gateRuns" (vRecs recs))))))))


fn rootRec rid: String opName: String path: String -> (List (Pair String Val))
  (list (vs "id" rid) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_ROOT") (vs "file" path)
    (vs "message" (str "'" path "' is outside :root; nothing in this step was written; the run goes on")))

fn ownsRec rid: String opName: String path: String owns: (List String) -> (List (Pair String Val))
  (list (vs "id" rid) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_OWNS") (vs "file" path)
    (pair "owns" (vStrs owns)) (vs "message" (str "'" path "' is outside :owns; nothing in this step was written; the run goes on")))

fn ! writeCheck op: (List (Pair String c/KvVal)) opName: String env: ExecEnv newId: (fn [] -> String) -> (Option (List (Pair String Val)))
  (let [target (opStr op "file" "")
        rawFields (filter (fn [w] (not (stringEmpty? w))) (stringSplit (stringJoin (map (fn [ch] (if (isWs ch) " " ch)) (stringChars (if (opTruthy op "rawFields") (opStr op "rawFields" "") ""))) "") " "))
        field (if (= opName "write") "content" "new")
        val (opStr op field "")
        form (opStr op "form" "")
        hasEscapes (and (or (stringContains? val "\"") (stringContains? val "\\"))
                        (or (stringContains? form "\\\"") (or (stringContains? form "\\\\") (or (stringContains? form "\\n") (stringContains? form "\\t")))))
        useRaw (and (not (listContains? rawFields field)) (and (opIsStr op field) (and (> (stringLength val) (rawRequiredBytes)) hasEscapes)))
        isRaw (fn [k] (mt (opGet op k) ((some v) (= v (c/kvStr ":raw"))) ((none) false)))
        rawMissing (or (= (opGet op "error") (some (c/kvStr "ERR_RAW_MISSING"))) (or (isRaw "content") (or (isRaw "old") (isRaw "new"))))
        owns env.owns]
    (cond
      (useRaw
        (some (list (vs "id" (newId)) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_USE_RAW") (vs "file" target)
                (vs "message" (str "send this as raw content: (:step :op \"write\" :file \"" target "\" :content :raw) then the code in a fenced block on the next lines, unescaped")))))
      (rawMissing
        (some (list (vs "id" (newId)) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_RAW_MISSING") (vs "file" target) (vs "message" "missing raw block for :raw"))))
      ((not (opTruthy op "file"))
        (some (list (vs "id" (newId)) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_MISSING_ARG") (vs "message" (str opName " needs :file")))))
      ((listEmpty? owns)
        (some (list (vs "id" (newId)) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_OWNS") (vs "file" target)
                (vs "message" (str "Edit rejected: no :owns covers " target)))))
      ((not (r/insideRoot! target env.root)) (some (rootRec (newId) opName target)))
      ((not (c/checkOwns target owns (absRoot! env.root))) (some (ownsRec (newId) opName target owns)))
      (else (none))))

fn ! aslRunner! repoRoot: String transport: String env: (Option (List String)) runTimeout: Int64 deadlineAt: (Option Float64) -> (fn [String String] -> t/AslRun)
  (fn [f rootDir]
    (let [res (o/runAsl repoRoot f rootDir (o/stepTimeout runTimeout deadlineAt (o/nowMono)) env transport)]
      (t/aslRun (o/runExit res) (o/runStdout res) (o/runStderr res))))

fn ! hiddenEnv! raw: String -> (List (Pair String String))
  (map (fn [nm] (pair nm (optionOr (envGet nm) ""))) (r/hiddenVars raw))

fn eo rec: (List (Pair String Val)) procs: r/Procs -> ExecOut
  (ExecOut :rec rec :procs procs)

fn ! runCtx! env: ExecEnv -> r/RunCtx
  (r/makeRunCtx env.root env.owns env.session (stepTimeout! env) (r/hiddenVars env.hiddenRaw) env.repoRoot)

fn ! aslOp! op: (List (Pair String c/KvVal)) env: ExecEnv newId: (fn [] -> String) snap: (fn [String] -> Bool) run: (fn [String String] -> t/AslRun) -> (List (Pair String Val))
  (mapRec (o/execAslOpCustom! op env.owns env.root newId snap run env.readCap (o/budgetLeft env.deadlineAt (o/nowMono))) fromAsl)

fn ! execOp! op: (List (Pair String c/KvVal)) env: ExecEnv procs: r/Procs newId: (fn [] -> String) snap: (fn [String] -> Bool) onKeep: (fn [String (Option String) Int64] -> Bool) run: (fn [String String] -> t/AslRun) -> ExecOut
  (let [opType (opStr op "type" "raw")
        opName (opStr op "op" opType)
        step (= opType "step")
        effect (if (and step (and (!= opName "intent") (not (stringEmpty? opName)))) (t/checkEffect env.effects opName) (t/effectAllowed))
        gates env.gates
        cmdText (g/pyStrip (opFirst op (list "argv" "cmd") ""))
        gateIdx (if (and step (and (= opName "run") (not (listEmpty? gates))))
                  (listHead (filter (fn [k] (= (g/pyStrip (optionOr (listGet gates k) "")) cmdText)) (range 0 (listLength gates))))
                  (none))]
    (cond
      ((and step (= opName "intent")) (eo (intentReceipt op (newId)) procs))
      ((mt effect ((t/effectUndeclared) true) (_ false))
        (eo (list (vs "id" (newId)) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_EFFECT_UNDECLARED")
              (vs "message" (str "Operation '" opName "' not declared in effects registry")))
          procs))
      ((mt effect ((t/effectConfirm) true) (_ false)) (eo (needsConfirmRec (newId) opName) procs))
      ((and step (= opName "gate")) (eo (execGateOp! (opGet op "n") env newId) procs))
      ((some? gateIdx)
        (let [k (optionOr gateIdx 0)
              rec (execGateOp! (some (c/kvInt (stringFromInt64 (+ k 1)))) env newId)]
          (eo (recSet rec "message" (vStr (str "ran as declared gate " (stringFromInt64 (+ k 1))))) procs)))
      ((and step (hiddenTouched op env))
        (eo (list (vs "id" (newId)) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_HIDDEN_PATH")
              (vs "message" "that path belongs to the evaluation, not the task; it is not read; declared gates run with (:step :op \"gate\") and after each write"))
          procs))
      ((and step (harnessTouched op env.root))
        (eo (list (vs "id" (newId)) (vs "op" opName) (vs "status" "rejected") (vs "error" "ERR_HARNESS_PATH")
              (vs "file" (opFirst op (list "file" "path") ""))
              (vs "message" ".asl/run holds this loop's own journals, agent files and patches, not the task; it is not read"))
          procs))
      ((and step (and (= opName "run") (opTruthy op "readHint")))
        (eo (list (vs "id" (newId)) (vs "op" "run") (vs "status" "rejected") (vs "error" "ERR_RUN_READ") (pair "cmd" (opVal op "argv" (vStr "")))
              (pair "message" (opVal op "message" (vNone))))
          procs))
      ((and step (= opName "run"))
        (let [res (r/execRunOp! op (runCtx! env) procs (newId) onKeep)]
          (eo (mapRec res.rec fromRun) res.procs)))
      ((and step (= opName "delete"))
        (eo (mapRec (r/execDeleteOp! op (runCtx! env) (newId) snap) fromRun) procs))
      ((and step (= opName "manage"))
        (let [res (r/execManageOp! op (runCtx! env) procs (newId) onKeep)]
          (eo (mapRec res.rec fromRun) res.procs)))
      ((and step (= opName "note")) (eo (execNoteOp op (newId)) procs))
      (else (eo (execRest! op opType opName env newId snap run) procs))))

fn ! execRest! op: (List (Pair String c/KvVal)) opType: String opName: String env: ExecEnv newId: (fn [] -> String) snap: (fn [String] -> Bool) run: (fn [String String] -> t/AslRun) -> (List (Pair String Val))
  (let [step (= opType "step")
        refused (if (and step (or (= opName "write") (= opName "edit"))) (writeCheck op opName env newId) (none))]
    (cond
      ((some? refused) (optionOr refused (list)))
      ((and step (= opName "txn"))
        (mapRec (t/execTxn! (opStr op "form" "") env.owns env.root env.effects newId snap run) fromTxn))
      ((and step (and (= opName "flush") env.writesPersisted))
        (list (vs "id" (newId)) (vs "op" "flush") (vs "status" "ok") (pair "exit" (vInt 0)) (vs "message" "no-op: writes already persisted")))
      ((and step (listContains? (gitOpNames) opName))
        (let [rid (newId)
              ctx (g/makeGitCtx env.root env.mode env.defaultBase (stepTimeout! env) env.readCap (none))]
          (mapRec (g/execGitOp! op ctx rid) fromGit)))
      ((or (= opType "done") (and step (= opName "done")))
        (listAppend
          (list (vs "id" (newId)) (vs "op" "done") (vs "type" "done") (vs "status" "ok") (pair "form" (opVal op "form" (vStr "(:done)"))))
          (if (opTruthy op "commit") (list (pair "commit" (opVal op "commit" (vNone)))) (list))))
      ((and step (= opName "tree"))
        (hideHarnessEntries (aslOp! op env newId snap run) (if (opTruthy op "path") (opStr op "path" "") ".") env.root))
      ((and step (listContains? (aslOpNames) opName)) (aslOp! op env newId snap run))
      ((= opType "evidence")
        (list (vs "id" (newId)) (vs "type" "evidence") (pair "cmd" (opVal op "cmd" (vStr ""))) (pair "exit" (opVal op "exit" (vInt 0)))))
      ((= opType "findings") (list (vs "id" (newId)) (vs "type" "findings") (pair "form" (opVal op "form" (vStr "")))))
      ((= opType "escalate") (list (vs "id" (newId)) (vs "type" "escalate") (pair "form" (opVal op "form" (vStr "")))))
      ((= opType "raw") (list (vs "id" (newId)) (vs "type" "raw") (pair "text" (opVal op "text" (vStr "")))))
      (else (list (vs "id" (newId)) (vs "op" opName) (vs "status" "recorded")))))
