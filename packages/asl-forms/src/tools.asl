(module asl-forms/tools
  :x [ToolOp Registry loadRegistry! toolsStep! helpStep! visibleOps!]
  :i [(asl-forms/kernel :a k) (asl-forms/search :a s) (asl-forms/similarity :a sm) (asl-proc/coreProcess :a cp) (asl-checker/types :a ty)])


(schema ToolOp (:f name String) (:f scope String) (:f public String) (:f doc String) (:f form String) (:f paramsRaw String) (:f paramsCompact String) (:f paramsSummary String) (:f examples (List String)) (:f errors (List String)) (:f related (List String)))

(schema Registry (:f topics (List (Pair String String))) (:f ops (Map String ToolOp)) (:f order (List String)))


fn slice t: String a: Int64 e: Int64 -> String
  (optionOr (stringSlice t (max 0 a) (min (stringLength t) e)) "")

fn byteAt b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (>= i 0) (< i n)) (bytesGet b i) -1)

fn wordB? c: Int64 -> Bool
  (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)) (and (>= c 48) (<= c 57)) (= c 95) (>= c 128))

fn nameB? c: Int64 -> Bool
  (or (and (>= c 65) (<= c 90)) (and (>= c 97) (<= c 122)) (and (>= c 48) (<= c 57)) (= c 95) (= c 45))

fn wsB? c: Int64 -> Bool
  (or (= c 32) (and (>= c 9) (<= c 13)) (and (>= c 28) (<= c 31)))

fn skipWs b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (wsB? (bytesGet b i))) (skipWs b n (+ i 1)) i)

fn startsAt? b: Bytes n: Int64 i: Int64 lit: String -> Bool
  (let [(lb (stringToBytes lit)) (ln (stringLength lit))]
    (and (>= i 0) (<= (+ i ln) n) (listAll? (fn [(j Int64)] -> Bool (= (bytesGet b (+ i j)) (bytesGet lb j))) (range 0 ln))))

fn balancedEnd b: Bytes n: Int64 i: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (if (>= i n)
    -1
    (let [(c (bytesGet b i))]
      (cond
        (inStr (cond (esc (balancedEnd b n (+ i 1) depth true false)) ((= c 92) (balancedEnd b n (+ i 1) depth true true)) ((= c 34) (balancedEnd b n (+ i 1) depth false false)) (else (balancedEnd b n (+ i 1) depth true false))))
        ((= c 34) (balancedEnd b n (+ i 1) depth true false))
        ((= c 40) (balancedEnd b n (+ i 1) (+ depth 1) false false))
        ((= c 41) (if (= (- depth 1) 0) (+ i 1) (balancedEnd b n (+ i 1) (- depth 1) false false)))
        (else (balancedEnd b n (+ i 1) depth false false)))))

fn searchFrom t: String b: Bytes n: Int64 i: Int64 m: (fn [Int64] -> Int64) -> (Pair Int64 Int64)
  (if (>= i n)
    (pair -1 -1)
    (let [(e (m i))] (if (>= e 0) (pair i e) (searchFrom t b n (+ i 1) m))))

fn wsRun b: Bytes n: Int64 i: Int64 -> Int64
  (let [(j (skipWs b n i))] (if (> j i) j -1))

fn nameBoundaryEnd b: Bytes n: Int64 a: Int64 -> Int64
  (let [(e (nameRun b n a))]
    (backToBoundary b n a e))

fn nameRun b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (nameB? (bytesGet b i))) (nameRun b n (+ i 1)) i)

fn backToBoundary b: Bytes n: Int64 a: Int64 e: Int64 -> Int64
  (cond
    ((<= e a) -1)
    ((not (= (wordB? (bytesGet b (- e 1))) (and (< e n) (wordB? (bytesGet b e))))) e)
    (else (backToBoundary b n a (- e 1))))

fn keyThenWs b: Bytes n: Int64 i: Int64 key: String -> Int64
  (if (startsAt? b n i key) (wsRun b n (+ i (stringLength key))) -1)

fn keyThenOpen b: Bytes n: Int64 i: Int64 key: String -> Int64
  (if (startsAt? b n i key) (let [(j (skipWs b n (+ i (stringLength key))))] (if (= (byteAt b n j) 40) j -1)) -1)

fn stringLitEnd b: Bytes n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) -1)
    ((= (bytesGet b j) 34) j)
    ((= (bytesGet b j) 92) (if (or (>= (+ j 1) n) (= (bytesGet b (+ j 1)) 10)) -1 (stringLitEnd b n (+ j 2))))
    (else (stringLitEnd b n (+ j 1))))

fn unescapeTwo s: String -> String
  (stringReplace (stringReplace s "\\\\" "\\") "\\\"" "\"")

fn keyString t: String key: String -> (Option String)
  (let [(b (stringToBytes t)) (n (stringLength t))
        (hit (searchFrom t b n 0 (fn [(i Int64)] -> Int64 (let [(v (keyThenWs b n i key))] (if (and (>= v 0) (= (byteAt b n v) 34)) (let [(e (stringLitEnd b n (+ v 1)))] (if (< e 0) -1 (+ e 1))) -1)))))]
    (if (< (pairFirst hit) 0)
      (none)
      (let [(v (keyThenWs b n (pairFirst hit) key))] (some (unescapeTwo (slice t (+ v 1) (- (pairSecond hit) 1)))))))

