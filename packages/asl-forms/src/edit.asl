(module asl-forms/edit :x [SyntaxResult Checkers Verdict DelimDiag delimDiag delimError languageOf syntaxLang validateStaged! unifiedDiff! fnmatch parseOwns linesFailed stepReadOnly writeStep! editStep! diffStep! preflushStep! flushStep! discardStep! txnStep! editOp!] :i [(asl-forms/kernel :a k) (asl-forms/vfs :a v) (asl-forms/repair :a rep) (asl-coord/claims :a coord)])


(schema SyntaxResult (:f status String) (:f message String) (:f before String) (:f host String))

(schema Checkers (:f aslCheck (fn [String String (Option String)] -> SyntaxResult)) (:f foreignCheck (fn [String String] -> SyntaxResult)))

(schema Verdict (:f code String) (:f message String) (:f fields String))

(schema DelimDiag (:f kind String) (:f byte Int64) (:f expected String) (:f msg String))

(schema Blk (:f i Int64) (:f j Int64) (:f size Int64))

(schema Op (:f tag String) (:f i1 Int64) (:f i2 Int64) (:f j1 Int64) (:f j2 Int64))

(schema Seqs (:f ids Bytes) (:f la Int64) (:f lb Int64) (:f start Bytes) (:f eff Bytes) (:f pos Bytes) (:f gen Bytes) (:f len Bytes) (:f call Bytes))

(schema Snap (:f path String) (:f prior (Option String)) (:f disk (Option String)) (:f fd Int64))

(schema TxnRun (:f snaps (List Snap)) (:f lines (List String)) (:f failedAt String))


fn stepHead id: Int64 op: String -> String
  (str "  (:step :id " (stringFromInt64 id) " :op \"" op "\"")

fn okStep id: Int64 op: String tail: String -> k/EditOutcome
  (k/EditOutcome :lines (list (str (stepHead id op) " :status \"ok\"" tail ")")) :errCount 0)

fn failStep id: Int64 op: String code: String tail: String -> k/EditOutcome
  (k/EditOutcome :lines (list (str (stepHead id op) " :status \"rejected\" :error-code \"" code "\"" tail ")")) :errCount 1)

fn msgTail msg: String -> String
  (str " :message \"" (k/escapeAsnVal msg) "\"")

fn quoted s: String -> String
  (str "\"" (k/escapeAsnVal s) "\"")

fn flagOn? kw: (Map String String) key: String -> Bool
  (listContains? (list "true" ":true" "1") (stringLower (optionOr (mapGet kw key) "")))

fn autofixOff? kw: (Map String String) -> Bool
  (listContains? (list "false" "0" "none" "off") (k/lstripColons (stringLower (optionOr (mapGet kw "autofix") ""))))

fn targetArg kw: (Map String String) args: (List String) -> String
  (k/kwOr kw "file" (k/kwOr kw "path" (optionOr (listHead args) "")))

fn lastDot s: String i: Int64 -> Int64
  (cond ((< i 0) -1) ((= (k/charAt s i) ".") i) (else (lastDot s (- i 1))))

fn leadingDots s: String i: Int64 -> Int64
  (if (= (k/charAt s i) ".") (leadingDots s (+ i 1)) i)

fn extOf path: String -> String
  (let [(base (k/baseName path))
        (at (lastDot base (- (stringLength base) 1)))]
    (if (> at (- (leadingDots base 0) 1)) (optionOr (stringSlice base at (stringLength base)) "") ""))

fn langByExt ext: String -> String
  (cond
    ((= ext ".asl") "asl") ((= ext ".asn") "asn")
    ((listContains? (list ".ts" ".tsx" ".mts" ".cts") ext) "typescript")
    ((listContains? (list ".js" ".jsx" ".mjs" ".cjs") ext) "javascript")
    ((= ext ".py") "python") ((= ext ".go") "go") ((= ext ".rs") "rust")
    ((or (= ext ".c") (= ext ".h")) "c") ((= ext ".java") "java")
    ((or (= ext ".sh") (= ext ".bash")) "shell") ((= ext ".md") "markdown")
    ((= ext ".json") "json") ((or (= ext ".yaml") (= ext ".yml")) "yaml") ((= ext ".toml") "toml")
    (else "text"))

fn shebangLang prog: String -> String
  (cond
    ((= prog "python") "python")
    ((listContains? (list "bash" "sh" "zsh" "dash" "ksh") prog) "shell")
    ((= prog "node") "javascript")
    (else "text"))

fn stripVersion s: String -> String
  (let [(n (stringLength s))
        (c (k/charAt s (- n 1)))]
    (if (and (> n 0) (or (= c ".") (and (>= (charCode c) 48) (<= (charCode c) 57))))
      (stripVersion (optionOr (stringSlice s 0 (- n 1)) ""))
      s))

fn words s: String -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w)))
          (stringSplit (stringReplace (stringReplace (stringReplace s "\t" " ") "\r" " ") "\n" " ") " "))

fn progOf ws: (List String) -> String
  (mt (listHead ws)
    ((none) "")
    ((some w)
      (let [(prog (k/baseName w))]
        (if (or (= prog "env") (stringStartsWith? w "-"))
          (progOf (optionOr (listTail ws) (list)))
          (stripVersion prog)))))

fn shebangProg text: String -> String
  (if (stringStartsWith? text "#!")
    (progOf (words (optionOr (stringSlice (optionOr (listHead (stringSplit text "\n")) "") 2 (stringLength text)) "")))
    "")

fn languageOf! path: String -> String
  (let [(ext (stringLower (extOf path)))]
    (if (not (stringEmpty? ext))
      (langByExt ext)
      (mt (fileReadString path)
        ((err _) "text")
        ((ok whole)
          (let [(line (optionOr (listHead (stringSplit (optionOr (stringSlice whole 0 (min 256 (stringLength whole))) "") "\n")) ""))
                (prog (shebangProg line))]
            (if (stringEmpty? prog) "text" (shebangLang prog)))))))

fn syntaxLang! path: String content: String -> String
  (let [(lang (languageOf! path))
        (prog (shebangProg content))]
    (cond
      ((or (!= lang "text") (not (stringEmpty? (extOf path)))) lang)
      ((stringEmpty? prog) "text")
      (else (shebangLang prog))))

fn checkerOf lang: String -> String
  (cond
    ((= lang "python") "python") ((= lang "json") "json") ((= lang "javascript") "node") ((= lang "shell") "bash")
    ((= lang "typescript") "tsc") ((= lang "yaml") "pyyaml") ((= lang "toml") "tomllib") ((= lang "c") "cc")
    (else ""))

fn closerOf b: Int64 -> Int64
  (cond ((= b 40) 41) ((= b 91) 93) (else 125))

fn byteChar b: Int64 -> String
  (cond ((= b 40) "(") ((= b 41) ")") ((= b 91) "[") ((= b 93) "]") ((= b 123) "{") (else "}"))

fn unclosed stack: (List (Pair Int64 Int64)) n: Int64 -> DelimDiag
  (let [(top (pairFirst (optionOr (listHead stack) (pair 40 0))))]
    (DelimDiag :kind "unclosed" :byte n :expected (stringJoin (map (fn [(p (Pair Int64 Int64))] -> String (byteChar (closerOf (pairFirst p)))) stack) "")
               :msg (str "unclosed delimiter '" (byteChar top) "' (" (stringFromInt64 (listLength stack)) " open containers remain)")))

fn diagScan b: Bytes n: Int64 i: Int64 stack: (List (Pair Int64 Int64)) inStr: Bool inComment: Bool -> (Option DelimDiag)
  (if (>= i n)
    (cond
      (inStr (some (DelimDiag :kind "unclosed" :byte n :expected "\"" :msg "unterminated string literal")))
      ((not (listEmpty? stack)) (some (unclosed stack n)))
      (else (none)))
    (let [(c (bytesGet b i))]
      (cond
        (inComment (diagScan b n (+ i 1) stack inStr (!= c 10)))
        (inStr (cond ((= c 92) (diagScan b n (+ i 2) stack true false)) ((= c 34) (diagScan b n (+ i 1) stack false false)) (else (diagScan b n (+ i 1) stack true false))))
        ((= c 34) (diagScan b n (+ i 1) stack true false))
        ((= c 59) (diagScan b n (+ i 1) stack false true))
        ((or (= c 40) (= c 91) (= c 123)) (diagScan b n (+ i 1) (cons (pair c i) stack) false false))
        ((or (= c 41) (= c 93) (= c 125))
          (mt (listHead stack)
            ((none) (some (DelimDiag :kind "unexpected" :byte i :expected "" :msg (str "unexpected closing delimiter '" (byteChar c) "' at byte " (stringFromInt64 i)))))
            ((some top)
              (if (= (closerOf (pairFirst top)) c)
                (diagScan b n (+ i 1) (optionOr (listTail stack) (list)) false false)
                (let [(exp (byteChar (closerOf (pairFirst top))))]
                  (some (DelimDiag :kind "mismatch" :byte i :expected exp
                                   :msg (str "mismatched delimiter '" (byteChar c) "' (expected '" exp "') at byte " (stringFromInt64 i)))))))))
        (else (diagScan b n (+ i 1) stack false false)))))

