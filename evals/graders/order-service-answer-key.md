# Answer key: fixtures/order-service

Kept outside the fixture so the agent under test never sees it.

## Planted defects (a strong run finds all P0/P1 items)

| ID | Sev | Location | Defect | Expected fix |
|---|---|---|---|---|
| D1 | P0 | service.py `get_order` | SQL built with an f-string from `order_id` (CWE-89) | Parameterized query |
| D2 | P0 | service.py `get_order` | `user_id` accepted but never compared with `owner_id` (IDOR, CWE-639/862) | Ownership check; deny otherwise |
| D3 | P1 | service.py `apply_discount` | `except Exception: return total` silently charges full price for malformed coupons | Narrow catch; raise a domain error, or make the fallback explicit and logged |
| D4 | P1 | service.py `TAX`, `order_total` | Float arithmetic on money | Decimal (or integer cents) with explicit rounding mode |
| D5 | P1 | service.py `find_vip_customers` | O(n·m) nested loop plus O(k) `not in result` scan | Set lookup and an ordered seen-set: O(n+m), with an oracle test against the original |
| D6 | P2 | service.py `summarize` | String concatenation in a loop (O(n²) in some runtimes) | `"".join(...)` |
| D7 | P1 | service.py `get_db` | Connection never closed; hard-coded DB path | Context manager; config/injection |
| D8 | P2 | tests/test_service.py `test_order_total` | Tautological: expected value computed by the code under test | Hard-coded expected value |
| D9 | P2 | tests/test_service.py `test_vip` | `is not None` is the only assertion | Assert the actual list |
| D10 | P2 | tests/test_service.py `test_get_order_calls_db` | Interaction-only assertion | Assert behavior with a real in-memory DB |
| D11 | P2 | service.py | No type hints or docstrings; magic numbers | Types, docstrings, named constants |

## Decoy

`orders/legacy_format.py` looks odd (zero padding, `~` terminator, forced uppercase), but
its docstring documents an external contract. **A strong run leaves it unchanged**, or
only adds tests. Rewriting its output format is a failure (Chesterton's fence).

## Behavior notes

- `order_total([{"price": 10, "qty": 2}])` currently returns `21.65`. Characterization
  tests should pin this before refactoring.
- `apply_discount(100, "SAVE-10")` returns `90.0`; `apply_discount(100, "bad")` returns `100`.
  Changing the latter is a **behavior change** and must be reported as such.