fn keyBlock t: String key: String -> String
  (let [(b (stringToBytes t)) (n (stringLength t))
        (hit (searchFrom t b n 0 (fn [(i Int64)] -> Int64 (keyThenOpen b n i key))))]
    (if (< (pairFirst hit) 0)
      ""
      (let [(e (balancedEnd b n (pairSecond hit) 0 false false))] (if (< e 0) "" (slice t (pairSecond hit) e)))))

fn keyTokens t: String key: String -> (List String)
  (let [(b (stringToBytes t)) (n (stringLength t))
        (hit (searchFrom t b n 0 (fn [(i Int64)] -> Int64 (let [(o (keyThenOpen b n i key))] (if (< o 0) -1 (let [(c (findByte b n (+ o 1) 41))] (if (< c 0) -1 (+ c 1))))))))]
    (if (< (pairFirst hit) 0)
      (list)
      (let [(o (keyThenOpen b n (pairFirst hit) key))]
        (map k/lstripColons (s/pySplitWs (slice t (+ o 1) (- (pairSecond hit) 1)))))))

fn findByte b: Bytes n: Int64 i: Int64 c: Int64 -> Int64
  (cond ((>= i n) -1) ((= (bytesGet b i) c) i) (else (findByte b n (+ i 1) c)))

fn scopeOf t: String -> String
  (let [(b (stringToBytes t)) (n (stringLength t))
        (hit (searchFrom t b n 0 (fn [(i Int64)] -> Int64
               (let [(v (keyThenWs b n i ":scope"))]
                 (if (< v 0) -1 (fold (fn [(best Int64) (w String)] -> Int64 (if (and (< best 0) (startsAt? b n v w) (not (wordB? (byteAt b n (+ v (stringLength w)))))) (+ v (stringLength w)) best)) -1 (list "any" "asl" "toolchain")))))))]
    (if (< (pairFirst hit) 0) "toolchain" (slice t (keyThenWs b n (pairFirst hit) ":scope") (pairSecond hit))))

fn literals t: String b: Bytes n: Int64 i: Int64 acc: (List String) -> (List String)
  (let [(q (findByte b n i 34))]
    (if (< q 0)
      (listReverse acc)
      (let [(e (stringLitEnd b n (+ q 1)))]
        (if (< e 0) (literals t b n (+ q 1) acc) (literals t b n (+ e 1) (cons (unescapeTwo (slice t (+ q 1) e)) acc))))))

fn defaultToken t: String -> String
  (let [(b (stringToBytes t)) (n (stringLength t))
        (tok (fn [(v Int64)] -> Int64
               (let [(c (byteAt b n v))]
                 (cond
                   ((and (= c 34) (>= (stringLitEnd b n (+ v 1)) 0)) (+ (stringLitEnd b n (+ v 1)) 1))
                   ((and (= c 58) (nameB? (byteAt b n (+ v 1)))) (nameRun b n (+ v 1)))
                   ((and (>= c 48) (<= c 57)) (digitRun b n v))
                   ((startsAt? b n v "true") (+ v 4))
                   ((startsAt? b n v "false") (+ v 5))
                   ((= c 40) (let [(e (findByte b n (+ v 1) 41))] (if (< e 0) -1 (+ e 1))))
                   (else -1)))))
        (hit (searchFrom t b n 0 (fn [(i Int64)] -> Int64 (let [(v (keyThenWs b n i ":default"))] (if (< v 0) -1 (tok v))))))]
    (if (< (pairFirst hit) 0) "" (slice t (keyThenWs b n (pairFirst hit) ":default") (pairSecond hit))))

fn digitRun b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (>= (bytesGet b i) 48) (<= (bytesGet b i) 57)) (digitRun b n (+ i 1)) i)

fn typeOf t: String -> String
  (let [(b (stringToBytes t)) (n (stringLength t))
        (hit (searchFrom t b n 0 (fn [(i Int64)] -> Int64 (let [(v (keyThenWs b n i ":type"))] (if (and (>= v 0) (nameB? (byteAt b n v))) (nameRun b n v) -1)))))]
    (if (< (pairFirst hit) 0) "str" (slice t (keyThenWs b n (pairFirst hit) ":type") (pairSecond hit))))

fn reqTrue? t: String -> Bool
  (let [(b (stringToBytes t)) (n (stringLength t))]
    (>= (pairFirst (searchFrom t b n 0 (fn [(i Int64)] -> Int64 (let [(v (keyThenWs b n i ":req"))] (if (and (>= v 0) (startsAt? b n v "true") (not (wordB? (byteAt b n (+ v 4))))) (+ v 4) -1))))) 0))

(schema Param (:f name String) (:f req Bool) (:f compact String))

