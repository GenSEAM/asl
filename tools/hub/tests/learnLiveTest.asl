(module asl-tools/hub/tests/learnLiveTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (aslGateway/rateLearn :a rl) (asl-tools/hub/learn :a ln)])

; (:m :ref ORCH-AIMD-LIVE :do "the hub's learner process on scratch files: one tick over a throttled-only window raises the alias rpm by 20 percent of its start (20 to 24), a window with 3.2 percent real 429 cuts it by 0.7, and the looping timer, started with no stored rate, writes the store by itself within its first interval")
fn row at: Int64 outcome: String -> String
  (str "(:call :at " (stringFromInt64 at) " :profile \"\" :intent \"code\" :alias \"m1\" :provider \"stubProv\" :model \"m\" :in 1 :cached 0 :out 1 :reasoning 0 :ttftMs absent :ms 5 :outcome \"" outcome "\" :charge 0)")

fn rows at: Int64 n: Int64 outcome: String -> (List String)
  (map (fn [(i Int64)] -> String (row (+ at i) outcome)) (range 0 n))

fn near a: Float64 b: Float64 -> Bool
  (< (abs (- a b)) 0.001)

fn gatewayText -> String
  "(:gateway :v 2 :providers ((:provider :id stubProv :kind openai :base \"http://127.0.0.1:1/v1\")) :models ((:model :id m1 :provider stubProv :name \"m1-target\" :rpm 20)) :profiles ((:profile :id default :routes ((:intent any :chain (m1))))) :uses ((:use :for default :profile default)))\n"

