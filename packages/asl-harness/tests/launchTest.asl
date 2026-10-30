(module asl-harness/tests/launchTest
  :x [runTests]
  :i [(asl-harness/launch :a l)])

fn fixturePath -> String
  "tests/parity/harness/launchFixture.asn"

fn sha s: String -> String
  (bytesSha256 (stringToBytes s))

fn tailOf xs: (List T) -> (List T)
  (optionOr (listTail xs) (list))

fn fget row: l/Asn key: String -> (Option l/Asn)
  (l/asnGet row key)

fn fstr row: l/Asn key: String -> String
  (match (fget row key) ((some v) (optionOr (l/textOf v) "")) ((none) ""))

fn fint row: l/Asn key: String -> String
  (match (fget row key) ((some v) (match v ((l/asnInt n) n) (_ "none"))) ((none) "none"))

fn fhas row: l/Asn key: String -> Bool
  (some? (fget row key))

fn fbool row: l/Asn key: String -> Bool
  (= (fstr row key) "true")

fn itemsOf v: l/Asn -> (List l/Asn)
  (match v ((l/asnForm xs) xs) (_ (list)))

fn flist row: l/Asn key: String -> (List String)
  (match (fget row key) ((some v) (map (fn [(x l/Asn)] -> String (optionOr (l/textOf x) "")) (itemsOf v))) ((none) (list)))

fn section fx: l/Asn key: String -> (List l/Asn)
  (match (fget fx key) ((some v) (itemsOf v)) ((none) (list)))

fn replaceAll s: String subs: (List (Pair String String)) -> String
  (fold (fn [(acc String) (p (Pair String String))] -> String (if (stringEmpty? (pairFirst p)) acc (stringReplace acc (pairFirst p) (pairSecond p)))) s subs)

fn showList xs: (List String) -> String
  (str "(" (stringJoin xs " | ") ")")

fn checkTruthy row: l/Asn -> Bool
  (let [(text (fstr row "text"))
        (want (fbool row "want"))
        (v (l/asnFloat text))
        (got (l/truthy v))
        (formsOfOk (if want
                     (= (l/formsOf (some v) "x" "test") (err "launch: test is not a list"))
                     (= (l/formsOf (some v) "x" "test") (ok (list)))))
        (formOrOk (if want
                    (= (l/formOr (some v) "test") (err "launch: test is not a list"))
                    (= (l/formOr (some v) "test") (ok (l/asnForm (list))))))]
    (do (assert (= got want) (str "truthy " text ": got " (if got "true" "false") " want " (if want "true" "false")))
        (assert formsOfOk (str "formsOf " text))
        (assert formOrOk (str "formOr " text))
        (and (= got want) (and formsOfOk formOrOk))))

fn checkReader row: l/Asn -> Bool
  (let [(text (fstr row "text"))
        (kind (match row ((l/asnForm xs) (match (listHead xs) ((some h) (match h ((l/asnKw k) k) (_ ""))) ((none) ""))) (_ "")))
        (got (cond
               ((= kind "all") (match (l/readAll text) ((ok vs) (pair "dump" (stringJoin (map l/asnDump vs) " "))) ((err e) (pair "error" e))))
               ((= kind "one") (match (l/readOne text) ((ok v) (pair "dump" (l/asnDump v))) ((err e) (pair "error" e))))
               ((= kind "get") (match (l/readOne text) ((ok v) (pair "dump" (match (l/asnGet v (fstr row "key")) ((some x) (l/asnDump x)) ((none) "none")))) ((err e) (pair "error" e))))
               ((= kind "forms") (match (l/readOne text)
                                   ((ok v) (pair "dump" (stringJoin (map l/asnDump (l/asnForms v (if (stringEmpty? (fstr row "head")) (none) (some (fstr row "head"))))) " ")))
                                   ((err e) (pair "error" e))))
               (else (pair "kind" kind))))
        (want (if (fhas row "error") (pair "error" (fstr row "error")) (pair "dump" (fstr row "dump"))))]
    (do (assert (= got want) (str "reader " kind " " (l/asnDump (l/asnStr text)) ": got " (pairSecond got) " want " (pairSecond want)))
        (= got want)))

fn srcText row: l/Asn key: String base: String -> String
  (match (fget row key) ((some v) (match v ((l/asnStr s) s) (_ base))) ((none) base))

(schema Suite (:f fx l/Asn) (:f paths l/Paths) (:f base l/Loaded) (:f loaded (List (Pair String l/Loaded))) (:f platform String) (:f date String))

fn loadedOf s: Suite tag: String -> l/Loaded
  (if (or (stringEmpty? tag) (= tag "real"))
    s.base
    (optionOr (match (listHead (filter (fn [(p (Pair String l/Loaded))] -> Bool (= (pairFirst p) tag)) s.loaded)) ((some p) (some (pairSecond p))) ((none) (none))) s.base))

fn buildSuite fx: l/Asn -> Suite
  (let [(src (optionOr (fget fx "sources") (l/asnForm (list))))
        (h (fstr src "harness")) (c (fstr src "clients")) (t (fstr src "tools"))
        (paths (l/pathsFor "{root}" (fstr fx "host")))
        (synth (map (fn [(r l/Asn)] -> (Pair String l/Loaded)
                      (pair (fstr r "id") (l/loadSources paths (srcText r "harness" h) (srcText r "clients" c) (srcText r "tools" t))))
                    (listAppend (section fx "synth") (listAppend (section fx "argvClients") (section fx "writeClients")))))
        (firstRender (optionOr (listHead (section fx "render")) (l/asnForm (list))))
        (fills (fillPairs firstRender))]
    (Suite :fx fx :paths paths :base (l/loadSources paths h c t) :loaded synth
           :platform (optionOr (lookup fills "platform") "") :date (optionOr (lookup fills "date") "")))

fn lookup xs: (List (Pair String String)) k: String -> (Option String)
  (match (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) k)) xs)) ((some p) (some (pairSecond p))) ((none) (none)))

fn fillPairs row: l/Asn -> (List (Pair String String))
  (match (fget row "fills")
    ((some v) (map (fn [(p l/Asn)] -> (Pair String String)
                     (let [(xs (itemsOf p))]
                       (pair (optionOr (match (listHead xs) ((some k) (l/textOf k)) ((none) (none))) "")
                             (optionOr (match (listHead (tailOf xs)) ((some k) (l/textOf k)) ((none) (none))) ""))))
                   (itemsOf v)))
    ((none) (list)))

fn envProbe s: Suite eid: String -> l/Probe
  (let [(row (optionOr (listHead (filter (fn [(r l/Asn)] -> Bool (= (fstr r "id") eid)) (section s.fx "envs"))) (l/asnForm (list))))
        (cfg (fstr row "cfg"))
        (asl (fstr row "asl"))]
    (l/Probe :root (fstr row "root") :branch (fstr row "branch") :rules (fbool row "rules") :aslSrc (fbool row "aslSrc")
             :migrate (and (not (stringEmpty? cfg)) (l/migrateOn cfg)) :asl (if (stringEmpty? asl) (none) (some asl)) :session (fbool row "session")))

fn renderOpts row: l/Asn cwd: String promptDir: (Option String) fills: (List (Pair String String)) -> l/RenderOpts
  (l/RenderOpts :cwd cwd :client (fstr row "client") :mode (fstr row "mode") :core (fbool row "core") :promptDir promptDir
                :drop (flist row "drop") :only (flist row "only") :fills fills :once (fbool row "once") :platform "" :date "")

fn checkRender s: Suite row: l/Asn -> Bool
  (let [(pd (fstr row "promptDir"))
        (opts (renderOpts row (fstr row "cwd") (if (stringEmpty? pd) (none) (some pd)) (fillPairs row)))
        (got (l/render (loadedOf s (fstr row "sources")) (envProbe s (fstr row "env")) opts))
        (label (str "render " (fstr row "sources") " " (fstr row "env") " " opts.client " " opts.mode " core " (fstr row "core") " once " (fstr row "once")))
        (good (if (fhas row "error")
                (= got (err (fstr row "error")))
                (match got
                  ((ok t) (and (= (sha t) (fstr row "sha")) (= (stringFromInt64 (stringLength t)) (fint row "len"))))
                  ((err _) false))))]
    (do (assert good (str label ": got " (match got ((ok t) (str "sha " (sha t) " " t)) ((err e) (str "error " e))) " want " (if (fhas row "error") (fstr row "error") (fstr row "sha"))))
        good))

fn checkArgv s: Suite row: l/Asn -> Bool
  (let [(loaded (loadedOf s (fstr row "sources")))
        (clients (resultOr loaded.clients (list)))
        (exe (fstr row "exe"))
        (got (l/buildArgv clients loaded.paths.clients (fstr row "client") (if (stringEmpty? exe) (none) (some exe)) "/run/p.md" "/run/d"
                          (fbool row "lean") (flist row "extra") (fbool row "coord") (fstr row "cwd") (fstr row "base") (fbool row "ask") (fbool row "shellOnly")))
        (good (cond
                ((fhas row "error") (= got (err (fstr row "error"))))
                ((fhas row "crash") (= got (err (str "launch: no :shell for claude in " loaded.paths.clients))))
                (else (= got (ok (flist row "argv"))))))]
    (do (assert good (str "argv " (fstr row "sources") " " (fstr row "client") " lean " (fstr row "lean") " coord " (fstr row "coord") " shellOnly " (fstr row "shellOnly")
                          " ask " (fstr row "ask") " extra " (showList (flist row "extra")) ": got " (match got ((ok a) (showList a)) ((err e) e))))
        good))

