import re
from datetime import date
from pathlib import Path

import pdfplumber

from parsers.base import StatementParser, Transaction

MONTH_MAP = {
    "ene": 1, "feb": 2, "mar": 3, "abr": 4,
    "may": 5, "jun": 6, "jul": 7, "ago": 8,
    "sep": 9, "oct": 10, "nov": 11, "dic": 12,
}

# Regex for regular transaction lines:
# DD-mmm-YYYY DD-mmm-YYYY DESCRIPTION +/- $AMOUNT
TRANSACTION_RE = re.compile(
    r"(\d{2}-[a-z]{3}-\d{4})\s+"  # operation date
    r"\d{2}-[a-z]{3}-\d{4}\s+"    # charge date (captured but unused)
    r"(.+?)\s+"                    # description
    r"([+-])\s+"                   # sign
    r"\$([\d,]+\.\d{2})"          # amount
)

# Regex to extract MSI info from description like "AMAZON A MESES A 12 MESES S/I"
MSI_RE = re.compile(r"A\s+(\d+)\s+MESES\s+S/I")

# Regex to detect monthly installment payments like "04 DE 12 MERPAGO*MONTESSORI"
# These are skipped — the original purchase (full amount) is the real transaction.
INSTALLMENT_PAYMENT_RE = re.compile(r"^\d{2} DE \d{2} ")

# Section headers to detect which section we're in
REGULAR_SECTION_HEADER = "CARGOS,COMPRAS Y ABONOS REGULARES"
MSI_SECTION_HEADER = "COMPRAS Y CARGOS DIFERIDOS A MESES SIN INTERESES"
BENEFITS_SECTION_HEADER = "DETALLE DE TRANSACCIONES DE BENEFICIOS"
SKIP_SECTIONS = {MSI_SECTION_HEADER, BENEFITS_SECTION_HEADER}

# Lines to skip entirely
SKIP_LINE_PATTERNS = [
    re.compile(r"^IVA\s*:\$"),           # IVA breakdown after payments
    re.compile(r"^de promoción"),          # continuation of IVA breakdown
    re.compile(r"^TOTAL\s+(CARGOS|ABONOS)"),  # totals
    re.compile(r"^Notas:"),               # footer notes
    re.compile(r"^Número de cuenta:"),     # page header
    re.compile(r"^Página\s+\d+"),          # page number
    re.compile(r"^Fecha$"),                # column header
    re.compile(r"^de la\s+Descripción"),   # column header continuation
    re.compile(r"^de cargo$"),             # column header
    re.compile(r"^operación$"),            # column header
    re.compile(r"^Tarjeta titular:"),       # sub-header
]


def _parse_date(date_str: str) -> date:
    """Parse DD-mmm-YYYY date with Spanish month abbreviations."""
    day_str, month_str, year_str = date_str.split("-")
    month = MONTH_MAP.get(month_str.lower())
    if month is None:
        raise ValueError(f"Unknown month abbreviation: {month_str}")
    return date(int(year_str), month, int(day_str))


def _parse_amount(amount_str: str) -> float:
    """Parse amount string like '1,165.00' to float."""
    return float(amount_str.replace(",", ""))


def _should_skip_line(line: str) -> bool:
    """Check if a line should be skipped."""
    return any(p.match(line) for p in SKIP_LINE_PATTERNS)


class BbvaTcParser(StatementParser):
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

                    # Track which section we're in
                    if REGULAR_SECTION_HEADER in line:
                        in_regular_section = True
                        continue

                    if any(header in line for header in SKIP_SECTIONS):
                        in_regular_section = False
                        continue

                    # Also exit regular section on non-transaction sections
                    if "ATENCIÓN DE QUEJAS" in line or "NOTAS ACLARATORIAS" in line:
                        in_regular_section = False
                        continue

                    if not in_regular_section:
                        continue

                    if _should_skip_line(line):
                        continue

                    match = TRANSACTION_RE.match(line)
                    if not match:
                        continue

                    op_date_str, description, sign, amount_str = match.groups()

                    # Skip monthly installment payments (e.g. "04 DE 12 MERPAGO*MONTESSORI").
                    # The original purchase at full amount is imported separately.
                    if INSTALLMENT_PAYMENT_RE.match(description):
                        continue

                    op_date = _parse_date(op_date_str)
                    amount = _parse_amount(amount_str)

                    # + means charge (expense), - means payment/credit (income)
                    tx_type = "EXPENSE" if sign == "+" else "INCOME"

                    # Detect MSI installments from description.
                    installments_count = 1
                    msi_match = MSI_RE.search(description)
                    if msi_match:
                        installments_count = int(msi_match.group(1))

                    transactions.append(Transaction(
                        date=op_date,
                        type=tx_type,
                        amount=amount,
                        currency="MXN",
                        account=account_name,
                        destination_account="",
                        category="",
                        tags="",
                        notes=description.strip(),
                        installments_count=installments_count,
                    ))

        return transactions
