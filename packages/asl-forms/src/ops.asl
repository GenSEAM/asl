(module asl-forms/ops :x [StepOutcome runStep! splitLinesKeepEnds pyInt] :i [(asl-forms/kernel :a k) (asl-forms/similarity :a sm) (asl-forms/symbol :a sy) (asl-forms/delegate :a d) (asl-proc/coreProcess :a cp) (asl-forms/search :a s) (asl-forms/tools :a t) (asl-forms/gate :a g) (asl-forms/vfs :a v) (asl-html/convert :a conv) (asl-ir/types :a ty) (asl-target-js/main :a jsc) (asl-forms/edit :a e) (asl-forms/lens :a l) (asl-forms/evalOp :a ev) (asl-forms/memOp :a m) (asl-forms/docOp :a doc)])


(schema StepOutcome (:f lines (List String)) (:f errCount Int64))

(schema TreeAcc (:f files Int64) (:f dirs Int64) (:f entries (List String)))


fn stepHead id: Int64 op: String -> String
  (str "  (:step :id " (stringFromInt64 id) " :op \"" op "\"")

fn done line: String -> StepOutcome
  (StepOutcome :lines (list line) :errCount 0)

fn failedStep line: String -> StepOutcome
  (StepOutcome :lines (list line) :errCount 1)

fn rejected id: Int64 op: String code: String tail: String -> StepOutcome
  (failedStep (str (stepHead id op) " :status \"rejected\" :error-code \":" code "\"" tail ")"))

fn unimplemented id: Int64 op: String -> StepOutcome
  (rejected id op "ERR_UNIMPLEMENTED" " :message \"Operation not implemented\"")

fn msgTail msg: String -> String
  (str " :message \"" (k/escapeAsnVal msg) "\"")

fn digitsOnly? s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (and (>= (charCode c) 48) (<= (charCode c) 57))) (stringChars s)))

fn underscoresOk? s: String -> Bool
  (listAll? digitsOnly? (stringSplit s "_"))

fn pyInt raw: String -> (Option Int64)
  (let [(t (stringTrim raw))
        (sign (if (or (stringStartsWith? t "-") (stringStartsWith? t "+")) (k/charAt t 0) ""))
        (body (optionOr (stringSlice t (stringLength sign) (stringLength t)) ""))]
    (if (underscoresOk? body) (stringToInt64 (str sign (stringReplace body "_" ""))) (none)))

fn echoStep id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(msg (k/kwOr kw "message" (k/kwOr kw "echo" (optionOr (listHead args) ""))))]
    (done (str (stepHead id "echo") " :status \"ok\" :message \"" (k/escapeAsnVal msg) "\")")))

fn ! evalStep root: String id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(out (ev/evalStep! root id kw args))]
    (StepOutcome :lines (list (pairFirst out)) :errCount (pairSecond out)))

fn jobStep id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(given (k/kwOr kw "subop" (k/kwOr kw "action" "")))
        (subop (cond
                 ((not (stringEmpty? given)) given)
                 ((mapHas? kw "spawn") "spawn")
                 ((mapHas? kw "status") "status")
                 ((mapHas? kw "cancel") "cancel")
                 (else (optionOr (listHead args) "spawn"))))
        (sub (k/lstripColons subop))
        (jid (k/kwOr kw "jobId" (k/kwOr kw "id" "")))]
    (failedStep (str (stepHead id "job") " :subop \"" (k/escapeAsnVal sub) "\" :status \"rejected\" :error-code \":ERR_NOT_IMPLEMENTED\" :jobId \"" (k/escapeAsnVal jid)
                     "\" :message \"job supervision is not implemented; use (:manage :action :spawn|:poll|:tail|:kill|:list)\")")))

fn runStep id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (rejected id "run" "ERR_NOT_IMPLEMENTED" " :message \"to run ASL code, use (:eval :code \\\"...\\\"); to run a file from the CLI, use asl run FILE\"")

fn consultStep id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(prompt (k/kwOr kw "prompt" (optionOr (listHead args) "")))
        (target (k/kwOr kw "target" (k/kwOr kw "symbol" "")))
        (role (k/kwOr kw "role" "falsifier"))]
    (if (stringEmpty? prompt)
      (rejected id "consult" "ERR_MISSING_ARG" " :message \"Missing prompt argument\"")
      (rejected id "consult" "ERR_NOT_IMPLEMENTED"
                (str " :role \"" (k/escapeAsnVal role) "\" :prompt \"" (k/escapeAsnVal prompt) "\" :target \"" (k/escapeAsnVal target)
                     "\" :message \"no critic model is wired to this op; route external consultation through asl-relay\""))))