fn delimDiag text: String -> (Option DelimDiag)
  (diagScan (stringToBytes text) (stringLength text) 0 (list) false false)

fn delimError text: String -> String
  (mt (delimDiag text) ((some d) d.msg) ((none) ""))

fn aslFile? path: String -> Bool
  (or (stringEndsWith? path ".asl") (stringEndsWith? path ".asn"))

fn preOrForced pre: Bool -> String
  (if pre " :preexisting true" " :forced true")

fn validateAsl ch: Checkers path: String lang: String before: (Option String) after: String force: Bool -> Verdict
  (mt (delimDiag after)
    ((none)
      (if (= lang "asn")
        (Verdict :code "" :message "" :fields " :balanced true")
        (let [(r (ch.aslCheck path after before))
              (st r.status)
              (diag r.message)
              (chk " :checker \"asl-host\"")
              (pre (= r.before "error"))]
          (cond
            ((= st "ok") (Verdict :code "" :message "" :fields (str " :balanced true :syntax :ok" chk)))
            ((or pre force) (Verdict :code "" :message "" :fields (str " :balanced true :syntax :error" chk (preOrForced pre) " :syntaxMessage " (quoted diag))))
            (else (Verdict :code ":ERR_CHECK_FAILED" :message (if (stringEmpty? diag) (str "asl-host check " st) diag) :fields (str " :balanced true :syntax :error" chk)))))))
    ((some d)
      (let [(pre (mt before ((some b) (some? (delimDiag b))) ((none) false)))
            (detail (str " :byte " (stringFromInt64 d.byte) (if (stringEmpty? d.expected) "" (str " :expected " (quoted d.expected)))))]
        (if (or pre force)
          (Verdict :code "" :message "" :fields (str " :balanced false" detail (preOrForced pre)))
          (Verdict :code ":ERR_UNBALANCED" :message d.msg :fields detail)))))

fn foreignOf ch: Checkers path: String lang: String content: String -> SyntaxResult
  (if (stringEmpty? (checkerOf lang))
    (SyntaxResult :status "skipped" :message (str "no local checker for " lang) :before "" :host "")
    (ch.foreignCheck path content))

fn validateStaged! ch: Checkers path: String before: (Option String) after: String force: Bool -> Verdict
  (let [(lang (syntaxLang! path after))]
    (if (or (= lang "asl") (= lang "asn"))
      (validateAsl ch path lang before after force)
      (let [(r (foreignOf ch path lang after))
            (st r.status)
            (msg r.message)
            (checker (checkerOf lang))
            (host (str r.host (if (stringEmpty? checker) "" (str " :checker \"" checker "\""))))]
        (if (!= st "error")
          (Verdict :code "" :message "" :fields (str " :syntax :" st host (if (and (= st "skipped") (not (stringEmpty? msg)) (not (stringEmpty? checker))) (str " :syntaxMessage " (quoted msg)) "")))
          (let [(pre (mt before ((some b) (= (foreignOf ch path lang b).status "error")) ((none) false)))]
            (if (or pre force)
              (Verdict :code "" :message "" :fields (str " :syntax :error" host (preOrForced pre) " :syntaxMessage " (quoted msg)))
              (Verdict :code ":ERR_SYNTAX" :message msg :fields (str " :syntax :error" host))))))))

