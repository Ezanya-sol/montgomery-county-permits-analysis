-- ============================================================
-- Where is building happening, and how is the county growing?
-- Requires: permits_clean with valuation_flag (run 01_load_and_clean.sql first)
-- ============================================================


-- ------------------------------------------------------------
-- 1. Construction value by city
--    Only valuations flagged 'ok', so missing, zero, negative and outlier values
--    (see 01_load_and_clean.sql) don't distort the totals.
--    About 1,400 permits have no city; they are grouped as UNKNOWN.
-- ------------------------------------------------------------
select
    coalesce(city, 'UNKNOWN')                                                     as city,
    count(*)                                                                      as permits,
    round(sum(valuation), 1)                                                      as total_valuation,
    round(percentile_cont(0.5) within group (order by valuation)::numeric, 1)     as median_valuation,
    round(100.0 * sum(valuation) / sum(sum(valuation)) over (), 1)                as pct_of_county_valuation
from permits_clean
where valuation_flag = 'ok'
group by city
order by total_valuation desc;
-- Result (top 5):
--   BETHESDA       23,602 permits | $3.20B | median $40,334 | 23.0% of county value
--   SILVER SPRING  40,490 permits | $1.86B | median $16,462 | 13.4%
--   CLARKSBURG     12,232 permits | $1.27B | median $95,000 |  9.1%
--   POTOMAC        12,734 permits | $1.24B | median $30,000 |  9.0%
--   CHEVY CHASE     8,613 permits | $1.06B | median $41,000 |  7.6%
-- Bethesda has almost a quarter of the county's residential construction value.
-- Silver Spring has the most permits but a low median: many small projects.
-- Clarksburg's high median ($95,000) reflects mostly new homes rather than repairs.


-- ------------------------------------------------------------
-- 2. Top 3 cities for new single-family homes in each 5-year period
--    Periods are based on the application date (added), which every permit has.
--    The 2025 period only contains 2025 and part of 2026, so its counts are not
--    comparable with full periods.
-- ------------------------------------------------------------
with city_counts as (
    select
        (extract(year from added)::int / 5) * 5 as period_start,
        city,
        count(*)                                as new_homes
    from permits_clean
    where use_code = 'SINGLE FAMILY DWELLING'
      and work_type = 'CONSTRUCT'
      and city is not null
    group by period_start, city
),
ranked as (
    select
        *,
        rank() over (partition by period_start order by new_homes desc) as city_rank
    from city_counts
)
select
    period_start,
    city_rank,
    city,
    new_homes
from ranked
where city_rank <= 3
order by period_start, city_rank;
-- Result (leader per period):
--   2000-04  BOYDS        1,407
--   2005-09  CLARKSBURG     813   (Bethesda 2nd, 723)
--   2010-14  CLARKSBURG     791   (Bethesda 2nd, 677)
--   2015-19  CLARKSBURG     791   (Bethesda 2nd, 789: effectively a tie)
--   2020-24  BETHESDA       837   (Boyds 2nd, 313)
--   2025-    BETHESDA       269   (partial period)
-- The lead moved from the outer suburbs (Boyds, then Clarksburg) to Bethesda.
-- Bethesda's count has stayed fairly flat (about 680-840 per period); it took the lead
-- mainly because new-home construction in the outer suburbs slowed down.


-- ------------------------------------------------------------
-- 3. Why does Bethesda, a fully built-up area, have so many "new" homes?
--    Exploratory check: read a sample of recent descriptions.
-- ------------------------------------------------------------
select description
from permits_clean
where city = 'BETHESDA'
  and use_code = 'SINGLE FAMILY DWELLING'
  and work_type = 'CONSTRUCT'
  and added >= '2020-01-01'
limit 20;
-- Result: most descriptions mention demolishing an existing house and building a new one.
-- Bethesda's new homes appear to be mostly teardowns (replacements), not added housing.


-- ------------------------------------------------------------
-- 4. Share of new single-family homes that are teardowns, by city (since 2015)
--    A permit counts as a teardown if its description mentions demo, tear, raze or rebuild.
--    Only cities with at least 100 new-home permits.
--
--    Limitation: descriptions are free text and not standardized. Teardowns whose description
--    doesn't use these words (e.g. just "NEW SFH") are missed, so these shares are a lower bound.
-- ------------------------------------------------------------
with city_counts as (
    select
        city,
        count(*)                                                       as new_home_permits,
        count(*) filter (where description ~* '(demo|tear|raze|rebuild)') as teardown_permits
    from permits_clean
    where use_code = 'SINGLE FAMILY DWELLING'
      and work_type = 'CONSTRUCT'
      and added >= '2015-01-01'
    group by city
)
select
    coalesce(city, 'UNKNOWN')                                      as city,
    new_home_permits,
    teardown_permits,
    round(100.0 * teardown_permits / new_home_permits, 1)          as teardown_pct
from city_counts
where new_home_permits >= 100
order by teardown_pct desc;
-- Result:
--   Highest: BETHESDA 49.9% (946 of 1,895), CHEVY CHASE 46.7%, KENSINGTON 42.7%,
--            POTOMAC 25.5%, ROCKVILLE 23.4%
--   Lowest:  CLARKSBURG 0.2% (2 of 873), BOYDS 0.4%, BURTONSVILLE 0.4%,
--            GERMANTOWN 1.2%, POOLESVILLE 1.3%
--
-- Finding: the county is growing in two different ways.
-- - Inner suburbs (Bethesda, Chevy Chase, Kensington): about half of new homes replace
--   a demolished house, so they add little or no housing.
-- - Outer suburbs (Clarksburg, Boyds, Germantown): almost all new homes are new
--   developments on open land.
