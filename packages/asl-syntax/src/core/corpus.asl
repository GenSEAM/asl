(module asl-syntax/core/corpus
  :x [UpstreamEntry
      UpstreamManifest
      CorpusMismatch
      CorpusReport
      makeUpstreamEntry
      makeUpstreamManifest
      makeCorpusMismatch
      makeCorpusReport
      mismatchPath
      mismatchOffset
      mismatchExpectedLen
      mismatchActualLen
      mismatchReason
      reportFiles
      reportBytes
      reportMismatches
      reportMismatchCount
      reportSuccess?
      manifestEntries
      copyBytes!
      cloneBytes!
      findFirstDiffOffset
      gitTrackedFiles!
      verifyUpstreamEntry!
      verifyUpstreamManifest!
      verifyUpstreamManifestFile!
      parseUpstreamManifest
      runCorpusOnFiles!
      runCorpus!
      runCorpusTreeOnFiles!
      runCorpusTree!]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/asl/lex :a lex)])

(schema UpstreamEntry
  (:f url String)
  (:f commit String)
  (:f sha256 String)
  (:f license String)
  (:f path String))

(schema UpstreamManifest
  (:f entries (List UpstreamEntry)))

(schema CorpusMismatch
  (:f path String)
  (:f firstDiffOffset Int64)
  (:f expectedLength Int64)
  (:f actualLength Int64)
  (:f reason String))

(schema CorpusReport
  (:f files Int64)
  (:f bytes Int64)
  (:f mismatches (List CorpusMismatch)))

fn makeUpstreamEntry url: String commit: String sha256: String license: String path: String -> UpstreamEntry
  (UpstreamEntry :url url :commit commit :sha256 sha256 :license license :path path)

fn makeUpstreamManifest entries: (List UpstreamEntry) -> UpstreamManifest
  (UpstreamManifest :entries entries)

fn makeCorpusMismatch path: String firstDiffOffset: Int64 expectedLength: Int64 actualLength: Int64 reason: String -> CorpusMismatch
  (CorpusMismatch :path path
                  :firstDiffOffset firstDiffOffset
                  :expectedLength expectedLength
                  :actualLength actualLength
                  :reason reason)

fn makeCorpusReport files: Int64 bytes: Int64 mismatches: (List CorpusMismatch) -> CorpusReport
  (CorpusReport :files files :bytes bytes :mismatches mismatches)

fn mismatchPath m: CorpusMismatch -> String
  m.path

fn mismatchOffset m: CorpusMismatch -> Int64
  m.firstDiffOffset

fn mismatchExpectedLen m: CorpusMismatch -> Int64
  m.expectedLength

fn mismatchActualLen m: CorpusMismatch -> Int64
  m.actualLength

fn mismatchReason m: CorpusMismatch -> String
  m.reason

fn reportFiles r: CorpusReport -> Int64
  r.files

fn reportBytes r: CorpusReport -> Int64
  r.bytes

fn reportMismatches r: CorpusReport -> (List CorpusMismatch)
  r.mismatches

fn reportMismatchCount r: CorpusReport -> Int64
  (listLength r.mismatches)

fn reportSuccess? r: CorpusReport -> Bool
  (listEmpty? r.mismatches)

fn manifestEntries m: UpstreamManifest -> (List UpstreamEntry)
  m.entries

fn copyBytes! src: Bytes dst: Bytes idx: Int64 limit: Int64 -> Unit
  (if (>= idx limit)
    ()
    (do
      (bytesSet dst idx (bytesGet src idx))
      (copyBytes! src dst (+ idx 1) limit)))

fn cloneBytes! bs: Bytes -> Bytes
  (let [(len (bytesLength bs))
        (out (bytesAlloc len))]
    (do
      (copyBytes! bs out 0 len)
      out))

fn findDiffLoop a: Bytes b: Bytes idx: Int64 limit: Int64 -> (Option Int64)
  (if (>= idx limit)
    (none)
    (if (!= (bytesGet a idx) (bytesGet b idx))
      (some idx)
      (findDiffLoop a b (+ idx 1) limit)))

