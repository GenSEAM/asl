(module asl-target-sh/rules
  :x [Ctx
      main
      rulesMain!
      renderTier
      sessionRules
      toolT0
      toolPublicOps
      toolOps
      toolTopics
      toolTopicText
      toolbeltSkillMd
      toolbeltSkillAsn
      llmsTxt
      privateLeaks
      unenforcedInvariants
      renderBetween
      extractBetween
      wsRulesPath
      workspaceRuleLines!
      insertBeforePack
      combinedRulesText!]
  :i [(asl-target-sh/distrib :a dist)])

(schema Ctx (:f root String) (:f mode String) (:f src String) (:f tools String) (:f home String))

(schema Report (:f rc Int64) (:f lines (List String)))

fn sortUnique xs: (List String) -> (List String)
  (listReverse (fold (fn [acc x] (mt (listHead acc) ((some h) (if (= h x) acc (cons x acc))) ((none) (cons x acc)))) (list) (listSort xs)))

fn spaceJoined xs: (List String) -> String
  (fold (fn [acc x] (str acc x " ")) "" xs)

fn consAll xs: (List String) acc: (List String) -> (List String)
  (fold (fn [a x] (cons x a)) acc xs)

fn wsRulesPath ctx: Ctx -> String
  (str ctx.root "/.asl/rules.asn")

fn workspaceRuleLines! ctx: Ctx -> (List String)
  (let [(f (wsRulesPath ctx))]
    (if (not (dist/isRegular! f))
      (list)
      (let [(lines (dist/splitLines (resultOr (dist/readText! f) "")))]
        (if (and (not (listEmpty? lines)) (stringStartsWith? (optionOr (listHead lines) "") "(:workspaceRules"))
          (optionOr (listTail lines) (list))
          lines))))

fn insertBeforePack languageLines: (List String) wsLines: (List String) -> (List String)
  (listReverse (pairSecond (fold (fn [(acc (Pair Bool (List String))) (l String)] -> (Pair Bool (List String))
                               (let [(done (pairFirst acc)) (out (pairSecond acc))]
                                 (if (and (not done) (stringStartsWith? l "  (:pack "))
                                   (pair true (cons l (consAll wsLines out)))
                                   (pair done (cons l out)))))
                             (pair false (list)) languageLines)))

fn combinedRulesText! ctx: Ctx -> String
  (let [(languageText (resultOr (dist/readText! ctx.src) ""))
        (wsLines (workspaceRuleLines! ctx))]
    (if (listEmpty? wsLines)
      languageText
      (dist/joinLines (insertBeforePack (dist/splitLines languageText) wsLines))))

fn afterSpaces s: String -> Int64
  (let [(bs (stringToBytes s)) (n (bytesLength bs))]
    (countSpaces bs 0 n))

fn countSpaces bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (= (bytesGet bs i) 32)) (countSpaces bs (+ i 1) n) i)

fn spacedPrefix? s: String prefix: String -> Bool
  (let [(i (afterSpaces s))]
    (and (> i 0) (stringStartsWith? (dist/sliceFrom s i) prefix)))

fn classByte? b: Int64 cls: String -> Bool
  (cond
    ((= cls "alpha") (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122))))
    ((= cls "lower") (and (>= b 97) (<= b 122)))
    ((= cls "word") (or (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (and (>= b 48) (<= b 57)) (= b 95) (= b 45)))
    (else false))

fn runEnd bs: Bytes i: Int64 n: Int64 cls: String -> Int64
  (if (and (< i n) (classByte? (bytesGet bs i) cls)) (runEnd bs (+ i 1) n cls) i)

fn litRun s: String lit: String cls: String -> (Option String)
  (litRunFrom s (stringToBytes s) lit cls 0)

fn litRunFrom s: String bs: Bytes lit: String cls: String from: Int64 -> (Option String)
  (mt (stringIndexOf (dist/sliceFrom s from) lit)
    ((none) (none))
    ((some rel)
      (let [(start (+ from rel (stringLength lit)))
            (stop (runEnd bs start (bytesLength bs) cls))]
        (if (> stop start)
          (some (optionOr (stringSlice s start stop) ""))
          (litRunFrom s bs lit cls (+ from rel 1))))))

fn allRuns s: String prefix: String cls: String -> (List String)
  (listReverse (allRunsFrom s (stringToBytes s) prefix cls 0 (list)))

fn allRunsFrom s: String bs: Bytes prefix: String cls: String from: Int64 acc: (List String) -> (List String)
  (mt (stringIndexOf (dist/sliceFrom s from) prefix)
    ((none) acc)
    ((some rel)
      (let [(start (+ from rel (stringLength prefix)))
            (stop (runEnd bs start (bytesLength bs) cls))]
        (allRunsFrom s bs prefix cls stop (cons (optionOr (stringSlice s start stop) "") acc)))))

fn formNames s: String -> (List String)
  (filter (fn [n] (and (not (stringEmpty? n)) (classByte? (charCode (dist/sliceTo n 1)) "alpha"))) (allRuns s "(:" "word"))

