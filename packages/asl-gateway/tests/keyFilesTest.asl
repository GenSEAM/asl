(module aslGateway/tests/keyFilesTest
  :x [runTests]
  :i [(config :a cfg)
      (asl-tools/fleet/run :a fr)
      (asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)])

; (:m :ref GW-KEYSTORE-20261019 :do "covers config.asl's resolveProviderKey!/keyFileLookup!/gatewayKeyFilesFromProps/expandUserPath directly (no process boundary needed, since they take their inputs as plain parameters), plus two end-to-end checks: a real child ./bin/asl process proves the file-before-env precedence against a genuinely different process environment it cannot fake by sharing this test's own env, and gateway_config_parse! proves the config check accepts a key found only in a listed file and names both the env var and the files searched when neither has it")

fn ! hostExe! -> String
  (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl"))

fn quoteStr s: String -> String
  (str "\"" s "\"")

fn keyFilesFormOf paths: (List String) -> String
  (str "(list " (stringJoin (map quoteStr paths) " ") ")")

fn probeScript paths: (List String) keyEnv: String -> String
  (str "(module gwkeysProbe\n  :x [main]\n  :i [(aslGateway/config :a cfg)])\n\n"
       "fn ! main args: (List String) -> (Result Unit IoError)\n"
       "  (do (println (optionOr (cfg/resolveProviderKey! " (keyFilesFormOf paths) " \"" keyEnv "\") \"ABSENT\")) (ok ()))\n")

fn ! probe! root: String tag: String paths: (List String) keyEnv: String envOverrides: (List String) -> String
  (let [(script (str root "/" tag ".asl"))
        (_ (fileWrite script (probeScript paths keyEnv)))
        (out (fr/runGuarded (list (hostExe!) "run" script) (resultOr (realPath ".") ".") (fr/childEnv envOverrides) (fr/limits 30 50)))]
    (stringTrim out.stdout))

fn ! testFileWinsOverEnv! root: String -> Bool
  (let [(keyFile (str root "/fileWins.env"))
        (_ (fileWrite keyFile "export GWKEYS_TEST_PROBE=\"from-file\"\n"))
        (got (probe! root "fileWins" (list keyFile) "GWKEYS_TEST_PROBE" (list "GWKEYS_TEST_PROBE=from-env")))]
    (assert (= got "from-file") (str "a key present in a listed file wins over a different value of the same name in the process environment, got " got))
    (= got "from-file"))

fn ! testFileAbsentFallsBackToEnv! root: String -> Bool
  (let [(got (probe! root "envFallback" (list (str root "/noSuchFile.env")) "GWKEYS_TEST_PROBE" (list "GWKEYS_TEST_PROBE=from-env")))]
    (assert (= got "from-env") (str "a key file that does not exist is skipped, not an error, falling back to the process environment, got " got))
    (= got "from-env"))

fn ! testFileLacksKeyFallsBackToEnv! root: String -> Bool
  (let [(keyFile (str root "/other.env"))
        (_ (fileWrite keyFile "OTHER_NAME=irrelevant\n"))
        (got (probe! root "envFallback2" (list keyFile) "GWKEYS_TEST_PROBE" (list "GWKEYS_TEST_PROBE=from-env")))]
    (assert (= got "from-env") (str "a key file present but lacking the name falls back to the process environment, got " got))
    (= got "from-env"))

fn ! testBothAbsentYieldsNone! root: String -> Bool
  (let [(got (probe! root "bothAbsent" (list (str root "/noSuchFile2.env")) "GWKEYS_TEST_PROBE_UNSET_XYZ" (list)))]
    (assert (= got "ABSENT") (str "neither a key file nor the process environment having the name resolves to none, got " got))
    (= got "ABSENT"))

fn ! testFilesInOrderFirstWins! root: String -> Bool
  (let [(first (str root "/order1.env"))
        (second (str root "/order2.env"))
        (_ (fileWrite first "GWKEYS_TEST_PROBE=\"first\"\n"))
        (_ (fileWrite second "GWKEYS_TEST_PROBE=\"second\"\n"))
        (fwd (optionOr (cfg/keyFileLookup! (list first second) "GWKEYS_TEST_PROBE") ""))
        (rev (optionOr (cfg/keyFileLookup! (list second first) "GWKEYS_TEST_PROBE") ""))]
    (assert (= fwd "first") (str "keyFileLookup! returns the first listed file's value when both define the name, got " fwd))
    (assert (= rev "second") (str "reversing the list order reverses which file wins, got " rev))
    (and (= fwd "first") (= rev "second")))

fn ! testKeyFileLookupSkipsMissingThenFindsNext! root: String -> Bool
  (let [(present (str root "/order3.env"))
        (_ (fileWrite present "GWKEYS_TEST_PROBE=\"third\"\n"))
        (got (optionOr (cfg/keyFileLookup! (list (str root "/missingFirst.env") present) "GWKEYS_TEST_PROBE") ""))]
    (assert (= got "third") (str "a missing earlier file is skipped and the next listed file is still consulted, got " got))
    (= got "third"))

fn ! testKeyFileLookupNoneOnEmptyList -> Bool
  (let [(got (cfg/keyFileLookup! (list) "GWKEYS_TEST_PROBE"))]
    (assert (none? got) "an empty key-file list resolves to none, leaving the caller to fall back to the environment")
    (none? got))

fn testExpandUserPath -> Bool
  (let [(home (optionOr (envGet "HOME") ""))
        (tilde (cfg/expandUserPath "~"))
        (tildeSlash (cfg/expandUserPath "~/.asl/keys.env"))
        (absolute (cfg/expandUserPath "/tmp/plain/keys.env"))]
    (do
      (assert (= tilde home) (str "bare ~ expands to HOME, got " tilde))
      (assert (= tildeSlash (str home "/.asl/keys.env")) (str "~/... expands against HOME, got " tildeSlash))
      (assert (= absolute "/tmp/plain/keys.env") "a path with no leading ~ passes through unchanged")
      (and (= tilde home) (and (= tildeSlash (str home "/.asl/keys.env")) (= absolute "/tmp/plain/keys.env")))))

fn testGatewayKeyFilesFromPropsParsesList -> Bool
  (let [(text "(:gateway :v 2 :profile p1 :keyFiles (\"/a/one.env\" \"/b/two.env\")\n  :profiles ((:profile :id p1 :routes ((:intent any :chain ())))))")
        (parsed (ast/readForms (lx/tokenize text)))]
    (match parsed
      ((err e) (do (assert false (str "fixture text must parse: " e)) false))
      ((ok forms)
        (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
          (match (cfg/asn_props top (some ":gateway"))
            ((err e) (do (assert false (str "fixture props must parse: " e)) false))
            ((ok g)
              (let [(got (cfg/gatewayKeyFilesFromProps g))]
                (do (assert (= got (list "/a/one.env" "/b/two.env")) (str "keyFiles props parse to the ordered path list, got " (stringJoin got ",")))
                    (= got (list "/a/one.env" "/b/two.env"))))))))))

fn testGatewayKeyFilesFromPropsAbsentIsEmpty -> Bool
  (let [(text "(:gateway :v 2 :profile p1\n  :profiles ((:profile :id p1 :routes ((:intent any :chain ())))))")
        (parsed (ast/readForms (lx/tokenize text)))]
    (match parsed
      ((err e) (do (assert false (str "fixture text must parse: " e)) false))
      ((ok forms)
        (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
          (match (cfg/asn_props top (some ":gateway"))
            ((err e) (do (assert false (str "fixture props must parse: " e)) false))
            ((ok g)
              (let [(got (cfg/gatewayKeyFilesFromProps g))]
                (do (assert (listEmpty? got) "no :keyFiles form means an empty search list, never a guess")
                    (listEmpty? got)))))))))

fn ! testMissingKeyNamesFilesAndEnv! -> Bool
  (let [(text (str "(:gateway :v 2 :keyFiles (\"/tmp/gwkeysTestAbsentDirXyz/keys.env\")\n"
                    "  :providers ((:provider :id probe :kind openai :base \"https://example.test/v1\" :keyEnv \"GWKEYS_TEST_PROBE_UNSET_CFG\"))\n"
                    "  :models ((:model :id probeModel :provider probe :name \"probe-model\"))\n"
                    "  :profiles ((:profile :id p1 :routes ((:intent any :chain (probeModel)))))\n"
                    "  :uses ((:use :for default :profile p1)))\n"))
        (parsed (cfg/gateway_config_parse! text "keyFilesTest" ".asl/mem/calibration/index.asn"))]
    (match parsed
      ((err e) (do (assert false (str "a missing key is a warning on the parsed table, not a hard parse failure: " e)) false))
      ((ok tbl)
        (let [(w (stringJoin tbl.warnings "; "))]
          (do
            (assert (stringContains? w "GWKEYS_TEST_PROBE_UNSET_CFG") (str "the warning names the env var searched: " w))
            (assert (stringContains? w "/tmp/gwkeysTestAbsentDirXyz/keys.env") (str "the warning names the key file searched: " w))
            (and (stringContains? w "GWKEYS_TEST_PROBE_UNSET_CFG") (stringContains? w "/tmp/gwkeysTestAbsentDirXyz/keys.env")))))))

fn ! testFileSatisfiesConfigCheck! root: String -> Bool
  (let [(keyFile (str root "/cfgOk.env"))
        (_ (fileWrite keyFile "GWKEYS_TEST_PROBE_CFG_OK=anything\n"))
        (text (str "(:gateway :v 2 :keyFiles (\"" keyFile "\")\n"
                    "  :providers ((:provider :id probe :kind openai :base \"https://example.test/v1\" :keyEnv \"GWKEYS_TEST_PROBE_CFG_OK\"))\n"
                    "  :models ((:model :id probeModel :provider probe :name \"probe-model\"))\n"
                    "  :profiles ((:profile :id p1 :routes ((:intent any :chain (probeModel)))))\n"
                    "  :uses ((:use :for default :profile p1)))\n"))
        (parsed (cfg/gateway_config_parse! text "keyFilesTest" ".asl/mem/calibration/index.asn"))]
    (match parsed
      ((err e) (do (assert false (str "a key present in a listed key file must satisfy the config check: " e)) false))
      ((ok tbl)
        (do
          (assert (listEmpty? tbl.warnings) (str "no key-env warning once the key file supplies the key: " (stringJoin tbl.warnings "; ")))
          (assert (= tbl.keyFiles (list keyFile)) "the parsed table carries its own :keyFiles list forward for call-time resolution")
          (and (listEmpty? tbl.warnings) (= tbl.keyFiles (list keyFile)))))))

fn ! runTests -> Bool
  (let [(root (str "/tmp/asl-gwkeys-fixture-" (stringFromInt64 (nowNs))))
        (_ (dirCreate root))
        (r1 (testFileWinsOverEnv! root))
        (r2 (testFileAbsentFallsBackToEnv! root))
        (r3 (testFileLacksKeyFallsBackToEnv! root))
        (r4 (testBothAbsentYieldsNone! root))
        (r5 (testFilesInOrderFirstWins! root))
        (r6 (testKeyFileLookupSkipsMissingThenFindsNext! root))
        (r7 (testKeyFileLookupNoneOnEmptyList))
        (r8 (testExpandUserPath))
        (r9 (testGatewayKeyFilesFromPropsParsesList))
        (r10 (testGatewayKeyFilesFromPropsAbsentIsEmpty))
        (r11 (testMissingKeyNamesFilesAndEnv!))
        (r12 (testFileSatisfiesConfigCheck! root))
        (_ (fr/shellOut (str "rm -rf " root) 5000))]
    (do
      (assert r1 "file-wins-over-env end to end")
      (assert r2 "missing-file falls back to env end to end")
      (assert r3 "file-lacking-key falls back to env end to end")
      (assert r4 "both absent resolves to none end to end")
      (assert r5 "keyFileLookup! honors listed order")
      (assert r6 "keyFileLookup! skips a missing file and keeps searching")
      (assert r7 "keyFileLookup! on an empty list is none")
      (assert r8 "expandUserPath expands ~ against HOME and passes other paths through")
      (assert r9 "gatewayKeyFilesFromProps parses an ordered path list")
      (assert r10 "gatewayKeyFilesFromProps is empty when :keyFiles is absent")
      (assert r11 "a key missing from every file and the environment names both in the config error")
      (assert r12 "a key file satisfies the config check and its path rides along on the parsed table")
      true))
