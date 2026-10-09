(module asl-forms/lens :x [lensStep fixedRatio fnmatch stripStringLiterals canonicalLenses] :i [(asl-forms/kernel :a k) (asl-forms/delegate :a d)])


(schema Telemetry (:f rc Int64) (:f digest String) (:f suites Int64) (:f passedSuites Int64) (:f failedSuites Int64) (:f declaredAsserts Int64) (:f executedAsserts Int64) (:f executedRefutes Int64) (:f totalWallMs Int64))

(schema LensState (:f lists (Map String (List String))) (:f skipped Int64) (:f tel (Map String Telemetry)) (:f intel (Map String (Pair Int64 String))) (:f status (Map String String)) (:f metrics (Map String String)) (:f findings (List String)))

(schema LensScope (:f root String) (:f scopeRoot String))


fn canonicalLenses -> (List String)
  (list "falsification" "invariants" "concurrency" "security" "attention-density" "architecture" "non-vacuity" "optimization" "resilience" "contract-precision" "minimal-surface" "consistency" "coupling")

fn lensAliases -> (Map String String)
  (mapFromPairs (list (pair "token-economics" "attention-density") (pair "tokeneconomics" "attention-density") (pair "attentiondensity" "attention-density")
                      (pair "api-ergonomics" "contract-precision") (pair "apiergonomics" "contract-precision") (pair "contractprecision" "contract-precision")
                      (pair "minimalsurface" "minimal-surface") (pair "nonvacuity" "non-vacuity") (pair "teleology" "security") (pair "semantics" "non-vacuity")
                      (pair "gates" "falsification") (pair "trimap" "consistency") (pair "grading" "falsification") (pair "astaddressing" "contract-precision")
                      (pair "ramtxn" "concurrency") (pair "foreign" "architecture") (pair "limitcycle" "resilience") (pair "workspaceisolation" "invariants")
                      (pair "dyck1purity" "invariants")))

fn destructivePatterns -> (List String)
  (list "rm -rf / " "rm -rf ~" "rm -rf $HOME" "rm -fr / ")

fn vacuousPatterns -> (List String)
  (list "(assert true)" "(assert #t)" "assert(True)" "assert True" "assert(true)" "assert(1)")

fn asnBool b: Bool -> String
  (if b "true" "false")

fn num n: Int64 -> String
  (stringFromInt64 n)

fn quotedList xs: (List String) -> String
  (str "[" (stringJoin (map (fn [(x String)] -> String (str "\"" x "\"")) xs) " ") "]")

fn firstFive xs: (List String) -> String
  (stringJoin (listTake xs 5) ", ")

fn splitHi v: Float64 -> Float64
  (let [(c (* 134217729.0 v))]
    (- c (- c v)))

fn aboveRatio a: Int64 den: Int64 -> Bool
  (let [(af (int64ToFloat64 a))
        (df (int64ToFloat64 den))
        (x (/ af df))
        (p (* x df))
        (xh (splitHi x))
        (xl (- x xh))
        (dh (splitHi df))
        (dl (- df dh))
        (e (+ (+ (+ (- (* xh dh) p) (* xh dl)) (* xl dh)) (* xl dl)))]
    (> (+ (- p af) e) 0.0))

fn gcd a: Int64 b: Int64 -> Int64
  (if (= b 0) a (gcd b (mod a b)))

fn powerOfTwo? n: Int64 -> Bool
  (cond ((<= n 0) false) ((= n 1) true) ((= (mod n 2) 1) false) (else (powerOfTwo? (/ n 2))))

fn pow10 k: Int64 -> Int64
  (if (<= k 0) 1 (* 10 (pow10 (- k 1))))

fn padLeft s: String width: Int64 -> String
  (if (>= (stringLength s) width) s (padLeft (str "0" s) width))

fn fixedRatio a: Int64 den: Int64 places: Int64 -> String
  (let [(scale (pow10 places))
        (n (* a scale))
        (q (/ n den))
        (r (mod n den))
        (up (cond
              ((> (* 2 r) den) true)
              ((< (* 2 r) den) false)
              ((powerOfTwo? (/ den (gcd a den))) (= (mod q 2) 1))
              (else (aboveRatio a den))))
        (rounded (if up (+ q 1) q))]
    (str (num (/ rounded scale)) "." (padLeft (num (mod rounded scale)) places)))

fn stripScan b: Bytes s: String i: Int64 n: Int64 from: Int64 inStr: Bool esc: Bool acc: (List String) -> (List String)
  (cond
    ((>= i n) (if inStr acc (cons (optionOr (stringSlice s from n) "") acc)))
    (esc (stripScan b s (+ i 1) n from inStr false acc))
    (inStr
      (let [(c (bytesGet b i))]
        (cond
          ((= c 92) (stripScan b s (+ i 1) n from true true acc))
          ((= c 34) (stripScan b s (+ i 1) n (+ i 1) false false acc))
          (else (stripScan b s (+ i 1) n from true false acc)))))
    ((= (bytesGet b i) 34) (stripScan b s (+ i 1) n i true false (cons (optionOr (stringSlice s from i) "") acc)))
    (else (stripScan b s (+ i 1) n from false false acc)))

fn stripStringLiterals text: String -> String
  (k/concatAll (listReverse (stripScan (stringToBytes text) text 0 (stringLength text) 0 false false (list))))

fn digitAt? s: String i: Int64 -> Bool
  (let [(c (k/charAt s i))]
    (and (not (stringEmpty? c)) (>= (charCode c) 48) (<= (charCode c) 57)))

fn spaceEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (k/isSpaceChar (k/charAt s i))) (spaceEnd s (+ i 1) n) i)

fn digitEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (digitAt? s i)) (digitEnd s (+ i 1) n) i)

fn lineTagCount s: String b: Bytes from: Int64 acc: Int64 -> Int64
  (let [(at (k/findFrom s b ":line" from))]
    (if (< at 0)
      acc
      (let [(n (stringLength s))
            (sp (spaceEnd s (+ at 5) n))
            (de (digitEnd s sp n))]
        (if (and (> sp (+ at 5)) (> de sp))
          (lineTagCount s b de (+ acc 1))
          (lineTagCount s b (+ at 1) acc)))))

