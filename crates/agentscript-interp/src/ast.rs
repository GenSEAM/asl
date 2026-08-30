//! Owned AST for AgentScript, built from the project's tree-sitter CST.
//!
//! Ownership decouples evaluation from tree-sitter's arena lifetimes: modules
//! are resolved and their trees may live anywhere, and the evaluator holds an
//! `Ast` without borrowing a `Parser`. Node kind strings and source spans are
//! copied out; the interpreter never needs to re-parse.

use std::collections::BTreeMap;

/// A type as written in the source. Only the numeric widths matter to the
/// evaluator (literal width is pinned by the called signature); everything else
/// is erased but must still be *recognized* so that a stray node in type
/// position is never silently skipped.
#[derive(Debug, Clone, PartialEq)]
pub enum Type {
    Named(String),
    Qualified(String, String),
    App(Box<Type>, Vec<Type>),
    Int32,
    Int64,
    Float64,
}

impl Type {
    pub fn width(&self) -> Option<NumericWidth> {
        match self {
            Type::Int32 => Some(NumericWidth::I32),
            Type::Int64 => Some(NumericWidth::I64),
            Type::Float64 => Some(NumericWidth::F64),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NumericWidth {
    I32,
    I64,
    F64,
}

#[derive(Debug, Clone)]
pub struct Param {
    pub name: String,
    pub ty: Type,
}

/// A literal integer, carrying the digits as written and the optional width
/// pinned by the *caller's* signature at the call site. The digits include the
/// sign; AgentScript reads a sign as part of the digits.
#[derive(Debug, Clone)]
pub struct IntLit {
    pub digits: String,
    pub width: Option<NumericWidth>,
    pub span: Span,
}

#[derive(Debug, Clone, Copy)]
pub struct Span {
    pub line: usize,
    pub col: usize,
}

#[derive(Debug, Clone)]
pub enum Expr {
    Int(IntLit),
    Float(f64),
    Str(String),
    Bool(bool),
    Unit,
    Ident(String),
    /// A qualified name: alias/member (lowercase member, prelude case, or a
    /// ucamel constructor reached through an alias as `alias/TypeName`).
    Qualified(String, String),
    Let(Vec<(String, Expr)>, Vec<Expr>),
    If(Box<Expr>, Box<Expr>, Box<Expr>),
    Cond(Vec<CondClause>),
    Match(Box<Expr>, Vec<(Pattern, Vec<Expr>)>),
    Try(Box<Expr>),
    Fn(FnLit),
    /// A constructor builtin as a plain expression: ok/err/some/none/pair/list.
    Ctor(String, Vec<Expr>),
    /// A record construction: `(TypeName :field v ...)` (ucamel head).
    Record(String, Vec<(String, Expr)>),
    FieldAccess { field: String, target: Box<Expr> },
    /// A call with an arbitrary callee expression (ident, qualified, or nested).
    Call(Box<Expr>, Vec<Expr>),
}

#[derive(Debug, Clone)]
pub struct CondClause {
    /// None for the `:else` clause.
    pub condition: Option<Expr>,
    pub body: Vec<Expr>,
}

#[derive(Debug, Clone)]
pub struct FnLit {
    pub params: Vec<Param>,
    pub body: Vec<Expr>,
}

#[derive(Debug, Clone)]
pub enum Pattern {
    /// A bare identifier binds.
    Bind(String),
    Wildcard,
    Int(String),
    Float(f64),
    Str(String),
    Bool(bool),
    Ok(Box<Pattern>),
    Err(Box<Pattern>),
    Some(Box<Pattern>),
    None,
    List,
    Cons(Box<Pattern>, Box<Pattern>),
    Pair(Box<Pattern>, Box<Pattern>),
    /// A user/prelude case pattern. `case` is the bare case name (resolved to
    /// its defining module's tag at match time).
    Case(String, Vec<Pattern>),
}

#[derive(Debug, Clone)]
pub enum TopLevel {
    Defun(Defun),
}

#[derive(Debug, Clone)]
pub struct Defun {
    pub name: String,
    pub effect: bool,
    pub params: Vec<Param>,
    pub ret: Type,
    pub body: Vec<Expr>,
}

#[derive(Debug, Clone)]
pub struct SchemaField {
    pub name: String,
    pub default: Option<Expr>,
}

#[derive(Debug, Clone)]
pub struct Schema {
    pub name: String,
    pub fields: Vec<SchemaField>,
}

/// A module unit: what one file contributes to the program.
#[derive(Debug, Clone)]
pub struct Unit {
    /// The defining module path (its declared `module` name), or None for the
    /// root file that declares no module header.
    pub module_path: Option<String>,
    /// alias -> module path for imports.
    pub imports: Vec<(String, String)>,
    pub defuns: Vec<Defun>,
    pub schemas: Vec<Schema>,
    /// enum case -> declared case (in declaration order). Value is the list of
    /// user cases in declaration order as written.
    pub enum_cases: Vec<(String, Vec<String>)>,
    /// Top-level exported names (function and type), as declared in :export.
    pub exports: Vec<String>,
}

impl Unit {
    pub fn find_defun(&self, name: &str) -> Option<&Defun> {
        self.defuns.iter().find(|d| d.name == name)
    }
    pub fn schema(&self, name: &str) -> Option<&Schema> {
        self.schemas.iter().find(|s| s.name == name)
    }
    pub fn enum_case_order(&self, name: &str) -> Option<&Vec<String>> {
        self.enum_cases.iter().find(|(n, _)| n == name).map(|(_, v)| v)
    }
}

/// A full program: the root unit plus its transitive imported units, resolved
/// in dependency order with the root last.
#[derive(Debug, Clone)]
pub struct Program {
    pub units: Vec<(String, Unit)>,
}

impl Program {
    pub fn root_unit(&self) -> &Unit {
        &self.units[self.units.len() - 1].1
    }
    pub fn root_path(&self) -> &str {
        &self.units[self.units.len() - 1].0
    }
}
