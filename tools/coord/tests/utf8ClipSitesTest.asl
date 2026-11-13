(module asl/tools/coord/tests/utf8ClipSitesTest
  :x [runTests]
  :i [(asl-tools/coord/trial :a tr) (asl-tools/coord/stall :a sl) (asl-tools/coord/commitGuard :a cg) (asl-tools/coord/mergeCheck :a mc) (asl-tools/coord/store :a st) (asl-tools/audit/run :a ar)])

; (:m :ref UTF8-CLIP-SWEEP :do "each site's byte cap lands inside a 3-byte CJK character (U+6F22) that follows cap - 1 ASCII bytes: the stored text keeps the ASCII prefix and drops the whole character instead of its first byte")
fn tail cap: Int64 -> String
  (str (stringRepeat "a" (- cap 1)) "漢" "zz")

fn prefix cap: Int64 -> String
  (stringRepeat "a" (- cap 1))

fn ! testTrialClip -> Bool
  (do (assert (= (tr/clip (tail 400)) (st/q (prefix 400))) "trial clip: a 400-byte cut inside a CJK character keeps the 399 ASCII bytes")
      (assert (= (tr/clip "short 漢") (st/q "short 漢")) "trial clip: text under 400 bytes is kept whole")
      true)

fn ! testStallOpText -> Bool
  (do (assert (= (sl/opText (tail 100)) (prefix 100)) "stall opText: a 100-byte cut inside a CJK character keeps the 99 ASCII bytes")
      (assert (= (sl/opText "ok 漢") "ok 漢") "stall opText: a short reply is kept whole")
      true)

fn ! testCommitGuardEsc1 -> Bool
  (do (assert (= (cg/esc1 (tail 160)) (str (prefix 160) "...")) "commitGuard esc1: a 160-byte cut inside a CJK character keeps the 159 ASCII bytes and the ellipsis")
      (assert (= (cg/esc1 "say \"漢\"") "say '漢'") "commitGuard esc1: short text is kept, quotes replaced")
      true)

fn ! testMergeCheckWhyOf -> Bool
  (do (assert (= (mc/whyOf (str "first line\n" (tail 240) "\n\n")) (prefix 240)) "mergeCheck whyOf: a 240-byte cut inside a CJK character keeps the 239 ASCII bytes")
      (assert (= (mc/whyOf "ERR 漢\n") "ERR 漢") "mergeCheck whyOf: a short last line is kept whole")
      true)

fn ! testAuditClip -> Bool
  (do (assert (= (ar/clip (str "  " (tail 170))) (prefix 170)) "audit clip: a 170-byte cut inside a CJK character keeps the 169 ASCII bytes")
      (assert (= (ar/clip " x \u6f22 ") "x \u6f22") "audit clip: short text is trimmed and kept")
      true)

fn ! runTests -> Bool
  (do (assert (testTrialClip) "trial clip")
      (assert (testStallOpText) "stall opText")
      (assert (testCommitGuardEsc1) "commitGuard esc1")
      (assert (testMergeCheckWhyOf) "mergeCheck whyOf")
      (assert (testAuditClip) "audit clip")
      true)
