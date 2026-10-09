(module asl/agentLoop/card
  :x [Backend Pool AgentCard defaultAllowlist buildCard formatCardAsn main]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/core :a c) (asl/agentLoop/exec :a ex) (asl/agentLoop/providers :a pv)])

(schema Backend
  (:f name String)
  (:f defaultModel String))

(schema Pool
  (:f name String)
  (:f size Int64))

(schema AgentCard
  (:f name String)
  (:f acceptedKeys (List String))
  (:f allowlist (List String))
  (:f deliverables (List String))
  (:f backends (List Backend))
  (:f gatewayPools (List Pool))
  (:f receiptFields (List String))
  (:f escalateForm String))

fn extractLocalOps text: String n: Int64 i: Int64 acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [marker "(:effect :op \""]
      (mt (stringIndexOf (c/sliceOf text i n) marker)
        ((none) (listReverse acc))
        ((some subPos)
          (let [pos (+ i subPos)
                startOp (+ pos (stringLength marker))]
            (mt (stringIndexOf (c/sliceOf text startOp n) "\"")
              ((none) (listReverse acc))
              ((some subEnd)
                (let [endOp (+ startOp subEnd)
                      op (c/sliceOf text startOp endOp)
                      limitEnd (min n (+ endOp 40))
                      restSnippet (c/sliceOf text endOp limitEnd)
                      isLocal (stringContains? restSnippet ":class :local")
                      newAcc (if (and isLocal (!= op "step")) (cons op acc) acc)]
                  (extractLocalOps text n (+ endOp 1) newAcc)))))))))

fn ! getAllowlist rootDir: String -> (Result (List String) String)
  (let [path (str rootDir "/scripts/agentLoop/effects.asn")]
    (mt (fileReadString path)
      ((err e) (err e))
      ((ok text) (ok (extractLocalOps text (stringLength text) 0 (list))))))

fn poolRows text: String n: Int64 i: Int64 acc: (List Pool) -> (List Pool)
  (mt (stringIndexOf (c/sliceOf text i n) "TrackedSemaphore(int(os.environ.get(")
    ((none) (listSortBy (fn [p] p.name) (listReverse acc)))
    ((some found)
      (let [a (+ i found (stringLength "TrackedSemaphore(int(os.environ.get("))
            comma (mt (stringIndexOf (c/sliceOf text a n) ",") ((some p) (+ a p)) (none -1))
            close (if (< comma 0) -1 (mt (stringIndexOf (c/sliceOf text comma n) ")") ((some p) (+ comma p)) (none -1)))
            size (if (< close 0) -1 (optionOr (stringToInt64 (stringTrim (c/sliceOf text (+ comma 1) close))) -1))
            nameAt (if (< close 0) -1 (mt (stringIndexOf (c/sliceOf text close n) "name=\"") ((some p) (+ close p 6)) (none -1)))
            nameEnd (if (< nameAt 0) -1 (mt (stringIndexOf (c/sliceOf text nameAt n) "\"") ((some p) (+ nameAt p)) (none -1)))
            name (if (< nameEnd 0) "" (c/sliceOf text nameAt nameEnd))
            rows (if (and (>= size 0) (not (stringEmpty? name))) (cons (Pool :name name :size size) acc) acc)
            next (if (> nameEnd 0) (+ nameEnd 1) a)]
        (poolRows text n next rows))))

fn concurrencyRows text: String n: Int64 i: Int64 acc: (List Pool) -> (List Pool)
  (if (>= i n) (listSortBy (fn [p] p.name) (listReverse acc))
    (let [markerText "os.environ.get("
          found (mt (stringIndexOf (c/sliceOf text i n) markerText) ((some p) (+ i p)) (none -1))]
      (if (< found 0) (listSortBy (fn [p] p.name) (listReverse acc))
        (let [after (+ found (stringLength markerText))
              dq (optionOr (stringIndexOf (c/sliceOf text after n) "\"") -1)
              sq (optionOr (stringIndexOf (c/sliceOf text after n) "'") -1)
              q (if (< dq 0) sq (if (< sq 0) dq (min dq sq)))
              quote (if (= q dq) "\"" "'")
              envStart (+ after q 1)
              envEnd (if (< q 0) -1 (mt (stringIndexOf (c/sliceOf text envStart n) quote) ((some p) (+ envStart p)) (none -1)))
              comma (if (< envEnd 0) -1 (mt (stringIndexOf (c/sliceOf text envEnd n) ",") ((some p) (+ envEnd p)) (none -1)))
              close (if (< comma 0) -1 (mt (stringIndexOf (c/sliceOf text comma n) ")") ((some p) (+ comma p)) (none -1)))
              env (if (< envEnd 0) "" (c/sliceOf text envStart envEnd))
              suffix "_CONCURRENCY"
              envLen (stringLength env)
              suffixLen (stringLength suffix)
              isConcurrency (and (>= envLen suffixLen) (= (c/sliceOf env (- envLen suffixLen) envLen) suffix))
              poolName (if isConcurrency (stringLower (c/sliceOf env 0 (- envLen suffixLen))) "")
              size (if (< close 0) -1 (optionOr (stringToInt64 (stringTrim (c/sliceOf text (+ comma 1) close))) -1))
              rows (if (and isConcurrency (not (stringEmpty? poolName)) (>= size 0)) (cons (Pool :name poolName :size size) acc) acc)
              next (if (>= close 0) (+ close 1) (+ after 1))]
          (concurrencyRows text n next rows)))))

