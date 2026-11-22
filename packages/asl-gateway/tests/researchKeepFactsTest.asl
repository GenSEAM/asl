(module aslGateway/tests/researchKeepFactsTest
  :x [runTests]
  :i [(asl-json/json :a j) (pyText :a pt) (search :a srch) (research :a rs) (asl-tools/fleet/run :a fr)])

; (:m :ref RESEARCH-KEEP-FACTS :do "an auditor chain that fails on every model keeps the extracted facts as unverified, and an alias that answered HTTP 400 is called once per run; stub curl and a canned model, no network, no model call, each run owns one directory under /tmp")

(schema Out (:f rep j/Json) (:f asn String) (:f wire String) (:f prompts (List String)) (:f failed String) (:f models (List String)))

(schema Caps (:f subQuestions Int64) (:f sources Int64) (:f searches Int64) (:f fetches Int64) (:f modelCalls Int64) (:f decompose String) (:f nodes Int64) (:f depth Int64))

fn topic -> String
  "Widget engines: (1) alpha rotor torque; (2) beta valve leakage; (3) gamma seal wear"

fn capsOf subQuestions: Int64 sources: Int64 searches: Int64 fetches: Int64 modelCalls: Int64 decompose: String nodes: Int64 depth: Int64 -> Caps
  (Caps :subQuestions subQuestions :sources sources :searches searches :fetches fetches :modelCalls modelCalls :decompose decompose :nodes nodes :depth depth)

fn modeText c: Caps -> String
  (str "(:researchModes :v 2)\n"
       "(:mode :id flash :pipeline plan :depth flash :engine auto :decompose none :subQuestions 1 :queriesPerSub 1 :resultsPerQuery 3 :fetchPerQuery 3 :batchSources 2 :maxSourcesPerSub 3 :saturationBatches 1 :resolveMargin 2"
       " :maxDepth 0 :maxChildren 0 :maxNodes 1 :childSharedTerms 1 :childChars 80 :counterQuery false :minFacts 2 :minSources 1 :followUpRounds 0 :followUpQueries 0 :maxSearches 2 :maxFetches 6 :maxModelCalls 5 :wallSeconds 600 :queryChars 200 :reformulations ())\n"
       "(:mode :id deep :pipeline plan :depth targeted :engine auto :decompose " c.decompose " :subQuestions " (stringFromInt64 c.subQuestions)
       " :queriesPerSub 1 :resultsPerQuery 4 :fetchPerQuery 3 :batchSources 2 :maxSourcesPerSub " (stringFromInt64 c.sources) " :saturationBatches 2 :resolveMargin 2 :counterQuery false :minFacts 2 :minSources 2"
       " :followUpRounds 3 :followUpQueries 1 :maxSearches " (stringFromInt64 c.searches) " :maxFetches " (stringFromInt64 c.fetches) " :maxModelCalls " (stringFromInt64 c.modelCalls)
       " :maxDepth " (stringFromInt64 c.depth) " :maxChildren 2 :maxNodes " (stringFromInt64 c.nodes) " :childSharedTerms 1 :childChars 80 :wallSeconds 600 :queryChars 200 :reformulations (\"explained\" \"benchmark results\"))\n")

fn page url: String text: String -> (Pair String String)
  (pair url (str "<html><head><title>page</title></head><body><p>" text "</p></body></html>"))

fn pages -> (List (Pair String String))
  (list (page "https://docs.test/a1" "The alpha rotor delivers 40 newton metres of torque at 3000 rpm.")
        (page "https://lab.test/a2" "Alpha rotor torque falls by 12 percent above 90 degrees celsius.")
        (page "https://blog.test/a3" "An overview page about rotors.")
        (page "https://docs.test/b1" "The beta valve leaks 3 millilitres per hour at 5 bar.")
        (page "https://forum.test/b2" "The beta valve does not leak at all below 5 bar.")
        (page "https://wiki.test/b3" "Beta valve leakage doubles after 10000 cycles.")
        (page "https://more.test/b4" "Beta valve leakage is explained by seat erosion.")
        (page "https://shop.test/g1" "Buy gamma seals today.")
        (page "https://ads.test/g2" "Gamma seal catalogue.")
        (page "https://rare.test/g3" "Gamma seal wear reaches 2 microns per year.")
        (page "https://parts.test/c1" "The alpha rotor bearing preload is 200 newtons. The bearing is rated for 9000 rpm.")
        (page "https://mirror.test/z1" "The zeta mirror drifts 5 arcseconds per hour.")
        (page "https://mirror.test/z1?utm=x" "The zeta mirror drifts 5 arcseconds per hour.")
        (page "https://copy.test/z1" "The zeta mirror drifts 5 arcseconds per hour.")
        (page "https://mirror.test/z2" "The zeta mirror drift halves with a carbon mount."))