fn ! walkTree root: String dir: String -> (List (Pair String String))
  (match (dirList dir)
    ((err _) (list))
    ((ok names)
      (let [(full (fn [(n String)] -> String (str dir "/" n)))
            (isDir (fn [(n String)] -> Bool (match (fileStat (str dir "/" n)) ((ok st) st.isDir) ((err _) false))))
            (rel (fn [(n String)] -> String (optionOr (stringSlice (str dir "/" n) (+ (stringLength root) 1) (stringLength (str dir "/" n))) n)))
            (files (map (fn [(n String)] -> (Pair String String)
                          (pair (rel n) (sha (stringReplace (resultOr (fileReadString (full n)) "") root "{run}"))))
                        (filter (fn [(n String)] -> Bool (not (isDir n))) names)))
            (subs (fold (fn [(acc (List (Pair String String))) (n String)] -> (List (Pair String String)) (listAppend acc (walkTree root (full n))))
                        (list) (filter isDir names)))]
        (listAppend files subs))))

fn fileRows row: l/Asn -> (List (Pair String String))
  (match (fget row "files")
    ((some v) (map (fn [(f l/Asn)] -> (Pair String String) (pair (fstr f "path") (fstr f "sha"))) (itemsOf v)))
    ((none) (list)))

fn showTree xs: (List (Pair String String)) -> String
  (showList (map (fn [(p (Pair String String))] -> String (str (pairFirst p) "=" (optionOr (stringSlice (pairSecond p) 0 8) ""))) xs))

fn ! checkWrite s: Suite base: String i: Int64 row: l/Asn -> Bool
  (let [(runDir (str base "/w" (stringFromInt64 i) "/run"))
        (pre (if (fbool row "notePre") (and (ok? (dirCreate runDir)) (ok? (fileWrite (str runDir "/note.md") "kept\n"))) true))
        (loaded (loadedOf s (fstr row "sources")))
        (client (fstr row "client"))
        (opts (l/RenderOpts :cwd "/ws/asex" :client client :mode "implement" :core false :promptDir (some runDir) :drop (list) :only (list)
                            :fills (list (pair "platform" s.platform) (pair "date" s.date)) :once (fbool row "once") :platform "" :date ""))
        (prompt (resultOr (l/render loaded (envProbe s "asex") opts) ""))
        (got (l/writePrompt! loaded client prompt runDir (fbool row "bare") (fbool row "shellOnly")))
        (tree (walkTree runDir runDir))
        (subs (list (pair runDir "{run}")))
        (headOk (if (fhas row "error")
                  (= got (err (fstr row "error")))
                  (match got
                    ((ok p) (and (= (replaceAll (pairFirst p) subs) (fstr row "path")) (= (replaceAll (pairSecond p) subs) (fstr row "extraDir"))))
                    ((err _) false))))
        (treeOk (= tree (fileRows row)))]
    (do (assert pre (str "write " client ": note.md seeded"))
        (assert (not (stringEmpty? prompt)) (str "write " client ": prompt renders"))
        (assert headOk (str "write " (fstr row "sources") " " client " once " (fstr row "once") " bare " (fstr row "bare") " shellOnly " (fstr row "shellOnly") ": got "
                            (match got ((ok p) (str (pairFirst p) " " (pairSecond p))) ((err e) e))))
        (assert treeOk (str "write " (fstr row "sources") " " client " tree: got " (showTree tree) " want " (showTree (fileRows row))))
        (and headOk treeOk)))

fn ! checkMain s: Suite base: String i: Int64 row: l/Asn -> Bool
  (let [(args (flist row "args"))
        (runDir (str base "/m" (stringFromInt64 i) "/run/" (optionOr (listHead args) "x") "-1"))
        (ctx (l/Ctx :cwd "/ws/asex" :runDir runDir :probe (envProbe s "asex")
                    :exes (list (pair "claude" "/stub/bin/claude") (pair "codex" "/stub/bin/codex") (pair "agy" "/stub/bin/agy"))
                    :platform "" :date "" :fills (list (pair "platform" s.platform) (pair "date" s.date))))
        (o (l/mainWith! s.base ctx args))
        (subs (list (pair runDir "{run}")))
        (exitOk (if (= (fint row "exit") "none") (= o.action "exec") (= (stringFromInt64 o.exit) (fint row "exit"))))
        (outNorm (if (stringContains? o.out ":promptChars ") (pairFirst (promptFacts o.out subs (optionOr (listHead args) ""))) (replaceAll o.out subs)))
        (outOk (= (sha outNorm) (fstr row "stdoutSha")))
        (errOk (= (replaceAll o.errText subs) (fstr row "stderr")))
        (actOk (and (= o.action (fstr row "action"))
                    (or (= o.action "none")
                        (and (= (map (fn [(a String)] -> String (replaceAll a subs)) o.argv) (flist row "argv")) (= o.launched (fstr row "launched"))))))
        (tree (walkTree runDir runDir))
        (treeOk (= tree (fileRows row)))
        (label (str "main " (showList args)))]
    (do (assert exitOk (str label ": exit " (stringFromInt64 o.exit) " action " o.action))
        (assert outOk (str label ": stdout " outNorm))
        (assert errOk (str label ": stderr " (replaceAll o.errText subs) " want " (fstr row "stderr")))
        (assert actOk (str label ": action " o.action " " (showList o.argv) " launched " o.launched))
        (assert treeOk (str label ": files " (showTree tree) " want " (showTree (fileRows row))))
        (and exitOk (and outOk (and errOk (and actOk treeOk))))))

fn ! run argv: (List String) cwd: String -> Bool
  (match (l/runCapture! argv (some cwd) (none))
    ((ok c) (do (assert (= c.code 0) (str (stringJoin argv " ") " exits 0: " c.errText)) (= c.code 0)))
    ((err e) (do (assert false (str (stringJoin argv " ") ": " e)) false)))

