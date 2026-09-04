(module asl-checker/unify
  :d "Hindley-Milner Functional Type Unification for AgentScript"
  :x [UnifyOutcome
      apply-subst
      occurs-in?
      kind-narrow
      type-equal?
      unify]
  :i [(types :a ty)])

(dfe UnifyOutcome
  (:c u-ok [(subst (Map Int64 ty/Type))] "Unification succeeded with updated substitution")
  (:c u-err [(msg String) (numeric Bool)] "Unification failed with message and numeric mismatch flag"))

(df resolve-var-subst [(subst (Map Int64 ty/Type)) (cur ty/Type)] -> ty/Type
  :d "Iteratively follows metavariable chains in Python for loop to avoid stack overflow."
  (fold (fn [(t ty/Type) (step-idx Int64)] -> ty/Type
          (mt t
            ((ty/ty-var id _)
             (mt (map-get subst id)
               ((some nxt)
                (mt nxt
                  ((ty/ty-var nid _) (if (= nid id) t nxt))
                  (_ nxt)))
               ((none) t)))
            (_ t)))
        cur
        (range 0 5000)))

(df apply-subst-list [(subst (Map Int64 ty/Type)) (ts (List ty/Type))] -> (List ty/Type)
  :d "Applies substitution to a list of types."
  (map (fn [(item ty/Type)] -> ty/Type (apply-subst subst item)) ts))

(df apply-subst [(subst (Map Int64 ty/Type)) (t ty/Type)] -> ty/Type
  :d "Resolves metavariable chains in t until a fixed point is reached."
  (let [(root (resolve-var-subst subst t))]
    (mt root
      ((ty/ty-var _ _) root)
      ((ty/ty-con name args mod shown)
       (ty/ty-con name (apply-subst-list subst args) mod shown))
      ((ty/ty-fun params ret)
       (ty/ty-fun (apply-subst-list subst params) (apply-subst subst ret))))))

(df occurs-in? [(id Int64) (t ty/Type) (subst (Map Int64 ty/Type))] -> Bool
  :d "Occurs check: returns true if metavar id occurs free in t after pruning."
  (let [(pruned (apply-subst subst t))]
    (mt pruned
      ((ty/ty-var id2 _) (= id id2))
      ((ty/ty-con _ args _ _)
       (fold (fn [(acc Bool) (arg ty/Type)] -> Bool
               (or acc (occurs-in? id arg subst)))
             false
             args))
      ((ty/ty-fun params ret)
       (or (fold (fn [(acc Bool) (p ty/Type)] -> Bool
                   (or acc (occurs-in? id p subst)))
                 false
                 params)
           (occurs-in? id ret subst))))))

(df kind-narrow [(k1 String) (k2 String)] -> (Option String)
  :d "Lattice narrowing for type variable kinds: any < num < int."
  (cond
    ((= k1 "any") (some k2))
    ((= k2 "any") (some k1))
    ((= k1 "num")
     (if (or (= k2 "num") (= k2 "int")) (some k2) (none)))
    ((= k1 "int")
     (if (or (= k2 "num") (= k2 "int")) (some "int") (none)))
    (:else (none))))

(df same-length? [(l1 (List ty/Type)) (l2 (List ty/Type))] -> Bool
  (= (list-length l1) (list-length l2)))

(df diff-length? [(l1 (List ty/Type)) (l2 (List ty/Type))] -> Bool
  (not (= (list-length l1) (list-length l2))))

(df type-list-equal? [(l1 (List ty/Type)) (l2 (List ty/Type))] -> Bool
  (and (same-length? l1 l2)
       (fold (fn [(acc Bool) (p (Pair ty/Type ty/Type))] -> Bool
               (and acc (type-equal? (.-first p) (.-second p))))
             true
             (zip l1 l2))))

(df mod-differs? [(m1 (Option String)) (m2 (Option String))] -> Bool
  (mt m1
    ((none) false)
    ((some s1)
     (mt m2
       ((none) false)
       ((some s2) (not (= s1 s2)))))))

(df mod-compatible? [(m1 (Option String)) (m2 (Option String))] -> Bool
  (mt m1
    ((none) true)
    ((some s1)
     (mt m2
       ((none) true)
       ((some s2) (= s1 s2))))))

