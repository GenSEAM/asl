(module aslGateway/tests/admissionAimdTest
  :x [runTests]
  :i [(admission :a adm)
      (config :a c)
      (asl-tools/fleet/run :a fr)])

; (:m :ref GW-SYN-ADMISSION :do "a fake upstream that answers 429 above 2 in flight, driven through the real shared admission state: the cap halves once per burst, never passes the static limit, regrows by 1 per streak of successes, and a Retry-After pauses the lane")
fn row n: Int64 mx: Int64 -> c/GatewayLimit
  (c/GatewayLimit :provider "syn" :scope "model" :model "f" :window "" :calls 0 :tokens 0 :concurrency n :max mx)

fn ! fill! n: Int64 home: String lims: (List c/GatewayLimit) now: Int64 -> Int64
  (if (<= n 0) 0
    (+ (match (adm/admitShared! home lims "syn" "f" now 600000) ((ok t) (if t 1 0)) ((err _) 0))
       (fill! (- n 1) home lims now)))

fn ! cut! n: Int64 home: String lims: (List c/GatewayLimit) now: Int64 -> Int64
  (if (<= n 0) 0
    (do (adm/concurrency429After! home lims "syn" "f" now 0)
      (cut! (- n 1) home lims now)))

fn ! win! n: Int64 home: String lims: (List c/GatewayLimit) now: Int64 -> Int64
  (if (<= n 0) 0
    (do (adm/releaseShared! home lims "syn" "f" now true)
      (win! (- n 1) home lims now)))

fn ! capOf! home: String -> Int64
  (match (fileReadString (str home "/.asl/run/gwAdmission/syn-f.asn"))
    ((err _) 0)
    ((ok t) (match (adm/parseLane t) ((ok l) l.cap) ((err _) 0))))

fn ! inFlightOf! home: String -> Int64
  (listLength (filter (fn [(s String)] -> Bool (stringStartsWith? s "syn\tf\t"))
                (stringSplit (resultOr (fileReadString (str home "/.asl/run/gwAdmission/leases.tsv")) "") "\n")))

fn ! runTests -> Bool
  (let [(home (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/admissionAimdTest.XXXXXX" 5000) "")))
        (lims (list (row 6 6)))
        (took1 (fill! 8 home lims 1000))
        (burst (cut! 4 home lims 1100))
        (capCut (capOf! home))
        (left (inFlightOf! home))
        (took2 (fill! 8 home lims 5000))
        (_w (win! 19 home lims 900000))
        (capShort (capOf! home))
        (_w2 (win! 1 home lims 900000))
        (capGrown (capOf! home))
        (_w3 (win! 400 home lims 9000000))
        (capTop (capOf! home))
        (ra (adm/concurrency429After! home lims "syn" "f" 20000000 1000))
        (_free (win! 20 home lims 20000100))
        (heldHalf (fill! 1 home lims 20000500))
        (heldEnd (fill! 1 home lims 20001000))
        (_free2 (win! 20 home lims 20001100))
        (hugeRa (adm/concurrency429After! home lims "syn" "f" 30000000 999999999))
        (heldHuge (fill! 1 home lims 30000000))
        (afterMax (fill! 1 home lims 30300001))
        (cleaned (fr/shellOut (str "/bin/rm -rf " home) 5000))]
    (do
      (assert (= took1 6) (str "eight asks against the static limit 6 admit 6: " (stringFromInt64 took1)))
      (assert (= capCut 3) (str "four simultaneous 429s cut the cap once, 6 -> 3: " (stringFromInt64 capCut)))
      (assert (= left 2) (str "the failed calls freed their leases, 2 stay in flight: " (stringFromInt64 left)))
      (assert (= took2 1) (str "under cap 3 with 2 in flight one more call is admitted: " (stringFromInt64 took2)))
      (assert (= capShort 3) (str "19 successes do not regrow the cap: " (stringFromInt64 capShort)))
      (assert (= capGrown 4) (str "the 20th success inside no 429 for the quiet period regrows it by 1: " (stringFromInt64 capGrown)))
      (assert (= capTop 6) (str "regrowth stops at the static limit 6: " (stringFromInt64 capTop)))
      (assert (ok? ra) "a 429 with Retry-After 1000 ms is recorded")
      (assert (= heldHalf 0) "inside Retry-After nothing is admitted")
      (assert (= heldEnd 1) "at Retry-After the lane admits again")
      (assert (ok? hugeRa) "an absurd Retry-After is recorded")
      (assert (= heldHuge 0) "the hold applies")
      (assert (= afterMax 1) "a Retry-After is clipped to 300 s")
      (assert (ok? cleaned) "temp dir removed")
      true))
