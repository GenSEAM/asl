(module ws/asl/tools/observe/common
  :x [Ctx Outcome Proc Section
      ctxEnv ctxHome esc rejectLine rejected crashed receiptMax limitMax
      runArgv! git! workspace! shortRev! workspaceFiles!
      joinPath dirName baseName splitExt isAbs lexists? isDir? isFile? isLink? realPathLoose! relPath!
      pyIntText lstripChars rstripChars stripChars pyStrip pyIsSpaceCode
      fitReceipt atStr quoted sortUnique dedupe byteLen lines keepEndsLines
      closeMatches charCodes utf8Replace mapGetOr utf8Valid? spaceLenAt findFrom universalNewlines catAll joinWith splitByte]
  :i [(asl-forms/similarity :a sim)])

(schema Ctx
  (:f cwd String)
  (:f env (List (Pair String String)))
  (:f spawnEnv (Option (List String)))
  (:f now Int64)
  (:f date String))

(schema Outcome (:f out String) (:f err String) (:f code Int64))

(schema Proc (:f code Int64) (:f out String) (:f errText String))

(schema Section (:f key String) (:f items (List String)) (:f limit Int64))

fn receiptMax -> Int64
  4096

fn limitMax -> Int64
  100

fn mapGetOr kv: (List (Pair String String)) k: String -> (Option String)
  (mt (listHead kv)
    ((none) (none))
    ((some p) (if (= (pairFirst p) k) (some (pairSecond p)) (mapGetOr (optionOr (listTail kv) (list)) k))))

fn ctxEnv ctx: Ctx k: String -> (Option String)
  (mapGetOr ctx.env k)

fn ctxHome ctx: Ctx -> String
  (optionOr (ctxEnv ctx "HOME") "")

fn esc s: String -> String
  (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn rejectLine code: String message: String extra: String -> String
  (str "(:observe :status :rejected :error " code extra " :message \"" (esc message) "\")")

fn rejected line: String -> Outcome
  (Outcome :out (str line "\n") :err "" :code 1)

fn crashed message: String -> Outcome
  (Outcome :out "" :err (str message "\n") :code 1)

fn quoted s: String -> String
  (str "\"" (esc s) "\"")

fn atStr rel: String line: Int64 -> String
  (str "\"" (esc rel) ":" (stringFromInt64 line) "\"")

fn byteLen s: String -> Int64
  (stringLength s)

(schema Pump (:f outOpen Bool) (:f errOpen Bool) (:f out (List String)) (:f errs (List String)))

fn ! readSide fd: Int64 -> (Pair Bool String)
  (mt (fdRead fd 65536)
    ((ok chunk) (if (stringEmpty? chunk) (do (fdClose fd) (pair false "")) (pair true chunk)))
    ((err e) (if (= e "wouldBlock") (pair true "") (do (fdClose fd) (pair false "")))))

fn ! pump sp: SpawnedProc st: Pump -> Pump
  (if (not (or st.outOpen st.errOpen))
    st
    (let [(fds (listAppend (if st.outOpen (list (pair sp.stdout 1)) (list)) (if st.errOpen (list (pair sp.stderr 1)) (list))))]
      (mt (fdPoll fds 60000)
        ((err e) (if (= e "interrupted") (pump sp st) (with st :outOpen false :errOpen false :errs (cons (str "poll: " e) st.errs))))
        ((ok ready)
          (let [(ro (and st.outOpen (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) sp.stdout)) ready)))
                (re (and st.errOpen (listAny? (fn [(p (Pair Int64 Int64))] -> Bool (= (pairFirst p) sp.stderr)) ready)))
                (o (if ro (readSide sp.stdout) (pair st.outOpen "")))
                (e2 (if re (readSide sp.stderr) (pair st.errOpen "")))]
            (pump sp (Pump :outOpen (pairFirst o) :errOpen (pairFirst e2)
                           :out (if (stringEmpty? (pairSecond o)) st.out (cons (pairSecond o) st.out))
                           :errs (if (stringEmpty? (pairSecond e2)) st.errs (cons (pairSecond e2) st.errs)))))))))

fn ! runArgv! argv: (List String) cwd: String ctx: Ctx -> (Result Proc String)
  (mt (procSpawnv argv (some cwd) ctx.spawnEnv)
    ((err e) (err e))
    ((ok sp)
      (do
        (fdClose sp.stdin)
        (let [(st (pump sp (Pump :outOpen true :errOpen true :out (list) :errs (list))))]
          (mt (procWaitPid sp.pid false)
            ((err e) (err e))
            ((ok code) (ok (Proc :code (optionOr code -1) :out (catAll (listReverse st.out)) :errText (catAll (listReverse st.errs))))))))))