fn commandNames s: String -> (List String)
  (filter (fn [n] (not (stringEmpty? n))) (allRuns s "`asl " "lower"))

fn unescapeQuotes s: String -> String
  (stringReplace s "\\\"" "\"")

fn trimTrailingWs s: String -> String
  (let [(n (stringLength s)) (last (dist/sliceFrom s (- n 1)))]
    (if (and (> n 0) (or (= last " ") (= last "\t") (= last "\r") (= last "\n"))) (trimTrailingWs (dist/sliceTo s (- n 1))) s))

fn dropClosingQuote s: String -> String
  (let [(t (trimTrailingWs s))]
    (if (stringEndsWith? t "\"") (dist/sliceTo t (- (stringLength t) 1)) s))

fn dropFinalQuote s: String -> String
  (if (stringEndsWith? s "\"") (dist/sliceTo s (- (stringLength s) 1)) s)

fn trimSpaces s: String -> String
  (let [(a (afterSpaces s)) (t (dist/sliceFrom s a))]
    (if (stringEndsWith? t " ") (trimSpacesEnd t) t))

fn trimSpacesEnd s: String -> String
  (if (stringEndsWith? s " ") (trimSpacesEnd (dist/sliceTo s (- (stringLength s) 1))) s)

fn opHeader line: String cls: String -> (Option String)
  (if (stringStartsWith? line "    (:op :")
    (mt (litRun line ":op :" cls) ((some n) (if (stringStartsWith? line (str "    (:op :" n)) (some n) (none))) ((none) (none)))
    (none))

fn t0Lines tools: String unescape: Bool -> (List String)
  (map (fn [l] (let [(s (dropClosingQuote (dist/sliceFrom l (+ (afterSpaces l) 5))))] (if unescape (unescapeQuotes s) s)))
    (filter (fn [l] (stringStartsWith? (dist/sliceFrom l (afterSpaces l)) ":t0 \"")) (dist/splitLines tools)))

fn toolT0 tools: String -> String
  (dist/joinLines (t0Lines tools true))

(schema OpScan (:f name String) (:f pub Bool) (:f out (List String)))

fn publicNames tools: String -> (List String)
  (let [(flush (fn [(st OpScan)] -> (List String) (if (and (not (stringEmpty? st.name)) st.pub) (cons st.name st.out) st.out)))
        (final (fold (fn [(st OpScan) (l String)] -> OpScan
                       (let [(st1 (mt (opHeader l "word")
                                    ((some n) (OpScan :name n :pub false :out (flush st)))
                                    ((none) st)))]
                         (if (spacedPrefix? l ":public \"") (OpScan :name st1.name :pub true :out st1.out) st1)))
                 (OpScan :name "" :pub false :out (list)) (dist/splitLines tools)))]
    (listReverse (flush final)))

fn toolPublicOps tools: String -> String
  (str "Public ops: " (stringJoin (publicNames tools) ", ") "\n")

fn toolbeltSkillAsn tools: String -> String
  (str "(:skill :name \"asl-toolbelt\" :generatedFrom \"asl/grammar/tools.asn\" :guide \"SKILL.md\"\n  :t0 \""
       (stringJoin (t0Lines tools false) "\n") "\"\n  :ops (\n"
       (dist/joinLines (map (fn [n] (str "    (:" n ")")) (publicNames tools)))
       "  ))\n")

(schema OpDoc (:f name String) (:f params String) (:f doc String) (:f enums String) (:f out (List String)))

fn bracketWords s: String -> String
  (let [(a (mt (stringIndexOf s "[") ((some i) (dist/sliceFrom s (+ i 1))) ((none) s)))
        (b (mt (stringIndexOf a "]") ((some i) (dist/sliceTo a i)) ((none) a)))]
    (trimSpaces b))

fn squeezeSpaces s: String -> String
  (if (stringContains? s "  ") (squeezeSpaces (stringReplace s "  " " ")) s)

fn enumKey line: String -> (Option String)
  (let [(i (afterSpaces line)) (rest (dist/sliceFrom line i))]
    (if (= i 0)
      (none)
      (let [(keys (list "actions" "ops" "subcmds" "roles" "scopes" "lenses" "profiles"))
            (hit (filter (fn [k] (stringStartsWith? rest (str ":" k " ["))) keys))]
        (listHead hit))))

fn flushDoc st: OpDoc -> (List String)
  (if (and (not (stringEmpty? st.name)) (not (stringEmpty? st.doc)))
    (cons (str "- `(:" st.name (if (stringEmpty? st.params) "" (str " " st.params)) ")` " st.doc st.enums) st.out)
    st.out)