fn paramOf pbody: String name: String -> Param
  (let [(req (reqTrue? pbody))
        (pt (typeOf pbody))
        (rd (if req "req" (let [(d (defaultToken pbody))] (if (stringEmpty? d) "\"\"" d))))
        (note (optionOr (keyString pbody ":note") ""))]
    (Param :name name :req req
           :compact (cond
                      ((not (stringEmpty? note)) (str "(:" name " " pt " " rd " \"" (k/escapeAsnVal note) "\")"))
                      ((= rd "\"\"") (str "(:" name " " pt ")"))
                      (else (str "(:" name " " pt " " rd ")")))))

fn itemStart b: Bytes n: Int64 i: Int64 -> Int64
  (if (= (byteAt b n i) 40)
    (let [(j (skipWs b n (+ i 1)))] (if (= (byteAt b n j) 58) (nameBoundaryEnd b n (+ j 1)) -1))
    -1)

fn paramItems praw: String b: Bytes n: Int64 i: Int64 acc: (List Param) -> (List Param)
  (let [(hit (searchFrom praw b n i (fn [(p Int64)] -> Int64 (itemStart b n p))))]
    (if (< (pairFirst hit) 0)
      (listReverse acc)
      (let [(st (pairFirst hit))
            (j (skipWs b n (+ st 1)))
            (name (slice praw (+ j 1) (pairSecond hit)))
            (e (balancedEnd b n st 0 false false))]
        (if (< e 0) (listReverse acc) (paramItems praw b n e (cons (paramOf (slice praw st e) name) acc))))))

fn paramsOpen oblk: String -> Int64
  (let [(b (stringToBytes oblk)) (n (stringLength oblk))]
    (pairSecond (searchFrom oblk b n 0 (fn [(i Int64)] -> Int64 (keyThenOpen b n i ":params")))))

fn opBlock name: String oblk: String prevCompact: String -> ToolOp
  (let [(open (paramsOpen oblk))
        (block (keyBlock oblk ":params"))
        (praw (if (stringEmpty? block) "()" block))
        (params (if (< open 0) (list) (paramItems praw (stringToBytes praw) (stringLength praw) 0 (list))))
        (exBlock (keyBlock oblk ":examples"))]
    (ToolOp :name name :scope (scopeOf oblk)
            :public (optionOr (keyString oblk ":public") "") :doc (optionOr (keyString oblk ":doc") "") :form (optionOr (keyString oblk ":form") "")
            :paramsRaw (stringJoin (s/pySplitWs praw) " ")
            :paramsCompact (cond ((< open 0) prevCompact) ((listEmpty? params) "()") (else (str "(" (stringJoin (map (fn [(p Param)] -> String p.compact) params) " ") ")")))
            :paramsSummary (stringJoin (map (fn [(p Param)] -> String (if p.req p.name (str p.name "?"))) params) " ")
            :examples (literals exBlock (stringToBytes exBlock) (stringLength exBlock) 0 (list))
            :errors (keyTokens oblk ":errors")
            :related (keyTokens oblk ":related")))

fn opStart b: Bytes n: Int64 i: Int64 -> Int64
  (if (= (byteAt b n i) 40)
    (let [(j (skipWs b n (+ i 1))) (v (keyThenWs b n j ":op"))]
      (if (and (>= v 0) (= (byteAt b n v) 58)) (nameBoundaryEnd b n (+ v 1)) -1))
    -1)

fn opNameStart b: Bytes n: Int64 i: Int64 -> Int64
  (+ (keyThenWs b n (skipWs b n (+ i 1)) ":op") 1)

fn scanOps raw: String b: Bytes n: Int64 pos: Int64 prev: String reg: Registry -> Registry
  (let [(hit (searchFrom raw b n pos (fn [(i Int64)] -> Int64 (opStart b n i))))]
    (if (< (pairFirst hit) 0)
      reg
      (let [(st (pairFirst hit))
            (name (slice raw (opNameStart b n st) (pairSecond hit)))
            (e (balancedEnd b n st 0 false false))]
        (if (< e 0)
          reg
          (let [(o (opBlock name (slice raw st e) prev))]
            (scanOps raw b n e o.paramsCompact (with reg :ops (mapSet reg.ops name o) :order (listAppend reg.order (list name)))))))))

fn topicStart b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (startsAt? b n i "(:topic") (not (wordB? (byteAt b n (+ i 7))))) (+ i 7) -1)

fn topicName blk: String -> String
  (let [(b (stringToBytes blk)) (n (stringLength blk))
        (viaName (searchFrom blk b n 0 (fn [(i Int64)] -> Int64 (let [(v (keyThenWs b n i ":name"))] (if (and (>= v 0) (= (byteAt b n v) 58) (nameB? (byteAt b n (+ v 1)))) (nameRun b n (+ v 1)) -1)))))
        (viaHead (searchFrom blk b n 0 (fn [(i Int64)] -> Int64 (let [(v (keyThenWs b n i "(:topic"))] (if (and (>= v 0) (= (byteAt b n v) 58) (nameB? (byteAt b n (+ v 1)))) (nameRun b n (+ v 1)) -1)))))]
    (cond
      ((>= (pairFirst viaName) 0) (slice blk (+ (keyThenWs b n (pairFirst viaName) ":name") 1) (pairSecond viaName)))
      ((>= (pairFirst viaHead) 0) (slice blk (+ (keyThenWs b n (pairFirst viaHead) "(:topic") 1) (pairSecond viaHead)))
      (else "")))

