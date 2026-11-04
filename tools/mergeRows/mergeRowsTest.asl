(module ws/mergeRows/mergeRowsTest :x [runTests] :i [(ws/mergeRows/mergeRows :a m) (asl-tools/fleet/run :a fr)])
fn ! runTests -> Bool
  (do
    (assert (testHistoryReplay!) "five historical conflicts and three Git merges replay cleanly")
    (assert (testAttributes!) "knownRed, hostValidity and camelLexicon merge with the asnRows driver")
    (assert (testLedger! ".asl/mem/knownRed.asn" "  (:suite \"rowsOurs.asl\" :cause \"E\")" "  (:suite \"rowsTheirs.asl\" :cause \"E\")") "knownRed rows added on both branches merge in place")
    (assert (testLedger! "tools/camelLexicon.asn" "    (\"rows-ours\" \"rowsOurs\")" "    (\"rows-theirs\" \"rowsTheirs\")") "camelLexicon rows added on both branches merge in place")
    (assert (testLedger! "scripts/audit/foreignBaseline.asn" "  (:raise :path \"rowsOurs.sh\" :lang :shell :lines 1 :py 0)" "  (:raise :path \"rowsTheirs.sh\" :lang :shell :lines 1 :py 0)") "foreignBaseline raises added on both branches merge in place")
    (assert (testHostValidityLedger!) "hostValidity rows added on both branches merge and recount (:total)")
    (assert (testDelete) "delete versus unchanged removes row")
    (assert (testConflict) "same key divergent update marks only that row")
    (assert (testLarger) "baseline rows changed on both sides take the larger line count")
    (assert (testMetaBaseline) "meta baseline rows merge by the larger :plain value")
    (assert (testLangMismatch) "language mismatch conflicts")
    (assert (testTie) "same line count divergent baseline rows conflict")
    (assert (testRaiseThreeWay) "raises merge three-way: a raise ours retired stays retired")
    (assert (testIdentity) "identity preserves original bytes")
    (assert (testKnownRed) "knownRed rows added on both sides land before the closing line without blank lines")
    (assert (testHostValidity) "hostValidity rows added on both sides recount (:total)")
    (assert (testSections) "camelLexicon additions stay in their section and the closing suffix moves to the last row")
    (assert (testDeleteLast) "deleting the last row of a section moves its closers to the row before")
    (assert (testDeleteVersusChange) "a row theirs changed and ours deleted conflicts")
    true)
; (:m :ref FOREIGN-PORT-1 :do "the historical replay is ASL: git show feeds the driver through fr jobs, and the expected merge is recomputed here by a row oracle independent of mergeRows.asl, one textual assert per checkpoint so declared equals executed")
fn isSpaceChar c: String -> Bool
  (or (= c " ") (or (= c "\n") (or (= c "\t") (= c "\r"))))
fn canonLoop cs: (List String) i: Int64 depth: Int64 quoted: Bool escaped: Bool acc: (List String) -> String
  (if (>= i (listLength cs))
    (stringJoin (listReverse acc) "")
    (let [(c (optionOr (listGet cs i) ""))]
      (cond
        (quoted (canonLoop cs (+ i 1) depth (if escaped true (not (= c "\""))) (if escaped false (= c "\\")) (cons c acc)))
        ((= c "\"") (canonLoop cs (+ i 1) depth true false (cons c acc)))
        ((= c "(") (canonLoop cs (+ i 1) (+ depth 1) false false (cons c acc)))
        ((= c ")") (if (= depth 1)
                     (stringJoin (listReverse (cons c acc)) "")
                     (canonLoop cs (+ i 1) (- depth 1) false false (cons c acc))))
        ((isSpaceChar c) (canonLoop cs (+ i 1) depth false false acc))
        (else (canonLoop cs (+ i 1) depth false false (cons c acc))))))
fn canonical text: String -> String
  (canonLoop (stringChars (stringTrim text)) 0 0 false false (list))
fn quoteEnd cs: (List String) i: Int64 -> Int64
  (if (>= i (listLength cs))
    -1
    (let [(c (optionOr (listGet cs i) ""))]
      (cond
        ((= c "\\") (quoteEnd cs (+ i 2)))
        ((= c "\"") i)
        (else (quoteEnd cs (+ i 1))))))
fn afterTag raw: String tag: String -> String
  (match (stringIndexOf raw tag)
    ((none) "")
    ((some at) (stringTrim (optionOr (stringSlice raw (+ at (stringLength tag)) (stringLength raw)) ""))))
