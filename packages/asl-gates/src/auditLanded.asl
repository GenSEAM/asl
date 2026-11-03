(module asl-gates/auditLanded
  :x [Commit rowFieldsAny rowText rowItems evIds evIdsLoose stripStrings fromShas exemptKind gradeRows headSince gradeRow GradeRow isoOfMs parseLog landedChecks ledgerPath cmdLanded!]
  :i [(asl-gates/auditGates :a ag) (asl-syntax/asl/asn :a asn)])

; (:m :ref LANDED-AUDIT :do "main commits must be graded: the tracked ledger .asl/mem/grades.asn holds one (:grade :ev ID :sha SHA :verdict pass|fixNeeded :by FAMILY :at ISO) row per verdict, the newest row of an ev id wins, and a head row (:gradesHead :since SHA) is the checkpoint older history is not audited from; audit landed [--since REF] lists the commits in REF..HEAD that are neither exempt nor carry an :ev id whose newest verdict is pass, exit 1 on any. Exempt: a merge commit (more than one parent), a wip rescue commit (message head (:c :a wip :do), and a commit touching only the ledger (the verdict itself)")
(schema Commit
  (:f sha String)
  (:f parents Int64)
  (:f msg String)
  (:f files (List String)))

(schema GradeRow
  (:f ev String)
  (:f sha String)
  (:f verdict String)
  (:f base String))

fn ledgerPath -> String
  ".asl/mem/grades.asn"

fn wordAt s: String -> String
  (let [(t (stringTrim s))
        (w (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit t " ")) "") ")")) ""))]
    (stringReplace w "\"" ""))

; (:m :ref LANDED-AUDIT :do "the fields of the first form of a text whatever its tag, an error when the text is not one ASN form")
fn rowFieldsAny raw: String -> (Result (List asn/AsnField) String)
  (match (asn/asnRead (stringTrim raw))
    ((err e) (err e))
    ((ok (asn/asnTagged _ fields _)) (ok fields))
    ((ok _) (err "not a tagged form")))

fn symOrString v: asn/AsnValue -> String
  (match v
    ((asn/asnSym name) name)
    (_ (optionOr (asn/asnStringValue v) "")))

fn fieldOf fields: (List asn/AsnField) key: String -> (Option asn/AsnValue)
  (match (listFind (fn [(f asn/AsnField)] -> Bool (= f.key (str ":" key))) fields)
    ((some f) (some f.val))
    ((none) (none)))

fn itemsOfValue v: asn/AsnValue -> (List String)
  (let [(vals (match v
                ((asn/asnUnit) (list))
                ((asn/asnTuple items) items)
                ((asn/asnVec items) items)
                ((asn/asnPair a b) (list a b))
                ((asn/asnTagged t _ kids) (cons (asn/asnSym t) kids))
                ((asn/asnCase name args) (cons (asn/asnSym name) args))
                ((asn/asnCtor name fs) (cons (asn/asnSym name) (map (fn [(f asn/AsnField)] -> asn/AsnValue f.val) fs)))
                (_ (list v))))]
    (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (map symOrString vals)))

; (:m :ref LANDED-AUDIT :do "rowText reads one key of a one-form text as text, empty when the text is not a form or lacks the key; rowItems reads it as a list of words")
fn rowText raw: String key: String -> String
  (match (rowFieldsAny raw)
    ((err _) "")
    ((ok fs) (match (fieldOf fs key) ((some v) (symOrString v)) ((none) ""))))

fn rowItems raw: String key: String -> (List String)
  (match (rowFieldsAny raw)
    ((err _) (list))
    ((ok fs) (match (fieldOf fs key) ((some v) (itemsOfValue v)) ((none) (list)))))

; (:m :ref LANDED-AUDIT :do "string literals dropped from a line (backslash escapes honoured), so a scan for :ev never reads one inside a string")
fn stripStrings s: String -> String
  (pairFirst (fold (fn [(st (Pair String (Pair Bool Bool))) (ch String)] -> (Pair String (Pair Bool Bool))
                     (let [(out (pairFirst st))
                           (inStr (pairFirst (pairSecond st)))
                           (esc (pairSecond (pairSecond st)))]
                       (cond
                         ((and inStr esc) (pair out (pair true false)))
                         ((and inStr (= ch "\\")) (pair out (pair true true)))
                         ((and inStr (= ch "\"")) (pair (str out " ") (pair false false)))
                         (inStr st)
                         ((= ch "\"") (pair out (pair true false)))
                         (else (pair (str out ch) (pair false false))))))
                   (pair "" (pair false false)) (stringChars s)))

; (:m :ref LANDED-AUDIT :do "the tolerant reader of :ev for a first line the ASN reader refuses (a symbol such as W1b-FIX, mixed case with a hyphen, is refused as a whole form): the line without its strings, the words after the first ' :ev ' as a list in parentheses, or one bare word")
fn evIdsLoose line: String -> (List String)
  (let [(parts (stringSplit (stripStrings line) " :ev "))]
    (if (<= (listLength parts) 1) (list)
      (let [(after (stringTrim (optionOr (listGet parts 1) "")))
            (open (stringStartsWith? after "("))
            (inner (if open (optionOr (listHead (stringSplit (optionOr (stringSlice after 1 (stringLength after)) "") ")")) "") ""))]
        (if open
          (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (map wordAt (stringSplit inner " ")))
          (let [(w (wordAt after))] (if (stringEmpty? w) (list) (list w)))))))

