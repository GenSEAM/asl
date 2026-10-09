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
  (mt (fget row key) ((some v) (optionOr (l/textOf v) "")) ((none) ""))

fn fint row: l/Asn key: String -> String
  (mt (fget row key) ((some v) (mt v ((l/asnInt n) n) (_ "none"))) ((none) "none"))

fn fhas row: l/Asn key: String -> Bool
  (some? (fget row key))

fn fbool row: l/Asn key: String -> Bool
  (= (fstr row key) "true")

fn itemsOf v: l/Asn -> (List l/Asn)
  (mt v ((l/asnForm xs) xs) (_ (list)))

fn flist row: l/Asn key: String -> (List String)
  (mt (fget row key) ((some v) (map (fn [(x l/Asn)] -> String (optionOr (l/textOf x) "")) (itemsOf v))) ((none) (list)))

fn section fx: l/Asn key: String -> (List l/Asn)
  (mt (fget fx key) ((some v) (itemsOf v)) ((none) (list)))

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
        (kind (mt row ((l/asnForm xs) (mt (listHead xs) ((some h) (mt h ((l/asnKw k) k) (_ ""))) ((none) ""))) (_ "")))
        (got (cond
               ((= kind "all") (mt (l/readAll text) ((ok vs) (pair "dump" (stringJoin (map l/asnDump vs) " "))) ((err e) (pair "error" e))))
               ((= kind "one") (mt (l/readOne text) ((ok v) (pair "dump" (l/asnDump v))) ((err e) (pair "error" e))))
               ((= kind "get") (mt (l/readOne text) ((ok v) (pair "dump" (mt (l/asnGet v (fstr row "key")) ((some x) (l/asnDump x)) ((none) "none")))) ((err e) (pair "error" e))))
               ((= kind "forms") (mt (l/readOne text)
                                   ((ok v) (pair "dump" (stringJoin (map l/asnDump (l/asnForms v (if (stringEmpty? (fstr row "head")) (none) (some (fstr row "head"))))) " ")))
                                   ((err e) (pair "error" e))))
               (else (pair "kind" kind))))
        (want (if (fhas row "error") (pair "error" (fstr row "error")) (pair "dump" (fstr row "dump"))))]
    (do (assert (= got want) (str "reader " kind " " (l/asnDump (l/asnStr text)) ": got " (pairSecond got) " want " (pairSecond want)))
        (= got want)))

fn srcText row: l/Asn key: String base: String -> String
  (mt (fget row key) ((some v) (mt v ((l/asnStr s) s) (_ base))) ((none) base))

(schema Suite (:f fx l/Asn) (:f paths l/Paths) (:f base l/Loaded) (:f loaded (List (Pair String l/Loaded))) (:f platform String) (:f date String))

fn loadedOf s: Suite tag: String -> l/Loaded
  (if (or (stringEmpty? tag) (= tag "real"))
    s.base
    (optionOr (mt (listHead (filter (fn [(p (Pair String l/Loaded))] -> Bool (= (pairFirst p) tag)) s.loaded)) ((some p) (some (pairSecond p))) ((none) (none))) s.base))

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
  (mt (listHead (filter (fn [(p (Pair String String))] -> Bool (= (pairFirst p) k)) xs)) ((some p) (some (pairSecond p))) ((none) (none)))

fn fillPairs row: l/Asn -> (List (Pair String String))
  (mt (fget row "fills")
    ((some v) (map (fn [(p l/Asn)] -> (Pair String String)
                     (let [(xs (itemsOf p))]
                       (pair (optionOr (mt (listHead xs) ((some k) (l/textOf k)) ((none) (none))) "")
                             (optionOr (mt (listHead (tailOf xs)) ((some k) (l/textOf k)) ((none) (none))) ""))))
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
                (mt got
                  ((ok t) (and (= (sha t) (fstr row "sha")) (= (stringFromInt64 (stringLength t)) (fint row "len"))))
                  ((err _) false))))]
    (do (assert good (str label ": got " (mt got ((ok t) (str "sha " (sha t) " " t)) ((err e) (str "error " e))) " want " (if (fhas row "error") (fstr row "error") (fstr row "sha"))))
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
                          " ask " (fstr row "ask") " extra " (showList (flist row "extra")) ": got " (mt got ((ok a) (showList a)) ((err e) e))))
        good))

