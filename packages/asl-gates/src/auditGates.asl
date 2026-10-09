(module asl-gates/auditGates
  :x [Check AuditRun fmtCheck emit passCheck failCheck notComputedCheck perItem
      syntaxCheck! remoteCheck! ssotCheck! emojiCheck! conflictMarkerCheck! coreCheck!
      manifestCheck! groundingCheck! grammarChecks! skillCheck! installerChecks! storageChecks!
      lineHasPlaceholder? staticGateChecks! recordCheck! recordRefused? writeRecord! fullGreenDir cmdGates! cmdGatesAt! spawnFullJob! snapshotFault cmdClosure! cmdSteps! cmdCheck! cmdBuild! cmdConsistency!
      esc isFile! isLink? readText! readBytes! git! gitOk! itos basename dirname]
  :i [(asl-gates/dyck :a dyck)
      (asl-gates/runnerMain :a rm)
      (asl-gates/runnerLedger :a rl)
      (asl-gates/suiteRunner :a sr)
      (asl-gates/auditForeign :a af)
      (asl-proc/coreProcess :a p)])

(schema Check
  (:f id String)
  (:f status String)
  (:f err String)
  (:f ev String)
  (:f n (Option Int64))
  (:f trust (Option String)))

(schema AuditRun
  (:f receipt String)
  (:f summary String)
  (:f exitCode Int64))

fn itos k: Int64 -> String
  (stringFromInt64 k)

fn cut s: String a: Int64 b: Int64 -> String
  (optionOr (stringSlice s a b) "")

fn escByte b: Int64 -> String
  (cond
    ((= b 92) "\\\\")
    ((= b 34) "\\\"")
    ((= b 13) "")
    ((= b 10) "\\n")
    ((and (>= b 32) (<= b 126)) (cut (printable) (- b 32) (- b 31)))
    (else "?"))

fn printable -> String
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

fn escLoop bs: Bytes n: Int64 i: Int64 acc: (List String) -> String
  (if (>= i n)
    (stringJoin (listReverse acc) "")
    (let [(b (bytesGet bs i))]
      (cond
        ((and (>= b 128) (< b 192)) (escLoop bs n (+ i 1) acc))
        ((>= b 192) (escLoop bs n (+ i 1) (cons "?" acc)))
        (else (escLoop bs n (+ i 1) (cons (escByte b) acc))))))

fn esc text: String limit: Int64 -> String
  (let [(bs (stringToBytes text)) (s (escLoop bs (bytesLength bs) 0 (list)))]
    (if (> (stringLength s) limit) (cut s 0 limit) s))

fn fmtCheck c: Check -> String
  (let [(parts0 (list (str "(:check :id " c.id " :status " c.status)))
        (parts1 (mt c.n ((some num) (listAppend parts0 (list (str ":n " (itos num))))) ((none) parts0)))
        (parts2 (mt c.trust ((some t) (listAppend parts1 (list (str ":trust " t)))) ((none) parts1)))
        (parts3 (if (stringEmpty? c.err) parts2 (listAppend parts2 (list (str ":err " c.err)))))
        (parts4 (if (stringEmpty? c.ev) parts3 (listAppend parts3 (list (str ":ev \"" (esc c.ev 400) "\"")))))]
    (str (stringJoin parts4 " ") ")"))

fn passCheck id: String n: (Option Int64) trust: (Option String) -> Check
  (Check :id id :status ":passed" :err "" :ev "" :n n :trust trust)

fn failCheck id: String err: String ev: String n: (Option Int64) trust: (Option String) -> Check
  (Check :id id :status ":failed" :err err :ev ev :n n :trust trust)

fn notComputedCheck id: String ev: String -> Check
  (Check :id id :status ":notComputed" :err "ERR_NOT_COMPUTED" :ev ev :n (none) :trust (none))

fn failedOf checks: (List Check) -> (List Check)
  (filter (fn [(c Check)] -> Bool (!= c.status ":passed")) checks)

fn emit sub: String checks: (List Check) head: String tail: String pending: Bool -> AuditRun
  (let [(failed (failedOf checks))
        (status (if (and pending (listEmpty? failed))
                  ":pending"
                  (if (or (not (listEmpty? failed)) (listEmpty? checks)) ":failed" ":passed")))
        (statusWord (cut status 1 (stringLength status)))
        (parts0 (cons (str "(:audit :sub " sub " :status " status) (if (stringEmpty? head) (list) (list head))))
        (parts1 (listAppend parts0 (map fmtCheck checks)))
        (parts2 (if (stringEmpty? tail) parts1 (listAppend parts1 (list tail))))
        (summary (str "audit " sub ": " statusWord ", " (itos (listLength checks)) " checks, " (itos (listLength failed)) " not passed"
                      (stringJoin (map (fn [(c Check)] -> String (str "; " c.id " " c.err)) (listTake failed 5)) "")))]
    (AuditRun :receipt (str (stringJoin parts2 " ") ")") :summary summary :exitCode (if (= status ":passed") 0 1)))

fn perItem cid: String bad: (List String) err: String n: (Option Int64) -> (List Check)
  (if (listEmpty? bad)
    (list (passCheck cid n (none)))
    (let [(cap 50)
          (taken (listTake bad cap))
          (firstItem (optionOr (listHead taken) ""))
          (restTaken (optionOr (listTail taken) (list)))
          (firstCheck (Check :id cid :status ":failed" :err err :ev firstItem :n n :trust (none)))
          (restChecks (map (fn [(b String)] -> Check (failCheck cid err b (none) (none))) restTaken))
          (baseChecks (cons firstCheck restChecks))]
      (if (> (listLength bad) cap)
        (listAppend baseChecks (list (failCheck cid err (str (itos (- (listLength bad) cap)) " more not listed") (none) (none))))
        baseChecks)))

fn isFile! path: String -> Bool
  (mt (fileReadBytes path) ((ok _) true) ((err _) false))

fn ! isLink? path: String -> Bool
  (mt (p/exec! (p/withTimeout (p/cmd "/bin/sh" (list "-c" "test -L \"$1\"" "sh" path)) 5000))
    ((err _) false)
    ((ok o) (= o.exitCode 0)))

