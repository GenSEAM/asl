(module ws/asl/tools/observe/tests/observeTest
  :x [runTests]
  :i [(ws/asl/tools/observe/common :a c)
      (ws/asl/tools/observe/observe :a o)])

fn fixturePath -> String
  "tests/parity/observe/observeFixture.asn"

fn fixtureCases -> Int64
  219

(enum A (:c aStr [(s String)]) (:c aKw [(k String)]) (:c aInt [(n Int64)]) (:c aSym [(s String)]) (:c aList [(xs (List A))]))

(schema R (:f v A) (:f at Int64) (:f bad String))

fn badAt what: String i: Int64 -> R
  (R :v (aList (list)) :at i :bad (str what " at byte " (stringFromInt64 i)))

fn byteTable -> String
  "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x2a\x2b\x2c\x2d\x2e\x2f\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x3a\x3b\x3c\x3d\x3e\x3f\x40\x41\x42\x43\x44\x45\x46\x47\x48\x49\x4a\x4b\x4c\x4d\x4e\x4f\x50\x51\x52\x53\x54\x55\x56\x57\x58\x59\x5a\x5b\x5c\x5d\x5e\x5f\x60\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6a\x6b\x6c\x6d\x6e\x6f\x70\x71\x72\x73\x74\x75\x76\x77\x78\x79\x7a\x7b\x7c\x7d\x7e\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff"

fn byteStr k: Int64 -> String
  (optionOr (stringSlice (byteTable) k (+ k 1)) "")

fn hexVal b: Int64 -> Int64
  (cond ((and (>= b 48) (<= b 57)) (- b 48)) ((and (>= b 97) (<= b 102)) (- b 87)) (else 0))

fn strLoop s: String bs: Bytes i: Int64 n: Int64 start: Int64 acc: (List String) -> R
  (let [(b (if (< i n) (bytesGet bs i) -1))]
    (cond
      ((< b 0) (badAt "unterminated string" i))
      ((= b 34) (R :v (aStr (c/catAll (listReverse (cons (optionOr (stringSlice s start i) "") acc)))) :at (+ i 1) :bad ""))
      ((and (= b 92) (>= (+ i 1) n)) (badAt "unterminated escape" i))
      ((and (= b 92) (= (bytesGet bs (+ i 1)) 120) (>= (+ i 3) n)) (badAt "unterminated hex escape" i))
      ((= b 92)
        (let [(e (bytesGet bs (+ i 1))) (pre (cons (optionOr (stringSlice s start i) "") acc))]
          (cond
            ((= e 110) (strLoop s bs (+ i 2) n (+ i 2) (cons "\n" pre)))
            ((= e 116) (strLoop s bs (+ i 2) n (+ i 2) (cons "\t" pre)))
            ((= e 114) (strLoop s bs (+ i 2) n (+ i 2) (cons "\r" pre)))
            ((= e 120) (strLoop s bs (+ i 4) n (+ i 4) (cons (byteStr (+ (* 16 (hexVal (bytesGet bs (+ i 2)))) (hexVal (bytesGet bs (+ i 3))))) pre)))
            (else (strLoop s bs (+ i 2) n (+ i 2) (cons (byteStr e) pre))))))
      (else (strLoop s bs (+ i 1) n start acc))))

fn skip bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (let [(b (bytesGet bs i))] (or (= b 32) (= b 10) (= b 9) (= b 13)))) (skip bs (+ i 1) n) i)

fn atomEnd bs: Bytes i: Int64 n: Int64 -> Int64
  (if (and (< i n) (let [(b (bytesGet bs i))] (not (or (= b 32) (= b 10) (= b 9) (= b 13) (= b 40) (= b 41) (= b 91) (= b 93) (= b 34))))) (atomEnd bs (+ i 1) n) i)

fn listLoop s: String bs: Bytes i: Int64 n: Int64 acc: (List A) -> R
  (let [(j (skip bs i n))]
    (cond
      ((>= j n) (badAt "unterminated list" j))
      ((let [(b (bytesGet bs j))] (or (= b 41) (= b 93))) (R :v (aList (listReverse acc)) :at (+ j 1) :bad ""))
      (else (let [(r (readAt s bs j n))] (if (stringEmpty? r.bad) (listLoop s bs r.at n (cons r.v acc)) r)))))

