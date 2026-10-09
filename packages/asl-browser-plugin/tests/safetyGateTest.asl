(module aslBrowserPlugin/tests/safetyGateTest :x [testTiers testAllowList testFailClosed runTests] :i [(aslBrowserPlugin/safetyGate :a sg)])

fn testTiers -> Bool
  (do
    (assert (sg/validateBrowserAction "list-tabs" false (list) "example.com") "a safe action runs with no allow-list")
    (assert (sg/validateBrowserAction "get-dom" false (list "a.com") "b.com") "a safe action runs off the allow-list")
    true)

fn testAllowList -> Bool
  (do
    (assert (sg/validateBrowserAction "open-tab" false (list "a.com") "a.com") "a guarded action runs on an allowed domain")
    (refute (sg/validateBrowserAction "open-tab" false (list "a.com") "b.com") "a guarded action is denied off the allow-list")
    (assert (sg/validateBrowserAction "submit-form" true (list "a.com") "a.com") "a confirmed dangerous action runs on an allowed domain")
    (refute (sg/validateBrowserAction "submit-form" false (list "a.com") "a.com") "an unconfirmed dangerous action is denied")
    true)

fn testFailClosed -> Bool
  (do
    (refute (sg/validateBrowserAction "open-tab" false (list) "a.com") "an empty allow-list denies a guarded action")
    (refute (sg/validateBrowserAction "submit-form" true (list) "a.com") "an empty allow-list denies a confirmed dangerous action")
    true)

fn runTests -> Bool
  (and (testTiers) (and (testAllowList) (testFailClosed)))
