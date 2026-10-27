(module asl-forms/tests/unknownKeyTest :x [runTests] :i [(asl-forms/ops :a ops)])

fn root! -> String
  (resultOr (realPath ".") ".")

fn line! form: String -> String
  (optionOr (listHead (ops/runStep! (root!) 1 form).lines) "")

fn errs! form: String -> Int64
  (ops/runStep! (root!) 1 form).errCount

fn ! testIntelPathIsRejected -> Bool
  (let [(form "(:intel :op outline :path asl/packages/asl-intel/src/stubs.asl)")
        (l (line! form))]
    (do (assert (= (errs! form) 1) (str "unknown :path on :intel is an error, not an outline of the default file: " l))
        (assert (stringContains? l "ERR_UNKNOWN_KEY") (str "error code names the class: " l))
        (assert (stringContains? l ":keys (:path)") (str "the offending key is named: " l))
        (assert (stringContains? l ":accepted (") (str "accepted keys are listed: " l))
        (assert (stringContains? l ":file") (str "accepted keys include :file: " l))
        true))

fn ! testOtherOpIsRejected -> Bool
  (let [(form "(:read :file asl/grammar/tools.asn :bogus 1 :alsoBogus 2)")
        (l (line! form))]
    (do (assert (= (errs! form) 1) (str "the check is shared, not intel-only: " l))
        (assert (stringContains? l ":keys (:alsoBogus :bogus)") (str "every unknown key listed, sorted: " l))
        true))

fn ! testKnownKeysPass -> Bool
  (let [(l (line! "(:intel :op outline :file asl/packages/asl-intel/src/stubs.asl)"))
        (r (line! "(:read :file asl/grammar/tools.asn :limit 2)"))]
    (do (assert (not (stringContains? l "ERR_UNKNOWN_KEY")) (str "declared keys are not rejected: " l))
        (assert (not (stringContains? r "ERR_UNKNOWN_KEY")) (str "declared keys are not rejected on read: " r))
        true))

fn ! runTests -> Bool
  (do (assert (testIntelPathIsRejected) "intel with an unknown key fails with ERR_UNKNOWN_KEY")
      (assert (testOtherOpIsRejected) "read with unknown keys fails with ERR_UNKNOWN_KEY")
      (assert (testKnownKeysPass) "declared keys still run")
      true)
