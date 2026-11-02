(module asl-gates/auditLanded
  :x [Commit evIds exemptKind gradeVerdicts headSince gradeRow isoOfMs parseLog landedChecks ledgerPath cmdLanded!]
  :i [(asl-gates/auditGates :a ag)])

; (:m :ref LANDED-AUDIT :do "main commits must be graded: the tracked ledger .asl/mem/grades.asn holds one (:grade :ev ID :sha SHA :verdict pass|fixNeeded :by FAMILY :at ISO) row per verdict, the newest row of an ev id wins, and a head row (:gradesHead :since SHA) is the checkpoint older history is not audited from; audit landed [--since REF] lists the commits in REF..HEAD that are neither exempt nor carry an :ev id whose newest verdict is pass, exit 1 on any. Exempt: a merge commit (more than one parent), a wip rescue commit (message head (:c :a wip :do), and a commit touching only the ledger (the verdict itself)")
(schema Commit
  (:f sha String)
  (:f parents Int64)
  (:f msg String)
  (:f files (List String)))

fn ledgerPath -> String
  ".asl/mem/grades.asn"

fn wordAt s: String -> String
  (let [(t (stringTrim s))
        (w (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit t " ")) "") ")")) ""))]
    (stringReplace w "\"" ""))

; (:m :ref LANDED-AUDIT :do "evIds reads the ids after the first :ev of a commit message: a parenthesised list, a quoted string or one bare word; quotes are dropped")
fn evIds msg: String -> (List String)
  (let [(parts (stringSplit msg " :ev "))]
    (if (<= (listLength parts) 1) (list)
      (let [(after (stringTrim (optionOr (listGet parts 1) "")))
            (open (stringStartsWith? after "("))
            (inner (if open (optionOr (listHead (stringSplit (optionOr (stringSlice after 1 (stringLength after)) "") ")")) "") ""))]
        (if open
          (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (map wordAt (stringSplit inner " ")))
          (let [(w (wordAt after))] (if (stringEmpty? w) (list) (list w)))))))

fn keyVal line: String key: String -> String
  (let [(parts (stringSplit line (str " " key " ")))]
    (if (<= (listLength parts) 1) "" (wordAt (optionOr (listGet parts 1) ""))))

; (:m :ref LANDED-AUDIT :do "newest verdict per ev id from the ledger text, later rows replace earlier ones")
fn gradeVerdicts text: String -> (List (Pair String String))
  (fold (fn [(acc (List (Pair String String))) (line String)] -> (List (Pair String String))
          (if (stringStartsWith? line "(:grade ")
            (let [(ev (keyVal line ":ev"))
                  (v (keyVal line ":verdict"))]
              (if (or (stringEmpty? ev) (stringEmpty? v)) acc
                (listAppend (filter (fn [(p (Pair String String))] -> Bool (!= (pairFirst p) ev)) acc) (list (pair ev v)))))
            acc))
        (list) (stringLines text))

fn headSince text: String -> String
  (match (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:gradesHead ")) (stringLines text)))
    ((some l) (keyVal l ":since"))
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

; (:m :ref LANDED-AUDIT :do "one ledger row; verdict is pass or fixNeeded, by the family of the grader")
fn gradeRow ev: String sha: String verdict: String by: String at: String -> String
  (str "(:grade :ev " (quoted ev) " :sha " (quoted sha) " :verdict " verdict " :by " (quoted by) " :at " (quoted at) ")")

fn wip? msg: String -> Bool
  (stringStartsWith? msg "(:c :a wip :do")

; (:m :ref LANDED-AUDIT :do "why a commit is not audited: merge, wip or ledger; empty when it is")
fn exemptKind c: Commit -> String
  (cond
    ((> c.parents 1) "merge")
    ((wip? c.msg) "wip")
    ((and (not (listEmpty? c.files)) (listAll? (fn [(f String)] -> Bool (= f (ledgerPath))) c.files)) "ledger")
    (else ""))

fn graded? c: Commit verdicts: (List (Pair String String)) -> Bool
  (listAny? (fn [(id String)] -> Bool
              (match (listFind (fn [(p (Pair String String))] -> Bool (= (pairFirst p) id)) verdicts)
                ((some p) (= (pairSecond p) "pass"))
                ((none) false)))
            (evIds c.msg))

fn short sha: String -> String
  (optionOr (stringSlice sha 0 9) sha)

fn subjectOf msg: String -> String
  (let [(l (optionOr (listHead (stringLines msg)) ""))]
    (optionOr (stringSlice l 0 (if (< (stringLength l) 100) (stringLength l) 100)) l))

; (:m :ref LANDED-AUDIT :do "one failed check per commit that is not exempt and has no :ev id whose newest verdict is pass, oldest first; none failing is one passed check counting the audited commits")
fn landedChecks commits: (List Commit) ledger: String -> (List ag/Check)
  (let [(verdicts (gradeVerdicts ledger))
        (audited (filter (fn [(c Commit)] -> Bool (stringEmpty? (exemptKind c))) commits))
        (bad (filter (fn [(c Commit)] -> Bool (not (graded? c verdicts))) audited))]
    (if (listEmpty? bad)
      (list (ag/passCheck "landed" (some (listLength audited)) (none)))
      (map (fn [(c Commit)] -> ag/Check
             (ag/failCheck (str "ungraded-" (short c.sha)) (if (listEmpty? (evIds c.msg)) "ERR_NO_EV" "ERR_UNGRADED") (subjectOf c.msg) (none) (none)))
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
        ((ok out) (ag/emit "landed" (landedChecks (parseLog out) ledger) (str ":since " (quoted since)) "" false)))))
