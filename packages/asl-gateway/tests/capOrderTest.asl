(module aslGateway/tests/capOrderTest
  :x [runTests]
  :i [(aslGateway/capOrder :a co)
      (aslGateway/capOrderStats :a cos)
      (aslGateway/usageLedger :a ul)
      (aslGateway/config :a cfg)])

; (:m :ref GW-CAP-ORDER :do "made-up aliases only; ranking is pure so every case hands it stats and a clock, ledger and journal readers run on fixture rows, the write-back runs on a fixture config text, config check on :order rows")
fn now -> Int64
  100000000000

fn opts -> co/OrderOpts
  (co/OrderOpts :explore 12 :refreshS 3600 :minSamples 5 :staleS 3600 :off (list) :at 0)

fn stat alias: String attempts: Int64 green: Int64 -> co/AliasStat
  (co/AliasStat :alias alias :attempts attempts :green green :calls 10 :callsOk 10 :limitHits 0 :capPermille -1 :lastMs (- (now) 1000))

fn pool -> (List co/AliasStat)
  (list (stat "aa" 10 2) (stat "bb" 10 7) (stat "cc" 10 4) (stat "dd" 10 0))

fn weightOf r: co/Ranked a: String -> Int64
  (optionOr (listHead (map (fn [(p (Pair String Int64))] -> Int64 (pairSecond p)) (filter (fn [(p (Pair String Int64))] -> Bool (= (pairFirst p) a)) r.weights))) -1)

fn sumWeights r: co/Ranked -> Int64
  (listSum (map (fn [(p (Pair String Int64))] -> Int64 (pairSecond p)) r.weights))

fn ! testOrder -> Bool
  (let [(r (co/rankChain (list "aa" "bb" "cc" "dd") (pool) (opts) (now)))]
    (do (assert (= r.chain (list "bb" "cc" "aa" "dd")) (str "ORDER: best unit yield first, got " r.chain))
        (assert (= (weightOf r "bb") 53) (str "ORDER: bb weight is its score share of 100, got " (weightOf r "bb")))
        (assert (= (weightOf r "dd") 0) "ORDER: an alias with no green unit weighs 0 but stays in the chain")
        (assert (listEmpty? r.explored) "ORDER: nothing is explored when every alias has fresh samples")
        (assert (<= (sumWeights r) 100) "ORDER: weights never exceed the 100 scale")
        true))

fn ! testExplore -> Bool
  (let [(r (co/rankChain (list "aa" "bb" "cc" "dd" "ee") (pool) (opts) (now)))
        (exploitSum (+ (weightOf r "aa") (+ (weightOf r "bb") (+ (weightOf r "cc") (weightOf r "dd")))))]
    (do (assert (= r.explored (list "ee")) "EXPLORE: an alias without any sample is explored")
        (assert (= (weightOf r "ee") 12) (str "EXPLORE: the configured share goes to the explored alias, got " (weightOf r "ee")))
        (assert (<= exploitSum 88) (str "EXPLORE: exploit weights share the rest, got " exploitSum))
        (assert (= (optionOr (listLast r.chain) "") "ee") "EXPLORE: explored aliases follow the ranked ones in the chain")
        (let [(r2 (co/rankChain (list "aa" "bb" "ee" "ff") (list (stat "aa" 10 2) (stat "bb" 10 7)) (with (opts) :explore 20) (now)))]
          (do (assert (= (+ (weightOf r2 "ee") (weightOf r2 "ff")) 20) "EXPLORE: two explored aliases split the share")
              true))))

fn listLast xs: (List String) -> (Option String)
  (listHead (listReverse xs))

fn ! testStale -> Bool
  (let [(old (co/AliasStat :alias "aa" :attempts 10 :green 9 :calls 10 :callsOk 10 :limitHits 0 :capPermille -1 :lastMs (- (now) 7200000)))
        (r (co/rankChain (list "aa" "bb") (list old (stat "bb" 10 3)) (opts) (now)))]
    (do (assert (= r.explored (list "aa")) "STALE: evidence older than staleS makes the alias explored again")
        (assert (= (weightOf r "aa") 12) "STALE: a stale alias draws the exploration share, not its old score")
        true))