fn lineTags text: String -> Int64
  (lineTagCount text (stringToBytes text) 0 0)

fn tabEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (or (= (k/charAt s i) " ") (= (k/charAt s i) "\t"))) (tabEnd s (+ i 1) n) i)

fn headCount s: String b: Bytes needle: String from: Int64 acc: Int64 -> Int64
  (let [(at (k/findFrom s b needle from))]
    (if (< at 0)
      acc
      (let [(after (+ at (stringLength needle)))
            (e (tabEnd s after (stringLength s)))]
        (if (> e after) (headCount s b needle e (+ acc 1)) (headCount s b needle (+ at 1) acc)))))

fn assertHeads text: String -> Int64
  (let [(b (stringToBytes text))]
    (+ (headCount text b "(assert" 0 0) (headCount text b "(refute" 0 0)))

fn cappedAt text: String b: Bytes from: Int64 -> Int64
  (let [(at (k/findFrom text b "capped at " from))]
    (if (< at 0)
      -1
      (let [(ds (+ at 10))
            (de (digitEnd text ds (stringLength text)))]
        (if (> de ds) (optionOr (stringToInt64 (optionOr (stringSlice text ds de) "")) -1) (cappedAt text b (+ at 1))))))

fn charCount text: String -> Int64
  (let [(b (stringToBytes text))]
    (listLength (filter (fn [(i Int64)] -> Bool (!= (& (bytesGet b i) 192) 128)) (range 0 (bytesLength b)))))

fn classEnd pat: (List String) i: Int64 n: Int64 -> Int64
  (let [(j0 (if (and (< i n) (= (optionOr (listGet pat i) "") "!")) (+ i 1) i))
        (j1 (if (and (< j0 n) (= (optionOr (listGet pat j0) "") "]")) (+ j0 1) j0))]
    (closeBracket pat j1 n))

fn closeBracket pat: (List String) j: Int64 n: Int64 -> Int64
  (cond ((>= j n) -1) ((= (optionOr (listGet pat j) "") "]") j) (else (closeBracket pat (+ j 1) n)))

fn classHas items: (List String) c: String -> Bool
  (mt (listHead items)
    ((none) false)
    ((some a)
      (let [(rest (optionOr (listTail items) (list)))]
        (if (and (= (optionOr (listGet rest 0) "") "-") (> (listLength rest) 1))
          (or (and (>= (charCode c) (charCode a)) (<= (charCode c) (charCode (optionOr (listGet rest 1) a))))
              (classHas (listDrop rest 2) c))
          (or (= a c) (classHas rest c))))))

fn globAt pat: (List String) pi: Int64 pn: Int64 s: (List String) si: Int64 sn: Int64 -> Bool
  (if (>= pi pn)
    (= si sn)
    (let [(p (optionOr (listGet pat pi) ""))]
      (cond
        ((= p "*") (or (globAt pat (+ pi 1) pn s si sn) (and (< si sn) (globAt pat pi pn s (+ si 1) sn))))
        ((= p "?") (and (< si sn) (globAt pat (+ pi 1) pn s (+ si 1) sn)))
        ((and (= p "[") (>= (classEnd pat (+ pi 1) pn) 0))
          (let [(close (classEnd pat (+ pi 1) pn))
                (neg (= (optionOr (listGet pat (+ pi 1)) "") "!"))
                (items (optionOr (listSlice pat (if neg (+ pi 2) (+ pi 1)) close) (list)))]
            (and (< si sn)
                 (!= (classHas items (optionOr (listGet s si) "")) neg)
                 (globAt pat (+ close 1) pn s (+ si 1) sn))))
        (else (and (< si sn) (= p (optionOr (listGet s si) "")) (globAt pat (+ pi 1) pn s (+ si 1) sn))))))

fn fnmatch name: String pat: String -> Bool
  (let [(p (stringChars pat)) (s (stringChars name))]
    (globAt p 0 (listLength p) s 0 (listLength s)))