fn findFirstDiffOffset expected: Bytes actual: Bytes -> (Option Int64)
  (let [(lenA (bytesLength expected))
        (lenB (bytesLength actual))
        (minLen (min lenA lenB))]
    (mt (findDiffLoop expected actual 0 minLen)
      ((some diffAt) (some diffAt))
      ((none)
       (if (!= lenA lenB)
         (some minLen)
         (none)))))

fn normalizeExt ext: String -> String
  (if (stringStartsWith? ext ".")
    (optionOr (stringSlice ext 1 (stringLength ext)) "")
    ext)

fn gitTrackedFiles! ext: String -> (Result (List String) String)
  (let [(cleanExt (normalizeExt ext))
        (cmd (if (stringEmpty? cleanExt)
               "git ls-files"
               (str "git ls-files \"*." cleanExt "\"")))
        (out (processRun cmd))]
    (if (!= out.exitCode 0)
      (err (str "git ls-files failed: " out.stderr))
      (let [(rawLines (stringSplit out.stdout "\n"))
            (files (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) rawLines))]
        (ok files))))

fn corpusFilesLoop! pipeline: (fn [Bytes] -> (Result Bytes String))
                   files: (List String)
                   totalFiles: Int64
                   totalBytes: Int64
                   mismatches: (List CorpusMismatch) -> CorpusReport
  (if (listEmpty? files)
    (CorpusReport :files totalFiles :bytes totalBytes :mismatches (listReverse mismatches))
    (let [(head (optionOr (listHead files) ""))
          (tail (optionOr (listTail files) (list)))]
      (mt (fileReadBytes head)
        ((err ioErr)
         (let [(m (CorpusMismatch :path head :firstDiffOffset -1 :expectedLength 0 :actualLength 0 :reason (str "read error: " ioErr)))]
           (corpusFilesLoop! pipeline tail (+ totalFiles 1) totalBytes (cons m mismatches))))
        ((ok bs)
         (let [(fileLen (bytesLength bs))
               (newBytes (+ totalBytes fileLen))]
           (mt (pipeline bs)
             ((err parseErr)
              (let [(m (CorpusMismatch :path head :firstDiffOffset -1 :expectedLength fileLen :actualLength 0 :reason (str "parse error: " parseErr)))]
                (corpusFilesLoop! pipeline tail (+ totalFiles 1) newBytes (cons m mismatches))))
             ((ok printed)
              (mt (findFirstDiffOffset bs printed)
                ((none)
                 (corpusFilesLoop! pipeline tail (+ totalFiles 1) newBytes mismatches))
                ((some diffOff)
                 (let [(m (CorpusMismatch :path head :firstDiffOffset diffOff :expectedLength fileLen :actualLength (bytesLength printed) :reason "print mismatch"))]
                   (corpusFilesLoop! pipeline tail (+ totalFiles 1) newBytes (cons m mismatches))))))))))))

fn runCorpusOnFiles! pipeline: (fn [Bytes] -> (Result Bytes String)) files: (List String) -> CorpusReport
  (corpusFilesLoop! pipeline files 0 0 (list))

fn runCorpus! pipeline: (fn [Bytes] -> (Result Bytes String)) ext: String -> (Result CorpusReport String)
  (mt (gitTrackedFiles! ext)
    ((ok files) (ok (runCorpusOnFiles! pipeline files)))
    ((err msg) (err msg)))

fn runCorpusTreeOnFiles! parse: (fn [Bytes] -> (Result tr/Node String)) print: (fn [Bytes tr/Node] -> Bytes) files: (List String) -> CorpusReport
  (let [(pipeline (fn [(bs Bytes)] -> (Result Bytes String)
                    (mt (parse bs)
                      ((ok root) (ok (print bs root)))
                      ((err e) (err e)))))]
    (runCorpusOnFiles! pipeline files))

fn runCorpusTree! parse: (fn [Bytes] -> (Result tr/Node String)) print: (fn [Bytes tr/Node] -> Bytes) ext: String -> (Result CorpusReport String)
  (mt (gitTrackedFiles! ext)
    ((ok files) (ok (runCorpusTreeOnFiles! parse print files)))
    ((err msg) (err msg)))

