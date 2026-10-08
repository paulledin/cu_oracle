-- CURRENT_NCUA_BRANCH_FILE: every credit union site in the latest NCUA branch
-- file (NCUA_DATA.BRANCHES.MOST_CURRENT), one row per site.
-- Dynamic table: refreshes itself (target lag 1 hour) when MOST_CURRENT changes.
-- Kept current-only on purpose: the quarterly branch files are still a work in
-- progress (e.g., ~790 sites appeared at once in the December 2025 file), so
-- branch history is not in the CU Oracle yet.
-- Run as SYSADMIN. The ANALYTICS schema's future grants give CU_ORACLE_APP_READ
-- SELECT whenever this is re-created.

create or replace dynamic table CU_ORACLE_AGENT_DB.ANALYTICS.CURRENT_NCUA_BRANCH_FILE(
	FCHT,
	JOIN_NUMBER,
	SITENAME,
	SITETYPENAME,
	MAINOFFICE,
	PHYSICALADDRESSLINE1,
	PHYSICALADDRESSLINE2,
	PHYSICALADDRESSCITY,
	PHYSICALADDRESSSTATECODE,
	PHYSICALADDRESSPOSTALCODE,
	PHONENUMBER,
	HOURSOFOPERATION,
	MEMBERSERVICES,
	ATM,
	DRIVETHRU
)
target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = PAUL_WH
as
SELECT
    cu_number AS fcht,
    join_number,
    sitename,
    sitetypename,
    mainoffice,
    physicaladdressline1,
    physicaladdressline2,
    physicaladdresscity,
    physicaladdressstatecode,
    physicaladdresspostalcode,
    phonenumber,
    hoursofoperation,
    CASE
        WHEN memberservices = 1 THEN 'Yes'
        WHEN memberservices = 0 THEN 'No'
        ELSE NULL
    END AS memberservices,
    CASE
        WHEN atm = 1 THEN 'Yes'
        WHEN atm = 0 THEN 'No'
        ELSE NULL
    END AS atm,
    CASE
        WHEN drivethru = 1 THEN 'Yes'
        WHEN drivethru = 0 THEN 'No'
        ELSE NULL
    END AS drivethru
FROM ncua_data.branches.most_current;
