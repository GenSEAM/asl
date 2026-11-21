(module asl-runtime/tests/refcountCoverTest
  :x [testMakeRefHeaderNormal testMakeRefHeaderEmptyPtr testMakeRefHeaderNoNonePath
      testRtRetainNormal testRtRetainFromFreed testRtRetainZeroCount testRtRetainMaxMinusOne
      testRtReleaseNormal testRtReleaseFreesAtZero testRtReleaseBelowZeroClamps testRtReleaseMax
      testRtReleaseNoNonePath testLifecycle runTests]
  :i [(asl-runtime/refcount :a rc)])

fn testMakeRefHeaderNormal -> Bool
  (let [(h (rc/makeRefHeader "obj-1"))]
    (assert (= h.ptr "obj-1") "makeRefHeader must preserve ptr")
    (assert (= h.refCount 1) "makeRefHeader must start with refCount 1")
    (assert (not h.isFreed) "makeRefHeader must start unfreed")
    true)

fn testMakeRefHeaderEmptyPtr -> Bool
  (let [(h (rc/makeRefHeader ""))]
    (assert (= h.ptr "") "makeRefHeader must accept an empty ptr")
    (assert (= h.refCount 1) "empty ptr header must still start with refCount 1")
    (assert (not h.isFreed) "empty ptr header must start unfreed")
    true)

fn testMakeRefHeaderNoNonePath -> Bool
  (let [(h (rc/makeRefHeader "obj"))]
    (refute h.isFreed "makeRefHeader has no error path; result must never be freed")
    (assert (> h.refCount 0) "makeRefHeader has no none path; refCount must be positive")
    true)

fn testRtRetainNormal -> Bool
  (let [(h (rc/rtRetain (rc/makeRefHeader "obj-1")))]
    (assert (= h.ptr "obj-1") "rtRetain must preserve ptr")
    (assert (= h.refCount 2) "rtRetain must increment refCount from 1 to 2")
    (assert (not h.isFreed) "rtRetain must keep the header unfreed")
    true)

fn testRtRetainFromFreed -> Bool
  (let [(freed (with (rc/makeRefHeader "obj-1") :refCount 0 :isFreed true))
        (h (rc/rtRetain freed))]
    (assert (= h.refCount 1) "rtRetain on a zero-count header must raise refCount to 1")
    (assert (not h.isFreed) "rtRetain must revive a freed header")
    true)

fn testRtRetainMaxMinusOne -> Bool
  (let [(h (rc/rtRetain (with (rc/makeRefHeader "obj-1") :refCount 9223372036854775806)))]
    (assert (= h.refCount 9223372036854775807) "rtRetain at max-1 must reach max Int64")
    (assert (not h.isFreed) "rtRetain at max-1 must stay unfreed")
    true)

fn testRtRetainZeroCount -> Bool
  (let [(h (rc/rtRetain (with (rc/makeRefHeader "obj-1") :refCount 0)))]
    (assert (= h.refCount 1) "rtRetain at refCount 0 must give 1")
    (assert (not h.isFreed) "rtRetain at refCount 0 must leave the header unfreed")
    true)

fn testRtReleaseNormal -> Bool
  (let [(h (rc/rtRelease (rc/rtRetain (rc/makeRefHeader "obj-1"))))]
    (assert (= h.ptr "obj-1") "rtRelease must preserve ptr")
    (assert (= h.refCount 1) "rtRelease must decrement refCount from 2 to 1")
    (assert (not h.isFreed) "rtRelease above zero must keep the header unfreed")
    true)

fn testRtReleaseFreesAtZero -> Bool
  (let [(h (rc/rtRelease (rc/makeRefHeader "obj-1")))]
    (assert (= h.refCount 0) "rtRelease at refCount 1 must drop to 0")
    (assert h.isFreed "rtRelease at refCount 1 must mark the header freed")
    true)

fn testRtReleaseBelowZeroClamps -> Bool
  (let [(freed (with (rc/makeRefHeader "obj-1") :refCount 0 :isFreed true))
        (h (rc/rtRelease freed))]
    (assert (= h.refCount 0) "rtRelease below zero must clamp refCount at 0")
    (assert h.isFreed "rtRelease below zero must stay freed")
    true)

fn testRtReleaseMax -> Bool
  (let [(h (rc/rtRelease (with (rc/makeRefHeader "obj-1") :refCount 9223372036854775807)))]
    (assert (= h.refCount 9223372036854775806) "rtRelease at max must drop to max-1")
    (assert (not h.isFreed) "rtRelease at max must stay unfreed")
    true)

fn testRtReleaseNoNonePath -> Bool
  (let [(h (rc/rtRelease (rc/makeRefHeader "obj")))]
    (assert (>= h.refCount 0) "rtRelease has no none path; refCount must never go negative")
    (assert h.isFreed "rtRelease has no none path; the last release must free")
    true)

fn testLifecycle -> Bool
  (let [(h0 (rc/makeRefHeader "obj"))
        (h1 (rc/rtRetain h0))
        (h2 (rc/rtRetain h1))
        (h3 (rc/rtRelease h2))
        (h4 (rc/rtRelease h3))
        (h5 (rc/rtRelease h4))]
    (assert (= h1.refCount 2) "lifecycle: first retain must give 2")
    (assert (= h2.refCount 3) "lifecycle: second retain must give 3")
    (assert (= h3.refCount 2) "lifecycle: first release must give 2")
    (assert (= h4.refCount 1) "lifecycle: second release must give 1")
    (assert (not h4.isFreed) "lifecycle: header must stay unfreed at refCount 1")
    (assert (= h5.refCount 0) "lifecycle: final release must give 0")
    (assert h5.isFreed "lifecycle: final release must free the header")
    true)

fn runTests -> Bool
  (do
    (assert (testMakeRefHeaderNormal) "makeRefHeader normal test must pass")
    (assert (testMakeRefHeaderEmptyPtr) "makeRefHeader empty ptr test must pass")
    (assert (testMakeRefHeaderNoNonePath) "makeRefHeader no-none-path test must pass")
    (assert (testRtRetainNormal) "rtRetain normal test must pass")
    (assert (testRtRetainFromFreed) "rtRetain from freed test must pass")
    (assert (testRtRetainZeroCount) "rtRetain zero-count test must pass")
    (assert (testRtRetainMaxMinusOne) "rtRetain max-1 test must pass")
    (assert (testRtReleaseNormal) "rtRelease normal test must pass")
    (assert (testRtReleaseFreesAtZero) "rtRelease frees-at-zero test must pass")
    (assert (testRtReleaseBelowZeroClamps) "rtRelease below-zero clamp test must pass")
    (assert (testRtReleaseMax) "rtRelease max test must pass")
    (assert (testRtReleaseNoNonePath) "rtRelease no-none-path test must pass")
    (assert (testLifecycle) "lifecycle test must pass")
    true)

fn main args: (List String) -> (Result Int64 String)
  (ok 0)
