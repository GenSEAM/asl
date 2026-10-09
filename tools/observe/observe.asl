(module ws/asl/tools/observe/observe
  :x [runObserve main]
  :i [(ws/asl/tools/observe/common :a c)
      (ws/asl/tools/observe/args :a a)
      (ws/asl/tools/observe/memory :a mem)
      (ws/asl/tools/observe/session :a ses)
      (ws/asl/tools/observe/callers :a cal)
      (ws/asl/tools/observe/status :a sts)
      (ws/asl/tools/observe/coverage :a cov)
      (ws/asl/tools/observe/tokenCost :a tc)
      (asl-regex/regex :a re)])

fn dims -> (List String)
  (list "tokenCost" "memory" "session" "callers" "status" "coverage")

fn listDims? dim: String -> Bool
  (or (= dim "callers") (= dim "status") (= dim "coverage"))

fn finish r: (Result String String) -> c/Outcome
  (mt r ((ok receipt) (c/Outcome :out (str receipt "\n") :err "" :code 0)) ((err line) (c/rejected line)))

fn crashOr r: (Result String String) -> c/Outcome
  (mt r
    ((ok receipt) (c/Outcome :out (str receipt "\n") :err "" :code 0))
    ((err line) (if (stringStartsWith? line "(:observe ") (c/rejected line) (c/crashed line))))

fn warned wr: (Pair String (Result String String)) -> c/Outcome
  (let [(o (crashOr (pairSecond wr)))]
    (c/Outcome :out o.out :err (str (pairFirst wr) o.err) :code o.code))

fn parseLimit raw: String -> (Result Int64 String)
  (mt (c/pyIntText (c/lstripChars raw ":"))
    ((none) (err (c/rejectLine "ERR_BAD_ARG" (str ":limit must be an integer, got " raw) "")))
    ((some n)
      (let [(v (if (or (stringStartsWith? n "-") (> (stringLength n) 3)) (none) (stringToInt64 n)))]
        (mt v
          ((some k) (if (or (< k 1) (> k (c/limitMax))) (err (c/rejectLine "ERR_BAD_ARG" (str ":limit must be within 1.." (stringFromInt64 (c/limitMax)) ", got " n) "")) (ok k)))
          ((none) (err (c/rejectLine "ERR_BAD_ARG" (str ":limit must be within 1.." (stringFromInt64 (c/limitMax)) ", got " n) "")))))))

fn ! dispatch! ctx: c/Ctx args: a/Args dim: String limit: Int64 root: String scope: String -> c/Outcome
  (let [(symbol (c/pyStrip args.symbol)) (pathArg (c/pyStrip args.path))]
    (cond
      ((= dim "session") (crashOr (ses/observeSession! root limit ctx)))
      ((= dim "memory") (finish (mem/observeMemory! root ctx)))
      ((= dim "callers")
        (if (stringEmpty? symbol)
          (c/rejected (c/rejectLine "ERR_BAD_ARG" "callers needs :symbol <name>" ""))
          (warned (cal/observeCallers! root symbol (c/pyStrip args.module) limit ctx))))
      ((= dim "status")
        (if (= (not (stringEmpty? symbol)) (not (stringEmpty? pathArg)))
          (c/rejected (c/rejectLine "ERR_BAD_ARG" "status needs exactly one of :symbol <name> or :path <file>" ""))
          (mt (if (stringEmpty? pathArg) (ok "") (c/relPath! root pathArg ":path"))
            ((err line) (c/rejected line))
            ((ok path) (warned (sts/observeStatus! root symbol path limit ctx))))))
      ((= dim "coverage")
        (if (stringEmpty? (c/pyStrip args.spec))
          (c/rejected (c/rejectLine "ERR_BAD_ARG" "coverage needs :spec <file>" ""))
          (mt (c/relPath! root (c/pyStrip args.spec) ":spec")
            ((err line) (c/rejected line))
            ((ok spec)
              (if (not (c/isFile? (c/joinPath root spec)))
                (c/rejected (c/rejectLine "ERR_BAD_ARG" (str ":spec is not a file: " args.spec) ""))
                (if (stringEmpty? args.id)
                  (warned (cov/observeCoverage! root spec (none) limit ctx))
                  (mt (mt (unbalancedAt (stringToBytes args.id) 0 (bytesLength (stringToBytes args.id)) 0)
                        ((some i) (err (str "regex-compile: error at position " (stringFromInt64 i) ": unmatched close parenthesis ')'")))
                        ((none) (re/regex-compile! args.id)))
                    ((err e) (c/rejected (c/rejectLine "ERR_BAD_ARG" (str ":id is not a regular expression: " (pyRegexError e)) "")))
                    ((ok rx) (warned (cov/observeCoverage! root spec (some rx) limit ctx))))))))))
      ((= dim "tokenCost") (finish (tc/observeTokenCost! root scope limit ctx)))
      (else (c/rejected (c/rejectLine "ERR_UNKNOWN_DIM" (str "unknown dimension " dim) "")))))

