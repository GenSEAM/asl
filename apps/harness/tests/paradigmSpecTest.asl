(module aslHarness/paradigmSpecTest :x [validateParadigmSpec verifyActionOntology runTests] :i [])

fn containsId? items: (List Str) target: Str -> Bool
  (fold (fn [(acc Bool) (item Str)] -> Bool (if acc true (= item target))) false items)

fn hasAllIds? collection: (List Str) expected: (List Str) -> Bool
  (fold (fn [(acc Bool) (target Str)] -> Bool (if acc (containsId? collection target) false)) true expected)

fn hasSigilToken? text: Str -> Bool
  (or (stringContains? text "@") (stringContains? text "#"))

fn conformsToDecisions? decisions: (List Str) -> Bool
  (let [(expected (list "d40" "d41" "d42" "d43" "d44" "d45" "d46" "d47" "d48" "d49")) (hasSigils (fold (fn [(acc Bool) (item Str)] -> Bool (if acc true (hasSigilToken? item))) false decisions))] (and (= (listLength decisions) 10) (and (not hasSigils) (hasAllIds? decisions expected))))

fn hasValidOntology? actions: (List Str) roles: (List Str) -> Bool
  (let [(expActs (list "perceive" "transliterate" "deliberate" "mutate" "verify" "reconcile" "compress")) (expRoles (list "scout" "transliterator" "planner" "implementer" "auditor" "meta-audit" "compactor")) (hasCoAuthor (containsId? roles "co-author"))] (and (= (listLength actions) 7) (and (= (listLength roles) 7) (and (not hasCoAuthor) (and (hasAllIds? actions expActs) (hasAllIds? roles expRoles))))))

fn validateParadigmSpec -> Bool
  (let [(canonicalDecisions (list "d40" "d41" "d42" "d43" "d44" "d45" "d46" "d47" "d48" "d49")) (incompleteDecisions (list "d40" "d41" "d42" "d43")) (sigilTainted (list "d40" "@d41" "d42" "d43" "d44" "d45" "d46" "d47" "d48" "d49")) (emptyDecisions (list))] (assert (= (listLength canonicalDecisions) 10) "Paradigm must synchronize exactly 10 decisions d40-d49") (assert (conformsToDecisions? canonicalDecisions) "Canonical decisions d40-d49 must pass validation") (assert (not (conformsToDecisions? incompleteDecisions)) "Incomplete decisions must fail validation") (assert (not (conformsToDecisions? sigilTainted)) "Sigil-tainted decisions must fail validation") (assert (not (conformsToDecisions? emptyDecisions)) "Empty decision set must fail validation") true)

fn verifyActionOntology -> Bool
  (let [(actions (list "perceive" "transliterate" "deliberate" "mutate" "verify" "reconcile" "compress")) (roles (list "scout" "transliterator" "planner" "implementer" "auditor" "meta-audit" "compactor")) (invalidActions (list "perceive" "arbitrary-code-exec" "mutate")) (forbiddenRoles (list "scout" "transliterator" "planner" "implementer" "auditor" "meta-audit" "co-author"))] (assert (= (listLength actions) 7) "Ontology must define exactly 7 canonical action primitives") (assert (= (listLength roles) 7) "Ontology must define exactly 7 teleological agent roles") (assert (hasValidOntology? actions roles) "Canonical actions and roles must verify cleanly") (assert (not (hasValidOntology? invalidActions roles)) "Invalid action primitive must be rejected") (assert (not (hasValidOntology? actions forbiddenRoles)) "Forbidden co-author role must be rejected") true)

fn runTests -> Bool
  (do (assert (validateParadigmSpec) "validate-paradigm-spec must pass") (assert (verifyActionOntology) "verify-action-ontology must pass") true)
