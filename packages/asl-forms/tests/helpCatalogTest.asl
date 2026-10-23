(module asl-forms/tests/helpCatalogTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/search :a s) (asl-forms/tools :a t) (asl-ir/lower :a lo) (asl-forms/gate :a g)])

fn helpLine! ctx: s/KnowCtx name: String -> String
  (optionOr (listHead (t/helpStep! ctx 1 (mapSet (mapEmpty) "builtin" name) (list)).lines) "")

fn betweenAll text: String b: Bytes open: String close: String from: Int64 acc: (List String) -> (List String)
  (let [(at (k/findFrom text b open from))]
    (if (< at 0) (listReverse acc)
      (let [(a (+ at (stringLength open))) (e (k/findFrom text b close a))]
        (if (< e 0) (listReverse acc)
          (betweenAll text b open close (+ e (stringLength close)) (cons (optionOr (stringSlice text a e) "") acc))))))

fn listedNames line: String -> (List String)
  (betweenAll line (stringToBytes line) "(:name \"" "\"" 0 (list))

fn nativeBound? name: String -> Bool
  (or (some? (lo/builtinArity name)) (listContains? (list "parMap" "parFold") name))

fn probePath dir: String i: Int64 -> String
  (str dir "/p" (stringFromInt64 i) ".asl")

fn probeSource i: Int64 name: String -> String
  (str "(module helpProbe" (stringFromInt64 i) " :x [] :i [])\n\nfn ! probe -> Int64\n  (do (" name ") 0)\n")

fn rejectedAt text: String path: String -> Bool
  (listAny? (fn [(l String)] -> Bool (and (stringStartsWith? l (str path ":")) (or (stringContains? l "unbound symbol") (stringContains? l " parse ERR_")))) (stringSplit text "\n"))

; (:m :ref REDS-HELP-NATIVE :do "one module per listed name so a name the reader rejects (a retired spelling) condemns only itself; asl check judges them in a single call")
fn ! unbound! root: String dir: String names: (List String) -> (List String)
  (let [(indexed (enumerate names))
        (made (dirCreate dir))
        (written (map (fn [(ip (Pair Int64 String))] -> Bool (ok? (fileWrite (probePath dir (pairFirst ip)) (probeSource (pairFirst ip) (pairSecond ip))))) indexed))
        (out (g/runArgv! (listAppend (list "./bin/asl" "check") (map (fn [(ip (Pair Int64 String))] -> String (probePath dir (pairFirst ip))) indexed)) (some root) (none) 600000 0))
        (text (str out.out out.errText))
        (bad (map pairSecond (filter (fn [(ip (Pair Int64 String))] -> Bool (rejectedAt text (probePath dir (pairFirst ip)))) indexed)))
        (cleaned (map (fn [(ip (Pair Int64 String))] -> Bool (ok? (pathRemove (probePath dir (pairFirst ip))))) indexed))]
    (if (and (ok? made) (listAll? (fn [(w Bool)] -> Bool w) written) (listAll? (fn [(c Bool)] -> Bool c) cleaned) (ok? (pathRemove dir))) bad (cons "probe setup failed" bad)))