fn ! gitIn cwd: String args: (List String) -> Bool
  (run (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@t" "-c" "init.defaultBranch=main") args) cwd)

fn ! buildStep ws: String step: String -> Bool
  (cond
    ((= step "git") (gitIn ws (list "init" "-q")))
    ((= step "commit") (and (ok? (fileWrite (str ws "/f.txt") "x\n")) (and (gitIn ws (list "add" "f.txt")) (gitIn ws (list "commit" "-q" "-m" "c")))))
    ((= step "detach") (gitIn ws (list "checkout" "-q" "--detach")))
    ((= step "asl") (ok? (fileWrite (str ws "/a.asl") "x\n")))
    ((= step "add") (gitIn ws (list "add" "a.asl")))
    ((stringStartsWith? step "cfg:") (ok? (fileWrite (str ws "/.asl.config.asn") (optionOr (stringSlice step 4 (stringLength step)) ""))))
    ((= step "rules") (and (ok? (dirCreate (str ws "/asl/grammar"))) (ok? (fileWrite (str ws "/asl/grammar/rules.asn") "(:rules)\n"))))
    ((= step "rulesdir") (ok? (dirCreate (str ws "/asl/grammar/rules.asn"))))
    (else (do (assert false (str "unknown step " step)) false)))

fn ! buildWs ws: String steps: (List String) -> Bool
  (let [(made (ok? (dirCreate ws)))
        (done (listAll? (fn [(st String)] -> Bool (buildStep ws st)) steps))
        (sub (ok? (dirCreate (str ws "/sub/deeper"))))]
    (and made (and done sub)))

fn ! checkFacts top: String row: l/Asn -> Bool
  (let [(base (str top "/facts"))
        (ws (str base "/" (fstr row "ws")))
        (built (buildWs ws (flist row "steps")))
        (cwd (if (stringEmpty? (fstr row "sub")) ws (str ws "/" (fstr row "sub"))))
        (got (l/probe! cwd))]
    (match got
      ((err e) (do (assert false (str "facts " (fstr row "ws") ": " e)) false))
      ((ok p)
        (let [(fs (l/factsOf (list) "claude" "implement" false p))
              (fact (fn [(k String)] -> String (match (listHead (filter (fn [(q (Pair String Bool))] -> Bool (= (pairFirst q) k)) fs)) ((some q) (if (pairSecond q) "true" "false")) ((none) "?"))))
              (good (and built (and (= (fact "git") (fstr row "git")) (and (= (fact "asex") (fstr row "asex")) (and (= (fact "foreign") (fstr row "foreign"))
                     (and (= (fact "aslProject") (fstr row "aslProject")) (= (stringReplace (l/gitState p) base "{base}") (fstr row "state"))))))))]
          (do (assert good (str "facts " (fstr row "ws") ": git " (fact "git") " asex " (fact "asex") " foreign " (fact "foreign") " aslProject " (fact "aslProject")
                                " state " (stringReplace (l/gitState p) base "{base}")))
              good)))))

fn ! checkWhich base: String row: l/Asn -> Bool
  (let [(dir (fn [(k String)] -> String (if (or (= k "A") (or (= k "B") (= k "C"))) (str base "/which/" k) k)))
        (spec (fstr row "path"))
        (pathVar (if (= spec "<unset>") (none) (some (stringJoin (map dir (stringSplit spec ":")) ":"))))
        (name (stringReplace (stringReplace (fstr row "name") "{A}" (dir "A")) "{B}" (dir "B")))
        (got (optionOr (l/whichIn! pathVar name) ""))
        (good (= (stringReplace got (str base "/which") "{base}") (fstr row "result")))]
    (do (assert good (str "which " spec " " (fstr row "name") ": got " got)) good))

fn ! buildWhich base: String -> Bool
  (let [(w (str base "/which"))]
    (and (ok? (dirCreate (str w "/A"))) (and (ok? (dirCreate (str w "/B"))) (and (ok? (dirCreate (str w "/C/tool")))
    (and (ok? (fileWrite (str w "/A/tool") "#!/bin/sh\n")) (and (ok? (fileWrite (str w "/B/tool") "#!/bin/sh\n")) (and (ok? (fileWrite (str w "/B/other") "#!/bin/sh\n"))
    (and (run (list "chmod" "755" (str w "/A/tool")) base) (and (run (list "chmod" "644" (str w "/B/tool")) base) (run (list "chmod" "700" (str w "/B/other")) base))))))))))

fn stubScript -> String
  "#!/bin/sh\nprintf '%s\\n' \"$0\" \"$@\" > \"$STUB_LOG\"\nprintf 'launched=%s\\n' \"$ASL_LAUNCHED\" >> \"$STUB_LOG\"\ncase \"$STUB_MODE\" in\n  out) printf 'hello\\n'; printf 'warn\\n' >&2 ;;\n  empty) printf 'run ended with no output\\n' >&2 ;;\n  split) printf 'run ended with ' >&2; sleep 0.2; printf 'no output\\n' >&2 ;;\n  fail) printf 'bad\\n' >&2; exit 3 ;;\n  sig) kill -TERM $$ ;;\nesac\nexit 0\n"

fn pruneDirs -> (List String)
  (list "claude-99999999" "codex-1" "junk-12" "claude-abc" "agy-99999998")

(schema E2e (:f base String) (:f root String) (:f stubs String) (:f ws String) (:f host String) (:f launch String) (:f platform String) (:f date String))

; (:m :ref LAUNCHTEST-CACHEPIN :do "every e2e case below execs ctx.host (the bin/asl wrapper) with HOME redirected to a scratch dir; without this, the wrapper's own home-based native-cli pointer lookup finds nothing and cold-rebuilds the whole toolchain from asl/seed per case, which is slow and, under load, can fail its own self-probe (ERR_HOST_ABSENT) since the stage-0 host is gone; pinning ASL_NATIVE_CLI_CACHE to the real HOME's already-built cache keeps every isolated-HOME exec on the fast path")
fn nativeCliCache -> String
  (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))

fn ! buildE2e s: Suite base: String -> (Result E2e String)
  (let [(e (str base "/e2e")) (root (str base "/e2e/root")) (stubs (str base "/e2e/stubs")) (ws (str base "/e2e/ws"))
        (src (optionOr (fget s.fx "sources") (l/asnForm (list))))
        (made (and (ok? (dirCreate (str root "/asl/grammar"))) (ok? (dirCreate stubs))))
        (grammar (and (ok? (fileWrite (str root "/asl/grammar/harness.asn") (fstr src "harness")))
                      (and (ok? (fileWrite (str root "/asl/grammar/clients.asn") (replaceAll (fstr src "clients") (list (pair ":id codex " ":id codex :outputCut \"10k tokens\" ") (pair ":id agy " ":id agy :workerWait \"30 minutes\" "))))) (ok? (fileWrite (str root "/asl/grammar/tools.asn") (fstr src "tools"))))))
        (grammar5 (and (ok? (fileWrite (str root "/asl/grammar/harness5.asn") (resultOr (fileReadString "asl/grammar/harness5.asn") "")))
                       (ok? (fileWrite (str root "/asl/grammar/terms.asn") (resultOr (fileReadString "asl/grammar/terms.asn") "")))))
        (stubsOk (listAll? (fn [(c String)] -> Bool (and (ok? (fileWrite (str stubs "/" c) (stubScript))) (run (list "chmod" "755" (str stubs "/" c)) base)))
                           (list "claude" "codex" "agy")))
        (wsOk (buildWs ws (list "git")))]
    (if (not (and made (and grammar (and grammar5 (and stubsOk wsOk)))))
      (err "e2e setup failed")
      (match (realPath "bin/asl")
        ((err e) (err (str "bin/asl: " e)))
        ((ok host)
          (match (realPath "asl/packages/asl-harness/src/launch.asl")
            ((err e) (err (str "launch.asl: " e)))
            ((ok launch)
              (match (l/platform!)
                ((err e) (err e))
                ((ok plat)
                  (match (l/today!)
                    ((err e) (err e))
                    ((ok day) (ok (E2e :base e :root root :stubs stubs :ws ws :host host :launch launch :platform plat :date day))))))))))))

fn clientOfDir d: String -> String
  (match (listHead (filter (fn [(c String)] -> Bool (stringStartsWith? d (str c "-"))) (list "claude" "codex" "agy"))) ((some c) c) ((none) ""))

fn promptBody client: String text: String -> String
  (if (= client "agy")
    (match (stringIndexOf text "---\n\n") ((some i) (optionOr (stringSlice text (+ i 5) (stringLength text)) "")) ((none) text))
    text)

fn ! promptFacts raw: String subs: (List (Pair String String)) client: String -> (Pair String String)
  (match (stringIndexOf raw ":prompt \"")
    ((none) (pair raw ""))
    ((some i)
      (let [(after (optionOr (stringSlice raw (+ i 9) (stringLength raw)) ""))
            (path (match (stringIndexOf after "\" :promptChars ") ((some j) (optionOr (stringSlice after 0 j) "")) ((none) "")))
            (numStart (match (stringIndexOf raw ":promptChars ") ((some j) (+ j 13)) ((none) 0)))
            (numText (optionOr (listHead (stringSplit (optionOr (stringSlice raw numStart (stringLength raw)) "") " ")) ""))
            (body (promptBody client (resultOr (fileReadString path) "")))
            (bs (stringToBytes body))
            (chars (fold (fn [(acc Int64) (k Int64)] -> Int64 (if (= (& (bytesGet bs k) 192) 128) acc (+ acc 1))) 0 (range 0 (bytesLength bs))))]
        (do (assert (= numText (stringFromInt64 chars)) (str "promptChars " numText " equals the prompt's characters " (stringFromInt64 chars)))
            (pair (replaceAll (stringReplace raw (str ":promptChars " numText " ") ":promptChars {n} ") subs) (sha (replaceAll body subs)))))))

fn ! checkE2e ctx: E2e i: Int64 row: l/Asn -> Bool
  (let [(args (flist row "args"))
        (kind (fstr row "pathKind"))
        (home (str ctx.base "/home" (stringFromInt64 i)))
        (runRoot (str home "/.asl/run/harness"))
        (made (ok? (dirCreate runRoot)))
        (pre (if (= kind "prune") (listAll? (fn [(d String)] -> Bool (ok? (dirCreate (str runRoot "/" d)))) (pruneDirs)) true))
        (log (str ctx.base "/log" (stringFromInt64 i)))
        (env (list (str "PATH=" (if (= kind "bare") "" (str ctx.stubs ":")) "/usr/bin:/bin") (str "HOME=" home) (str "STUB_LOG=" log)
                   (str "STUB_MODE=" (fstr row "stubMode")) "LANG=C" (str "ASL_ROOT=" ctx.root) (str "ASL_NATIVE_CLI_CACHE=" (nativeCliCache))))
        (res (l/runCapture! (listAppend (list ctx.host "run" ctx.launch) args) (some ctx.ws) (some env)))]
    (match res
      ((err e) (do (assert false (str "e2e " (showList args) ": " e)) false))
      ((ok c)
        (let [(dirs (resultOr (dirList runRoot) (list)))
              (pidDirs (filter (fn [(d String)] -> Bool (and (not (stringEmpty? (clientOfDir d))) (not (listContains? (pruneDirs) d)))) dirs))
              (subs (listAppend (list (pair ctx.host "{host}"))
                                (listAppend (map (fn [(d String)] -> (Pair String String) (pair d (str (clientOfDir d) "-PID"))) pidDirs)
                                            (list (pair runRoot "{run}") (pair ctx.base "{base}") (pair ctx.platform "{platform}") (pair ctx.date "{date}")))))
              (dry (and (listContains? args "--dry-run") (= c.code 0)))
              (pf (if dry (promptFacts c.out subs (optionOr (listHead args) "")) (pair (replaceAll c.out subs) "")))
              (stubLog (replaceAll (resultOr (fileReadString log) "") subs))
              (label (str "e2e " (showList args) " " kind " " (fstr row "stubMode")))
              (exitOk (= (fint row "exit") (stringFromInt64 c.code)))
              (outOk (= (pairFirst pf) (fstr row "stdout")))
              (errOk (= (replaceAll c.errText subs) (fstr row "stderr")))
              (logOk (= stubLog (fstr row "stubLog")))
              (dirsOk (= (map (fn [(d String)] -> String (replaceAll d subs)) dirs) (flist row "runDirs")))
              (promptOk (= (pairSecond pf) (fstr row "promptSha")))]
          (do (assert (and made pre) (str label ": setup"))
              (assert exitOk (str label ": exit " (stringFromInt64 c.code) " stderr " c.errText))
              (assert outOk (str label ": stdout " (pairFirst pf) " want " (fstr row "stdout")))
              (assert errOk (str label ": stderr " (replaceAll c.errText subs) " want " (fstr row "stderr")))
              (assert logOk (str label ": stub log " stubLog " want " (fstr row "stubLog")))
              (assert dirsOk (str label ": run dirs " (showList dirs)))
              (assert promptOk (str label ": prompt sha " (pairSecond pf) " want " (fstr row "promptSha")))
              (and exitOk (and outOk (and errOk (and logOk (and dirsOk promptOk))))))))))

fn ! freezeFor! root: String -> String
  (let [(h (resultOr (fileReadString (str root "/asl/grammar/harness.asn")) ""))
        (c (resultOr (fileReadString (str root "/asl/grammar/clients.asn")) ""))
        (t (resultOr (fileReadString (str root "/asl/grammar/tools.asn")) ""))]
    (optionOr (stringSlice (sha (str h c t)) 0 8) ""))

fn ! checkPromptOnly ctx: E2e i: Int64 -> Bool
  (let [(home (str ctx.base "/promptHome" (stringFromInt64 i)))
        (promptDir (str home "/custom-prompt"))
        (made (ok? (dirCreate promptDir)))
        (log (str ctx.base "/promptOnly.log"))
        (env (list (str "PATH=" ctx.stubs ":/usr/bin:/bin") (str "HOME=" home) (str "STUB_LOG=" log)
                   (str "ASL_ROOT=" ctx.root) (str "ASL_LAUNCH_PROMPT_DIR=" promptDir) "LANG=C" (str "ASL_NATIVE_CLI_CACHE=" (nativeCliCache))))
        (out (l/runCapture! (list ctx.host "run" ctx.launch "claude" "--prompt-only") (some ctx.ws) (some env)))
        (captured (match out ((ok c) c) ((err _) (l/Captured :code 127 :out "" :errText "could not run prompt-only"))))
        (row (if (= captured.code 0) (l/readOne captured.out) (err captured.errText)))
        (path (match row ((ok r) (optionOr (l/textOf (optionOr (l/asnGet r "path") (l/asnStr ""))) "")) ((err _) "")))
        (freeze (match row ((ok r) (optionOr (l/textOf (optionOr (l/asnGet r "freeze") (l/asnStr ""))) "")) ((err _) "")))
        (codeOk (= captured.code 0))
        (pathOk (and (not (stringEmpty? path)) (and (stringStartsWith? path promptDir) (fileExists? path))))
        (freezeOk (= freeze (freezeFor! ctx.root)))
        (silent (not (fileExists? log)))
        (good (and made (and codeOk (and pathOk (and freezeOk silent)))))]
    (do (assert good (str "prompt-only wrote " path " and freeze " freeze " without executing client; stderr " captured.errText)) good))

fn ! hookRun ctx: E2e i: Int64 args: (List String) extra: String -> l/Captured
  (let [(home (str ctx.base "/hookHome" (stringFromInt64 i)))
        (env (listAppend (list (str "PATH=" ctx.stubs ":" (resultOr (realPath "bin") "/usr/bin") ":" ctx.root "/bin:/usr/bin:/bin") (str "HOME=" home) (str "ASL_ROOT=" ctx.root) "LANG=C" (str "ASL_NATIVE_CLI_CACHE=" (nativeCliCache))) (if (stringEmpty? extra) (list) (list extra))))
        (got (l/runCapture! (listAppend (list ctx.host "run" ctx.launch) args) (some ctx.ws) (some env)))]
    (match got ((ok c) c) ((err e) (l/Captured :code 127 :out "" :errText e))))

fn ! checkPromptHooks ctx: E2e -> (List Bool)
  (let [(base (hookRun ctx 1 (list "claude" "--print-prompt") ""))
        (drop (hookRun ctx 2 (list "claude" "--print-prompt") "ASL_LAUNCH_DROP=evidence"))
        (fill (hookRun ctx 3 (list "claude" "--print-prompt") "ASL_LAUNCH_FILL_ASL=HOOK_FILL_SENTINEL"))
        (once (hookRun ctx 4 (list "claude" "--print-prompt") "ASL_LAUNCH_ONCE=true"))
        (argv (hookRun ctx 5 (list "claude" "--prompt-only" "--" "--hook-tail") ""))
        (dropOk (and (= drop.code 0) (and (stringContains? base.out "a claim holds when a tool result") (not (stringContains? drop.out "a claim holds when a tool result")))))
        (fillOk (and (= fill.code 0) (stringContains? fill.out "HOOK_FILL_SENTINEL")))
        (onceOk (and (= once.code 0) (and (stringContains? base.out "a client that compacts keeps recent turns") (not (stringContains? once.out "a client that compacts keeps recent turns")))))
        (argvOk (and (= argv.code 0) (and (stringContains? argv.out ":argv (") (stringContains? argv.out "--hook-tail"))))
        (pass (hookRun ctx 6 (list "claude" "--prompt-only" "--model" "hookModel" "--" "--hook-tail") ""))
        (passOk (and (= pass.code 0) (stringContains? pass.out "\"--model\" \"hookModel\" \"--hook-tail\"")))]
    (do (assert dropOk (str "drop removes evidence layer; exit " (stringFromInt64 drop.code) " stderr " drop.errText))
        (assert fillOk "fill substitutes ASL value")
        (assert onceOk "once omits memory layer")
        (assert argvOk "prompt-only argv includes tail")
        (assert passOk (str "args launch does not know reach the client in order, before the -- tail; exit " (stringFromInt64 pass.code) " out " pass.out " err " pass.errText))
        (list dropOk fillOk onceOk argvOk passOk)))

fn leasePidDigits s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (and (>= (charCode c) 48) (<= (charCode c) 57))) (stringChars s)))

