(module asl-compiler/tests/checkCacheTest
  :x [runTests]
  :i [(asl-compiler/checkCache :a cc) (tools/fleet/run :a fr) (tools/nativeTest :a nt)])

fn asl1 -> String
  "asl/packages/asl-compiler/src/asl1.asl"

fn ! asl1Bin! -> String
  (let [(built (nt/prepareRun (asl1) (nt/fingerprint)))]
    (mt built.binary
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
  (mt (dirList dir)
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
        (assert (ok? (fr/shellOut (str "rm -rf '" work "'") 10000)) "work directory removed")
        true))
