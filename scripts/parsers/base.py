from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import date
from pathlib import Path


@dataclass
class Transaction:
    date: date
    type: str               # "EXPENSE" | "INCOME"
    amount: float           # Always positive, in unit currency (pesos)
    currency: str           # "MXN"
    account: str            # Account name for CSV
    destination_account: str  # Always ""
    category: str           # Mapped category or ""
    tags: str               # Always ""
    notes: str              # Original bank concept
    nature: str = ""        # Financial nature (required, obligation, etc.)
    installments_count: int = 1  # MSI installment count


class StatementParser(ABC):
    @abstractmethod
    def parse(self, pdf_path: Path, account_name: str) -> list[Transaction]:
        """Parse a bank statement PDF and return a list of transactions."""
        ...
