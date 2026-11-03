(module asl/agentLoop/tests/writeRejectTest
  :x [runTests]
  :i [(asl/agentLoop/reply :a r) (asl/agentLoop/txn :a t)])

; (:m :ref LEON-WRITE-REJECT :do "shapes from node2 journals 2026-11-01 (757c44c7, 07d58b01, 4da6a09d): a write step whose :raw had its file text right after the closed form without a fence, or :raw followed by the quoted text, was refused ERR_RAW_MISSING 57 times of 70; a checker refusal carried the cut tail of the nested receipt as its :message instead of the checker's :syntaxMessage")

fn bareReply -> String
  "(:step :op \"write\" :file \"a/b.asl\" :content :raw)\n(module a/b\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n(:step :op \"done\")"

fn inlineReply -> String
  "(:step :op \"write\" :file \"a/b.asl\" :content :raw \"(module a/b :x [] :i [])\")"

fn fencedReply -> String
  "(:step :op \"write\" :file \"a/b.asl\" :content :raw)\n```\nhello\n```\n"

fn proseReply -> String
  "(:step :op \"write\" :file \"docs/a.md\" :content :raw)\nI will now write the file with the new section.\n(:done :summary \"x\")"

fn doneAfterReply -> String
  "(:step :op \"write\" :file \"a/b.asl\" :content :raw)\n(module a/b :x [] :i [])\n(:done :summary \"x\")"

fn asnReply -> String
  "(:step :op \"write\" :file \"a/b.asn\" :content :raw)\n(:row :id 1)\n(:row :id 2)\n(:done)"

fn checkerOut -> String
  "(:receipt :op txn :status :aborted :error :ERR_TXN_ABORTED :detail (:step :file \"a/b.asl\" :staged true :bytes 48968 :pendingFlush true :balanced true :syntax :error :checker \"asl-checker\" :forced true :syntaxMessage \"a/b.asl:62:4: ERR_TYPE_MISMATCH if condition: expected Bool, found (Option _)\" :repaired ()))"

fn ! runTests -> Bool
  (let [bare (r/bindRawBlocks (bareReply))
        inl (r/bindRawBlocks (inlineReply))
        fen (r/bindRawBlocks (fencedReply))
        prs (r/bindRawBlocks (proseReply))
        dn (r/bindRawBlocks (doneAfterReply))
        asn (r/bindRawBlocks (asnReply))
        ref (t/txnRefusal (checkerOut) "" "ERR_WRITE_FAILED" none)]
    (do
      (assert (= bare.count 1) "a bare tail after the closed :raw step binds as the one raw block")
      (assert (stringContains? bare.text ":content \"(module a/b\\n  :x [f]") "the bare text is the :content")
      (assert (not (stringContains? bare.text ":content :raw")) "no :raw is left unbound")
      (assert (stringContains? bare.text "(:step :op \"done\")") "the next step stays a step")
      (assert (listEmpty? bare.missing) "nothing is missing")
      (assert (stringContains? inl.text ":content  \"(module a/b :x [] :i [])\"") "an inline :raw string drops the :raw")
      (assert (not (stringContains? inl.text ":raw \"")) "no :raw before the quoted text")
      (assert (= fen.count 1) "a fenced block still binds as before")
      (assert (stringContains? fen.text ":content \"hello\\n\"") "the fenced text is the content")
      (assert (stringContains? (pairSecond ref) "ERR_TYPE_MISMATCH if condition") "the checker's syntaxMessage is the refusal message")
      (assert (not (stringContains? (pairSecond ref) "ERR_WRITE_FAILED")) "no cut tail of the nested receipt")
      (assert (= prs.count 0) "prose after a raw step for a .md target is not bound as content")
      (assert (stringContains? prs.text "(:done :summary") "the done step after prose is kept")
      (assert (= dn.count 1) "a form tail followed by (:done binds the module text")
      (assert (stringContains? dn.text "(:done :summary") "the (:done step is not swallowed into the content")
      (assert (not (stringContains? dn.text "x\\\")\\n")) "the done form is not inside the content string")
      (assert (stringContains? asn.text "(:done)") "an .asn tail ends at (:done")
      (assert (stringContains? asn.text "(:row :id 2)\\n\"") "an .asn tail binds the rows up to the done step")
      true))
