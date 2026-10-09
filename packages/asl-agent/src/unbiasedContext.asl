(module aslAgent/unbiasedContext
  :x [UnbiasedContextFrame refutePersonaPreamble sanitizeObservation buildUnbiasedContextFrame formatUnbiasedContextFrame]
  :i [(asl/packages/asl-agent/src/omniIntent :a oi)])

(schema UnbiasedContextFrame
  (:f intent oi/OmniIntent)
  (:f symbols (List Str))
  (:f observations (List Str))
  (:f attractorVectors (List Str))
  (:f ownsBoundaries (List Str)))

fn refutePersonaPreamble prompt: Str -> Bool
  (not
    (or (stringContains? prompt "You are an expert")
      (or (stringContains? prompt "You are a helpful")
        (or (stringContains? prompt "Sure, I can")
          (or (stringContains? prompt "Sure! I can")
            (or (stringContains? prompt "As an AI")
              (or (stringContains? prompt "I'd be happy to")
                (stringContains? prompt "I would be happy to"))))))))

fn sanitizeObservation raw: Str -> Str
  (let [(t1 (stringReplace raw "Here is the output:\n" ""))
        (t2 (stringReplace t1 "Sure! " ""))
        (t3 (stringReplace t2 "Certainly! " ""))]
    (stringTrim t3))

fn buildUnbiasedContextFrame intent: oi/OmniIntent symbols: (List Str) obs: (List Str) attractors: (List Str) owns: (List Str) -> UnbiasedContextFrame
  (UnbiasedContextFrame
    :intent intent
    :symbols symbols
    :observations (map (fn [(o Str)] -> Str (sanitizeObservation o)) obs)
    :attractorVectors attractors
    :ownsBoundaries owns)

fn formatUnbiasedContextFrame frame: UnbiasedContextFrame -> Str
  (let [(intentPart (oi/formatOmniIntentAsn frame.intent))
        (symPart (if (listEmpty? frame.symbols) "()" (str "(" (stringJoin frame.symbols " ") ")")))
        (obsPart (if (listEmpty? frame.observations) "()" (str "(\"" (stringJoin frame.observations "\" \"") "\")")))
        (attPart (if (listEmpty? frame.attractorVectors) "()" (str "(" (stringJoin frame.attractorVectors " ") ")")))
        (ownsPart (if (listEmpty? frame.ownsBoundaries) "()" (str "(\"" (stringJoin frame.ownsBoundaries "\" \"") "\")")))]
    (str "(:unbiased-context-frame\n"
         "  :intent " intentPart "\n"
         "  :symbols " symPart "\n"
         "  :observations " obsPart "\n"
         "  :attractors " attPart "\n"
         "  :owns " ownsPart ")"))
