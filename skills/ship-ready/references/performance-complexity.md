# Time & Space Complexity Optimization

## Contents
1. Workflow and keep/revert rule
2. Big-O reference
3. Data-structure choice
4. Slow patterns in AI-generated code → fixes
5. Space optimization
6. I/O and system level
7. Measuring correctly
8. When not to optimize

---

## 1. Workflow: MEASURE → IDENTIFY → FIX → VERIFY → GUARD

1. **Measure.** Profile under realistic load or benchmark at 3+ input sizes. For a whole
   service, start with the USE method (Utilization, Saturation, Errors per resource) before guessing.
2. **Identify.** Read the profile or flame graph; name the hot function and its current
   cost: `O(n·m) time, O(n) space, 1 + n DB queries`.
3. **Fix.** Algorithm and data structure first, then I/O, then memory layout, then
   micro-optimizations (rarely).
4. **Verify.** Same harness, same machine, same inputs. Oracle test proves identical output.
5. **Guard.** Add a regression benchmark or complexity test to CI for the hot path.

**Keep/revert rule**

| Result | Decision |
|---|---|
| Faster beyond noise; all tests green | Keep. Record Big-O and numbers in the docstring and report |
| Within noise | **Revert**: neutral is a revert |
| Faster but any test red | **Revert** |
| Small gain off the hot path that hurts readability | Revert, or keep with an ADR |

Keep a ledger of reverted attempts.

Knuth in full: "We should forget about small efficiencies, say about 97% of the time:
premature optimization is the root of all evil. Yet we should not pass up our
opportunities in that critical 3%." Profiling finds the 3%.

## 2. Big-O reference (n = 1,000,000)

| Complexity | ~operations | Verdict |
|---|---|---|
| O(1), O(log n) | 1–20 | Ideal |
| O(n) | 10⁶ | Good |
| O(n log n) | 2·10⁷ | Good (comparison-sort bound) |
| O(n²) | 10¹² | Too slow beyond ~10⁴ |
| O(2ⁿ), O(n!) | — | Only for tiny n |

Always state **time, space, and I/O round-trips**. An O(n) loop that makes n network
calls is slower than an O(n log n) in-memory sort.

## 3. Data-structure choice

| Need | Use | Cost | Note |
|---|---|---|---|
| Membership test | Hash set | O(1) | Replaces `x in list` (O(n)) |
| Key → value | Hash map | O(1) | |
| Ordered keys, range queries | Balanced tree / sorted array + binary search | O(log n) | |
| Repeated min/max, top-k | Heap | O(log n) push/pop | Top-k in O(n log k) |
| Queue | Deque / ring buffer | O(1) at ends | `list.pop(0)` is O(n) |
| Prefix lookup | Trie | O(key length) | |
| Range sums | Prefix sums / Fenwick tree | O(1) / O(log n) | |
| Connectivity | Union-find | ~O(1) amortized | |
| Recent-items cache | LRU (hash map + linked list) | O(1) | Bounded size |

## 4. Slow patterns in AI-generated code → fixes

| Pattern | Cost | Fix | Becomes |
|---|---|---|---|
| Nested loops matching two collections | O(n·m) | Index one side in a hash map | O(n+m) |
| `if x in list` inside a loop | O(n²) | Build a set once | O(n) |
| String concatenation in a loop | O(n²) | Join / builder | O(n) |
| Sorting inside a loop | O(n² log n) | Sort once, or a heap | O(n log n) |
| Recomputing overlapping subproblems | Exponential | Memoize / dynamic programming | Polynomial |
| Query per item (N+1) | n round-trips | Batch, `JOIN`, `IN (...)`, eager loading | 1–2 round-trips |
| Load whole file/table into memory | O(n) space | Stream, iterate, paginate, cursor | O(1) space |
| Array slicing in recursion | O(n²) space/time | Pass indices | O(n) |
| `list.count` / `indexOf` in a loop | O(n²) | Counter / hash map | O(n) |
| Duplicate detection by pairwise compare | O(n²) | Seen-set | O(n) |
| Linear search over sorted data | O(n) | Binary search | O(log n) |
| Sliding window recomputed each step | O(n·k) | Running window | O(n) |
| Regex compiled per call / catastrophic backtracking | O(n) per call / exponential | Compile once; linear-time engine (RE2) or anchored patterns | Linear |
| Unbounded `cache = {}` | Memory leak | `lru_cache(maxsize)` / TTL | Bounded |

