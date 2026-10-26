#!/usr/bin/env python3
"""Check the source boundaries used by the ticket ownership induction.

This check complements the CVL obligations; it does not execute a prover.
Run from any directory with Python 3. A mismatch requires reviewing and updating
both the source refinement and its proof definitions.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]


def tokens(source):
    source = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    return re.findall(
        r"[A-Za-z_$][A-Za-z0-9_$]*|0x[0-9a-fA-F]+|[0-9]+|"
        r">>|<<|<=|>=|==|!=|&&|\|\||\+=|[^\s]", source
    )


def block(stream, marker):
    """Return the unique marked block's body and token boundaries."""
    marker = tokens(marker)
    starts = [i for i in range(len(stream)) if stream[i:i + len(marker)] == marker]
    assert len(starts) == 1, ("missing or ambiguous block", marker)
    opening = stream.index("{", starts[0] + len(marker))
    depth = 1
    closing = opening + 1
    while depth:
        depth += (stream[closing] == "{") - (stream[closing] == "}")
        closing += 1
    return stream[opening + 1:closing - 1], starts[0], closing


def expect(actual, expected, label):
    assert actual == tokens(expected), label


def check():
    library = tokens((ROOT / "src/libraries/LibTicketRanges.sol").read_text())
    step_source = tokens((ROOT / "formal/certora/ownership/harness/TicketSearchStep.sol").read_text())
    owner, _, _ = block(library, "function ownerOfTicket")
    iteration, start, end = block(owner, "while (low < high)")
    expect(owner[:start], """
        uint256 high = entries.length;
        if (high == 0 || ticket >= entries[high - 1].endExclusive) {
            revert Errors.InvalidTicket(ticket);
        }
        uint256 low = 0;
    """, "production initialization or invalid-ticket guard changed")
    expect(owner[end:], "return entries[low].buyer;", "production owner return changed")
    step, _, _ = block(step_source, "function step")
    assert step == tokens("if (low < high) {") + iteration + tokens("} return (low, high);"), \
        "step harness must contain only the exact guarded production iteration and tuple return"

    append, _, _ = block(library, "function append")
    expect(append, """
        uint256 length = entries.length;
        if (buyer == address(0) || endExclusive == 0 ||
            (length != 0 && endExclusive <= entries[length - 1].endExclusive)) {
            revert Errors.InvalidTicketRange();
        }
        entries.push(TicketRange(buyer, endExclusive));
    """, "production append checks or buyer/end identity changed")
    harness = tokens((ROOT / "formal/certora/ownership/harness/TicketOwnership.sol").read_text())
    wrapper, _, _ = block(harness, "function append")
    expect(wrapper, "LibTicketRanges.append(entries,buyer,endExclusive); sold=endExclusive;",
           "append proof wrapper changed")

    lottery = tokens((ROOT / "src/facets/LotteryFacet.sol").read_text())
    purchase, _, _ = block(lottery, "function _recordPurchase")
    expect(purchase, """
        uint32 startTicket = round.soldTickets;
        uint32 endExclusive = startTicket + ticketQuantity;
        uint256 amount = uint256(round.config.ticketPrice) * ticketQuantity;
        address paymentToken = round.config.paymentToken;
        round.soldTickets = endExclusive;
        round.receipts += amount;
        TicketRange[] storage entries = gs.entries[roundId];
        LibTicketRanges.append(entries, msg.sender, endExclusive);
        LibLotteryStorage.accountingStorage().assetAccounting[paymentToken].activeRoundEscrow += amount;
        LibExactToken.pullExact(paymentToken, msg.sender, amount);
        emit TicketsPurchased(roundId, msg.sender, paymentToken, startTicket,
                              ticketQuantity, endExclusive, amount);
        if (endExclusive == round.config.ticketCount) _commitSellout(round, roundId);
    """, "production purchase-to-buyer/endpoint connection changed")
    call = tokens("_recordPurchase(gs, round, roundId, ticketQuantity);")
    for name in ("openRound", "buyTickets"):
        body, _, _ = block(lottery, "function " + name)
        assert sum(body[i:i + len(call)] == call for i in range(len(body))) == 1, \
            ("purchase entrypoint connection changed", name)


if __name__ == "__main__":
    check()
    print("Ownership source correspondence: PASS")
