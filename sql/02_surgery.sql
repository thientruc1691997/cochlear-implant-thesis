/* ============================================================
   MODULE   : 02_surgery.sql
   PURPOSE  : Identify all cochlear implant surgeries per patient
              per ear. Flag records that require clinical review.
   INPUT    : #Patient (Module 01)
   OUTPUT   : #Surgery
   GRAIN    : 1 row = 1 PatientID x 1 ear side
 
   TABLES USED:
     [Audiqueen].[Audiqueen].[Event]       Clinical events
     [Audiqueen].[Audiqueen].[EventType]   Event type lookup
     [Audiqueen].[dbo].[LookupSide]        SideID -> Side label
 
   ── DECISIONS LOG ──────────────────────────────────────────
   DEC-01  Only 'Cochlear implant' events used as implant anchors.
           'Revision CI' and 'CI flap revision' excluded.
           EVIDENCE: Revision CI descriptions confirm no new device
           (e.g. "revisie; geen nieuw SN", "Magneet herplaatst",
           "infectie gedraineerd") — all in Dutch.
 
   DEC-02  Confirmed implant = description IS NOT NULL.
           Possible miscoded revision = description IS NULL.
           RATIONALE: All true implants have a description
           (device name or LAURA SN...). Revisions never do.
           Description is stored as-is (no parsing) — brand,
           model, SN, flags (*EXPL, *HER, *LEK) can be extracted
           later in Python/R if needed.
 
   DEC-03  Device stored as wide format:
           device_description_1 = first confirmed implant
           device_description_2 = second confirmed implant
           Only confirmed (non-NULL description) events numbered.
 
   DEC-04  explant_flag = 1 ONLY when last_explant_date is AFTER
           last_implant_date — patient no longer has a device.
           If Explant is followed by a new CI, no flag is set.
 
   DEC-05  Side = 0 (unknown laterality) excluded.
   DEC-06  Events with NULL Date excluded.
   ── END DECISIONS LOG ──────────────────────────────────────
   ============================================================ */
 
 
/* -- Drop temp table if it already exists from a prior run --- */
IF OBJECT_ID('tempdb..#Surgery') IS NOT NULL
    DROP TABLE #Surgery;
 
 
/* ============================================================
   STEP 1 - EDA: inspect before filtering
   ----------------------------------------
   Run once to confirm event type names and LookupSide values.
   Comment out after confirmed.
   ============================================================ */
 
-- 1a. CI-related event types and counts
SELECT
    et.Name                             AS event_type,
    e.[Side],
    COUNT(*)                            AS n_events,
    SUM(CASE WHEN e.description IS NOT NULL
             THEN 1 ELSE 0 END)         AS n_with_description
FROM [Audiqueen].[Event] e
JOIN [Audiqueen].[EventType] et
  ON et.EventTypeID = e.EventTypeID
WHERE et.Name IN (
    'Cochlear implant',
    'Revision CI',
    'CI flap revision',
    'Explant CI'
)
AND (e.Archived = 0 OR e.Archived IS NULL)
GROUP BY et.Name, e.[Side]
ORDER BY et.Name, e.[Side];
 
-- 1b. LookupSide values
SELECT * FROM [dbo].[LookupSide];
 
 
/* ============================================================
   STEP 2 - Extract all Cochlear implant events
   ──────────────────────────────────────────────
   One row per CI event at this stage.
   description IS NOT NULL = confirmed new device placed (DEC-02)
   description IS NULL     = possible miscoded revision
   ============================================================ */
