import re
from datetime import date
from pathlib import Path

import pdfplumber

from parsers.base import StatementParser, Transaction

# Transaction line: YYYY-MM-DD YYYY-MM-DD DESCRIPTION +/-$AMOUNT
TRANSACTION_RE = re.compile(
    r"(\d{4}-\d{2}-\d{2})\s+"      # operation date
    r"\d{4}-\d{2}-\d{2}\s+"        # charge date (ignored)
    r"(.+?)\s+"                    # description (non-greedy)
    r"([+-])\$([\d,]+\.\d{2})"     # sign + amount
)

RFC_SUFFIX_RE = re.compile(r";\s*RFC:\s*\S+$")

# Section headers
REGULAR_SECTION_HEADER = "CARGOS, ABONOS Y COMPRAS REGULARES"
MSI_SECTION_HEADER = "COMPRAS Y CARGOS DIFERIDOS A MESES"
STOP_SECTIONS = ["Total de cargos", "ATENCIÓN DE QUEJAS"]


def _parse_date(date_str: str) -> date:
    """Parse YYYY-MM-DD date."""
    return date.fromisoformat(date_str)


def _parse_amount(amount_str: str) -> float:
    """Parse amount string like '2,039.77' to float."""
    return float(amount_str.replace(",", ""))


def _clean_description(description: str) -> str:
    """Strip the '; RFC: XXXXX' suffix from descriptions."""
    return RFC_SUFFIX_RE.sub("", description).strip()


class RappiParser(StatementParser):
    def parse(self, pdf_path: Path, account_name: str) -> list[Transaction]:
        transactions: list[Transaction] = []
        in_regular_section = False

        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages:
                text = page.extract_text()
                if not text:
                    continue

                for line in text.split("\n"):
                    line = line.strip()
                    if not line:
                        continue

                    if REGULAR_SECTION_HEADER in line:
                        in_regular_section = True
                        continue

                    if MSI_SECTION_HEADER in line:
                        in_regular_section = False
                        continue

                    if any(stop in line for stop in STOP_SECTIONS):
                        in_regular_section = False
                        continue

                    if not in_regular_section:
                        continue

                    match = TRANSACTION_RE.match(line)
                    if not match:
                        continue

                    op_date_str, description, sign, amount_str = match.groups()

                    op_date = _parse_date(op_date_str)
                    amount = _parse_amount(amount_str)
                    notes = _clean_description(description)

                    # + means charge (expense), - means payment/credit (income)
                    tx_type = "EXPENSE" if sign == "+" else "INCOME"

                    transactions.append(Transaction(
                        date=op_date,
                        type=tx_type,
                        amount=amount,
                        currency="MXN",
                        account=account_name,
                        destination_account="",
                        category="",
                        tags="",
                        notes=notes,
                        installments_count=1,
                    ))

        return transactions
