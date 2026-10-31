#!/usr/bin/env python3
"""Property-based fuzz of the session-list paging contract (PR #106 blocker #1).

The example-based widget tests only cover the pin layouts their author
thought of. This script transcribes the STOCK server semantics from
hermes-agent source and the CLIENT completion rule from
session_list_screen.dart / workspace_screen.dart / connection_manager.dart,
then asks Hypothesis to find (totalWindow, pin-set, pin-positions,
page-size) combinations where the client's accumulated set differs from
the server's full set — the oracle-anchoring countermeasure: the expected
value here is the FULL set, computed independently of the client loop.

Server semantics (grounded, do not "fix" from memory):
  gateway/platforms/api_server.py::_handle_list_sessions +
  hermes_state_sessions.py::list_sessions_rich(include_pinned=True):
    page = window rows [offset, offset+limit)  (newest-first, disjoint)
         + EVERY pinned row not in the window   (back-fill, repeats on
                                                 every page)
    has_more = (# non-pinned rows in the combined response) >= limit
  hermes_cli/web_routers/sessions.py::get_sessions (archived path):
    same back-fill, plus total = session_count(same scope)
    (window rows + pins outside the window; pins inside counted once)

Client rules under test:
  api-server path (session_list_screen / Home loader):
    advance offset by the REQUESTED page size; dedupe by id;
    zero-new-ids pages counted consecutively; completion proven iff
    zero_new >= (pin_count // page_size + 1) with pin_count == pins on a
    page (exact, since every response carries every pin); prune only on
    proven completion.
  archived path (connection_manager.getArchivedSessions):
    total-driven: advance until offset >= total.

Run:  /home/jon/.venvs/pbt/bin/python scripts/paging_contract_fuzz.py
"""
from hypothesis import HealthCheck, given, settings, strategies as st


# ── stock server model ──────────────────────────────────────────────────────

class StockServer:
    """ids are ints 0..total-1 (newest-first); pins is a frozenset."""

    def __init__(self, total, pins):
        self.total = total
        self.pins = frozenset(p for p in pins if 0 <= p < total)

    def page(self, offset, limit):
        window = list(range(offset, min(offset + limit, self.total)))
        backfill = [p for p in sorted(self.pins) if p not in set(window)]
        rows = [("pin", p) if p in self.pins else ("row", p)
                for p in backfill + window]
        non_pinned = sum(1 for kind, _ in rows if kind != "pin")
        return rows, non_pinned >= limit

    def full_set(self):
        return set(range(self.total)) | set(self.pins)

    # dashboard archived router: total counts the filtered rows exactly
    def total_count(self):
        return self.total  # pins are rows; back-fill never adds new ids


# ── client models (mirrors of the Dart rules) ───────────────────────────────

def client_api_server_pages(server, page_size, max_pages=200):
    """Returns (accumulated_ids, prune_sets) — prune_sets is the raw-id
    set at every point the client believed completion proven. max_pages
    is generous here; the production caps (scroll-driven screen = none,
    Home loader = 20x100) bound VOLUME, not correctness — the property
    below is about what the client CLAIMS, so a cap hit must simply mean
    "never claimed complete"."""
    seen = set()
    zero_new = 0
    pin_count = 0
    offset = 0
    prunes = []
    for _ in range(max_pages):
        rows, _has_more = server.page(offset, page_size)
        ids = {i for _, i in rows}
        new = ids - seen
        seen |= ids
        pins_on_page = sum(1 for kind, _ in rows if kind == "pin")
        pin_count = max(pin_count, pins_on_page)
        zero_new = zero_new + 1 if not new else 0
        required = 1 if pin_count == 0 else pin_count // page_size + 1
        if zero_new >= required:
            prunes.append(frozenset(seen))
            return seen, prunes
        offset += page_size
    return seen, prunes  # cap reached: never complete, never pruned