fn ! testOff -> Bool
  (let [(r (co/rankChain (list "aa" "bb" "cc" "dd") (pool) (with (opts) :off (list "cc")) (now)))]
    (do (assert (= r.excluded (list "cc")) "OFF: a turned off alias is named in excluded")
        (assert (not (listContains? r.chain "cc")) "OFF: a turned off alias leaves the chain")
        (assert (= (weightOf r "cc") -1) "OFF: a turned off alias has no weight")
        true))

fn ! testKept -> Bool
  (let [(chain (list "aa" "bb" "cc" "dd" "ee"))
        (r (co/rankChain chain (pool) (with (opts) :off (list "dd")) (now)))]
    (do (assert (= (listSort (listAppend r.chain r.excluded)) (listSort chain)) "KEPT: every original alias is in chain or excluded, none dropped silently")
        (assert (listAll? (fn [(p (Pair String Int64))] -> Bool (>= (pairSecond p) 0)) r.weights) "KEPT: weights are non-negative")
        (assert (= (listLength r.weights) (listLength r.chain)) "KEPT: every chain alias has a weight")
        true))

fn ! testTies -> Bool
  (let [(same (list (stat "aa" 10 5) (stat "bb" 10 5) (stat "cc" 10 5)))
        (r (co/rankChain (list "cc" "aa" "bb") same (opts) (now)))
        (none0 (co/rankChain (list "aa" "bb") (list) (opts) (now)))]
    (do (assert (= r.chain (list "cc" "aa" "bb")) (str "TIES: equal scores keep the original chain order, got " r.chain))
        (assert (= none0.chain (list "aa" "bb")) "TIES: no stats at all keeps the chain order")
        (assert (= (weightOf none0 "aa") 50) "TIES: all explored share the whole scale")
        (assert (= (co/aliasScore (stat "aa" 10 5)) 500) "SCORE: five green of ten attempts is 500 permille")
        (assert (< (co/aliasScore (co/AliasStat :alias "x" :attempts 10 :green 5 :calls 10 :callsOk 5 :limitHits 2 :capPermille 500 :lastMs 1)) 500) "SCORE: failing calls and a half used cap lower the score")
        true))

fn ! testRefresh -> Bool
  (let [(o (with (opts) :at (- (now) 3600000)))]
    (do (assert (co/refreshDue? (opts) (now)) "REFRESH: a route never written is due")
        (assert (co/refreshDue? o (now)) "REFRESH: due exactly at refreshS")
        (assert (not (co/refreshDue? o (- (now) 1))) "REFRESH: not due before refreshS")
        true))

fn ledgerRow atMs: Int64 alias: String outcome: String status: Int64 -> ul/CallRow
  (ul/CallRow :atMs atMs :profile "p" :intent "construct" :alias alias :provider "pv" :model "m" :inTokens 10 :cachedTokens 0 :outTokens 2
    :reasoningTokens 0 :ttftMs none :ms none :outcome outcome :charge 0 :tag none :temperature none :topP none :maxTokens none :effort none
    :api "chat" :stream false :toolCount 0 :promptBytes 0 :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none :status status :reason none)

fn viaParser r: ul/CallRow -> (List ul/CallRow)
  (match (ul/callRowParse (ul/callRowLine r)) ((ok p) (list p)) ((err _) (list)))

fn statOf stats: (List co/AliasStat) a: String -> co/AliasStat
  (optionOr (listHead (filter (fn [(s co/AliasStat)] -> Bool (= s.alias a)) stats)) (co/untestedStat a))