fn stripQuotes s: String -> String
  (cond
    ((stringStartsWith? s "\"") (stripQuotes (optionOr (stringSlice s 1 (stringLength s)) "")))
    ((stringEndsWith? s "\"") (stripQuotes (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")))
    (else s))

fn repairRun text: String lang: String spanStart: Int64 spanEnd: Int64 old: (Option String) pick: String -> rep/RepairResult
  (mt old
    ((some o) (rep/repairEdit text lang spanStart spanEnd o (stripQuotes pick)))
    ((none) (rep/repairTextPick text lang spanStart spanEnd (stripQuotes pick))))

fn receiptLine res: rep/RepairResult -> String
  (optionOr (listHead (stringSplit (rep/repairResultReceipt res) "\n")) "")

fn leftCount res: rep/RepairResult -> Int64
  (listLength (rep/repairResultLeft res))

fn unrepairable id: Int64 op: String rel: String res: rep/RepairResult -> k/EditOutcome
  (failStep id op ":ERR_UNREPAIRABLE"
            (str " :file " (quoted rel) " " (receiptLine res) " :message \"repair left " (stringFromInt64 (leftCount res))
                 " item(s); nothing staged (resend with :pick \\\"K.N\\\" to apply option N of item K, one pair per item)\""))

fn stagedOrDisk! vs: v/Vfs path: String -> (Result (Option String) String)
  (mt (v/stagedContent! vs path)
    ((some s) (ok (some s)))
    ((none) (if (k/isFile! path) (mt (v/readText! path) ((ok t) (ok (some t))) ((err e) (err e))) (ok (none)))))

fn writeLocked! vs: v/Vfs ch: Checkers id: Int64 kw: (Map String String) fpath: String content0: String -> k/EditOutcome
  (let [(rel (k/relToRoot vs.root fpath))
        (lang (languageOf! fpath))]
    (mt (stagedOrDisk! vs fpath)
      ((err e) (failStep id "write" ":ERR_WRITE_FAILED" (msgTail e)))
      ((ok prior)
        (let [(repairing (and (not (autofixOff? kw)) (or (= lang "asl") (= lang "asn")) (some? (delimDiag content0))))
              (res (if repairing (some (repairRun content0 lang -1 -1 (none) (k/kwOr kw "pick" ""))) (none)))]
          (mt res
            ((some r) (if (= (leftCount r) 0) (writeChecked! vs ch id kw fpath rel prior (rep/repairResultText r) (str " " (receiptLine r))) (if (flagOn? kw "force") (writeChecked! vs ch id kw fpath rel prior content0 " :repairSkipped true") (unrepairable id "write" rel r))))
            ((none) (writeChecked! vs ch id kw fpath rel prior content0 "")))))))

fn writeChecked! vs: v/Vfs ch: Checkers id: Int64 kw: (Map String String) fpath: String rel: String prior: (Option String) content: String fix: String -> k/EditOutcome
  (let [(vd (validateStaged! ch fpath prior content (flagOn? kw "force")))]
    (if (not (stringEmpty? vd.code))
      (failStep id "write" vd.code (str " :file " (quoted rel) vd.fields (msgTail (str vd.message "; pass :force true to stage anyway"))))
      (mt (v/stage! vs fpath content)
        ((err e) (failStep id "write" ":ERR_WRITE_FAILED" (msgTail e)))
        ((ok _) (okStep id "write" (str " :file " (quoted rel) " :bytes " (stringFromInt64 (stringLength content)) " :staged true :pendingFlush true" vd.fields fix))))))

fn writeStep! vs: v/Vfs ch: Checkers held: (List String) id: Int64 kw: (Map String String) args: (List String) -> k/EditOutcome
  (let [(raw (targetArg kw args))
        (content (k/kwOr kw "content" (optionOr (listGet args 1) "")))
        (res (k/resolveInRoot! vs.root raw))
        (fpath (pairFirst res))]
    (cond
      ((stringEmpty? raw) (failStep id "write" ":ERR_MISSING_ARG" " :message \"Missing file argument\""))
      ((and (none? (mapGet kw "content")) (< (listLength args) 2)) (failStep id "write" ":ERR_MISSING_ARG" " :message \"Missing :content (pass :content \\\"\\\" to stage an empty file)\""))
      ((not (stringEmpty? (pairSecond res))) (failStep id "write" ":ERR_BOUNDARY_VIOLATION" (msgTail (pairSecond res))))
      ((k/isDir! fpath) (failStep id "write" ":ERR_IS_DIRECTORY" (msgTail (str "Target is a directory: " raw))))
      (else
        (mt (v/withLock! vs held fpath (fn [] -> k/EditOutcome (writeLocked! vs ch id kw fpath content)))
          ((ok out) out)
          ((err e) (failStep id "write" ":ERR_WRITE_FAILED" (msgTail e)))))))

fn countFrom text: String b: Bytes needle: String from: Int64 n: Int64 -> Int64
  (let [(at (k/findFrom text b needle from))]
    (if (< at 0) n (countFrom text b needle (+ at (stringLength needle)) (+ n 1))))

fn replaceFrom text: String b: Bytes old: String new: String from: Int64 all: Bool acc: (List String) -> String
  (let [(at (k/findFrom text b old from))]
    (if (< at 0)
      (k/concatAll (listReverse (cons (optionOr (stringSlice text from (stringLength text)) "") acc)))
      (let [(acc2 (cons new (cons (optionOr (stringSlice text from at) "") acc)))
            (next (+ at (stringLength old)))]
        (if all
          (replaceFrom text b old new next all acc2)
          (k/concatAll (listReverse (cons (optionOr (stringSlice text next (stringLength text)) "") acc2)))))))

fn lastIndex text: String b: Bytes needle: String from: Int64 last: Int64 -> Int64
  (let [(at (k/findFrom text b needle from))]
    (if (< at 0) last (lastIndex text b needle (+ at 1) at)))

fn editLocked! vs: v/Vfs ch: Checkers id: Int64 kw: (Map String String) fpath: String old: String new: String -> k/EditOutcome
  (let [(rel (k/relToRoot vs.root fpath))
        (all (flagOn? kw "all"))]
    (mt (stagedOrDisk! vs fpath)
      ((err e) (failStep id "edit" ":ERR_EDIT_FAILED" (msgTail e)))
      ((ok found)
        (let [(base (optionOr found ""))
              (bb (stringToBytes base))
              (occ (countFrom base bb old 0 0))]
          (cond
            ((= occ 0) (failStep id "edit" ":ERR_NO_MATCH" (msgTail (str "Old target string not found in file: " rel))))
            ((and (> occ 1) (not all))
              (failStep id "edit" ":ERR_AMBIGUOUS" (str " :count " (stringFromInt64 occ) (msgTail (str "Old target string matches " (stringFromInt64 occ) " times in " rel "; widen it or pass :all true")))))
            (else
              (let [(replaced (replaceFrom base bb old new 0 all (list)))
                    (lang (languageOf! fpath))
                    (at (k/findFrom base bb old 0))
                    (spanEnd (+ (if all (+ (lastIndex base bb old 0 -1) (* (- occ 1) (- (stringLength new) (stringLength old)))) at) (stringLength new)))
                    (repairing (and (not (autofixOff? kw)) (or (= lang "asl") (= lang "asn")) (some? (delimDiag replaced))))]
                (if repairing
                  (let [(r (repairRun replaced lang at spanEnd (if all (none) (some old)) (k/kwOr kw "pick" "")))]
                    (if (= (leftCount r) 0)
                      (editChecked! vs ch id kw fpath rel base (rep/repairResultText r) occ (str " " (receiptLine r)))
                      (if (flagOn? kw "force") (editChecked! vs ch id kw fpath rel base replaced occ " :repairSkipped true") (unrepairable id "edit" rel r))))
                  (editChecked! vs ch id kw fpath rel base replaced occ "")))))))))

fn editChecked! vs: v/Vfs ch: Checkers id: Int64 kw: (Map String String) fpath: String rel: String base: String replaced: String occ: Int64 fix: String -> k/EditOutcome
  (let [(vd (validateStaged! ch fpath (some base) replaced (flagOn? kw "force")))]
    (if (not (stringEmpty? vd.code))
      (failStep id "edit" vd.code (str " :file " (quoted rel) vd.fields fix (msgTail (str vd.message "; nothing staged (pass :force true)"))))
      (mt (v/stage! vs fpath replaced)
        ((err e) (failStep id "edit" ":ERR_EDIT_FAILED" (msgTail e)))
        ((ok _) (okStep id "edit" (str " :file " (quoted rel) " :staged true :replacements " (stringFromInt64 occ) " :bytes " (stringFromInt64 (stringLength replaced))
                                       " :pendingFlush true" vd.fields fix))))))

fn editStep! vs: v/Vfs ch: Checkers held: (List String) id: Int64 kw: (Map String String) args: (List String) -> k/EditOutcome
  (let [(raw (targetArg kw args))
        (old (k/kwOr kw "old" (optionOr (listGet args 1) "")))
        (new (k/kwOr kw "new" (optionOr (listGet args 2) "")))
        (res (k/resolveEditTarget! vs.root raw))
        (fpath (pairFirst res))
        (perr (pairSecond res))]
    (cond
      ((stringEmpty? raw) (failStep id "edit" ":ERR_MISSING_ARG" " :message \"Missing file argument\""))
      ((not (stringEmpty? perr)) (failStep id "edit" (if (stringContains? perr "Ambiguous") ":ERR_AMBIGUOUS_PATH" ":ERR_BOUNDARY_VIOLATION") (msgTail perr)))
      ((and (not (k/isFile! fpath)) (none? (v/stagedContent! vs fpath))) (failStep id "edit" ":ERR_FILE_NOT_FOUND" (msgTail (str "File not found: " raw))))
      ((stringEmpty? old) (failStep id "edit" ":ERR_MISSING_ARG" " :message \"Missing :old target string\""))
      (else
        (mt (v/withLock! vs held fpath (fn [] -> k/EditOutcome (editLocked! vs ch id kw fpath old new)))
          ((ok out) out)
          ((err e) (failStep id "edit" ":ERR_EDIT_FAILED" (msgTail e)))))))

fn slots n: Int64 -> Bytes
  (bytesAlloc (* 8 (max 1 n)))

fn geti arr: Bytes i: Int64 -> Int64
  (optionOr (float64ToInt64 (bytesGetFloat64 arr i)) 0)

fn seti! arr: Bytes i: Int64 x: Int64 -> Unit
  (bytesSetFloat64 arr i (int64ToFloat64 x))

fn upto i: Int64 n: Int64 body: (fn [Int64] -> Unit) -> Unit
  (if (< i n) (do (body i) (upto (+ i 1) n body)) ())

fn assignIds! ids: Bytes a: (List String) b: (List String) la: Int64 lb: Int64 -> Int64
  (let [(entries (listSortBy pairFirst (listAppend (zip a (range 0 la)) (zip b (range la (+ la lb))))))
        (last (fold (fn [(acc (Pair String Int64)) (e (Pair String Int64))] -> (Pair String Int64)
                      (let [(id (if (and (> (pairSecond acc) 0) (= (pairFirst acc) (pairFirst e))) (pairSecond acc) (+ (pairSecond acc) 1)))]
                        (do (seti! ids (pairSecond e) (- id 1)) (pair (pairFirst e) id))))
                    (pair "" 0)
                    entries))]
    (pairSecond last))

fn seqsOf! a: (List String) b: (List String) -> Seqs
  (let [(la (listLength a))
        (lb (listLength b))
        (ids (slots (+ la lb)))
        (nIds (assignIds! ids a b la lb))
        (cnt (slots nIds))
        (eff (slots nIds))
        (start (slots nIds))
        (fill (slots nIds))
        (pos (slots lb))
        (ntest (+ (/ lb 100) 1))]
    (do
      (upto 0 lb (fn [(j Int64)] -> Unit (let [(id (geti ids (+ la j)))] (seti! cnt id (+ (geti cnt id) 1)))))
      (upto 0 nIds (fn [(id Int64)] -> Unit (seti! eff id (if (and (>= lb 200) (> (geti cnt id) ntest)) 0 (geti cnt id)))))
      (upto 1 nIds (fn [(id Int64)] -> Unit (seti! start id (+ (geti start (- id 1)) (geti eff (- id 1))))))
      (upto 0 nIds (fn [(id Int64)] -> Unit (seti! fill id (geti start id))))
      (upto 0 lb (fn [(j Int64)] -> Unit (let [(id (geti ids (+ la j)))] (if (> (geti eff id) 0) (do (seti! pos (geti fill id) j) (seti! fill id (+ (geti fill id) 1))) ()))))
      (let [(call (slots 1))]
        (do (seti! call 0 2)
            (Seqs :ids ids :la la :lb lb :start start :eff eff :pos pos :gen (slots (* 2 (+ lb 1))) :len (slots (* 2 (+ lb 1))) :call call)))))

fn aId s: Seqs i: Int64 -> Int64
  (geti s.ids i)

fn bId s: Seqs j: Int64 -> Int64
  (geti s.ids (+ s.la j))

fn colScan! s: Seqs k: Int64 k1: Int64 i: Int64 blo: Int64 bhi: Int64 base: Int64 best: Blk -> Blk
  (if (>= k k1)
    best
    (let [(j (geti s.pos k))]
      (cond
        ((< j blo) (colScan! s (+ k 1) k1 i blo bhi base best))
        ((>= j bhi) best)
        (else
          (let [(width (+ s.lb 1))
                (prevAt (+ (* (mod (+ i 1) 2) width) (- j 1)))
                (prev (if (and (> j 0) (= (geti s.gen prevAt) (- (+ base i) 1))) (geti s.len prevAt) 0))
                (kk (+ prev 1))
                (curAt (+ (* (mod i 2) width) j))]
            (do (seti! s.gen curAt (+ base i))
                (seti! s.len curAt kk)
                (colScan! s (+ k 1) k1 i blo bhi base (if (> kk best.size) (Blk :i (+ (- i kk) 1) :j (+ (- j kk) 1) :size kk) best))))))))

fn rowScan! s: Seqs i: Int64 ahi: Int64 blo: Int64 bhi: Int64 base: Int64 best: Blk -> Blk
  (if (>= i ahi)
    best
    (let [(id (aId s i))
          (k0 (geti s.start id))]
      (rowScan! s (+ i 1) ahi blo bhi base (colScan! s k0 (+ k0 (geti s.eff id)) i blo bhi base best))))

fn extendBack s: Seqs alo: Int64 blo: Int64 m: Blk -> Blk
  (if (and (> m.i alo) (> m.j blo) (= (aId s (- m.i 1)) (bId s (- m.j 1))))
    (extendBack s alo blo (Blk :i (- m.i 1) :j (- m.j 1) :size (+ m.size 1)))
    m)

fn extendFwd s: Seqs ahi: Int64 bhi: Int64 m: Blk -> Blk
  (let [(ie (+ m.i m.size))
        (je (+ m.j m.size))]
    (if (and (< ie ahi) (< je bhi) (= (aId s ie) (bId s je)))
      (extendFwd s ahi bhi (with m :size (+ m.size 1)))
      m))

fn longest! s: Seqs alo: Int64 ahi: Int64 blo: Int64 bhi: Int64 -> Blk
  (let [(base (geti s.call 0))]
    (do (seti! s.call 0 (+ base s.la 2))
        (extendFwd s ahi bhi (extendBack s alo blo (rowScan! s alo ahi blo bhi base (Blk :i alo :j blo :size 0))))))

fn blocksInto! s: Seqs alo: Int64 ahi: Int64 blo: Int64 bhi: Int64 acc: (List Blk) -> (List Blk)
  (let [(m (longest! s alo ahi blo bhi))
        (kk m.size)]
    (if (= kk 0)
      acc
      (let [(right (if (and (< (+ m.i kk) ahi) (< (+ m.j kk) bhi)) (blocksInto! s (+ m.i kk) ahi (+ m.j kk) bhi acc) acc))
            (withM (cons m right))]
        (if (and (< alo m.i) (< blo m.j)) (blocksInto! s alo m.i blo m.j withM) withM))))

fn collapse bs: (List Blk) cur: Blk acc: (List Blk) -> (List Blk)
  (mt (listHead bs)
    ((none) (listReverse (if (> cur.size 0) (cons cur acc) acc)))
    ((some b)
      (let [(rest (optionOr (listTail bs) (list)))]
        (if (and (= (+ cur.i cur.size) b.i) (= (+ cur.j cur.size) b.j))
          (collapse rest (with cur :size (+ cur.size b.size)) acc)
          (collapse rest b (if (> cur.size 0) (cons cur acc) acc))))))

fn opcodes bs: (List Blk) i: Int64 j: Int64 acc: (List Op) -> (List Op)
  (mt (listHead bs)
    ((none) (listReverse acc))
    ((some b)
      (let [(ai b.i)
            (bj b.j)
            (tag (cond ((and (< i ai) (< j bj)) "replace") ((< i ai) "delete") ((< j bj) "insert") (else "")))
            (acc1 (if (stringEmpty? tag) acc (cons (Op :tag tag :i1 i :i2 ai :j1 j :j2 bj) acc)))
            (acc2 (if (> b.size 0) (cons (Op :tag "equal" :i1 ai :i2 (+ ai b.size) :j1 bj :j2 (+ bj b.size)) acc1) acc1))]
        (opcodes (optionOr (listTail bs) (list)) (+ ai b.size) (+ bj b.size) acc2))))

fn trimEnds codes: (List Op) n: Int64 -> (List Op)
  (let [(c0 (optionOr (listHead codes) (Op :tag "equal" :i1 0 :i2 1 :j1 0 :j2 1)))
        (first (if (= c0.tag "equal") (Op :tag "equal" :i1 (max c0.i1 (- c0.i2 n)) :i2 c0.i2 :j1 (max c0.j1 (- c0.j2 n)) :j2 c0.j2) c0))
        (codes1 (cons first (optionOr (listTail codes) (list))))
        (cl (optionOr (listLast codes1) first))
        (last (if (= cl.tag "equal") (Op :tag "equal" :i1 cl.i1 :i2 (min cl.i2 (+ cl.i1 n)) :j1 cl.j1 :j2 (min cl.j2 (+ cl.j1 n))) cl))]
    (listAppend (listTake codes1 (- (listLength codes1) 1)) (list last)))

fn groupScan codes: (List Op) n: Int64 group: (List Op) acc: (List (List Op)) -> (List (List Op))
  (mt (listHead codes)
    ((none)
      (let [(g (listReverse group))]
        (listReverse (if (and (not (listEmpty? g)) (not (and (= (listLength g) 1) (= (optionOr (listHead g) (Op :tag "" :i1 0 :i2 0 :j1 0 :j2 0)).tag "equal")))) (cons g acc) acc))))
    ((some c)
      (let [(rest (optionOr (listTail codes) (list)))]
        (if (and (= c.tag "equal") (> (- c.i2 c.i1) (* 2 n)))
          (let [(head (Op :tag "equal" :i1 c.i1 :i2 (min c.i2 (+ c.i1 n)) :j1 c.j1 :j2 (min c.j2 (+ c.j1 n))))
                (tail (Op :tag "equal" :i1 (max c.i1 (- c.i2 n)) :i2 c.i2 :j1 (max c.j1 (- c.j2 n)) :j2 c.j2))]
            (groupScan rest n (list tail) (cons (listReverse (cons head group)) acc)))
          (groupScan rest n (cons c group) acc)))))

fn formatRange start: Int64 stop: Int64 -> String
  (let [(len (- stop start))]
    (cond
      ((= len 1) (stringFromInt64 (+ start 1)))
      ((= len 0) (str (stringFromInt64 start) ",0"))
      (else (str (stringFromInt64 (+ start 1)) "," (stringFromInt64 len)))))

(schema Cur (:f rest (List String)) (:f at Int64))

(schema Emit (:f out (List String)) (:f ca Cur) (:f cb Cur))

fn emitRange cur: Cur lo: Int64 hi: Int64 prefix: String out: (List String) -> (Pair (List String) Cur)
  (let [(rest (listDrop cur.rest (- lo cur.at)))]
    (pair (fold (fn [(acc (List String)) (l String)] -> (List String) (cons (str prefix l) acc)) out (listTake rest (- hi lo)))
          (Cur :rest rest :at lo)))

fn emitOp e: Emit o: Op -> Emit
  (cond
    ((= o.tag "equal")
      (let [(r (emitRange e.ca o.i1 o.i2 " " e.out))] (with e :out (pairFirst r) :ca (pairSecond r))))
    (else
      (let [(ra (if (= o.tag "insert") (pair e.out e.ca) (emitRange e.ca o.i1 o.i2 "-" e.out)))
            (rb (if (= o.tag "delete") (pair (pairFirst ra) e.cb) (emitRange e.cb o.j1 o.j2 "+" (pairFirst ra))))]
        (Emit :out (pairFirst rb) :ca (pairSecond ra) :cb (pairSecond rb)))))

fn emitGroup e: Emit g: (List Op) -> Emit
  (let [(z (Op :tag "" :i1 0 :i2 0 :j1 0 :j2 0))
        (first (optionOr (listHead g) z))
        (last (optionOr (listLast g) z))
        (head (str "@@ -" (formatRange first.i1 last.i2) " +" (formatRange first.j1 last.j2) " @@\n"))]
    (fold emitOp (with e :out (cons head e.out)) g))

fn unifiedDiff! a: (List String) b: (List String) fromFile: String toFile: String n: Int64 -> (List String)
  (let [(s (seqsOf! a b))
        (la s.la)
        (lb s.lb)
        (bs (listAppend (collapse (blocksInto! s 0 la 0 lb (list)) (Blk :i 0 :j 0 :size 0) (list)) (list (Blk :i la :j lb :size 0))))
        (groups (groupScan (trimEnds (opcodes bs 0 0 (list)) n) n (list) (list)))]
    (if (listEmpty? groups)
      (list)
      (listReverse (fold emitGroup (Emit :out (list (str "+++ " toFile "\n") (str "--- " fromFile "\n")) :ca (Cur :rest a :at 0) :cb (Cur :rest b :at 0)) groups).out)))

fn fileDiff! vs: v/Vfs tp: String staged: String -> String
  (let [(rel (k/relToRoot vs.root tp))
        (gerr (v/writeGuard! vs.root tp))]
    (if (not (stringEmpty? gerr))
      (str "(:fileDiff :file " (quoted rel) " :error-code :ERR_BOUNDARY_VIOLATION :message " (quoted gerr) ")")
      (let [(disk (if (k/isFile! tp) (resultOr (v/readText! tp) "") ""))
            (dl (unifiedDiff! (k/splitLinesKeepEnds disk) (k/splitLinesKeepEnds staged) (str "disk/" rel) (str "staged/" rel) 2))]
        (str "(:fileDiff :file " (quoted rel) " :diskBytes " (stringFromInt64 (stringLength disk)) " :stagedBytes " (stringFromInt64 (stringLength staged))
             " :hunkLines " (stringFromInt64 (listLength dl)) " :patch " (quoted (k/concatAll dl)) ")"))))

fn unreadable! tps: (List String) -> (List String)
  (filter (fn [(tp String)] -> Bool (and (k/isFile! tp) (not (resultOk? (v/readText! tp))))) tps)

fn resultOk? r: (Result String String) -> Bool
  (mt r ((ok _) true) ((err _) false))

fn diffStep! vs: v/Vfs id: Int64 kw: (Map String String) args: (List String) -> k/EditOutcome
  (let [(raw (targetArg kw args))
        (res (if (stringEmpty? raw) (pair "" "") (k/resolveInRoot! vs.root raw)))
        (perr (pairSecond res))
        (targets (if (stringEmpty? raw) (v/stagedPaths! vs) (if (some? (v/stagedContent! vs (pairFirst res))) (list (pairFirst res)) (list))))
        (chunks (fold (fn [(acc (List String)) (tp String)] -> (List String)
                        (mt (v/stagedContent! vs tp) ((none) acc) ((some staged) (cons (fileDiff! vs tp staged) acc))))
                      (list)
                      (if (stringEmpty? perr) targets (list))))
        (bad (unreadable! targets))]
    (cond
      ((not (stringEmpty? perr)) (failStep id "diff" ":ERR_BOUNDARY_VIOLATION" (msgTail perr)))
      ((listEmpty? targets) (okStep id "diff" " :stagedCount 0 :clean true :diffs []"))
      ((not (listEmpty? bad)) (failStep id "diff" ":ERR_READ_FAILED" (msgTail (str "Failed to read file: " (k/relToRoot vs.root (optionOr (listHead bad) ""))))))
      (else (okStep id "diff" (str " :stagedCount " (stringFromInt64 (listLength chunks)) " :clean false :diffs [" (stringJoin (listReverse chunks) " ") "]")))))

fn checksPassed -> String
  " :canFlush true :checksPassed [:dyck1Purity :syntaxIntegrity]"

fn preflushStep! vs: v/Vfs id: Int64 kw: (Map String String) args: (List String) -> k/EditOutcome
  (let [(raw (targetArg kw args))
        (root vs.root)]
    (if (stringEmpty? raw)
      (let [(all (v/stagedPaths! vs))
            (escaped (map (fn [(tp String)] -> String (k/relToRoot root tp)) (filter (fn [(tp String)] -> Bool (not (stringEmpty? (v/writeGuard! root tp)))) all)))
            (bad (map (fn [(tp String)] -> String (k/relToRoot root tp))
                      (filter (fn [(tp String)] -> Bool (and (aslFile? tp) (mt (v/stagedContent! vs tp) ((some sc) (not (stringEmpty? (delimError sc)))) ((none) false)))) all)))]
        (cond
          ((listEmpty? all) (okStep id "preflush" (str " :stagedCount 0" (checksPassed))))
          ((not (listEmpty? escaped)) (failStep id "preflush" ":ERR_BOUNDARY_VIOLATION" (msgTail (str "Staged path no longer resolves inside the workspace: " (stringJoin escaped ",")))))
          ((not (listEmpty? bad)) (failStep id "preflush" ":ERR_SYNTAX_MALFORMATION" (msgTail (str "Unbalanced Dyck-1 delimiters in staged: " (stringJoin bad ", ")))))
          (else (okStep id "preflush" (str " :stagedCount " (stringFromInt64 (listLength all)) (checksPassed))))))
      (let [(res (k/resolveInRoot! root raw))
            (fpath (pairFirst res))
            (staged (v/stagedContent! vs fpath))]
        (cond
          ((not (stringEmpty? (pairSecond res))) (failStep id "preflush" ":ERR_BOUNDARY_VIOLATION" (msgTail (pairSecond res))))
          ((and (none? staged) (not (k/isFile! fpath))) (failStep id "preflush" ":ERR_FILE_NOT_FOUND" (msgTail (str "File not found: " raw))))
          (else
            (mt (mt staged ((some s) (ok s)) ((none) (v/readText! fpath)))
              ((err e) (failStep id "preflush" ":ERR_READ_FAILED" (msgTail (str "Failed to read file: " e))))
              ((ok c)
                (if (and (aslFile? fpath) (not (stringEmpty? (delimError c))))
                  (failStep id "preflush" ":ERR_SYNTAX_MALFORMATION" (msgTail (str "Unbalanced Dyck-1 delimiters in file: " (k/relToRoot root fpath))))
                  (okStep id "preflush" (str " :file " (quoted (k/relToRoot root fpath)) " :staged " (if (some? staged) "true" "false") (checksPassed)))))))))))

fn ! diskMatches? path: String meta: v/VfsMeta -> Bool
  (let [(cur (k/isFile! path))]
    (and (= cur meta.baseExists)
         (or (not cur) (= (v/shaText (resultOr (v/readText! path) "")) meta.baseSha))))

fn flushOne! vs: v/Vfs tp: String -> (Pair String String)
  (let [(rel (k/relToRoot vs.root tp))]
    (mt (v/stagedContent! vs tp)
      ((none) (pair ":ERR_NOT_STAGED" (str "No staged modification for " rel)))
      ((some staged)
        (let [(gerr (v/writeGuard! vs.root tp))
              (derr (if (aslFile? tp) (delimError staged) ""))]
          (cond
            ((not (stringEmpty? gerr)) (pair ":ERR_BOUNDARY_VIOLATION" gerr))
            ((not (stringEmpty? derr)) (pair ":ERR_SYNTAX_MALFORMATION" (str "Tier-0 preflush failed in " rel ": " derr)))
            ((not (diskMatches? tp (v/stagedMeta! vs tp))) (pair ":ERR_STALE_BASE" (str "Disk changed since staging; refusing to clobber " rel)))
            (else
              (mt (v/atomicWrite! tp staged)
                ((err e) (pair ":ERR_WRITE_FAILED" e))
                ((ok renamed) (mt (v/unstage! vs tp) ((err e) (pair ":ERR_WRITE_FAILED" e)) ((ok _) (pair "" (if renamed "" "inPlace"))))))))))))

fn flushAll! vs: v/Vfs held: (List String) tps: (List String) flushed: (List (Pair String Bool)) fails: (List (Pair String String)) -> (Pair (List (Pair String Bool)) (List (Pair String String)))
  (mt (listHead tps)
    ((none) (pair (listReverse flushed) (listReverse fails)))
    ((some tp)
      (let [(rest (optionOr (listTail tps) (list)))
            (r (mt (v/withLock! vs held tp (fn [] -> (Pair String String) (flushOne! vs tp))) ((ok p) p) ((err e) (pair ":ERR_WRITE_FAILED" e))))]
        (if (stringEmpty? (pairFirst r))
          (flushAll! vs held rest (cons (pair tp (= (pairSecond r) "inPlace")) flushed) fails)
          (flushAll! vs held rest flushed (cons r fails))))))

fn flushStep! vs: v/Vfs held: (List String) id: Int64 kw: (Map String String) args: (List String) -> k/EditOutcome
  (let [(raw (targetArg kw args))
        (root vs.root)
        (res (if (stringEmpty? raw) (pair "" "") (k/resolveInRoot! root raw)))
        (selErr (pairSecond res))
        (targets (cond ((stringEmpty? raw) (v/stagedPaths! vs)) ((stringEmpty? selErr) (list (pairFirst res))) (else (list))))
        (first (optionOr (listHead targets) ""))
        (stagedBy (if (and (not (listEmpty? targets)) (none? (v/stagedContent! vs first))) (v/stagedByOther! vs first) ""))]
    (cond
      ((not (stringEmpty? selErr)) (failStep id "flush" ":ERR_BOUNDARY_VIOLATION" (msgTail selErr)))
      ((not (stringEmpty? stagedBy))
        (failStep id "flush" ":ERR_STAGED_BY" (str " :path " (quoted (k/relToRoot root first)) " :session " (quoted stagedBy) " :message \"staged by another session; only that session may flush it\"")))
      ((listEmpty? targets) (okStep id "flush" " :flushedCount 0 :persisted false :message \"no staged modifications\""))
      (else
        (let [(r (flushAll! vs held targets (list) (list)))
              (flushed (pairFirst r))
              (fails (pairSecond r))]
          (mt (listHead fails)
            ((some f)
              (failStep id "flush" (pairFirst f) (str " :flushedCount " (stringFromInt64 (listLength flushed)) " :failedCount " (stringFromInt64 (listLength fails)) (msgTail (pairSecond f)))))
            ((none)
              (let [(inPlace (map pairFirst (filter pairSecond flushed)))]
                (okStep id "flush" (str " :flushedCount " (stringFromInt64 (listLength flushed)) " :persisted true :synced false :atomic "
                                        (if (listEmpty? inPlace) "true" (str "false :inPlace [" (stringJoin (map (fn [(x String)] -> String (quoted (k/relToRoot root x))) inPlace) " ") "]"))
                                        " :files [" (stringJoin (map (fn [(x (Pair String Bool))] -> String (quoted (k/relToRoot root (pairFirst x)))) flushed) " ") "]")))))))))

fn flat r: (Result (Result T String) String) -> (Result T String)
  (mt r ((err e) (err e)) ((ok inner) inner))

fn discardStep! vs: v/Vfs held: (List String) id: Int64 kw: (Map String String) args: (List String) -> k/EditOutcome
  (let [(raw (targetArg kw args))
        (root vs.root)]
    (if (stringEmpty? raw)
      (mt (v/discardAll! vs held)
        ((err e) (failStep id "discard" ":ERR_DISCARD_FAILED" (msgTail e)))
        ((ok n) (okStep id "discard" (str " :discardedCount " (stringFromInt64 n) " :discarded " (if (> n 0) "true" "false")))))
      (let [(res (k/resolveInRoot! root raw))
            (fpath (pairFirst res))
            (other (if (stringEmpty? (pairSecond res)) (v/stagedByOther! vs fpath) ""))]
        (cond
          ((not (stringEmpty? (pairSecond res))) (failStep id "discard" ":ERR_BOUNDARY_VIOLATION" (msgTail (pairSecond res))))
          ((and (none? (v/stagedContent! vs fpath)) (not (stringEmpty? other)))
            (failStep id "discard" ":ERR_STAGED_BY" (str " :path " (quoted (k/relToRoot root fpath)) " :session " (quoted other) " :message \"staged by another session; only that session may discard it\"")))
          (else
            (mt (flat (v/withLock! vs held fpath (fn [] -> (Result Bool String) (let [(had (some? (v/stagedContent! vs fpath)))] (mt (v/unstage! vs fpath) ((err e) (err e)) ((ok _) (ok had)))))))
              ((err e) (failStep id "discard" ":ERR_DISCARD_FAILED" (msgTail e)))
              ((ok had) (okStep id "discard" (str " :file " (quoted (k/relToRoot root fpath)) " :discardedCount " (if had "1" "0") " :discarded " (if had "true" "false"))))))))))

fn classEnd p: String i: Int64 n: Int64 -> Int64
  (let [(j0 (if (= (k/charAt p i) "!") (+ i 1) i))
        (j1 (if (= (k/charAt p j0) "]") (+ j0 1) j0))]
    (classClose p j1 n))

fn classClose p: String j: Int64 n: Int64 -> Int64
  (cond ((>= j n) -1) ((= (k/charAt p j) "]") j) (else (classClose p (+ j 1) n)))

fn inClass set: String c: String i: Int64 -> Bool
  (let [(n (stringLength set))]
    (cond
      ((>= i n) false)
      ((and (< (+ i 2) n) (= (k/charAt set (+ i 1)) "-"))
        (or (and (>= (charCode c) (charCode (k/charAt set i))) (<= (charCode c) (charCode (k/charAt set (+ i 2))))) (inClass set c (+ i 3))))
      (else (or (= c (k/charAt set i)) (inClass set c (+ i 1))))))

fn globAt p: String pi: Int64 pn: Int64 s: String si: Int64 sn: Int64 -> Bool
  (if (>= pi pn)
    (= si sn)
    (let [(c (k/charAt p pi))]
      (cond
        ((= c "*") (or (globAt p (+ pi 1) pn s si sn) (and (< si sn) (globAt p pi pn s (+ si 1) sn))))
        ((= c "?") (and (< si sn) (globAt p (+ pi 1) pn s (+ si 1) sn)))
        ((= c "[")
          (let [(e (classEnd p (+ pi 1) pn))]
            (if (< e 0)
              (and (< si sn) (= (k/charAt s si) "[") (globAt p (+ pi 1) pn s (+ si 1) sn))
              (let [(neg (= (k/charAt p (+ pi 1)) "!"))
                    (set (optionOr (stringSlice p (if neg (+ pi 2) (+ pi 1)) e) ""))]
                (and (< si sn) (!= neg (inClass set (k/charAt s si) 0)) (globAt p (+ e 1) pn s (+ si 1) sn))))))
        (else (and (< si sn) (= c (k/charAt s si)) (globAt p (+ pi 1) pn s (+ si 1) sn))))))

fn fnmatch name: String pat: String -> Bool
  (globAt pat 0 (stringLength pat) name 0 (stringLength name))

fn quoteEnd s: String i: Int64 n: Int64 -> Int64
  (cond
    ((>= i n) -1)
    ((= (k/charAt s i) "\\") (if (< (+ i 1) n) (quoteEnd s (+ i 2) n) -1))
    ((= (k/charAt s i) "\"") i)
    (else (quoteEnd s (+ i 1) n)))

fn quotedParts s: String i: Int64 n: Int64 acc: (List String) -> (List String)
  (cond
    ((>= i n) (listReverse acc))
    ((= (k/charAt s i) "\"")
      (let [(e (quoteEnd s (+ i 1) n))]
        (if (< e 0) (quotedParts s (+ i 1) n acc) (quotedParts s (+ e 1) n (cons (optionOr (stringSlice s (+ i 1) e) "") acc)))))
    (else (quotedParts s (+ i 1) n acc)))

fn ownsSep? c: String -> Bool
  (or (k/isSpaceChar c) (= c "(") (= c ")") (= c "[") (= c "]"))

fn parseOwns raw: String -> (List String)
  (let [(q (quotedParts raw 0 (stringLength raw) (list)))]
    (if (not (listEmpty? q))
      q
      (filter (fn [(t String)] -> Bool (and (not (stringEmpty? t)) (!= t "true")))
              (stringSplit (k/concatAll (map (fn [(c String)] -> String (if (ownsSep? c) " " c)) (stringChars raw))) " "))))

fn stripSlash s: String -> String
  (cond
    ((stringStartsWith? s "/") (stripSlash (optionOr (stringSlice s 1 (stringLength s)) "")))
    ((stringEndsWith? s "/") (stripSlash (optionOr (stringSlice s 0 (- (stringLength s) 1)) "")))
    (else s))

fn owned? root: String owns: (List String) path: String -> Bool
  (let [(rel (k/relToRoot root path))]
    (listAny? (fn [(o0 String)] -> Bool (let [(o (stripSlash o0))] (or (= rel o) (stringStartsWith? rel (str o "/")) (fnmatch rel o)))) owns))

fn digitsEnd s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (>= (charCode (k/charAt s i)) 48) (<= (charCode (k/charAt s i)) 57)) (digitsEnd s (+ i 1) n) i)

fn keyEnd s: String i: Int64 n: Int64 -> Int64
  (let [(c (k/charAt s i))]
    (if (and (< i n) (or (= c "-") (and (>= (charCode c) 65) (<= (charCode c) 90)) (and (>= (charCode c) 97) (<= (charCode c) 122)))) (keyEnd s (+ i 1) n) i))

fn at? s: String i: Int64 lit: String -> Bool
  (= (optionOr (stringSlice s i (+ i (stringLength lit))) "") lit)

fn pairsThenRejected s: String i: Int64 n: Int64 -> Bool
  (cond
    ((at? s i " :status \"rejected\"") true)
    ((at? s i " :")
      (let [(ke (keyEnd s (+ i 2) n))
            (key (optionOr (stringSlice s (+ i 2) ke) ""))]
        (if (and (> ke (+ i 2)) (!= key "status") (at? s ke " \""))
          (let [(qe (quoteEnd s (+ ke 2) n))]
            (and (>= qe 0) (pairsThenRejected s (+ qe 1) n)))
          false)))
    (else false))

fn rejectedLine? l: String -> Bool
  (let [(n (stringLength l))
        (i (skipWs l 0 n))]
    (and (at? l i "(:step :id ")
         (let [(d (digitsEnd l (+ i 11) n))]
           (and (> d (+ i 11))
                (at? l d " :op \"")
                (let [(qe (quoteEnd l (+ d 6) n))]
                  (and (>= qe 0) (pairsThenRejected l (+ qe 1) n)))))))

fn skipWs s: String i: Int64 n: Int64 -> Int64
  (if (and (< i n) (k/isSpaceChar (k/charAt s i))) (skipWs s (+ i 1) n) i)

fn linesFailed lines: (List String) errs: Int64 -> Bool
  (or (> errs 0) (listAny? rejectedLine? lines))

fn stepReadOnly op: String kw: (Map String String) -> Bool
  (cond
    ((= op "note") (listContains? (list "list" "query") (k/lstripColons (k/kwOr kw "action" "list"))))
    ((= op "fix") (not (listContains? (list "true" "1" "indentation" "heuristic") (k/lstripColons (stringLower (optionOr (mapGet kw "apply") ""))))))
    ((= op "doctor") (not (listContains? (list "true" "1") (k/lstripColons (stringLower (optionOr (mapGet kw "write") ""))))))
    (else (listContains? (list "echo" "read" "query" "q" "tree" "observe" "diff" "check" "chk" "gate" "test" "tools" "help" "intel" "doctor" "ping" "where" "search" "research" "crawl" "lens" "preflush") op)))

fn heldPaths vs: v/Vfs held: (List String) snaps: (List Snap) -> (List String)
  (listAppend held (map (fn [(s Snap)] -> String (v/lockPath vs s.path)) snaps))

fn snapped? snaps: (List Snap) path: String -> Bool
  (listAny? (fn [(s Snap)] -> Bool (= s.path path)) snaps)

fn abortWith st: TxnRun line: String failedAt: String -> TxnRun
  (with st :lines (cons line st.lines) :failedAt failedAt)

fn innerLine k: Int64 op: String tail: String -> String
  (str "(:step :id " (stringFromInt64 k) " :op \"" op "\"" tail ")")

fn runInner vs: v/Vfs run: (fn [Int64 String (List String)] -> k/EditOutcome) held: (List String) st: TxnRun k: Int64 op: String fs: String -> TxnRun
  (let [(out (run k fs (heldPaths vs held st.snaps)))
        (bad (linesFailed out.lines out.errCount))]
    (with st :lines (fold (fn [(acc (List String)) (l String)] -> (List String) (cons (stringTrim l) acc)) st.lines out.lines) :failedAt (if bad (str "step " (stringFromInt64 k) " (" op ")") "")))

fn snapTake! vs: v/Vfs held: (List String) st: TxnRun path: String -> (Result TxnRun String)
  (if (snapped? st.snaps path)
    (ok st)
    (let [(lp (v/lockPath vs path))
          (fdr (if (listContains? held lp) (ok -1) (v/lockAcquire! vs path)))]
      (mt fdr
        ((err e) (err e))
        ((ok fd)
          (mt (if (k/isFile! path) (mt (v/readText! path) ((ok t) (ok (some t))) ((err e) (err e))) (ok (none)))
            ((err e) (do (if (>= fd 0) (resultOr (v/lockRelease! vs path fd) ()) ()) (err e)))
            ((ok disk)
              (ok (with st :snaps (listAppend st.snaps (list (Snap :path path :prior (v/stagedContent! vs path) :disk disk :fd fd)))))))))))

fn txnInner! vs: v/Vfs run: (fn [Int64 String (List String)] -> k/EditOutcome) held: (List String) owns: (List String) st: TxnRun k: Int64 fs: String -> TxnRun
  (let [(p (k/parseStep fs))
        (op p.op)
        (kw p.kwargs)
        (root vs.root)
        (here (str "step " (stringFromInt64 k) " (" op ")"))]
    (if (not (stringEmpty? st.failedAt))
      (abortWith st (innerLine k (k/escapeAsnVal op) (str " :status \"skipped\" :reason \"transaction aborted at " st.failedAt "\"")) st.failedAt)
      (if (or (= op "edit") (= op "write") (and (= op "fix") (not (stepReadOnly op kw))))
        (let [(target (targetArg kw p.args))
              (res (cond ((stringEmpty? target) (pair "" "Missing file argument")) ((= op "write") (k/resolveInRoot! root target)) (else (k/resolveEditTarget! root target))))
              (ipath (pairFirst res))
              (ierr (pairSecond res))]
          (if (or (not (stringEmpty? ierr)) (not (owned? root owns ipath)))
            (abortWith st (innerLine k op (str " :status \"rejected\" :error-code \":ERR_OWNS\" :file " (quoted target) (msgTail (if (stringEmpty? ierr) (str target " is outside :owns") ierr)))) here)
            (mt (snapTake! vs held st ipath)
              ((err e) (abortWith st (innerLine k op (str " :status \"rejected\" :error-code \":ERR_LOCK\" :file " (quoted target) (msgTail e))) here))
              ((ok st2) (runInner vs run held st2 k op fs)))))
        (if (not (stepReadOnly op kw))
          (abortWith st (innerLine k (k/escapeAsnVal op) " :status \"rejected\" :error-code \":ERR_TXN_FORBIDDEN\" :message \"only edit, write, fix and read-only steps may run inside a txn; the txn flushes or restores itself\"") here)
          (runInner vs run held st k op fs)))))

fn restoreStaged! vs: v/Vfs snaps: (List Snap) -> (List String)
  (fold (fn [(errs (List String)) (s Snap)] -> (List String)
          (mt (mt s.prior ((none) (v/unstage! vs s.path)) ((some prior) (v/stage! vs s.path prior)))
            ((ok _) errs)
            ((err e) (listAppend errs (list e)))))
        (list)
        snaps)

fn releaseAll! vs: v/Vfs snaps: (List Snap) -> (List String)
  (fold (fn [(errs (List String)) (s Snap)] -> (List String)
          (if (< s.fd 0) errs (mt (v/lockRelease! vs s.path s.fd) ((ok _) errs) ((err e) (listAppend errs (list e))))))
        (list)
        (listReverse snaps))

fn rollback! vs: v/Vfs snaps: (List Snap) flushed: (List String) -> (List String)
  (fold (fn [(errs (List String)) (p String)] -> (List String)
          (let [(disk (mt (listHead (filter (fn [(s Snap)] -> Bool (= s.path p)) snaps)) ((some s) s.disk) ((none) (none))))
                (r (mt disk ((none) (if (k/isFile! p) (pathRemove p) (ok ()))) ((some prior) (mt (v/atomicWrite! p prior) ((ok _) (ok ())) ((err e) (err e))))))]
            (mt r ((ok _) errs) ((err e) (listAppend errs (list e))))))
        (list)
        flushed)

fn errTail errs: (List String) -> String
  (if (listEmpty? errs) "" (str " :restoreError " (quoted (stringJoin errs "; "))))

fn flushSnaps! vs: v/Vfs held: (List String) snaps: (List Snap) todo: (List Snap) flushed: (List String) -> (Pair (List String) String)
  (mt (listHead todo)
    ((none) (pair (listReverse flushed) ""))
    ((some s)
      (let [(rest (optionOr (listTail todo) (list)))
            (p s.path)]
        (if (none? (v/stagedContent! vs p))
          (flushSnaps! vs held snaps rest flushed)
          (let [(out (flushStep! vs (heldPaths vs held snaps) 0 (mapSet (mapEmpty) "file" (k/relToRoot vs.root p)) (list)))]
            (if (linesFailed out.lines out.errCount)
              (pair (listReverse flushed) p)
              (flushSnaps! vs held snaps rest (cons p flushed))))))))

fn relList vs: v/Vfs paths: (List String) -> String
  (stringJoin (map (fn [(p String)] -> String (quoted (k/relToRoot vs.root p))) paths) " ")

fn txnFinish! vs: v/Vfs held: (List String) id: Int64 owns: (List String) st: TxnRun -> k/EditOutcome
  (let [(snaps st.snaps)
        (touched (relList vs (map (fn [(s Snap)] -> String s.path) snaps)))
        (ownsAsn (stringJoin (map quoted owns) " "))
        (steps (stringJoin (listReverse st.lines) " "))]
    (if (not (stringEmpty? st.failedAt))
      (let [(errs (listAppend (restoreStaged! vs snaps) (releaseAll! vs snaps)))]
        (failStep id "txn" ":ERR_TXN_ABORTED" (str " :failedAt " (quoted st.failedAt) " :owns [" ownsAsn "] :restored [" touched "] :flushed [] :steps [" steps "]" (errTail errs))))
      (mt (scopePathList! vs.root (optionOr (envGet "ASL_UNIT") "") (txnPending! vs snaps))
        ((err refusal)
          (let [(errs (listAppend (restoreStaged! vs snaps) (releaseAll! vs snaps)))]
            (failStep id "txn" ":ERR_SCOPE_REFUSED" (str " :receipt " refusal " :owns [" ownsAsn "] :restored [" touched "] :flushed [] :steps [" steps "]" (errTail errs)))))
        ((ok _) (txnCommit! vs held id ownsAsn steps snaps)))))

fn txnPending! vs: v/Vfs snaps: (List Snap) -> (List String)
  (map (fn [(s Snap)] -> String s.path)
       (filter (fn [(s Snap)] -> Bool (some? (v/stagedContent! vs s.path))) snaps))

fn txnCommit! vs: v/Vfs held: (List String) id: Int64 ownsAsn: String steps: String snaps: (List Snap) -> k/EditOutcome
  (let [(r (flushSnaps! vs held snaps snaps (list)))
        (flushed (pairFirst r))
        (failed (pairSecond r))]
    (if (not (stringEmpty? failed))
      (let [(errs (listAppend (listAppend (rollback! vs snaps flushed) (restoreStaged! vs snaps)) (releaseAll! vs snaps)))]
        (failStep id "txn" ":ERR_TXN_FLUSH_FAILED" (str " :owns [" ownsAsn "] :failed " (quoted (k/relToRoot vs.root failed)) " :rolledBack [" (relList vs flushed) "] :flushed [] :steps [" steps "]" (errTail errs))))
      (let [(errs (releaseAll! vs snaps))]
        (if (listEmpty? errs)
          (okStep id "txn" (str " :owns [" ownsAsn "] :flushed [" (relList vs flushed) "] :steps [" steps "]"))
          (failStep id "txn" ":ERR_LOCK" (str " :owns [" ownsAsn "] :flushed [" (relList vs flushed) "] :steps [" steps "]" (errTail errs)))))))

fn txnStep! vs: v/Vfs run: (fn [Int64 String (List String)] -> k/EditOutcome) held: (List String) id: Int64 kw: (Map String String) args: (List String) -> k/EditOutcome
  (let [(owns (parseOwns (k/kwOr kw "owns" "")))
        (inner (filter (fn [(a String)] -> Bool (stringStartsWith? a "(")) args))]
    (if (or (listEmpty? owns) (listEmpty? inner))
      (failStep id "txn" ":ERR_MISSING_ARG" " :message \"txn needs :owns (paths) and at least one nested form\"")
      (let [(st (fold (fn [(acc (Pair TxnRun Int64)) (fs String)] -> (Pair TxnRun Int64)
                        (pair (txnInner! vs run held owns (pairFirst acc) (pairSecond acc) fs) (+ (pairSecond acc) 1)))
                      (pair (TxnRun :snaps (list) :lines (list) :failedAt "") 1)
                      inner))]
        (txnFinish! vs held id owns (pairFirst st)))))

fn scopePathList! root: String unit: String paths: (List String) -> (Result Unit String)
  (mt (listHead paths)
    ((none) (ok ()))
    ((some path)
      (mt (coord/pathAllowed! root unit (k/relToRoot root path))
        ((err e) (err e))
        ((ok _) (scopePathList! root unit (optionOr (listTail paths) (list)))))))

fn scopeEditCheck! vs: v/Vfs kw: (Map String String) args: (List String) -> (Option String)
  (let [(raw (targetArg kw args))
        (resolved (k/resolveEditTarget! vs.root raw))
        (path (pairFirst resolved))]
    (if (or (stringEmpty? raw) (not (stringEmpty? (pairSecond resolved))))
      (none)
      (mt (coord/pathAllowed! vs.root (optionOr (envGet "ASL_UNIT") "") (k/relToRoot vs.root path))
        ((ok _) (none))
        ((err e) (some e)))))

fn scopeFlushCheck! vs: v/Vfs kw: (Map String String) args: (List String) -> (Option String)
  (let [(raw (targetArg kw args))
        (resolved (if (stringEmpty? raw) (pair "" "") (k/resolveInRoot! vs.root raw)))
        (paths (cond
          ((not (stringEmpty? raw)) (if (stringEmpty? (pairSecond resolved)) (list (pairFirst resolved)) (list)))
          (else (v/stagedPaths! vs))))]
    (mt (scopePathList! vs.root (optionOr (envGet "ASL_UNIT") "") paths)
      ((ok _) (none))
      ((err e) (some e))))

fn editOp! vs: v/Vfs ch: Checkers run: (fn [Int64 String (List String)] -> k/EditOutcome) held: (List String) id: Int64 op: String kw: (Map String String) args: (List String) -> (Option k/EditOutcome)
  (cond
    ((= op "write") (some (writeStep! vs ch held id kw args)))
    ((= op "edit")
      (mt (scopeEditCheck! vs kw args)
        ((some refusal) (some (failStep id "edit" ":ERR_SCOPE_REFUSED" (str " :receipt " refusal))))
        ((none) (some (editStep! vs ch held id kw args)))))
    ((= op "diff") (some (diffStep! vs id kw args)))
    ((= op "preflush") (some (preflushStep! vs id kw args)))
    ((= op "flush")
      (mt (scopeFlushCheck! vs kw args)
        ((some refusal) (some (failStep id "flush" ":ERR_SCOPE_REFUSED" (str " :receipt " refusal))))
        ((none) (some (flushStep! vs held id kw args)))))
    ((= op "discard") (some (discardStep! vs held id kw args)))
    ((= op "txn") (some (txnStep! vs run held id kw args)))
    (else (none)))
