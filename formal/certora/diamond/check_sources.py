#!/usr/bin/env python3
"""Check the initializer element refinement directly against repository sources."""

from pathlib import Path
import re


def block_body(source: str, marker: str) -> str:
    """Extract one complete block, ignoring braces in comments and literals."""
    assert source.count(marker) == 1, f"expected one {marker!r}"
    start = source.index("{", source.index(marker))
    tokens = re.finditer(
        r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]',
        source[start:],
    )
    depth = 0
    for token in tokens:
        value = token.group()
        if value == "{":
            depth += 1
        elif value == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1 : start + token.start()]
    raise AssertionError(f"unterminated block for {marker!r}")


def compact(source: str) -> str:
    return re.sub(r"\s+", "", source)


def check_sources(production: str, model: str) -> None:
    # The wrapper supplies the selected immutable calldata element as its argument.
    # Require that selection to be the entire production loop prefix, so newly
    # inserted statements before validation cannot silently escape comparison.
    loop = block_body(
        production, "for (uint256 i; i < params.lotteryConfigs.length; ++i)"
    )
    binding = re.match(
        r"\s*LotteryConfig\s+calldata\s+config\s*=\s*"
        r"params\.lotteryConfigs\[i\];\s*",
        loop,
    )
    assert binding is not None, "initializer calldata element binding changed"
    body = loop[binding.end() :].rstrip()
    assert body.startswith("LibLotteryConfig.validate(config);"), (
        "initializer body no longer starts with validation"
    )
    assert body in model, "initializer element is not a verbatim production body"

    prelude = (
        "LibLotteryStorage.GameStorage storage game=LibLotteryStorage.gameStorage();"
        "LibLotteryStorage.AccountingStorage storage accounting="
        "LibLotteryStorage.accountingStorage();"
    )
    actual = block_body(model, "function append(")
    assert compact(actual) == compact(prelude + body), (
        "initializer append wrapper differs from its storage prelude and full body"
    )


def main() -> None:
    root = Path(__file__).resolve().parents[3]
    check_sources(
        (root / "src/initializers/LotteryInit.sol").read_text(),
        (Path(__file__).resolve().parent / "harness/InitializerElement.sol").read_text(),
    )
    print("PASS: exact initializer element body and complete append wrapper")


if __name__ == "__main__":
    main()
