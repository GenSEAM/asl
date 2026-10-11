(module asl/agentLoop/tests/providersTest
  :x [runTests]
  :i [(asl/agentLoop/providers :a pv) (asl/agentLoop/core :a c) (asl-json/json :a j) (asl-proc/coreProcess :a cp)])

fn byteText b: Int64 -> String
  (let [(tbl "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\x7f\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f\xa0\xa1\xa2\xa3\xa4\xa5\xa6\xa7\xa8\xa9\xaa\xab\xac\xad\xae\xaf\xb0\xb1\xb2\xb3\xb4\xb5\xb6\xb7\xb8\xb9\xba\xbb\xbc\xbd\xbe\xbf\xc0\xc1\xc2\xc3\xc4\xc5\xc6\xc7\xc8\xc9\xca\xcb\xcc\xcd\xce\xcf\xd0\xd1\xd2\xd3\xd4\xd5\xd6\xd7\xd8\xd9\xda\xdb\xdc\xdd\xde\xdf\xe0\xe1\xe2\xe3\xe4\xe5\xe6\xe7\xe8\xe9\xea\xeb\xec\xed\xee\xef\xf0\xf1\xf2\xf3\xf4\xf5\xf6\xf7\xf8\xf9\xfa\xfb\xfc\xfd\xfe\xff")]
    (optionOr (stringSlice tbl b (+ b 1)) ""))

fn b64Text! s: String -> String
  (mt (bytesFromBase64 s)
    ((ok raw) (stringJoin (map (fn [k] (byteText (bytesGet raw k))) (range 0 (bytesLength raw))) ""))
    ((err e) (str "<bad base64: " e ">")))

fn kvText v: c/KvVal -> String
  (mt v ((c/kvStr s) s) ((c/kvInt s) s))

fn has kv: (List (Pair String c/KvVal)) k: String -> Bool
  (or (some? (c/dictGet kv k)) (some? (c/dictGet kv (str k "B64"))))

fn fld! kv: (List (Pair String c/KvVal)) k: String -> String
  (mt (c/dictGet kv k)
    ((some v) (kvText v))
    (none (mt (c/dictGet kv (str k "B64"))
            ((some v) (b64Text! (kvText v)))
            (none ""))))

fn jsonOf text: String -> j/Json
  (resultOr (j/jsonParse text) (j/jnull))

fn jsonItems v: j/Json -> (List j/Json)
  (mt v ((j/jarr xs) xs) (_ (list)))

fn jsonText v: j/Json -> String
  (mt v ((j/jstr s) s) (_ (pv/pyRepr v)))

fn optText o: (Option String) -> String
  (mt o ((some s) (pv/pyReprString s)) (none "None"))

fn check label: String want: String got: String -> Bool
  (do (assert (= want got) (str label ": want " (pv/pyReprString want) " got " (pv/pyReprString got))) true)

fn checkTrue label: String cond: Bool -> Bool
  (do (assert cond label) true)

fn ! writeFile path: String text: String -> Bool
  (ok? (fileWrite path text))

fn fillRoot text: String root: String -> String
  (stringReplace (stringReplace text "{ROOT}" root) "{PORT}" "9")

fn pairsText ps: (List (Pair String String)) -> String
  (str "{" (stringJoin (map (fn [p] (str (pv/pyReprString (pairFirst p)) ": " (pv/pyReprString (pairSecond p)))) ps) ", ") "}")

fn timingText t: (Option pv/Timing) -> String
  (mt t
    ((some x) (str "{'queueWaitSec': " (stringFromFloat64 x.queueWaitSec) ", 'execSec': " (stringFromFloat64 x.execSec) "}"))
    (none "None"))

fn usageText u: (Option (List (Pair String j/Json))) -> String
  (mt u
    ((some ps) (str "{" (stringJoin (map (fn [p] (str (pv/pyReprString (pairFirst p)) ": " (pv/pyRepr (pairSecond p)))) ps) ", ") "}"))
    (none "None"))

fn servedText s: (Option (List (Pair String String))) -> String
  (mt s ((some ps) (pairsText ps)) (none "None"))

fn expectedCode kind: String exc: String -> String
  (cond
    ((= exc "ValueError") "ERR_VALUE")
    ((= exc "TimeoutExpired") "ERR_TIMEOUT")
    ((and (= exc "FileNotFoundError") (= kind "cli")) "ERR_TOOL_ABSENT")
    ((= exc "FileNotFoundError") "ERR_NOT_FOUND")
    (else (str "unmapped " exc)))

