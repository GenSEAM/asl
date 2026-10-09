(module aslHarness/bench
  :x [Task Check AnswerIntSpec FileLinePair FileLineAltSpec QuoteExistsSpec IdSetSpec PreserveFact ConflictSide ConflictRow RescoreSum
      formatAsnStr formatAsnBool formatAsnInt formatRescoreLine formatRescoreSumLine
      loadTask! loadTasks! loadForbid loadAnswerInt loadFileLineSet loadFileLineAlt loadQuoteExists loadIdSet loadTrue loadSources loadPreserve loadConflicts loadNoNewFacts loadMaxRatio
      judgeGate judgeMentions judgeAnswerInt judgeQuoteExists! judgeIdSet judgeFileLineAlt
      judgeFileLineReply verdict rescore main]
  :i [(aslHarness/benchAsn :a asn)])

(schema AnswerIntSpec
  (:f value Int64)
  (:f noun String)
  (:f forbid (List Int64)))

(schema FileLinePair
  (:f path String)
  (:f line Int64))

(schema FileLineAltSpec
  (:f path String)
  (:f line Int64)
  (:f alts (List Int64)))

(schema QuoteExistsSpec
  (:f file String)
  (:f line String)
  (:f marker String))

(schema IdSetSpec
  (:f ids (List String))
  (:f done (List String)))

(schema PreserveFact
  (:f id String)
  (:f tokens (List (List String))))

(schema ConflictSide
  (:f values (List String))
  (:f sources (List String)))

(schema ConflictRow
  (:f id String)
  (:f sides (List ConflictSide)))

(schema Check
  (:f gate (Option String))
  (:f unchanged (List String))
  (:f readOnly Bool)
  (:f mentions (List (List String)))
  (:f forbid (List String))
  (:f excuse (List String))
  (:f answerInt (Option AnswerIntSpec))
  (:f fileLineSet (List FileLinePair))
  (:f fileLineAlt (List FileLineAltSpec))
  (:f quoteExists (Option QuoteExistsSpec))
  (:f noFabricatedIdents Bool)
  (:f idSet (Option IdSetSpec))
  (:f sources (List String))
  (:f preserve (List PreserveFact))
  (:f conflicts (List ConflictRow))
  (:f noNewFacts Bool)
  (:f maxRatio (Option Float64)))

(schema Task
  (:f id String)
  (:f dir String)
  (:f prompt String)
  (:f check Check)
  (:f mode String)
  (:f observe (Option String)))

(schema RescoreSum
  (:f caseName String)
  (:f client String)
  (:f condition String)
  (:f passCount Int64)
  (:f runCount Int64))

fn asnField values: (List asn/AsnValue) name: String -> (Option asn/AsnValue)
  (if (< (listLength values) 2)
    (none)
    (mt (listHead values)
      ((none) (none))
      ((some keyValue)
        (mt keyValue
          ((asnAtom value)
            (if (= value name) (listGet values 1) (asnField (listDrop values 2) name)))
          ((asnString value) (asnField (listDrop values 2) name))
          ((asnList items) (asnField (listDrop values 2) name))))))

fn asnFieldString values: (List asn/AsnValue) name: String -> (Option String)
  (mt (asnField values name)
    ((none) (none))
    ((some item)
      (mt item
        ((asnString value) (some value))
        ((asnAtom value) (some value))
        ((asnList items) (none)))))

fn asnFieldBool values: (List asn/AsnValue) name: String -> Bool
  (match (asnFieldString values name)
    ((none) false)
    ((some text) (= text "true")))

fn testAsnNested x: (Result asn/AsnValue String) -> Bool
  (mt x
    ((err message) false)
    ((ok form)
      (mt form
        ((asnList items) true)
        ((asnString value) false)
        ((asnAtom value) false))))

fn casesDir -> String
  "tests/harnessBench/cases"

fn defaultLedger -> String
  "tests/harnessBench/ledger.asn"

fn replyDir! -> String
  (optionOr (envGet "HBENCH_REPLY_DIR") ".asl/run/harnessBench/replies")

