from pathlib import Path

import pdfplumber

from parsers.bbva_deb import BbvaDebParser
from parsers.bbva_tc import BbvaTcParser
from parsers.rappi import RappiParser
from parsers.base import StatementParser

PARSERS: dict[str, type[StatementParser]] = {
    "bbva_tc": BbvaTcParser,
    "bbva_deb": BbvaDebParser,
    "rappi": RappiParser,
}


def detect_bank(pdf_path: Path) -> str:
    """Detect bank type from PDF content by reading the first page."""
    with pdfplumber.open(pdf_path) as pdf:
        first_page_text = pdf.pages[0].extract_text() or ""
        text = first_page_text.lower()

    if "rappicard" in text:
        return "rappi"

    if "bbva" in text:
        if "libretón" in text or "libreton" in text or "cuenta digital" in text:
            return "bbva_deb"
        if "tarjeta de crédito" in text or "tarjeta oro bbva" in text:
            return "bbva_tc"

    raise ValueError(
        f"Could not detect bank from PDF: {pdf_path.name}. "
        "Supported banks: Rappi, BBVA TC (credit card), BBVA Deb (debit)"
    )


def get_parser(bank_id: str) -> StatementParser:
    """Get parser instance for the given bank ID."""
    parser_cls = PARSERS.get(bank_id)
    if parser_cls is None:
        raise ValueError(f"No parser for bank: {bank_id}. Available: {list(PARSERS.keys())}")
    return parser_cls()
