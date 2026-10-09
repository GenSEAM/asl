(module asl-intel/stubs
  :x [Header StubFinding StubSummary parenTrim constSpan? headersOf! headerParams constantBody? paramsUnused? placeholder? trackedAsl! analyzeStubs! stubsJson stubJson formatStubsAsn formatStubsSummary runStubs!]
  :i [(asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/json :a j)
      (asl-intel/host :a h)
      (asl-intel/deadcode :a dc)])

(schema Header
  (:f rawName String)
  (:f params String)
  (:f ret String)
  (:f start Int64)
  (:f bodyStart Int64)
  (:f bodyEnd Int64))

(schema StubFinding
  (:f file String)
  (:f function String)
  (:f kind String)
  (:f params (List String))
  (:f body String)
  (:f returnType String)
  (:f reason String))

(schema StubSummary
  (:f files Int64)
  (:f functions Int64)
  (:f stubs (List StubFinding)))

fn headersOf! code: String b: Bytes n: Int64 -> (List Header)
  (let [(ms (r/rexFindAll (p/patFnHeader!) b n))
        (starts (listAppend (optionOr (listTail (map (fn [(c (List Int64))] -> Int64 (optionOr (listGet c 0) 0)) ms)) (list)) (list n)))]
    (map (fn [(pr (Pair (List Int64) Int64))] -> Header
           (let [(c (pairFirst pr))]
             (Header :rawName (t/pyStrip (optionOr (r/rexGroup code c 1) ""))
                     :params (t/pyStrip (optionOr (r/rexGroup code c 2) ""))
                     :ret (t/pyStrip (optionOr (r/rexGroup code c 3) ""))
                     :start (optionOr (listGet c 0) 0)
                     :bodyStart (optionOr (listGet c 1) 0)
                     :bodyEnd (pairSecond pr))))
         (zip ms starts)))

fn headerParams paramsStr: String -> (List String)
  (let [(raw (map (fn [(q String)] -> String (t/lstripSet (t/pyStrip (optionOr (listHead (stringSplit q ":")) "")) "("))
                  (filter (fn [(q String)] -> Bool (or (stringContains? q ":") (and (not (stringEmpty? q)) (and (not (stringStartsWith? q "(")) (not (stringStartsWith? q "["))))))
                          (t/pySplit paramsStr))))]
    (filter (fn [(q String)] -> Bool (and (not (stringEmpty? q)) (not (listContains? (list "fn" "defn" "->" "!") q)))) raw))

fn trivialConsts -> (List String)
  (list "true" "false" "nil" "\"\"" "0" "[]" "()" "(ok true)" "(ok nil)" "(ok ())" "(list)" "list")

fn parenTrim b: Bytes s: Int64 e: Int64 -> (Pair Int64 Int64)
  (cond
    ((and (< s e) (paren? (bytesGet b s))) (parenTrim b (+ s 1) e))
    ((and (< s e) (paren? (bytesGet b (- e 1)))) (parenTrim b s (- e 1)))
    (else (pair s e)))

fn paren? c: Int64 -> Bool
  (or (= c 40) (= c 41))

fn constSpan? code: String s: Int64 e: Int64 -> Bool
  (and (<= (- e s) 9) (listContains? (trivialConsts) (t/sliceStr code s e)))

fn paramsUnused? params: (List String) body: String -> Bool
  (listAll? (fn [(q String)] -> Bool (not (t/wordHas? body q))) params)

fn sigils -> (List Bytes)
  (map stringToBytes (list "TODO" "UNIMPLEMENTED" "NOT_IMPLEMENTED" "STUB_EVASION"))

fn sigilFirsts -> Bytes
  (let [(tbl (bytesAlloc 256))]
    (do (bytesSet tbl 84 1) (bytesSet tbl 116 1) (bytesSet tbl 85 2) (bytesSet tbl 117 2)
        (bytesSet tbl 78 3) (bytesSet tbl 110 3) (bytesSet tbl 83 4) (bytesSet tbl 115 4) tbl))