fn ! leasePidCase ctx: E2e i: Int64 supplied: String -> l/Captured
  (let [(home (str ctx.base "/leaseHome" (stringFromInt64 i)))
        (env (listAppend (list (str "PATH=" ctx.base "/leaseStubs:/usr/bin:/bin") (str "HOME=" home) (str "ASL_ROOT=" ctx.root) "LANG=C" (str "ASL_NATIVE_CLI_CACHE=" (nativeCliCache)))
                         (if (stringEmpty? supplied) (list) (list (str "ASL_LEASE_PID=" supplied)))))
        (got (l/runCapture! (list ctx.host "run" ctx.launch "claude") (some ctx.ws) (some env)))]
    (match got ((ok c) c) ((err e) (l/Captured :code 127 :out "" :errText e))))

fn ! checkLeasePid ctx: E2e -> (List Bool)
  (let [(script "#!/bin/sh\nprintf 'pid=%s\\n' \"$ASL_LEASE_PID\"\nif [ \"$ASL_LEASE_PID\" = \"$$\" ]; then printf 'holder=self\\n'; else printf 'holder=other\\n'; fi\ncase \"$ASL_LEASE_PID\" in ''|*[!0-9]*) printf 'valid=no\\n' ;; *) printf 'valid=yes\\n'; if kill -0 \"$ASL_LEASE_PID\" 2>/dev/null; then printf 'alive=yes\\n'; else printf 'alive=no\\n'; fi ;; esac\nsleep 0.2\n")
        (stubDir (str ctx.base "/leaseStubs"))
        (path (str stubDir "/claude"))
        (made (ok? (dirCreate stubDir)))
        (written (and made (ok? (fileWrite path script))))
        (chmod (and written (run (list "chmod" "755" path) ctx.base)))
        (generated (leasePidCase ctx 1 ""))
        (passed (leasePidCase ctx 2 "424242"))
        (genLines (stringSplit generated.out "\n"))
        (genLine (optionOr (listHead genLines) ""))
        (genPid (if (stringStartsWith? genLine "pid=") (optionOr (stringSlice genLine 4 (stringLength genLine)) "") ""))
        (genOk (and (= generated.code 0) (and (leasePidDigits genPid) (= generated.out (str "pid=" genPid "\nholder=self\nvalid=yes\nalive=yes\n")))))
        (passOk (and (= passed.code 0) (= passed.out "pid=424242\nholder=other\nvalid=yes\nalive=no\n")))]
    (do (assert (and made chmod) "lease pid agent stub installed")
        (assert genOk (str "generated ASL_LEASE_PID is the exec'd agent's own live pid: " generated.out " stderr " generated.errText))
        (assert passOk (str "caller ASL_LEASE_PID passes through: " passed.out))
        (list genOk passOk)))

fn countTrue xs: (List Bool) -> Int64
  (listLength (filter (fn [(b Bool)] -> Bool b) xs))

fn ! eachIndexed rows: (List l/Asn) f: (Fn Int64 l/Asn Bool) -> (List Bool)
  (map (fn [(p (Pair Int64 l/Asn))] -> Bool (f (pairFirst p) (pairSecond p))) (zip (range 0 (listLength rows)) rows))

fn commonPrefix a: String b: String -> Int64
  (let [(n (min (stringLength a) (stringLength b)))]
    (fold (fn [(acc Int64) (i Int64)] -> Int64 (if (and (= acc i) (= (slice a i (+ i 1)) (slice b i (+ i 1)))) (+ acc 1) acc)) 0 (range 0 n)))

fn liveProbe p: l/Probe branch: String -> l/Probe
  (l/Probe :root p.root :branch branch :rules p.rules :aslSrc p.aslSrc :migrate p.migrate :asl p.asl :session p.session)

fn liveRender loaded: l/Loaded p: l/Probe client: String date: String branch: String dir: String -> String
  (resultOr (l/render loaded (liveProbe p branch)
              (l/RenderOpts :cwd "/ws/asex" :client client :mode "implement" :core false :promptDir (some dir) :drop (list) :only (list)
                            :fills (list (pair "platform" "Plat 1.0 arch") (pair "date" date)) :once false :platform "" :date "")) "")

fn staticEnd prompt: String client: String -> Int64
  (let [(marker (if (= client "claude") "__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__" "workspace /ws/asex"))]
    (optionOr (stringIndexOf prompt marker) 0))