fn readAt s: String bs: Bytes i: Int64 n: Int64 -> R
  (let [(j (skip bs i n)) (b (if (< j n) (bytesGet bs j) -1))]
    (cond
      ((< b 0) (badAt "unexpected end" j))
      ((or (= b 41) (= b 93)) (badAt "unexpected close" j))
      ((= b 34) (strLoop s bs (+ j 1) n (+ j 1) (list)))
      ((or (= b 40) (= b 91)) (listLoop s bs (+ j 1) n (list)))
      (else
        (let [(e (atomEnd bs j n)) (t (optionOr (stringSlice s j e) ""))]
          (R :v (cond ((stringStartsWith? t ":") (aKw (optionOr (stringSlice t 1 (stringLength t)) "")))
                      ((some? (stringToInt64 t)) (aInt (optionOr (stringToInt64 t) 0)))
                      (else (aSym t)))
             :at e :bad "")))))

fn items v: A -> (List A)
  (mt v ((aList xs) xs) (_ (list)))

fn getKey xs: (List A) k: String -> (Option A)
  (mt (listHead xs)
    ((none) (none))
    ((some x) (let [(rest (optionOr (listTail xs) (list)))]
                (mt x
                  ((aKw kk) (if (= kk k) (listHead rest) (getKey rest k)))
                  (_ (getKey rest k))))))

fn fget v: A k: String -> A
  (optionOr (getKey (items v) k) (aList (list)))

fn text v: A -> String
  (mt v ((aStr s) s) ((aSym s) s) ((aKw s) s) ((aInt n) (stringFromInt64 n)) (_ ""))

fn num v: A -> Int64
  (mt v ((aInt n) n) (_ 0))

fn texts v: A -> (List String)
  (map text (items v))

fn pairsOf v: A -> (List (Pair String A))
  (map (fn [(p A)] -> (Pair String A) (let [(xs (items p))] (pair (text (optionOr (listHead xs) (aStr ""))) (optionOr (listGet xs 1) (aStr ""))))) (items v))

(schema Fx (:f now Int64) (:f date String) (:f python String) (:f env (List (Pair String String))) (:f git (List String)) (:f commitDate String) (:f cases (List A)) (:f tool String))

fn parseFixture! s: String -> (Result Fx String)
  (let [(bs (stringToBytes s)) (n (bytesLength bs)) (r (readAt s bs 0 n)) (v r.v)]
    (cond
      ((not (stringEmpty? r.bad)) (err r.bad))
      ((< (skip bs r.at n) n) (err (str "trailing bytes at byte " (stringFromInt64 (skip bs r.at n)))))
      (else (ok (Fx :now (num (fget v "now")) :date (text (fget v "date")) :python (text (fget v "python"))
                    :env (map (fn [(p (Pair String A))] -> (Pair String String) (pair (pairFirst p) (text (pairSecond p)))) (pairsOf (fget v "env")))
                    :git (texts (fget v "git")) :commitDate (text (fget v "commitDate")) :cases (items (fget v "cases"))
                    :tool (resultOr (realPath ".") "."))))))

fn loadText! -> (Result String String)
  (mt (fileReadString (fixturePath))
    ((err e) (err (str (fixturePath) ": " e)))
    ((ok s) (ok s)))

fn ! prefixRejected? s: String cut: Int64 -> Bool
  (mt (parseFixture! (optionOr (stringSlice s 0 cut) ""))
    ((ok _) false)
    ((err _) true))

fn envRows kv: (List (Pair String String)) -> (List String)
  (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (pairSecond p))) kv)

fn runOk! argv: (List String) cwd: String env: (List (Pair String String)) -> (Result String String)
  (mt (c/runArgv! argv cwd (c/Ctx :cwd cwd :env env :spawnEnv (some (envRows env)) :now 0 :date ""))
    ((err e) (err (str (stringJoin argv " ") ": " e)))
    ((ok p) (if (= p.code 0) (ok p.out) (err (str (stringJoin argv " ") " exited " (stringFromInt64 p.code) ": " p.errText)))))

fn writeFile! path: String data: String -> (Result Unit String)
  (mt (dirCreate (c/dirName path))
    ((err e) (err e))
    ((ok _) (fileWrite path data)))

fn writeAll! base: String files: (List (Pair String A)) subst: (fn [String] -> String) -> (Result Unit String)
  (fold (fn [(acc (Result Unit String)) (p (Pair String A))] -> (Result Unit String)
          (mt acc ((err e) (err e)) ((ok _) (writeFile! (c/joinPath base (subst (pairFirst p))) (text (pairSecond p))))))
        (ok ()) files)

