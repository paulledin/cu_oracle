-- CU_ORACLE_LIVE: one row per US credit union known to America's Credit Unions
-- (NIMBLE via ACUS_DATA.CORE_DATA), with organizational and contact details plus
-- the latest reported assets, members, employees, and branch count.
-- 2026-10-15: added SURVIVOR_ and CURRENT_SUCCESSOR_ merger fields, and
-- CHARTER_STATE (needs CU_NCUA_CHARTER_STATE from cu_name_aliases.sql first).
-- 2026-10-16: AFL and LEAGUE_AFFILIATED empty for merged/liquidated credit unions.
-- Dynamic table: refreshes itself (target lag 1 hour) when CORE_DATA changes.
-- Run as SYSADMIN. The ANALYTICS schema's future grants give CU_ORACLE_APP_READ
-- SELECT whenever this is re-created.

create or replace dynamic table CU_ORACLE_AGENT_DB.ANALYTICS.CU_ORACLE_LIVE(
	NIMBLE_CUNA_ID,
	STATUS,
	NAME,
	PHONE,
	WEB,
	LEAGUE_NAME,
	PO_ADDRESS,
	PO_CITY,
	PO_STATE,
	PO_ZIP_CODE,
	ST_ADDRESS,
	ST_CITY,
	ST_STATE,
	ST_ZIP_CODE,
	COUNTRY,
	LEAGUE_AFFILIATED,
	AFL,
	FCHT,
	CEO_FULL_NAME,
	ORG_DATE,
	TOM_CODE,
	STATUS_CHG_DATE,
	JOIN_NUMBER,
	LAST_REPORTED_ASSETS,
	LAST_REPORTED_MEMBERS,
	LAST_PERIOD_REPORTED,
	LOW_INCOME_DESIGNATED,
	FULL_TIME_EMPLOYEES,
	PART_TIME_EMPLOYEES,
	BRANCHES,
	TOM_DESCRIPTION,
	SURVIVOR_ID,
	SURVIVOR_NAME,
	CURRENT_SUCCESSOR_ID,
	CURRENT_SUCCESSOR_NAME,
	CHARTER_STATE
)
target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = PAUL_WH
as
SELECT
    f1.nimble_cuna_id, f1.status, f1.name, f1.phone, f1.web, f1.league_name,
    f1.po_address, f1.po_city, f1.po_state, f1.po_zip_code,
    f1.st_address, f1.st_city, f1.st_state, f1.st_zip_code, f1.country,
    -- Affiliation ends when a credit union merges or liquidates, so it is left
    -- empty for those statuses rather than shown as "not affiliated".
    IFF(f1.status IN ('M', 'L'), NULL, f1.league_affiliated) AS league_affiliated,
    IFF(f1.status IN ('M', 'L'), NULL, f1.afl)               AS afl,
    f1.fcht, f1.ceo_full_name, f1.org_date, f1.tom_code,
    f1.status_chg_date, f1.join_number,
    f1.total_assets AS "LAST_REPORTED_ASSETS", f1.members AS "LAST_REPORTED_MEMBERS",
    f1.last_period_reported,
    CASE
        WHEN f1.low_income_designated = 1 THEN 'Yes'
        WHEN f1.low_income_designated = 0 THEN 'No'
        ELSE NULL
    END AS low_income_designated,
    f1.full_time_employees, f1.part_time_employees, f1.branches,
    f2.description,
    -- Merged credit unions: the credit union each merged into directly, and the
    -- end of the merger chain today (chains are at most 5 deep; 6 levels kept).
    s1.nimble_cuna_id::string AS survivor_id,
    s1.name                   AS survivor_name,
    COALESCE(s6.nimble_cuna_id, s5.nimble_cuna_id, s4.nimble_cuna_id,
             s3.nimble_cuna_id, s2.nimble_cuna_id, s1.nimble_cuna_id)::string AS current_successor_id,
    COALESCE(s6.name, s5.name, s4.name, s3.name, s2.name, s1.name)           AS current_successor_name,
    -- The state a credit union is headquartered in, by ACUs convention: its NCUA
    -- charter state (most recent report), or its address state if it never reported.
    COALESCE(cs.charter_state, f1.st_state)                                  AS charter_state
FROM acus_data.core_data.core_data f1
LEFT JOIN acus_data.core_data.tom_descriptions f2 on f1.tom_code=f2.tom
LEFT JOIN cu_oracle_agent_db.analytics.cu_ncua_charter_state cs ON cs.join_number = f1.join_number
LEFT JOIN acus_data.core_data.core_data s1 ON f1.status = 'M' AND s1.nimble_cuna_id::string = f1.survivor_id::string
LEFT JOIN acus_data.core_data.core_data s2 ON s1.status = 'M' AND s2.nimble_cuna_id::string = s1.survivor_id::string
LEFT JOIN acus_data.core_data.core_data s3 ON s2.status = 'M' AND s3.nimble_cuna_id::string = s2.survivor_id::string
LEFT JOIN acus_data.core_data.core_data s4 ON s3.status = 'M' AND s4.nimble_cuna_id::string = s3.survivor_id::string
LEFT JOIN acus_data.core_data.core_data s5 ON s4.status = 'M' AND s5.nimble_cuna_id::string = s4.survivor_id::string
LEFT JOIN acus_data.core_data.core_data s6 ON s5.status = 'M' AND s6.nimble_cuna_id::string = s5.survivor_id::string
WHERE f1.country = 'United States';
