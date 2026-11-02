(module asl-cli/release
  :x [Pin releaseRow releaseAmong valueAfter quotedAfter tagOfPath tagCmp pinOf pinProblem releaseTag! versionLine! pinCheck!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl-parser/reader :a rd)])

; (:m :ref INBOX-RELEASE-PIN :do "which release is running: a release is a checkout under <home>/.asl/releases/<tag> whose bin/asl runs with ASL_CLI_ROOT set to it; its tag is read from <root>/.release/version.asn (:release :tag T :commit C) when a release build wrote one, else from the directory name under releases/, else the checkout's exact git tag; --version prints the banner, then release and commit, and the pin status when the workspace pins")
fn quotedAfter text: String key: String -> String
  (match (listGet (stringSplit text (str key " \"")) 1)
    ((none) "")
    ((some r) (optionOr (listHead (stringSplit r "\"")) "")))

fn tagOfPath root: String -> String
  (let [(parts (stringSplit root "/"))
        (n (listLength parts))
        (last (optionOr (listGet parts (- n 1)) ""))
        (parent (optionOr (listGet parts (- n 2)) ""))]
    (if (and (= parent "releases") (stringStartsWith? last "v")) last ""))

fn singleQuote s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! gitOut root: String argv: String -> String
  (let [(res (processRun (str "git -C " (singleQuote root) " " argv " 2>/dev/null")))]
    (if (= res.exitCode 0) (stringTrim res.stdout) ""))

fn ! stampText root: String -> String
  (resultOr (fileReadString (str root "/.release/version.asn")) "")

; (:m :ref INBOX-RELEASE-PIN :do "the tag of the running release without spawning anything: the stamp, then the directory name; empty for a plain checkout")
fn ! releaseTag! root: String -> String
  (let [(stamped (quotedAfter (stampText root) ":tag"))]
    (if (stringEmpty? stamped) (tagOfPath root) stamped))

(schema Pin
  (:f pin String)
  (:f min String)
  (:f mode String)
  (:f file String))

; (:m :ref INBOX-RELEASE-PIN :do "the workspace setting is (:release :pin \"0.0.2\" :min \"0.0.1\" :mode warn|refuse, the mode with or without a leading colon, tags with or without a leading v) anywhere in .asl.config.asn; :pin wants exactly that version, :min that version or a later one; the default mode is warn")
fn commentFree text: String -> String
  (stringJoin (filter (fn [(l String)] -> Bool (not (stringStartsWith? (stringTrim l) ";"))) (stringSplit text "\n")) "\n")

fn unquote s: String -> String
  (if (and (stringStartsWith? s "\"") (>= (stringLength s) 2)) (optionOr (stringSlice s 1 (- (stringLength s) 1)) "") s)

; (:m :ref INBOX-RELEASE-PIN :do "the items of the list that follows the atom :release as a key, found by the ASN reader anywhere in the text, so a :release inside a string or as a value (:level :release, not followed by a list) is not a pin row")
fn releaseAmong items: (List rd/SExpr) -> (Option (List rd/SExpr))
  (match (listHead items)
    ((none) (none))
    ((some h)
      (let [(rest (optionOr (listTail items) (list)))
            (next (optionOr (listHead rest) (rd/makeAtom "")))]
        (if (and (rd/isAtom? h) (and (= (rd/sexprHead h) ":release") (rd/isList? next)))
          (some (rd/sexprToList next))
          (match (releaseRow h)
            ((some r) (some r))
            ((none) (releaseAmong rest)))))))

fn releaseRow form: rd/SExpr -> (Option (List rd/SExpr))
  (if (or (rd/isList? form) (rd/isVect? form))
    (releaseAmong (rd/sexprToList form))
    (none))

fn valueAfter items: (List rd/SExpr) key: String -> String
  (match (listHead items)
    ((none) "")
    ((some h)
      (let [(rest (optionOr (listTail items) (list)))]
        (if (and (rd/isAtom? h) (= (rd/sexprHead h) key))
          (match (listHead rest) ((some v) (if (rd/isAtom? v) (unquote (rd/sexprHead v)) "")) ((none) ""))
          (valueAfter rest key)))))

fn pinOf text: String file: String -> (Option Pin)
  (match (releaseRow (rd/parseSexpr (str "(" (commentFree text) "\n)")))
    ((none) (none))
    ((some items)
      (let [(mode (valueAfter items ":mode"))]
        (some (Pin :pin (valueAfter items ":pin") :min (valueAfter items ":min") :mode (if (or (= mode "refuse") (= mode ":refuse")) "refuse" "warn") :file file)))))

fn dropV tag: String -> String
  (if (stringStartsWith? tag "v") (optionOr (stringSlice tag 1 (stringLength tag)) "") tag)

fn numsOf tag: String -> (List Int64)
  (map (fn [(w String)] -> Int64 (optionOr (stringToInt64 w) 0)) (stringSplit (stringReplace (dropV tag) "-" ".") "."))