fn excludedTreeDir? name: String -> Bool
  (or (= name ".git") (= name "node_modules") (= name "__pycache__"))

fn relJoin relDir: String name: String -> String
  (if (stringEmpty? relDir) name (str relDir "/" name))

fn walkTree! dir: String relDir: String depth: Int64 acc: TreeAcc -> TreeAcc
  (mt (dirList dir)
    ((err _) acc)
    ((ok names)
      (let [(isDirs (map (fn [(nm String)] -> Bool (k/isDir! (k/joinPath dir nm))) names))
            (pairs (zip names isDirs))
            (files (map pairFirst (filter (fn [(p (Pair String Bool))] -> Bool (not (pairSecond p))) pairs)))
            (dirs (filter (fn [(nm String)] -> Bool (not (excludedTreeDir? nm))) (map pairFirst (filter pairSecond pairs))))
            (listed (if (< depth 3) (fold (fn [(es (List String)) (f String)] -> (List String) (cons (relJoin relDir f) es)) acc.entries files) acc.entries))
            (here (TreeAcc :files (+ acc.files (listLength files)) :dirs (+ acc.dirs (listLength dirs)) :entries listed))]
        (fold (fn [(a TreeAcc) (d String)] -> TreeAcc
                (if (k/realChild? dir d) (walkTree! (k/joinPath dir d) (relJoin relDir d) (+ depth 1) a) a))
              here
              dirs))))

fn quoted s: String -> String
  (str "\"" (k/escapeAsnVal s) "\"")

fn treeStep! root: String id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(tPath (k/kwOr kw "path" (optionOr (listHead args) ".")))
        (res (k/resolveInRoot! root tPath))
        (target (pairFirst res))]
    (cond
      ((not (stringEmpty? (pairSecond res))) (rejected id "tree" "ERR_BOUNDARY_VIOLATION" (msgTail (pairSecond res))))
      ((not (k/isDir! target)) (rejected id "tree" "ERR_PATH_NOT_FOUND" (msgTail (str "Directory not found: " tPath))))
      (else
        (let [(walked (walkTree! target "" 0 (TreeAcc :files 0 :dirs 0 :entries (list))))
              (entries (listReverse walked.entries))
              (n (listLength entries))]
          (done (str (stepHead id "tree") " :status \"ok\" :path " (quoted (k/relToRoot root target))
                     " :totalFiles " (stringFromInt64 walked.files) " :totalDirs " (stringFromInt64 walked.dirs)
                     " :depth 3 :entries (" (stringJoin (map quoted (listTake entries 200)) " ") ")"
                     (if (> n 200) (str " :more " (stringFromInt64 (- n 200))) "") ")"))))))

fn splitLinesKeepEnds text: String -> (List String)
  (k/splitLinesKeepEnds text)

fn charCount b: Bytes i: Int64 e: Int64 acc: Int64 -> Int64
  (if (>= i e) acc (charCount b (+ i 1) e (if (= (& (bytesGet b i) 192) 128) acc (+ acc 1))))

fn pageKeep b: Bytes ends: (List Int64) start: Int64 cap: Int64 byteCap: Int64 keep: Int64 used: Int64 -> Int64
  (mt (listHead ends)
    ((none) keep)
    ((some e)
      (let [(len (charCount b start e 0))]
        (if (and (< keep cap) (or (= keep 0) (<= (+ used len) byteCap)))
          (pageKeep b (optionOr (listTail ends) (list)) e cap byteCap (+ keep 1) (+ used len))
          keep))))

fn nthAnchor c: String b: Bytes anchor: String idx: Int64 seen: Int64 want: Int64 -> Int64
  (if (or (< idx 0) (>= seen want)) idx (nthAnchor c b anchor (k/findFrom c b anchor (+ idx 1)) (+ seen 1) want))

fn lineStart b: Bytes i: Int64 -> Int64
  (cond ((<= i 0) 0) ((= (bytesGet b (- i 1)) 10) i) (else (lineStart b (- i 1))))

fn charsEnd b: Bytes n: Int64 i: Int64 left: Int64 -> Int64
  (cond
    ((>= i n) n)
    ((= (& (bytesGet b i) 192) 128) (charsEnd b n (+ i 1) left))
    ((= left 0) i)
    (else (charsEnd b n (+ i 1) (- left 1))))

(schema ReadReq (:f id Int64) (:f rel String) (:f anchor String) (:f limit Int64) (:f byteCap Int64))

