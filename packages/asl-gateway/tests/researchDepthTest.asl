(module aslGateway/tests/researchDepthTest
  :x [runTests]
  :i [(asl-json/json :a j) (pyText :a pt) (search :a srch) (research :a rs) (asl-tools/fleet/run :a fr)])

; (:m :ref RESEARCH-DEPTH :do "depth modes over the stub curl and a canned model: no network, no model call; every run owns one directory under /tmp, removed at the end")

(schema Out (:f rep j/Json) (:f asn String) (:f wire String) (:f prompts (List String)) (:f failed String))

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

fn promptsOf st: srch/HubState -> (List String)
  (map (fn [(c j/Json)] -> String (pt/pyStr (optionOr (pt/jget c "prompt") (j/jstr "")))) st.cliCalls)

fn outOf dir: String r: (Pair (Result j/Json pt/PyErr) srch/HubState) -> Out
  (match (pairFirst r)
    ((err e) (Out :rep (j/jnull) :asn "" :wire "" :prompts (list) :failed (str e.kind ": " e.msg)))
    ((ok rep)
      (Out :rep rep :asn (match (rs/formatResearchAsn rep false) ((ok s) s) ((err e) (str "format failed: " e.msg))) :wire "" :prompts (promptsOf (pairSecond r)) :failed "")))

fn ! runMode! dir: String text: String id: String subject: String writers: (List j/Json) audits: (List j/Json) nowMs: Int64 -> Out
  (runClock! dir text id subject writers audits (fn [(u Int64)] -> Int64 nowMs))

; (:m :do "how many requests the stub curl has served in a run directory: the injected clock of a run that must pass its wall half way counts time in requests")
fn ! served! dir: String -> Int64
  (match (dirList dir)
    ((err _) 0)
    ((ok names) (listLength (filter (fn [(nm String)] -> Bool (stringStartsWith? nm "req.")) names))))

fn ! runClock! dir: String text: String id: String subject: String writers: (List j/Json) audits: (List j/Json) clock: (fn [Int64] -> Int64) -> Out
  (if (not (stubDir! dir))
    (Out :rep (j/jnull) :asn "" :wire "" :prompts (list) :failed "stub setup failed")
    (match (rs/researchModeOf text id)
      ((err e) (Out :rep (j/jnull) :asn "" :wire "" :prompts (list) :failed e.msg))
      ((ok mode)
        (let [(o (outOf dir (rs/executeResearchPlan! (hub dir) subject mode writers false (some audits) (fn [(m String)] -> j/Json (j/jnull)) cannedModel 0 clock)))]
          (Out :rep o.rep :asn o.asn :wire (wireOf! dir) :prompts o.prompts :failed o.failed)))))

fn ! runDeep! dir: String c: Caps subject: String audits: (List j/Json) nowMs: Int64 -> Out
  (runMode! dir (modeText c) "deep" subject (list (entry "W" "m-w")) audits nowMs)

fn ! runSingle! dir: String audits: (List j/Json) -> Out
  (if (not (stubDir! dir))
    (Out :rep (j/jnull) :asn "" :wire "" :prompts (list) :failed "stub setup failed")
    (let [(o (outOf dir (rs/executeResearchHub! (hub dir) (topic) "flash" (list (entry "W" "m-w")) (j/jstr "auto") false (some audits) (fn [(m String)] -> j/Json (j/jnull)) cannedModel)))]
      (Out :rep o.rep :asn o.asn :wire (wireOf! dir) :prompts o.prompts :failed o.failed)))

fn asked? o: Out query: String -> Bool
  (pt/hasSubstr o.wire (str "url = \"" (braveUrl query) "\""))

fn fetched? o: Out url: String -> Bool
  (pt/hasSubstr o.wire (str "url = \"" url "\""))

fn strs v: j/Json -> (List String)
  (match v ((j/jarr xs) (map (fn [(x j/Json)] -> String (pt/pyStr x)) xs)) (_ (list)))

fn sourcesOf o: Out -> (List String)
  (listSort (strs (optionOr (pt/jget o.rep "sources") (j/jnull))))

