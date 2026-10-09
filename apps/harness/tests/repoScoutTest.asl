(module aslHarness/repoScoutTest :x [testScoutReact19 testScoutPydanticV2 testAuditCodeClean testAuditCodeForbidden testFormatProfileAsn runRepoScoutTests runTests] :i [(repoScout :a rs)])

fn testScoutReact19 -> Bool
  (let [(pkgJson "{\n  \"dependencies\": {\n    \"react\": \"19.0.0\"\n  }\n}") (prof (rs/scoutRepo "/app" "package.json" pkgJson))] (assert (= prof.ecosystem "js-ts") "ecosystem is js-ts") (assert (= prof.primaryFramework "react") "framework is react") (assert (listContains? prof.forbiddenApis "useFormState") "has forbidden useFormState") (assert (listContains? prof.recommendedApis "useActionState") "has recommended useActionState") true)

fn testScoutPydanticV2 -> Bool
  (let [(poetryLock "[[package]]\nname = \"pydantic\"\nversion = \"2.6.1\"\n") (prof (rs/scoutRepo "/backend" "poetry.lock" poetryLock))] (assert (= prof.ecosystem "python") "ecosystem is python") (assert (= prof.primaryFramework "pydantic") "framework is pydantic") (assert (listContains? prof.forbiddenApis ".dict()") "has forbidden .dict()") (assert (listContains? prof.recommendedApis ".model_dump()") "has recommended .model_dump()") true)

fn testAuditCodeClean -> Bool
  (let [(pkgJson "{\n  \"dependencies\": {\n    \"react\": \"19.0.0\"\n  }\n}") (prof (rs/scoutRepo "/app" "package.json" pkgJson)) (cleanCode "export function Form() { const [state, action] = useActionState(submitHandler, null); return <form action={action}/>; }") (res (rs/auditCodeDiff cleanCode prof))] (assert res.allowed "clean code allowed") (assert (not (listContains? res.violations "useFormState")) "no violations in clean code") true)

fn testAuditCodeForbidden -> Bool
  (let [(pkgJson "{\n  \"dependencies\": {\n    \"react\": \"19.0.0\"\n  }\n}") (prof (rs/scoutRepo "/app" "package.json" pkgJson)) (badCode "export function Form() { const [state, action] = useFormState(submitHandler, null); return <form action={action}/>; }") (res (rs/auditCodeDiff badCode prof))] (assert (not res.allowed) "forbidden code blocked") (assert (listContains? res.violations "useFormState") "violations contains useFormState") true)

fn testFormatProfileAsn -> Bool
  (let [(prof (rs/makeEmptyProfile)) (asnStr (rs/formatProfileAsn prof))] (assert (stringContains? asnStr "(:repo-profile") "contains :repo-profile") (assert (stringContains? asnStr ":eco \"generic\"") "contains :eco generic") true)

fn runRepoScoutTests -> Bool
  (do (testScoutReact19) (testScoutPydanticV2) (testAuditCodeClean) (testAuditCodeForbidden) (testFormatProfileAsn) true)

fn runTests -> Bool
  (runRepoScoutTests)