fn rstripSlash s: String -> String
  (if (stringEndsWith? s "/") (rstripSlash (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")) s)

fn ignoredBy rel: String pat: String -> Bool
  (let [(p (d/pyStrip pat))]
    (cond
      ((stringEndsWith? p "/**") (stringStartsWith? rel (str (rstripSlash (optionOr (stringSlice p 0 (- (stringLength p) 3)) "")) "/")))
      ((stringEndsWith? p "/") (or (stringStartsWith? rel p) (stringContains? (str "/" rel) (str "/" p))))
      ((stringStartsWith? p "**/")
        (let [(t (rstripSlash (optionOr (stringSlice p 3 (stringLength p)) "")))]
          (or (stringStartsWith? rel (str t "/")) (stringContains? rel (str "/" t "/")) (stringEndsWith? rel (str "/" t)))))
      (else (or (fnmatch rel p) (fnmatch (k/baseName rel) p)))))

fn negativeFixture? rel: String -> Bool
  (listAny? (fn [(m String)] -> Bool (stringContains? (str "/" rel) m))
            (list "/corpus/invalid/" "/corpus/asn/invalid/" "/invalid/" "/fixtures/invalid/" "/fixtures/unbalanced/"))

fn cleanLines out: String -> (List String)
  (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (map d/pyStrip (stringSplit out "\n")))

fn withList st: LensState key: String v: (List String) -> LensState
  (with st :lists (mapSet st.lists key v))

fn record st: LensState lid: String status: String metrics: String -> LensState
  (with st :status (mapSet st.status lid status) :metrics (mapSet st.metrics lid metrics))

fn finding st: LensState lid: String sev: String msg: String -> LensState
  (with st :findings (cons (str "(:finding :lens \"" lid "\" :severity :" sev " :message \"" (k/escapeAsnVal msg) "\")") st.findings))

fn findingIf st: LensState cond: Bool lid: String sev: String msg: String -> LensState
  (if cond (finding st lid sev msg) st)

fn ! lensSh sc: LensScope argv: (List String) -> (Pair Int64 String)
  (let [(sp (d/spawnRun argv (some sc.root) (mapEmpty) 300))]
    (if (stringEmpty? sp.failure) (pair sp.code (str sp.out sp.errText)) (pair -1 sp.failure)))

fn ! gitLines sc: LensScope st: LensState key: String sub: String -> (Pair (List String) LensState)
  (mt (mapGet st.lists key)
    ((some v) (pair v st))
    ((none)
      (let [(res (lensSh sc (list "git" sub)))
            (v (if (= (pairFirst res) 0) (cleanLines (pairSecond res)) (list)))]
        (pair v (withList st key v)))))

fn ! trackedFiles sc: LensScope st: LensState -> (Pair (List String) LensState)
  (gitLines sc st "tf" "ls-files")

fn ! gitRemotes sc: LensScope st: LensState -> (Pair (List String) LensState)
  (gitLines sc st "rem" "remote")

fn ! scopedFiles sc: LensScope st: LensState -> (Pair (List String) LensState)
  (mt (mapGet st.lists "sf")
    ((some v) (pair v st))
    ((none)
      (let [(base (k/relPath sc.scopeRoot (k/normalizePath sc.root)))
            (t (trackedFiles sc st))
            (v (if (or (= base ".") (stringEmpty? base)) (pairFirst t) (let [(pfx (str (rstripSlash base) "/"))] (filter (fn [(f String)] -> Bool (stringStartsWith? f pfx)) (pairFirst t)))))]
        (pair v (withList (pairSecond t) "sf" v)))))

fn ! readRel sc: LensScope rel: String -> (Option String)
  (let [(ap (if (stringStartsWith? rel "/") rel (k/joinPath sc.root rel)))]
    (if (not (k/isFile! ap))
      (none)
      (mt (fileReadString ap) ((ok text) (some (k/universalNewlines text))) ((err _) (none)))))

fn ! ignorePatterns sc: LensScope st: LensState -> (Pair (List String) LensState)
  (mt (mapGet st.lists "ign")
    ((some v) (pair v st))
    ((none)
      (let [(v (mt (readRel sc ".aslignore")
                 ((none) (list))
                 ((some text) (filter (fn [(l String)] -> Bool (and (not (stringEmpty? l)) (not (stringStartsWith? l "#")))) (map d/pyStrip (stringSplit text "\n"))))))]
        (pair v (withList st "ign" v)))))

fn ! auditScopeFiles sc: LensScope st: LensState -> (Pair (List String) LensState)
  (mt (mapGet st.lists "asf")
    ((some v) (pair v st))
    ((none)
      (let [(sf (scopedFiles sc st))
            (ig (ignorePatterns sc (pairSecond sf)))
            (keep (filter (fn [(f String)] -> Bool (not (or (listAny? (fn [(p String)] -> Bool (ignoredBy f p)) (pairFirst ig)) (negativeFixture? f)))) (pairFirst sf)))
            (s2 (withList (pairSecond ig) "asf" keep))]
        (pair keep (LensState :lists s2.lists :skipped (- (listLength (pairFirst sf)) (listLength keep)) :tel s2.tel :intel s2.intel
                              :status s2.status :metrics s2.metrics :findings s2.findings)))))

fn telField raw: String field: String -> Int64
  (mt (d/fieldNumber raw field false) ((some v) (optionOr (stringToInt64 v) -1)) ((none) -1))

fn hexChar? c: String -> Bool
  (stringContains? "0123456789abcdefABCDEF" c)

fn hexEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (hexChar? (k/charAt s i))) (hexEnd s (+ i 1) n) i)

fn digestScan s: String b: Bytes from: Int64 -> String
  (let [(at (k/findFrom s b ":runnerDigest" from))]
    (if (< at 0)
      ""
      (let [(n (stringLength s))
            (sp (spaceEnd s (+ at 13) n))
            (he (hexEnd s (+ sp 1) n))]
        (if (and (> sp (+ at 13)) (= (k/charAt s sp) "\"") (> he (+ sp 1)) (= (k/charAt s he) "\""))
          (optionOr (stringSlice s (+ sp 1) he) "")
          (digestScan s b (+ at 1))))))

fn telemetryOf rc: Int64 raw: String -> Telemetry
  (Telemetry :rc rc :digest (digestScan raw (stringToBytes raw) 0)
             :suites (telField raw "suites") :passedSuites (telField raw "passedSuites") :failedSuites (telField raw "failedSuites")
             :declaredAsserts (telField raw "declaredAsserts") :executedAsserts (telField raw "executedAsserts")
             :executedRefutes (telField raw "executedRefutes") :totalWallMs (telField raw "totalWallMs"))

fn ! gateTelemetry sc: LensScope st: LensState runId: Int64 -> (Pair Telemetry LensState)
  (mt (mapGet st.tel (num runId))
    ((some t) (pair t st))
    ((none)
      (let [(runner (k/joinPath sc.root "scripts/runGateTests.sh"))
            (telPath (str "/tmp/aslLensTel." (num (procSelf)) "." (num runId) ".asn"))
            (t (if (not (k/isFile! runner))
                 (telemetryOf -1 "")
                 (let [(res (lensSh sc (list "bash" runner (str "--telemetry=" telPath))))
                       (raw (resultOr (fileReadString telPath) ""))
                       (gone (pathRemove telPath))]
                   (telemetryOf (pairFirst res) raw))))]
        (pair t (with st :tel (mapSet st.tel (num runId) t))))))

fn ! intelReport sc: LensScope st: LensState sub: String -> (Pair (Pair Int64 String) LensState)
  (mt (mapGet st.intel sub)
    ((some r) (pair r st))
    ((none)
      (let [(bin (k/joinPath sc.root "bin/asl"))
            (r (if (k/isFile! bin) (lensSh sc (list bin "intel" sub)) (pair -1 "")))]
        (pair r (with st :intel (mapSet st.intel sub r))))))

fn intelNum text: String field: String -> Int64
  (mt (d/fieldNumber text field true) ((some v) (optionOr (stringToInt64 v) -1)) ((none) -1))

fn ! cpuCount -> Int64
  (let [(sp (d/spawnRun (list "getconf" "_NPROCESSORS_ONLN") (none) (mapEmpty) 10))
        (n (if (and (stringEmpty? sp.failure) (= sp.code 0)) (optionOr (stringToInt64 (d/pyStrip sp.out)) 0) 0))]
    (if (> n 0) n 1))

fn endsWithAny? f: String exts: (List String) -> Bool
  (listAny? (fn [(e String)] -> Bool (stringEndsWith? f e)) exts)

fn ! readAll sc: LensScope files: (List String) -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (rel String)] -> (List (Pair String String))
          (mt (readRel sc rel) ((none) acc) ((some c) (cons (pair rel c) acc))))
        (list) files)

