//! The AgentScript grammar, wrapped for Rust consumers.
//!
//! parser.c is compiled by build.rs into a static lib; this crate exposes it
//! through the tree-sitter runtime. ABI compatibility is checked by
//! Language::new (the parser is generated at ABI 14, which the pinned tree-sitter
//! release accepts).

use tree_sitter::Language;

extern "C" {
    fn tree_sitter_agentscript() -> *const ();
}

/// The AgentScript language, for parsing with `tree_sitter::Parser`.
pub fn language() -> Language {
    unsafe { Language::new(tree_sitter_language::LanguageFn::from_raw(tree_sitter_agentscript)) }
}

#[cfg(test)]
mod tests {
    use super::language;
    use tree_sitter::Parser;

    #[test]
    fn parses_a_source_end_to_end() {
        let mut parser = Parser::new();
        parser
            .set_language(&language())
            .expect("pinned tree-sitter release accepts the generated grammar ABI");
        let tree = parser.parse("(defun ! main [(args (List String))] -> (Result Unit IoError) (println (str \"a\" \"b\")))", None)
            .expect("valid source parses");
        assert_eq!(tree.root_node().kind(), "source_file");
        assert!(!has_error(tree.root_node()));
    }

    #[test]
    fn reports_a_syntax_error() {
        let mut parser = Parser::new();
        parser
            .set_language(&language())
            .expect("pinned tree-sitter release accepts the generated grammar ABI");
        // Unclosed string and a bare symbol after it
        let tree = parser.parse("(defun f [] -> Int64 \"hello)", None).expect("tree returned");
        assert!(has_error(tree.root_node()));
    }

    fn has_error(node: tree_sitter::Node) -> bool {
        let mut stack = vec![node];
        while let Some(n) = stack.pop() {
            let kind = n.kind();
            if kind == "ERROR" || kind == "MISSING" {
                return true;
            }
            let mut c = n.walk();
            for ch in n.children(&mut c) {
                stack.push(ch);
            }
        }
        false
    }
}