fn fixtureHelp! root: String rel: String from: String to: String needle: String -> String
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp/") "aslHelpCatalog_" (stringFromInt64 (mod (nowNs) 1000000000))))
        (copied (list "asl/prelude/prelude.asn" "asl/packages/asl-checker/src/types.asl"))
        (source (resultOr (fileReadString (k/joinPath root rel)) ""))
        (changed (stringReplace source from to))
        (made (list (dirCreate (k/joinPath dir "asl/prelude")) (dirCreate (k/joinPath dir "asl/packages/asl-checker/src"))))
        (written (map (fn [(path String)] -> (Result Unit String)
                        (fileWrite (k/joinPath dir path) (if (= path rel) changed (resultOr (fileReadString (k/joinPath root path)) ""))))
                      copied))
        (line (if (and (listAll? ok? made) (listAll? ok? written) (not (= changed source)))
                (helpLine! (s/KnowCtx :ws dir :toolRoot dir :binDir "" :vfsDir "" :toolsFile (k/joinPath root "asl/grammar/tools.asn") :home "") needle)
                "fixture setup failed"))
        (removed (pathRemove dir))]
    (if (ok? removed) line "fixture cleanup failed"))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (ctx (s/KnowCtx :ws root :toolRoot root :binDir "" :vfsDir "" :toolsFile "" :home ""))
        (preludeText (resultOr (fileReadString (k/joinPath root "asl/prelude/prelude.asn")) ""))
        (names (filter nativeBound? (betweenAll preludeText (stringToBytes preludeText) "(:name \"" "\"" 0 (list))))
        (tcp (helpLine! ctx "tcpConnect"))
        (fd (helpLine! ctx "fdPoll"))
        (readLine (helpLine! ctx "read-"))
        (missing (filter (fn [(name String)] -> Bool (not (stringContains? (helpLine! ctx name) ":status \"ok\""))) names))
        (listed (listedNames (helpLine! ctx "")))
        (probeDir (str (optionOr (envGet "TMPDIR") "/tmp/") "aslHelpProbe_" (stringFromInt64 (mod (nowNs) 1000000000))))
        (unboundListed (unbound! root probeDir listed))
        (probeGone (if (fileExists? probeDir) (pathRemove probeDir) (ok ())))
        (absentInPrelude (fixtureHelp! root "asl/prelude/prelude.asn" "    (:name \"+\" :sec" "    (:name \"read-all\" :sec \"I/O\" :type \"-> String\" :src \"asl/host/src/prelude.c\"\n      :doc \"fixture row for an :absent name\")\n    (:name \"+\" :sec" "read-"))
        (checkerIgnored (fixtureHelp! root "asl/packages/asl-checker/src/types.asl" "(= name \"stringLength\") (sigFn (list \"String\") \"Int64\")" "(= name \"stringLength\") (sigFn (list \"String\") \"FakeSignatureType\")" "stringLength"))]
    (do
      (println (str "(:helpCatalog :native " (stringFromInt64 (listLength names)) " :missing " (stringFromInt64 (listLength missing))
                    " :listed " (stringFromInt64 (listLength listed)) " :unbound " (stringFromInt64 (listLength unboundListed)) ")"))
      (assert (stringContains? tcp ":status \"ok\"") "checker-only tcpConnect is present")
      (assert (stringContains? tcp ":type \"Int64 -> (Result Int64 String)\"") "checker signature is shown")
      (assert (stringContains? tcp ":doc absent") "checker-only builtin has no doc")
      (assert (stringContains? fd ":status \"ok\"") "natively lowered fdPoll is present")
      (assert (not (listEmpty? names)) "prelude.asn lists natively lowered builtins")
      (assert (listEmpty? missing) (str "every natively lowered prelude builtin appears in help: " (stringJoin missing ",")))
      (assert (> (listLength listed) 100) (str "the full catalog lists builtins: " (stringFromInt64 (listLength listed))))
      (assert (ok? probeGone) "the binding probe module is removed")
      (assert (listEmpty? unboundListed) (str "every listed builtin is bound by asl check: " (stringJoin unboundListed ",")))
      (assert (not (stringContains? readLine "(:name \"read-line\"")) "an :absent name is not listed as a builtin")
      (assert (stringContains? readLine ":unbound (\"read-line\" \"read-all\")") "an :absent name is reported unbound")
      (assert (and (stringContains? absentInPrelude ":status \"ok\"") (not (stringContains? absentInPrelude "(:name \"read-all\""))) (str "an :absent name prelude.asn lists is not listed: " absentInPrelude))
      (assert (stringContains? checkerIgnored ":type \"String -> Int64\"") (str "a signature edited only in the tree's types.asl text is ignored: the linked asl-checker/types module is authoritative: " checkerIgnored))
      (assert (not (stringContains? checkerIgnored "FakeSignatureType")) "the tree's edited signature text never reaches the catalog")
      true))