### Worked example

```python
# BEFORE: O(n·m) time and an O(k) scan per hit. Typical LLM output.
def find_common_customers(orders, vip_ids):
    result = []
    for order in orders:
        for vip in vip_ids:
            if order["customer_id"] == vip and order["customer_id"] not in result:
                result.append(order["customer_id"])
    return result

# AFTER: O(n + m) time, O(m) space, first-seen order preserved.
def find_common_customers(orders: Iterable[Order], vip_ids: Iterable[str]) -> list[str]:
    """Return IDs of VIP customers who placed at least one order, in first-seen order.

    Complexity: O(n + m) time, O(m) space; n = orders, m = vip_ids.
    """
    vip_set = set(vip_ids)
    seen: dict[str, None] = {}               # dicts preserve insertion order
    for order in orders:
        if order.customer_id in vip_set:
            seen.setdefault(order.customer_id)
    return list(seen)

# GUARD: oracle property test
@given(st.lists(order_strategy()), st.lists(st.text()))
def test_matches_original(orders, vips):
    assert find_common_customers(orders, vips) == find_common_customers_original(orders, vips)
```

## 5. Space optimization

- Generators, iterators and streams instead of materialized lists.
- In-place algorithms when callers don't need the original.
- Rolling arrays in dynamic programming: O(n·m) → O(m).
- Compact representations: arrays/NumPy for numeric data, `__slots__`, struct packing, right-sized ints.
- Bounded caches with eviction; measure hit rate.
- Chunked batch processing and paginated APIs.
- Bound every input-driven allocation (upload size, page size, recursion depth): unbounded allocation is also CWE-770.

## 6. I/O and system level (often bigger than Big-O)

- Batch network and DB calls; connection pooling; timeouts on everything.
- Check query plans (`EXPLAIN`); add the missing index; select only needed columns.
- Cache with explicit invalidation and TTL.
- Run independent I/O concurrently (`asyncio.gather`, `Promise.all`, goroutines) **with a concurrency limit**.
- Compress large payloads; avoid chatty APIs.

## 7. Measuring correctly

| Language | CPU profiler | Memory | Benchmark harness |
|---|---|---|---|
| Python | py-spy, scalene, cProfile | memray, tracemalloc | pytest-benchmark, pyperf |
| JS/TS | `--cpu-prof`, Chrome DevTools, clinic.js | heap snapshots | tinybench, vitest bench |
| Java/Kotlin | async-profiler, JFR | JFR | JMH |
| Go | pprof | pprof heap | `go test -bench` + benchstat |
| Rust | perf + flamegraph | dhat | criterion |
| C# | dotnet-trace | dotnet-counters | BenchmarkDotNet |

Benchmark hygiene:
- Use a harness (it handles warm-up, JIT and dead-code elimination).
- Several runs; report **median and spread** (IQR or p95), never a single number.
- Compare with a statistical tool where available (benchstat, criterion, pyperf compare).
- Test at 3+ sizes and check that the growth curve matches the claimed Big-O.
- For latency load tests, beware coordinated omission: use tools that correct for it (wrk2, k6 with arrival-rate executors).

## 8. When not to optimize

- n is small and bounded (< ~1,000) and not inside a loop.
- No profile or SLO puts it on the hot path.
- The gain is within noise, or the code becomes much harder to read for < 20% gain.

Record the decision in an ADR if a reviewer is likely to ask.
