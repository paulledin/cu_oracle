-- CU_ORACLE_LIVE: one row per US credit union known to America's Credit Unions
-- (NIMBLE via ACUS_DATA.CORE_DATA), with organizational and contact details plus
-- the latest reported assets, members, employees, and branch count.
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
	TOM_DESCRIPTION
)
target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = PAUL_WH
as
SELECT
    nimble_cuna_id, status, name, phone, web, league_name,
    po_address, po_city, po_state, po_zip_code,
    st_address, st_city, st_state, st_zip_code, country,
    league_affiliated, afl, fcht, ceo_full_name, org_date, tom_code,
    status_chg_date, join_number,
    total_assets AS "LAST_REPORTED_ASSETS", members AS "LAST_REPORTED_MEMBERS",
    last_period_reported,
    CASE
        WHEN low_income_designated = 1 THEN 'Yes'
        WHEN low_income_designated = 0 THEN 'No'
        ELSE NULL
    END AS low_income_designated,
    full_time_employees, part_time_employees, branches,
    f2.description
FROM acus_data.core_data.core_data f1
LEFT JOIN acus_data.core_data.tom_descriptions f2 on f1.tom_code=f2.tom
WHERE country = 'United States';
