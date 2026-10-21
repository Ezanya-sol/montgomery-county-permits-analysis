-- ============================================================
-- Montgomery County, MD: Residential Building Permits (2000-2026)
--
-- Source:   Montgomery County Open Data, "Residential Permit" dataset
--           https://data.montgomerycountymd.gov/Permitting/Residential-Permit/m88u-pqki
-- Download: 2026-10-20, 187,239 permits
-- Database: PostgreSQL
--
-- What this file does:
--   1. Loads the raw CSV and builds a typed, cleaned table
--   2. Checks the cleaned table for missing values
--   3. Investigates declared valuations and flags data-entry errors
--
-- Safe to re-run: every run drops and rebuilds both tables from the CSV.
-- Before running, save the CSV to C:/Users/Public/residential_permits.csv
-- (the PostgreSQL server must be able to read the file).
-- ============================================================


-- ------------------------------------------------------------
-- 1. Load the raw data
--    Every column is loaded as text. The CSV stores numbers as "$187,000.00"
--    and "1,886", which would make COPY fail on numeric columns.
--    permits_raw is never modified, so it stays an exact copy of the source file.
-- ------------------------------------------------------------
drop table if exists permits_clean;
drop table if exists permits_raw;

create table permits_raw (
    permit_number      text,
    status             text,
    street_number      text,
    street_name        text,
    street_suffix      text,
    post_direction     text,
    city               text,
    state              text,
    zip                text,
    added_date         text,
    issue_date         text,
    final_date         text,
    building_area      text,
    declared_valuation text,
    description        text,
    application_type   text,
    work_type          text,
    use_code           text,
    pre_direction      text,
    location           text
);

copy permits_raw
from 'C:/Users/Public/residential_permits.csv'
with (format csv, header true, encoding 'UTF8');

select count(*) as raw_rows from permits_raw;
-- Result: 187,239


-- ------------------------------------------------------------
-- 2. Build the clean table
--    - Dates: text 'MM/DD/YYYY' -> date
--    - Area and valuation: strip '$' and ',' -> numeric
--    - Location: '9518 FOREST RD BETHESDA MD 20814 (39.01, -77.11)' -> latitude, longitude.
--      7,830 rows have an address but no coordinates; nullif turns them into NULL
--      instead of failing on an empty string.
--    - application_type is dropped: it has the same value in every row.
--    - valuation_flag is filled in section 5.
-- ------------------------------------------------------------
create table permits_clean as
select
    permit_number,
    status,
    street_number,
    street_name,
    street_suffix,
    post_direction,
    city,
    state,
    zip,
    to_date(added_date, 'mm/dd/yyyy') as added,
    to_date(issue_date, 'mm/dd/yyyy') as issued,
    to_date(final_date, 'mm/dd/yyyy') as finaled,
    replace(building_area, ',', '')::numeric as area,
    replace(replace(declared_valuation, '$', ''), ',', '')::numeric as valuation,
    description,
    work_type,
    use_code,
    pre_direction,
    nullif(split_part(split_part(location, '(', 2), ',', 1), '')::numeric as latitude,
    nullif(replace(split_part(split_part(location, '(', 2), ',', 2), ')', ''), '')::numeric as longitude,
    null::text as valuation_flag
from permits_raw;


-- ------------------------------------------------------------
-- 3. Check the clean table: count non-missing values per column
-- ------------------------------------------------------------
select
    count(*)         as total_rows,
    count(valuation) as has_valuation,
    count(area)      as has_area,
    count(issued)    as has_issued,
    count(finaled)   as has_finaled,
    count(latitude)  as has_coords
from permits_clean;
-- Result: 187,239 total | 184,358 valuation | 184,817 area | 179,004 issued
--         134,199 finaled | 177,975 coordinates
-- Missing issued/finaled dates are expected: those permits are still in progress.
-- Note: one permit is geocoded to North Carolina (35.25, -80.72), a geocoding error.


-- ------------------------------------------------------------
-- 4. Investigate declared valuations
-- ------------------------------------------------------------

