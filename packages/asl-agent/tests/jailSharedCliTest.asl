(module aslAgent/tests/jailSharedCliTest
  :x [runTests]
  :i [(aslAgent/jail :a jl) (aslAgent/core :a c) (asl-tools/fleet/run :a fr)])

; (:m :ref LEON-JAIL-SHARED-CLI :do "a writer whose CLI sources equal a shared cli-<digest> entry that no head names (it branched from an older base) takes that entry from the read-only shared store instead of building; sources that fit no entry keep the private build; the store is never written, by the harness or from inside the jail. The fixture's shared store lives in scratch and stands in for the parent's real HOME")
fn ! tmpBase! -> String
  (match (fileStat "/private/tmp") ((ok st) (if st.isDir "/private/tmp" "/tmp")) ((err _) "/tmp"))

fn ! readText! p: String -> String
  (resultOr (fileReadString p) "")

fn ! snap! shared: String name: String body: String -> Bool
  (let [d (str shared "/" name)
        a (ok? (dirCreate d))
        b (ok? (fileWrite (str d "/bin") (str name "\n")))
        e (ok? (fileWrite (str d "/deps") "a.asl\n"))
        g (ok? (dirCreate (str d "/src")))
        h (ok? (fileWrite (str d "/src/a.asl") body))]
    (and a (and b (and e (and g h)))))

fn ! cliDirs! cli: String -> (List String)
  (listSort (filter (fn [n] (stringStartsWith? n "cli-")) (resultOr (dirList cli) (list))))

fn ! seedFor! base: String tag: String body: String -> (Pair (List String) String)
  (let [dir (str base "/" tag)
        root (str dir "/root")
        shared (str dir "/fakeHome/.asl/run/nativeCli")
        fakeHome (str dir "/fakeHome")
        made (and (ok? (dirCreate root)) (and (ok? (dirCreate shared)) (and (snap! shared "cli-old" "OLD\n") (snap! shared "cli-new" "NEW\n"))))
        realRoot (resultOr (realPath root) root)
        head (jl/cliHeadName realRoot)
        pointed (ok? (fileWrite (str shared "/" head) (str (resultOr (realPath shared) shared) "/cli-new\n")))
        written (ok? (fileWrite (str root "/a.asl") body))
        rows (jl/childEnvIn! root (list "PATH=/usr/bin:/bin") (list) fakeHome true)
        home (jl/jailHome root)
        cli (str home "/.asl/run/nativeCli")
        target (stringTrim (readText! (str cli "/" head)))]
    (pair (if (and made (and pointed written)) (cliDirs! cli) (list "fixture failed")) target))

fn ! sandboxGates! base: String -> Bool
  (let [fakeHome (str base "/wfakeHome")
        shared (str fakeHome "/.asl/run/nativeCli")
        root (str base "/wroot")
        made (and (ok? (dirCreate root)) (and (ok? (dirCreate shared)) (snap! shared "cli-old" "OLD\n")))
        inherited (list "PATH=/usr/bin:/bin")
        home (jl/jailHome root)
        rows (jl/childEnvIn! root inherited (list) fakeHome true)
        sources (map pairSecond (jl/cacheSources! inherited fakeHome))
        tool (jl/jailTool!)
        plan (jl/jailPlan! tool false root home rows (list) (list) false fakeHome sources)
        script (str "echo planted > " shared "/planted 2> /dev/null; echo planted > " shared "/cli-old/planted 2> /dev/null; exit 0")
        ran (if (stringEmpty? tool) -1 (fr/runOneLimited (fr/job (jl/jailWrap! plan (list "/bin/sh" "-c" script)) root rows) (fr/limits 30 16)).exit)
        planted (or (ok? (fileStat (str shared "/planted"))) (ok? (fileStat (str shared "/cli-old/planted"))))]
    (do
      (assert made "the fixture's shared store was written")
      (assert (or (stringEmpty? tool) (= ran 0)) "the jailed shell ran")
      (assert (not planted) "a jailed child cannot write into the shared store")
      (assert (not (listAny? (fn [w] (stringContains? w "nativeCli")) plan.writes)) "the shared store is in no write list of the plan")
      true))

fn ! runTests -> Bool
  (let [base (str (tmpBase!) "/leonsharedcli-" (stringFromInt64 (monotonicNs)))
        made (dirCreate base)
        older (seedFor! base "o" "OLD\n")
        newer (seedFor! base "n" "NEW\n")
        odd (seedFor! base "x" "ODD\n")
        oldHead (jl/cliHeadName (resultOr (realPath (str base "/o/root")) (str base "/o/root")))
        sandboxed (sandboxGates! base)
        oldBefore (readText! (str base "/o/fakeHome/.asl/run/nativeCli/cli-old/bin"))
        cleaned (pathRemove base)]
    (do
      (assert (ok? made) "the base directory was made")
      (assert (listContains? (pairFirst older) "cli-old") (str "sources equal to an older shared entry no head names: the harness copies that entry and builds nothing: " (c/joinSep (pairFirst older) " ")))
      (assert (stringEndsWith? (pairSecond older) "/cli-old") (str "the private head names the copy of the older entry: " (pairSecond older)))
      (assert (stringEndsWith? (pairSecond newer) "/cli-new") (str "sources equal to the head's own entry keep it: " (pairSecond newer)))
      (assert (not (stringEndsWith? (pairSecond odd) "/cli-old")) (str "sources that fit no entry do not take a foreign entry, the unit builds privately: " (pairSecond odd)))
      (assert (= oldBefore "cli-old\n") "the shared entry the unit took is unchanged")
      (assert sandboxed "the shared store stays read-only")
      (assert (ok? cleaned) "the fixture directory was removed")
      true))
