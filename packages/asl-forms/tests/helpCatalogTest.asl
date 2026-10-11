(module asl-forms/tests/helpCatalogTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/search :a s) (asl-forms/tools :a t) (asl-forms/gate :a g)])

fn quoteAt b: Bytes n: Int64 i: Int64 -> Int64
  (if (>= i n) -1 (if (= (bytesGet b i) 34) i (quoteAt b n (+ i 1))))

fn registrationNamesAt text: String b: Bytes from: Int64 acc: (List String) -> (List String)
  (let [(at (k/findFrom text b "{\"" from))]
    (if (< at 0) (listReverse acc)
      (let [(a (+ at 2)) (e (quoteAt b (stringLength text) a))]
        (if (< e 0) (listReverse acc)
          (registrationNamesAt text b (+ e 1)
            (if (and (< (+ e 1) (stringLength text)) (= (bytesGet b (+ e 1)) 44)) (cons (optionOr (stringSlice text a e) "") acc) acc))))))

fn registeredNames text: String -> (List String)
  (registrationNamesAt text (stringToBytes text) 0 (list))

fn betweenAll text: String b: Bytes open: String close: String from: Int64 acc: (List String) -> (List String)
  (let [(at (k/findFrom text b open from))]
    (if (< at 0) (listReverse acc)
      (let [(a (+ at (stringLength open))) (e (k/findFrom text b close a))]
        (if (< e 0) (listReverse acc)
          (betweenAll text b open close (+ e (stringLength close)) (cons (optionOr (stringSlice text a e) "") acc))))))

fn arrayNames text: String -> (List String)
  (let [(b (stringToBytes text))
        (suffixes (betweenAll text b "{#P \"" "\"" 0 (list)))
        (table (k/findFrom text b "arrayBuiltins[] = {" 0))
        (tableEnd (if (< table 0) -1 (k/findFrom text b "};" table)))
        (tableText (if (< tableEnd 0) "" (optionOr (stringSlice text table tableEnd) "")))
        (prefixes (betweenAll tableText (stringToBytes tableText) "ROWS(" ")" 0 (list)))]
    (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (map (fn [(s String)] -> String (str p s)) suffixes))) (list) prefixes))

fn tableNames path: String text: String -> (List String)
  (if (= path "asl/host/src/arrays.c")
    (arrayNames text)
    (let [(marker (cond ((= path "asl/host/src/prelude.c") "const Builtin coreBuiltins[] = {")
                        ((= path "asl/host/src/sys.c") "const Builtin sysBuiltins[] = {")
                        ((= path "asl/host/src/sysNet.c") "const Builtin sysNetBuiltins[] = {")
                        ((= path "asl/host/src/parallel.c") "const Builtin parallelBuiltins[] = {")
                        (else "const Builtin kernelBuiltins[] = {")))
          (b (stringToBytes text))
          (a (k/findFrom text b marker 0))
          (e (if (< a 0) -1 (k/findFrom text b "};" a)))]
      (if (or (< a 0) (< e 0)) (list) (registeredNames (optionOr (stringSlice text (+ a (stringLength marker)) e) "")))))

fn cNames! root: String paths: (List String) acc: (List String) -> (List String)
  (mt (listHead paths)
    ((none) (listSort (listReverse acc)))
    ((some path)
      (let [(source (resultOr (fileReadString (str root "/" path)) ""))]
        (cNames! root (optionOr (listTail paths) (list)) (listAppend (tableNames path source) acc)))))

fn helpLine! ctx: s/KnowCtx name: String -> String
  (optionOr (listHead (t/helpStep! ctx 1 (mapSet (mapEmpty) "builtin" name) (list)).lines) "")

fn listedNames line: String -> (List String)
  (betweenAll line (stringToBytes line) "(:name \"" "\"" 0 (list))

fn unknownSymbol? out: g/RunOut -> Bool
  (or (not (stringEmpty? out.failure)) (stringContains? (str out.out out.errText) "ERR_UNKNOWN_SYMBOL"))

fn unbound! host: String root: String probe: String names: (List String) -> (List String)
  (filter (fn [(name String)] -> Bool
            (and (unknownSymbol? (g/runArgv! (list host "eval" (str "(fn [] (" name "))")) (some root) (none) 10000 0))
                 (or (not (ok? (fileWrite probe (str "(module helpProbe :x [main] :i [(sys :a sys)])\nfn main -> Int64\n  (do (sys/" name ") 0)\n"))))
                     (unknownSymbol? (g/runArgv! (list host "run" probe) (some root) (none) 10000 0)))))
          names)

