(module asl-cli/tests/argParsersTest :x [runTests] :i [(asl-cli/ir :a ir) (asl-cli/conform :a cf)])

; (:m :ref COVBATCH4 :do "parseIrArgs and parseConformArgs: defaults, = and space forms, flags, unknown flags, first path wins")
fn irOf args: (List String) -> String
  (let [(o (ir/parseIrArgs args "" "" false))] (str o.path "|" o.target "|" (if o.verifyOnly "v" "-")))

fn cfOf args: (List String) -> String
  (let [(o (cf/parseConformArgs args "" "" false))] (str o.profile "|" o.rule "|" (if o.invert "i" "-")))

fn runTests -> Bool
  (do
    (assert (= (irOf (list)) "|c11|-") "no arguments: empty path, default target")
    (assert (= (irOf (list "f.asl")) "f.asl|c11|-") "a path")
    (assert (= (irOf (list "--target=py" "f.asl")) "f.asl|py|-") "target with =")
    (assert (= (irOf (list "--target" "wasm" "f.asl")) "f.asl|wasm|-") "target with a space")
    (assert (= (irOf (list "f.asl" "--verify-only")) "f.asl|c11|v") "verify only")
    (assert (= (irOf (list "-x" "f.asl")) "f.asl|c11|-") "an unknown dash flag is skipped")
    (assert (= (irOf (list "a.asl" "b.asl")) "a.asl|c11|-") "the first path wins")
    (assert (= (irOf (list "f.asl" "--target")) "f.asl|c11|-") "a target flag without a value keeps the default")
    (assert (= (cfOf (list)) "py||-") "no arguments: default profile")
    (assert (= (cfOf (list "--profile=c11")) "c11||-") "profile with =")
    (assert (= (cfOf (list "--profile" "wasm")) "wasm||-") "profile with a space")
    (assert (= (cfOf (list "--rule=r1")) "py|r1|-") "rule with =")
    (assert (= (cfOf (list "--rule" "r2" "--invert")) "py|r2|i") "rule with a space and invert")
    (assert (= (cfOf (list "--bogus" "--invert")) "py||i") "an unknown flag is skipped")
    (assert (= (cfOf (list "--profile")) "py||-") "a profile flag without a value keeps the default")
    true)