; (:m :ref LANDED-AUDIT :do "evIds parses the commit message's first line as one ASN form and reads its :ev (a list, a string or a symbol), so an :ev inside a string never counts; a line the ASN reader refuses falls back to the string-stripped scan of evIdsLoose")
fn evIds msg: String -> (List String)
  (let [(line (optionOr (listHead (stringLines msg)) ""))]
    (match (rowFieldsAny line)
      ((err _) (evIdsLoose line))
      ((ok _) (rowItems line "ev"))))

; (:m :ref LANDED-AUDIT :do "fromShas reads the sources of a cherry-pick -x message: every '(cherry picked from commit SHA)' line")
fn fromShas msg: String -> (List String)
  (fold (fn [(acc (List String)) (line String)] -> (List String)
          (let [(parts (stringSplit line "(cherry picked from commit "))]
            (if (<= (listLength parts) 1) acc
              (listAppend acc (list (stringReplace (stringTrim (optionOr (listGet parts 1) "")) ")" ""))))))
        (list) (stringLines msg))

; (:m :ref LANDED-AUDIT :do "the ledger rows in file order; base is the row's :base (the merge-base with main at grade time) or empty for an old row; a row whose form does not parse is dropped")
fn gradeRows text: String -> (List GradeRow)
  (fold (fn [(acc (List GradeRow)) (line String)] -> (List GradeRow)
          (if (stringStartsWith? line "(:grade ")
            (let [(ev (rowText line "ev"))
                  (sha (rowText line "sha"))
                  (v (rowText line "verdict"))]
              (if (or (stringEmpty? ev) (or (stringEmpty? sha) (stringEmpty? v))) acc (listAppend acc (list (GradeRow :ev ev :sha sha :verdict v :base (rowText line "base"))))))
            acc))
        (list) (stringLines text))