fn ! git! args: (List String) root: String ctx: Ctx -> (Result (Pair Int64 String) String)
  (mt (runArgv! (cons "git" args) root ctx)
    ((ok p) (ok (pair p.code p.out)))
    ((err e) (err (rejectLine "ERR_TOOL_ABSENT" (str "git could not be run (" e "); observe reads the workspace through git") ""))))

fn ! workspace! ctx: Ctx -> (Result String String)
  (mt (git! (list "rev-parse" "--show-toplevel") ctx.cwd ctx)
    ((err e) (err e))
    ((ok p) (let [(top (pyStrip (pairSecond p)))] (ok (if (and (= (pairFirst p) 0) (not (stringEmpty? top))) top ctx.cwd)))))

fn ! shortRev! root: String ctx: Ctx -> (Result String String)
  (mt (git! (list "rev-parse" "--short" "HEAD") root ctx)
    ((err e) (err e))
    ((ok p) (let [(r (pyStrip (pairSecond p)))] (ok (if (and (= (pairFirst p) 0) (not (stringEmpty? r))) r "none")))))

fn ! workspaceFiles! root: String ctx: Ctx -> (Result (List String) String)
  (mt (git! (list "ls-files" "-z" "-co" "--exclude-standard") root ctx)
    ((err e) (err e))
    ((ok p)
      (if (!= (pairFirst p) 0)
        (err (rejectLine "ERR_GIT" (str "git ls-files failed in " root) ""))
        (ok (filter (fn [(rel String)] -> Bool (isFile? (joinPath root rel)))
                    (sortUnique (filter (fn [(x String)] -> Bool (not (stringEmpty? x))) (splitByte (pairSecond p) 0))))))))

fn isAbs p: String -> Bool
  (stringStartsWith? p "/")

fn joinPath a: String b: String -> String
  (cond ((isAbs b) b) ((stringEmpty? a) b) ((stringEndsWith? a "/") (str a b)) (else (str a "/" b)))

fn lastSlash s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (optionOr (stringSlice s i (+ i 1)) "") "/") i) (else (lastSlash s (- i 1))))

fn dirName p: String -> String
  (let [(i (lastSlash p (- (stringLength p) 1)))]
    (if (< i 0) "" (let [(head (optionOr (stringSlice p 0 (+ i 1)) ""))] (let [(t (rstripChars head "/"))] (if (stringEmpty? t) head t)))))

fn baseName p: String -> String
  (let [(i (lastSlash p (- (stringLength p) 1)))]
    (optionOr (stringSlice p (+ i 1) (stringLength p)) p))

fn lastDot s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (optionOr (stringSlice s i (+ i 1)) "") ".") i) (else (lastDot s (- i 1))))

fn allDots? s: String i: Int64 -> Bool
  (cond ((< i 0) true) ((= (optionOr (stringSlice s i (+ i 1)) "") ".") (allDots? s (- i 1))) (else false))

fn splitExt p: String -> (Pair String String)
  (let [(b (baseName p)) (i (lastDot b (- (stringLength b) 1)))]
    (if (or (< i 0) (allDots? b (- i 1)))
      (pair p "")
      (let [(cut (- (stringLength p) (- (stringLength b) i)))]
        (pair (optionOr (stringSlice p 0 cut) p) (optionOr (stringSlice p cut (stringLength p)) "")))))

fn ! lexists? p: String -> Bool
  (ok? (fileStat p))

fn ! isDir? p: String -> Bool
  (mt (fileStat p) ((ok s) s.isDir) ((err _) false))

fn ! isFile? p: String -> Bool
  (mt (fileStat p) ((ok s) s.isFile) ((err _) false))

fn ! isLink? p: String -> Bool
  (let [(parent (dirName p)) (name (baseName p))]
    (mt (realPath p)
      ((err _) false)
      ((ok r) (mt (realPath (if (stringEmpty? parent) "." parent))
                ((ok pr) (!= r (joinPath pr name)))
                ((err _) false)))))

fn loosePart! cur: String parts: (List String) -> String
  (mt (listHead parts)
    ((none) (if (stringEmpty? cur) "/" cur))
    ((some c)
      (let [(rest (optionOr (listTail parts) (list)))]
        (cond
          ((or (stringEmpty? c) (= c ".")) (loosePart! cur rest))
          ((= c "..") (loosePart! (let [(d (dirName cur))] (if (= d "/") "" d)) rest))
          (else (let [(nxt (str cur "/" c))]
                  (mt (realPath nxt)
                    ((ok r) (loosePart! (if (= r "/") "" r) rest))
                    ((err _) (loosePart! nxt rest)))))))))