fn ! walkTree root: String dir: String -> (List (Pair String String))
  (mt (dirList dir)
    ((err _) (list))
    ((ok names)
      (let [(full (fn [(n String)] -> String (str dir "/" n)))
            (isDir (fn [(n String)] -> Bool (mt (fileStat (str dir "/" n)) ((ok st) st.isDir) ((err _) false))))
            (rel (fn [(n String)] -> String (optionOr (stringSlice (str dir "/" n) (+ (stringLength root) 1) (stringLength (str dir "/" n))) n)))
            (files (map (fn [(n String)] -> (Pair String String)
                          (pair (rel n) (sha (stringReplace (resultOr (fileReadString (full n)) "") root "{run}"))))
                        (filter (fn [(n String)] -> Bool (not (isDir n))) names)))
            (subs (fold (fn [(acc (List (Pair String String))) (n String)] -> (List (Pair String String)) (listAppend acc (walkTree root (full n))))
                        (list) (filter isDir names)))]
        (listAppend files subs))))

fn fileRows row: l/Asn -> (List (Pair String String))
  (mt (fget row "files")
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
                  (mt got
                    ((ok p) (and (= (replaceAll (pairFirst p) subs) (fstr row "path")) (= (replaceAll (pairSecond p) subs) (fstr row "extraDir"))))
                    ((err _) false))))
        (treeOk (= tree (fileRows row)))]
    (do (assert pre (str "write " client ": note.md seeded"))
        (assert (not (stringEmpty? prompt)) (str "write " client ": prompt renders"))
        (assert headOk (str "write " (fstr row "sources") " " client " once " (fstr row "once") " bare " (fstr row "bare") " shellOnly " (fstr row "shellOnly") ": got "
                            (mt got ((ok p) (str (pairFirst p) " " (pairSecond p))) ((err e) e))))
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
  (mt (l/runCapture! argv (some cwd) (none))
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
    (mt got
      ((err e) (do (assert false (str "facts " (fstr row "ws") ": " e)) false))
      ((ok p)
        (let [(fs (l/factsOf (list) "claude" "implement" false p))
              (fact (fn [(k String)] -> String (mt (listHead (filter (fn [(q (Pair String Bool))] -> Bool (= (pairFirst q) k)) fs)) ((some q) (if (pairSecond q) "true" "false")) ((none) "?"))))
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

fn ! buildE2e s: Suite base: String -> (Result E2e String)
  (let [(e (str base "/e2e")) (root (str base "/e2e/root")) (stubs (str base "/e2e/stubs")) (ws (str base "/e2e/ws"))
        (src (optionOr (fget s.fx "sources") (l/asnForm (list))))
        (made (and (ok? (dirCreate (str root "/asl/grammar"))) (ok? (dirCreate stubs))))
        (grammar (and (ok? (fileWrite (str root "/asl/grammar/harness.asn") (fstr src "harness")))
                      (and (ok? (fileWrite (str root "/asl/grammar/clients.asn") (fstr src "clients"))) (ok? (fileWrite (str root "/asl/grammar/tools.asn") (fstr src "tools"))))))
        (stubsOk (listAll? (fn [(c String)] -> Bool (and (ok? (fileWrite (str stubs "/" c) (stubScript))) (run (list "chmod" "755" (str stubs "/" c)) base)))
                           (list "claude" "codex" "agy")))
        (wsOk (buildWs ws (list "git")))]
    (if (not (and made (and grammar (and stubsOk wsOk))))
      (err "e2e setup failed")
      (mt (realPath "asl/host/out/asl-host")
        ((err e) (err (str "asl-host: " e)))
        ((ok host)
          (mt (realPath "asl/packages/asl-harness/src/launch.asl")
            ((err e) (err (str "launch.asl: " e)))
            ((ok launch)
              (mt (l/platform!)
                ((err e) (err e))
                ((ok plat)
                  (mt (l/today!)
                    ((err e) (err e))
                    ((ok day) (ok (E2e :base e :root root :stubs stubs :ws ws :host host :launch launch :platform plat :date day))))))))))))

fn clientOfDir d: String -> String
  (mt (listHead (filter (fn [(c String)] -> Bool (stringStartsWith? d (str c "-"))) (list "claude" "codex" "agy"))) ((some c) c) ((none) ""))

fn promptBody client: String text: String -> String
  (if (= client "agy")
    (mt (stringIndexOf text "---\n\n") ((some i) (optionOr (stringSlice text (+ i 5) (stringLength text)) "")) ((none) text))
    text)

fn ! promptFacts raw: String subs: (List (Pair String String)) client: String -> (Pair String String)
  (mt (stringIndexOf raw ":prompt \"")
    ((none) (pair raw ""))
    ((some i)
      (let [(after (optionOr (stringSlice raw (+ i 9) (stringLength raw)) ""))
            (path (mt (stringIndexOf after "\" :promptChars ") ((some j) (optionOr (stringSlice after 0 j) "")) ((none) "")))
            (numStart (mt (stringIndexOf raw ":promptChars ") ((some j) (+ j 13)) ((none) 0)))
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
                   (str "STUB_MODE=" (fstr row "stubMode")) "LANG=C" (str "ASL_ROOT=" ctx.root)))
        (res (l/runCapture! (listAppend (list ctx.host "run" ctx.launch) args) (some ctx.ws) (some env)))]
    (mt res
      ((err e) (do (assert false (str "e2e " (showList args) ": " e)) false))
      ((ok c)
        (let [(dirs (resultOr (dirList runRoot) (list)))
              (pidDirs (filter (fn [(d String)] -> Bool (and (not (stringEmpty? (clientOfDir d))) (not (listContains? (pruneDirs) d)))) dirs))
              (subs (listAppend (list (pair (str ctx.root "/asl/host/out/asl-host") "{host}"))
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
                   (str "ASL_ROOT=" ctx.root) (str "ASL_LAUNCH_PROMPT_DIR=" promptDir) "LANG=C"))
        (out (l/runCapture! (list ctx.host "run" ctx.launch "claude" "--prompt-only") (some ctx.ws) (some env)))
        (captured (mt out ((ok c) c) ((err _) (l/Captured :code 127 :out "" :errText "could not run prompt-only"))))
        (row (if (= captured.code 0) (l/readOne captured.out) (err captured.errText)))
        (path (mt row ((ok r) (optionOr (l/textOf (optionOr (l/asnGet r "path") (l/asnStr ""))) "")) ((err _) "")))
        (freeze (mt row ((ok r) (optionOr (l/textOf (optionOr (l/asnGet r "freeze") (l/asnStr ""))) "")) ((err _) "")))
        (codeOk (= captured.code 0))
        (pathOk (and (not (stringEmpty? path)) (and (stringStartsWith? path promptDir) (fileExists? path))))
        (freezeOk (= freeze (freezeFor! ctx.root)))
        (silent (not (fileExists? log)))
        (good (and made (and codeOk (and pathOk (and freezeOk silent)))))]
    (do (assert good (str "prompt-only wrote " path " and freeze " freeze " without executing client; stderr " captured.errText)) good))

fn ! hookRun ctx: E2e i: Int64 args: (List String) extra: String -> l/Captured
  (let [(home (str ctx.base "/hookHome" (stringFromInt64 i)))
        (env (listAppend (list (str "PATH=" ctx.stubs ":" (resultOr (realPath "bin") "/usr/bin") ":" ctx.root "/bin:/usr/bin:/bin") (str "HOME=" home) (str "ASL_ROOT=" ctx.root) "LANG=C") (if (stringEmpty? extra) (list) (list extra))))
        (got (l/runCapture! (listAppend (list ctx.host "run" ctx.launch) args) (some ctx.ws) (some env)))]
    (mt got ((ok c) c) ((err e) (l/Captured :code 127 :out "" :errText e))))

fn ! checkPromptHooks ctx: E2e -> (List Bool)
  (let [(base (hookRun ctx 1 (list "claude" "--print-prompt") ""))
        (drop (hookRun ctx 2 (list "claude" "--print-prompt") "ASL_LAUNCH_DROP=evidence"))
        (fill (hookRun ctx 3 (list "claude" "--print-prompt") "ASL_LAUNCH_FILL_ASL=HOOK_FILL_SENTINEL"))
        (once (hookRun ctx 4 (list "claude" "--print-prompt") "ASL_LAUNCH_ONCE=true"))
        (argv (hookRun ctx 5 (list "claude" "--prompt-only" "--" "--hook-tail") ""))
        (dropOk (and (= drop.code 0) (and (stringContains? base.out "a claim holds when a tool result") (not (stringContains? drop.out "a claim holds when a tool result")))))
        (fillOk (and (= fill.code 0) (stringContains? fill.out "HOOK_FILL_SENTINEL")))
        (onceOk (and (= once.code 0) (and (stringContains? base.out "a client that compacts keeps recent turns") (not (stringContains? once.out "a client that compacts keeps recent turns")))))
        (argvOk (and (= argv.code 0) (and (stringContains? argv.out ":argv (") (stringContains? argv.out "--hook-tail"))))]
    (do (assert dropOk (str "drop removes evidence layer; exit " (stringFromInt64 drop.code) " stderr " drop.errText))
        (assert fillOk "fill substitutes ASL value")
        (assert onceOk "once omits memory layer")
        (assert argvOk "prompt-only argv includes tail")
        (list dropOk fillOk onceOk argvOk)))

fn leasePidDigits s: String -> Bool
  (and (not (stringEmpty? s)) (listAll? (fn [(c String)] -> Bool (and (>= (charCode c) 48) (<= (charCode c) 57))) (stringChars s)))

fn ! leasePidCase ctx: E2e i: Int64 supplied: String -> l/Captured
  (let [(home (str ctx.base "/leaseHome" (stringFromInt64 i)))
        (env (listAppend (list (str "PATH=" ctx.base "/leaseStubs:/usr/bin:/bin") (str "HOME=" home) (str "ASL_ROOT=" ctx.root) "LANG=C")
                         (if (stringEmpty? supplied) (list) (list (str "ASL_LEASE_PID=" supplied)))))
        (got (l/runCapture! (list ctx.host "run" ctx.launch "claude") (some ctx.ws) (some env)))]
    (mt got ((ok c) c) ((err e) (l/Captured :code 127 :out "" :errText e))))

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

fn ! runTests -> Bool
  (mt (fileReadString (fixturePath))
    ((err e) (do (assert false (str "fixture " (fixturePath) ": " e)) false))
    ((ok text)
      (mt (l/readOne text)
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
                (leasePid (mt e2eSuite ((err e) (do (assert false (str "lease pid setup: " e)) (list false false))) ((ok ctx) (checkLeasePid ctx))))
                (promptOnly (mt e2eSuite ((err e) (do (assert false (str "prompt-only setup: " e)) false)) ((ok ctx) (checkPromptOnly ctx 99))))
                (hooks (mt e2eSuite ((err e) (do (assert false (str "hook setup: " e)) (list false false false false))) ((ok ctx) (checkPromptHooks ctx))))
                (e2es (mt e2eSuite
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
                (assert (= (listLength mains) 22) "22 main cases")
                (assert (= (listLength facts) 14) "14 facts cases")
                (assert (= (listLength whiches) 13) "13 which cases")
                (assert (= (listLength e2es) 24) "24 end-to-end cases")
                (assert (= (listLength leasePid) 2) "2 lease pid cases")
                (assert promptOnly "prompt-only writes prompt, reports freeze and does not execute")
                (assert (ok? cleaned) "scratch dir removed")
                (assert (= (countTrue all) 740) "740 cases pass")
                (println (str "(:launchParity :cases " (stringFromInt64 (listLength all)) " :passed " (stringFromInt64 (countTrue all)) ")"))
                (= (countTrue all) (listLength all))))))))