fn emitRead req: ReadReq content: String sliceInfo: String baseLine: Int64 -> StepOutcome
  (let [(cap (if (> req.limit 0) req.limit 200))
        (b (stringToBytes content))
        (ends (k/lineEnds content))
        (total (listLength ends))
        (keep (pageKeep b ends 0 cap req.byteCap 0 0))
        (cut (and (stringEmpty? req.anchor) (< keep total)))
        (body (if cut (optionOr (stringSlice content 0 (optionOr (listGet ends (- keep 1)) 0)) "") content))
        (trunc (if cut
                 (str " :truncated true :limit " (stringFromInt64 cap) " :maxBytes " (stringFromInt64 req.byteCap) " :totalLines " (stringFromInt64 total)
                      " :more (:start " (stringFromInt64 (+ baseLine keep)) " :end " (stringFromInt64 (- (+ baseLine total) 1)) ")")
                 ""))]
    (done (str (stepHead req.id "read") " :status \"ok\" :file \"" req.rel "\"" sliceInfo trunc " :content \"" (k/escapeAsnVal body) "\")")))

fn readSymbol req: ReadReq c: String lang: String sym: String -> StepOutcome
  (let [(found (sy/findSymbol c sym))
        (syms (pairSecond found))]
    (mt (pairFirst found)
      ((none)
        (let [(near (sm/nearestSymbols sym (map (fn [(d sy/SymbolDef)] -> String d.name) syms) 5))]
          (failedStep (str (stepHead req.id "read") " :status \"rejected\" :error-code \":ERR_SYMBOL_NOT_FOUND\" :file \"" req.rel "\" :symbol \"" (k/escapeAsnVal sym)
                           "\" :language \"" lang "\" :symbolsIndexed " (stringFromInt64 (listLength syms)) " :nearest [" (stringJoin (map quoted near) " ") "])"))))
      ((some hit)
        (let [(hs hit.start)
              (he hit.end)
              (first (sy/lineOf c hs))]
          (emitRead req (optionOr (stringSlice c hs he) "")
                    (str " :symbol \"" (k/escapeAsnVal sym) "\" :kind \"" (k/escapeAsnVal hit.kind) "\" :language \"" lang "\" :start " (stringFromInt64 first)
                         " :end " (stringFromInt64 (sy/lineOf c (max hs (- he 1)))))
                    first)))))

fn readAnchor req: ReadReq c: String kw: (Map String String) -> StepOutcome
  (let [(anchor req.anchor)
        (b (stringToBytes c))
        (want (max 1 (optionOr (pyInt (k/kwOr kw "occurrence" "1")) 1)))
        (idx (nthAnchor c b anchor (k/findFrom c b anchor 0) 1 want))]
    (if (< idx 0)
      (failedStep (str (stepHead req.id "read") " :status \"rejected\" :error-code \":ERR_ANCHOR_NOT_FOUND\" :file \"" req.rel "\" :anchor \"" (k/escapeAsnVal anchor) "\")"))
      (let [(st (lineStart b idx))
            (span (if (> req.limit 0) req.limit 1000))
            (e (charsEnd b (stringLength c) st span))]
        (emitRead req (optionOr (stringSlice c st e) "") (str " :anchor \"" (k/escapeAsnVal anchor) "\" :occurrence " (stringFromInt64 want)) 1))))

fn readRange req: ReadReq c: String rStart: Int64 rEnd: Int64 -> StepOutcome
  (let [(ends (k/lineEnds c))
        (n (listLength ends))
        (lo (if (> rStart 0) rStart 1))
        (hi (if (> rEnd 0) rEnd n))]
    (if (or (> lo n) (< hi lo))
      (failedStep (str (stepHead req.id "read") " :status \"rejected\" :error-code \":ERR_RANGE_OUT_OF_BOUNDS\" :file \"" req.rel "\" :start " (stringFromInt64 lo)
                       " :end " (stringFromInt64 hi) " :lines " (stringFromInt64 n) ")"))
      (let [(top (min hi n))
            (from (if (= lo 1) 0 (optionOr (listGet ends (- lo 2)) 0)))
            (to (optionOr (listGet ends (- top 1)) 0))]
        (emitRead req (optionOr (stringSlice c from to) "") (str " :start " (stringFromInt64 lo) " :end " (stringFromInt64 top)) lo))))

fn readNumber kw: (Map String String) key: String -> (Option Int64)
  (let [(v (k/kwOr kw key ""))]
    (if (stringEmpty? v) (some 0) (pyInt v)))

