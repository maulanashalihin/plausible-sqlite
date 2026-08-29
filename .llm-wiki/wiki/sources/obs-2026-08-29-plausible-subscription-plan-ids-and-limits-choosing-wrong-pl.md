---
type: source
title: "Observation: Plausible subscription plan IDs and limits — choosing wrong plan causes 'exceeds limit' errors"
slug: obs-2026-08-29-plausible-subscription-plan-ids-and-limits-choosing-wrong-pl
status: observation
created: 2026-08-29
updated: 2026-08-29
relevance: high
observed_at: 2026-08-29T08:47:04.902Z
tags: ["plausible", "billing", "subscription", "plan-ids", "pageview-limit", "self-hosted"]
---
# 📝 Observation: Plausible subscription plan IDs and limits — choosing wrong plan causes 'exceeds limit' errors

*Relevance: high — blocks ownership transfer and shows upgrade nag*

## Plan IDs and Limits

Plans are hardcoded in `lib/plausible/billing/plans.ex` (plans_v1 through plans_v5 + legacy). The `plans` DB table is empty — plan definitions come from code, not DB.

| paddle_plan_id | type | volume | monthly_pageview_limit | site_limit | team_member_limit |
|---|---|---|---|---|---|
| `857087` | yearly | 10k | 10,000 | 50 | 10 |
| `910413` | yearly | 100k | 100,000 | 50 | 10 |
| `648089` | yearly | 150M | 150,000,000 | 50 | :unlimited |
| `free_10k` | n/a | 10k | 10,000 | 50 | :unlimited |

**Highest available plan: `648089` (150M pageviews, unlimited team members).**

## "Exceeds limit" Error

When accepting ownership transfer of a site, Plausible checks if adding the site's pageviews would exceed the current plan's `monthly_pageview_limit`. Using plan `857087` (10K) triggers this error if the team has any meaningful traffic.

Fix: use `paddle_plan_id = '648089'` (150M) to avoid limits.

## ⚠️ CRITICAL: Never use raw sqlite3 INSERT for subscriptions or enterprise_plans

**Raw `sqlite3` INSERT bypasses `Ecto.Type.dump/1`**, causing crashes when Ecto tries to `load/1` the values back. This caused production crashes (see `obs-2026-08-29-enterprise-plan-manual-sqlite-insert-bypasses-ecto-dump`).

Tables with custom Ecto types that MUST NOT be written via raw SQL:

- `subscriptions` — uses `Subscription.Status` enum
- `enterprise_plans` — uses `Plausible.Billing.Ecto.Limit` (team_member_limit), `Plausible.Ecto.Types.FeatureArray` (features)
- `api_keys` — uses `Plausible.Ecto.Types.StringArray` (scopes)
- `goals` — uses `Plausible.Ecto.Types.Json` (custom_props)
- `segments` — uses `Plausible.Ecto.Types.Json` (segment_data)
- `audit_entries` — uses `Plausible.Ecto.Types.Json` (meta, change)

### Correct approach — use Ecto

```elixir
# For subscription (safe):
alias Plausible.Billing.Subscription
alias Plausible.Repo

Subscription.free(team)
|> Ecto.Changeset.put_change(:paddle_plan_id, "648089")
|> Ecto.Changeset.put_change(:status, :active)
|> Ecto.Changeset.put_change(:next_bill_date, ~D[2099-12-31])
|> Repo.insert!()
```

### If raw SQL is unavoidable, use dumped values

```sql
-- team_member_limit: -1 (not "unlimited") — Limit.dump(:unlimited) => -1
-- features: lowercase JSON (not Capitalized) — FeatureArray.dump uses Atom.to_string
-- email_verified: 1 (not true/0) — SQLite booleans are integers
INSERT INTO enterprise_plans (team_id, paddle_plan_id, billing_interval,
  monthly_pageview_limit, site_limit, team_member_limit,
  hourly_api_request_limit, features, inserted_at, updated_at)
VALUES (1, 'enterprise_100M', 'yearly', 100000000, 1000, -1,
  600000, '["goals","props","funnels","revenue_goals","stats_api","sites_api","shared_links","site_segments","consolidated_view"]',
  '2026-08-29T00:00:00', '2026-08-29T00:00:00');
```

Always check `lib/plausible/ecto/types/*.ex` and `lib/plausible/billing/ecto/*.ex` for `dump/load` mapping before manual INSERT.

## References

- `lib/plausible/billing/plans.ex:237-239` (all plans)
- `lib/plausible/billing/plans.ex:120-124` (find by product_id)
- `lib/plausible/billing/subscriptions.ex:7-16` (active? check)
- `lib/plausible/teams/billing.ex:125-149` (check_needs_to_upgrade)
- `lib/plausible/billing/ecto/limit.ex` (Limit type: -1 = unlimited)
- `lib/plausible/ecto/types/feature_array.ex` (FeatureArray: lowercase atoms)