fn checkOutcome! kv: (List (Pair String c/KvVal)) root: String r: (Result (Option String) pv/ProviderError) -> Bool
  (let [(cid (fld! kv "id"))
        (outcome (fld! kv "outcome"))
        (kind (fld! kv "kind"))]
    (mt r
      ((ok reply)
        (and (check (str cid " outcome") outcome "ok")
             (and (check (str cid " isNone") (fld! kv "isNone") (if (none? reply) "True" "False"))
                  (check (str cid " reply") (fld! kv "reply") (optionOr reply "")))))
      ((err e)
        (let [(wantCode (if (= outcome "raise") (expectedCode kind (fld! kv "exc")) (fld! kv "code")))
              (wantMsg (fillRoot (fld! kv "msg") root))
              (gotMsg (pv/errorMessage e))]
          (and (check (str cid " outcome (" (pv/errorCode e) " " gotMsg ")") outcome (if (= outcome "raise") "raise" "error"))
               (and (check (str cid " code") wantCode (pv/errorCode e))
                    (if (has kv "affix")
                      (checkTrue (str cid " message affix: " gotMsg)
                        (and (stringStartsWith? gotMsg (fld! kv "affix"))
                             (or (!= wantCode "ERR_GATEWAY_OFFLINE") (stringEndsWith? gotMsg "; run ./bin/asl-gateway start"))))
                      (check (str cid " message") wantMsg gotMsg))))))))

fn checkParse! kv: (List (Pair String c/KvVal)) -> Bool
  (let [(cid (fld! kv "id"))]
    (mt (pv/parseAsnReply (fld! kv "input"))
      ((ok hf)
        (and (check (str cid " outcome") (fld! kv "outcome") "ok")
             (and (check (str cid " head") (fld! kv "head") (pairFirst hf))
                  (check (str cid " fields")
                    (stringJoin (map (fn [p] (stringJoin (map jsonText (jsonItems p)) "=")) (jsonItems (jsonOf (fld! kv "fields")))) "|")
                    (stringJoin (map (fn [p] (str (pairFirst p) "=" (pairSecond p))) (pairSecond hf)) "|")))))
      ((err e)
        (and (check (str cid " outcome") (fld! kv "outcome") "raise")
             (check (str cid " message") (fld! kv "msg") e)))))

fn ! checkNumbers kv: (List (Pair String c/KvVal)) -> Bool
  (let [(cid (fld! kv "id"))
        (t0 (monotonicNs))
        (parsed (pv/asnNumbers (fld! kv "input")))
        (ms (/ (- (monotonicNs) t0) 1000000))]
    (mt parsed
      ((ok ps)
        (and (check (str cid " outcome") (fld! kv "outcome") "ok")
             (and (or (not (has kv "timed")) (checkTrue (str cid " parsed within 500 ms: " (stringFromInt64 ms)) (< ms 500)))
             (check (str cid " pairs")
               (stringJoin (map (fn [p] (stringJoin (map jsonText (jsonItems p)) "=")) (jsonItems (jsonOf (fld! kv "pairs")))) "|")
               (stringJoin (map (fn [p] (str (pairFirst p) "=" (pv/pyRepr (pairSecond p)))) ps) "|")))))
      ((err e)
        (and (check (str cid " outcome") (fld! kv "outcome") "raise")
             (and (check (str cid " code") (expectedCode "numbers" (fld! kv "exc")) (pv/errorCode e))
                  (check (str cid " message") (fld! kv "msg") (pv/errorMessage e)))))))

fn checkServed! kv: (List (Pair String c/KvVal)) -> Bool
  (let [(fields (mt (jsonOf (fld! kv "input")) ((j/jobj ps) ps) (_ (list))))]
    (check (str (fld! kv "id") " served") (fld! kv "out") (servedText (pv/servedFields fields))))

fn checkStrings label: String want: String got: (List String) -> Bool
  (check label (stringJoin (map pv/pyReprString (map jsonText (jsonItems (jsonOf want)))) ", ") (stringJoin (map pv/pyReprString got) ", "))