fn writeFills! base: String rows: (List A) -> (Result Unit String)
  (fold (fn [(acc (Result Unit String)) (row A)] -> (Result Unit String)
          (let [(xs (items row))]
            (mt acc
              ((err e) (err e))
              ((ok _) (writeFile! (c/joinPath base (text (optionOr (listHead xs) (aStr "")))) (stringRepeat (text (optionOr (listGet xs 1) (aStr ""))) (num (optionOr (listGet xs 2) (aInt 0)))))))))
        (ok ()) rows)

fn octal n: Int64 width: Int64 -> String
  (if (<= width 0) "" (str (octal (/ n 8) (- width 1)) (stringFromInt64 (mod n 8))))

fn nul n: Int64 -> String
  (stringRepeat "\x00" n)

fn padTo s: String n: Int64 -> String
  (str s (nul (- n (stringLength s))))

fn byteSum bs: Bytes i: Int64 n: Int64 acc: Int64 -> Int64
  (if (>= i n) acc (byteSum bs (+ i 1) n (+ acc (bytesGet bs i))))

fn tarMember name: String data: String mtime: Int64 -> String
  (let [(pre (str (padTo name 100) "0000644\x00" "0000000\x00" "0000000\x00" (octal (stringLength data) 11) "\x00" (octal mtime 11) "\x00"))
        (post (str "0" (nul 100) "ustar\x00" "00" (nul 32) (nul 32) (nul 8) (nul 8) (nul 155) (nul 12)))
        (sum (byteSum (stringToBytes (str pre "        " post)) 0 512 0))
        (hdr (str pre (octal sum 6) "\x00 " post))
        (pad (mod (- 512 (mod (stringLength data) 512)) 512))]
    (str hdr data (nul pad)))

fn setMtimes! base: String rows: (List (Pair String Int64)) tarPath: String env: (List (Pair String String)) -> (Result Unit String)
  (if (listEmpty? rows)
    (ok ())
    (let [(members (map (fn [(p (Pair String Int64))] -> String
                          (tarMember (pairFirst p) (mt (fileReadString (c/joinPath base (pairFirst p))) ((ok d) d) ((err _) "")) (pairSecond p)))
                        rows))]
      (mt (fileWrite tarPath (str (c/catAll members) (nul 1024)))
        ((err e) (err e))
        ((ok _) (mt (runOk! (list "tar" "-xf" tarPath "-C" base) base env) ((err e) (err e)) ((ok _) (ok ())))))))

fn hashOf s: String -> String
  (optionOr (stringSlice (bytesSha256 (stringToBytes s)) 0 16) "")

fn replaceAll s: String a: String b: String -> String
  (if (stringContains? s a) (c/joinWith (stringSplit s a) b) s)

(schema Built (:f root String) (:f home String))