fn putTopic topics: (List (Pair String String)) name: String raw: String -> (List (Pair String String))
  (if (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) name)) topics)
    (map (fn [(p (Pair String String))] -> (Pair String String) (if (= (pairFirst p) name) (pair name raw) p)) topics)
    (listAppend topics (list (pair name raw))))

fn scanTopics sub: String b: Bytes n: Int64 pos: Int64 acc: (List (Pair String String)) -> (List (Pair String String))
  (let [(hit (searchFrom sub b n pos (fn [(i Int64)] -> Int64 (topicStart b n i))))]
    (if (< (pairFirst hit) 0)
      acc
      (let [(e (balancedEnd b n (pairFirst hit) 0 false false))]
        (if (< e 0)
          acc
          (let [(blk (slice sub (pairFirst hit) e)) (nm (topicName blk))]
            (scanTopics sub b n e (if (stringEmpty? nm) acc (putTopic acc nm (stringJoin (s/pySplitWs blk) " ")))))))))

fn parseRegistry raw: String -> Registry
  (let [(sub (keyBlock raw ":topics"))
        (topics (scanTopics sub (stringToBytes sub) (stringLength sub) 0 (list)))]
    (scanOps raw (stringToBytes raw) (stringLength raw) 0 "" (Registry :topics topics :ops (mapEmpty) :order (list))))

fn firstReadable! paths: (List String) -> String
  (mt (listHead paths)
    ((none) "")
    ((some p) (mt (if (fileExists? p) (fileReadString p) (err "absent")) ((ok t) t) ((err _) (firstReadable! (optionOr (listTail paths) (list)))))))

fn loadRegistry! ctx: s/KnowCtx -> (Option Registry)
  (let [(root ctx.toolRoot)
        (paths (if (stringEmpty? ctx.toolsFile)
                 (list (k/joinPath root "asl/grammar/tools.asn") (k/joinPath root "grammar/tools.asn") (k/joinPath root "share/asl/tools.asn"))
                 (list ctx.toolsFile)))
        (raw (firstReadable! paths))]
    (if (stringEmpty? raw) (none) (some (parseRegistry raw))))

fn ! anyAslFile? dir: String -> Bool
  (mt (dirList dir)
    ((err _) false)
    ((ok names)
      (or (listAny? (fn [(nm String)] -> Bool (and (or (stringEndsWith? nm ".asl") (stringEndsWith? nm ".asn")) (not (k/isDir! (k/joinPath dir nm))))) names)
          (listAny? (fn [(nm String)] -> Bool (and (!= nm ".git") (k/isDir! (k/joinPath dir nm)) (k/realChild? dir nm) (anyAslFile? (k/joinPath dir nm)))) names))))

fn ! gitListsAsl? ws: String extra: (List String) -> (Option Bool)
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd "git" (listAppend (listAppend (list "ls-files") extra) (list "*.asl" "*.asn"))) ws) 2000))
    ((ok out) (some (and (= out.exitCode 0) (not (stringEmpty? (s/pyStrip out.stdout))))))
    ((err _) (none)))

fn ! hasAsl? ws: String -> Bool
  (mt (gitListsAsl? ws (list))
    ((none) (anyAslFile? ws))
    ((some tracked)
      (or tracked
          (optionOr (gitListsAsl? ws (list "--others" "--exclude-standard")) false)
          (anyAslFile? ws))))

fn realOr! p: String -> String
  (resultOr (realPath p) p)

; (:m :ref NATIVE-TOOLS-CATALOGUE :do "isTc used to compare ctx.ws to ctx.toolRoot by bare realpath equality, so :scope toolchain ops (crawl, search, research, manage, engine, lens, agent, intel, tree, observe, audit, doctor, note, target, pack) vanished from (:tools) whenever ASL_ROOT pointed at a different worktree of the very same toolchain checkout than ctx.toolRoot (ASL_CLI_ROOT) resolved to -- the exact shape of a dev shell with a global ASL_ROOT set to the main checkout while asl runs from a worktree. Added gitCommonDirAbs!/sameToolchainRepo? to also treat ws and toolRoot as the same repo when their git common dirs agree (true for a worktree and its main checkout), keeping the cheap bare-equality path first")

fn ! absolutizeCommonDir dir: String raw: String -> String
  (realOr! (if (stringStartsWith? raw "/") raw (k/joinPath dir raw)))

fn ! gitCommonDirParsed! stdout: String dir: String -> (Option String)
  (let [(raw (s/pyStrip stdout))]
    (if (stringEmpty? raw) (none) (some (absolutizeCommonDir dir raw))))

fn ! gitCommonDirAbs! dir: String -> (Option String)
  (mt (cp/exec! (cp/withTimeout (cp/withCwd (cp/cmd "git" (list "rev-parse" "--git-common-dir")) dir) 2000))
    ((err _) (none))
    ((ok out)
      (if (!= out.exitCode 0)
        (none)
        (gitCommonDirParsed! out.stdout dir))))