fn readStep! root: String id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(raw (k/kwOr kw "file" (k/kwOr kw "path" (optionOr (listHead args) ""))))
        (target (if (stringEmpty? raw) (pair "" "") (k/resolveEditTarget! root raw)))
        (fpath (pairFirst target))
        (perr (pairSecond target))
        (sym (k/kwOr kw "symbol" (k/kwOr kw "sym" "")))
        (anchor (k/kwOr kw "anchor" ""))
        (lim (readNumber kw "limit"))
        (rs (readNumber kw "start"))
        (re (readNumber kw "end"))
        (numOk (and (some? lim) (some? rs) (some? re)))]
    (cond
      ((stringEmpty? raw) (rejected id "read" "ERR_MISSING_ARG" " :message \"Missing file argument\""))
      ((not (stringEmpty? perr)) (rejected id "read" (if (stringContains? perr "Ambiguous") "ERR_AMBIGUOUS_PATH" "ERR_BOUNDARY_VIOLATION") (msgTail perr)))
      ((not (k/isFile! fpath)) (rejected id "read" "ERR_FILE_NOT_FOUND" (msgTail (str "File not found: " raw))))
      ((not numOk) (rejected id "read" "ERR_INVALID_ARG" " :message \":limit, :start and :end must be integers\""))
      (else
        (mt (fileReadString fpath)
          ((err e) (rejected id "read" "ERR_READ_FAILED" (msgTail (str "Failed to read file: " e))))
          ((ok bytesText)
            (let [(kind (k/binaryKind bytesText))
                  (rel (k/escapeAsnVal (k/relToRoot root fpath)))]
              (if (not (stringEmpty? kind))
                (failedStep (str (stepHead id "read") " :status \"rejected\" :error-code \":ERR_BINARY\" :file \"" rel "\" :bytes "
                                 (stringFromInt64 (mt (fileStat fpath) ((ok st) st.size) ((err _) (stringLength bytesText)))) " :kind \"" kind "\")"))
                (let [(c (k/universalNewlines bytesText))
                      (byteCap (mt (pyInt (k/kwOr kw "maxBytes" "12000")) ((some v) (max 256 v)) ((none) 12000)))
                      (req (ReadReq :id id :rel rel :anchor anchor :limit (optionOr lim 0) :byteCap byteCap))
                      (lang (sy/languageOf! fpath))
                      (s0 (optionOr rs 0))
                      (e0 (optionOr re 0))]
                  (cond
                    ((and (not (stringEmpty? sym)) (stringEmpty? lang)) (rejected id "read" "ERR_NOT_PORTED" (str " :file \"" (k/escapeAsnVal raw) "\" :symbol \"" (k/escapeAsnVal sym) "\" :message \"Symbol reads for this language are not ported to ASL\"")))
                    ((not (stringEmpty? sym)) (readSymbol req c lang sym))
                    ((not (stringEmpty? anchor)) (readAnchor req c kw))
                    ((or (!= s0 0) (!= e0 0)) (readRange req c s0 e0))
                    (else (emitRead req c "" 1)))))))))))


fn boolKw? kw: (Map String String) key: String -> Bool
  (let [(v (k/lstripColons (stringLower (optionOr (mapGet kw key) ""))))]
    (or (= v "true") (= v "1")))

fn tail400 s: String -> String
  (let [(n (stringLength s))]
    (if (> n 400) (optionOr (stringSlice s (- n 400) n) "") s))

fn packStep! root: String id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(ctx (d/contextFromEnv! root (resultOr (realPath ".") ".")))
        (aslPath (k/joinPath ctx.binDir "asl"))
        (target (k/kwOr kw "target" (optionOr (listHead args) "")))
        (baseArgs (list aslPath "pack"))
        (a1 (if (not (stringEmpty? target)) (listAppend baseArgs (list "--target" (k/lstripColons target))) baseArgs))
        (a2 (if (boolKw? kw "quick") (listAppend a1 (list "--quick")) a1))
        (a3 (if (or (boolKw? kw "dist") (boolKw? kw "all")) (listAppend a2 (list "--dist")) a2))
        (a4 (if (or (boolKw? kw "self") (boolKw? kw "selfOnly")) (listAppend a3 (list "--self")) a3))
        (a5 (if (boolKw? kw "install") (listAppend a4 (list "--install")) a4))
        (v (k/kwOr kw "version" ""))
        (a6 (if (not (stringEmpty? v)) (listAppend a5 (list "--version" v)) a5))
        (a7 (if (or (boolKw? kw "skip_gates") (boolKw? kw "skipGates")) (listAppend a6 (list "--skip-gates")) a6))
        (sp (d/spawnRun a7 (some ctx.rootDir) (mapEmpty) 300))]
    (cond
      ((not (stringEmpty? sp.failure))
        (rejected id "pack" "ERR_EXEC_FAILED" (msgTail sp.failure)))
      ((!= sp.code 0)
        (let [(errS (d/pyStrip sp.errText))
              (outS (d/pyStrip sp.out))
              (rawMsg (cond ((not (stringEmpty? errS)) errS) ((not (stringEmpty? outS)) outS) (else "pack failed")))
              (msg (tail400 rawMsg))]
          (failedStep (str (stepHead id "pack") " :status \"rejected\" :error-code \":ERR_PACK_FAILED\" :exitCode " (stringFromInt64 sp.code) " :message \"" (k/escapeAsnVal msg) "\")"))))
      (else
        (let [(tOut (if (not (stringEmpty? target)) target "all"))]
          (done (str (stepHead id "pack") " :status \"ok\" :target \"" (k/escapeAsnVal tOut) "\" :exitCode 0)"))))))

