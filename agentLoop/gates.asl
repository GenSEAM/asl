(module asl/agentLoop/gates
  :x [GateResult PlaceholderHit
      makeGateResult gateCmd gateExit gateStdout gateStderr gateTimeout gateSeconds
      gateVerdicts
      isPassLine isSwallowedExceptLine isSingleLineSwallow
      findSwallowedInAdded scanHunkSwallowed!
      hitFile hitLine hitText placeholderHit
      parseCmdTokens isPathLike candidateGatePaths! missingGatePaths! missingGateFiles!
      vacuousOutsideOwns!
      gateRunScripts gatePartitionFiles gateVacuousMessage gateRevertOutcome gateRevertVerdict]
  :i [(asl/agentLoop/core :a c) (asl/agentLoop/diff :a d)])

enum GateResult
  (gateResultOf cmd: String exitCode: Int64 stdout: String stderr: String timeout: Bool seconds: Int64)

fn makeGateResult cmd: String exitCode: Int64 stdout: String stderr: String timeout: Bool seconds: Int64 -> GateResult
  (gateResultOf cmd exitCode stdout stderr timeout seconds)

fn gateCmd g: GateResult -> String
  (mt g ((gateResultOf c _ _ _ _ _) c))

fn gateExit g: GateResult -> Int64
  (mt g ((gateResultOf _ e _ _ _ _) e))

fn gateStdout g: GateResult -> String
  (mt g ((gateResultOf _ _ o _ _ _) o))

fn gateStderr g: GateResult -> String
  (mt g ((gateResultOf _ _ _ er _ _) er))

fn gateTimeout g: GateResult -> Bool
  (mt g ((gateResultOf _ _ _ _ t _) t))

fn gateSeconds g: GateResult -> Int64
  (mt g ((gateResultOf _ _ _ _ _ s) s))

fn gateVerdicts results: (List GateResult) reverted: Bool -> (List String)
  (map (fn [g] (c/gateVerdict reverted (gateExit g) (gateStdout g) (gateStderr g))) results)

fn stripComment s: String -> String
  (mt (stringIndexOf s "#")
    ((some idx) (stringTrim (optionOr (stringSlice s 0 idx) "")))
    ((none) s))

fn isPassLine line: String -> Bool
  (let [s (stripComment (stringTrim line))]
    (or (= s "pass")
      (or (stringStartsWith? s "pass;")
        (stringStartsWith? s "pass "))))

fn isTargetExcept? target: String -> Bool
  (let [t1 (mt (stringIndexOf target " as ")
             ((some idx) (stringTrim (optionOr (stringSlice target 0 idx) "")))
             ((none) target))
        t2 (if (and (stringContains? t1 ",") (not (stringStartsWith? t1 "(")))
             (mt (stringIndexOf t1 ",")
               ((some cidx) (stringTrim (optionOr (stringSlice t1 0 cidx) "")))
               ((none) t1))
             t1)
        t3 (if (and (stringStartsWith? t2 "(") (stringEndsWith? t2 ")"))
             (let [inner (stringTrim (optionOr (stringSlice t2 1 (- (stringLength t2) 1)) ""))]
               (if (stringEndsWith? inner ",")
                 (stringTrim (optionOr (stringSlice inner 0 (- (stringLength inner) 1)) ""))
                 inner))
             t2)]
    (or (= t3 "Exception") (= t3 "BaseException")))

fn skipWhitespace s: String n: Int64 i: Int64 -> Int64
  (if (and (< i n) (c/isSpace (c/ch s i))) (skipWhitespace s n (+ i 1)) i)

