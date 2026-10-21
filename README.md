# Montgomery County, MD: Residential Building Permits Analysis

An end-to-end SQL analysis of **187,239 residential building permits** issued in Montgomery County, Maryland from 2000 to 2026. It covers loading and cleaning messy public data, then answering three questions: how good is the data, how long do approvals take, and where and how is the county building?

**Tools:** PostgreSQL (CTEs, window functions, percentiles, regex, `UPDATE ... FROM`)

---

## Key findings

1. **The county is growing in two different ways.** Since 2015, **about half of new single-family homes in Bethesda (49.9%), Chevy Chase (46.7%) and Kensington (42.7%) replaced a demolished house**. In the outer suburbs (Clarksburg, Boyds, Burtonsville), fewer than 1% did. Inner suburbs are rebuilding existing lots, while outer suburbs are adding new housing on open land.

2. **Bethesda leads new-home construction, but not because it's growing.** The top city for new homes moved from Boyds (2000–04) to Clarksburg (2005–19) to Bethesda (2020 onward). Bethesda's count stayed fairly flat at about 680–840 per 5-year period; it took the lead because construction in the outer suburbs slowed.

3. **Single-family approvals roughly doubled in 2020 and haven't recovered.** The median time from application to permit rose from 11 days (2019) to 21 days (2020), peaked at 28 days (2021), and stayed at 22–27 days through 2025. The jump coincides with the COVID-19 pandemic and isn't explained by workload: 2020 had *fewer* applications than 2019.

4. **Simple projects are approved the same day; multi-unit projects wait much longer.** Decks, sheds and hot tubs have a median approval time of **0 days**. Townhouses take a median of 50 days and modular homes 77 days. Duplexes have a median of 59 days, but the slowest 10% wait more than 500.

5. **Bethesda holds almost a quarter (23.0%) of the county's residential construction value**: $3.2B across 23,602 permits, nearly twice as much as Silver Spring, which has more permits.

---

## Data