fn hits urls: (List String) -> String
  (pt/jsonDumps (j/jobj (list (pair "web" (j/jobj (list (pair "results" (j/jarr (map (fn [(u String)] -> j/Json (j/jobj (list (pair "title" (j/jstr (str "Result " u))) (pair "url" (j/jstr u)) (pair "description" (j/jstr (str "snippet of " u)))))) urls)))))))) -1)

fn braveUrl query: String -> String
  (let [(r (srch/braveReq query (if (= query (topic)) 3 4) "brave-test"))] r.url)

fn counterOf part: String -> String
  (str part " limitations drawbacks failure criticisms")

fn searches -> (List (Pair String String))
  (list (pair (braveUrl (topic)) (hits (list "https://docs.test/a1" "https://docs.test/b1" "https://shop.test/g1")))
        (pair (braveUrl "Widget engines alpha rotor torque") (hits (list "https://docs.test/a1" "https://lab.test/a2" "https://blog.test/a3")))
        (pair (braveUrl "alpha rotor torque") (hits (list "https://blog.test/a3")))
        (pair (braveUrl "Widget engines beta valve leakage") (hits (list "https://docs.test/a1" "https://docs.test/b1" "https://forum.test/b2" "https://wiki.test/b3")))
        (pair (braveUrl (counterOf "beta valve leakage")) (hits (list "https://more.test/b4")))
        (pair (braveUrl "beta valve leakage") (hits (list)))
        (pair (braveUrl "Widget engines gamma seal wear") (hits (list "https://shop.test/g1")))
        (pair (braveUrl "gamma seal wear") (hits (list)))
        (pair (braveUrl "gamma seal wear explained") (hits (list "https://ads.test/g2")))
        (pair (braveUrl "gamma seal wear benchmark results") (hits (list "https://rare.test/g3")))
        (pair (braveUrl "alpha rotor bearing preload") (hits (list "https://parts.test/c1")))
        (pair (braveUrl "alpha rotor bearing grease") (hits (list)))
        (pair (braveUrl "Zeta mirror drift") (hits (list "https://mirror.test/z1" "https://copy.test/z1" "https://mirror.test/z2")))
        (pair (braveUrl "Zeta mirror drift explained") (hits (list "https://mirror.test/z1?utm=x")))
        (pair (braveUrl "Zeta mirror drift benchmark results") (hits (list)))
        (pair (braveUrl "Dead link rot") (hits (list "https://gone.test/d1" "https://gone.test/d2")))
        (pair (braveUrl "Dead link rot explained") (hits (list "https://gone.test/d3")))
        (pair (braveUrl "Dead link rot benchmark results") (hits (list)))
        (pair "https://llm.test/v1/chat/completions" (llmBody (reportOf (listTake (cannedFacts) 2) "")))
        (pair "https://llm.test/bad/chat/completions" (llmBody "no form in this reply")))

fn fact url: String subject: String obj: String quote: String against: Bool -> (Pair String String)
  (pair url (str "(:fact :id \"fact-1\" :predicate (:relation \"states\" :subject \"" subject "\" :object \"" obj "\") :claim \"" quote "\" :evidence \"" quote "\" :source \"" url
                 "\" :sourceKind :unverifiedWeb :verificationStatus :corroborated :crawled true :isFalsifying " (if against "true" "false") ")"))

