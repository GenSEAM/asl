(module asl-forms/main :x [main runPayload! runPayloadText! workspaceFor! Drive driveOutcome! driveExitCode] :i [(asl-forms/kernel :a k) (asl-forms/wire :a w) (asl-forms/ops :a ops) (asl-coord/claims :a coord)])


(schema Drive (:f lines (List String)) (:f failed (List Bool)) (:f heads (List String)) (:f errs Int64) (:f stop String))


fn envOr! name: String -> String
  (optionOr (envGet name) "")

fn gitTop! probe: String -> String
  (cond
    ((fileExists? (k/joinPath probe ".git")) probe)
    ((= (k/dirName probe) probe) "")
    (else (gitTop! (k/dirName probe))))

fn realOr! p: String -> String
  (resultOr (realPath p) (k/normalizePath p))

fn workspaceRoot! rootArg: String cwd: String -> String
  (cond
    ((not (stringEmpty? rootArg)) (realOr! rootArg))
    ((not (stringEmpty? (envOr! "ASL_ROOT"))) (realOr! (envOr! "ASL_ROOT")))
    (else (let [(top (gitTop! cwd))] (if (stringEmpty? top) cwd top))))

fn toolchainRoot! cwd: String -> String
  (let [(given (envOr! "ROOT_DIR"))
        (binDir (if (stringEmpty? (envOr! "SCRIPT_DIR")) (k/joinPath cwd "bin") (envOr! "SCRIPT_DIR")))]
    (cond
      ((not (stringEmpty? given)) given)
      ((= (k/baseName binDir) "bin") (k/dirName binDir))
      (else cwd)))

fn uniqueRoots items: (List String) acc: (List String) -> (List String)
  (mt (listHead items)
    ((none) (listSortBy (fn [(r String)] -> Int64 (- 0 (stringLength r))) (listReverse acc)))
    ((some r)
      (uniqueRoots (optionOr (listTail items) (list)) (if (or (stringEmpty? r) (= r "/") (listContains? acc r)) acc (cons r acc)))))

fn workspaceFor! rootArg: String -> w/Workspace
  (let [(cwd (realOr! "."))
        (root (workspaceRoot! rootArg cwd))
        (rootDir (toolchainRoot! cwd))
        (tools (resultOr (fileReadString (k/joinPath rootDir "asl/grammar/tools.asn")) ""))]
    (w/Workspace :root root
                 :roots (uniqueRoots (list rootDir (resultOr (realPath rootDir) "") root (resultOr (realPath root) "")) (list))
                 :ops (w/toolOps tools)))

fn readOnly? op: String kw: (Map String String) -> Bool
  (cond
    ((= op "note") (listContains? (list "list" "query") (k/lstripColons (k/kwOr kw "action" "list"))))
    ((= op "fix") (not (listContains? (list "true" "1" "indentation" "heuristic") (k/lstripColons (stringLower (optionOr (mapGet kw "apply") ""))))))
    ((= op "doctor") (not (listContains? (list "true" "1") (k/lstripColons (stringLower (optionOr (mapGet kw "write") ""))))))
    (else (listContains? (list "echo" "read" "query" "q" "tree" "observe" "diff" "check" "chk" "gate" "test" "tools" "help" "intel" "doctor" "ping" "where" "search" "research" "crawl" "lens" "preflush") op)))

fn gateOp? op: String -> Bool
  (listContains? (list "check" "chk" "gate" "test" "preflush" "lens" "audit") op)

fn flushAfterMutation? steps: (List k/ParsedStep) mutating: Bool -> Bool
  (mt (listHead steps)
    ((none) false)
    ((some p)
      (or (and (= p.op "flush") mutating)
          (flushAfterMutation? (optionOr (listTail steps) (list)) (or mutating (not (readOnly? p.op p.kwargs)))))))

fn repeat x: Bool n: Int64 -> (List Bool)
  (map (fn [(i Int64)] -> Bool x) (range 0 n))

fn restFrom s: String i: Int64 -> String
  (optionOr (stringSlice s i (stringLength s)) "")

