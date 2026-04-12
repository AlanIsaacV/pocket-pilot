import re
from datetime import date
from pathlib import Path

import pdfplumber

from parsers.base import StatementParser, Transaction

MONTH_MAP = {
    "ENE": 1, "FEB": 2, "MAR": 3, "ABR": 4,
    "MAY": 5, "JUN": 6, "JUL": 7, "AGO": 8,
    "SEP": 9, "OCT": 10, "NOV": 11, "DIC": 12,
}

# Statement period: "Periodo DEL DD/MM/YYYY AL DD/MM/YYYY"
PERIOD_RE = re.compile(
    r"Periodo\s+DEL\s+(\d{2}/\d{2}/\d{4})\s+AL\s+(\d{2}/\d{2}/\d{4})"
)

# Transaction first line: DD/MMM DD/MMM DESCRIPTION AMOUNT [SALDO SALDO]
TRANSACTION_HEAD_RE = re.compile(
    r"^(\d{2}/[A-Z]{3})\s+"          # operation date
    r"\d{2}/[A-Z]{3}\s+"             # liquidation date (ignored)
    r"(.+?)\s+"                      # description (non-greedy)
    r"([\d,]+\.\d{2})"              # first amount (tx amount)
    r"(?:\s+[\d,]+\.\d{2})*\s*$"    # trailing saldo amounts (ignored)
)

# Section delimiters
SECTION_START = "Detalle de Movimientos Realizados"
SECTION_END = "Total de Movimientos"

# Descriptions that indicate incoming money
INCOME_KEYWORDS = ["SPEI RECIBIDO", "DEPOSITO", "ABONO", "DEVOLUCION", "BONIFICACION"]


def _parse_date_dmy(date_str: str) -> date:
    """Parse DD/MM/YYYY date."""
    day, month, year = date_str.split("/")
    return date(int(year), int(month), int(day))


def _extract_period(text: str) -> tuple[date, date]:
    """Extract statement period from the full text."""
    match = PERIOD_RE.search(text)
    if not match:
        raise ValueError("Could not find statement period header (Periodo DEL ... AL ...)")
    return _parse_date_dmy(match.group(1)), _parse_date_dmy(match.group(2))


def _resolve_year(day: int, month: int, period_start: date, period_end: date) -> int:
    """Determine the correct year for a DD/MMM date given the statement period.

    Handles periods that span a year boundary (e.g., Dec 2025 to Jan 2026).
    """
    for year in (period_start.year, period_end.year):
        try:
            candidate = date(year, month, day)
        except ValueError:
            continue
        if period_start <= candidate <= period_end:
            return year
    # Fallback for edge cases: months >= start month use start year
    if month >= period_start.month:
        return period_start.year
    return period_end.year


def _parse_tx_date(date_str: str, period_start: date, period_end: date) -> date:
    """Parse DD/MMM transaction date and resolve year from the period."""
    day_str, month_str = date_str.split("/")
    day = int(day_str)
    month = MONTH_MAP[month_str]
    year = _resolve_year(day, month, period_start, period_end)
    return date(year, month, day)


def _parse_amount(amount_str: str) -> float:
    """Parse amount string like '1,165.00' to float."""
    return float(amount_str.replace(",", ""))


def _classify_type(description: str) -> str:
    """Classify transaction as INCOME or EXPENSE based on description keywords."""
    desc_upper = description.upper()
    for keyword in INCOME_KEYWORDS:
        if keyword in desc_upper:
            return "INCOME"
    return "EXPENSE"


def _extract_concept(line: str) -> str | None:
    """Extract user concept from a continuation line starting with 7 digits.

    SPEI continuation lines look like: '2901260antojos de embarazo Referencia 0052688884 722'
    Returns the concept text ('antojos de embarazo') or None.
    """
    stripped = line.strip()
    if not re.match(r"^\d{7}", stripped):
        return None
    concept = stripped[7:]
    ref_idx = concept.find("Referencia")
    if ref_idx != -1:
        concept = concept[:ref_idx]
    concept = concept.strip()
    if not concept or concept.isdigit():
        return None
    return concept


def _build_notes(description: str, continuation_lines: list[str]) -> str:
    """Build the notes field from description and continuation lines.

    For SPEI transactions, extracts the user concept from the 7-digit prefix line.
    For other transactions, uses the first continuation line stripped of Referencia suffix.
    """
    desc = description.strip()
    if not continuation_lines:
        return desc

    first = continuation_lines[0].strip()

    # Try to extract concept from 7-digit prefix line (SPEI transactions)
    concept = _extract_concept(first)
    if concept:
        return f"{desc} | {concept}"

    # For non-SPEI: use first continuation stripped of Referencia suffix
    clean = re.sub(r"\s*Referencia\s.*$", "", first).strip()
    if clean:
        return f"{desc} | {clean}"

    return desc


class BbvaDebParser(StatementParser):
    def parse(self, pdf_path: Path, account_name: str) -> list[Transaction]:
        transactions: list[Transaction] = []

        with pdfplumber.open(pdf_path) as pdf:
            full_text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        period_start, period_end = _extract_period(full_text)

        # Collect lines within the transaction section
        in_section = False
        section_lines: list[str] = []
        for line in full_text.split("\n"):
            if SECTION_START in line:
                in_section = True
                continue
            if SECTION_END in line:
                in_section = False
                continue
            if in_section:
                section_lines.append(line)

        # Group lines into transaction blocks: (head_match, [continuation_lines])
        raw_transactions: list[tuple[re.Match, list[str]]] = []
        for line in section_lines:
            head_match = TRANSACTION_HEAD_RE.match(line.strip())
            if head_match:
                raw_transactions.append((head_match, []))
            elif raw_transactions and line.strip():
                raw_transactions[-1][1].append(line)

        # Build Transaction objects
        for head_match, continuations in raw_transactions:
            date_str = head_match.group(1)
            description = head_match.group(2)
            amount_str = head_match.group(3)

            tx_date = _parse_tx_date(date_str, period_start, period_end)
            amount = _parse_amount(amount_str)
            tx_type = _classify_type(description)
            notes = _build_notes(description, continuations)

            transactions.append(Transaction(
                date=tx_date,
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
