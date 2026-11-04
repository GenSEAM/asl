(module aslAgent/poolOps
  :x [PoolSelf poolSelf poolSelfOf formField formBody askReceipt! servePending! answerReceipt! askWaitMs poolOp? poolOpReceipt!]
  :i [(aslAgent/poolChannel :a ch)
      (aslAgent/core :a c)])

; (:m :ref LEON-POOL-ASK-OP :do "Leon's side of the pool channel, as reply ops: (:ask :to i :body (...)) blocks the turn until task i answers and returns the answer as the op receipt; between turns servePending! hands the asks other tasks sent this one to the model as a (:poolAsks ...) observation, and (:answer :to i :body (...)) or (:answer :id \"...\" :body (...)) posts the reply back; a task outside a pool gets ERR_NOT_IN_POOL")
(schema PoolSelf
  (:f chan String)
  (:f idx Int64))

fn poolSelf chan: String idx: Int64 -> (Option PoolSelf)
  (if (or (stringEmpty? chan) (< idx 0)) none (some (PoolSelf :chan chan :idx idx)))

fn askWaitMs -> Int64
  60000

fn wordAt s: String i: Int64 -> String
  (let [(rest (c/sliceOf s i (stringLength s)))
        (end (fold (fn [(acc Int64) (stop String)] -> Int64 (match (stringIndexOf rest stop) ((some k) (min acc k)) ((none) acc)))
                   (stringLength rest) (list " " ")")))]
    (stringReplace (c/sliceOf rest 0 end) "\"" ""))

; (:m :ref LEON-POOL-ASK-OP :do "fields are read from the header before :body only, so a :to inside the body never names the peer")
fn formField form: String key: String -> String
  (let [(head (match (stringIndexOf form " :body ") ((some b) (c/sliceOf form 0 b)) ((none) form)))]
    (match (stringIndexOf (str head " ") (str " :" key " "))
      ((none) "")
      ((some i) (wordAt (str head " ") (+ i (+ (stringLength key) 3))))))

; (:m :ref LEON-POOL-ASK-OP :do "the pool names a task's channel and index on its (:agent ...) form as :poolChan and :poolIdx; a form without them is not in a pool")
fn poolSelfOf agentForm: String -> (Option PoolSelf)
  (poolSelf (formField agentForm "poolChan") (optionOr (stringToInt64 (formField agentForm "poolIdx")) -1))

fn bodyEnd cs: (List String) i: Int64 depth: Int64 inStr: Bool esc: Bool -> Int64
  (match (listGet cs i)
    ((none) -1)
    ((some ch)
      (cond
        (esc (bodyEnd cs (+ i 1) depth inStr false))
        ((and inStr (= ch "\\")) (bodyEnd cs (+ i 1) depth true true))
        ((= ch "\"") (bodyEnd cs (+ i 1) depth (not inStr) false))
        (inStr (bodyEnd cs (+ i 1) depth true false))
        ((= ch "(") (bodyEnd cs (+ i 1) (+ depth 1) false false))
        ((= ch ")") (if (= depth 1) i (bodyEnd cs (+ i 1) (- depth 1) false false)))
        (else (bodyEnd cs (+ i 1) depth false false)))))

; (:m :ref LEON-POOL-ASK-OP :do "the body is the balanced form after :body, read from the op's own form text, so a nested list survives whatever parseKv makes of it")
fn formBody form: String -> (Option String)
  (match (stringIndexOf form " :body (")
    ((none) none)
    ((some i)
      (let [(cs (stringChars (c/sliceOf form (+ i 7) (stringLength form))))
            (e (bodyEnd cs 0 0 false false))]
        (if (< e 0) none (some (stringJoin (listTake cs (+ e 1)) ""))))))

fn rejected op: String to: String code: String -> String
  (str "(:" op (if (stringEmpty? to) "" (str " :to " to)) " :status :rejected :error " code ")")