fn readText! path: String -> (Option String)
  (mt (fileReadString path) ((ok s) (some s)) ((err _) (none)))

fn readBytes! path: String -> (Option Bytes)
  (mt (fileReadBytes path) ((ok b) (some b)) ((err _) (none)))

fn basename path: String -> String
  (let [(parts (stringSplit path "/"))]
    (optionOr (listLast parts) path))

fn dirname path: String -> String
  (let [(parts (stringSplit path "/"))]
    (if (<= (listLength parts) 1)
      "."
      (stringJoin (listTake parts (- (listLength parts) 1)) "/")))

fn gitCmd root: String args: (List String) -> p/ProcessCmd
  (p/withTimeout (p/withCwd (p/cmd "git" args) root) 600000)

fn git! root: String args: (List String) -> (Result String String)
  (mt (p/exec! (gitCmd root args))
    ((err _) (err (str "git " (stringJoin args " ") " could not run")))
    ((ok o) (if (= o.exitCode 0) (ok (stringTrim o.stdout)) (err (str "git " (stringJoin args " ") ": " (stringTrim o.stderr))))))

fn gitOk! root: String args: (List String) -> Bool
  (mt (p/exec! (gitCmd root args))
    ((ok o) (= o.exitCode 0))
    ((err _) false))

fn trackedRoot! root: String args: (List String) -> (List String)
  (let [(cmdArgs (listAppend (list "ls-files" "-z" "--") args))]
    (mt (p/exec! (gitCmd root cmdArgs))
      ((err _) (list))
      ((ok o) (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit o.stdout "\x00")))))

fn negativeSegment? p: String -> Bool
  (or (stringStartsWith? p "invalid/") (or (stringEndsWith? p "/invalid") (or (stringContains? p "/invalid/") (= p "invalid"))))

fn linkRelative path: String -> String
  (if (stringStartsWith? path "./") (cut path 2 (stringLength path)) path)

fn symlinks! root: String -> (Option (List String))
  (mt (p/exec! (p/withTimeout (p/withCwd (p/cmd "find" (list "." "-type" "l" "-print0")) root) 600000))
    ((err _) (none))
    ((ok o)
     (if (!= o.exitCode 0)
       (none)
       (some (map linkRelative
                  (filter (fn [(path String)] -> Bool (stringStartsWith? path "./"))
                          (stringSplit o.stdout "\x00")))))))

fn syntaxCheck! root: String cid: String -> (List Check)
  (let [(files (filter (fn [(p String)] -> Bool (not (negativeSegment? p))) (trackedRoot! root (list "*.asl" "*.asn"))))
        (links (symlinks! root))
        (checked (fold (fn [(acc (Pair (List String) (List String))) (p String)] -> (Pair (List String) (List String))
                         (let [(full (str root "/" p))]
                           (if (mt links ((some paths) (listContains? paths p)) ((none) (isLink? full)))
                             acc
                             (mt (readBytes! full)
                               ((none) (pair (pairFirst acc) (cons (str p " is tracked but missing from the worktree") (pairSecond acc))))
                               ((some bs)
                                (mt (dyck/check bs (not (stringEndsWith? p ".asl")))
                                  ((none) acc)
                                  ((some pairRes)
                                   (pair (cons (str p " byte " (itos (pairFirst pairRes)) " " (pairSecond pairRes)) (pairFirst acc)) (pairSecond acc)))))))))
                       (pair (list) (list))
                       files))
        (bad (listReverse (pairFirst checked)))
        (missing (listReverse (pairSecond checked)))
        (mainChecks (perItem cid bad "ERR_UNBALANCED" (some (listLength files))))]
    (if (listEmpty? missing)
      mainChecks
      (listAppend mainChecks (perItem cid missing "ERR_TRACKED_MISSING" (none)))))

fn remoteCheck! root: String -> Check
  (let [(remotes (mt (git! root (list "remote"))
                   ((ok out) (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit out "\n")))
                   ((err _) (list))))]
    (if (listEmpty? remotes)
      (passCheck "workspaceIsolation" (none) (none))
      (failCheck "workspaceIsolation" "ERR_WORKSPACE_REMOTE" (str "git remote lists " (stringJoin remotes " ")) (none) (none))))

fn ssotCheck! root: String -> Check
  (let [(installPath (str root "/scripts/install.sh"))]
    (if (not (isFile! installPath))
      (failCheck "ssot" "ERR_SSOT_DRIFT" "exit 127; " (none) (none))
      (mt (p/exec! (p/withTimeout (p/withCwd (p/cmd installPath (list "--check-rules")) root) 600000))
        ((err _) (failCheck "ssot" "ERR_SSOT_DRIFT" "exit 127; " (none) (none)))
        ((ok o)
         (let [(lines (stringSplit (str o.stdout o.stderr) "\n"))
               (drift (fold (fn [(acc (List String)) (l String)] -> (List String)
                              (if (stringContains? l "DRIFT")
                                (cons (stringTrim l) acc)
                                acc))
                            (list)
                            lines))]
           (if (and (= o.exitCode 0) (listEmpty? drift))
             (passCheck "ssot" (none) (none))
             (failCheck "ssot" "ERR_SSOT_DRIFT" (str "exit " (itos o.exitCode) "; " (stringJoin (listTake (listReverse drift) 6) "; ")) (none) (none))))))))

fn hasEmoji? line: String -> Bool
  (let [(bs (stringToBytes line)) (n (bytesLength bs))]
    (emojiLoop bs n 0))

fn emojiLoop bs: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n)
    false
    (let [(b (bytesGet bs i))]
      (cond
        ((and (= b 239) (< (+ i 2) n))
         (if (and (= (bytesGet bs (+ i 1)) 184) (= (bytesGet bs (+ i 2)) 143))
           true
           (emojiLoop bs n (+ i 3))))
        ((and (= b 240) (< (+ i 3) n))
         (let [(b1 (bytesGet bs (+ i 1))) (b2 (bytesGet bs (+ i 2)))]
           (if (and (= b1 159) (and (>= b2 128) (<= b2 171)))
             true
             (emojiLoop bs n (+ i 4)))))
        ((>= b 240) (emojiLoop bs n (+ i 4)))
        ((>= b 224) (emojiLoop bs n (+ i 3)))
        ((>= b 192) (emojiLoop bs n (+ i 2)))
        (else (emojiLoop bs n (+ i 1))))))

