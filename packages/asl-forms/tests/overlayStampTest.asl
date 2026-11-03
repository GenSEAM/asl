(module asl-forms/tests/overlayStampTest :x [runTests] :i [(asl-forms/gate :a g)])

; (:m :ref RELAY-FORMS-SLOW :do "a staged edit is checked in an overlay copy of the tree; the copy's deps are byte-identical to the workspace's, so the check summarises them from the workspace stamp instead of re-checking every body (nativeTest.asl: 81 bodies, about 40 s per staged edit on node2)")
fn ! put! root: String rel: String text: String -> Bool
  (let [(p (str root "/" rel))
        (parts (stringSplit p "/"))
        (_ (dirCreate (stringJoin (listTake parts (- (listLength parts) 1)) "/")))]
    (ok? (fileWrite p text)))

fn ! tree! root: String a: String b: String -> Bool
  (and (put! root ".asl.config.asn" "(:aslConfig :workspace \"ovs\" :root true)\n") (and (put! root "asl/ovs/b.asl" b) (put! root "asl/ovs/a.asl" a)))

fn ! runTests -> Bool
  (let [(tag (str (stringFromInt64 (procSelf)) "x" (stringFromInt64 (monotonicNs))))
        (w (str "/tmp/overlayStampW_" tag))
        (o (str "/tmp/overlayStampO_" tag))
        (b (str "(module asl/ovs/b\n  :x [two]\n  :i [])\n\n; (:m :do \"" tag "\")\nfn two -> Int64\n  2\n"))
        (a "(module asl/ovs/a\n  :x [main]\n  :i [(asl/ovs/b :a b)])\n\nfn main -> Int64\n  (b/two)\n")
        (made (and (tree! w a b) (tree! o a b)))
        (first (g/nativeCheck! w "asl/ovs/a.asl"))
        (again (g/nativeCheck! w "asl/ovs/a.asl"))
        (copy (g/nativeCheck! o "asl/ovs/a.asl"))
        (_ (pathRemove w))
        (_ (pathRemove o))]
    (do
      (assert made "the workspace and its copy are written")
      (assert (= first.code 0) (str "the workspace check passes: " first.out first.errText))
      (assert (stringContains? again.out ":summarised 1") (str "precondition: a repeat workspace check reuses its stamp: " again.out))
      (assert (= copy.code 0) (str "the copy check passes: " copy.out copy.errText))
      (assert (stringContains? copy.out ":summarised 1") (str "a check of a byte-identical copy reuses the workspace stamp: " copy.out))
      (refute (stringContains? copy.out ":checked 2") (str "the copy's dependency body is not checked again: " copy.out))
      (refute (fileExists? w) "the scratch trees are removed")
      true))
