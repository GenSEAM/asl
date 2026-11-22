(module asl-agent/tests/promptEchoTest
  :x [runTests]
  :i [(asl-agent/promptEcho :a pe)])

; (:m :ref LEON-ECHO-GUARD :do "the classifier half of the echo guard: a reply that copies two prompt paragraphs is echo, an ASN step reply on the same task is not, a five-token reply has share 0.0, and a reply whose 8-grams are exactly half from the prompt is not echo because the boundary is strict")

fn para1 -> String
  "the agent loop reads the task and writes one file at a time before the gates run"

fn para2 -> String
  "a reply that copies the prompt back is not work and the guard must name it as echo"

fn taskText -> String
  (str (para1) "\n\n" (para2) "\n\n" "owned paths at claim: asl/packages/asl-agent/src/promptEcho.asl")

fn copied -> String
  (str (para1) "\n\n" (para2))

fn stepReply -> String
  "(:step :op \"write\" :file \"asl/packages/asl-agent/src/promptEcho.asl\" :content :raw)\n(:step :op \"gate\")"

fn halfPrompt -> String
  "aa bb cc dd ee ff gg hh"

fn halfReply -> String
  "aa bb cc dd ee ff gg hh ii"

fn ! runTests -> Bool
  (let [share (pe/echoShare (taskText) (copied) 8)
        half (pe/echoShare (halfPrompt) (halfReply) 8)]
    (do
      (assert (>= share 0.9) (str "a reply that copies two prompt paragraphs is echo, share " (stringFromFloat64 share)))
      (assert (pe/promptEcho? (taskText) (copied)) "promptEcho? is true for the copied reply")
      (assert (not (pe/promptEcho? (taskText) (stepReply))) "an ASN step reply on the same task is not echo")
      (assert (= (pe/echoShare (taskText) (stepReply) 8) 0.0) "the step reply shares no 8-gram with the prompt")
      (assert (= (pe/echoShare (taskText) "one two three four five" 8) 0.0) "a five-token reply has share 0.0")
      (assert (not (pe/promptEcho? (taskText) "one two three four five")) "and is not echo")
      (assert (= half 0.5) (str "half the 8-grams from the prompt is share 0.5, got " (stringFromFloat64 half)))
      (assert (not (pe/promptEcho? (halfPrompt) (halfReply))) "0.5 is not above 0.5, so it is not echo")
      (assert (= (listLength (pe/ngramsOf "a b c d" 2)) 3) "four tokens give three bigrams")
      (assert (= (optionOr (listHead (pe/ngramsOf "A B C" 1)) "") "a") "tokens are lowercased")
      (assert (= (listLength (pe/ngramsOf "a\nb\nc" 2)) 2) "a newline separates tokens")
      (assert (listEmpty? (pe/ngramsOf "a b" 3)) "fewer tokens than n give no n-gram")
      true))
