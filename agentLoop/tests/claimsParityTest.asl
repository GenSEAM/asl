(module asl/agentLoop/tests/claimsParityTest
  :x [runTests]
  :i [(asl/agentLoop/claims :a cl) (asl/agentLoop/plan :a p) (asl/agentLoop/core :a c)])

fn fieldsOfLine line: String -> (List (Pair String p/SexpVal))
  (mt (p/planTree line)
    ((ok tree)
      (let [items (mt (listHead tree)
                    ((some h) (mt h ((p/sexpList it) it) ((p/sexpAtom _) (list)) ((p/sexpStr _) (list))))
                    (none (list)))]
        (pairFirst (p/planFields items))))
    ((err _) (list)))

fn getStr kv: (List (Pair String p/SexpVal)) k: String -> String
  (mt (p/kvGet kv k)
    ((some v) (mt v ((p/valStr s) s) ((p/valFlag b) (if b "true" "false")) ((p/valList _) "")))
    (none ""))

fn getInt kv: (List (Pair String p/SexpVal)) k: String -> Int64
  (optionOr (stringToInt64 (getStr kv k)) 0)

fn getBool kv: (List (Pair String p/SexpVal)) k: String -> Bool
  (= (getStr kv k) "true")

fn getNodes kv: (List (Pair String p/SexpVal)) k: String -> (List p/SexpNode)
  (mt (p/kvGet kv k)
    ((some v) (mt v ((p/valList items) items) ((p/valStr _) (list)) ((p/valFlag _) (list))))
    (none (list)))

fn nodeFields node: p/SexpNode -> (List (Pair String p/SexpVal))
  (mt node
    ((p/sexpList items) (pairFirst (p/planFields items)))
    ((p/sexpAtom _) (list))
    ((p/sexpStr _) (list)))

fn nodeStr node: p/SexpNode -> String
  (mt node
    ((p/sexpStr s) s)
    ((p/sexpAtom a) a)
    ((p/sexpList _) ""))

fn stringsOf nodes: (List p/SexpNode) -> (List String)
  (map nodeStr nodes)

fn getStrList kv: (List (Pair String p/SexpVal)) k: String -> (List String)
  (stringsOf (getNodes kv k))

fn gateRunFromNode node: p/SexpNode -> (Pair String Int64)
  (let [kv (nodeFields node)]
    (pair (getStr kv "cmd") (getInt kv "exit")))

fn receiptFromNode node: p/SexpNode -> cl/Receipt
  (let [kv (nodeFields node)]
    (cl/receiptOf (getStr kv "id") (getStr kv "cmd") (getStr kv "op") (getStr kv "status") (getStr kv "error")
                  (getBool kv "needsConfirm") (getBool kv "hasExit") (getInt kv "exit")
                  (map gateRunFromNode (getNodes kv "gateRuns"))
                  (getBool kv "hasSpan") (getInt kv "spanStart") (getInt kv "spanEnd") (getStr kv "file")))

fn receiptsFromKv kv: (List (Pair String p/SexpVal)) k: String -> (List cl/Receipt)
  (map receiptFromNode (getNodes kv k))

fn claimFromItemNode node: p/SexpNode -> cl/Claim
  (let [kv (nodeFields node)
        hasReceipt (getBool kv "hasReceipt")
        text (getStr kv "text")]
    (cl/evidenceClaim text (if hasReceipt (some text) (none)) (none) false))

fn spanFromNode node: p/SexpNode -> (Pair Int64 Int64)
  (let [kv (nodeFields node)] (pair (getInt kv "start") (getInt kv "end")))

fn coverageEntryFromNode node: p/SexpNode -> (Pair String (List (Pair Int64 Int64)))
  (let [kv (nodeFields node)]
    (pair (getStr kv "path") (map spanFromNode (getNodes kv "spans"))))

fn coverageFromKv kv: (List (Pair String p/SexpVal)) k: String -> (List (Pair String (List (Pair Int64 Int64))))
  (map coverageEntryFromNode (getNodes kv k))

fn turnEntryFromNode node: p/SexpNode -> cl/TurnEvidenceEntry
  (let [kv (nodeFields node)
        turn (getInt kv "turn")
        reads (map (fn [rn] (let [rkv (nodeFields rn)] (pair (getStr rkv "path") (pair (getInt rkv "start") (getInt rkv "end")))))
                (getNodes kv "reads"))
        keys (map (fn [s] (list (c/kvStr s))) (getStrList kv "keys"))]
    (cl/turnEvidenceEntry turn reads keys))

fn strEq name: String got: String want: String -> Bool
  (do (assert (= got want) (str name ": got " got " want " want)) (= got want))

fn boolEq name: String got: Bool want: String -> Bool
  (strEq name (if got "true" "false") want)

fn intEq name: String got: Int64 want: Int64 -> Bool
  (do (assert (= got want) (str name ": got " (stringFromInt64 got) " want " (stringFromInt64 want))) (= got want))