fn headSince text: String -> String
  (match (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gradesHead ")) (stringLines text)))
    ((some l) (rowText l "since"))
    ((none) ""))

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn two n: Int64 -> String
  (if (< n 10) (str "0" (stringFromInt64 n)) (stringFromInt64 n))

; (:m :ref LANDED-AUDIT :do "UTC date and time of an epoch in milliseconds as YYYY-MM-DDTHH:MM:SSZ (days to civil date by the proleptic Gregorian rule)")
fn isoOfMs ms: Int64 -> String
  (let [(secs (/ ms 1000))
        (days (/ secs 86400))
        (rem (- secs (* days 86400)))
        (z (+ days 719468))
        (era (/ z 146097))
        (doe (- z (* era 146097)))
        (yoe (/ (+ (- doe (/ doe 1460)) (- (/ doe 36524) (/ doe 146096))) 365))
        (doy (- doe (- (+ (* 365 yoe) (/ yoe 4)) (/ yoe 100))))
        (mp (/ (+ (* 5 doy) 2) 153))
        (d (+ (- doy (/ (+ (* 153 mp) 2) 5)) 1))
        (m (if (< mp 10) (+ mp 3) (- mp 9)))
        (y (+ (+ yoe (* era 400)) (if (<= m 2) 1 0)))]
    (str (stringFromInt64 y) "-" (two m) "-" (two d) "T" (two (/ rem 3600)) ":" (two (/ (- rem (* (/ rem 3600) 3600)) 60)) ":" (two (- rem (* (/ rem 60) 60))) "Z"))

; (:m :ref LANDED-AUDIT :do "one ledger row; base is the merge-base of the reviewed head with main, empty when unknown; verdict is pass or fixNeeded, by the family of the grader")
fn gradeRow ev: String sha: String base: String verdict: String by: String at: String -> String
  (str "(:grade :ev " (quoted ev) " :sha " (quoted sha) (if (stringEmpty? base) "" (str " :base " (quoted base))) " :verdict " verdict " :by " (quoted by) " :at " (quoted at) ")")

fn wip? msg: String -> Bool
  (stringStartsWith? msg "(:c :a wip :do")

; (:m :ref LANDED-AUDIT :do "why a commit is not audited: merge or ledger; empty when it is audited. A wip rescue commit is not exempt: it belongs on a unit branch, and one on main is a finding")
fn exemptKind c: Commit -> String
  (cond
    ((> c.parents 1) "merge")
    ((and (not (listEmpty? c.files)) (listAll? (fn [(f String)] -> Bool (= f (ledgerPath))) c.files)) "ledger")
    (else ""))

; (:m :ref LANDED-AUDIT :do "a commit is graded when, for one of its :ev ids, the newest ledger row whose :sha covers it is a pass; covers is (candidate sha, row sha, row base) -> the row's reviewed head is that commit or a descendant of it and, when the row has a :base, the commit is not an ancestor of that base (it lies on the reviewed branch since it left main); the candidates are the commit and the sources a cherry-pick -x names, so a later commit reusing an old passed id is not covered")
fn graded? c: Commit rows: (List GradeRow) covers: (fn [String String String] -> Bool) -> Bool
  (let [(cands (cons c.sha (fromShas c.msg)))]
    (listAny? (fn [(id String)] -> Bool
                (let [(mine (filter (fn [(r GradeRow)] -> Bool
                                      (and (= r.ev id) (listAny? (fn [(cand String)] -> Bool (covers cand r.sha r.base)) cands)))
                                    rows))]
                  (match (listLast mine)
                    ((some r) (= r.verdict "pass"))
                    ((none) false))))
              (evIds c.msg)))

fn short sha: String -> String
  (optionOr (stringSlice sha 0 9) sha)

fn subjectOf msg: String -> String
  (let [(l (optionOr (listHead (stringLines msg)) ""))]
    (optionOr (stringSlice l 0 (if (< (stringLength l) 100) (stringLength l) 100)) l))

; (:m :ref LANDED-AUDIT :do "one failed check per audited commit that is a wip rescue commit (ERR_WIP_ON_MAIN) or has no covering pass row (ERR_UNGRADED, or ERR_NO_EV without any :ev), oldest first; none failing is one passed check counting the audited commits")
fn landedChecks commits: (List Commit) ledger: String covers: (fn [String String String] -> Bool) -> (List ag/Check)
  (let [(rows (gradeRows ledger))
        (audited (filter (fn [(c Commit)] -> Bool (stringEmpty? (exemptKind c))) commits))
        (bad (filter (fn [(c Commit)] -> Bool (or (wip? c.msg) (not (graded? c rows covers)))) audited))]
    (if (listEmpty? bad)
      (list (ag/passCheck "landed" (some (listLength audited)) (none)))
      (map (fn [(c Commit)] -> ag/Check
             (ag/failCheck (str "ungraded-" (short c.sha)) (cond ((wip? c.msg) "ERR_WIP_ON_MAIN") ((listEmpty? (evIds c.msg)) "ERR_NO_EV") (else "ERR_UNGRADED")) (subjectOf c.msg) (none) (none)))
           bad)))

; (:m :ref LANDED-AUDIT :do "parseLog reads git log --name-only --format=@@C@@%H@@%P@@%B@@F@@ output: one record per commit; git prints newest first, the result is oldest first")
fn parseLog out: String -> (List Commit)
  (fold (fn [(acc (List Commit)) (rec String)] -> (List Commit)
          (let [(halves (stringSplit rec "@@F@@"))
                (meta (stringSplit (optionOr (listHead halves) "") "@@"))
                (sha (stringTrim (optionOr (listGet meta 0) "")))
                (parents (listLength (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim (optionOr (listGet meta 1) "")) " "))))
                (msg (stringTrim (stringJoin (optionOr (listTail (optionOr (listTail meta) (list))) (list)) "@@")))
                (files (filter (fn [(f String)] -> Bool (not (stringEmpty? f))) (map stringTrim (stringLines (optionOr (listGet halves 1) "")))))]
            (if (stringEmpty? sha) acc (cons (Commit :sha sha :parents parents :msg msg :files files) acc))))
        (list) (stringSplit out "@@C@@"))

fn flagOf argv: (List String) key: String -> String
  (match (listHead argv)
    ((none) "")
    ((some a) (let [(rest (optionOr (listTail argv) (list)))]
                (if (= a key) (optionOr (listHead rest) "") (flagOf rest key)))))

; (:m :ref LANDED-AUDIT :do "audit landed [--since REF]: REF defaults to the :since of the ledger head row; without either the audit fails, it never guesses a checkpoint")
fn cmdLanded! root: String argv: (List String) -> ag/AuditRun
  (let [(ledger (optionOr (ag/readText! (str root "/" (ledgerPath))) ""))
        (given (flagOf argv "--since"))
        (since (if (stringEmpty? given) (headSince ledger) given))]
    (if (stringEmpty? since)
      (ag/emit "landed" (list (ag/failCheck "checkpoint" "ERR_NO_CHECKPOINT" "no --since and no (:gradesHead :since SHA) row in .asl/mem/grades.asn" (none) (none))) "" "" false)
      (match (ag/git! root (list "log" "--name-only" "--format=@@C@@%H@@%P@@%B@@F@@" (str since "..HEAD")))
        ((err e) (ag/emit "landed" (list (ag/failCheck "log" "ERR_GIT_LOG" e (none) (none))) "" "" false))
        ((ok out) (ag/emit "landed" (landedChecks (parseLog out) ledger (fn [(cand String) (rowSha String) (rowBase String)] -> Bool (and (ag/gitOk! root (list "merge-base" "--is-ancestor" cand rowSha)) (or (stringEmpty? rowBase) (not (ag/gitOk! root (list "merge-base" "--is-ancestor" cand rowBase))))))) (str ":since " (quoted since)) "" false)))))
