-- Credit union name matching for the CU Oracle.
--
--   CU_NAME_KEY(name)      normalizes a name to a matching key: lowercase, drops
--                          "credit union"/"federal credit union"/"FCU"/"CU",
--                          EFCU/ECU/Emp -> employees, & -> and, Dept -> department,
--                          1st/2nd/3rd -> first/second/third, NIMBLE "| ..." tags,
--                          punctuation, and all spaces ("Mid State" = "MidState").
--   CU_NAME_HISTORY_NCUA   every legal name and website domain each credit union
--                          used in the NCUA quarterly call reports (1994-present),
--                          with the first and last quarter it appeared. Rebuilt by
--                          REFRESH_CU_NAME_HISTORY when a new quarter is loaded.
--   CU_NCUA_CHARTER_STATE  each credit union's charter state on its most recent
--                          NCUA report (same procedure); CU_ORACLE_LIVE.CHARTER_STATE.
--   CU_TRADE_NAMES         hand-maintained trade names and nicknames (owner:
--                          Paul Ledin). Add rows with INSERT; see the examples.
--   CU_NAME_ALIASES        view combining the current NIMBLE name, NCUA names
--                          (current and former), website names, and trade names.
--                          The CU Oracle resolves credit union names through it.
--
-- Run as SYSADMIN. The ANALYTICS schema's future grants cover the tables and view;
-- the function needs its own USAGE grants (at the bottom).