fn spanChars s: String i: Int64 chars: String -> Int64
  (let [(c (k/charAt s i))]
    (if (and (= (stringLength c) 1) (stringContains? chars c)) (spanChars s (+ i 1) chars) i))

fn quotedEnd s: String i: Int64 -> Int64
  (let [(c (k/charAt s i))]
    (cond
      ((stringEmpty? c) -1)
      ((= c "\"") (+ i 1))
      ((= c "\\") (let [(e (k/charAt s (+ i 1)))] (if (or (stringEmpty? e) (= e "\n")) -1 (quotedEnd s (+ i 2)))))
      (else (quotedEnd s (+ i 1)))))

fn rejectedFields? s: String i: Int64 -> Bool
  (let [(rest (restFrom s i))
        (keyEnd (spanChars s (+ i 2) "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-"))
        (key (optionOr (stringSlice s (+ i 2) keyEnd) ""))
        (valueEnd (if (stringStartsWith? (restFrom s keyEnd) " \"") (quotedEnd s (+ keyEnd 2)) -1))]
    (cond
      ((stringStartsWith? rest " :status \"rejected\"") true)
      ((not (stringStartsWith? rest " :")) false)
      ((or (stringEmpty? key) (= key "status") (stringStartsWith? key "status-")) false)
      ((< valueEnd 0) false)
      (else (rejectedFields? s valueEnd))))

fn rejectedStep? line: String -> Bool
  (let [(s (trimPy line))
        (idEnd (spanChars s 11 "0123456789"))
        (opEnd (if (stringStartsWith? (restFrom s idEnd) " :op \"") (quotedEnd s (+ idEnd 6)) -1))]
    (and (stringStartsWith? s "(:step :id ") (> idEnd 11) (>= opEnd 0) (rejectedFields? s opEnd)))

fn stepFailed? lines: (List String) errs: Int64 -> Bool
  (or (> errs 0) (listAny? rejectedStep? lines))

fn stepErrCount lines: (List String) errs: Int64 -> Int64
  (if (> errs 0) errs (if (stepFailed? lines errs) 1 0))

fn driveExitCode d: Drive -> Int64
  (if (> d.errs 0) 1 0)

fn driveOutcome! root: String rest: (List (Pair String k/ParsedStep)) id: Int64 sequential: Bool d: Drive p: k/ParsedStep out: ops/StepOutcome -> Drive
  (let [(op p.op)
        (n (listLength out.lines))
        (stepFailed (stepFailed? out.lines out.errCount))
        (stepErrs (stepErrCount out.lines out.errCount))
        (stop (if (and sequential stepFailed (or (not (readOnly? op p.kwargs)) (gateOp? op)))
                (str "short-circuit after step " (stringFromInt64 id) " (" (k/escapeAsnVal op) ") failed")
                ""))]
    (drive! root rest id sequential
           (Drive :lines (listAppend d.lines out.lines) :failed (listAppend d.failed (repeat (> out.errCount 0) n))
                  :heads (listAppend d.heads (map (fn [(l String)] -> String op) out.lines)) :errs (+ d.errs stepErrs) :stop stop)))

fn coordinationStep! root: String id: Int64 p: k/ParsedStep -> ops/StepOutcome
  (let [(op p.op)
        (kw p.kwargs)
        (unit (k/kwOr kw "unit" (optionOr (listHead p.args) "")))
        (result (cond
          ((= op "claim") (coord/claim! root unit (coord/parseOwns (k/kwOr kw "owns" ""))))
          ((= op "claims") (coord/claims! root))
          ((= op "release") (coord/release! root unit))
          (else (err "unknown coordination operation"))))]
    (mt result
      ((ok receipt) (ops/StepOutcome :lines (list receipt) :errCount 0))
      ((err receipt) (ops/StepOutcome :lines (list receipt) :errCount 1))))