fn pathKey raw: String -> (Option String)
  (let [(rest (afterTag raw ":path"))]
    (if (stringStartsWith? rest "\"")
      (let [(cs (stringChars rest))
            (e (quoteEnd cs 1))]
        (if (< e 1) (none) (some (stringJoin (listTake (listDrop cs 1) (- e 1)) ""))))
      (none)))
fn tokenLen cs: (List String) i: Int64 -> Int64
  (let [(c (optionOr (listGet cs i) " "))]
    (if (or (isSpaceChar c) (or (= c "(") (= c ")"))) i (tokenLen cs (+ i 1))))
fn tokenAfter raw: String tag: String -> String
  (let [(cs (stringChars (afterTag raw tag)))]
    (stringJoin (listTake cs (tokenLen cs 0)) ""))
fn formsOf text: String wanted: String -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "(" wanted))) (map stringTrim (stringLines text)))
fn rowsLoop raws: (List String) order: (List String) rows: (Map String String) -> (Option (Pair (List String) (Map String String)))
  (match (listHead raws)
    ((none) (some (pair (listReverse order) rows)))
    ((some raw)
      (match (pathKey raw)
        ((none) (none))
        ((some k) (if (mapHas? rows k)
                    (none)
                    (rowsLoop (optionOr (listTail raws) (list)) (cons k order) (mapSet rows k raw)))))))
fn rowsOf text: String tag: String -> (Option (Pair (List String) (Map String String)))
  (rowsLoop (formsOf text tag) (list) (mapEmpty))
fn hasRows? o: (Option (Pair (List String) (Map String String))) -> Bool
  (match o ((none) false) ((some _) true))
fn sameRow a: (Option String) b: (Option String) -> Bool
  (match a
    ((none) (match b ((none) true) ((some _) false)))
    ((some x) (match b ((none) false) ((some y) (= (canonical x) (canonical y))))))
fn chooseRow key: String baseline: Bool b: (Option String) o: (Option String) t: (Option String) -> (Result (Option String) String)
  (cond
    ((sameRow o b) (ok t))
    ((or (sameRow t b) (sameRow o t)) (ok o))
    (else
      (match o
        ((none) (err (str "unresolvable conflict at " key)))
        ((some ro)
          (match t
            ((none) (err (str "unresolvable conflict at " key)))
            ((some rt)
              (let [(l1 (tokenAfter ro ":lang"))
                    (l2 (tokenAfter rt ":lang"))
                    (n1 (optionOr (stringToInt64 (tokenAfter ro ":lines")) -1))
                    (n2 (optionOr (stringToInt64 (tokenAfter rt ":lines")) -1))]
                (cond
                  ((not baseline) (err (str "unresolvable conflict at " key)))
                  ((or (stringEmpty? l1) (or (not (= l1 l2)) (or (< n1 0) (< n2 0)))) (err (str "unresolvable baseline conflict at " key)))
                  ((and (= n1 n2) (not (= (canonical ro) (canonical rt)))) (err (str "equal-ratchet baseline conflict at " key)))
                  ((>= n1 n2) (ok (some ro)))
                  (else (ok (some rt)))))))))))
fn chooseAll keys: (List String) baseline: Bool bm: (Map String String) om: (Map String String) tm: (Map String String) acc: (List (Pair String String)) -> (Result (List (Pair String String)) String)
  (match (listHead keys)
    ((none) (ok (listReverse acc)))
    ((some k)
      (match (chooseRow k baseline (mapGet bm k) (mapGet om k) (mapGet tm k))
        ((err e) (err e))
        ((ok chosen)
          (chooseAll (optionOr (listTail keys) (list)) baseline bm om tm
            (match chosen ((none) acc) ((some row) (cons (pair k row) acc))))))))
fn dedupe xs: (List String) -> (List String)
  (listReverse (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (cons x acc))) (list) xs))
fn blankCount text: String -> Int64
  (let [(pieces (stringSplit text "\n"))]
    (listCount (fn [(l String)] -> Bool (stringEmpty? (stringTrim l))) (listTake pieces (- (listLength pieces) 1))))
