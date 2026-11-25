(module asl-compiler/tests/checkCacheTest
  :x [runTests]
  :i [(asl-compiler/checkCache :a cc) (asl-tools/fleet/run :a fr) (asl-tools/nativeTest :a nt)])

fn asl1 -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn ! asl1Bin! -> String
  (let [(built (nt/prepareRun (asl1) (nt/fingerprint)))]
    (match built.binary
      ((some bin) bin)
      ((none) (do (assert false (str "asl1.asl builds natively: " built.reason)) ""))))


fn depOk -> String
  "(module dep :x [value] :i [])\n\nfn value -> Int64\n  41\n"

fn depHidden -> String
  "(module dep :x [] :i [])\n\nfn value -> Int64\n  41\n"

fn mainSource -> String
  "(module main :x [answer] :i [(dep :a d)])\n\nfn answer -> Int64\n  (+ (d/value) 1)\n"

fn badSource -> String
  "(module bad :x [f] :i [])\n\nfn f -> Int64\n  (undefinedThing 1)\n"

fn ! check cache: String entry: String -> fr/Done
  (fr/runOneLimited (fr/job (list (asl1Bin!) "check" entry) "." (fr/childEnv (list (str "ASL_CHECK_CACHE=" cache)))) (fr/limits 300 16))

fn ! entriesIn dir: String -> (List String)
  (match (dirList dir)
    ((err _) (list))
    ((ok names) (filter (fn [(n String)] -> Bool (stringEndsWith? n ".verdict")) names)))

fn ! onlyEntry dir: String -> String
  (let [(names (entriesIn dir))]
    (if (= (listLength names) 1) (str dir "/" (optionOr (listHead names) "")) ""))

fn keyOf path: String -> String
  (stringReplace (optionOr (listLast (stringSplit path "/")) "") ".verdict" "")

fn testDecode -> Bool
  (let [(v (cc/Verdict :exitCode 1 :body "a.asl:1:1: [rule-2] x is not defined\n"))
        (text (cc/encodeVerdict "k1" v))
        (back (cc/decodeVerdict "k1" text))]
    (do (assert (some? back) "an encoded verdict decodes under its own key")
        (assert (= (optionOr (optionMap (fn [(d cc/Verdict)] -> String d.body) back) "") v.body) "the decoded body is byte for byte the stored one")
        (assert (= (optionOr (optionMap (fn [(d cc/Verdict)] -> Int64 d.exitCode) back) 9) 1) "the decoded exit code is the stored one")
        (assert (none? (cc/decodeVerdict "k2" text)) "a verdict stored under another key is a miss")
        (assert (none? (cc/decodeVerdict "k1" (stringReplace text "x is" "y is"))) "a body that does not match its digest is a miss")
        (assert (none? (cc/decodeVerdict "k1" (optionOr (stringSlice text 0 30) ""))) "a truncated entry is a miss")
        (assert (none? (cc/decodeVerdict "k1" "garbage")) "garbage is a miss")
        (assert (none? (cc/decodeVerdict "k1" (stringReplace text "\n1\n" "\nx\n"))) "a non-integer exit code is a miss")
        true))

fn ! testColdWarmIdentical work: String -> Bool
  (let [(cache (str work "/cacheBad"))
        (bad (str work "/bad.asl"))
        (written (fileWrite bad (badSource)))
        (cold (check cache bad))
        (stored (entriesIn cache))
        (warm (check cache bad))]
    (do (assert (ok? written) "bad.asl fixture written")
        (assert (= cold.exit 1) (str "cold check of an unbound symbol exits 1, got " cold.exit))
        (assert (stringContains? cold.out (str bad ":4:4: [ERR_UNKNOWN_SYMBOL] unbound symbol: undefinedThing\n")) (str "cold check prints the diagnostic: " cold.out))
        (assert (= (listLength stored) 1) (str "the cold run stores one verdict, got " (listLength stored)))
        (assert (= warm.exit cold.exit) (str "warm exit equals cold exit, got " warm.exit))
        (assert (= warm.out cold.out) (str "warm diagnostics equal cold ones byte for byte: " warm.out))
        true))

fn ! testDependencyEditFlips work: String -> Bool
  (let [(cache (str work "/cacheDep"))
        (dep (str work "/dep.asl"))
        (main (str work "/main.asl"))
        (w1 (fileWrite dep (depOk)))
        (w2 (fileWrite main (mainSource)))
        (cold (check cache main))
        (warm (check cache main))
        (w3 (fileWrite dep (depHidden)))
        (edited (check cache main))
        (again (check cache main))]
    (do (assert (and (ok? w1) (ok? w2)) "dep.asl and main.asl fixtures written")
        (assert (= cold.exit 0) (str "main checks clean cold: " cold.out))
        (assert (= warm.exit 0) (str "and warm: " warm.out))
        (assert (ok? w3) "dep.asl edited to stop exporting value")
        (assert (= edited.exit 1) (str "after the dependency edit the warm cache is not replayed: main fails, got exit " edited.exit))
        (assert (stringContains? edited.out "ERR_NOT_EXPORTED: value is not exported by dep") (str "with the checker's diagnostic: " edited.out))
        (assert (= again.out edited.out) (str "the new verdict replays identically: " again.out))
        (assert (= (listLength (entriesIn cache)) 2) "each dependency state has its own verdict")
        true))