fn journalText -> String
  (str "(:profile :unit \"u1\" :lane \"cheap\" :profile \"w\" :at 900)\n"
       "(:t :unit \"u1\" :from writing :to gating :stage write :model \"aa\" :tokens 5 :costUsd 0.000000 :verdict \"written\" :ms 10 :at 1000)\n"
       "(:t :unit \"u1\" :from merging :to merged :stage merge :model \"\" :tokens 0 :costUsd 0.000000 :verdict \"merged\" :ms 10 :at 2000)\n"
       "(:t :unit \"u2\" :from writing :to gating :stage write :model \"bb\" :tokens 5 :costUsd 0.000000 :verdict \"claimedGreen\" :ms 10 :at 3000)\n"
       "(:t :unit \"u3\" :from writing :to ready :stage write :model \"bb\" :tokens 0 :costUsd 0.000000 :verdict \"fail: gate red\" :ms 10 :at 4000)\n"
       "(:t :unit \"u4\" :from writing :to ready :stage write :model \"cc\" :tokens 0 :costUsd 0.000000 :verdict \"providerFail: 429\" :ms 10 :at 5000)\n"
       "not a row\n")

fn ! testReaders -> Bool
  (let [(rows (listFlatMap viaParser
                (list (ledgerRow 1000 "aa" "ok" 200) (ledgerRow 2000 "aa" "ok" 200) (ledgerRow 3000 "aa" "error" 500) (ledgerRow 4000 "aa" "limit" 0)
                      (ledgerRow 5000 "bb" "ok" 200) (ledgerRow 6000 "bb" "error" 429) (ledgerRow 7000 "cc" "breakerOpen" 0))))
        (led (cos/ledgerStats rows 0))
        (a (statOf led "aa"))
        (b (statOf led "bb"))
        (cc (statOf led "cc"))
        (jres (cos/journalStats (journalText) 0 (plainNames)))
        (jr (pairFirst jres))
        (ja (statOf jr "aa"))
        (jb (statOf jr "bb"))
        (since (cos/ledgerStats rows 5000))
        (both (cos/measuredStats led jr))
        (ba (statOf both "aa"))]
    (do (assert (= (listLength rows) 7) "READ: every fixture row survives the ledger parser round trip")
        (assert (and (= a.calls 3) (= a.callsOk 2)) (str "READ: sent calls and ok calls per alias, got " a.calls " " a.callsOk))
        (assert (= a.limitHits 1) "READ: a limit skip counts as a limit hit")
        (assert (= b.limitHits 1) "READ: a 429 counts as a limit hit")
        (assert (= cc.calls 0) "READ: a gateway-answered breaker row is not a call that reached the provider")
        (assert (= a.lastMs 4000) "READ: newest evidence time per alias")
        (assert (not (listAny? (fn [(s co/AliasStat)] -> Bool (= s.alias "aa")) since)) "READ: rows before sinceMs are ignored")
        (assert (and (= ja.attempts 1) (= ja.green 1)) (str "JOURNAL: aa has one attempt and one merged unit, got " ja.attempts " " ja.green))
        (assert (and (= jb.attempts 2) (= jb.green 0)) (str "JOURNAL: bb has two attempts and no merged unit, got " jb.attempts " " jb.green))
        (assert (not (listAny? (fn [(s co/AliasStat)] -> Bool (= s.alias "cc")) jr)) "JOURNAL: a provider failure is no attempt of the model")
        (assert (and (= ba.attempts 1) (= ba.calls 3) (= ba.green 1)) "MERGE: ledger and journal fields of one alias land in one stat")
        true))

fn cfgWith extra: String -> String
  (str "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n"
       "  :models ((:model :id aa :provider test :name \"n-a\") (:model :id bb :provider test :name \"n-b\") (:model :id cc :provider test :name \"n-c\"))\n"
       "  :profiles ((:profile :id p1 :routes ((:intent any :chain (aa bb cc) :spread ((aa 3) (bb 1)) " extra "))))\n"
       "  :uses ((:use :for default :profile p1)))")

fn parses? text: String -> Bool
  (ok? (cfg/gatewayConfigParse! text "capOrderCheck" ".asl/mem/calibration/index.asn"))