fn mergeProblem baseText: String oursText: String theirsText: String outText: String logical: String -> String
  (let [(baseline (stringContains? logical "foreignBaseline"))
        (tag (if baseline ":file" ":path"))
        (empty (pair (list) (mapEmpty)))
        (rb (rowsOf baseText tag))
        (ro (rowsOf oursText tag))
        (rt (rowsOf theirsText tag))
        (ra (rowsOf outText tag))
        (bm (pairSecond (optionOr rb empty)))
        (om (pairSecond (optionOr ro empty)))
        (tm (pairSecond (optionOr rt empty)))
        (am (pairSecond (optionOr ra empty)))
        (oOrder (pairFirst (optionOr ro empty)))
        (tOrder (pairFirst (optionOr rt empty)))
        (aOrder (pairFirst (optionOr ra empty)))
        (newKeys (listSort (filter (fn [(k String)] -> Bool (not (mapHas? om k))) (mapKeys tm))))]
    (if (not (and (hasRows? rb) (and (hasRows? ro) (and (hasRows? rt) (hasRows? ra)))))
      (str logical ": a row has no quoted :path or repeats a key")
      (match (chooseAll (listAppend oOrder newKeys) baseline bm om tm (list))
        ((err e) (str logical ": " e))
        ((ok chosen)
          (let [(chosenMap (mapFromPairs chosen))
                (chosenKeys (map pairFirst chosen))
                (missing (filter (fn [(k String)] -> Bool (not (mapHas? am k))) chosenKeys))
                (extra (filter (fn [(k String)] -> Bool (not (mapHas? chosenMap k))) aOrder))
                (changed (filter (fn [(k String)] -> Bool
                                   (and (mapHas? am k)
                                        (not (= (canonical (mapGetOr chosenMap k "")) (canonical (mapGetOr am k ""))))))
                                 chosenKeys))
                (orderBad (or (not (= (filter (fn [(k String)] -> Bool (mapHas? om k)) aOrder)
                                      (filter (fn [(k String)] -> Bool (mapHas? chosenMap k)) oOrder)))
                              (not (= (filter (fn [(k String)] -> Bool (listContains? newKeys k)) aOrder)
                                      (filter (fn [(k String)] -> Bool (and (listContains? newKeys k) (mapHas? chosenMap k))) tOrder)))))
                (baseR (map canonical (formsOf baseText ":raise")))
                (oursR (map canonical (formsOf oursText ":raise")))
                (theirsR (map canonical (formsOf theirsText ":raise")))
                (actualR (map canonical (formsOf outText ":raise")))
                (keptOurs (filter (fn [(r String)] -> Bool (or (not (listContains? baseR r)) (listContains? theirsR r))) oursR))
                (raises (listAppend keptOurs
                          (filter (fn [(r String)] -> Bool (and (not (listContains? baseR r)) (not (listContains? keptOurs r)))) (dedupe theirsR))))
                (raiseMissing (filter (fn [(r String)] -> Bool (not (listContains? actualR r))) raises))
                (raiseExtra (filter (fn [(r String)] -> Bool (not (listContains? raises r))) actualR))
                (raiseOrderBad (or (not (= (listSort actualR) (listSort raises)))
                                   (not (= (filter (fn [(r String)] -> Bool (listContains? oursR r)) actualR)
                                           (filter (fn [(r String)] -> Bool (listContains? oursR r)) raises)))))
                (blankGrowth (> (blankCount outText) (optionOr (listMax (list (blankCount oursText) (blankCount theirsText))) 0)))]
            (if (and (listEmpty? missing) (and (listEmpty? extra) (and (listEmpty? changed) (and (not orderBad) (and (listEmpty? raiseMissing) (and (listEmpty? raiseExtra) (and (not raiseOrderBad) (not blankGrowth))))))))
              ""
              (str logical ": expected rows " (stringFromInt64 (listLength chosen)) ", actual rows " (stringFromInt64 (listLength aOrder))
                   ", missing " (stringFromInt64 (listLength missing)) ", extra " (stringFromInt64 (listLength extra))
                   ", changed " (stringFromInt64 (listLength changed)) ", rowOrderBad " (if orderBad "true" "false")
                   ", raiseMissing " (stringFromInt64 (listLength raiseMissing)) ", raiseExtra " (stringFromInt64 (listLength raiseExtra))
                   ", raiseOrderBad " (if raiseOrderBad "true" "false") ", blankGrowth " (if blankGrowth "true" "false")
                   (match (listHead (listAppend missing (listAppend extra changed))) ((some k) (str " first " k)) ((none) "")))))))))