fn drive! root: String steps: (List (Pair String k/ParsedStep)) idx: Int64 sequential: Bool d: Drive -> Drive
  (mt (listHead steps)
    ((none) d)
    ((some rp)
      (let [(p (pairSecond rp))
            (rest (optionOr (listTail steps) (list)))
            (op p.op)
            (id (+ idx 1))]
        (if (not (stringEmpty? d.stop))
          (drive! root rest id sequential
                 (with d :lines (listAppend d.lines (list (str "  (:step :id " (stringFromInt64 id) " :op \"" (k/escapeAsnVal op) "\" :status \"skipped\" :reason \"" d.stop "\")"))) :failed (listAppend d.failed (list false)) :heads (listAppend d.heads (list op))))
          (let [(out (if (or (= op "claim") (= op "claims") (= op "release"))
                       (coordinationStep! root id p)
                       (ops/runStep! root id (pairFirst rp))))]
            (driveOutcome! root rest id sequential d p out))))))

fn wireAll! ws: w/Workspace lines: (List String) failed: (List Bool) heads: (List String) -> (List String)
  (map (fn [(t (Pair (Pair String Bool) String))] -> String (w/wireReceipt! ws (pairFirst (pairFirst t)) (pairSecond (pairFirst t)) (pairSecond t)))
       (zip (zip lines failed) heads))

fn trimPy s: String -> String
  (let [(n (stringLength s))]
    (cond
      ((and (> n 0) (k/isSpaceChar (k/charAt s 0))) (trimPy (optionOr (stringSlice s 1 n) "")))
      ((and (> n 0) (k/isSpaceChar (k/charAt s (- n 1)))) (trimPy (optionOr (stringSlice s 0 (- n 1)) "")))
      (else s)))

fn runPayloadText! ws: w/Workspace raw: String -> (Pair String Int64)
  (let [(payload (trimPy raw))]
    (cond
      ((stringEmpty? payload) (pair (str (w/wireError "ERR_PARSE" "Empty input; nothing executed" "") "\n") 2))
      ((not (k/isBalanced payload))
        (pair (str (w/wireError "ERR_UNBALANCED" "Unbalanced Dyck-1 input; nothing executed" (str " :depth " (stringFromInt64 (k/countDyck1 (stringTrim payload))))) "\n") 2))
      (else
        (let [(raws (k/extractSteps payload))
              (steps (map k/parseStep raws))]
          (if (or (listEmpty? raws) (listAny? (fn [(p k/ParsedStep)] -> Bool (stringEmpty? p.op)) steps))
            (pair (str (w/wireError "ERR_PARSE" "Empty form or no executable forms in input; nothing executed" "") "\n") 2)
            (let [(sequential (or (k/batchSeq payload) (flushAfterMutation? steps false)))
                  (d (drive! ws.root (zip raws steps) 0 sequential (Drive :lines (list) :failed (list) :heads (list) :errs 0 :stop "")))
                  (wire (wireAll! ws d.lines d.failed d.heads))]
              (pair (str (if (= (listLength wire) 1) (optionOr (listHead wire) "") (str "(:batch " (stringJoin wire " ") ")")) "\n")
                    (driveExitCode d))))))))

fn runPayload! ws: w/Workspace raw: String -> Int64
  (let [(result (runPayloadText! ws raw))]
    (do (println (optionOr (stringSlice (pairFirst result) 0 (- (stringLength (pairFirst result)) 1)) "")) (pairSecond result)))

fn validSession? s: String -> Bool
  (and (not (stringContains? s ".."))
       (!= s ".")
       (listAll? (fn [(c String)] -> Bool (let [(k (charCode c))] (or (and (>= k 48) (<= k 57)) (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)) (= c ".") (= c "_") (= c "-")))) (stringChars s)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(hasRoot (= (optionOr (listHead args) "") "--root"))
        (rootArg (if hasRoot (optionOr (listGet args 1) "") ""))
        (payloadArgs (if hasRoot (listDrop args 2) args))
        (session (envOr! "ASL_SESSION"))]
    (if (and (not (stringEmpty? session)) (not (validSession? session)))
      (do (println "(:error :code ERR_BAD_SESSION :message \"ASL_SESSION must match [A-Za-z0-9._-]+ without ..\")") (ok 2))
      (ok (runPayload! (workspaceFor! rootArg) (stringJoin payloadArgs " ")))))
