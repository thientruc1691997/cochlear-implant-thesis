/* ============================================================
   MODULE   : 05_keywords.sql
   PURPOSE  : Extract keywords and parent keywords per patient
              per ear. Multiple keywords concatenated per row.
   INPUT    : #Surgery (Module 02)
   OUTPUT   : #Keywords
   GRAIN    : 1 row = 1 PatientID x 1 SideID

   TABLE COLUMNS CONFIRMED:
     PatientKeyword : PatientID, KeywordID, Side (tinyint)
     Keyword        : KeywordID, ParentKeywordID, Keyword,
                      IsReadOnly, Used, SnomedNumber

   DECISIONS LOG:
   DEC-20  PatientKeyword.Side: 1=Left, 2=Right, 0=Unknown->both, 3=Both->both
   DEC-21  ParentKeyword resolved via self-join on Keyword table
           using ParentKeywordID -> KeywordID.
   DEC-22  Keywords concatenated alphabetically per patient-ear.
   DEC-23  has_bilateral_kw = 1 if any keyword from Side 0 or 3.
   ============================================================ */

IF OBJECT_ID('tempdb..#Keywords')    IS NOT NULL DROP TABLE #Keywords;
IF OBJECT_ID('tempdb..#KW_Expanded') IS NOT NULL DROP TABLE #KW_Expanded;
IF OBJECT_ID('tempdb..#KW_Agg')      IS NOT NULL DROP TABLE #KW_Agg;


/* ============================================================
   STEP 1 - EDA (run once, comment out after confirmed)
   ============================================================ */

-- 1a. Side distribution in PatientKeyword
SELECT
    [Side],
    COUNT(DISTINCT PatientID)   AS n_patients,
    COUNT(*)                    AS n_records
FROM [dbo].[PatientKeyword]
GROUP BY [Side]
ORDER BY [Side];

-- 1b. Top 20 keywords with parent
SELECT TOP 20
    k.Keyword,
    kp.Keyword                  AS ParentKeyword,
    COUNT(*)                    AS n
FROM [dbo].[PatientKeyword] pk
JOIN      [dbo].[Keyword] k
       ON k.KeywordID        = pk.KeywordID
LEFT JOIN [dbo].[Keyword] kp
       ON kp.KeywordID       = k.ParentKeywordID
GROUP BY k.Keyword, kp.Keyword
ORDER BY n DESC;

-- 1c. Coverage vs #Surgery
SELECT
    COUNT(DISTINCT s.PatientID) AS surgery_patients,
    COUNT(DISTINCT pk.PatientID)AS patients_with_keywords
FROM #Surgery s
LEFT JOIN [dbo].[PatientKeyword] pk
       ON pk.PatientID = s.PatientID;


/* ============================================================
   STEP 2 - Expand keywords to ear level
   ─────────────────────────────────────
   Columns used:
     PatientKeyword : PatientID, KeywordID, Side
     Keyword        : KeywordID, Keyword, ParentKeywordID
   ============================================================ */
SELECT
    pk.PatientID,
    ear.SideID,
    pk.[Side]                                           AS original_side,
    CASE WHEN pk.[Side] IN (0,3) THEN 1 ELSE 0 END     AS is_bilateral_kw,
    k.Keyword                                           AS kw_name,
    kp.Keyword                                          AS kw_parent

INTO #KW_Expanded

FROM [dbo].[PatientKeyword] pk

JOIN [dbo].[Keyword] k
  ON k.KeywordID = pk.KeywordID

LEFT JOIN [dbo].[Keyword] kp
       ON kp.KeywordID = k.ParentKeywordID       -- self-join to get parent name (DEC-21)

/* Expand Side 0 & 3 to both ears, keep Side 1 & 2 as-is */
JOIN (
    SELECT 1 AS SideID, 1 AS MatchSide UNION ALL -- Left only
    SELECT 1, 0                        UNION ALL -- Unknown -> Left
    SELECT 1, 3                        UNION ALL -- Both -> Left
    SELECT 2, 2                        UNION ALL -- Right only
    SELECT 2, 0                        UNION ALL -- Unknown -> Right
    SELECT 2, 3                                  -- Both -> Right
) ear ON ear.MatchSide = pk.[Side]