fn targetSource! root: String kw: (Map String String) args: (List String) -> (Result (Pair String String) String)
  (let [(raw (k/kwOr kw "file" (k/kwOr kw "path" (optionOr (listGet args 1) ""))))
        (target (if (stringEmpty? raw) (pair "" "Missing :file") (k/resolveEditTarget! root raw)))]
    (cond
      ((not (stringEmpty? (pairSecond target))) (err (pairSecond target)))
      ((not (k/isFile! (pairFirst target))) (err (str "File not found: " raw)))
      (else (mt (fileReadString (pairFirst target)) ((ok text) (ok (pair (pairFirst target) text))) ((err e) (err (str "Failed to read " raw ": " e)))))))

fn compiled! kind: String path: String source: String -> (Result String (List String))
  (cond
    ((listContains? (conv/kinds) kind) (conv/convertSource kind source))
    (else
      (mt (jsc/compileWithTypes! path)
        ((err ds) (err (map (fn [(d ty/IrDiag)] -> String (str d.code ": " d.message)) ds)))
        ((ok both) (ok (if (= kind "ts") (pairSecond both) (pairFirst both)))))))

fn targetConverted! root: String id: Int64 tname: String kw: (Map String String) args: (List String) -> (Result String StepOutcome)
  (mt (targetSource! root kw args)
    ((err e) (err (rejected id "target" "ERR_MISSING_ARG" (msgTail e))))
    ((ok found)
      (mt (compiled! tname (pairFirst found) (pairSecond found))
        ((ok text) (ok text))
        ((err es) (err (rejected id "target" "ERR_TARGET" (str " :target \"" tname "\" :errors (" (stringJoin (map (fn [(e String)] -> String (str "\"" (k/escapeAsnVal e) "\"")) es) " ") ")")))))))

fn targetStep id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(rawName (k/kwOr kw "name" (k/kwOr kw "target" (k/kwOr kw "to" (optionOr (listHead args) "list")))))
        (tname (k/lstripColons rawName))]
    (cond
      ((= tname "list")
        (done (str (stepHead id "target") " :status \"ok\" :targets (\"svg\" \"html\" \"css\" \"js\" \"ts\") :note \"svg, html and css convert an ASN form; js and ts compile an ASL entry module; :out stages the result like (:write)\")")))
      ((= tname "distrib")
        (rejected id "target" "ERR_NOT_IMPLEMENTED" " :message \"distribution generation is not connected to its generator\""))
      ((listContains? (list "sh" "shell" "posix" "ps1" "powershell" "cmd" "bat" "c" "go" "llvm" "py" "rs" "swift" "wat") tname)
        (rejected id "target" "ERR_NOT_IMPLEMENTED" (str " :message \"No compiler is wired for target " (k/escapeAsnVal tname) "\"")))
      (else
        (rejected id "target" "ERR_UNKNOWN_TARGET" (str " :message \"Unknown compilation target: " (k/escapeAsnVal tname) "\"")))))

fn targetWired? kw: (Map String String) args: (List String) -> Bool
  (listContains? ["svg" "html" "css" "js" "ts"] (k/lstripColons (k/kwOr kw "name" (k/kwOr kw "target" (k/kwOr kw "to" (optionOr (listHead args) "list"))))))

fn identChar? c: String first: Bool -> Bool
  (let [(k (charCode c))]
    (if first
      (or (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)))
      (or (and (>= k 65) (<= k 90)) (and (>= k 97) (<= k 122)) (and (>= k 48) (<= k 57)) (= c "_") (= c "-"))))

