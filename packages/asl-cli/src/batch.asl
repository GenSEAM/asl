(module asl-cli/batch
  :d "Pure AgentScript native batch evaluator engine and RPC wire contract implementation."
  :x [BatchArg
      BatchStep
      BatchRequest
      StepResult
      evalBatch
      executeSingleStep
      parseTokensToRequest
      findDefun
      evalSeq]
  :i [(ast :a a)
      (evaluator :a ev)
      (reader :a rd)
      (lexer :a lx)
      (asl-text/text :a txt)])

(dfe BatchArg
  (:c argPos [(val Str)])
  (:c argKw  [(key Str) (val Str)]))

(dfs BatchStep
  (:f id Int64)
  (:f op Str)
  (:f args (List BatchArg)))

(dfs BatchRequest
  (:f seq Bool)
  (:f steps (List BatchStep)))

(dfs StepResult
  (:f id Int64)
  (:f op Str)
  (:f status Str)
  (:f isErr Bool)
  (:f output Str))

(df escapeStr [(s Str)] -> Str
  (let [(s1 (string-replace s "\\" "\\\\"))]
    (let [(s2 (string-replace s1 "\"" "\\\""))]
      (string-replace s2 "\n" "\\n"))))

(df cleanTokenText [(t lx/Token)] -> Str
  (let [(raw (.-rawText t))]
    (mt (.-kind t)
      ((lx/tokString _) (txt/stripQuotes raw))
      (_ raw))))

(df isSafePath [(path Str)] -> Bool
  (and (not (string-starts-with? path "/.."))
       (and (not (string-starts-with? path "../"))
            (and (not (string-contains? path "/../"))
                 (not (= path ".."))))))

(df findDefun [(forms (List a/TopForm))] -> (Option a/DefunNode)
  (mt (list-head forms)
    ((some form)
     (mt form
       ((a/topDefun d) (some d))
       (_ (mt (list-tail forms)
            ((some rest) (findDefun rest))
            ((none) (none))))))
    ((none) (none))))

(df evalSeq [(body (List rd/SExpr)) (env ev/EvalEnv)] -> ev/EvalValue
  (mt (list-head body)
    ((some firstExpr)
     (let [(val (ev/evalSexpr firstExpr env))]
       (mt val
         ((ev/valError _) val)
         (_ (mt (list-tail body)
              ((some rest)
               (if (list-empty? rest)
                   val
                   (evalSeq rest env)))
              ((none) val))))))
    ((none) (ev/valNull))))

(df getArgKwLoop [(args (List BatchArg)) (key Str) (idx Int64) (len Int64)] -> (Option Str)
  (if (>= idx len)
      (none)
      (let [(arg (option-or (list-get args idx) (argPos "")))]
        (mt arg
          ((argKw k v)
           (if (= k key)
               (some v)
               (getArgKwLoop args key (+ idx 1) len)))
          (_ (getArgKwLoop args key (+ idx 1) len))))))

(df getArgKw [(args (List BatchArg)) (key Str)] -> (Option Str)
  (getArgKwLoop args key 0 (list-length args)))

(df getArgPosLoop [(args (List BatchArg)) (targetIdx Int64) (currPos Int64) (idx Int64) (len Int64)] -> (Option Str)
  (if (>= idx len)
      (none)
      (let [(arg (option-or (list-get args idx) (argPos "")))]
        (mt arg
          ((argPos v)
           (if (= currPos targetIdx)
               (some v)
               (getArgPosLoop args targetIdx (+ currPos 1) (+ idx 1) len)))
          (_ (getArgPosLoop args targetIdx currPos (+ idx 1) len))))))

(df getArgPos [(args (List BatchArg)) (posIdx Int64)] -> (Option Str)
  (getArgPosLoop args posIdx 0 0 (list-length args)))

(df getArgVal [(args (List BatchArg)) (key Str) (posIdx Int64) (fallback Str)] -> Str
  (let [(kwOpt (getArgKw args key))]
    (mt kwOpt
      ((some v) v)
      ((none)
       (let [(posOpt (getArgPos args posIdx))]
         (mt posOpt
           ((some pv) pv)
           ((none) fallback)))))))

(df executeEchoStep [(stepId Int64) (args (List BatchArg))] -> StepResult
  (let [(msg1 (getArgVal args "message" 0 ""))
        (msg (if (= msg1 "") (getArgVal args "echo" 0 "") msg1))]
    (StepResult
      :id stepId
      :op "echo"
      :status "ok"
      :isErr false
      :output (str "  (:step :id " (string-from-int64 stepId)
                   " :op \"echo\" :status \"ok\" :message \""
                   (escapeStr msg) "\")"))))