fn opDocStep st: OpDoc l: String -> OpDoc
  (let [(st1 (mt (opHeader l "alpha")
               ((some n) (OpDoc :name n :params "" :doc "" :enums "" :out (flushDoc st)))
               ((none) st)))
        (named (not (stringEmpty? st1.name)))
        (st2 (if (and named (spacedPrefix? l ":params ["))
               (OpDoc :name st1.name :params (bracketWords l) :doc st1.doc :enums st1.enums :out st1.out)
               st1))
        (st3 (mt (if named (enumKey l) (none))
               ((some k) (OpDoc :name st2.name :params st2.params :doc st2.doc
                           :enums (str st2.enums " " k ": " (squeezeSpaces (stringReplace (bracketWords l) ":" "")) ".") :out st2.out))
               ((none) st2)))]
    (if (and named (spacedPrefix? l ":public \""))
      (OpDoc :name st3.name :params st3.params :doc (dropFinalQuote (dist/sliceFrom l (+ (afterSpaces l) 9))) :enums st3.enums :out st3.out)
      st3))

fn toolOps tools: String -> String
  (dist/joinLines (listReverse (flushDoc (fold opDocStep (OpDoc :name "" :params "" :doc "" :enums "" :out (list)) (dist/splitLines tools)))))

fn toolTopics tools: String -> String
  (str (stringJoin (fold (fn [acc l] (if (stringStartsWith? l "    (:topic :name :")
                                        (mt (litRun l ":name :" "alpha") ((some t) (listAppend acc (list t))) ((none) acc))
                                        acc))
                     (list) (dist/splitLines tools)) ", ") "\n")

fn dropTopicTail s: String -> String
  (let [(t (trimTrailingWsNoNl s))]
    (cond
      ((stringEndsWith? t "\" :examples (") (dist/sliceTo t (- (stringLength t) 13)))
      ((stringEndsWith? t "\"") (dist/sliceTo t (- (stringLength t) 1)))
      (else s)))

fn trimTrailingWsNoNl s: String -> String
  (let [(n (stringLength s)) (last (dist/sliceFrom s (- n 1)))]
    (if (and (> n 0) (or (= last " ") (= last "\t") (= last "\r"))) (trimTrailingWsNoNl (dist/sliceTo s (- n 1))) s))

fn topicLine prefixLen: Int64 l: String -> String
  (let [(s (dist/sliceFrom l prefixLen))
        (cut (mt (stringIndexOf s "\" :tools \"")
               ((none) (none))
               ((some i) (mt (stringIndexOf (dist/sliceFrom s (+ i 10)) "\"")
                           ((some j) (some (pair i j)))
                           ((none) (none))))))
        (body (mt cut ((some p) (dist/sliceTo s (pairFirst p))) ((none) s)))
        (tail (mt cut ((some p) (optionOr (stringSlice s (+ (pairFirst p) 10) (+ (pairFirst p) 10 (pairSecond p))) "")) ((none) "")))
        (text (unescapeQuotes (dropTopicTail body)))]
    (if (stringEmpty? tail) text (str text " " tail)))

fn toolTopicText tools: String name: String -> String
  (let [(prefix (str "    (:topic :name :" name " :text \""))]
    (dist/joinLines (map (fn [l] (topicLine (stringLength prefix) l)) (filter (fn [l] (stringStartsWith? l prefix)) (dist/splitLines tools)))))

fn expandTemplate tpl: String t0: String ops: String lang: String topics: String -> String
  (dist/joinLines (fold (fn [acc l]
                     (cond
                       ((= l "{{T0}}") (listAppend acc (dist/splitLines t0)))
                       ((= l "{{OPS}}") (listAppend acc (dist/splitLines ops)))
                       ((= l "{{LANGUAGE}}") (listAppend acc (dist/splitLines lang)))
                       (else (listAppend acc (list (if (stringEmpty? topics) l (stringReplace l "{{TOPICS}}" topics)))))))
               (list) (dist/splitLines tpl)))

fn toolbeltSkillMd tpl: String tools: String -> String
  (expandTemplate tpl (toolT0 tools) (toolPublicOps tools) (toolTopicText tools "language") "")

fn llmsTxt tpl: String tools: String -> String
  (let [(topics (optionOr (listHead (dist/splitLines (toolTopics tools))) ""))]
    (dist/joinLines (fold (fn [acc l]
                       (cond
                         ((= l "{{OPS}}") (listAppend acc (dist/splitLines (toolOps tools))))
                         ((= l "{{LANGUAGE}}") (listAppend acc (dist/splitLines (toolTopicText tools "language"))))
                         (else (listAppend acc (list (stringReplace l "{{TOPICS}}" topics))))))
                 (list) (dist/splitLines tpl))))

fn renderTier rules: String tier: String -> String
  (let [(req (tierRank tier))
        (lines (dist/splitLines rules))
        (st (fold (fn [(acc (Pair Bool (List String))) (l String)] -> (Pair Bool (List String))
                    (let [(inc (pairFirst acc)) (out (pairSecond acc))]
                      (cond
                        ((stringStartsWith? l "(:rules") (pair inc (cons l out)))
                        ((stringStartsWith? l "  (:rule :id ")
                          (let [(fc (mt (litRun l ":force :" "lower") ((some f) (str ":" f)) ((none) "")))
                                (take (if (= tier "essential") (stringContains? l ":core true") (<= (forceRank fc) req)))]
                            (pair take (if take (cons l out) out))))
                        ((stringStartsWith? l "  (:pack ") (let [(take (>= req 5))] (pair take (if take (cons l out) out))))
                        ((stringStartsWith? l ")") (pair inc (cons l out)))
                        (else (pair inc (if inc (cons l out) out))))))
              (pair false (list)) lines))
        (body (listReverse (pairSecond st)))]
    (dist/joinLines (if (< req 6) (listAppend body (list ")")) body)))