WHERE pk.[Side] IN (0, 1, 2, 3);


CREATE INDEX IX_KW_Expanded ON #KW_Expanded (PatientID, SideID);


/* ============================================================
   STEP 3 - Aggregate per PatientID x SideID
   Parent keywords are ordered to match keywords
   ============================================================ */

SELECT
    base.PatientID,
    base.SideID,

    /* Keywords ordered alphabetically */
    STUFF((
        SELECT '; ' + x.kw_name
        FROM (
            SELECT DISTINCT
                e2.kw_name,
                e2.kw_parent
            FROM #KW_Expanded e2
            WHERE e2.PatientID = base.PatientID
              AND e2.SideID    = base.SideID
        ) x
        ORDER BY x.kw_name
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS keywords,

    /* Parent keywords in the SAME order as keywords */
    STUFF((
        SELECT '; ' + COALESCE(x.kw_parent, '')
        FROM (
            SELECT DISTINCT
                e3.kw_name,
                e3.kw_parent
            FROM #KW_Expanded e3
            WHERE e3.PatientID = base.PatientID
              AND e3.SideID    = base.SideID
        ) x
        ORDER BY x.kw_name
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS parent_keywords,

    /* Best readable version: keyword and parent kept together */
    STUFF((
        SELECT '; ' + x.kw_name
             + CASE
                   WHEN x.kw_parent IS NOT NULL
                   THEN ' [' + x.kw_parent + ']'
                   ELSE ''
               END
        FROM (
            SELECT DISTINCT
                e4.kw_name,
                e4.kw_parent
            FROM #KW_Expanded e4
            WHERE e4.PatientID = base.PatientID
              AND e4.SideID    = base.SideID
        ) x
        ORDER BY x.kw_name
        FOR XML PATH(''), TYPE
    ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS keyword_parent_pairs,

    COUNT(DISTINCT d.kw_name) AS keyword_count,
    MAX(d.is_bilateral_kw)    AS has_bilateral_kw,

    /* ============================
       Encoded keyword features
       ============================ */

    /* SIR: raw numeric score, including 0 */
    MAX(CASE 
            WHEN d.kw_parent = 'SIR'
             AND CHARINDEX(':', d.kw_name) > 1
            THEN TRY_CAST(LEFT(d.kw_name, CHARINDEX(':', d.kw_name) - 1) AS INT)
        END) AS sir_score,

    /* SIR intelligibility only: scores 1-5, excluding child-before-6 label */
    MAX(CASE 
            WHEN d.kw_parent = 'SIR'
             AND CHARINDEX(':', d.kw_name) > 1
             AND TRY_CAST(LEFT(d.kw_name, CHARINDEX(':', d.kw_name) - 1) AS INT) BETWEEN 1 AND 5
            THEN TRY_CAST(LEFT(d.kw_name, CHARINDEX(':', d.kw_name) - 1) AS INT)
        END) AS sir_intelligibility_score,

    MAX(CASE 
            WHEN d.kw_parent = 'SIR'
            THEN 1 ELSE 0
        END) AS has_sir,

    MAX(CASE 
            WHEN d.kw_name = '0: Child implanted before age 6'
             AND d.kw_parent = 'SIR'
            THEN 1 ELSE 0
        END) AS sir_child_implanted_before_6,

    MAX(CASE 
            WHEN d.kw_name = '1: Completely Intelligible in Conversation'
             AND d.kw_parent = 'SIR'
            THEN 1 ELSE 0
        END) AS sir_completely_intelligible,

    MAX(CASE 
            WHEN d.kw_name = '2: Mostly Intelligible in Conversation'
             AND d.kw_parent = 'SIR'
            THEN 1 ELSE 0
        END) AS sir_mostly_intelligible,

    MAX(CASE 
            WHEN d.kw_name = '3: Somewhat Intelligible in Conversation'
             AND d.kw_parent = 'SIR'
            THEN 1 ELSE 0
        END) AS sir_somewhat_intelligible,

    /* Type of hearing loss */
    MAX(CASE WHEN d.kw_name = 'Postlingually Acquired'
            AND d.kw_parent = 'Type of Hearing Loss'
            THEN 1 ELSE 0 END) AS kw_postlingually_acquired,

    MAX(CASE WHEN d.kw_name = 'Congenital'
            AND d.kw_parent = 'Type of Hearing Loss'
            THEN 1 ELSE 0 END) AS kw_congenital_type,

    MAX(CASE WHEN d.kw_name = 'Perilingual'
            AND d.kw_parent = 'Type of Hearing Loss'
            THEN 1 ELSE 0 END) AS kw_perilingual,

    /* Course of hearing loss */
    MAX(CASE WHEN d.kw_name = 'Progressive (slow)'
            AND d.kw_parent = 'Course of Hearing Loss'
            THEN 1 ELSE 0 END) AS kw_progressive_slow,

    MAX(CASE WHEN d.kw_name = 'Sudden'
            AND d.kw_parent = 'Course of Hearing Loss'
            THEN 1 ELSE 0 END) AS kw_sudden,

    /* Cause of hearing loss */
    MAX(CASE WHEN d.kw_name = 'Unknown'
            AND d.kw_parent = 'Cause of Hearing Loss'
            THEN 1 ELSE 0 END) AS kw_unknown_cause,

    MAX(CASE WHEN d.kw_name = 'Congenital'
            AND d.kw_parent = 'Cause of Hearing Loss'
            THEN 1 ELSE 0 END) AS kw_congenital_cause,

    /* Ear */
    MAX(CASE WHEN d.kw_name = 'Normal'
            AND d.kw_parent = 'Ear'
            THEN 1 ELSE 0 END) AS kw_normal_ear,

    /* OTHER */
    MAX(CASE WHEN d.kw_name = 'CI Bilateral'
            AND d.kw_parent = 'OTHER'
            THEN 1 ELSE 0 END) AS kw_ci_bilateral,

    /* Genetic */
    MAX(CASE WHEN d.kw_parent = 'Genetic'
            THEN 1 ELSE 0 END) AS has_genetic,

    MAX(CASE WHEN d.kw_name = 'Connexine 26'
            AND d.kw_parent = 'Genetic'
            THEN 1 ELSE 0 END) AS kw_connexine_26,

    MAX(CASE WHEN d.kw_name = 'COCH (DFNA9)'
            AND d.kw_parent = 'Genetic'
            THEN 1 ELSE 0 END) AS kw_coch_dfna9,

    /* Malformation */
    MAX(CASE WHEN d.kw_parent = 'Malformation'
            THEN 1 ELSE 0 END) AS has_malformation,

    MAX(CASE WHEN d.kw_name = 'Enlarged Vestibular Aqueduct'
            AND d.kw_parent = 'Malformation'
            THEN 1 ELSE 0 END) AS kw_enlarged_vestibular_aqueduct,

    /* Degenerative/Aging */
    MAX(CASE WHEN d.kw_name = 'Menière'
            AND d.kw_parent = 'Degenerative/Aging'
            THEN 1 ELSE 0 END) AS has_meniere,

    /* Risk factor */
    MAX(CASE WHEN d.kw_parent = 'Risk Factor'
            THEN 1 ELSE 0 END) AS has_risk_factor,

    MAX(CASE WHEN d.kw_name = 'Family History'
            AND d.kw_parent = 'Risk Factor'
            THEN 1 ELSE 0 END) AS kw_family_history,

    /* Infectious */
    MAX(CASE WHEN d.kw_parent = 'Infectious'
            THEN 1 ELSE 0 END) AS has_infectious,

    MAX(CASE WHEN d.kw_name = 'Meningitis'
            AND d.kw_parent = 'Infectious'
            THEN 1 ELSE 0 END) AS kw_meningitis,

    /* Study: keep for audit, not main model */
    MAX(CASE WHEN d.kw_parent = 'Study'
            THEN 1 ELSE 0 END) AS has_study_keyword,

    MAX(CASE WHEN d.kw_name = 'OG060 CI reimplantation'
            AND d.kw_parent = 'Study'
            THEN 1 ELSE 0 END) AS kw_og060_ci_reimplantation

INTO #KW_Agg

FROM (SELECT DISTINCT PatientID, SideID FROM #KW_Expanded) base
JOIN #KW_Expanded d
  ON d.PatientID = base.PatientID
 AND d.SideID    = base.SideID

GROUP BY base.PatientID, base.SideID;


/* ============================================================
   STEP 4 - Final merge to #Surgery grain
   ============================================================ */
SELECT
    s.PatientID,
    s.SideID,

    /* Raw keyword audit columns */
    COALESCE(a.keywords, '')             AS keywords,
    COALESCE(a.parent_keywords, '')      AS parent_keywords,
    COALESCE(a.keyword_parent_pairs, '') AS keyword_parent_pairs,
    COALESCE(a.keyword_count, 0)         AS keyword_count,
    COALESCE(a.has_bilateral_kw, 0)      AS has_bilateral_kw,

    /* SIR */
    a.sir_score,
    a.sir_intelligibility_score,
    COALESCE(a.has_sir, 0)                          AS has_sir,
    COALESCE(a.sir_child_implanted_before_6, 0)     AS sir_child_implanted_before_6,
    COALESCE(a.sir_completely_intelligible, 0)      AS sir_completely_intelligible,
    COALESCE(a.sir_mostly_intelligible, 0)          AS sir_mostly_intelligible,
    COALESCE(a.sir_somewhat_intelligible, 0)        AS sir_somewhat_intelligible,

    /* Type of Hearing Loss */
    COALESCE(a.kw_postlingually_acquired, 0)        AS kw_postlingually_acquired,
    COALESCE(a.kw_congenital_type, 0)               AS kw_congenital_type,
    COALESCE(a.kw_perilingual, 0)                   AS kw_perilingual,

    /* Course of Hearing Loss */
    COALESCE(a.kw_progressive_slow, 0)              AS kw_progressive_slow,
    COALESCE(a.kw_sudden, 0)                        AS kw_sudden,

    /* Cause of Hearing Loss */
    COALESCE(a.kw_unknown_cause, 0)                 AS kw_unknown_cause,
    COALESCE(a.kw_congenital_cause, 0)              AS kw_congenital_cause,

    /* Ear */
    COALESCE(a.kw_normal_ear, 0)                    AS kw_normal_ear,

    /* OTHER */
    COALESCE(a.kw_ci_bilateral, 0)                  AS kw_ci_bilateral,

    /* Genetic */
    COALESCE(a.has_genetic, 0)                      AS has_genetic,
    COALESCE(a.kw_connexine_26, 0)                  AS kw_connexine_26,
    COALESCE(a.kw_coch_dfna9, 0)                    AS kw_coch_dfna9,

    /* Malformation */
    COALESCE(a.has_malformation, 0)                 AS has_malformation,
    COALESCE(a.kw_enlarged_vestibular_aqueduct, 0)  AS kw_enlarged_vestibular_aqueduct,

    /* Degenerative/Aging */
    COALESCE(a.has_meniere, 0)                      AS has_meniere,

    /* Risk Factor */
    COALESCE(a.has_risk_factor, 0)                  AS has_risk_factor,
    COALESCE(a.kw_family_history, 0)                AS kw_family_history,

    /* Infectious */
    COALESCE(a.has_infectious, 0)                   AS has_infectious,
    COALESCE(a.kw_meningitis, 0)                    AS kw_meningitis,

    /* Study: keep for audit, not main model */
    COALESCE(a.has_study_keyword, 0)                AS has_study_keyword,
    COALESCE(a.kw_og060_ci_reimplantation, 0)       AS kw_og060_ci_reimplantation

INTO #Keywords

FROM #Surgery s
LEFT JOIN #KW_Agg a
       ON a.PatientID = s.PatientID
      AND a.SideID    = s.SideID;

/* -- Cleanup intermediate tables --------------------------- */
DROP TABLE #KW_Expanded;
DROP TABLE #KW_Agg;

/* -- Index ------------------------------------------------- */
CREATE INDEX IX_Keywords_PatientSide
    ON #Keywords (PatientID, SideID);
