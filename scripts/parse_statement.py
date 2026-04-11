#!/usr/bin/env python3
"""Parse bank statement PDFs into CSV format for Pocket Pilot import."""

import argparse
from pathlib import Path

from categorizer import categorize
from csv_writer import write_csv
from parsers import detect_bank, get_parser

# Default account names per bank
DEFAULT_ACCOUNTS = {
    "bbva_tc": "BBVA TC",
}


def main():
    parser = argparse.ArgumentParser(
        description="Parse bank statement PDFs into CSV for Pocket Pilot import."
    )
    parser.add_argument("pdf_path", type=Path, help="Path to the bank statement PDF")
    parser.add_argument("--account", type=str, help="Account name for CSV (default: inferred from bank)")
    parser.add_argument("--output", type=Path, help="Output CSV path (default: <pdf_name>.csv)")
    args = parser.parse_args()

    pdf_path: Path = args.pdf_path
    if not pdf_path.exists():
        print(f"Error: File not found: {pdf_path}")
        raise SystemExit(1)

    # Detect bank
    bank_id = detect_bank(pdf_path)
    print(f"Detected bank: {bank_id}")

    # Determine account name
    account_name = args.account or DEFAULT_ACCOUNTS.get(bank_id, bank_id)

    # Parse
    statement_parser = get_parser(bank_id)
    transactions = statement_parser.parse(pdf_path, account_name)
    print(f"Parsed {len(transactions)} transactions")

    # Categorize
    categorized = 0
    for tx in transactions:
        category = categorize(tx.notes)
        if category:
            tx.category = category
            categorized += 1

    # Write CSV
    output_path = args.output or pdf_path.with_suffix(".csv")
    write_csv(transactions, output_path)

    # Summary
    total = len(transactions)
    pct = (categorized / total * 100) if total > 0 else 0
    print()
    print(f"✓ Parsed {total} transactions from {pdf_path.name}")
    print(f"✓ Categorized: {categorized}/{total} ({pct:.0f}%)")
    print(f"✓ Uncategorized: {total - categorized} transactions (empty category for app mapping)")
    print(f"✓ Output: {output_path}")


if __name__ == "__main__":
    main()