fn tierRank tier: String -> Int64
  (cond
    ((= tier "essential") 1)
    ((or (= tier "hot") (= tier "affordance")) 2)
    ((or (= tier "orientation") (= tier "t1")) 3)
    ((or (= tier "heuristic") (= tier "t2")) 4)
    ((= tier "pack") 5)
    (else 6))

fn forceRank f: String -> Int64
  (cond
    ((= f ":invariant") 1)
    ((= f ":affordance") 2)
    ((= f ":orientation") 3)
    ((= f ":heuristic") 4)
    (else 5))

(schema Sess (:f h String) (:f d String) (:f e String) (:f out (List String)))

fn sessFlush st: Sess -> (List String)
  (if (stringEmpty? st.h) st.out (cons (str st.h " :do \"" st.d "\"" st.e ")") st.out))

fn sessEmpty out: (List String) -> Sess
  (Sess :h "" :d "" :e "" :out out)

fn quotedAfter l: String key: String -> (Option String)
  (mt (stringIndexOf l key)
    ((none) (none))
    ((some i) (mt (stringIndexOf (dist/sliceFrom l (+ i (stringLength key))) "\"")
                ((some j) (some (optionOr (stringSlice l i (+ i (stringLength key) j 1)) "")))
                ((none) (none)))))

fn sessStep st: Sess l: String -> Sess
  (cond
    ((stringStartsWith? l "  :form ") st)
    ((stringStartsWith? l "  (:rule ") (Sess :h l :d "" :e "" :out (sessFlush st)))
    ((stringStartsWith? l "    :do \"") (with st :d (dropFinalQuote (dist/sliceFrom l 9))))
    ((stringStartsWith? l "    :refute ") st)
    ((stringStartsWith? l "    :enforcedBy ")
      (let [(e1 (mt (quotedAfter l ":enforcedBy \"") ((some m) (str " " m)) ((none) st.e)))
            (e2 (if (stringContains? l ":coAuthor false") (str e1 " :coAuthor false") e1))]
        (with st :e e2)))
    (else (sessEmpty (cons l (sessFlush st)))))

fn sessionRules rules: String -> String
  (let [(lines (dist/splitLines rules))]
    (if (listEmpty? lines)
      ""
      (let [(first (optionOr (listHead lines) ""))
            (head (mt (stringIndexOf first " :basis ") ((some i) (dist/sliceTo first i)) ((none) first)))
            (start (list "  :form \":invariant names the command that exits non-zero on violation; :core true loads every session; :when lists phases, absent means all; the full edition adds each rule's refutation and basis\""
                         (str head " :full \"./scripts/install.sh --tier full\"")))
            (final (fold sessStep (sessEmpty start) (optionOr (listTail lines) (list))))]
        (dist/joinLines (listReverse final.out)))))

(schema Inv (:f id String) (:f force String) (:f cmd Bool) (:f out (List String)))

fn invFlush st: Inv -> (List String)
  (if (and (not (stringEmpty? st.id)) (= st.force "invariant") (not st.cmd)) (cons st.id st.out) st.out)

fn realCommand? l: String -> Bool
  (realCommandFrom l 0)

fn realCommandFrom l: String from: Int64 -> Bool
  (mt (stringIndexOf (dist/sliceFrom l from) ":enforcedBy \"")
    ((none) false)
    ((some rel)
      (let [(start (+ from rel 13))
            (rest (dist/sliceFrom l start))]
        (mt (stringIndexOf rest "\"")
          ((none) false)
          ((some j) (if (nonBlank? (dist/sliceTo rest j)) true (realCommandFrom l (+ from rel 1))))))))

fn nonBlank? s: String -> Bool
  (not (stringEmpty? (stringReplace (stringReplace s " " "") "\t" "")))

fn invStep st: Inv l: String -> Inv
  (let [(st1 (if (or (stringStartsWith? l "  (:rule ") (stringStartsWith? l "  (:pack ")) (Inv :id "" :force "" :cmd false :out (invFlush st)) st))
        (st2 (if (stringStartsWith? l "  (:rule :id ")
               (Inv :id (optionOr (litRun l ":id " "word") "") :force st1.force :cmd st1.cmd :out st1.out)
               st1))
        (named (not (stringEmpty? st2.id)))
        (st3 (mt (if named (litRun l ":force :" "lower") (none))
               ((some f) (Inv :id st2.id :force f :cmd st2.cmd :out st2.out))
               ((none) st2)))]
    (if (and named (realCommand? l)) (Inv :id st3.id :force st3.force :cmd true :out st3.out) st3))

