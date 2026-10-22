-- ============================================================
-- Dashboard view: one prepared table for the Power BI dashboard
-- Requires: permits_clean with valuation_flag (run 01_load_and_clean.sql first)
--
-- The heavy logic stays in SQL so Power BI only has to aggregate:
--   - valuation is kept only where valuation_flag = 'ok', so bad values never reach a total
--   - approval_days, is_new_home and is_teardown are precomputed
--   - description is left out: Power BI doesn't need the long text
-- ============================================================

-- drop first: "create or replace view" cannot change an existing column's data type
drop view if exists permits_dashboard;

create view permits_dashboard as
select
    permit_number,
    status,
    coalesce(city, 'UNKNOWN')                       as city,
    use_code,
    work_type,
    added,
    issued,
    extract(year from added)::int                   as year_added,
    latitude,
    longitude,
    case when valuation_flag = 'ok' then valuation end as valuation,
    issued - added                                  as approval_days,
    use_code = 'SINGLE FAMILY DWELLING'
        and work_type = 'CONSTRUCT'                 as is_new_home,
    use_code = 'SINGLE FAMILY DWELLING'
        and work_type = 'CONSTRUCT'
        and description ~* '(demo|tear|raze|rebuild)' as is_teardown
from permits_clean;


-- Check the view
select
    count(*)                            as total_rows,
    count(valuation)                    as ok_valuations,
    count(*) filter (where is_new_home) as new_homes,
    count(*) filter (where is_teardown) as teardowns
from permits_dashboard;
-- Result: 187,239 rows | 182,398 ok valuations | 21,503 new homes | 3,229 teardowns