fn fileHasEmoji! root: String p: String -> (Option String)
  (let [(full (str root "/" p))]
    (mt (readText! full)
      ((none) (none))
      ((some text)
       (let [(lines (stringSplit text "\n"))]
         (findEmojiLine p lines 1)))))

fn findEmojiLine p: String lines: (List String) n: Int64 -> (Option String)
  (mt (listHead lines)
    ((none) (none))
    ((some l)
     (if (hasEmoji? l)
       (some (str p " line " (itos n)))
       (findEmojiLine p (optionOr (listTail lines) (list)) (+ n 1)))))

fn emojiCheck! root: String -> (List Check)
  (let [(files (trackedRoot! root (list "*.asn" "*.asl")))
        (bad (fold (fn [(acc (List String)) (p String)] -> (List String)
                     (mt (fileHasEmoji! root p)
                       ((some b) (cons b acc))
                       ((none) acc)))
                   (list)
                   files))]
    (perItem "c2Emoji" (listReverse bad) "ERR_EMOJI" (some (listLength files))))

fn checkConflictLines p: String lines: (List String) n: Int64 state: Int64 start: Int64 fence: Bool isMd: Bool acc: (List String) -> (List String)
  (mt (listHead lines)
    ((none)
     (if (!= state 0)
       (cons (str "unresolved merge conflict in " p " line " (itos start) " unterminated marker") acc)
       acc))
    ((some line)
     (let [(rest (optionOr (listTail lines) (list)))
           (trimmed (stringTrim line))
           (newFence (if (and isMd (stringStartsWith? trimmed "```")) (not fence) fence))]
       (if newFence
         (checkConflictLines p rest (+ n 1) state start newFence isMd acc)
         (cond
           ((and (= state 0) (stringStartsWith? line "<<<<<<< "))
            (checkConflictLines p rest (+ n 1) 1 n newFence isMd acc))
           ((and (= state 1) (= line "======="))
            (checkConflictLines p rest (+ n 1) 2 start newFence isMd acc))
           ((and (= state 2) (stringStartsWith? line ">>>>>>> "))
            (checkConflictLines p rest (+ n 1) 0 0 newFence isMd
                                (cons (str "unresolved merge conflict in " p " lines " (itos start) "-" (itos n)) acc)))
           ((or (stringStartsWith? line ">>>>>>> ") (and (= state 0) (= line "=======")))
            (checkConflictLines p rest (+ n 1) state start newFence isMd
                                (cons (str "unresolved merge conflict in " p " line " (itos n) " stray marker") acc)))
           (else
            (checkConflictLines p rest (+ n 1) state start newFence isMd acc)))))))

fn fileConflictMarkers! root: String p: String -> (List String)
  (let [(full (str root "/" p))]
    (mt (readBytes! full)
      ((none) (list))
      ((some bs)
       (let [(n (bytesLength bs))
             (hasNull (nullInHead bs (min n 8192) 0))]
         (if hasNull
           (list)
           (mt (readText! full)
             ((none) (list))
             ((some text)
              (let [(lines (stringSplit text "\n"))
                    (isMd (stringEndsWith? p ".md"))]
                (listReverse (checkConflictLines p lines 1 0 0 false isMd (list)))))))))))

fn nullInHead bs: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n)
    false
    (if (= (bytesGet bs i) 0) true (nullInHead bs n (+ i 1))))

fn conflictMarkerCheck! root: String -> (List Check)
  (let [(files (trackedRoot! root (list)))
        (bad (fold (fn [(acc (List String)) (p String)] -> (List String)
                     (listAppend acc (fileConflictMarkers! root p)))
                   (list)
                   files))]
    (perItem "conflictMarkers" bad "ERR_CONFLICT_MARKER" (some (listLength files))))

fn coreCheck! root: String cid: String args: (List String) -> Check
  (let [(corePath (str root "/bin/asl-core"))]
    (if (not (isFile! corePath))
      (notComputedCheck cid "bin/asl-core absent")
      (mt (p/exec! (p/withTimeout (p/withCwd (p/cmd corePath args) root) 600000))
        ((err _) (failCheck cid "ERR_CORE_FAILED" (str "bin/asl-core " (stringJoin args " ") " could not run") (none) (some ":unverifiedCore")))
        ((ok o)
         (if (= o.exitCode 0)
           (passCheck cid (none) (some ":unverifiedCore"))
           (failCheck cid "ERR_CORE_FAILED" (str "bin/asl-core " (stringJoin args " ") " exit " (itos o.exitCode)) (none) (some ":unverifiedCore")))))))

fn manifestCheck! root: String -> (List Check)
  (let [(files (filter (fn [(p String)] -> Bool (= (basename p) "manifest.asn")) (trackedRoot! root (list "*manifest.asn"))))
        (checked (fold (fn [(acc (Pair (List String) (List String))) (p String)] -> (Pair (List String) (List String))
                         (let [(full (str root "/" p))]
                           (mt (readBytes! full)
                             ((none) (pair (pairFirst acc) (cons (str p " is tracked but missing from the worktree") (pairSecond acc))))
                             ((some bs)
                              (mt (dyck/check bs true)
                                ((none) acc)
                                ((some pairRes)
                                 (pair (cons (str p " byte " (itos (pairFirst pairRes)) " " (pairSecond pairRes)) (pairFirst acc)) (pairSecond acc))))))))
                       (pair (list) (list))
                       files))
        (bad (listReverse (pairFirst checked)))
        (missing (listReverse (pairSecond checked)))
        (parseErrors (pairSecond (rm/packagesAt root)))
        (checks0 (perItem "gate1Manifests" bad "ERR_MANIFEST" (some (listLength files))))
        (checks1 (if (listEmpty? missing) checks0 (listAppend checks0 (perItem "gate1Manifests" missing "ERR_TRACKED_MISSING" (none)))))]
    (if (listEmpty? parseErrors)
      checks1
      (listAppend checks1 (perItem "gate1Dependencies" parseErrors "ERR_MANIFEST_PARSE" (none)))))