| | |
|---|---|
| **Source** | [Montgomery County Open Data – Residential Permit](https://data.montgomerycountymd.gov/Permitting/Residential-Permit/m88u-pqki) |
| **Downloaded** | October 20, 2026 |
| **Rows** | 187,239 permits (January 2000 – October 2026) |
| **Fields** | Permit number, status, address, application/issue/final dates, building area, declared valuation, free-text description, work type, use code, location |

---

## Data cleaning

The raw CSV couldn't be loaded straight into typed columns, and several fields had quality problems. Every issue below was found and handled in SQL ([`01_load_and_clean.sql`](01_load_and_clean.sql)).

| Issue | Example | How it was handled |
|---|---|---|
| Numbers stored as formatted text | `"$187,000.00"`, `"1,886"` | Loaded all columns as text into `permits_raw`, then stripped `$` and `,` and cast to `numeric` |
| Dates stored as text | `"09/30/2022"` | Converted with `to_date(..., 'mm/dd/yyyy')` |
| Coordinates embedded in an address string | `"9518 FOREST RD BETHESDA MD 20814 (39.01, -77.11)"` | Extracted latitude and longitude with `split_part`; the 7,830 addresses without coordinates became NULL via `nullif` |
| Missing, zero and negative valuations | 2,881 missing, 1,552 at $0, one at **-$300** | Flagged, not deleted |
| Implausible valuations | **$371.6M** for rooftop solar panels; an **$18.7M** deck | Flagged as outliers (see below) |
| Column with a single value | `application_type` is the same in every row | Dropped |
| Geocoding error | One permit located in North Carolina | Noted (does not affect the analysis) |

### Choosing an outlier rule
Valuations vary hugely by project type ($2,500 for a typical shed vs. hundreds of thousands for a new house), so each permit was compared with the **median valuation of its own use code**. The median was used instead of the average because outliers distort the average: one $18.7M "deck" nearly doubles the average deck valuation ($12,787 vs. a $6,500 median).

Several thresholds were tested:

| Threshold | Permits flagged | Share |
|---|---|---|
| 2× use-code median | 56,006 | 30.64% |
| 10× | 8,405 | 4.60% |
| **50×** | **407** | **0.22%** |
| 100× | 200 | 0.11% |

A 2× threshold flagged nearly a third of all permits, far too many to be data-entry errors. At **50×**, a manual review confirmed the flagged values were implausible. Every permit was then labeled `ok`, `missing`, `zero`, `negative` or `outlier` in a `valuation_flag` column, so later analysis can exclude bad values without losing any rows.

**Final flags:** 182,398 ok | 2,881 missing | 1,552 zero | 407 outlier | 1 negative

---

## Analysis

### 1. Approval times ([`02_approval_times.sql`](02_approval_times.sql))
**Question:** how long does it take to get a residential permit, and does it depend on the project?

- County-wide, the **median approval time is 9 days**, but the **average is 32.6 days**. A minority of very slow permits pulls the average up, so medians and 90th percentiles are used throughout.
- By project type, medians range from **0 days** (decks, sheds, hot tubs, retaining walls) to **77 days** (modular homes). A 0-day median suggests simple projects go through an express or over-the-counter review.
- For single-family homes over time:
  - **2008–2010:** approvals sped up to 2–4 days as applications fell by about half during the housing crash. Lower reviewer workload may explain the speed-up.
  - **Same period:** unissued permits rose from about 20 a year to 100–150, suggesting some projects were abandoned.
  - **2020 onward:** approvals doubled even though applications fell, so workload doesn't explain this change.

### 2. Where and how the county is building ([`03_where_building_happens.sql`](03_where_building_happens.sql))
**Question:** which areas have the most construction, and how is that changing?

- **By value:**
  - Bethesda leads with $3.2B (23.0% of the county).
  - Silver Spring has the most permits (40,490) but a low median ($16,462), meaning many small projects.
  - Clarksburg's high median ($95,000) reflects mostly new homes.
- **New homes over time:** ranked cities within each 5-year period using `rank() over (partition by ...)`. The leader moved from the outer suburbs to Bethesda.
- **Teardowns:** reading Bethesda's descriptions showed most "new homes" replaced demolished houses. A regex search of descriptions (`demo|tear|raze|rebuild`) measured the teardown share by city, revealing the inner/outer suburb split in Key Finding 1.

---

## Limitations

- **Teardown shares are a lower bound.** Teardowns were found by keywords in free-text descriptions. A teardown described only as, say, "NEW SFH" is missed, so the true share is at least as high as reported.
- **Recent approval times are understated (right-censoring).** Slow permits from 2025–2026 haven't been issued yet (792 from 2026 are still pending), so only the fast ones are counted in those years' medians.
- **Declared valuation is self-reported** by applicants and isn't verified by the county.
- **Use codes with very few permits can't be flagged as outliers**, because their median is effectively their own value.
- **Correlation, not causation:** the timing of changes (the 2008 crash, COVID-19) is noted, but this data alone can't establish why approval times changed.
- **2020 has unusually few unissued permits** (6, compared with hundreds in nearby years). This may reflect a records cleanup and is worth investigating.

---

## How to run

1. Install PostgreSQL and create a database (e.g. `montgomery_permits`).
2. Download the CSV from the [source page](https://data.montgomerycountymd.gov/Permitting/Residential-Permit/m88u-pqki) (Export → CSV).
3. Save it as `C:/Users/Public/residential_permits.csv`, or edit the path in the `copy` command in `01_load_and_clean.sql`. The PostgreSQL server must be able to read the file.
4. Run the files in order:

| File | What it does |
|---|---|
| [`01_load_and_clean.sql`](01_load_and_clean.sql) | Loads the raw data, builds `permits_clean`, investigates valuations and applies quality flags. Safe to re-run: it drops and rebuilds both tables. |
| [`02_approval_times.sql`](02_approval_times.sql) | Approval-time analysis |
| [`03_where_building_happens.sql`](03_where_building_happens.sql) | Construction value by city, new-home rankings and teardown analysis |

The dataset updates daily, so results from a newer download will differ slightly from the numbers above.

---

## Next steps

- Build an interactive Power BI dashboard of these findings *(link coming soon)*
- Compare home sizes (`area`) for teardown rebuilds vs. new developments
- Cross-check teardowns against the county's Demolition Permits dataset to replace the keyword estimate with a direct match

---

*Author: Ezanya Solomon Zewdu · [LinkedIn](https://www.linkedin.com/in/ezanya-solomon-450aa2267/) · [GitHub](https://github.com/Ezanya-sol)*
