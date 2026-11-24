(module asl-tools/coord/deployWindow
  :x [pendingPath mark! clear! untilOf live? shaOf]
  :i [])

; (:m :ref DEPLOY-WINDOW :do "a node deploy that passed its verify leaves (:deploy :pending SHA :at MS :untilMs MS) in the conductor store before it waits for the running trains; the conductor starts no train and no admission while a live marker is there, so a train gap exists; the expiry keeps a dead deployer from freezing the queue, and an unreadable marker counts as absent")
fn pendingPath dir: String -> String
  (str dir "/deployPending.asn")

fn ! mark! dir: String sha: String atMs: Int64 ttlMs: Int64 -> Bool
  (let [(_ (dirCreate dir))]
    (ok? (fileWrite (pendingPath dir) (str "(:deploy :pending \"" sha "\" :at " (stringFromInt64 atMs) " :untilMs " (stringFromInt64 (+ atMs ttlMs)) ")\n"))))

fn ! clear! dir: String -> Bool
  (let [(_ (pathRemove (pendingPath dir)))]
    (not (fileExists? (pendingPath dir))))

fn untilOf text: String -> Int64
  (match (stringIndexOf text ":untilMs ")
    ((none) 0)
    ((some i)
      (let [(rest (optionOr (stringSlice text (+ i 9) (stringLength text)) ""))]
        (optionOr (stringToInt64 (stringTrim (optionOr (listHead (stringSplit rest ")")) ""))) 0))))

fn shaOf text: String -> String
  (match (stringIndexOf text ":pending \"")
    ((none) "")
    ((some i) (optionOr (listHead (stringSplit (optionOr (stringSlice text (+ i 10) (stringLength text)) "") "\"")) "")))

fn ! live? dir: String nowMs: Int64 -> Bool
  (> (untilOf (resultOr (fileReadString (pendingPath dir)) "")) nowMs)
