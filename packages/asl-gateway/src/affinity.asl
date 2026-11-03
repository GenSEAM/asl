(module aslGateway/affinity
  :x [AffinityConfig AffinityRecord affinityDefault affinityConfigFromText affinityAnswer affinityNote]
  :i [(aslGateway/config :a c)])

; (:m :ref GW-SESSION-AFFINITY :do "a session (X-ASL-Session, else body session) keeps the chain member that last answered it while it keeps answering: the cache prefix stays warm and reasoning formats never mix; config rows (:gateway ... :affinity true|false :affinityStickSec S :affinityForgetSec S :affinitySwitch dropReasoning|keep) with defaults true, 1800, 86400, dropReasoning")
(schema AffinityConfig
  (:f on Bool)
  (:f stickSec Int64)
  (:f forgetSec Int64)
  (:f dropOnSwitch Bool))

(schema AffinityRecord
  (:f alias String)
  (:f atMs Int64))

fn affinityDefault -> AffinityConfig
  (AffinityConfig :on true :stickSec 1800 :forgetSec 86400 :dropOnSwitch true)

fn affinityConfigFromText text: String -> AffinityConfig
  (let [(d (affinityDefault))
        (on (match (c/gatewayTopScalarOverride text "affinity") ((some (c/scalarBool b)) b) (_ d.on)))
        (stick (optionOr (c/gatewayTopIntOverride text "affinityStickSec") d.stickSec))
        (forget (optionOr (c/gatewayTopIntOverride text "affinityForgetSec") d.forgetSec))
        (drop (match (c/gatewayTopScalarOverride text "affinitySwitch") ((some (c/scalarStr s)) (!= s "keep")) (_ d.dropOnSwitch)))]
    (AffinityConfig :on on :stickSec (max 1 stick) :forgetSec (max stick forget) :dropOnSwitch drop))

; (:m :ref GW-SESSION-AFFINITY :do "the answer to one session's affinity ask: empty when affinity is off, the key is empty or the record is older than :affinityForgetSec, else (alias stick drop) where stick is 1 while the last answer is under :affinityStickSec old and drop is 1 when a switch drops prior reasoning")
fn affinityAnswer cfg: AffinityConfig st: (Map String AffinityRecord) session: String nowMs: Int64 -> (List String)
  (if (or (not cfg.on) (stringEmpty? session))
    (list)
    (match (mapGet st session)
      ((none) (list))
      ((some r)
        (let [(age (- nowMs r.atMs))]
          (if (> age (* cfg.forgetSec 1000))
            (list)
            (list r.alias (if (<= age (* cfg.stickSec 1000)) "1" "0") (if cfg.dropOnSwitch "1" "0")))))))

; (:m :ref GW-SESSION-AFFINITY :do "records the member that answered a session and forgets every record older than :affinityForgetSec, so the table holds only live sessions")
fn affinityNote cfg: AffinityConfig st: (Map String AffinityRecord) session: String alias: String nowMs: Int64 -> (Map String AffinityRecord)
  (if (or (not cfg.on) (or (stringEmpty? session) (stringEmpty? alias)))
    st
    (let [(limitMs (* cfg.forgetSec 1000))
          (live (fold (fn [(acc (Map String AffinityRecord)) (k String)] -> (Map String AffinityRecord)
                        (match (mapGet st k)
                          ((some r) (if (> (- nowMs r.atMs) limitMs) (mapRemove acc k) acc))
                          ((none) acc)))
                  st (mapKeys st)))]
      (mapSet live session (AffinityRecord :alias alias :atMs nowMs))))
