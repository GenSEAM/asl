(module asl/agentLoop/frame
  :x [Frame frameMaxTokens peersClip estimateTokens leaksEgress renderFrame]
  :i [])

(schema Frame
  (:f unit String)
  (:f kind String)
  (:f atoms (List String))
  (:f owns (List String))
  (:f gates (List String))
  (:f os String)
  (:f toolchain String)
  (:f online (List String))
  (:f alias String)
  (:f family String)
  (:f rung String)
  (:f attempt Int64)
  (:f attempts Int64)
  (:f calls Int64)
  (:f tokens Int64)
  (:f seconds Int64)
  (:f escalations Int64)
  (:f requests Int64)
  (:f next (List String))
  (:f peers String))

fn frameMaxTokens -> Int64
  120

fn peersClip -> Int64
  60

fn estimateTokens text: String -> Int64
  (/ (+ (stringLength text) 3) 4)

fn leakNeedles -> (List String)
  (list ".asl/mem" "sk-" "ghp_" "AKIA" "xoxb-" "xoxp-" "xoxa-" "xoxr-" "xoxs-" "API_KEY" "SECRET" "TOKEN=" "KEY=")

fn leaksEgress text: String -> Bool
  (some? (listHead (filter (fn [(n String)] -> Bool (stringContains? text n)) (leakNeedles))))

fn quoted s: String -> String
  (str "\"" s "\"")

fn words xs: (List String) -> String
  (str "(" (stringJoin xs " ") ")")

fn clip s: String n: Int64 -> String
  (if (> (stringLength s) n) (optionOr (stringSlice s 0 n) s) s)

fn peersText f: Frame -> String
  (if (stringEmpty? f.peers) "none" (quoted (clip f.peers (peersClip))))

fn optionsText -> String
  "(escalate needCtx needOwns needTime split)"

fn frameText f: Frame -> String
  (str "(:frame :task (:unit " f.unit " :kind " f.kind " :atoms " (words f.atoms) " :owns " (words f.owns) " :gates " (words (map quoted f.gates)) ")"
       " :env (:os " f.os " :tc " f.toolchain " :online " (words f.online) ")"
       " :lane (:alias " f.alias " :family " f.family " :rung " f.rung " :try " f.attempt "/" f.attempts ")"
       " :budget (:calls " f.calls " :tok " f.tokens " :sec " f.seconds " :esc " f.escalations " :req " f.requests ")"
       " :options " (optionsText)
       " :next " (words f.next)
       " :bar redGreenRevert :peers " (peersText f) ")")

fn renderFrame f: Frame -> (Result String String)
  (let [(text (frameText f))]
    (cond
      ((leaksEgress text) (err "frame refused: egress filter"))
      ((> (estimateTokens text) (frameMaxTokens)) (err (str "frame refused: " (estimateTokens text) " tokens over " (frameMaxTokens))))
      (else (ok text))))