fn groundingCheck! root: String -> Check
  (let [(claimsPath (str root "/asl/bench/publishedClaims.asn"))
        (ssotPath (str root "/asl/packages/asl-gates/src/siteClaims.asl"))]
    (if (or (not (isFile! claimsPath)) (not (isFile! ssotPath)))
      (failCheck "gate3Grounding" "ERR_UNGROUNDED" "claims registry or siteClaims.asl missing" (none) (none))
      (let [(published (optionOr (readText! claimsPath) ""))
            (ssot (optionOr (readText! ssotPath) ""))
            (metrics (extractMatches published ":metric \"" "\""))
            (registry (extractRegistry ssot))]
        (if (listEmpty? registry)
          (failCheck "gate3Grounding" "ERR_UNGROUNDED" "standardClaims registry not parseable in siteClaims.asl" (none) (none))
          (let [(bad0 (map (fn [(x String)] -> String (str "ungrounded metric " x))
                           (filter (fn [(x String)] -> Bool (not (listContains? registry x))) metrics)))
                (bad1 (listAppend bad0 (map (fn [(x String)] -> String (str "registry metric missing " x))
                                            (filter (fn [(x String)] -> Bool (not (listContains? metrics x))) registry))))
                (bad2 (if (< (listLength registry) 12) (cons (str "standardClaims implausibly small (" (itos (listLength registry)) ")") bad1) bad1))
                (bad (if (listEmpty? metrics) (cons "no :metric claims in asl/bench/publishedClaims.asn" bad2) bad2))]
            (if (listEmpty? bad)
              (passCheck "gate3Grounding" (some (listLength metrics)) (none))
              (failCheck "gate3Grounding" "ERR_UNGROUNDED" (stringJoin (listTake bad 8) "; ") (some (listLength metrics)) (none))))))))

fn stringIndexOfFrom s: String needle: String from: Int64 -> (Option Int64)
  (let [(n (stringLength s))]
    (if (or (< from 0) (> from n))
      (none)
      (mt (stringSlice s from n)
        ((none) (none))
        ((some sliced)
         (mt (stringIndexOf sliced needle)
           ((none) (none))
           ((some idx) (some (+ from idx))))))))

fn extractMatches text: String prefix: String suffix: String -> (List String)
  (let [(k (stringLength prefix))]
    (findMatchesLoop text prefix suffix k 0 (list)))

fn findMatchesLoop text: String prefix: String suffix: String k: Int64 i: Int64 acc: (List String) -> (List String)
  (mt (stringIndexOfFrom text prefix i)
    ((none) (listReverse acc))
    ((some start)
     (let [(vStart (+ start k))]
       (mt (stringIndexOfFrom text suffix vStart)
         ((none) (listReverse acc))
         ((some end)
          (let [(val (cut text vStart end))]
            (findMatchesLoop text prefix suffix k (+ end 1) (cons val acc))))))))

fn extractRegistry text: String -> (List String)
  (let [(marker "fn standardClaims")]
    (mt (stringIndexOf text marker)
      ((none) (list))
      ((some idx)
       (mt (stringIndexOfFrom text "(list" idx)
         ((none) (list))
         ((some lStart)
          (mt (stringIndexOfFrom text ")" lStart)
            ((none) (list))
            ((some lEnd)
             (let [(body (cut text (+ lStart 5) lEnd))]
               (extractMatches body "\"" "\"")))))))))

fn grammarChecks! root: String -> (List Check)
  (let [(path (str root "/asl/grammar/grammar.asn"))]
    (if (not (isFile! path))
      (list (failCheck "gate6GrammarCount" "ERR_GRAMMAR_COUNT" "asl/grammar/grammar.asn absent" (none) (none)))
      (let [(text (optionOr (readText! path) ""))
            (symCount (listLength (extractMatches text "(:sym " " ")))
            (over (findOverBudget text))]
        (list
          (if (= symCount 48)
            (passCheck "gate6GrammarCount" (some symCount) (none))
            (failCheck "gate6GrammarCount" "ERR_GRAMMAR_COUNT" (str "asl/grammar/grammar.asn declares " (itos symCount) " symbols, bin/asl-core requires 48") (some symCount) (none)))
          (if (listEmpty? over)
            (passCheck "gate6C4" (none) (none))
            (failCheck "gate6C4" "ERR_C4" (str "over-budget symbols without :rationale in asl/grammar/grammar.asn: " (stringJoin (listTake over 8) " ")) (none) (none)))))))

fn findOverBudget text: String -> (List String)
  (let [(symBlocks (extractMatches text "(:sym :name \"" ")"))]
    (fold (fn [(acc (List String)) (blk String)] -> (List String)
            (let [(nameEnd (optionOr (stringIndexOf blk "\"") 0))
                  (name (cut blk 0 nameEnd))
                  (tokIdx (stringIndexOf blk ":tokens "))]
              (mt tokIdx
                ((none) acc)
                ((some ti)
                 (let [(rest (cut blk (+ ti 8) (stringLength blk)))
                       (sp (optionOr (stringIndexOf rest " ") (stringLength rest)))
                       (tokStr (cut rest 0 sp))
                       (tokVal (optionOr (stringToInt64 tokStr) 0))]
                   (if (and (> tokVal 2) (not (stringContains? blk ":rationale")))
                     (cons name acc)
                     acc))))))
          (list)
          symBlocks))

fn skillCheck! root: String -> (List Check)
  (let [(files (filter (fn [(p String)] -> Bool (= (basename p) "SKILL.md")) (trackedRoot! root (list "*SKILL.md"))))
        (bad (fold (fn [(acc (List String)) (p String)] -> (List String)
                     (let [(full (str root "/" p))]
                       (mt (readText! full)
                         ((none) acc)
                         ((some text)
                          (if (validFrontmatter? text) acc (cons p acc))))))
                   (list)
                   files))]
    (perItem "gate7Skill" (map (fn [(b String)] -> String (str "missing YAML frontmatter with name and description " b)) (listReverse bad)) "ERR_SKILL" (some (listLength files))))

fn validFrontmatter? text: String -> Bool
  (let [(lines (stringSplit text "\n"))]
    (if (or (listEmpty? lines) (!= (stringTrim (optionOr (listHead lines) "")) "---"))
      false
      (findFrontmatterEnd (optionOr (listTail lines) (list)) false false)))