fn unenforcedInvariants rules: String -> (List String)
  (listReverse (invFlush (fold invStep (Inv :id "" :force "" :cmd false :out (list)) (dist/splitLines rules))))

fn privateWords -> (List String)
  (list "asex" "monorepo" "codexLuna" "freeTier" "shadowCritic" "chiefJustice" "teleology" "triMap" "astAddressing" "ramTxn"
        "limitCycle" "workspaceIsolation" "dyck1Purity" "tokenEconomics" "manage_task" "memory ledgers" "SuperviseGate"
        "tests/acceptance" "principles.asn" ".asl/mem" "gpt-6-astra" "gpt-5.6-luna" "llmgateway" "/Users/" "/home/")

fn privateLeaks text: String home: String -> (List String)
  (let [(found (sortUnique (filter (fn [w] (stringContains? text w)) (privateWords))))]
    (if (and (not (stringEmpty? home)) (not (= home "/")) (stringContains? text home)) (listAppend found (list home)) found))

fn extractBetween text: String startLine: String endLine: String -> String
  (dist/joinLines (listReverse (pairSecond (fold (fn [(acc (Pair Int64 (List String))) (l String)] -> (Pair Int64 (List String))
                                              (let [(state (pairFirst acc)) (out (pairSecond acc))]
                                                (cond
                                                  ((= state 0) (if (= l startLine) (pair 1 out) acc))
                                                  ((= state 1) (if (= l endLine) (pair 2 out) (pair 1 (cons l out))))
                                                  (else acc))))
                                        (pair 0 (list)) (dist/splitLines text)))))

fn renderBetween text: String startLine: String endLine: String body: String -> String
  (let [(bodyText (stringJoin (dist/splitLines body) "\n"))]
    (dist/joinLines (listReverse (pairSecond (fold (fn [(acc (Pair Bool (List String))) (l String)] -> (Pair Bool (List String))
                                                (let [(skip (pairFirst acc)) (out (pairSecond acc))]
                                                  (cond
                                                    ((and (not skip) (= l startLine)) (pair true (cons bodyText (cons l out))))
                                                    ((and skip (= l endLine)) (pair false (cons l out)))
                                                    (skip acc)
                                                    (else (pair false (cons l out))))))
                                          (pair false (list)) (dist/splitLines text))))))

fn ! gitOk? ctx: Ctx args: (List String) -> Bool
  (mt (dist/runArgv! (listAppend (list "git" "-C" ctx.root) args) (none) (none) 60000)
    ((ok r) (= r.code 0))
    ((err e) (do (dist/writeErr! (str "rules: git unavailable (" e ")\n")) false)))

fn ! tracked? ctx: Ctx path: String -> Bool
  (let [(prefix (str ctx.root "/"))
        (rel (if (stringStartsWith? path prefix) (dist/sliceFrom path (stringLength prefix)) path))]
    (and (gitOk? ctx (list "rev-parse" "--is-inside-work-tree"))
         (or (gitOk? ctx (list "ls-files" "--error-unmatch" "--" rel))
             (gitOk? ctx (list "cat-file" "-e" (str "HEAD:" rel))))))

fn say rep: Report line: String -> Report
  (with rep :lines (cons line rep.lines))

fn fail rep: Report line: String -> Report
  (Report :rc 1 :lines (cons line rep.lines))

fn skipSurface! ctx: Ctx rep: Report name: String path: String -> Report
  (if (and (= ctx.mode "check") (tracked? ctx path))
    (fail rep (str "  MISSING " name " (tracked surface " path ")"))
    (say rep (str "  skip " name " (missing " path ")")))

fn resolveTarget! path: String -> String
  (mt (realPath path) ((ok p) p) ((err _) path))

fn writeAtomic! path: String text: String -> (Result Unit String)
  (let [(target (resolveTarget! path))
        (dirMade (dirCreate (dist/dirName target)))
        (wantExec (dist/isExecutable! target))
        (tmp (str target "." (stringFromInt64 (procSelf)) ".tmp"))]
    (mt (fileWrite tmp text)
      ((err e) (err e))
      ((ok _)
        (let [(mode (& (dist/modeOf! tmp) 511))
              (want (if wantExec 493 420))
              (chmodded (if (= mode want) (ok ()) (dist/chmodTo! tmp want)))]
          (mt chmodded
            ((err e) (do (pathRemove tmp) (err e)))
            ((ok _) (pathRename tmp target)))))))

fn surfaceRows ctx: Ctx -> (List (List String))
  (list (list "agents-md" (str ctx.root "/AGENTS.md"))
        (list "claude-md" (str ctx.root "/CLAUDE.md")))

fn rowAt row: (List String) i: Int64 -> String
  (optionOr (listGet row i) "")

fn startMarker -> String
  "<!-- ASL_RULES_START -->"

fn endMarker -> String
  "<!-- ASL_RULES_END -->"

