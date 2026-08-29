---
type: source
title: "Observation: Plausible dual-database architecture"
slug: obs-2026-08-29-plausible-dual-database-architecture
status: observation
created: 2026-08-29
updated: 2026-08-29
relevance: undefined
observed_at: 2026-08-29T05:37:16.849Z
---
# 📝 Observation: Plausible dual-database architecture
Observation: Plausible dual-database architecture — PostgreSQL for app data, ClickHouse for analytics

#⭐ Plausible architecture: dual-database design

Plausible Analytics uses TWO databases with fundamentally different roles:

1. **PostgreSQL** (Ecto, `Plausible.Repo`) — OLTP. Stores app data: users, sites, teams, billing, API keys, settings, segments, annotations. 234 migrations. Standard CRUD patterns.

2. **ClickHouse** (`Plausible.ClickhouseRepo`, `Plausible.IngestRepo`) — OLAP column-store. Stores event analytics: pageviews, sessions, all stats queries. ~9,500 lines across 49 files in `lib/plausible/stats/`. Heavy use of ClickHouse-specific SQL: `countIf`, `uniq`, `toDate`, `toTimeZone`, `timeSlots`, `argMax`, `leadInFrame`, `multiMatchAny`, `arrayJoin`, array columns (`meta.key`/`meta.value`), materialized views, sampling (`_sample_factor`).

## Why two databases
- Web analytics generates thousands of events/second for busy sites
- Dashboard queries scan millions of events (unique visitors this month, top 10 pages)
- PostgreSQL/SQLite (row-store OLTP) would be too slow for these aggregations at scale
- ClickHouse (column-store OLAP) scans only relevant columns, compresses 10-100x, runs aggregations in milliseconds

## Implication for SQLite conversion
Converting PostgreSQL → SQLite is straightforward (both are OLTP). Converting ClickHouse → SQLite would require rewriting the entire stats engine — ClickHouse functions have no SQLite equivalents, and performance for large datasets would be unacceptable. The correct scope is: PostgreSQL → SQLite, keep ClickHouse.
*Relevance: undefined*
---
*Observed: 2026-08-29T05:37:16.849Z*