(module asl-checker/check
  :d "Pass 3 Hindley-Milner Type Inference and Unified Checker Entry Points"
  :x [InferState
      check-module
      check-source
      check-file!]
  :i [(types :a ty) (unify :a u) (resolve :a r) (ast :a a) (reader :a rd)])

(dfs InferState
  (:f subst (Map Int64 ty/Type) "Defun-scoped substitution map")
  (:f next-var Int64 "Defun-scoped next fresh metavar id")
  (:f int-sites (List (Pair String Int64)) "Integer literals with metavar id")
  (:f map-sites (List (Pair ty/Type String)) "Inferred types with scope label")
  (:f lambdas (List (Pair (List ty/Type) ty/Type)) "Lambda parameter and return types")
  (:f diags (List ty/Diagnostic) "Pass 3 diagnostics"))

(df make-infer-state [] -> InferState
  (InferState :subst (map-empty)
              :next-var 1
              :int-sites (list)
              :map-sites (list)
              :lambdas (list)
              :diags (list)))

(df fresh-var [(st InferState) (kind String)] -> (Pair ty/Type InferState)
  (let [(nid (.-next-var st))]
    (pair (ty/ty-var nid kind)
          (InferState :subst (.-subst st)
                      :next-var (+ nid 1)
                      :int-sites (.-int-sites st)
                      :map-sites (.-map-sites st)
                      :lambdas (.-lambdas st)
                      :diags (.-diags st)))))

(df add-diag [(st InferState) (code String) (msg String) (path String)] -> InferState
  (InferState :subst (.-subst st)
              :next-var (.-next-var st)
              :int-sites (.-int-sites st)
              :map-sites (.-map-sites st)
              :lambdas (.-lambdas st)
              :diags (list-cons (ty/Diagnostic :code code :message msg :line 1 :col 1 :path path)
                                (.-diags st))))

(df note-map-type [(st InferState) (t ty/Type) (scope String)] -> InferState
  (InferState :subst (.-subst st)
              :next-var (.-next-var st)
              :int-sites (.-int-sites st)
              :map-sites (list-cons (pair t scope) (.-map-sites st))
              :lambdas (.-lambdas st)
              :diags (.-diags st)))

(df note-int-literal [(st InferState) (tok String) (vid Int64)] -> InferState
  (InferState :subst (.-subst st)
              :next-var (.-next-var st)
              :int-sites (list-cons (pair tok vid) (.-int-sites st))
              :map-sites (.-map-sites st)
              :lambdas (.-lambdas st)
              :diags (.-diags st)))

(df note-lambda [(st InferState) (params (List ty/Type)) (ret ty/Type)] -> InferState
  (InferState :subst (.-subst st)
              :next-var (.-next-var st)
              :int-sites (.-int-sites st)
              :map-sites (.-map-sites st)
              :lambdas (list-cons (pair params ret) (.-lambdas st))
              :diags (.-diags st)))

(df set-subst [(st InferState) (s (Map Int64 ty/Type))] -> InferState
  (InferState :subst s
              :next-var (.-next-var st)
              :int-sites (.-int-sites st)
              :map-sites (.-map-sites st)
              :lambdas (.-lambdas st)
              :diags (.-diags st)))

(df expect-type [(st InferState) (have ty/Type) (want ty/Type) (where String) (path String)] -> InferState
  (let [(st1 (note-map-type (note-map-type st have where) want where))]
    (mt (u/unify have want (.-subst st1))
      ((u/u-ok next-subst) (set-subst st1 next-subst))
      ((u/u-err msg is-num)
       (let [(code (if is-num "rule-6" "type"))]
         (add-diag st1 code (str where ": " msg) path))))))

(df qualify-type-with-mod [(t ty/Type) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary))] -> ty/Type
  (mt t
    ((ty/ty-var _ _) t)
    ((ty/ty-con name args opt-mod opt-shown)
     (let [(is-local (and (not (string-empty? (.-name mod)))
                          (or (mt (r/mod-schema mod name) ((some _) true) ((none) false))
                              (mt (r/mod-enum mod name) ((some _) true) ((none) false)))))
           (next-mod (mt opt-mod
                       ((some alias)
                        (mt (r/mod-import mod alias)
                          ((some mpath)
                           (mt (map-get deps mpath)
                             ((some target) (some (.-name target)))
                             ((none) (some mpath))))
                          ((none) opt-mod)))
                       ((none)
                        (if is-local
                          (some (.-name mod))
                          (none)))))]
        (ty/ty-con name (map (fn [(a ty/Type)] -> ty/Type (qualify-type-with-mod a mod deps)) args) next-mod opt-shown)))
    ((ty/ty-fun params ret)
     (ty/ty-fun (map (fn [(p ty/Type)] -> ty/Type (qualify-type-with-mod p mod deps)) params)
                (qualify-type-with-mod ret mod deps)))))

