-- CU_ORACLE_SEMANTIC: the only data source the CU Oracle's Cortex Agent can use.
-- 2026-10-08: CURRENT_NCUA_FINANCIALS_FILE (latest quarter only) replaced by
-- NCUA_FINANCIALS_HISTORY (one row per credit union per quarter, five years).
-- Run as SYSADMIN. The view name is a placeholder so it can be built under a
-- test name first: replace {{VIEW_NAME}} before running.

create or replace semantic view CU_ORACLE_AGENT_DB.ANALYTICS.{{VIEW_NAME}}
	tables (
		CU_ORACLE_AGENT_DB.ANALYTICS.CURRENT_NCUA_BRANCH_FILE comment='The table contains records of credit union branch locations as reported to the NCUA. Each record represents a single branch site and includes details about the site type, physical address, contact information, and available member services such as ATM and drive-through access.',
		CU_ORACLE_AGENT_DB.ANALYTICS.CU_ORACLE_LIVE primary key (NIMBLE_CUNA_ID) unique (JOIN_NUMBER) comment='The table contains records of all US credit unions ever known to America''s Credit Unions (formally CUNA and NAFCU) and recorded in their Association Management Software (AMS). Specifically it includes their organizational and contact information. Each record represents a single credit union and includes details about its location, financial condition, leadership, and affiliations.',
		CU_ORACLE_AGENT_DB.ANALYTICS.NCUA_FINANCIALS_HISTORY primary key (JOIN_NUMBER, PERIOD_DATE) comment='Quarterly NCUA 5300 call report financials for every credit union, one row per credit union per quarter, covering the latest five years. Use for current financials (filter IS_LATEST_PERIOD), time series, trends, growth rates, and multi-period ratios. Balance amounts are as of the quarter end; never add them up across quarters.'
	)
	relationships (
		CURRENT_NCUA_BRANCH_FILE_TO_CU_ORACLE_LIVE as CURRENT_NCUA_BRANCH_FILE(JOIN_NUMBER) references CU_ORACLE_LIVE(JOIN_NUMBER),
		NCUA_FINANCIALS_HISTORY_TO_CU_ORACLE_LIVE as NCUA_FINANCIALS_HISTORY(JOIN_NUMBER) references CU_ORACLE_LIVE(JOIN_NUMBER)
	)
	facts (
		CURRENT_NCUA_BRANCH_FILE.FCHT as FCHT comment='The National Credit Union Administration (NCUA) assigned federal charter number. FCHT < 60000 = Federally Chartered and Federally Insured, 60000-80000 = State Chartered Federally Insured, > 80000 = State Chartered, Privately Insured.' sample_values ('6', '1815', '3202'),
		CURRENT_NCUA_BRANCH_FILE.JOIN_NUMBER as JOIN_NUMBER comment='The National Credit Union Administration (NCUA) assigned unique ID for joining NCUA call report data across time periods.' sample_values ('7', '11', '2'),
		CU_ORACLE_LIVE.ACTIVE_CU_WITH_CHARTER labels = (filter) as NOT fcht IS NULL AND status = 'A' comment='Filters for credit unions that are currently active (status = ''A'') and have a valid NCUA federal charter number (fcht is not null). Use when questions ask about ''active credit unions'', ''how many active credit unions are there'', or require counting/analyzing credit unions that are both operational and have an NCUA charter on record. Helps ensure analysis focuses on currently operating, federally recognized credit unions.',
		CU_ORACLE_LIVE.FCHT as FCHT comment='The National Credit Union Administration (NCUA) assigned federal charter number. FCHT < 60000 = Federally Chartered and Federally Insured, 60000-80000 = State Chartered Federally Insured, > 80000 = State Chartered, Privately Insured.' sample_values ('2275', '884', '22530'),
		CU_ORACLE_LIVE.JOIN_NUMBER as JOIN_NUMBER comment='The National Credit Union Administration (NCUA) assigned unique ID for joining NCUA call report data across time periods.' sample_values ('9531', '20759', '537'),
		CU_ORACLE_LIVE.LAST_REPORTED_ASSETS as LAST_REPORTED_ASSETS comment='The credit union''s most recently National Credit Union Administration (NCUA) reported total assets, account code 010.' sample_values ('4604340', '229977718', '175586733'),
		CU_ORACLE_LIVE.LAST_REPORTED_MEMBERS as LAST_REPORTED_MEMBERS comment='The credit union''s most recently National Credit Union Administration (NCUA) member count, account code 083.' sample_values ('3602', '3489', '5801'),
		NCUA_FINANCIALS_HISTORY.LATEST_PERIOD labels = (filter) as is_latest_period comment='Filters to the most recent quarter of NCUA financial data. Apply whenever a question asks for current, latest, or most recent financials, or does not mention a time period, trend, or growth.',
		NCUA_FINANCIALS_HISTORY.JOIN_NUMBER as JOIN_NUMBER comment='The NCUA assigned unique ID for joining NCUA call report data across time periods.',
		NCUA_FINANCIALS_HISTORY.CHARTER_NUMBER as CHARTER_NUMBER comment='The NCUA charter number (same as FCHT) as reported for this quarter.',
		NCUA_FINANCIALS_HISTORY.YEAR as YEAR comment='Calendar year of the quarter end.',
		NCUA_FINANCIALS_HISTORY.QUARTER as QUARTER comment='Calendar quarter of the quarter end, 1-4. Quarter 4 is the year-end (December) report.',
		NCUA_FINANCIALS_HISTORY.MEMBERS as MEMBERS comment='Number of members at quarter end.',
		NCUA_FINANCIALS_HISTORY.TOTAL_ASSETS as TOTAL_ASSETS comment='Total assets in dollars at quarter end.',
		NCUA_FINANCIALS_HISTORY.AMT_TOTAL_SHARES_AND_DEPOSITS as AMT_TOTAL_SHARES_AND_DEPOSITS comment='Total shares and deposits (member and nonmember savings) in dollars at quarter end.',
		NCUA_FINANCIALS_HISTORY.NET_WORTH as NET_WORTH comment='Net worth (capital) in dollars at quarter end, as defined for NCUA prompt corrective action.',
		NCUA_FINANCIALS_HISTORY.AMT_TOTAL_LOANS as AMT_TOTAL_LOANS comment='Total loans and leases in dollars at quarter end.',
		NCUA_FINANCIALS_HISTORY.AMT_TOTAL_DELQ_LOANS as AMT_TOTAL_DELQ_LOANS comment='Total delinquent loans in dollars at quarter end.',
		NCUA_FINANCIALS_HISTORY.AMT_MEMBER_BUSINESS_LOANS as AMT_MEMBER_BUSINESS_LOANS comment='Total member business loans in dollars at quarter end.',
		NCUA_FINANCIALS_HISTORY.FULL_TIME_EMPLOYEES as FULL_TIME_EMPLOYEES comment='Number of full-time employees at quarter end.',
		NCUA_FINANCIALS_HISTORY.PART_TIME_EMPLOYEES as PART_TIME_EMPLOYEES comment='Number of part-time employees at quarter end.',
		NCUA_FINANCIALS_HISTORY.NET_INCOME_YTD as NET_INCOME_YTD comment='Net income year-to-date in dollars, as reported (cumulative from January 1 through the quarter end).',
		NCUA_FINANCIALS_HISTORY.NET_INCOME_QTR as NET_INCOME_QTR comment='Net income earned in that quarter alone, in dollars.',
		NCUA_FINANCIALS_HISTORY.NET_INCOME_ANNUALIZED as NET_INCOME_ANNUALIZED comment='Year-to-date net income annualized (YTD x 4 / quarter), in dollars. Use to compare income across quarters.',
		NCUA_FINANCIALS_HISTORY.NET_CHARGEOFFS_YTD as NET_CHARGEOFFS_YTD comment='Net loan charge-offs year-to-date in dollars, as reported.',
		NCUA_FINANCIALS_HISTORY.NET_CHARGEOFFS_QTR as NET_CHARGEOFFS_QTR comment='Net loan charge-offs in that quarter alone, in dollars.',
		NCUA_FINANCIALS_HISTORY.NET_CHARGEOFFS_ANNUALIZED as NET_CHARGEOFFS_ANNUALIZED comment='Year-to-date net charge-offs annualized (YTD x 4 / quarter), in dollars.',
		NCUA_FINANCIALS_HISTORY.AVG_ASSETS_YTD as AVG_ASSETS_YTD comment='Average of quarter-end and prior year-end total assets; denominator for return on assets.',
		NCUA_FINANCIALS_HISTORY.AVG_LOANS_YTD as AVG_LOANS_YTD comment='Average of quarter-end and prior year-end total loans; denominator for the net charge-off rate.',
		NCUA_FINANCIALS_HISTORY.NET_WORTH_RATIO_PCT as NET_WORTH_RATIO_PCT comment='Net worth as a percent of total assets for one credit union.',
		NCUA_FINANCIALS_HISTORY.LOAN_TO_SHARE_PCT as LOAN_TO_SHARE_PCT comment='Total loans as a percent of total shares and deposits for one credit union.',
		NCUA_FINANCIALS_HISTORY.DELINQUENCY_RATE_PCT as DELINQUENCY_RATE_PCT comment='Delinquent loans as a percent of total loans for one credit union.',
		NCUA_FINANCIALS_HISTORY.ROA_PCT as ROA_PCT comment='Return on assets for one credit union: annualized net income as a percent of average assets.',
		NCUA_FINANCIALS_HISTORY.NET_CHARGEOFF_RATE_PCT as NET_CHARGEOFF_RATE_PCT comment='Annualized net charge-offs as a percent of average loans for one credit union.',
		NCUA_FINANCIALS_HISTORY.ASSETS_YOY_GROWTH_PCT as ASSETS_YOY_GROWTH_PCT comment='Percent change in total assets from the same quarter one year earlier. Growth can include assets acquired through mergers.',
		NCUA_FINANCIALS_HISTORY.LOANS_YOY_GROWTH_PCT as LOANS_YOY_GROWTH_PCT comment='Percent change in total loans from the same quarter one year earlier.',
		NCUA_FINANCIALS_HISTORY.SHARES_YOY_GROWTH_PCT as SHARES_YOY_GROWTH_PCT comment='Percent change in total shares and deposits from the same quarter one year earlier.',
		NCUA_FINANCIALS_HISTORY.MEMBERS_YOY_GROWTH_PCT as MEMBERS_YOY_GROWTH_PCT comment='Percent change in members from the same quarter one year earlier.',
		NCUA_FINANCIALS_HISTORY.NET_WORTH_YOY_GROWTH_PCT as NET_WORTH_YOY_GROWTH_PCT comment='Percent change in net worth from the same quarter one year earlier.'
	)
	dimensions (
		CURRENT_NCUA_BRANCH_FILE.ATM as ATM comment='Indicates whether an automated teller machine (ATM) is present at the branch location.' sample_values ('No', 'Yes'),
		CURRENT_NCUA_BRANCH_FILE.DRIVETHRU as DRIVETHRU comment='Indicates whether the branch has a drive-through facility.' sample_values ('Yes', 'No'),
		CURRENT_NCUA_BRANCH_FILE.HOURSOFOPERATION as HOURSOFOPERATION comment='The hours of operation for the branch location.' sample_values ('MONDAY - FRIDAY, 8:00 AM - 5:00 PM'),
		CURRENT_NCUA_BRANCH_FILE.MAINOFFICE as MAINOFFICE comment='Indicates whether the branch location is the main office of the credit union.' sample_values ('Yes', 'No'),
		CURRENT_NCUA_BRANCH_FILE.MEMBERSERVICES as MEMBERSERVICES comment='Indicates whether member services are offered at the branch location.' sample_values ('Yes', 'No'),
		CURRENT_NCUA_BRANCH_FILE.PHYSICALADDRESSCITY as PHYSICALADDRESSCITY comment='The city component of the physical address.' sample_values ('Atlanta', 'LYNCHBURG', 'Slidell'),
		CURRENT_NCUA_BRANCH_FILE.PHYSICALADDRESSLINE1 as PHYSICALADDRESSLINE1 comment='The primary line of the physical street address.' sample_values ('205 Arkansas Ave', '1901 Highway 3125', '763 Main St'),
		CURRENT_NCUA_BRANCH_FILE.PHYSICALADDRESSLINE2 as PHYSICALADDRESSLINE2 comment='The second line of a physical address, typically used for suite, room, or unit information.' sample_values ('Price Chopper Plaza', 'Suite F'),
		CURRENT_NCUA_BRANCH_FILE.PHYSICALADDRESSPOSTALCODE as PHYSICALADDRESSPOSTALCODE comment='The postal code associated with the physical address of the branch location.' sample_values ('06705', '70071-5633', '70427'),
		CURRENT_NCUA_BRANCH_FILE.PHYSICALADDRESSSTATECODE as PHYSICALADDRESSSTATECODE comment='The two-letter state code associated with the physical address of the branch.' sample_values ('MS', 'LA', 'IA'),
		CURRENT_NCUA_BRANCH_FILE.SITENAME as SITENAME comment='The name of the credit union branch or site location.' sample_values ('MORRIS SHEPPARD TEXARKANA FCU', 'New Haven Teachers FCU Main Office', 'RED RIVER FCU'),
		CURRENT_NCUA_BRANCH_FILE.SITETYPENAME as SITETYPENAME comment='The name of the site type classification for a branch location.' sample_values ('Corporate Office', 'Branch Office'),
		CU_ORACLE_LIVE.AFL as AFL comment='Affiliation status of the credit union. A=Affiliated, N=Not Affiliated.' sample_values ('N', 'A'),
		CU_ORACLE_LIVE.CEO_FULL_NAME as CEO_FULL_NAME comment='The full name of the chief executive officer.' sample_values ('Steven Shaffner', 'Pamela Goodman', 'Patrick Gallagher'),
		CU_ORACLE_LIVE.LAST_PERIOD_REPORTED as LAST_PERIOD_REPORTED comment='The date of the last period for which the credit union has submitted 5300 Call Report data to the National Credit Union Administration (NCUA).' sample_values ('2025-12-31', '2025-06-30', '2012-09-30'),
		CU_ORACLE_LIVE.LEAGUE_AFFILIATED as LEAGUE_AFFILIATED comment='The state league affiliation of the credit union. A=League Affiliated, N=Not League Affiliated.' sample_values ('United States', 'Panama'),
		CU_ORACLE_LIVE.LEAGUE_NAME as LEAGUE_NAME comment='The name of the state credit union league which the credit union belongs to, or would belong to if they were affiliated.' sample_values ('Tennessee League and Mississippi Credit Union Association', 'Illinois Credit Union League', 'CrossState Credit Union Association'),
		CU_ORACLE_LIVE.NAME as NAME comment='The name of a credit union.' sample_values ('St Mark CU', 'Great Neck School EFCU', 'Molokai Community FCU'),
		CU_ORACLE_LIVE.NIMBLE_CUNA_ID as NIMBLE_CUNA_ID comment='A unique identifier assigned by America''s Credit Unions (ACUs), formally known as the CUNA ID or CUID.' sample_values ('10027773', '10018610', '10024555'),
		CU_ORACLE_LIVE.ORG_DATE as ORG_DATE comment='The date the credit union was organized.' sample_values ('1965-11-30', '1935-09-01', '1945-12-07'),
		CU_ORACLE_LIVE.PHONE as PHONE comment='The credit union''s main/general purpose telephone number.' sample_values ('2034027400', '3525882732', '5855911055'),
		CU_ORACLE_LIVE.PO_ADDRESS as PO_ADDRESS comment='The mailing address of the credit union.' sample_values ('221 Main St', 'PO Box 2028', '4400 Maplewood Dr'),
		CU_ORACLE_LIVE.PO_CITY as PO_CITY comment='The city of the mailing address of the credit union.' sample_values ('Chicago', 'Santa Ana', 'Rochester'),
		CU_ORACLE_LIVE.PO_STATE as PO_STATE comment='The two-letter state abbreviation of the mailing address of the credit union.' sample_values ('NY', 'IL', 'PA'),
		CU_ORACLE_LIVE.PO_ZIP_CODE as PO_ZIP_CODE comment='The postal zip code of the mailing address of the credit union.' sample_values ('60619-1827', '14624-4537', '11354-3143'),
		CU_ORACLE_LIVE.ST_ADDRESS as ST_ADDRESS comment='The physical/street address of the credit union.' sample_values ('2998 Chili Ave', '2514 N Main St', '15 Vanderbilt Ave Ste D41'),
		CU_ORACLE_LIVE.ST_CITY as ST_CITY comment='The city of the physical/street address of the credit union.' sample_values ('Rochester', 'Boulder', 'Fort Wayne'),
		CU_ORACLE_LIVE.ST_STATE as ST_STATE comment='The two-letter state abbreviation of the physical/mailing address of the credit union.' sample_values ('NY', 'PA', 'IL'),
		CU_ORACLE_LIVE.ST_ZIP_CODE as ST_ZIP_CODE comment='The postal zip code of the physical/street address of the credit union.' sample_values ('12110-1007', '14624-4537', '92705-4934'),
		CU_ORACLE_LIVE.STATUS as STATUS comment='The current status of the credit union in America''s Credit Union''s records. A=Active, P=Pending Merger/Liquidation, M=Merged, I=Inactive' sample_values ('M', 'P', 'A'),
		CU_ORACLE_LIVE.STATUS_CHG_DATE as STATUS_CHG_DATE comment='The date on which the status was last changed.' sample_values ('1949-07-11', '1950-12-08', '1953-11-20'),
		CU_ORACLE_LIVE.TOM_CODE as TOM_CODE comment='Type of Membership (TOM) code, also known as Field of Membership (FOM) code.' sample_values ('00', '01', '36'),
		CU_ORACLE_LIVE.WEB as WEB comment='The website of the credit union.' sample_values ('www.lmhospcu.com', 'www.educationpersonnelfcu.com', 'www.greatplainsfcu.com'),
		NCUA_FINANCIALS_HISTORY.PERIOD_DATE as PERIOD_DATE comment='Quarter-end date of the NCUA call report (March 31, June 30, September 30, or December 31). Use for time series and trends.',
		NCUA_FINANCIALS_HISTORY.PERIOD as PERIOD comment='Quarter of the NCUA call report as YYYYMM text, e.g. 202606 for June 2026.' sample_values ('202606', '202512', '202306'),
		NCUA_FINANCIALS_HISTORY.IS_LATEST_PERIOD as IS_LATEST_PERIOD comment='TRUE for rows in the most recent quarter available.',
		NCUA_FINANCIALS_HISTORY.CHARTERSTATE as CHARTERSTATE comment='The state in which the credit union charter was issued.' sample_values ('LA', 'TX', 'CT'),
		NCUA_FINANCIALS_HISTORY.NIMBLE_CUNA_ID as NIMBLE_CUNA_ID comment='America''s Credit Unions identifier for the credit union (CUNA ID).' sample_values ('10018582', '10013786', '10028304')
	)
	metrics (
		CU_ORACLE_LIVE.NUM_CREDIT_UNIONS as COUNT(nimble_cuna_id) comment='Calculates the total count of credit unions by counting records using the unique identifier (nimble_cuna_id). Use when questions ask about ''how many credit unions'', ''number of credit unions'', ''count of credit unions'', ''active credit union count'', or ''total credit unions''. Commonly used with a filter on status = ''A'' to count only active credit unions, or with other filters (e.g., by state, league, charter type) to count credit unions within a specific segment. Helps answer questions about the size and distribution of the credit union landscape tracked by America''s Credit Unions.',
		NCUA_FINANCIALS_HISTORY.AGG_NET_WORTH_RATIO_PCT as SUM(net_worth) / NULLIF(SUM(total_assets), 0) * 100 comment='Aggregate net worth ratio for a group of credit unions (sum of net worth over sum of assets, percent). Use for industry, state, or peer-group net worth ratios in a given quarter.',
		NCUA_FINANCIALS_HISTORY.AGG_LOAN_TO_SHARE_PCT as SUM(amt_total_loans) / NULLIF(SUM(amt_total_shares_and_deposits), 0) * 100 comment='Aggregate loan-to-share ratio for a group of credit unions, percent.',
		NCUA_FINANCIALS_HISTORY.AGG_DELINQUENCY_RATE_PCT as SUM(amt_total_delq_loans) / NULLIF(SUM(amt_total_loans), 0) * 100 comment='Aggregate delinquency rate for a group of credit unions (delinquent loans over total loans, percent).',
		NCUA_FINANCIALS_HISTORY.AGG_ROA_PCT as SUM(net_income_annualized) / NULLIF(SUM(avg_assets_ytd), 0) * 100 comment='Aggregate return on assets for a group of credit unions (annualized net income over average assets, percent).',
		NCUA_FINANCIALS_HISTORY.AGG_NET_CHARGEOFF_RATE_PCT as SUM(net_chargeoffs_annualized) / NULLIF(SUM(avg_loans_ytd), 0) * 100 comment='Aggregate net charge-off rate for a group of credit unions (annualized net charge-offs over average loans, percent).'
	)
	ai_sql_generation 'Never include the words: Credit Union, Federal Credit Union, CU, or FCU in a name search. Always use wildcards for name searches.