fn findFrontmatterEnd lines: (List String) hasName: Bool hasDesc: Bool -> Bool
  (mt (listHead lines)
    ((none) false)
    ((some l)
     (let [(t (stringTrim l))]
       (if (= t "---")
         (and hasName hasDesc)
         (let [(nName (or hasName (stringStartsWith? t "name:")))
               (nDesc (or hasDesc (stringStartsWith? t "description:")))]
           (findFrontmatterEnd (optionOr (listTail lines) (list)) nName nDesc))))))

fn installerChecks! root: String -> (List Check)
  (let [(rulesPath (str root "/asl/grammar/rules.asn"))
        (srcPath (str root "/scripts/install.sh"))
        (rulesOk (and (isFile! rulesPath) (> (bytesLength (optionOr (readBytes! rulesPath) (bytesAlloc 0))) 0)))
        (c1 (if rulesOk (passCheck "gate7Rules" (none) (none)) (failCheck "gate7Rules" "ERR_RULES" "asl/grammar/rules.asn unreadable or empty" (none) (none))))
        (srcOk (isFile! srcPath))
        (c2 (if srcOk (passCheck "gate7Installer" (none) (none)) (failCheck "gate7Installer" "ERR_INSTALLER_DRIFT" "scripts/install.sh absent" (none) (none))))]
    (if (not srcOk)
      (list c1 c2)
      (let [(srcBytes (optionOr (readBytes! srcPath) (bytesAlloc 0)))
            (copies (list "asl/dist/install.sh" "asl/web/dist/install.sh" "asl/web/public/install.sh"))
            (drift (fold (fn [(acc (List String)) (p String)] -> (List String)
                           (let [(full (str root "/" p))]
                             (mt (readBytes! full)
                               ((none) (cons p acc))
                               ((some cb) (if (= cb srcBytes) acc (cons p acc))))))
                         (list)
                         copies))
            (c3 (if (listEmpty? drift)
                  (passCheck "gate7InstallerIdentity" (some (listLength copies)) (none))
                  (failCheck "gate7InstallerIdentity" "ERR_INSTALLER_DRIFT" (str "differs from scripts/install.sh: " (stringJoin (listReverse drift) " ")) (some (listLength copies)) (none))))]
        (list c1 c2 c3))))

fn storageChecks! root: String -> (List Check)
  (let [(files (trackedRoot! root (list ".asl/mem/tasks/*.asn")))
        (bad (fold (fn [(acc (List String)) (p String)] -> (List String)
                     (let [(full (str root "/" p))]
                       (mt (readText! full)
                         ((none) acc)
                         ((some text)
                          (listAppend acc (findPlaceholderLines p (stringSplit text "\n") 1))))))
                   (list)
                   files))]
    (perItem "receiptDigests" (map (fn [(b String)] -> String (str "placeholder :digest in " b)) bad) "ERR_PLACEHOLDER_DIGEST" (some (listLength files))))

fn findPlaceholderLines p: String lines: (List String) n: Int64 -> (List String)
  (mt (listHead lines)
    ((none) (list))
    ((some l)
     (let [(rest (findPlaceholderLines p (optionOr (listTail lines) (list)) (+ n 1)))]
       (if (lineHasPlaceholder? l)
         (cons (str p " line " (itos n)) rest)
         rest))))

fn lineHasPlaceholder? l: String -> Bool
  (or (stringContains? l ":digest \"placeholder\"")
      (or (stringContains? l ":digest \"PLACEHOLDER\"")
          (or (stringContains? l ":digest \"TODO\"")
              (or (stringContains? l ":digest \"\"")
                  (hasZeroDigest? l)))))

fn hasZeroDigest? line: String -> Bool
  (zeroDigestFrom? line 0)

fn zeroDigestFrom? line: String from: Int64 -> Bool
  (mt (stringIndexOfFrom line ":digest \"" from)
    ((none) false)
    ((some marker) (let [(start (+ marker 9))]
      (mt (stringIndexOfFrom line "\"" start)
        ((none) false)
        ((some end) (let [(digest (cut line start end))
                          (bytes (stringToBytes digest))]
          (or (and (>= (stringLength digest) 16)
                   (allZeroBytes bytes (bytesLength bytes) 0))
              (zeroDigestFrom? line (+ end 1)))))))))

fn allZeroBytes bytes: Bytes n: Int64 i: Int64 -> Bool
  (if (>= i n) true
    (and (= (bytesGet bytes i) 48) (allZeroBytes bytes n (+ i 1))))

fn staticGateChecks! root: String -> (List Check)
  (let [(c1 (manifestCheck! root))
        (c2 (syntaxCheck! root "gate2Syntax"))
        (c3 (list (groundingCheck! root)))
        (fa (af/foreignAudit! root false ""))
        (c4 (mt fa ((ok a) (map (fn [(fc af/Check)] -> Check (Check :id fc.id :status fc.status :err fc.err :ev fc.ev :n fc.n :trust (none))) a.checks)) ((err _) (list (failCheck "gate4Foreign" "ERR_FOREIGN" "foreign audit error" (none) (none))))))
        (c5 (list (remoteCheck! root)))
        (c6 (grammarChecks! root))
        (c7 (emojiCheck! root))
        (c8 (skillCheck! root))
        (c9 (installerChecks! root))
        (c10 (list (coreCheck! root "core67" (list "audit" "gates" "--only=6,7"))))]
    (listAppend c1 (listAppend c2 (listAppend c3 (listAppend c4 (listAppend c5 (listAppend c6 (listAppend c7 (listAppend c8 (listAppend c9 c10))))))))))

fn ! recordRefused? root: String scope: String -> Bool
  (let [(status (resultOr (git! root (list "status" "--porcelain")) ""))
        (tree (resultOr (git! root (list "write-tree")) ""))
        (head (resultOr (git! root (list "rev-parse" "HEAD^{tree}")) ""))]
    (or (!= scope ":full") (or (not (stringEmpty? status)) (or (stringEmpty? tree) (!= tree head)))))

