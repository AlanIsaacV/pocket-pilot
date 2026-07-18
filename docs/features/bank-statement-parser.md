# Bank Statement Parser (Python scripts)

## What it does

Standalone **Python** scripts in `scripts/` that parse bank-statement PDFs into the 11-column CSV
consumed by [CSV Import](csv-import.md). **Not an app feature** — utility scripts run locally via
`uv`. Currently supports three Mexican bank products.

## Entry points

```bash
cd scripts
uv run parse_statement.py <pdf> [--account NAME] [--output PATH]
```

## Files involved

```
scripts/
├── pyproject.toml              # uv project: pdfplumber>=0.11
├── parse_statement.py          # CLI entrypoint
├── parsers/
│   ├── __init__.py             # detect_bank() + parser registry
│   ├── base.py                 # Transaction dataclass + StatementParser ABC
│   ├── bbva_tc.py              # BBVA credit card
│   ├── bbva_deb.py             # BBVA debit (Libretón)
│   └── rappi.py                # RappiCard (Banorte)
├── categorizer.py              # 190+ keyword→category mappings (first match wins)
└── csv_writer.py               # Transaction list → 11-column CSV
```

## Supported banks

| Bank ID    | Product              | Date format        | Type detection       | Account default |
|------------|----------------------|--------------------|----------------------|-----------------|
| `bbva_tc`  | BBVA credit card     | `DD-mmm-YYYY`      | `+`/`-` sign         | BBVA TC         |
| `bbva_deb` | BBVA Libretón debit  | `DD/MMM` (no year) | Description keywords | BBVA Deb        |
| `rappi`    | RappiCard (Banorte)  | `YYYY-MM-DD`       | `+$`/`-$` sign       | Rappi           |

## Data flow / key behaviors

1. **Bank detection** — reads first-page text, matches keywords (checks "rappicard" first, then
   "bbva" sub-types) to pick the parser.
2. **BBVA TC** — `extract_text()` + line-by-line regex; Spanish month map (`ene→1…dic→12`); skips
   MSI installment payments (`NN DE NN` prefix) but keeps original purchases with `installments_count`.
3. **BBVA Deb** — full-text extraction (period header needed for dates); two-pass (collect section
   lines → group into multi-line blocks); year resolved from `Periodo DEL DD/MM/YYYY AL …`; notes
   combine description + SPEI continuation concept.
4. **Rappi** — page-by-page `extract_text()` + regex; ISO dates; strips `; RFC: XXX` suffix; skips
   the MSI section entirely.
5. **Categorizer** — ordered `(keyword, category)` tuples matched against the uppercase concept
   (specific keywords first); unmatched → empty string.

## Extending

Add `parsers/<bank>.py` implementing `StatementParser`, register it in `parsers/__init__.py`, and add
a default account in `parse_statement.py`.

## Related docs

- [csv-import.md](csv-import.md) — the in-app importer that consumes this output.
- Historical design: `docs/specs/2026-04-11-bank-statement-parser-design.md`.
- `scripts/dump_captured_notifications.sh` (adb + sqlite3, debug builds) extracts notification
  fixtures — see [notification-capture.md](notification-capture.md).
```
