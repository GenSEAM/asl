(module asl-forms/tests/paramTypeTest :x [runTests] :i [(asl-forms/ops :a ops) (asl-forms/tools :a t)])

; (:m :ref FORMS-PARAM-TYPES :do "the :type the catalogue declares is enforced at dispatch: a wrong-typed int or bool is ERR_PARAM_TYPE naming key, type and value; str values and well-typed ints pass; a toolRoot declared str passes a path, so a :type int mutant on it is red here")
fn root! -> String
  (resultOr (realPath ".") ".")

fn line! form: String -> String
  (optionOr (listHead (ops/runStep! (root!) 1 form).lines) "")

fn ! testPure -> Bool
  (do (assert (t/paramTypeOk? "int" "5000") "an integer is an int")
      (assert (t/paramTypeOk? "int" "-3") "a negative integer is an int")
      (assert (not (t/paramTypeOk? "int" "abc")) "text is not an int")
      (assert (not (t/paramTypeOk? "int" "")) "an empty value is not an int")
      (assert (not (t/paramTypeOk? "int" "1.5")) "a decimal is not an int")
      (assert (t/paramTypeOk? "bool" "true") "true is a bool")
      (assert (t/paramTypeOk? "bool" "false") "false is a bool")
      (assert (t/paramTypeOk? "bool" "") "a bare flag is a bool")
      (assert (not (t/paramTypeOk? "bool" "yes")) "yes is not a bool")
      (assert (t/paramTypeOk? "str" "anything at all") "str is not checked")
      (assert (t/paramTypeOk? "sym" "x") "sym is not checked")
      (assert (t/paramTypeOk? "forms" "(a b)") "forms is not checked")
      true)

fn ! testDispatch -> Bool
  (let [(bad (line! "(:eval :code \"(+ 1 2)\" :timeoutMs abc)"))
        (good (line! "(:eval :code \"(+ 1 2)\" :timeoutMs 5000)"))
        (boolBad (line! "(:agent :task x :dryRun maybe)"))
        (root (line! (str "(:agent :task x :toolRoot " (root!) "/nowhere-toolroot :dryRun true)")))]
    (do (assert (stringContains? bad "ERR_PARAM_TYPE") (str "a wrong-typed int is refused: " bad))
        (assert (stringContains? bad ":timeoutMs :type int :got \"abc\"") (str "the receipt names key, type and value: " bad))
        (assert (not (stringContains? good "ERR_PARAM_TYPE")) (str "a well-typed int passes: " good))
        (assert (stringContains? boolBad "ERR_PARAM_TYPE") (str "a wrong-typed bool is refused: " boolBad))
        (assert (not (stringContains? root "ERR_PARAM_TYPE")) (str "a path for :toolRoot (declared str) is not a type error: " root))
        true))

fn ! runTests -> Bool
  (do (assert (testPure) "type predicate")
      (assert (testDispatch) "dispatch")
      true)
