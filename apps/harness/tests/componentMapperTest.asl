(module aslHarness/componentMapperTest :x [testScanComponentUsages testBatchTransformClasses testAuditDesignPolicy testHuntLibraryResidues testFormatComponentMap runComponentTests runTests] :i [(componentMapper :a cm)])

fn sampleJsxCode -> Str
  (str "import React from 'react';\n" "import { Modal, Button } from '@/components/ui';\n" "import _ from 'lodash';\n\n" "export function UserPage() {\n" "  return (\n" "    <div className=\"container p-4\">\n" "      <Modal title=\"User Form\">\n" "        <input type=\"text\" className=\"btn-old input-text\" />\n" "        <Button className=\"btn-old\">Submit</Button>\n" "      </Modal>\n" "    </div>\n" "  );\n" "}\n")

fn testScanComponentUsages -> Bool
  (let [(cmap (cm/scanComponentUsages (sampleJsxCode) "src/pages/UserPage.tsx"))] (assert (= cmap.totalComponents 2) "two custom components found") (assert (= cmap.totalNative 2) "two native tags found") true)

fn testBatchTransformClasses -> Bool
  (let [(rule (cm/BatchTransformRule :targetTag "" :oldClass "btn-old" :newClass "btn-primary" :scopePattern "/pages/")) (res (cm/batchTransformClasses (sampleJsxCode) rule)) (ruleCollision (cm/BatchTransformRule :targetTag "" :oldClass "btn" :newClass "btn-new" :scopePattern "")) (resCollision (cm/batchTransformClasses "<div className=\"btn-primary\">" ruleCollision))] (assert (= res.occurrencesReplaced 2) "two occurrences replaced") (assert (stringContains? res.modifiedContent "btn-primary") "modified contains btn-primary") (assert (not (stringContains? res.modifiedContent "btn-old")) "btn-old removed") (assert (= resCollision.occurrencesReplaced 0) "zero collision replaced") (assert (= resCollision.modifiedContent "<div className=\"btn-primary\">") "collision untouched") true)

fn testAuditDesignPolicy -> Bool
  (let [(cmap (cm/scanComponentUsages (sampleJsxCode) "src/pages/UserPage.tsx")) (report (cm/auditDesignPolicy cmap (list "input" "button") "Input"))] (assert (not report.passed) "native inputs fail design policy") (let [(v (optionOr (listHead report.violations) (cm/PolicyViolation :filePath "" :line 0 :forbiddenTag "" :recommendedReplacement "" :ruleName "")))] (assert (= v.forbiddenTag "input") "violation forbidden tag is input")) true)

fn testHuntLibraryResidues -> Bool
  (let [(report (cm/huntLibraryResidues (sampleJsxCode) "src/pages/UserPage.tsx" "lodash" (list "debounce" "throttle")))] (assert (not report.clean) "lodash import detected as unclean") (assert (> (listLength report.matches) 0) "matches found") true)

fn testFormatComponentMap -> Bool
  (let [(cmap (cm/scanComponentUsages (sampleJsxCode) "src/pages/UserPage.tsx")) (asnStr (cm/formatComponentMap cmap))] (assert (stringContains? asnStr "(:component-map") "contains :component-map") (assert (stringContains? asnStr ":components 2") "contains :components 2") (assert (stringContains? asnStr ":native 2") "contains :native 2") true)

fn runComponentTests -> Bool
  (do (testScanComponentUsages) (testBatchTransformClasses) (testAuditDesignPolicy) (testHuntLibraryResidues) (testFormatComponentMap) true)

fn runTests -> Bool
  (runComponentTests)