fn isSwallowedExceptLine line: String -> Bool
  (let [s (stripComment (stringTrim line))]
    (if (not (stringEndsWith? s ":"))
      false
      (let [rest (stringTrim (optionOr (stringSlice s 0 (- (stringLength s) 1)) ""))]
        (cond
          ((= rest "except") true)
          ((not (stringStartsWith? rest "except")) false)
          (else
            (let [n (stringLength rest)]
              (if (<= n 6)
                false
                (if (not (c/isSpace (c/ch rest 6)))
                  false
                  (let [j (skipWhitespace rest n 7)]
                    (if (>= j n)
                      false
                      (let [target (stringTrim (optionOr (stringSlice rest j n) ""))]
                        (isTargetExcept? target))))))))))))

fn isSingleLineSwallow line: String -> Bool
  (let [s (stripComment (stringTrim line))]
    (mt (stringIndexOf s ":")
      ((some cidx)
        (let [pre (optionOr (stringSlice s 0 cidx) "")
              post (optionOr (stringSlice s (+ cidx 1) (stringLength s)) "")]
          (if (isPassLine post)
            (isSwallowedExceptLine (str pre ":"))
            false)))
      ((none) false)))

fn findFirstSignificant hunk: (List (Pair Int64 String)) -> (Option String)
  (if (listEmpty? hunk)
    (none)
    (let [item (c/firstOf hunk)
          rest (c/restOf hunk)
          lineText (pairSecond item)
          trimmed (stripComment (stringTrim lineText))]
      (if (stringEmpty? trimmed)
        (findFirstSignificant rest)
        (some trimmed))))

fn scanSwallowedAdded hunk: (List (Pair Int64 String)) acc: (List Int64) -> (List Int64)
  (if (listEmpty? hunk)
    (listReverse acc)
    (let [item (c/firstOf hunk)
          rest (c/restOf hunk)
          lineNo (pairFirst item)
          lineText (pairSecond item)]
      (cond
        ((isSingleLineSwallow lineText)
          (scanSwallowedAdded rest (cons lineNo acc)))
        ((isSwallowedExceptLine lineText)
          (mt (findFirstSignificant rest)
            ((some sig)
              (if (isPassLine sig)
                (scanSwallowedAdded rest (cons lineNo acc))
                (scanSwallowedAdded rest acc)))
            ((none)
              (scanSwallowedAdded rest acc))))
        (else
          (scanSwallowedAdded rest acc)))))

fn findSwallowedInAdded hunkAdded: (List (Pair Int64 String)) -> (List Int64)
  (scanSwallowedAdded hunkAdded (list))

fn zipLinesWithIndex lines: (List String) start: Int64 -> (List (Pair Int64 String))
  (if (listEmpty? lines)
    (list)
    (cons (pair start (c/firstOf lines))
          (zipLinesWithIndex (c/restOf lines) (+ start 1))))

fn sliceHunk lines: (List String) j1: Int64 j2: Int64 -> (List (Pair Int64 String))
  (let [sub (optionOr (listSlice lines j1 j2) (list))]
    (zipLinesWithIndex sub (+ j1 1)))

fn scanCodesLoop codes: (List d/DiffOpcode) newLines: (List String) acc: (List Int64) -> (List Int64)
  (if (listEmpty? codes)
    (listReverse acc)
    (let [op (c/firstOf codes)
          rest (c/restOf codes)
          tag op.tag]
      (if (or (= tag "insert") (= tag "replace"))
        (let [hunk (sliceHunk newLines op.j1 op.j2)
              found (findSwallowedInAdded hunk)]
          (scanCodesLoop rest newLines (listAppend (listReverse found) acc)))
        (scanCodesLoop rest newLines acc))))

fn scanHunkSwallowed! oldLines: (List String) newLines: (List String) -> (List Int64)
  (if (listEmpty? oldLines)
    (findSwallowedInAdded (zipLinesWithIndex newLines 1))
    (let [codes (d/getOpcodes oldLines newLines)]
      (scanCodesLoop codes newLines (list))))

enum PlaceholderHit
  (placeholderHitOf file: String line: Int64 text: String)

fn hitFile h: PlaceholderHit -> String
  (mt h ((placeholderHitOf f _ _) f))