NCUA_FINANCIALS_HISTORY has one row per credit union per quarter. Unless the question asks about a specific past period, a trend, a change over time, or growth, filter it to IS_LATEST_PERIOD = TRUE. Never sum balance amounts (assets, loans, shares, net worth, members, employees) across quarters; for totals over time, group by PERIOD_DATE.
Net income and net charge-offs are reported year-to-date: use the _QTR columns for a single quarter, the _ANNUALIZED columns to compare quarters, and the year-end (QUARTER = 4) _YTD value for a full calendar year.
For one credit union, use the _PCT ratio and growth columns. For a group, state, or the whole industry, use the AGG_ metrics (sum of numerators over sum of denominators); never average individual credit unions'' ratios.
For growth over several years, compare the same quarter in each year (for example June 2021 to June 2026) and compute compound annual growth when asked for an annual rate. Always state which quarter-end dates the figures cover.'
	ai_question_categorization 'Dismissively reject any questions about commercial banks as unworthy of the CU Oracle''s compute tokens. '
	ai_verified_queries (
		"Who is the CEO of Heartland Credit Union in Madison Wisconsin?" AS (
QUESTION 'Who is the CEO of Heartland Credit Union in Madison Wisconsin?'
VERIFIED_AT 1780603689
VERIFIED_BY 'Paul Ledin'
ONBOARDING_QUESTION true
SQL 'SELECT
  name,
  ceo_full_name,
  st_city,
  st_state
FROM
  cu_oracle_live
WHERE
  LOWER(name) LIKE ''%heartland%''
  AND LOWER(st_city) = ''madison''
  AND LOWER(st_state) = ''wi''
  AND status = ''A'''),
		"How many active credit unions are there in the US today?" AS (
QUESTION 'How many active credit unions are there in the US today?'
VERIFIED_AT 1780604241
VERIFIED_BY 'Paul Ledin'
ONBOARDING_QUESTION true
SQL 'SELECT
  COUNT(nimble_cuna_id) AS active_credit_union_count
FROM
  cu_oracle_live
WHERE
  status = ''A''
  AND fcht IS NOT NULL'),
		"What is the oldest credit union in the country?" AS (
QUESTION 'What is the oldest credit union in the country?'
VERIFIED_AT 1780677164
VERIFIED_BY 'Paul Ledin'
ONBOARDING_QUESTION false
SQL 'SELECT
  nimble_cuna_id,
  name,
  org_date,
  st_state,
  po_state,
  last_reported_assets,
  last_reported_members,
  status
FROM
  cu_oracle_live
WHERE
  NOT org_date IS NULL
ORDER BY
  org_date ASC
LIMIT
  1'),
		"How many credit unions are affiliated with the Wisconsin League?" AS (
QUESTION 'How many credit unions are affiliated with the Wisconsin League?'
VERIFIED_AT 1780678126
VERIFIED_BY 'Paul Ledin'
ONBOARDING_QUESTION false
SQL 'SELECT
  COUNT(nimble_cuna_id) AS credit_union_count
FROM
  cu_oracle_live
WHERE
  LOWER(league_name) LIKE ''%wisconsin%'''),
		"What's the date of the current NCUA branch data?" AS (
QUESTION 'What''s the date of the current NCUA branch data?'
VERIFIED_AT 1788537653
VERIFIED_BY 'Paul Ledin'
ONBOARDING_QUESTION false
SQL 'SELECT
  MAX(col.last_period_reported) AS latest_ncua_branch_data_date
FROM
  current_ncua_branch_file AS br
  LEFT OUTER JOIN cu_oracle_live AS col ON br.join_number = col.join_number'),
		"What is the credit union industry's net worth ratio?" AS (
QUESTION 'What is the credit union industry''s net worth ratio?'
VERIFIED_AT 1791504000
VERIFIED_BY 'Claude Code (for Paul Ledin)'
ONBOARDING_QUESTION false
SQL 'SELECT
  period_date,
  SUM(net_worth) / NULLIF(SUM(total_assets), 0) * 100 AS net_worth_ratio_pct
FROM
  ncua_financials_history
WHERE
  is_latest_period
GROUP BY
  period_date'),
		"How have total credit union assets changed over the last five years?" AS (
QUESTION 'How have total credit union assets changed over the last five years?'
VERIFIED_AT 1791504000
VERIFIED_BY 'Claude Code (for Paul Ledin)'
ONBOARDING_QUESTION false
SQL 'SELECT
  period_date,
  SUM(total_assets) AS total_assets
FROM
  ncua_financials_history
GROUP BY
  period_date
ORDER BY
  period_date'),
		"Show Heartland Credit Union in Madison Wisconsin's assets and members by quarter" AS (
QUESTION 'Show Heartland Credit Union in Madison Wisconsin''s assets and members by quarter'
VERIFIED_AT 1791504000
VERIFIED_BY 'Claude Code (for Paul Ledin)'
ONBOARDING_QUESTION false
SQL 'SELECT
  h.period_date,
  h.total_assets,
  h.members,
  h.assets_yoy_growth_pct,
  h.members_yoy_growth_pct
FROM
  ncua_financials_history AS h
  JOIN cu_oracle_live AS col ON h.join_number = col.join_number
WHERE
  LOWER(col.name) LIKE ''%heartland%''
  AND LOWER(col.st_city) = ''madison''
  AND LOWER(col.st_state) = ''wi''
ORDER BY
  h.period_date')
	);