fn ! repoInvariants sc: LensScope st0: LensState -> LensState
  (let [(a (auditScopeFiles sc st0))
        (read (listReverse (readAll sc (filter (fn [(f String)] -> Bool (endsWithAny? f (list ".asl" ".asn"))) (pairFirst a)))))
        (checked (listLength read))
        (unbal (map pairFirst (filter (fn [(p (Pair String String))] -> Bool (not (k/isBalanced (pairSecond p)))) read)))
        (r (gitRemotes sc (pairSecond a)))
        (rems (pairFirst r))
        (s1 (findingIf (pairSecond r) (not (listEmpty? unbal)) "invariants" "high" (str "Unbalanced Dyck-1 delimiters in " (num (listLength unbal)) " file(s): " (firstFive unbal))))
        (s2 (findingIf s1 (not (listEmpty? rems)) "invariants" "critical" (str "Workspace zero-remote invariant violated: " (stringJoin rems ", "))))]
    (if (= checked 0)
      (record s2 "invariants" "unmeasured" "(:filesChecked 0 :reason \"no ASL/ASN files in scope\")")
      (record s2 "invariants" (if (and (listEmpty? unbal) (listEmpty? rems)) "pass" "fail")
              (str "(:filesChecked " (num checked) " :balanced " (num (- checked (listLength unbal))) " :unbalanced " (num (listLength unbal))
                   " :excludedFromScope " (num s2.skipped) " :scopeSource \".aslignore + negative fixtures\" :remotesCount " (num (listLength rems))
                   " :zeroRemote " (asnBool (listEmpty? rems)) ")"))))

fn ! repoSecurity sc: LensScope st0: LensState -> LensState
  (let [(r (gitRemotes sc st0))
        (rems (pairFirst r))
        (a (auditScopeFiles sc (pairSecond r)))
        (read (listReverse (readAll sc (filter (fn [(f String)] -> Bool (endsWithAny? f (list ".sh" ".bash" ".zsh"))) (pairFirst a)))))
        (danger (map pairFirst (filter (fn [(p (Pair String String))] -> Bool (listAny? (fn [(pat String)] -> Bool (stringContains? (pairSecond p) pat)) (destructivePatterns))) read)))
        (s1 (findingIf (pairSecond a) (not (listEmpty? rems)) "security" "critical" (str "Monorepo sovereignty breach: non-zero git remotes " (stringJoin rems ", "))))
        (s2 (findingIf s1 (not (listEmpty? danger)) "security" "critical" (str "Unconstrained destructive purge in " (firstFive danger))))]
    (record s2 "security" (if (and (listEmpty? rems) (listEmpty? danger)) "pass" "fail")
            (str "(:remotesCount " (num (listLength rems)) " :zeroRemote " (asnBool (listEmpty? rems)) " :shellFilesScanned " (num (listLength read))
                 " :destructivePatterns " (num (listLength danger)) ")")))

fn ! repoFalsification sc: LensScope st0: LensState -> LensState
  (let [(g (gateTelemetry sc st0 1)) (t (pairFirst g)) (st (pairSecond g))]
    (if (< t.rc 0)
      (finding (record st "falsification" "unmeasured" "(:reason \"gate runner scripts/runGateTests.sh unavailable\")") "falsification" "high" "Falsification unmeasurable: gate runner not executable")
      (let [(okf (and (= t.rc 0) (= t.failedSuites 0) (> t.suites 0) (> t.executedAsserts 0)))
            (s1 (findingIf st (not okf) "falsification" "high" (str "Gate suite falsification failed: exit " (num t.rc) ", failedSuites " (num t.failedSuites) ", executedAsserts " (num t.executedAsserts))))]
        (record s1 "falsification" (if okf "pass" "fail")
                (str "(:runnerExit " (num t.rc) " :suites " (num t.suites) " :passedSuites " (num t.passedSuites) " :failedSuites " (num t.failedSuites)
                     " :executedAsserts " (num t.executedAsserts) " :executedRefutes " (num t.executedRefutes) " :runnerDigest \"" (k/escapeAsnVal t.digest) "\")")))))

