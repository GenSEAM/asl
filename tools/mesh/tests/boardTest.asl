(module ws/asl/tools/mesh/tests/boardTest
  :x [runTests]
  :i [(ws/asl/tools/mesh/board :a board)])

fn fixturePath -> String
  "tests/parity/mesh/boardFixture.asn"

fn fieldLoop s: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (Pair String Int64)
  (if (>= i n)
    (pair (stringJoin (listReverse acc) "") n)
    (let [b (bytesGet bs i)]
      (cond
        ((= b 34) (pair (stringJoin (listReverse acc) "") (+ i 1)))
        ((= b 92)
          (let [c (bytesGet bs (+ i 1))
                piece (cond ((= c 110) "\n") ((= c 114) "\r") ((= c 116) "\t") (else (optionOr (stringSlice s (+ i 1) (+ i 2)) "")))]
            (fieldLoop s bs (+ i 2) n (cons piece acc))))
        (else
          (let [j (plainEnd bs i n)]
            (fieldLoop s bs j n (cons (optionOr (stringSlice s i j) "") acc)))))))

fn plainEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 34) (= (bytesGet bs i) 92)) i (plainEnd bs (+ i 1) n))

fn lineFields s: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse acc))
    ((= (bytesGet bs i) 34)
      (let [r (fieldLoop s bs (+ i 1) n (list))]
        (lineFields s bs (pairSecond r) n (cons (pairFirst r) acc))))
    (else (lineFields s bs (+ i 1) n acc)))

fn caseFields line: String -> (List String)
  (let [bs (stringToBytes line)]
    (lineFields line bs 0 (bytesLength bs) (list)))

fn tokEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (or (>= i n) (= (bytesGet bs i) 44) (= (bytesGet bs i) 93) (= (bytesGet bs i) 41) (= (bytesGet bs i) 125) (= (bytesGet bs i) 58)) i (tokEnd bs (+ i 1) n))

fn decStr s: String bs: Bytes i: Int64 n: Int64 acc: (List String) -> (Pair String Int64)
  (let [b (bytesGet bs i)]
    (cond
      ((= b 34) (pair (stringJoin (listReverse acc) "") (+ i 1)))
      ((= b 92) (decStr s bs (+ i 2) n (cons (optionOr (stringSlice s (+ i 1) (+ i 2)) "") acc)))
      (else (let [j (plainEnd bs i n)] (decStr s bs j n (cons (optionOr (stringSlice s i j) "") acc))))))

fn decItems s: String bs: Bytes i: Int64 n: Int64 close: Int64 acc: (List board/AsnValue) -> (Pair (List board/AsnValue) Int64)
  (cond
    ((= (bytesGet bs i) close) (pair (listReverse acc) (+ i 1)))
    ((= (bytesGet bs i) 44) (decItems s bs (+ i 1) n close acc))
    (else (let [r (dec s bs i n)] (decItems s bs (pairSecond r) n close (cons (pairFirst r) acc)))))

fn decEntries s: String bs: Bytes i: Int64 n: Int64 acc: (List (Pair String board/AsnValue)) -> (Pair (List (Pair String board/AsnValue)) Int64)
  (cond
    ((= (bytesGet bs i) 125) (pair (listReverse acc) (+ i 1)))
    ((= (bytesGet bs i) 44) (decEntries s bs (+ i 1) n acc))
    (else
      (let [k (decStr s bs (+ i 2) n (list))
            v (dec s bs (+ (pairSecond k) 1) n)]
        (decEntries s bs (pairSecond v) n (cons (pair (pairFirst k) (pairFirst v)) acc)))))