;WITH CIEvents AS (
 
    SELECT
        e.PatientID,
        e.[Side]                            AS SideID,
        e.[Date]                            AS implant_date,
        e.EventID,
        e.description,
 
        /* Confirmed implant flag (DEC-02) */
        CASE
            WHEN e.description IS NOT NULL THEN 1
            ELSE 0
        END                                 AS has_description
 
    FROM [Audiqueen].[Event] e
    JOIN [Audiqueen].[EventType] et
      ON et.EventTypeID = e.EventTypeID
 
    WHERE et.Name  = 'Cochlear implant'     -- DEC-01
      AND (e.Archived = 0 OR e.Archived IS NULL)
      AND e.[Side] IN (1, 2)               -- DEC-05
      AND e.[Date] IS NOT NULL             -- DEC-06
 
)
,
 
 
/* ============================================================
   STEP 3 - Number confirmed implants chronologically (DEC-03)
   ─────────────────────────────────────────────────────────────
   Only events with a description get a sequence number.
   NULL-description events are counted separately.
   ============================================================ */
CIEventsNumbered AS (
 
    SELECT
        *,
        CASE
            WHEN has_description = 1
            THEN ROW_NUMBER() OVER (
                    PARTITION BY PatientID, SideID, has_description
                    ORDER BY implant_date ASC
                 )
            ELSE NULL
        END                                 AS confirmed_seq
 
    FROM CIEvents
 
),
 
 
/* ============================================================
   STEP 4 - Explant events (DEC-04)
   ─────────────────────────────────
   Capture the most recent explant date per patient-ear.
   ============================================================ */
ExplantEvents AS (
 
    SELECT
        e.PatientID,
        e.[Side]                            AS SideID,
        MAX(e.[Date])                       AS last_explant_date,
        COUNT(*)                            AS explant_count
    FROM [Audiqueen].[Event] e
    JOIN [Audiqueen].[EventType] et
      ON et.EventTypeID = e.EventTypeID
    WHERE et.Name = 'Explant CI'
      AND (e.Archived = 0 OR e.Archived IS NULL)
      AND e.[Side] IN (1, 2)
    GROUP BY e.PatientID, e.[Side]
 
),
 
 
/* ============================================================
   STEP 5 - Aggregate to 1 row per PatientID x ear
   ============================================================ */
ImplantSummary AS (
 
    SELECT
        PatientID,
        SideID,
 
        /* Implant timeline */
        MIN(implant_date)                   AS first_implant_date,
        MAX(implant_date)                   AS last_implant_date,
        COUNT(*)                            AS implant_event_count,
        SUM(has_description)                AS confirmed_implant_count,
        SUM(1 - has_description)            AS possible_revision_count,
 
        /* Reimplant = more than 1 confirmed device on same ear */
        CASE
            WHEN SUM(has_description) > 1 THEN 1
            ELSE 0
        END                                 AS reimplant_flag,
 
        /* DR review flag = any event has no description */
        CASE
            WHEN SUM(1 - has_description) > 0 THEN 1
            ELSE 0
        END                                 AS needs_dr_review,
 
        /* Device descriptions in wide format (DEC-03) */
        MAX(CASE WHEN confirmed_seq = 1
                 THEN implant_date   END)   AS device_1_date,
        MAX(CASE WHEN confirmed_seq = 1
                 THEN description    END)   AS device_description_1,
 
        MAX(CASE WHEN confirmed_seq = 2
                 THEN implant_date   END)   AS device_2_date,
        MAX(CASE WHEN confirmed_seq = 2
                 THEN description    END)   AS device_description_2
 
    FROM CIEventsNumbered
    GROUP BY PatientID, SideID
    )
,

FirstImplantedEar AS (

    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY PatientID
            ORDER BY first_implant_date ASC, SideID ASC
        ) AS rn_first_ear
    FROM ImplantSummary
)


 
/* ============================================================
   STEP 6 - Final merge
   ─────────────────────
   Join #Patient, LookupSide, ExplantEvents.
   Compute age at surgery and explant flag.
   ============================================================ */
