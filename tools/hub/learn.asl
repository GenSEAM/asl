(module asl-tools/hub/learn
  :x [specsOf totalsOf tailLines learnTick! main]
  :i [(asl-tools/fleet/run :a fr) (aslGateway/config :a c) (aslGateway/rateLearn :a rl)])

; (:m :ref ORCH-AIMD-LIVE :do "the live half of GW-RPM-AIMD: every :every-sec the loop reads the gateway config for each alias's configured :rpm (the start) and the provider :rpmTotal of shared providers, replays the last window of the usage ledger through rateLearn/learnAll, and rewrites the rate store; it exits when --parent is gone, so a hub restart never leaves a learner behind")
fn specsOf table: c/GatewayTable -> (List rl/Spec)
  (listFlatMap (fn [(id String)] -> (List rl/Spec)
                 (match (mapGet table.models id)
                   ((none) (list))
                   ((some m)
                     (match m.params.rpm
                       ((some r) (if (> r 0.0) (list (rl/Spec :alias id :provider m.provider :start r :max 0.0)) (list)))
                       ((none) (list))))))
    table.modelOrder)

fn totalsOf table: c/GatewayTable -> (Map String Float64)
  (mapFromPairs
    (listFlatMap (fn [(p (Pair String c/GatewayProvider))] -> (List (Pair String Float64))
                   (let [(prov (pairSecond p))]
                     (if (and prov.rpmShared (> prov.rpm 0.0)) (list (pair (pairFirst p) prov.rpm)) (list))))
      (mapPairs table.providers)))

; (:m :ref ORCH-AIMD-LIVE :do "the ledger only grows and its rows are time ordered, so one tick reads the last tailBytes of it through tail -c (no byte-to-string builtin lowers), not the whole file; the cut first line is dropped, and a window older than the tail counts only the part inside it")
fn tailBytes -> Int64
  4194304

fn ! tailLines path: String maxBytes: Int64 -> (List String)
  (let [(size (resultOr (fileSize path) 0))
        (text (if (or (<= size 0) (stringContains? path "'")) ""
                (resultOr (fr/shellOut (str "/usr/bin/tail -c " (stringFromInt64 maxBytes) " '" path "'") 20000) "")))]
    (if (> size maxBytes) (listDrop (stringSplit text "\n") 1) (stringSplit text "\n")))

; (:m :ref ORCH-AIMD-LIVE :do "the gateway's bucket key is the upstream model name, not the alias: the learner also writes the learned rates by that name, the lowest of the aliases sharing one name, next to the alias store, so the reactor reads a small file with no config parse")
fn byNamePath storePath: String -> String
  (let [(parts (stringSplit storePath "/"))]
    (str (stringJoin (listTake parts (- (listLength parts) 1)) "/") "/ratesByName.asn"))

fn byNameRates table: c/GatewayTable learned: (Map String Float64) -> (Map String Float64)
  (fold (fn [(acc (Map String Float64)) (id String)] -> (Map String Float64)
              (match (mapGet learned id)
                ((none) acc)
                ((some r)
                  (match (mapGet table.models id)
                    ((none) acc)
                    ((some m) (mapSet acc m.name (match (mapGet acc m.name) ((some old) (min old r)) ((none) r))))))))
    (mapEmpty) table.modelOrder)

fn ! writeByName! table: c/GatewayTable learned: (Map String Float64) path: String -> Bool
  (ok? (rl/writeStore! path (byNameRates table learned)))

fn ! learnTick! gatewayPath: String ledgerPath: String storePath: String nowMs: Int64 windowMs: Int64 -> (Result Int64 String)
  (match (fileReadString gatewayPath)
    ((err e) (err (str "ERR_HUB_LEARN_CONFIG: " e)))
    ((ok text)
      (match (c/gateway_config_parse! text "default" "")
        ((err e) (err (str "ERR_HUB_LEARN_CONFIG: " e)))
        ((ok table)
          (let [(lines (tailLines ledgerPath (tailBytes)))
                (learned (rl/learnAll (specsOf table) (rl/readStore! storePath) lines (- nowMs windowMs) nowMs (totalsOf table)))]
            (match (rl/writeStore! storePath learned)
              ((err e) (err (str "ERR_HUB_LEARN_STORE: " e)))
              ((ok _) (do (writeByName! table learned (byNamePath storePath)) (ok (mapSize learned))))))))))

fn flagAfter args: (List String) flag: String fallback: String -> String
  (match (listIndexOf args flag)
    ((none) fallback)
    ((some i) (optionOr (listGet args (+ i 1)) fallback)))

fn parentGone? parent: Int64 -> Bool
  (and (> parent 0) (match (procAlive? parent) ((ok alive) (not alive)) ((err _) true)))

fn ! loop! gatewayPath: String ledgerPath: String storePath: String everySec: Int64 windowSec: Int64 parent: Int64 -> (Result Int64 String)
  (if (and (> parent 0) (parentGone? parent)) (ok 0)
    (do (learnTick! gatewayPath ledgerPath storePath (/ (nowNs) 1000000) (* windowSec 1000))
      (sleepWhile! everySec parent)
      (loop! gatewayPath ledgerPath storePath everySec windowSec parent)))

fn ! sleepWhile! secs: Int64 parent: Int64 -> Bool
  (if (or (<= secs 0) (and (> parent 0) (parentGone? parent))) true
    (do (sleepMs 1000) (sleepWhile! (- secs 1) parent)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") ""))
        (gateway (flagAfter args "--gateway" (str home "/.asl/gateway.asn")))
        (ledger (flagAfter args "--ledger" (str home "/.asl/run/usage/gatewayCalls.asn")))
        (store (flagAfter args "--store" (str home "/.asl/run/hub/rates.asn")))
        (every (optionOr (stringToInt64 (flagAfter args "--every-sec" "600")) 600))
        (window (optionOr (stringToInt64 (flagAfter args "--window-sec" "")) every))
        (parent (optionOr (stringToInt64 (flagAfter args "--parent" "0")) 0))]
    (if (listContains? args "--once")
      (match (learnTick! gateway ledger store (optionOr (stringToInt64 (flagAfter args "--now" "")) (/ (nowNs) 1000000)) (* window 1000))
        ((err e) (err e))
        ((ok _) (ok 0)))
      (loop! gateway ledger store every window parent)))