fn checkCase kv: (List (Pair String p/SexpVal)) -> Bool
  (let [fnName (getStr kv "fn") cid (getStr kv "id")]
    (cond
      ((= fnName "hasNegatorNear")
        (boolEq cid (cl/hasNegatorNear (getStr kv "sentence") (getInt kv "matchStart")) (getStr kv "want")))

      ((= fnName "wrongCitationNote")
        (let [claims (map claimFromItemNode (getNodes kv "items"))]
          (strEq cid (cl/wrongCitationNote claims) (getStr kv "want"))))

      ((= fnName "extractProseStrings")
        (let [useOld (getBool kv "useOld")
              planOn (getBool kv "planOn")
              keys (if useOld (cl/oldStructuralKeys) (cl/newStructuralKeys))
              got (cl/extractProseStrings (getStr kv "text") keys planOn)
              want (getStrList kv "want")]
          (strEq cid (c/joinSep got "|") (c/joinSep want "|"))))

      ((= fnName "mergeFindings")
        (let [earlier (getStrList kv "earlier")
              result (cl/mergeFindings (getStr kv "form") earlier)
              kept (pairFirst result) replaced (pairSecond result)
              wantKept (getStrList kv "wantKept")]
          (and (intEq (str cid ".replaced") replaced (getInt kv "wantReplaced"))
            (strEq (str cid ".kept") (c/joinSep kept "|") (c/joinSep wantKept "|")))))

      ((= fnName "isTurnObservation")
        (boolEq cid (cl/isTurnObservation (c/parseReply (getStr kv "reply"))) (getStr kv "want")))

      ((= fnName "unwrapReadTxns")
        (let [result (cl/unwrapReadTxns (c/parseReply (getStr kv "reply")))]
          (and (intEq (str cid ".count") (cl/unwrapResultCount result) (getInt kv "wantCount"))
            (intEq (str cid ".opsLen") (listLength (cl/unwrapResultOps result)) (getInt kv "wantOpsLen")))))

      ((= fnName "receiptBacks")
        (let [hasCE (getBool kv "hasExit")
              ce (if hasCE (some (getInt kv "exit")) (none))
              receipts (receiptsFromKv kv "receipts")]
          (boolEq cid (cl/receiptBacks (getStr kv "rid") ce receipts) (getStr kv "want"))))

      ((= fnName "isBacked")
        (let [receipts (receiptsFromKv kv "receipts")]
          (boolEq cid (cl/isBacked (getStr kv "cmd") (getInt kv "exit") receipts) (getStr kv "want"))))

      ((= fnName "isProseClaimBacked")
        (let [receipts (receiptsFromKv kv "receipts")
              gates (getStrList kv "gates")]
          (boolEq cid (cl/isProseClaimBacked (getStr kv "sentence") receipts gates (getBool kv "gatePassBacked")) (getStr kv "want"))))

      ((= fnName "extractClaims")
        (let [receipts (receiptsFromKv kv "receipts")
              gates (getStrList kv "gates")
              result (cl/extractClaims (getStr kv "reply") receipts (getBool kv "isOldCall") gates
                       (getBool kv "checkProse") (getBool kv "gatePassBacked") (getBool kv "planOn"))
              gotBacked (c/joinSep (map (fn [cm] (if (cl/claimBacked cm) "true" "false")) (cl/claimsResultClaims result)) "|")
              wantBacked (c/joinSep (getStrList kv "wantBacked") "|")]
          (and (intEq (str cid ".total") (cl/claimsResultTotal result) (getInt kv "wantTotal"))
            (and (intEq (str cid ".unbacked") (cl/claimsResultUnbacked result) (getInt kv "wantUnbacked"))
              (strEq (str cid ".backed") gotBacked wantBacked)))))

      ((= fnName "turnBringsEvidence")
        (let [ops (c/parseReply (getStr kv "reply"))
              receipts (receiptsFromKv kv "receipts")
              coverageIn (coverageFromKv kv "coverageIn")
              result (cl/turnBringsEvidence ops receipts coverageIn (list) (getStr kv "mode") (getStr kv "base") false)]
          (and (boolEq (str cid ".new") (cl/evidenceUpdateNew result) (getStr kv "wantNew"))
            (and (intEq (str cid ".coveragePaths") (listLength (cl/evidenceUpdateCoverage result)) (getInt kv "wantCoveragePaths"))
              (intEq (str cid ".seenKeys") (listLength (cl/evidenceUpdateSeenKeys result)) (getInt kv "wantSeenKeys"))))))

      ((= fnName "forgetCutEvidence")
        (let [entries (map turnEntryFromNode (getNodes kv "entries"))
              whole (map (fn [s] (optionOr (stringToInt64 s) 0)) (getStrList kv "whole"))
              result (cl/forgetCutEvidence entries whole)]
          (strEq cid (cl/forgetCutResultText result) (getStr kv "wantText"))))

      (else false)))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        content (resultOr (fileReadString (str root "/asl/agentLoop/tests/claimsParityFixture.asn")) "")
        lines (filter (fn [l] (stringStartsWith? l "(:case ")) (stringLines content))
        n (listLength lines)]
    (do
      (assert (>= n 40) "the claims parity fixture holds at least 40 cases")
      (fold (fn [acc line] (and (checkCase (fieldsOfLine line)) acc)) true lines)))