fn ident? s: String -> Bool
  (and (not (stringEmpty? s))
       (identChar? (k/charAt s 0) true)
       (listAll? (fn [(c String)] -> Bool (identChar? c false)) (stringChars (optionOr (stringSlice s 1 (stringLength s)) ""))))

fn badKwItems act: String mode: String stepOp: String -> (List String)
  (let [(validAction (listContains? (list "list" "spawn" "step" "snapshot" "close") act))
        (b1 (if (and (ident? act) validAction) (list) (list "action")))
        (b2 (if (ident? mode) b1 (listAppend b1 (list "mode"))))
        (b3 (if (ident? stepOp) b2 (listAppend b2 (list "stepOp"))))]
    b3)

fn browserSessionStep! id: Int64 kw: (Map String String) args: (List String) -> StepOutcome
  (let [(actRaw (k/kwOr kw "action" (k/kwOr kw "act" (optionOr (listHead args) "list"))))
        (act (k/lstripColons actRaw))
        (sid (k/kwOr kw "sessionId" (k/kwOr kw "session_id" "")))
        (modeRaw (k/kwOr kw "mode" "auto"))
        (mode (k/lstripColons modeRaw))
        (stepOpRaw (k/kwOr kw "stepOp" (k/kwOr kw "op" "navigate")))
        (stepOp (k/lstripColons stepOpRaw))
        (url (k/kwOr kw "url" (k/kwOr kw "target" "")))
        (eSid (k/escapeAsnVal sid))
        (eUrl (k/escapeAsnVal url))
        (eStepOp (k/escapeAsnVal stepOp))
        (eAct (k/escapeAsnVal act))
        (badKw (badKwItems act mode stepOp))]
    (if (not (listEmpty? badKw))
      (rejected id "browserSession" "ERR_INVALID_ARG" (str " :message \"Fields must be identifiers: " (k/escapeAsnVal (stringJoin badKw " ")) "\""))
      (let [(portStr (optionOr (envGet "ASL_GATEWAY_PORT") "8765"))
            (gwPort (optionOr (stringToInt64 portStr) 8765))
            (gwUrl (str "http://127.0.0.1:" (stringFromInt64 gwPort)))
            (isList (= act "list"))
            (body (if isList "" (str "(:sessionAction :action :" act " :sessionId \"" eSid "\" :mode :" mode " :stepOp :" stepOp " :url \"" eUrl "\")")))
            (reqUrl (if isList (str gwUrl "/api/asl/browser/session/list") (str gwUrl "/api/asl/browser/session/" act)))
            (cmd (if isList
                   (list "curl" "-sS" "-f" "-m" "2" reqUrl)
                   (list "curl" "-sS" "-f" "-m" "2" "-X" "POST" "-H" "Content-Type: application/asn+sexpr" "-d" body reqUrl)))
            (sp (d/spawnRun cmd (none) (mapEmpty) 3))
            (dispatched (and (stringEmpty? sp.failure) (= sp.code 0)))]
        (if dispatched
          (let [(data (d/pyStrip sp.out))]
            (cond
              ((stringContains? data ":status :rejected")
                (rejected id "browserSession" "ERR_GATEWAY_REJECTED" (str " :message \"" (k/escapeAsnVal (tail400 data)) "\"")))
              ((and (= act "list") (not (stringContains? data ":browserSessions")))
                (rejected id "browserSession" "ERR_GATEWAY_RESPONSE" " :message \"Gateway list response has no sessions field\""))
              ((and (not (= act "list")) (not (stringContains? data ":status :ok")))
                (rejected id "browserSession" "ERR_GATEWAY_RESPONSE" " :message \"Gateway response does not confirm success\""))
              ((= act "list")
                (done (str (stepHead id "browserSession") " :action \"list\" :status \"ok\" :sessions " data ")")))
              ((= act "spawn")
                (done (str (stepHead id "browserSession") " :action \"spawn\" :status \"ok\" :receipt\n" data ")")))
              ((= act "snapshot")
                (done (str (stepHead id "browserSession") " :action \"snapshot\" :status \"ok\" :receipt\n" data ")")))
              ((= act "step")
                (done (str (stepHead id "browserSession") " :action \"step\" :status \"ok\" :receipt\n" data ")")))
              ((= act "close")
                (done (str (stepHead id "browserSession") " :action \"close\" :status \"ok\" :receipt\n" data ")")))
              (else
                (done (str (stepHead id "browserSession") " :action \"" eAct "\" :status \"ok\" :sessionId \"" eSid "\" :receipt\n" data ")")))))
          (rejected id "browserSession" "ERR_GATEWAY_FAILED"
                    (str " :message \"Browser gateway request failed (curl exit "
                         (stringFromInt64 sp.code) ")\""))))))

