(module asl/agentLoop/tests/turnParityTest
  :x [runTests]
  :i [(asl/agentLoop/turn :a tr) (asl/agentLoop/reply :a r) (asl/agentLoop/core :a c) (asl/agentLoop/plan :a p) (asl/agentLoop/tests/parity :a t)])

fn sVal v: c/KvVal -> String
  (mt v ((c/kvStr x) (t/sStr x)) ((c/kvInt x) (mt (stringToInt64 x) ((some i) (t/sInt i)) ((none) (t/sStr x)))))

fn sOps ops: (List (List (Pair String c/KvVal))) -> String
  (t/sList (map (fn [op] (t/sDict (map (fn [pr] (pair (pairFirst pr) (sVal (pairSecond pr)))) op))) ops))

fn chars s: String off: Int64 -> Int64
  (r/charsBefore s off)

fn sCut full: String ci: r/CutInfo -> String
  (t/sDict (list (pair "offset" (t/sInt ci.offset)) (pair "bytes" (t/sInt ci.bytes)) (pair "head" (t/sOpt ci.head))
                 (pair "op" (t/sOpt ci.op)) (pair "file" (t/sOpt ci.file)) (pair "start" (t/sInt ci.start))
                 (pair "text" (t/sStr ci.text))))

fn sSpans input: String spans: (List (Pair Int64 Int64)) -> String
  (t/sList (map (fn [sp] (t/sList (list (t/sInt (chars input (pairFirst sp))) (t/sInt (chars input (pairSecond sp)))))) spans))

fn sAuto a: r/AutoRepair input: String -> String
  (t/sDict (listAppend
    (list (pair "text" (t/sStr a.text)) (pair "notice" (t/sOpt a.notice)) (pair "kinds" (t/sStrs a.kinds))
          (pair "left" (t/sInt a.left)) (pair "quoteCount" (t/sInt a.quoteCount)))
    (mt a.leftSpans ((some spans) (list (pair "leftSpans" (sSpans input spans)))) ((none) (list)))))

fn sFacts f: r/ReplyFacts input: String -> String
  (let [bound (r/bindRawBlocks input).text]
    (t/sDict (listAppend
      (list (pair "ops" (sOps f.ops)) (pair "repeated" (t/sInt f.repeated)) (pair "forms" (t/sStrs f.forms))
            (pair "prose" (t/sBool f.prose)) (pair "dataFindings" (t/sStrs f.dataFindings)))
      (mt f.cut ((some ci) (list (pair "cut" (sCut bound ci)))) ((none) (list))))))

fn ! dispatch fname: String args: (List p/SexpNode) -> String
  (let [raw (t/argStr (t/argAt args 0))
        declNode (t/argAt args 1)
        declared (if (t/argNil? declNode) none (some (t/argStrs declNode)))
        got (tr/turnReply raw declared)]
    (t/sDict (list (pair "text" (t/sStr got.text)) (pair "degenerateAt" (mt got.degenerateAt ((some i) (t/sInt i)) ((none) "nil")))
                   (pair "degenerateRepeats" (t/sInt got.degenerateRepeats)) (pair "capBytes" (t/sInt got.capBytes))
                   (pair "rawBlocks" (t/sInt got.rawBlocks)) (pair "unfenced" (t/sInt got.unfenced))
                   (pair "missingRaw" (t/sStrs got.missingRaw)) (pair "facts" (sFacts got.facts raw))
                   (pair "repair" (mt got.repair ((some a) (sAuto a raw)) ((none) "nil"))))))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        path (str root "/asl/agentLoop/tests/turnParityFixtures.asn")
        passed (t/replay! path (list "turnReply") (fn [f a] (dispatch f a)))
        cutReply (tr/turnReply "(:step :op \"read\" :file \"a.txt\")\n(:step :op \"write\" :file \"big.txt\" :content \"abc" none)
        cut cutReply.facts.cut
        priorCut (r/CutInfo :offset 33 :bytes 18 :head (some "step") :op (some "write") :file none :start 33 :text "(:step :op \"write\"")
        parsedCut (r/CutInfo :offset 55 :bytes 8 :head (some "step") :op (some "done") :file none :start 55 :text "(:step :")
        endCut (r/CutInfo :offset 33 :bytes 18 :head (some "step") :op (some "write") :file none :start 33 :text "(:step :op \"write\"")
        cutSpans (some (list (pair 33 63)))
        openReply (tr/turnReply "((" none)
        openRepair openReply.repair
        prose (str "explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation "
                   "explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation "
                   "explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation "
                   "explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation "
                   "explanation explanation explanation explanation explanation explanation explanation explanation explanation explanation "
                   "(:step :op \"read\" :file \"a.txt\")")
        proseReply (tr/turnReply prose none)]
    (do
      (assert (= passed 7) "all seven independently recorded turn results match the core turn implementation")
      (assert (mt cut ((some ci) (and (= ci.op (some "write")) (= ci.file (some "big.txt")))) ((none) false))
              "a cut write keeps its operation and file for ERR_REPLY_CUT")
      (assert (and (= openReply.text "((") (mt openRepair ((some a) (stringEmpty? a.text)) ((none) false)))
              "an empty repair retains the malformed reply rather than erasing it")
      (assert (not (tr/cutRestored (some priorCut) (some parsedCut) cutSpans))
              "an already reparsed cut is not replaced by the pre-repair cut")
      (assert (tr/cutRestored (some priorCut) none cutSpans)
              "a pre-repair cut is retained when reparsing has no cut")
      (assert (not (tr/cutRestored (some endCut) none (some (list (pair 10 33)))))
              "a cut exactly at a repaired span end is outside the span")
      (assert (and (some? proseReply.repair) (not (listEmpty? proseReply.facts.ops)))
              "prose surrounding a parsed step enters reply repair")
      (assert (= (tr/vendorRetryPause "ERR_VENDOR" 2 (list 3 8) (some 20)) 8) "transient retry takes its configured backoff slot")
      (assert (= (tr/vendorRetryPause "ERR_VENDOR" 2 (list 3 8) (some 4)) 4) "retry backoff is capped by remaining wall budget")
      (assert (= (tr/vendorRetryPause "ERR_CONTEXT_TOO_LONG" 2 (list 3 8) none) 0) "non-transient provider failures do not back off")
      true))
