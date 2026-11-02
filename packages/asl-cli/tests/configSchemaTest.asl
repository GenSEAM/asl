(module asl-cli/tests/configSchemaTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/configSchema :a cs)])

; (:m :ref WS-CONFIG-SCHEMA :do "gate for asl/grammar/workspaceConfig.asn and cs: a config using every key at a sound value is clean, the repo's own .asl.config.asn is clean, and an unknown key, a wrong type, an out-of-range value, a duplicate key and unbalanced delimiters are each an error naming the key; a group the schema does not name is left alone; the CLI path reports exit 1 on an error file")

fn ! schemaRules -> (List cs/Rule)
  (cs/rulesOf (resultOr (fileReadString "asl/grammar/workspaceConfig.asn") ""))

fn codesOf c: cs/Checked -> (List String)
  (map (fn [(i cs/Issue)] -> String i.code) c.issues)

fn ! checkOf text: String -> cs/Checked
  (cs/checkText text (schemaRules))

fn validText -> String
  (stringJoin (list
    ";; a comment line outside any form"
    "(:aslConfig :workspace \"w\" :build (:anything 1 :goes (2 3))"
    "  ; another comment"
    "  :native (:parts 8 :level :dev :rc :notrace :clang \"/usr/bin/clang\" :llc \"/usr/bin/llc\" :opt \"/usr/bin/opt\" :wasmLd \"/usr/bin/wasm-ld\" :llvmNm \"/usr/bin/llvm-nm\" :node \"/usr/bin/node\" :storeCap 2G :storeMinAge 60m :sweep false :claimWaitS 900 :lockGraceS 10 :buildPool \"/tmp/pool\" :buildTokens 2)"
    "  :fleet (:drainBytes 1048576 :drainMs 300)"
    "  :nativeCli (:buildWaitS 3600 :coldStallS 300 :formsPin true :relayPin true :relayPaths [\"tools/remote\" \"asl/tools/fleet\"])"
    "  :deploy (:warmS 900 :warmNice 10 :warmEntries [\"asl/agentLoop/leonServe.asl\"])"
    "  :leonPool (:ctlProbeRetries 5 :ctlProbeDelayMs 100)"
    "  :agentLoop (:parseDefectEscalate 8 :readOutlineBytes 16384 :baseline true :specCheck false :toolMemo false :graderIntent grade :graderProfile \"p\" :gatewayConfig \"/tmp/g.asn\" :wallReserveSec 120 :wallGateMinSec 60 :gateVacuousRounds 2 :gateMaxDescendants 512 :contextKeepTurns 8 :contextToolCapBytes 1500 :contextMaxOlderLines 50 :readStreakNudge 6 :readStreakEscalate 12 :doc \"d\")"
    "  :remoteJobs (:claimSweepS 300)"
    "  :release (:pin \"0.0.2\" :min \"0.0.1\" :mode :warn))"
    "") "\n")

fn ! testValid -> Bool
  (let [(rules (schemaRules))
        (c (checkOf (validText)))]
    (do (assert (>= (cs/keyCount rules) 20) (str "the schema holds at least the 20 key rows this test uses, got " (stringFromInt64 (cs/keyCount rules))))
        (assert (listEmpty? c.issues) (str "a config using every key at a sound value is clean: " (stringJoin (codesOf c) " ")))
        (assert (= c.checked (cs/keyCount rules)) (str "every key of the strict groups was checked, got " (stringFromInt64 c.checked)))
        (assert (= (cs/defaultOf rules "native" "storeCap") (some "2G")) "a key's documented default is readable from its row")
        (assert (= (cs/defaultOf rules "native" "nope") (none)) "an unknown key has no default")
        (let [(repo (checkOf (resultOr (fileReadString ".asl.config.asn") "")))]
          (assert (listEmpty? repo.issues) (str "the repo's own .asl.config.asn passes: " (stringJoin (codesOf repo) " "))))
        true))

fn ! testUnknown -> Bool
  (let [(c (checkOf "(:aslConfig :native (:partz 4 :parts 4) :nativeCli (:buildWait 5) :release (:pinn \"1.0\"))"))]
    (do (assert (= (listLength c.issues) 3) (str "three unknown keys give three errors, got " (stringFromInt64 (listLength c.issues))))
        (assert (= (listLength (filter (fn [(k String)] -> Bool (= k "unknownKey")) (codesOf c))) 3) (str "each is an unknownKey: " (stringJoin (codesOf c) " ")))
        (assert (stringContains? (cs/receipt "f" c) ":partz") "the receipt names the unknown key")
        (assert (stringContains? (cs/receipt "f" c) ":status :error") "the receipt status is error")
        (let [(good (checkOf "(:aslConfig :native (:parts 4))"))]
          (assert (stringContains? (cs/receipt "f" good) ":status :ok") "a sound file has status ok"))
        true))

