-- One-time fix (2026-10-15): NCUA_FINANCIALS_202403, _202409, and _202603 were
-- loaded with 743 columns instead of 744-748, missing five derived variables.
-- This adds them back, computed from the raw 5300 accounts in
-- NCUA_DATA.ACCTCODES.ACCTCODES_<P> using NCUA's own definitions
-- (NCUA_DATA.PUBLIC.NCUA_DEFINED_VARIABLES).
--
-- Validated before running: on NCUA_FINANCIALS_202406 (a complete table) these
-- formulas reproduce all five named columns exactly for all 4,631 credit unions.
--
-- Benefits every consumer of these tables (CU Oracle history, Credit Analysis).
-- Re-runnable: ADD COLUMN IF NOT EXISTS, and the UPDATE just recomputes.
-- Run as SYSADMIN (table owner).

EXECUTE IMMEDIATE $$
DECLARE
    periods ARRAY DEFAULT ARRAY_CONSTRUCT('202403', '202409', '202603');
    p VARCHAR;
    f VARCHAR;
    a VARCHAR;
BEGIN
    FOR i IN 0 TO ARRAY_SIZE(periods) - 1 DO
        p := periods[i];
        f := 'NCUA_DATA.FINANCIALS.NCUA_FINANCIALS_' || p;
        a := 'NCUA_DATA.ACCTCODES.ACCTCODES_' || p;
        EXECUTE IMMEDIATE 'ALTER TABLE ' || f || ' ADD COLUMN IF NOT EXISTS AMT_NET_MBL_BALANCE FLOAT';
        EXECUTE IMMEDIATE 'ALTER TABLE ' || f || ' ADD COLUMN IF NOT EXISTS AMT_ALLOWANCE_FOR_CREDIT_LOSS FLOAT';
        EXECUTE IMMEDIATE 'ALTER TABLE ' || f || ' ADD COLUMN IF NOT EXISTS AMT_UNDIVIDED_EARNINGS FLOAT';
        EXECUTE IMMEDIATE 'ALTER TABLE ' || f || ' ADD COLUMN IF NOT EXISTS AMT_ALL_OTHER_RESERVES FLOAT';
        EXECUTE IMMEDIATE 'ALTER TABLE ' || f || ' ADD COLUMN IF NOT EXISTS EARNING_ASSETS FLOAT';
        EXECUTE IMMEDIATE
            'UPDATE ' || f || ' t SET ' ||
            '  AMT_NET_MBL_BALANCE = s.ACCT_400A, ' ||
            '  AMT_ALLOWANCE_FOR_CREDIT_LOSS = s.ACCT_LI0003, ' ||
            '  AMT_UNDIVIDED_EARNINGS = s.ACCT_940, ' ||
            '  AMT_ALL_OTHER_RESERVES = s.ACCT_658 + s.ACCT_668 + s.ACCT_658A + s.ACCT_996 + s.ACCT_945A + s.ACCT_945C + s.ACCT_EQ0009 + s.ACCT_945B + s.ACCT_602, ' ||
            '  EARNING_ASSETS = IFF(s.ACCT_AS0048 > s.ACCT_719, ' ||
            '      s.ACCT_025B + s.ACCT_003 + s.ACCT_NV0158 + (0.75 * s.ACCT_AS0009) - s.ACCT_AS0048 + s.ACCT_794, ' ||
            '      s.ACCT_025B + s.ACCT_003 + s.ACCT_NV0158 + (0.75 * s.ACCT_AS0009) - s.ACCT_719 + s.ACCT_794) ' ||
            'FROM ' || a || ' s WHERE s.CU_NUMBER::STRING = t.CU_NUMBER::STRING';
    END FOR;
    RETURN 'Backfilled 5 columns in ' || ARRAY_SIZE(periods) || ' tables.';
END;
$$;