fn verifyUpstreamEntry! entry: UpstreamEntry -> (Result Bool String)
  (if (stringEmpty? entry.url)
    (err "missing required field: url")
    (if (stringEmpty? entry.commit)
      (err "missing required field: commit")
      (if (stringEmpty? entry.sha256)
        (err "missing required field: sha256")
        (if (stringEmpty? entry.license)
          (err "missing required field: license")
          (if (stringEmpty? entry.path)
            (err "missing required field: path")
            (mt (fileReadBytes entry.path)
              ((err ioErr)
               (err (str "upstream file not found: " entry.path " (" ioErr ")")))
              ((ok bs)
               (let [(actualSha (bytesSha256 bs))]
                 (if (!= actualSha entry.sha256)
                   (err (str "sha256 mismatch for " entry.path ": expected " entry.sha256 " but got " actualSha))
                   (ok true))))))))))

fn verifyEntriesLoop! entries: (List UpstreamEntry) errors: (List String) -> (Result Bool (List String))
  (if (listEmpty? entries)
    (if (listEmpty? errors)
      (ok true)
      (err (listReverse errors)))
    (let [(head (optionOr (listHead entries) (UpstreamEntry :url "" :commit "" :sha256 "" :license "" :path "")))
          (tail (optionOr (listTail entries) (list)))]
      (mt (verifyUpstreamEntry! head)
        ((ok _) (verifyEntriesLoop! tail errors))
        ((err e) (verifyEntriesLoop! tail (cons e errors))))))

fn verifyUpstreamManifest! manifest: UpstreamManifest -> (Result Bool (List String))
  (verifyEntriesLoop! manifest.entries (list))

(schema DyckError
  (:f offset Int64)
  (:f msg String))

fn isDyckOpener c: Int64 -> Bool
  (or (= c 40) (or (= c 91) (= c 123)))

fn dyckCloserWant c: Int64 -> Int64
  (if (= c 41) 40 (if (= c 93) 91 123))

fn isDyckCloser c: Int64 -> Bool
  (or (= c 41) (or (= c 93) (= c 125)))

fn dyckLoop bs: Bytes len: Int64 i: Int64 stack: (List (Pair Int64 Int64)) inStr: Bool inComment: Bool strStart: Int64 -> (Option DyckError)
  (if (>= i len)
    (if inStr
      (some (DyckError :offset strStart :msg "unterminated string"))
      (if (not (listEmpty? stack))
        (let [(top (optionOr (listHead stack) (pair 0 0)))]
          (some (DyckError :offset (pairSecond top) :msg "unclosed delimiter")))
        (none)))
    (let [(c (bytesGet bs i))]
      (if inComment
        (if (= c 10)
          (dyckLoop bs len (+ i 1) stack false false strStart)
          (dyckLoop bs len (+ i 1) stack false true strStart))
        (if inStr
          (if (= c 92)
            (if (>= (+ i 1) len)
              (some (DyckError :offset strStart :msg "unterminated string"))
              (dyckLoop bs len (+ i 2) stack true false strStart))
            (if (= c 34)
              (dyckLoop bs len (+ i 1) stack false false strStart)
              (dyckLoop bs len (+ i 1) stack true false strStart)))
          (if (= c 34)
            (dyckLoop bs len (+ i 1) stack true false i)
            (if (= c 59)
              (dyckLoop bs len (+ i 1) stack false true strStart)
              (if (isDyckOpener c)
                (dyckLoop bs len (+ i 1) (cons (pair c i) stack) false false strStart)
                (if (isDyckCloser c)
                  (if (listEmpty? stack)
                    (some (DyckError :offset i :msg "unexpected closing delimiter"))
                    (let [(top (optionOr (listHead stack) (pair 0 0)))
                          (topC (pairFirst top))
                          (want (dyckCloserWant c))]
                      (if (!= topC want)
                        (some (DyckError :offset i :msg "mismatched closing delimiter"))
                        (dyckLoop bs len (+ i 1) (optionOr (listTail stack) (list)) false false strStart))))
                  (dyckLoop bs len (+ i 1) stack false false strStart)))))))))

fn checkDyckBalance bs: Bytes len: Int64 -> (Option DyckError)
  (dyckLoop bs len 0 (list) false false 0)

(schema RawEntryState
  (:f url String)
  (:f commit String)
  (:f sha256 String)
  (:f license String)
  (:f path String)
  (:f hasUrl Bool)
  (:f hasCommit Bool)
  (:f hasSha256 Bool)
  (:f hasLicense Bool)
  (:f hasPath Bool))

