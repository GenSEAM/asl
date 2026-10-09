(module aslHarness/polyglotAstTest :x [testDetectSourceLanguage testExtractPolyglotPythonAst testExtractPolyglotTypescriptAst testExtractPolyglotGoAst testExtractPolyglotRustAst testExtractPolyglotPhpAst testExtractComposerVersion testExtractPhpAttributes testAuditPhpCompatibility runPolyglotTests runTests] :i [(polyglotAst :a pa) (depsPhp :a dp)])

fn testDetectSourceLanguage -> Bool
  (let [(lPy (pa/detectSourceLanguage "server/main.py")) (lTs (pa/detectSourceLanguage "src/components/App.tsx")) (lGo (pa/detectSourceLanguage "cmd/daemon/main.go")) (lRs (pa/detectSourceLanguage "crates/core/src/lib.rs")) (lPhp (pa/detectSourceLanguage "app/Http/Controllers/UserController.php"))] (assert (match lPy ((langPython) true) (_ false)) "py is lang-python") (assert (match lTs ((langTypescript) true) (_ false)) "ts is lang-typescript") (assert (match lGo ((langGo) true) (_ false)) "go is lang-go") (assert (match lRs ((langRust) true) (_ false)) "rs is lang-rust") (assert (match lPhp ((langPhp) true) (_ false)) "php is lang-php") true)

fn testExtractPolyglotPythonAst -> Bool
  (let [(code (str "import os\n\n" "class DataPipeline:\n" "    def __init__(self):\n" "        pass\n\n" "    def process_records(self, batch):\n" "        return batch\n\n" "def main():\n" "    p = DataPipeline()\n")) (outline (pa/extractAstOutline code "pipeline.py"))] (assert (= outline.totalSymbols 4) "python total symbols is 4") (assert (> (stringLength (pa/formatAstOutline outline)) 0) "formatted outline non-empty") true)

fn testExtractPolyglotTypescriptAst -> Bool
  (let [(code (str "import React from 'react';\n\n" "export interface UserProfile {\n" "  id: string;\n" "  email: string;\n" "}\n\n" "export type UserRole = 'admin' | 'viewer';\n\n" "export function renderHeader(profile: UserProfile): JSX.Element {\n" "  return <div>{profile.email}</div>;\n" "}\n")) (outline (pa/extractAstOutline code "src/UserProfile.tsx"))] (assert (= outline.totalSymbols 3) "ts total symbols is 3") (assert (not (= outline.totalSymbols 0)) "ts total symbols is not 0") true)

fn testExtractPolyglotGoAst -> Bool
  (let [(code (str "package main\n\n" "type WorkerPool struct {\n" "    size int\n" "}\n\n" "type TaskRunner interface {\n" "    Run() error\n" "}\n\n" "func StartServer(port int) error {\n" "    return nil\n" "}\n")) (outline (pa/extractAstOutline code "main.go"))] (assert (= outline.totalSymbols 3) "go total symbols is 3") (assert (not (= outline.totalSymbols 0)) "go total symbols is not 0") true)

fn testExtractPolyglotRustAst -> Bool
  (let [(code (str "pub struct Config {\n" "    pub port: u16,\n" "}\n\n" "pub enum Status {\n" "    Active,\n" "    Idle,\n" "}\n\n" "pub fn initialize() -> Config {\n" "    Config { port: 8080 }\n" "}\n\n" "pub fn solve<T>(input: T) -> T {\n" "    input\n" "}\n")) (outline (pa/extractAstOutline code "src/lib.rs")) (lastSym (optionOr (listGet outline.symbols 3) (pa/PolyglotSymbol :name "" :kind "" :line 0 :signature "" :docstring "")))] (assert (= outline.totalSymbols 4) "rust total symbols is 4") (assert (= lastSym.name "solve") "last sym is solve") true)

fn testExtractPolyglotPhpAst -> Bool
  (let [(code (str "<?php\n\n" "namespace App\\Services;\n\n" "interface PaymentGateway {\n" "    public function charge(int $amount): bool;\n" "}\n\n" "class StripeGateway implements PaymentGateway {\n" "    public function charge(int $amount): bool {\n" "        return true;\n" "    }\n" "}\n")) (outline (pa/extractAstOutline code "app/Services/StripeGateway.php"))] (assert (= outline.totalSymbols 4) "php total symbols is 4") (assert (not (= outline.totalSymbols 0)) "php total symbols is not 0") true)

fn testExtractComposerVersion -> Bool
  (let [(composerLock (str "{\n" "    \"packages\": [\n" "        {\n" "            \"name\": \"symfony/http-foundation\",\n" "            \"version\": \"v6.3.2\"\n" "        },\n" "        {\n" "            \"name\": \"guzzlehttp/guzzle\",\n" "            \"version\": \"7.8.1\"\n" "        }\n" "    ]\n" "}\n")) (v (dp/extractComposerVersion composerLock "guzzlehttp/guzzle"))] (assert (match v ((none) false) ((some ver) (= ver "7.8.1"))) "composer version is 7.8.1") (assert (match (dp/extractComposerVersion composerLock "nonexistent/pkg") ((none) true) ((some _) false)) "nonexistent pkg returns none") true)

fn testExtractPhpAttributes -> Bool
  (let [(code (str "<?php\n\n" "class ApiController {\n" "    #[Route('/api/v1/users', methods: ['GET'])]\n" "    public function getUsers() {\n" "        return [];\n" "    }\n" "}\n")) (attrs (dp/extractPhpAttributes code))] (assert (= (listLength attrs) 1) "1 php attribute found") (let [(firstAttr (optionOr (listGet attrs 0) (dp/PhpAttribute :targetSymbol "" :attributeName "" :arguments "" :line 0)))] (assert (= firstAttr.attributeName "Route") "attribute is Route")) true)

fn testAuditPhpCompatibility -> Bool
  (let [(code (str "<?php\n" "$fn = create_function('$a', 'return $a * 2;');\n" "echo $fn(5);\n")) (report8 (dp/auditPhpCompatibility code "8.2")) (report7 (dp/auditPhpCompatibility code "7.4"))] (assert (not report8.compatible) "report8 not compatible") (assert (= (listLength report8.violations) 1) "1 violation in report8") (assert report7.compatible "report7 compatible") true)

fn testExtractNegativeAst -> Bool
  (let [(pyOut (pa/extractAstOutline "random text" "main.py")) (tsOut (pa/extractAstOutline "nothing here" "main.ts")) (goOut (pa/extractAstOutline "foo bar" "main.go")) (rsOut (pa/extractAstOutline "baz qux" "main.rs")) (phpOut (pa/extractAstOutline "<?php \n echo 'hi';" "main.php"))] (assert (= pyOut.totalSymbols 0) "py negative") (assert (= tsOut.totalSymbols 0) "ts negative") (assert (= goOut.totalSymbols 0) "go negative") (assert (= rsOut.totalSymbols 0) "rs negative") (assert (= phpOut.totalSymbols 0) "php negative") true)

fn runPolyglotTests -> Bool
  (do (testDetectSourceLanguage) (testExtractPolyglotPythonAst) (testExtractPolyglotTypescriptAst) (testExtractPolyglotGoAst) (testExtractPolyglotRustAst) (testExtractPolyglotPhpAst) (testExtractNegativeAst) (testExtractComposerVersion) (testExtractPhpAttributes) (testAuditPhpCompatibility) true)

fn runTests -> Bool
  (runPolyglotTests)
