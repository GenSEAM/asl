(module asl/agentLoop/tests/leonPoolTest
  :x [runTests]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/leonPool :a lp) (asl/agentLoop/sessionPool :a sp)
      (asl/agentLoop/providers :a pv) (asl-tools/fleet/run :a fr)])

; (:m :ref SE3-POOL-DRIVER :do "the same scripted run (write blue, write green and done, gate grep) goes once through the blocking path (mainWithRoots) and once through the pool driver in one process; their journals are byte-identical once the session id is replaced; 8 such runs share one pool and all end ok")
fn ! sh! cmd: String -> Bool
  (ok? (fr/shellOut cmd 20000))

fn ! prepRoot! root: String -> Bool
  (and (sh! (str "/bin/mkdir -p " root "/tests/fixtures/agentLoop/mvp"))
    (and (ok? (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))\n"))
      (and (sh! (str "/bin/cp asl/agentLoop/tests/fixtures/liveLoop/edit.asn " root "/tests/fixtures/agentLoop/mvp/edit.asn"))
        (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
          (sh! (str "cd " root " && git init -q -b main && git config user.name leonPool && git config user.email leon-pool@example.invalid && git add -- subject.txt && git commit -q -m initial"))))))

fn form -> String
  "(:agent :task \"write then gate\" :backend \"script/edit\" :mode \"implement\" :owns (\"subject.txt\") :gates (\"grep -qx green subject.txt\"))"

fn fieldAfter text: String key: String -> String
  (match (stringIndexOf text key)
    ((none) "")
    ((some at)
      (let [(rest (optionOr (stringSlice text (+ at (stringLength key)) (stringLength text)) ""))]
        (match (stringIndexOf rest "\"") ((some e) (optionOr (stringSlice rest 0 e) "")) ((none) "")))))

; (:m :ref SE3-POOL-DRIVER :do "a receipt id is a fresh hash per write, so it is masked; every other byte of the journal is compared")
fn quoteChar? c: String -> Bool
  (or (= c "\\") (= c "\""))

fn skipQuotes text: String at: Int64 -> Int64
  (if (quoteChar? (optionOr (stringSlice text at (+ at 1)) "")) (skipQuotes text (+ at 1)) at)

fn maskIds text: String -> String
  (match (stringIndexOf text ":receipt :id ")
    ((none) text)
    ((some at)
      (let [(from (skipQuotes text (+ at 13)))]
        (str (optionOr (stringSlice text 0 from) "") "IDMASKED" (maskIds (optionOr (stringSlice text (+ from 16) (stringLength text)) ""))))))

fn journalOf root: String sid: String -> String
  (maskIds (stringReplace (stringReplace (resultOr (fileReadString (str root "/.asl/run/agentLoop/" sid ".journal")) "") sid "SID") root "ROOT"))

fn onlyIn a: String b: String -> (List String)
  (let [(other (stringSplit b "\n"))]
    (filter (fn [(l String)] -> Bool (not (listContains? other l))) (stringSplit a "\n")))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn sidOfPath path: String -> String
  (stringReplace (optionOr (listLast (stringSplit path "/")) "") ".journal" "")

fn ! pump! p: sp/Pool book: (List (Pair String lp/Live)) deadline: Int64 -> (Pair sp/Pool (List (Pair String lp/Live)))
  (if (or (sp/poolIdle? p) (>= (nowMs!) deadline)) (pair p book)
    (match (fdPoll (sp/poolWatch p) 10)
      ((err _) (pump! p book deadline))
      ((ok ready)
        (let [(stepped (sp/poolStepG! p ready lp/leonTurn! book (nowMs!)))]
          (pump! (pairFirst stepped) (pairSecond stepped) deadline)))))

fn ! openAll! book: (List (Pair String lp/Live)) p: sp/Pool roots: (List String) repoRoot: String -> (Pair sp/Pool (List (Pair String lp/Live)))
  (fold (fn [(acc (Pair sp/Pool (List (Pair String lp/Live)))) (root String)] -> (Pair sp/Pool (List (Pair String lp/Live)))
          (let [(id (stringReplace root "/" "_"))
                (opened (lp/leonOpen! (pairSecond acc) id (form) repoRoot root (pv/providerEnv! root)))]
            (match (pairSecond opened)
              ((some _) (pair (pairFirst acc) (pairFirst opened)))
              ((none) (pair (sp/poolSubmit! (pairFirst acc) id id (nowMs!)) (pairFirst opened))))))
    (pair p book) roots)

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/leonPoolTest.XXXXXX" 5000) "")))
        (repoRoot (resultOr (realPath ".") "."))
        (blockRoot (str temp "/block"))
        (oneRoot (str temp "/one"))
        (manyRoots (map (fn [(i Int64)] -> String (str temp "/many" (stringFromInt64 i))) (range 0 8)))
        (prepared (and (prepRoot! blockRoot) (and (prepRoot! oneRoot) (listAll? (fn [(r String)] -> Bool (prepRoot! r)) manyRoots))))
        (blocked (m/mainWithRoots (list (form)) repoRoot blockRoot))
        (blockSid (fieldAfter blocked.stdout ":session \""))
        (blockJournal (journalOf blockRoot blockSid))
        (sock (str temp "/none.sock"))
        (spill (str temp "/spill"))
        (made (dirCreate spill))
        (oneId (stringReplace oneRoot "/" "_"))
        (t1 (nowMs!))
        (oneOpen (openAll! (list) (sp/newPool sock 8 64 60000 spill) (list oneRoot) repoRoot))
        (oneOut (pump! (pairFirst oneOpen) (pairSecond oneOpen) (+ (nowMs!) 120000)))
        (oneWall (- (nowMs!) t1))
        (oneLive (listFind (fn [(e (Pair String lp/Live))] -> Bool (= (pairFirst e) oneId)) (pairSecond oneOut)))
        (oneSid (match oneLive ((some e) (sidOfPath (pairSecond e).sess.path)) ((none) "")))
        (oneJournal (journalOf oneRoot oneSid))
        (manyOpen (openAll! (list) (sp/newPool sock 8 64 60000 spill) manyRoots repoRoot))
        (manyOut (pump! (pairFirst manyOpen) (pairSecond manyOpen) (+ (nowMs!) 300000)))
        (manyDone (sp/poolDone (pairFirst manyOut)))
        (manyExits (map (fn [(r String)] -> Int64 (lp/leonExit (pairSecond manyOut) (stringReplace r "/" "_"))) manyRoots))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert prepared "fixture roots prepared")
      (assert (= blocked.exitCode 0) (str "the blocking run ends ok: " blocked.stdout))
      (assert (and (not (stringEmpty? oneSid)) (not (stringEmpty? blockJournal))) "both runs left a journal")
      (assert (= oneJournal blockJournal) (str "journals byte-identical: blocking " (stringFromInt64 (stringLength blockJournal)) " chars, pool " (stringFromInt64 (stringLength oneJournal)) " chars\n--- only blocking\n" (stringJoin (onlyIn blockJournal oneJournal) "\n") "\n--- only pool\n" (stringJoin (onlyIn oneJournal blockJournal) "\n")))
      (assert (= (listLength manyDone) 8) (str "8 runs in one pool all finished: " (stringFromInt64 (listLength manyDone))))
      (assert (listAll? (fn [(x Int64)] -> Bool (= x 0)) manyExits) "all 8 runs ended with exit 0")
      (assert removed "temp dir removed")
      true))