fn cmpNums a: (List Int64) b: (List Int64) -> Int64
  (cond
    ((and (listEmpty? a) (listEmpty? b)) 0)
    (else
      (let [(x (optionOr (listHead a) 0))
            (y (optionOr (listHead b) 0))]
        (cond
          ((< x y) -1)
          ((> x y) 1)
          (else (cmpNums (optionOr (listTail a) (list)) (optionOr (listTail b) (list))))))))

; (:m :ref INBOX-RELEASE-PIN :do "tags compare numerically part by part after dropping the v: v0.0.2-1 (numeric suffix) is later than v0.0.2, a letter suffix (v0.0.2-rc1) is a pre-release and earlier than v0.0.2, v0.0.10 is later than v0.0.9; -1, 0 or 1")
fn suffixRank suffix: String -> Int64
  (cond
    ((stringEmpty? suffix) 0)
    ((some? (stringToInt64 (optionOr (stringSlice suffix 0 1) ""))) 1)
    (else -1))

fn cmpSuffix a: String b: String -> Int64
  (let [(ra (suffixRank a)) (rb (suffixRank b))]
    (cond
      ((< ra rb) -1)
      ((> ra rb) 1)
      ((= ra 1) (cmpNums (numsOf a) (numsOf b)))
      ((= a b) 0)
      ((= ra -1) (if (< a b) -1 1))
      (else 0)))

fn tagCmp a: String b: String -> Int64
  (let [(ba (optionOr (listHead (stringSplit (dropV a) "-")) ""))
        (bb (optionOr (listHead (stringSplit (dropV b) "-")) ""))
        (sa (optionOr (stringSlice (dropV a) (min (stringLength (dropV a)) (+ (stringLength ba) 1)) (stringLength (dropV a))) ""))
        (sb (optionOr (stringSlice (dropV b) (min (stringLength (dropV b)) (+ (stringLength bb) 1)) (stringLength (dropV b))) ""))
        (c (cmpNums (numsOf ba) (numsOf bb)))]
    (if (!= c 0) c (cmpSuffix sa sb)))

; (:m :ref INBOX-RELEASE-PIN :do "empty when the running tag satisfies the pin, else one sentence naming both tags; an unknown running tag satisfies nothing it cannot be compared with, so it is not a mismatch")
fn pinProblem p: Pin running: String -> String
  (cond
    ((stringEmpty? running) "")
    ((and (not (stringEmpty? p.pin)) (!= (tagCmp running p.pin) 0)) (str "this workspace pins release " p.pin " in " p.file " but release " running " is running"))
    ((and (not (stringEmpty? p.min)) (< (tagCmp running p.min) 0)) (str "this workspace needs release " p.min " or later in " p.file " but release " running " is running"))
    (else ""))

fn ! configIn! dir: String -> (Option Pin)
  (let [(cfg (str dir "/.asl.config.asn"))]
    (cond
      ((fileExists? cfg) (pinOf (resultOr (fileReadString cfg) "") cfg))
      ((or (stringEmpty? dir) (= dir "/")) (none))
      (else (configIn! (sys/parentOf dir)))))

; (:m :ref INBOX-RELEASE-PIN :do "the banner line, then release <tag> <commit> (the commit from the stamp, else git; dev when there is no tag), then a (:release ...) line with the pin status when the workspace pins; the banner stays the first line")
fn ! versionLine! root: String cwd: String -> String
  (let [(stamp (stampText root))
        (tag0 (releaseTag! root))
        (tag (if (stringEmpty? tag0) (gitOut root "describe --tags --exact-match HEAD") tag0))
        (commit0 (quotedAfter stamp ":commit"))
        (commit (if (stringEmpty? commit0) (gitOut root "rev-parse --short=12 HEAD") commit0))
        (line (str "asl 0.1.0 (bin/asl) release " (if (stringEmpty? tag) "dev" tag) (if (stringEmpty? commit) "" (str " " commit))))]
    (match (configIn! cwd)
      ((none) line)
      ((some p)
        (let [(problem (pinProblem p (if (stringEmpty? tag) "" tag)))]
          (str line "\n(:release :pin " (if (stringEmpty? p.pin) "none" (str "\"" p.pin "\"")) " :min " (if (stringEmpty? p.min) "none" (str "\"" p.min "\"")) " :running " (if (stringEmpty? tag) "unknown" (str "\"" tag "\"")) " :status " (if (stringEmpty? problem) ":ok" ":mismatch") " :mode " p.mode ")")))))

; (:m :ref INBOX-RELEASE-PIN :do "before every command except --version: a pin mismatch writes one (:asl :status :warning :error ERR_RELEASE_PIN ...) line to stderr; with :mode refuse it returns true and the command does not run")
fn ! pinCheck! root: String cwd: String -> Bool
  (match (configIn! cwd)
    ((none) false)
    ((some p)
      (let [(problem (pinProblem p (releaseTag! root)))]
        (if (stringEmpty? problem)
          false
          (do (sys/sayErr! (str "(:asl :status " (if (= p.mode "refuse") ":failed" ":warning") " :error ERR_RELEASE_PIN :pin \"" p.pin "\" :min \"" p.min "\" :running \"" (releaseTag! root) "\" :mode " p.mode " :message \"" problem "\")"))
              (= p.mode "refuse"))))))
