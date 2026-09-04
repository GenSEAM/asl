# @genseam/asl-compiler

Unified 100% Self-Hosted AgentScript Compiler Pipeline.

## Architecture
`asl-compiler` orchestrates the complete AgentScript compilation lifecycle in pure ASL:

1. **Parser** (`@genseam/asl-parser`): Lexical analysis, S-expression reader, and structured AST generation.
2. **Type Checker** (`@genseam/asl-checker`): Hindley-Milner bidirectional type inference, cross-module signature resolution, and §9 specification rule enforcement.
3. **Code Generator** (`@genseam/asl-codegen`): Top-level declaration emission, type translation, builtin lowering, and standalone executable assembly.

## Usage
```lisp
(compile-source source-text "main.asl" [])
```

Zero Python runtime dependencies in shipped compiler logic.
