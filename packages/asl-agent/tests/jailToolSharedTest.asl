(module aslAgent/tests/jailToolSharedTest
  :x [runTests]
  :i [(aslAgent/jail :a jl)])

; (:m :ref NODE-CLI-REBUILD-PER-TREE :do "an edit of any file the CLI entry names in its deps (the gateway, observe, coord, ... are compiled into the CLI and run in process) leaves the head behind the edit, so bin/asl builds the unit's own CLI and its gates never run the main tree's tool; an edit of a file the deps do not name (asl-agent, tests) keeps the head on the main entry, stamped past it; a failed build is never answered by pointing the head at the main entry")
fn ! tmpBase! -> String
  (match (fileStat "/private/tmp") ((ok st) (if st.isDir "/private/tmp" "/tmp")) ((err _) "/tmp"))

fn ! readText! p: String -> String
  (resultOr (fileReadString p) "")

fn gwPath -> String
  "asl/packages/asl-gateway/src/g.asl"

fn outPath -> String
  "asl/packages/asl-agent/src/x.asl"

fn cliPath -> String
  "asl/packages/asl-cli/src/c.asl"

fn parentDir p: String -> String
  (let [parts (stringSplit p "/")]
    (stringJoin (listTake parts (- (listLength parts) 1)) "/"))

fn ! put! p: String body: String -> Bool
  (let [made (dirCreate (parentDir p))]
    (ok? (fileWrite p body)))

fn ! snapshot! shared: String -> Bool
  (let [d (str shared "/cli-main")]
    (and (put! (str d "/bin") "MAINBIN\n")
      (and (put! (str d "/deps") (str (gwPath) "\n" (cliPath) "\n"))
        (and (put! (str d "/src/" (gwPath)) "gw main\n") (put! (str d "/src/" (cliPath)) "cli main\n")))))

fn ! stampOf! p: String -> Int64
  (match (fileStat p) ((ok st) st.mtimeNs) ((err _) -1))

fn ! stampAt! p: String ns: Int64 -> Bool
  (ok? (fileUtime p ns))

; (:m :ref NODE-CLI-REBUILD-PER-TREE :do "a fixture: the shared store holds the main entry with a pointer one hour old, the root holds its own bytes")
(schema Seen
  (:f target String)
  (:f headStamp Int64)
  (:f gwStamp Int64)
  (:f cliStamp Int64)
  (:f report String))

fn ! seen! base: String tag: String gwBody: String cliBody: String marker: String markerAfter: Bool -> Seen
  (let [dir (str base "/" tag)
        root (str dir "/root")
        fakeHome (str dir "/fakeHome")
        shared (str fakeHome "/.asl/run/nativeCli")
        now (nowNs)
        hour (* 3600 1000000000)
        built (and (ok? (dirCreate root)) (snapshot! shared))
        realRoot (resultOr (realPath root) root)
        head (jl/cliHeadName realRoot)
        pointed (and (put! (str shared "/" head) (str (resultOr (realPath shared) shared) "/cli-main\n")) (stampAt! (str shared "/" head) (- now hour)))
        wrote (and (put! (str root "/" (gwPath)) gwBody) (and (put! (str root "/" (cliPath)) cliBody) (put! (str root "/" (outPath)) (str gwBody cliBody))))
        inherited (list "PATH=/usr/bin:/bin")
        first (jl/childEnvIn! root inherited (list) fakeHome true)
        home (jl/jailHome root)
        cli (str home "/.asl/run/nativeCli")
        marked (if (stringEmpty? marker) true (and (put! (str cli "/" marker) "build failed\n") (stampAt! (str cli "/" marker) now)))
        gwAt (stampAt! (str root "/" (gwPath)) (- now (* 50 1000000000)))
        cliAt (stampAt! (str root "/" (cliPath)) (if markerAfter (+ now (* 50 1000000000)) (- now (* 50 1000000000))))
        second (jl/childEnvIn! root inherited (list) fakeHome true)]
    (Seen :target (stringTrim (readText! (str cli "/" head)))
          :headStamp (stampOf! (str cli "/" head))
          :gwStamp (stampOf! (str root "/" (gwPath)))
          :cliStamp (stampOf! (str root "/" (cliPath)))
          :report (if (and built (and pointed (and wrote (and marked (and gwAt cliAt))))) (readText! (str home "/.asl/seedReport.asn")) "fixture failed")))

fn ! runTests -> Bool
  (let [base (str (tmpBase!) "/leontoolshared-" (stringFromInt64 (monotonicNs)))
        made (dirCreate base)
        outOnly (seen! base "o" "gw main\n" "cli main\n" "" false)
        gwEdit (seen! base "g" "gw task\n" "cli main\n" "" false)
        cliEdit (seen! base "t" "gw main\n" "cli task\n" "" false)
        failed (seen! base "f" "gw main\n" "cli task\n" "cli-zzz.failed" false)
        cleaned (pathRemove base)]
    (do
      (assert (ok? made) "the base directory was made")
      (assert (stringEndsWith? outOnly.target "/cli-main") (str "an edit of a file the entry's deps do not name keeps the main entry: " outOnly.target))
      (assert (>= outOnly.headStamp outOnly.gwStamp) "the head is stamped past it, bin/asl builds nothing")
      (assert (< gwEdit.headStamp gwEdit.gwStamp) "an edit of a gateway file the entry names in its deps leaves the head behind it: bin/asl builds the unit's own CLI, its gates never run the main tree's gateway code in process")
      (assert (< cliEdit.headStamp cliEdit.cliStamp) "an edit of a tool source leaves the head behind it")
      (assert (< failed.headStamp failed.cliStamp) "a failed build is not answered by the main entry: the head stays behind the edit, so the builder refuses at once with its recorded reason")
      (assert (not (stringContains? failed.report "fallback")) "no fallback row")
      (assert (ok? cleaned) "the fixture directory was removed")
      true))