fn ! build! fx: Fx cs: A base: String k: Int64 -> (Result Built String)
  (let [(rootRaw (c/joinPath base (str "w" (stringFromInt64 k)))) (homeRaw (c/joinPath base (str "h" (stringFromInt64 k))))]
    (mt (dirCreate rootRaw)
      ((err e) (err e))
      ((ok _)
        (mt (dirCreate homeRaw)
          ((err e) (err e))
          ((ok _)
            (let [(root (optionOr (resultToOption (realPath rootRaw)) rootRaw)) (home (optionOr (resultToOption (realPath homeRaw)) homeRaw))
                  (hash (hashOf root))
                  (sub (fn [(s String)] -> String (replaceAll (replaceAll (replaceAll s "{root}" root) "{home}" home) "{hash}" hash)))
                  (genv (listAppend fx.env (list (pair "GIT_AUTHOR_DATE" fx.commitDate) (pair "GIT_COMMITTER_DATE" fx.commitDate))))
                  (git (fn [(args (List String))] -> (Result String String) (runOk! (listAppend fx.git args) root genv)))
                  (steps (list
                    (fn [] -> (Result String String) (mt (writeAll! root (pairsOf (fget cs "files")) sub) ((ok _) (ok "")) ((err e) (err e))))
                    (fn [] -> (Result String String) (mt (writeFills! root (items (fget cs "fills"))) ((ok _) (ok "")) ((err e) (err e))))
                    (fn [] -> (Result String String) (if (= (text (fget cs "git")) "true") (git (list "init" "-q")) (ok "")))
                    (fn [] -> (Result String String) (if (= (text (fget cs "git")) "true") (git (list "add" "-A")) (ok "")))
                    (fn [] -> (Result String String) (if (= (text (fget cs "git")) "true") (git (list "commit" "-q" "--no-verify" "--allow-empty" "-m" "c0")) (ok "")))
                    (fn [] -> (Result String String)
                      (fold (fn [(acc (Result String String)) (p (Pair String A))] -> (Result String String) (mt acc ((err e) (err e)) ((ok _) (git (list "mv" (pairFirst p) (text (pairSecond p)))))))
                            (ok "") (pairsOf (fget cs "renames"))))
                    (fn [] -> (Result String String) (mt (writeAll! root (pairsOf (fget cs "after")) sub) ((ok _) (ok "")) ((err e) (err e))))
                    (fn [] -> (Result String String) (mt (writeAll! home (pairsOf (fget cs "home")) sub) ((ok _) (ok "")) ((err e) (err e))))
                    (fn [] -> (Result String String)
                      (fold (fn [(acc (Result String String)) (p (Pair String A))] -> (Result String String)
                              (mt acc ((err e) (err e))
                                ((ok _) (let [(dst (c/joinPath root (pairFirst p)))]
                                          (mt (dirCreate (c/dirName dst))
                                            ((err e) (err e))
                                            ((ok _) (runOk! (list "ln" "-s" (sub (text (pairSecond p))) dst) root genv)))))))
                            (ok "") (pairsOf (fget cs "links"))))
                    (fn [] -> (Result String String)
                      (let [(rows (map (fn [(p (Pair String A))] -> (Pair String Int64) (pair (sub (pairFirst p)) (num (pairSecond p)))) (pairsOf (fget cs "mtimes"))))
                            (homeRows (filter (fn [(p (Pair String Int64))] -> Bool (stringStartsWith? (pairFirst p) (str home "/"))) rows))
                            (rootRows (filter (fn [(p (Pair String Int64))] -> Bool (not (stringStartsWith? (pairFirst p) (str home "/")))) rows))
                            (rel (fn [(p (Pair String Int64))] -> (Pair String Int64) (pair (optionOr (stringSlice (pairFirst p) (+ (stringLength home) 1) (stringLength (pairFirst p))) "") (pairSecond p))))]
                        (mt (setMtimes! root rootRows (c/joinPath base (str "r" (stringFromInt64 k) ".tar")) genv)
                          ((err e) (err e))
                          ((ok _) (mt (setMtimes! home (map rel homeRows) (c/joinPath base (str "m" (stringFromInt64 k) ".tar")) genv) ((err e) (err e)) ((ok _) (ok "")))))))))]
              (mt (fold (fn [(acc (Result String String)) (step (fn [] -> (Result String String)))] -> (Result String String) (mt acc ((err e) (err e)) ((ok _) (step)))) (ok "") steps)
                ((err e) (err e))
                ((ok _) (ok (Built :root root :home home))))))))))

fn norm s: String b: Built -> String
  (replaceAll (replaceAll s b.root "{root}") b.home "{home}")

(schema Tools (:f py String) (:f noPy String))

fn withPath env: (List (Pair String String)) path: String -> (List (Pair String String))
  (listAppend (filter (fn [(p (Pair String String))] -> Bool (!= (pairFirst p) "PATH")) env) (list (pair "PATH" path)))

fn ! findTool! name: String path: String -> (Result String String)
  (mt (listHead (filter (fn [(d String)] -> Bool (and (not (stringEmpty? d)) (c/isFile? (c/joinPath d name)))) (stringSplit path ":")))
    ((none) (err (str name " is not on PATH " path)))
    ((some d) (ok (c/joinPath d name))))

fn ! makeTools! fx: Fx base: String -> (Result Tools String)
  (let [(py (c/joinPath base "py")) (noPy (c/joinPath base "nopy"))
        (fixPath (optionOr (listHead (map pairSecond (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) "PATH")) fx.env))) ""))]
    (mt (findTool! "python3" (optionOr (envGet "PATH") ""))
      ((err e) (err e))
      ((ok pyBin)
        (mt (findTool! "git" fixPath)
          ((err e) (err e))
          ((ok gitBin)
            (mt (dirCreate py)
              ((err e) (err e))
              ((ok _)
                (mt (dirCreate noPy)
                  ((err e) (err e))
                  ((ok _)
                    (mt (runOk! (list "ln" "-s" pyBin (c/joinPath py "python3")) base fx.env)
                      ((err e) (err e))
                      ((ok _)
                        (mt (runOk! (list "ln" "-s" gitBin (c/joinPath noPy "git")) base fx.env)
                          ((err e) (err e))
                          ((ok _) (ok (Tools :py py :noPy noPy)))))))))))))))

fn ! pythonVersion! tools: Tools base: String -> (Result String String)
  (mt (runOk! (list (c/joinPath tools.py "python3") "-c" "import sys; print(sys.version.split()[0])") base (list))
    ((err e) (err e))
    ((ok out) (ok (c/pyStrip out))))