fn rowOf o: Out sid: String -> j/Json
  (match (optionOr (pt/jget o.rep "coverage") (j/jnull))
    ((j/jarr xs) (optionOr (listHead (filter (fn [(r j/Json)] -> Bool (pt/pyEq (optionOr (pt/jget r "id") (j/jnull)) (j/jstr sid))) xs)) (j/jnull)))
    (_ (j/jnull)))

; (:m :do "a coverage row as state/stop/facts/sourcesTaken, so an assert names all four")
fn row o: Out sid: String -> String
  (let [(r (rowOf o sid)) (g (fn [(k String)] -> String (pt/pyStr (optionOr (pt/jget r k) (j/jstr "")))))]
    (str (g "state") "/" (g "stop") "/" (g "facts") "/" (g "sourcesTaken")))

fn parentOf o: Out sid: String -> String
  (pt/pyStr (optionOr (pt/jget (rowOf o sid) "parent") (j/jstr "")))

fn planStr o: Out k: String -> String
  (pt/pyStr (optionOr (pt/jget (optionOr (pt/jget o.rep "plan") (j/jnull)) k) (j/jstr "")))

fn uncovered o: Out -> (List String)
  (strs (optionOr (pt/jget o.rep "uncovered") (j/jnull)))

fn subOfFact o: Out url: String -> String
  (match (optionOr (pt/jget o.rep "facts") (j/jnull))
    ((j/jarr xs) (pt/joinSep (map (fn [(f j/Json)] -> String (pt/pyStr (optionOr (pt/jget f "sub") (j/jstr ""))))
                                  (filter (fn [(f j/Json)] -> Bool (pt/pyEq (optionOr (pt/jget f "sourceUrl") (j/jnull)) (j/jstr url))) xs)) ","))
    (_ ""))

fn modeErr text: String id: String -> String
  (match (rs/researchModeOf text id) ((ok _) "") ((err e) e.msg))

