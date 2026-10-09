(module asl-audio/dictation :x [isContinuationWord isFastPathWord calculateDynamicHangoverMs accumulateUtterance shouldExtendHangover DictationBuffer makeInitialDictationBuffer stepDictationTimer] :i [])

(schema DictationBuffer
  (:f isActive Bool)
  (:f firstArrivalMs Int64)
  (:f lastArrivalMs Int64)
  (:f currentHangoverMs Int64)
  (:f textPayload String)
  (:f fragmentCount Int64)
  (:f isFinalized Bool))

fn makeInitialDictationBuffer -> DictationBuffer
  (DictationBuffer
    :isActive false
    :firstArrivalMs 0
    :lastArrivalMs 0
    :currentHangoverMs 550
    :textPayload ""
    :fragmentCount 0
    :isFinalized false)

fn isContinuationWord word: String -> Bool
  (let [(w (stringTrim (stringLower word)))]
    (if (or (= w "для") (or (= w "в") (or (= w "во") (or (= w "на") (= w "с")))))
      true
      (if (or (= w "со") (or (= w "из") (or (= w "к") (or (= w "по") (= w "о")))))
        true
        (if (or (= w "об") (or (= w "про") (or (= w "под") (or (= w "над") (= w "и")))))
          true
          (if (or (= w "а") (or (= w "но") (or (= w "что") (or (= w "где") (= w "или")))))
            true
            (if (or (= w "запусти") (or (= w "проверь") (or (= w "покажи") (or (= w "найди") (= w "сделай")))))
              true
              (if (or (= w "in") (or (= w "for") (or (= w "on") (or (= w "with") (= w "from")))))
                true
                (if (or (= w "to") (or (= w "and") (or (= w "run") (= w "check"))))
                  true
                  false))))))))

fn isFastPathWord word: String -> Bool
  (let [(w (stringTrim (stringLower word)))]
    (if (or (= w "стоп") (or (= w "отмена") (or (= w "да") (= w "нет"))))
      true
      (if (or (= w "применить") (or (= w "статус") (or (= w "enter") (= w "esc"))))
        true
        false)))

fn calculateDynamicHangoverMs trailingToken: String -> Int64
  (cond
    ((isFastPathWord trailingToken) 150)
    ((isContinuationWord trailingToken) 1400)
    (else 550))

fn shouldExtendHangover trailingToken: String -> Bool
  (isContinuationWord trailingToken)

fn extractTrailingToken text: String -> String
  (let [(trimmed (stringTrim text))
        (chars (stringChars trimmed))
        (len (listLength chars))]
    (if (<= len 0)
      ""
      (let [(parts (stringSplit trimmed " "))
            (pLen (listLength parts))]
        (if (<= pLen 0)
          ""
          (optionOr (listHead (listReverse parts)) "")))))

fn accumulateUtterance buf: DictationBuffer newFragment: String timestampMs: Int64 -> DictationBuffer
  (let [(clean (stringTrim newFragment))]
    (if (= clean "")
      buf
      (let [(prevText buf.textPayload)
            (merged (if (= prevText "") clean (str prevText " " clean)))
            (trailing (extractTrailingToken merged))
            (hangover (calculateDynamicHangoverMs trailing))
            (firstAt (if buf.isActive buf.firstArrivalMs timestampMs))
            (count (+ buf.fragmentCount 1))]
        (DictationBuffer
          :isActive true
          :firstArrivalMs firstAt
          :lastArrivalMs timestampMs
          :currentHangoverMs hangover
          :textPayload merged
          :fragmentCount count
          :isFinalized false))))

fn stepDictationTimer buf: DictationBuffer nowMs: Int64 maxSafetyCeilingMs: Int64 -> DictationBuffer
  (if (not buf.isActive)
    buf
    (let [(elapsedSinceLast (- nowMs buf.lastArrivalMs))
          (totalDuration (- nowMs buf.firstArrivalMs))
          (hangover buf.currentHangoverMs)
          (shouldFinalize (or (>= elapsedSinceLast hangover)
                              (>= totalDuration maxSafetyCeilingMs)))]
      (if shouldFinalize
        (with buf :isActive false :lastArrivalMs nowMs :currentHangoverMs hangover :isFinalized true)
        buf)))
