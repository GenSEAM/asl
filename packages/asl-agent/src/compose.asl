(module aslAgent/compose
  :x [QuestionKind
      UnresolvedQuestion
      AssumedFact
      Composition
      kindOperator
      kindLookup
      operator
      lookup
      makeUnresolvedQuestion
      makeAssumedFact
      makeEmptyComposition
      addUnresolvedQuestion
      addAssumedFact
      closeUnresolvedQuestion
      supersedeAssumedFact
      extractPendingLookups
      resolveLookupQuestion
      renderCompositionContext
      listFirst]
  :i [])

(enum QuestionKind
  (:c kindOperator [] "Question addressed to human operator")
  (:c kindLookup [] "Question resolved via codebase or tool lookup"))

(schema UnresolvedQuestion
  (:f id Str)
  (:f prompt Str)
  (:f kind QuestionKind))

(schema AssumedFact
  (:f id Str)
  (:f claim Str))

(schema Composition
  (:f openQuestions (List UnresolvedQuestion))
  (:f assumedFacts (List AssumedFact)))

fn operator -> QuestionKind
  (kindOperator)

fn lookup -> QuestionKind
  (kindLookup)

fn listFirst list: (List Any) -> Any
  (optionOr (listHead list) "")

fn makeUnresolvedQuestion id: Str prompt: Str kind: QuestionKind -> UnresolvedQuestion
  (UnresolvedQuestion :id id :prompt prompt :kind kind)

fn makeAssumedFact id: Str claim: Str -> AssumedFact
  (AssumedFact :id id :claim claim)

fn makeEmptyComposition -> Composition
  (Composition :openQuestions (list) :assumedFacts (list))

fn addUnresolvedQuestion comp: Composition question: UnresolvedQuestion -> Composition
  (with comp :openQuestions (listAppend comp.openQuestions (list question)))

fn addAssumedFact comp: Composition fact: AssumedFact -> Composition
  (with comp :assumedFacts (listAppend comp.assumedFacts (list fact)))

fn closeUnresolvedQuestion comp: Composition questionId: Str -> Composition
  (let [(remaining (filter (fn [(q UnresolvedQuestion)] -> Bool (!= q.id questionId)) comp.openQuestions))] (with comp :openQuestions remaining))

fn supersedeAssumedFact comp: Composition factId: Str newClaim: Str -> Composition
  (let [(updated (map (fn [(f AssumedFact)] -> AssumedFact (if (= f.id factId) (AssumedFact :id factId :claim newClaim) f)) comp.assumedFacts))] (with comp :assumedFacts updated))

fn extractPendingLookups comp: Composition -> (List UnresolvedQuestion)
  (filter (fn [(q UnresolvedQuestion)] -> Bool (mt q.kind ((kindLookup) true) ((kindOperator) false))) comp.openQuestions)

fn resolveLookupQuestion comp: Composition questionId: Str resolution: Str -> Composition
  (let [(closed (closeUnresolvedQuestion comp questionId)) (fact (makeAssumedFact questionId resolution))] (addAssumedFact closed fact))

fn renderCompositionContext comp: Composition -> Str
  (str "(:composition-context :open-count " (stringFromInt64 (listLength comp.openQuestions)) " :assumed-count " (stringFromInt64 (listLength comp.assumedFacts)) ")")