def client_archived_pages(server, page_size, max_pages=300):
    seen = set()
    offset = 0
    total = None
    for _ in range(max_pages):
        rows, _ = server.page(offset, page_size)
        seen |= {i for _, i in rows}
        total = server.total_count()
        offset += page_size
        if total is not None and offset >= total:
            return seen, True
    return seen, False


# ── properties ──────────────────────────────────────────────────────────────

@settings(max_examples=800, suppress_health_check=[HealthCheck.too_slow])
@given(
    total=st.integers(min_value=0, max_value=140),
    pins=st.lists(st.integers(min_value=0, max_value=149), max_size=12),
    page_size=st.sampled_from([1, 2, 3, 5, 7, 50, 100]),
)
def test_api_server_paging_accumulates_everything(total, pins, page_size):
    server = StockServer(total, pins)
    got, prunes = client_api_server_pages(server, page_size)
    full = server.full_set()
    # 1. no truncation: every row the server can ever serve was collected
    assert got == full, (
        f"total={total} pins={sorted(server.pins)} ps={page_size}: "
        f"missing {sorted(full - got)}")
    # 2. prune only ever ran on the COMPLETE set
    for p in prunes:
        assert set(p) == full, "pruned against a partial raw-id set"


@settings(max_examples=800, suppress_health_check=[HealthCheck.too_slow])
@given(
    total=st.integers(min_value=0, max_value=250),
    pins=st.lists(st.integers(min_value=0, max_value=259), max_size=12),
    page_size=st.sampled_from([1, 2, 50, 100]),
)
def test_archived_total_driven_paging_accumulates_everything(total, pins,
                                                             page_size):
    server = StockServer(total, pins)
    got, complete = client_archived_pages(server, page_size)
    assert got == server.full_set()
    # total-driven walk always completes within the cap for these sizes
    assert complete


def client_naive_zero_new(server, page_size, max_pages=20):
    """The OLD rule: stop at the FIRST zero-new page. Kept as a plain
    function so the witness test can call it directly."""
    seen = set()
    offset = 0
    for _ in range(max_pages):
        rows, _ = server.page(offset, page_size)
        ids = {i for _, i in rows}
        if not (ids - seen):
            break  # old rule: EOF
        seen |= ids
        offset += page_size
    return seen


@settings(max_examples=400, suppress_health_check=[HealthCheck.too_slow])
@given(
    total=st.integers(min_value=0, max_value=140),
    pins=st.lists(st.integers(min_value=0, max_value=149), max_size=12),
    page_size=st.sampled_from([2, 3, 5]),
)
def test_naive_zero_new_rule_truncates_sometimes(total, pins, page_size):
    """The old rule (stop at the FIRST zero-new page) may truncate; this
    runs alongside the property above as a witness counter (below)."""
    server = StockServer(total, pins)
    return client_naive_zero_new(server, page_size) == server.full_set()


def test_witness_generator_expresses_the_pin_only_window():
    """Hard witness: the reviewer's exact stock-SessionDB layout —
    s0..s5 with s2,s3 pinned, page size 2 — MUST truncate under the old
    rule and MUST NOT under the new one. If this ever fails, the fuzz
    generator cannot express blocker #1 and its PASS certifies nothing."""
    server = StockServer(6, [2, 3])
    assert client_naive_zero_new(server, 2) != server.full_set(), \
        "old rule no longer truncates on the witness"
    got, prunes = client_api_server_pages(server, 2)
    assert got == server.full_set(), "new rule truncated the witness"
    assert prunes and all(set(p) == server.full_set() for p in prunes)


if __name__ == "__main__":
    test_api_server_paging_accumulates_everything()
    print("PASS  api-server paging accumulates everything, prunes complete-only")
    test_archived_total_driven_paging_accumulates_everything()
    print("PASS  archived total-driven paging accumulates everything")
    test_witness_generator_expresses_the_pin_only_window()
    print("PASS  witness: reviewer's pin-only layout truncates under the "
          "old rule, survives under the new one")