fn surfaceStep! ctx: Ctx body: String rep: Report row: (List String) -> Report
  (let [(name (rowAt row 0)) (f (rowAt row 1))]
    (if (not (dist/isRegular! f))
      (skipSurface! ctx rep name f)
      (mt (dist/readText! f)
        ((err e) (fail rep (str "  DRIFT " name " (" f ")")))
        ((ok text)
          (if (= ctx.mode "check")
            (if (= (extractBetween text (startMarker) (endMarker)) body) (say rep (str "  ok   " name)) (fail rep (str "  DRIFT " name " (" f ")")))
            (mt (writeAtomic! f (renderBetween text (startMarker) (endMarker) body))
              ((ok _) (say rep (str "  rendered " name)))
              ((err e) (fail rep (str "  DRIFT " name " (" f ": " e ")")))))))))

fn leakLine label: String leaks: (List String) -> String
  (str "  LEAK " label ": " (spaceJoined leaks))

fn unknownNames! ctx: Ctx text: String -> (List String)
  (let [(ops (filter (fn [n] (not (stringEmpty? n))) (map (fn [l] (optionOr (opHeader l "word") "")) (dist/splitLines (resultOr (dist/readText! ctx.tools) "")))))
        (forms (map (fn [n] (str "(:" n ")")) (filter (fn [n] (not (listContains? ops n))) (sortUnique (formNames text)))))
        (entry (str ctx.root "/bin/asl"))]
    (if (dist/isExecutable! entry)
      (let [(cmds (helpCommands! entry))]
        (listAppend forms (map (fn [n] (str "asl " n)) (filter (fn [n] (not (listContains? cmds n))) (sortUnique (commandNames text))))))
      forms))

fn helpCommands! entry: String -> (List String)
  (let [(outText (mt (dist/runArgv! (list entry "help") (none) (none) 120000) ((ok r) r.out) ((err _) "")))]
    (listReverse (pairSecond (fold (fn [(acc (Pair Bool (List String))) (l String)] -> (Pair Bool (List String))
                                     (let [(c (pairFirst acc)) (out (pairSecond acc))]
                                       (cond
                                         ((stringStartsWith? l "Commands:") (pair true out))
                                         ((and c (stringStartsWith? l "  ") (classByte? (charCode (optionOr (stringSlice l 2 3) " ")) "lower"))
                                           (pair c (cons (optionOr (listHead (filter (fn [w] (not (stringEmpty? w))) (stringSplit (stringReplace l "\t" " ") " "))) "") out)))
                                         ((and c (stringEmpty? l)) (pair false out))
                                         (else acc))))
                               (pair false (list)) (dist/splitLines outText)))))

fn outputRows ctx: Ctx -> (List (List String))
  (let [(r ctx.root)]
    (list (list "toolbelt-skill-md" (str r "/asl/skills/asl-toolbelt/SKILL.md") "skillMd")
          (list "toolbelt-skill-asn" (str r "/asl/skills/asl-toolbelt/skill.asn") "skillAsn")
          (list "llms" (str r "/asl/llms.txt") "llms")))

fn renderOutput! ctx: Ctx which: String -> String
  (let [(tools (resultOr (dist/readText! ctx.tools) ""))
        (r ctx.root)]
    (cond
      ((= which "skillMd") (toolbeltSkillMd (resultOr (dist/readText! (str r "/asl/grammar/toolbeltSkill.md")) "") tools))
      ((= which "skillAsn") (toolbeltSkillAsn tools))
      (else (llmsTxt (resultOr (dist/readText! (str r "/asl/grammar/llmsEntry.md")) "") tools))))

fn outputStep! ctx: Ctx rep: Report row: (List String) -> Report
  (let [(name (rowAt row 0)) (f (rowAt row 1))
        (body (renderOutput! ctx (rowAt row 2)))
        (leaks (privateLeaks body ctx.home))
        (rep1 (if (listEmpty? leaks) rep (fail rep (leakLine name leaks))))
        (unknown (if (stringEndsWith? f ".asn") (list) (unknownNames! ctx body)))
        (rep2 (if (listEmpty? unknown) rep1 (fail rep1 (str "  UNKNOWN " name " names what does not exist: " (spaceJoined unknown)))))]
    (if (= ctx.mode "check")
      (if (= (dist/readText! f) (ok body)) (say rep2 (str "  ok   " name)) (fail rep2 (str "  DRIFT " name " (" f ")")))
      (mt (writeAtomic! f body)
        ((ok _) (say rep2 (str "  rendered " name)))
        ((err e) (fail rep2 (str "  DRIFT " name " (" f ": " e ")"))))))

fn installerCopies ctx: Ctx -> (List String)
  (let [(r ctx.root)]
    (list (str r "/asl/dist/install.sh") (str r "/asl/web/dist/install.sh") (str r "/asl/web/public/install.sh")))

fn emitStep! ctx: Ctx rep: Report -> Report
  (let [(f (str ctx.root "/scripts/install.sh"))
        (want (dist/generateInstallSh))]
    (if (= ctx.mode "check")
      (if (= (dist/readText! f) (ok want)) (say rep (str "  ok   installer-emit (" f ")")) (fail rep (str "  DRIFT installer-emit (" f ")")))
      (mt (writeAtomic! f want)
        ((ok _) (say rep "  rendered installer-emit"))
        ((err e) (fail rep (str "  DRIFT installer-emit (" f ": " e ")"))))))

