import csv
from pathlib import Path

from parsers.base import Transaction

HEADERS = [
    "date", "type", "amount", "currency", "account",
    "destination_account", "category", "tags", "notes",
    "nature", "installments_count",
]


def write_csv(transactions: list[Transaction], output_path: Path) -> None:
    """Write transactions to CSV in the format Pocket Pilot expects."""
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(HEADERS)
        for tx in transactions:
            writer.writerow([
                f"{tx.date} 12:00:00",
                tx.type,
                f"{tx.amount:.2f}",
                tx.currency,
                tx.account,
                tx.destination_account,
                tx.category,
                tx.tags,
                tx.notes,
                tx.nature,
                tx.installments_count,
            ])
