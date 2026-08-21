"""A stub in the shape the real corpus uses, including the two constructs a
regex-based prototype got wrong: a nested generic whose parameters contain a
comma, and an optional return."""

class DataFrame:
    def height(self) -> int: ...

def read_csv(path: str) -> DataFrame:
    """Read a CSV file into a dataframe."""

def read_csv_opts(path: str, options: dict[str, list[int]]) -> DataFrame:
    """Read a CSV file with per-column options."""

def height(df: DataFrame) -> int:
    """Number of rows in a dataframe."""

def column_names(df: DataFrame) -> list[str]:
    """Column names, in order."""

def first_row(df: DataFrame) -> dict[str, str] | None:
    """The first row, or None when the frame is empty."""

def describe(df: DataFrame, percentiles: list[float] | None) -> DataFrame:
    """Summary statistics."""

def scan_all(*paths: str) -> DataFrame:
    """Variadic, so no declaration can be generated for it."""

def to_arrow(df: DataFrame) -> bytes:
    """Returns bytes, which the language has no type for yet."""

def readCSV(path: str) -> DataFrame:
    """A camelCase host name, which §8 mangling cannot reproduce."""

def write_csv(df: DataFrame, path: str) -> None:
    """Write a dataframe out; returns nothing."""

def rows_untyped(xs: list) -> int:
    """A container with no element type — not an opaque, and not a List."""

def as_map(df: DataFrame) -> dict:
    """Same, for a mapping."""
