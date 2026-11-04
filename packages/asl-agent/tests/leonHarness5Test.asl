(module aslAgent/tests/leonHarness5Test
  :x [runTests]
  :i [(aslAgent/journal :a j)])

; (:m :ref LEON-HARNESS5 :do "Leon's system prompt carries the harness5 rows asl launch renders and the leon client rules, and none of the old prose contract; no provider is called, the prompt is only built")

fn ! promptOf! root: String ctx: (Option Int64) plan: Bool -> String
  (match (j/buildSystemPrompt root "port the loop" root "02aff5d0" (list "./bin/asl test x") ctx plan)
    ((ok t) t)
    ((err e) (str "ERR " e)))

fn ! runTests -> Bool
  (let [root (resultOr (realPath ".") ".")
        full (promptOf! root (some 32000) true)
        small (promptOf! root (some 4000) false)
        bare (promptOf! root none false)
        has (fn [t s] (stringContains? t s))]
    (do
      (assert (not (has full "ERR ")) "the prompt builds from the repo grammar")
      (assert (has full "(:layer :id evidence") "harness5 row evidence is in Leon's prompt")
      (assert (not (has full "(:layer :id breaker")) "the shell-only breaker row, with its (:witness) literal no op runs, is not in Leon's prompt")
      (assert (has full "(:exit (:done :when (written gatesPass))") "the leon client rules carry the exit row")
      (assert (has full "(:layer :id attractors (:mode implement") "harness5 attractors are bound to mode implement")
      (assert (has full "(:layer :id clientRules (:is reply asnForms)") "the leon client rules of clients.asn render as the clientRules layer")
      (assert (has full "(:glossary (:term") "the harness5 glossary renders")
      (assert (has full "ERR_BOUNDARY_VIOLATION") "the loop protocol row about the workspace boundary is kept")
      (assert (has full "(:escalate :reason s") "the escalate form is named in the protocol rows, with or without :seen and :tried")
      (assert (has full "(:plan :first") "a plan run carries the plan row")
      (assert (has full "(:gates :run") "declared gates render as a gates row")
      (assert (not (has full "(:task \"port the loop\")")) "the task is not in the system prompt; the user turn carries it once")
      (assert (has full "(:base \"02aff5d0\")") "the base is an ASN row")
      (assert (not (has full "answer contract:")) "the old prose answer contract is gone")
      (assert (not (has full "grounding: a claim holds")) "the old prose grounding sentence is gone")
      (assert (not (has full "never writes a bare except")) "the Python-only restriction is gone")
      (assert (not (has full "Task: ")) "no prose Task line")
      (assert (not (has small "(:plan :first")) "a run without plan carries no plan row")
      (assert (has small "(:layer :id evidence") "a small context still gets the harness rows")
      (assert (not (has bare "(:layer :id evidence")) "an absent context budget renders no harness layers")
      (assert (has bare "(:batch :example") "the dynamic loop rows stay without a budget")
      true))