fn ! runTests -> Bool
  (let [(base (str "/tmp/aslResearchDepth." (stringFromInt64 (procSelf))))
        (cleanStart (pathRemove base))
        (made (dirCreate base))
        (both (list (entry "W" "m-w") (entry "A" "m-a")))
        (c (capsOf 3 6 20 20 20 "model" 8 1))
        (full (modeText c))
        (single (runSingle! (str base "/single") both))
        (flash (runMode! (str base "/flash") full "flash" (topic) (list (entry "W" "m-w")) both 0))
        (twoStops (runDeep! (str base "/twoStops") (capsOf 3 6 2 20 20 "model" 3 1) (topic) both 0))
        (broken (runMode! (str base "/broken") full "deep" (topic) (list (entry "B" "m-bad") (j/jobj (list (pair "dispatch" (j/jstr "codex/m-x"))))) both 0))
        (steps (rs/researchParts "Steps:\n1. alpha rotor\n2. beta valve"))
        (unsplit (map (fn [(s String)] -> Int64 (listLength (pairSecond (rs/researchParts s)))) (list "Pick option 1) or 2) for the build" "phase 1) design; phase 2) build" "Upgrade from 1. 2 to 2. 0 breaks things" "(1) a; (3) c; (2) b")))
        (deep (runDeep! (str base "/deep") c (topic) both 0))
        (sameAuditor (runDeep! (str base "/same") c (topic) (list (entry "W" "m-w")) 0))
        (oneSource (runDeep! (str base "/ceiling") (capsOf 3 1 20 20 20 "model" 8 1) (topic) both 0))
        (fewSearches (runDeep! (str base "/searches") (capsOf 3 6 2 20 20 "model" 8 1) (topic) both 0))
        (fewFetches (runDeep! (str base "/fetches") (capsOf 3 6 20 3 20 "model" 8 1) (topic) both 0))
        (fewCalls (runDeep! (str base "/calls") (capsOf 3 6 20 20 2 "model" 8 1) (topic) both 0))
        (lateClock (runDeep! (str base "/wall") c (topic) both 700000))
        (capped (runDeep! (str base "/capped") (capsOf 2 6 20 20 20 "model" 8 1) (topic) both 0))
        (split (runDeep! (str base "/split") c "Small pump faults" both 0))
        (fewNodes (runDeep! (str base "/nodes") (capsOf 3 6 20 20 20 "model" 4 1) (topic) both 0))
        (deeper (runDeep! (str base "/deeper") (capsOf 3 6 20 20 20 "model" 8 2) (topic) both 0))
        (whole (runDeep! (str base "/whole") (capsOf 3 6 20 20 20 "enumerated" 8 1) "Small pump faults" both 0))
        (mirror (runDeep! (str base "/mirror") (capsOf 3 6 20 20 20 "enumerated" 8 1) "Zeta mirror drift" both 0))
        (oneFetch (runDeep! (str base "/oneFetch") (capsOf 3 6 20 1 20 "model" 8 1) (topic) both 0))
        (margin3 (runMode! (str base "/margin3") (pt/replaceAll full ":resolveMargin 2 :counterQuery" ":resolveMargin 3 :counterQuery") "deep" (topic) (list (entry "W" "m-w")) both 0))
        (nearWall (runMode! (str base "/nearWall") full "deep" (topic) (list (httpEntry "v1")) both 598500))
        (midDir (str base "/wallMid"))
        (wallMid (runClock! midDir full "deep" (topic) (list (entry "W" "m-w")) both (fn [(u Int64)] -> Int64 (* 150000 (served! midDir)))))
        (dead (runDeep! (str base "/dead") (capsOf 3 6 20 20 20 "enumerated" 8 1) "Dead link rot" both 0))
        (garbled (runMode! (str base "/garbled") full "deep" (topic) (list (entry "B" "m-bad")) both 0))
        (chainDir (str base "/chainWall"))
        (chainWall (runClock! chainDir (modeText (capsOf 3 6 20 20 20 "enumerated" 8 1)) "deep" "Zeta mirror drift" (list (httpEntry "bad") (entry "W" "m-w")) both (fn [(u Int64)] -> Int64 (* 160000 (served! chainDir)))))
        (fetchDir (str base "/fetchWall"))
        (fetchWall (runClock! fetchDir full "deep" (topic) (list (entry "W" "m-w")) both (fn [(u Int64)] -> Int64 (* 200000 (served! fetchDir)))))
        (lean (j/jobj (list (pair "alias" (j/jstr "L")) (pair "dispatch" (j/jstr "m-l")))))
        (timeoutOf (fn [(e j/Json)] -> String (pt/pyStr (optionOr (pt/jget e "timeoutSec") (j/jstr "unset")))))
        (parts (rs/researchParts (topic)))
        (bare (rs/researchParts "1) rotor torque; 2) valve leakage"))
        (plain (rs/researchParts "rotor torque in version 2 (1) of the engine"))
        (deepMode (rs/researchModeOf full "deep"))
        (variants (match deepMode ((ok m) (map (fn [(q (Pair Bool String))] -> String (pairSecond q)) (rs/subQueries m "Widget engines, 2026" "beta valve leakage"))) ((err _) (list))))
        (cleaned (pathRemove base))]
    (do
      (if (stringEmpty? deep.failed) () (eprintln (str "deep run failed: " deep.failed)))
      (if (stringEmpty? flash.failed) () (eprintln (str "flash run failed: " flash.failed)))
      (assert (and (= (pairFirst parts) "Widget engines") (= (pairSecond parts) (list "alpha rotor torque" "beta valve leakage" "gamma seal wear"))) "an enumerated topic splits into its stem and its own parts")
      (assert (= (pairSecond bare) (list "rotor torque" "valve leakage")) "the 1) 2) style splits too")
      (assert (listEmpty? (pairSecond plain)) "a single marker is not an enumeration")
      (assert (= variants (list "Widget engines beta valve leakage" "beta valve leakage" "beta valve leakage explained" "beta valve leakage benchmark results")) "query variants: stem clause + part, bare part, then each declared reformulation")
      (assert (pt/hasSubstr (modeErr "(:mode :id deep :pipeline plan :subQuestions 3)" "deep") "lacks an integer :queriesPerSub") "a plan row without a budget names the missing key")
      (assert (pt/hasSubstr (modeErr full "exhaustive") "no (:mode :id exhaustive") "an undeclared mode is an error")
      (assert (match (rs/researchModeOf "(:mode :id flash :pipeline single :depth flash)" "flash") ((ok m) (pt/pyEq (optionOr (pt/jget m "pipeline") (j/jnull)) (j/jstr "single"))) ((err _) false)) "a single row needs no budgets")
      (assert (and (stringEmpty? single.failed) (= (sourcesOf single) (list "https://docs.test/a1" "https://docs.test/b1")) (fetched? single "https://shop.test/g1") (none? (pt/jget single.rep "coverage"))) "the single pipeline fetches all three results and reports no coverage")
      (assert (and (stringEmpty? flash.failed) (= (row flash "s1") "covered/sufficient/2/2") (= (sourcesOf flash) (list "https://docs.test/a1" "https://docs.test/b1")) (not (fetched? flash "https://shop.test/g1")))
              "adaptive flash: two agreeing sources cover the question, the third result is never fetched")
      (assert (and (= (planStr flash "decomposition") "none") (asked? flash (topic))) "flash never splits an enumerated topic")
      (assert (and (stringEmpty? deep.failed) (= (planStr deep "decomposition") "enumerated") (= (row deep "s1") "covered/sufficient/2/2") (not (fetched? deep "https://blog.test/a3")) (not (asked? deep "alpha rotor torque")))
              "agreeing sources stop a unit below its source ceiling and before any further query")
      (assert (and (= (row deep "s2") "covered/sufficient/4/4") (fetched? deep "https://wiki.test/b3") (asked? deep (counterOf "beta valve leakage")) (fetched? deep "https://more.test/b4") (not (asked? deep "beta valve leakage")))
              "sources that contradict each other keep the unit going: the rest of the results, then one counter-evidence query, until one side leads")
      (assert (not (asked? deep (counterOf "alpha rotor torque"))) "no counter-evidence query without a contradiction")
      (assert (and (= (row deep "s3") "noEvidence/saturated/0/2") (asked? deep "gamma seal wear") (asked? deep "gamma seal wear explained") (not (asked? deep "gamma seal wear benchmark results")))
              "two batches without a new verified fact saturate a unit before its queries run out")
      (assert (= (sourcesOf deep) (list "https://docs.test/a1" "https://docs.test/b1" "https://forum.test/b2" "https://lab.test/a2" "https://more.test/b4" "https://parts.test/c1" "https://wiki.test/b3")) "deep holds the flash sources and five more")
      (assert (and (= (subOfFact deep "https://more.test/b4") "s2") (pt/hasSubstr deep.asn ":sub \"s2\"")) "a fact keeps the id of its sub-question")
      (assert (= (uncovered deep) (list "Widget engines: gamma seal wear")) "the report names the sub-question left without evidence")
      (assert (and (pt/hasSubstr deep.asn "(:sub :id \"s3\" :state :noEvidence :stop :saturated :facts 0 :factSources 0 :sourcesTaken 2") (pt/hasSubstr deep.asn ":uncovered (\"Widget engines: gamma seal wear\")")
                   (pt/hasSubstr deep.asn "without enough evidence: Widget engines: gamma seal wear"))
              "the ASN report carries each unit's state, stop reason and sources taken, the uncovered list and a summary naming the open part")
      (assert (and (pt/pyEq (optionOr (pt/jget (optionOr (pt/jget deep.rep "auditor") (j/jnull)) "alias") (j/jnull)) (j/jstr "A")) (pt/hasSubstr deep.asn ":auditorIndependent true")) "the auditor is the chain entry that is not the writer's model")
      (assert (and (pt/pyEq (optionOr (pt/jget (optionOr (pt/jget sameAuditor.rep "auditor") (j/jnull)) "alias") (j/jnull)) (j/jstr "W")) (pt/hasSubstr sameAuditor.asn ":auditorIndependent false :auditNote \"the auditor is the writer's model")) "an audit chain with only the writer's model is said so in the report")
      (assert (and (= (row oneSource "s1") "thin/ceiling/1/1") (not (fetched? oneSource "https://lab.test/a2")) (not (asked? oneSource "alpha rotor torque")) (= (row oneSource "s3") "noEvidence/ceiling/0/1")) "the source ceiling stops a unit that is not yet sufficient, without a further query")
      (assert (and (= (planStr fewSearches "stoppedBy") "searches") (= (row fewSearches "s1") "covered/sufficient/2/2") (= (row fewSearches "s2") "contested/budget/3/3") (= (row fewSearches "s3") "budget/budget/0/0")
                   (not (asked? fewSearches (counterOf "beta valve leakage"))) (not (asked? fewSearches "Widget engines gamma seal wear")) (= (listLength (uncovered fewSearches)) 2))
              "the search budget stops the run: the contradiction stays open and is reported as contested, the last sub-question is not started")
      (assert (and (= (planStr fewFetches "stoppedBy") "fetches") (= (row fewFetches "s2") "thin/budget/1/1") (not (fetched? fewFetches "https://forum.test/b2"))) "the fetch budget cuts a batch short and stops the unit")
      (assert (and (= (planStr fewCalls "stoppedBy") "modelCalls") (= (row fewCalls "s1") "covered/sufficient/2/2") (= (row fewCalls "s2") "budget/budget/0/0") (not (asked? fewCalls "Widget engines beta valve leakage"))
                   (listAny? (fn [(p String)] -> Bool (stringStartsWith? p "AUDIT.")) fewCalls.prompts))
              "the model-stage budget stops the next sub-question before it searches and keeps the audit stage it reserved")
      (assert (and (= (planStr lateClock "stoppedBy") "wall") (= (row lateClock "s1") "budget/budget/0/0") (= (row lateClock "s3") "budget/budget/0/0") (stringEmpty? lateClock.wire) (listEmpty? lateClock.prompts)
                   (pt/pyEq (optionOr (pt/jget lateClock.rep "status") (j/jnull)) (j/jstr "noEvidence")))
              "past the wall budget nothing is searched or sent to a model")
      (assert (and (= (planStr capped "stoppedBy") "subQuestions") (= (row capped "s3") "budget/budget/0/0") (not (asked? capped "Widget engines gamma seal wear")) (= (uncovered capped) (list "Widget engines: gamma seal wear")))
              "a part beyond the sub-question budget is not researched and is named as uncovered")
      (assert (and (= (planStr split "decomposition") "model") (asked? split "delta pump noise") (asked? split "epsilon belt slip") (= (uncovered split) (list "delta pump noise" "epsilon belt slip")) (= (row split "s1") "noEvidence/queriesExhausted/0/0"))
              "a topic without parts is split by one model stage into sub-questions that are each searched until their queries run out")
      (assert (and (= (planStr whole "decomposition") "none") (asked? whole "Small pump faults") (not (asked? whole "delta pump noise"))) "with :decompose enumerated a topic without parts stays one unit")
      (assert (and (= (row deep "s1.1") "thin/queriesExhausted/2/1") (asked? deep "alpha rotor bearing preload") (= (row deep "s1.2") "noEvidence/queriesExhausted/0/0") (asked? deep "alpha rotor shaft alloy") (= (parentOf deep "s1.1") "s1") (= (parentOf deep "s1.2") "s1"))
              "open questions of a finished unit become its children, each a unit of its own, their text rebuilt from word tokens; two facts from one source stay below a floor of two sources")
      (assert (and (not (asked? deep "weather in paris tomorrow")) (not (asked? deep "alpha rotor casing paint")) (= (row deep "s1.3") "///")
                   (pt/hasSubstr deep.asn ":notSpawned (:duplicate 1 :irrelevant 1 :depth 1 :children 1 :nodes 0 :budget 0)"))
              "a duplicate of a node, an off-topic question and one beyond the children ceiling are not spawned and are counted by reason")
      (assert (and (not (asked? deep "alpha rotor bearing grease")) (asked? deeper "alpha rotor bearing grease") (= (parentOf deeper "s1.1.1") "s1.1")) "the depth ceiling bounds the tree: a grandchild only when the row allows depth 2")
      (assert (and (= (subOfFact deep "https://parts.test/c1") "s1.1,s1.1") (pt/hasSubstr deep.asn "(:sub :id \"s1.1\" :state :thin :stop :queriesExhausted :facts 2 :factSources 1 :sourcesTaken 1 :searches 3 :parent \"s1\"")) "a child fact keeps its node id and the report carries the parent of every node")
      (assert (and (= (planStr fewNodes "stoppedBy") "nodes") (= (row fewNodes "s1.1") "thin/queriesExhausted/2/1") (= (row fewNodes "s1.2") "///") (not (asked? fewNodes "alpha rotor shaft alloy"))) "the node ceiling stops the tree and is named")
      (assert (and (= (row fewSearches "s1.1") "budget/budget/0/0") (not (asked? fewSearches "alpha rotor bearing preload"))) "children share the run budgets: with searches spent a spawned child is not researched")
      (assert (and (= (row flash "s1.1") "///") (not (asked? flash "alpha rotor bearing preload")) (not (listAny? (fn [(p String)] -> Bool (pt/hasSubstr p "Open questions:")) flash.prompts))
                   (listAny? (fn [(p String)] -> Bool (pt/hasSubstr p "Open questions:")) deep.prompts))
              "depth 0 grows nothing and sends the pinned prompt; a growing mode asks the extractor for open questions")
      (assert (and (= (subOfFact deep "https://docs.test/a1") "s1") (not (pt/hasSubstr (subOfFact deep "https://docs.test/a1") "s2"))) "a source one unit already took is not taken again by another unit of the plan")
      (assert (and (= (planStr twoStops "stoppedBy") "nodes") (= (row twoStops "s1.1") "///") (= (row twoStops "s2") "contested/budget/3/3") (= (row twoStops "s3") "budget/budget/0/0")) "the first stop of a run is the one named: the node ceiling met after the first unit stays named when the search budget runs out later")
      (assert (and (stringEmpty? broken.failed) (= (row broken "s1") "covered/sufficient/2/2") (= (row broken "s2") "covered/sufficient/4/4") (= (row broken "s3") "failed/error/0/0")
                   (pt/hasSubstr broken.asn "(:sub :id \"s3\" :state :failed :stop :error") (pt/hasSubstr broken.asn ":error \"KeyError") (= (uncovered broken) (list "Widget engines: gamma seal wear")))
              "a hard error inside one unit fails that unit, named in its row, and keeps the units before it")
      (assert (and (= (pairSecond steps) (list "alpha rotor" "beta valve")) (= unsplit (list 0 0 0 0))) "numbered lines split; option 1) or 2), phase 1) .. phase 2), version 1. 2 and out-of-order markers do not")
      (assert (and (pt/hasSubstr (modeErr (str full full) "deep") "more than one (:mode :id deep") (pt/hasSubstr (modeErr "(:mode :id deep :pipeline plan :reformulations explained)" "deep") ":reformulations as a list")) "a duplicate mode row and a non-list :reformulations are errors")
      (assert (and (= (row mirror "s1") "thin/queriesExhausted/4/4") (pt/hasSubstr mirror.asn ":facts 4 :factSources 1 :sourcesTaken 4"))
              "sources are counted by registrable host and a sentence repeated on another host counts once: one host, its tracking-parameter copy and a mirror do not meet a floor of two sources")
      (assert (and (= (planStr oneFetch "stoppedBy") "fetches") (= (row oneFetch "s1") "thin/budget/1/1") (= (row oneFetch "s1.1") "///") (not (asked? oneFetch "alpha rotor bearing preload")) (pt/hasSubstr oneFetch.asn ":nodes 0 :budget 5)"))
              "a unit stopped by a budget spawns no children: its open questions are counted as not spawned")
      (assert (and (= (row margin3 "s2") "contested/queriesExhausted/4/4") (asked? margin3 (counterOf "beta valve leakage")) (pt/hasSubstr margin3.asn "(:sub :id \"s2\" :state :contested :stop :queriesExhausted :facts 4 :factSources 4 :sourcesTaken 4 :searches 5 "))
              "a contradiction that outlives its counter-evidence query does not ask it again: five searches (the first query, the counter query, three follow-ups), then the unit ends contested")
      (assert (and (= (row nearWall "s1") "covered/sufficient/2/2") (pt/hasSubstr nearWall.wire "max-time = 2\n") (not (pt/hasSubstr nearWall.wire "max-time = 900")) (pt/hasSubstr nearWall.wire "max-time = 1.5\n")
                   (not (pt/hasSubstr nearWall.wire "max-time = 3.5")) (pt/hasSubstr deep.wire "max-time = 3.5\n"))
              "with 1.5 s of wall left a model route of 900 s is sent with 2 s and a fetch with 1.5 s; far from the wall a fetch keeps its 3.5 s")
      (assert (and (= (map timeoutOf (list (rs/stageEntry (httpEntry "v1") 30000) (rs/stageEntry lean 20000) (rs/stageEntry lean 60000) (rs/stageEntry (httpEntry "v1") 2000000))) (list "30" "20" "unset" "900"))
                   (= (list (rs/stageSeconds 400 30000) (rs/stageSeconds 400 900000) (rs/stageSeconds 400 1)) (list 30 400 1)))
              "a stage timeout is cut to the wall left and never raised: 900 s to 30 s, the default 45 s to 20 s, untouched when the wall left is longer")
      (assert (and (= (planStr wallMid "stoppedBy") "wall") (= (row wallMid "s1") "covered/sufficient/2/2") (= (row wallMid "s2") "noEvidence/budget/0/0") (= (sourcesOf wallMid) (list "https://docs.test/a1" "https://lab.test/a2"))
                   (pt/pyEq (optionOr (pt/jget wallMid.rep "status") (j/jnull)) (j/jstr "unverified")) (pt/hasSubstr (pt/pyStr (optionOr (pt/jget wallMid.rep "reason") (j/jnull))) "before the audit stage")
                   (not (listAny? (fn [(p String)] -> Bool (stringStartsWith? p "AUDIT.")) wallMid.prompts)))
              "a run that passes its wall half way returns the partial report: the finished unit and its facts stay, later units are not researched, the audit is not started and the report says so")
      (assert (and (listEmpty? chainWall.prompts) (pt/hasSubstr (pt/jsonDumps (optionOr (pt/jget chainWall.rep "tried") (j/jnull)) -1) "no wall left") (= (planStr chainWall "stoppedBy") "wall") (= (row chainWall "s1") "noEvidence/budget/0/2"))
              "when the first entry of a chain uses up the wall, the next entry is not started and is listed as not tried for lack of wall")
      (assert (and (= (planStr fetchWall "stoppedBy") "wall") (= (row fetchWall "s1") "noEvidence/budget/0/2") (listEmpty? fetchWall.prompts) (not (pt/hasSubstr fetchWall.asn ":error")))
              "when the fetches of a batch use up the wall, the batch is not sent to a model and the unit stops on the wall budget, not on an extractor error")
      (assert (= (row dead "s1") "noEvidence/queriesExhausted/0/3") "batches of pages that could not be fetched do not saturate a unit: it goes on until its queries run out")
      (assert (and (= (row garbled "s3") "thin/queriesExhausted/1/3") (pt/hasSubstr garbled.asn ":searches 4 :error \"research chain exhausted\"")) "a batch whose extractor chain gave no usable reply does not count toward saturation: the unit goes on to the source that holds its fact")
      (assert (ok? cleaned) "stub directories removed")
      true))