fn recordCheck! root: String scope: String -> Check
  (if (recordRefused? root scope)
    (failCheck "fullGreenRecord" "ERR_RECORD_REFUSED" "record needs --full, a clean worktree and write-tree equal to HEAD^{tree}" (none) (none))
    (passCheck "fullGreenRecord" (none) (none)))

fn fullGreenDir -> String
  ".asl/mem/benchmarks/fullGreen/"

fn recordLine! root: String r: sr/SuiteResult -> (Result String String)
  (let [(path r.suite)]
    (mt (fileReadBytes (str root "/" path))
      ((err e) (err (str "cannot read suite " path ": " e)))
      ((ok bs)
       (let [(nul "\u0000")
             (key (str path nul (bytesSha256 bs) nul (itos r.asserts) nul (itos r.refutes) nul r.cause))]
         (ok (str "  (:suite :path \"" path "\" :digest \"" (bytesSha256 (stringToBytes key)) "\")\n"))))))

fn recordBody! root: String results: (List sr/SuiteResult) -> (Result String String)
  (fold (fn [(acc (Result String String)) (r sr/SuiteResult)] -> (Result String String)
          (mt acc
            ((err e) (err e))
            ((ok text) (resultMap (recordLine! root r) (fn [(l String)] -> String (str text l))))))
        (ok "")
        (listSortBy (fn [(r sr/SuiteResult)] -> String r.suite) results))

fn writeRecord! root: String results: (List sr/SuiteResult) -> (Result String String)
  (mt (git! root (list "rev-parse" "HEAD"))
    ((err e) (err e))
    ((ok head)
     (mt (git! root (list "rev-parse" "HEAD^{tree}"))
       ((err e) (err e))
       ((ok tree)
        (mt (recordBody! root results)
          ((err e) (err e))
          ((ok lines)
           (let [(body (str lines ")\n"))
                 (rel (str (fullGreenDir) head ".asn"))
                 (first (str "(:fullGreen :v 1 :sha \"" head "\" :tree \"" tree "\" :origin :runner :suites " (itos (listLength results))
                             " :receiptDigest \"" (bytesSha256 (stringToBytes body)) "\"\n"))]
             (mt (dirCreate (str root "/" (fullGreenDir)))
               ((err e) (err (str "cannot create " (fullGreenDir) ": " e)))
               ((ok _)
                (mt (fileWrite (str root "/" rel) (stringToBytes (str first body)))
                  ((err e) (err (str "cannot write " rel ": " e)))
                  ((ok _) (ok rel))))))))))))

fn tier name: String cs: (List Check) -> Check
  (let [(bad (filter (fn [(c Check)] -> Bool (!= c.status ":passed")) cs))
        (anyNotComputed (listAny? (fn [(c Check)] -> Bool (= c.status ":notComputed")) cs))
        (capName (str "tier" (stringUpper (cut name 0 1)) (cut name 1 (stringLength name))))]
    (if anyNotComputed
      (notComputedCheck capName (stringJoin (map (fn [(c Check)] -> String c.ev) cs) "; "))
      (if (listEmpty? bad)
        (passCheck capName (none) (none))
        (failCheck capName "ERR_TIER_FAILED" (esc (stringJoin (map (fn [(c Check)] -> String (str c.id " " c.err " " c.ev)) bad) "; ") 400) (none) (none)))))

fn jobsValue jobs: (List String) -> (Option String)
  (mt (listLast jobs)
    ((none) (none))
    ((some j) (some (cut j 7 (stringLength j)))))

fn shellQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn spawnFullJob! root: String argv: (List String) -> (Result String String)
  (let [(id (str "auditGates" (stringFromInt64 (nowNs))))
        (forwarded (filter (fn [(a String)] -> Bool (!= a "--sync")) argv))
        (jobCmd (str "cd " (shellQuote root) " && bin/asl audit gates --sync"
                     (if (listEmpty? forwarded) "" (str " " (stringJoin forwarded " ")))))
        (form (str "(:manage :action :spawn :id \"" id "\" :cmd \"" (esc jobCmd 5000) "\")"))
        (aslBin (str root "/bin/asl"))]
    (mt (p/exec! (p/withTimeout (p/withCwd (p/cmd aslBin (list form)) root) 60000))
      ((err e) (err (str "manage spawn failed: " e)))
      ((ok o)
       (if (and (= o.exitCode 0) (stringContains? o.stdout ":status :ok"))
         (ok id)
         (let [(out (str o.stdout o.stderr)) (n (stringLength out))]
           (err (if (> n 300) (cut out (- n 300) n) out)))))))

fn suiteGateChecks! id: String results: (List sr/SuiteResult) ledger: (List rl/LedgerEntry) root: String -> (List Check)
  (let [(rec (rl/reconcile! results ledger root))
        (bad (map (fn [(c rl/ReconcileCheck)] -> Check
                    (failCheck id c.err (str c.suite ": " c.ev) (none) (none))) rec.checks))]
    (if (listEmpty? results)
      (list (failCheck id "ERR_NO_SUITES" "no suite discovered in scope" (none) (none)))
      (if (listEmpty? bad) (list (passCheck id (some (listLength results)) (none))) bad)))

fn snapshotFault id: String f: sr/Fault -> Check
  (if (= f.kind "terminated")
    (failCheck "internal" "ERR_AUDIT_INTERNAL" f.msg (none) (none))
    (failCheck id "ERR_RUNNER" (str f.kind ": " f.msg) (none) (none)))

fn countAsserts results: (List sr/SuiteResult) -> Int64
  (fold (fn [(n Int64) (r sr/SuiteResult)] -> Int64 (+ n r.asserts)) 0 results)

fn countRefutes results: (List sr/SuiteResult) -> Int64
  (fold (fn [(n Int64) (r sr/SuiteResult)] -> Int64 (+ n r.refutes)) 0 results)

fn countDeclared results: (List sr/SuiteResult) -> Int64
  (fold (fn [(n Int64) (r sr/SuiteResult)] -> Int64 (+ n r.declared)) 0 results)

fn countPassed results: (List sr/SuiteResult) -> Int64
  (fold (fn [(n Int64) (r sr/SuiteResult)] -> Int64 (if (= r.cause "OK") (+ n 1) n)) 0 results)

