(module aslAgent/promptEcho
  :x [ngramsOf echoShare promptEcho?]
  :i [])

fn tokenize text: String -> (List String)
  (let [lowered (stringLower text)
        noTabs (stringReplace lowered "\t" " ")
        noNl (stringReplace noTabs "\n" " ")
        noCr (stringReplace noNl "\r" " ")
        parts (stringSplit noCr " ")]
    (filter (fn [t] (not (stringEmpty? t))) parts))

fn ngramsLoop toks: (List String) n: Int64 acc: (List String) -> (List String)
  (if (< (listLength toks) n)
    (listReverse acc)
    (let [window (optionOr (listSlice toks 0 n) (list))
          gram (stringJoin window " ")]
      (ngramsLoop (listDrop toks 1) n (cons gram acc))))

fn ngramsOf text: String n: Int64 -> (List String)
  (ngramsLoop (tokenize text) n (list))

fn echoShare prompt: String reply: String n: Int64 -> Float64
  (let [replyToks (tokenize reply)
        replyLen (listLength replyToks)]
    (if (< replyLen n)
      0.0
      (let [promptGrams (ngramsOf prompt n)
            replyGrams (ngramsOf reply n)
            total (listLength replyGrams)
            hits (listLength (filter (fn [g] (listContains? promptGrams g)) replyGrams))]
        (if (= total 0)
          0.0
          (/ (int64ToFloat64 hits) (int64ToFloat64 total))))))

fn promptEcho? prompt: String reply: String -> Bool
  (> (echoShare prompt reply 8) 0.5)
