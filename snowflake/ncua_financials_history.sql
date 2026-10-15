-- NCUA_FINANCIALS_HISTORY: one row per credit union per quarter for the latest
-- N quarters (default 21 = five years plus the matching quarter five years back),
-- built from the per-quarter NCUA_DATA.FINANCIALS.NCUA_FINANCIALS_YYYYMM tables.
-- Replaces CURRENT_NCUA_FINANCIALS_FILE in the CU_ORACLE_SEMANTIC semantic view.
--
-- Conventions:
--   * Balance items (assets, loans, shares, net worth, members, employees) are
--     point-in-time as of PERIOD_DATE.
--   * NCUA reports flow items year-to-date. *_YTD is as reported, *_QTR is the
--     quarter alone (YTD less the prior quarter's YTD, Q1 = YTD), and
--     *_ANNUALIZED = YTD * 4 / QUARTER.
--   * Includes every line of the Credit Analysis report's balance sheet and income
--     statement (credit_analysis/FIELD_MAP.md), with the report's definitions and
--     subtotals, so the CU Oracle's figures match the reports. Income statement
--     items are year-to-date (_YTD) as reported.
--   * Ratio columns ending _PCT are percentages (11.4 = 11.4%). NET_WORTH_RATIO_PCT
--     is NCUA's official PCA net worth ratio.
--   * TOTAL_EMPLOYEES = full-time + part-time headcount; FTE_EMPLOYEES = full-time
--     + half of part-time (NCUA's full-time-equivalent convention).
--   * ROA and the net charge-off rate use the average of the current balance and
--     the prior year-end balance (an approximation of NCUA's average assets/loans).
--   * Mergers come from ACUS_DATA.CORE_DATA.CORE_DATA (status 'M', SURVIVOR_ID,
--     STATUS_CHG_DATE). MERGER_IN_PRIOR_YEAR / MERGERS_PRIOR_YEAR cover mergers
--     into this credit union in the 12 months ending PERIOD_DATE; acquired assets
--     and members are each merged credit union's balances at its last call
--     report. ORGANIC_ growth is pro forma: this quarter vs the combined size a
--     year earlier of this credit union plus the credit unions it absorbed.
--   * The build reads 4 extra quarters so every kept quarter has a year-ago value
--     and a prior year-end value; only the latest N quarters are kept.
--
-- Run as SYSADMIN. The ANALYTICS schema's future grants give CU_ORACLE_APP_READ
-- SELECT on the table each time it is rebuilt.

CREATE OR REPLACE PROCEDURE CU_ORACLE_AGENT_DB.ANALYTICS.REFRESH_NCUA_FINANCIALS_HISTORY(
    N_QUARTERS NUMBER DEFAULT 21,
    FORCE BOOLEAN DEFAULT FALSE)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Rebuilds CU_ORACLE_AGENT_DB.ANALYTICS.NCUA_FINANCIALS_HISTORY from the latest NCUA_FINANCIALS_YYYYMM tables (skips if already current unless FORCE).'
EXECUTE AS OWNER
AS
$$
DECLARE
    union_sql VARCHAR DEFAULT '';
    latest_period VARCHAR DEFAULT '';
    current_period VARCHAR DEFAULT NULL;
    n_tables NUMBER DEFAULT 0;
    sel VARCHAR;
    n_missing NUMBER DEFAULT 0;
    -- Columns read from each NCUA_FINANCIALS_YYYYMM table. Any column a quarter's
    -- table lacks is read as NULL instead of failing the build.
    src_cols VARCHAR DEFAULT
        'NIMBLE_CUNA_ID,JOIN_NUMBER,CU_NUMBER,CHARTERSTATE,MEMBERS,TOTAL_ASSETS,' ||
        'AMT_TOTAL_SHARES_AND_DEPOSITS,PCA_NET_WORTH,PCA_NET_WORTH_RATIO,AMT_TOTAL_LOANS,' ||
        'AMT_TOTAL_DELQ_LOANS,AMT_NET_MBL_BALANCE,NET_INCOME,NET_CHARGEOFFS,' ||
        'FULL_TIME_EMPLOYEES,PART_TIME_EMPLOYEES,' ||
        -- Credit Analysis balance sheet
        'CASH_AND_EQUIVALENTS,TOTAL_INVESTMENTS,AMT_CREDIT_CARDS,AMT_OTHER_UNSECURED,AMT_PAL,' ||
        'AMT_EDUCATIONAL,AMT_NEW_AUTO,AMT_USED_AUTO,AMT_LEASES,AMT_OTHER_NON_RE,' ||
        'AMT_FIRST_MORTGAGES,AMT_SECOND_MORTGAGES,AMT_OTHER_REAL_ESTATE_LOANS,' ||
        'AMT_TOTAL_MBL_RE_SECURED_MAIN,AMT_TOTAL_MBL_NON_RE_SECURED,LOANS_HELD_FOR_SALE,' ||
        'LOAN_LOSS_ALLOWANCE,LAND_AND_BUILDING,OTHER_FIXED_ASSETS,ACCOUNTS_PAYABLE,' ||
        'ACCRUED_DIVIDENDS_AND_INTEREST_PAYABLE,AMT_ALLOWANCE_FOR_CREDIT_LOSS,TOTAL_BORROWINGS,' ||
        'AMT_TOTAL_SHARES,AMT_NONMEMBER_DEPOSITS,AMT_UNDIVIDED_EARNINGS,AMT_ALL_OTHER_RESERVES,' ||
        'TOTAL_LIABILITIES_AND_CAPITAL,AMT_TOTAL_DELQ_LOANS_2_TO_6MO,AMT_TOTAL_DELQ_LOANS_6_TO_12MO,' ||
        'AMT_TOTAL_DELQ_LOANS_OVER_12MO,' ||
        -- Credit Analysis income statement (year-to-date)
        'INTEREST_ON_LOANS,REBATES,FEE_INCOME,INVESTMENT_INCOME,OTHER_OPERATING_INCOME,' ||
        'SALARY_AND_BENEFITS_EXP,OFFICE_OCCUPANCY_EXP,OFFICE_OPERATIONS_EXP,' ||
        'EDUCATIONAL_AND_PROMOTIONAL_EXP,LOAN_SERVICING_EXP,PROFESSIONAL_AND_OUTSIDE_SERVICES_EXP,' ||
        'MEMBER_INSURANCE_EXP,ALL_OTHER_EXPENSES,PROVISIONS_FOR_LOAN_LOSS,NON_OPERATING_GAIN_LOSS,' ||
        'INTEREST_ON_BORROWINGS,INTEREST_ON_DIVIDENDS_AND_SAVINGS';
BEGIN
    SHOW TABLES LIKE 'NCUA_FINANCIALS_%' IN SCHEMA NCUA_DATA.FINANCIALS;
    LET rs RESULTSET := (
        SELECT "name" AS TBL
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE REGEXP_LIKE("name", '^NCUA_FINANCIALS_[0-9]{6}$')
        QUALIFY ROW_NUMBER() OVER (ORDER BY "name" DESC) <= :N_QUARTERS + 4
        ORDER BY TBL);
    LET c1 CURSOR FOR rs;
    FOR r IN c1 DO
        latest_period := RIGHT(r.TBL, 6);
        EXECUTE IMMEDIATE 'SHOW COLUMNS IN TABLE NCUA_DATA.FINANCIALS.' || r.TBL;
        sel := (
            SELECT LISTAGG(IFF(p."column_name" IS NULL, 'NULL::FLOAT AS ' || w.value::STRING, w.value::STRING), ', ')
                   WITHIN GROUP (ORDER BY w.index)
            FROM TABLE(FLATTEN(INPUT => SPLIT(:src_cols, ','))) w
            LEFT JOIN TABLE(RESULT_SCAN(LAST_QUERY_ID())) p ON p."column_name" = w.value::STRING);
        n_missing := n_missing + REGEXP_COUNT(sel, 'NULL::FLOAT AS ');
        union_sql := union_sql || IFF(n_tables = 0, '', ' UNION ALL ') ||
            'SELECT ''' || latest_period || ''' AS PERIOD, ' || sel ||
            ' FROM NCUA_DATA.FINANCIALS.' || r.TBL;
        n_tables := n_tables + 1;
    END FOR;

    IF (n_tables = 0) THEN
        RETURN 'No NCUA_FINANCIALS_YYYYMM tables found - nothing built.';
    END IF;

    IF (NOT FORCE) THEN
        BEGIN
            SELECT MAX(PERIOD) INTO :current_period
            FROM CU_ORACLE_AGENT_DB.ANALYTICS.NCUA_FINANCIALS_HISTORY;
        EXCEPTION
            WHEN OTHER THEN current_period := NULL;
        END;
        IF (current_period = latest_period) THEN
            RETURN 'Already current through ' || latest_period || ' - not rebuilt.';
        END IF;
    END IF;

    EXECUTE IMMEDIATE 'CREATE OR REPLACE TEMPORARY TABLE CU_ORACLE_AGENT_DB.ANALYTICS.NCUA_HIST_RAW AS ' || union_sql;

    CREATE OR REPLACE TABLE CU_ORACLE_AGENT_DB.ANALYTICS.NCUA_FINANCIALS_HISTORY
    COMMENT = 'Quarterly NCUA 5300 call report financials, one row per credit union per quarter, latest five years. Built by REFRESH_NCUA_FINANCIALS_HISTORY.'
    AS
    WITH base AS (
        SELECT
            NIMBLE_CUNA_ID,
            TRY_TO_NUMBER(JOIN_NUMBER)            AS JOIN_NUMBER,
            TRY_TO_NUMBER(CU_NUMBER)              AS CHARTER_NUMBER,
            CHARTERSTATE,
            PERIOD,
            LAST_DAY(TO_DATE(PERIOD, 'YYYYMM'))   AS PERIOD_DATE,
            MEMBERS,
            TOTAL_ASSETS,
            AMT_TOTAL_SHARES_AND_DEPOSITS,
            PCA_NET_WORTH                         AS NET_WORTH,
            PCA_NET_WORTH_RATIO,
            AMT_TOTAL_LOANS,
            AMT_TOTAL_DELQ_LOANS,
            -- Net member business loan balance (5300 account 400A): the statutory
            -- MBL measure, as used on the Credit Analysis balance sheet
            AMT_NET_MBL_BALANCE                   AS AMT_MEMBER_BUSINESS_LOANS,
            NET_INCOME                            AS NET_INCOME_YTD,
            NET_CHARGEOFFS                        AS NET_CHARGEOFFS_YTD,
            FULL_TIME_EMPLOYEES,
            PART_TIME_EMPLOYEES,
            -- Credit Analysis balance sheet line items (labels match the report)
            CASH_AND_EQUIVALENTS,
            TOTAL_INVESTMENTS                     AS INVESTMENTS_AND_DEPOSITS,
            AMT_CREDIT_CARDS                      AS CREDIT_CARD_LOANS,
            COALESCE(AMT_OTHER_UNSECURED, 0) + COALESCE(AMT_PAL, 0) + COALESCE(AMT_EDUCATIONAL, 0) AS OTHER_UNSECURED_LOANS,
            AMT_NEW_AUTO                          AS NEW_AUTO_LOANS,
            AMT_USED_AUTO                         AS USED_AUTO_LOANS,
            AMT_LEASES                            AS LEASES_RECEIVABLE,
            AMT_OTHER_NON_RE                      AS OTHER_SECURED_NON_RE_LOANS,
            AMT_FIRST_MORTGAGES                   AS FIRST_MORTGAGE_LOANS,
            AMT_SECOND_MORTGAGES                  AS SECOND_MORTGAGE_LOANS,
            AMT_OTHER_REAL_ESTATE_LOANS           AS OTHER_NON_COMMERCIAL_RE_LOANS,
            AMT_TOTAL_MBL_RE_SECURED_MAIN         AS COMMERCIAL_RE_SECURED_LOANS,
            AMT_TOTAL_MBL_NON_RE_SECURED          AS COMMERCIAL_NON_RE_SECURED_LOANS,
            LOANS_HELD_FOR_SALE,
            LOAN_LOSS_ALLOWANCE,
            LAND_AND_BUILDING,
            OTHER_FIXED_ASSETS,
            ACCOUNTS_PAYABLE,
            ACCRUED_DIVIDENDS_AND_INTEREST_PAYABLE AS ACCRUED_DIVIDENDS_AND_INTEREST,
            AMT_ALLOWANCE_FOR_CREDIT_LOSS         AS ALLOWANCE_OFF_BALANCE_SHEET_EXPOSURES,
            TOTAL_BORROWINGS                      AS BORROWINGS,
            AMT_TOTAL_SHARES                      AS MEMBER_SHARES,
            AMT_NONMEMBER_DEPOSITS                AS NONMEMBER_DEPOSITS,
            AMT_UNDIVIDED_EARNINGS                AS UNDIVIDED_EARNINGS,
            AMT_ALL_OTHER_RESERVES                AS ALL_OTHER_RESERVES,
            TOTAL_LIABILITIES_AND_CAPITAL,
            AMT_TOTAL_DELQ_LOANS_2_TO_6MO         AS DELINQUENT_LOANS_2_TO_6_MONTHS,
            AMT_TOTAL_DELQ_LOANS_6_TO_12MO        AS DELINQUENT_LOANS_6_TO_12_MONTHS,
            AMT_TOTAL_DELQ_LOANS_OVER_12MO        AS DELINQUENT_LOANS_OVER_12_MONTHS,
            -- Credit Analysis income statement line items, year-to-date as reported
            INTEREST_ON_LOANS                     AS LOAN_AND_LEASE_INTEREST_YTD,
            REBATES                               AS INTEREST_REBATES_YTD,
            FEE_INCOME                            AS FEE_INCOME_YTD,
            INVESTMENT_INCOME                     AS INVESTMENT_INCOME_YTD,
            OTHER_OPERATING_INCOME                AS OTHER_OPERATING_INCOME_YTD,
            SALARY_AND_BENEFITS_EXP               AS SALARIES_AND_BENEFITS_YTD,
            OFFICE_OCCUPANCY_EXP                  AS OFFICE_OCCUPANCY_YTD,
            OFFICE_OPERATIONS_EXP                 AS OFFICE_OPERATIONS_YTD,
            EDUCATIONAL_AND_PROMOTIONAL_EXP       AS EDUCATIONAL_AND_PROMOTIONAL_YTD,
            LOAN_SERVICING_EXP                    AS LOAN_SERVICING_YTD,
            PROFESSIONAL_AND_OUTSIDE_SERVICES_EXP AS PROFESSIONAL_AND_OUTSIDE_SERVICES_YTD,
            MEMBER_INSURANCE_EXP                  AS MEMBER_INSURANCE_YTD,
            ALL_OTHER_EXPENSES                    AS ALL_OTHER_EXPENSES_YTD,
            PROVISIONS_FOR_LOAN_LOSS              AS PROVISION_FOR_LOAN_LOSSES_YTD,
            NON_OPERATING_GAIN_LOSS               AS NON_OPERATING_GAIN_LOSS_YTD,
            INTEREST_ON_BORROWINGS                AS INTEREST_ON_BORROWINGS_YTD,
            INTEREST_ON_DIVIDENDS_AND_SAVINGS     AS DIVIDENDS_YTD
        FROM CU_ORACLE_AGENT_DB.ANALYTICS.NCUA_HIST_RAW
    ),
    -- Mergers from ACUS_DATA.CORE_DATA (authoritative merger source): each merged
    -- credit union, its survivor, and its size at its last call report.
    mergers AS (
        SELECT
            c.NIMBLE_CUNA_ID::STRING                      AS TARGET_ID,
            c.SURVIVOR_ID::STRING                         AS SURVIVOR_ID,
            TRY_TO_DATE(c.STATUS_CHG_DATE::STRING)        AS MERGER_DATE
        FROM ACUS_DATA.CORE_DATA.CORE_DATA c
        WHERE c.STATUS = 'M'
          AND c.SURVIVOR_ID IS NOT NULL
          AND TRY_TO_DATE(c.STATUS_CHG_DATE::STRING) IS NOT NULL
    ),
    targets AS (
        SELECT m.TARGET_ID, m.SURVIVOR_ID, m.MERGER_DATE,
               t.TOTAL_ASSETS AS TARGET_ASSETS, t.MEMBERS AS TARGET_MEMBERS
        FROM mergers m
        LEFT JOIN base t ON t.NIMBLE_CUNA_ID = m.TARGET_ID AND t.PERIOD_DATE <= m.MERGER_DATE
        QUALIFY ROW_NUMBER() OVER (PARTITION BY m.TARGET_ID ORDER BY t.PERIOD_DATE DESC NULLS LAST) = 1
    ),
    merger_flags AS (
        SELECT
            b.JOIN_NUMBER,
            b.PERIOD_DATE,
            COUNT_IF(tg.MERGER_DATE > LAST_DAY(DATEADD(month, -3, b.PERIOD_DATE))) AS MERGERS_IN_QUARTER,
            COUNT(*)                                    AS MERGERS_PRIOR_YEAR,
            SUM(COALESCE(tg.TARGET_ASSETS, 0))          AS ACQUIRED_ASSETS_PRIOR_YEAR,
            SUM(COALESCE(tg.TARGET_MEMBERS, 0))         AS ACQUIRED_MEMBERS_PRIOR_YEAR,
            -- Merged credit unions' balances one year before this quarter (falling
            -- back to their last report), for pro forma (organic) growth.
            SUM(COALESCE(ty.TOTAL_ASSETS, tg.TARGET_ASSETS, 0)) AS ACQUIRED_ASSETS_YEAR_AGO,
            SUM(COALESCE(ty.MEMBERS, tg.TARGET_MEMBERS, 0))     AS ACQUIRED_MEMBERS_YEAR_AGO
        FROM base b
        JOIN targets tg ON tg.SURVIVOR_ID = b.NIMBLE_CUNA_ID
                       AND tg.MERGER_DATE >  DATEADD(year, -1, b.PERIOD_DATE)
                       AND tg.MERGER_DATE <= b.PERIOD_DATE
        LEFT JOIN base ty ON ty.NIMBLE_CUNA_ID = tg.TARGET_ID
                         AND ty.PERIOD_DATE = DATEADD(year, -1, b.PERIOD_DATE)
        GROUP BY b.JOIN_NUMBER, b.PERIOD_DATE
    ),
    calc AS (
        SELECT
            b.*,
            YEAR(b.PERIOD_DATE)                                   AS YEAR,
            QUARTER(b.PERIOD_DATE)                                AS QUARTER,
            DENSE_RANK() OVER (ORDER BY b.PERIOD_DATE DESC)       AS PERIOD_RANK,
            IFF(QUARTER(b.PERIOD_DATE) = 1, b.NET_INCOME_YTD,
                b.NET_INCOME_YTD - pq.NET_INCOME_YTD)             AS NET_INCOME_QTR,
            b.NET_INCOME_YTD * 4 / QUARTER(b.PERIOD_DATE)         AS NET_INCOME_ANNUALIZED,
            IFF(QUARTER(b.PERIOD_DATE) = 1, b.NET_CHARGEOFFS_YTD,
                b.NET_CHARGEOFFS_YTD - pq.NET_CHARGEOFFS_YTD)     AS NET_CHARGEOFFS_QTR,
            b.NET_CHARGEOFFS_YTD * 4 / QUARTER(b.PERIOD_DATE)     AS NET_CHARGEOFFS_ANNUALIZED,
            (b.TOTAL_ASSETS + COALESCE(pd.TOTAL_ASSETS, b.TOTAL_ASSETS)) / 2          AS AVG_ASSETS_YTD,
            (b.AMT_TOTAL_LOANS + COALESCE(pd.AMT_TOTAL_LOANS, b.AMT_TOTAL_LOANS)) / 2 AS AVG_LOANS_YTD,
            ya.TOTAL_ASSETS                   AS YA_ASSETS,
            ya.AMT_TOTAL_LOANS                AS YA_LOANS,
            ya.AMT_TOTAL_SHARES_AND_DEPOSITS  AS YA_SHARES,
            ya.MEMBERS                        AS YA_MEMBERS,
            ya.NET_WORTH                      AS YA_NET_WORTH,
            COALESCE(mf.MERGERS_IN_QUARTER, 0)          AS MERGERS_IN_QUARTER,
            COALESCE(mf.MERGERS_PRIOR_YEAR, 0)          AS MERGERS_PRIOR_YEAR,
            COALESCE(mf.ACQUIRED_ASSETS_PRIOR_YEAR, 0)  AS ACQUIRED_ASSETS_PRIOR_YEAR,
            COALESCE(mf.ACQUIRED_MEMBERS_PRIOR_YEAR, 0) AS ACQUIRED_MEMBERS_PRIOR_YEAR,
            COALESCE(mf.ACQUIRED_ASSETS_YEAR_AGO, 0)    AS ACQUIRED_ASSETS_YEAR_AGO,
            COALESCE(mf.ACQUIRED_MEMBERS_YEAR_AGO, 0)   AS ACQUIRED_MEMBERS_YEAR_AGO
        FROM base b
        LEFT JOIN merger_flags mf ON mf.JOIN_NUMBER = b.JOIN_NUMBER
                                 AND mf.PERIOD_DATE = b.PERIOD_DATE
        LEFT JOIN base pq ON pq.JOIN_NUMBER = b.JOIN_NUMBER
                         AND pq.PERIOD_DATE = LAST_DAY(DATEADD(month, -3, b.PERIOD_DATE))
        LEFT JOIN base pd ON pd.JOIN_NUMBER = b.JOIN_NUMBER
                         AND pd.PERIOD_DATE = DATE_FROM_PARTS(YEAR(b.PERIOD_DATE) - 1, 12, 31)
        LEFT JOIN base ya ON ya.JOIN_NUMBER = b.JOIN_NUMBER
                         AND ya.PERIOD_DATE = DATEADD(year, -1, b.PERIOD_DATE)
    )
    SELECT
        NIMBLE_CUNA_ID,
        JOIN_NUMBER,
        CHARTER_NUMBER,
        CHARTERSTATE,
        PERIOD,
        PERIOD_DATE,
        YEAR,
        QUARTER,
        PERIOD_RANK = 1                                                        AS IS_LATEST_PERIOD,
        MEMBERS,
        TOTAL_ASSETS,
        AMT_TOTAL_SHARES_AND_DEPOSITS,
        NET_WORTH,
        AMT_TOTAL_LOANS,
        AMT_TOTAL_DELQ_LOANS,
        AMT_MEMBER_BUSINESS_LOANS,
        FULL_TIME_EMPLOYEES,
        PART_TIME_EMPLOYEES,
        COALESCE(FULL_TIME_EMPLOYEES, 0) + COALESCE(PART_TIME_EMPLOYEES, 0)       AS TOTAL_EMPLOYEES,
        -- NCUA convention: a part-time employee counts as half a full-time equivalent
        COALESCE(FULL_TIME_EMPLOYEES, 0) + COALESCE(PART_TIME_EMPLOYEES, 0) * 0.5 AS FTE_EMPLOYEES,
        NET_INCOME_YTD,
        NET_INCOME_QTR,
        NET_INCOME_ANNUALIZED,
        NET_CHARGEOFFS_YTD,
        NET_CHARGEOFFS_QTR,
        NET_CHARGEOFFS_ANNUALIZED,
        AVG_ASSETS_YTD,
        AVG_LOANS_YTD,
        -- Credit Analysis balance sheet (labels and formulas match the report)
        CASH_AND_EQUIVALENTS,
        INVESTMENTS_AND_DEPOSITS,
        COALESCE(CASH_AND_EQUIVALENTS, 0) + COALESCE(INVESTMENTS_AND_DEPOSITS, 0) AS TOTAL_CASH_AND_INVESTMENTS,
        CREDIT_CARD_LOANS,
        OTHER_UNSECURED_LOANS,
        NEW_AUTO_LOANS,
        USED_AUTO_LOANS,
        LEASES_RECEIVABLE,
        OTHER_SECURED_NON_RE_LOANS,
        FIRST_MORTGAGE_LOANS,
        SECOND_MORTGAGE_LOANS,
        OTHER_NON_COMMERCIAL_RE_LOANS,
        COMMERCIAL_RE_SECURED_LOANS,
        COMMERCIAL_NON_RE_SECURED_LOANS,
        AMT_TOTAL_LOANS - COALESCE(LOANS_HELD_FOR_SALE, 0)                     AS LOANS_EXCL_HELD_FOR_SALE,
        LOANS_HELD_FOR_SALE,
        LOAN_LOSS_ALLOWANCE,
        LAND_AND_BUILDING,
        OTHER_FIXED_ASSETS,
        -- residual that ties the itemized assets to total assets (allowance is a contra-asset)
        TOTAL_ASSETS - (COALESCE(CASH_AND_EQUIVALENTS, 0) + COALESCE(INVESTMENTS_AND_DEPOSITS, 0))
            - AMT_TOTAL_LOANS + COALESCE(LOAN_LOSS_ALLOWANCE, 0)
            - COALESCE(LAND_AND_BUILDING, 0) - COALESCE(OTHER_FIXED_ASSETS, 0)  AS ALL_OTHER_ASSETS,
        ACCOUNTS_PAYABLE,
        ACCRUED_DIVIDENDS_AND_INTEREST,
        ALLOWANCE_OFF_BALANCE_SHEET_EXPOSURES,
        BORROWINGS,
        MEMBER_SHARES,
        NONMEMBER_DEPOSITS,
        COALESCE(ACCOUNTS_PAYABLE, 0) + COALESCE(ACCRUED_DIVIDENDS_AND_INTEREST, 0)
            + COALESCE(ALLOWANCE_OFF_BALANCE_SHEET_EXPOSURES, 0) + COALESCE(BORROWINGS, 0)
            + COALESCE(MEMBER_SHARES, 0) + COALESCE(NONMEMBER_DEPOSITS, 0)     AS TOTAL_LIABILITIES,
        UNDIVIDED_EARNINGS,
        ALL_OTHER_RESERVES,
        TOTAL_LIABILITIES_AND_CAPITAL,
        DELINQUENT_LOANS_2_TO_6_MONTHS,
        DELINQUENT_LOANS_6_TO_12_MONTHS,
        DELINQUENT_LOANS_OVER_12_MONTHS,
        -- Credit Analysis income statement, year-to-date (subtotals as the report computes them)
        LOAN_AND_LEASE_INTEREST_YTD,
        INTEREST_REBATES_YTD,
        FEE_INCOME_YTD,
        INVESTMENT_INCOME_YTD,
        OTHER_OPERATING_INCOME_YTD,
        COALESCE(LOAN_AND_LEASE_INTEREST_YTD, 0) - COALESCE(INTEREST_REBATES_YTD, 0) + COALESCE(FEE_INCOME_YTD, 0)
            + COALESCE(INVESTMENT_INCOME_YTD, 0) + COALESCE(OTHER_OPERATING_INCOME_YTD, 0) AS TOTAL_INCOME_YTD,
        SALARIES_AND_BENEFITS_YTD,
        OFFICE_OCCUPANCY_YTD,
        OFFICE_OPERATIONS_YTD,
        EDUCATIONAL_AND_PROMOTIONAL_YTD,
        LOAN_SERVICING_YTD,
        PROFESSIONAL_AND_OUTSIDE_SERVICES_YTD,
        MEMBER_INSURANCE_YTD,
        ALL_OTHER_EXPENSES_YTD,
        COALESCE(SALARIES_AND_BENEFITS_YTD, 0) + COALESCE(OFFICE_OCCUPANCY_YTD, 0) + COALESCE(OFFICE_OPERATIONS_YTD, 0)
            + COALESCE(EDUCATIONAL_AND_PROMOTIONAL_YTD, 0) + COALESCE(LOAN_SERVICING_YTD, 0)
            + COALESCE(PROFESSIONAL_AND_OUTSIDE_SERVICES_YTD, 0) + COALESCE(MEMBER_INSURANCE_YTD, 0)
            + COALESCE(ALL_OTHER_EXPENSES_YTD, 0)                              AS OPERATING_EXPENSES_YTD,
        PROVISION_FOR_LOAN_LOSSES_YTD,
        NON_OPERATING_GAIN_LOSS_YTD,
        INTEREST_ON_BORROWINGS_YTD,
        DIVIDENDS_YTD,
        COALESCE(INTEREST_ON_BORROWINGS_YTD, 0) + COALESCE(DIVIDENDS_YTD, 0)  AS COST_OF_FUNDS_YTD,
        TOTAL_INCOME_YTD - OPERATING_EXPENSES_YTD - COALESCE(PROVISION_FOR_LOAN_LOSSES_YTD, 0)
            + COALESCE(NON_OPERATING_GAIN_LOSS_YTD, 0)                         AS NET_INCOME_BEFORE_DIVIDENDS_YTD,
        -- NCUA's official PCA net worth ratio (account 998, in basis points), as on
        -- the Credit Analysis report; falls back to net worth / assets if missing
        ROUND(COALESCE(PCA_NET_WORTH_RATIO / 100, NET_WORTH / NULLIF(TOTAL_ASSETS, 0) * 100), 4) AS NET_WORTH_RATIO_PCT,
        ROUND(AMT_TOTAL_LOANS / NULLIF(AMT_TOTAL_SHARES_AND_DEPOSITS, 0) * 100, 4) AS LOAN_TO_SHARE_PCT,
        ROUND(AMT_TOTAL_DELQ_LOANS / NULLIF(AMT_TOTAL_LOANS, 0) * 100, 4)      AS DELINQUENCY_RATE_PCT,
        ROUND(NET_INCOME_ANNUALIZED / NULLIF(AVG_ASSETS_YTD, 0) * 100, 4)      AS ROA_PCT,
        ROUND(NET_CHARGEOFFS_ANNUALIZED / NULLIF(AVG_LOANS_YTD, 0) * 100, 4)   AS NET_CHARGEOFF_RATE_PCT,
        ROUND((TOTAL_ASSETS / NULLIF(YA_ASSETS, 0) - 1) * 100, 4)              AS ASSETS_YOY_GROWTH_PCT,
        ROUND((AMT_TOTAL_LOANS / NULLIF(YA_LOANS, 0) - 1) * 100, 4)            AS LOANS_YOY_GROWTH_PCT,
        ROUND((AMT_TOTAL_SHARES_AND_DEPOSITS / NULLIF(YA_SHARES, 0) - 1) * 100, 4) AS SHARES_YOY_GROWTH_PCT,
        ROUND((MEMBERS / NULLIF(YA_MEMBERS, 0) - 1) * 100, 4)                  AS MEMBERS_YOY_GROWTH_PCT,
        ROUND((NET_WORTH / NULLIF(YA_NET_WORTH, 0) - 1) * 100, 4)              AS NET_WORTH_YOY_GROWTH_PCT,
        MERGERS_IN_QUARTER > 0                                                 AS MERGER_IN_QUARTER,
        MERGERS_IN_QUARTER,
        MERGERS_PRIOR_YEAR > 0                                                 AS MERGER_IN_PRIOR_YEAR,
        MERGERS_PRIOR_YEAR,
        ACQUIRED_ASSETS_PRIOR_YEAR,
        ACQUIRED_MEMBERS_PRIOR_YEAR,
        ROUND((TOTAL_ASSETS / NULLIF(YA_ASSETS + ACQUIRED_ASSETS_YEAR_AGO, 0) - 1) * 100, 4) AS ORGANIC_ASSETS_YOY_GROWTH_PCT,
        ROUND((MEMBERS / NULLIF(YA_MEMBERS + ACQUIRED_MEMBERS_YEAR_AGO, 0) - 1) * 100, 4)   AS ORGANIC_MEMBERS_YOY_GROWTH_PCT
    FROM calc
    WHERE PERIOD_RANK <= :N_QUARTERS
    ORDER BY JOIN_NUMBER, PERIOD_DATE;

    DROP TABLE IF EXISTS CU_ORACLE_AGENT_DB.ANALYTICS.NCUA_HIST_RAW;
    RETURN 'Rebuilt NCUA_FINANCIALS_HISTORY through ' || latest_period ||
           ' (latest ' || N_QUARTERS || ' quarters kept, ' || n_tables || ' read; ' ||
           n_missing || ' missing source columns read as NULL).';
END;
$$;

-- Daily check at 6am Eastern: rebuilds only when a newer NCUA quarter has been loaded.
-- Also refreshes the NCUA name history used for name matching (cu_name_aliases.sql).
CREATE OR REPLACE TASK CU_ORACLE_AGENT_DB.ANALYTICS.REFRESH_NCUA_FINANCIALS_HISTORY_TASK
    WAREHOUSE = PAUL_WH
    SCHEDULE = 'USING CRON 0 6 * * * America/New_York'
    COMMENT = 'Daily: rebuild NCUA_FINANCIALS_HISTORY and CU_NAME_HISTORY_NCUA if a newer NCUA quarter is available.'
AS
BEGIN
    CALL CU_ORACLE_AGENT_DB.ANALYTICS.REFRESH_NCUA_FINANCIALS_HISTORY(21, FALSE);
    CALL CU_ORACLE_AGENT_DB.ANALYTICS.REFRESH_CU_NAME_HISTORY(FALSE);
END;

ALTER TASK CU_ORACLE_AGENT_DB.ANALYTICS.REFRESH_NCUA_FINANCIALS_HISTORY_TASK RESUME;
