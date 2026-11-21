(module aslAgent/tests/commitResumeFlagTest
  :x [runTests]
  :i [(aslAgent/main :a m)])

; (:m :ref LIVELOOP-COMMIT-RESUME :do "the resumed run args must copy ra.commit: :commit true on the invocation survives the resume path, and an absent :commit stays false")

fn ! resumeState -> m/ResumeState
  (m/ResumeState :session "s" :journal "j" :task "t" :modeHint none :intent none :owns (list) :gates (list) :base "main"
                 :contextTokens none :note "" :result none :history (list) :turn 0 :reply "" :plan none)

fn ! runArgsOf form: String -> m/RunArgs
  (m/runArgsOf (m/parseInvocation form ".").params 600 1200 false)

fn ! runTests -> Bool
  (do
    (assert (let [ra (runArgsOf "(:agent :task \"t\" :commit true)")
                  st (resumeState)]
              (m/resumed ra st).commit)
      ":commit true survives the resume path")
    (assert (not (let [ra (runArgsOf "(:agent :task \"t\")")
                       st (resumeState)]
                   (m/resumed ra st).commit))
      "no :commit key stays false through the resume path")
    true)