SELECT
 
    /* Identifiers */
    s.PatientID,
    s.SideID,
    ls.Side                             AS SideLabel,
 
    /* Demographics from Module 01 */
    p.BirthDate,
    CAST(
        DATEDIFF(DAY, p.BirthDate, s.first_implant_date)
        / 365.25
    AS DECIMAL(5,1))                    AS age_at_first_implant,
    CAST(
        DATEDIFF(DAY, p.BirthDate, s.last_implant_date)
        / 365.25
    AS DECIMAL(5,1))                    AS age_at_last_implant,
 
    /* Implant timeline */
    s.first_implant_date,
    s.last_implant_date,                -- anchor for all pre/post test modules
    s.implant_event_count,
    s.confirmed_implant_count,
    s.possible_revision_count,
    s.reimplant_flag,
 
    /* Device descriptions (DEC-02, DEC-03) */
    s.device_1_date,
    s.device_description_1,
    s.device_2_date,
    s.device_description_2,
 
    /* Explant (DEC-04) */
    COALESCE(ex.explant_count, 0)       AS explant_count,
    ex.last_explant_date,
    CASE
        WHEN ex.last_explant_date IS NULL                THEN 0
        WHEN ex.last_explant_date > s.last_implant_date  THEN 1
        ELSE 0
    END                                 AS explant_flag,
 
    /* DR review flag */
    s.needs_dr_review
 
INTO #Surgery
 
FROM FirstImplantedEar s

JOIN #Patient p
  ON p.PatientID = s.PatientID

LEFT JOIN [dbo].[LookupSide] ls
       ON ls.ID = s.SideID

LEFT JOIN ExplantEvents ex
       ON ex.PatientID = s.PatientID
      AND ex.SideID    = s.SideID

LEFT JOIN dbo.PatientIdExternalIDMapping m
       ON s.PatientID = m.PatientID

LEFT JOIN dbo.ExternalSurgeryPatients esp
       ON m.ExternalID = esp.ExternalID

WHERE s.rn_first_ear = 1
  AND esp.ExternalID IS NULL
  AND s.first_implant_date >= '2003-01-01';
 
/* -- Indexes for fast joins in downstream modules ------------ */
CREATE INDEX IX_Surgery_PatientSide
    ON #Surgery (PatientID, SideID);
 
CREATE INDEX IX_Surgery_LastImplant
    ON #Surgery (PatientID, SideID, last_implant_date);
 
 /* ============================================================
   QA CHECK
   ============================================================ */
SELECT
    COUNT(*)                                                        AS total_rows,
    COUNT(DISTINCT PatientID)                                       AS unique_patients,
    COUNT(*) - COUNT(DISTINCT CONCAT(PatientID,'-',SideID))         AS duplicate_rows,
    SUM(CASE WHEN SideLabel             IS NULL THEN 1 ELSE 0 END)  AS null_sidelabel,
    SUM(CASE WHEN last_implant_date     IS NULL THEN 1 ELSE 0 END)  AS null_last_implant,
    SUM(CASE WHEN device_description_1  IS NULL THEN 1 ELSE 0 END)  AS no_confirmed_device,
    SUM(CASE WHEN SideID = 1            THEN 1 ELSE 0 END)          AS left_ears,
    SUM(CASE WHEN SideID = 2            THEN 1 ELSE 0 END)          AS right_ears,
    SUM(reimplant_flag)                                             AS reimplant_ears,
    SUM(needs_dr_review)                                            AS ears_needing_review,
    SUM(explant_flag)                                               AS explanted_no_new_device
FROM #Surgery;
 
/* -- Records flagged for DR review -------------------------- */
SELECT
    PatientID,
    SideID,
    SideLabel,
    first_implant_date,
    last_implant_date,
    implant_event_count,
    confirmed_implant_count,
    possible_revision_count,
    device_description_1,
    device_description_2,
    explant_flag,
    last_explant_date,
    needs_dr_review
FROM #Surgery
WHERE needs_dr_review = 1
   OR explant_flag    = 1
ORDER BY PatientID, SideID;
 
/* -- Preview ------------------------------------------------ */
SELECT TOP 20 *
FROM #Surgery
ORDER BY PatientID, SideID;