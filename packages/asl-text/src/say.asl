(module asl-text/say :x [say! sayErr!] :i [])

; (:m :ref LAYER-CUT-01 :do "line output shared by packages of every layer: asl-cli/system delegates here, so the agent layer prints without importing the apps layer")
fn say! text: String -> Bool
  (do (println text) true)

fn sayErr! text: String -> Bool
  (do (eprintln text) true)