fn ! testRange -> Bool
  (let [(hi (checkOf "(:aslConfig :native (:parts 65))"))
        (lo (checkOf "(:aslConfig :native (:parts 0))"))
        (edge (checkOf "(:aslConfig :native (:parts 1) :nativeCli (:buildWaitS 604800))"))
        (word (checkOf "(:aslConfig :native (:parts many))"))
        (level (checkOf "(:aslConfig :native (:level :fast))"))
        (wait (checkOf "(:aslConfig :nativeCli (:buildWaitS 0))"))
        (cap (checkOf "(:aslConfig :native (:storeCap 0))"))
        (age (checkOf "(:aslConfig :native (:storeMinAge 5d))"))
        (flag (checkOf "(:aslConfig :native (:sweep maybe))"))
        (formsTypo (checkOf "(:aslConfig :nativeCli (:formsPin ture))"))
        (pin (checkOf "(:aslConfig :release (:pin \"v1\"))"))
        (mode (checkOf "(:aslConfig :release (:mode :explode))"))
        (paths (checkOf "(:aslConfig :nativeCli (:relayPaths \"tools\"))"))
        (path (checkOf "(:aslConfig :native (:clang \"\"))"))
        (turns (checkOf "(:aslConfig :agentLoop (:contextKeepTurns many))"))
        (rounds (checkOf "(:aslConfig :agentLoop (:gateVacuousRounds 0))"))
        (typo (checkOf "(:aslConfig :agentLoop (:contextKeepTurn 3))"))]
    (do (assert (= (codesOf hi) (list "outOfRange")) (str "parts 65 is outOfRange: " (stringJoin (codesOf hi) " ")))
        (assert (stringContains? (cs/receipt "f" hi) "1..64") "the message names the range")
        (assert (= (codesOf lo) (list "outOfRange")) "parts 0 is outOfRange")
        (assert (listEmpty? edge.issues) "the range ends 1 and 604800 are accepted")
        (assert (= (codesOf word) (list "badType")) "parts many is badType")
        (assert (= (codesOf level) (list "outOfRange")) "level :fast is outOfRange")
        (assert (= (codesOf wait) (list "outOfRange")) "buildWaitS 0 is outOfRange")
        (assert (= (codesOf cap) (list "outOfRange")) "storeCap 0 is outOfRange")
        (assert (= (codesOf age) (list "outOfRange")) "storeMinAge 5d is outOfRange")
        (assert (= (codesOf flag) (list "badType")) "sweep maybe is badType")
        (assert (= (codesOf formsTypo) (list "badType")) "formsPin ture is badType")
        (assert (= (codesOf pin) (list "badType")) "pin v1 is badType")
        (assert (= (codesOf mode) (list "outOfRange")) "mode :explode is outOfRange")
        (assert (= (codesOf paths) (list "badType")) "relayPaths as a bare string is badType")
        (assert (= (codesOf path) (list "badType")) "an empty clang path is badType")
        (assert (= (codesOf turns) (list "badType")) (str ":agentLoop contextKeepTurns many is badType: " (stringJoin (codesOf turns) " ")))
        (assert (= (codesOf rounds) (list "outOfRange")) (str ":agentLoop gateVacuousRounds 0 is outOfRange: " (stringJoin (codesOf rounds) " ")))
        (assert (= (codesOf typo) (list "unknownKey")) (str ":agentLoop is closed: a misspelt key is unknownKey: " (stringJoin (codesOf typo) " ")))
        true))

fn ! testShape -> Bool
  (let [(dup (checkOf "(:aslConfig :native (:parts 4 :parts 5))"))
        (open (checkOf "(:aslConfig :native (:parts 4)"))
        (str1 (checkOf "(:aslConfig :native (:clang \"a)b\"))"))
        (atom (checkOf "(:aslConfig :native 4)"))
        (none1 (checkOf ""))
        (other (checkOf "(:aslConfig :daemon (:whatever 1) :mesh (:x y))"))]
    (do (assert (= (codesOf dup) (list "duplicateKey")) "a key twice in a group is duplicateKey")
        (assert (= (codesOf open) (list "unbalanced")) "a missing close delimiter is unbalanced")
        (assert (listEmpty? str1.issues) "a delimiter inside a string does not unbalance")
        (assert (= (codesOf atom) (list "badType")) "a strict group that is not a list is badType")
        (assert (= (codesOf none1) (list "empty")) "an empty file is empty")
        (assert (listEmpty? other.issues) "a group the schema does not name is not checked")
        true))

fn ! removeAll! path: String -> (Result Unit String)
  (if (sys/isFile? path) (pathRemove path)
    (do (map (fn [(n String)] -> (Result Unit String) (removeAll! (str path "/" n))) (resultOr (dirList path) (list)))
        (pathRemove path)))

fn ! testFile -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/configSchemaTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate work))
        (bad (str work "/bad.asn"))
        (good (str work "/good.asn"))
        (_ (fileWrite bad "(:aslConfig :native (:parts 99))\n"))
        (_ (fileWrite good (validText)))
        (schema (str root "/asl/grammar/workspaceConfig.asn"))
        (badRun (cs/cli! (list "check" bad schema)))
        (goodRun (cs/cli! (list "check" good schema)))
        (missing (cs/cli! (list "check" (str work "/absent.asn") schema)))
        (usage (cs/cli! (list "check")))
        (noSchema (cs/checkFile! good (str work "/absent.schema")))
        (lines (cs/warnLines! root "f.asn" "(:aslConfig :native (:parts 99 :zz 1))"))
        (quiet (cs/warnLines! root "f.asn" (validText)))
        (noRoot (cs/warnLines! work "f.asn" "(:aslConfig :native (:parts 99))"))
        (gone (removeAll! work))]
    (do (assert (= badRun (ok 1)) (str "an out-of-range file exits 1: " (stringFromInt64 (resultOr badRun -9))))
        (assert (= goodRun (ok 0)) "a sound file exits 0")
        (assert (not (ok? missing)) "an unreadable config is an error")
        (assert (not (ok? usage)) "no file is a usage error")
        (assert (not (ok? noSchema)) "an unreadable schema is an error")
        (assert (= (listLength lines) 2) (str "warnLines gives one line per error: " (stringJoin lines " | ")))
        (assert (stringContains? (optionOr (listHead lines) "") "f.asn :native :parts") "a warning names the file and the key")
        (assert (listEmpty? quiet) "a sound config warns nothing")
        (assert (listEmpty? noRoot) "a root without the schema warns nothing")
        (assert (ok? gone) "the work directory is removed")
        true))

fn ! runTests -> Bool
  (do (testValid) (testUnknown) (testRange) (testShape) (testFile) true)