fn ! checkLive s: Suite -> (List Bool)
  (let [(rd (fn [(f String)] -> String (resultOr (fileReadString (str "asl/grammar/" f)) "")))
        (hText (rd "harness.asn"))
        (cText (rd "clients.asn"))
        (tText (rd "tools.asn"))
        (live (l/loadSources s.paths hText cText tText))
        (old (l/loadSources s.paths (replaceAll hText (list (pair " :volatile true" ""))) cText tText))
        (p (envProbe s "asex"))
        (stableFor (fn [(ld l/Loaded) (client String)] -> Bool
                     (let [(a (liveRender ld p client "2026-01-02" "main" "/run/x-1"))
                           (b (liveRender ld p client "2027-03-04" "feature" "/run/x-22222"))
                           (end (staticEnd a client))]
                       (and (> end 1000) (and (>= (commonPrefix a b) end) (!= a b))))))
        (claudeA (liveRender live p "claude" "2026-01-02" "main" "/run/x-1"))
        (agyA (liveRender live p "agy" "2026-01-02" "main" "/run/x-1"))
        (codexA (liveRender live p "codex" "2026-01-02" "main" "/run/x-1"))
        (clients (resultOr live.clients (list)))
        (argv (resultOr (l/buildArgv clients live.paths.clients "claude" (some "/stub/bin/claude") "/run/p.md" "/run/d" false (list) false "" "" false false) (list)))
        (settings (optionOr (listHead (tailOf (dropUntil argv "--settings"))) ""))
        (usage (l/usageText))
        (r1 (stableFor live "claude")) (r2 (stableFor live "agy")) (r3 (stableFor live "codex"))
        (r4 (not (stableFor old "claude")))
        (r5 (not (stableFor old "agy")))
        (r6 (> (stringLength claudeA) 0))
        (r7 (some? (stringIndexOf claudeA "\n__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__\nworkspace /ws/asex")))
        (r8 (none? (stringIndexOf agyA "__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__")))
        (r9 (and (some? (stringIndexOf settings "\"includeGitInstructions\":false")) (some? (stringIndexOf settings "\"attribution\":{\"commit\":\"\",\"pr\":\"\"}"))))
        (r10 (and (none? (stringIndexOf usage (str "launch" ".py"))) (some? (stringIndexOf usage "asl launch <claude|codex|agy>"))))
        (r11 (and (none? (stringIndexOf hText "at most 30 minutes")) (none? (stringIndexOf hText "about 10k tokens"))))
        (r12 (and (some? (stringIndexOf cText ":workerWait \"30 minutes\"")) (some? (stringIndexOf cText ":outputCut \"10k tokens\""))))
        (r13 (some? (stringIndexOf (liveRenderOnce live p) "waits at most 30 minutes for running workers")))
        (r14 (some? (stringIndexOf codexA "cuts a long output at about 10k tokens")))]
    (do (assert r1 "live claude: prefix up to the boundary is identical across date, branch and run dir")
        (assert r2 "live agy: prefix before the environment layer is identical across date, branch and run dir")
        (assert r3 "live codex: prefix before the environment layer is identical across date, branch and run dir")
        (assert r4 "mutant: without :volatile the claude prefix differs (old order is red)")
        (assert r5 "mutant: without :volatile the agy prefix differs (old order is red)")
        (assert r6 "live claude prompt renders")
        (assert r7 "claude prompt carries the boundary line directly before the volatile tail")
        (assert r8 "agy prompt carries no boundary line")
        (assert r9 (str "claude --settings carries includeGitInstructions false and empty attribution: " settings))
        (assert r10 "usage text names asl launch and not the retired launcher")
        (assert r11 "harness.asn holds no vendor literals for agy worker wait or codex output cut")
        (assert r12 "clients.asn holds the vendor facts")
        (assert r13 "agy once layer is filled from clients.asn")
        (assert r14 "codex cut layer is filled from clients.asn")
        (list r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 r12 r13 r14)))

fn dropUntil xs: (List String) k: String -> (List String)
  (match (listHead xs)
    ((none) (list))
    ((some x) (if (= x k) xs (dropUntil (tailOf xs) k))))

fn liveRenderOnce loaded: l/Loaded p: l/Probe -> String
  (resultOr (l/render loaded p
              (l/RenderOpts :cwd "/ws/asex" :client "agy" :mode "implement" :core false :promptDir (some "/run/x-1") :drop (list) :only (list)
                            :fills (list (pair "platform" "Plat 1.0 arch") (pair "date" "2026-01-02")) :once true :platform "" :date "")) "")

fn isIdKw x: l/Asn -> Bool
  (match x ((l/asnKw n) (= n "id")) (_ false))

fn namesLoop xs: (List l/Asn) skipId: Bool prevId: Bool acc: (List String) -> (List String)
  (match (listHead xs)
    ((none) acc)
    ((some x)
      (namesLoop (tailOf xs) skipId (isIdKw x) (listAppend acc (if (and skipId prevId) (list) (namesOf x))))))

fn namesOf v: l/Asn -> (List String)
  (match v
    ((l/asnSym n) (list n))
    ((l/asnKw n) (list n))
    ((l/asnForm xs) (namesLoop xs (match (listHead xs) ((some (l/asnKw n)) (= n "layer")) (_ false)) false (list)))
    (_ (list)))

fn stringBytesOf v: l/Asn lits: (List String) -> Int64
  (match v
    ((l/asnStr s) (if (listContains? lits s) 0 (stringLength (l/asnQuote s))))
    ((l/asnForm xs) (fold (fn [(acc Int64) (x l/Asn)] -> Int64 (+ acc (stringBytesOf x lits))) 0 xs))
    (_ 0))

fn withoutBoundary text: String -> String
  (stringJoin (filter (fn [(ln String)] -> Bool (!= ln "__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__")) (stringSplit text "\n")) "\n")

fn knownNames terms: l/Asn schema: l/Asn -> (List String)
  (let [(ids (map (fn [(t l/Asn)] -> String (fstr t "id")) (l/asnForms (optionOr (fget terms "items") (l/asnForm (list))) (some "term"))))
        (enums (fold (fn [(acc (List String)) (k String)] -> (List String) (listAppend acc (namesOf (optionOr (fget schema k) (l/asnForm (list))))))
                     (list) (list "kindEnum" "factEnum" "ordEnum" "literalKinds" "modifierKeys" "layerKeys" "forms")))]
    (listAppend ids (listAppend enums (list "layer" "glossary"))))

fn unresolvedIn text: String known: (List String) -> (List String)
  (match (l/readAll (withoutBoundary text))
    ((err e) (list (str "unparsed: " e)))
    ((ok vs) (filter (fn [(n String)] -> Bool (not (listContains? known n))) (fold (fn [(acc (List String)) (v l/Asn)] -> (List String) (listAppend acc (namesOf v))) (list) vs))))

fn shareTenths text: String lits: (List String) -> Int64
  (match (l/readAll (withoutBoundary text))
    ((err _) 1000)
    ((ok vs) (/ (* 1000 (fold (fn [(acc Int64) (v l/Asn)] -> Int64 (+ acc (stringBytesOf v lits))) 0 vs)) (max 1 (stringLength text)))))

fn asnOpts client: String date: String dir: String once: Bool -> l/RenderOpts
  (l/RenderOpts :cwd "/ws/asex" :client client :mode "implement" :core false :promptDir (some dir) :drop (list) :only (list)
                :fills (list (pair "platform" "Plat 1.0 arch") (pair "date" date)) :once once :platform "" :date "")

fn asnRender2 loaded: l/Loaded p: l/Probe opts: l/RenderOpts h5: String terms: String absent: (List String) -> String
  (resultOr (l/renderAsnText loaded p opts h5 terms absent) "")

fn asnRender loaded: l/Loaded p: l/Probe opts: l/RenderOpts h5: String terms: String -> String
  (resultOr (l/renderAsnText loaded p opts h5 terms (list)) "")

fn swapLayers h5: String -> String
  (replaceAll h5 (list (pair ":static (" ":TMPX (") (pair ":volatile (" ":static (") (pair ":TMPX (" ":volatile (")))

fn lineCount text: String -> Int64
  (listLength (filter (fn [(ln String)] -> Bool (not (stringEmpty? ln))) (stringSplit text "\n")))

