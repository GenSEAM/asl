(module asl-intel/sweep
  :x [Sweep sweepMonorepo! balanceError pyOsError runSweep!]
  :i [(asl-intel/text :a t)
      (asl-intel/host :a h)])

(schema Sweep
  (:f ok Bool)
  (:f count Int64)
  (:f errors (List (Pair String String)))
  (:f out String)
  (:f err String))

fn errnoOf reason: String -> Int64
  (cond
    ((= reason "No such file or directory") 2)
    ((= reason "Permission denied") 13)
    ((= reason "Operation not permitted") 1)
    ((= reason "Not a directory") 20)
    ((= reason "Is a directory") 21)
    ((= reason "Read-only file system") 30)
    (else -1))

fn pyOsError path: String hostErr: String -> String
  (let [(tail (str ": " path ": "))
        (b (stringToBytes hostErr)) (tb (stringToBytes tail))
        (at (t/bytesIndexOf b (bytesLength b) tb (bytesLength tb) 0))
        (reason (if (< at 0) "" (t/sliceStr hostErr (+ at (bytesLength tb)) (bytesLength b))))
        (no (errnoOf reason))]
    (if (< no 0) hostErr (str "[Errno " (t/intStr no) "] " reason ": " (t/pyReprStr path))))

fn balanceError s: String -> (Option String)
  (let [(b (stringToBytes s))] (scan b (bytesLength b) 0 0 false false (list)))

fn scan b: Bytes n: Int64 i: Int64 ci: Int64 inStr: Bool esc: Bool stack: (List Int64) -> (Option String)
  (if (>= i n)
    (cond
      (inStr (some "unclosed string"))
      ((not (listEmpty? stack)) (some (str "unclosed delimiters: " (t/concatAll (map (fn [(c Int64)] -> String (t/charStr c)) (listReverse stack))))))
      (else (none)))
    (let [(x (bytesGet b i))
          (ci2 (if (and (>= x 128) (< x 192)) ci (+ ci 1)))
          (idx (- ci2 1))]
      (cond
        ((and (>= x 128) (< x 192)) (scan b n (+ i 1) ci inStr esc stack))
        (inStr (cond
                 (esc (scan b n (+ i 1) ci2 true false stack))
                 ((= x 92) (scan b n (+ i 1) ci2 true true stack))
                 ((= x 34) (scan b n (+ i 1) ci2 false false stack))
                 (else (scan b n (+ i 1) ci2 true false stack))))
        ((= x 34) (scan b n (+ i 1) ci2 true false stack))
        ((or (= x 40) (or (= x 91) (= x 123))) (scan b n (+ i 1) ci2 false false (cons x stack)))
        ((or (= x 41) (or (= x 93) (= x 125)))
          (let [(want (cond ((= x 41) 40) ((= x 93) 91) (else 123)))]
            (if (= (optionOr (listHead stack) -1) want)
              (scan b n (+ i 1) ci2 false false (optionOr (listTail stack) (list)))
              (some (str "unexpected " (t/charStr x) " at byte " (t/intStr idx))))))
        (else (scan b n (+ i 1) ci2 false false stack)))))

fn sweepFiles! ctx: h/Ctx root: String -> (Result (List String) String)
  (mt (h/gitLsFiles! ctx root)
    ((ok fs) (ok (filter (fn [(f String)] -> Bool (or (stringEndsWith? f ".asl") (stringEndsWith? f ".asn"))) fs)))
    ((err _)
      (mt (h/findTree! ctx root true (list "*.asl" "*.asn"))
        ((err e) (err e))
        ((ok tree) (ok (map (fn [(f String)] -> String (t/relPath f root ctx.cwd)) (h/walkFiles! tree)))))))

fn checkFile! root: String f: String -> (Option String)
  (let [(full (t/joinPath root f))]
    (if (h/isDir? full) (some (str "[Errno 21] Is a directory: " (t/pyReprStr full)))
      (mt (h/readText! full)
        ((err e) (some (pyOsError full e)))
        ((ok s) (balanceError s)))))

fn sweepMonorepo! ctx: h/Ctx root: String verbose: Bool -> (Result Sweep String)
  (mt (sweepFiles! ctx root)
    ((err e) (err e))
    ((ok files)
      (let [(errs (listReverse (fold (fn [(acc (List (Pair String String))) (f String)] -> (List (Pair String String))
                                       (if (stringContains? f "/invalid/") acc
                                         (mt (checkFile! root f) ((some m) (cons (pair f m) acc)) ((none) acc))))
                                     (list) files)))
            (k (listLength files))
            (head "--> Checking monorepo-wide S-expression delimiter balance across all git-tracked files...")]
        (if (listEmpty? errs)
          (ok (Sweep :ok true :count k :errors errs
                     :out (if verbose (str head "\n    ✓ 100% balanced across all " (t/intStr k) " git-tracked ASL/ASN files.\n") "") :err ""))
          (ok (Sweep :ok false :count k :errors errs :out ""
                     :err (if verbose
                            (t/concatAll (listAppend (list head "\n    ✗ Delimiter errors in " (t/intStr (listLength errs)) " files across monorepo:\n")
                                                     (map (fn [(pr (Pair String String))] -> String (str "      - " (pairFirst pr) ": " (pairSecond pr) "\n")) (t/takeN errs 10))))
                            "")))))))

fn runSweep! ctx: h/Ctx -> h/Outcome
  (mt (sweepMonorepo! ctx ctx.home true)
    ((err e) (h/outcome "" (str "Error: " e "\n") 1))
    ((ok sw) (h/outcome sw.out sw.err (if sw.ok 0 1))))