fn dec s: String bs: Bytes i: Int64 n: Int64 -> (Pair board/AsnValue Int64)
  (let [b (bytesGet bs i)]
    (cond
      ((= b 78) (pair (board/asnNone) (+ i 1)))
      ((= b 84) (pair (board/asnBool true) (+ i 1)))
      ((= b 70) (pair (board/asnBool false) (+ i 1)))
      ((= b 105)
        (let [j (tokEnd bs i n)]
          (mt (stringToInt64 (optionOr (stringSlice s (+ i 1) j) ""))
            ((some v) (pair (board/asnInt v) j))
            ((none) (pair (board/asnNone) j)))))
      ((= b 102)
        (let [j (tokEnd bs i n)]
          (mt (stringToFloat64 (optionOr (stringSlice s (+ i 1) j) ""))
            ((some v) (pair (board/asnFloat v) j))
            ((none) (pair (board/asnNone) j)))))
      ((= b 115) (let [r (decStr s bs (+ i 2) n (list))] (pair (board/asnStr (pairFirst r)) (pairSecond r))))
      ((= b 91) (let [r (decItems s bs (+ i 1) n 93 (list))] (pair (board/asnList (pairFirst r)) (pairSecond r))))
      ((= b 40) (let [r (decItems s bs (+ i 1) n 41 (list))] (pair (board/asnTuple (pairFirst r)) (pairSecond r))))
      (else (let [r (decEntries s bs (+ i 1) n (list))] (pair (board/asnDict (pairFirst r)) (pairSecond r))))))

fn decode s: String -> board/AsnValue
  (let [bs (stringToBytes s)]
    (pairFirst (dec s bs 0 (bytesLength bs))))

