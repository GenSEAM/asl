(module aslAgent/tests/jailCliCacheDriver
  :x [main]
  :i [(aslAgent/jail :a jl)])

; (:m :ref LEON-JAIL-CLI-CACHE :do "one re-seed of a fixture private native CLI cache in its own process, so jailCliCacheTest can start it through fleet/run with a hard timeout: a re-seed that opens a FIFO blocks forever and must fail the test by the bound instead of hanging it. args: home, shared cache, root, then the head names; prints (:rows \"<outcomes>\" :stamp <mtime ns of the first private head>)")
fn ! main args: (List String) -> (Result Int64 String)
  (let [home (optionOr (listGet args 0) "")
        shared (optionOr (listGet args 1) "")
        root (optionOr (listGet args 2) "")
        heads (listDrop args 3)
        rows (jl/seedCachesWith! "none" home (list (pair "ASL_NATIVE_CLI_CACHE" shared)) heads root)
        firstHead (str home "/.asl/run/nativeCli/" (optionOr (listHead heads) ""))
        stamp (match (fileLstat firstHead) ((ok st) st.mtimeNs) ((err _) -1))]
    (do
      (println (str "(:rows \"" (stringJoin (map pairSecond rows) " ") "\" :stamp " (stringFromInt64 stamp) ")"))
      (ok 0)))