fn ! repoNonVacuity sc: LensScope st0: LensState -> LensState
  (let [(g (gateTelemetry sc st0 1)) (t (pairFirst g))
        (iv (intelReport sc (pairSecond g) "vacuity")) (rcV (pairFirst (pairFirst iv))) (outV (pairSecond (pairFirst iv))) (st (pairSecond iv))
        (tot (if (= rcV 0) (intelNum outV "totalAssertions") -1))
        (vac (if (= rcV 0) (intelNum outV "vacuousTestsCount") -1))
        (stubs (if (= rcV 0) (intelNum outV "trivialStubsCount") -1))]
    (if (and (< t.rc 0) (!= rcV 0))
      (record st "non-vacuity" "unmeasured" "(:reason \"neither gate runner nor asl-intel vacuity available\")")
      (let [(declared t.declaredAsserts)
            (executed t.executedAsserts)
            (refuted (if (>= t.executedRefutes 0) t.executedRefutes 0))
            (verified (if (>= executed 0) (+ executed refuted) -1))
            (gap (if (and (>= declared 0) (>= verified 0)) (- declared verified) -1))
            (okv (and (> executed 0) (= t.failedSuites 0) (= vac 0) (= stubs 0) (= gap 0)))
            (s1 (findingIf st (> vac 0) "non-vacuity" "high" (str "Vacuous test suites detected: " (num vac))))
            (s2 (findingIf s1 (> stubs 0) "non-vacuity" "high" (str "Trivial stubs detected: " (num stubs))))
            (s3 (findingIf s2 (> gap 0) "non-vacuity" "high" (str "Declared-vs-verified assertion gap unreconciled: declared " (num declared) ", verified " (num verified) " (" (num executed) " asserts + " (num refuted) " refutes), gap " (num gap))))]
        (record s3 "non-vacuity" (if okv "pass" "fail")
                (str "(:declaredAsserts " (num declared) " :executedAsserts " (num executed) " :executedRefutes " (num refuted) " :verifiedTotal " (num verified)
                     " :declaredVerifiedGap " (num gap) " :monorepoAssertions " (num tot) " :vacuousTests " (num vac) " :trivialStubs " (num stubs) ")")))))

fn ! repoConcurrency sc: LensScope st0: LensState -> LensState
  (let [(g1 (gateTelemetry sc st0 1)) (g2 (gateTelemetry sc (pairSecond g1) 2)) (t1 (pairFirst g1)) (t2 (pairFirst g2)) (st (pairSecond g2))]
    (if (or (< t1.rc 0) (< t2.rc 0))
      (record st "concurrency" "unmeasured" "(:reason \"gate runner unavailable, determinism unmeasurable\")")
      (let [(stable (and (not (stringEmpty? t1.digest)) (= t1.digest t2.digest)))
            (s1 (findingIf st (not stable) "concurrency" "high" (str "Parallel runner digest non-deterministic: " t1.digest " vs " t2.digest)))]
        (record s1 "concurrency" (if stable "pass" "fail")
                (str "(:parallelWorkers " (num (cpuCount)) " :digestRunA \"" (k/escapeAsnVal t1.digest) "\" :digestRunB \"" (k/escapeAsnVal t2.digest) "\" :digestStable " (asnBool stable) ")")))))

fn ! repoOptimization sc: LensScope st0: LensState -> LensState
  (let [(g (gateTelemetry sc st0 1)) (t (pairFirst g)) (st (pairSecond g))]
    (if (or (< t.rc 0) (< t.totalWallMs 0))
      (record st "optimization" "unmeasured" "(:reason \"gate runner wall-clock unmeasurable\")")
      (let [(oko (and (>= t.totalWallMs 0) (< t.totalWallMs 60000)))
            (s1 (findingIf st (not oko) "optimization" "medium" (str "Gate suite wall time exceeded 60s budget: " (num t.totalWallMs) "ms")))]
        (record s1 "optimization" (if oko "pass" "fail") (str "(:gateSuiteWallMs " (num t.totalWallMs) " :auditProcessPeakRssMb -1 :budgetMs 60000)")))))

fn ! repoArchitecture sc: LensScope st0: LensState -> LensState
  (let [(sf (scopedFiles sc st0))
        (pkg (filter (fn [(f String)] -> Bool (stringStartsWith? f "asl/packages/")) (pairFirst sf)))
        (aslSrc (filter (fn [(f String)] -> Bool (stringEndsWith? f ".asl")) pkg))
        (foreign (filter (fn [(f String)] -> Bool (endsWithAny? f (list ".c" ".h" ".py" ".ts" ".tsx" ".js" ".mjs" ".rs" ".go" ".java" ".rb" ".php" ".swift"))) pkg))
        (denom (+ (listLength aslSrc) (listLength foreign)))
        (st (pairSecond sf))]
    (if (= denom 0)
      (record st "architecture" "unmeasured" "(:reason \"no package source files in scope\")")
      (let [(oka (listEmpty? foreign))
            (s1 (findingIf st (not oka) "architecture" "high" (str "Foreign source inside pure ASL package partition: " (firstFive foreign))))]
        (record s1 "architecture" (if oka "pass" "fail")
                (str "(:packageSourceFiles " (num denom) " :pureAslFiles " (num (listLength aslSrc)) " :foreignFiles " (num (listLength foreign)) " :pureAslRatio " (fixedRatio (listLength aslSrc) denom 4) ")")))))

fn ! repoCoupling sc: LensScope st0: LensState -> LensState
  (let [(iv (intelReport sc st0 "coupling")) (rc (pairFirst (pairFirst iv))) (out (pairSecond (pairFirst iv))) (st (pairSecond iv))]
    (if (!= rc 0)
      (record st "coupling" "unmeasured" "(:reason \"asl-intel coupling unavailable\")")
      (let [(cycles (intelNum out "cyclesCount"))
            (fictions (intelNum out "totalFictions"))
            (ghosts (intelNum out "ghostModulesCount"))
            (undecl (intelNum out "undeclaredImportsCount"))
            (s1 (findingIf st (> cycles 0) "coupling" "high" (str "Inter-package dependency cycles detected: " (num cycles))))
            (s2 (findingIf s1 (> fictions 0) "coupling" "medium" (str "Module fictions detected: " (num fictions))))]
        (record s2 "coupling" (if (and (= cycles 0) (= fictions 0)) "pass" "fail")
                (str "(:interPackageCycles " (num cycles) " :moduleFictions " (num fictions) " :ghostModules " (num ghosts) " :undeclaredImports " (num undecl) ")")))))

fn ! repoMinimalSurface sc: LensScope st0: LensState -> LensState
  (let [(iv (intelReport sc st0 "deadcode")) (rc (pairFirst (pairFirst iv))) (out (pairSecond (pairFirst iv))) (st (pairSecond iv))]
    (if (!= rc 0)
      (record st "minimal-surface" "unmeasured" "(:reason \"asl-intel deadcode unavailable\")")
      (let [(total (intelNum out "totalDefinitions"))
            (dead (intelNum out "deadPrivateCount"))
            (s1 (findingIf st (> dead 0) "minimal-surface" "medium" (str "Speculative bloat: " (num dead) " dead private definitions of " (num total))))]
        (record s1 "minimal-surface" (if (= dead 0) "pass" "fail") (str "(:totalDefinitions " (num total) " :deadPrivateDefinitions " (num dead) ")")))))