fn ! getGatewayPools rootDir: String -> (Result (List Pool) String)
  (mt (fileReadString (str rootDir "/bin/asl-gateway"))
    ((err e) (err e))
    ((ok text)
      (let [pools (poolRows text (stringLength text) 0 (list))]
        (ok (if (listEmpty? pools) (concurrencyRows text (stringLength text) 0 (list)) pools)))))

fn backendData! rootDir: String -> (Result (List Backend) String)
  (ok (map (fn [name] (Backend :name name :defaultModel (if (= name "agy") (m/defaultModel name) "")))
    (listAppend (m/supportedBackends) (pv/testBackendPrefixes))))

fn shapeFor name: String shapes: (List (Pair String String)) -> String
  (mt (listHead shapes)
    ((none) "(:escalate :reason s)")
    ((some entry) (if (= (pairFirst entry) name) (pairSecond entry) (shapeFor name (optionOr (listTail shapes) (list))))))

fn deliverableData! rootDir: String -> (Result (Pair (List String) String) String)
  (ok (pair (ex/deliverables) (shapeFor "escalate" (ex/opShapes))))

fn ! buildCard rootDir: String -> (Result AgentCard String)
  (mt (getAllowlist rootDir)
    ((err e) (err e))
    ((ok allowlist)
      (mt (deliverableData! rootDir)
        ((err e) (err e))
        ((ok loopFacts)
          (mt (backendData! rootDir)
            ((err e) (err e))
            ((ok backends)
              (mt (getGatewayPools rootDir)
                ((err e) (err e))
                ((ok gatewayPools)
                  (mt (m/receiptFieldNames rootDir)
                    ((err e) (err e))
                    ((ok receiptFields)
                      (ok (AgentCard
                        :name "Leon"
                        :acceptedKeys (m/acceptedKeys)
                        :allowlist allowlist
                        :deliverables (pairFirst loopFacts)
                        :backends backends
                        :gatewayPools gatewayPools
                        :receiptFields receiptFields
                        :escalateForm (pairSecond loopFacts)))))))))))))

fn formatCardAsn card: AgentCard -> String
  (let [lines (list
          "(:agentCard"
          (str "  :agent \"" card.name "\"")
          (str "  :acceptedKeys (" (stringJoin (map (fn [k] (str "\"" k "\"")) card.acceptedKeys) " ") ")")
          (str "  :allowlist (" (stringJoin (map (fn [op] (str "\"" op "\"")) card.allowlist) " ") ")")
          (str "  :deliverables (" (stringJoin (map (fn [d] (str ":" d)) card.deliverables) " ") ")")
          "  :backends ("
          (stringJoin (map (fn [b]
                            (if (stringEmpty? b.defaultModel)
                              (str "    (:backend \"" b.name "\")")
                              (str "    (:backend \"" b.name "\" :defaultModel \"" b.defaultModel "\")")))
                          card.backends) "\n")
          "  )"
          "  :gatewayPools ("
          (stringJoin (map (fn [p] (str "    (:pool \"" p.name "\" :size " (stringFromInt64 p.size) ")"))
                          card.gatewayPools) "\n")
          "  )"
          (str "  :receiptFields (" (stringJoin (map (fn [f] (str "\"" f "\"")) card.receiptFields) " ") ")")
          (str "  :escalateForm \"" (stringReplace (stringReplace card.escalateForm "\\" "\\\\") "\"" "\\\"") "\"")
          ")")]
    (stringJoin lines "\n"))

fn ! main argv: (List String) -> (Result Int64 String)
  (let [root (if (and (not (listEmpty? argv)) (not (stringStartsWith? (c/firstOf argv) "-")))
               (c/firstOf argv)
               (optionOr (envGet "ASL_ROOT_DIR") "."))
        cardResult (buildCard root)]
    (mt cardResult
      ((err e) (err e))
      ((ok card)
        (do
          (println (formatCardAsn card))
          (ok 0)))))