fn closureTests! root: String -> Check
  (let [(basePair (rm/chooseBaseAt! root))
        (baseOpt (pairFirst basePair))
        (problems (pairSecond basePair))]
    (mt baseOpt
      ((none) (notComputedCheck "tierTests" "suite scope is :full; run audit gates --full"))
      ((some base)
       (if (not (listEmpty? problems))
         (notComputedCheck "tierTests" (str "suite scope is :full; run audit gates --full: " (stringJoin (listTake problems 4) "; ")))
         (let [(affected (rm/affectedAt! root base.sha))
               (scope (pairFirst affected))
               (info (pairSecond affected))
               (suites (pairFirst info))
               (why (pairSecond info))]
           (if (= scope ":full")
             (notComputedCheck "tierTests" (str "suite scope is :full; run audit gates --full: " why))
             (mt (sr/snapRun root suites (sr/workerCount (none)) 0)
               ((err f) (tier "tests" (list (snapshotFault "tests" f))))
               ((ok snap)
                (mt (rl/ledgerAt root (none))
                  ((err e) (tier "tests" (list (failCheck "tests" "ERR_LEDGER_READ" e (none) (none)))))
                  ((ok ledger) (tier "tests" (suiteGateChecks! "tests" snap.results ledger root))))))))))))

fn cmdSteps! root: String argv: (List String) -> AuditRun
  (emit "steps" (storageChecks! root) "" "" false)

fn cmdBuild! root: String argv: (List String) -> AuditRun
  (let [(aslBin (str root "/bin/asl"))]
    (if (not (isFile! aslBin))
      (emit "build" (list (failCheck "build" "ERR_BUILD_FAILED" (str "[Errno 2] No such file or directory: '" aslBin "'") (none) (none))) "" "" false)
      (mt (p/exec! (p/withTimeout (p/withCwd (p/cmd aslBin (cons "build" argv)) root) 600000))
        ((err _) (emit "build" (list (failCheck "build" "ERR_BUILD_FAILED" (str "[Errno 2] No such file or directory: '" aslBin "'") (none) (none))) "" "" false))
        ((ok o)
         (let [(rc o.exitCode)
               (sOut o.stdout)
               (sErr o.stderr)
               (out (stringTrim (if (and (not (stringEmpty? sOut)) (not (stringEmpty? sErr)))
                                  (str sOut "\n" sErr)
                                  (str sOut sErr))))]
           (if (= rc 0)
             (emit "build" (list (passCheck "build" (none) (none))) "" "" false)
             (emit "build" (list (failCheck "build" "ERR_BUILD_FAILED" out (none) (none))) "" "" false)))))))

fn checkOneFile! root: String a: String -> (List Check)
  (let [(full (if (stringStartsWith? a "/") a (str root "/" a)))]
    (if (not (isFile! full))
      (list (failCheck "file" "ERR_NO_FILE" a (none) (none)))
      (let [(bs (optionOr (readBytes! full) (bytesAlloc 0)))
            (res (dyck/check bs (not (stringEndsWith? a ".asl"))))
            (cBal (mt res
                    ((some pairRes) (failCheck "balance" "ERR_UNBALANCED" (str a " byte " (itos (pairFirst pairRes)) " " (pairSecond pairRes)) (none) (none)))
                    ((none) (passCheck "balance" (none) (none)))))
            (cCore (coreCheck! root "coreCheck" (list "check" full)))
            (cCoreFixed (Check :id cCore.id :status cCore.status :err cCore.err :ev (str a " " cCore.ev) :n cCore.n :trust cCore.trust))]
        (list cBal cCoreFixed))))

fn cmdCheck! root: String argv: (List String) -> AuditRun
  (if (listEmpty? argv)
    (let [(checks (listAppend (syntaxCheck! root "syntax") (list (coreCheck! root "coreCheck" (list "check")))))]
      (emit "check" checks "" "" false))
    (let [(checks (fold (fn [(acc (List Check)) (a String)] -> (List Check)
                          (listAppend acc (checkOneFile! root a)))
                        (list)
                        argv))]
      (emit "check" checks "" "" false)))

fn cmdConsistency! root: String argv: (List String) -> AuditRun
  (let [(c1 (syntaxCheck! root "syntax"))
        (c2 (list (remoteCheck! root) (ssotCheck! root)))
        (c3 (emojiCheck! root))
        (c4 (conflictMarkerCheck! root))
        (c5 (list (coreCheck! root "coreConsistency" (list "audit" "consistency"))))
        (checks (listAppend c1 (listAppend c2 (listAppend c3 (listAppend c4 c5)))))]
    (emit "consistency" checks "" "" false))

fn cmdClosure! root: String argv: (List String) -> AuditRun
  (let [(tSyntax (tier "syntax" (syntaxCheck! root "syntax")))
        (tTypes (notComputedCheck "tierTypes" "no type-check audit is computed"))
        (tBounds (tier "bounds" (optionOr (listTail (grammarChecks! root)) (list))))
        (tClaims (tier "claims" (list (groundingCheck! root))))
        (tRules (tier "rules" (list (ssotCheck! root) (remoteCheck! root))))
        (tTests (closureTests! root))
        (tStorage (tier "storage" (storageChecks! root)))
        (tWasm (notComputedCheck "tierWasm" "no checker exists for tier wasm"))
        (tStage2 (notComputedCheck "tierStage2" "no checker exists for tier stage2"))
        (tMesh (notComputedCheck "tierMesh" "no checker exists for tier mesh"))
        (tiers (list tSyntax tTypes tTests tBounds tClaims tWasm tStage2 tMesh tStorage tRules))]
    (emit "closure" tiers "" "" false))

fn validJobs? a: String -> Bool
  (let [(parts (stringSplit a "="))]
    (if (!= (listLength parts) 2)
      false
      (mt (stringToInt64 (optionOr (listLast parts) ""))
        ((none) false)
        ((some n) (>= n 1)))))

fn unverifiedBaseProblem? p: String -> Bool
  (or (stringContains? p "re-hash")
      (or (stringContains? p "named for") (stringContains? p ":tree")))

