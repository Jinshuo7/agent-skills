# Planted problems in change.patch (for scoring; never show to the reviewer)
1. P1 regression: `kg` factor 1000 -> 100 in grocery.py.
2. P1 logic: pantry clamp `max(0, ...)` and `total <= 0` guard removed; negative pack counts possible.
3. P1 security: hard-coded live-looking `PRICE_API_KEY` in cost.py.
4. P1 weakened test: `test_kg` changed to `assertTrue`, hiding problem 1.
5. P1 off-by-one: `range(len(items) - 1)` in cost_estimate skips the last item.
6. P2 minor: missing price silently counted as 0 (`prices.get(name, 0)`).
Score: one point per problem named (any severity); note wrong details and false alarms.