fn cannedFacts -> (List (Pair String String))
  (list (fact "https://docs.test/a1" "alpha rotor" "40 newton metres" "The alpha rotor delivers 40 newton metres of torque at 3000 rpm" false)
        (fact "https://lab.test/a2" "alpha rotor torque" "12 percent" "Alpha rotor torque falls by 12 percent above 90 degrees celsius" false)
        (fact "https://docs.test/b1" "beta valve" "3 millilitres per hour" "The beta valve leaks 3 millilitres per hour at 5 bar" false)
        (fact "https://forum.test/b2" "beta valve" "no leak below 5 bar" "The beta valve does not leak at all below 5 bar" true)
        (fact "https://wiki.test/b3" "beta valve leakage" "10000 cycles" "Beta valve leakage doubles after 10000 cycles" false)
        (fact "https://more.test/b4" "beta valve leakage" "seat erosion" "Beta valve leakage is explained by seat erosion" false)
        (fact "https://rare.test/g3" "gamma seal wear" "2 microns per year" "Gamma seal wear reaches 2 microns per year" false)
        (fact "https://parts.test/c1" "alpha rotor bearing" "200 newtons" "The alpha rotor bearing preload is 200 newtons" false)
        (fact "https://parts.test/c1" "alpha rotor bearing" "9000 rpm" "The bearing is rated for 9000 rpm" false)
        (fact "https://mirror.test/z1" "zeta mirror" "5 arcseconds per hour" "The zeta mirror drifts 5 arcseconds per hour" false)
        (fact "https://mirror.test/z1?utm=x" "zeta mirror" "5 arcseconds per hour" "The zeta mirror drifts 5 arcseconds per hour" false)
        (fact "https://copy.test/z1" "zeta mirror" "5 arcseconds per hour" "The zeta mirror drifts 5 arcseconds per hour" false)
        (fact "https://mirror.test/z2" "carbon mount" "halves the drift" "The zeta mirror drift halves with a carbon mount" false))

fn reportOf held: (List (Pair String String)) more: String -> String
  (str "(:researchReport :topic \"t\" :summary \"s\" :positiveSynthesis \"p\" :falsificationCritique \"c\"" more " :facts ("
       (pt/joinSep (map (fn [(f (Pair String String))] -> String (pairSecond f)) held) " ") ") :sources ("
       (pt/joinSep (map (fn [(f (Pair String String))] -> String (str "\"" (pairFirst f) "\"")) held) " ") "))")

; (:m :do "the reply of a fixture HTTP model route as an OpenAI-style chat completion: /v1 always answers with the two alpha rotor facts, /bad with no form")
fn llmBody content: String -> String
  (pt/jsonDumps (j/jobj (list (pair "choices" (j/jarr (list (j/jobj (list (pair "message" (j/jobj (list (pair "role" (j/jstr "assistant")) (pair "content" (j/jstr content)))))))))))) -1)

; (:m :do "a writer reached over HTTP through the stub curl, with a route timeout far above any wall of the fixture")
fn httpEntry path: String -> j/Json
  (j/jobj (list (pair "alias" (j/jstr "H")) (pair "dispatch" (j/jstr "m-http")) (pair "upstream" (j/jobj (list (pair "provider" (j/jstr "synthetic")) (pair "url" (j/jstr (str "https://llm.test/" path))))))
                (pair "params" (j/jobj (list))) (pair "timeoutSec" (j/jint 900))))

; (:m :do "what the canned writer marks as open: five candidates beside the a1 page (one to sanitise, one duplicate of a node, one off topic, one more, one beyond the children ceiling), one beside the child page")
fn cannedOpen prompt: String -> String
  (cond
    ((pt/hasSubstr prompt "\"https://docs.test/a1\"") " :openQuestions (\"Alpha rotor: bearing preload?\" \"Alpha Rotor Torque\" \"weather in paris tomorrow\" \"alpha rotor shaft alloy\" \"alpha rotor casing paint\")")
    ((pt/hasSubstr prompt "\"https://parts.test/c1\"") " :openQuestions (\"alpha rotor bearing grease\")")
    (else ""))

