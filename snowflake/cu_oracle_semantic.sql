-- CU_ORACLE_SEMANTIC: the only data source the CU Oracle's Cortex Agent can use.
-- 2026-10-08: CURRENT_NCUA_FINANCIALS_FILE (latest quarter only) replaced by
-- NCUA_FINANCIALS_HISTORY (one row per credit union per quarter, five years).
-- 2026-10-08: merger flags, acquired balances, and organic growth columns added.
-- 2026-10-15: clarified LAST_REPORTED_ fields (any credit union back to 1994) vs
-- NCUA_FINANCIALS_HISTORY (latest five years), with a routing rule and example.
-- 2026-10-15: SURVIVOR_ and CURRENT_SUCCESSOR_ merger fields on CU_ORACLE_LIVE.
-- 2026-10-15: CU_NAME_ALIASES for name matching (see cu_name_aliases.sql);
-- STATUS C = Conservatorship.
-- 2026-10-15: default universe for aggregates = all credit unions that filed the
-- latest call report (any status); affiliation questions = status A or P.
-- 2026-10-15: state = charter state (CHARTERSTATE / CHARTER_STATE); employee
-- questions report total and FTE (TOTAL_EMPLOYEES, FTE_EMPLOYEES).
-- Run as SYSADMIN. The view name is a placeholder so it can be built under a
-- test name first: replace {{VIEW_NAME}} before running.