fn ! testReplayFromEntry work: String -> Bool
  (let [(cache (str work "/cacheForge"))
        (entry (str work "/forged.asl"))
        (written (fileWrite entry (depOk)))
        (cold (check cache entry))
        (path (onlyEntry cache))
        (body "forged.asl:9:9: [sentinel] replayed from the cache\n")
        (forged (fileWrite path (cc/encodeVerdict (keyOf path) (cc/Verdict :exitCode 1 :body body))))
        (warm (check cache entry))]
    (do (assert (ok? written) "forged.asl fixture written")
        (assert (= cold.exit 0) (str "the clean fixture checks clean cold: " cold.out))
        (assert (not (stringEmpty? path)) "the cold run stored one verdict")
        (assert (ok? forged) "a well-formed sentinel verdict replaces it")
        (assert (= warm.exit 1) (str "the warm run exits with the stored code, got " warm.exit))
        (assert (= warm.out body) (str "the warm run replays the stored diagnostics byte for byte: " warm.out))
        true))

fn ! testCorruptEntryIsMiss work: String -> Bool
  (let [(cache (str work "/cacheCorrupt"))
        (bad (str work "/corrupt.asl"))
        (written (fileWrite bad (badSource)))
        (cold (check cache bad))
        (path (onlyEntry cache))
        (broken (fileWrite path "aslCheckVerdict 1\nnot a verdict"))
        (warm (check cache bad))
        (repaired (fileReadString path))]
    (do (assert (ok? written) "corrupt.asl fixture written")
        (assert (= cold.exit 1) (str "the fixture fails cold, got " cold.exit))
        (assert (not (stringEmpty? path)) "the cold run stored one verdict")
        (assert (ok? broken) "the verdict is overwritten with a corrupt one")
        (assert (= warm.exit cold.exit) (str "a corrupt verdict is a miss, not an error: exit " warm.exit))
        (assert (= warm.out cold.out) (str "and the cold diagnostics come back: " warm.out))
        (assert (some? (cc/decodeVerdict (keyOf path) (resultOr repaired ""))) "the miss rewrote a valid verdict")
        (assert (listEmpty? (filter (fn [(n String)] -> Bool (stringContains? n ".tmp.")) (resultOr (dirList cache) (list "x.tmp.")))) "no temporary file is left behind")
        true))

fn ! testWarmFaster work: String -> Bool
  (let [(cache (str work "/cacheSelf"))
        (cold (check cache (asl1)))
        (warm (check cache (asl1)))
        (path (onlyEntry cache))]
    (do (assert (= cold.exit 0) (str "asl1.asl checks clean cold: " cold.out))
        (assert (= warm.exit 0) (str "and warm: " warm.out))
        (assert (= warm.out cold.out) "warm output equals cold output")
        (assert (some? (cc/decodeVerdict (keyOf path) (resultOr (fileReadString path) ""))) "the verdict for asl1.asl is stored")
        (assert (< (* warm.ms 3) (* cold.ms 2)) (str "the warm check of asl1.asl takes under two-thirds of the cold one (1.5x floor, native startup cost included): warm " warm.ms " ms, cold " cold.ms " ms"))
        true))

; (:m :ref CHECK-VERDICT-RELPATH :do "the key follows content, not the tree path: two roots with equal files key equal and share one verdict, an edit to a closure file changes the key")
fn rn s: String -> String
  (stringReplace (stringReplace s "module dep " "module depR ") "(dep :a d)" "(depR :a d)")

fn ! testKeyIgnoresRoot work: String -> Bool
  (let [(cache (str work "/cacheRoots"))
        (a (str work "/rootA"))
        (b (str work "/rootB"))
        (m1 (dirCreate a))
        (m2 (dirCreate b))
        (c1 (fileWrite (str a "/.asl.config.asn") "(:aslConfig :workspace \"fx\")\n"))
        (c2 (fileWrite (str b "/.asl.config.asn") "(:aslConfig :workspace \"fx\")\n"))
        (w1 (fileWrite (str a "/depR.asl") (rn (depOk))))
        (w2 (fileWrite (str a "/main.asl") (rn (mainSource))))
        (w3 (fileWrite (str b "/depR.asl") (rn (depOk))))
        (w4 (fileWrite (str b "/main.asl") (rn (mainSource))))
        (ra (check cache (str a "/main.asl")))
        (rb (check cache (str b "/main.asl")))
        (shared (listLength (entriesIn cache)))
        (w5 (fileWrite (str b "/depR.asl") (rn (depHidden))))
        (rc (check cache (str b "/main.asl")))]
    (do (assert (and (ok? w1) (and (ok? w2) (and (ok? w3) (and (ok? w4) (and (ok? m1) (ok? m2)))))) "two fixture roots written")
        (assert (= ra.exit 0) (str "root A checks clean: " ra.out))
        (assert (= rb.exit 0) (str "root B checks clean: " rb.out))
        (assert (= shared 1) (str "two roots share one verdict, got " shared))
        (assert (ok? w5) "depR.asl edited in root B")
        (assert (= rc.exit 1) (str "the edited closure is not replayed: exit " rc.exit))
        (assert (= (listLength (entriesIn cache)) 2) "a content change in a closure file changes the key: a second verdict")
        true))