fn hasMarkers? text: String -> Bool
  (listAny? (fn [(l String)] -> Bool (let [(t (stringTrim l))] (or (= t "<<<<<<< ours") (or (= t "=======") (= t ">>>>>>> theirs"))))) (stringLines text))
fn ! gitRun! cwd: String args: (List String) env: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (cons "git" args) cwd (fr/childEnv env)) (fr/limits 180 64))
fn ! gitShow! root: String rev: String path: String -> String
  (let [(d (gitRun! root (list "show" (str rev ":" path)) (list)))]
    (if (= d.exit 0) d.out ""))
fn ! parentsOf! root: String commit: String -> (List String)
  (stringSplit (stringTrim (gitRun! root (list "show" "-s" "--format=%P" commit) (list)).out) " ")
fn ! driverRun! root: String args: (List String) -> fr/Done
  (fr/runOneLimited (fr/job (listAppend (list (str root "/bin/asl") "run" (str root "/asl/tools/mergeRows/mergeRows.asl")) args) root (fr/childEnv (list))) (fr/limits 600 64))
fn ! directProblem! root: String tmp: String commit: String path: String -> String
  (let [(parents (parentsOf! root commit))
        (p1 (optionOr (listGet parents 0) ""))
        (p2 (optionOr (listGet parents 1) ""))
        (base (stringTrim (gitRun! root (list "merge-base" p1 p2) (list)).out))
        (dir (str tmp "/" commit "-" (stringFromInt64 (stringLength path))))
        (_ (dirCreate dir))
        (baseText (gitShow! root base path))
        (oursText (gitShow! root p1 path))
        (theirsText (gitShow! root p2 path))
        (_ (fileWrite (str dir "/base.asn") baseText))
        (_ (fileWrite (str dir "/ours.asn") oursText))
        (_ (fileWrite (str dir "/theirs.asn") theirsText))
        (d (driverRun! root (list (str dir "/base.asn") (str dir "/ours.asn") (str dir "/theirs.asn") path)))
        (outText (resultOr (fileReadString (str dir "/ours.asn")) ""))
        (_ (fileWrite (str dir "/validate-base.asn") outText))
        (_ (fileWrite (str dir "/validate-ours.asn") outText))
        (_ (fileWrite (str dir "/validate-theirs.asn") outText))
        (v (driverRun! root (list (str dir "/validate-base.asn") (str dir "/validate-ours.asn") (str dir "/validate-theirs.asn") path)))
        (againText (resultOr (fileReadString (str dir "/validate-ours.asn")) ""))
        (problem (mergeProblem baseText oursText theirsText outText path))]
    (cond
      ((or (stringEmpty? baseText) (or (stringEmpty? oursText) (stringEmpty? theirsText))) (str commit " " path ": git show returned no content"))
      ((not (= d.exit 0)) (str "driver failed for " commit " " path " (exit " (stringFromInt64 d.exit) ") " d.out))
      ((hasMarkers? outText) (str "conflict marker in merged " path))
      ((not (stringEmpty? problem)) problem)
      ((not (= v.exit 0)) (str "invalid merged ASN for " commit " " path " (exit " (stringFromInt64 v.exit) ") " v.out))
      ((not (= againText outText)) (str "identity merge rewrote output for " commit " " path))
      (else "")))
fn ! gitCmd! repo: String args: (List String) -> fr/Done
  (gitRun! repo args (list "GIT_CONFIG_NOSYSTEM=1" "GIT_CONFIG_GLOBAL=/dev/null"))
fn ! commitPair! repo: String p: String baseline: String allowlist: String root: String msg: String -> Bool
  (let [(_ (fileWrite (str repo "/" baseline) (gitShow! root p baseline)))
        (_ (fileWrite (str repo "/" allowlist) (gitShow! root p allowlist)))
        (a (gitCmd! repo (list "add" baseline allowlist)))
        (c (gitCmd! repo (list "commit" "-qm" msg)))]
    (and (= a.exit 0) (= c.exit 0)))
