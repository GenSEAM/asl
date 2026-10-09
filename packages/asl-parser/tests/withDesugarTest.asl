(module asl-parser/withDesugarTest
  :x [runTests]
  :i [(asl-parser/ast :a ast) (asl-parser/reader :a rd)])

fn bodyOf src: String name: String -> String
  (mt (ast/parse src)
    ((ok forms) (stringJoin (map (fn [f] (mt f ((ast/topDefun d) (if (= d.name name) (stringJoin (map rd/renderSexpr d.body) " ") "")) (_ ""))) forms) ""))
    ((err e) (str "ERR " e.msg)))

fn header -> String
  "(module m :x [f])\n\n(schema P (:f a Int64 \"\") (:f b String \"\") (:f c Bool \"\"))\n\n"

fn runTests -> Bool
  (do
    (assert (= (bodyOf (str (header) "fn f p: P -> P\n  (with p :a (+ p.a 1) :c false)\n") "f") "(P :a (+ p.a 1) :b p.b :c false)")
            "with on a parameter of a local schema expands to the full construction in declared field order")
    (assert (= (bodyOf (str (header) "fn f p: P -> P\n  (g (with p :b \"x\"))\n") "f") "(g (P :a p.a :b \"x\" :c p.c))")
            "a nested with expands in place")
    (assert (= (bodyOf (str (header) "fn f p: Q -> Q\n  (with p :b \"x\")\n") "f") "(with p :b \"x\")")
            "with on a parameter of an unknown schema stays for the checker")
    (assert (= (bodyOf (str (header) "fn f p: P -> P\n  (with p :z 1)\n") "f") "(with p :z 1)")
            "with naming an unknown field stays for the checker")
    (assert (= (bodyOf (str (header) "fn f p: P -> Int64\n  (g (h p).a.b \"(x).y\" (k (m p)).c)\n") "f") "(g (h p).a.b \"(x).y\" (k (m p)).c)")
            "the fn-header path reads (expr).f.g as nested field access and leaves strings alone")
    (assert (stringContains? (bodyOf (str (header) "fn f p: P -> Int64\n  (.-a p)\n") "f") "ERR_READ_FIELD (.-a x) is retired: write x.a")
            "the fn-header path rejects the retired (.-f x) spelling with a fix hint")
    (assert (= (bodyOf (str (header) "fn f p: P -> String\n  (str \"(.-a p)\" :.-a)\n") "f") "(str \"(.-a p)\" :.-a)")
            "the fn-header path leaves .- inside strings and keywords alone")
    (assert (= (bodyOf (str (header) "fn f -> Int64\n  (let [(o (P :a 1 :b \"x\" :c true)) (o2 (with o :a 9))] o2.a)\n") "f") "(let (list (o (P :a 1 :b \"x\" :c true)) (o2 (P :a 9 :b o.b :c o.c))) o2.a)")
            "with on a let-bound record of a local schema expands")
    (assert (= (bodyOf (str (header) "fn f -> P\n  (with (g 1) :a 2)\n\nfn g n: Int64 -> P\n  (P :a n :b \"\" :c true)\n") "f") "(let [(withSource0 (g 1))] (P :a 2 :b withSource0.b :c withSource0.c))")
            "with on a call returning a local schema binds the source once")
    (assert (= (bodyOf (str (header) "fn f p: P -> P\n  (mt (h p) ((some p) (with p :a 2)) ((none) p))\n") "f") "(mt (h p) ((some p) (with p :a 2)) ((none) p))")
            "an mt arm that rebinds p hides p's schema, so with stays for the checker")
    (assert (= (bodyOf (str (header) "fn f p: P -> P\n  (with (g withSource0) :a 2)\n\nfn g n: Int64 -> P\n  (P :a n :b \"\" :c true)\n") "f") "(let [(withSource1 (g withSource0))] (P :a 2 :b withSource1.b :c withSource1.c))")
            "the source binding never captures a name the with form uses")
    (assert (stringContains? (bodyOf (str (header) "fn f p: P -> P\n  (g (lambda [(p R)] -> R (with p :a 7)))\n") "f") "(with p :a 7)")
            "a lambda parameter p hides the outer p: P, so with stays for the checker")
    (assert (stringContains? (bodyOf (str (header) "fn f p: P -> P\n  (g (lambda [p] (with p :a 7)))\n") "f") "(with p :a 7)")
            "an untyped lambda parameter p hides the outer p: P too")
    true)
