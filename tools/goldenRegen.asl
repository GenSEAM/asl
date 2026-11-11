(module asl-tools/goldenRegen
  :x [Target PathChange onlyIn significant pathOfLine pathCounts digitsPrefix numberAfter closureFiles git! pinOf! pinOfText! commitsIn! changesOf! untraced? checkerTarget! irTargets! corpusTarget! main]
  :i [(asl-tools/fleet/run :a fr)
      (asl-tools/fleet/model :a fm)
      (asl/packages/asl-checker/tests/quadGoldenTest :a cq)
      (asl/packages/asl-ir/tests/quadGoldenTest :a iq)
      (asl/packages/asl-ir/tests/lowerCorpusTest :a lct)
      (asl-ir/link :a lk)])

; (:m :ref QUAD-GOLDEN-AUTO :do "regenerates the three drift-prone golden expectations in one call: the checker quadGolden texts, the asl-ir quadGolden linked-IR digests and the lowerCorpusTest closure count; each drift is classified by the source commits since the commit that last changed the golden (checker texts: per file named by the changed lines; digests and count: the files of the link closure), and a golden is rewritten only with --apply and only when every changed line traces to a commit in that range, unless --force")

(schema Target (:f row String) (:f drift Bool) (:f applied Bool) (:f untraced Bool))

(schema PathChange (:f path String) (:f removed Int64) (:f added Int64) (:f commits (List String)))

fn countsOf lines: (List String) -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (l String)] -> (Map String Int64) (mapSet m l (+ 1 (optionOr (mapGet m l) 0)))) (mapEmpty) lines)

; (:m :do "the lines of A that B does not match, as a multiset difference in A's order: a line present twice in A and once in B is reported once")
fn onlyIn a: (List String) b: (List String) -> (List String)
  (listReverse (pairSecond (fold (fn [(st (Pair (Map String Int64) (List String))) (l String)] -> (Pair (Map String Int64) (List String))
                                   (let [(n (optionOr (mapGet (pairFirst st) l) 0))]
                                     (if (> n 0)
                                       (pair (mapSet (pairFirst st) l (- n 1)) (pairSecond st))
                                       (pair (pairFirst st) (cons l (pairSecond st))))))
                                 (pair (countsOf b) (list)) a)))

; (:m :do "drops the lines that carry no content for a diff: blank lines and a lone closing paren")
fn significant lines: (List String) -> (List String)
  (filter (fn [(l String)] -> Bool (and (not (stringEmpty? (stringTrim l))) (!= (stringTrim l) ")"))) lines)

; (:m :do "the first asl/... .asl path in a golden line (a summary :path, a diagnostic locus, a module line or a bare dependency row), empty when the line names none")
fn pathOfLine line: String -> String
  (match (stringIndexOf line "asl/")
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice line i (stringLength line)) ""))]
        (match (stringIndexOf rest ".asl")
          ((none) "")
          ((some j) (optionOr (stringSlice rest 0 (+ j 4)) ""))))))

fn pathCounts lines: (List String) -> (Map String Int64)
  (fold (fn [(m (Map String Int64)) (l String)] -> (Map String Int64)
          (let [(p (pathOfLine l))] (mapSet m p (+ 1 (optionOr (mapGet m p) 0)))))
        (mapEmpty) lines)

fn digitEnd b: Bytes n: Int64 i: Int64 -> Int64
  (if (and (< i n) (and (>= (bytesGet b i) 48) (<= (bytesGet b i) 57))) (digitEnd b n (+ i 1)) i)

fn digitsPrefix s: String -> String
  (let [(b (stringToBytes s))] (optionOr (stringSlice s 0 (digitEnd b (bytesLength b) 0)) ""))

; (:m :do "the integer written right after the first MARKER in a text, -1 when the marker or the digits are missing")
fn numberAfter text: String marker: String -> Int64
  (match (stringIndexOf text marker)
    ((none) -1)
    ((some i)
      (let [(rest (optionOr (stringSlice text (+ i (stringLength marker)) (stringLength text)) ""))]
        (optionOr (stringToInt64 (digitsPrefix rest)) -1))))

fn headerLines lines: (List String) acc: (List String) -> (List String)
  (match (listHead lines)
    ((none) (listReverse acc))
    ((some l) (if (or (stringStartsWith? l "(ok)") (stringStartsWith? l "(err)")) (listReverse acc)
                (headerLines (optionOr (listTail lines) (list)) (cons l acc)))))

; (:m :do "the distinct source paths of the link-closure unit rows that head a linked text, in order, up to the (ok) or (err) line")
fn closureFiles text: String -> (List String)
  (fold (fn [(acc (List String)) (p String)] -> (List String) (if (or (stringEmpty? p) (listContains? acc p)) acc (listAppend acc (list p))))
        (list) (map pathOfLine (headerLines (stringLines text) (list))))

fn rootRelative text: String -> String
  (match (realPath ".")
    ((ok root) (stringReplace text (str root "/") ""))
    ((err _) text))

fn digestOf text: String -> String
  (str (stringFromInt64 (fnv1a64 text)) ":" (stringFromInt64 (stringLength text)))