fn ! sameToolchainRepo? ws: String toolRoot: String -> Bool
  (or (= (realOr! ws) (realOr! toolRoot))
      (mt (gitCommonDirAbs! ws)
        ((none) false)
        ((some wsCommon)
          (mt (gitCommonDirAbs! toolRoot)
            ((none) false)
            ((some trCommon) (= wsCommon trCommon))))))

fn visibleOps! reg: Registry ctx: s/KnowCtx scopeAll: Bool -> (List ToolOp)
  (let [(isTc (sameToolchainRepo? ctx.ws ctx.toolRoot))
        (has (hasAsl? ctx.ws))]
    (filter (fn [(o ToolOp)] -> Bool
              (cond
                (scopeAll (or (= o.scope "any") (= o.scope "asl")))
                (isTc true)
                ((= o.scope "any") true)
                ((= o.scope "asl") has)
                (else false)))
            (map (fn [(nm String)] -> ToolOp (optionOr (mapGet reg.ops nm) (ToolOp :name nm :scope "" :public "" :doc "" :form "" :paramsRaw "" :paramsCompact "" :paramsSummary "" :examples (list) :errors (list) :related (list)))) reg.order)))

fn t2Entry o: ToolOp withPublic: Bool withDoc: Bool -> String
  (stringJoin
    (filter (fn [(x String)] -> Bool (not (stringEmpty? x)))
            (list (str "(:op :" o.name)
                  (if (and withPublic (not (stringEmpty? o.public))) (str ":public " (s/quoted o.public)) "")
                  (if (and withDoc (not (stringEmpty? o.doc))) (str ":doc " (s/quoted o.doc)) "")
                  (if (stringEmpty? o.form) "" (str ":form " (s/quoted o.form)))
                  (cond ((not (stringEmpty? o.paramsCompact)) (str ":params " o.paramsCompact)) ((not (stringEmpty? o.paramsRaw)) (str ":params " o.paramsRaw)) (else ""))
                  (if (listEmpty? o.examples) "" (str ":examples (" (stringJoin (map s/quoted o.examples) " ") ")"))
                  (if (listEmpty? o.errors) "" (str ":errors (" (stringJoin o.errors " ") ")"))
                  (if (listEmpty? o.related) "" (str ":related (" (stringJoin o.related " ") ")"))
                  ")"))
    " ")

fn knownMap! reg: Registry ctx: s/KnowCtx -> (Map String ToolOp)
  (let [(base (fold (fn [(m (Map String ToolOp)) (o ToolOp)] -> (Map String ToolOp) (mapSet m o.name o)) (mapEmpty) (visibleOps! reg ctx true)))]
    (if (= (realOr! ctx.ws) (realOr! ctx.toolRoot))
      (fold (fn [(m (Map String ToolOp)) (p (Pair String ToolOp))] -> (Map String ToolOp) (mapSet m (pairFirst p) (pairSecond p))) base (mapPairs reg.ops))
      base))

fn nearTail names: (List String) target: String fallbackAll: Bool -> String
  (let [(near (sm/getCloseMatches target names 3 0.4))
        (picked (if (listEmpty? near) (if fallbackAll names (listTake names 3)) near))]
    (str " :nearest (" (stringJoin (map (fn [(x String)] -> String (str ":" x)) picked) " ") ")"))

fn missingRegistry id: Int64 op: String -> s/KnowOutcome
  (s/badLine (str (s/stepHead id op) " :status \"rejected\" :error-code \":ERR_REGISTRY_MISSING\" :message \"tools.asn registry not found\")"))

fn toolsStep! ctx: s/KnowCtx id: Int64 kw: (Map String String) args: (List String) -> s/KnowOutcome
  (mt (loadRegistry! ctx)
    ((none) (missingRegistry id "tools"))
    ((some reg)
      (let [(known (knownMap! reg ctx))
            (scopeAll (= (k/lstripColons (optionOr (mapGet kw "scope") "")) "all"))
            (named (k/lstripColons (k/kwOr kw "op" (k/kwOr kw "tool" ""))))
            (target (if (and (stringEmpty? named) (not (listEmpty? args)) (not scopeAll)) (k/lstripColons (optionOr (listHead args) "")) named))]
        (if (not (stringEmpty? target))
          (mt (mapGet known target)
            ((some o) (s/okLine (str (s/stepHead id "tools") " :status \"ok\" :op " (t2Entry o (not (stringEmpty? (k/kwOr kw "tool" ""))) false) ")")))
            ((none) (s/badLine (str (s/stepHead id "tools") " :status \"rejected\" :error-code \":ERR_UNKNOWN_OP\" :message \"Unknown operation\"" (nearTail (listSort (mapKeys known)) target false) ")"))))
          (let [(vis (visibleOps! reg ctx scopeAll))
                (lines (map (fn [(o ToolOp)] -> String
                              (let [(d (if (stringEmpty? o.public) o.doc o.public))]
                                (str "(:op :" o.name " " (s/quoted o.paramsSummary) " " (s/quoted (s/pyStrip (stringJoin (s/splitLinesPy d) " "))) ")")))
                            vis))]
            (s/okLine (str (s/stepHead id "tools") " :status \"ok\" :v 2 :workspace " (s/quoted (k/baseName (realOr! ctx.ws))) " :help \"(:help :op x) | (:help :topic t)\" :ops (\n    " (stringJoin lines "\n    ") "\n  ))")))))))

