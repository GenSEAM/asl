(module ws/asl/tools/observe/args
  :x [Args parseArgs usageText helpText]
  :i [(ws/asl/tools/observe/common :a c)])

(schema Args
  (:f dim (Option String)) (:f scope String) (:f limit String) (:f symbol String) (:f module String)
  (:f path String) (:f spec String) (:f id String))

fn usageText -> String
  (str "usage: observe.asl [-h] --dim DIM [--scope SCOPE] [--limit LIMIT]\n"
       "                   [--symbol SYMBOL] [--module MODULE] [--path PATH]\n"
       "                   [--spec SPEC] [--id ID]\n")

fn helpText -> String
  (str (usageText) "\noptions:\n  -h, --help       show this help message and exit\n  --dim DIM\n  --scope SCOPE\n  --limit LIMIT\n"
       "  --symbol SYMBOL\n  --module MODULE\n  --path PATH\n  --spec SPEC\n  --id ID\n")

fn optionStrings -> (List String)
  (list "-h" "--help" "--dim" "--scope" "--limit" "--symbol" "--module" "--path" "--spec" "--id")

fn actionOf opt: String -> String
  (cond ((or (= opt "-h") (= opt "--help")) "help") (else (optionOr (stringSlice opt 2 (stringLength opt)) "")))

fn actionName act: String -> String
  (if (= act "help") "-h/--help" (str "--" act))

(schema Opt (:f act (Option String)) (:f spelling String) (:f sep (Option String)) (:f explicit (Option String)))

(enum Tok (:c tokArg [(s String)]) (:c tokSep [(s String)]) (:c tokOpt [(o Opt) (s String)]))

fn usageError msg: String -> c/Outcome
  (c/Outcome :out "" :err (str (usageText) "observe.asl: error: " msg "\n") :code 2)

fn partitionEq s: String -> (Pair String (Option String))
  (mt (stringIndexOf s "=")
    ((none) (pair s (none)))
    ((some i) (pair (optionOr (stringSlice s 0 i) "") (some (optionOr (stringSlice s (+ i 1) (stringLength s)) "")))))

fn negNumber? s: String -> Bool
  (let [(body (optionOr (stringSlice s 1 (stringLength s)) ""))
        (digits? (fn [(t String)] -> Bool (listAll? (fn [(ch String)] -> Bool (and (>= (charCode ch) 48) (<= (charCode ch) 57))) (stringChars t))))]
    (and (stringStartsWith? s "-")
         (or (and (not (stringEmpty? body)) (digits? body))
             (mt (stringIndexOf body ".")
               ((none) false)
               ((some i) (let [(a (optionOr (stringSlice body 0 i) "")) (b (optionOr (stringSlice body (+ i 1) (stringLength body)) ""))]
                           (and (digits? a) (not (stringEmpty? b)) (digits? b))))))))

fn optionTuples s: String -> (List Opt)
  (if (stringStartsWith? s "--")
    (let [(pe (partitionEq s))]
      (map (fn [(o String)] -> Opt (Opt :act (some (actionOf o)) :spelling o :sep (optionMap (fn [(x String)] -> String "=") (pairSecond pe)) :explicit (pairSecond pe)))
           (filter (fn [(o String)] -> Bool (stringStartsWith? o (pairFirst pe))) (optionStrings))))
    (let [(short (optionOr (stringSlice s 0 2) s)) (rest (optionOr (stringSlice s 2 (stringLength s)) ""))]
      (fold (fn [(acc (List Opt)) (o String)] -> (List Opt)
              (cond ((= o short) (listAppend acc (list (Opt :act (some (actionOf o)) :spelling o :sep (some "") :explicit (some rest)))))
                    ((stringStartsWith? o s) (listAppend acc (list (Opt :act (some (actionOf o)) :spelling o :sep (none) :explicit (none)))))
                    (else acc)))
            (list) (optionStrings))))

fn classify s: String -> (Result Tok c/Outcome)
  (cond
    ((or (stringEmpty? s) (not (stringStartsWith? s "-"))) (ok (tokArg s)))
    ((listContains? (optionStrings) s) (ok (tokOpt (Opt :act (some (actionOf s)) :spelling s :sep (none) :explicit (none)) s)))
    ((= (stringLength s) 1) (ok (tokArg s)))
    (else
      (let [(pe (partitionEq s))]
        (if (and (some? (pairSecond pe)) (listContains? (optionStrings) (pairFirst pe)))
          (ok (tokOpt (Opt :act (some (actionOf (pairFirst pe))) :spelling (pairFirst pe) :sep (some "=") :explicit (pairSecond pe)) s))
          (let [(tups (optionTuples s))]
            (cond
              ((> (listLength tups) 1)
                (err (usageError (str "ambiguous option: " s " could match " (stringJoin (map (fn [(o Opt)] -> String o.spelling) tups) ", ")))))
              ((= (listLength tups) 1) (ok (tokOpt (optionOr (listHead tups) (Opt :act (none) :spelling s :sep (none) :explicit (none))) s)))
              ((negNumber? s) (ok (tokArg s)))
              ((stringContains? s " ") (ok (tokArg s)))
              (else (ok (tokOpt (Opt :act (none) :spelling s :sep (none) :explicit (none)) s)))))))))

