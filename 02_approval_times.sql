-- ============================================================
-- Approval times: how long does it take to get a residential permit?
-- Requires: permits_clean (run 01_load_and_clean.sql first)
--
-- "Approval time" = days from application (added) to permit issue (issued).
-- Permits that have not been issued yet have no approval time and are left out
-- of the medians and percentiles.
-- ============================================================


-- ------------------------------------------------------------
-- 1. County-wide approval time
--    Approval times are heavily skewed (most permits take days, a few take years),
--    so the median is reported alongside the average.
-- ------------------------------------------------------------
select
    count(*)                                                                    as issued_permits,
    round(avg(issued - added), 1)                                               as avg_days,
    round(percentile_cont(0.5) within group (order by issued - added)::numeric) as median_days,
    round(percentile_cont(0.9) within group (order by issued - added)::numeric) as p90_days
from permits_clean
where issued is not null;
-- Result: 179,004 issued permits | average 32.6 days | median 9 days | 90th percentile 80 days
-- The average is more than 3x the median: a minority of very slow permits pulls it up.


-- ------------------------------------------------------------
-- 2. Approval time by project type
--    Only use codes with at least 100 issued permits, so small groups don't distort the ranking.
-- ------------------------------------------------------------
select
    use_code,
    count(*)                                                                    as issued_permits,
    round(percentile_cont(0.5) within group (order by issued - added)::numeric) as median_days,
    round(percentile_cont(0.9) within group (order by issued - added)::numeric) as p90_days
from permits_clean
where issued is not null
group by use_code
having count(*) >= 100
order by median_days desc, p90_days desc;
-- Result (median / 90th percentile days):
--   Slowest: MODULAR 77 / 211, DUPLEX 59 / 513, TOWNHOUSE 50 / 260
--   SINGLE FAMILY DWELLING 13 / 83 (115,427 permits)
--   Fastest: SHED, HOT TUB, DECK, HOT TUB & DECK and RETAINING WALL all have a median of 0 days
--
-- A median of 0 days means at least half of these permits are issued the same day they are
-- applied for. This suggests simple projects go through an express or over-the-counter review.
--
-- The median shows the typical wait; the 90th percentile shows the long tail. A large gap
-- (e.g. DUPLEX: 59 vs 513 days) means most permits are reasonably quick, but a minority
-- wait far longer.


-- ------------------------------------------------------------
-- 3. Approval time for single-family homes by year of application
--    applications = all permits applied for that year (a measure of reviewer workload)
--    not_issued   = permits applied for that year that have not been issued yet
-- ------------------------------------------------------------
select
    extract(year from added)                                                    as year_added,
    count(*)                                                                    as applications,
    round(percentile_cont(0.5) within group (order by issued - added)::numeric) as median_days,
    count(*) filter (where issued is null)                                      as not_issued
from permits_clean
where use_code = 'SINGLE FAMILY DWELLING'
group by year_added
order by year_added;
-- Result:
--   2000-2007: median 9-14 days, about 4,000-6,000 applications a year
--   2008-2010: median drops to 2-4 days while applications fall to about 2,800-3,300
--              and unissued permits rise from about 20 a year to 100-150
--   2015:      one-year spike to 21 days
--   2020:      jump to 21 days, peaking at 28 days in 2021; still 22-27 days through 2025
--
-- Findings:
-- - The 2008-2010 speed-up coincides with the housing market crash. With half as many
--   applications, reviewers had less work, which may explain the faster approvals.
--   The rise in unissued permits suggests some projects were abandoned when financing dried up.
-- - Workload does not explain every change: 2020 had fewer applications than 2019 (3,932 vs
--   4,170) but approvals roughly doubled (11 to 21 days). The jump coincides with the
--   COVID-19 pandemic, but this data cannot show the cause.
-- - 2020 has only 6 unissued permits, far fewer than the years around it. This is worth
--   checking; it may reflect a records cleanup.
--
-- Caveat (right-censoring): recent years look faster than they will turn out to be.
-- Slow permits from 2025-2026 are still waiting (792 from 2026 are not yet issued), so only
-- the fast ones are counted. The 2025 and 2026 medians are incomplete.