fn envOr! name: String -> String
  (optionOr (envGet name) "")

fn toolchainRoot! root: String -> String
  (let [(given (k/toolEnv! "ROOT_DIR"))
        (script (k/toolEnv! "SCRIPT_DIR"))
        (cwd (resultOr (realPath ".") root))]
    (cond ((not (stringEmpty? given)) given)
          ((not (stringEmpty? script)) (k/dirName script))
          (else cwd)))

fn binDirectory! root: String -> String
  (let [(given (k/toolEnv! "SCRIPT_DIR"))
        (toolRoot (toolchainRoot! root))]
    (if (stringEmpty? given) (k/joinPath toolRoot "bin") given))

fn knowContext! root: String -> s/KnowCtx
  (let [(ws (if (stringEmpty? (envOr! "ASL_ROOT")) root (envOr! "ASL_ROOT")))
        (toolRoot (toolchainRoot! root))
        (bin (binDirectory! root))
        (vfs (envOr! "ASL_VFS_DIR"))
        (tools (optionOr (envGet "ASL_TOOLS_ASN") (k/joinPath toolRoot "asl/grammar/tools.asn")))]
    (s/KnowCtx :ws ws :toolRoot toolRoot :binDir bin :vfsDir vfs :toolsFile tools :home (envOr! "HOME")))

fn gateContext! root: String -> g/GateEnv
  (let [(toolRoot (toolchainRoot! root))
        (bin (binDirectory! root))
        (given (envOr! "ASL_HOST"))
        (host (if (stringEmpty? given) (k/joinPath toolRoot "asl/host/out/asl-host") given))
        (vs (v/vfsAt root (v/vfsRoot! root (envOr! "ASL_VFS_DIR") (envOr! "HOME")) (envOr! "ASL_SESSION")))
        (staged (stagedCheckFiles! vs (v/stagedPaths! vs)))]
    (g/GateEnv :root root :rootDir toolRoot :binDir bin :host host :staged staged))

fn stagedCheckFiles! vs: v/Vfs paths: (List String) -> (List (Pair String String))
  (mt (listHead paths)
    ((none) (list))
    ((some path)
      (let [(rest (optionOr (listTail paths) (list)))]
        (mt (v/stagedContent! vs path)
          ((some content) (cons (pair path content) (stagedCheckFiles! vs rest)))
          ((none) (stagedCheckFiles! vs rest))))))

fn checkEnv! env: g/GateEnv -> g/GateEnv
  (let [(vs (v/vfsAt env.root
                     (v/vfsRoot! env.root (envOr! "ASL_VFS_DIR") (envOr! "HOME"))
                     (envOr! "ASL_SESSION")))
        (staged (stagedCheckFiles! vs (v/stagedPaths! vs)))]
    (g/GateEnv :root env.root :rootDir env.rootDir :binDir env.binDir :host env.host :staged staged))

fn checkResult! env: g/GateEnv path: String content: String before: (Option String) -> e/SyntaxResult
  (let [(r (g/validateStaged! (checkEnv! env) path before content false))
        (code (optionOr (listHead r) ""))
        (msg (optionOr (listGet r 1) ""))]
    (e/SyntaxResult :status (if (stringEmpty? code) "ok" "error") :message msg :before "" :host ""))

fn foreignResult! env: g/GateEnv path: String content: String -> e/SyntaxResult
  (let [(r (g/foreignSyntax! env path content))]
    (e/SyntaxResult :status (pairFirst r) :message (pairSecond r) :before "" :host ""))

fn editCheckers! env: g/GateEnv -> e/Checkers
  (e/Checkers :aslCheck (fn [(path String) (content String) (before (Option String))] -> e/SyntaxResult (checkResult! env path content before))
              :foreignCheck (fn [(path String) (content String)] -> e/SyntaxResult (foreignResult! env path content)))

fn runNested! root: String id: Int64 form: String held: (List String) -> StepOutcome
  (let [(p (k/parseStep form))]
    (runStepHeld! root id p.op p.kwargs p.args held form))

