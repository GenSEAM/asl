(module asl-checker/builtinRecordFieldTest
  :x [runTests]
  :i [(check :a c) (types :a ty)])

; (:m :ref NATIVE-CHECK-DISAGREE :do "regression for the disagreement bin/asl check and asl-host check have on a host-returned record's own field names: resolve.asl#collectAllFieldNames kept a hand-written whitelist of 'every field name any builtin record has' that drifted from what the host actually returns (missing SpawnedProc.pid/stdin, FileStat.mtimeNs, LinkStat.mtimeNs, and all of Rusage/PlatformInfo), so sp.stdin on a real procSpawnv result read ERR_UNKNOWN_SYMBOL 'no record in this module has a field stdin' from the self-hosted checker while asl-host check accepted the same file")

fn checkerProbe src: String -> (List ty/Diagnostic)
  (c/checkSource src (mapEmpty) "builtinRecordFieldProbe.asl")

fn diagnosticText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn spawnedProcSource -> String
  (stringJoin (list
    "(module probe :x [spawnFields] :i [])"
    ""
    "fn ! spawnFields argv: (List String) -> Int64"
    "  (mt (procSpawnv argv (none) (none))"
    "    ((err _) 0)"
    "    ((ok sp) (+ sp.pid (+ sp.stdin (+ sp.stdout sp.stderr)))))") "\n")

fn fileStatSource -> String
  (stringJoin (list
    "(module probe :x [statFields] :i [])"
    ""
    "fn ! statFields path: String -> Int64"
    "  (mt (fileStat path)"
    "    ((err _) 0)"
    "    ((ok st) (+ st.mode (+ st.mtime st.mtimeNs))))") "\n")

fn rusageSource -> String
  (stringJoin (list
    "(module probe :x [rusageFields] :i [])"
    ""
    "fn ! rusageFields -> Int64"
    "  (mt (procRusage)"
    "    ((err _) 0)"
    "    ((ok u) (+ u.selfMaxRssKb (+ u.selfUserUs (+ u.selfSysUs (+ u.childrenMaxRssKb (+ u.childrenUserUs u.childrenSysUs)))))))") "\n")

fn platformInfoSource -> String
  (stringJoin (list
    "(module probe :x [platformFields] :i [])"
    ""
    "fn ! platformFields -> String"
    "  (mt (platformInfo) ((ok p) (str p.os p.release p.machine)) ((err _) \"\"))") "\n")

fn ! runTests -> Bool
  (let [(spawnDiags (checkerProbe (spawnedProcSource)))
        (statDiags (checkerProbe (fileStatSource)))
        (rusageDiags (checkerProbe (rusageSource)))
        (platformDiags (checkerProbe (platformInfoSource)))]
    (do
      (assert (listEmpty? spawnDiags) (str "checker knows every SpawnedProc field a real procSpawnv call returns (pid, stdin, stdout, stderr): " (diagnosticText spawnDiags)))
      (assert (listEmpty? statDiags) (str "checker knows FileStat.mtimeNs, not just the fields fileStat had before mtimeNs was added: " (diagnosticText statDiags)))
      (assert (listEmpty? rusageDiags) (str "checker knows every Rusage field procRusage returns: " (diagnosticText rusageDiags)))
      (assert (listEmpty? platformDiags) (str "checker knows every PlatformInfo field platformInfo returns: " (diagnosticText platformDiags)))
      true))