fn ! git! dir: String args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list "git" "-C" dir) args) dir (fr/childEnv (list))) (fr/limits 120 8))

fn lineList out: String -> (List String)
  (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map stringTrim (stringLines out)))

; (:m :do "the commit that last changed PATH, empty when there is none or git fails; it is the pin the drift is measured from")
fn ! pinOf! root: String path: String -> String
  (let [(d (git! root (list "log" "-1" "--format=%H" "--" path)))]
    (if (= d.exit 0) (stringTrim d.out) ""))

; (:m :do "the commit that last added or removed the text NEEDLE in PATH (git log -S), falling back to the last commit touching PATH: the golden is measured from the edit that pinned its current value, not from an unrelated edit of the file")
fn ! pinOfText! root: String path: String needle: String -> String
  (let [(d (git! root (list "log" "-1" "--format=%H" (str "-S" needle) "--" path)))
        (hit (if (= d.exit 0) (stringTrim d.out) ""))]
    (if (stringEmpty? hit) (pinOf! root path) hit))

; (:m :do "short ids of the commits after PIN that touch PATH, newest first; none when PIN is empty")
fn ! commitsIn! root: String pin: String path: String -> (List String)
  (if (stringEmpty? pin) (list)
    (let [(d (git! root (list "log" "--format=%h" (str pin "..HEAD") "--" path)))]
      (if (= d.exit 0) (lineList d.out) (list))))

fn ! addedIn! root: String pin: String path: String -> (List String)
  (if (stringEmpty? pin) (list)
    (let [(d (git! root (list "log" "--diff-filter=A" "--format=%h" (str pin "..HEAD") "--" path)))]
      (if (= d.exit 0) (lineList d.out) (list))))

fn ! changeOf! root: String pin: String rm: (Map String Int64) ad: (Map String Int64) p: String -> PathChange
  (PathChange :path p :removed (optionOr (mapGet rm p) 0) :added (optionOr (mapGet ad p) 0)
              :commits (if (stringEmpty? p) (list) (commitsIn! root pin p)))

; (:m :do "per path named by the removed and added lines: line counts and the commits since PIN that touched it; a line that names no path is reported under the empty path with no commits")
fn ! changesOf! root: String pin: String removed: (List String) added: (List String) -> (List PathChange)
  (let [(rm (pathCounts removed))
        (ad (pathCounts added))
        (paths (listSort (mapKeys (fold (fn [(m (Map String Bool)) (k String)] -> (Map String Bool) (mapSet m k true)) (mapEmpty) (listAppend (mapKeys rm) (mapKeys ad))))))]
    (map (fn [(p String)] -> PathChange (changeOf! root pin rm ad p)) paths))

; (:m :do "true when some change has no commit in the range: that drift is not explained by a source edit and must be reviewed, not re-recorded")
fn untraced? cs: (List PathChange) -> Bool
  (listAny? (fn [(c PathChange)] -> Bool (listEmpty? c.commits)) cs)

fn q s: String -> String
  (fm/asnQuote s)

fn changeRow c: PathChange -> String
  (str "(:path " (q c.path) " :removed " c.removed " :added " c.added " :commits (" (stringJoin c.commits " ") "))")

fn changesRow cs: (List PathChange) -> String
  (str "(" (stringJoin (map changeRow cs) " ") ")")

fn untracedPaths cs: (List PathChange) -> String
  (str "(" (stringJoin (map (fn [(c PathChange)] -> String (q c.path)) (filter (fn [(c PathChange)] -> Bool (listEmpty? c.commits)) cs)) " ") ")")

fn quiet file: String status: String -> Target
  (Target :row (str "(:golden :file " (q file) " :status " status ")") :drift false :applied false :untraced false)

fn ! checkerTarget! root: String go: Bool force: Bool entry: String -> Target
  (let [(path (cq/goldenFileFor entry))
        (text (rootRelative (cq/corpusText entry)))
        (want (resultOr (fileReadString path) ""))]
    (if (= want text) (quiet path ":unchanged")
      (let [(pin (pinOf! root path))
            (removed (significant (onlyIn (stringLines want) (stringLines text))))
            (added (significant (onlyIn (stringLines text) (stringLines want))))
            (cs (changesOf! root pin removed added))
            (bad (untraced? cs))
            (done (if (and go (or force (not bad))) (ok? (fileWrite path text)) false))]
        (Target :row (str "(:golden :file " (q path) " :status " (if done ":applied" ":drift") " :pin " (q pin) " :removed " (listLength removed) " :added " (listLength added)
                          " :changes " (changesRow cs) (if bad (str " :untraced " (untracedPaths cs)) "") ")")
                :drift true :applied done :untraced bad))))

fn ! closureChanges! root: String pin: String files: (List String) -> (List PathChange)
  (filter (fn [(c PathChange)] -> Bool (not (listEmpty? c.commits)))
          (map (fn [(p String)] -> PathChange (PathChange :path p :removed 0 :added 0 :commits (commitsIn! root pin p))) files))

