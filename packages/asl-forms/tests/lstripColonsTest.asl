(module asl-forms/tests/lstripColonsTest :x [runTests] :i [(asl-forms/kernel :a k)])

; (:m :ref COVRATCHET :do "lstripColons: strips every leading colon and nothing else")
fn runTests -> Bool
  (do
    (assert (= (k/lstripColons ":a") "a") "one colon")
    (assert (= (k/lstripColons "::a") "a") "two colons")
    (assert (= (k/lstripColons "a") "a") "no colon")
    (assert (= (k/lstripColons "a:b") "a:b") "an inner colon stays")
    (assert (= (k/lstripColons ":a:") "a:") "a trailing colon stays")
    (assert (= (k/lstripColons "") "") "empty")
    (assert (= (k/lstripColons ":") "") "only one colon")
    (assert (= (k/lstripColons ":::") "") "only colons")
    true)