; (:m :ref FOREIGN-PORT-1 :do "returns the default-merge problem and the driver-merge problem for one historical pair, built in a scratch repository: a first merge without merge.asnRows must conflict, a second with the driver configured must merge cleanly and match the oracle")
fn ! gitPair! root: String tmp: String commit: String -> (Pair String String)
  (let [(baseline "scripts/audit/foreignBaseline.asn")
        (allowlist "scripts/audit/foreignAllowlist.asn")
        (parents (parentsOf! root commit))
        (p1 (optionOr (listGet parents 0) ""))
        (p2 (optionOr (listGet parents 1) ""))
        (base (stringTrim (gitRun! root (list "merge-base" p1 p2) (list)).out))
        (repo (str tmp "/git-" commit))
        (_ (dirCreate repo))
        (_ (gitCmd! repo (list "init" "-q")))
        (_ (gitCmd! repo (list "config" "user.name" "Merge Rows Test")))
        (_ (gitCmd! repo (list "config" "user.email" "merge-rows-test@example.invalid")))
        (_ (dirCreate (str repo "/scripts")))
        (_ (dirCreate (str repo "/scripts/audit")))
        (_ (fileWrite (str repo "/.gitattributes") (str baseline " merge=asnRows\n" allowlist " merge=asnRows\n")))
        (_ (fileWrite (str repo "/" baseline) (gitShow! root base baseline)))
        (_ (fileWrite (str repo "/" allowlist) (gitShow! root base allowlist)))
        (addBase (gitCmd! repo (list "add" ".gitattributes" baseline allowlist)))
        (commitBase (gitCmd! repo (list "commit" "-qm" "base")))
        (baseBranch (stringTrim (gitCmd! repo (list "branch" "--show-current")).out))
        (_ (gitCmd! repo (list "checkout" "-qb" "ours")))
        (oursOk (commitPair! repo p1 baseline allowlist root "ours"))
        (_ (gitCmd! repo (list "checkout" "-qb" "theirs" baseBranch)))
        (theirsOk (commitPair! repo p2 baseline allowlist root "theirs"))
        (_ (gitCmd! repo (list "checkout" "-q" "ours")))
        (plain (gitCmd! repo (list "merge" "--no-edit" "theirs")))
        (wantAllow (= commit "1219de8973fbfe3d99219b4fe2bf62ccce1fdfc6"))
        (plainProblem
          (cond
            ((not (and (= addBase.exit 0) (and (= commitBase.exit 0) (and oursOk theirsOk)))) (str commit ": scratch repository setup failed"))
            ((= plain.exit 0) (str "default Git merge unexpectedly clean for " commit))
            ((not (stringContains? plain.out (str "CONFLICT (content): Merge conflict in " baseline))) (str "default merge did not report the baseline text conflict for " commit ": " plain.out))
            ((and wantAllow (not (stringContains? plain.out (str "CONFLICT (content): Merge conflict in " allowlist)))) (str "default merge did not report the allowlist text conflict for " commit))
            (else "")))
        (_ (gitCmd! repo (list "merge" "--abort")))
        (_ (gitCmd! repo (list "config" "merge.asnRows.driver" (str root "/bin/asl run " root "/asl/tools/mergeRows/mergeRows.asl %O %A %B %P"))))
        (merged (gitCmd! repo (list "merge" "--no-edit" "theirs")))
        (outBaseline (resultOr (fileReadString (str repo "/" baseline)) ""))
        (outAllow (resultOr (fileReadString (str repo "/" allowlist)) ""))
        (probBaseline (mergeProblem (gitShow! root base baseline) (gitShow! root p1 baseline) (gitShow! root p2 baseline) outBaseline baseline))
        (probAllow (mergeProblem (gitShow! root base allowlist) (gitShow! root p1 allowlist) (gitShow! root p2 allowlist) outAllow allowlist))
        (driverProblem
          (cond
            ((not (= merged.exit 0)) (str "Git merge failed for historical pair " commit " (exit " (stringFromInt64 merged.exit) ") " merged.out))
            ((or (hasMarkers? outBaseline) (hasMarkers? outAllow)) (str "conflict marker after the driver merge of " commit))
            ((not (stringEmpty? probBaseline)) probBaseline)
            (else probAllow)))]
    (pair plainProblem driverProblem))