(df instantiate-sig [(params (List String)) (ret String) (typevars (List String)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Pair (Pair (List ty/Type) ty/Type) InferState)
  (let [(v-res (fold (fn [(acc (Pair (Map String ty/Type) InferState)) (vname String)] -> (Pair (Map String ty/Type) InferState)
                       (let [(kind (if (= vname "N") "num" (if (= vname "I") "int" "any")))
                             (f-res (fresh-var (.-second acc) kind))]
                         (pair (map-set (.-first acc) vname (.-first f-res))
                               (.-second f-res))))
                     (pair (map-empty) st)
                     typevars))]
    (let [(vmap (.-first v-res))
          (st1 (.-second v-res))
          (inst-p (map (fn [(p String)] -> ty/Type
                         (qualify-type-with-mod (subst-parsed-type (ty/parse-type-str p (list)) vmap) mod deps))
                       params))
          (inst-r (qualify-type-with-mod (subst-parsed-type (ty/parse-type-str ret (list)) vmap) mod deps))]
      (pair (pair inst-p inst-r) st1))))

(df subst-parsed-types [(ts (List ty/Type)) (vmap (Map String ty/Type))] -> (List ty/Type)
  :d "Applies type variable mapping to a list of parsed types."
  (map (fn [(item ty/Type)] -> ty/Type (subst-parsed-type item vmap)) ts))

(df subst-parsed-type [(t ty/Type) (vmap (Map String ty/Type))] -> ty/Type
  :d "Substitutes concrete type variables in parsed types with fresh metavariables."
  (mt t
    ((ty/ty-var _ _) t)
    ((ty/ty-con name args opt-mod opt-shown)
     (mt (map-get vmap name)
       ((some mapped) mapped)
       ((none)
        (ty/ty-con name
                   (subst-parsed-types args vmap)
                   opt-mod
                   opt-shown))))
    ((ty/ty-fun params ret)
     (ty/ty-fun (subst-parsed-types params vmap)
                (subst-parsed-type ret vmap)))))

(df sig-res-to-fun [(res (Pair (Pair (List ty/Type) ty/Type) InferState))] -> (Option (Pair ty/Type InferState))
  (some (pair (ty/ty-fun (.-first (.-first res)) (.-second (.-first res))) (.-second res))))

(df param-types-to-strs [(params (List (Pair String String)))] -> (List String)
  (map (fn [(p (Pair String String))] -> String (.-second p)) params))

(df lookup-local-fun [(sym String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (r/mod-fun mod sym)
    ((some f)
     (let [(p-strs (param-types-to-strs (.-params f)))
           (res (instantiate-sig p-strs (.-ret f) (.-typevars f) mod deps st))]
       (sig-res-to-fun res)))
    ((none) (none))))

(df lookup-builtin-sig [(sym String) (mod r/ModuleSummary) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (ty/builtin-sig sym)
    ((some bsig)
     (let [(params (.-first bsig))
           (ret (.-second (.-second bsig)))
           (tvars (collect-tvars params ret))
           (res (instantiate-sig params ret tvars mod (map-empty) st))]
       (sig-res-to-fun res)))
    ((none) (none))))

(df lookup-local-case [(sym String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (map-get (.-case-owner mod) sym)
    ((some ename)
     (mt (r/mod-enum mod ename)
       ((some esum)
        (let [(matching (filter (fn [(c r/CaseSummary)] -> Bool (= (.-name c) sym)) (.-cases esum)))]
          (mt (list-head matching)
            ((some c)
             (let [(p-strs (param-types-to-strs (.-params c)))
                   (tvars (.-typevars esum))
                   (ret-str (if (list-empty? tvars)
                                ename
                                (str "(" ename " " (string-join tvars " ") ")")))
                   (res (instantiate-sig p-strs ret-str tvars mod deps st))]
               (sig-res-to-fun res)))
            ((none) (none)))))
       ((none) (none))))
    ((none) (none))))

(df lookup-local-symbol [(sym String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (lookup-local-fun sym mod deps st)
    ((some res) (some res))
    ((none) (lookup-local-case sym mod deps st))))

(df lookup-imported-symbol [(sym String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (let [(parts (string-split sym "/"))
        (alias (mt (list-get parts 0) ((some a) a) ((none) "")))
        (member (mt (list-get parts 1) ((some m) m) ((none) "")))]
    (mt (r/mod-import mod alias)
      ((some mpath)
       (mt (map-get deps mpath)
         ((some target) (lookup-local-symbol member target deps st))
         ((none) (none))))
      ((none) (none)))))

(df lookup-symbol-type [(sym String) (env (Map String ty/Type)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Option (Pair ty/Type InferState))
  (mt (map-get env sym)
    ((some t) (some (pair t st)))
    ((none)
     (mt (lookup-local-symbol sym mod deps st)
       ((some res) (some res))
       ((none)
        (mt (lookup-builtin-sig sym mod st)
          ((some res) (some res))
          ((none)
           (if (string-contains? sym "/")
             (lookup-imported-symbol sym mod deps st)
             (none)))))))))

(df collect-tvars [(params (List String)) (ret String)] -> (List String)
  (let [(all-strs (list-cons ret params))]
    (fold (fn [(acc (List String)) (s String)] -> (List String)
            (fold (fn [(aacc (List String)) (w String)] -> (List String)
                    (if (and (= (string-length w) 1) (string-contains? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" w))
                      (if (list-contains? aacc w) aacc (list-cons w aacc))
                      aacc))
                  acc
                  (string-split (string-replace (string-replace (string-replace (string-replace s "(" " ") ")" " ") "[" " ") "]" " ") " ")))
          (list)
          all-strs)))

(df is-float-lit? [(v String)] -> Bool
  (let [(s (r/clean-num-sign v))]
    (if (string-contains? s ".")
      (let [(parts (string-split s "."))]
        (and (= (list-length parts) 2)
             (and (is-all-digits (mt (list-get parts 0) ((some d) d) ((none) "")))
                  (is-all-digits (mt (list-get parts 1) ((some d) d) ((none) ""))))))
      false)))

(df is-int-lit? [(v String)] -> Bool
  (let [(s (r/clean-num-sign v))]
    (and (not (string-empty? s)) (is-all-digits s))))

(df unit-type [] -> ty/Type
  (ty/ty-con "Unit" (list) (none) (none)))

(df last-expr-unit [(l (List rd/SExpr))] -> rd/SExpr
  (mt (list-head (list-reverse l))
    ((some e) e)
    ((none) (rd/make-atom "()"))))

(df infer-atom [(v String) (env (Map String ty/Type)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (scope String) (path String) (st InferState)] -> (Pair ty/Type InferState)
  (cond
    ((string-starts-with? v "\"")
     (pair (ty/ty-con "String" (list) (none) (none)) st))
    ((or (= v "true") (= v "false"))
     (pair (ty/ty-con "Bool" (list) (none) (none)) st))
    ((or (= v "()") (= v "nil"))
     (pair (unit-type) st))
    ((is-float-lit? v)
     (pair (ty/ty-con "Float64" (list) (none) (none)) st))
    ((is-int-lit? v)
     (let [(vid (.-next-var st))
           (f-res (fresh-var st "int"))
           (vty (.-first f-res))
           (st1 (.-second f-res))
           (st2 (note-int-literal st1 v vid))]
       (pair vty st2)))
    (:else
     (mt (lookup-symbol-type v env mod deps st)
       ((some found) found)
       ((none) (fresh-var st "any"))))))

(df infer-atom-fm [(fm FrameMachine) (v String) (st InferState)] -> (Pair ty/Type InferState)
  (infer-atom v (.-env fm) (.-mod fm) (.-deps fm) (.-scope fm) (.-path fm) st))

(df as-ty-var [(t ty/Type)] -> ty/Type
  t)

(df is-all-digits [(s String)] -> Bool
  (if (string-empty? s)
    false
    (fold (fn [(acc Bool) (c String)] -> Bool
            (and acc (string-contains? "0123456789" c)))
          true
          (string-chars s))))

(df parse-param-parts [(parts (List rd/SExpr)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary))] -> (Pair String (Option ty/Type))
  (let [(h (r/first-head-ident parts))
        (sub (r/safe-tail parts))]
    (mt (list-head sub)
      ((some ty-node)
       (pair h (some (qualify-type-with-mod (ty/parse-type-str (rd/render-sexpr ty-node) (list)) mod deps))))
      ((none) (pair h (none))))))

(df parse-param-ann [(p rd/SExpr) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary))] -> (Pair String (Option ty/Type))
  (mt p
    ((rd/sexpr-atom n) (pair n (none)))
    ((rd/sexpr-list parts) (parse-param-parts parts mod deps))
    ((rd/sexpr-vect parts) (parse-param-parts parts mod deps))))

(dfe InferFrame
  (:c f-eval [(expr rd/SExpr)] "Evaluate expression next")
  (:c f-call [(callee-name String) (callee-ty ty/Type) (args-done (List ty/Type)) (args-pending (List rd/SExpr)) (env (Map String ty/Type))] "Call evaluation continuation")
  (:c f-let-val [(bname String) (bindings-rest (List rd/SExpr)) (tail-exprs (List rd/SExpr)) (env (Map String ty/Type))] "Let binding evaluation continuation")
  (:c f-if-cond [(then-e rd/SExpr) (else-e rd/SExpr) (env (Map String ty/Type))] "If condition continuation")
  (:c f-if-then [(else-e rd/SExpr) (then-ty ty/Type) (env (Map String ty/Type))] "If branches continuation")
  (:c f-try-inner [(val-var ty/Type)] "Try continuation"))

(dfs FrameMachine
  (:f frames (List InferFrame) "Pending evaluation frame stack")
  (:f values (List ty/Type) "Evaluated type values stack")
  (:f env (Map String ty/Type) "Current lexical type environment")
  (:f ret-type (Option ty/Type) "Enclosing defun return type")
  (:f in-lambda Bool "True when evaluating inside fn")
  (:f scope String "Current scope label")
  (:f path String "Source file path")
  (:f mod r/ModuleSummary "Module summary")
  (:f deps (Map String r/ModuleSummary) "Dependency summaries")
  (:f state InferState "Inference state carrying substitution"))

(df fm-push-fresh [(fm FrameMachine) (rest-frames (List InferFrame)) (st InferState)] -> FrameMachine
  (let [(f-res (fresh-var st "any"))]
    (FrameMachine :frames rest-frames
                  :values (list-cons (.-first f-res) (.-values fm))
                  :env (.-env fm)
                  :ret-type (.-ret-type fm)
                  :in-lambda (.-in-lambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state (.-second f-res))))

(df pop-value [(fm FrameMachine)] -> (Pair ty/Type (List ty/Type))
  (pair (mt (list-head (.-values fm)) ((some v) v) ((none) (unit-type)))
        (r/safe-tail (.-values fm))))

(df fm-tick [(fm FrameMachine) (tick-idx Int64)] -> FrameMachine
  (mt (list-head (.-frames fm))
    ((none) fm)
    ((some top-frame)
     (let [(rest-frames (r/safe-tail (.-frames fm)))]
       (mt top-frame
         ((f-eval expr)
          (fm-eval-step expr rest-frames fm))
         ((f-call cname cty args-done args-pending cenv)
          (fm-call-step cname cty args-done args-pending cenv rest-frames fm))
         ((f-let-val bname brest tails lenv)
          (fm-let-val-step bname brest tails lenv rest-frames fm))
         ((f-if-cond then-e else-e ienv)
          (fm-if-cond-step then-e else-e ienv rest-frames fm))
         ((f-if-then else-e then-ty ienv)
          (fm-if-then-step else-e then-ty ienv rest-frames fm))
         ((f-try-inner val-var)
          (fm-try-step val-var rest-frames fm)))))))

(df bind-match-pattern [(pat rd/SExpr) (scrut-ty ty/Type) (env (Map String ty/Type)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Pair (Map String ty/Type) InferState)
  (mt pat
    ((rd/sexpr-atom name)
     (if (or (= name "_") (r/is-literal-atom? name))
       (pair env st)
       (pair (map-set env name scrut-ty) st)))
    ((rd/sexpr-vect _)
     (pair env st))
    ((rd/sexpr-list parts)
     (mt (list-head parts)
       ((none) (pair env st))
       ((some h)
        (let [(cname (rd/sexpr-head h))
              (sub-pats (r/safe-tail parts))
              (ctor-opt (lookup-symbol-type cname env mod deps st))]
          (mt ctor-opt
            ((none) (pair env st))
            ((some ctor-res)
             (let [(ctor-ty (.-first ctor-res))
                   (st1 (.-second ctor-res))]
               (mt (u/apply-subst (.-subst st1) ctor-ty)
                 ((ty/ty-fun cparams cret)
                  (let [(st2 (expect-type st1 scrut-ty cret (str "pattern " cname) (.-path mod)))]
                    (fold (fn [(acc (Pair (Map String ty/Type) InferState)) (pair-item (Pair rd/SExpr ty/Type))] -> (Pair (Map String ty/Type) InferState)
                            (bind-match-pattern (.-first pair-item)
                                                (u/apply-subst (.-subst (.-second acc)) (.-second pair-item))
                                                (.-first acc)
                                                mod
                                                deps
                                                (.-second acc)))
                          (pair env st2)
                          (zip sub-pats cparams))))
                 (_ (pair env st1))))))))))))

(df fm-try-outside-error [(fm FrameMachine) (inner-e rd/SExpr) (rest-frames (List InferFrame))] -> FrameMachine
  (let [(st1 (add-diag (.-state fm) "rule-5" "try outside a defun returning (Result _ E)" (.-path fm)))]
    (FrameMachine :frames (list-cons (f-eval inner-e) rest-frames)
                  :values (.-values fm)
                  :env (.-env fm)
                  :ret-type (.-ret-type fm)
                  :in-lambda (.-in-lambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state st1)))

(df fm-eval-step [(expr rd/SExpr) (rest-frames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (mt expr
    ((rd/sexpr-atom v)
     (let [(res (infer-atom-fm fm v (.-state fm)))]
       (FrameMachine :frames rest-frames
                     :values (list-cons (.-first res) (.-values fm))
                     :env (.-env fm)
                     :ret-type (.-ret-type fm)
                     :in-lambda (.-in-lambda fm)
                     :scope (.-scope fm)
                     :path (.-path fm)
                     :mod (.-mod fm)
                     :deps (.-deps fm)
                     :state (note-map-type (.-second res) (.-first res) (.-scope fm)))))
    ((rd/sexpr-vect items)
     (let [(f-res (fresh-var (.-state fm) "any"))
           (elem-ty (.-first f-res))
           (st1 (.-second f-res))]
       (FrameMachine :frames rest-frames
                     :values (list-cons (ty/ty-con "List" (list elem-ty) (none) (none)) (.-values fm))
                     :env (.-env fm)
                     :ret-type (.-ret-type fm)
                     :in-lambda (.-in-lambda fm)
                     :scope (.-scope fm)
                     :path (.-path fm)
                     :mod (.-mod fm)
                     :deps (.-deps fm)
                     :state st1)))
    ((rd/sexpr-list items)
     (mt (list-head items)
       ((none)
        (FrameMachine :frames rest-frames
                      :values (list-cons (unit-type) (.-values fm))
                      :env (.-env fm)
                      :ret-type (.-ret-type fm)
                      :in-lambda (.-in-lambda fm)
                      :scope (.-scope fm)
                      :path (.-path fm)
                      :mod (.-mod fm)
                      :deps (.-deps fm)
                      :state (.-state fm)))
       ((some h)
        (let [(head-tok (rd/sexpr-head h))
              (tail-args (r/safe-tail items))]
          (cond
            ((= head-tok "let")
             (let [(bitems (r/first-vect-items tail-args))
                   (tails (r/safe-tail tail-args))]
               (if (list-empty? bitems)
                 (let [(last-e (last-expr-unit tails))]
                   (FrameMachine :frames (list-cons (f-eval last-e) rest-frames)
                                 :values (.-values fm)
                                 :env (.-env fm)
                                 :ret-type (.-ret-type fm)
                                 :in-lambda (.-in-lambda fm)
                                 :scope (.-scope fm)
                                 :path (.-path fm)
                                 :mod (.-mod fm)
                                 :deps (.-deps fm)
                                 :state (.-state fm)))
                 (let [(first-b (r/first-expr-empty bitems))
                       (brest (r/safe-tail bitems))
                       (bparts (mt first-b ((rd/sexpr-list bp) bp) ((rd/sexpr-vect bp) bp) (_ (list))))
                       (bname (r/first-head-ident bparts))
                       (bval (r/second-expr-empty bparts))]
                   (FrameMachine :frames (list-cons (f-eval bval) (list-cons (f-let-val bname brest tails (.-env fm)) rest-frames))
                                 :values (.-values fm)
                                 :env (.-env fm)
                                 :ret-type (.-ret-type fm)
                                 :in-lambda (.-in-lambda fm)
                                 :scope (.-scope fm)
                                 :path (.-path fm)
                                 :mod (.-mod fm)
                                 :deps (.-deps fm)
                                 :state (.-state fm))))))

            ((= head-tok "if")
             (let [(cond-e (mt (list-get tail-args 0) ((some c) c) ((none) (rd/make-atom "true"))))
                   (then-e (mt (list-get tail-args 1) ((some t) t) ((none) (rd/make-atom "()"))))
                   (else-e (mt (list-get tail-args 2) ((some e) e) ((none) (rd/make-atom "()"))))]
               (FrameMachine :frames (list-cons (f-eval cond-e) (list-cons (f-if-cond then-e else-e (.-env fm)) rest-frames))
                             :values (.-values fm)
                             :env (.-env fm)
                             :ret-type (.-ret-type fm)
                             :in-lambda (.-in-lambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state (.-state fm))))

            ((= head-tok "cond")
             (let [(f-res (fresh-var (.-state fm) "any"))
                   (out-var (.-first f-res))
                   (st-out (.-second f-res))
                   (st-final (fold (fn [(st-acc InferState) (clause rd/SExpr)] -> InferState
                                     (mt clause
                                       ((rd/sexpr-list cparts)
                                        (let [(chead-expr (r/first-expr-empty cparts))
                                               (chead (rd/sexpr-head chead-expr))
                                               (cbodies (r/safe-tail cparts))
                                               (last-b (last-expr-unit cbodies))]
                                           (if (= chead ":else")
                                             (let [(bres (eval-fm fm last-b st-acc))]
                                               (expect-type (.-second bres) (.-first bres) out-var "cond else clause" (.-path fm)))
                                             (let [(cres (eval-fm fm chead-expr st-acc))
                                                   (st-c (expect-type (.-second cres) (.-first cres) (ty/ty-con "Bool" (list) (none) (none)) "cond test" (.-path fm)))
                                                   (bres (eval-fm fm last-b st-c))]
                                               (expect-type (.-second bres) (.-first bres) out-var "cond clause" (.-path fm))))))
                                        (_ st-acc)))
                                   st-out
                                   tail-args))]
               (FrameMachine :frames rest-frames
                             :values (list-cons (u/apply-subst (.-subst st-final) out-var) (.-values fm))
                             :env (.-env fm)
                             :ret-type (.-ret-type fm)
                             :in-lambda (.-in-lambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state st-final)))

            ((or (= head-tok "match") (= head-tok "mt"))
             (let [(scrutinee (r/first-expr-unit tail-args))
                   (arms (r/safe-tail tail-args))
                   (scrut-res (eval-fm fm scrutinee (.-state fm)))
                   (scrut-ty (.-first scrut-res))
                   (st-scrut (.-second scrut-res))
                   (f-res (fresh-var st-scrut "any"))
                   (out-var (.-first f-res))
                   (st-out (.-second f-res))
                   (st-final (fold (fn [(st-acc InferState) (arm rd/SExpr)] -> InferState
                                     (mt arm
                                       ((rd/sexpr-list arm-parts)
                                        (let [(pat (mt (list-head arm-parts) ((some p) p) ((none) (rd/make-atom "_"))))
                                              (body-exprs (r/safe-tail arm-parts))
                                              (bind-res (bind-match-pattern pat (u/apply-subst (.-subst st-acc) scrut-ty) (.-env fm) (.-mod fm) (.-deps fm) st-acc))
                                              (arm-env (.-first bind-res))
                                              (st-arm (.-second bind-res))
                                              (last-body (last-expr-unit body-exprs))
                                              (body-res (eval-with-env fm last-body arm-env st-arm))
                                              (body-ty (.-first body-res))
                                              (st-b (.-second body-res))]
                                          (expect-type st-b body-ty out-var "match arm" (.-path fm))))
                                       (_ st-acc)))
                                   st-out
                                   arms))]
               (FrameMachine :frames rest-frames
                             :values (list-cons (u/apply-subst (.-subst st-final) out-var) (.-values fm))
                             :env (.-env fm)
                             :ret-type (.-ret-type fm)
                             :in-lambda (.-in-lambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state st-final)))

            ((= head-tok "try")
             (let [(inner-e (r/first-expr-unit tail-args))]
               (if (.-in-lambda fm)
                 (let [(st1 (add-diag (.-state fm) "rule-5" "try inside fn: it would return from the enclosing defun, not from the lambda" (.-path fm)))]
                   (FrameMachine :frames (list-cons (f-eval inner-e) rest-frames)
                                 :values (.-values fm)
                                 :env (.-env fm)
                                 :ret-type (.-ret-type fm)
                                 :in-lambda (.-in-lambda fm)
                                 :scope (.-scope fm)
                                 :path (.-path fm)
                                 :mod (.-mod fm)
                                 :deps (.-deps fm)
                                 :state st1))
                 (let [(enclosing (mt (.-ret-type fm)
                                    ((some r) (u/apply-subst (.-subst (.-state fm)) r))
                                    ((none) (unit-type))))]
                   (mt enclosing
                     ((ty/ty-con rname rargs _ _)
                      (if (and (= rname "Result") (= (list-length rargs) 2))
                        (let [(f-res (fresh-var (.-state fm) "any"))
                              (vty (.-first f-res))
                              (st1 (.-second f-res))]
                          (FrameMachine :frames (list-cons (f-eval inner-e) (list-cons (f-try-inner vty) rest-frames))
                                        :values (.-values fm)
                                        :env (.-env fm)
                                        :ret-type (.-ret-type fm)
                                        :in-lambda (.-in-lambda fm)
                                        :scope (.-scope fm)
                                        :path (.-path fm)
                                        :mod (.-mod fm)
                                        :deps (.-deps fm)
                                        :state st1))
                        (fm-try-outside-error fm inner-e rest-frames)))
                     (_
                      (fm-try-outside-error fm inner-e rest-frames)))))))

            ((= head-tok "fn")
             (let [(is-bang (and (not (list-empty? tail-args))
                                 (= (r/first-head-ident tail-args) "!")))
                   (rem-args (if is-bang (r/safe-tail tail-args) tail-args))
                   (after-params (r/safe-tail rem-args))
                   (has-ret-ann (and (not (list-empty? after-params))
                                     (= (r/first-head-ident after-params) "->")))
                   (body-nodes (if has-ret-ann
                                 (r/safe-tail (r/safe-tail after-params))
                                 after-params))
                   (param-items (r/first-vect-items rem-args))
                   (p-res (fold (fn [(acc (Pair (Pair (List ty/Type) (Map String ty/Type)) (Pair InferState Bool))) (p rd/SExpr)] -> (Pair (Pair (List ty/Type) (Map String ty/Type)) (Pair InferState Bool))
                                  (let [(pann (parse-param-ann p (.-mod fm) (.-deps fm)))
                                        (pname (.-first pann))
                                        (opt-ty (.-second pann))]
                                    (mt opt-ty
                                      ((some pty)
                                       (pair (pair (list-cons pty (.-first (.-first acc)))
                                                   (map-set (.-second (.-first acc)) pname pty))
                                             (pair (.-first (.-second acc)) (.-second (.-second acc)))))
                                      ((none)
                                       (let [(f-res (fresh-var (.-first (.-second acc)) "any"))
                                             (pty (.-first f-res))
                                             (st1 (.-second f-res))]
                                         (pair (pair (list-cons pty (.-first (.-first acc)))
                                                     (map-set (.-second (.-first acc)) pname pty))
                                               (pair st1 true)))))))
                                (pair (pair (list) (.-env fm)) (pair (.-state fm) false))
                                param-items))
                    (params-ty (list-reverse (.-first (.-first p-res))))
                    (fn-env (.-second (.-first p-res)))
                    (st1 (.-first (.-second p-res)))
                    (has-p-elided (.-second (.-second p-res)))
                    (after-arrow (if has-ret-ann (r/safe-tail after-params) (list)))
                    (ret-node-opt (list-head after-arrow))
                    (ret-info (mt ret-node-opt
                                ((some rnode)
                                 (pair (qualify-type-with-mod (ty/parse-type-str (rd/render-sexpr rnode) (list)) (.-mod fm) (.-deps fm))
                                       (pair st1 has-p-elided)))
                                ((none)
                                 (let [(f-ret (fresh-var st1 "any"))]
                                   (pair (.-first f-ret) (pair (.-second f-ret) true))))))
                    (ret-ty (.-first ret-info))
                    (st2 (.-first (.-second ret-info)))
                    (has-elided (.-second (.-second ret-info)))
                    (last-body (last-expr-unit body-nodes))
                    (body-res (run-expr-direct last-body fn-env (some ret-ty) true (.-scope fm) (.-path fm) (.-mod fm) (.-deps fm) st2))
                    (body-ty (.-first body-res))
                    (st3 (expect-type (.-second body-res) body-ty ret-ty "lambda body" (.-path fm)))
                    (st4 (if has-elided (note-lambda st3 params-ty ret-ty) st3))
                    (fn-ty (ty/ty-fun params-ty ret-ty))]
               (FrameMachine :frames rest-frames
                             :values (list-cons fn-ty (.-values fm))
                             :env (.-env fm)
                             :ret-type (.-ret-type fm)
                             :in-lambda (.-in-lambda fm)
                             :scope (.-scope fm)
                             :path (.-path fm)
                             :mod (.-mod fm)
                             :deps (.-deps fm)
                             :state st4)))

            ((string-starts-with? head-tok ".-")
             (let [(fname (r/slice-from head-tok 2))
                   (tgt-e (r/first-expr-unit tail-args))
                   (tgt-res (eval-fm fm tgt-e (.-state fm)))
                   (tgt-ty (u/apply-subst (.-subst (.-second tgt-res)) (.-first tgt-res)))
                   (st1 (.-second tgt-res))]
               (mt tgt-ty
                 ((ty/ty-con tname targs topt-mod _)
                  (if (and (= tname "Pair") (= (list-length targs) 2))
                    (let [(out-ty (if (= fname "first")
                                    (mt (list-get targs 0) ((some f) f) ((none) (unit-type)))
                                    (mt (list-get targs 1) ((some s) s) ((none) (unit-type)))))]
                      (FrameMachine :frames rest-frames
                                    :values (list-cons out-ty (.-values fm))
                                    :env (.-env fm)
                                    :ret-type (.-ret-type fm)
                                    :in-lambda (.-in-lambda fm)
                                    :scope (.-scope fm)
                                    :path (.-path fm)
                                    :mod (.-mod fm)
                                    :deps (.-deps fm)
                                    :state st1))
                    (let [(target-mod (mt topt-mod
                                        ((some alias)
                                         (mt (r/mod-import (.-mod fm) alias)
                                           ((some mpath) (map-get (.-deps fm) mpath))
                                           ((none) (none))))
                                        ((none) (some (.-mod fm)))))]
                      (mt target-mod
                        ((none)
                         (fm-push-fresh fm rest-frames st1))
                        ((some smod)
                         (mt (r/mod-schema smod tname)
                           ((some ssum)
                            (let [(f-match (filter (fn [(f r/FieldSummary)] -> Bool (= (.-name f) fname)) (.-fields ssum)))]
                              (mt (list-head f-match)
                                ((some fdef)
                                 (let [(field-ty (ty/parse-type-str (.-type fdef) (list)))
                                       (subst-map (fold (fn [(acc (Map String ty/Type)) (p (Pair String ty/Type))] -> (Map String ty/Type)
                                                          (map-set acc (.-first p) (.-second p)))
                                                        (map-empty)
                                                        (zip (.-typevars ssum) targs)))
                                       (inst-field (subst-parsed-type field-ty subst-map))]
                                   (FrameMachine :frames rest-frames
                                                 :values (list-cons inst-field (.-values fm))
                                                 :env (.-env fm)
                                                 :ret-type (.-ret-type fm)
                                                 :in-lambda (.-in-lambda fm)
                                                 :scope (.-scope fm)
                                                 :path (.-path fm)
                                                 :mod (.-mod fm)
                                                 :deps (.-deps fm)
                                                 :state st1)))
                                ((none)
                                 (let [(st2 (add-diag st1 "type" (str (ty/show-type tgt-ty) " has no field " fname) (.-path fm)))]
                                   (fm-push-fresh fm rest-frames st2))))))
                           ((none)
                            (fm-push-fresh fm rest-frames st1))))))))
                 (_
                  (fm-push-fresh fm rest-frames st1)))))

            (:else
             (let [(callee-res (infer-atom-fm fm head-tok (.-state fm)))
                   (callee-ty (.-first callee-res))
                   (st1 (.-second callee-res))]
               (if (list-empty? tail-args)
                 (mt (u/apply-subst (.-subst st1) callee-ty)
                   ((ty/ty-fun p r)
                    (FrameMachine :frames rest-frames
                                  :values (list-cons r (.-values fm))
                                  :env (.-env fm)
                                  :ret-type (.-ret-type fm)
                                  :in-lambda (.-in-lambda fm)
                                  :scope (.-scope fm)
                                  :path (.-path fm)
                                  :mod (.-mod fm)
                                  :deps (.-deps fm)
                                  :state st1))
                   (_
                    (FrameMachine :frames rest-frames
                                  :values (list-cons callee-ty (.-values fm))
                                  :env (.-env fm)
                                  :ret-type (.-ret-type fm)
                                  :in-lambda (.-in-lambda fm)
                                  :scope (.-scope fm)
                                  :path (.-path fm)
                                  :mod (.-mod fm)
                                  :deps (.-deps fm)
                                  :state st1)))
                 (let [(first-arg (r/first-expr-unit tail-args))
                       (pending-args (r/safe-tail tail-args))]
                   (FrameMachine :frames (list-cons (f-eval first-arg) (list-cons (f-call head-tok callee-ty (list) pending-args (.-env fm)) rest-frames))
                                 :values (.-values fm)
                                 :env (.-env fm)
                                 :ret-type (.-ret-type fm)
                                 :in-lambda (.-in-lambda fm)
                                 :scope (.-scope fm)
                                 :path (.-path fm)
                                 :mod (.-mod fm)
                                 :deps (.-deps fm)
                                 :state st1))))))))))))

(df fm-call-step [(cname String) (cty ty/Type) (args-done (List ty/Type)) (args-pending (List rd/SExpr)) (cenv (Map String ty/Type)) (rest-frames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (pop-value fm))
        (val (.-first pv))
        (rem-values (.-second pv))
        (next-done (r/list-append-one args-done val))]
    (if (list-empty? args-pending)
      (let [(pruned-callee (u/apply-subst (.-subst (.-state fm)) cty))]
        (mt pruned-callee
          ((ty/ty-fun params ret)
           (let [(st-unify (fold-expect-args next-done params cname (.-path fm) (.-state fm)))]
             (FrameMachine :frames rest-frames
                           :values (list-cons (u/apply-subst (.-subst st-unify) ret) rem-values)
                           :env (.-env fm)
                           :ret-type (.-ret-type fm)
                           :in-lambda (.-in-lambda fm)
                           :scope (.-scope fm)
                           :path (.-path fm)
                           :mod (.-mod fm)
                           :deps (.-deps fm)
                           :state st-unify)))
          (_
           (let [(f-res (fresh-var (.-state fm) "any"))]
             (FrameMachine :frames rest-frames
                           :values (list-cons (.-first f-res) rem-values)
                           :env (.-env fm)
                           :ret-type (.-ret-type fm)
                           :in-lambda (.-in-lambda fm)
                           :scope (.-scope fm)
                           :path (.-path fm)
                           :mod (.-mod fm)
                           :deps (.-deps fm)
                           :state (.-second f-res))))))
      (let [(next-arg (r/first-expr-unit args-pending))
            (rem-pending (r/safe-tail args-pending))]
        (FrameMachine :frames (list-cons (f-eval next-arg) (list-cons (f-call cname cty next-done rem-pending cenv) rest-frames))
                      :values rem-values
                      :env (.-env fm)
                      :ret-type (.-ret-type fm)
                      :in-lambda (.-in-lambda fm)
                      :scope (.-scope fm)
                      :path (.-path fm)
                      :mod (.-mod fm)
                      :deps (.-deps fm)
                      :state (.-state fm))))))

(df fold-expect-args [(args (List ty/Type)) (params (List ty/Type)) (cname String) (path String) (st InferState)] -> InferState
  (mt (list-head args)
    ((none) st)
    ((some a)
     (mt (list-head params)
       ((none) st)
       ((some p)
        (let [(st1 (expect-type st a p (str "argument to " cname) path))]
          (fold-expect-args (r/safe-tail args)
                            (r/safe-tail params)
                            cname
                            path
                            st1)))))))

(df fm-let-val-step [(bname String) (brest (List rd/SExpr)) (tails (List rd/SExpr)) (lenv (Map String ty/Type)) (rest-frames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (pop-value fm))
        (val (.-first pv))
        (rem-values (.-second pv))
        (next-env (map-set lenv bname val))]
    (if (list-empty? brest)
      (let [(last-e (last-expr-unit tails))]
        (FrameMachine :frames (list-cons (f-eval last-e) rest-frames)
                      :values rem-values
                      :env next-env
                      :ret-type (.-ret-type fm)
                      :in-lambda (.-in-lambda fm)
                      :scope (.-scope fm)
                      :path (.-path fm)
                      :mod (.-mod fm)
                      :deps (.-deps fm)
                      :state (.-state fm)))
      (let [(next-b (r/first-expr-empty brest))
            (rem-brest (r/safe-tail brest))
            (bparts (mt next-b ((rd/sexpr-list bp) bp) ((rd/sexpr-vect bp) bp) (_ (list))))
            (next-bname (r/first-head-ident bparts))
            (next-bval (r/second-expr-empty bparts))]
        (FrameMachine :frames (list-cons (f-eval next-bval) (list-cons (f-let-val next-bname rem-brest tails next-env) rest-frames))
                      :values rem-values
                      :env next-env
                      :ret-type (.-ret-type fm)
                      :in-lambda (.-in-lambda fm)
                      :scope (.-scope fm)
                      :path (.-path fm)
                      :mod (.-mod fm)
                      :deps (.-deps fm)
                      :state (.-state fm))))))

(df fm-if-cond-step [(then-e rd/SExpr) (else-e rd/SExpr) (ienv (Map String ty/Type)) (rest-frames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (pop-value fm))
        (cond-ty (.-first pv))
        (rem-values (.-second pv))
        (st1 (expect-type (.-state fm) cond-ty (ty/ty-con "Bool" (list) (none) (none)) "if condition" (.-path fm)))]
    (FrameMachine :frames (list-cons (f-eval then-e) (list-cons (f-if-then else-e cond-ty ienv) rest-frames))
                  :values rem-values
                  :env ienv
                  :ret-type (.-ret-type fm)
                  :in-lambda (.-in-lambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state st1)))

(df fm-if-then-step [(else-e rd/SExpr) (then-ty ty/Type) (ienv (Map String ty/Type)) (rest-frames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (pop-value fm))
        (actual-then (.-first pv))
        (rem-values (.-second pv))
        (else-res (eval-with-env fm else-e ienv (.-state fm)))
        (else-ty (.-first else-res))
        (st1 (expect-type (.-second else-res) else-ty actual-then "if branches" (.-path fm)))]
    (FrameMachine :frames rest-frames
                  :values (list-cons actual-then rem-values)
                  :env ienv
                  :ret-type (.-ret-type fm)
                  :in-lambda (.-in-lambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state st1)))

(df fm-try-step [(val-var ty/Type) (rest-frames (List InferFrame)) (fm FrameMachine)] -> FrameMachine
  (let [(pv (pop-value fm))
        (inner-ty (.-first pv))
        (rem-values (.-second pv))
        (enclosing (mt (.-ret-type fm)
                     ((some r) (u/apply-subst (.-subst (.-state fm)) r))
                     ((none) (ty/ty-con "Result" (list val-var (unit-type)) (none) (none)))))
        (err-ty (mt enclosing
                  ((ty/ty-con _ rargs _ _)
                   (mt (list-get rargs 1) ((some e) e) ((none) (unit-type))))
                  (_ (unit-type))))
        (want-res (ty/ty-con "Result" (list val-var err-ty) (none) (none)))
        (st1 (expect-type (.-state fm) inner-ty want-res "try" (.-path fm)))]
    (FrameMachine :frames rest-frames
                  :values (list-cons val-var rem-values)
                  :env (.-env fm)
                  :ret-type (.-ret-type fm)
                  :in-lambda (.-in-lambda fm)
                  :scope (.-scope fm)
                  :path (.-path fm)
                  :mod (.-mod fm)
                  :deps (.-deps fm)
                  :state st1)))

(df fm-run [(fm FrameMachine) (budget Int64)] -> FrameMachine
  :d "Iterative doubling budget worklist execution loop."
  (let [(next-fm (fold fm-tick fm (range 0 budget)))]
    (if (list-empty? (.-frames next-fm))
      next-fm
      (fm-run next-fm (* budget 2)))))

(df run-expr-direct [(expr rd/SExpr) (env (Map String ty/Type)) (ret-type (Option ty/Type)) (in-lambda Bool) (scope String) (path String) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (st InferState)] -> (Pair ty/Type InferState)
  (let [(init-fm (FrameMachine :frames (list (f-eval expr))
                               :values (list)
                               :env env
                               :ret-type ret-type
                               :in-lambda in-lambda
                               :scope scope
                               :path path
                               :mod mod
                               :deps deps
                               :state st))]
    (let [(final-fm (fm-run init-fm 64))]
      (let [(out-ty (mt (list-head (.-values final-fm))
                      ((some t) t)
                      ((none) (unit-type))))
            (st-noted (note-map-type (.-state final-fm) out-ty scope))]
        (pair out-ty st-noted)))))

(df eval-with-env [(fm FrameMachine) (e rd/SExpr) (env (Map String ty/Type)) (st InferState)] -> (Pair ty/Type InferState)
  (run-expr-direct e env (.-ret-type fm) (.-in-lambda fm) (.-scope fm) (.-path fm) (.-mod fm) (.-deps fm) st))

(df eval-fm [(fm FrameMachine) (e rd/SExpr) (st InferState)] -> (Pair ty/Type InferState)
  (eval-with-env fm e (.-env fm) st))

(df check-undetermined-lambdas [(lambdas (List (Pair (List ty/Type) ty/Type))) (subst (Map Int64 ty/Type)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (lam (Pair (List ty/Type) ty/Type))] -> (List ty/Diagnostic)
          (let [(params (.-first lam))
                (ret (.-second lam))
                (all-tys (list-cons ret params))
                (has-unbound (fold (fn [(acc-u Bool) (t ty/Type)] -> Bool
                                     (or acc-u
                                         (let [(pruned (u/apply-subst subst t))]
                                           (mt pruned
                                             ((ty/ty-var _ _) true)
                                             (_ false)))))
                                   false
                                   all-tys))]
            (if has-unbound
              (list-cons (ty/Diagnostic :code "annotation" :message "nothing in this position determines the lambda's types; write them" :line 1 :col 1 :path path) a)
              a)))
        acc
        lambdas))

(df check-literal-ranges [(int-sites (List (Pair String Int64))) (subst (Map Int64 ty/Type)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (site (Pair String Int64))] -> (List ty/Diagnostic)
          (let [(tok-str (.-first site))
                (vid (.-second site))
                (wty (u/apply-subst subst (ty/ty-var vid "int")))
                (tname (mt wty
                         ((ty/ty-con n _ _ _) n)
                         (_ "Int64")))]
            (mt (ty/int-range-bounds tname)
              ((none) a)
              ((some b)
               (let [(low (.-first b))
                     (high (.-second b))
                     (num-opt (string-to-int64 tok-str))
                     (bad-lit? (mt num-opt ((none) true) ((some n) (or (< n low) (> n high)))))]
                 (if bad-lit?
                   (list-cons (ty/Diagnostic :code "literal-range" :message (str "the literal " tok-str " does not fit " tname " (" (string-from-int64 low) ".." (string-from-int64 high) ")") :line 1 :col 1 :path path) a)
                   a))))))
        acc
        int-sites))

(df map-has-key? [(m (Map String Bool)) (k String)] -> Bool
  (mt (map-get m k)
    ((some _) true)
    ((none) false)))

(df extract-map-keys-list [(types (List ty/Type)) (subst (Map Int64 ty/Type))] -> (List ty/Type)
  (fold (fn [(acc (List ty/Type)) (t ty/Type)] -> (List ty/Type)
          (list-append (extract-map-keys t subst) acc))
        (list)
        types))

(df extract-map-keys [(t ty/Type) (subst (Map Int64 ty/Type))] -> (List ty/Type)
  (let [(pruned (u/apply-subst subst t))]
    (mt pruned
      ((ty/ty-con name args _ _)
       (let [(sub-keys (extract-map-keys-list args subst))]
         (if (and (= name "Map") (>= (list-length args) 1))
           (list-cons (mt (list-head args) ((some k) k) ((none) pruned)) sub-keys)
           sub-keys)))
      ((ty/ty-fun params ret)
       (list-append (extract-map-keys ret subst) (extract-map-keys-list params subst)))
      ((ty/ty-var _ _) (list)))))

(df check-type-unordered [(t ty/Type) (subst (Map Int64 ty/Type)) (visited (Map String Bool)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary))] -> (Option String)
  (let [(pruned (u/apply-subst subst t))]
    (mt pruned
      ((ty/ty-var _ _) (none))
      ((ty/ty-fun _ _) (none))
      ((ty/ty-con name args opt-mod _)
       (if (ty/unordered-type? name)
         (some name)
         (let [(bad-arg (fold (fn [(acc (Option String)) (a ty/Type)] -> (Option String)
                                (mt acc
                                  ((some _) acc)
                                  ((none) (check-type-unordered a subst visited mod deps))))
                              (none)
                              args))]
           (mt bad-arg
             ((some b) (some b))
             ((none)
              (let [(type-key (str (mt opt-mod ((some m) m) ((none) (.-name mod))) "/" name))]
                (if (map-has-key? visited type-key)
                  (none)
                  (let [(next-vis (map-set visited type-key true))
                        (target-mod (mt opt-mod
                                      ((some m)
                                        (if (= m (.-name mod))
                                          (some mod)
                                          (mt (r/mod-import mod m)
                                            ((some mpath) (map-get deps mpath))
                                            ((none) (map-get deps m)))))
                                       ((none) (some mod))))]
                    (mt target-mod
                      ((none) (none))
                      ((some tmod)
                       (mt (r/mod-schema tmod name)
                         ((some ssum)
                          (fold (fn [(acc (Option String)) (f r/FieldSummary)] -> (Option String)
                                  (mt acc
                                    ((some _) acc)
                                    ((none)
                                     (let [(fty (ty/parse-type-str (.-type f) (list)))]
                                       (check-type-unordered fty subst next-vis tmod deps)))))
                                (none)
                                (.-fields ssum)))
                         ((none)
                          (mt (r/mod-enum tmod name)
                            ((some esum)
                             (fold (fn [(acc (Option String)) (c r/CaseSummary)] -> (Option String)
                                     (mt acc
                                       ((some _) acc)
                                       ((none)
                                        (fold (fn [(cacc (Option String)) (p (Pair String String))] -> (Option String)
                                                (mt cacc
                                                  ((some _) cacc)
                                                  ((none)
                                                   (let [(pty (qualify-type-with-mod (ty/parse-type-str (.-second p) (list)) mod deps))]
                                                     (check-type-unordered pty subst next-vis tmod deps)))))
                                              acc
                                              (.-params c)))))
                                   (none)
                                   (.-cases esum)))
                            ((none) (none))))))))))))))))))

(df check-map-key-rules [(map-sites (List (Pair ty/Type String))) (subst (Map Int64 ty/Type)) (mod r/ModuleSummary) (deps (Map String r/ModuleSummary)) (path String) (acc (List ty/Diagnostic))] -> (List ty/Diagnostic)
  (fold (fn [(a (List ty/Diagnostic)) (site (Pair ty/Type String))] -> (List ty/Diagnostic)
          (let [(ty-site (.-first site))
                (scope-lbl (.-second site))
                (mkeys (extract-map-keys ty-site subst))]
            (fold (fn [(ka (List ty/Diagnostic)) (k ty/Type)] -> (List ty/Diagnostic)
                    (mt (check-type-unordered k subst (map-empty) mod deps)
                      ((none) ka)
                      ((some bad)
                       (let [(shown (ty/show-type k))
                             (msg (if (= shown bad)
                                    (str shown " as a Map key has no total order; map-keys is specified to return keys sorted")
                                    (str "the Map key " shown " reaches " bad ", which has no total order; map-keys is specified to return keys sorted")))]
                         (list-cons (ty/Diagnostic :code "map-key-order" :message msg :line 1 :col 1 :path path) ka)))))
                  a
                  mkeys)))
        acc
        map-sites))

(df check-module [(forms (List a/TopForm)) (deps (Map String r/ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  :d "Purely functional semantic type checker for an AST module."
  (let [(summary (r/collect-summary forms path))
        (p12-diags (r/resolve-module summary forms deps))]
    (if (not (list-empty? p12-diags))
      p12-diags
      (let [(defun-diags (fold (fn [(acc (List ty/Diagnostic)) (form a/TopForm)] -> (List ty/Diagnostic)
                                 (mt form
                                   ((a/top-defun d)
                                    (let [(st0 (make-infer-state))
                                          (env0 (fold (fn [(e (Map String ty/Type)) (p a/Param)] -> (Map String ty/Type)
                                                        (map-set e (.-name p) (qualify-type-with-mod (ty/parse-type-str (.-type p) (list)) summary deps)))
                                                      (map-empty)
                                                      (.-params d)))
                                          (ret-ty (qualify-type-with-mod (ty/parse-type-str (.-ret-type d) (list)) summary deps))
                                          (scope-name (str "function " (.-name d)))
                                          (st-params (fold (fn [(s InferState) (p a/Param)] -> InferState
                                                             (note-map-type s (qualify-type-with-mod (ty/parse-type-str (.-type p) (list)) summary deps) scope-name))
                                                           st0
                                                           (.-params d)))
                                          (st-note (note-map-type st-params ret-ty scope-name))
                                          (body-nodes (.-body d))]
                                      (if (list-empty? body-nodes)
                                        acc
                                        (let [(last-e (last-expr-unit body-nodes))
                                              (res (run-expr-direct last-e env0 (some ret-ty) false scope-name path summary deps st-note))
                                              (last-ty (.-first res))
                                              (st1 (.-second res))
                                              (st2 (expect-type st1 last-ty ret-ty (str "return of " (.-name d)) path))
                                              (st3-subst (.-subst st2))
                                              (d-lam (check-undetermined-lambdas (.-lambdas st2) st3-subst path (.-diags st2)))
                                              (d-lit (check-literal-ranges (.-int-sites st2) st3-subst path d-lam))
                                              (d-map (check-map-key-rules (.-map-sites st2) st3-subst summary deps path d-lit))]
                                          (list-append d-map acc)))))
                                   (_ acc)))
                               (list)
                               forms))]
        defun-diags))))

(df parse-err-diag [(pe a/ParseError) (path String)] -> (List ty/Diagnostic)
  (list (ty/Diagnostic :code "parse" :message (.-msg pe) :line (.-line pe) :col (.-col pe) :path path)))

(df check-source [(src String) (deps (Map String r/ModuleSummary)) (path String)] -> (List ty/Diagnostic)
  :d "Parses and semantically checks an AgentScript source string."
  (mt (a/parse src)
    ((ok forms) (check-module forms deps path))
    ((err pe) (parse-err-diag pe path))))

(df ! check-file! [(path String) (roots (List String))] -> (Result (List ty/Diagnostic) IoError)
  :d "Effectful entry point: loads source and dependencies from filesystem and checks."
  (let [(src (try (file-read path)))]
    (mt (a/parse src)
      ((err pe) (ok (parse-err-diag pe path)))
      ((ok forms)
       (let [(summary (r/collect-summary forms path))
             (import-paths (r/map-values-list (.-imports summary)))
             (all-roots (list-cons (mt (parent-dir path) ((some p) p) ((none) ".")) roots))
             (deps (try (r/load-module-deps! all-roots import-paths)))]
         (ok (check-module forms deps path)))))))

(df parent-dir [(p String)] -> (Option String)
  (if (string-contains? p "/")
    (let [(parts (string-split p "/"))
          (segs (list-reverse (r/safe-tail (list-reverse parts))))]
      (if (list-empty? segs)
        (some ".")
        (some (string-join segs "/"))))
    (some ".")))