fn ! testCheck -> Bool
  (do (assert (parses? (cfgWith "")) "CHECK: a route without :order parses as before")
      (assert (parses? (cfgWith ":order measured :explore 12 :refreshS 86400")) "CHECK: a valid :order row parses")
      (assert (parses? (cfgWith ":order measured :orderOff (cc) :orderAt 5 :minSamples 3 :staleS 120")) "CHECK: every option parses")
      (assert (not (parses? (cfgWith ":order fixed"))) "CHECK: only measured is a mode")
      (assert (not (parses? (cfgWith ":order measured :explore 90"))) "CHECK: explore above 50 is an error")
      (assert (not (parses? (cfgWith ":order measured :refreshS 5"))) "CHECK: refreshS below 60 is an error")
      (assert (not (parses? (cfgWith ":order measured :orderOff (ghost)"))) "CHECK: an unknown alias in :orderOff is an error")
      (assert (not (parses? (cfgWith ":explore 12"))) "CHECK: an option without :order is an error")
      true)

fn ! testApply -> Bool
  (let [(plain (cfgWith ""))
        (text (cfgWith ":order measured :explore 12 :refreshS 3600"))
        (stats (list (stat "aa" 10 1) (stat "bb" 10 8) (stat "cc" 10 5)))
        (plainRes (cos/orderConfigText plain stats (now)))
        (res (cos/orderConfigText text stats (now)))]
    (match plainRes
      ((err e) (do (assert false (str "APPLY: a plain config must pass through: " e)) false))
      ((ok p)
        (do (assert (= (pairFirst p) plain) "OFF: a config without :order comes back byte for byte")
            (assert (listEmpty? (pairSecond p)) "OFF: no receipt rows without :order")
            (match res
              ((err e) (do (assert false (str "APPLY: " e)) false))
              ((ok r)
                (let [(out (pairFirst r))
                      (again (cos/orderConfigText out stats (+ (now) 1000)))
                      (later (cos/orderConfigText out stats (+ (now) 3600000)))]
                  (do (assert (stringContains? out ":chain (bb cc aa)") (str "APPLY: chain rewritten best first, got " out))
                      (assert (stringContains? out (str ":orderAt " (stringFromInt64 (now)))) "APPLY: the refresh time is stamped")
                      (assert (parses? out) "APPLY: the rewritten config still parses")
                      (assert (stringContains? out ":spread ((bb ") "APPLY: spread follows the ranking")
                      (assert (match again ((ok a) (and (= (pairFirst a) out) (stringContains? (optionOr (listHead (pairSecond a)) "") "fresh"))) ((err _) false)) "REFRESH: a second run inside refreshS leaves the text alone")
                      (assert (match later ((ok a) (stringContains? (optionOr (listHead (pairSecond a)) "") "ranked")) ((err _) false)) "REFRESH: a run past refreshS ranks again")
                      true))))))))

fn plainNames -> (List (Pair String String))
  (list (pair "aa" "aa") (pair "bb" "bb") (pair "cc" "cc"))

fn names -> (List (Pair String String))
  (list (pair "aa" "Vendor/Model-A") (pair "bb" "model-b") (pair "cc" "model-b") (pair "dd" "x/y") (pair "ee" "unknown") (pair "ff" ""))