fn ! testHistoryReplay! -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (tmp (str (optionOr (envGet "TMPDIR") "/tmp") "/aslMergeRowsHistory-" (stringFromInt64 (monotonicNs))))
        (_ (dirCreate tmp))
        (b "scripts/audit/foreignBaseline.asn")
        (a "scripts/audit/foreignAllowlist.asn")
        (c1 "1219de8973fbfe3d99219b4fe2bf62ccce1fdfc6")
        (c2 "20f3c4ae62431692c8b09e961ecdae81a6bb79bd")
        (c3 "d41b122130b166984c70436d0b04eca7275b89ed")
        (c4 "0f351d3666199aaf45af6f3c3e21d82176c1370e")
        (c5 "b107fc89894e3527ca2cc46e5c7f9cb748038418")
        (d1b (directProblem! root tmp c1 b))
        (d1a (directProblem! root tmp c1 a))
        (d2b (directProblem! root tmp c2 b))
        (d2a (directProblem! root tmp c2 a))
        (d3b (directProblem! root tmp c3 b))
        (d3a (directProblem! root tmp c3 a))
        (d4b (directProblem! root tmp c4 b))
        (d4a (directProblem! root tmp c4 a))
        (d5b (directProblem! root tmp c5 b))
        (d5a (directProblem! root tmp c5 a))
        (g1 (gitPair! root tmp c1))
        (g2 (gitPair! root tmp c2))
        (g3 (gitPair! root tmp c3))]
    (do
      (assert (stringEmpty? d1b) (str "direct 1219de89 baseline: " d1b))
      (assert (stringEmpty? d1a) (str "direct 1219de89 allowlist: " d1a))
      (assert (stringEmpty? d2b) (str "direct 20f3c4ae baseline: " d2b))
      (assert (stringEmpty? d2a) (str "direct 20f3c4ae allowlist: " d2a))
      (assert (stringEmpty? d3b) (str "direct d41b1221 baseline: " d3b))
      (assert (stringEmpty? d3a) (str "direct d41b1221 allowlist: " d3a))
      (assert (stringEmpty? d4b) (str "direct 0f351d36 baseline: " d4b))
      (assert (stringEmpty? d4a) (str "direct 0f351d36 allowlist: " d4a))
      (assert (stringEmpty? d5b) (str "direct b107fc89 baseline: " d5b))
      (assert (stringEmpty? d5a) (str "direct b107fc89 allowlist: " d5a))
      (assert (stringEmpty? (pairFirst g1)) (str "git 1219de89 default textual merge conflicts: " (pairFirst g1)))
      (assert (stringEmpty? (pairSecond g1)) (str "git 1219de89 clean merge via merge.asnRows: " (pairSecond g1)))
      (assert (stringEmpty? (pairFirst g2)) (str "git 20f3c4ae default textual merge conflicts: " (pairFirst g2)))
      (assert (stringEmpty? (pairSecond g2)) (str "git 20f3c4ae clean merge via merge.asnRows: " (pairSecond g2)))
      (assert (stringEmpty? (pairFirst g3)) (str "git d41b1221 default textual merge conflicts: " (pairFirst g3)))
      (assert (stringEmpty? (pairSecond g3)) (str "git d41b1221 clean merge via merge.asnRows: " (pairSecond g3)))
      (pathRemove tmp)
      true))
fn testAttributes! -> Bool
  (match (fileReadString ".gitattributes")
    ((err _) false)
    ((ok text) (let [(lines (stringLines text))]
      (and (listContains? lines ".asl/mem/knownRed.asn merge=asnRows")
           (listContains? lines "tests/audit/hostValidity.asn merge=asnRows")
           (listContains? lines "tools/camelLexicon.asn merge=asnRows")))))
fn insertBeforeLast text: String row: String -> String
  (let [(lines (stringSplit text "\n")) (n (listLength lines))
        (cut (if (stringEmpty? (optionOr (listGet lines (- n 1)) "x")) (- n 2) (- n 1)))]
    (stringJoin (listAppend (listTake lines cut) (cons row (listDrop lines cut))) "\n"))
fn testLedger! path: String oursRow: String theirsRow: String -> Bool
  (match (fileReadString path)
    ((err _) false)
    ((ok base)
      (let [(ours (insertBeforeLast base oursRow))
            (r (m/mergeRows base ours (insertBeforeLast base theirsRow) "rows"))]
        (and (not r.conflict) (= r.text (insertBeforeLast ours theirsRow))))))
fn bumpTotal text: String by: Int64 -> String
  (stringJoin (map (fn [(l String)] -> String
    (if (stringStartsWith? l "(:total ")
      (str "(:total " (stringFromInt64 (+ by (optionOr (stringToInt64 (optionOr (stringSlice l 8 (- (stringLength l) 1)) "")) 0))) ")")
      l)) (stringSplit text "\n")) "\n")