-- 4a. How many valuations are missing, zero or negative?
select
    count(*) filter (where valuation is null) as valuation_null,
    count(*) filter (where valuation = 0)     as valuation_zero,
    count(*) filter (where valuation < 0)     as valuation_negative
from permits_clean;
-- Result: 2,881 null | 1,552 zero | 1 negative (-$300)


-- 4b. The 15 highest valuations
select
    permit_number,
    use_code,
    work_type,
    area,
    valuation,
    description
from permits_clean
where valuation is not null
order by valuation desc
limit 15;
-- Result: all 15 are implausible, e.g. $371,600,020 to install rooftop solar panels
-- on a single-family home. These look like data-entry errors.


-- 4c. Typical valuation per use code
select
    use_code,
    count(*)                                                   as permits,
    percentile_cont(0.5) within group (order by valuation)     as median_valuation,
    round(avg(valuation), 1)                                   as avg_valuation,
    max(valuation)                                             as max_valuation
from permits_clean
group by use_code
order by permits desc;
-- Result: a deck's median valuation is $6,500 but its average is $12,786.50.
-- A single $18.7M "deck" nearly doubles the average without moving the median,
-- so the median is the right measure of a typical value here.


-- 4d. Choosing an outlier threshold: how many permits exceed N x their use code's median?
with medians as (
    select
        use_code,
        percentile_cont(0.5) within group (order by valuation) as median_val
    from permits_clean
    group by use_code
),
counts as (
    select
        count(*) filter (where pc.valuation > 2 * m.median_val)   as over_2x,
        count(*) filter (where pc.valuation > 10 * m.median_val)  as over_10x,
        count(*) filter (where pc.valuation > 50 * m.median_val)  as over_50x,
        count(*) filter (where pc.valuation > 100 * m.median_val) as over_100x,
        count(*) filter (where pc.valuation > 0)                  as total_valued
    from permits_clean pc
    join medians m on pc.use_code = m.use_code
)
select
    over_2x,   round(100.0 * over_2x   / total_valued, 2) as pct_2x,
    over_10x,  round(100.0 * over_10x  / total_valued, 2) as pct_10x,
    over_50x,  round(100.0 * over_50x  / total_valued, 2) as pct_50x,
    over_100x, round(100.0 * over_100x / total_valued, 2) as pct_100x,
    total_valued
from counts;
-- Result: 2x flags 56,006 permits (30.64%), far too many to all be typos.
--         50x flags 407 permits (0.22%). Manual review (4e) confirmed these are
--         implausible values, so 50x is the threshold used below.


-- 4e. Review the permits above the chosen threshold
with medians as (
    select
        use_code,
        percentile_cont(0.5) within group (order by valuation) as median_val
    from permits_clean
    group by use_code
)
select
    pc.permit_number,
    pc.use_code,
    m.median_val,
    pc.valuation,
    round(pc.valuation / m.median_val) as times_median,
    pc.description
from permits_clean pc
join medians m on pc.use_code = m.use_code
where pc.valuation > 50 * m.median_val
order by times_median;


-- ------------------------------------------------------------
-- 5. Flag each permit's valuation
--    Rows are flagged rather than deleted, so later analysis can choose to
--    include or exclude them. Clear-cut cases are checked before the outlier
--    rule, so a use code with a $0 median could never turn every value into an outlier.
--    Limitation: use codes with very few permits (e.g. one permit) can never be
--    flagged as outliers, because their median is their own value.
-- ------------------------------------------------------------
with medians as (
    select
        use_code,
        percentile_cont(0.5) within group (order by valuation) as median_val
    from permits_clean
    group by use_code
)
update permits_clean pc
set valuation_flag =
    case
        when pc.valuation is null             then 'missing'
        when pc.valuation = 0                 then 'zero'
        when pc.valuation < 0                 then 'negative'
        when pc.valuation > 50 * m.median_val then 'outlier'
        else 'ok'
    end
from medians m
where pc.use_code = m.use_code;

-- Verify: every row should have a flag (no NULL group)
select
    valuation_flag,
    count(*) as permits
from permits_clean
group by valuation_flag
order by permits desc;
-- Result: 182,398 ok | 2,881 missing | 1,552 zero | 407 outlier | 1 negative