; (:m :ref CHECK-VERDICT-RELPATH :do "a verdict stored by root C replays in root D with D's paths in its diagnostics, never C's")
fn ! testReplayNamesAskingRoot work: String -> Bool
  (let [(cache (str work "/cacheAsk"))
        (c (str work "/rootC"))
        (d (str work "/rootD"))
        (m1 (dirCreate c))
        (m2 (dirCreate d))
        (c1 (fileWrite (str c "/.asl.config.asn") "(:aslConfig :workspace \"fx\")\n"))
        (c2 (fileWrite (str d "/.asl.config.asn") "(:aslConfig :workspace \"fx\")\n"))
        (w1 (fileWrite (str c "/bad.asl") (badSource)))
        (w2 (fileWrite (str d "/bad.asl") (badSource)))
        (rc (check cache (str c "/bad.asl")))
        (stored (listLength (entriesIn cache)))
        (rd (check cache (str d "/bad.asl")))
        (after (listLength (entriesIn cache)))]
    (do (assert (and (ok? m1) (and (ok? m2) (and (ok? c1) (and (ok? c2) (and (ok? w1) (ok? w2)))))) "two failing fixture roots written")
        (assert (and (= rc.exit 1) (= stored 1)) (str "root C fails and stores one verdict: " rc.out))
        (assert (= rd.exit 1) (str "root D replays the failure: " rd.out))
        (assert (= after 1) (str "root D is a hit, no new verdict, got " after))
        (assert (stringContains? rd.out (str d "/bad.asl:4:4: [ERR_UNKNOWN_SYMBOL]")) (str "the replayed diagnostic names root D: " rd.out))
        (assert (not (stringContains? rd.out c)) (str "and never root C: " rd.out))
        true))

; (:m :ref CHECK-VERDICT-RELPATH :do "identical failing files at different paths in one tree keep separate verdicts and each replay names its own file")
fn ! testSamePathsDiffer work: String -> Bool
  (let [(cache (str work "/cacheTwin"))
        (root (str work "/rootT"))
        (m1 (dirCreate root))
        (m2 (dirCreate (str root "/a")))
        (m3 (dirCreate (str root "/b")))
        (c1 (fileWrite (str root "/.asl.config.asn") "(:aslConfig :workspace \"fx\")\n"))
        (w1 (fileWrite (str root "/a/bad.asl") (badSource)))
        (w2 (fileWrite (str root "/b/bad.asl") (badSource)))
        (ra (check cache (str root "/a/bad.asl")))
        (rb (check cache (str root "/b/bad.asl")))
        (n (listLength (entriesIn cache)))]
    (do (assert (and (ok? m1) (and (ok? m2) (and (ok? m3) (and (ok? c1) (and (ok? w1) (ok? w2)))))) "twin fixtures written")
        (assert (= n 2) (str "two identical files at different paths give two verdicts, got " n))
        (assert (stringContains? ra.out (str root "/a/bad.asl:4:4")) (str "a names a: " ra.out))
        (assert (stringContains? rb.out (str root "/b/bad.asl:4:4")) (str "b names b: " rb.out))
        (assert (not (stringContains? rb.out "/a/bad.asl")) (str "b never names a: " rb.out))
        true))

fn ! runTests -> Bool
  (let [(made (fr/shellOut "d=$(mktemp -d) && cd \"$d\" && pwd -P" 10000))
        (work (stringTrim (resultOr made "")))]
    (do (assert (and (ok? made) (not (stringEmpty? work))) "mktemp -d makes a work directory")
        (assert (ok? (fileWrite (str work "/.asl.config.asn") "(:aslConfig :workspace \"fx\")\n")) "fixture workspace config written")
        (assert (testDecode) "testDecode")
        (assert (testColdWarmIdentical work) "testColdWarmIdentical")
        (assert (testDependencyEditFlips work) "testDependencyEditFlips")
        (assert (testReplayFromEntry work) "testReplayFromEntry")
        (assert (testCorruptEntryIsMiss work) "testCorruptEntryIsMiss")
        (assert (testWarmFaster work) "testWarmFaster")
        (assert (testKeyIgnoresRoot work) "testKeyIgnoresRoot")
        (assert (testReplayNamesAskingRoot work) "testReplayNamesAskingRoot")
        (assert (testSamePathsDiffer work) "testSamePathsDiffer")
        (assert (ok? (fr/shellOut (str "rm -rf '" work "'") 10000)) "work directory removed")
        true))