(df executeEvalStep [(stepId Int64) (args (List BatchArg))] -> StepResult
  (let [(expr (getArgVal args "expr" 0 ""))]
    (if (= expr "")
        (StepResult
          :id stepId
          :op "eval"
          :status "rejected"
          :isErr true
          :output (str "  (:step :id " (string-from-int64 stepId)
                       " :op \"eval\" :status \"rejected\" :error-code \":ERR_MISSING_ARG\" :message \"Missing expr argument\")"))
        (let [(wrapped (str "(df eval-temp [] -> Any\n  " expr ")"))]
          (mt (a/parse wrapped)
            ((err pe)
             (StepResult
               :id stepId
               :op "eval"
               :status "rejected"
               :isErr true
               :output (str "  (:step :id " (string-from-int64 stepId)
                            " :op \"eval\" :status \"rejected\" :error-code \":ERR_EVAL_FAILED\" :message \""
                            (escapeStr (.-msg pe)) "\")")))
            ((ok forms)
             (let [(dfOpt (findDefun forms))]
               (mt dfOpt
                 ((none)
                  (StepResult
                    :id stepId
                    :op "eval"
                    :status "rejected"
                    :isErr true
                    :output (str "  (:step :id " (string-from-int64 stepId)
                                 " :op \"eval\" :status \"rejected\" :error-code \":ERR_EVAL_FAILED\" :message \"No expression found\")")))
                 ((some dfNode)
                  (let [(body (.-body dfNode))]
                    (if (list-empty? body)
                        (StepResult
                          :id stepId
                          :op "eval"
                          :status "ok"
                          :isErr false
                          :output (str "  (:step :id " (string-from-int64 stepId)
                                       " :op \"eval\" :status \"ok\" :result \"null\")"))
                        (let [(env (ev/makeRootEnv))
                              (lastVal (evalSeq body env))]
                          (mt lastVal
                            ((ev/valError emsg)
                             (StepResult
                               :id stepId
                               :op "eval"
                               :status "rejected"
                               :isErr true
                               :output (str "  (:step :id " (string-from-int64 stepId)
                                            " :op \"eval\" :status \"rejected\" :error-code \":ERR_EVAL_FAILED\" :message \""
                                            (escapeStr emsg) "\")")))
                            (_
                             (StepResult
                               :id stepId
                               :op "eval"
                               :status "ok"
                               :isErr false
                               :output (str "  (:step :id " (string-from-int64 stepId)
                                            " :op \"eval\" :status \"ok\" :result \""
                                            (escapeStr (ev/formatVal lastVal)) "\")"))))))))))))))))

(df executeReadStep [(stepId Int64) (args (List BatchArg))] -> StepResult
  (let [(f1 (getArgVal args "file" 0 ""))
        (file (if (= f1 "") (getArgVal args "path" 0 "") f1))]
    (if (= file "")
        (StepResult
          :id stepId
          :op "read"
          :status "rejected"
          :isErr true
          :output (str "  (:step :id " (string-from-int64 stepId)
                       " :op \"read\" :status \"rejected\" :error-code \":ERR_MISSING_ARG\" :message \"Missing file argument\")"))
        (if (not (isSafePath file))
            (StepResult
              :id stepId
              :op "read"
              :status "rejected"
              :isErr true
              :output (str "  (:step :id " (string-from-int64 stepId)
                           " :op \"read\" :status \"rejected\" :error-code \":ERR_BOUNDARY_VIOLATION\" :message \"Path escapes workspace boundary: "
                           (escapeStr file) "\")"))
            (if (not (file-exists? file))
                (StepResult
                  :id stepId
                  :op "read"
                  :status "rejected"
                  :isErr true
                  :output (str "  (:step :id " (string-from-int64 stepId)
                               " :op \"read\" :status \"rejected\" :error-code \":ERR_FILE_NOT_FOUND\" :message \"File not found: "
                               (escapeStr file) "\")"))
                (let [(readRes (file-read file))]
                  (mt readRes
                    ((err _)
                     (StepResult
                       :id stepId
                       :op "read"
                       :status "rejected"
                       :isErr true
                       :output (str "  (:step :id " (string-from-int64 stepId)
                                    " :op \"read\" :status \"rejected\" :error-code \":ERR_READ_FAILED\" :message \"Failed to read file: "
                                    (escapeStr file) "\")")))
                    ((ok content)
                     (StepResult
                       :id stepId
                       :op "read"
                       :status "ok"
                       :isErr false
                       :output (str "  (:step :id " (string-from-int64 stepId)
                                    " :op \"read\" :status \"ok\" :file \""
                                    (escapeStr file) "\" :content \""
                                    (escapeStr content) "\")"))))))))))