fn classEnd bs: Bytes i: Int64 n: Int64 first: Bool -> Int64
  (cond
    ((>= i n) n)
    ((and first (= (bytesGet bs i) 94)) (classEnd bs (+ i 1) n true))
    ((and first (= (bytesGet bs i) 93)) (classEnd bs (+ i 1) n false))
    ((= (bytesGet bs i) 92) (classEnd bs (+ i 2) n false))
    ((= (bytesGet bs i) 93) (+ i 1))
    (else (classEnd bs (+ i 1) n false)))

fn unbalancedAt bs: Bytes i: Int64 n: Int64 depth: Int64 -> (Option Int64)
  (if (>= i n)
    (none)
    (let [(b (bytesGet bs i))]
      (cond
        ((= b 92) (unbalancedAt bs (+ i 2) n depth))
        ((= b 91) (unbalancedAt bs (classEnd bs (+ i 1) n true) n depth))
        ((= b 40) (unbalancedAt bs (+ i 1) n (+ depth 1)))
        ((= b 41) (if (= depth 0) (some i) (unbalancedAt bs (+ i 1) n (- depth 1))))
        (else (unbalancedAt bs (+ i 1) n depth)))))

fn pyRegexError e: String -> String
  (let [(rest (optionOr (stringSlice e (stringLength "regex-compile: error at position ") (stringLength e)) e))
        (colon (optionOr (stringIndexOf rest ": ") 0))
        (pos (optionOr (stringSlice rest 0 colon) ""))
        (what (optionOr (stringSlice rest (+ colon 2) (stringLength rest)) rest))]
    (cond
      ((stringStartsWith? what "unclosed group") (str "missing ), unterminated subpattern at position " pos))
      ((stringStartsWith? what "unclosed non-capturing group") (str "missing ), unterminated subpattern at position " pos))
      ((stringStartsWith? what "unmatched close parenthesis") (str "unbalanced parenthesis at position " pos))
      ((stringStartsWith? what "unclosed character class") (str "unterminated character set at position " pos))
      ((stringStartsWith? what "trailing backslash") (str "bad escape (end of pattern) at position " pos))
      (else (str what " at position " pos))))

fn ! runObserve ctx: c/Ctx argv: (List String) -> c/Outcome
  (mt (a/parseArgs argv)
    ((err o) o)
    ((ok args)
      (let [(dim (c/lstripChars (optionOr args.dim "") ":"))]
        (if (not (listContains? (dims) dim))
          (c/rejected (c/rejectLine "ERR_UNKNOWN_DIM" (str "unknown dimension " dim "; known: " (c/joinWith (dims) " "))
                                    (str " :dim " (c/quoted dim) " :nearest (" (c/joinWith (c/closeMatches dim (dims) 2 0.0) " ") ")")))
          (let [(rawLimit (if (stringEmpty? (c/pyStrip args.limit)) (if (listDims? dim) "100" "20") args.limit))]
            (mt (parseLimit rawLimit)
              ((err line) (c/rejected line))
              ((ok limit)
                (mt (c/workspace! ctx)
                  ((err line) (c/rejected line))
                  ((ok root)
                    (let [(scopeArg (c/pyStrip args.scope))]
                      (mt (if (stringEmpty? scopeArg) (ok "") (c/relPath! root scopeArg ":scope"))
                        ((err line) (c/rejected line))
                        ((ok scope) (dispatch! ctx args dim limit root scope)))))))))))))

fn envPair row: String -> (Pair String String)
  (mt (stringIndexOf row "=")
    ((some i) (pair (optionOr (stringSlice row 0 i) row) (optionOr (stringSlice row (+ i 1) (stringLength row)) "")))
    ((none) (pair row "")))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (realPath ".")
    ((err e) (err e))
    ((ok cwd)
      (let [(ctx (c/Ctx :cwd cwd :env (map envPair (envList)) :spawnEnv (none) :now (/ (nowNs) 1000000000) :date ""))
            (o (runObserve ctx args))]
        (do
          (if (stringEmpty? o.out) true (print o.out))
          (if (stringEmpty? o.err) true (do (fdWrite 2 o.err) true))
          (ok o.code)))))