fn targetRun! root: String id: Int64 kw: (Map String String) args: (List String) held: (List String) -> StepOutcome
  (let [(tname (k/lstripColons (k/kwOr kw "name" (k/kwOr kw "target" (k/kwOr kw "to" (optionOr (listHead args) ""))))))
        (out (k/kwOr kw "out" ""))]
    (mt (targetConverted! root id tname kw args)
      ((err refusal) refusal)
      ((ok text)
        (if (stringEmpty? out)
          (done (str (stepHead id "target") " :status \"ok\" :target \"" tname "\" :bytes " (stringFromInt64 (stringLength text)) " :output \"" (k/escapeAsnVal text) "\")"))
          (mt (e/editOp! (resultOr (v/vfsContext! root) (v/vfsAt root (v/vfsRoot! root (envOr! "ASL_VFS_DIR") (envOr! "HOME")) (envOr! "ASL_SESSION")))
                        (editCheckers! (gateContext! root))
                        (fn [(n Int64) (form String) (h (List String))] -> k/EditOutcome
                          (let [(r (runNested! root n form h))] (k/EditOutcome :lines r.lines :errCount r.errCount)))
                        held id "write" (mapSet (mapSet (mapEmpty) "file" out) "content" text) [])
            ((some staged) (StepOutcome :lines staged.lines :errCount staged.errCount))
            ((none) (rejected id "target" "ERR_WRITE_FAILED" " :message \"the staging buffer did not take the write\"")))))))

fn delegateContext! root: String -> d/DelegateCtx
  (d/contextFromEnv! root (resultOr (realPath ".") root))

fn runStepHeld! root: String id: Int64 op: String kw: (Map String String) args: (List String) held: (List String) form: String -> StepOutcome
  (cond
    ((= op "echo") (echoStep id kw args))
    ((= op "eval") (evalStep root id kw args))
    ((= op "mem")
      (let [(out (m/memStep! root id kw args held))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    ((= op "doc")
      (let [(out (doc/docStep! root id kw))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    ((= op "ping") (done (str (stepHead id "ping") " :status \"ok\" :pong true)")))
    ((= op "read") (readStep! root id kw args))
    ((= op "tree") (treeStep! root id kw args))
    ((= op "run") (runStep id kw args))
    ((= op "job") (jobStep id kw args))
    ((= op "consult") (consultStep id kw args))
    ((= op "pack") (packStep! root id kw args))
    ((and (or (= op "target") (= op "codegen")) (targetWired? kw args)) (targetRun! root id kw args held))
    ((or (= op "target") (= op "codegen")) (targetStep id kw args))
    ((= op "browserSession") (browserSessionStep! id kw args))
    ((or (= op "q") (= op "query"))
      (let [(out (s/queryStep! (knowContext! root) id kw args))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    ((= op "where")
      (let [(out (s/whereStep! (knowContext! root) id kw args))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    ((= op "note")
      (let [(out (s/noteStep! (knowContext! root) id kw args))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    ((= op "tools")
      (let [(out (t/toolsStep! (knowContext! root) id kw args))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    ((= op "help")
      (let [(out (t/helpStep! (knowContext! root) id kw args))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    ((= op "observe")
      (let [(out (s/observeStep! (knowContext! root) id kw args (list "format" "depth" "root" "max" "dim" "mode" "limit" "sort" "filter" "detail" "exclude" "symbol" "scope" "path" "spec" "id")))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    ((= op "lens")
      (let [(out (l/lensStep (delegateContext! root).rootDir id kw args))]
        (StepOutcome :lines (list out.line) :errCount out.errCount)))
    ((g/gateOp? op)
      (let [(env (gateContext! root))
            (out (g/runGate! env (fn [(n Int64) (form String)] -> (Pair (List String) Int64)
                                  (let [(r (runNested! root n form (list)))] (pair r.lines r.errCount))) id op kw args))]
        (StepOutcome :lines out.lines :errCount out.errCount)))
    (else
      (mt (e/editOp! (resultOr (v/vfsContext! root) (v/vfsAt root (v/vfsRoot! root (envOr! "ASL_VFS_DIR") (envOr! "HOME")) (envOr! "ASL_SESSION")))
                    (editCheckers! (gateContext! root))
                    (fn [(n Int64) (form String) (held (List String))] -> k/EditOutcome
                      (let [(r (runNested! root n form held))] (k/EditOutcome :lines r.lines :errCount r.errCount)))
                    held id op kw args)
        ((some out) (StepOutcome :lines out.lines :errCount out.errCount))
        ((none)
          (if (d/delegateOp? op)
            (let [(out (d/runDelegate (delegateContext! root) id op kw args form))]
              (StepOutcome :lines (list out.line) :errCount out.errCount))
            (unimplemented id op))))))

fn runStep! root: String id: Int64 form: String -> StepOutcome
  (runNested! root id form (list))