fn formatAsnStr s: String -> String
  (let [(rep (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" " "))
        (n (stringLength rep))
        (trunc (if (> n 300) (optionOr (stringSlice rep 0 300) rep) rep))]
    (str "\"" trunc "\""))

fn formatAsnBool b: Bool -> String
  (if b "true" "false")

fn formatAsnInt n: Int64 -> String
  (stringFromInt64 n)

fn formatRescoreLine caseName: String client: String condition: String replyId: String pass: Bool why: String -> String
  (str "(:rescore :case " (formatAsnStr caseName)
       " :client " (formatAsnStr client)
       " :condition " (formatAsnStr condition)
       " :reply " (formatAsnStr replyId)
       " :pass " (formatAsnBool pass)
       (if pass "" (str " :why " (formatAsnStr why)))
       ")")

fn formatRescoreSumLine caseName: String client: String condition: String passCount: Int64 runCount: Int64 -> String
  (str "(:rescoreSum :case " (formatAsnStr caseName)
       " :client " (formatAsnStr client)
       " :condition " (formatAsnStr condition)
       " :pass " (formatAsnInt passCount)
       " :runs " (formatAsnInt runCount)
       ")")

fn loadForbid pats: (List String) -> (Result (List String) String)
  (if (listEmpty? pats)
    (err ":forbid must be a non-empty list of regex strings")
    (if (listAny? (fn [(s String)] -> Bool (stringEmpty? s)) pats)
      (err ":forbid must not contain empty strings")
      (ok pats)))

fn loadAnswerInt value: Int64 noun: String forbid: (List Int64) -> (Result AnswerIntSpec String)
  (if (stringEmpty? noun)
    (err ":answerInt :noun must be non-empty")
    (if (listContains? forbid value)
      (err ":answerInt :forbid holds its own :value")
      (ok (AnswerIntSpec :value value :noun noun :forbid forbid))))

fn loadFileLineSet pairs: (List FileLinePair) -> (Result (List FileLinePair) String)
  (if (listEmpty? pairs)
    (err ":fileLineSet must be non-empty")
    (if (listAny? (fn [(p FileLinePair)] -> Bool (< p.line 1)) pairs)
      (err ":fileLineSet line below 1")
      (ok pairs)))

fn loadFileLineAlt alts: (List FileLineAltSpec) -> (Result (List FileLineAltSpec) String)
  (if (listEmpty? alts)
    (err ":fileLineAlt must be non-empty")
    (ok alts))

fn loadQuoteExists file: String line: String marker: String -> (Result QuoteExistsSpec String)
  (if (or (stringEmpty? file) (or (stringEmpty? line) (stringEmpty? marker)))
    (err ":quoteExists fields must be non-empty")
    (if (not (stringContains? line marker))
      (err ":quoteExists :line must contain :marker")
      (ok (QuoteExistsSpec :file file :line (stringJoin (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit line " ")) " ") :marker marker))))

fn loadIdSet ids: (List String) done: (List String) -> (Result IdSetSpec String)
  (if (listEmpty? ids)
    (err ":idSet :ids must be non-empty")
    (if (not (listAll? (fn [(d String)] -> Bool (listContains? ids d)) done))
      (err ":idSet :done must be members of :ids")
      (ok (IdSetSpec :ids ids :done done))))

fn loadTrue b: Bool -> (Result Bool String)
  (if b (ok true) (err "expected true"))

fn loadSources paths: (List String) -> (Result (List String) String)
  (if (listEmpty? paths)
    (err ":sources must be non-empty")
    (if (listAny? (fn [(p String)] -> Bool (or (stringEmpty? p) (stringStartsWith? p "/"))) paths)
      (err ":sources must be relative non-empty paths")
      (ok paths)))

fn loadPreserve facts: (List PreserveFact) -> (Result (List PreserveFact) String)
  (if (listEmpty? facts)
    (err ":preserve must be non-empty")
    (ok facts))

fn loadConflicts rows: (List ConflictRow) -> (Result (List ConflictRow) String)
  (if (listEmpty? rows)
    (err ":conflicts must be non-empty")
    (ok rows))

fn loadNoNewFacts b: Bool -> (Result Bool String)
  (if b (ok true) (err ":noNewFacts takes true"))

fn loadMaxRatio r: Float64 -> (Result Float64 String)
  (if (and (> r 0.0) (<= r 1.0))
    (ok r)
    (err ":maxRatio must be in (0, 1]"))

fn ! judgeGate cmd: String caseDir: String work: String -> (List String)
  (let [(expanded (stringReplace cmd "{case}" caseDir))
        (res (processRun (str "cd " work " && " expanded)))]
    (if (!= res.exitCode 0)
      (list (str "gate exit " (stringFromInt64 res.exitCode)))
      (list)))

fn judgeMentions needles: (List (List String)) reply: String -> (List String)
  (let [(replyLower (stringLower reply))]
    (fold (fn [(acc (List String)) (grp (List String))] -> (List String)
            (let [(found (listAny? (fn [(m String)] -> Bool (stringContains? replyLower (stringLower m))) grp))]
              (if found
                acc
                (cons (str "missing mention '" (optionOr (listHead grp) "") "'") acc))))
          (list)
          needles))

fn intTokens text: String -> (List String)
  (let [(spaced (stringReplace (stringReplace (stringReplace (stringReplace text "." " ") "," " ") ":" " ") "\n" " "))]
    (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (stringSplit spaced " ")))

fn nearbyCountNoun tokens: (List String) index: Int64 noun: String -> Bool
  (let [(one (optionOr (listGet tokens (+ index 1)) ""))
        (two (optionOr (listGet tokens (+ index 2)) ""))
        (plural (str noun "s"))]
    (or (= one noun) (or (= one plural) (or (= two noun) (= two plural)))))

fn judgeAnswerInt spec: AnswerIntSpec reply: String -> (List String)
  (let [(tokens (intTokens reply))
        (target (stringFromInt64 spec.value))
        (nounIdx (optionOr (listIndexOf tokens spec.noun) (optionOr (listIndexOf tokens (str spec.noun "s")) -1)))
        (targetIdx (optionOr (listIndexOf tokens target) -1))
        (hasNoun (and (> nounIdx targetIdx) (<= nounIdx (+ targetIdx 2))))
        (hasTarget (>= targetIdx 0))
        (hasForbidden (listAny? (fn [(n Int64)] -> Bool
          (let [(idx (optionOr (listIndexOf tokens (stringFromInt64 n)) -1))]
            (and (>= idx 0) (nearbyCountNoun tokens idx spec.noun))))
          spec.forbid))]
    (if (and hasNoun hasTarget (not hasForbidden))
      (list)
      (list (str "answerInt (want " target ")"))))

fn judgeQuoteExists! spec: QuoteExistsSpec work: String reply: String -> (List String)
  (let [(path (str work "/" spec.file))
        (fileRes (fileReadString path))
        (line spec.line)
        (quoted (stringContains? reply (str "`" line "`")))]
    (mt fileRes
      ((err e) (list (str "quote file unreadable: " e)))
      ((ok contents)
        (if (not (stringContains? contents line))
          (list (str "quote source line missing in " spec.file))
          (if (and quoted (stringContains? line spec.marker))
            (list)
            (list (str "quote missing exact quoted line containing '" spec.marker "'")))))))

fn judgeIdSet spec: IdSetSpec reply: String -> (List String)
  (let [(missing (filter (fn [(d String)] -> Bool (not (stringContains? reply d))) spec.done))]
    (map (fn [(m String)] -> String (str "idSet missing " m)) missing))

fn judgeFileLineAlt alt: (List FileLineAltSpec) want: (List FileLinePair) -> (List String)
  (let [(missing (filter (fn [(a FileLineAltSpec)] -> Bool
                           (not (listAny? (fn [(w FileLinePair)] -> Bool
                                            (and (= a.path w.path)
                                                 (or (= a.line w.line)
                                                     (listContains? a.alts w.line))))
                                          want)))
                         alt))]
    (map (fn [(m FileLineAltSpec)] -> String (str "fileLineAlt has no allowed call line for " m.path)) missing))

fn asnValueText value: asn/AsnValue -> (Option String)
  (mt value
    ((asnString value) (some value))
    ((asnAtom value) (some value))
    ((asnList items) (none)))

fn asnValueInt value: asn/AsnValue -> (Option Int64)
  (mt (asnValueText value)
    ((none) (none))
    ((some text) (stringToInt64 text)))

fn asnFieldItems values: (List asn/AsnValue) name: String -> (List asn/AsnValue)
  (optionOr
    (mt (asnField values name)
      ((none) (none))
      ((some value) (asnTopItems value)))
    (list))

fn asnFieldStrings values: (List asn/AsnValue) name: String -> (List String)
  (map (fn [(value asn/AsnValue)] -> String (optionOr (asnValueText value) ""))
    (asnFieldItems values name))

fn asnValueGroup value: asn/AsnValue -> (List String)
  (mt value
    ((asnList items) (map (fn [(item asn/AsnValue)] -> String (optionOr (asnValueText item) "")) items))
    ((asnString value) (list value))
    ((asnAtom value) (list value)))

fn asnFieldGroups values: (List asn/AsnValue) name: String -> (List (List String))
  (map asnValueGroup (asnFieldItems values name))

fn asnAnswerInt values: (List asn/AsnValue) -> (Option AnswerIntSpec)
  (mt (asnField values ":answerInt")
    ((none) (none))
    ((some value)
      (let [(fields (optionOr (asnTopItems value) (list)))
            (target (optionOr (asnValueInt (optionOr (listGet fields 1) (asnAtom "0"))) 0))
            (noun (optionOr (asnFieldString fields ":noun") ""))
            (forbid (map (fn [(v asn/AsnValue)] -> Int64 (optionOr (asnValueInt v) 0))
                      (filter (fn [(v asn/AsnValue)] -> Bool (some? (asnValueInt v)))
                        (asnFieldItems fields ":forbid"))))]
        (some (AnswerIntSpec :value target :noun noun :forbid forbid)))))

fn asnIdSet values: (List asn/AsnValue) -> (Option IdSetSpec)
  (mt (asnField values ":idSet")
    ((none) (none))
    ((some value)
      (let [(fields (optionOr (asnTopItems value) (list)))]
        (some (IdSetSpec :ids (asnFieldStrings fields ":ids") :done (asnFieldStrings fields ":done"))))))

fn asnAtString items: (List asn/AsnValue) index: Int64 -> (Option String)
  (mt (listGet items index)
    ((none) (none))
    ((some value) (asnValueText value)))

fn asnAtInt items: (List asn/AsnValue) index: Int64 -> (Option Int64)
  (mt (listGet items index)
    ((none) (none))
    ((some value) (asnValueInt value)))

fn asnPair value: asn/AsnValue -> (Option FileLinePair)
  (mt (asnTopItems value)
    ((none) (none))
    ((some items)
      (mt (asnAtString items 0)
        ((none) (none))
        ((some path)
          (mt (asnAtInt items 1)
            ((none) (none))
            ((some line) (some (FileLinePair :path path :line line))))))))

fn asnFileLines values: (List asn/AsnValue) name: String -> (List FileLinePair)
  (map (fn [(row asn/AsnValue)] -> FileLinePair
    (optionOr (asnPair row) (FileLinePair :path "" :line 0)))
    (asnFieldItems values name))

fn asnFileLineAlt values: (List asn/AsnValue) name: String -> (List FileLineAltSpec)
  (map
    (fn [(row asn/AsnValue)] -> FileLineAltSpec
      (let [(parts (optionOr (asnTopItems row) (list)))
            (path (optionOr (asnAtString parts 0) ""))
            (line (optionOr (asnAtInt parts 1) 0))
            (tail (listDrop parts 2))
            (altLines (map (fn [(value asn/AsnValue)] -> Int64 (optionOr (asnValueInt value) 0))
                       (filter (fn [(value asn/AsnValue)] -> Bool (some? (asnValueInt value))) tail)))]
        (FileLineAltSpec :path path :line line :alts altLines)))
    (asnFieldItems values name))

fn asnQuote values: (List asn/AsnValue) -> (Option QuoteExistsSpec)
  (mt (asnField values ":quoteExists")
    ((none) (none))
    ((some value)
      (let [(fields (optionOr (asnTopItems value) (list)))
            (file (optionOr (asnFieldString fields ":file") ""))
            (line (optionOr (asnFieldString fields ":line") ""))
            (marker (optionOr (asnFieldString fields ":marker") ""))]
        (some (QuoteExistsSpec :file file :line line :marker marker)))))

fn asnPreserve values: (List asn/AsnValue) -> (List PreserveFact)
  (map (fn [(row asn/AsnValue)] -> PreserveFact
    (let [(items (optionOr (asnTopItems row) (list)))
          (id (optionOr (asnAtString items 0) ""))
          (facts (listDrop items 1))]
      (PreserveFact :id id :tokens (map (fn [(fact asn/AsnValue)] -> (List String)
        (stringSplit (optionOr (asnValueText fact) "") "|")) facts))))
    (asnFieldItems values ":preserve"))

fn asnConflictSide value: asn/AsnValue -> (Option ConflictSide)
  (mt (asnTopItems value)
    ((none) (none))
    ((some items)
      (mt (asnAtString items 0)
        ((none) (none))
        ((some value)
          (mt (asnAtString items 1)
            ((none) (none))
            ((some sources)
              (some (ConflictSide :values (stringSplit value "|") :sources (stringSplit sources "|")))))))))

fn asnConflict value: asn/AsnValue -> (Option ConflictRow)
  (mt (asnTopItems value)
    ((none) (none))
    ((some items)
      (mt (asnAtString items 0)
        ((none) (none))
        ((some id)
          (some (ConflictRow :id id :sides
            (map (fn [(side asn/AsnValue)] -> ConflictSide
              (optionOr (asnConflictSide side) (ConflictSide :values (list) :sources (list))))
              (listDrop items 1))))))))

fn asnConflicts values: (List asn/AsnValue) -> (List ConflictRow)
  (map (fn [(row asn/AsnValue)] -> ConflictRow
    (optionOr (asnConflict row) (ConflictRow :id "" :sides (list))))
    (asnFieldItems values ":conflicts"))

fn asnRatio values: (List asn/AsnValue) -> (Option Float64)
  (mt (asnField values ":maxRatio")
    ((none) (none))
    ((some value)
      (mt (asnValueText value)
        ((none) (none))
        ((some text) (stringToFloat64 text)))))

fn asnTopItems form: asn/AsnValue -> (Option (List asn/AsnValue))
  (mt form
    ((asnList items) (some items))
    ((asnString value) (none))
    ((asnAtom value) (none)))

fn loadTask! dir: String -> (Result Task String)
  (let [(path (str dir "/task.asn"))
        (parsed (asn/parseFile! path))
        (expectedId (optionOr (listLast (stringSplit dir "/")) dir))]
    (mt parsed
      ((err message) (err (str "task parse failed " path ": " message)))
      ((ok form)
        (mt (asnTopItems form)
          ((none) (err (str "task is not an ASN list: " path)))
          ((some items)
            (let [(fields (optionOr (listTail items) (list)))
                  (id (optionOr (asnFieldString fields ":id") expectedId))
                  (prompt (optionOr (asnFieldString fields ":prompt") ""))
                  (checkFields (asnFieldItems fields ":check"))
                  (modeAtom (optionOr (asnFieldString fields ":mode") (if (or (asnFieldBool checkFields ":readOnly") (stringStartsWith? expectedId "scout")) "scout" "implement")))
                  (mode (if (stringStartsWith? modeAtom ":") (optionOr (stringSlice modeAtom 1 (stringLength modeAtom)) modeAtom) modeAtom))
                  (observe (asnFieldString fields ":observe"))
                  (check (Check :gate (asnFieldString checkFields ":gate")
                                :unchanged (asnFieldStrings checkFields ":unchanged")
                                :readOnly (asnFieldBool checkFields ":readOnly")
                                :mentions (asnFieldGroups checkFields ":mentions")
                                :forbid (asnFieldStrings checkFields ":forbid")
                                :excuse (asnFieldStrings checkFields ":excuse")
                                :answerInt (asnAnswerInt checkFields)
                                :fileLineSet (asnFileLines checkFields ":fileLineSet")
                                :fileLineAlt (asnFileLineAlt checkFields ":fileLineAlt")
                                :quoteExists (asnQuote checkFields)
                                :noFabricatedIdents (asnFieldBool checkFields ":noFabricatedIdents")
                                :idSet (asnIdSet checkFields) :sources (asnFieldStrings checkFields ":sources")
                                :preserve (asnPreserve checkFields) :conflicts (asnConflicts checkFields)
                                :noNewFacts (asnFieldBool checkFields ":noNewFacts") :maxRatio (asnRatio checkFields)))]
              (if (or (!= id expectedId) (stringEmpty? prompt) (listEmpty? checkFields))
                (err (str "invalid task fields in " path))
                (ok (Task :id id :dir dir :prompt prompt :check check :mode mode :observe observe)))))))))
fn loadTasks! casesPath: String -> (Result (List Task) String)
  (mt (dirList casesPath)
    ((err message) (err message))
    ((ok names)
      (fold (fn [(acc (Result (List Task) String)) (name String)] -> (Result (List Task) String)
        (mt acc
          ((err message) (err message))
          ((ok tasks)
            (let [(dir (str casesPath "/" name))
                  (path (str dir "/task.asn"))]
              (if (not (fileExists? path))
                (ok tasks)
                (mt (loadTask! dir)
                  ((err message) (err message))
                  ((ok task) (ok (listAppend tasks (list task))))))))))
        (ok (list)) names)))

fn citationBoundary reply: String token: String -> Bool
  (or (stringEndsWith? reply token)
    (or (stringContains? reply (str token " "))
      (or (stringContains? reply (str token "\n"))
        (or (stringContains? reply (str token ","))
          (or (stringContains? reply (str token ")"))
            (or (stringContains? reply (str token "]"))
              (or (stringContains? reply (str token "}"))
                (or (stringContains? reply (str token ";"))
                  (stringContains? reply (str token "."))))))))))

fn citationForLine path: String line: Int64 reply: String -> Bool
  (let [(number (stringFromInt64 line))]
    (or (citationBoundary reply (str path ":" number))
      (or (citationBoundary reply (str path ": " number))
        (citationBoundary reply (str path " " number)))))

fn expectedCitationMatches pair: FileLinePair alt: (List FileLineAltSpec) reply: String -> Bool
  (let [(matches (filter (fn [(candidate FileLineAltSpec)] -> Bool (= candidate.path pair.path)) alt))
        (allowed (fold (fn [(acc (List Int64)) (candidate FileLineAltSpec)] -> (List Int64)
                   (listAppend acc (listAppend (list candidate.line) candidate.alts)))
                 (list pair.line) matches))]
    (listAny? (fn [(line Int64)] -> Bool (citationForLine pair.path line reply)) allowed))

fn judgeFileLineReply pairs: (List FileLinePair) alt: (List FileLineAltSpec) reply: String -> (List String)
  (map (fn [(pair FileLinePair)] -> String (str "missing citation " pair.path ":" (stringFromInt64 pair.line)))
    (filter (fn [(pair FileLinePair)] -> Bool (not (expectedCitationMatches pair alt reply))) pairs))

fn ! judgeTask task: Task work: String reply: String -> (List String)
  (let [(check task.check)
        (gateFails (mt check.gate ((none) (list)) ((some cmd) (judgeGate cmd task.dir work))))
        (mentionFails (judgeMentions check.mentions reply))
        (intFails (mt check.answerInt ((none) (list)) ((some spec) (judgeAnswerInt spec reply))))
        (quoteFails (mt check.quoteExists ((none) (list)) ((some spec) (judgeQuoteExists! spec work reply))))
        (idFails (mt check.idSet ((none) (list)) ((some spec) (judgeIdSet spec reply))))
        (altFails (judgeFileLineAlt check.fileLineAlt check.fileLineSet))
        (citationFails (judgeFileLineReply check.fileLineSet check.fileLineAlt reply))]
    (listAppend gateFails
      (listAppend mentionFails
        (listAppend intFails (listAppend quoteFails (listAppend idFails (listAppend altFails citationFails)))))))

fn ! verdict caseId: String work: String reply: String -> (List String)
  (mt (loadTask! (str (casesDir) "/" caseId))
    ((err message) (list (str "unknown case " caseId)))
    ((ok task) (judgeTask task work reply)))

fn ! scoreLedgerLine tasks: (List Task) line: String -> (Option (List String))
  (mt (asn/parse line)
    ((err message) (none))
    ((ok form)
      (mt (asnTopItems form)
        ((none) (none))
        ((some items)
          (let [(fields (optionOr (listTail items) (list)))
                (caseName (optionOr (asnFieldString fields ":case") ""))
                (client (optionOr (asnFieldString fields ":client") ""))
                (condition (optionOr (asnFieldString fields ":condition") ""))
                (replyId (optionOr (asnFieldString fields ":replyId") ""))
                (taskOpt (listHead (filter (fn [(task Task)] -> Bool (= task.id caseName)) tasks)))
                (replyPath (str (replyDir!) "/" replyId ".txt"))]
            (mt taskOpt
              ((none) (none))
              ((some task)
                (if (or (stringEmpty? client) (stringEmpty? condition) (stringEmpty? replyId) (not (fileExists? replyPath)))
                  (none)
                  (let [(reply (resultOr (fileReadString replyPath) ""))
                        (why (judgeTask task task.dir reply))
                        (pass (listEmpty? why))]
                    (some (list caseName client condition replyId (formatAsnBool pass) (stringJoin why "; "))))))))))))

fn rescoreKey row: (List String) -> String
  (str (optionOr (listGet row 0) "") "\t" (optionOr (listGet row 1) "") "\t" (optionOr (listGet row 2) ""))

fn updateRescoreSum sums: (Map String RescoreSum) row: (List String) -> (Map String RescoreSum)
  (let [(caseName (optionOr (listGet row 0) ""))
        (client (optionOr (listGet row 1) ""))
        (condition (optionOr (listGet row 2) ""))
        (pass (= (optionOr (listGet row 4) "false") "true"))
        (key (rescoreKey row))
        (old (optionOr (mapGet sums key) (RescoreSum :caseName caseName :client client :condition condition :passCount 0 :runCount 0)))
        (next (RescoreSum :caseName caseName :client client :condition condition
                          :passCount (+ old.passCount (if pass 1 0))
                          :runCount (+ old.runCount 1)))]
    (mapSet sums key next))

fn scoreLedgerLines! tasks: (List Task) lines: (List String) -> (List (List String))
  (fold (fn [(acc (List (List String))) (line String)] -> (List (List String))
          (mt (scoreLedgerLine tasks line)
            ((none) acc)
            ((some row) (listAppend acc (list row)))))
    (list) lines)

fn ! printRescoreRuns rows: (List (List String)) -> Unit
  (fold (fn [(acc Unit) (row (List String))] -> Unit
          (do (println (formatRescoreLine
            (optionOr (listGet row 0) "")
            (optionOr (listGet row 1) "")
            (optionOr (listGet row 2) "")
            (optionOr (listGet row 3) "")
            (= (optionOr (listGet row 4) "false") "true")
            (optionOr (listGet row 5) ""))) acc))
    () rows)

fn ! printRescoreSums sums: (Map String RescoreSum) -> Unit
  (fold (fn [(acc Unit) (sum RescoreSum)] -> Unit
          (do (println (formatRescoreSumLine sum.caseName sum.client sum.condition sum.passCount sum.runCount)) acc))
    () (mapValues sums))

fn ! rescore ledger: String -> (Result Int64 String)
  (mt (fileReadString ledger)
    ((err message) (err message))
    ((ok contents)
      (mt (loadTasks! (casesDir))
        ((err message) (err message))
        ((ok tasks)
          (let [(runs (scoreLedgerLines! tasks (stringLines contents)))
                (sums (fold updateRescoreSum (mapEmpty) runs))]
            (do
              (printRescoreRuns runs)
              (printRescoreSums sums)
              (ok (if (listEmpty? runs) 1 0))))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(hasRescore (listContains? args "--rescore"))
        (ledgerArg (fold (fn [(acc String) (p (Pair String String))] -> String
                           (if (= (pairFirst p) "--ledger") (pairSecond p) acc))
                         (defaultLedger)
                         (zip args (optionOr (listTail args) (list)))))]
    (if hasRescore
      (rescore ledgerArg)
      (do
        (println "usage: bench.asl --rescore [--ledger <path>]")
        (ok 2))))