fn emptyEntryState -> RawEntryState
  (RawEntryState :url "" :commit "" :sha256 "" :license "" :path "" :hasUrl false :hasCommit false :hasSha256 false :hasLicense false :hasPath false)

fn parseEntryBodyLoop text: String toks: (List tr/Token) st: RawEntryState -> (Result (Pair UpstreamEntry (List tr/Token)) String)
  (if (listEmpty? toks)
    (err "unexpected end of tokens inside entry")
    (let [(tok (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (if (lex/isRparen tok)
        (if (not st.hasUrl)
          (err "missing key in entry: url")
          (if (not st.hasCommit)
            (err "missing key in entry: commit")
            (if (not st.hasSha256)
              (err "missing key in entry: sha256")
              (if (not st.hasLicense)
                (err "missing key in entry: license")
                (if (not st.hasPath)
                  (err "missing key in entry: path")
                  (ok (pair (UpstreamEntry :url st.url :commit st.commit :sha256 st.sha256 :license st.license :path st.path)
                            (optionOr (listTail toks) (list)))))))))
        (if (not (lex/isKeywordToken tok))
          (err (str "expected keyword in entry but got " tok.kind))
          (let [(kStr (lex/tokenSliceString text tok))]
            (if (and (!= kStr ":url")
                (and (!= kStr ":commit")
                (and (!= kStr ":sha256")
                (and (!= kStr ":license")
                (and (!= kStr ":path")
                     (!= kStr ":note"))))))
              (err (str "unknown key in entry: " kStr))
              (if (or (and (= kStr ":url") st.hasUrl)
                  (or (and (= kStr ":commit") st.hasCommit)
                  (or (and (= kStr ":sha256") st.hasSha256)
                  (or (and (= kStr ":license") st.hasLicense)
                      (and (= kStr ":path") st.hasPath)))))
                (err (str "duplicate key in entry: " kStr))
                (let [(afterKey (optionOr (listTail toks) (list)))]
                  (if (listEmpty? afterKey)
                    (err (str "missing value for key " kStr))
                    (let [(vTok (optionOr (listHead afterKey) (tr/makeToken "" 0 0)))]
                      (if (not (lex/isStringToken vTok))
                        (err (str "expected string value for key " kStr))
                        (let [(vRaw (optionOr (stringSlice text (+ vTok.start 1) (- vTok.end 1)) ""))
                              (nextToks (optionOr (listTail afterKey) (list)))
                              (nextSt (if (= kStr ":note") st (if (= kStr ":url")
                                        (with st :url vRaw :hasUrl true)
                                        (if (= kStr ":commit")
                                          (with st :commit vRaw :hasCommit true)
                                          (if (= kStr ":sha256")
                                            (with st :sha256 vRaw :hasSha256 true)
                                            (if (= kStr ":license")
                                              (with st :license vRaw :hasLicense true)
                                              (with st :path vRaw :hasPath true)))))))]
                          (parseEntryBodyLoop text nextToks nextSt)))))))))))))

fn parseOneEntry text: String toks: (List tr/Token) -> (Result (Pair UpstreamEntry (List tr/Token)) String)
  (if (listEmpty? toks)
    (err "expected (:entry in entries list")
    (let [(t0 (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (if (not (lex/isLparen t0))
        (err "expected (:entry in entries list")
        (let [(tail0 (optionOr (listTail toks) (list)))]
          (if (listEmpty? tail0)
            (err "expected :entry keyword after (")
            (let [(t1 (optionOr (listHead tail0) (tr/makeToken "" 0 0)))]
              (if (or (not (lex/isKeywordToken t1)) (!= (lex/tokenSliceString text t1) ":entry"))
                (err "expected :entry keyword after (")
                (parseEntryBodyLoop text (optionOr (listTail tail0) (list)) (emptyEntryState)))))))))

fn parseEntriesListLoop text: String toks: (List tr/Token) acc: (List UpstreamEntry) -> (Result (Pair (List UpstreamEntry) (List tr/Token)) String)
  (if (listEmpty? toks)
    (err "unexpected end of tokens in :entries list")
    (let [(tok (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (if (lex/isRbracket tok)
        (ok (pair (listReverse acc) (optionOr (listTail toks) (list))))
        (mt (parseOneEntry text toks)
          ((err e) (err e))
          ((ok resPair)
           (parseEntriesListLoop text (pairSecond resPair) (cons (pairFirst resPair) acc)))))))

fn parseManifestTopLoop text: String toks: (List tr/Token) entriesOpt: (Option (List UpstreamEntry)) -> (Result UpstreamManifest String)
  (if (listEmpty? toks)
    (err "unexpected end of manifest")
    (let [(tok (optionOr (listHead toks) (tr/makeToken "" 0 0)))]
      (if (lex/isRparen tok)
        (mt entriesOpt
          ((none) (err "missing :entries in manifest"))
          ((some entries) (ok (UpstreamManifest :entries entries))))
        (if (not (lex/isKeywordToken tok))
          (err (str "unexpected token in manifest: " (lex/tokenSliceString text tok)))
          (let [(kw (lex/tokenSliceString text tok))]
            (if (= kw ":entries")
              (mt entriesOpt
                ((some _) (err "duplicate :entries in manifest"))
                ((none)
                 (let [(afterKw (optionOr (listTail toks) (list)))]
                   (if (listEmpty? afterKw)
                     (err "expected [ after :entries")
                     (let [(openTok (optionOr (listHead afterKw) (tr/makeToken "" 0 0)))]
                       (if (not (lex/isLbracket openTok))
                         (err "expected [ after :entries")
                         (mt (parseEntriesListLoop text (optionOr (listTail afterKw) (list)) (list))
                           ((err e) (err e))
                           ((ok pairRes)
                            (parseManifestTopLoop text (pairSecond pairRes) (some (pairFirst pairRes)))))))))))
              (let [(afterKw (optionOr (listTail toks) (list)))]
                (if (listEmpty? afterKw)
                  (err (str "missing value for keyword " kw))
                  (parseManifestTopLoop text (optionOr (listTail afterKw) (list)) entriesOpt)))))))))

fn isTriviaToken tok: tr/Token -> Bool
  (or (lex/isWhitespaceToken tok)
  (or (lex/isNewlineToken tok)
      (lex/isCommentToken tok)))

fn filterSignificantTokens toks: (List tr/Token) -> (List tr/Token)
  (filter (fn [(t tr/Token)] -> Bool (not (isTriviaToken t))) toks)

fn parseUpstreamManifest text: String -> (Result UpstreamManifest String)
  (let [(bs (stringToBytes text))
        (len (bytesLength bs))]
    (mt (checkDyckBalance bs len)
      ((some dyckErr)
       (err (str "unbalanced manifest at byte " dyckErr.offset ": " dyckErr.msg)))
      ((none)
       (let [(allToks (lex/tokenize text))
             (sigToks (filterSignificantTokens allToks))]
         (if (listEmpty? sigToks)
           (err "empty manifest")
           (let [(t0 (optionOr (listHead sigToks) (tr/makeToken "" 0 0)))]
             (if (not (lex/isLparen t0))
               (err "manifest must start with (")
               (let [(tail0 (optionOr (listTail sigToks) (list)))]
                 (if (listEmpty? tail0)
                   (err "manifest missing top-level symbol")
                   (let [(t1 (optionOr (listHead tail0) (tr/makeToken "" 0 0)))
                         (kw (lex/tokenSliceString text t1))]
                     (if (or (not (lex/isKeywordToken t1))
                             (and (!= kw ":upstreamManifest") (!= kw ":manifest")))
                       (err (str "manifest must start with (:upstreamManifest, got " kw))
                       (parseManifestTopLoop text (optionOr (listTail tail0) (list)) (none)))))))))))))

fn verifyUpstreamManifestFile! path: String -> (Result Bool (List String))
  (mt (fileReadString path)
    ((err ioErr)
     (err (list (str "cannot read manifest file: " path " (" ioErr ")"))))
    ((ok content)
     (mt (parseUpstreamManifest content)
       ((err parseErr)
        (err (list (str "manifest parse error: " parseErr))))
       ((ok manifest)
        (verifyUpstreamManifest! manifest)))))