CREATE OR REPLACE FUNCTION CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(NAME VARCHAR)
RETURNS VARCHAR
COMMENT = 'Normalizes a credit union name to a matching key (see cu_name_aliases.sql).'
AS
$$
    REPLACE(TRIM(
        REGEXP_REPLACE(
        REGEXP_REPLACE(
        REGEXP_REPLACE(
        REGEXP_REPLACE(
        REGEXP_REPLACE(
        REGEXP_REPLACE(
        REGEXP_REPLACE(
        REGEXP_REPLACE(
            REPLACE(REPLACE(LOWER(SPLIT_PART(NAME, '|', 1)), '''', ''), '&', ' and '),
            '[^a-z0-9 ]', ' '),
            '\\b(efcu|ecu|emp|empl|employee)\\b', 'employees'),
            '\\b(dept|depart)\\b', 'department'),
            '\\b1st\\b', 'first'),
            '\\b2nd\\b', 'second'),
            '\\b3rd\\b', 'third'),
            '\\b(federal credit union|credit union|fcu|cu)\\b', ' '),
            '\\s+', ' ')
    ), ' ', '')
$$;

CREATE OR REPLACE PROCEDURE CU_ORACLE_AGENT_DB.ANALYTICS.REFRESH_CU_NAME_HISTORY(
    FORCE BOOLEAN DEFAULT FALSE)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Rebuilds CU_NAME_HISTORY_NCUA from every NCUA_FINANCIALS_YYYYMM table (skips if already current unless FORCE).'
EXECUTE AS OWNER
AS
$$
DECLARE
    union_sql VARCHAR DEFAULT '';
    latest_period VARCHAR DEFAULT '';
    current_period VARCHAR DEFAULT NULL;
    n_tables NUMBER DEFAULT 0;
BEGIN
    SHOW TABLES LIKE 'NCUA_FINANCIALS_%' IN SCHEMA NCUA_DATA.FINANCIALS;
    LET rs RESULTSET := (
        SELECT "name" AS TBL
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE REGEXP_LIKE("name", '^NCUA_FINANCIALS_[0-9]{6}$')
        ORDER BY TBL);
    LET c1 CURSOR FOR rs;
    FOR r IN c1 DO
        latest_period := RIGHT(r.TBL, 6);
        union_sql := union_sql || IFF(n_tables = 0, '', ' UNION ALL ') ||
            'SELECT ''' || latest_period || ''' AS PERIOD, JOIN_NUMBER, CU_NAME, WEBSITE, CHARTERSTATE ' ||
            'FROM NCUA_DATA.FINANCIALS.' || r.TBL;
        n_tables := n_tables + 1;
    END FOR;

    IF (n_tables = 0) THEN
        RETURN 'No NCUA_FINANCIALS_YYYYMM tables found - nothing built.';
    END IF;

    IF (NOT FORCE) THEN
        BEGIN
            SELECT TO_CHAR(MAX(LAST_PERIOD), 'YYYYMM') INTO :current_period
            FROM CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_HISTORY_NCUA;
        EXCEPTION
            WHEN OTHER THEN current_period := NULL;
        END;
        IF (current_period = latest_period) THEN
            RETURN 'Already current through ' || latest_period || ' - not rebuilt.';
        END IF;
    END IF;

    EXECUTE IMMEDIATE 'CREATE OR REPLACE TEMPORARY TABLE CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_RAW AS ' || union_sql;

    CREATE OR REPLACE TABLE CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_HISTORY_NCUA
    COMMENT = 'Legal names and website names from every NCUA quarterly call report, with first and last quarter used. Built by REFRESH_CU_NAME_HISTORY.'
    AS
    WITH raw AS (
        SELECT
            TRY_TO_NUMBER(JOIN_NUMBER)            AS JOIN_NUMBER,
            LAST_DAY(TO_DATE(PERIOD, 'YYYYMM'))   AS PERIOD_DATE,
            NULLIF(TRIM(CU_NAME), '')             AS CU_NAME,
            -- second-level domain label: www.penfed.org -> penfed
            REGEXP_SUBSTR(
                REGEXP_SUBSTR(LOWER(TRIM(WEBSITE)), '^(https?://)?(www[0-9]?\\.)?([^/:?# ]+)', 1, 1, 'e', 3),
                '([a-z0-9-]+)\\.[a-z]{2,}$', 1, 1, 'e', 1) AS WEBSITE_NAME
        FROM CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_RAW
    )
    SELECT JOIN_NUMBER, 'NCUA name' AS ALIAS_SOURCE, CU_NAME AS VALUE,
           MIN(PERIOD_DATE) AS FIRST_PERIOD, MAX(PERIOD_DATE) AS LAST_PERIOD
    FROM raw WHERE JOIN_NUMBER IS NOT NULL AND CU_NAME IS NOT NULL
    GROUP BY 1, 2, 3
    UNION ALL
    SELECT JOIN_NUMBER, 'Website', WEBSITE_NAME, MIN(PERIOD_DATE), MAX(PERIOD_DATE)
    FROM raw WHERE JOIN_NUMBER IS NOT NULL AND LENGTH(WEBSITE_NAME) >= 3
    GROUP BY 1, 2, 3;

    -- Each credit union's charter state on its most recent report. INSERT OVERWRITE
    -- (not CREATE OR REPLACE) keeps the table object stable for the CU_ORACLE_LIVE
    -- dynamic table that joins to it.
    CREATE TABLE IF NOT EXISTS CU_ORACLE_AGENT_DB.ANALYTICS.CU_NCUA_CHARTER_STATE (
        JOIN_NUMBER NUMBER, CHARTER_STATE VARCHAR, AS_OF_PERIOD DATE)
        COMMENT = 'Charter state from each credit union''s most recent NCUA call report. Built by REFRESH_CU_NAME_HISTORY.';
    INSERT OVERWRITE INTO CU_ORACLE_AGENT_DB.ANALYTICS.CU_NCUA_CHARTER_STATE
    SELECT TRY_TO_NUMBER(JOIN_NUMBER), NULLIF(TRIM(CHARTERSTATE), ''), LAST_DAY(TO_DATE(PERIOD, 'YYYYMM'))
    FROM CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_RAW
    WHERE TRY_TO_NUMBER(JOIN_NUMBER) IS NOT NULL AND NULLIF(TRIM(CHARTERSTATE), '') IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY TRY_TO_NUMBER(JOIN_NUMBER) ORDER BY PERIOD DESC) = 1;

    DROP TABLE IF EXISTS CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_RAW;
    RETURN 'Rebuilt CU_NAME_HISTORY_NCUA and CU_NCUA_CHARTER_STATE through ' || latest_period || ' from ' || n_tables || ' quarterly tables.';
END;
$$;

-- Build the history now if it is missing or behind (the daily task keeps it current).
CALL CU_ORACLE_AGENT_DB.ANALYTICS.REFRESH_CU_NAME_HISTORY(FALSE);
-- (After changing what the procedure builds, run it once with TRUE to force a rebuild.)

-- Hand-maintained trade names and nicknames (owner: Paul Ledin). To add one:
--   INSERT INTO CU_ORACLE_AGENT_DB.ANALYTICS.CU_TRADE_NAMES (NIMBLE_CUNA_ID, TRADE_NAME, NOTE)
--   VALUES ('10031885', 'PenFed', 'Brand name of Pentagon FCU');
-- Changes show up in the CU Oracle immediately (CU_NAME_ALIASES is a view).
CREATE TABLE IF NOT EXISTS CU_ORACLE_AGENT_DB.ANALYTICS.CU_TRADE_NAMES (
    NIMBLE_CUNA_ID VARCHAR NOT NULL COMMENT 'America''s Credit Unions ID (ACUS ID) of the credit union',
    TRADE_NAME     VARCHAR NOT NULL COMMENT 'Trade name, brand, acronym, or nickname people use',
    NOTE           VARCHAR          COMMENT 'Optional context, e.g., source or why it is needed',
    ADDED_BY       VARCHAR DEFAULT CURRENT_USER(),
    ADDED_ON       DATE    DEFAULT CURRENT_DATE()
)
COMMENT = 'Hand-maintained credit union trade names and nicknames (owner: Paul Ledin). Feeds CU_NAME_ALIASES.';

-- Starter rows (re-runnable: only inserts names not already listed).
INSERT INTO CU_ORACLE_AGENT_DB.ANALYTICS.CU_TRADE_NAMES (NIMBLE_CUNA_ID, TRADE_NAME, NOTE)
SELECT s.id, s.tn, s.note
FROM (SELECT * FROM VALUES
        ('10031885', 'PenFed',       'Brand name of Pentagon FCU'),
        ('10013583', 'Navy Federal', 'Common name of Navy FCU'),
        ('10024904', 'SECU',         'State Employees'' Credit Union (North Carolina); not SECU Credit Union of Maryland')
     ) s(id, tn, note)
WHERE NOT EXISTS (SELECT 1 FROM CU_ORACLE_AGENT_DB.ANALYTICS.CU_TRADE_NAMES t
                  WHERE t.NIMBLE_CUNA_ID = s.id AND t.TRADE_NAME = s.tn);

CREATE OR REPLACE VIEW CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_ALIASES
COMMENT = 'Every name a credit union is known by: current NIMBLE name, NCUA legal names (current and former), website names, and hand-maintained trade names. Match on ALIAS_KEY.'
AS
WITH live AS (
    SELECT NIMBLE_CUNA_ID, JOIN_NUMBER, NAME FROM CU_ORACLE_AGENT_DB.ANALYTICS.CU_ORACLE_LIVE
),
-- website names shared by more than one credit union (e.g., hosted on a league
-- or vendor domain) can't identify a credit union
shared_websites AS (
    SELECT VALUE FROM CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_HISTORY_NCUA
    WHERE ALIAS_SOURCE = 'Website'
    GROUP BY VALUE HAVING COUNT(DISTINCT JOIN_NUMBER) > 1
),
ncua AS (
    SELECT l.NIMBLE_CUNA_ID, h.ALIAS_SOURCE, h.VALUE, h.FIRST_PERIOD, h.LAST_PERIOD,
           MAX(h.LAST_PERIOD) OVER (PARTITION BY h.JOIN_NUMBER) AS LAST_REPORT
    FROM CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_HISTORY_NCUA h
    JOIN live l ON l.JOIN_NUMBER = h.JOIN_NUMBER
    WHERE NOT (h.ALIAS_SOURCE = 'Website' AND h.VALUE IN (SELECT VALUE FROM shared_websites))
),
aliases AS (
    SELECT NIMBLE_CUNA_ID, TRIM(SPLIT_PART(NAME, '|', 1)) AS ALIAS, 'Current name' AS ALIAS_TYPE,
           NULL::DATE AS FIRST_PERIOD, NULL::DATE AS LAST_PERIOD
    FROM live WHERE NAME IS NOT NULL
    UNION ALL
    SELECT NIMBLE_CUNA_ID, VALUE,
           CASE WHEN ALIAS_SOURCE = 'Website' THEN 'Website name'
                WHEN LAST_PERIOD < LAST_REPORT THEN 'Former NCUA name'
                ELSE 'NCUA name' END,
           FIRST_PERIOD, LAST_PERIOD
    FROM ncua
    UNION ALL
    SELECT NIMBLE_CUNA_ID, TRADE_NAME, 'Trade name', NULL, NULL
    FROM CU_ORACLE_AGENT_DB.ANALYTICS.CU_TRADE_NAMES
)
SELECT NIMBLE_CUNA_ID, ALIAS,
       CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(ALIAS) AS ALIAS_KEY,
       ALIAS_TYPE, FIRST_PERIOD, LAST_PERIOD
FROM aliases
WHERE CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(ALIAS) <> '';

GRANT USAGE ON FUNCTION CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(VARCHAR) TO ROLE CU_ORACLE_APP_READ;
GRANT USAGE ON FUNCTION CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(VARCHAR) TO ROLE CLAUDE;