create or replace semantic view CU_ORACLE_AGENT_DB.ANALYTICS.{{VIEW_NAME}}
	tables (
		CU_ORACLE_AGENT_DB.ANALYTICS.CURRENT_NCUA_BRANCH_FILE comment='The table contains records of credit union branch locations as reported to the NCUA. Each record represents a single branch site and includes details about the site type, physical address, contact information, and available member services such as ATM and drive-through access.',
		CU_ORACLE_AGENT_DB.ANALYTICS.CU_ORACLE_LIVE primary key (NIMBLE_CUNA_ID) unique (JOIN_NUMBER) comment='The table contains records of all US credit unions ever known to America''s Credit Unions (formally CUNA and NAFCU) and recorded in their Association Management Software (AMS). Specifically it includes their organizational and contact information. Each record represents a single credit union and includes details about its location, financial condition, leadership, and affiliations.',
		CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_ALIASES comment='Every name a credit union is or was known by, one row per name: its current name, NCUA legal names (current and former, with the quarters used), website names (e.g. penfed for Pentagon FCU), and hand-maintained trade names (e.g. PenFed, Navy Federal, SECU). Use it to find credit unions by name, then join to CU_ORACLE_LIVE on NIMBLE_CUNA_ID.',
		CU_ORACLE_AGENT_DB.ANALYTICS.NCUA_FINANCIALS_HISTORY primary key (JOIN_NUMBER, PERIOD_DATE) comment='Quarterly NCUA 5300 call report financials, one row per credit union per quarter, covering only the latest five years. Credit unions that merged, liquidated, or stopped reporting before that window are not in this table; use CU_ORACLE_LIVE.LAST_REPORTED_ fields for them. Use for current financials (filter IS_LATEST_PERIOD), time series, trends, growth rates, and multi-period ratios. Balance amounts are as of the quarter end; never add them up across quarters.'
	)
	relationships (
		CURRENT_NCUA_BRANCH_FILE_TO_CU_ORACLE_LIVE as CURRENT_NCUA_BRANCH_FILE(JOIN_NUMBER) references CU_ORACLE_LIVE(JOIN_NUMBER),
		NCUA_FINANCIALS_HISTORY_TO_CU_ORACLE_LIVE as NCUA_FINANCIALS_HISTORY(JOIN_NUMBER) references CU_ORACLE_LIVE(JOIN_NUMBER),
		CU_NAME_ALIASES_TO_CU_ORACLE_LIVE as CU_NAME_ALIASES(NIMBLE_CUNA_ID) references CU_ORACLE_LIVE(NIMBLE_CUNA_ID)
	)
	facts (
		CURRENT_NCUA_BRANCH_FILE.FCHT as FCHT comment='The National Credit Union Administration (NCUA) assigned federal charter number. FCHT < 60000 = Federally Chartered and Federally Insured, 60000-80000 = State Chartered Federally Insured, > 80000 = State Chartered, Privately Insured.' sample_values ('6', '1815', '3202'),
		CURRENT_NCUA_BRANCH_FILE.JOIN_NUMBER as JOIN_NUMBER comment='The National Credit Union Administration (NCUA) assigned unique ID for joining NCUA call report data across time periods.' sample_values ('7', '11', '2'),
		CU_ORACLE_LIVE.ACTIVE_CU_WITH_CHARTER labels = (filter) as NOT fcht IS NULL AND status = 'A' comment='Credit unions whose status in America''s Credit Unions'' records is Active (status = ''A'') and that have an NCUA charter number. Use ONLY when the user explicitly asks about active credit unions or about status. It is not the default for counts or totals: those use all credit unions that filed the most recent call report (NCUA_FINANCIALS_HISTORY LATEST_PERIOD), and affiliation questions use ACTIVE_OR_PENDING.',
		CU_ORACLE_LIVE.ACTIVE_OR_PENDING labels = (filter) as status IN ('A', 'P') comment='Credit unions whose status is Active or Pending (merger or liquidation pending). The default universe for ANY question involving affiliation, with America''s Credit Unions (AFL) or with a state league (LEAGUE_AFFILIATED), e.g. how many credit unions are affiliated with America''s Credit Unions.',
		CU_ORACLE_LIVE.FCHT as FCHT comment='The National Credit Union Administration (NCUA) assigned federal charter number. FCHT < 60000 = Federally Chartered and Federally Insured, 60000-80000 = State Chartered Federally Insured, > 80000 = State Chartered, Privately Insured.' sample_values ('2275', '884', '22530'),
		CU_ORACLE_LIVE.JOIN_NUMBER as JOIN_NUMBER comment='The National Credit Union Administration (NCUA) assigned unique ID for joining NCUA call report data across time periods.' sample_values ('9531', '20759', '537'),
		CU_ORACLE_LIVE.LAST_REPORTED_ASSETS as LAST_REPORTED_ASSETS comment='Total assets in dollars (NCUA account code 010) from the credit union''s final or most recent NCUA call report, dated LAST_PERIOD_REPORTED. Available for any credit union that ever reported, back to 1994, including merged, liquidated, and inactive credit unions. The one source of assets for credit unions not in NCUA_FINANCIALS_HISTORY; for active credit unions it equals the latest quarter in NCUA_FINANCIALS_HISTORY.' sample_values ('4604340', '229977718', '175586733'),
		CU_ORACLE_LIVE.LAST_REPORTED_MEMBERS as LAST_REPORTED_MEMBERS comment='Members (NCUA account code 083) from the credit union''s final or most recent NCUA call report, dated LAST_PERIOD_REPORTED. Available for any credit union that ever reported, back to 1994, including merged, liquidated, and inactive credit unions. The one source of member counts for credit unions not in NCUA_FINANCIALS_HISTORY.' sample_values ('3602', '3489', '5801'),
		CU_ORACLE_LIVE.BRANCHES as BRANCHES comment='Number of offices, including the main office, as recorded by America''s Credit Unions: current for active credit unions, and as of the last record for merged, liquidated, or inactive ones. Use for how many branches or offices a credit union (or a group of credit unions) has.' sample_values ('1', '11', '388'),
		NCUA_FINANCIALS_HISTORY.LATEST_PERIOD labels = (filter) as is_latest_period comment='Filters to the most recent quarter of NCUA financial data. Apply whenever a question asks for current, latest, or most recent figures, or does not mention a time period, trend, or growth. Credit unions in this quarter (every credit union that filed the latest call report, whatever its status) are the default universe for counts, totals, and other aggregates across credit unions.',
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
		NCUA_FINANCIALS_HISTORY.TOTAL_EMPLOYEES as TOTAL_EMPLOYEES comment='Total employee headcount at quarter end: full-time plus part-time employees.',
		NCUA_FINANCIALS_HISTORY.FTE_EMPLOYEES as FTE_EMPLOYEES comment='Full-time equivalent (FTE) employees at quarter end: full-time employees plus half of part-time employees (NCUA convention).',
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
		NCUA_FINANCIALS_HISTORY.NET_WORTH_YOY_GROWTH_PCT as NET_WORTH_YOY_GROWTH_PCT comment='Percent change in net worth from the same quarter one year earlier.',
		NCUA_FINANCIALS_HISTORY.MERGERS_IN_QUARTER as MERGERS_IN_QUARTER comment='Number of credit unions merged into this credit union during this quarter.',
		NCUA_FINANCIALS_HISTORY.MERGERS_PRIOR_YEAR as MERGERS_PRIOR_YEAR comment='Number of credit unions merged into this credit union in the 12 months ending at this quarter end.',
		NCUA_FINANCIALS_HISTORY.ACQUIRED_ASSETS_PRIOR_YEAR as ACQUIRED_ASSETS_PRIOR_YEAR comment='Total assets, in dollars, of the credit unions merged into this credit union in the prior 12 months, as of each merged credit union''s last call report.',
		NCUA_FINANCIALS_HISTORY.ACQUIRED_MEMBERS_PRIOR_YEAR as ACQUIRED_MEMBERS_PRIOR_YEAR comment='Members of the credit unions merged into this credit union in the prior 12 months, as of each merged credit union''s last call report.',
		NCUA_FINANCIALS_HISTORY.ORGANIC_ASSETS_YOY_GROWTH_PCT as ORGANIC_ASSETS_YOY_GROWTH_PCT comment='Organic (pro forma) year-over-year asset growth: total assets now vs the combined assets one year earlier of this credit union plus any credit unions merged into it in the prior 12 months. Equals ASSETS_YOY_GROWTH_PCT when there was no merger.',
		NCUA_FINANCIALS_HISTORY.ORGANIC_MEMBERS_YOY_GROWTH_PCT as ORGANIC_MEMBERS_YOY_GROWTH_PCT comment='Organic (pro forma) year-over-year member growth: members now vs the combined members one year earlier of this credit union plus any credit unions merged into it in the prior 12 months. Equals MEMBERS_YOY_GROWTH_PCT when there was no merger.'
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
		CU_ORACLE_LIVE.AFL as AFL comment='Affiliation status of the credit union with America''s Credit Unions (ACUs) i.e. is the credit union currently affiliated with America''s Credit Unions (ACUs). A=Affiliated, N=Not Affiliated.' sample_values ('N', 'A'),
		CU_ORACLE_LIVE.CEO_FULL_NAME as CEO_FULL_NAME comment='The full name of the chief executive officer.' sample_values ('Steven Shaffner', 'Pamela Goodman', 'Patrick Gallagher'),
		CU_ORACLE_LIVE.LAST_PERIOD_REPORTED as LAST_PERIOD_REPORTED comment='Quarter-end date of the credit union''s final or most recent NCUA 5300 call report; the as-of date for LAST_REPORTED_ASSETS and LAST_REPORTED_MEMBERS. For merged or liquidated credit unions it is usually the quarter before the merger or liquidation.' sample_values ('2026-06-30', '2019-12-31', '2012-09-30'),
		CU_ORACLE_LIVE.LEAGUE_AFFILIATED as LEAGUE_AFFILIATED comment='Affiliation status of the credit union with their state credit union league i.e. is the credit union currently affiliated with its state league. A=Affiliated, N=Not Affiliated.' sample_values ('A', 'N'),
		CU_ORACLE_LIVE.LEAGUE_NAME as LEAGUE_NAME comment='The name of the state credit union league which the credit union belongs to, or would belong to if they were affiliated.' sample_values ('Tennessee League and Mississippi Credit Union Association', 'Illinois Credit Union League', 'CrossState Credit Union Association'),
		CU_ORACLE_LIVE.NAME as NAME comment='The name of a credit union.' sample_values ('St Mark CU', 'Great Neck School EFCU', 'Molokai Community FCU'),
		CU_ORACLE_LIVE.NIMBLE_CUNA_ID as NIMBLE_CUNA_ID comment='A unique identifier assigned by America''s Credit Unions (ACUs), formally known as the CUNA ID or CUID.' sample_values ('10027773', '10018610', '10024555'),
		CU_ORACLE_LIVE.ORG_DATE as ORG_DATE comment='The date the credit union was organized.' sample_values ('1965-11-30', '1935-09-01', '1945-12-07'),
		CU_ORACLE_LIVE.PHONE as PHONE comment='The credit union''s main/general purpose telephone number.' sample_values ('2034027400', '3525882732', '5855911055'),
		CU_ORACLE_LIVE.PO_ADDRESS as PO_ADDRESS comment='The mailing address of the credit union.' sample_values ('221 Main St', 'PO Box 2028', '4400 Maplewood Dr'),
		CU_ORACLE_LIVE.PO_CITY as PO_CITY comment='The city of the mailing address of the credit union.' sample_values ('Chicago', 'Santa Ana', 'Rochester'),
		CU_ORACLE_LIVE.PO_STATE as PO_STATE comment='The two-letter state abbreviation of the mailing address of the credit union. An address field only; for which state a credit union is in, use CHARTER_STATE.' sample_values ('NY', 'IL', 'PA'),
		CU_ORACLE_LIVE.CHARTER_STATE as CHARTER_STATE comment='The state a credit union is headquartered in, by America''s Credit Unions convention: its NCUA charter state from its most recent call report (or its address state if it never filed one). Use for every question about which state a credit union is in or counts by state, even where it differs from the street address.' sample_values ('TX', 'CA', 'WI'),
		CU_ORACLE_LIVE.PO_ZIP_CODE as PO_ZIP_CODE comment='The postal zip code of the mailing address of the credit union.' sample_values ('60619-1827', '14624-4537', '11354-3143'),
		CU_ORACLE_LIVE.ST_ADDRESS as ST_ADDRESS comment='The physical/street address of the credit union.' sample_values ('2998 Chili Ave', '2514 N Main St', '15 Vanderbilt Ave Ste D41'),
		CU_ORACLE_LIVE.ST_CITY as ST_CITY comment='The city of the physical/street address of the credit union.' sample_values ('Rochester', 'Boulder', 'Fort Wayne'),
		CU_ORACLE_LIVE.ST_STATE as ST_STATE comment='The two-letter state abbreviation of the credit union''s physical street address. An address field only; for which state a credit union is in, use CHARTER_STATE (they differ for a few credit unions).' sample_values ('NY', 'PA', 'IL'),
		CU_ORACLE_LIVE.ST_ZIP_CODE as ST_ZIP_CODE comment='The postal zip code of the physical/street address of the credit union.' sample_values ('12110-1007', '14624-4537', '92705-4934'),
		CU_ORACLE_LIVE.STATUS as STATUS comment='The current status of the credit union in America''s Credit Union''s records. A=Active, P=Pending Merger/Liquidation, M=Merged, L=Liquidated, I=Inactive, C=Conservatorship (operating under NCUA conservatorship; still files call reports)' sample_values ('M', 'L', 'A'),
		CU_NAME_ALIASES.ALIAS as ALIAS comment='One name the credit union is or was known by, as written in its source.' sample_values ('PenFed', 'PENTAGON', 'Teachers Credit Union'),
		CU_NAME_ALIASES.ALIAS_KEY as ALIAS_KEY comment='Normalized matching key for ALIAS, from CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(): lowercase, no spaces or punctuation, without credit union / federal credit union / FCU / CU, and with EFCU/ECU shown as employees. Compare it to CU_NAME_KEY() of the name the user typed.' sample_values ('penfed', 'pentagon', 'boeingemployees'),
		CU_NAME_ALIASES.ALIAS_TYPE as ALIAS_TYPE comment='Where the name comes from: Current name (America''s Credit Unions records), NCUA name (current legal name on call reports), Former NCUA name (an earlier legal name, e.g. before a rebrand), Website name, or Trade name (hand-maintained).' sample_values ('Current name', 'Former NCUA name', 'Trade name'),
		CU_NAME_ALIASES.FIRST_PERIOD as FIRST_PERIOD comment='For NCUA and website names, the first quarter-end the name appeared on a call report.',
		CU_NAME_ALIASES.LAST_PERIOD as LAST_PERIOD comment='For NCUA and website names, the last quarter-end the name appeared on a call report.',
		CU_NAME_ALIASES.NIMBLE_CUNA_ID as NIMBLE_CUNA_ID comment='America''s Credit Unions ID of the credit union this name belongs to; joins to CU_ORACLE_LIVE.NIMBLE_CUNA_ID.',
		CU_ORACLE_LIVE.STATUS_CHG_DATE as STATUS_CHG_DATE comment='The date on which the status was last changed.' sample_values ('1949-07-11', '1950-12-08', '1953-11-20'),
		CU_ORACLE_LIVE.TOM_CODE as TOM_CODE comment='Type of Membership (TOM) code, also known as Field of Membership (FOM) code.' sample_values ('00', '01', '36'),
		CU_ORACLE_LIVE.SURVIVOR_ID as SURVIVOR_ID comment='For a merged credit union (STATUS = M), the NIMBLE_CUNA_ID of the credit union it merged into directly. Empty for credit unions that have not merged.',
		CU_ORACLE_LIVE.SURVIVOR_NAME as SURVIVOR_NAME comment='For a merged credit union, the name of the credit union it merged into directly (the survivor of that merger).' sample_values ('SchoolsFirst FCU', 'Gesa CU', 'Midwest United CU'),
		CU_ORACLE_LIVE.CURRENT_SUCCESSOR_ID as CURRENT_SUCCESSOR_ID comment='For a merged credit union, the NIMBLE_CUNA_ID of the credit union it is part of today, following any later mergers of its survivor. Equals SURVIVOR_ID when the survivor has not itself merged.',
		CU_ORACLE_LIVE.CURRENT_SUCCESSOR_NAME as CURRENT_SUCCESSOR_NAME comment='For a merged credit union, the name of the credit union it is part of today, following any later mergers of its survivor (e.g., Teachers CU merged into Midwest United CU, which later merged into CommunityAmerica, so its current successor is CommunityAmerica).' sample_values ('CommunityAmerica Credit Union', 'TDECU', 'Vibrant CU'),
		CU_ORACLE_LIVE.WEB as WEB comment='The website of the credit union.' sample_values ('www.lmhospcu.com', 'www.educationpersonnelfcu.com', 'www.greatplainsfcu.com'),
		NCUA_FINANCIALS_HISTORY.PERIOD_DATE as PERIOD_DATE comment='Quarter-end date of the NCUA call report (March 31, June 30, September 30, or December 31). Use for time series and trends.',
		NCUA_FINANCIALS_HISTORY.PERIOD as PERIOD comment='Quarter of the NCUA call report as YYYYMM text, e.g. 202606 for June 2026.' sample_values ('202606', '202512', '202306'),
		NCUA_FINANCIALS_HISTORY.IS_LATEST_PERIOD as IS_LATEST_PERIOD comment='TRUE for rows in the most recent quarter available.',
		NCUA_FINANCIALS_HISTORY.MERGER_IN_QUARTER as MERGER_IN_QUARTER comment='TRUE if at least one credit union merged into this credit union during this quarter.',
		NCUA_FINANCIALS_HISTORY.MERGER_IN_PRIOR_YEAR as MERGER_IN_PRIOR_YEAR comment='TRUE if at least one credit union merged into this credit union in the 12 months ending at this quarter end, so its year-over-year growth includes acquired balances.',
		NCUA_FINANCIALS_HISTORY.CHARTERSTATE as CHARTERSTATE comment='The credit union''s charter state on that quarter''s call report. By America''s Credit Unions convention this is the state the credit union is headquartered in; use it for every state question about financials or counts, even where it differs from the street address.' sample_values ('LA', 'TX', 'CT'),
		NCUA_FINANCIALS_HISTORY.NIMBLE_CUNA_ID as NIMBLE_CUNA_ID comment='America''s Credit Unions identifier for the credit union (CUNA ID).' sample_values ('10018582', '10013786', '10028304')
	)
	metrics (
		CU_ORACLE_LIVE.NUM_CREDIT_UNIONS as COUNT(nimble_cuna_id) comment='Count of credit union records in America''s Credit Unions'' directory (every credit union ever known, any status). Use for counts by status (e.g. how many credit unions have merged), and with ACTIVE_OR_PENDING for affiliation counts. For general counts such as how many credit unions there are, or how many have fewer than 10 employees, use NUM_REPORTING_CREDIT_UNIONS instead.',
		NCUA_FINANCIALS_HISTORY.NUM_REPORTING_CREDIT_UNIONS as COUNT(DISTINCT join_number) comment='Number of credit unions that filed an NCUA call report. With the LATEST_PERIOD filter, the default count of credit unions for questions like how many credit unions there are, how many are in a state, or how many have fewer than 10 employees. Group by PERIOD_DATE for counts over time.',
		NCUA_FINANCIALS_HISTORY.AGG_NET_WORTH_RATIO_PCT as SUM(net_worth) / NULLIF(SUM(total_assets), 0) * 100 comment='Aggregate net worth ratio for a group of credit unions (sum of net worth over sum of assets, percent). Use for industry, state, or peer-group net worth ratios in a given quarter.',
		NCUA_FINANCIALS_HISTORY.AGG_LOAN_TO_SHARE_PCT as SUM(amt_total_loans) / NULLIF(SUM(amt_total_shares_and_deposits), 0) * 100 comment='Aggregate loan-to-share ratio for a group of credit unions, percent.',
		NCUA_FINANCIALS_HISTORY.AGG_DELINQUENCY_RATE_PCT as SUM(amt_total_delq_loans) / NULLIF(SUM(amt_total_loans), 0) * 100 comment='Aggregate delinquency rate for a group of credit unions (delinquent loans over total loans, percent).',
		NCUA_FINANCIALS_HISTORY.AGG_ROA_PCT as SUM(net_income_annualized) / NULLIF(SUM(avg_assets_ytd), 0) * 100 comment='Aggregate return on assets for a group of credit unions (annualized net income over average assets, percent).',
		NCUA_FINANCIALS_HISTORY.AGG_NET_CHARGEOFF_RATE_PCT as SUM(net_chargeoffs_annualized) / NULLIF(SUM(avg_loans_ytd), 0) * 100 comment='Aggregate net charge-off rate for a group of credit unions (annualized net charge-offs over average loans, percent).'
	)
	ai_sql_generation 'To find a credit union by name, search CU_NAME_ALIASES (current, former, website, and trade names): match ALIAS_KEY LIKE ''%'' || CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(''<name the user typed>'') || ''%'', take the distinct NIMBLE_CUNA_IDs, and join them to CU_ORACLE_LIVE. Never search CU_ORACLE_LIVE.NAME directly with words like Credit Union, Federal Credit Union, CU, or FCU. Narrow by city or state when the user gives one. If more than one credit union matches, list them with city and state and ask which one. Report the credit union under its current NAME; if it matched on a former or trade name, say so (e.g. "Everwise Credit Union, formerly Teachers Credit Union"). If nothing matches, try JAROWINKLER_SIMILARITY(ALIAS_KEY, CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(''<name>'')) >= 90 before saying the credit union was not found.