; (:m :do "one digest golden of the asl-ir quadGoldenTest: recomputed, compared with its pinned value and, on drift, classified by the commits since the test file last changed that touched the files of its link closure (the prelude for lowerSourceWith); applied by replacing the quoted digest in the test source")
fn ! digestTarget! root: String go: Bool force: Bool testPath: String key: String want: String -> Target
  (let [(isSrc (= key "lowerSourceWith"))
        (text (if isSrc (iq/sourceText) (iq/linkedText key)))
        (got (digestOf (rootRelative text)))]
    (if (= got want) (quiet key ":unchanged")
      (let [(pin (pinOfText! root testPath want))
            (files (if isSrc (list (lk/preludePath)) (closureFiles (rootRelative text))))
            (cs (closureChanges! root pin files))
            (bad (listEmpty? cs))
            (src (resultOr (fileReadString testPath) ""))
            (once (= (listLength (stringSplit src (str "\"" want "\""))) 2))
            (done (if (and go (and once (or force (not bad)))) (ok? (fileWrite testPath (stringReplace src (str "\"" want "\"") (str "\"" got "\"")))) false))]
        (Target :row (str "(:digest :file " (q testPath) " :key " (q key) " :status " (if done ":applied" ":drift") " :pin " (q pin) " :want " (q want) " :got " (q got)
                          " :closureChanges " (changesRow cs) (if bad " :untraced (\"no closure file changed since the pin\")" "") ")")
                :drift true :applied done :untraced bad))))

fn ! irTargets! root: String go: Bool force: Bool -> (List Target)
  (let [(testPath "asl/packages/asl-ir/tests/quadGoldenTest.asl")]
    (map (fn [(p (Pair String String))] -> Target (digestTarget! root go force testPath (pairFirst p) (pairSecond p))) (iq/goldenDigests)))

; (:m :do "the closure size asserted by lowerCorpusTest: recomputed from the compiler entry's link closure; on drift the new units are the closure files added after the pin, and applying rewrites the count in the assert and its message and names each new unit with its adding commit before the got text")
fn ! corpusTarget! root: String go: Bool force: Bool -> Target
  (let [(testPath "asl/packages/asl-ir/tests/lowerCorpusTest.asl")
        (units (resultOr (lk/loadClosure! (lct/entryPath)) (list)))
        (got (listLength units))
        (src (resultOr (fileReadString testPath) ""))
        (want (numberAfter src "(= (listLength units) "))]
    (if (= got want) (quiet testPath ":unchanged")
      (let [(pin (pinOfText! root testPath (str "(= (listLength units) " want ")")))
            (fresh (filter (fn [(p (Pair String String))] -> Bool (not (stringEmpty? (pairSecond p))))
                           (map (fn [(u lk/LinkUnit)] -> (Pair String String) (pair u.name (stringJoin (addedIn! root pin u.path) " "))) units)))
            (prose (stringJoin (map (fn [(p (Pair String String))] -> String (str ", and " (pairFirst p) " since " (optionOr (listHead (stringSplit (pairSecond p) " ")) ""))) fresh) ""))
            (bad (or (< want 0) (and (> got want) (listEmpty? fresh))))
            (s1 (stringReplace src (str "(= (listLength units) " want ")") (str "(= (listLength units) " got ")")))
            (s2 (stringReplace s1 (str "the closure loads " want " modules") (str "the closure loads " got " modules")))
            (oneGot (= (listLength (stringSplit s2 "), got ")) 2))
            (s3 (if oneGot (stringReplace s2 "), got " (str prose "), got ")) s2))
            (done (if (and go (or force (not bad))) (ok? (fileWrite testPath s3)) false))]
        (Target :row (str "(:count :file " (q testPath) " :status " (if done ":applied" ":drift") " :pin " (q pin) " :want " want " :got " got
                          " :newUnits (" (stringJoin (map (fn [(p (Pair String String))] -> String (str "(" (q (pairFirst p)) " " (q (pairSecond p)) ")")) fresh) " ") ")"
                          (if bad " :untraced (\"no unit added since the pin explains the count\")" "") ")")
                :drift true :applied done :untraced bad))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(go (listContains? args "--apply"))
        (force (listContains? args "--force"))
        (checker (map (fn [(e String)] -> Target (checkerTarget! "." go force e)) (cq/entries)))
        (ir (irTargets! "." go force))
        (count (corpusTarget! "." go force))
        (all (listAppend (listAppend checker ir) (list count)))
        (_ (map (fn [(t Target)] -> Unit (println t.row)) all))
        (drift (listLength (filter (fn [(t Target)] -> Bool t.drift) all)))
        (applied (listLength (filter (fn [(t Target)] -> Bool t.applied) all)))
        (pending (filter (fn [(t Target)] -> Bool (and t.drift (not t.applied))) all))
        (bad (listAny? (fn [(t Target)] -> Bool t.untraced) pending))]
    (do (println (str "(:goldenRegen :targets " (listLength all) " :drift " drift " :applied " applied " :pending " (listLength pending) " :untraced " (listLength (filter (fn [(t Target)] -> Bool t.untraced) pending)) ")"))
        (ok (cond ((listEmpty? pending) 0) (bad 2) (else 1)))))
