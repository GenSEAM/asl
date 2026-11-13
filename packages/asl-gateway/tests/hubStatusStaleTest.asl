(module aslGateway/tests/hubStatusStaleTest
  :x [runTests]
  :i [(server :a srv)
      (aslGateway/cliDispatch :a cli)
      (aslGateway/chat :a ch)
      (aslGateway/config :a c)
      (aslGateway/poolDispatch :a pd)
      (aslGateway/breaker :a b)
      (aslGateway/upstream :a u)
      (aslGateway/dispatch :a dp)
      (aslGateway/omniApi :a om)])

fn emptyLoop home: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir "/tmp" :registryPath "/tmp/absent.asn"
     :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
     :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
     :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
     :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :affinity (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

; (:m :ref GW-HUB-STATUS-STRICT :do "hubStatusText! with a stale profiles cache carries :configStale (:error ...) that reads back as ASN with the error text; a clean cache has no such field")
fn ! statusWith stale: String -> String
  (srv/hubStatusText! (with (emptyLoop "/tmp") :profiles (c/ProfilesCache :key none :result (err "gateway profiles not loaded") :stale stale)))

fn ! writeStatus! path: String text: String -> Bool
  (ok? (fileWrite path (str text "\n")))

; (:m :ref GW-HUB-STATUS-STRICT :do "the strict probe on the real rendered status: stale fixture exits 1 with --strict and 0 without, clean exits 0 either way, an unreadable file exits 2")
fn ! testRenderAndProbe -> Bool
  (let [(stale (statusWith "profile p1 route any: :spread entry (4) must be (ALIAS WEIGHT)"))
        (clean (statusWith ""))
        (dir (str "/tmp/asl-hubstatus-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate dir))
        (sf (str dir "/stale.asn"))
        (cf (str dir "/clean.asn"))
        (w1 (writeStatus! sf stale))
        (w2 (writeStatus! cf clean))
        (strictStale (cli/gatewayHubStatusCli! (list "--file" sf "--strict")))
        (plainStale (cli/gatewayHubStatusCli! (list "--file" sf)))
        (strictClean (cli/gatewayHubStatusCli! (list "--file" cf "--strict")))
        (missing (cli/gatewayHubStatusCli! (list "--file" (str dir "/absent.asn") "--strict")))
        (noTok (cli/gatewayHubStatusCli! (list "--token-env" "ASL_HUBSTATUS_NO_SUCH_VAR_UMEDIA" "--strict")))
        (gone (pathRemove dir))]
    (do (assert (stringContains? stale " :configStale (:error \"profile p1 route any: :spread entry (4) must be (ALIAS WEIGHT)\")") (str "STALE: the stale cache renders :configStale with its error: " stale))
        (assert (not (stringContains? clean ":configStale")) (str "STALE: a clean cache renders no :configStale: " clean))
        (assert (stringStartsWith? stale "(:hub :uptimeSec ") "STALE: the status keeps its head")
        (assert (cli/hubStatusStale? stale) "STALE: the probe predicate sees the stale form")
        (assert (not (cli/hubStatusStale? clean)) "STALE: the probe predicate is false on a clean status")
        (assert (= strictStale (ok 1)) (str "STALE: --strict exits 1 on a stale status: " strictStale))
        (assert (= plainStale (ok 0)) "STALE: without --strict the probe only prints, exit 0")
        (assert (= strictClean (ok 0)) "STALE: --strict exits 0 on a clean status")
        (assert (= missing (ok 2)) "STALE: an unreadable status file exits 2, not 0")
        (assert (and (cli/tokenSafe? "abc.DEF-123_xyz") (and (not (cli/tokenSafe? "a\"b")) (and (not (cli/tokenSafe? "a\\b")) (and (not (cli/tokenSafe? "a\nb")) (not (cli/tokenSafe? "a\rb")))))) "STALE: a token with a quote, backslash or line break is refused, a plain one passes")
        (assert (= noTok (ok 2)) "STALE: a named token variable that is unset exits 2")
        true))

; (:m :ref GW-CONFIG-LAST-GOOD-LOWS :do "a read error counts as a bad edit: after a good load the file turns unreadable (mode 000) and the load still answers the last good table with :stale set")
fn ! testReadErrorIsBadEdit -> Bool
  (let [(home (str "/tmp/asl-hubstatus-rd-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate (str home "/.asl")))
        (path (c/gatewayProfilesPath home))
        (good "(:gateway :v 2\n  :providers ((:provider :id test :kind openai :base \"https://example.test/v1\" :keyEnv \"TEST_KEY\"))\n  :models ((:model :id m1 :provider test :name \"model-a\"))\n  :profiles ((:profile :id p1 :routes ((:intent any :chain (m1)))))\n  :uses ((:use :for default :profile p1)))")
        (w1 (fileWrite path good))
        (first (c/gatewayProfilesLoad! (c/emptyProfilesCache) home ".asl/mem/calibration/index.asn"))
        (w2 (fileWrite path (str good " ")))
        (modeOff (fileChmod path 0))
        (denied (err? (fileReadString path)))
        (second (c/gatewayProfilesLoad! (pairFirst first) home ".asl/mem/calibration/index.asn"))
        (modeOn (fileChmod path 384))
        (gone (pathRemove home))]
    (do (assert (ok? (pairSecond first)) "READERR: the good file loads")
        (assert (ok? modeOff) "READERR: the mode change applies")
        (if denied
          (do (assert (ok? (pairSecond second)) "READERR: an unreadable file still serves the last good table")
              (assert (not (stringEmpty? (c/profilesStale (pairFirst second)))) (str "READERR: the read error is held as :stale: " (c/profilesStale (pairFirst second))))
              true)
          (do (assert (ok? (pairSecond second)) "READERR: skipped, this user reads a mode 000 file (root); the last good table is still served")
              true))))

fn ! runTests -> Bool
  (do (assert (testRenderAndProbe) "GW-HUB-STATUS-STRICT: render and strict probe")
      (assert (testReadErrorIsBadEdit) "GW-CONFIG-LAST-GOOD-LOWS: a read error is a bad edit")
      true)