fn ! checkAsn s: Suite -> (List Bool)
  (let [(rd (fn [(f String)] -> String (resultOr (fileReadString (str "asl/grammar/" f)) "")))
        (h5 (rd "harness5.asn")) (tt (rd "terms.asn")) (sc (rd "terms.schema.asn"))
        (live (l/loadSources s.paths (rd "harness.asn") (rd "clients.asn") (rd "tools.asn")))
        (p (envProbe s "asex"))
        (termsV (resultOr (l/readOne tt) (l/asnForm (list))))
        (schemaV (resultOr (l/readOne sc) (l/asnForm (list))))
        (h5V (resultOr (l/readOne h5) (l/asnForm (list))))
        (known (knownNames termsV schemaV))
        (lits (map (fn [(f l/Asn)] -> String (fstr f "text")) (l/asnForms (optionOr (fget h5V "literals") (l/asnForm (list))) (some "literal"))))
        (rendered (fn [(c String) (date String) (branch String) (dir String)] -> String
                    (asnRender live (liveProbe p branch) (asnOpts c date dir false) h5 tt)))
        (clientsList (list "claude" "agy" "codex"))
        (claudeA (rendered "claude" "2026-01-02" "main" "/run/x-1"))
        (okParse (map (fn [(c String)] -> Bool
                        (let [(t (rendered c "2026-01-02" "main" "/run/x-1"))]
                          (match (l/readAll (withoutBoundary t))
                            ((ok vs) (and (> (listLength vs) 10) (= (listLength vs) (lineCount (withoutBoundary t)))))
                            ((err _) false))))
                      clientsList))
        (resolves (map (fn [(c String)] -> Bool (listEmpty? (unresolvedIn (rendered c "2026-01-02" "main" "/run/x-1") known))) clientsList))
        (seeded (asnRender live p (asnOpts "claude" "2026-01-02" "/run/x-1" false)
                  (replaceAll h5 (list (pair "(denoise atomize ground)" "(denoise atomize zzGround)"))) tt))
        (seededRed (listAny? (fn [(n String)] -> Bool (= n "zzGround")) (unresolvedIn seeded known)))
        (shares (map (fn [(c String)] -> Bool (< (shareTenths (rendered c "2026-01-02" "main" "/run/x-1") lits) 100)) clientsList))
        (shareProbe (> (shareTenths "(:a \"xxxxxxxxxxxxxxxxxxxx\")" lits) 100))
        (stable (fn [(src String) (c String)] -> Bool
                  (let [(a (asnRender live (liveProbe p "main") (asnOpts c "2026-01-02" "/run/x-1" false) src tt))
                        (b (asnRender live (liveProbe p "feature") (asnOpts c "2027-03-04" "/run/x-22222" false) src tt))
                        (end (optionOr (stringIndexOf a (if (= c "claude") "\n__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__" "(:layer :id env")) 0))]
                    (and (> end 1000) (and (>= (commonPrefix a b) end) (!= a b))))))
        (stableOk (map (fn [(c String)] -> Bool (stable h5 c)) clientsList))
        (stableMutant (not (stable (swapLayers h5) "claude")))
        (gloss (and (some? (stringIndexOf claudeA "(:glossary (:term :id ")) (some? (stringIndexOf claudeA "(:term :id mention :kind property"))))
        (glossNoDup (= (listLength (stringSplit claudeA "(:term :id mention ")) 2))
        (glossSkips (none? (stringIndexOf claudeA "(:term :id alias ")))
        (litsInlined (and (some? (stringIndexOf claudeA ":from \"asl/grammar/capabilities.asn\"")) (none? (stringIndexOf claudeA "capabilitiesPath"))))
        (fillsApplied (and (some? (stringIndexOf claudeA "(:fill cwd \"/ws/asex\")")) (some? (stringIndexOf claudeA "(:fill date \"2026-01-02\")"))))
        (agyA (rendered "agy" "2026-01-02" "main" "/run/x-1"))
        (agyFills (and (some? (stringIndexOf agyA "(:fill promptDir \"/run/x-1\")")) (some? (stringIndexOf agyA "(:fill note \"/run/x-1/note.md\")"))))
        (boundary (and (some? (stringIndexOf claudeA "\n__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__\n(:layer :id env")) (none? (stringIndexOf agyA "__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__"))))
        (universal (listAll? (fn [(f String)] -> Bool (some? (stringIndexOf claudeA f)))
                     (list "(:needs notDone (:each (stub deadFlag missingDependency)))" "(:covers enumeration (:all searched))" "(:not (:dominates signalOverNoise completeness))"
                           "(:needs exact scope :for (:each figure))" "(:not edit :when gateUnrunnable)" "(:holdsWhen methodClaim commandResult)")))
        (codexA (rendered "codex" "2026-01-02" "main" "/run/x-1"))
        (has (fn [(t String) (w String)] -> Bool (some? (stringIndexOf t w))))
        (ownRules (fn [(t String) (mine String) (others (List String))] -> Bool (and (has t mine) (not (listAny? (fn [(o String)] -> Bool (has t o)) others)))))
        (clientCodex (ownRules codexA "(:via edit applyPatch :lit " (list "replaceFileContent" "systemReminder")))
        (clientAgy (ownRules agyA "(:via edit (writeToFile replaceFileContent))" (list "allSettled" "systemReminder" "applyPatch")))
        (clientClaude (ownRules claudeA "(:isA systemReminder applicationText)" (list "allSettled" "replaceFileContent" "applyPatch")))
        (glossBytes (stringLength (optionOr (listHead (filter (fn [(ln String)] -> Bool (stringStartsWith? ln "(:glossary ")) (stringSplit claudeA "\n"))) "")))
        (glossTrim (< glossBytes 5500))
        (loadBearing (listAll? (fn [(id String)] -> Bool (has claudeA (str "(:term :id " id " "))) (list "mention" "use" "resolution" "done" "claimed" "exact" "generalization" "scope"))
                     )
        (trimmed (and (not (has claudeA "(:term :id verification ")) (and (not (has claudeA "(:term :id principal ")) (not (has claudeA "(:term :id valueOrder ")))))
        (modeRender (fn [(c String) (m String)] -> String (asnRender live p (with (asnOpts c "2026-01-02" "/run/x-1" false) :mode m) h5 tt)))
        (scoutA (modeRender "claude" "scout"))
        (implA (modeRender "claude" "implement"))
        (modeBind (and (has scoutA "(:mode scout (:attractor verification ") (and (has scoutA "(:attractor completeness :prefers allSitesListed :shadow firstHitStop)") (and (not (has scoutA "nonVacuity")) (and (not (has scoutA "(:mode implement")) (and (not (has scoutA ":from taskKind")) (and (has implA "(:mode implement ") (and (not (has implA "(:attractor completeness")) (has (modeRender "claude" "grade") "(:attractor nonVacuity ")))))))))
        (sizesOf (fn [(c String)] -> (List Int64) (map (fn [(m String)] -> Int64 (stringLength (modeRender c m))) (list "scout" "implement" "grade" "distill"))))
        (claudeSizes (sizesOf "claude"))
        (promptCap (listAll? (fn [(n Int64)] -> Bool (<= n 5500)) claudeSizes))
        (termCount (- (listLength (stringSplit claudeA "(:term :id ")) 1))
        (glossCap (<= termCount 12))
        (lost (listAll? (fn [(f String)] -> Bool (has claudeA f))
                (list "(:needs verdictNo (:each blocker))" "(:needs claim anchor :from toolResult)" "(:needs generalization (:each searchedSite))"
                      "(:covers resolution (alias reExport tableEntry storedFn test recursion forwarder))" "(:covers mockTest mock)" "(:holdsWhen measurement inputsRan)" "(:needs ruledOutSite siteName)")))
        (cutValue (and (has codexA "(:fill outputCut \"10k tokens\")") (has (asnRender live p (asnOpts "agy" "2026-01-02" "/run/x-1" true) h5 tt) "(:fill waitLimit \"30 minutes\")")))
        (codexDistill (and (has codexA "(:holdsWhen persist requestResolved)") (not (has claudeA "persist"))))
        (absentList (list "capabilitiesPath" "clientsPath" "languageTopic"))
        (foreignA (asnRender2 live p (asnOpts "claude" "2026-01-02" "/run/x-1" false) h5 tt absentList))
        (noAsex (and (not (has foreignA "asl/grammar/")) (and (has claudeA "asl/grammar/capabilities.asn") (and (has foreignA "(:layer :id capabilities") (has foreignA "(:replaces absent fallback)")))))
        (absentLive (and (listEmpty? (l/absentPaths h5 ".")) (listAll? (fn [(id String)] -> Bool (listContains? (l/absentPaths h5 "/nonexistent/ws") id)) absentList)))
        (badGrammar (l/renderAsnText live p (asnOpts "claude" "2026-01-02" "/run/x-1" false) "(:harness" tt (list)))]
    (do (assert (listAll? (fn [(b Bool)] -> Bool b) okParse) (str "asn render parses as balanced one-form-per-line ASN for claude agy codex: " (stringJoin (map (fn [(b Bool)] -> String (if b "y" "n")) okParse) "")))
        (assert (listAll? (fn [(b Bool)] -> Bool b) resolves)
                (str "every symbol resolves to a terms id or schema key: " (stringJoin (listTake (unresolvedIn claudeA known) 8) " ")))
        (assert seededRed "seeded unknown symbol is reported unresolved")
        (assert (listAll? (fn [(b Bool)] -> Bool b) shares) (str "plaintextShare under 0.10 for each client: " (stringFromInt64 (shareTenths claudeA lits)) " per mille claude"))
        (assert shareProbe "the share measure reacts to string-heavy text")
        (assert (listAll? (fn [(b Bool)] -> Bool b) stableOk) (str "asn prefix byte-stable across date, branch and pid for each client: " (stringJoin (map (fn [(b Bool)] -> String (if b "y" "n")) stableOk) "")))
        (assert stableMutant "mutant: volatile layers first makes the prefix unstable")
        (assert gloss "glossary carries the rich defs the prompt references")
        (assert glossNoDup "glossary lists a term once")
        (assert glossSkips "glossary skips classification-only terms")
        (assert litsInlined "literals are inlined where referenced")
        (assert fillsApplied "explicit fills carry their values")
        (assert agyFills "agy fills promptDir and note")
        (assert boundary "claude boundary precedes the volatile tail, agy has none")
        (assert (err? badGrammar) "a malformed harness5 is an error, not a prompt")
        (assert universal "universal forms render: blockers listed, enumeration, figures, gate-unrunnable abstain, method claims cite a result")
        (assert (and clientCodex (and clientAgy clientClaude)) (str "each client renders its own rules and none of the others: " (stringJoin (map (fn [(b Bool)] -> String (if b "y" "n")) (list clientCodex clientAgy clientClaude)) "")))
        (assert (and glossTrim trimmed) (str "glossary trimmed: " (stringFromInt64 glossBytes) " bytes, attractor, actor and value terms absent; claude render " (stringFromInt64 (stringLength claudeA)) " bytes"))
        (assert loadBearing "load-bearing glossary terms stay")
        (assert modeBind (str "asn render binds the attractors of --mode with inline defs: " (stringJoin (map stringFromInt64 claudeSizes) " ")))
        (assert promptCap (str "claude render at most 5500 bytes in every mode (cwd /ws/asex): " (stringJoin (map stringFromInt64 claudeSizes) " ") " agy " (stringJoin (map stringFromInt64 (sizesOf "agy")) " ") " codex " (stringJoin (map stringFromInt64 (sizesOf "codex")) " ")))
        (assert glossCap (str "glossary holds at most 12 terms: " (stringFromInt64 termCount)))
        (assert lost "lost clauses render: recursion, forwarders, mock, measurement inputs, anchors, blockers, searched sites")
        (assert cutValue "codexCut and agyOnce print their client values")
        (assert codexDistill "codex persistence rule is a client row, not appended text")
        (assert noAsex "a render outside asex omits capabilities, clients and tools paths and keeps the layer")
        (assert absentLive "absentPaths is empty in the asex tree and lists every path literal elsewhere")
        (listAppend okParse (listAppend resolves (listAppend shares (listAppend stableOk (list seededRed shareProbe stableMutant gloss glossNoDup glossSkips litsInlined fillsApplied agyFills boundary (err? badGrammar) universal (and clientCodex (and clientAgy clientClaude)) (and glossTrim trimmed) loadBearing modeBind promptCap glossCap lost cutValue noAsex absentLive codexDistill)))))))