Default universe for counts, totals, and other aggregates across credit unions (e.g. how many credit unions have fewer than 10 employees, total industry assets, credit unions by state): every credit union that filed the most recent call report, i.e. NCUA_FINANCIALS_HISTORY rows with IS_LATEST_PERIOD = TRUE, whatever their STATUS. Count them with COUNT(DISTINCT JOIN_NUMBER) and join to CU_ORACLE_LIVE only for attributes such as state, league, or name. Do not filter on STATUS unless the question asks about status (active, merged, liquidated, pending, conservatorship). Exception: any question involving affiliation, with America''s Credit Unions (AFL) or a state league (LEAGUE_AFFILIATED), uses CU_ORACLE_LIVE credit unions with STATUS IN (''A'', ''P''). Always say which group the figures cover (e.g. "credit unions that filed the June 30, 2026 call report").
NCUA_FINANCIALS_HISTORY has one row per credit union per quarter. Unless the question asks about a specific past period, a trend, a change over time, or growth, filter it to IS_LATEST_PERIOD = TRUE. Never sum balance amounts (assets, loans, shares, net worth, members, employees) across quarters; for totals over time, group by PERIOD_DATE.
Net income and net charge-offs are reported year-to-date: use the _QTR columns for a single quarter, the _ANNUALIZED columns to compare quarters, and the year-end (QUARTER = 4) _YTD value for a full calendar year.
For one credit union, use the _PCT ratio and growth columns. For a group, state, or the whole industry, use the AGG_ metrics (sum of numerators over sum of denominators); never average individual credit unions'' ratios.
When reporting or ranking a credit union''s asset or member growth, check MERGER_IN_PRIOR_YEAR; if TRUE, say it grew partly through mergers and also give ORGANIC_ASSETS_YOY_GROWTH_PCT or ORGANIC_MEMBERS_YOY_GROWTH_PCT. For questions about organic growth, use the ORGANIC_ columns.
States: the state a credit union is in is always its charter state, never its address. Use NCUA_FINANCIALS_HISTORY.CHARTERSTATE with financial data and CU_ORACLE_LIVE.CHARTER_STATE otherwise (including affiliation questions); use ST_STATE, PO_STATE, and city only to describe an address or to identify a specific credit union the user describes by location.
Employees: when a question asks about employees, staff, or headcount, give both total employees (TOTAL_EMPLOYEES, full-time plus part-time) and full-time equivalents (FTE_EMPLOYEES, full-time plus half of part-time), and say which is which; for thresholds (e.g. fewer than 10 employees) report the count under each measure. If the question asks specifically for FTEs, give only FTE_EMPLOYEES.
For how many branches or offices a credit union has, use CU_ORACLE_LIVE.BRANCHES. Use CURRENT_NCUA_BRANCH_FILE for branch locations, addresses, hours, and services (ATM, drive-through); it is current only, so there is no branch history.
For growth over several years, compare the same quarter in each year (for example June 2021 to June 2026) and compute compound annual growth when asked for an annual rate. Always state which quarter-end dates the figures cover.
Assets and members come from two places. NCUA_FINANCIALS_HISTORY has every quarter for the latest five years; use it for any credit union that still reports and for anything over time. CU_ORACLE_LIVE.LAST_REPORTED_ASSETS and LAST_REPORTED_MEMBERS hold one figure per credit union from its final or most recent call report, back to 1994; use them for merged, liquidated, or inactive credit unions, or any credit union with no rows in NCUA_FINANCIALS_HISTORY. Whenever you report a LAST_REPORTED_ figure, also return LAST_PERIOD_REPORTED and state that date, and do not add up or rank LAST_REPORTED_ figures with different dates without saying so.
For who a credit union merged into, report SURVIVOR_NAME and, if different, CURRENT_SUCCESSOR_NAME, with STATUS_CHG_DATE as the merger date. For which credit unions merged into a given credit union, match its NIMBLE_CUNA_ID against SURVIVOR_ID for direct mergers, or against CURRENT_SUCCESSOR_ID for every credit union that is now part of it (including through earlier mergers); say which one you used.
For any question about affiliation, return AFL (affiliation with America''s Credit Unions) and LEAGUE_AFFILIATED (affiliation with the state league) as separate columns, America''s Credit Unions affiliation first; never combine or substitute one for the other.'
	ai_question_categorization 'Dismissively reject, in a humorous way, any questions about commercial banks as unworthy of the CU Oracle''s compute tokens. Affiliation status with America''s Credit Unions (ACUs) is distinct from league affiliation and should always be reported separately with an emphasis on America''s Credit Unions Affiliation.'
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
VERIFIED_AT 1792022400
VERIFIED_BY 'Paul Ledin (revised by Claude Code 2026-10-15: affiliated, active or pending only)'
ONBOARDING_QUESTION false
SQL 'SELECT
  COUNT(nimble_cuna_id) AS credit_union_count