fn hitLine h: PlaceholderHit -> Int64
  (mt h ((placeholderHitOf _ l _) l))

fn hitText h: PlaceholderHit -> String
  (mt h ((placeholderHitOf _ _ t) t))

fn failingOutputs gateResults: (List GateResult) -> String
  (c/joinSep
    (fold (fn [acc g]
            (let [code (gateExit g)]
              (if (and (!= code 0) (!= code -1))
                (cons (str (gateStdout g) "\n" (gateStderr g)) acc)
                acc)))
          (list) (listReverse gateResults))
    "\n")

fn checkFileLines file: String lines: (List String) lineNo: Int64 out: String -> (Option PlaceholderHit)
  (if (listEmpty? lines)
    (none)
    (let [ln (c/firstOf lines)
          rest (c/restOf lines)
          text (stringTrim ln)]
      (if (and (not (stringEmpty? text))
               (and (stringContains? text "assert")
                    (stringContains? out text)))
        (some (placeholderHitOf file lineNo text))
        (checkFileLines file rest (+ lineNo 1) out))))

fn checkFiles files: (List (Pair String String)) out: String -> (Option PlaceholderHit)
  (if (listEmpty? files)
    (none)
    (let [f (c/firstOf files)
          fs (c/restOf files)
          wf (pairFirst f)
          content (pairSecond f)
          lines (stringLines content)]
      (mt (checkFileLines wf lines 1 out)
        ((some hit) (some hit))
        ((none) (checkFiles fs out)))))

fn placeholderHit gateResults: (List GateResult) files: (List (Pair String String)) -> (Option PlaceholderHit)
  (let [failing (filter (fn [g] (and (!= (gateExit g) 0) (!= (gateExit g) -1))) gateResults)]
    (if (listEmpty? failing)
      (none)
      (let [out (failingOutputs gateResults)]
        (checkFiles files out))))

fn scanCmdTokens s: String n: Int64 i: Int64 cur: (List String) inQuote: String escaped: Bool acc: (List String) hasTok: Bool -> (Option (List String))
  (if (>= i n)
    (if (or escaped (!= inQuote ""))
      (none)
      (if hasTok
        (some (listReverse (cons (c/joinAll (listReverse cur)) acc)))
        (some (listReverse acc))))
    (let [ch (c/ch s i)]
      (if escaped
        (scanCmdTokens s n (+ i 1) (cons ch cur) inQuote false acc true)
        (if (= inQuote "'")
          (if (= ch "'")
            (scanCmdTokens s n (+ i 1) cur "" false acc true)
            (scanCmdTokens s n (+ i 1) (cons ch cur) "'" false acc true))
          (if (= inQuote "\"")
            (cond
              ((= ch "\"")
                (scanCmdTokens s n (+ i 1) cur "" false acc true))
              ((= ch "\\")
                (if (< (+ i 1) n)
                  (let [nxt (c/ch s (+ i 1))]
                    (if (or (= nxt "\"") (= nxt "\\"))
                      (scanCmdTokens s n (+ i 2) (cons nxt cur) "\"" false acc true)
                      (scanCmdTokens s n (+ i 1) (cons ch cur) "\"" false acc true)))
                  (scanCmdTokens s n (+ i 1) (cons ch cur) "\"" false acc true)))
              (else
                (scanCmdTokens s n (+ i 1) (cons ch cur) "\"" false acc true)))
            (cond
              ((c/isSpace ch)
                (if hasTok
                  (scanCmdTokens s n (+ i 1) (list) "" false (cons (c/joinAll (listReverse cur)) acc) false)
                  (scanCmdTokens s n (+ i 1) (list) "" false acc false)))
              ((= ch "'")
                (scanCmdTokens s n (+ i 1) cur "'" false acc true))
              ((= ch "\"")
                (scanCmdTokens s n (+ i 1) cur "\"" false acc true))
              ((= ch "\\")
                (scanCmdTokens s n (+ i 1) cur "" true acc true))
              (else
                (scanCmdTokens s n (+ i 1) (cons ch cur) "" false acc true))))))))