fn upstreamJournal -> String
  (str "(:t :unit \"u1\" :from writing :to gating :stage write :model \"vendor/model-a\" :tokens 5 :costUsd 0.000000 :verdict \"written\" :ms 10 :at 1000)\n"
       "(:t :unit \"u1\" :from merging :to merged :stage merge :model \"\" :tokens 0 :costUsd 0.000000 :verdict \"merged\" :ms 10 :at 2000)\n"
       "(:t :unit \"u2\" :from writing :to gating :stage write :model \"private/Model-B\" :tokens 5 :costUsd 0.000000 :verdict \"written\" :ms 10 :at 3000)\n"
       "(:t :unit \"u3\" :from writing :to ready :stage write :model \"unknown\" :tokens 0 :costUsd 0.000000 :verdict \"fail: x\" :ms 10 :at 4000)\n"
       "(:t :unit \"u4\" :from writing :to ready :stage write :model \"\" :tokens 0 :costUsd 0.000000 :verdict \"fail: x\" :ms 10 :at 5000)\n"
       "(:t :unit \"u5\" :from writing :to ready :stage write :model \"nope/zzz\" :tokens 0 :costUsd 0.000000 :verdict \"fail: x\" :ms 10 :at 6000)\n")

fn ! testUpstream -> Bool
  (let [(res (cos/journalStats (upstreamJournal) 0 (names)))
        (s (pairFirst res))
        (a (statOf s "aa"))
        (b (statOf s "bb"))
        (c (statOf s "cc"))
        (parsed (cos/modelNames (cfgWith "")))]
    (do (assert (and (= a.attempts 1) (= a.green 1)) (str "UPSTREAM: a case-insensitive exact upstream string credits its alias, got " a.attempts " " a.green))
        (assert (and (= b.attempts 1) (= c.attempts 1)) "UPSTREAM: a provider-prefixed string credits every alias sharing the model")
        (assert (and (= b.green 0) (= c.green 0)) "UPSTREAM: an unmerged unit is not green")
        (assert (= (pairSecond res) 3) (str "UPSTREAM: unknown, empty and unmatched rows are counted, got " (pairSecond res)))
        (assert (not (listAny? (fn [(x co/AliasStat)] -> Bool (or (= x.alias "dd") (or (= x.alias "ee") (= x.alias "ff")))) s)) "UPSTREAM: an alias nobody names, one named unknown and one with an empty name get no row")
        (assert (= parsed (list (pair "aa" "n-a") (pair "bb" "n-b") (pair "cc" "n-c"))) (str "UPSTREAM: model rows give alias and upstream name, got " parsed))
        true))

fn ! testFixRound -> Bool
  (let [(text (cfgWith ":order measured :explore 12 :refreshS 3600 :orderOff (cc)"))
        (stats (list (stat "aa" 10 1) (stat "bb" 10 8) (stat "cc" 10 5)))
        (res (cos/orderConfigText text stats (now)))
        (twice (str (journalText) "(:t :unit \"u1\" :from merging :to merged :stage merge :model \"\" :tokens 0 :costUsd 0.000000 :verdict \"merged\" :ms 10 :at 2500)\n"))
        (jt (pairFirst (cos/journalStats twice 0 (plainNames))))
        (ja (statOf jt "aa"))
        (dir (str (optionOr (envGet "TMPDIR") "/tmp") "/capOrderTest." (stringFromInt64 (procSelf))))
        (_ (pathRemove dir))
        (_ (dirCreate dir))
        (path (str dir "/cfg.asn"))
        (_ (fileWrite path "one"))
        (same (cos/configUnchanged! path "one"))
        (_ (fileWrite path "two"))
        (moved (cos/configUnchanged! path "one"))
        (missing (cos/configUnchanged! (str dir "/none.asn") "one"))
        (_ (pathRemove dir))]
    (do (match res
          ((err e) (assert false (str "OFFKEEP: " e)))
          ((ok r)
            (do (assert (stringContains? (pairFirst r) ":chain (bb aa cc)") (str "OFFKEEP: a turned off alias stays in the written chain, last, got " (pairFirst r)))
                (assert (not (stringContains? (pairFirst r) "(cc ")) "OFFKEEP: a turned off alias gets no spread weight")
                (assert (parses? (pairFirst r)) "OFFKEEP: the written config still parses"))))
        (assert (<= ja.green ja.attempts) (str "GREEN: a unit merged twice counts once, got " ja.green " of " ja.attempts))
        (assert same "LOST: an unchanged config passes the pre-rename check")
        (assert (not moved) "LOST: a config that changed since it was read fails the check")
        (assert (not missing) "LOST: a vanished config fails the check")
        true))

