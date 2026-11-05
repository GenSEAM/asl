(module asl/tools/vcs/tests/vcsChild
  :x [main]
  :i [(asl-tools/vcs/vcs :a v)])

; (:m :ref VCS-LAYER-CORE :do "test helper, not a suite: asl run vcsChild.asl REPO ASLROOT PATH MSG commits PATH through the vcs layer and prints the receipt, so vcsTest can run the layer as a child with a hostile git environment")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(r (v/commit! (optionOr (listGet args 0) "") (optionOr (listGet args 1) "") (list (optionOr (listGet args 2) "")) (optionOr (listGet args 3) "") "commit"))]
    (do (println r.text) (ok r.code)))