fn ! askReceipt! self: (Option PoolSelf) form: String -> String
  (let [(to (formField form "to"))
        (wait (optionOr (stringToInt64 (formField form "waitMs")) (askWaitMs)))]
    (match self
      ((none) (rejected "ask" to "ERR_NOT_IN_POOL"))
      ((some me)
        (match (stringToInt64 to)
          ((none) (rejected "ask" to "ERR_ASK_NO_PEER"))
          ((some peer)
            (match (formBody form)
              ((none) (rejected "ask" to "ERR_ASK_NOT_ASN"))
              ((some body)
                (match (ch/ask! me.chan me.idx peer body wait)
                  ((ok answer) (str "(:ask :to " to " :status :ok :answer " answer ")"))
                  ((err code) (rejected "ask" to code))))))))))

fn servedDir me: PoolSelf -> String
  (str (ch/inboxDir me.chan me.idx) ".served")

; (:m :ref LEON-POOL-ASK-OP :do "the between-turn hook: asks waiting in this task's inbox move to its served dir, where an (:answer) op finds them, and come back as one ASN observation line, empty when there are none")
fn ! servePending! self: (Option PoolSelf) -> String
  (match self
    ((none) "")
    ((some me)
      (let [(qs (ch/asks! me.chan me.idx))
            (_ (if (listEmpty? qs) true (ok? (dirCreate (servedDir me)))))
            (kept (filter (fn [(q ch/PoolMsg)] -> Bool (ok? (fileWrite (str (servedDir me) "/" q.id ".msg") (ch/msgLine q)))) qs))]
        (if (listEmpty? kept)
          ""
          (str "(:poolAsks ("
               (stringJoin (map (fn [(q ch/PoolMsg)] -> String (str "(:ask :id \"" q.id "\" :from " (stringFromInt64 q.from) " :body " q.body ")")) kept) " ")
               ") :reply \"(:answer :to <from> :body (...))\")")))))

fn ! served! me: PoolSelf -> (List ch/PoolMsg)
  (fold (fn [(acc (List ch/PoolMsg)) (n String)] -> (List ch/PoolMsg)
          (match (ch/parseMsg (resultOr (fileReadString (str (servedDir me) "/" n)) "")) ((some q) (listAppend acc (list q))) ((none) acc)))
        (list) (listSort (filter (fn [(n String)] -> Bool (stringEndsWith? n ".msg")) (resultOr (dirList (servedDir me)) (list)))))

fn ! answerReceipt! self: (Option PoolSelf) form: String -> String
  (let [(id (formField form "id"))
        (to (formField form "to"))]
    (match self
      ((none) (rejected "answer" to "ERR_NOT_IN_POOL"))
      ((some me)
        (let [(qs (served! me))
              (pick (listHead (filter (fn [(q ch/PoolMsg)] -> Bool (if (stringEmpty? id) (= (stringFromInt64 q.from) to) (= q.id id))) qs)))]
          (match pick
            ((none) (rejected "answer" to "ERR_ANSWER_NO_ASK"))
            ((some q)
              (match (formBody form)
                ((none) (rejected "answer" to "ERR_ASK_NOT_ASN"))
                ((some body)
                  (match (ch/answer! me.chan me.idx q body)
                    ((ok _) (do (pathRemove (str (servedDir me) "/" q.id ".msg"))
                                (str "(:answer :id \"" q.id "\" :to " (stringFromInt64 q.from) " :status :ok)")))
                    ((err code) (rejected "answer" to code)))))))))))

fn opName op: (List (Pair String c/KvVal)) -> String
  (match (c/dictOr op "op") ((c/kvStr t) t) ((c/kvInt t) t))

fn opForm op: (List (Pair String c/KvVal)) -> String
  (match (c/dictOr op "form") ((c/kvStr t) t) ((c/kvInt t) t))

; (:m :ref LEON-POOL-ASK-OP :do "the reply-op dispatch: a parsed (:ask) or (:answer) op from c/parseReply is a pool op, run here instead of by exec, and its receipt is one ASN form")
fn poolOp? op: (List (Pair String c/KvVal)) -> Bool
  (listContains? (list "ask" "answer") (opName op))

fn ! poolOpReceipt! self: (Option PoolSelf) op: (List (Pair String c/KvVal)) -> String
  (if (= (opName op) "ask") (askReceipt! self (opForm op)) (answerReceipt! self (opForm op)))
