(module asl-store/conform
  :x [Step Script ScriptRun stepOp stepFault parseScript runPure runEff failureOf]
  :i [(asl-store/types :a ty) (asl-store/wire :a w) (asl-store/mem :a mem)])

; (:m :ref VS-CORE :do "a conformance script is data: a header (:script :id ID :checks N) and one form per step, (:step OP REPLY) runs an op and matches its printed reply, (:fault NAME ARG) asks an effectful harness to damage its storage; N is the number of :step forms and a runner that executes fewer or more is red")
(enum Step (:c stepOp [(op ty/Op) (expect w/Sx) (src String)]) (:c stepFault [(name String) (arg String)]))

(schema Script (:f id String) (:f declared Int64) (:f steps (List Step)))

(schema ScriptRun (:f id String) (:f declared Int64) (:f executed Int64) (:f failures (List String)))

fn kwValue items: (List w/Sx) key: String -> String
  (cond
    ((listEmpty? items) "")
    ((= (w/leafText (w/headOr items)) key) (w/leafText (w/headOr (w/tailOr items))))
    (else (kwValue (w/tailOr items) key)))

; (:m :ref VS-CORE :do "an expected reply must be a list whose head is a literal atom, so a step can never be satisfied by a bare _ or by any reply at all")
fn literalHead? x: w/Sx -> Bool
  (match x
    ((w/sxList es) (match (w/headOr es) ((w/sxAtom t) (not (= t "_"))) (_ false)))
    (_ false))

fn stepOf x: w/Sx -> (Result Step String)
  (match x
    ((w/sxList items)
      (let [(head (w/leafText (w/headOr items)))]
        (cond
          ((and (= head ":step") (and (= (listLength items) 3) (literalHead? (w/headOr (w/tailOr (w/tailOr items))))))
            (match (w/opParse (w/headOr (w/tailOr items)))
              ((ok op) (ok (stepOp op (w/headOr (w/tailOr (w/tailOr items))) (w/sxShow (w/headOr (w/tailOr items))))))
              ((err e) (err e))))
          ((and (= head ":fault") (= (listLength items) 3))
            (ok (stepFault (w/leafText (w/headOr (w/tailOr items))) (w/leafText (w/headOr (w/tailOr (w/tailOr items)))))))
          (else (err (str "bad script form " (w/sxShow x)))))))
    (_ (err "script form is not a list")))

fn stepsOf forms: (List w/Sx) acc: (List Step) -> (Result (List Step) String)
  (if (listEmpty? forms)
    (ok (listReverse acc))
    (match (stepOf (w/headOr forms))
      ((err e) (err e))
      ((ok s) (stepsOf (w/tailOr forms) (cons s acc)))))

fn stepCount steps: (List Step) -> Int64
  (listLength (filter (fn [(s Step)] -> Bool (match s ((stepOp _ _ _) true) ((stepFault _ _) false))) steps))

; (:m :ref VS-CORE :do "the :checks of the header must equal the number of :step forms, so a script that was edited without its count is refused at parse time")
fn parseScript text: String -> (Result Script String)
  (match (w/sxRead text)
    ((err e) (err e))
    ((ok forms)
      (match (w/headOr forms)
        ((w/sxList head)
          (if (= (w/leafText (w/headOr head)) ":script")
            (match (stepsOf (w/tailOr forms) (list))
              ((err e) (err e))
              ((ok steps)
                (let [(id (kwValue head ":id")) (declared (optionOr (stringToInt64 (kwValue head ":checks")) -1))]
                  (if (and (not (stringEmpty? id)) (= declared (stepCount steps)))
                    (ok (Script :id id :declared declared :steps steps))
                    (err (str "script " id " declares " (stringFromInt64 declared) " checks, has " (stringFromInt64 (stepCount steps))))))))
            (err "first form is not (:script ...)")))
        (_ (err "empty script")))))

fn failureOf id: String n: Int64 src: String expect: w/Sx reply: ty/Reply -> (Option String)
  (let [(actual (w/replyShow reply))]
    (if (w/sxMatch expect actual)
      (none)
      (some (str id " step " (stringFromInt64 n) " " src ": expected " (w/sxShow expect) " got " (w/sxShow actual)))))

fn addFailure fs: (List String) f: (Option String) -> (List String)
  (match f ((some t) (listAppend fs (list t))) ((none) fs))

fn restOf steps: (List Step) -> (List Step)
  (optionOr (listTail steps) (list))

fn firstOf steps: (List Step) -> Step
  (optionOr (listHead steps) (stepFault "" ""))

fn pureLoop id: String steps: (List Step) st: mem/MemState step: (fn [mem/MemState ty/Op] -> (Pair mem/MemState ty/Reply)) n: Int64 fs: (List String) -> (Pair Int64 (List String))
  (if (listEmpty? steps)
    (pair n fs)
    (match (firstOf steps)
      ((stepOp op expect src)
        (let [(r (step st op))]
          (pureLoop id (restOf steps) (pairFirst r) step (+ n 1) (addFailure fs (failureOf id (+ n 1) src expect (pairSecond r))))))
      ((stepFault name _) (pureLoop id (restOf steps) st step n (listAppend fs (list (str id ": fault " name " has no meaning for a pure adapter")))))))

; (:m :ref VS-CORE :do "run a script against a pure adapter step from an empty state; executed counts the :step forms actually run so a gate can compare it with declared")
fn runPure script: Script step: (fn [mem/MemState ty/Op] -> (Pair mem/MemState ty/Reply)) -> ScriptRun
  (let [(r (pureLoop script.id script.steps (mem/memEmpty) step 0 (list)))]
    (ScriptRun :id script.id :declared script.declared :executed (pairFirst r) :failures (pairSecond r)))

fn ! effLoop id: String steps: (List Step) call: (fn ! [ty/Op] -> ty/Reply) fault: (fn ! [String String] -> Bool) n: Int64 fs: (List String) -> (Pair Int64 (List String))
  (if (listEmpty? steps)
    (pair n fs)
    (match (firstOf steps)
      ((stepOp op expect src)
        (let [(reply (call op))]
          (effLoop id (restOf steps) call fault (+ n 1) (addFailure fs (failureOf id (+ n 1) src expect reply)))))
      ((stepFault name arg)
        (if (fault name arg)
          (effLoop id (restOf steps) call fault n fs)
          (effLoop id (restOf steps) call fault n (listAppend fs (list (str id ": fault " name " refused"))))))))

; (:m :ref VS-CORE :do "run a script against an effectful adapter, a call fn per op and a fault fn that damages the adapter's own storage; the adapter must hold a fresh empty store")
fn ! runEff script: Script call: (fn ! [ty/Op] -> ty/Reply) fault: (fn ! [String String] -> Bool) -> ScriptRun
  (let [(r (effLoop script.id script.steps call fault 0 (list)))]
    (ScriptRun :id script.id :declared script.declared :executed (pairFirst r) :failures (pairSecond r)))
