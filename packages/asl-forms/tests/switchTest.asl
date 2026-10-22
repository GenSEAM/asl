(module asl-forms/tests/switchTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/gate :a g) (asl-syntax/asl/paren :a prn)])

fn repoRoot! -> String
  (resultOr (realPath ".") "")

fn runCliWith! root: String payload: String extra: (List String) -> g/RunOut
  (let [(repo (repoRoot!))
        (cli (k/joinPath repo "bin/asl"))
        (path (k/joinPath root "bin"))
        (cache (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli")))
        (clang (optionOr (envGet "CLANG") "/usr/bin/clang"))
        (env (listAppend (list (str "PATH=" path) (str "HOME=" root) (str "ASL_ROOT=" root) (str "ASL_NATIVE_CLI_CACHE=" cache) (str "CLANG=" clang)) extra))]
    (g/runArgv! (list cli payload) (some root) (some env) 30000 0))

fn runCli! root: String payload: String -> g/RunOut
  (runCliWith! root payload (list))

fn asnValid? text: String -> Bool
  (let [(root (prn/parseString text))]
    (and (not (prn/hasErrors root)) (not (listEmpty? (prn/topLevelForms root)))))

fn successfulReceipt? out: g/RunOut op: String field: String value: String -> Bool
  (and (= out.code 0)
       (asnValid? out.out)
       (stringStartsWith? out.out (str "(:" op))
       (stringContains? out.out field)
       (stringContains? out.out value))

fn ! runTests -> Bool
  (let [(repo (repoRoot!))]
  (let [(base (str (optionOr (envGet "TMPDIR") "/tmp/") "aslSwitchForms_" (stringFromInt64 (mod (nowNs) 1000000000))))
        (made (dirCreate base))
        (bin (k/joinPath base "bin"))
        (madeBin (dirCreate bin))
        (bashLink (pathSymlink "/bin/bash" (k/joinPath bin "bash")))
        (lsLink (pathSymlink "/bin/ls" (k/joinPath bin "ls")))
        (exprLink (pathSymlink "/bin/expr" (k/joinPath bin "expr")))
        (dirnameLink (pathSymlink "/usr/bin/dirname" (k/joinPath bin "dirname")))
        (binEntryCount (match (dirList bin) ((err _) -1) ((ok names) (listLength names))))
        (git (g/runArgv! (list "git" "init" "-q" base) (none) (none) 10000 0))
        (file (k/joinPath base "switchFixture.asl"))
        (written (fileWrite file "(module switch/sample :x [greet])\nfn greet -> String\n  \"hello\"\n"))
        (readSymbol (runCli! base "(:read :file \"switchFixture.asl\" :symbol \"greet\")"))
        (readRange (runCli! base "(:read :file \"switchFixture.asl\" :start 1 :end 3)"))
        (query (runCli! base "(:query :text \"greet\")"))
        (edit (runCli! base "(:edit :file \"switchFixture.asl\" :old \"hello\" :new \"switched\") (:flush)"))
        (afterEdit (resultOr (fileReadString file) ""))
        (outline (runCli! base "(:intel :op outline :file \"switchFixture.asl\")"))
        (tools (runCli! base "(:tools)"))
        (failure (runCli! base "(:read :file \"missing.asl\")"))
        (wrapper (k/joinPath base "host-wrapper.sh"))
        (marker (k/joinPath base "host-wrapper.ran"))
        (wrapperWritten (fileWrite wrapper (str "#!/bin/bash\n: > '" marker "'\nprintf '%s\\n' '(:stub :ok)'\nexit 7\n")))
        (wrapperChmod (g/runArgv! (list "chmod" "+x" wrapper) (none) (none) 5000 0))
        (stderrRoute (runCliWith! base "(:ping)" (list (str "ASL_HOST=" wrapper))))
        (wrapperRan (fileExists? marker))
        (clean (g/runArgv! (list "rm" "-rf" base) (none) (none) 5000 0))]
    (do
      (assert (= binEntryCount 4) "restricted PATH directory contains only the four explicitly linked runtime tools")
      (assert (and (ok? madeBin) (and (ok? bashLink) (and (ok? lsLink) (and (ok? exprLink) (ok? dirnameLink))))) "restricted PATH contains only bin/asl runtime utilities")
      (assert (= git.code 0) "fixture is a temporary git repository")
      (assert (ok? written) "fixture source file was written")
      (assert (successfulReceipt? readSymbol "read" ":content" "hello") "symbol read has source content in a successful read receipt")
      (assert (and (successfulReceipt? readRange "read" ":start 1" ":end 3") (stringContains? readRange.out ":end 3")) "ranged read has read content and preserves requested start and end")
      (assert (successfulReceipt? query "query" ":defs" "greet") "query receipt contains matching definitions")
      (assert (and (= edit.code 0) (and (stringStartsWith? edit.out "(:batch") (and (asnValid? edit.out) (not (stringContains? edit.out ":status :ok"))))) "edit and flush return successful operation receipts without wire status")
      (assert (stringContains? afterEdit "switched") "edit and flush changed the fixture source")
      (assert (successfulReceipt? outline "intel" "greet" "greet") "outline returns its operation data")
      (assert (successfulReceipt? tools "tools" ":ops" ":read") "tools receipt contains the operation catalogue")
      (assert (and (!= failure.code 0) (and (asnValid? failure.out) (and (stringStartsWith? failure.out "(:read :status :rejected") (not (stringContains? failure.out ":status :ok"))))) "failing read is valid ASN carrying :status :rejected, never :ok")
      (assert (and (ok? wrapperWritten) (= wrapperChmod.code 0)) "the stand-in ASL_HOST wrapper was written and made executable")
      (assert (and (= stderrRoute.code 0) (and (stringStartsWith? stderrRoute.out "(:ping") (and (not (stringContains? stderrRoute.out "(:stub :ok)")) (not wrapperRan)))) (str "the native CLI runs forms in-process and never starts an ASL_HOST runner: " stderrRoute.out))
      true)))