fn realPathLoose! p: String cwd: String -> String
  (let [(full (if (isAbs p) p (joinPath cwd p)))]
    (loosePart! "" (stringSplit full "/")))

fn relPath! root: String arg: String what: String -> (Result String String)
  (let [(full (realPathLoose! (joinPath root arg) root))
        (base (realPathLoose! root root))]
    (cond
      ((and (!= full base) (not (stringStartsWith? full (str base "/"))))
        (err (rejectLine "ERR_BOUNDARY_VIOLATION" (str what " resolves outside the workspace: " arg) "")))
      ((not (lexists? full))
        (err (rejectLine "ERR_PATH_NOT_FOUND" (str what " not found: " arg) "")))
      ((= full base) (ok ""))
      (else (ok (optionOr (stringSlice full (+ (stringLength base) 1) (stringLength full)) "")))))

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn inChars? c: String chars: String -> Bool
  (and (not (stringEmpty? c)) (stringContains? chars c))

fn lstripFrom s: String chars: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (inChars? (charAt s i) chars)) (lstripFrom s chars (+ i 1)) i)

fn rstripFrom s: String chars: String i: Int64 -> Int64
  (if (and (> i 0) (inChars? (charAt s (- i 1)) chars)) (rstripFrom s chars (- i 1)) i)

fn lstripChars s: String chars: String -> String
  (optionOr (stringSlice s (lstripFrom s chars 0) (stringLength s)) "")

fn rstripChars s: String chars: String -> String
  (optionOr (stringSlice s 0 (rstripFrom s chars (stringLength s))) "")

fn stripChars s: String chars: String -> String
  (lstripChars (rstripChars s chars) chars)

fn pyIsSpaceCode c: Int64 -> Bool
  (or (and (>= c 9) (<= c 13)) (and (>= c 28) (<= c 32)) (= c 133) (= c 160) (= c 5760) (and (>= c 8192) (<= c 8202))
      (= c 8232) (= c 8233) (= c 8239) (= c 8287) (= c 12288))

fn contAt? bs: Bytes i: Int64 n: Int64 -> Bool
  (and (< i n) (>= (bytesGet bs i) 128) (<= (bytesGet bs i) 191))

fn codeAt bs: Bytes i: Int64 n: Int64 -> (Pair Int64 Int64)
  (let [(b0 (bytesGet bs i))
        (need (cond ((< b0 128) 1) ((and (>= b0 194) (< b0 224)) 2) ((and (>= b0 224) (< b0 240)) 3) ((and (>= b0 240) (< b0 245)) 4) (else 0)))]
    (cond
      ((= need 0) (pair -1 1))
      ((= need 1) (pair b0 1))
      (else
        (let [(lo1 (cond ((= b0 224) 160) ((= b0 240) 144) (else 128)))
              (hi1 (cond ((= b0 237) 159) ((= b0 244) 143) (else 191)))
              (b1 (if (< (+ i 1) n) (bytesGet bs (+ i 1)) -1))]
          (cond
            ((or (< b1 lo1) (> b1 hi1)) (pair -1 1))
            ((= need 2) (pair (+ (* (- b0 192) 64) (- b1 128)) 2))
            ((not (contAt? bs (+ i 2) n)) (pair -1 2))
            ((= need 3) (pair (+ (* (- b0 224) 4096) (* (- b1 128) 64) (- (bytesGet bs (+ i 2)) 128)) 3))
            ((not (contAt? bs (+ i 3) n)) (pair -1 3))
            (else (pair (+ (* (- b0 240) 262144) (* (- b1 128) 4096) (* (- (bytesGet bs (+ i 2)) 128) 64) (- (bytesGet bs (+ i 3)) 128)) 4)))))))

fn validLoop bs: Bytes i: Int64 n: Int64 -> Bool
  (cond
    ((>= i n) true)
    ((< (bytesGet bs i) 128) (validLoop bs (+ i 1) n))
    (else (let [(c (codeAt bs i n))] (if (< (pairFirst c) 0) false (validLoop bs (+ i (pairSecond c)) n)))))

fn utf8Valid? s: String -> Bool
  (let [(bs (stringToBytes s))] (validLoop bs 0 (bytesLength bs)))

fn spaceLenAt bs: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n)
    0
    (let [(b (bytesGet bs i))]
      (if (< b 128)
        (if (pyIsSpaceCode b) 1 0)
        (let [(c (codeAt bs i n))] (if (and (>= (pairFirst c) 0) (pyIsSpaceCode (pairFirst c))) (pairSecond c) 0)))))