fn parseCmdTokens cmd: String -> (Option (List String))
  (scanCmdTokens cmd (stringLength cmd) 0 (list) "" false (list) false)

fn isPathChar c: String -> Bool
  (or (c/isWordByte c) (or (= c ".") (or (= c "/") (= c "-"))))

fn allPathChars s: String n: Int64 i: Int64 -> Bool
  (if (>= i n) true
    (if (isPathChar (c/ch s i)) (allPathChars s n (+ i 1)) false))

fn lastDotIndex s: String i: Int64 best: Int64 -> Int64
  (if (< i 0) best
    (if (= (c/ch s i) ".") i (lastDotIndex s (- i 1) best)))

fn allWordChars s: String n: Int64 i: Int64 -> Bool
  (if (>= i n) true
    (if (c/isWordByte (c/ch s i)) (allWordChars s n (+ i 1)) false))

fn isPathLike tok: String -> Bool
  (let [n (stringLength tok)]
    (if (<= n 2)
      false
      (if (not (allPathChars tok n 0))
        false
        (let [dot (lastDotIndex tok (- n 1) -1)]
          (if (<= dot 0)
            false
            (if (= dot (- n 1))
              false
              (allWordChars tok n (+ dot 1))))))))

fn gatePathParts p: String -> (List String)
  (listReverse
    (fold (fn [acc x]
            (cond
              ((or (= x "") (= x ".")) acc)
              ((= x "..") (if (listEmpty? acc) acc (c/restOf acc)))
              (else (cons x acc))))
      (list) (stringSplit p "/")))

fn gateCommonLen a: (List String) b: (List String) k: Int64 -> Int64
  (if (or (listEmpty? a) (or (listEmpty? b) (!= (c/firstOf a) (c/firstOf b))))
    k
    (gateCommonLen (c/restOf a) (c/restOf b) (+ k 1)))

fn candidatePathsLoop! toks: (List String) rootDir: String acc: (List String) -> (List String)
  (if (listEmpty? toks)
    (listReverse acc)
    (let [tok (c/firstOf toks)
          rest (c/restOf toks)]
      (cond
        ((stringStartsWith? tok "-")
          (candidatePathsLoop! rest rootDir acc))
        ((stringStartsWith? tok "/")
          (let [pp (gatePathParts tok)
                rootAbs (if (stringStartsWith? rootDir "/") rootDir (resultOr (realPath rootDir) rootDir))
                rp (gatePathParts rootAbs)
                common (gateCommonLen pp rp 0)]
            (if (and (!= (stringTrim rootDir) "") (= common (listLength rp)))
              (let [relParts (optionOr (listSlice pp common (listLength pp)) (list))
                    rel (c/joinSep relParts "/")]
                (if (or (listContains? acc rel) (stringEmpty? rel))
                  (candidatePathsLoop! rest rootDir acc)
                  (candidatePathsLoop! rest rootDir (cons rel acc))))
              (candidatePathsLoop! rest rootDir acc))))
        ((isPathLike tok)
          (if (listContains? acc tok)
            (candidatePathsLoop! rest rootDir acc)
            (candidatePathsLoop! rest rootDir (cons tok acc))))
        (else
          (candidatePathsLoop! rest rootDir acc)))))

fn candidateGatePaths! cmd: String rootDir: String -> (List String)
  (mt (parseCmdTokens cmd)
    ((some toks) (candidatePathsLoop! toks rootDir (list)))
    ((none) (list)))

fn missingGatePaths! cmd: String rootDir: String -> (List String)
  (let [candidates (candidateGatePaths! cmd rootDir)]
    (filter (fn [rel]
              (let [full (if (or (= rootDir "") (= rootDir "."))
                           rel
                           (str rootDir "/" rel))]
                (not (fileExists? full))))
            candidates))

