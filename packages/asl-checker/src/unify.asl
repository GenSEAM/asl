(module asl-checker/unify
  :d "Hindley-Milner Functional Type Unification for AgentScript"
  :x [UnifyOutcome
      applySubst
      occursIn?
      kindNarrow
      typeEqual?
      unify
      resolveVarSubst
      resolveVarSubstRec]
  :i [(types :a ty)])

(dfe UnifyOutcome
  (:c uOk [(subst (Map Int64 ty/Type))] "Unification succeeded with updated substitution")
  (:c uErr [(msg String) (numeric Bool)] "Unification failed with message and numeric mismatch flag"))

(df resolveVarSubstRec [(subst (Map Int64 ty/Type)) (cur ty/Type) (fuel Int64)] -> ty/Type
  :d "Recursively follows metavariable substitution chains with fuel bound to prevent cycles."
  (if (<= fuel 0)
    cur
    (mt cur
      ((ty/tyVar id _)
       (mt (map-get subst id)
         ((some nxt)
          (mt nxt
            ((ty/tyVar nid _)
             (if (= nid id)
               cur
               (resolveVarSubstRec subst nxt (- fuel 1))))
            (_ nxt)))
         ((none) cur)))
      (_ cur))))

(df resolveVarSubst [(subst (Map Int64 ty/Type)) (cur ty/Type)] -> ty/Type
  :d "Resolves metavariable chains using bounded recursion."
  (resolveVarSubstRec subst cur 100))

(df applySubstList [(subst (Map Int64 ty/Type)) (ts (List ty/Type))] -> (List ty/Type)
  :d "Applies substitution to a list of types."
  (map (fn [(item ty/Type)] -> ty/Type (applySubst subst item)) ts))

(df applySubst [(subst (Map Int64 ty/Type)) (t ty/Type)] -> ty/Type
  :d "Resolves metavariable chains in t until a fixed point is reached."
  (let [(root (resolveVarSubst subst t))]
    (mt root
      ((ty/tyVar _ _) root)
      ((ty/tyCon name args mod shown)
       (ty/tyCon name (applySubstList subst args) mod shown))
      ((ty/tyFun params ret)
       (ty/tyFun (applySubstList subst params) (applySubst subst ret))))))

(df occursIn? [(id Int64) (t ty/Type) (subst (Map Int64 ty/Type))] -> Bool
  :d "Occurs check: returns true if metavar id occurs free in t after pruning."
  (let [(pruned (applySubst subst t))]
    (mt pruned
      ((ty/tyVar id2 _) (= id id2))
      ((ty/tyCon _ args _ _)
       (fold (fn [(acc Bool) (arg ty/Type)] -> Bool
               (or acc (occursIn? id arg subst)))
             false
             args))
      ((ty/tyFun params ret)
       (or (fold (fn [(acc Bool) (p ty/Type)] -> Bool
                   (or acc (occursIn? id p subst)))
                 false
                 params)
           (occursIn? id ret subst))))))

(df kindNarrow [(k1 String) (k2 String)] -> (Option String)
  :d "Lattice narrowing for type variable kinds: any < num < int."
  (cond
    ((= k1 "any") (some k2))
    ((= k2 "any") (some k1))
    ((= k1 "num")
     (if (or (= k2 "num") (= k2 "int")) (some k2) (none)))
    ((= k1 "int")
     (if (or (= k2 "num") (= k2 "int")) (some "int") (none)))
    (:else (none))))

(df sameLength? [(l1 (List ty/Type)) (l2 (List ty/Type))] -> Bool
  (= (list-length l1) (list-length l2)))

(df diffLength? [(l1 (List ty/Type)) (l2 (List ty/Type))] -> Bool
  (not (= (list-length l1) (list-length l2))))

(df typeListEqualStep [(l1 (List ty/Type)) (l2 (List ty/Type)) (idx Int64) (len Int64)] -> Bool
  (if (>= idx len)
      true
      (let [(t1 (option-or (list-get l1 idx) (ty/tyVar -1 "any")))
            (t2 (option-or (list-get l2 idx) (ty/tyVar -1 "any")))]
        (if (typeEqual? t1 t2)
            (typeListEqualStep l1 l2 (+ idx 1) len)
            false))))

(df typeListEqual? [(l1 (List ty/Type)) (l2 (List ty/Type))] -> Bool
  (and (sameLength? l1 l2)
       (typeListEqualStep l1 l2 0 (list-length l1))))

(df modDiffers? [(m1 (Option String)) (m2 (Option String))] -> Bool
  (mt m1
    ((none) false)
    ((some s1)
     (mt m2
       ((none) false)
       ((some s2) (not (= s1 s2)))))))

(df modCompatible? [(m1 (Option String)) (m2 (Option String))] -> Bool
  (mt m1
    ((none) true)
    ((some s1)
     (mt m2
       ((none) true)
       ((some s2) (= s1 s2))))))