FROM
  cu_oracle_live
WHERE
  LOWER(league_name) LIKE ''%wisconsin%''
  AND league_affiliated = ''A''
  AND status IN (''A'', ''P'')'),
		"How many credit unions are affiliated with America's Credit Unions?" AS (
QUESTION 'How many credit unions are affiliated with America''s Credit Unions?'
VERIFIED_AT 1792022400
VERIFIED_BY 'Claude Code (for Paul Ledin)'
ONBOARDING_QUESTION false
SQL 'SELECT
  COUNT(nimble_cuna_id) AS acu_affiliated_credit_unions
FROM
  cu_oracle_live
WHERE
  afl = ''A''
  AND status IN (''A'', ''P'')'),
		"How many credit unions have fewer than 10 employees?" AS (
QUESTION 'How many credit unions have fewer than 10 employees?'
VERIFIED_AT 1792022400
VERIFIED_BY 'Claude Code (for Paul Ledin)'
ONBOARDING_QUESTION false
SQL 'SELECT
  period_date,
  COUNT(DISTINCT IFF(total_employees < 10, join_number, NULL)) AS credit_unions_under_10_total_employees,
  COUNT(DISTINCT IFF(fte_employees < 10, join_number, NULL)) AS credit_unions_under_10_fte_employees
FROM
  ncua_financials_history
WHERE
  is_latest_period
GROUP BY
  period_date'),
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
  h.period_date'),
		"How big was Schools Financial Credit Union in Sacramento when it merged?" AS (
QUESTION 'How big was Schools Financial Credit Union in Sacramento when it merged?'
VERIFIED_AT 1792022400
VERIFIED_BY 'Claude Code (for Paul Ledin)'
ONBOARDING_QUESTION false
SQL 'SELECT
  name,
  st_city,
  st_state,
  status,
  status_chg_date,
  last_period_reported,
  last_reported_assets,
  last_reported_members
FROM
  cu_oracle_live
WHERE
  LOWER(name) LIKE ''%schools financial%''
  AND LOWER(st_city) = ''sacramento'''),
		"Which credit unions have merged into Gesa Credit Union?" AS (
QUESTION 'Which credit unions have merged into Gesa Credit Union?'
VERIFIED_AT 1792022400
VERIFIED_BY 'Claude Code (for Paul Ledin)'
ONBOARDING_QUESTION false
SQL 'SELECT
  m.name,
  m.st_city,
  m.st_state,
  m.status_chg_date AS merger_date,
  m.survivor_name,
  m.last_period_reported,
  m.last_reported_assets,
  m.last_reported_members
FROM
  cu_oracle_live AS m
  JOIN cu_oracle_live AS g ON m.survivor_id = g.nimble_cuna_id
WHERE
  LOWER(g.name) LIKE ''%gesa%''
  AND g.status = ''A''
ORDER BY
  m.status_chg_date DESC'),
		"What are PenFed's total assets and members?" AS (
QUESTION 'What are PenFed''s total assets and members?'
VERIFIED_AT 1792022400
VERIFIED_BY 'Claude Code (for Paul Ledin)'
ONBOARDING_QUESTION false
SQL 'WITH matches AS (
  SELECT DISTINCT
    nimble_cuna_id
  FROM
    cu_name_aliases
  WHERE
    alias_key LIKE ''%'' || CU_ORACLE_AGENT_DB.ANALYTICS.CU_NAME_KEY(''PenFed'') || ''%''
)
SELECT
  col.name,
  col.st_city,
  col.st_state,
  h.period_date,
  h.total_assets,
  h.members
FROM
  matches AS m
  JOIN cu_oracle_live AS col ON col.nimble_cuna_id = m.nimble_cuna_id
  JOIN ncua_financials_history AS h ON h.join_number = col.join_number
WHERE
  h.is_latest_period
  AND col.status = ''A''')
	);
