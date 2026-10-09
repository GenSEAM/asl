(module aslAgentCore/premise :x [PremiseRecord makePremise falsifyPremise formatPremise] :i [])

(schema PremiseRecord (:f id Str) (:f statement Str) (:f falsified Bool))

fn makePremise id: Str statement: Str -> PremiseRecord
  (PremiseRecord :id id :statement statement :falsified false)

fn falsifyPremise premise: PremiseRecord -> PremiseRecord
  (with premise :falsified true)

fn formatPremise premise: PremiseRecord -> Str
  (if premise.falsified (str "(:premise :id \"" premise.id "\" :statement \"" premise.statement "\" :falsified true)") (str "(:premise :id \"" premise.id "\" :statement \"" premise.statement "\" :falsified false)"))
