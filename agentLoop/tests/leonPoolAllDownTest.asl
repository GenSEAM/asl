(module asl/agentLoop/tests/leonPoolAllDownTest
  :x [runTests]
  :i [(asl/agentLoop/leonPool :a lp) (asl/agentLoop/sessionPool :a sp) (asl/agentLoop/providers :a pv) (asl-tools/fleet/run :a fr)])

; (:m :ref LEON-TURN-ALLDOWN-WAIT :do "the pool's downFits branch of decide!: a Live whose quick retries are spent (retries 3) and whose gateway answer is 502 no model answered holds the ask allDownPauseSec seconds as Turn.holdMs and asks again in the same session with waited advanced; with waited at allDownWaitSec the pause no longer fits and the answer is applied, ending the ask")

fn ! sh! cmd: String -> Bool
  (ok? (fr/shellOut cmd 20000))

fn allDownReply -> String
  (let [(body "{\"error\":\"profile freeWriter: no model answered (a, b)\"}")]
    (str "HTTP/1.1 502 Bad Gateway\r\nContent-Type: application/json\r\nContent-Length: " (stringFromInt64 (stringLength body)) "\r\nConnection: close\r\n\r\n" body))

fn envFor root: String -> pv/ProviderEnv
  (pv/ProviderEnv :gatewayUrl "http://127.0.0.1:1/v1/chat/completions" :inProcess false :profile "" :gatewayConfig (str root "/.asl/gateway.asn")
    :tmpDir (str root "/tmp") :childEnv (mapEmpty))

fn ! prepRoot! root: String -> Bool
  (and (sh! (str "/bin/mkdir -p " root "/.asl " root "/tmp"))
    (and (ok? (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false :allDownPauseSec 7 :allDownWaitSec 20))\n"))
      (and (ok? (fileWrite (str root "/.asl/hub.asn") (str "(:hub :sock \"" root "/never.sock\" :class \"lead\")\n")))
        (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
          (sh! (str "cd " root " && git init -q -b main && git config user.name leonPool && git config user.email leon-pool@example.invalid && git add -- subject.txt && git commit -q -m initial"))))))

fn form -> String
  "(:agent :task \"write then gate\" :backend \"agy\" :mode \"implement\" :owns (\"subject.txt\") :gates (\"grep -qx green subject.txt\") :nativeTools \"off\")"

fn withLive book: (List (Pair String lp/Live)) f: (fn [lp/Live] -> lp/Live) -> (List (Pair String lp/Live))
  (map (fn [(e (Pair String lp/Live))] -> (Pair String lp/Live) (pair (pairFirst e) (f (pairSecond e)))) book)

fn waitedOf book: (List (Pair String lp/Live)) -> Int64
  (fold (fn [(acc Int64) (e (Pair String lp/Live))] -> Int64 (+ acc (pairSecond e).waited)) 0 book)

fn askOpen? book: (List (Pair String lp/Live)) -> Bool
  (listAny? (fn [(e (Pair String lp/Live))] -> Bool (some? (pairSecond e).ask)) book)

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/leonPoolAllDownTest.XXXXXX" 5000) "")))
        (repoRoot (resultOr (realPath ".") "."))
        (root (str temp "/r0"))
        (prepared (prepRoot! root))
        (opened (lp/leonOpen! (list) "r0" (form) repoRoot root (envFor root)))
        (first (lp/leonTurn! (pairFirst opened) "r0" ""))
        (spent (withLive (pairFirst first) (fn [(l lp/Live)] -> lp/Live (with l :retries 3))))
        (held (lp/leonTurn! spent "r0" (allDownReply)))
        (full (withLive (pairFirst held) (fn [(l lp/Live)] -> lp/Live (with l :retries 3 :waited 20))))
        (settledTurn (lp/leonTurn! full "r0" (allDownReply)))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert prepared "root prepared")
      (assert (none? (pairSecond opened)) "the run opened")
      (assert (askOpen? (pairFirst first)) "the first turn left an ask outstanding")
      (assert (= (pairSecond held).holdMs 7000) (str "an all-down answer with quick retries spent holds allDownPauseSec: " (stringFromInt64 (pairSecond held).holdMs)))
      (assert (some? (pairSecond held).request) "the held ask is asked again in the same session")
      (assert (= (waitedOf (pairFirst held)) 7) "waited advanced by the pause")
      (assert (none? (pairSecond settledTurn).request) "with waited at the budget no new ask is made")
      (assert (not (askOpen? (pairFirst settledTurn))) "the ask is settled when the pause no longer fits")
      (assert removed "temp dir removed")
      true))