fn ! testRace -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/capOrderRace." (stringFromInt64 (procSelf))))
        (_ (pathRemove dir))
        (_ (dirCreate dir))
        (config (str dir "/cfg.asn"))
        (tmp (str config ".order.tmp"))
        (backup (str config ".bak"))
        (_ (fileWrite config "old"))
        (raced (cos/commitOrdered! config "old" "ranked" tmp backup (fn [] -> Bool (ok? (fileWrite config "edited by someone else")))))
        (afterRace (resultOr (fileReadString config) ""))
        (tmpLeft (ok? (fileStat tmp)))
        (_ (fileWrite config "old"))
        (clean (cos/commitOrdered! config "old" "ranked" tmp backup (fn [] -> Bool true)))
        (afterClean (resultOr (fileReadString config) ""))
        (_ (pathRemove dir))]
    (do (assert (= raced (ok 1)) "RACE: a config that moved between read and rename is refused")
        (assert (= afterRace "edited by someone else") "RACE: the concurrent edit is kept, nothing written over it")
        (assert (not tmpLeft) "RACE: the tmp file is removed on refusal")
        (assert (= clean (ok 0)) "RACE: an unchanged config is renamed over")
        (assert (= afterClean "ranked") "RACE: the ranked text is the config after a clean commit")
        true))

fn ! testCli -> Bool
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/capOrderCli." (stringFromInt64 (procSelf))))
        (_ (pathRemove dir))
        (_ (dirCreate dir))
        (config (str dir "/cfg.asn"))
        (journal (str dir "/journal.asn"))
        (text (cfgWith ":order measured :explore 12 :refreshS 3600 :minSamples 1 :staleS 31536000"))
        (_ (fileWrite config text))
        (_ (fileWrite journal (str "(:t :unit \"u1\" :from writing :to gating :stage write :model \"n-b\" :tokens 5 :costUsd 0.000000 :verdict \"written\" :ms 10 :at 1000)\n"
                                   "(:t :unit \"u1\" :from merging :to merged :stage merge :model \"\" :tokens 0 :costUsd 0.000000 :verdict \"merged\" :ms 10 :at 2000)\n"
                                   "(:t :unit \"u2\" :from writing :to ready :stage write :model \"n-a\" :tokens 0 :costUsd 0.000000 :verdict \"fail: x\" :ms 10 :at 3000)\n")))
        (base (list "--config" config "--ledger" (str dir "/none.asn") "--journal" journal "--now" "10000000" "--windowH" "100000"))
        (dry (cos/orderCli! base))
        (afterDry (resultOr (fileReadString config) ""))
        (applied (cos/orderCli! (listAppend base (list "--apply"))))
        (afterApply (resultOr (fileReadString config) ""))
        (files (resultOr (dirList dir) (list)))
        (backups (filter (fn [(f String)] -> Bool (stringContains? f ".bak-")) files))
        (_ (pathRemove dir))]
    (do (assert (= dry (ok 0)) "CLI: a dry run succeeds")
        (assert (= afterDry text) "CLI: a dry run writes nothing")
        (assert (= applied (ok 0)) "CLI: --apply succeeds")
        (assert (stringContains? afterApply ":chain (bb aa cc)") (str "CLI: --apply writes the ranked chain, got " afterApply))
        (assert (stringContains? afterApply ":spread ((bb ") "CLI: --apply writes the spread")
        (assert (stringContains? afterApply ":orderAt 10000000") "CLI: --apply stamps :orderAt")
        (assert (= (listLength backups) 1) "CLI: --apply keeps one backup of the old config")
        true))

fn ! runTests -> Bool
  (do (testOrder) (testExplore) (testStale) (testOff) (testKept) (testTies) (testRefresh) (testReaders) (testCheck) (testApply) (testUpstream) (testFixRound) (testRace) (testCli) true)
