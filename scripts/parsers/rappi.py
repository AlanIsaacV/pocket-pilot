import re
from datetime import date
from pathlib import Path

import pdfplumber

from parsers.base import StatementParser, Transaction

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

RFC_SUFFIX_RE = re.compile(r";\s*RFC:\s*\S+$")


def _parse_date(date_str: str) -> date:
    return date.fromisoformat(date_str)


def _parse_amount(amount_str: str) -> float:
    return float(amount_str.replace(",", ""))


def _clean_description(description: str) -> str:
    """Strip '; RFC: XXXXX' suffix and trailing whitespace."""
    return RFC_SUFFIX_RE.sub("", description).strip()


# ---------------------------------------------------------------------------
# NEW FORMAT (Banorte, from ~March 2026)
# ---------------------------------------------------------------------------

# Section headers
NEW_REGULAR_HEADER = "CARGOS, ABONOS Y COMPRAS REGULARES"
NEW_MSI_HEADER = "COMPRAS Y CARGOS DIFERIDOS A MESES"
NEW_STOP_SECTIONS = ["Total de cargos", "ATENCIÓN DE QUEJAS"]

# YYYY-MM-DD YYYY-MM-DD DESCRIPTION +/-$AMOUNT
NEW_TX_RE = re.compile(
    r"(\d{4}-\d{2}-\d{2})\s+"      # operation date
    r"\d{4}-\d{2}-\d{2}\s+"        # charge date (ignored)
    r"(.+?)\s+"                    # description (non-greedy)
    r"([+-])\$([\d,]+\.\d{2})"     # sign + amount
)

# MSI line (after joining continuation lines):
# YYYY-MM-DD DESCRIPTION $ORIG_AMOUNT $PENDING $PAYMENT N de M RATE%
NEW_MSI_RE = re.compile(
    r"(\d{4}-\d{2}-\d{2})\s+"               # operation date
    r"(.+?)\s+"                              # description
    r"\$([\d,]+\.\d{2})\s+"                  # original amount
    r"\$[\d,]+\.\d{2}\s+"                    # pending (ignored)
    r"\$[\d,]+\.\d{2}\s+"                    # payment (ignored)
    r"(\d+)\s+de\s+(\d+)\s+"                # N de M
    r"[\d.]+"                                # interest rate
)

# ---------------------------------------------------------------------------
# OLD FORMAT (Tarjetas del Futuro / Rappi original, through ~Feb 2026)
# ---------------------------------------------------------------------------

# Charges: YYYY-MM-DD MERCHANT [$0.00 | USD XX.XX] $AMOUNT
OLD_CHARGE_RE = re.compile(
    r"(\d{4}-\d{2}-\d{2})\s+"       # date
    r"(.+)\s+"                       # description (greedy — captures up to last $)
    r"\$([\d,]+\.\d{2})\s*$"         # MXN amount at end of line
)

# Payments: YYYY-MM-DD DESCRIPTION AMOUNT  (no $ prefix)
OLD_PAYMENT_RE = re.compile(
    r"(\d{4}-\d{2}-\d{2})\s+"
    r"(.+?)\s+"
    r"([\d,]+\.\d{2})\s*$"
)

# MSI: YYYY-MM-DD MERCHANT $ ORIG $ PENDING $ INTEREST N de M $ MONTHLY
OLD_MSI_RE = re.compile(
    r"(\d{4}-\d{2}-\d{2})\s+"                   # date
    r"(.+?)\s+"                                  # merchant
    r"\$\s*([\d,]+\.\d{2})\s+"                   # original amount
    r"\$\s*[\d,]+\.\d{2}\s+"                     # pending (ignored)
    r"\$\s*[\d,]+\.\d{2}\s+"                     # interest (ignored)
    r"(\d+)\s+de\s+(\d+)\s+"                     # N de M
    r"\$\s*[\d,]+\.\d{2}"                        # monthly (ignored)
)

# Lines to skip inside old-format sections
OLD_SKIP_RE = re.compile(
    r"^(Subtotal|Movimientos tarjeta|Fecha\s+(Comercio|Detalle|Más detalle)"
    r"|Compra en el Extranjero|Total cargos|Total pagos"
    r"|Las mensualidades)"
)