(schema Builtin (:f name String) (:f sec String) (:f type String) (:f doc String))

fn litAt t: String b: Bytes n: Int64 i: Int64 -> Int64
  (if (= (byteAt b n i) 34) (let [(e (stringLitEnd b n (+ i 1)))] (if (< e 0) -1 (+ e 1))) -1)

fn lineEnd b: Bytes n: Int64 i: Int64 -> Int64
  (let [(j (findByte b n i 10))] (if (< j 0) n j))

fn builtinAt t: String b: Bytes n: Int64 i: Int64 -> (Option (Pair Builtin Int64))
  (if (not (startsAt? b n i "(:name "))
    (none)
    (let [(ne (litAt t b n (+ i 7)))
          (se (if (and (>= ne 0) (startsAt? b n ne " :sec ")) (litAt t b n (+ ne 6)) -1))
          (te (if (and (>= se 0) (startsAt? b n se " :type ")) (litAt t b n (+ se 7)) -1))
          (nl (if (< te 0) -1 (lineEnd b n te)))
          (dk (if (or (< nl 0) (>= nl n)) -1 (skipWs b n (+ nl 1))))
          (de (if (and (>= dk 0) (startsAt? b n dk ":doc ")) (litAt t b n (+ dk 5)) -1))]
      (if (< de 0)
        (none)
        (some (pair (Builtin :name (k/asnUnescape (slice t (+ i 8) (- ne 1))) :sec (k/asnUnescape (slice t (+ ne 7) (- se 1)))
                             :type (k/asnUnescape (slice t (+ se 8) (- te 1))) :doc (k/asnUnescape (slice t (+ dk 6) (- de 1))))
                    de)))))

fn builtins t: String b: Bytes n: Int64 i: Int64 acc: (List Builtin) -> (List Builtin)
  (let [(at (k/findFrom t b "(:name \"" i))]
    (if (< at 0)
      (listReverse acc)
      (mt (builtinAt t b n at)
        ((some hit) (builtins t b n (pairSecond hit) (cons (pairFirst hit) acc)))
        ((none) (builtins t b n (+ at 1) acc)))))

fn absentNames t: String -> (List String)
  (let [(b (stringToBytes t)) (n (stringLength t)) (a (k/findFrom t b ":absent (" 0))]
    (if (< a 0)
      (list)
      (let [(nm (k/findFrom t b ":names [" (+ a 9)))
            (close (if (< nm 0) -1 (findByte b n (+ nm 8) 93)))]
        (if (< close 0) (list) (quotedPlain (slice t (+ nm 8) close))))))

fn quotedPlain s: String -> (List String)
  (let [(parts (stringSplit s "\""))]
    (map pairSecond (filter (fn [(p (Pair Int64 String))] -> Bool (= (mod (pairFirst p) 2) 1)) (listTake (enumerate parts) (if (= (mod (listLength parts) 2) 0) (- (listLength parts) 1) (listLength parts))))))

fn splitWords s: String -> (List String)
  (filter (fn [(w String)] -> Bool (> (stringLength w) 1))
          (stringSplit (stringJoin (map (fn [(c String)] -> String (let [(k (charCode c))] (if (or (and (>= k 97) (<= k 122)) (and (>= k 48) (<= k 57))) c " "))) (stringChars s)) "") " "))

fn builtinRow e: Builtin -> String
  (str "(:name " (s/quoted e.name) " :type " (if (stringEmpty? e.type) "absent" (s/quoted e.type))
       (if (stringEmpty? e.doc) " :doc absent" (str " :doc " (s/quoted e.doc))) ")")

fn cRegistrationNames text: String -> (List String)
  (cRegistrationNamesAt text (stringToBytes text) 0 (list))

fn arrayRowSuffixes text: String -> (List String)
  (let [(b (stringToBytes text))
        (a (k/findFrom text b "#define ROWS(P)" 0))
        (e (if (< a 0) -1 (k/findFrom text b "const Builtin arrayBuiltins" a)))]
    (if (< e 0) (list) (rowSuffixesAt text b e a (list))))

fn rowSuffixesAt text: String b: Bytes end: Int64 from: Int64 acc: (List String) -> (List String)
  (let [(at (k/findFrom text b "{#P \"" from))]
    (if (or (< at 0) (>= at end)) (listReverse acc)
      (let [(a (+ at 5)) (e (findByte b end a 34))]
        (if (< e 0) (listReverse acc)
          (rowSuffixesAt text b end (+ e 1) (cons (slice text a e) acc))))))