(df type-equal? [(t1 ty/Type) (t2 ty/Type)] -> Bool
  :d "Structural equality on Type trees."
  (mt t1
    ((ty/ty-var id1 _)
     (mt t2
       ((ty/ty-var id2 _) (= id1 id2))
       (_ false)))
    ((ty/ty-con n1 a1 m1 _)
     (mt t2
       ((ty/ty-con n2 a2 m2 _)
        (and (= n1 n2)
             (and (mod-compatible? m1 m2)
                  (and (same-length? a1 a2)
                       (type-list-equal? a1 a2)))))
       (_ false)))
    ((ty/ty-fun p1 r1)
     (mt t2
       ((ty/ty-fun p2 r2)
        (and (same-length? p1 p2)
             (and (type-list-equal? p1 p2)
                  (type-equal? r1 r2))))
       (_ false)))))

(df unify-lists [(l1 (List ty/Type)) (l2 (List ty/Type)) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (diff-length? l1 l2)
    (u-err "type argument arity mismatch" false)
    (fold (fn [(res UnifyOutcome) (p (Pair ty/Type ty/Type))] -> UnifyOutcome
            (mt res
              ((u-ok cur-subst) (unify (.-first p) (.-second p) cur-subst))
              ((u-err _ _) res)))
          (u-ok subst)
          (zip l1 l2))))

(df bind-var-checked [(id Int64) (target ty/Type) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (occurs-in? id target subst)
    (u-err "occurs check failed: cyclic substitution" false)
    (u-ok (map-set subst id target))))

(df bind-var-con [(id Int64) (k String) (c-ty ty/Type) (c-name String) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (and (= k "num") (not (ty/is-numeric-type? c-name)))
    (u-err (str "expected a number, found " (ty/show-type c-ty)) (ty/is-numeric-type? c-name))
    (if (and (= k "int") (not (ty/is-integral-type? c-name)))
      (u-err (str "expected an integer, found " (ty/show-type c-ty)) (ty/is-numeric-type? c-name))
      (bind-var-checked id c-ty subst))))

(df bind-var-fun [(id Int64) (k String) (fun-ty ty/Type) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (= k "any")
    (bind-var-checked id fun-ty subst)
    (u-err "cannot unify function with numeric kind" false)))

(df err-expected-found [(a ty/Type) (b ty/Type) (num-mismatch Bool)] -> UnifyOutcome
  (u-err (str "expected " (ty/show-type a) ", found " (ty/show-type b)) num-mismatch))

(df unify [(t1 ty/Type) (t2 ty/Type) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  :d "Unifies two types under an immutable substitution, returning u-ok or u-err."
  (let [(a (apply-subst subst t1))
        (b (apply-subst subst t2))]
    (if (type-equal? a b)
      (u-ok subst)
      (mt a
        ((ty/ty-var id1 k1)
         (mt b
           ((ty/ty-var id2 k2)
            (mt (kind-narrow k1 k2)
              ((some nk)
               (if (= id1 id2)
                 (u-ok subst)
                 (let [(s1 (map-set subst id1 (ty/ty-var id2 nk)))]
                   (u-ok (map-set s1 id2 (ty/ty-var id2 nk))))))
              ((none) (u-err "kind mismatch" false))))
           ((ty/ty-con b-name _ _ _)
            (bind-var-con id1 k1 b b-name subst))
           ((ty/ty-fun _ _)
            (bind-var-fun id1 k1 b subst))))
        ((ty/ty-con a-name a-args a-mod a-shown)
         (mt b
           ((ty/ty-var _ _)
            (unify b a subst))
           ((ty/ty-con b-name b-args b-mod b-shown)
            (if (or (not (= a-name b-name))
                    (or (mod-differs? a-mod b-mod)
                        (diff-length? a-args b-args)))
              (let [(num-mismatch (and (ty/is-numeric-type? a-name) (ty/is-numeric-type? b-name)))]
                (err-expected-found a b num-mismatch))
              (unify-lists a-args b-args subst)))
           ((ty/ty-fun _ _)
            (err-expected-found a b false))))
        ((ty/ty-fun a-params a-ret)
         (mt b
           ((ty/ty-var _ _)
            (unify b a subst))
           ((ty/ty-con _ _ _ _)
            (err-expected-found a b false))
           ((ty/ty-fun b-params b-ret)
            (if (diff-length? a-params b-params)
              (err-expected-found a b false)
              (mt (unify-lists a-params b-params subst)
                ((u-ok next-subst) (unify a-ret b-ret next-subst))
                ((u-err msg num) (u-err msg num)))))))))))