fn fixtureHelp! root: String rel: String from: String to: String needle: String -> String
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp/") "aslHelpCatalog_" (stringFromInt64 (mod (nowNs) 1000000000))))
        (copied (list "asl/prelude/prelude.asn" "asl/packages/asl-checker/src/types.asl" "asl/host/src/prelude.c" "asl/host/src/arrays.c"))
        (source (resultOr (fileReadString (k/joinPath root rel)) ""))
        (changed (stringReplace source from to))
        (made (list (dirCreate (k/joinPath dir "asl/prelude")) (dirCreate (k/joinPath dir "asl/packages/asl-checker/src")) (dirCreate (k/joinPath dir "asl/host/src"))))
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
        (host (k/joinPath root "asl/host/out/asl-host"))
        (paths (list "asl/host/src/prelude.c" "asl/host/src/sys.c" "asl/host/src/sysNet.c" "asl/host/src/arrays.c" "asl/host/src/parallel.c" "asl/host/src/kernels.c"))
        (names (cNames! root paths (list)))
        (tcp (helpLine! ctx "tcpConnect"))
        (fd (helpLine! ctx "fdPoll"))
        (readLine (helpLine! ctx "read-"))
        (missing (filter (fn [(name String)] -> Bool (not (stringContains? (helpLine! ctx name) ":status \"ok\""))) names))
        (listed (listedNames (helpLine! ctx "")))
        (probePath (str (optionOr (envGet "TMPDIR") "/tmp/") "aslHelpProbe_" (stringFromInt64 (mod (nowNs) 1000000000)) ".asl"))
        (unboundListed (unbound! host root probePath listed))
        (probeGone (if (fileExists? probePath) (pathRemove probePath) (ok ())))
        (probe (fixtureHelp! root "asl/host/src/arrays.c" "{#P \"ArrayScan\"" "{#P \"ArrayZzProbe\", P##Scan, 3, 0}, {#P \"ArrayScan\"" "ArrayZzProbe"))
        (absentInC (fixtureHelp! root "asl/host/src/prelude.c" "const Builtin coreBuiltins[] = {" "const Builtin coreBuiltins[] = {{\"read-line\", bList, -1, 0}, " "read-"))
        (absentInPrelude (fixtureHelp! root "asl/prelude/prelude.asn" "    (:name \"+\" :sec" "    (:name \"read-all\" :sec \"I/O\" :type \"-> String\" :src \"asl/host/src/prelude.c\"\n      :doc \"fixture row for an :absent name\")\n    (:name \"+\" :sec" "read-"))
        (checkerIgnored (fixtureHelp! root "asl/packages/asl-checker/src/types.asl" "(= name \"stringLength\") (sigFn (list \"String\") \"Int64\")" "(= name \"stringLength\") (sigFn (list \"String\") \"FakeSignatureType\")" "stringLength"))]
    (do
      (println (str "(:helpCatalog :registered " (stringFromInt64 (listLength names)) " :missing " (stringFromInt64 (listLength missing))
                    " :listed " (stringFromInt64 (listLength listed)) " :unbound " (stringFromInt64 (listLength unboundListed)) ")"))
      (assert (stringContains? tcp ":status \"ok\"") "checker-only tcpConnect is present")
      (assert (stringContains? tcp ":type \"Int64 -> (Result Int64 String)\"") "checker signature is shown")
      (assert (stringContains? tcp ":doc absent") "checker-only builtin has no doc")
      (assert (stringContains? fd ":status \"ok\"") "host-registered fdPoll is present")
      (assert (not (listEmpty? names)) "the six host registration tables contain builtin rows")
      (assert (listEmpty? missing) (str "every C table builtin appears in help: " (stringJoin missing ",")))
      (assert (> (listLength listed) 100) (str "the full catalog lists builtins: " (stringFromInt64 (listLength listed))))
      (assert (ok? probeGone) "the binding probe module is removed")
      (assert (listEmpty? unboundListed) (str "every listed builtin is bound by asl-host: " (stringJoin unboundListed ",")))
      (assert (not (stringContains? readLine "(:name \"read-line\"")) "an :absent name is not listed as a builtin")
      (assert (stringContains? readLine ":unbound (\"read-line\" \"read-all\")") "an :absent name is reported unbound")
      (assert (and (stringContains? absentInC ":status \"ok\"") (not (stringContains? absentInC "(:name \"read-line\""))) (str "an :absent name a host table registers is not listed: " absentInC))
      (assert (stringContains? absentInC ":unbound (\"read-line\" \"read-all\")") "a host-registered :absent name is still reported unbound")
      (assert (and (stringContains? absentInPrelude ":status \"ok\"") (not (stringContains? absentInPrelude "(:name \"read-all\""))) (str "an :absent name prelude.asn lists is not listed: " absentInPrelude))
      (assert (stringContains? probe ":count 3") (str "a new arrays.c ROWS row appears under each prefix: " probe))
      (assert (stringContains? probe "(:name \"i8ArrayZzProbe\"") "the i8 prefix of the new ROWS row is listed")
      (assert (stringContains? checkerIgnored ":type \"String -> Int64\"") (str "a signature edited only in the tree's types.asl text is ignored: the linked asl-checker/types module is authoritative: " checkerIgnored))
      (assert (not (stringContains? checkerIgnored "FakeSignatureType")) "the tree's edited signature text never reaches the catalog")
      true))