fn colScript -> String
  "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$STUB_LOG\"\ncat > \"$STUB_LOG.in\"\nif [ -n \"$STUB_RMDIR\" ]; then rm -rf $STUB_RMDIR; fi\nprintf 'out\\n'\nexit ${STUB_EXIT:-0}\n"

fn colHome ctx: E2e i: Int64 -> String
  (str ctx.base "/colHome" (stringFromInt64 i))

fn colLog ctx: E2e i: Int64 -> String
  (str ctx.base "/colLog" (stringFromInt64 i))

fn ! colRun ctx: E2e i: Int64 args: (List String) exitCode: String rmDir: Bool stdin: String -> l/Captured
  (let [(home (colHome ctx i))
        (stubDir (str ctx.base "/colStubs"))
        (runRoot (str home "/.asl/run/harness"))
        (made (and (ok? (dirCreate runRoot)) (ok? (dirCreate stubDir))))
        (stubs (listAll? (fn [(c String)] -> Bool (and (ok? (fileWrite (str stubDir "/" c) (colScript))) (run (list "chmod" "755" (str stubDir "/" c)) ctx.base))) (list "claude" "codex" "agy")))
        (envRows (listAppend (list (str "PATH=" stubDir ":/usr/bin:/bin") (str "HOME=" home) (str "STUB_LOG=" (colLog ctx i)) (str "STUB_EXIT=" exitCode) "LANG=C" (str "ASL_ROOT=" ctx.root) (str "ASL_NATIVE_CLI_CACHE=" (nativeCliCache)))
                             (if rmDir (list (str "STUB_RMDIR=" runRoot "/" (optionOr (listHead args) "x") "-*")) (list))))
        (cmd "stdin=\"$1\"; host=\"$2\"; launch=\"$3\"; shift 3; printf '%s' \"$stdin\" | \"$host\" run \"$launch\" \"$@\"")
        (got (l/runCapture! (listAppend (list "/bin/sh" "-c" cmd "sh" stdin ctx.host ctx.launch) args) (some ctx.ws) (some envRows)))]
    (do (assert (and made stubs) "collector stubs installed")
        (match got ((ok c) c) ((err e) (l/Captured :code 127 :out "" :errText e)))))

fn ! runFileOf home: String client: String -> (Pair String String)
  (let [(root (str home "/.asl/run/harness"))
        (dirs (filter (fn [(d String)] -> Bool (stringStartsWith? d (str client "-"))) (resultOr (dirList root) (list))))
        (dir (str root "/" (optionOr (listHead dirs) "none")))]
    (pair dir (resultOr (fileReadString (str dir "/run.asn")) "")))

fn promptPathOf out: String -> String
  (match (stringIndexOf out ":prompt \"")
    ((none) "")
    ((some i)
      (let [(after (optionOr (stringSlice out (+ i 9) (stringLength out)) ""))]
        (match (stringIndexOf after "\" :promptChars ") ((some j) (optionOr (stringSlice after 0 j) "")) ((none) "")))))

fn ! checkAsnCli ctx: E2e -> (List Bool)
  (let [(pp (hookRun ctx 20 (list "claude" "--format" "asn" "--print-prompt") ""))
        (proseA (hookRun ctx 25 (list "claude" "--print-prompt") ""))
        (proseB (hookRun ctx 26 (list "claude" "--format" "prose" "--print-prompt") ""))
        (bad (hookRun ctx 24 (list "claude" "--format" "bogus" "--print-prompt") ""))
        (claudeDry (hookRun ctx 23 (list "claude" "--format" "asn" "--ask" "--dry-run" "--" "-p" "hello" "--output-format" "json") ""))
        (codexDry (hookRun ctx 21 (list "codex" "--format" "asn" "--dry-run" "--" "exec" "hello") ""))
        (agyDry (hookRun ctx 22 (list "agy" "--format" "asn" "--dry-run" "--" "-p" "hello") ""))
        (agyPath (promptPathOf agyDry.out))
        (agyWorker (resultOr (fileReadString (str (optionOr (stringSlice agyPath 0 (optionOr (stringIndexOf agyPath "asl.md") 0)) "") "asl-worker.md")) ""))
        (agyMain (resultOr (fileReadString agyPath) ""))
        (codexFile (resultOr (fileReadString (promptPathOf codexDry.out)) ""))
        (claudeFile (resultOr (fileReadString (promptPathOf claudeDry.out)) ""))
        (printed (and (= pp.code 0) (and (stringStartsWith? pp.out "(:layer :id orient") (and (some? (stringIndexOf pp.out "(:glossary ")) (some? (stringIndexOf pp.out "(:fill cwd "))))))
        (proseSame (and (= proseA.code 0) (and (= proseA.out proseB.out) (and (not (stringStartsWith? proseA.out "(:layer")) (> (stringLength proseA.out) 1000)))))
        (badOk (and (= bad.code 2) (some? (stringIndexOf bad.errText "--format takes prose or asn"))))
        (oneShotClaude (and (= claudeDry.code 0) (and (some? (stringIndexOf claudeDry.out "\"-p\" \"hello\" \"--output-format\" \"json\")")) (and (none? (stringIndexOf claudeDry.out "--format")) (and (none? (stringIndexOf claudeDry.out "--ask")) (stringStartsWith? claudeFile "(:layer"))))))
        (oneShotCodex (and (= codexDry.code 0) (and (and (some? (stringIndexOf codexDry.out "\"exec\" \"-c\" ")) (some? (stringIndexOf codexDry.out "\"hello\"))"))) (and (none? (stringIndexOf codexDry.out "--format")) (stringStartsWith? codexFile "(:layer")))))
        (oneShotAgy (and (= agyDry.code 0) (and (some? (stringIndexOf agyDry.out "\"-p\" \"hello\")")) (and (none? (stringIndexOf agyDry.out "--format")) (some? (stringIndexOf agyMain "(:layer :id orient"))))))
        (cdxAppend (hookRun ctx 27 (list "codex" "--codex-mode" "append" "--format" "asn" "--dry-run") ""))
        (cdxReplace (hookRun ctx 28 (list "codex" "--codex-mode" "replace" "--format" "asn" "--dry-run") ""))
        (cdxDefault (hookRun ctx 31 (list "codex" "--format" "asn" "--dry-run") ""))
        (cdxProse (hookRun ctx 32 (list "codex" "--dry-run") ""))
        (defaultOk (and (= cdxDefault.code 0) (and (some? (stringIndexOf cdxDefault.out "model_instructions_file=")) (and (none? (stringIndexOf cdxDefault.out "developer_instructions")) (and (= cdxProse.code 0) (and (some? (stringIndexOf cdxProse.out "model_instructions_file=")) (none? (stringIndexOf cdxProse.out "developer_instructions"))))))))
        (cdxBad (hookRun ctx 29 (list "claude" "--codex-mode" "append" "--dry-run") ""))
        (cdxBad2 (hookRun ctx 30 (list "codex" "--codex-mode" "merge" "--dry-run") ""))
        (cdxFile (resultOr (fileReadString (promptPathOf cdxAppend.out)) ""))
        (appendOk (and (= cdxAppend.code 0) (and (some? (stringIndexOf cdxAppend.out "\"developer_instructions=")) (and (none? (stringIndexOf cdxAppend.out "model_instructions_file")) (and (none? (stringIndexOf cdxAppend.out "--codex-mode")) (stringStartsWith? cdxFile "(:layer"))))))
        (replaceOk (and (= cdxReplace.code 0) (and (some? (stringIndexOf cdxReplace.out "model_instructions_file=")) (none? (stringIndexOf cdxReplace.out "developer_instructions")))))
        (badMode (and (= cdxBad.code 2) (and (some? (stringIndexOf cdxBad.errText "--codex-mode applies to codex only")) (and (= cdxBad2.code 2) (some? (stringIndexOf cdxBad2.errText "--codex-mode takes replace or append"))))))
        (workerOk (and (some? (stringIndexOf agyMain "(:layer :id delegate")) (and (some? (stringIndexOf agyWorker "(:layer :id orient")) (and (some? (stringIndexOf agyWorker "(:layer :id workerReport")) (none? (stringIndexOf agyWorker "(:layer :id delegate"))))))]
    (do (assert printed (str "--format asn --print-prompt prints ASN with glossary and fills: exit " (stringFromInt64 pp.code) " " pp.errText))
        (assert proseSame "--format prose is the default render, byte for byte")
        (assert badOk (str "--format bogus exits 2: " bad.errText))
        (assert oneShotClaude (str "claude -p ... --output-format json passes through untouched with --format asn and --ask: " claudeDry.out claudeDry.errText))
        (assert oneShotCodex (str "codex exec tail passes through untouched with --format asn: " codexDry.out codexDry.errText))
        (assert oneShotAgy (str "agy -p tail passes through untouched with --format asn: " agyDry.out agyDry.errText))
        (assert appendOk (str "--codex-mode append passes the ASN as -c developer_instructions and drops model_instructions_file: " cdxAppend.errText))
        (assert replaceOk "--codex-mode replace keeps model_instructions_file")
        (assert defaultOk "codex default is replace with --format asn and with prose")
        (assert badMode "--codex-mode is codex only and takes replace or append")
        (assert workerOk "agy worker prompt drops delegate and agyOnce and keeps the report layer in ASN")
        (list printed proseSame badOk oneShotClaude oneShotCodex oneShotAgy workerOk appendOk replaceOk badMode defaultOk)))