fn testHostValidityLedger! -> Bool
  (match (fileReadString "tests/audit/hostValidity.asn")
    ((err _) false)
    ((ok base)
      (let [(o "(:f :path \"rowsOurs.asl\" :code ERR_X :class staleName)\n")
            (t "(:f :path \"rowsTheirs.asl\" :code ERR_X :class staleName)\n")
            (r (m/mergeRows base (bumpTotal (str base o) 1) (bumpTotal (str base t) 1) "hostValidity"))]
        (and (stringStartsWith? base "(:total ") (stringEndsWith? base "\n") (not r.conflict)
             (= r.text (bumpTotal (str base o t) 2))))))
fn testDelete -> Bool
  (let [(b "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c)\n(:path \"b.c\" :kind :c)\n)")
        (o "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c)\n)")
        (r (m/mergeRows b o b "allowlist"))]
    (and (not r.conflict) (not (stringContains? r.text "b.c"))))
fn testConflict -> Bool
  (let [(b "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c :rationale \"old\")\n(:path \"b.c\" :kind :c)\n)")
        (o "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c :rationale \"ours\")\n(:path \"b.c\" :kind :c)\n)")
        (t "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c :rationale \"theirs\")\n(:path \"b.c\" :kind :c)\n)")
        (r (m/mergeRows b o t "allowlist"))]
    (and r.conflict
         (stringContains? r.text "<<<<<<< ours\n(:path \"a.c\"")
         (stringContains? r.text ">>>>>>> theirs\n(:path \"b.c\"")
         (= (listLength (stringSplit r.text "=======")) 2)))
fn testLarger -> Bool
  (let [(h "(:foreignBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n")
        (b (str h "(:file :path \"a.c\" :lang :c :lines 1007 :py 0)\n)"))
        (o (str h "(:file :path \"a.c\" :lang :c :lines 1067 :py 0)\n)"))
        (t (str h "(:file :path \"a.c\" :lang :c :lines 1026 :py 0)\n)"))
        (oursLarger (m/mergeRows b o t "baseline"))
        (theirsLarger (m/mergeRows b t o "baseline"))]
    (and (not oursLarger.conflict) (stringContains? oursLarger.text ":lines 1067") (not (stringContains? oursLarger.text ":lines 1026"))
         (not theirsLarger.conflict) (stringContains? theirsLarger.text ":lines 1067") (not (stringContains? theirsLarger.text ":lines 1026"))))
fn testMetaBaseline -> Bool
  (let [(h "(:metaBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n")
        (b (str h "(:file :path \"a.asl\" :plain 7)\n)"))
        (o (str h "(:file :path \"a.asl\" :plain 9)\n)"))
        (t (str h "(:file :path \"a.asl\" :plain 8)\n)"))
        (oursLarger (m/mergeRows b o t "metaBaseline"))
        (theirsLarger (m/mergeRows b t o "metaBaseline"))]
    (and (not oursLarger.conflict) (stringContains? oursLarger.text ":plain 9") (not (stringContains? oursLarger.text ":plain 8"))
         (not theirsLarger.conflict) (stringContains? theirsLarger.text ":plain 9") (not (stringContains? theirsLarger.text ":plain 8"))))
fn testLangMismatch -> Bool
  (let [(h "(:foreignBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n")
        (b (str h "(:file :path \"a.asl\" :lang :c :lines 5 :py 0)\n)"))
        (o (str h "(:file :path \"a.asl\" :lang :c :lines 7 :py 0)\n)"))
        (t (str h "(:file :path \"a.asl\" :lang :py :lines 99 :py 0)\n)"))
        (r (m/mergeRows b o t "baseline"))]
    (and r.conflict
         (stringContains? r.text ":lang :c :lines 7")
         (stringContains? r.text ":lang :py :lines 99")))
fn testRaiseThreeWay -> Bool
  (let [(h "(:foreignBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\")\n")
        (a "(:raise :path \"a.c\" :lang :c :lines 2 :py 0 :reason \"a\" :date \"d\")")
        (b "(:raise :path \"b.c\" :lang :c :lines 3 :py 0 :reason \"b\" :date \"d\")")
        (c "(:raise :path \"c.c\" :lang :c :lines 4 :py 0 :reason \"c\" :date \"d\")")
        (d "(:raise :path \"d.c\" :lang :c :lines 5 :py 0 :reason \"d\" :date \"d\")")
        (r (m/mergeRows (str h a "\n" b "\n") (str h b "\n" c "\n") (str h a "\n" b "\n" d "\n") "baseline"))]
    (and (not r.conflict)
         (= r.text (str h b "\n" c "\n" d "\n"))))