fn ! repoConsistency sc: LensScope st: LensState -> LensState
  (let [(ssot (k/joinPath sc.root "scripts/install.sh"))]
    (if (not (k/isFile! ssot))
      (record st "consistency" "unmeasured" "(:reason \"scripts/install.sh SSOT checker unavailable\")")
      (let [(rc (pairFirst (lensSh sc (list "bash" ssot "--check-rules"))))
            (s1 (findingIf st (!= rc 0) "consistency" "high" (str "SSOT rule surfaces drifted from asl/grammar/rules.asn (install.sh --check-rules exit " (num rc) ")")))]
        (record s1 "consistency" (if (= rc 0) "pass" "fail")
                (str "(:ssotCheckerExit " (num rc) " :ssotSource \"asl/grammar/rules.asn\" :renderedSurfacesVerified " (asnBool (= rc 0)) ")")))))

fn ! repoAttention sc: LensScope st0: LensState -> LensState
  (let [(a (auditScopeFiles sc st0))
        (read (listReverse (readAll sc (filter (fn [(f String)] -> Bool (stringEndsWith? f ".asn")) (pairFirst a)))))
        (viol (map pairFirst (filter (fn [(p (Pair String String))] -> Bool (> (lineTags (stripStringLiterals (pairSecond p))) 0)) read)))
        (st (pairSecond a))]
    (if (listEmpty? read)
      (record st "attention-density" "unmeasured" "(:reason \"no ASN ledgers in scope\")")
      (let [(s1 (findingIf st (not (listEmpty? viol)) "attention-density" "medium" (str "Zero-Line-Number Invariant violated in " (num (listLength viol)) " ASN file(s): " (firstFive viol))))]
        (record s1 "attention-density" (if (listEmpty? viol) "pass" "fail")
                (str "(:asnFilesScanned " (num (listLength read)) " :lineNumberViolations " (num (listLength viol)) " :zeroLineNumbers " (asnBool (listEmpty? viol)) ")")))))

fn opName chunk: String -> String
  (let [(h (d/pyStrip chunk))
        (n (stringLength h))
        (e (fold (fn [(acc Int64) (i Int64)] -> Int64 (if (and (= acc i) (not (k/isSpaceChar (k/charAt h i)))) (+ i 1) acc)) 1 (range 1 n)))]
    (if (and (stringStartsWith? h ":") (> e 1)) (optionOr (stringSlice h 1 e) "?") "?"))

fn ! repoContract sc: LensScope st: LensState -> LensState
  (mt (readRel sc "asl/grammar/tools.asn")
    ((none) (record st "contract-precision" "unmeasured" "(:reason \"asl/grammar/tools.asn not present in scope\")"))
    ((some c)
      (let [(chunks (listDrop (stringSplit c "(:op ") 1))
            (total (listLength chunks))
            (undoc (map opName (filter (fn [(ch String)] -> Bool (not (stringContains? ch ":doc"))) chunks)))
            (documented (- total (listLength undoc)))]
        (if (= total 0)
          (record st "contract-precision" "unmeasured" "(:reason \"no :op contracts declared in tools.asn\")")
          (record (findingIf st (!= documented total) "contract-precision" "medium" (str "Tool contracts missing :doc: " (firstFive undoc)))
                  "contract-precision" (if (= documented total) "pass" "fail")
                  (str "(:declaredOps " (num total) " :documentedOps " (num documented) " :undocumentedOps " (num (- total documented)) ")"))))))

fn ! repoResilience sc: LensScope st: LensState -> LensState
  (mt (readRel sc "asl/grammar/rules.asn")
    ((none) (record st "resilience" "unmeasured" "(:reason \"asl/grammar/rules.asn not present in scope\")"))
    ((some c)
      (let [(thr (cappedAt c (stringToBytes c) 0))
            (witness (or (stringContains? c ":witness") (stringContains? c "witness record")))
            (okr (and (> thr 0) witness))]
        (record (findingIf st (not okr) "resilience" "medium" (str "Circuit-breaker limit-cycle rule not grounded in rules.asn (threshold " (num thr) ")"))
                "resilience" (if okr "pass" "fail")
                (str "(:circuitBreakerThreshold " (num thr) " :witnessRecordDeclared " (asnBool witness) ")")))))

fn ! repoLens sc: LensScope st: LensState lid: String -> LensState
  (cond
    ((= lid "invariants") (repoInvariants sc st))
    ((= lid "security") (repoSecurity sc st))
    ((= lid "falsification") (repoFalsification sc st))
    ((= lid "non-vacuity") (repoNonVacuity sc st))
    ((= lid "concurrency") (repoConcurrency sc st))
    ((= lid "optimization") (repoOptimization sc st))
    ((= lid "architecture") (repoArchitecture sc st))
    ((= lid "coupling") (repoCoupling sc st))
    ((= lid "minimal-surface") (repoMinimalSurface sc st))
    ((= lid "consistency") (repoConsistency sc st))
    ((= lid "attention-density") (repoAttention sc st))
    ((= lid "contract-precision") (repoContract sc st))
    ((= lid "resilience") (repoResilience sc st))
    (else (record st lid "unmeasured" "(:reason \"no repo-scope evaluator implemented for this lens\")")))