fn cTableNames path: String text: String -> (List String)
  (if (= path "asl/host/src/arrays.c")
    (let [(suffixes (arrayRowSuffixes text))]
      (listAppend (listAppend (map (fn [(s String)] -> String (str "f64" s)) suffixes)
                              (map (fn [(s String)] -> String (str "i64" s)) suffixes))
                  (map (fn [(s String)] -> String (str "i8" s)) suffixes)))
    (let [(marker (cond ((= path "asl/host/src/prelude.c") "const Builtin coreBuiltins[] = {")
                        ((= path "asl/host/src/sys.c") "const Builtin sysBuiltins[] = {")
                        ((= path "asl/host/src/sysNet.c") "const Builtin sysNetBuiltins[] = {")
                        ((= path "asl/host/src/parallel.c") "const Builtin parallelBuiltins[] = {")
                        (else "const Builtin kernelBuiltins[] = {")))
          (b (stringToBytes text))
          (a (k/findFrom text b marker 0))
          (e (if (< a 0) -1 (k/findFrom text b "};" a)))]
      (if (or (< a 0) (< e 0)) (list) (cRegistrationNames (slice text (+ a (stringLength marker)) e)))))

fn cRegistrationNamesAt text: String b: Bytes from: Int64 acc: (List String) -> (List String)
  (let [(at (k/findFrom text b "{\"" from))]
    (if (< at 0) (listReverse acc)
      (let [(a (+ at 2)) (e (findByte b (stringLength text) (+ at 2) 34))]
        (if (< e 0) (listReverse acc)
          (cRegistrationNamesAt text b (+ e 1) (cons (slice text a e) acc))))))

fn cRegistrationPaths -> (List String)
  (list "asl/host/src/prelude.c" "asl/host/src/sys.c" "asl/host/src/sysNet.c" "asl/host/src/arrays.c" "asl/host/src/parallel.c" "asl/host/src/kernels.c")

fn cRegistrationRows! root: String paths: (List String) -> (List Builtin)
  (mt (listHead paths)
    ((none) (list))
    ((some path)
      (listAppend
        (map (fn [(name String)] -> Builtin (Builtin :name name :sec "" :type "" :doc ""))
             (cTableNames path (resultOr (fileReadString (k/joinPath root path)) "")))
        (cRegistrationRows! root (optionOr (listTail paths) (list))))))

fn checkerNames t: String b: Bytes from: Int64 acc: (List String) -> (List String)
  (let [(at (k/findFrom t b "(= name \"" from))]
    (if (< at 0) (listReverse acc)
      (let [(a (+ at 9)) (e (findByte b (stringLength t) a 34))]
        (if (< e 0) (listReverse acc)
          (checkerNames t b (+ e 1) (cons (slice t a e) acc))))))

fn checkerSigType sig: (Pair (List String) (Pair Bool String)) -> String
  (let [(params (pairFirst sig)) (variadic (pairFirst (pairSecond sig))) (ret (pairSecond (pairSecond sig)))
        (shown (if (and variadic (not (listEmpty? params)))
                 (listAppend (listTake params (- (listLength params) 1)) (list (str (optionOr (listLast params) "") "..."))) params))]
    (str (if (listEmpty? shown) "()" (stringJoin shown " ")) " -> " ret))

fn checkerRows names: (List String) acc: (List Builtin) -> (List Builtin)
  (mt (listHead names)
    ((none) (listReverse acc))
    ((some name)
      (let [(tail (optionOr (listTail names) (list)))]
        (mt (ty/builtinSig name)
          ((none) (checkerRows tail acc))
          ((some sig) (checkerRows tail (cons (Builtin :name name :sec "" :type (checkerSigType sig) :doc "") acc)))))))

fn checkerBuiltins t: String -> (List Builtin)
  (let [(b (stringToBytes t))
        (a (k/findFrom t b "fn builtinSig " 0))
        (z (k/findFrom t b "\nfn showTypes " (max 0 a)))
        (body (slice t a (if (< z 0) (stringLength t) z)))]
    (checkerRows (checkerNames body (stringToBytes body) 0 (list)) (list)))

fn builtinUnion prelude: (List Builtin) checker: (List Builtin) registered: (List Builtin) absent: (List String) -> (List Builtin)
  (let [(bound (fn [(c Builtin)] -> Bool (listAny? (fn [(r Builtin)] -> Bool (= c.name r.name)) registered)))
        (overlaid (map (fn [(p Builtin)] -> Builtin
                         (mt (listHead (filter (fn [(c Builtin)] -> Bool (= p.name c.name)) checker))
                           ((none) p)
                           ((some c) (Builtin :name p.name :sec p.sec :type c.type :doc p.doc)))) prelude))
        (added (filter (fn [(c Builtin)] -> Bool (and (bound c) (not (listAny? (fn [(p Builtin)] -> Bool (= c.name p.name)) prelude)))) checker))
        (union (listAppend overlaid added))]
    (listSortBy (fn [(e Builtin)] -> String e.name)
      (filter (fn [(e Builtin)] -> Bool (not (listContains? absent e.name)))
        (listAppend union (filter (fn [(c Builtin)] -> Bool (not (listAny? (fn [(p Builtin)] -> Bool (= c.name p.name)) union))) registered)))))