fn testKnownRed -> Bool
  (let [(h "(:knownRed :v 1 :date \"d\"\n")
        (x "  (:suite \"x.asl\" :cause \"E\")\n")
        (y "  (:suite \"y.asl\" :cause \"E\")\n")
        (z "  (:suite \"z.asl\" :cause \"E\")\n")
        (r (m/mergeRows (str h x ")\n") (str h x y ")\n") (str h x z ")\n") "rows"))]
    (and (not r.conflict) (= r.text (str h x y z ")\n"))))
fn testHostValidity -> Bool
  (let [(row (fn [(p String) (c String)] -> String (str "(:f :path \"" p "\" :code ERR_X :class " c ")\n")))
        (b (str "(:total 1)\n" (row "a.asl" "staleName")))
        (o (str "(:total 2)\n" (row "a.asl" "staleName") (row "b.asl" "staleName") (row "n.asl" "negativeFixture")))
        (t (str "(:total 2)\n" (row "a.asl" "staleName") (row "c.asl" "staleName")))
        (r (m/mergeRows b o t "hostValidity"))]
    (and (not r.conflict)
         (= r.text (str "(:total 3)\n" (row "a.asl" "staleName") (row "b.asl" "staleName") (row "n.asl" "negativeFixture") (row "c.asl" "staleName")))))
fn testSections -> Bool
  (let [(b "(:lexicon :id \"x\"\n  :chosen (\n    (:old \"a-b\" :new \"aB\"))\n  :renames (\n    (\"c-d\" \"cD\")))\n")
        (o "(:lexicon :id \"x\"\n  :chosen (\n    (:old \"a-b\" :new \"aB\"))\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"e-f\" \"eF\")))\n")
        (t "(:lexicon :id \"x\"\n  :chosen (\n    (:old \"a-b\" :new \"aB\")\n    (:old \"g-h\" :new \"gH\"))\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"i-j\" \"iJ\")))\n")
        (r (m/mergeRows b o t "rows"))]
    (and (not r.conflict)
         (= r.text "(:lexicon :id \"x\"\n  :chosen (\n    (:old \"a-b\" :new \"aB\")\n    (:old \"g-h\" :new \"gH\"))\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"e-f\" \"eF\")\n    (\"i-j\" \"iJ\")))\n")))
fn testDeleteLast -> Bool
  (let [(b "(:lexicon :id \"x\"\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"e-f\" \"eF\")))\n")
        (o "(:lexicon :id \"y\"\n  :renames (\n    (\"c-d\" \"cD\")\n    (\"e-f\" \"eF\")))\n")
        (t "(:lexicon :id \"x\"\n  :renames (\n    (\"c-d\" \"cD\")))\n")
        (r (m/mergeRows b o t "rows"))]
    (and (not r.conflict) (= r.text "(:lexicon :id \"y\"\n  :renames (\n    (\"c-d\" \"cD\")))\n")))
fn testDeleteVersusChange -> Bool
  (let [(h "(:knownRed :v 1\n")
        (b (str h "  (:suite \"x.asl\" :cause \"E\")\n  (:suite \"y.asl\" :cause \"E\")\n)\n"))
        (o (str h "  (:suite \"y.asl\" :cause \"E\")\n)\n"))
        (t (str h "  (:suite \"x.asl\" :cause \"F\")\n  (:suite \"y.asl\" :cause \"E\")\n)\n"))
        (r (m/mergeRows b o t "rows"))]
    (and r.conflict (stringContains? r.text "=======\n  (:suite \"x.asl\" :cause \"F\")\n>>>>>>> theirs")))
fn testTie -> Bool
  (let [(h "(:foreignBaseline :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n")
        (b (str h "(:file :path \"a.c\" :lang :c :lines 9 :py 0)\n)"))
        (o (str h "(:file :path \"a.c\" :lang :c :lines 8 :py 0)\n)"))
        (t (str h "(:file :path \"a.c\" :lang :c :lines 8 :py 1)\n)"))
        (r (m/mergeRows b o t "baseline"))]
    (and r.conflict (stringContains? r.text "<<<<<<< ours") (stringContains? r.text "=======") (stringContains? r.text ">>>>>>> theirs")))
fn testIdentity -> Bool
  (let [(s "(:foreignAllowlist :v 1 :owner \"x\" :date \"d\" :doc \"h\"\n(:path \"a.c\" :kind :c)\n\n)")
        (r (m/mergeRows s s s "allowlist"))]
    (and (not r.conflict) (= r.text s)))