(df typeEqual? [(t1 ty/Type) (t2 ty/Type)] -> Bool
  :d "Structural equality on Type trees."
  (mt t1
    ((ty/tyVar id1 _)
     (mt t2
       ((ty/tyVar id2 _) (= id1 id2))
       (_ false)))
    ((ty/tyCon n1 a1 m1 _)
     (mt t2
       ((ty/tyCon n2 a2 m2 _)
        (and (= n1 n2)
             (and (modCompatible? m1 m2)
                  (and (sameLength? a1 a2)
                       (typeListEqual? a1 a2)))))
       (_ false)))
    ((ty/tyFun p1 r1)
     (mt t2
       ((ty/tyFun p2 r2)
        (and (sameLength? p1 p2)
             (and (typeListEqual? p1 p2)
                  (typeEqual? r1 r2))))
       (_ false)))))

(df unifyListsStep [(l1 (List ty/Type)) (l2 (List ty/Type)) (idx Int64) (len Int64) (curSubst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (>= idx len)
      (uOk curSubst)
      (let [(t1 (option-or (list-get l1 idx) (ty/tyVar -1 "any")))
            (t2 (option-or (list-get l2 idx) (ty/tyVar -1 "any")))
            (res (unify t1 t2 curSubst))]
        (mt res
          ((uOk nextSubst) (unifyListsStep l1 l2 (+ idx 1) len nextSubst))
          ((uErr _ _) res)))))

(df unifyLists [(l1 (List ty/Type)) (l2 (List ty/Type)) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (diffLength? l1 l2)
    (uErr "type argument arity mismatch" false)
    (unifyListsStep l1 l2 0 (list-length l1) subst)))

(df bindVarChecked [(id Int64) (target ty/Type) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (occursIn? id target subst)
    (uErr "occurs check failed: cyclic substitution" false)
    (uOk (map-set subst id target))))

(df bindVarCon [(id Int64) (k String) (cTy ty/Type) (cName String) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (and (= k "num") (not (ty/isNumericType? cName)))
    (uErr (str "expected a number, found " (ty/showType cTy)) (ty/isNumericType? cName))
    (if (and (= k "int") (not (ty/isIntegralType? cName)))
      (uErr (str "expected an integer, found " (ty/showType cTy)) (ty/isNumericType? cName))
      (bindVarChecked id cTy subst))))

(df bindVarFun [(id Int64) (k String) (funTy ty/Type) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  (if (= k "any")
    (bindVarChecked id funTy subst)
    (uErr "cannot unify function with numeric kind" false)))

(df errExpectedFound [(a ty/Type) (b ty/Type) (numMismatch Bool)] -> UnifyOutcome
  (uErr (str "expected " (ty/showType a) ", found " (ty/showType b)) numMismatch))

(df unify [(t1 ty/Type) (t2 ty/Type) (subst (Map Int64 ty/Type))] -> UnifyOutcome
  :d "Unifies two types under an immutable substitution, returning u-ok or u-err."
  (let [(a (applySubst subst t1))
        (b (applySubst subst t2))]
    (if (typeEqual? a b)
      (uOk subst)
      (mt a
        ((ty/tyVar id1 k1)
         (mt b
           ((ty/tyVar id2 k2)
            (mt (kindNarrow k1 k2)
              ((some nk)
               (if (= id1 id2)
                 (uOk subst)
                 (let [(s1 (map-set subst id1 (ty/tyVar id2 nk)))]
                   (uOk (map-set s1 id2 (ty/tyVar id2 nk))))))
              ((none) (uErr "kind mismatch" false))))
           ((ty/tyCon bName _ _ _)
            (bindVarCon id1 k1 b bName subst))
           ((ty/tyFun _ _)
            (bindVarFun id1 k1 b subst))))
        ((ty/tyCon aName aArgs aMod aShown)
         (mt b
           ((ty/tyVar _ _)
            (unify b a subst))
           ((ty/tyCon bName bArgs bMod bShown)
            (if (or (not (= aName bName))
                    (or (modDiffers? aMod bMod)
                        (diffLength? aArgs bArgs)))
              (let [(numMismatch (and (ty/isNumericType? aName) (ty/isNumericType? bName)))]
                (errExpectedFound a b numMismatch))
              (unifyLists aArgs bArgs subst)))
           ((ty/tyFun _ _)
            (errExpectedFound a b false))))
        ((ty/tyFun aParams aRet)
         (mt b
           ((ty/tyVar _ _)
            (unify b a subst))
           ((ty/tyCon _ _ _ _)
            (errExpectedFound a b false))
           ((ty/tyFun bParams bRet)
            (if (diffLength? aParams bParams)
              (errExpectedFound a b false)
              (mt (unifyLists aParams bParams subst)
                ((uOk nextSubst) (unify aRet bRet nextSubst))
                ((uErr msg num) (uErr msg num)))))))))))