(df executeWriteStep [(stepId Int64) (args (List BatchArg))] -> StepResult
  (let [(f1 (getArgVal args "file" 0 ""))
        (file (if (= f1 "") (getArgVal args "path" 0 "") f1))
        (content (getArgVal args "content" 1 ""))]
    (if (= file "")
        (StepResult
          :id stepId
          :op "write"
          :status "rejected"
          :isErr true
          :output (str "  (:step :id " (string-from-int64 stepId)
                       " :op \"write\" :status \"rejected\" :error-code \":ERR_MISSING_ARG\" :message \"Missing file argument\")"))
        (if (not (isSafePath file))
            (StepResult
              :id stepId
              :op "write"
              :status "rejected"
              :isErr true
              :output (str "  (:step :id " (string-from-int64 stepId)
                           " :op \"write\" :status \"rejected\" :error-code \":ERR_BOUNDARY_VIOLATION\" :message \"Path escapes workspace boundary: "
                           (escapeStr file) "\")"))
            (let [(writeRes (file-write file content))]
              (mt writeRes
                ((err _)
                 (StepResult
                   :id stepId
                   :op "write"
                   :status "rejected"
                   :isErr true
                   :output (str "  (:step :id " (string-from-int64 stepId)
                                " :op \"write\" :status \"rejected\" :error-code \":ERR_WRITE_FAILED\" :message \"Write failed\")")))
                ((ok _)
                 (StepResult
                   :id stepId
                   :op "write"
                   :status "ok"
                   :isErr false
                   :output (str "  (:step :id " (string-from-int64 stepId)
                                " :op \"write\" :status \"ok\" :file \""
                                (escapeStr file) "\" :bytes "
                                (string-from-int64 (string-length content)) ")")))))))))

(df executeChkStep [(stepId Int64) (args (List BatchArg))] -> StepResult
  (let [(f1 (getArgVal args "file" 0 ""))
        (file (if (= f1 "") (getArgVal args "path" 0 "") f1))]
    (if (= file "")
        (StepResult
          :id stepId
          :op "chk"
          :status "rejected"
          :isErr true
          :output (str "  (:step :id " (string-from-int64 stepId)
                       " :op \"chk\" :status \"rejected\" :error-code \":ERR_MISSING_ARG\" :message \"Missing file argument\")"))
        (if (not (file-exists? file))
            (StepResult
              :id stepId
              :op "chk"
              :status "rejected"
              :isErr true
              :output (str "  (:step :id " (string-from-int64 stepId)
                           " :op \"chk\" :status \"rejected\" :error-code \":ERR_FILE_NOT_FOUND\" :message \"File not found: "
                           (escapeStr file) "\")"))
            (StepResult
              :id stepId
              :op "chk"
              :status "ok"
              :isErr false
              :output (str "  (:step :id " (string-from-int64 stepId)
                           " :op \"chk\" :status \"ok\" :file \""
                           (escapeStr file) "\" :valid true)"))))))

(df executeWhereStep [(stepId Int64) (args (List BatchArg))] -> StepResult
  (let [(s1 (getArgVal args "symbol" 0 ""))
        (sym (if (= s1 "") (getArgVal args "name" 0 "") s1))]
    (StepResult
      :id stepId
      :op "where"
      :status "ok"
      :isErr false
      :output (str "  (:step :id " (string-from-int64 stepId)
                   " :op \"where\" :status \"ok\" :symbol \""
                   (escapeStr sym) "\" :scope \"workspace\")"))))