fn ! resolveHost repo: String -> (Option String)
  (mt (envGet "ASL_HOST")
    ((some h) (if (fileExists? h)
                (some (resultOr (realPath h) h))
                (do (println (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (assert false (str "invalid environment variable: ASL_HOST path does not exist: " h))
                    (none))))
    ((none) (let [p (resultOr (realPath "asl/host/out/asl-host") "asl/host/out/asl-host")]
              (if (fileExists? p)
                (some p)
                (do (println (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (assert false (str "the stage-0 host is absent at " p "; build it with sh asl/host/build.sh or set ASL_HOST"))
                    (none))))))

fn ! makeStubBin host: String root: String -> Bool
  (let [(stub (resultOr (realPath "asl/agentLoop/tests/providerStub.asl") "providerStub.asl"))
        (bin (str root "/bin"))
        (made (and (ok? (dirCreate bin)) (ok? (dirCreate (str root "/emptyBin")))))
        (wrote (map (fn [t] (writeFile (str bin "/" t) (str "#!/bin/sh\nexec \"" host "\" run \"" stub "\" " t " \"$@\"\n"))) (list "codex" "claude" "curl")))
        (chmod (cp/exec! (cp/cmd "chmod" (list "755" (str bin "/codex") (str bin "/claude") (str bin "/curl")))))]
    (and made (and (listAll? (fn [w] w) wrote) (mt chmod ((ok o) (= o.exitCode 0)) ((err _) false)))))

fn ! blankKeys -> (Map String String)
  (fold (fn [m row] (let [(name (optionOr (stringSlice row 0 (optionOr (stringIndexOf row "=") 0)) ""))]
                      (if (stringEndsWith? name "_API_KEY") (mapSet m name "") m)))
        (mapEmpty) (envList))

fn envFor! root: String stubDir: String pathMode: String url: String profile: String config: String -> pv/ProviderEnv
  (pv/ProviderEnv :gatewayUrl url :inProcess false :profile profile :gatewayConfig config :tmpDir (str root "/tmp")
    :childEnv (mapSet (mapSet (blankKeys) "PATH" (str (if (= pathMode "empty") (str root "/emptyBin") (str root "/bin")) ":/usr/bin:/bin")) "STUB_DIR" stubDir)
    :ollamaUrl "http://127.0.0.1:9/v1/chat/completions")

fn ! setupStub stubDir: String out: String code: String last: String sleep: String -> Bool
  (and (ok? (dirCreate stubDir))
       (and (writeFile (str stubDir "/reply.out") out)
            (and (writeFile (str stubDir "/reply.exit") code)
                 (and (or (stringEmpty? last) (writeFile (str stubDir "/reply.last") last))
                      (or (stringEmpty? sleep) (writeFile (str stubDir "/reply.sleepMs") sleep))))))

fn recordLines text: String -> (List String)
  (map (fn [l] (c/asnUnescape (optionOr (stringSlice l 1 (- (stringLength l) 1)) "")))
       (filter (fn [l] (not (stringEmpty? l))) (stringSplit text "\n")))

fn keyRun s: String -> Int64
  (let [(bs (stringToBytes s))]
    (listLength (listTake (filter (fn [k] (let [(b (bytesGet bs k))] (or (and (>= b 48) (<= b 57)) (or (and (>= b 65) (<= b 90)) (or (and (>= b 97) (<= b 122)) (or (= b 45) (= b 95)))))))
                                  (range 0 (bytesLength bs)))
                          (bytesLength bs))))

fn keyAfter s: String prefix: String minLen: Int64 -> Bool
  (mt (stringIndexOf s prefix)
    ((some i) (let [(tail (optionOr (stringSlice s (+ i (stringLength prefix)) (stringLength s)) ""))
                    (word (optionOr (listHead (stringSplit (stringReplace (stringReplace tail "\"" " ") "'" " ") " ")) ""))]
                (>= (keyRun word) minLen)))
    (none false))

fn keyLooking s: String -> Bool
  (or (keyAfter s "sk-" 16)
    (or (keyAfter s "ghp_" 20)
      (or (keyAfter s "github_pat_" 20)
        (or (keyAfter s "xoxb-" 10)
          (or (keyAfter s "xoxp-" 10)
            (or (keyAfter s "AIza" 30) (keyAfter s "AKIA" 16)))))))

fn apiKeyEntry row: String -> Bool
  (mt (stringIndexOf row "=")
    ((some i) (and (stringEndsWith? (optionOr (stringSlice row 0 i) "") "_API_KEY") (< (+ i 1) (stringLength row))))
    (none false))

fn ! checkNoKeys cid: String stubDir: String -> Bool
  (let [(argv (recordLines (resultOr (fileReadString (str stubDir "/argv")) "")))
        (env (recordLines (resultOr (fileReadString (str stubDir "/env")) "")))
        (stdin (resultOr (fileReadString (str stubDir "/stdin")) ""))
        (leaks (filter (fn [s] (or (keyLooking s) (apiKeyEntry s))) (listAppend argv env)))]
    (and (checkTrue (str cid " child argv and env carry no key-looking value: " (stringJoin (map (fn [s] (optionOr (stringSlice s 0 12) "")) leaks) ",")) (listEmpty? leaks))
         (checkTrue (str cid " child stdin carries no key-looking value") (not (keyLooking stdin)))))

fn ! runProviderCase kv: (List (Pair String c/KvVal)) root: String kind: String -> Bool
  (let [(cid (fld! kv "id"))
        (name (fld! kv "name"))
        (dir (if (= kind "scriptProvider") (str root "/tests/fixtures/agentLoop/mvp") (str root "/tests/fixtures/agentLoop/recorded")))
        (file (if (= kind "scriptProvider") (str dir "/" name ".asn") (str dir "/" name)))
        (prep (and (ok? (dirCreate dir)) (or (not (has kv "content")) (writeFile file (fld! kv "content")))))
        (backend (str (if (= kind "scriptProvider") "script/" "replay/") name))
        (env (envFor! root (str root "/stub/" cid) "stub" "" "" ""))
        (made (pv/makeProvider! backend "scout" root "" 600 "sprov" 1200 true env))]
    (and (checkTrue (str cid " fixture file written") prep)
      (mt made
        ((err e) (checkOutcome! kv root (err e)))
        ((ok p)
          (let [(n (optionOr (stringToInt64 (fld! kv "calls")) 0))
                (step (fn [acc k] (let [(t (pv/nextTurn! (pairFirst acc) "sys" "user"))]
                                    (pair t.provider (cons t.reply (pairSecond acc))))))
                (run (fold step (pair p (list)) (range 0 n)))
                (outs (listReverse (pairSecond run)))
                (want (map (fn [v] (mt v ((j/jnull) "None") (_ (pv/pyReprString (jsonText v))))) (jsonItems (jsonOf (fld! kv "outs")))))
                (got (map (fn [r] (mt r ((ok o) (optText o)) ((err e) (str "error " (pv/errorMessage e))))) outs))
                (lock (str root "/.asl/run/agentLoop/" (mt (pv/vendorName p) ((some v) v) (none "None")) ".lock"))]
            (and (check (str cid " outcome") (fld! kv "outcome") "ok")
              (and (check (str cid " name") (fld! kv "providerName") (pv/providerName p))
                (and (check (str cid " vendor") (fld! kv "vendor") (optText (pv/vendorName p)))
                  (and (check (str cid " replies") (stringJoin want ", ") (stringJoin got ", "))
                    (or (= kind "scriptProvider")
                        (check (str cid " lock file") (fld! kv "lockExists") (if (fileExists? lock) "True" "False"))))))))))))

fn ! runCliCase kv: (List (Pair String c/KvVal)) root: String -> Bool
  (let [(cid (fld! kv "id"))
        (vendor (fld! kv "vendor"))
        (mode (fld! kv "mode"))
        (session (fld! kv "session"))
        (stubDir (str root "/stub/" cid))
        (staged (setupStub stubDir (fld! kv "replyOut") (fld! kv "replyExit") (fld! kv "replyLast") (fld! kv "sleepMs")))
        (codexDir (str root "/.asl/run/agentLoop/codex/" session))
        (pre (or (not (has kv "preLast")) (and (ok? (dirCreate codexDir)) (writeFile (str codexDir "/" mode ".last") (fld! kv "preLast")))))
        (env (envFor! root stubDir (fld! kv "path") "" "" ""))
        (made (pv/makeProvider! vendor mode root (fld! kv "model") (optionOr (stringToInt64 (fld! kv "timeout")) 600) session 1200 true env))]
    (mt made
      ((err e) (checkTrue (str cid " provider made: " (pv/errorMessage e)) false))
      ((ok p)
        (let [(t (pv/nextTurn! p (fld! kv "sys") (fld! kv "user")))
              (argvText (fileReadString (str stubDir "/argv")))
              (called (ok? argvText))
              (instr (fileReadString (str codexDir "/" mode ".md")))
              (cwd (resultOr (fileReadString (str stubDir "/cwd")) ""))
              (base (optionOr (listLast (stringSplit cwd "/")) ""))
              (cleaned (pv/cleanup! p))]
          (and (checkTrue (str cid " stub staged") (and staged pre))
            (and (checkOutcome! kv root t.reply)
              (and (check (str cid " child called") (if (has kv "argv") "True" "False") (if called "True" "False"))
                (and (or (not called)
                         (and (check (str cid " argv") (stringJoin (map (fn [a] (fillRoot (jsonText a) root)) (jsonItems (jsonOf (fld! kv "argv")))) " | ")
                                (stringJoin (recordLines (resultOr argvText "")) " | "))
                           (and (check (str cid " stdin") (fld! kv "stdin") (resultOr (fileReadString (str stubDir "/stdin")) ""))
                             (and (check (str cid " cwd scratch") (fld! kv "cwdOk")
                                    (if (and (stringStartsWith? base (str "asl_" vendor "_cwd_")) (not (fileExists? cwd))) "True" "False"))
                               (checkNoKeys cid stubDir)))))
                  (and (check (str cid " instructions file") (fld! kv "instr") (resultOr instr ""))
                    (checkTrue (str cid " cleanup") (ok? cleaned)))))))))))

fn unquoteLoop s: String bs: Bytes n: Int64 i: Int64 acc: (List String) -> String
  (cond
    ((>= i n) (stringJoin (listReverse acc) ""))
    ((and (= (bytesGet bs i) 92) (< (+ i 1) n))
      (let [(c (bytesGet bs (+ i 1)))
            (piece (cond ((= c 110) "\n") ((= c 114) "\r") ((= c 116) "\t") ((= c 118) "\x0b") (else (byteText c))))]
        (unquoteLoop s bs n (+ i 2) (cons piece acc))))
    (else (unquoteLoop s bs n (+ i 1) (cons (byteText (bytesGet bs i)) acc))))

fn configUnescape s: String -> String
  (let [(bs (stringToBytes s))]
    (unquoteLoop s bs (bytesLength bs) 0 (list)))

fn configValue line: String -> String
  (mt (stringIndexOf line " = ")
    ((some i) (let [(v (optionOr (stringSlice line (+ i 3) (stringLength line)) ""))]
                (configUnescape (optionOr (stringSlice v 1 (- (stringLength v) 1)) ""))))
    (none ""))

fn configRows config: String key: String -> (List String)
  (map configValue (filter (fn [l] (stringStartsWith? l (str key " = "))) (stringSplit config "\n")))

fn headerRow h: String -> String
  (mt (stringIndexOf h ": ")
    ((some i) (str (stringLower (optionOr (stringSlice h 0 i) "")) ": " (optionOr (stringSlice h (+ i 2) (stringLength h)) "")))
    (none h))

fn ! runGatewayCase kv: (List (Pair String c/KvVal)) root: String -> Bool
  (let [(cid (fld! kv "id"))
        (session (fld! kv "session"))
        (mode (fld! kv "mode"))
        (stubDir (str root "/stub/" cid))
        (staged (setupStub stubDir (fld! kv "raw") (if (has kv "curlExit") (fld! kv "curlExit") "0") "" ""))
        (cfgPath (str root "/gwcfg_" cid ".asn"))
        (cfgOk (or (not (has kv "config")) (writeFile cfgPath (fld! kv "config"))))
        (env (envFor! root stubDir "stub" (fld! kv "url") (fld! kv "profile") cfgPath))
        (made (pv/makeProvider! "agy" mode root (fld! kv "model") (optionOr (stringToInt64 (fld! kv "timeout")) 600) session
                (optionOr (stringToInt64 (fld! kv "queueTimeout")) 1200) (= (fld! kv "timeoutSet") "True") env))]
    (mt made
      ((err e) (checkTrue (str cid " provider made: " (pv/errorMessage e)) false))
      ((ok p)
        (let [(t (if (= (fld! kv "advise") "True")
                   (optionOr (pv/advise! p (fld! kv "sys") (fld! kv "user")) (pv/Turn :provider p :reply (ok none) :meta (pv/emptyMeta)))
                   (pv/nextTurn! p (fld! kv "sys") (fld! kv "user"))))
              (meta t.meta)
              (config (resultOr (fileReadString (str stubDir "/stdin")) ""))
              (called (fileExists? (str stubDir "/argv")))
              (agents (str root "/.asl/run/agentLoop/agents/" session))
              (agentFile (fileReadString (str agents "/.agents/plugins/aslLoop/agents/aslLoop" (optionOr (stringSlice (stringUpper mode) 0 1) "") (optionOr (stringSlice mode 1 (stringLength mode)) "") ".md")))
              (pluginJson (fileReadString (str agents "/.agents/plugins/aslLoop/plugin.json")))
              (workspace (if (fileExists? agents) "True" "False"))
              (cleaned (pv/cleanup! p))
              (wantHeaders (map (fn [h] (let [(xs (map jsonText (jsonItems h)))] (headerRow (str (optionOr (listHead xs) "") ": " (optionOr (listLast xs) ""))))) (jsonItems (jsonOf (fld! kv "sentHeaders")))))
              (gotHeaders (map headerRow (filter (fn [h] (!= h "Expect:")) (configRows config "header"))))]
          (and (checkTrue (str cid " stub staged") (and staged cfgOk))
            (and (checkOutcome! kv root t.reply)
              (and (check (str cid " timing") (fld! kv "timing") (timingText meta.timing))
                (and (check (str cid " usage") (fld! kv "usage") (usageText meta.usage))
                  (and (check (str cid " served") (fld! kv "served") (servedText meta.served))
                    (and (check (str cid " finish") (fld! kv "finish") (optText meta.finish))
                      (and (check (str cid " truncated") (fld! kv "truncated") (if meta.truncated "True" "False"))
                        (and (check (str cid " curl called") (fld! kv "reached") (if called "True" "False"))
                          (and (or (not called)
                                   (and (check (str cid " curl argv") "curl | --config | -" (stringJoin (recordLines (resultOr (fileReadString (str stubDir "/argv")) "")) " | "))
                                     (and (check (str cid " body") (fillRoot (fld! kv "body") root) (stringJoin (configRows config "data-raw") ""))
                                       (and (check (str cid " headers") (stringJoin wantHeaders " | ") (stringJoin gotHeaders " | "))
                                         (and (check (str cid " url") (fld! kv "url") (stringJoin (configRows config "url") ""))
                                           (and (check (str cid " max-time") (fld! kv "maxTime") (stringJoin (configRows config "max-time") ""))
                                             (and (check (str cid " noproxy") (fld! kv "loopback") (if (listEmpty? (configRows config "noproxy")) "False" "True"))
                                               (checkNoKeys cid stubDir))))))))
                            (and (check (str cid " agent file") (fillRoot (fld! kv "agentFile") root) (resultOr agentFile ""))
                              (and (check (str cid " plugin.json") (fld! kv "pluginJson") (resultOr pluginJson ""))
                                (and (check (str cid " workspace") (fld! kv "workspace") workspace)
                                  (checkTrue (str cid " cleanup") (ok? cleaned))))))))))))))))))

fn ! runOllamaCase kv: (List (Pair String c/KvVal)) root: String -> Bool
  (let [(cid (fld! kv "id"))
        (session (fld! kv "session"))
        (stubDir (str root "/stub/" cid))
        (staged (setupStub stubDir (fld! kv "raw") (if (has kv "curlExit") (fld! kv "curlExit") "0") "" ""))
        (env (envFor! root stubDir "stub" "" "" ""))
        (made (pv/makeProvider! "ollama" "scout" root (fld! kv "model") (optionOr (stringToInt64 (fld! kv "timeout")) 600) session
                (optionOr (stringToInt64 (fld! kv "queueTimeout")) 1200) (= (fld! kv "timeoutSet") "True") env))]
    (mt made
      ((err e) (checkTrue (str cid " provider made: " (pv/errorMessage e)) false))
      ((ok p)
        (let [(t (pv/nextTurn! p (fld! kv "sys") (fld! kv "user")))
              (meta t.meta)
              (config (resultOr (fileReadString (str stubDir "/stdin")) ""))
              (called (fileExists? (str stubDir "/argv")))]
          (and (checkTrue (str cid " stub staged") staged)
            (and (checkOutcome! kv root t.reply)
              (and (check (str cid " usage") (fld! kv "usage") (usageText meta.usage))
                (and (check (str cid " curl called") (fld! kv "reached") (if called "True" "False"))
                  (or (not called)
                    (and (check (str cid " curl argv") "curl | --config | -" (stringJoin (recordLines (resultOr (fileReadString (str stubDir "/argv")) "")) " | "))
                      (and (check (str cid " body") (fillRoot (fld! kv "body") root) (stringJoin (configRows config "data-raw") ""))
                        (and (check (str cid " url") (fld! kv "url") (stringJoin (configRows config "url") ""))
                          (and (check (str cid " noproxy") (fld! kv "loopback") (if (listEmpty? (configRows config "noproxy")) "False" "True"))
                            (checkNoKeys cid stubDir))))))))))))))

fn ! runVendorUnknown kv: (List (Pair String c/KvVal)) root: String -> Bool
  (let [(cfg (pv/VendorConfig :vendor (fld! kv "vendor") :mode "scout" :rootDir root :model "" :timeout 600 :queueTimeout 1200
               :sessionId "sother" :intent "auto" :timeoutSet true :env (envFor! root (str root "/stub/other") "stub" "" "" "") :link none))
        (t (pv/nextTurn! (pv/vendorProvider cfg) "s" "u"))]
    (checkOutcome! kv root t.reply))

fn ! runMakeCase kv: (List (Pair String c/KvVal)) root: String -> Bool
  (let [(cid (fld! kv "id"))]
    (mt (pv/makeProvider! (fld! kv "backend") "scout" root "" 600 "smake" 1200 true (envFor! root (str root "/stub/make") "stub" "" "" ""))
      ((ok p) (and (check (str cid " outcome") (fld! kv "outcome") "ok")
                (and (check (str cid " name") (fld! kv "providerName") (pv/providerName p))
                  (check (str cid " vendor") (fld! kv "vendor") (optText (pv/vendorName p))))))
      ((err e) (checkOutcome! kv root (err e)))))

fn ! runGatewayIds kv: (List (Pair String c/KvVal)) root: String -> Bool
  (let [(path (str root "/gateway_" (fld! kv "id") ".asn"))
        (wrote (or (not (has kv "content")) (writeFile path (fld! kv "content"))))]
    (and (checkTrue (str (fld! kv "id") " config written") wrote)
      (checkStrings (str (fld! kv "id") " ids") (fld! kv "ids") (pv/gatewayModelIds! path))))

fn ! runDryRun kv: (List (Pair String c/KvVal)) root: String -> Bool
  (let [(cid (fld! kv "id"))
        (url (if (has kv "url") (fld! kv "url") "http://127.0.0.1:8765/v1/chat/completions"))
        (env (envFor! root (str root "/stub/dry") "stub" url "" ""))
        (mode (fld! kv "mode"))
        (agent (str root "/.asl/run/agentLoop/agents/.agents/plugins/aslLoop/agents/aslLoop"
                    (if (stringEmpty? mode) "Scout" (str (stringUpper (optionOr (stringSlice mode 0 1) "")) (optionOr (stringSlice mode 1 (stringLength mode)) ""))) ".md"))]
    (mt (pv/buildDryRunInfo! (fld! kv "vendor") mode root (fld! kv "model") (optionOr (stringToInt64 (fld! kv "timeout")) 600) (optionOr (stringToInt64 (fld! kv "queueTimeout")) 1200) env)
      ((err e)
        (if (= (fld! kv "outcome") "error")
          (and (check (str cid " code") (fld! kv "code") (pv/errorCode e))
               (check (str cid " message") (fillRoot (fld! kv "msg") root) (pv/errorMessage e)))
          (checkTrue (str cid " dry run: " (pv/errorMessage e)) false)))
      ((ok info)
        (and (check (str cid " info") (fillRoot (fld! kv "out") root) (pv/pyJsonDumps info))
          (or (not (has kv "agentFile")) (check (str cid " agent file") (fld! kv "agentFile") (resultOr (fileReadString agent) "")))))))

fn ! checkRedirect root: String -> Bool
  (let [(stubDir (str root "/stub/redirect302"))
        (staged (setupStub stubDir "HTTP/1.1 302 Found\r\nLocation: /elsewhere\r\nContent-Length: 0\r\n\r\n" "0" "" ""))
        (env (envFor! root stubDir "stub" "http://127.0.0.1:9/v1/chat/completions" "" (str root "/none.asn")))]
    (mt (pv/makeProvider! "agy" "scout" root "" 600 "gredirect" 1200 true env)
      ((err e) (checkTrue (str "redirect302 provider: " (pv/errorMessage e)) false))
      ((ok p)
        (let [(t (pv/nextTurn! p "s" "u"))
              (got (mt t.reply ((ok _) "ok") ((err e) (str (pv/errorCode e) " " (pv/errorMessage e)))))]
          (and (checkTrue "redirect302 stub staged" staged)
            (check "redirect302 is an HTTP error" "ERR_VENDOR Gateway HTTP error 302: Found" got))))))

fn ! checkFreshDir root: String -> Bool
  (let [(base (str root "/tmp"))
        (taken (ok? (dirCreate (str base "/aslFresh_same"))))
        (got (pv/freshDir! base "aslFresh_" (fn [a] (if (= a 0) "same" "other")) 0))]
    (and (checkTrue "taken scratch name staged" taken)
      (check "freshDir! skips the taken name" (str base "/aslFresh_other") (mt got ((ok d) d) ((err e) (pv/errorMessage e))))))

fn ! checkTempDirs root: String -> Bool
  (mt (pv/makeProvider! "codex" "scout" root "" 600 "stemp" 1200 true (envFor! root (str root "/stub/temp") "stub" "" "" ""))
    ((err e) (checkTrue (str "tempDir provider: " (pv/errorMessage e)) false))
    ((ok p)
      (mt p
        ((pv/vendorProvider cfg)
          (let [(dirs (map (fn [k] (resultOr (pv/tempDir! cfg "asl_codex_cwd_") "")) (range 0 20)))
                (live (filter (fn [d] (and (not (stringEmpty? d)) (fileExists? d))) dirs))
                (distinct (fold (fn [acc d] (if (listContains? acc d) acc (cons d acc))) (list) live))
                (removed (map (fn [d] (ok? (pathRemove d))) live))]
            (and (check "twenty back-to-back temp dirs exist" "20" (stringFromInt64 (listLength live)))
              (and (check "twenty back-to-back temp dirs are distinct" "20" (stringFromInt64 (listLength distinct)))
                (checkTrue "temp dirs removed" (listAll? (fn [r] r) removed))))))
        (_ (checkTrue "tempDir provider is a vendor" false)))))

fn ! checkCase root: String line: String -> Bool
  (let [(kv (c/parseKv line))
        (kind (fld! kv "kind"))
        (cid (fld! kv "id"))]
    (cond
      ((= kind "parse") (checkParse! kv))
      ((= kind "numbers") (checkNumbers kv))
      ((= kind "served") (checkServed! kv))
      ((= kind "loopback") (check (str cid " loopback") (fld! kv "out") (if (pv/isLoopback (fld! kv "url")) "True" "False")))
      ((= kind "scriptTurns") (checkStrings (str cid " turns") (fld! kv "out") (pv/parseScriptTurns (fld! kv "input"))))
      ((= kind "replayLines") (checkStrings (str cid " lines") (fld! kv "out") (pv/parseReplayLines (fld! kv "input"))))
      ((or (= kind "scriptProvider") (= kind "replayProvider")) (runProviderCase kv root kind))
      ((= kind "gatewayIds") (runGatewayIds kv root))
      ((= kind "cli") (runCliCase kv root))
      ((= kind "gateway") (runGatewayCase kv root))
      ((= kind "ollama") (runOllamaCase kv root))
      ((= kind "vendorUnknown") (runVendorUnknown kv root))
      ((= kind "makeProvider") (runMakeCase kv root))
      ((= kind "dryRun") (runDryRun kv root))
      (else (checkTrue (str cid " has a known kind: " kind) false))))

fn ! runTests -> Bool
  (mt (resolveHost ".")
    ((none) false)
    ((some host)
     (let [(content (resultOr (fileReadString "asl/agentLoop/tests/providersFixture.asn") ""))
           (lines (filter (fn [l] (stringStartsWith? l "(:case ")) (stringLines content)))
           (tmp (resultOr (realPath (optionOr (envGet "TMPDIR") "/tmp")) "/tmp"))
           (root (str tmp "/aslProvidersTest" (stringFromInt64 (procSelf))))
           (fresh (if (fileExists? root) (ok? (pathRemove root)) true))
           (ready (and fresh (and (ok? (dirCreate (str root "/tmp"))) (makeStubBin host root))))
           (results (map (fn [l] (checkCase root l)) lines))
           (redirect (checkRedirect root))
           (temps (checkTempDirs root))
           (freshOk (checkFreshDir root))
           (removed (ok? (pathRemove root)))]
       (and (checkTrue (str "the fixture holds at least 150 cases: " (stringFromInt64 (listLength lines))) (>= (listLength lines) 150))
         (and (checkTrue "scratch root and stub bin ready" ready)
           (and (checkTrue "every case passed" (and redirect (and temps (and freshOk (listAll? (fn [r] r) results)))))
             (checkTrue "scratch root removed" removed)))))))