fn ! fileLens sc: LensScope st: LensState lid: String target: String path: String ext: String content: String -> LensState
  (cond
    ((= lid "invariants")
      (cond
        ((listContains? (list ".asn" ".asl") ext)
          (let [(bal (k/isBalanced content))]
            (record (findingIf st (not bal) "invariants" "high" (str "Unbalanced Dyck-1 delimiters in " target)) "invariants" (if bal "pass" "fail") (str "(:check \"dyck1Balance\" :balanced " (asnBool bal) ")"))))
        ((listContains? (list ".sh" ".bash") ext)
          (let [(rc (pairFirst (lensSh sc (list "bash" "-n" path))))]
            (record (findingIf st (!= rc 0) "invariants" "high" (str "Bash syntax verification failed in " target)) "invariants" (if (= rc 0) "pass" "fail") (str "(:check \"bashSyntax\" :exit " (num rc) ")"))))
        ((= ext ".py")
          (let [(rc (pairFirst (lensSh sc (list "python3" "-m" "py_compile" path))))]
            (record (findingIf st (!= rc 0) "invariants" "high" (str "Python syntax verification failed in " target)) "invariants" (if (= rc 0) "pass" "fail") (str "(:check \"pythonCompile\" :exit " (num rc) ")"))))
        (else (record st "invariants" "unmeasured" (str "(:reason \"no syntax verifier for extension " (k/escapeAsnVal (if (stringEmpty? ext) "none" ext)) "\")")))))
    ((= lid "security")
      (let [(hits (listLength (filter (fn [(p String)] -> Bool (stringContains? content p)) (destructivePatterns))))]
        (record (findingIf st (> hits 0) "security" "critical" (str "Unconstrained destructive purge violates V0 sovereignty in " target))
                "security" (if (= hits 0) "pass" "fail") (str "(:destructivePatternHits " (num hits) " :bytesScanned " (num (charCount content)) ")"))))
    ((= lid "non-vacuity")
      (let [(hits (listLength (filter (fn [(p String)] -> Bool (stringContains? content p)) (vacuousPatterns))))]
        (record (findingIf st (> hits 0) "non-vacuity" "high" (str "Vacuous assertion detected in " target))
                "non-vacuity" (if (= hits 0) "pass" "fail") (str "(:declaredAssertions " (num (assertHeads content)) " :vacuousPatternHits " (num hits) ")"))))
    ((= lid "attention-density")
      (if (not (listContains? (list ".asn" ".asl") ext))
        (record st "attention-density" "unmeasured" "(:reason \"zero-line-number invariant applies to ASL/ASN surfaces only\")")
        (let [(v (lineTags (stripStringLiterals content)))]
          (record (findingIf st (> v 0) "attention-density" "medium" (str "Zero-Line-Number Invariant violated in " target))
                  "attention-density" (if (= v 0) "pass" "fail") (str "(:lineNumberViolations " (num v) " :zeroLineNumbers " (asnBool (= v 0)) ")")))))
    (else (record st lid "unmeasured" "(:reason \"no file-scope evaluator implemented for this lens\")")))

fn stripQuotesColons tok: String -> String
  (let [(t (d/pyStrip tok))
        (noQuotes (stripChars (stripCharsRight t)))]
    (d/pyStrip (k/lstripColons noQuotes)))

fn quoteChar? c: String -> Bool
  (or (= c "\"") (= c "'"))

fn stripChars s: String -> String
  (if (and (> (stringLength s) 0) (quoteChar? (k/charAt s 0))) (stripChars (optionOr (stringSlice s 1 (stringLength s)) "")) s)

fn stripCharsRight s: String -> String
  (let [(n (stringLength s))]
    (if (and (> n 0) (quoteChar? (k/charAt s (- n 1)))) (stripCharsRight (optionOr (stringSlice s 0 (- n 1)) "")) s))

fn pySplit s: String -> (List String)
  (filter (fn [(x String)] -> Bool (not (stringEmpty? x)))
          (stringSplit (k/concatAll (map (fn [(c String)] -> String (if (k/isSpaceChar c) " " c)) (stringChars s))) " "))

fn requestedTokens raw: String -> (List String)
  (let [(lower (stringLower raw))
        (spaced (fold (fn [(acc String) (ch String)] -> String (stringReplace acc ch " ")) lower (list "(" ")" "[" "]" ",")))]
    (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (map stripQuotesColons (pySplit spaced))))

fn dedupe xs: (List String) acc: (List String) -> (List String)
  (mt (listHead xs)
    ((none) (listReverse acc))
    ((some x) (dedupe (optionOr (listTail xs) (list)) (if (listContains? acc x) acc (cons x acc)))))

fn opusProfile? p: String -> Bool
  (listContains? (list "opusluna" "opus" "agy-opus" "agyopus" "antigravityclaude" "claude-opus" "claudeopus" "adieopus" "adie-opus" "addieopus" "addie-opus" "opus4.6" "opus-4-6" "opus-5") p)

fn modelFor kw: (Map String String) profileLower: String -> String
  (if (or (listContains? (list "true" ":true") (optionOr (mapGet kw "cognitive") "")) (= (optionOr (mapGet kw "mode") "") "cognitive"))
    (cond
      ((opusProfile? profileLower) "claude-opus-5")
      ((= profileLower "freetier") "groq/qwen/qwen3.8-27b")
      ((= profileLower "frontier") "deepseek/deepseek-chat:free")
      (else "asl-local"))
    "asl-substrate")

