---
title: Free API Allowance Tracker
tags: [operations, api, costs]
---

# Free API Allowance Tracker

Record public allowance details and observed usage. Do not store keys, tokens, or secret account data.

| Provider / service | Free allowance | Reset window | Limits / caveats | Key configured? | Last verified | Source |
|---|---|---|---|---|---|---|
| Add providers after inventory | Unknown | Unknown | Verify official source and account-specific usage before relying on it | Unknown | Not checked | |

## Review procedure
1. Confirm current free allowance from the provider's official pricing or usage page.
2. Record request/token quotas, rate limits, reset schedule, model restrictions, and expiry conditions separately.
3. Check actual account usage before designing around a quota.
4. Prefer local inference for suitable workloads; route remote calls only when needed.
5. Recheck on provider/policy changes; mark unknown rather than guessing.
