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
        (boolBad (line! "(:agent :task x :plan maybe :dryRun true)"))
        (root (line! (str "(:agent :task x :toolRoot " (root!) "/nowhere-toolroot :dryRun true)")))]
    (do (assert (stringContains? bad "ERR_PARAM_TYPE") (str "a wrong-typed int is refused: " bad))
        (assert (stringContains? bad ":timeoutMs :type int :got \"abc\"") (str "the receipt names key, type and value: " bad))
        (assert (not (stringContains? good "ERR_PARAM_TYPE")) (str "a well-typed int passes: " good))
        (assert (stringContains? boolBad "ERR_PARAM_TYPE") (str "a wrong-typed bool is refused: " boolBad))
        (assert (not (stringContains? root "ERR_PARAM_TYPE")) (str "a path for :toolRoot (declared str) is not a type error: " root))
        true))

; (:m :ref FORMS-PARAM-TYPES :do "a step with a bad int and a bad bool is one ERR_PARAM_TYPE naming both, in the catalogue's key order whichever order the step wrote them (agent declares plan before timeout; every agent step also carries :dryRun true, so a removed check can only start a dry run, never a live agent), so a check that stops at the first wrong key is red here")
fn ! testMulti -> Bool
  (let [(a (line! "(:agent :task x :timeout abc :plan maybe :dryRun true)"))
        (b (line! "(:agent :task x :dryRun true :plan maybe :timeout abc)"))
        (one (line! "(:agent :task x :timeout abc :dryRun true)"))
        (pa (optionOr (stringIndexOf a "(:plan :type bool :got \"maybe\")") -1))
        (ta (optionOr (stringIndexOf a "(:timeout :type int :got \"abc\")") -1))]
    (do (assert (and (stringContains? a "(:plan :type bool :got \"maybe\")") (stringContains? a "(:timeout :type int :got \"abc\")")) (str "both wrong keys are named: " a))
        (assert (and (>= pa 0) (< pa ta)) (str "in catalogue key order, plan before timeout: " a))
        (assert (= a b) (str "the same receipt whichever order the step wrote the keys: " a " vs " b))
        (assert (and (stringContains? one "ERR_PARAM_TYPE") (not (stringContains? one ":plan"))) (str "one wrong key names only it: " one))
        true))

; (:m :ref CATALOGUE-ORDER-UNGATED :do "agent declares plan before timeout, which is also alphabetical, so a sort of the receipt keys passed the test; intel declares strict before limit, the reverse of the alphabet: a sorted receipt names limit first and is red here; intel is read-only, so a removed check can only run an outline")
fn ! testOrderNotAlphabetical -> Bool
  (let [(a (line! "(:intel :op outline :limit abc :strict maybe)"))
        (b (line! "(:intel :op outline :strict maybe :limit abc)"))
        (sa (optionOr (stringIndexOf a "(:strict :type bool :got \"maybe\")") -1))
        (la (optionOr (stringIndexOf a "(:limit :type int :got \"abc\")") -1))]
    (do (assert (and (>= sa 0) (>= la 0)) (str "both wrong keys are named: " a))
        (assert (< sa la) (str "strict before limit, the catalogue's order and not the alphabet's: " a))
        (assert (= a b) (str "the same receipt whichever order the step wrote the keys: " a " vs " b))
        true))

fn ! runTests -> Bool
  (do (assert (testPure) "type predicate")
      (assert (testDispatch) "dispatch")
      (assert (testMulti) "two wrong keys in one step")
      (assert (testOrderNotAlphabetical) "wrong keys keep the catalogue order when it is not alphabetical")
      true)