fn missingGateFilesLoop! results: (List GateResult) idx: Int64 rootDir: String acc: (List (Pair Int64 String)) -> (List (Pair Int64 String))
  (if (listEmpty? results)
    (listReverse acc)
    (let [g (c/firstOf results)
          rest (c/restOf results)]
      (if (or (= (gateExit g) 0) (or (= (gateExit g) -1) (gateTimeout g)))
        (missingGateFilesLoop! rest (+ idx 1) rootDir acc)
        (let [miss (missingGatePaths! (gateCmd g) rootDir)]
          (mt (listHead miss)
            ((some p) (missingGateFilesLoop! rest (+ idx 1) rootDir (cons (pair idx p) acc)))
            ((none) (missingGateFilesLoop! rest (+ idx 1) rootDir acc)))))))

fn missingGateFiles! gateResults: (List GateResult) rootDir: String -> (List (Pair Int64 String))
  (missingGateFilesLoop! gateResults 1 rootDir (list))

fn ! isFile? p: String -> Bool
  (mt (fileStat p)
    ((ok st) st.isFile)
    ((err _) false))

fn splitWhitespace s: String -> (List String)
  (filter (fn [w] (not (stringEmpty? w)))
    (stringSplit (stringReplace (stringReplace (stringReplace s "\t" " ") "\r" " ") "\n" " ") " "))

fn findFirstFile! words: (List String) rootDir: String -> (Option String)
  (if (listEmpty? words)
    (none)
    (let [w (c/firstOf words)
          ws (c/restOf words)
          full (if (or (= rootDir "") (= rootDir ".")) w (str rootDir "/" w))]
      (if (isFile? full)
        (some w)
        (findFirstFile! ws rootDir))))

fn findVacuousOutside! results: (List GateResult) verdicts: (List String) owns: (List String) rootDir: String -> (Option (Pair String String))
  (if (listEmpty? results)
    (none)
    (let [g (c/firstOf results)
          gs (c/restOf results)
          v (mt (listHead verdicts) ((some vd) vd) ((none) ""))
          restV (mt (listTail verdicts) ((some vt) vt) ((none) (list)))]
      (if (= v "vacuous")
        (let [words (splitWhitespace (gateCmd g))]
          (mt (findFirstFile! words rootDir)
            ((some f)
              (if (not (c/checkOwns f owns rootDir))
                (some (pair (gateCmd g) f))
                (findVacuousOutside! gs restV owns rootDir)))
            ((none)
              (findVacuousOutside! gs restV owns rootDir))))
        (findVacuousOutside! gs restV owns rootDir))))

fn vacuousOutsideOwns! results: (List GateResult) owns: (List String) rootDir: String -> (Option (Pair String String))
  (let [verdicts (gateVerdicts results false)]
    (findVacuousOutside! results verdicts owns rootDir))

fn stripLeadingDotSlash s: String -> String
  (if (stringEmpty? s)
    ""
    (if (or (stringStartsWith? s ".") (stringStartsWith? s "/"))
      (stripLeadingDotSlash (optionOr (stringSlice s 1 (stringLength s)) ""))
      s))

fn stripScriptQuotes t: String -> String
  (if (stringEmpty? t)
    ""
    (if (or (stringStartsWith? t "'") (stringStartsWith? t "\""))
      (stripScriptQuotes (optionOr (stringSlice t 1 (stringLength t)) ""))
      (if (or (stringEndsWith? t "'") (stringEndsWith? t "\""))
        (stripScriptQuotes (optionOr (stringSlice t 0 (- (stringLength t) 1)) ""))
        t)))

fn cleanScriptToken t: String -> String
  (let [t1 (if (and (stringStartsWith? t "'") (stringEndsWith? t "'") (> (stringLength t) 1))
             (optionOr (stringSlice t 1 (- (stringLength t) 1)) "")
             (if (and (stringStartsWith? t "\"") (stringEndsWith? t "\"") (> (stringLength t) 1))
               (optionOr (stringSlice t 1 (- (stringLength t) 1)) "")
               t))]
    (stripLeadingDotSlash (stripScriptQuotes t1)))