fn matchAt bs: Bytes pat: Bytes i: Int64 k: Int64 m: Int64 -> Bool
  (cond ((>= k m) true) ((= (bytesGet bs (+ i k)) (bytesGet pat k)) (matchAt bs pat i (+ k 1) m)) (else false))

fn findFrom bs: Bytes n: Int64 pat: Bytes i: Int64 -> Int64
  (let [(m (bytesLength pat))]
    (cond ((> (+ i m) n) -1) ((matchAt bs pat i 0 m) i) (else (findFrom bs n pat (+ i 1)))))

fn codesLoop bs: Bytes i: Int64 n: Int64 acc: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (if (>= i n)
    (listReverse acc)
    (let [(c (codeAt bs i n))]
      (codesLoop bs (+ i (pairSecond c)) n (cons (pair (pairFirst c) i) acc))))

fn charCodes s: String -> (List (Pair Int64 Int64))
  (let [(bs (stringToBytes s))] (codesLoop bs 0 (bytesLength bs) (list)))

fn replaceLoop s: String bs: Bytes i: Int64 n: Int64 start: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse (cons (optionOr (stringSlice s start n) "") acc))
    (let [(c (codeAt bs i n))]
      (if (< (pairFirst c) 0)
        (replaceLoop s bs (+ i (pairSecond c)) n (+ i (pairSecond c)) (cons "\xef\xbf\xbd" (cons (optionOr (stringSlice s start i) "") acc)))
        (replaceLoop s bs (+ i (pairSecond c)) n start acc))))

fn utf8Replace s: String -> String
  (let [(bs (stringToBytes s))] (catAll (replaceLoop s bs 0 (bytesLength bs) 0 (list))))

fn pyStripStart codes: (List (Pair Int64 Int64)) -> (List (Pair Int64 Int64))
  (mt (listHead codes)
    ((none) codes)
    ((some c) (if (pyIsSpaceCode (pairFirst c)) (pyStripStart (optionOr (listTail codes) (list))) codes)))

fn pyStrip s: String -> String
  (let [(codes (pyStripStart (charCodes s)))]
    (mt (listHead codes)
      ((none) "")
      ((some first)
        (let [(back (pyStripStart (listReverse codes)))]
          (mt (listHead back)
            ((none) "")
            ((some last) (let [(endAt (+ (pairSecond last) (pairSecond (codeAt (stringToBytes s) (pairSecond last) (stringLength s)))))]
                           (optionOr (stringSlice s (pairSecond first) endAt) ""))))))))

fn digit? c: String -> Bool
  (and (= (stringLength c) 1) (>= (charCode c) 48) (<= (charCode c) 57))

fn digitsOk? s: String i: Int64 prevDigit: Bool -> Bool
  (if (>= i (stringLength s))
    prevDigit
    (let [(c (charAt s i))]
      (cond ((digit? c) (digitsOk? s (+ i 1) true))
            ((and (= c "_") prevDigit) (digitsOk? s (+ i 1) false))
            (else false))))

fn pyIntText raw: String -> (Option String)
  (let [(s (pyStrip raw))
        (neg (stringStartsWith? s "-"))
        (body (if (or neg (stringStartsWith? s "+")) (optionOr (stringSlice s 1 (stringLength s)) "") s))]
    (if (or (stringEmpty? body) (not (digit? (charAt body 0))) (not (digitsOk? body 0 false)))
      (none)
      (let [(digits (lstripChars (stringReplace body "_" "") "0"))
            (mag (if (stringEmpty? digits) "0" digits))]
        (some (if (and neg (!= mag "0")) (str "-" mag) mag)))))

fn sortUnique xs: (List String) -> (List String)
  (dedupe (listSort xs) (list))

fn dedupe xs: (List String) acc: (List String) -> (List String)
  (mt (listHead xs)
    ((none) (listReverse acc))
    ((some x) (dedupe (optionOr (listTail xs) (list)) (if (= (optionOr (listHead acc) "\x00none") x) acc (cons x acc)))))

fn linesLoop s: String i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (if (< start n) (cons (optionOr (stringSlice s start n) "") acc) acc)))
    ((= (charAt s i) "\n") (linesLoop s (+ i 1) (+ i 1) n (cons (optionOr (stringSlice s start (+ i 1)) "") acc)))
    (else (linesLoop s (+ i 1) start n acc)))

fn keepEndsLines s: String -> (List String)
  (let [(bs (stringToBytes s))] (keepEndsBytes s bs 0 0 (bytesLength bs) (list)))