fn encStr s: String -> String
  (str "s\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn enc v: board/AsnValue -> String
  (mt v
    ((board/asnNone) "N")
    ((board/asnBool b) (if b "T" "F"))
    ((board/asnInt i) (str "i" (stringFromInt64 i)))
    ((board/asnFloat f) (str "f" (stringFromFloat64 f)))
    ((board/asnStr x) (encStr x))
    ((board/asnList xs) (str "[" (stringJoin (map enc xs) ",") "]"))
    ((board/asnTuple xs) (str "(" (stringJoin (map enc xs) ",") ")"))
    ((board/asnDict es)
      (str "{" (stringJoin (map (fn [p] (str (pairFirst p) ":" (pairSecond p)))
                             (listSortBy pairFirst (map (fn [p] (pair (encStr (pairFirst p)) (enc (pairSecond p)))) es))) ",") "}")))

fn encErr e: String -> String
  (let [parts (stringSplit e ": ")
        cls (optionOr (listHead parts) "")
        msg (optionOr (stringSlice e (+ (stringLength cls) 2) (stringLength e)) "")]
    (if (= cls "ValueError") (str "!ValueError:" msg) (str "!" cls)))

fn encStrRes r: (Result String String) -> String
  (mt r ((ok x) (encStr x)) ((err e) (encErr e)))

fn encOptStr o: (Option String) -> String
  (mt o ((some x) (encStr x)) ((none) "N"))

fn encOpt o: (Option board/AsnValue) -> String
  (mt o ((some x) (enc x)) ((none) "N"))

fn strList xs: (List String) -> board/AsnValue
  (board/asnList (map (fn [x] (board/asnStr x)) xs))

fn tokValue t: board/RecordTok -> board/AsnValue
  (let [kv (mt t
             ((board/tokOpen x) (pair "open" x))
             ((board/tokClose x) (pair "close" x))
             ((board/tokStr x) (pair "s" x))
             ((board/tokKey x) (pair "k" x))
             ((board/tokAtom x) (pair "a" x)))]
    (board/asnTuple (list (board/asnStr (pairFirst kv)) (board/asnStr (pairSecond kv)))))

fn recValue v: board/RecordValue -> board/AsnValue
  (mt v
    ((board/recLeaf t) (tokValue t))
    ((board/recForm items) (board/asnList (map recValue items))))

fn recMap es: (List (Pair String board/RecordValue)) -> board/AsnValue
  (board/asnDict (map (fn [p] (pair (pairFirst p) (recValue (pairSecond p)))) es))

fn argStr args: (List board/AsnValue) k: Int64 -> String
  (mt (optionOr (listGet args k) (board/asnNone)) ((board/asnStr x) x) (_ ""))

fn argInt args: (List board/AsnValue) k: Int64 -> Int64
  (mt (optionOr (listGet args k) (board/asnNone)) ((board/asnInt x) x) (_ 0))

fn arg args: (List board/AsnValue) k: Int64 -> board/AsnValue
  (optionOr (listGet args k) (board/asnNone))

fn argStrs args: (List board/AsnValue) k: Int64 -> (List String)
  (mt (arg args k) ((board/asnList xs) (map (fn [x] (mt x ((board/asnStr y) y) (_ ""))) xs)) (_ (list)))

fn argDict args: (List board/AsnValue) k: Int64 -> (List (Pair String board/AsnValue))
  (mt (arg args k) ((board/asnDict es) es) (_ (list)))

fn relOrEmpty root: String v: board/AsnValue -> String
  (mt v ((board/asnStr x) (board/pyJoin root x)) (_ ""))

fn toksOf b: String -> (List board/RecordTok)
  (board/recordTokens b)

fn normMs s: String -> String
  (let [parts (stringSplit s "DEF-")]
    (stringJoin (cons (optionOr (listHead parts) "") (map (fn [p] (if (and (>= (stringLength p) 13) (allDigits? (optionOr (stringSlice p 0 13) ""))) (str "<ms>" (optionOr (stringSlice p 13 (stringLength p)) "")) p)) (optionOr (listTail parts) (list)))) "DEF-"))

fn allDigits? s: String -> Bool
  (listAll? (fn [c] (stringContains? "0123456789" c)) (stringChars s))

fn runPure fnName: String args: (List board/AsnValue) root: String -> (Option String)
  (cond
    ((= fnName "sanitizeAsnString") (some (encStr (board/sanitizeAsnString (arg args 0)))))
    ((= fnName "unescapeAsnString") (some (encStr (board/unescapeAsnString (argStr args 0)))))
    ((= fnName "asnFieldString") (some (encOptStr (board/asnFieldString (argStr args 0) (argStr args 1)))))
    ((= fnName "normalizeSeverity") (some (encStr (board/normalizeSeverity (arg args 0)))))
    ((= fnName "renderAttractor") (some (encStr (board/renderAttractor (arg args 0)))))
    ((= fnName "insertIntoDefects") (some (encStrRes (board/insertIntoDefects (argStr args 0) (argStr args 1)))))
    ((= fnName "parseFinding") (some (encOpt (board/parseFinding (argStr args 0)))))
    ((= fnName "parseVerdict") (some (encOpt (board/parseVerdict (argStr args 0)))))
    ((= fnName "tokenizeAsn") (some (mt (board/tokenizeAsn (argStr args 0)) ((ok ts) (enc (strList ts))) ((err e) (encErr e)))))
    ((= fnName "parseAsnItem") (some (let [r (board/parseAsnItem (argStrs args 0) (argInt args 1))] (enc (board/asnTuple (list (pairFirst r) (board/asnInt (pairSecond r))))))))
    ((= fnName "parseAsnForm") (some (let [r (board/parseAsnForm (argStrs args 0) (argInt args 1))] (enc (board/asnTuple (list (pairFirst r) (board/asnInt (pairSecond r))))))))
    ((= fnName "extractGapBlocks") (some (enc (strList (board/extractGapBlocks (argStr args 0) (argStr args 1))))))
    ((= fnName "recordTokens") (some (enc (board/asnList (map tokValue (toksOf (argStr args 0)))))))
    ((= fnName "readRecord") (some (enc (recMap (board/readRecord (argStr args 0))))))
    ((= fnName "recordScalars") (some (enc (board/asnDict (map (fn [p] (pair (pairFirst p) (board/asnStr (board/recordScalar (pairSecond p))))) (board/readRecord (argStr args 0)))))))
    ((= fnName "parseGapBlock") (some (enc (board/parseGapBlock (argStr args 0)))))
    ((= fnName "parseVerification") (some (enc (board/parseVerification (argStr args 0)))))
    ((= fnName "recordValue") (some (let [r (board/recordValue (toksOf (argStr args 0)) (argInt args 1))] (enc (board/asnTuple (list (recValue (pairFirst r)) (board/asnInt (pairSecond r))))))))
    ((= fnName "formToMap")
      (some (mt (pairFirst (board/recordValue (toksOf (argStr args 0)) 0))
              ((board/recForm items) (enc (recMap (board/formToMap items (argInt args 1)))))
              (_ "!TypeError"))))
    ((= fnName "formFields") (some (encOpt (board/formFields (board/dictGet (board/readRecord (argStr args 0)) (argStr args 1))))))
    ((= fnName "normAgent") (some (encStr (board/normAgent (arg args 0)))))
    ((= fnName "asnList") (some (encStr (board/asnListText (argStrs args 0)))))
    ((= fnName "shardTextFromBlock") (some (encStr (board/shardTextFromBlock (argStr args 0)))))
    ((= fnName "setField") (some (encStrRes (board/setField (argStr args 0) (argStr args 1) (argStr args 2)))))
    ((= fnName "valueEnd") (some (mt (board/valueEnd (argStr args 0) (argInt args 1)) ((ok i) (str "i" (stringFromInt64 i))) ((err e) (encErr e)))))
    (else (none)))

fn deadPid! -> Int64
  (mt (procSpawnv (list "true") (none) (none))
    ((ok sp) (do (fdClose sp.stdin) (fdClose sp.stdout) (fdClose sp.stderr) (procWaitPid sp.pid false) sp.pid))
    ((err _) -1))

fn caseDir! base: String id: String -> String
  (let [d (str base "/" id)]
    (do (dirCreate d) d))

fn makeTree! root: String es: (List (Pair String board/AsnValue)) subst: (fn [String] -> String) -> Bool
  (listAll? (fn [p]
              (let [rel (subst (pairFirst p))
                    path (str root "/" rel)]
                (if (stringEndsWith? rel "/")
                  (ok? (dirCreate path))
                  (and (ok? (dirCreate (board/pyDirname path)))
                       (ok? (fileWrite path (mt (pairSecond p) ((board/asnStr x) x) (_ ""))))))))
            (listSortBy pairFirst es))

fn readTreeAt! root: String rel: String unsubst: (fn [String] -> String) acc: (List (Pair String board/AsnValue)) -> (List (Pair String board/AsnValue))
  (let [dir (if (stringEmpty? rel) root (str root "/" rel))]
    (mt (dirList dir)
      ((err _) acc)
      ((ok names)
        (fold (fn [a nm]
                (let [r (if (stringEmpty? rel) nm (str rel "/" nm))
                      full (str root "/" r)]
                  (mt (fileStat full)
                    ((err _) a)
                    ((ok st)
                      (if st.isDir
                        (readTreeAt! root r unsubst (cons (pair (str (unsubst r) "/") (board/asnNone)) a))
                        (cons (pair (unsubst r) (board/asnList (list (board/asnStr (resultOr (fileReadString full) "")) (board/asnBool (= (& st.mode 146) 0))))) a))))))
              acc names))))

fn readTree! root: String unsubst: (fn [String] -> String) -> String
  (enc (board/asnDict (readTreeAt! root "" unsubst (list))))

fn same x: String -> String
  x

fn hideRoot s: String root: String -> String
  (stringReplace s root "<R>")

fn encUnitRes r: (Result Unit String) -> String
  (mt r ((ok _) "N") ((err e) (encErr e)))

fn runFileCase! fnName: String args: (List board/AsnValue) root: String -> (Option String)
  (cond
    ((= fnName "atomicWriteFile") (some (encUnitRes (board/atomicWriteFile! (board/pyJoin root (argStr args 1)) (argStr args 2)))))
    ((= fnName "fileLock")
      (let [t (argStr args 1)
            target (if (or (stringEmpty? t) (= t "/dev/null")) t (board/pyJoin root t))]
        (some (encStrRes (board/withFileLock! target (fn [] (ok "held")))))))
    ((= fnName "saveDefectShard")
      (some (encStrRes (board/saveDefectShard! (arg args 1) (relOrEmpty root (arg args 2)) root))))
    ((= fnName "loadShardedBlackboard")
      (some (let [dir (mt (arg args 1) ((board/asnStr x) (board/pyJoin root x)) (_ (board/pyJoin root ".asl/mem/gaps/shards")))]
              (enc (board/asnList (board/loadShardedBlackboard! dir).shards)))))
    ((= fnName "compactObservationMemory")
      (some (mt (board/compactObservationMemory! (board/pyJoin root "sh") (board/pyJoin root "ar") (argInt args 1) (argInt args 2) (relOrEmpty root (arg args 3)))
              ((ok r) (enc (board/compactMetrics r)))
              ((err e) (encErr e)))))
    ((= fnName "writeShardForBlock") (some (encUnitRes (board/writeShardForBlock! (argStr args 1) (argStr args 2) (relOrEmpty root (arg args 3))))))
    ((= fnName "writeBoard") (some (encUnitRes (board/writeBoard! (board/pyJoin root "bb.asn") (argStr args 1) (relOrEmpty root (arg args 2))))))
    ((= fnName "distillShard") (some (encStr (board/distillShard! root (argStrs args 1) (argInt args 2)).digest)))
    (else (none)))

fn makeReadonly! paths: (List String) -> Bool
  (listAll? (fn [p] (= (fileChmod p 292) (ok ()))) paths)

fn fileCase! fnName: String args: (List board/AsnValue) root: String -> String
  (let [built (makeTree! root (argDict args 0) same)
        ro (if (= fnName "writeBoard") (makeReadonly! (map (fn [r] (str root "/" r)) (argStrs args 3))) true)
        res (optionOr (runFileCase! fnName args root) "!unknown")]
    (if (and built ro)
      (normMs (str (hideRoot res root) "|" (readTree! root same)))
      "!setupFailed"))

fn cleanupCase! args: (List board/AsnValue) root: String -> String
  (let [selfPid (stringFromInt64 (procSelf))
        dead (stringFromInt64 (deadPid!))
        subst (fn [r] (stringReplace (stringReplace r "{SELF}" selfPid) "{DEAD}" dead))
        unsubst (fn [r] (stringReplace (stringReplace r selfPid "{SELF}") dead "{DEAD}"))
        built (makeTree! root (argDict args 0) subst)
        dirs (mt (arg args 1) ((board/asnList _) (some (map (fn [d] (board/pyJoin root d)) (argStrs args 1)))) (_ (none)))
        envRel (mt (arg args 2) ((board/asnStr x) (some (board/pyJoin root x))) (_ (none)))
        res (mt (board/cleanupStaleTempFiles! root dirs (board/pidFileFor root envRel))
              ((ok r) (enc (board/cleanupMetrics r)))
              ((err e) (encErr e)))]
    (if built (str (hideRoot res root) "|" (readTree! root unsubst)) "!setupFailed"))

fn treeCase! fnName: String args: (List board/AsnValue) root: String -> String
  (if (not (makeTree! root (argDict args 0) same))
    "!setupFailed"
    (if (= fnName "commandVacuity")
      (encStr (board/commandVacuity! (arg args 1) (arg args 2) root))
      (mt (board/transitionAllowed! (arg args 1) (arg args 2) root)
        ((ok r) (enc (board/asnTuple (list (board/asnBool (pairFirst r)) (board/asnStr (pairSecond r))))))
        ((err e) (encErr e)))))

fn placeRoots v: board/AsnValue root: String home: String -> String
  (mt v ((board/asnStr x) (stringReplace (stringReplace x "@ROOT" root) "@HOME" home)) (_ ""))

fn configCase! args: (List board/AsnValue) base: String -> String
  (let [root (str base "/root")
        home (str base "/home")
        mk (and (ok? (dirCreate root)) (ok? (dirCreate home)))
        tree (argDict args 0)
        built (listAll? (fn [p]
                          (let [rel (pairFirst p)
                                path (if (stringStartsWith? rel "@HOME") (stringReplace rel "@HOME" home) (str root "/" rel))]
                            (if (stringEndsWith? rel "/")
                              (ok? (dirCreate path))
                              (and (ok? (dirCreate (board/pyDirname path))) (ok? (fileWrite path (mt (pairSecond p) ((board/asnStr x) x) (_ ""))))))))
                        (listSortBy pairFirst tree))
        res (board/loadMeshConfig! root home (argStr args 1) (placeRoots (arg args 2) root home) (placeRoots (arg args 3) root home)
              (placeRoots (arg args 4) root home) (argStr args 5))]
    (if (and mk built)
      (mt res
        ((ok r) (stringReplace (str (enc (pairFirst r)) "|" (encStr (pairSecond r))) base "<B>"))
        ((err e) (str (encErr e) "|" (encStr ""))))
      "!setupFailed"))

fn largeBoard n: Int64 -> String
  (str "(:board\n  :defects (\n"
       (stringJoin (map (fn [i] (str "    (:defect\n      :id \"DEF-" (stringFromInt64 i) "\"\n      :target \"asl/x" (stringFromInt64 (mod i 97)) ".asl#f\"\n      :hazard \"h \\\""
                                     (stringFromInt64 i) "\\\" (x\"\n      :status :" (if (= (mod i 3) 0) "remediated" "open") "\n      :confirmations " (stringFromInt64 (mod i 7)) ")\n"))
                        (range 0 n)) "")
       "  ))\n")

fn fieldInt v: board/AsnValue k: String -> Int64
  (mt v ((board/asnDict es) (mt (board/dictGet es k) ((some x) (mt x ((board/asnInt i) i) (_ 0))) ((none) 0))) (_ 0))

fn largeCase n: Int64 -> String
  (let [text (largeBoard n)
        blocks (board/extractGapBlocks text "defect")
        infos (map board/parseGapBlock blocks)
        ins (resultOr (board/insertIntoDefects text "\n    (:defect :id \"NEW\")") "")
        insLen (stringLength ins)
        lastInfo (mt (optionOr (listLast infos) (board/asnDict (list))) ((board/asnDict es) (board/asnDict (filter (fn [p] (!= (pairFirst p) "raw")) es))) (x x))
        remediated (listLength (filter (fn [v] (mt v ((board/asnDict es) (= (board/dictGet es "status") (some (board/asnStr "remediated")))) (_ false))) infos))]
    (enc (board/asnList (list (board/asnInt (board/cpLength text)) (board/asnInt (listLength blocks))
                              (board/asnInt (fold (fn [acc v] (+ acc (fieldInt v "confirmations"))) 0 infos))
                              (board/asnInt remediated) (board/asnInt (board/cpLength ins))
                              (board/asnStr (optionOr (stringSlice ins (- insLen 40) insLen) ""))
                              lastInfo
                              (board/asnInt (listLength (resultOr (board/tokenizeAsn text) (list))))
                              (mt (board/asnFieldString text "hazard") ((some h) (board/asnStr h)) ((none) (board/asnNone)))))))

fn runCase! fnName: String args: (List board/AsnValue) dir: String -> String
  (mt (runPure fnName args dir)
    ((some text) text)
    ((none) (runImpure! fnName args dir)))

fn runImpure! fnName: String args: (List board/AsnValue) dir: String -> String
  (cond
    ((or (= fnName "commandVacuity") (= fnName "transitionAllowed")) (treeCase! fnName args dir))
    ((= fnName "isProcessAlive")
      (let [sym (argStr args 0)
            pid (cond ((= sym "self") (procSelf)) ((= sym "dead") (deadPid!)) ((= sym "zero") 0) ((= sym "neg") -5) ((= sym "negOne") -1) ((= sym "one") 1) (else 99999999999))]
        (mt (board/isProcessAlive! pid) ((ok b) (if b "T" "F")) ((err e) (encErr e)))))
    ((= fnName "cleanupStaleTempFiles") (cleanupCase! args dir))
    ((= fnName "loadMeshConfig") (configCase! args dir))
    ((= fnName "largeBoard") (largeCase (argInt args 0)))
    (else (fileCase! fnName args dir)))

fn checkLine! base: String k: Int64 line: String -> Bool
  (let [fs (caseFields line)
        fnName (optionOr (listGet fs 0) "")
        id (optionOr (listGet fs 1) "")
        want (optionOr (listGet fs 2) "")
        args (map decode (optionOr (listTail (optionOr (listTail (optionOr (listTail fs) (list))) (list))) (list)))
        dir (caseDir! base (str "c" (stringFromInt64 k)))
        got (runCase! fnName args dir)
        same (= got want)]
    (do
      (if same () (eprintln (str "MISMATCH " fnName " " id "\n  want " want "\n  got  " got)))
      same))

fn declaredCases text: String -> Int64
  (let [head (optionOr (listHead (stringSplit text "\n")) "")
        after (optionOr (listGet (stringSplit head ":cases ") 1) "")]
    (optionOr (stringToInt64 (optionOr (listHead (stringSplit after ")")) "")) -1))

fn caseLines text: String -> (List String)
  (filter (fn [l] (stringStartsWith? l "(:case ")) (stringSplit text "\n"))

fn scratchBase! -> String
  (let [t (optionOr (envGet "TMPDIR") "/tmp")
        tt (if (and (stringEndsWith? t "/") (> (stringLength t) 1)) (optionOr (stringSlice t 0 (- (stringLength t) 1)) t) t)]
    (str tt "/u11boardTest." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))

fn ! runTests -> Bool
  (let [text (resultOr (fileReadString (fixturePath)) "")
        lines (caseLines text)
        base (scratchBase!)
        made (dirCreate base)
        results (map (fn [p] (pair (pairSecond p) (checkLine! base (pairFirst p) (pairSecond p)))) (enumerate lines))
        t0 (monotonicNs)
        big (largeCase 4000)
        ms (/ (- (monotonicNs) t0) 1000000)
        lockPath (str base "/contended.asn")
        held (board/acquireFileLock! lockPath)
        busy (fileLock (str lockPath ".lock") true)
        freed (board/releaseFileLock! (resultOr held -1))
        after (fileLock (str lockPath ".lock") true)
        dirLockTarget (str base "/directory-lock.asn")
        directoryLockPath (str dirLockTarget ".lock")
        directoryMade (dirCreate directoryLockPath)
        directoryLock (board/acquireFileLock! dirLockTarget)
        cleaned (pathRemove base)]
    (do
      (println (str "boardTest: " (stringFromInt64 (listLength lines)) " fixture cases, large 4000-record board in " (stringFromInt64 ms) " ms"))
      (assert (= (listLength lines) (declaredCases text)) "fixture case lines equal the recorder's :cases count")
      (map (fn [r] (assert (pairSecond r) (str "parity " (optionOr (stringSlice (pairFirst r) 0 80) "")))) results)
      (assert (stringContains? big "DEF-3999") "large board parsed to its last record")
      (assert (< ms 60000) "large board under 60 s")
      (assert (ok? held) "lock acquired")
      (assert (= busy (err "busy")) "a held lock is busy for a second open")
      (assert (ok? after) "released lock can be taken again")
      (assert (ok? directoryMade) "directory lock fixture created")
      (assert (= directoryLock (err "lock path is a directory")) "directory lock path returns a named rejection")
      (assert (ok? cleaned) "scratch base removed")
      true))