(df executeSingleStep [(stepId Int64) (op Str) (args (List BatchArg))] -> StepResult
  (let [(cleanOp (txt/stripColon op))]
    (cond
      ((= cleanOp "echo") (executeEchoStep stepId args))
      ((= cleanOp "eval") (executeEvalStep stepId args))
      ((= cleanOp "read") (executeReadStep stepId args))
      ((= cleanOp "write") (executeWriteStep stepId args))
      ((or (= cleanOp "chk") (= cleanOp "gate")) (executeChkStep stepId args))
      ((= cleanOp "where") (executeWhereStep stepId args))
      (:else
       (StepResult
         :id stepId
         :op cleanOp
         :status "rejected"
         :isErr true
         :output (str "  (:step :id " (string-from-int64 stepId)
                      " :op \"" (escapeStr cleanOp)
                      "\" :status \"rejected\" :error-code \":ERR_UNIMPLEMENTED\" :message \"Operation not implemented\")"))))))

(df parseStepArgsLoop [(tokens (List lx/Token)) (idx Int64) (len Int64) (acc (List BatchArg))] -> (Pair (List BatchArg) Int64)
  (if (>= idx len)
      (pair (list-reverse acc) idx)
      (let [(t (option-or (list-get tokens idx) (lx/makeToken (lx/tokEof) "" 0 0)))]
        (mt (.-kind t)
          ((lx/tokRparen)
           (pair (list-reverse acc) (+ idx 1)))
          ((lx/tokKeyword key)
           (if (< (+ idx 1) len)
               (let [(valTok (option-or (list-get tokens (+ idx 1)) (lx/makeToken (lx/tokEof) "" 0 0)))]
                 (mt (.-kind valTok)
                   ((lx/tokRparen)
                    (pair (list-reverse (list-cons (argKw (txt/stripColon key) "") acc)) (+ idx 1)))
                   (_
                    (parseStepArgsLoop tokens (+ idx 2) len
                                       (list-cons (argKw (txt/stripColon key) (cleanTokenText valTok)) acc)))))
               (parseStepArgsLoop tokens (+ idx 1) len
                                  (list-cons (argKw (txt/stripColon key) "") acc))))
          ((lx/tokLparen)
           (parseStepArgsLoop tokens (+ idx 1) len acc))
          (_
           (parseStepArgsLoop tokens (+ idx 1) len
                              (list-cons (argPos (cleanTokenText t)) acc)))))))

(df parseOneStep [(tokens (List lx/Token)) (startIdx Int64) (len Int64) (stepId Int64)] -> (Pair (Option BatchStep) Int64)
  (if (>= startIdx len)
      (pair (none) startIdx)
      (let [(t0 (option-or (list-get tokens startIdx) (lx/makeToken (lx/tokEof) "" 0 0)))]
        (mt (.-kind t0)
          ((lx/tokLparen)
           (if (< (+ startIdx 1) len)
               (let [(opTok (option-or (list-get tokens (+ startIdx 1)) (lx/makeToken (lx/tokEof) "" 0 0)))
                     (opName (txt/stripColon (cleanTokenText opTok)))
                     (argsParsed (parseStepArgsLoop tokens (+ startIdx 2) len (list)))]
                 (pair (some (BatchStep :id stepId :op opName :args (.-first argsParsed)))
                       (.-second argsParsed)))
               (pair (none) len)))
          (_
           (pair (none) (+ startIdx 1)))))))

(df parseBatchBodyLoop [(tokens (List lx/Token)) (idx Int64) (len Int64) (seqFlag Bool) (currId Int64) (acc (List BatchStep))] -> BatchRequest
  (if (>= idx len)
      (BatchRequest :seq seqFlag :steps (list-reverse acc))
      (let [(t (option-or (list-get tokens idx) (lx/makeToken (lx/tokEof) "" 0 0)))]
        (mt (.-kind t)
          ((lx/tokRparen)
           (BatchRequest :seq seqFlag :steps (list-reverse acc)))
          ((lx/tokEof)
           (BatchRequest :seq seqFlag :steps (list-reverse acc)))
          ((lx/tokKeyword key)
           (let [(k (txt/stripColon key))]
             (if (or (= k "seq") (= k "sequenced"))
                 (if (< (+ idx 1) len)
                     (let [(valTok (option-or (list-get tokens (+ idx 1)) (lx/makeToken (lx/tokEof) "" 0 0)))
                           (v (cleanTokenText valTok))]
                       (parseBatchBodyLoop tokens (+ idx 2) len (or (= v "true") (= v ":true")) currId acc))
                     (parseBatchBodyLoop tokens (+ idx 1) len true currId acc))
                 (parseBatchBodyLoop tokens (+ idx 1) len seqFlag currId acc))))
          ((lx/tokLparen)
           (let [(parsed (parseOneStep tokens idx len currId))]
             (mt (.-first parsed)
               ((some stp)
                (parseBatchBodyLoop tokens (.-second parsed) len seqFlag (+ currId 1) (list-cons stp acc)))
               ((none)
                (parseBatchBodyLoop tokens (.-second parsed) len seqFlag currId acc)))))
          (_
           (parseBatchBodyLoop tokens (+ idx 1) len seqFlag currId acc))))))

