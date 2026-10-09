(module asl/agentLoop/tests/cardTest
  :x [runTests]
  :i [(asl/agentLoop/card :a card)])

fn writeFixture! path: String content: String -> Bool
  (mt (fileWrite path content)
    ((err _) false)
    ((ok _) true))

fn cardText res: (Result card/AgentCard String) -> String
  (mt res
    ((ok value) (card/formatCardAsn value))
    ((err e) e))

fn cardFails! root: String -> Bool
  (mt (card/buildCard root)
    ((ok _) false)
    ((err _) true))

fn loopSource -> String
  "DELIVERABLES = (\"patch\", \"findings\")\n\n_OP_SHAPES = {\n    \"read\": '(:read p)',\n    \"escalate\": '(:escalate :why \"s\" :to \\'x\\')',\n}\n"

fn mainSource -> String
  "(module fixture)\n\nfn formatReceipt r: R -> String\n  (str \"(:agentReceipt :status :\" s \" :fixtureField \" f \" :gates ((:cmd \\\"\" c \"\\\" :exit 0)) :journal ())\" \")\")\n\nfn formatDryRun -> String\n  \" :notAField \"\n"

fn ! runTests -> Bool
  (let [root (optionOr (envGet "ASL_ROOT_DIR") ".")
        tmp (processRun "mktemp -d /tmp/asl-card-regression-fixture.XXXXXX")
        fixtureRoot (stringTrim tmp.stdout)
        dirs (processRun (str "mkdir -p " fixtureRoot "/scripts/agentLoop " fixtureRoot "/bin " fixtureRoot "/asl/agentLoop"))
        backendSource "for v in (\"agy\", \"nova\"):\n    pass\nif backend_str.startswith( 'mock/'):\n    pass\nmodel = self.model or \"fixture-model\"\n"
        gatewaySource "TrackedSemaphore(int(os.environ.get(\"AGY_CONCURRENCY\", 17)), name=\"nebula\")\n"
        backendWritten (writeFixture! (str fixtureRoot "/scripts/agentLoop/backend.py") backendSource)
        gatewayWritten (writeFixture! (str fixtureRoot "/bin/asl-gateway") gatewaySource)


        loopWritten (writeFixture! (str fixtureRoot "/scripts/agentLoop/loop.py") (loopSource))
        effectsWritten (writeFixture! (str fixtureRoot "/scripts/agentLoop/effects.asn") "(:effects (:entries ((:effect :op \"read\" :class :local) (:effect :op \"manage\" :class :local) (:effect :op \"customOnly\" :class :local) (:effect :op \"ignoredRemote\" :class :needsConfirm))))")
        mainWritten (writeFixture! (str fixtureRoot "/asl/agentLoop/main.asl") (mainSource))
        fixtureCard (cardText (card/buildCard fixtureRoot))
        cardDataResult (card/buildCard fixtureRoot)
        fallbackGatewayWritten (writeFixture! (str fixtureRoot "/bin/asl-gateway") "os.environ.get('AGY_CONCURRENCY', 17)\n")
        fallbackGatewayCard (cardText (card/buildCard fixtureRoot))
        missingReadFailed (cardFails! (str fixtureRoot "/missing"))
        gatewayRemoved (pathRemove (str fixtureRoot "/bin/asl-gateway"))
        gatewayReadFailed (cardFails! fixtureRoot)
        gatewayRestored (writeFixture! (str fixtureRoot "/bin/asl-gateway") gatewaySource)
        backendRemoved (pathRemove (str fixtureRoot "/scripts/agentLoop/backend.py"))
        backendReadFailed (cardFails! fixtureRoot)
        backendRestored (writeFixture! (str fixtureRoot "/scripts/agentLoop/backend.py") backendSource)
        loopRemoved (pathRemove (str fixtureRoot "/scripts/agentLoop/loop.py"))
        loopReadFailed (cardFails! fixtureRoot)
        loopRestored (writeFixture! (str fixtureRoot "/scripts/agentLoop/loop.py") (loopSource))
        effectsRemoved (pathRemove (str fixtureRoot "/scripts/agentLoop/effects.asn"))
        effectsReadFailed (cardFails! fixtureRoot)
        effectsRestored (writeFixture! (str fixtureRoot "/scripts/agentLoop/effects.asn") "(:effects (:entries ((:effect :op \"read\" :class :local) (:effect :op \"manage\" :class :local) (:effect :op \"customOnly\" :class :local) (:effect :op \"ignoredRemote\" :class :needsConfirm))))")
        mainRemoved (pathRemove (str fixtureRoot "/asl/agentLoop/main.asl"))
        mainReadFailed (cardFails! fixtureRoot)
        noFormatWritten (writeFixture! (str fixtureRoot "/asl/agentLoop/main.asl") "fn formatDryRun -> String\n  \"(:agentReceipt :status :ok)\"\n")
        noFormatFailed (cardFails! fixtureRoot)
        mainRestored (writeFixture! (str fixtureRoot "/asl/agentLoop/main.asl") (mainSource))
        noShapeWritten (writeFixture! (str fixtureRoot "/scripts/agentLoop/loop.py") "DELIVERABLES = (\"patch\", \"findings\")\n")
        noShapeCard (cardText (card/buildCard fixtureRoot))
        emptyEffectsWritten (writeFixture! (str fixtureRoot "/scripts/agentLoop/effects.asn") "(:effects (:entries ()))")
        emptyEffectsCard (cardText (card/buildCard fixtureRoot))
        unsupportedBackendWritten (writeFixture! (str fixtureRoot "/scripts/agentLoop/backend.py") "backend selected dynamically\n")
        unsupportedBackendCard (cardText (card/buildCard fixtureRoot))
        aslCard fixtureCard
        removed (pathRemove fixtureRoot)]
    (do
      (assert (= dirs.exitCode 0) "fixture directories created")
      (assert backendWritten "fixture backend source written")
      (assert fallbackGatewayWritten "fallback-only gateway source written")
      (assert (stringContains? fallbackGatewayCard "(:pool \"agy\" :size 17)") "gateway concurrency fallback derives pool name and default")
      (assert missingReadFailed "missing card sources are returned as an error")
      (assert (and (ok? gatewayRemoved) (and gatewayReadFailed (and gatewayRestored (and (ok? backendRemoved) (and (not backendReadFailed) backendRestored))))) "gateway is read from workspace while backend source is no longer a dependency")
      (assert (and (ok? loopRemoved) (and (not loopReadFailed) (and loopRestored (and (ok? effectsRemoved) (and effectsReadFailed effectsRestored))))) "retired Python loop is not read while effects remain required")
      (assert gatewayWritten "fixture gateway source written")
      (assert emptyEffectsWritten "empty source written")
      (assert unsupportedBackendWritten "unsupported backend source written")
      (assert (and (stringContains? unsupportedBackendCard ":deliverables (:findings :patch :plan :verdict)") (not (stringContains? unsupportedBackendCard ":deliverables (:patch :findings)"))) "deliverables come from current ASL loop, not retired Python fixture")
      (assert (and (stringContains? unsupportedBackendCard "(:backend \"codex\")") (stringContains? unsupportedBackendCard "(:backend \"claude\")")) "backend names come from the current ASL supportedBackends list")
      (assert (stringContains? unsupportedBackendCard "(:backend \"script\")") "script provider prefix remains exported without a Python source")
      (assert (stringContains? emptyEffectsCard ":allowlist ()") "empty source has empty derived allowlist")
      (assert loopWritten "deliverable source written")
      (assert effectsWritten "fixture effects source written")
      (assert mainWritten "fixture main source written")
      (assert (stringContains? fixtureCard "  :receiptFields (\"status\" \"fixtureField\" \"gates\" \"journal\")") "receipt fields derive from the fixture formatReceipt source")
      (assert (stringContains? fixtureCard "  :escalateForm \"(:escalate :reason s)\"") "escalate shape comes from the current ASL exec source, not the Python fixture")
      (assert (and (ok? mainRemoved) mainReadFailed) "a missing asl/agentLoop/main.asl is an error")
      (assert (and noFormatWritten noFormatFailed mainRestored) "a main source without fn formatReceipt is an error")
      (assert (and noShapeWritten (stringContains? noShapeCard "  :escalateForm \"(:escalate :reason s)\"")) "escalate shape comes from current ASL exec defaults, not the retired Python loop")
      (assert (stringContains? fixtureCard "customOnly") "allowlist derives custom local effect from source")
      (assert (not (stringContains? fixtureCard "ignoredRemote")) "allowlist excludes outward effects")
      (assert (stringContains? fixtureCard "(:backend \"agy\" :defaultModel \"gemini-3.8-flash\")") "backend model derives from the current ASL backend source")
      (assert (stringContains? fixtureCard "(:pool \"nebula\" :size 17)") "gateway pool derives from fixture source")
      (assert (and (stringContains? fixtureCard "(:backend \"codex\")") (not (stringContains? fixtureCard "(:backend \"nova\")"))) "supported backend rows reflect the ASL backend list, not the Python fixture")
      (assert (not (stringContains? fixtureCard "(:backend \"mock\")")) "unsupported Python test backend does not leak into the ASL backend list")
      (assert (stringContains? fixtureCard "(:backend \"script\")") "script provider prefix derives from ASL provider definitions")
      (assert (stringContains? fixtureCard "(:backend \"replay\")") "replay provider prefix derives from ASL provider definitions")
      (assert (ok? removed) "fixture directory removed after use")
      (assert (and (stringContains? aslCard ":deliverables (:findings :patch :plan :verdict)") (and (stringContains? aslCard ":backend \"codex\"") (stringContains? aslCard ":backend \"claude\""))) "card output carries ASL deliverables and supported backends")
      (assert (stringContains? aslCard "(:backend \"script\")") "script provider prefix is exported as a card backend")
      (assert (stringContains? aslCard "(:backend \"replay\")") "replay provider prefix is exported as a card backend")
      (assert (mt cardDataResult
        ((ok cardData) (and (= cardData.name "Leon") (and (listContains? cardData.deliverables "patch") (and (listContains? cardData.deliverables "findings") (and (listContains? cardData.allowlist "read") (and (listContains? cardData.allowlist "manage") (and (listContains? cardData.receiptFields "status") (listContains? cardData.receiptFields "journal"))))))))
        ((err _) false)) "card core fields derive from loaded sources")
      true))
