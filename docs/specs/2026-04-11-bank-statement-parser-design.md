# Bank Statement PDF → CSV Parser

## Context

Pocket Pilot already has a CSV import feature that accepts transactions in a specific 9-column format. To load historical transactions from bank statements (which come as PDFs with bank-specific layouts), we need standalone Python scripts that parse these PDFs and output the CSV format the app expects.

This is intentionally **not** an app feature — it's a set of utility scripts run locally. Each bank gets its own parser module. The first target is the BBVA credit card statement (`bbva_tc.pdf`), which has the most transactions.

## CSV Output Format

```csv
date,type,amount,currency,account,destination_account,category,tags,notes
2025-04-07 12:00:00,EXPENSE,200.00,MXN,BBVA TC,,Transporte público,,UBER TRIP
```

- `date`: `YYYY-MM-DD HH:MM:SS` (time fixed at `12:00:00` — statements don't include time). The app's import service passes this through as-is; the Flutter side truncates to date-only on storage.
- `type`: `EXPENSE` for purchases/charges, `INCOME` for payments/credits to the card
- `amount`: Always positive, in unit currency (pesos, not cents). Include decimal point for clarity (e.g., `200.00` for $200 MXN). The app's import service handles cents conversion internally.
- `currency`: `MXN`
- `account`: From `--account` flag or inferred from detected bank
- `destination_account`: Always empty (no transfers in statements)
- `category`: Matched via keyword map, or empty string if no match
- `tags`: Always empty (no tag info in statements)
- `notes`: Original transaction concept/description from the statement

## Architecture

```
scripts/
├── pyproject.toml              # uv project: python 3.12+, dep: pdfplumber
├── parse_statement.py          # CLI entry point
├── parsers/
│   ├── __init__.py             # detect_bank() + parser registry
│   ├── base.py                 # Transaction dataclass + StatementParser ABC
│   └── bbva_tc.py              # BBVA credit card parser
├── categorizer.py              # Keyword → category mapping
└── csv_writer.py               # Transaction list → CSV file
```

## Components

### 1. `parsers/base.py` — Transaction Model & Parser Interface

```python
@dataclass
class Transaction:
    date: datetime
    type: str               # "EXPENSE" | "INCOME"
    amount: float           # Always positive
    currency: str           # "MXN"
    account: str            # Account name for CSV
    destination_account: str  # Always ""
    category: str           # Mapped or ""
    tags: str               # Always ""
    notes: str              # Original bank concept

class StatementParser(ABC):
    @abstractmethod
    def parse(self, pdf_path: Path, account_name: str) -> list[Transaction]: ...
```

### 2. `parsers/__init__.py` — Bank Detection & Registry

- Reads first page text via `pdfplumber`
- Matches keywords to select parser:
  - "BBVA" + "tarjeta de crédito" → `BbvaTcParser`
  - (future: "BBVA" + "cuenta de cheques" → `BbvaParser`)
  - (future: "Rappi" → `RappiParser`)
- Raises clear error if bank not recognized

### 3. `parsers/bbva_tc.py` — BBVA Credit Card Parser

Uses `pdfplumber` with `page.extract_text()` + line-by-line regex parsing (not `extract_tables()`, as BBVA TC statements use text-based layouts, not HTML-style tables):

1. Open PDF and iterate pages
2. Extract text from each page via `page.extract_text()`
3. Parse lines with regex to identify transaction rows (date pattern + concept + amount)
4. Determine type: charges → `EXPENSE`, payments/credits → `INCOME`
5. Normalize dates from `DD/MMM/YYYY` (Spanish abbreviations) to `datetime`
6. Clean concept text (strip extra whitespace, normalize encoding)
7. Return `list[Transaction]` with `account_name` applied

**Date parsing — Spanish month abbreviations:**
BBVA uses Spanish month names. Use an explicit mapping instead of locale-dependent `strptime`:
```python
MONTH_MAP = {
    "ENE": 1, "FEB": 2, "MAR": 3, "ABR": 4,
    "MAY": 5, "JUN": 6, "JUL": 7, "AGO": 8,
    "SEP": 9, "OCT": 10, "NOV": 11, "DIC": 12,
}
```

**Key considerations:**
- BBVA TC statements have a header section (account info, balances) — skip non-transaction content
- Transactions may span multiple lines (long descriptions) — handle line continuation
- Amounts may use comma as decimal separator and/or period as thousands separator — normalize to float
- Both purchases AND payments to the card are imported (`INCOME` for payments)

### 4. `categorizer.py` — Hybrid Keyword Categorization

An ordered list of `(keyword, category)` tuples matched against the uppercase concept:

```python
KEYWORD_MAP = [
    # Specific matches first
    ("TOTALPLAY", "Internet"),
    ("TELMEX", "Internet"),
    ("IZZI", "Internet"),
    ("MEGACABLE", "Internet"),
    ("NETFLIX", "Streaming"),
    ("SPOTIFY", "Streaming"),
    ("DISNEY", "Streaming"),
    ("AMAZON PRIME", "Streaming"),
    ("HBO", "Streaming"),
    ("YOUTUBE", "Streaming"),
    ("APPLE.COM", "Software"),
    ("GOOGLE STORAGE", "Cloud"),
    ("ICLOUD", "Cloud"),
    ("UBER EATS", "Restaurante"),
    ("DIDI FOOD", "Restaurante"),
    ("RAPPI", "Restaurante"),
    ("UBER TRIP", "Taxi / Uber"),
    ("DIDI", "Taxi / Uber"),
    ("AMAZON", "Compras"),
    ("MERCADOLIBRE", "Compras"),
    ("MERCADO LIBRE", "Compras"),
    ("SHEIN", "Ropa y accesorios"),
    ("LIVERPOOL", "Compras"),
    ("OXXO", "Despensa"),
    ("WALMART", "Despensa"),
    ("SORIANA", "Despensa"),
    ("CHEDRAUI", "Despensa"),
    ("BODEGA AURRERA", "Despensa"),
    ("COSTCO", "Despensa"),
    ("SAMS CLUB", "Despensa"),
    ("SAM'S CLUB", "Despensa"),
    ("LA COMER", "Despensa"),
    ("MCDONALDS", "Restaurante"),
    ("DOMINOS", "Restaurante"),
    ("STARBUCKS", "Restaurante"),
    ("BURGER KING", "Restaurante"),
    ("LITTLE CAESARS", "Restaurante"),
    ("KFC", "Restaurante"),
    ("FARMACIA", "Farmacia"),
    ("FARMACIAS", "Farmacia"),
    ("SANBORNS", "Restaurante"),
    ("CFE", "Electricidad"),
    ("COMISION", "Comisiones"),
    ("ANUALIDAD", "Comisiones"),
    ("INTERES", "Intereses"),
    ("IVA", "Intereses"),
    ("GASOLINERA", "Combustible"),
    ("PEMEX", "Combustible"),
    ("ESTACIONAMIENTO", "Estacionamiento"),
    ("CINEPOLIS", "Cine"),
    ("CINEMEX", "Cine"),
    ("PLATZI", "Cursos"),
    ("STEAM", "Videojuegos"),
    ("PLAYSTATION", "Videojuegos"),
    ("XBOX", "Videojuegos"),
    ("NINTENDO", "Videojuegos"),
    # ... extensible
]
```

**Logic:** First keyword match wins. Unmatched → empty category (resolved in app's mapping screen).

**Function:**
```python
def categorize(concept: str) -> str:
    normalized = concept.upper()
    for keyword, category in KEYWORD_MAP:
        if keyword in normalized:
            return category
    return ""
```

### 5. `csv_writer.py` — CSV Output

Writes `list[Transaction]` to CSV with exact headers the app expects. Uses Python's `csv.writer` with default `QUOTE_MINIMAL` quoting — this correctly handles commas and special characters in the `notes` field (e.g., `"AMAZON.COM.MX, S. DE R.L."`).

### 6. `parse_statement.py` — CLI Entry Point

```bash
uv run parse_statement.py <pdf_path> [--account NAME] [--output PATH]
```

- `pdf_path` (required): Path to the bank statement PDF
- `--account` (optional): Account name for CSV. Default: inferred from bank (e.g., "BBVA TC")
- `--output` (optional): Output CSV path. Default: `<pdf_stem>.csv` in same directory

**Execution flow:**
1. Detect bank from PDF content
2. Select and run appropriate parser → `list[Transaction]`
3. Apply categorizer to each transaction
4. Write CSV
5. Print summary:
   ```
   ✓ Parsed 47 transactions from bbva_tc.pdf
   ✓ Categorized: 32/47 (68%)
   ✓ Uncategorized: 15 transactions (empty category for app mapping)
   ✓ Output: bbva_tc.csv
   ```

## Dependencies

```toml
[project]
name = "pocket-pilot-scripts"
requires-python = ">=3.12"
dependencies = ["pdfplumber>=0.11"]
```

Single dependency: `pdfplumber` (handles PDF text and table extraction).

## Extending to Other Banks

To add a new bank parser:
1. Create `parsers/<bank>.py` implementing `StatementParser`
2. Add detection keyword to `parsers/__init__.py` registry
3. Add bank-specific keywords to `categorizer.py` if needed

## Caveats

- **No duplicate detection**: Running the parser twice on the same PDF and importing both CSVs will create duplicates. The user is responsible for not importing the same statement twice.
- **Keyword map is best-effort**: The categorizer won't catch every concept. Unmatched transactions get an empty category and are resolved in the app's mapping screen during import.

## Verification

1. Run `uv run parse_statement.py bbva_tc.pdf` and verify CSV output
2. Check that dates are correctly formatted (`YYYY-MM-DD HH:MM:SS`)
3. Check that amounts are positive decimals in unit currency (pesos)
4. Check that EXPENSE/INCOME types are correctly assigned
5. Verify categorization rate in summary output
6. Import the CSV into Pocket Pilot and verify transactions appear correctly in the mapping screen
7. Spot-check a few transactions against the PDF to confirm data integrity
