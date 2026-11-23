(module aslAgent/tests/staticHintTest
  :x [runTests]
  :i [(aslAgent/staticHint :a sh)])

fn ! runTests -> Bool
  (let [(tmp (optionOr (envGet "TMPDIR") "/tmp"))
        (root (str tmp "/staticHintTest-" (stringFromInt64 (monotonicNs))))
        (_ (dirCreate root))
        (_ (fileWrite (str root "/alpha.asl") "a"))
        (_ (fileWrite (str root "/beta.asl") "b"))
        (_ (fileWrite (str root "/gamma.asl") "c"))
        (missing (sh/staticHint "(:receipt :id \"r1\" :op \"read\" :status :error :error \"ERR_NOT_FOUND\" :file \"alph.asl\")" root))
        (shape (sh/staticHint "(:receipt :id \"r2\" :op \"write\" :status :rejected :error \"ERR_RAW_MISSING\" :file \"out.txt\" :message \"missing :raw block\")" root))
        (editFirst (sh/staticHint "(:receipt :id \"r3\" :op \"gate\" :status :failed :exit 1)" root))
        (persisted (sh/staticHint "(:receipt :id \"r3\" :op \"gate\" :status :failed :exit 1)\n(:receipt :id \"r4\" :op \"edit\" :status :ok :persisted true)" root))
        (okR (sh/staticHint "(:receipt :id \"r5\" :op \"read\" :status :ok :file \"alpha.asl\")" root))
        (rawPresent (sh/staticHint "(:receipt :id \"r6\" :op \"write\" :status :rejected :error \"ERR_OTHER\" :file \"a.txt\" :content :raw)" root))
        (m (optionOr missing ""))
        (_ (pathRemove (str root "/alpha.asl")))
        (_ (pathRemove (str root "/beta.asl")))
        (_ (pathRemove (str root "/gamma.asl")))
        (_ (pathRemove root))]
    (do
      (assert (some? missing) "an ERR_NOT_FOUND receipt yields a missing hint")
      (assert (stringContains? m "(:hint :missing \"alph.asl\" :near (") "the missing hint names the file")
      (assert (stringContains? m ":near (\"alpha.asl\"") "the nearest existing name is listed first")
      (assert (= (optionOr shape "") "(:hint :writeShape \"(:write :file out.txt :raw [[...]])\")") "a rejected write missing :raw yields the writeShape form")
      (assert (= (optionOr editFirst "") "(:hint :editFirst \"the gate is red and nothing changed; edit before re-running it\")") "a failed gate with no persisted edit yields editFirst")
      (assert (none? persisted) "a persisted edit in the turn suppresses editFirst")
      (assert (none? okR) "an ok receipt yields none")
      (assert (none? rawPresent) "a rejected write whose text merely carries :raw is not a missing-raw hint")
      true))