; (:m :do "the canned model: a writer reply holds the canned fact of every fixture page its prompt carries, an audit reply supports every fact it is shown, a planning reply splits into two sub-questions")
fn cannedModel cli: String model: j/Json effort: j/Json prompt: String -> (Result j/Json pt/PyErr)
  (cond
    ((pt/pyEq model (j/jstr "m-400")) (err (pt/PyErr :kind "RuntimeError" :msg "HTTP 400")))
    ((and (pt/pyEq model (j/jstr "m-dead")) (stringStartsWith? prompt "AUDIT.")) (err (pt/PyErr :kind "RuntimeError" :msg "timeout")))
    (else (cannedOk cli model effort prompt)))

fn cannedOk cli: String model: j/Json effort: j/Json prompt: String -> (Result j/Json pt/PyErr)
  (let [(reply (cond
                 ((stringStartsWith? prompt "AUDIT.")
                   (pt/joinSep (map (fn [(k Int64)] -> String (str "(:check :id \"fact-" (stringFromInt64 k) "\" :verdict :supported :why \"stated\")"))
                                    (filter (fn [(k Int64)] -> Bool (pt/hasSubstr prompt (str "(:fact :id \"fact-" (stringFromInt64 k) "\""))) (range 1 40)))
                               "\n"))
                 ((and (pt/pyEq model (j/jstr "m-bad")) (pt/hasSubstr prompt "\"https://shop.test/g1\"")) "no form in this reply")
                 ((stringStartsWith? prompt "Research planning:") "(:subQuestions \"delta pump noise\" \"epsilon belt slip\")")
                 (else
                   (reportOf (filter (fn [(f (Pair String String))] -> Bool (pt/hasSubstr prompt (str "\"" (pairFirst f) "\""))) (cannedFacts)) (cannedOpen prompt)))))]
    (ok (j/jobj (list (pair "text" (j/jstr reply))))))

fn entry alias: String model: String -> j/Json
  (j/jobj (list (pair "alias" (j/jstr alias)) (pair "dispatch" (j/jstr (str "codex/" model))) (pair "upstream" (j/jobj (list (pair "provider" (j/jstr "codex-cli"))))) (pair "params" (j/jobj (list)))))

fn stubScript -> String
  "#!/bin/sh\nd=$(dirname \"$0\")\ncat > \"$d/req.$$\"\nurl=$(sed -n 's/^url = \"\\(.*\\)\"$/\\1/p' \"$d/req.$$\")\nn=$(grep -Fxn -e \"$url\" \"$d/urls\" | head -n 1 | cut -d: -f1)\nif [ -z \"$n\" ]; then echo \"stub: no route for $url\" >&2; exit 90; fi\ncat \"$d/r$n.head\" \"$d/r$n.body\"\n"

; (:m :do "the stub curl gets its exec bit through the fleet runner, bounded at 5 s: no bare child start (rule spawnSafety)")
fn ! chmodX! path: String -> Bool
  (ok? (fr/shellOut (str "/bin/chmod 755 " path) 5000))

fn ! stubDir! dir: String -> Bool
  (let [(routes (listAppend (map (fn [(s (Pair String String))] -> (Pair String (Pair String String)) (pair (pairFirst s) (pair "application/json" (pairSecond s)))) (searches))
                            (map (fn [(p (Pair String String))] -> (Pair String (Pair String String)) (pair (pairFirst p) (pair "text/html; charset=utf-8" (pairSecond p)))) (pages))))]
    (and (ok? (dirCreate dir))
         (ok? (fileWrite (str dir "/curl") (stubScript)))
         (chmodX! (str dir "/curl"))
         (ok? (fileWrite (str dir "/urls") (pt/treeJoin (map (fn [(r (Pair String (Pair String String)))] -> String (str (pairFirst r) "\n")) routes))))
         (listAll? (fn [(p (Pair Int64 (Pair String (Pair String String))))] -> Bool
                     (let [(base (str dir "/r" (stringFromInt64 (+ (pairFirst p) 1))))]
                       (and (ok? (fileWrite (str base ".head") (str "HTTP/1.1 200 OK\r\nContent-Type: " (pairFirst (pairSecond (pairSecond p))) "\r\n\r\n")))
                            (ok? (fileWrite (str base ".body") (pairSecond (pairSecond (pairSecond p))))))))
                   (enumerate routes))))

