import re
from decimal import Decimal

VERSION = "2.1"
STANDARD_ANNUAL_HOURS = 1950

# Strict currency format
MONEY = (
    r"\$\s*(?P<amount>"
    r"(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)"
    r"(?:\.[0-9]{1,2})?"
    r")(?![0-9,.])"
)

UNIT = (
    r"\s*(?P<unit>"
    r"/hour\b|/hr\b|per hour\b|hourly\b|"
    r"/year\b|per year\b|annually\b|annual\b|"
    r"/month\b|per month\b|monthly\b|"
    r"biweekly\b|bi-weekly\b"
    r")"
)

START = (
    r"\b(?:"
    r"(?:(?:minimum|starting|base)\s+)?salary"
    r"\s+for\s+this\s+position\s+"
    r"(?:traditionally\s+)?"
    r"(?:starts?\s+(?:at|between)|is)"
    r"|this\s+position\s+(?:traditionally\s+)?starts?\s+at|salary\s+range\s+for\s+this\s+position\s+is"
    r"|starting\s+salary\s+(?:is|of)"
    r"|salary\s+ranges?\s+from"
    r")\s+(?:(?:an?|the)\s+)?"
    r"(?:(?P<prefix_unit>hourly|annual|monthly|biweekly)"
    r"\s+(?:rate|salary|pay|wage)\s+of\s+)?"
)

BASE_PATTERN = re.compile(
    START + MONEY.replace(
        r"(?![0-9,.])", r"(?![0-9,]|\.[0-9])"
    ),
    re.I
)

UNIT_PATTERN = re.compile(UNIT, re.I)

RANGE_PATTERN = re.compile(
    r"\s*(?:-|–|—|to\b|and\b|up to\b)\s*"
    + MONEY.replace(
        r"(?![0-9,.])", r"(?![0-9,]|\.[0-9])"
    ),
    re.I
)


def normalize_frequency(unit):
    unit = unit.lower().strip()

    if unit in ("/hour", "/hr", "per hour", "hourly"):
        return "HOURLY"

    if unit in ("/year", "per year", "annually", "annual"):
        return "ANNUAL"

    if unit in ("/month", "per month", "monthly"):
        return "MONTHLY"

    if unit in ("biweekly", "bi-weekly"):
        return "BIWEEKLY"

    return "UNKNOWN"


def annualize(amount, frequency):
    factors = {
        "HOURLY": STANDARD_ANNUAL_HOURS,
        "ANNUAL": 1,
        "MONTHLY": 12,
        "BIWEEKLY": 26,
    }

    factor = factors.get(frequency)

    return amount * factor if factor else None


def extract_description_base(text):
    results = []

    if not text:
        return results

    for match in BASE_PATTERN.finditer(text):

        amount = Decimal(
            match.group("amount").replace(",", "")
        )

        if amount <= 0:
            continue

        tail = text[match.end():]
        unit_match = UNIT_PATTERN.match(tail)
        range_match = RANGE_PATTERN.match(tail)

        upper = None
        evidence_end = match.end()

        if range_match:
            upper = Decimal(
                range_match.group("amount").replace(",", "")
            )

            if upper < amount:
                continue

            unit_match = UNIT_PATTERN.match(
                tail[range_match.end():]
            )

            evidence_end += range_match.end()

        if unit_match:
            frequency = normalize_frequency(
                unit_match.group("unit")
            )
            evidence_end += unit_match.end()
        else:
            frequency = "UNKNOWN"

        prefix = match.group("prefix_unit")

        if prefix:
            prefix_frequency = normalize_frequency(prefix)

            if frequency not in ("UNKNOWN", prefix_frequency):
                continue

            frequency = prefix_frequency

        results.append({
            "base_salary": amount,
            "upper_salary": upper,
            "frequency": frequency,
            "annualized_salary": annualize(
                amount, frequency
            ),
            "frequency_basis": (
                "EXPLICIT"
                if frequency != "UNKNOWN"
                else "UNRESOLVED"
            ),
            "evidence": text[
                match.start():evidence_end
            ],
            "extraction_version": VERSION,
        })

    return results


if __name__ == "__main__":

    tests = [
        (
            "The salary for this position starts at $90,000.00.",
            "90000.00", "UNKNOWN"
        ),
        (
            "The salary for this position traditionally starts "
            "between $45,422.00 and $68,120.00.",
            "45422.00", "UNKNOWN"
        ),
        (
            "This position starts at a $22.00/hour base pay "
            "+ $2/hour of differential pay.",
            "22.00", "HOURLY"
        ),
        (
            "The salary for this position is "
            "$13.00 - $17.00 per hour.",
            "13.00", "HOURLY"
        ),
        (
            "The salary for this position traditionally starts "
            "at $42,900.00. Total compensation is $69,822.98.",
            "42900.00", "UNKNOWN"
        ),
        (
            "The salary for this position starts at $83,00.00.",
            None, None
        ),
        (
            "The department manages a $150,000,000 budget.",
            None, None
        ),
        (
            "This position starts at $14.23 per hour.",
            "14.23", "HOURLY"
        ),
    ]

    for index, (text, expected, frequency) in enumerate(tests, 1):

        result = extract_description_base(text)

        if expected is None:
            assert not result, result
        else:
            assert len(result) == 1, result
            assert result[0]["base_salary"] == Decimal(expected)
            assert result[0]["frequency"] == frequency

        print(f"Test {index}: PASS")

    assert annualize(Decimal("22"), "HOURLY") == Decimal("42900")

    print("Annualization test: PASS")
    print("COMPENSATION PARSER: ALL TESTS PASSED")