fn cacheRow -> String
  (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli")))

fn ! learnCmd temp: String extra: String -> String
  (str "/usr/bin/env " (cacheRow) " " (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")) " run "
       (resultOr (realPath "asl/tools/hub/learn.asl") "") " --gateway " temp "/gateway.asn --ledger " temp "/ledger.asn --store " temp "/rates.asn " extra)

fn ! tickOut! temp: String -> String
  (match (fr/shellOut (str "(" (learnCmd temp "--once --now 10000000 --window-sec 600") " 2>&1; echo EXIT:$?)") 600000)
    ((ok o) o)
    ((err e) e))

fn ! rateOf! temp: String -> Float64
  (mapGetOr (rl/readStore! (str temp "/rates.asn")) "m1" -1.0)

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/learnLiveTest.XXXXXX" 5000) "")))
        (wroteG (fileWrite (str temp "/gateway.asn") (gatewayText)))
        (wroteL1 (fileWrite (str temp "/ledger.asn") (stringJoin (rows 9999000 10 "throttled") "\n")))
        (t1 (tickOut! temp))
        (up (rateOf! temp))
        (byNameText (resultOr (fileReadString (str temp "/ratesByName.asn")) ""))
        (byName (mapGetOr (rl/readStore! (str temp "/ratesByName.asn")) "m1-target" -1.0))
        (tailFile (fileWrite (str temp "/tail.txt") "aaaa\nbbbb\ncccc\n"))
        (tailCut (ln/tailLines (str temp "/tail.txt") 7))
        (tailAll (ln/tailLines (str temp "/tail.txt") 100))
        (wroteL2 (fileWrite (str temp "/ledger.asn") (stringJoin (listAppend (rows 9999000 30 "ok") (rows 9999100 1 "429")) "\n")))
        (t2 (tickOut! temp))
        (down (rateOf! temp))
        (fresh (pathRemove (str temp "/rates.asn")))
        (nowMs (/ (monotonicNs) 1000000))
        (epochMs (/ (nowNs) 1000000))
        (wroteL3 (fileWrite (str temp "/ledger.asn") (stringJoin (rows (- epochMs 500) 10 "throttled") "\n")))
        (running (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " (learnCmd temp "--every-sec 1 --window-sec 3600") " 1>" temp "/learn.out 2>" temp "/learn.err")) (resultOr (realPath ".") ".") (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" (optionOr (envGet "HOME") "/tmp"))))))
        (pid (match running ((ok r) r.pid) ((err _) 0)))
        (stored (waitStore! (str temp "/rates.asn") 3000))
        (timed (rateOf! temp))
        (killed (if (> pid 0) (do (fr/killTree! pid) true) false))
        (pipes (match running ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)))
        (home2 (str temp "/h2"))
        (made2 (fr/shellOut (str "/bin/mkdir -p " home2 "/.asl/run/usage") 5000))
        (hubAsn (fileWrite (str home2 "/.asl/hub.asn") (str "(:hub :sock \"" home2 "/hub.sock\" :learnEverySec 1 :learnWindowSec 3600)\n")))
        (hubGw (fileWrite (str home2 "/.asl/gateway.asn") (gatewayText)))
        (hubLedger (fileWrite (str home2 "/.asl/run/usage/gatewayCalls.asn") (stringJoin (rows (- epochMs 500) 10 "throttled") "\n")))
        (hubRun (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")) " run "
                                                        (resultOr (realPath "asl/tools/hub/main.asl") "") " serve 1>" temp "/hub.out 2>" temp "/hub.err"))
                               (resultOr (realPath ".") ".")
                               (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" home2) (cacheRow)))))
        (hubPid (match hubRun ((ok r) r.pid) ((err _) 0)))
        (hubStored (waitStore! (str home2 "/.asl/run/hub/rates.asn") 12000))
        (hubRate (mapGetOr (rl/readStore! (str home2 "/.asl/run/hub/rates.asn")) "m1" -1.0))
        (hubKilled (if (> hubPid 0) (do (fr/killTree! hubPid) true) false))
        (hubPipes (match hubRun ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)))
        (hubLog (str (resultOr (fileReadString (str temp "/hub.err")) "") "|" (resultOr (fileReadString (str home2 "/.asl/run/hub/learn.log")) "") "|" (resultOr (fileReadString (str temp "/hub.out")) "")))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and (ok? wroteG) (and (ok? wroteL1) (stringContains? t1 "EXIT:0"))) (str "one learner tick ran: " t1))
      (assert (near up 24.0) (str "a throttled-only window raises 20 by 20 percent of its start: " (stringFromFloat64 up)))
      (assert (near byName 24.0) (str "the learner also writes the learned rate by upstream model name: " (stringFromFloat64 byName)))
      (assert (stringContains? byNameText ":cfg 20.0") (str "the by-name row carries the configured rpm: " byNameText))
      (assert (and (ok? tailFile) (and (= tailCut (list "cccc" "")) (= (listLength tailAll) 4))) "tailLines drops the cut first line only when it cut, and reads all of a small file")
      (assert (not (stringContains? (resultOr (fileReadString "asl/tools/hub/learn.asl") "") "shellOut")) "the ledger tail is read in-process (fileReadRange, bytesToString), not through a shell")
      (assert (and (ok? wroteL2) (stringContains? t2 "EXIT:0")) (str "the second tick ran: " t2))
      (assert (near down (* 24.0 0.7)) (str "3.2 percent real 429 cuts by 0.7: " (stringFromFloat64 down)))
      (assert (and (ok? wroteL3) stored) "the looping timer wrote the store with no stored rate before it")
      (assert (>= timed 24.0) (str "the timer's tick raised the rate: " (stringFromFloat64 timed)))
      (assert hubStored (str "the hub's own learner wrote the store: " hubLog))
      (assert (>= hubRate 24.0) (str "the hub's learner raised the throttled alias: " (stringFromFloat64 hubRate)))
      (assert (and hubKilled hubPipes) "the hub and its learner are killed")
      (assert (and killed (and pipes removed)) "the learner, its pipes and the temp dir are cleaned up")
      true))

fn ! waitStore! path: String attempts: Int64 -> Bool
  (if (<= attempts 0) false
    (if (fileExists? path) true (do (sleepMs 20) (waitStore! path (- attempts 1)))))
