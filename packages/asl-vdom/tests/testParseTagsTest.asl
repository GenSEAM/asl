(module test_parse_tags_test :x [runTests TestSelfClosingTags TestPruneTags TestComponentTags TestSignalBatching TestVnodeStructuralHash] :i [(aslVdom/vdom :a v) (aslVdom/polyglot :a p) (aslVdom/signals :a s)])

fn TestSelfClosingTags -> Bool
  (do (assert (p/isSelfClosing? "img") "img must be self-closing") (assert (p/isSelfClosing? "input") "input must be self-closing") (assert (p/isSelfClosing? "br") "br must be self-closing") (assert (p/isSelfClosing? "hr") "hr must be self-closing") (assert (not (p/isSelfClosing? "div")) "div must not be self-closing") (assert (not (p/isSelfClosing? "span")) "span must not be self-closing") true)

fn TestPruneTags -> Bool
  (do (assert (v/shouldPruneTag? "script") "script must be pruned") (assert (v/shouldPruneTag? "style") "style must be pruned") (assert (v/shouldPruneTag? "noscript") "noscript must be pruned") (assert (not (v/shouldPruneTag? "h1")) "h1 must not be pruned") (assert (not (v/shouldPruneTag? "p")) "p must not be pruned") true)

fn TestComponentTags -> Bool
  (do (assert (v/isComponentTag? "UserProfile") "UserProfile must be recognized as component") (assert (v/isComponentTag? "NavBar") "NavBar must be recognized as component") (assert (not (v/isComponentTag? "button")) "button must not be component") (assert (not (v/isComponentTag? "div")) "div must not be component") true)

fn TestSignalBatching -> Bool
  (let [(b0 (s/makeSignalBatch))]
    (assert (not b0.isPending) "New signal batch must not be pending")
    (assert (= (listLength b0.queuedSignalIds) 0) "New signal batch must have 0 queued signals")
    (let [(b1 (s/queueSignalUpdate b0 "sig-alpha"))
          (b2 (s/queueSignalUpdate b1 "sig-beta"))
          (b3 (s/queueSignalUpdate b2 "sig-alpha"))]
      (assert b3.isPending "Batch with queued signals must be pending")
      (assert (= (listLength b3.queuedSignalIds) 2) "Batch must deduplicate sig-alpha to 2 queued signals")
      (let [(flushed (s/flushSignalBatch b3))
            (bNext (pairFirst flushed))
            (signalIds (pairSecond flushed))]
        (assert (not bNext.isPending) "Flushed batch must reset isPending to false")
        (assert (= (listLength signalIds) 2) "Flushed signal IDs count must be 2")
        (assert (listContains? signalIds "sig-alpha") "Flushed signals must contain sig-alpha")
        (assert (listContains? signalIds "sig-beta") "Flushed signals must contain sig-beta")
        true)))

fn TestVnodeStructuralHash -> Bool
  (let [(t1 (v/el "div" (mapEmpty) (list (v/t "hello"))))
        (t2 (v/el "div" (mapEmpty) (list (v/t "hello"))))
        (t3 (v/el "div" (mapEmpty) (list (v/t "world"))))
        (h1 (v/vnodeStructuralHash t1))
        (h2 (v/vnodeStructuralHash t2))
        (h3 (v/vnodeStructuralHash t3))]
    (assert (= h1 h2) "Identical vnodes must produce identical structural hashes")
    (assert (!= h1 h3) "Distinct vnodes must produce distinct structural hashes")
    (let [(diffIdentical (v/diffNodes t1 t2 "root"))
          (diffDistinct (v/diffNodes t1 t3 "root"))]
      (assert (= (listLength diffIdentical) 0) "Diffing identical vnodes must short-circuit to 0 mutations")
      (assert (> (listLength diffDistinct) 0) "Diffing distinct vnodes must produce non-zero mutations")
      true))

fn runTests -> Bool
  (do
    (assert (TestSelfClosingTags) "TestSelfClosingTags must pass")
    (assert (TestPruneTags) "TestPruneTags must pass")
    (assert (TestComponentTags) "TestComponentTags must pass")
    (assert (TestSignalBatching) "TestSignalBatching must pass")
    (assert (TestVnodeStructuralHash) "TestVnodeStructuralHash must pass")
    true)