fn ! assemble sc: LensScope st0: LensState id: Int64 target: String scopeLabel: String kw: (Map String String) requested: (List String) -> d/Outcome
  (let [(statusOf (fn [(l String)] -> String (optionOr (mapGet st0.status l) "")))
        (executed (filter (fn [(l String)] -> Bool (listContains? (list "pass" "fail") (statusOf l))) requested))
        (unmeasured (filter (fn [(l String)] -> Bool (= (statusOf l) "unmeasured")) requested))
        (passed (filter (fn [(l String)] -> Bool (= (statusOf l) "pass")) executed))
        (failed (filter (fn [(l String)] -> Bool (= (statusOf l) "fail")) executed))
        (st1 (fold (fn [(s LensState) (l String)] -> LensState (finding s l "medium" (str "Lens requested but not evaluated; no measurement performed for " l))) st0 unmeasured))
        (score (if (listEmpty? executed) "0.00" (fixedRatio (listLength passed) (listLength executed) 2)))
        (verdict (cond ((listEmpty? executed) ":unverified") ((not (listEmpty? failed)) ":gapsDetected") ((not (listEmpty? unmeasured)) ":partial") (else ":certified")))
        (profile (d/pyStrip (k/lstripColons (k/kwOr kw "profile" "freeTier"))))
        (r (gitRemotes sc st1))
        (rems (pairFirst r))
        (st (pairSecond r))
        (results (map (fn [(l String)] -> String (str "(:lensResult :id \"" l "\" :status :" (statusOf l) " :metrics " (optionOr (mapGet st.metrics l) "") ")")) executed))
        (certified (= verdict ":certified"))]
    (d/Outcome :line (str (d/stepHead id "lens") " :status \"" (if certified "ok" "rejected") "\" :receipt (:lensAudit :target \"" (k/escapeAsnVal target) "\" :scope " scopeLabel
                          " :profile :" profile " :model \"" (k/escapeAsnVal (modelFor kw (stringLower profile))) "\" :status " verdict " :consensusScore " score
                          " :lensesRequested " (num (listLength requested)) " :lensesExecuted " (num (listLength executed)) " :lensesPassed " (num (listLength passed))
                          " :lensesFailed " (num (listLength failed)) " :lensesUnmeasured " (num (listLength unmeasured)) " :lenses " (quotedList executed)
                          " :lensesNotEvaluated " (quotedList unmeasured) " :lensesResults [" (stringJoin results " ") "] :findings [" (stringJoin (listReverse st.findings) " ")
                          "] :sovereignty (:zeroRemote " (asnBool (listEmpty? rems)) " :remotesCount " (num (listLength rems)) " :v0Preserved " (asnBool (listEmpty? rems)) ")))")
               :errCount (if certified 0 1)))

fn emptyState -> LensState
  (LensState :lists (mapEmpty) :skipped 0 :tel (mapEmpty) :intel (mapEmpty) :status (mapEmpty) :metrics (mapEmpty) :findings (list))

(schema Resolved (:f code String) (:f msg String) (:f whole Bool) (:f scopeRoot String) (:f path String))

fn ! resolveTarget root: String target: String isFileArg: Bool -> Resolved
  (let [(rootNorm (k/normalizePath root))
        (whole (and (listContains? (list "workspace" "repo" "monorepo" "." "all") target) (not isFileArg)))]
    (if whole
      (Resolved :code "" :msg "" :whole true :scopeRoot rootNorm :path "")
      (let [(path (if (stringStartsWith? target "/") target (k/normalizePath (k/joinPath rootNorm target))))]
        (cond
          ((not (or (= path rootNorm) (stringStartsWith? path (str rootNorm "/"))))
            (Resolved :code ":ERR_TARGET_OUTSIDE_ROOT" :msg (str "Target escapes workspace containment: " target) :whole false :scopeRoot rootNorm :path path))
          ((not (fileExists? path))
            (Resolved :code (if isFileArg ":ERR_FILE_NOT_FOUND" ":ERR_TARGET_NOT_FOUND") :msg (str "Target not found: " target) :whole false :scopeRoot rootNorm :path path))
          ((k/isDir! path)
            (if isFileArg
              (Resolved :code ":ERR_FILE_NOT_FOUND" :msg (str "Target is a directory, regular file expected: " target) :whole false :scopeRoot rootNorm :path path)
              (Resolved :code "" :msg "" :whole true :scopeRoot path :path path)))
          ((not (k/isFile! path))
            (Resolved :code ":ERR_TARGET_NOT_FOUND" :msg (str "Target is not a regular file: " target) :whole false :scopeRoot rootNorm :path path))
          (else (Resolved :code "" :msg "" :whole false :scopeRoot rootNorm :path path))))))

fn lensReject id: Int64 code: String msg: String -> d/Outcome
  (d/Outcome :line (str (d/stepHead id "lens") " :status \"rejected\" :error-code \"" code "\" :message \"" (k/escapeAsnVal msg) "\")") :errCount 1)

fn ! lensStep root: String id: Int64 kw: (Map String String) args: (List String) -> d/Outcome
  (let [(targetF (k/kwOr kw "file" (k/kwOr kw "path" "")))
        (targetT (k/kwOr kw "target" (k/kwOr kw "text" "")))
        (target (cond ((not (stringEmpty? targetF)) targetF) ((not (stringEmpty? targetT)) targetT) (else (optionOr (listHead args) "workspace"))))
        (res (resolveTarget root target (not (stringEmpty? targetF))))]
    (if (not (stringEmpty? res.code))
      (lensReject id res.code res.msg)
      (let [(raw (requestedTokens (k/kwOr kw "lenses" (k/kwOr kw "lens" "invariants"))))
            (aliases (lensAliases))
            (unknown (filter (fn [(l String)] -> Bool (not (or (= l "all") (listContains? (canonicalLenses) l) (mapHas? aliases l)))) raw))
            (requested (if (listContains? raw "all") (canonicalLenses) (dedupe (map (fn [(l String)] -> String (optionOr (mapGet aliases l) l)) raw) (list))))
            (sc (LensScope :root root :scopeRoot res.scopeRoot))]
        (cond
          ((not (listEmpty? unknown)) (lensReject id ":ERR_UNKNOWN_LENS" (str "Unknown audit lens(es): " (stringJoin unknown ", "))))
          ((listEmpty? requested) (lensReject id ":ERR_UNKNOWN_LENS" "No audit lenses requested"))
          (res.whole (assemble sc (fold (fn [(s LensState) (l String)] -> LensState (repoLens sc s l)) (emptyState) requested) id target ":workspace" kw requested))
          (else
            (mt (readRel sc res.path)
              ((none) (lensReject id ":ERR_TARGET_UNREADABLE" (str "Target could not be read: " target)))
              ((some content)
                (let [(ext (stringLower (d/pyExt res.path)))]
                  (assemble sc (fold (fn [(s LensState) (l String)] -> LensState (fileLens sc s l target res.path ext content)) (emptyState) requested) id target ":file" kw requested)))))))))