fn collectGateScripts words: (List String) acc: (List String) -> (List String)
  (if (listEmpty? words)
    acc
    (let [w (c/firstOf words)
          ws (c/restOf words)
          cleaned (cleanScriptToken w)]
      (if (or (stringEmpty? cleaned) (listContains? acc cleaned))
        (collectGateScripts ws acc)
        (collectGateScripts ws (cons cleaned acc)))))

fn gateRunScripts gates: (List String) -> (List String)
  (let [allScripts (fold (fn [acc g] (collectGateScripts (splitWhitespace g) acc)) (list) gates)]
    (listReverse allScripts))

fn partitionFilesLoop changed: (List String) runScripts: (List String) gateAcc: (List String) implAcc: (List String) -> (Pair (List String) (List String))
  (if (listEmpty? changed)
    (pair (listReverse gateAcc) (listReverse implAcc))
    (let [f (c/firstOf changed)
          fs (c/restOf changed)
          cleanF (stripLeadingDotSlash f)]
      (if (listContains? runScripts cleanF)
        (partitionFilesLoop fs runScripts (cons f gateAcc) implAcc)
        (partitionFilesLoop fs runScripts gateAcc (cons f implAcc)))))

fn gatePartitionFiles changed: (List String) runScripts: (List String) -> (Pair (List String) (List String))
  (partitionFilesLoop changed runScripts (list) (list))

fn vacuousCmdsLoop results: (List GateResult) verdicts: (List String) acc: (List String) -> (List String)
  (if (listEmpty? results)
    (listReverse acc)
    (let [g (c/firstOf results)
          gs (c/restOf results)
          v (mt (listHead verdicts) ((some vd) vd) ((none) ""))
          restV (mt (listTail verdicts) ((some vt) vt) ((none) (list)))]
      (if (= v "vacuous")
        (vacuousCmdsLoop gs restV (cons (gateCmd g) acc))
        (vacuousCmdsLoop gs restV acc))))

fn gateVacuousMessage results: (List GateResult) verdicts: (List String) -> (Option String)
  (let [vacuous (vacuousCmdsLoop results verdicts (list))]
    (if (listEmpty? vacuous)
      (none)
      (some (c/joinSep
              (map (fn [cmd]
                     (str "gate \"" cmd "\" is :vacuous: it reports no (:gate ... :asserts n :failed 0) with n > 0"))
                   vacuous)
              "; "))))

fn gateRevertOutcome g: GateResult -> String
  (if (gateTimeout g)
    (str ":timeout true :seconds " (stringFromInt64 (gateSeconds g)))
    (str ":exit " (stringFromInt64 (gateExit g))))

fn formatDetailLoop results: (List GateResult) verdicts: (List String) acc: (List String) -> String
  (if (listEmpty? results)
    (c/joinSep (listReverse acc) "; ")
    (let [g (c/firstOf results)
          gs (c/restOf results)
          v (mt (listHead verdicts) ((some vd) vd) ((none) ""))
          restV (mt (listTail verdicts) ((some vt) vt) ((none) (list)))
          item (str (gateCmd g) " :" v " " (gateRevertOutcome g))]
      (formatDetailLoop gs restV (cons item acc))))

fn gateRevertVerdict reverted: (List GateResult) verdicts: (List String) impl: (List String) newFiles: (List String) -> (Pair Bool String)
  (let [detail (formatDetailLoop reverted verdicts (list))
        hasFail (listContains? verdicts "failsOnRevert")]
    (if hasFail
      (let [keptStr (if (listEmpty? newFiles) "" (str " (kept " (c/joinSep newFiles ", ") ")"))]
        (pair true (str "revertCheck" keptStr ": " detail)))
      (pair false (str "no gate reports a failed assertion with " (c/joinSep impl ", ") " reverted to HEAD: " detail))))