# Clean trailing $0.00 or USD XX.XX from greedy charge description
TRAILING_CURRENCY_RE = re.compile(r"\s+(\$[\d,]+\.\d{2}|USD\s+[\d,]+\.\d{2})$")


class RappiParser(StatementParser):
    def parse(self, pdf_path: Path, account_name: str) -> list[Transaction]:
        full_text = self._extract_text(pdf_path)
        if NEW_REGULAR_HEADER in full_text:
            return self._parse_new_format(pdf_path, account_name)
        return self._parse_old_format(pdf_path, account_name)

    # ------------------------------------------------------------------
    # Text extraction
    # ------------------------------------------------------------------

    @staticmethod
    def _extract_text(pdf_path: Path) -> str:
        with pdfplumber.open(pdf_path) as pdf:
            parts = []
            for page in pdf.pages:
                text = page.extract_text()
                if text:
                    parts.append(text)
            return "\n".join(parts)

    # ------------------------------------------------------------------
    # NEW FORMAT (Banorte)
    # ------------------------------------------------------------------

    def _parse_new_format(self, pdf_path: Path, account_name: str) -> list[Transaction]:
        transactions: list[Transaction] = []
        section = "IDLE"  # IDLE | REGULAR | MSI
        msi_buffer: list[str] = []

        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages:
                text = page.extract_text()
                if not text:
                    continue

                for line in text.split("\n"):
                    line = line.strip()
                    if not line:
                        continue

                    # Section transitions
                    if NEW_REGULAR_HEADER in line:
                        if msi_buffer:
                            transactions.extend(self._flush_new_msi(msi_buffer, account_name))
                            msi_buffer.clear()
                        section = "REGULAR"
                        continue
                    if NEW_MSI_HEADER in line:
                        section = "MSI"
                        continue
                    if any(stop in line for stop in NEW_STOP_SECTIONS):
                        if msi_buffer:
                            transactions.extend(self._flush_new_msi(msi_buffer, account_name))
                            msi_buffer.clear()
                        section = "IDLE"
                        continue

                    if section == "REGULAR":
                        match = NEW_TX_RE.match(line)
                        if not match:
                            continue
                        op_date_str, description, sign, amount_str = match.groups()
                        tx_type = "EXPENSE" if sign == "+" else "INCOME"
                        transactions.append(Transaction(
                            date=_parse_date(op_date_str),
                            type=tx_type,
                            amount=_parse_amount(amount_str),
                            currency="MXN",
                            account=account_name,
                            destination_account="",
                            category="",
                            tags="",
                            notes=_clean_description(description),
                            installments_count=1,
                        ))

                    elif section == "MSI":
                        msi_buffer.append(line)

        # Flush any remaining MSI lines
        if msi_buffer:
            transactions.extend(self._flush_new_msi(msi_buffer, account_name))

        return transactions

    def _flush_new_msi(self, lines: list[str], account_name: str) -> list[Transaction]:
        """Join continuation lines in the MSI buffer and parse."""
        results: list[Transaction] = []
        for joined_line in self._join_continuation_lines(lines):
            tx = self._parse_new_msi_line(joined_line, account_name)
            if tx:
                results.append(tx)
        return results

    def _parse_new_msi_line(self, line: str, account_name: str) -> Transaction | None:
        """Parse a single MSI line from the new Banorte format."""
        match = NEW_MSI_RE.match(line)
        if not match:
            return None
        op_date_str, description, orig_amount_str, n_str, m_str = match.groups()
        if int(n_str) != 1:
            return None
        return Transaction(
            date=_parse_date(op_date_str),
            type="EXPENSE",
            amount=_parse_amount(orig_amount_str),
            currency="MXN",
            account=account_name,
            destination_account="",
            category="",
            tags="",
            notes=_clean_description(description),
            installments_count=int(m_str),
        )

    @staticmethod
    def _join_continuation_lines(lines: list[str]) -> list[str]:
        """Join lines that don't start with a date to the previous line."""
        joined: list[str] = []
        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue
            if joined and not re.match(r"\d{4}-\d{2}-\d{2}", stripped):
                joined[-1] += " " + stripped
            else:
                joined.append(stripped)
        return joined

    # ------------------------------------------------------------------
    # OLD FORMAT (Tarjetas del Futuro)
    # ------------------------------------------------------------------

    def _parse_old_format(self, pdf_path: Path, account_name: str) -> list[Transaction]:
        transactions: list[Transaction] = []
        section = "IDLE"  # IDLE | CHARGES | PAYMENTS | MSI
        prev_text_line = ""  # buffer for foreign-purchase merchant names

        with pdfplumber.open(pdf_path) as pdf:
            for page in pdf.pages:
                text = page.extract_text()
                if not text:
                    continue

                for line in text.split("\n"):
                    line = line.strip()
                    if not line:
                        continue

                    # --- Section transitions ---
                    if re.match(r"Compras y cargos \d+", line):
                        section = "CHARGES"
                        prev_text_line = ""
                        continue
                    if "Pagos, devoluciones y bonificaciones" in line:
                        section = "PAYMENTS"
                        continue
                    if line == "Compras a meses" or (
                        "Compras a meses" in line
                        and "retiros" not in line
                        and "Saldo" not in line
                        and len(line) < 25
                    ):
                        section = "MSI"
                        continue
                    if "Total cargos del periodo" in line:
                        section = "IDLE"
                        continue
                    if "Total pagos del periodo" in line:
                        section = "IDLE"
                        continue
                    if any(kw in line for kw in [
                        "Información de costos", "Desglose de monto",
                        "Tu estado de cuenta", "Contacto",
                    ]):
                        section = "IDLE"
                        continue

                    if section == "IDLE":
                        continue

                    if OLD_SKIP_RE.match(line):
                        continue

                    # --- CHARGES section ---
                    if section == "CHARGES":
                        match = OLD_CHARGE_RE.match(line)
                        if match:
                            op_date_str, raw_desc, amount_str = match.groups()
                            desc = TRAILING_CURRENCY_RE.sub("", raw_desc).strip()

                            # Foreign purchase: description is just the currency
                            # info, real merchant is on previous line
                            if re.match(r"^(USD|\$)", desc):
                                desc = prev_text_line if prev_text_line else desc

                            transactions.append(Transaction(
                                date=_parse_date(op_date_str),
                                type="EXPENSE",
                                amount=_parse_amount(amount_str),
                                currency="MXN",
                                account=account_name,
                                destination_account="",
                                category="",
                                tags="",
                                notes=desc,
                                installments_count=1,
                            ))
                            prev_text_line = ""
                        else:
                            # Buffer non-matching lines as potential merchant
                            # names for foreign purchases
                            if not line.startswith("Subtotal"):
                                prev_text_line = line
                        continue

                    # --- PAYMENTS section ---
                    if section == "PAYMENTS":
                        match = OLD_PAYMENT_RE.match(line)
                        if not match:
                            continue
                        op_date_str, description, amount_str = match.groups()
                        transactions.append(Transaction(
                            date=_parse_date(op_date_str),
                            type="INCOME",
                            amount=_parse_amount(amount_str),
                            currency="MXN",
                            account=account_name,
                            destination_account="",
                            category="",
                            tags="",
                            notes=description.strip(),
                            installments_count=1,
                        ))
                        continue

                    # --- MSI section ---
                    if section == "MSI":
                        if "Subtotal" in line:
                            section = "IDLE"
                            continue
                        match = OLD_MSI_RE.match(line)
                        if not match:
                            continue
                        op_date_str, merchant, orig_amount_str, n_str, m_str = match.groups()
                        if int(n_str) != 1:
                            continue
                        transactions.append(Transaction(
                            date=_parse_date(op_date_str),
                            type="EXPENSE",
                            amount=_parse_amount(orig_amount_str),
                            currency="MXN",
                            account=account_name,
                            destination_account="",
                            category="",
                            tags="",
                            notes=merchant.strip(),
                            installments_count=int(m_str),
                        ))

        return transactions