fn writeInPlace! path: String text: String -> (Result Unit String)
  (let [(existed (dist/isRegular! path))
        (dirMade (dirCreate (dist/dirName path)))]
    (mt (fileWrite path text)
      ((err e) (err e))
      ((ok _) (if existed (ok ()) (dist/chmodTo! path 493)))))

fn copyStep! ctx: Ctx rep: Report f: String -> Report
  (if (not (dist/isRegular! f))
    (skipSurface! ctx rep "installer" f)
    (if (= (dist/readText! f) (dist/readText! (str ctx.root "/scripts/install.sh")))
      (say rep (str "  ok   installer (" f ")"))
      (fail rep (str "  DRIFT installer (" f ")"))))

fn homeSkillDirs home: String -> (List String)
  (map (fn [d] (str home d))
    (list "/.agents/skills" "/.claude/skills" "/.cursor/skills" "/.codeium/windsurf/skills" "/.gemini/skills" "/.gemini/config/skills" "/.factory/skills" "/.codex/skills" "/.gemini/config/plugins/toolbelt/skills"))

fn homeStep! ctx: Ctx rep: Report d: String -> Report
  (let [(skill (str ctx.root "/asl/skills/asl-toolbelt/SKILL.md"))
        (target (str d "/asl-toolbelt/SKILL.md"))]
    (if (not (dist/isRegular! skill))
      rep
      (mt (dirCreate (str d "/asl-toolbelt"))
        ((err e) (do (dist/writeErr! (str "rules: " e "\n")) rep))
        ((ok _) (mt (fileWrite target (resultOr (dist/readText! skill) ""))
                  ((ok _) (say rep (str "  refreshed " target)))
                  ((err e) (do (dist/writeErr! (str "rules: " e "\n")) rep)))))))

fn flushReport! rep: Report -> Bool
  (dist/writeOut! (dist/joinLines (listReverse rep.lines)))

fn rulesMain! ctx: Ctx -> Int64
  (let [(rules (combinedRulesText! ctx))
        (check (= ctx.mode "check"))
        (rep0 (Report :rc 0 :lines (list)))
        (rep1 (if check
                (fold (fn [rep id] (fail rep (str "  UNENFORCED invariant " id " (:force :invariant without an :enforcedBy command)"))) rep0 (unenforcedInvariants rules))
                rep0))
        (body (sessionRules rules))
        (rep2 (fold (fn [rep row] (surfaceStep! ctx body rep row)) rep1 (surfaceRows ctx)))
        (rep3 (fold (fn [rep tpl]
                      (let [(leaks (privateLeaks (resultOr (dist/readText! tpl) "") ctx.home))]
                        (if (listEmpty? leaks) rep (fail rep (leakLine (str "toolbelt-template " tpl) leaks)))))
                    rep2 (list (str ctx.root "/asl/grammar/toolbeltSkill.md") (str ctx.root "/asl/grammar/llmsEntry.md"))))
        (rep4 (fold (fn [rep row] (outputStep! ctx rep row)) rep3 (outputRows ctx)))
        (rep5 (emitStep! ctx rep4))
        (rep6 (if check (fold (fn [rep f] (copyStep! ctx rep f)) rep5 (installerCopies ctx)) rep5))
        (rep7 (if (= ctx.mode "home") (fold (fn [rep d] (homeStep! ctx rep d)) rep6 (homeSkillDirs ctx.home)) rep6))
        (rep8 (if (and check (= rep7.rc 0)) (say rep7 (str "rules: all surfaces identical to " ctx.src)) rep7))]
    (do (flushReport! rep8)
        (if (and check (not (= rep8.rc 0))) (dist/writeErr! "rules: drift detected\n") true)
        rep8.rc))

fn lexiconRender! root: String -> Int64
  (let [(abs (str root "/asl/grammar/lexicon.asn"))
        (src (if (dist/isRegular! abs) abs "asl/grammar/lexicon.asn"))]
    (if (dist/isRegular! src)
      (do (dist/writeOut! (str "lexicon: rendered from " src "\n")) 0)
      (do (dist/writeErr! (str "lexicon: source not found at " src "\n")) 1)))

fn copyInstaller! src: String text: String target: String -> (Result Unit String)
  (let [(dirMade (dirCreate (dist/dirName target)))
        (tmp (str target ".tmp." (stringFromInt64 (procSelf))))]
    (mt (fileWrite tmp text)
      ((err e) (err e))
      ((ok _)
        (mt (dist/chmodTo! tmp (if (dist/isExecutable! src) 493 420))
          ((err e) (do (pathRemove tmp) (err e)))
          ((ok _) (pathRename tmp target))))))