fn keepEndsBytes s: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (if (< start n) (cons (optionOr (stringSlice s start n) "") acc) acc)))
    ((= (bytesGet bs i) 10) (keepEndsBytes s bs (+ i 1) (+ i 1) n (cons (optionOr (stringSlice s start (+ i 1)) "") acc)))
    (else (keepEndsBytes s bs (+ i 1) start n acc)))

fn catAll xs: (List String) -> String
  (let [(n (listLength xs))]
    (cond ((= n 0) "") ((= n 1) (optionOr (listHead xs) "")) ((= n 2) (stringConcat (optionOr (listHead xs) "") (optionOr (listGet xs 1) "")))
          (else (let [(h (/ n 2))] (stringConcat (catAll (listTake xs h)) (catAll (listDrop xs h)))))))

fn interleave xs: (List String) sep: String acc: (List String) -> (List String)
  (mt (listHead xs)
    ((none) (listReverse acc))
    ((some x) (interleave (optionOr (listTail xs) (list)) sep (cons x (if (listEmpty? acc) acc (cons sep acc))))))

fn joinWith xs: (List String) sep: String -> String
  (catAll (interleave xs sep (list)))

fn splitLoop s: String bs: Bytes b: Int64 i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (cons (optionOr (stringSlice s start n) "") acc)))
    ((= (bytesGet bs i) b) (splitLoop s bs b (+ i 1) (+ i 1) n (cons (optionOr (stringSlice s start i) "") acc)))
    (else (splitLoop s bs b (+ i 1) start n acc)))

fn splitByte s: String b: Int64 -> (List String)
  (let [(bs (stringToBytes s))] (splitLoop s bs b 0 0 (bytesLength bs) (list)))

fn crLoop s: String bs: Bytes i: Int64 start: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse (cons (optionOr (stringSlice s start n) "") acc)))
    ((= (bytesGet bs i) 13)
      (let [(skip (if (and (< (+ i 1) n) (= (bytesGet bs (+ i 1)) 10)) 2 1))]
        (crLoop s bs (+ i skip) (+ i skip) n (cons "\n" (cons (optionOr (stringSlice s start i) "") acc)))))
    (else (crLoop s bs (+ i 1) start n acc)))

fn universalNewlines s: String -> String
  (if (stringContains? s "\r") (let [(bs (stringToBytes s))] (catAll (crLoop s bs 0 0 (bytesLength bs) (list)))) s)

fn lines s: String -> (List String)
  (splitByte s 10)

fn sectionBody secs: (List Section) shown: (List Int64) -> String
  (joinWith (map (fn [(p (Pair Section Int64))] -> String
                     (str " :" (pairFirst p).key " (" (joinWith (listTake (pairFirst p).items (pairSecond p)) " ") ")"))
                   (zip secs shown)) "")

fn sectionMore secs: (List Section) shown: (List Int64) -> String
  (str " :more (" (joinWith (map (fn [(p (Pair Section Int64))] -> String
                                     (str ":" (pairFirst p).key " " (stringFromInt64 (- (listLength (pairFirst p).items) (pairSecond p)))))
                                   (zip secs shown)) " ") ")")

fn shrinkLast shown: (List Int64) -> (Option (List Int64))
  (let [(rev (listReverse shown))]
    (mt (shrinkFirstPositive rev (list))
      ((some r) (some (listReverse r)))
      ((none) (none))))

fn shrinkFirstPositive xs: (List Int64) acc: (List Int64) -> (Option (List Int64))
  (mt (listHead xs)
    ((none) (none))
    ((some x) (if (> x 0)
                (some (listAppend (listReverse acc) (cons (- x 1) (optionOr (listTail xs) (list)))))
                (shrinkFirstPositive (optionOr (listTail xs) (list)) (cons x acc)))))

fn fitLoop head: String secs: (List Section) tail: String what: String shown: (List Int64) -> (Result String String)
  (let [(receipt (str head (sectionBody secs shown) (sectionMore secs shown) tail ")"))]
    (if (< (byteLen receipt) (receiptMax))
      (ok receipt)
      (mt (shrinkLast shown)
        ((some next) (fitLoop head secs tail what next))
        ((none) (err (rejectLine "ERR_RECEIPT_TOO_LARGE" (str what " receipt exceeds " (stringFromInt64 (receiptMax)) " bytes with every list empty") ""))))))

fn fitReceipt head: String secs: (List Section) tail: String what: String -> (Result String String)
  (fitLoop head secs tail what (map (fn [(s Section)] -> Int64 (min s.limit (listLength s.items))) secs))

fn closeMatches word: String names: (List String) n: Int64 cutoff: Float64 -> (List String)
  (sim/getCloseMatches word names n cutoff)