fn ! wireOf! dir: String -> String
  (match (dirList dir)
    ((err _) "")
    ((ok names) (pt/treeJoin (map (fn [(nm String)] -> String (match (fileReadString (str dir "/" nm)) ((ok s) s) ((err _) "")))
                                  (filter (fn [(nm String)] -> Bool (stringStartsWith? nm "req.")) names)))))

fn hub dir: String -> srch/HubState
  (srch/newHubState (mapSet (mapSet (mapEmpty) "PATH" (str dir ":/usr/bin:/bin")) "BRAVE_API_KEY" "brave-test") 0 0 (mapEmpty) (mapEmpty))

fn modelsOf st: srch/HubState -> (List String)
  (map (fn [(c j/Json)] -> String (pt/pyStr (optionOr (pt/jget c "model") (j/jstr "")))) st.cliCalls)

fn promptsOf st: srch/HubState -> (List String)
  (map (fn [(c j/Json)] -> String (pt/pyStr (optionOr (pt/jget c "prompt") (j/jstr "")))) st.cliCalls)

fn outOf dir: String r: (Pair (Result j/Json pt/PyErr) srch/HubState) -> Out
  (match (pairFirst r)
    ((err e) (Out :rep (j/jnull) :asn "" :wire "" :prompts (list) :models (list) :failed (str e.kind ": " e.msg)))
    ((ok rep)
      (Out :rep rep :asn (match (rs/formatResearchAsn rep false) ((ok s) s) ((err e) (str "format failed: " e.msg))) :wire "" :prompts (promptsOf (pairSecond r)) :models (modelsOf (pairSecond r)) :failed "")))

fn ! runMode! dir: String text: String id: String subject: String writers: (List j/Json) audits: (List j/Json) nowMs: Int64 -> Out
  (runClock! dir text id subject writers audits (fn [(u Int64)] -> Int64 nowMs))

; (:m :do "how many requests the stub curl has served in a run directory: the injected clock of a run that must pass its wall half way counts time in requests")
fn ! served! dir: String -> Int64
  (match (dirList dir)
    ((err _) 0)
    ((ok names) (listLength (filter (fn [(nm String)] -> Bool (stringStartsWith? nm "req.")) names))))

fn ! runClock! dir: String text: String id: String subject: String writers: (List j/Json) audits: (List j/Json) clock: (fn [Int64] -> Int64) -> Out
  (if (not (stubDir! dir))
    (Out :rep (j/jnull) :asn "" :wire "" :prompts (list) :models (list) :failed "stub setup failed")
    (match (rs/researchModeOf text id)
      ((err e) (Out :rep (j/jnull) :asn "" :wire "" :prompts (list) :models (list) :failed e.msg))
      ((ok mode)
        (let [(o (outOf dir (rs/executeResearchPlan! (hub dir) subject mode writers false (some audits) (fn [(m String)] -> j/Json (j/jnull)) cannedModel 0 clock)))]
          (Out :rep o.rep :asn o.asn :wire (wireOf! dir) :prompts o.prompts :models o.models :failed o.failed)))))

fn ! runDeep! dir: String c: Caps subject: String audits: (List j/Json) nowMs: Int64 -> Out
  (runMode! dir (modeText c) "deep" subject (list (entry "W" "m-w")) audits nowMs)

fn ! runSingle! dir: String audits: (List j/Json) -> Out
  (if (not (stubDir! dir))
    (Out :rep (j/jnull) :asn "" :wire "" :prompts (list) :models (list) :failed "stub setup failed")
    (let [(o (outOf dir (rs/executeResearchHub! (hub dir) (topic) "flash" (list (entry "W" "m-w")) (j/jstr "auto") false (some audits) (fn [(m String)] -> j/Json (j/jnull)) cannedModel)))]
      (Out :rep o.rep :asn o.asn :wire (wireOf! dir) :prompts o.prompts :models o.models :failed o.failed)))

fn count model: String o: Out -> Int64
  (listLength (filter (fn [(m String)] -> Bool (= m model)) o.models))

fn facts o: Out -> (List j/Json)
  (match (optionOr (pt/jget o.rep "facts") (j/jnull)) ((j/jarr xs) xs) (_ (list)))