fn cmdGatesAt! root: String argv: (List String) inRunner: Bool -> AuditRun
  (let [(full (listContains? argv "--full"))
        (record (listContains? argv "--record"))
        (sync (listContains? argv "--sync"))
        (static (listContains? argv "--static"))
        (jobs (filter (fn [(a String)] -> Bool (stringStartsWith? a "--jobs=")) argv))
        (knownFlags (list "--full" "--record" "--sync" "--static"))
        (unknown0 (filter (fn [(a String)] -> Bool (and (not (listContains? knownFlags a)) (not (stringStartsWith? a "--jobs=")))) argv))
        (hasConflict (and static (or full (or record sync))))
        (unknown (if hasConflict (cons "--static with --full, --record or --sync" unknown0) unknown0))
        (badJobs (listAny? (fn [(a String)] -> Bool (not (validJobs? a))) jobs))]
    (if (or (not (listEmpty? unknown)) badJobs)
      (let [(reason (str "unknown argument " (stringJoin (listAppend unknown jobs) " ")))]
        (emit "gates" (list (failCheck "usage" "ERR_USAGE" reason (none) (none))) "" "" false))
      (if (and inRunner (not static))
        (emit "gates" (list (failCheck "gate5Suites" "ERR_NESTED" "audit gates called from inside a runner snapshot; suites are not run" (none) (none))) "" "" false)
        (let [(staticChecks (staticGateChecks! root))]
        (if static
          (emit "gates" staticChecks ":scope :static :suitesRun :no" "" false)
          (let [(basePair (rm/chooseBaseAt! root))
                (baseOpt (pairFirst basePair))
                (problems (pairSecond basePair))
                (baseFailed (or (and (not full) (not (listEmpty? problems)))
                                (listAny? unverifiedBaseProblem? problems)))
                (checks (if baseFailed (listAppend staticChecks (list (failCheck "fullGreenBase" "ERR_BASE_UNVERIFIED" (stringJoin (listTake problems 6) "; ") (none) (none)))) staticChecks))
                (baseSha (mt baseOpt ((some r) r.sha) ((none) "none")))
                (allSuites (resultOr (sr/discover root (list)) (list)))
                (baseLedger (if (none? baseOpt) (list) (resultOr (rl/ledgerAt root (some baseSha)) (list))))
                (ledger (resultOr (rl/ledgerAt root (none)) (list)))
                (deltaForm (rl/delta baseLedger ledger))
                (excluded (resultOr (sr/getExcludedForm root) ""))
                (staticRed (listAny? (fn [(c Check)] -> Bool (!= c.status ":passed")) checks))
                (scopeInfo (if (or full (none? baseOpt) (not (listEmpty? problems)))
                             (pair ":full" (pair allSuites (if full "--full" (if (none? baseOpt) "no verified fullGreen base" "base unverified"))))
                             (rm/affectedAt! root baseSha)))
                (scope (pairFirst scopeInfo))
                (scopeData (pairSecond scopeInfo))
                (suites (pairFirst scopeData))
                (reason (pairSecond scopeData))
                (head (str ":scope " scope " :base \"" baseSha "\" :scopeReason \"" (esc reason 400) "\""))
                (skipRed (and staticRed (= scope ":full") (not sync)))]
            (cond
              (skipRed
               (emit "gates" checks (str head " :suites " (itos (listLength suites)) " :suitesRun :no") (str deltaForm " " excluded) false))
              ((and (= scope ":full") (not full) (not sync))
               (emit "gates" checks (str head " :suites " (itos (listLength suites)) " :suitesRun :no :needs \"--full\"") (str deltaForm " " excluded) true))
              ((and (= scope ":full") full (not sync))
               (mt (spawnFullJob! root argv)
                 ((err e)
                  (emit "gates" (listAppend checks (list (failCheck "gate5Job" "ERR_JOB_SPAWN" e (none) (none)))) head (str deltaForm " " excluded) false))
                 ((ok job)
                  (emit "gates" checks (str head " :job \"" job "\" :suites " (itos (listLength suites))) (str deltaForm " " excluded) true))))
              (else
               (mt (sr/snapRun root suites (sr/workerCount (jobsValue jobs)) 0)
                 ((err f)
                  (if (= f.kind "busy")
                    (emit "gates" (list (failCheck "runnerLock" "ERR_BUSY" f.msg (none) (none))) "" "" false)
                    (emit "gates" (listAppend checks (list (snapshotFault "gate5Suites" f))) head (str deltaForm " " excluded) false)))
                 ((ok snap)
                  (mt (rl/ledgerAt root (none))
                    ((err e)
                     (emit "gates" (listAppend checks (list (failCheck "knownRed" "ERR_LEDGER_READ" e (none) (none)))) head (str deltaForm " " excluded) false))
                    ((ok liveLedger)
                     (let [(results snap.results)
                           (reconciled (rl/reconcile! results liveLedger root))
                           (runChecks (suiteGateChecks! "gate5Suites" results liveLedger root))
                           (refused (and record (recordRefused? root scope)))
                           (recordChecks (if refused (list (recordCheck! root scope)) (list)))
                           (allChecks (listAppend checks (listAppend runChecks recordChecks)))
                           (allPassed (listAll? (fn [(c Check)] -> Bool (= c.status ":passed")) allChecks))
                           (written (if (and record (not refused) allPassed) (writeRecord! root results) (ok "")))
                           (finalChecks (mt written
                                          ((err e) (listAppend allChecks (list (failCheck "fullGreenRecord" "ERR_RECORD_WRITE" (esc e 400) (none) (none)))))
                                          ((ok _) allChecks)))
                           (recordedForm (mt written
                                           ((ok rel) (if (stringEmpty? rel) "" (str " :recorded \"" rel "\"")))
                                           ((err _) "")))
                           (runHead (str head " :suites " (itos (listLength results))
                                          " :notEvaluated " (itos reconciled.notEvaluated)
                                          " :knownRedHeld " (itos reconciled.held)
                                          " :executedAsserts " (itos (countAsserts results))
                                          " :executedRefutes " (itos (countRefutes results))
                                          " :wallMs " (itos snap.wallMs) recordedForm))]
               (emit "gates" finalChecks runHead (str deltaForm " " excluded) false))))))))))))))

fn cmdGates! root: String argv: (List String) -> AuditRun
  (cmdGatesAt! root argv (not (stringEmpty? (optionOr (envGet "ASL_IN_RUNNER") ""))))