fn casePath tools: Tools cs: A -> String
  (if (= (text (fget cs "python")) "absent") tools.noPy (str tools.py ":/usr/bin:/bin"))

fn ! checkCase fx: Fx tools: Tools base: String k: Int64 cs: A -> Bool
  (let [(cid (text (fget cs "id")))]
    (mt (build! fx cs base k)
      ((err e) (do (assert (= e "") (str cid ": workspace build failed: " e)) false))
      ((ok b)
        (let [(sub (fn [(s String)] -> String (replaceAll (replaceAll (replaceAll s "{root}" b.root) "{home}" b.home) "{tool}" fx.tool)))
              (env (withPath (listAppend (listAppend fx.env (list (pair "HOME" b.home)))
                                         (map (fn [(p (Pair String A))] -> (Pair String String) (pair (pairFirst p) (sub (text (pairSecond p))))) (pairsOf (fget cs "env"))))
                             (casePath tools cs)))
              (cwd (c/joinPath b.root (text (fget cs "cwd"))))
              (ctx (c/Ctx :cwd (if (stringEndsWith? cwd "/") (optionOr (stringSlice cwd 0 (- (stringLength cwd) 1)) cwd) cwd) :env env :spawnEnv (some (envRows env)) :now fx.now :date fx.date))
              (t0 (nowNs))
              (got (o/runObserve ctx (texts (fget cs "argv"))))
              (ms (/ (- (nowNs) t0) 1000000))
              (maxMs (num (fget cs "maxMs")))
              (okTime (or (= maxMs 0) (<= ms maxMs)))
              (crash (text (fget cs "crash")))
              (wantErr (if (stringEmpty? crash) (text (fget cs "err")) (str crash "\n")))
              (okOut (= (norm got.out b) (text (fget cs "out"))))
              (okErr (= (norm got.err b) wantErr))
              (okExit (= got.code (num (fget cs "exit"))))]
          (do
            (assert okOut (str cid ": stdout\n got  " (norm got.out b) "\n want " (text (fget cs "out"))))
            (assert okErr (str cid ": stderr\n got  " (norm got.err b) "\n want " wantErr))
            (assert okExit (str cid ": exit got " (stringFromInt64 got.code) " want " (stringFromInt64 (num (fget cs "exit")))))
            (assert okTime (str cid ": took " (stringFromInt64 ms) " ms, bound " (stringFromInt64 maxMs) " ms"))
            (and okOut okErr okExit okTime))))))

fn tmpBase! -> String
  (let [(t (optionOr (envGet "TMPDIR") "/tmp"))]
    (c/joinPath (if (stringEmpty? t) "/tmp" t) (str "obsTest" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (/ (nowNs) 1000)))))

fn ! runTests -> Bool
  (mt (loadText!)
    ((err e) (do (assert (= e "") e) false))
    ((ok text0)
      (mt (parseFixture! text0)
        ((err e) (do (assert (= e "") (str (fixturePath) ": " e)) false))
        ((ok fx)
      (let [(base (tmpBase!))
            (truncOk (and (prefixRejected? text0 (/ (stringLength text0) 2)) (prefixRejected? text0 (- (stringLength text0) 2))
                          (mt (parseFixture! (str text0 " )")) ((ok _) false) ((err _) true))))]
        (mt (dirCreate base)
          ((err e) (do (assert (= e "") (str "temp dir: " e)) false))
          ((ok _)
            (do
            (assert truncOk "a truncated or overlong fixture is rejected")
            (mt (makeTools! fx base)
              ((err e) (do (assert (= e "") (str "tools: " e)) (pathRemove base) false))
              ((ok tools)
                (let [(ver (pythonVersion! tools base))
                      (okVer (= ver (ok fx.python)))
                      (results (map (fn [(p (Pair Int64 A))] -> Bool (checkCase fx tools base (pairFirst p) (pairSecond p))) (enumerate fx.cases)))
                      (cleaned (pathRemove base))]
                  (do
                    (assert okVer (str "python3 on PATH is " (mt ver ((ok v) v) ((err e) e)) "; the fixture was recorded with " fx.python))
                    (assert (= (listLength fx.cases) (fixtureCases)) (str "fixture holds " (stringFromInt64 (listLength fx.cases)) " cases, want " (stringFromInt64 (fixtureCases))))
                    (and truncOk okVer (= (listLength fx.cases) (fixtureCases)) (listAll? (fn [(r Bool)] -> Bool r) results))))))))))))))