fn renderInstallers! root: String -> Int64
  (let [(src (str root "/scripts/install.sh"))]
    (mt (dist/readText! src)
      ((err e) (do (dist/writeErr! (str "installers: " e "\n")) 1))
      ((ok text)
        (let [(errs (filter err? (map (fn [t] (copyInstaller! src text t)) (installerCopies (Ctx :root root :mode "render" :src "" :tools "" :home "")))))]
          (if (listEmpty? errs)
            (do (dist/writeOut! (str "installers: synchronized byte-identical distribution copies from " src "\n")) 0)
            (do (dist/writeErr! (str "installers: " (stringJoin (map (fn [r] (mt r ((err e) e) ((ok _) ""))) errs) "; ") "\n")) 1))))))

fn nestedDist! dir: String acc: (List String) -> (List String)
  (mt (dirList dir)
    ((err _) acc)
    ((ok names)
      (fold (fn [a n]
              (let [(p (str dir "/" n))
                    (a1 (if (stringContains? p "/dist/dist") (cons p a) a))]
                (if (and (dist/isDir! p) (not (dist/symlink? dir n))) (nestedDist! p a1) a1)))
            acc names)))

fn checkInstallers! root: String -> Int64
  (let [(src (str root "/scripts/install.sh"))
        (srcText (dist/readText! src))
        (e1 (fold (fn [bad t]
                    (cond
                      ((not (dist/isRegular! t)) (do (dist/writeErr! (str "installers: missing required distribution copy: " t "\n")) true))
                      ((not (= (dist/readText! t) srcText)) (do (dist/writeErr! (str "installers: drift detected in " t " (not byte-identical to " src ")\n")) true))
                      (else bad)))
                  false (installerCopies (Ctx :root root :mode "check" :src "" :tools "" :home ""))))
        (nested (listReverse (nestedDist! root (list))))
        (e2 (if (listEmpty? nested) e1 (do (dist/writeErr! (str "installers: nested dist directory detected: " (stringJoin nested "\n") "\n")) true)))
        (ctx (Ctx :root root :mode "check" :src "" :tools "" :home ""))
        (e3 (if (gitOk? ctx (list "rev-parse" "--is-inside-work-tree"))
              (mt (dist/runArgv! (list "git" "-C" root "ls-files" "*install.sh") (none) (none) 60000)
                ((err e) (do (dist/writeErr! (str "installers: git ls-files failed (" e ")\n")) true))
                ((ok r) (fold (fn [bad t]
                                (if (listContains? (list "scripts/install.sh" "asl/dist/install.sh" "asl/web/dist/install.sh" "asl/web/public/install.sh") t)
                                  bad
                                  (do (dist/writeErr! (str "installers: unauthorized or rogue tracked installer found: " t "\n")) true)))
                              e2 (filter (fn [t] (not (stringEmpty? t))) (dist/splitLines r.out)))))
              e2))
        (harness (str root "/tests/acceptance/third_party_toolbelt_harness_test.py"))]
    (if (not (dist/isRegular! harness))
      (do (dist/writeErr! (str "installers: missing required third-party toolbelt harness test: " harness "\n")) 1)
      (let [(ran (dist/runArgv! (list "python3" harness) (none) (none) 3600000))
            (e4 (mt ran
                  ((err e) (do (dist/writeErr! (str "installers: ERR_TOOL_ABSENT python3 (" e ")\n")) true))
                  ((ok r) (do (dist/writeOut! r.out) (dist/writeErr! r.errText)
                              (if (= r.code 0) e3 (do (dist/writeErr! "installers: third-party toolbelt harness acceptance verification failed\n") true))))))]
        (if e4
          1
          (do (dist/writeOut! "installers: verified 4 tracked canonical distribution mirrors are byte-identical and zero rogue installer copies exist\n") 0)))))

fn modeArg args: (List String) i: Int64 -> String
  (optionOr (listGet args i) "")

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (modeArg args 0))
        (flag (modeArg args 1))
        (src (str root "/asl/grammar/rules.asn"))
        (home (optionOr (envGet "HOME") ""))
        (needsRules (listContains? (list "--tier" "--render-rules" "--check-rules" "--render-home") flag))]
    (cond
      ((stringEmpty? root) (do (dist/writeErr! "rules: usage: rules.asl ROOT MODE\n") (ok 2)))
      ((= flag "--render-lexicon") (ok (lexiconRender! root)))
      ((= flag "--render-installers") (ok (renderInstallers! root)))
      ((= flag "--check-installers") (ok (checkInstallers! root)))
      ((not needsRules) (do (dist/writeErr! (str "rules: unknown mode " flag "\n")) (ok 2)))
      ((not (dist/isRegular! src)) (do (dist/writeErr! (str "missing " src "\n")) (ok 2)))
      ((= flag "--tier")
        (let [(t (modeArg args 2))
              (ctx (Ctx :root root :mode "render" :src src :tools "" :home home))]
          (do (dist/writeOut! (renderTier (combinedRulesText! ctx) (if (stringEmpty? t) "essential" t))) (ok 0))))
      (else
        (let [(mode (cond ((= flag "--check-rules") "check") ((= flag "--render-home") "home") (else "render")))]
          (ok (rulesMain! (Ctx :root root :mode mode :src src :tools (str root "/asl/grammar/tools.asn") :home home)))))))