fn sigilHits b: Bytes n: Int64 tbl: Bytes ws: (List Bytes) i: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n) (listReverse acc)
    (let [(code (bytesGet tbl (bytesGet b i)))]
      (if (= code 0) (sigilHits b n tbl ws (+ i 1) acc)
        (let [(w (optionOr (listGet ws (- code 1)) (bytesAlloc 0))) (k (bytesLength w))]
          (if (and (> k 0) (= (t/foldIndexOf b (min n (+ i k)) w k i) i))
            (sigilHits b n tbl ws (+ i 1) (cons (pair i k) acc))
            (sigilHits b n tbl ws (+ i 1) acc))))))

fn placeholder? b: Bytes hits: (List (Pair Int64 Int64)) s: Int64 e: Int64 -> Bool
  (listAny? (fn [(h (Pair Int64 Int64))] -> Bool
              (let [(j (pairFirst h)) (x (+ (pairFirst h) (pairSecond h)))]
                (and (and (>= j s) (<= x e))
                     (and (or (= j s) (not (t/wordBefore? b e j))) (or (= x e) (not (t/wordAt? b e x)))))))
            hits)

fn trackedAsl! ctx: h/Ctx root: String -> (Result (List String) String)
  (mt (h/gitLsFiles! ctx root)
    ((ok fs) (ok (filter (fn [(f String)] -> Bool (and (stringEndsWith? f ".asl") (not (stringContains? f "/invalid/")))) fs)))
    ((err _)
      (mt (dc/walkIgnoring! ctx root)
        ((err e) (err e))
        ((ok fs) (ok (map (fn [(f String)] -> String (t/relPath f root ctx.cwd)) fs))))))

fn classify rel: String isTest: Bool code: String b: Bytes hits: (List (Pair Int64 Int64)) hd: Header -> (Option StubFinding)
  (let [(n (bytesLength b))
        (bs (t/skipSpace b n hd.bodyStart))
        (be (t/trimSpaceBack b n bs hd.bodyEnd))
        (clean (parenTrim b bs be))
        (isConst (or (constSpan? code bs be) (constSpan? code (pairFirst clean) (pairSecond clean))))
        (name hd.rawName)]
    (if (not isConst)
      (if (placeholder? b hits bs be) (some (placeholderStub rel name code b bs be hd)) (none))
      (constStub rel isTest name code (t/sliceStr code bs be) b hits bs be hd)))

fn placeholderStub rel: String name: String code: String b: Bytes bs: Int64 be: Int64 hd: Header -> StubFinding
  (StubFinding :file rel :function name :kind "placeholder" :params (headerParams hd.params)
        :body (stringReplace (t/sliceStr code bs (t/cpOffset b be bs 50)) "\n" " ") :returnType hd.ret
        :reason "Function contains placeholder/unimplemented sigils")

fn constStub rel: String isTest: Bool name: String code: String body: String b: Bytes hits: (List (Pair Int64 Int64)) bs: Int64 be: Int64 hd: Header -> (Option StubFinding)
  (let [(params (headerParams hd.params))]
    (cond
      ((and (not (listEmpty? params)) (paramsUnused? params body))
        (some (StubFinding :file rel :function name :kind "ignored-params" :params params :body body :returnType hd.ret
                    :reason (str "Declared parameters " (t/pyReprList params) " are ignored; returns constant " body))))
      ((and isTest (and (or (stringStartsWith? name "test") (or (stringStartsWith? name "RunTests") (stringStartsWith? name "runTests")))
                        (and (not (stringContains? body "assert")) (not (stringContains? body "refute")))))
        (some (StubFinding :file rel :function name :kind "vacuous-test" :params params :body body :returnType hd.ret
                    :reason "Test function returns constant without executed assertions (D81 pass fraud)")))
      ((placeholder? b hits bs be) (some (placeholderStub rel name code b bs be hd)))
      (else (none))))