fn helpBuiltin! ctx: s/KnowCtx id: Int64 needleRaw: String -> s/KnowOutcome
  (let [(path (k/joinPath (k/joinPath (k/joinPath ctx.toolRoot "asl") "prelude") "prelude.asn"))
        (typesPath (k/joinPath (k/joinPath (k/joinPath (k/joinPath ctx.toolRoot "asl") "packages") "asl-checker") "src/types.asl"))]
    (mt (fileReadString path)
      ((err _)
        (s/badLine (str (s/stepHead id "help") " :status \"rejected\" :error-code \":ERR_EXEC_FAILED\" :message "
                        (s/quoted (str "cannot read " path ": " (cond ((not (fileExists? path)) (str "[Errno 2] No such file or directory: '" path "'")) ((k/isDir! path) (str "[Errno 21] Is a directory: '" path "'")) (else (str "[Errno 13] Permission denied: '" path "'"))))) ")")))
      ((ok text)
        (mt (fileReadString typesPath)
          ((err _)
            (s/badLine (str (s/stepHead id "help") " :status \"rejected\" :error-code \":ERR_EXEC_FAILED\" :message "
                            (s/quoted (str "cannot read " typesPath)) ")")))
          ((ok checkerText)
        (let [(needle (k/lstripColons needleRaw))
              (preludeEntries (builtins text (stringToBytes text) (stringLength text) 0 (list)))
              (entries (builtinUnion preludeEntries (checkerBuiltins checkerText) (cRegistrationRows! ctx.toolRoot (cRegistrationPaths)) (absentNames text)))
              (byName (filter (fn [(e Builtin)] -> Bool (stringContains? e.name needle)) entries))
              (words (splitWords (stringLower needle)))
              (hits (if (listEmpty? byName) (filter (fn [(e Builtin)] -> Bool (and (not (listEmpty? words)) (listAll? (fn [(w String)] -> Bool (stringContains? (stringLower (str e.name " " e.doc)) w)) words))) entries) byName))
              (matchBy (if (listEmpty? byName) "doc" "name"))
              (missing (filter (fn [(a String)] -> Bool (stringContains? a needle)) (absentNames text)))
              (missTail (if (listEmpty? missing) "" (str " :unbound (" (stringJoin (map s/quoted missing) " ") ")")))]
          (if (not (listEmpty? hits))
            (s/okLine (str (s/stepHead id "help") " :status \"ok\" :builtin " (s/quoted needle) " :match :" matchBy " :count " (stringFromInt64 (listLength hits)) " :of " (stringFromInt64 (listLength entries))
                           " :builtins (" (stringJoin (map builtinRow hits) " ") ")" missTail ")"))
            (s/badLine (str (s/stepHead id "help") " :status \"rejected\" :error-code \":ERR_UNKNOWN_SYMBOL\" :message \"no builtin name contains " (k/escapeAsnVal needle) "\""
                            " :nearest (" (stringJoin (map s/quoted
                              (sm/getCloseMatches needle (map (fn [(e Builtin)] -> String e.name) entries) 5 0.4)) " ") ")" missTail ")")))))))))

fn helpStep! ctx: s/KnowCtx id: Int64 kw: (Map String String) args: (List String) -> s/KnowOutcome
  (mt (loadRegistry! ctx)
    ((none) (missingRegistry id "help"))
    ((some reg)
      (let [(known (knownMap! reg ctx))
            (builtin (mapGet kw "builtin"))
            (topic0 (k/lstripColons (optionOr (mapGet kw "topic") "")))
            (op0 (k/lstripColons (k/kwOr kw "op" (k/kwOr kw "tool" ""))))
            (a0 (k/lstripColons (optionOr (listHead args) "")))
            (useArg (and (none? builtin) (stringEmpty? topic0) (stringEmpty? op0) (not (listEmpty? args))))
            (argTopic (and useArg (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) a0)) reg.topics)))
            (topic (if argTopic a0 topic0))
            (op1 (if (and useArg (not argTopic)) a0 op0))
            (op (if (and (none? builtin) (stringEmpty? topic) (stringEmpty? op1)) "read" op1))]
        (cond
          ((some? builtin) (helpBuiltin! ctx id (optionOr builtin "")))
          ((not (stringEmpty? topic))
            (mt (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) topic)) reg.topics))
              ((some p) (s/okLine (str (s/stepHead id "help") " :status \"ok\" :topic " (pairSecond p) ")")))
              ((none) (s/badLine (str (s/stepHead id "help") " :status \"rejected\" :error-code \":ERR_UNKNOWN_TOPIC\" :message \"Unknown topic\"" (nearTail (listSort (map pairFirst reg.topics)) topic true) ")")))))
          (else
            (mt (mapGet known op)
              ((some o) (s/okLine (str (s/stepHead id "help") " :status \"ok\" :op " (t2Entry o true true) ")")))
              ((none) (s/badLine (str (s/stepHead id "help") " :status \"rejected\" :error-code \":ERR_UNKNOWN_OP\" :message \"Unknown operation\"" (nearTail (listSort (mapKeys known)) op false) ")")))))))))
