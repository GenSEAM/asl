(module ws/asl/tools/observe/memory
  :x [topLevelForms observeMemory!]
  :i [(ws/asl/tools/observe/common :a c)])

fn ledgerCap -> Int64
  40

fn formsLoop bs: Bytes i: Int64 n: Int64 depth: Int64 forms: Int64 inStr: Bool inComment: Bool -> Int64
  (if (>= i n)
    forms
    (let [(b (bytesGet bs i))]
      (cond
        (inComment (formsLoop bs (+ i 1) n depth forms inStr (!= b 10)))
        (inStr (cond ((= b 92) (formsLoop bs (+ i 2) n depth forms true false))
                     ((= b 34) (formsLoop bs (+ i 1) n depth forms false false))
                     (else (formsLoop bs (+ i 1) n depth forms true false))))
        ((= b 34) (formsLoop bs (+ i 1) n depth forms true false))
        ((= b 59) (formsLoop bs (+ i 1) n depth forms false true))
        ((or (= b 40) (= b 91) (= b 123)) (formsLoop bs (+ i 1) n (+ depth 1) (if (= depth 0) (+ forms 1) forms) false false))
        ((or (= b 41) (= b 93) (= b 125)) (formsLoop bs (+ i 1) n (max 0 (- depth 1)) forms false false))
        (else (formsLoop bs (+ i 1) n depth forms false false)))))

fn topLevelForms data: String -> Int64
  (let [(bs (stringToBytes data))] (formsLoop bs 0 (bytesLength bs) 0 0 false false))

fn ledgerStats! path: String -> (Result (Pair Int64 Int64) String)
  (mt (fileReadString path)
    ((ok data) (ok (pair (topLevelForms data) (stringLength data))))
    ((err e) (err e)))

fn listDir! path: String -> (Result (List String) String)
  (dirList path)

fn walkSum! dir: String -> (Result (Pair Int64 Int64) String)
  (mt (listDir! dir)
    ((err e) (err e))
    ((ok names)
      (fold (fn [(acc (Result (Pair Int64 Int64) String)) (name String)] -> (Result (Pair Int64 Int64) String)
              (mt acc
                ((err e) (err e))
                ((ok tot)
                  (let [(full (c/joinPath dir name))]
                    (cond
                      ((c/isDir? full)
                        (if (c/isLink? full)
                          (ok tot)
                          (mt (walkSum! full) ((ok s) (ok (pair (+ (pairFirst tot) (pairFirst s)) (+ (pairSecond tot) (pairSecond s))))) ((err e) (err e)))))
                      ((stringEndsWith? name ".asn")
                        (mt (ledgerStats! full) ((ok s) (ok (pair (+ (pairFirst tot) (pairFirst s)) (+ (pairSecond tot) (pairSecond s))))) ((err e) (err e))))
                      (else (ok tot)))))))
            (ok (pair 0 0)) names)))

(schema Ledger (:f path String) (:f forms Int64) (:f bytes Int64))

fn ledgerForm l: Ledger -> String
  (str "(:path " (c/quoted l.path) " :forms " (stringFromInt64 l.forms) " :bytes " (stringFromInt64 l.bytes) ")")

fn entries! mem: String names: (List String) acc: (List Ledger) -> (Result (List Ledger) String)
  (mt (listHead names)
    ((none) (ok (listReverse acc)))
    ((some name)
      (let [(full (c/joinPath mem name)) (rel (str ".asl/mem/" name)) (rest (optionOr (listTail names) (list)))]
        (cond
          ((and (c/isFile? full) (stringEndsWith? name ".asn"))
            (mt (ledgerStats! full) ((ok s) (entries! mem rest (cons (Ledger :path rel :forms (pairFirst s) :bytes (pairSecond s)) acc))) ((err e) (err e))))
          ((c/isDir? full)
            (mt (walkSum! full) ((ok s) (entries! mem rest (cons (Ledger :path (str rel "/") :forms (pairFirst s) :bytes (pairSecond s)) acc))) ((err e) (err e))))
          (else (entries! mem rest acc))))))

fn ! observeMemory! root: String ctx: c/Ctx -> (Result String String)
  (let [(mem (c/joinPath root ".asl/mem"))]
    (if (not (c/isDir? mem))
      (err (c/rejectLine "ERR_PATH_NOT_FOUND" (str "no .asl/mem directory under " root) ""))
      (mt (listDir! mem)
        ((err e) (err (c/rejectLine "ERR_IO" e "")))
        ((ok names)
          (mt (entries! mem names (list))
            ((err e) (err (c/rejectLine "ERR_IO" e "")))
            ((ok ls)
              (mt (c/shortRev! root ctx)
                ((err e) (err e))
                ((ok rev)
                  (let [(shown (listTake ls (ledgerCap)))]
                    (ok (str "(:observe :dim memory :rev " rev " :ledgers (" (c/joinWith (map ledgerForm shown) " ") ") :more "
                             (stringFromInt64 (- (listLength ls) (listLength shown))) ")")))))))))))