fn analyzeStubs! ctx: h/Ctx root: String -> (Result StubSummary String)
  (mt (trackedAsl! ctx root)
    ((err e) (err e))
    ((ok files)
      (ok (inOrder (fold (fn [(st StubSummary) (rel String)] -> StubSummary
                  (mt (h/readText! (if (stringStartsWith? rel "/") rel (t/joinPath root rel)))
                    ((err _) st)
                    ((ok code)
                      (let [(b (stringToBytes code)) (hs (headersOf! code b (bytesLength b)))
                            (hits (sigilHits b (bytesLength b) (sigilFirsts) (sigils) 0 (list)))
                            (isTest (or (stringContains? rel "/tests/") (stringEndsWith? rel "Test.asl")))
                            (found (fold (fn [(acc (List StubFinding)) (hd Header)] -> (List StubFinding)
                                           (mt (classify rel isTest code b hits hd) ((some s) (cons s acc)) ((none) acc)))
                                         (list) hs))]
                        (StubSummary :files st.files :functions (+ st.functions (listLength hs))
                                    :stubs (listAppend found st.stubs))))))
                (StubSummary :files (listLength files) :functions 0 :stubs (list)) files)))))

fn inOrder res: StubSummary -> StubSummary
  (with res :stubs (listReverse res.stubs))

fn formatStubsAsn res: StubSummary -> String
  (t/joinWith (list "(:stubAudit" "  :status :ok"
                    (str "  :totalFilesScanned " (t/intStr res.files))
                    (str "  :totalFunctionsScanned " (t/intStr res.functions))
                    (str "  :stubsCount " (t/intStr (listLength res.stubs)))
                    (str "  :assertCount " (t/intStr res.functions))
                    (if (listEmpty? res.stubs) "  :stubs []"
                      (str "  :stubs [\n    " (t/joinWith (map (fn [(s StubFinding)] -> String (str "(:stub :file \"" s.file "\" :function \"" s.function "\" :kind \"" s.kind "\" :reason \"" s.reason "\")")) res.stubs) "\n    ") "\n  ]"))
                    ")")
              "\n")

fn formatStubsSummary res: StubSummary -> String
  (t/joinWith (listAppend
                (list "=== ASL FALSIFICATION, TRIVIAL RETURN & STUB AUDIT (ADR D81) ==="
                      (str "Files Scanned:       " (t/intStr res.files))
                      (str "Functions Scanned:   " (t/intStr res.functions))
                      (str "Flagged Stubs Count: " (t/intStr (listLength res.stubs))))
                (if (listEmpty? res.stubs)
                  (list "" "  ✓ Zero stub evasions or trivial functions detected.")
                  (cons "" (cons "--- Flagged Stubs & Trivial Implementations ---"
                    (map (fn [(s StubFinding)] -> String (str "  • [" s.kind "] " s.file " [" s.function "]: " s.reason)) res.stubs)))))
              "\n")

fn stubJson s: StubFinding -> j/Json
  (j/jObj (list (pair "file" (j/jStr s.file)) (pair "function" (j/jStr s.function)) (pair "kind" (j/jStr s.kind))
                (pair "params" (j/jStrs s.params)) (pair "body" (j/jStr s.body)) (pair "returnType" (j/jStr s.returnType))
                (pair "reason" (j/jStr s.reason))))

fn stubsJson res: StubSummary -> j/Json
  (j/jObj (list (pair "status" (j/jStr "ok"))
                (pair "totalFilesScanned" (j/jInt res.files))
                (pair "totalFunctionsScanned" (j/jInt res.functions))
                (pair "stubsCount" (j/jInt (listLength res.stubs)))
                (pair "stubs" (j/jArr (map stubJson res.stubs)))
                (pair "assertCount" (j/jInt res.functions))))

fn runStubs! ctx: h/Ctx fmt: String strict: Bool -> h/Outcome
  (mt (analyzeStubs! ctx ctx.home)
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok res)
      (let [(out (str (cond ((= fmt "json") (j/dumps (stubsJson res))) ((= fmt "summary") (formatStubsSummary res)) (else (formatStubsAsn res))) "\n"))
            (ns (listLength res.stubs))]
        (if (and strict (> ns 0))
          (h/outcome out (str "Error: " (t/intStr ns) " stub evasions / trivial functions detected!\n") 1)
          (h/outcome out "" 0)))))
