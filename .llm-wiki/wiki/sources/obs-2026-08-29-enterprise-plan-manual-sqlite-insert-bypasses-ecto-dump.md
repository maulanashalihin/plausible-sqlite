---
type: source
title: "Observation: Manual sqlite3 INSERT into enterprise_plans bypasses Ecto dump — causes Limit and FeatureArray load crashes"
slug: obs-2026-08-29-enterprise-plan-manual-sqlite-insert-bypasses-ecto-dump
status: observation
created: 2026-08-29
updated: 2026-08-29
relevance: high
observed_at: 2026-08-29T09:00:00.000Z
tags: ["plausible", "sqlite", "ecto", "enterprise-plan", "billing", "custom-type", "limit", "feature-array"]
---

# 📝 Observation: Manual sqlite3 INSERT into enterprise_plans bypasses Ecto dump — causes Limit and FeatureArray load crashes

*Observed: 2026-08-29T09:00:00.000Z*
*Relevance: high — blocks GET /sites for all users*

## Context
Upgrading team via raw `sqlite3` to avoid trial: `UPDATE teams` + `INSERT INTO enterprise_plans` + `INSERT INTO subscriptions` directly. This bypasses `Ecto.Type.dump/1`, so DB values differ from what `load/1` expects. Resulted in two sequential `ArgumentError at GET /sites`.

## Root Cause

### 1. `Plausible.Billing.Ecto.Limit` — `team_member_limit`
- Code: `dump(:unlimited) -> {:ok, -1}`, `load(-1) -> {:ok, :unlimited}`, `load("-1") -> {:ok, :unlimited}` (handles SQLite string "-1").
- Raw insert used `team_member_limit='unlimited'` (string). `load("unlimited")` falls through to `Ecto.Type.load(:integer, String.to_integer("unlimited"))` -> `** (ArgumentError) not a textual representation of an integer`.
- Fix: insert `-1` (integer), not `"unlimited"`.

### 2. `Plausible.Ecto.Types.FeatureArray` — `features`
- Code: `dump([:goals, :props]) -> Jason.encode(["goals","props"])` (lowercase, via `Feature.dump` -> `Atom.to_string(mod.name())` where `name` is `:goals`, `:props`, etc.).
- `load` does `Jason.decode` then `Feature.load(str)` which expects lowercase (`"prop"` -> `Props`, `"goals"` -> `Goals`). Capitalized `"Goals"` -> `cast` returns `:error`, then `elem(:error,1)` -> `** (ArgumentError) 2nd argument: not a tuple`.
- Raw insert used `'["Goals","Props","Funnels","RevenueGoals"...]'` capitalized -> crash.
- Fix: insert lowercase JSON `'["goals","props","funnels","revenue_goals","stats_api","sites_api","shared_links","site_segments","consolidated_view"]'`.

### 3. Bonus: `users.email_verified`
- New users inserted via sqlite need `email_verified=1`, else `GET /sites` redirects to `/activate` (not a crash but looks broken).

## Correct Approach

**Prefer Ecto (safe):**
```elixir
Repo.insert!(%EnterprisePlan{
  team_id: 1,
  paddle_plan_id: "enterprise_100M",
  billing_interval: :yearly,
  monthly_pageview_limit: 100_000_000,
  site_limit: 1000,
  team_member_limit: :unlimited,
  hourly_api_request_limit: 600_000,
  features: [:goals, :props, :funnels, :revenue_goals, :stats_api, :sites_api, :shared_links, :site_segments, :consolidated_view]
})
```

**If raw sqlite is unavoidable, use dumped values:**
```sql
UPDATE enterprise_plans SET team_member_limit=-1 WHERE team_id=1;
UPDATE enterprise_plans SET features='["goals","props","funnels","revenue_goals","stats_api","sites_api","shared_links","site_segments","consolidated_view"]';
UPDATE users SET email_verified=1 WHERE email='tester2@local.test';
-- subscriptions needs next_bill_amount TEXT NOT NULL and currency_code
```

## Lesson
Any table with custom Ecto types (`Limit`, `FeatureArray`, `StringArray` etc.) must not be written via raw `sqlite3` with Elixir-level values. Always check `lib/plausible/ecto/types/*.ex` and `lib/plausible/billing/ecto/*.ex` for `dump/load` mapping before manual INSERT.

## References
- `lib/plausible/billing/ecto/limit.ex:12-22`
- `lib/plausible/ecto/types/feature_array.ex:28`
- `lib/plausible/billing/feature.ex:146-244` (feature names: `:goals`, `:props`, etc.)
- Incident: `GET /sites` 500 -> fixed 2026-08-29 via `team_member_limit=-1` and lowercase features.
