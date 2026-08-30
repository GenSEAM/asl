//! Module resolution, ported from grammar/modules.py.
//!
//! Same two answers as the Python resolver: which file a module path names (over
//! an ordered list of source roots), and in what order a program's imports have
//! to be processed. Dependencies first, root last; a cycle is broken (not
//! diagnosed) by seeding `seen` with the root's declared path so a back-edge
//! neither recurses nor emits the root a second time.

use crate::ast::{Program, Unit};
use crate::cst::{self, Builder};
use std::collections::HashSet;
use std::path::{Path, PathBuf};

pub struct Loader {
    roots: Vec<PathBuf>,
}

impl Loader {
    pub fn new(roots: Vec<PathBuf>) -> Self {
        Loader { roots }
    }

    /// The file a module path names, over the search roots (`path + ".agentscript"`).
    fn find(&self, mod_path: &str) -> Option<PathBuf> {
        for root in &self.roots {
            let cand = root.join(format!("{}.agentscript", mod_path));
            if cand.exists() {
                return Some(cand);
            }
        }
        None
    }

    /// Every module the root imports, transitively, dependencies first and root
    /// excluded; then the root itself last. Each element is (mod_path, Unit).
    /// A missing module on the path is a hard load error.
    pub fn resolve(
        &self,
        root_path: &Path,
        root_tree: &tree_sitter::Tree,
        root_src: &str,
    ) -> Result<Program, String> {
        let mut roots = vec![root_path.parent().unwrap_or(Path::new(".")).to_path_buf()];
        roots.extend(self.roots.iter().cloned());

        let root_unit = build_unit_from(root_tree, root_src.as_bytes());
        let root_mod = root_unit.module_path.clone();

        let mut seen: HashSet<String> = HashSet::new();
        if let Some(m) = &root_mod {
            seen.insert(m.clone());
        }

        let mut order: Vec<(String, Unit)> = vec![];

        fn walk(
            unit: &Unit,
            roots: &[PathBuf],
            seen: &mut HashSet<String>,
            order: &mut Vec<(String, Unit)>,
            loader: &Loader,
        ) -> Result<(), String> {
            for (_, mod_path) in &unit.imports {
                if seen.contains(mod_path) {
                    continue;
                }
                seen.insert(mod_path.clone());
                let found = loader
                    .find(mod_path)
                    .ok_or_else(|| format!("no module {} on the search path", mod_path))?;
                let sub = loader.parse_file(&found)?;
                walk(&sub, roots, seen, order, loader)?;
                order.push((mod_path.clone(), sub));
            }
            Ok(())
        }

        walk(&root_unit, &roots, &mut seen, &mut order, self)?;
        let root_name = root_path
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        order.push((root_mod.clone().unwrap_or(root_name), root_unit));
        Ok(Program { units: order })
    }

    fn parse_file(&self, path: &Path) -> Result<Unit, String> {
        let src = std::fs::read_to_string(path)
            .map_err(|e| format!("{}: {}", path.display(), e))?;
        let tree = parse_source(&src).ok_or_else(|| format!("failed to parse {}", path.display()))?;
        Ok(build_unit_from(&tree, src.as_bytes()))
    }
}

/// Build a Unit from a parsed tree, owning the source.
pub fn build_unit_from(tree: &tree_sitter::Tree, src: &[u8]) -> Unit {
    let b = Builder::new(src);
    b.build_unit(tree.root_node())
}

/// Parse a source string; returns None on a syntax error.
pub fn parse_source(src: &str) -> Option<tree_sitter::Tree> {
    let mut parser = tree_sitter::Parser::new();
    parser
        .set_language(&agentscript_ts::language())
        .expect("tree-sitter could not load the AgentScript grammar");
    parser.parse(src, None)
}

/// Parse a source string, reporting a checked syntax error to the caller.
pub fn checked_parse(src: &str, source_name: &str) -> Result<tree_sitter::Tree, String> {
    let tree = parse_source(src)
        .ok_or_else(|| format!("failed to parse {}", source_name))?;
    if let Some(e) = cst::find_error(tree.root_node()) {
        let line = e.start_position().row + 1;
        return Err(format!("{}:{}: syntax error", source_name, line));
    }
    Ok(tree)
}
