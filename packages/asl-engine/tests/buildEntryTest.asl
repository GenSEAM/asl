(module asl-engine/buildEntryTest :x [runTests] :i [(asl-engine/build :a bld)])

; (:m :ref LLVM-FOR-ENTRY-TESTS :do "entryPath! finds the engine CLI entry under the working tree when no entry is configured, and toolRootOf turns an entry path back into the toolchain root, refusing a path that is not an engine entry")
fn ! runTests -> Bool
  (let [(given (optionOr (envGet "ASL_ENGINE_ENTRY") ""))
        (here (resultOr (realPath ".") "."))
        (local (str here (bld/entrySuffix)))
        (found (bld/entryPath!))]
    (do
      (assert (fileExists? local) "the working tree holds the engine CLI entry")
      (assert (= found (if (stringEmpty? given) local given)) "entryPath! is the configured entry, else the one under the working tree")
      (assert (= (bld/toolRootOf local) here) "toolRootOf of the tree's entry is the tree root")
      (assert (= (bld/toolRootOf (str "/opt/aslTool" (bld/entrySuffix))) "/opt/aslTool") "toolRootOf strips the entry suffix from any root")
      (assert (= (bld/toolRootOf "/opt/aslTool/asl/packages/asl-engine/src/other.asl") "") "a path that is not the engine entry has no tool root")
      (assert (= (bld/toolRootOf (bld/entrySuffix)) "") "the bare suffix has an empty root")
      (assert (= (bld/toolRootOf "") "") "an empty entry has no tool root")
      true))
