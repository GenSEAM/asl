(module asl-ir/blocks
  :x [BlockCtx blockCtx labelIndex paramNames locals tailCall collect exportName mangle quoted]
  :i [(asl-ir/types :a ty)])

fn identChar? c: String -> Bool
  (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (and (>= c "0") (<= c "9"))))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "0")

fn escapeChar escape: String c: String -> String
  (if (identChar? c) c (let [(n (charCode c))] (str escape (hexDigit (/ n 16)) (hexDigit (mod n 16)))))

fn mangle prefix: String escape: String name: String -> String
  (str prefix (stringJoin (map (fn [(c String)] -> String (escapeChar escape c)) (stringChars name)) ""))

fn replaceIn s: String old: String new: String -> String
  (if (stringContains? s old) (stringReplace s old new) s)

fn quoted s: String -> String
  (str "\"" (replaceIn (replaceIn (replaceIn (replaceIn (replaceIn s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\t" "\\t") "\"")

(schema BlockCtx (:f self String) (:f params (List String)) (:f labels (Map String Int64)) (:f params0 (Map String (List String))) (:f returners (List String)))

fn paramNames ps: (List ty/SsaParam) -> (List String)
  (map (fn [(p ty/SsaParam)] -> String p.name) ps)

fn soleParam b: ty/SsaBlock -> String
  (optionOr (listHead (paramNames b.params)) "")

fn forwards? known: (List String) b: ty/SsaBlock -> Bool
  (and (= (listLength b.params) 1)
    (and (listEmpty? b.instrs)
      (mt b.term
        ((ty/termReturn x) (= x (soleParam b)))
        ((ty/termJump e) (and (listContains? known e.target) (= e.args [(soleParam b)])))
        (_ false))))

fn returners known: (List String) blocks: (List ty/SsaBlock) -> (List String)
  (let [(next (map (fn [(b ty/SsaBlock)] -> String b.label) (filter (fn [(b ty/SsaBlock)] -> Bool (forwards? known b)) blocks)))]
    (if (= (listLength next) (listLength known)) known (returners next blocks)))

fn blockCtx fn0: ty/SsaFunction -> BlockCtx
  (BlockCtx :self fn0.name :params (paramNames fn0.params)
    :labels (fold (fn [(m (Map String Int64)) (p (Pair Int64 ty/SsaBlock))] -> (Map String Int64) (mapSet m (pairSecond p).label (pairFirst p))) (mapEmpty) (enumerate fn0.blocks))
    :params0 (fold (fn [(m (Map String (List String))) (b ty/SsaBlock)] -> (Map String (List String)) (mapSet m b.label (paramNames b.params))) (mapEmpty) fn0.blocks)
    :returners (returners [] fn0.blocks))

fn labelIndex ctx: BlockCtx label: String -> String
  (stringFromInt64 (optionOr (mapGet ctx.labels label) -1))

fn locals fn0: ty/SsaFunction -> (List String)
  (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
          (listAppend acc (listAppend (paramNames b.params) (map (fn [(i ty/SsaInstr)] -> String i.dest) b.instrs))))
        [] fn0.blocks)

fn tailCall ctx: BlockCtx b: ty/SsaBlock -> (Option (List String))
  (mt (listLast b.instrs)
    ((none) (none))
    ((some last)
      (mt last.op
        ((ty/opCall callee xs)
          (let [(returnsIt (mt b.term
                             ((ty/termReturn x) (= x last.dest))
                             ((ty/termJump e) (and (listContains? ctx.returners e.target) (= e.args [last.dest])))
                             (_ false)))]
            (if (and returnsIt (and (= callee ctx.self) (= (listLength xs) (listLength ctx.params)))) (some xs) (none))))
        (_ (none)))))

fn collect results: (List (Result String String)) -> (Result (List String) (List String))
  (let [(bad (fold (fn [(acc (List String)) (r (Result String String))] -> (List String) (mt r ((err e) (cons e acc)) ((ok _) acc))) [] results))]
    (if (listEmpty? bad) (ok (map (fn [(r (Result String String))] -> String (mt r ((ok s) s) ((err _) ""))) results)) (err (listReverse bad))))

fn exportName moduleName: String fnName: String -> (Option String)
  (let [(prefix (str moduleName "."))]
    (if (and (stringStartsWith? fnName prefix) (not (stringContains? fnName "@")))
      (stringSlice fnName (stringLength prefix) (stringLength fnName))
      (none)))