fn unaud? f: j/Json -> Bool
  (and (pt/pyEq (optionOr (pt/jget f "verificationStatus") (j/jnull)) (j/jstr "unverified")) (pt/pyEq (optionOr (pt/jget f "audit") (j/jnull)) (j/jstr "unaudited")))

fn statusOf o: Out -> String
  (pt/pyStr (optionOr (pt/jget o.rep "status") (j/jnull)))

fn ! runTests -> Bool
  (let [(base (str "/tmp/aslResearchKeepFacts." (stringFromInt64 (procSelf))))
        (cleanStart (pathRemove base))
        (made (dirCreate base))
        (dead (list (entry "D1" "m-dead") (entry "D2" "m-dead")))
        (both (list (entry "W" "m-w") (entry "A" "m-a")))
        (single (runSingle! (str base "/single") dead))
        (okSingle (runSingle! (str base "/okSingle") both))
        (deep (runMode! (str base "/deep") (modeText (capsOf 3 6 20 20 20 "model" 8 1)) "deep" (topic) (list (entry "W" "m-w")) dead 0))
        (okDeep (runMode! (str base "/okDeep") (modeText (capsOf 3 6 20 20 20 "model" 8 1)) "deep" (topic) (list (entry "W" "m-w")) both 0))
        (wallDir (str base "/wall"))
        (wall (runClock! wallDir (modeText (capsOf 3 6 20 20 20 "model" 8 1)) "deep" (topic) (list (entry "W" "m-w")) both (fn [(u Int64)] -> Int64 (* 150000 (served! wallDir)))))
        (bad (runMode! (str base "/bad") (modeText (capsOf 3 6 20 20 20 "model" 8 1)) "deep" (topic) (list (entry "B" "m-400") (entry "W" "m-w")) both 0))
        (cleaned (pathRemove base))]
    (do
      (if (stringEmpty? single.failed) () (eprintln (str "single run failed: " single.failed)))
      (if (stringEmpty? deep.failed) () (eprintln (str "deep run failed: " deep.failed)))
      (if (stringEmpty? bad.failed) () (eprintln (str "bad run failed: " bad.failed)))
      (assert (and (stringEmpty? okSingle.failed) (= (statusOf okSingle) "verified") (> (listLength (facts okSingle)) 0)) "control: a working auditor leaves the single pipeline verified with facts")
      (assert (and (stringEmpty? single.failed) (= (statusOf single) "unverified") (pt/hasSubstr (pt/pyStr (optionOr (pt/jget single.rep "reason") (j/jnull))) "auditor unavailable after 2 model(s)")
                   (= (listLength (facts single)) (listLength (facts okSingle)))
                   (> (listLength (facts single)) 0))
              "single pipeline: every auditor model fails, the run keeps all extracted facts, status unverified, the reason text is unchanged")
      (assert (pt/hasSubstr (pt/pyStr (optionOr (pt/jget single.rep "reason") (j/jnull))) (str (stringFromInt64 (listLength (facts single))) " fact(s) not audited")) "the reason counts the facts that were kept")
      (assert (and (stringEmpty? okDeep.failed) (> (listLength (facts okDeep)) 0)) "control: a working auditor keeps facts in the plan pipeline")
      (assert (and (stringEmpty? deep.failed) (= (statusOf deep) "unverified") (pt/hasSubstr (pt/pyStr (optionOr (pt/jget deep.rep "reason") (j/jnull))) "auditor unavailable after 2 model(s)")
                   (= (listLength (facts deep)) (listLength (facts okDeep))))
              "plan pipeline: every auditor model fails, the report keeps all extracted facts, status unverified")
      (assert (and (listAll? unaud? (facts single)) (listAll? unaud? (facts deep)) (> (listLength (facts wall)) 0) (listAll? unaud? (facts wall)) (not (listAny? unaud? (facts okSingle))))
              "facts kept without an audit are stamped unverified and unaudited, in the single, plan and wall-budget paths; audited facts are not")
      (assert (and (stringEmpty? bad.failed) (= (count "m-400" bad) 1) (> (count "m-w" bad) 1))
              "an alias that answered HTTP 400 is called once per run, not once per sub-question, and the next alias carries on")
      (assert (ok? cleaned) "stub directories removed")
      true))