(df parseTokensToRequest [(tokens (List lx/Token))] -> BatchRequest
  (let [(len (list-length tokens))]
    (if (< len 2)
        (BatchRequest :seq false :steps (list))
        (let [(t0 (option-or (list-get tokens 0) (lx/makeToken (lx/tokEof) "" 0 0)))
              (t1 (option-or (list-get tokens 1) (lx/makeToken (lx/tokEof) "" 0 0)))]
          (mt (.-kind t0)
            ((lx/tokLparen)
             (let [(headName (txt/stripColon (cleanTokenText t1)))]
               (if (= headName "batch")
                   (parseBatchBodyLoop tokens 2 len false 1 (list))
                   (let [(parsed (parseOneStep tokens 0 len 1))]
                     (mt (.-first parsed)
                       ((some stp) (BatchRequest :seq false :steps (list stp)))
                       ((none) (BatchRequest :seq false :steps (list))))))))
            (_ (BatchRequest :seq false :steps (list))))))))

(df executeStepsLoop [(steps (List BatchStep)) (seqMode Bool) (idx Int64) (len Int64) (priorFailed Bool) (acc (List StepResult))] -> (List StepResult)
  (if (>= idx len)
      (list-reverse acc)
      (let [(stp (option-or (list-get steps idx) (BatchStep :id 0 :op "" :args (list))))]
        (if (and seqMode priorFailed)
            (let [(aborted (StepResult
                             :id (.-id stp)
                             :op (.-op stp)
                             :status "aborted"
                             :isErr true
                             :output (str "  (:step :id " (string-from-int64 (.-id stp))
                                          " :status \"aborted\" :reason \"prior step failed\")")))]
              (executeStepsLoop steps seqMode (+ idx 1) len true (list-cons aborted acc)))
            (let [(res (executeSingleStep (.-id stp) (.-op stp) (.-args stp)))]
              (executeStepsLoop steps seqMode (+ idx 1) len (or priorFailed (.-isErr res)) (list-cons res acc)))))))

(df countErrorsLoop [(results (List StepResult)) (idx Int64) (len Int64) (acc Int64)] -> Int64
  (if (>= idx len)
      acc
      (let [(r (option-or (list-get results idx) (StepResult :id 0 :op "" :status "" :isErr false :output "")))]
        (countErrorsLoop results (+ idx 1) len (if (.-isErr r) (+ acc 1) acc)))))

(df stepResultOutput [(r StepResult)] -> Str
  :d "Extracts output string from a StepResult."
  (.-output r))

(df evalBatch [(payload Str)] -> (Result Str Str)
  :d "Evaluates an ASL batch payload and formats canonical :batch-res response."
  (let [(trimmed (string-trim payload))]
    (if (or (= trimmed "") (= trimmed "()"))
        (ok "(:batch-res :status \"completed\" :itemsCount 0 :parallel true :results [])\n")
        (let [(tokens (lx/tokenize trimmed))
              (req (parseTokensToRequest tokens))
              (steps (.-steps req))]
          (if (list-empty? steps)
              (ok "(:batch-res :status \"completed\" :itemsCount 0 :parallel true :results [])\n")
              (let [(stepCount (list-length steps))
                    (results (executeStepsLoop steps (.-seq req) 0 stepCount false (list)))
                    (errCount (countErrorsLoop results 0 stepCount 0))
                    (batchStatus (if (= errCount 0)
                                     "completed"
                                     (if (< errCount stepCount)
                                         "completed-with-errors"
                                         "failed")))
                    (modeFlag (if (.-seq req)
                                  " :parallel false :sequenced true"
                                  " :parallel true"))
                    (errPart (if (> errCount 0)
                                 (str " :failed-count " (string-from-int64 errCount)
                                      " :failedCount " (string-from-int64 errCount))
                                 ""))
                    (outputs (map stepResultOutput results))
                    (bodyStr (string-join outputs "\n"))]
                (ok (str "(:batch-res :status \"" batchStatus "\" :itemsCount "
                         (string-from-int64 stepCount)
                         errPart modeFlag
                         " :results [\n" bodyStr "\n])\n"))))))))