fn classifyAll args: (List String) acc: (List Tok) -> (Result (List Tok) c/Outcome)
  (mt (listHead args)
    ((none) (ok (listReverse acc)))
    ((some a)
      (if (= a "--")
        (ok (listAppend (listReverse acc) (cons (tokSep a) (map (fn [(x String)] -> Tok (tokArg x)) (optionOr (listTail args) (list))))))
        (mt (classify a)
          ((err o) (err o))
          ((ok t) (classifyAll (optionOr (listTail args) (list)) (cons t acc)))))))

fn pyRepr s: String -> String
  (let [(q (if (and (stringContains? s "'") (not (stringContains? s "\""))) "\"" "'"))
        (body (stringJoin (map (fn [(ch String)] -> String
                                 (let [(k (charCode ch))]
                                   (cond ((= ch "\\") "\\\\") ((= ch q) (str "\\" q)) ((= ch "\n") "\\n") ((= ch "\r") "\\r") ((= ch "\t") "\\t")
                                         ((or (< k 32) (= k 127)) (str "\\x" (hex2 k))) (else ch))))
                               (stringChars s)) ""))]
    (str q body q))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "0")

fn hex2 n: Int64 -> String
  (str (hexDigit (/ n 16)) (hexDigit (mod n 16)))

(schema St (:f args Args) (:f extras (List String)) (:f seen (List String)))

fn setArg a: Args act: String v: String -> Args
  (cond
    ((= act "dim") (with a :dim (some v)))
    ((= act "scope") (with a :scope v))
    ((= act "limit") (with a :limit v))
    ((= act "symbol") (with a :symbol v))
    ((= act "module") (with a :module v))
    ((= act "path") (with a :path v))
    ((= act "spec") (with a :spec v))
    (else (with a :id v)))

fn helpOutcome -> c/Outcome
  (c/Outcome :out (helpText) :err "" :code 0)

fn shortTail st: St o: Opt -> (Result St c/Outcome)
  (let [(ex (optionOr o.explicit "")) (sp (optionOr o.sep ""))]
    (if (or (not (stringEmpty? sp)) (stringStartsWith? ex "-"))
      (err (usageError (str "argument -h/--help: ignored explicit argument " (pyRepr ex))))
      (err (helpOutcome))))

fn tokAt toks: (List Tok) i: Int64 -> (Option Tok)
  (listGet toks i)

fn consumeOpt st: St o: Opt raw: String toks: (List Tok) i: Int64 -> (Result (Pair St Int64) c/Outcome)
  (mt o.act
    ((none) (ok (pair (with st :extras (listAppend st.extras (list raw))) (+ i 1))))
    ((some act)
      (mt o.explicit
        ((some ex)
          (cond
            ((and (= act "help") (not (stringStartsWith? o.spelling "--")) (not (stringEmpty? ex)))
              (mt (shortTail st o) ((ok s2) (ok (pair s2 (+ i 1)))) ((err e) (err e))))
            ((= act "help") (err (usageError (str "argument -h/--help: ignored explicit argument " (pyRepr ex)))))
            (else (ok (pair (with st :args (setArg st.args act ex) :seen (cons act st.seen)) (+ i 1))))))
        ((none)
          (if (= act "help")
            (err (helpOutcome))
            (mt (tokAt toks (+ i 1))
              ((some nt) (mt nt
                           ((tokArg v) (ok (pair (with st :args (setArg st.args act v) :seen (cons act st.seen)) (+ i 2))))
                           (_ (err (usageError (str "argument " (actionName act) ": expected one argument"))))))
              ((none) (err (usageError (str "argument " (actionName act) ": expected one argument"))))))))))

fn walk st: St toks: (List Tok) i: Int64 -> (Result St c/Outcome)
  (mt (tokAt toks i)
    ((none) (ok st))
    ((some t)
      (mt t
        ((tokOpt o raw) (mt (consumeOpt st o raw toks i) ((ok p) (walk (pairFirst p) toks (pairSecond p))) ((err e) (err e))))
        ((tokArg s) (walk (with st :extras (listAppend st.extras (list s))) toks (+ i 1)))
        ((tokSep s) (walk (with st :extras (listAppend st.extras (list s))) toks (+ i 1))))))

fn parseArgs argv: (List String) -> (Result Args c/Outcome)
  (mt (classifyAll argv (list))
    ((err e) (err e))
    ((ok toks)
      (mt (walk (St :args (Args :dim (none) :scope "" :limit "" :symbol "" :module "" :path "" :spec "" :id "") :extras (list) :seen (list)) toks 0)
        ((err e) (err e))
        ((ok st)
          (cond
            ((not (listContains? st.seen "dim")) (err (usageError "the following arguments are required: --dim")))
            ((not (listEmpty? st.extras)) (err (usageError (str "unrecognized arguments: " (stringJoin st.extras " ")))))
            (else (ok st.args)))))))