fn ! checkCollector ctx: E2e -> (List Bool)
  (let [(a (colRun ctx 1 (list "claude" "-p" "hi") "0" false "stdin-payload"))
        (ra (runFileOf (colHome ctx 1) "claude"))
        (digestA (sha (resultOr (fileReadString (str (pairFirst ra) "/claude.md")) "")))
        (logA (resultOr (fileReadString (colLog ctx 1)) ""))
        (inA (resultOr (fileReadString (str (colLog ctx 1) ".in")) ""))
        (b (colRun ctx 2 (list "claude" "-p" "hi") "7" false ""))
        (rb (runFileOf (colHome ctx 2) "claude"))
        (c (colRun ctx 3 (list "claude" "-p" "hi") "5" true ""))
        (d (colRun ctx 4 (list "codex" "exec" "hi") "0" false ""))
        (rd (runFileOf (colHome ctx 4) "codex"))
        (receiptOk (and (= a.code 0) (and (stringContains? a.out "out") (and (stringContains? (pairSecond ra) ":client claude") (and (stringContains? (pairSecond ra) ":exit 0")
                    (stringContains? (pairSecond ra) (str ":promptDigest \"" digestA "\"")))))))
        (stdinOk (and (= inA "stdin-payload") (and (stringContains? logA "-p\nhi") (not (stringEmpty? digestA)))))
        (exitOk (and (= b.code 7) (stringContains? (pairSecond rb) ":exit 7")))
        (failSoft (and (= c.code 5) (stringContains? c.errText "launch: collect:")))
        (codexOk (and (= d.code 0) (and (stringContains? (pairSecond rd) ":client codex") (stringContains? (pairSecond rd) ":exit 0"))))]
    (do (assert receiptOk (str "one-shot claude run writes run.asn with the prompt digest and exit 0: " a.errText " " (pairSecond ra)))
        (assert stdinOk (str "the child gets the launcher's stdin: " inA " log " logA))
        (assert exitOk (str "the child's exit code is propagated and recorded: " (stringFromInt64 b.code) " " (pairSecond rb)))
        (assert failSoft (str "a collect error is one stderr line and does not change the exit: " (stringFromInt64 c.code) " " c.errText))
        (assert codexOk (str "one-shot codex exec is collected too: " d.errText " " (pairSecond rd)))
        (list receiptOk stdinOk exitOk failSoft codexOk)))

fn ! checkSweep ctx: E2e -> (List Bool)
  (let [(first (colRun ctx 5 (list "claude") "0" false ""))
        (r1 (runFileOf (colHome ctx 5) "claude"))
        (dir (pairFirst r1))
        (startText (resultOr (fileReadString (str dir "/start.asn")) ""))
        (digest (sha (resultOr (fileReadString (str dir "/claude.md")) "")))
        (beforeSweep (pairSecond r1))
        (second (colRun ctx 5 (list "claude" "--print-prompt") "0" false ""))
        (r2 (runFileOf (colHome ctx 5) "claude"))
        (home6 (colHome ctx 6))
        (live (str home6 "/.asl/run/harness/claude-1"))
        (madeLive (and (ok? (dirCreate live)) (ok? (fileWrite (str live "/start.asn") "(:launchStart :client claude :startedAt 1 :cwd \"/x\" :promptDigest \"d\")\n"))))
        (done (str home6 "/.asl/run/harness/codex-99999999"))
        (madeDone (and (ok? (dirCreate done)) (and (ok? (fileWrite (str done "/start.asn") "(:launchStart :client codex :startedAt 1 :cwd \"/x\" :promptDigest \"d\")\n")) (ok? (fileWrite (str done "/run.asn") "kept\n")))))
        (third (colRun ctx 6 (list "claude" "--print-prompt") "0" false ""))
        (startOk (and (= first.code 0) (and (stringContains? startText "(:launchStart :client claude :startedAt ") (and (stringContains? startText (str ":promptDigest \"" digest "\"")) (stringEmpty? beforeSweep)))))
        (sweptOk (and (= second.code 0) (and (stringContains? (pairSecond r2) ":client claude") (and (stringContains? (pairSecond r2) ":exit -1") (stringContains? (pairSecond r2) (str ":promptDigest \"" digest "\""))))))
        (liveOk (and (fileExists? (str live "/start.asn")) (not (fileExists? (str live "/run.asn")))))
        (keptOk (= (resultOr (fileReadString (str done "/run.asn")) "") "kept\n"))]
    (do (assert startOk (str "an exec'd launch leaves start.asn with the prompt digest: " first.errText startText))
        (assert sweptOk (str "the next launch collects the dead run that has no run.asn: " second.errText (pairSecond r2)))
        (assert (and madeLive (and madeDone (= third.code 0))) "sweep fixtures built")
        (assert liveOk "a run whose pid is alive is not swept")
        (assert keptOk "a dir that already has run.asn is not collected again and survives the prune")
        (list startOk sweptOk liveOk keptOk)))

fn ! runTests -> Bool
  (match (fileReadString (fixturePath))
    ((err e) (do (assert false (str "fixture " (fixturePath) ": " e)) false))
    ((ok text)
      (match (l/readOne text)
        ((err e) (do (assert false (str "fixture parse: " e)) false))
        ((ok fx)
          (let [(s (buildSuite fx))
                (base0 (str "/tmp/aslLaunchTest-" (stringFromInt64 (procSelf))))
                (mk (dirCreate base0))
                (base (resultOr (realPath base0) base0))
                (truthy (map checkTruthy (section fx "truthy")))
                (reader (map checkReader (section fx "reader")))
                (renders (map (fn [(r l/Asn)] -> Bool (checkRender s r)) (section fx "render")))
                (argvs (map (fn [(r l/Asn)] -> Bool (checkArgv s r)) (section fx "argv")))
                (writes (eachIndexed (section fx "write") (fn [(i Int64) (r l/Asn)] -> Bool (checkWrite s base i r))))
                (mains (eachIndexed (section fx "main") (fn [(i Int64) (r l/Asn)] -> Bool (checkMain s base i r))))
                (facts (map (fn [(r l/Asn)] -> Bool (checkFacts base r)) (section fx "facts")))
                (whichBuilt (buildWhich base))
                (whiches (map (fn [(r l/Asn)] -> Bool (checkWhich base r)) (section fx "which")))
                (e2eSuite (buildE2e s base))
                (leasePid (match e2eSuite ((err e) (do (assert false (str "lease pid setup: " e)) (list false false))) ((ok ctx) (checkLeasePid ctx))))
                (live (checkLive s))
                (asnLive (checkAsn s))
                (asnCli (match e2eSuite ((err e) (do (assert false (str "asn setup: " e)) (list false))) ((ok ctx) (checkAsnCli ctx))))
                (collector (match e2eSuite ((err e) (do (assert false (str "collector setup: " e)) (list false))) ((ok ctx) (checkCollector ctx))))
                (sweep (match e2eSuite ((err e) (do (assert false (str "sweep setup: " e)) (list false))) ((ok ctx) (checkSweep ctx))))
                (asnAll (listAppend asnLive (listAppend asnCli (listAppend collector sweep))))
                (promptOnly (match e2eSuite ((err e) (do (assert false (str "prompt-only setup: " e)) false)) ((ok ctx) (checkPromptOnly ctx 99))))
                (hooks (match e2eSuite ((err e) (do (assert false (str "hook setup: " e)) (list false false false false))) ((ok ctx) (checkPromptHooks ctx))))
                (e2es (match e2eSuite
                        ((err e) (do (assert false (str "e2e setup: " e)) (list false)))
                        ((ok ctx) (eachIndexed (section fx "e2e") (fn [(i Int64) (r l/Asn)] -> Bool (checkE2e ctx i r))))))
                (all (listAppend truthy (listAppend reader (listAppend renders (listAppend argvs (listAppend writes (listAppend mains (listAppend facts (listAppend whiches (listAppend leasePid (listAppend hooks (cons promptOnly e2es))))))))))))
                (cleaned (pathRemove base))]
            (do (assert (ok? mk) "scratch dir created")
                (assert whichBuilt "which fixture dirs built")
                (assert (= (listLength truthy) 5) "5 truthy cases")
                (assert (= (listLength reader) 57) "57 reader cases")
                (assert (= (listLength renders) 197) "197 render cases")
                (assert (= (listLength argvs) 386) "386 argv cases")
                (assert (= (listLength writes) 15) "15 write cases")
                (assert (= (listLength mains) 21) "21 main cases")
                (assert (= (listLength facts) 14) "14 facts cases")
                (assert (= (listLength whiches) 13) "13 which cases")
                (assert (= (listLength e2es) 23) "23 end-to-end cases")
                (assert (= (listLength leasePid) 2) "2 lease pid cases")
                (assert (= (countTrue live) 14) "14 live-grammar cases")
                (assert promptOnly "prompt-only writes prompt, reports freeze and does not execute")
                (assert (ok? cleaned) "scratch dir removed")
                (assert (= (countTrue all) 739) "739 cases pass")
                (assert (= (listLength asnAll) 55) "55 asn, collector and sweep checks")
                (println (str "(:launchParity :cases " (stringFromInt64 (listLength all)) " :passed " (stringFromInt64 (countTrue all)) ")"))
                (println (str "(:launchAsn :checks " (stringFromInt64 (listLength asnAll)) " :passed " (stringFromInt64 (countTrue asnAll)) ")"))
                (and (= (countTrue all) (listLength all)) (= (countTrue asnAll) (listLength asnAll)))))))))
