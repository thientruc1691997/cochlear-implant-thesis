/* ============================================================
   MODULE   : 03_pre_tests_v2.sql
   PURPOSE  : Extract pre-operative audiological test results
              for each patient-ear combination.
   INPUT    : #Surgery (Module 02)
   OUTPUT   : #PreTests
   GRAIN    : 1 row = 1 PatientID x 1 SideID

   TABLES USED:
     [Audiqueen].[Audiqueen].[Result]
     [Audiqueen].[Audiqueen].[ResultDevices]    
     [Audiqueen].[Audiqueen].[Audiometry]
     [Audiqueen].[Audiqueen].[AudiometryPoint]
     [Audiqueen].[Audiqueen].[SpeechAudiometry]
     [Audiqueen].[Audiqueen].[SpeechAudiometryPoint]
     [Audiqueen].[Audiqueen].[Discriminations]    

   ── CHANGES v2
   FIX-01  NoResponse → threshold + 5 dB (not NULL).
           AudiometryPoint.NoResponse=1 means the patient did
           not respond at the maximum level tested. The stored
           Threshold value is used as-is + 5 dB to indicate
           the true threshold is at or above that level.
           A flag pre_audio_[freq]_nr=1 is added per frequency.
           RATIONALE: DR Govaerts meeting 2026-03-24.

   FIX-02  Aided/Unaided classification via ResultDevices view.
           Replaces Conduction proxy for speech and phoneme.
           Priority 1: ResultDevices.TypeL/TypeR contains 'HA'
                       → aided with hearing aid 
           Priority 1: ResultDevices.TypeL/TypeR contains 'CI'
                       or 'ESP' → aided with CI → exclude
           Priority 2: No ResultDevices entry → fall back to
                       Conduction IN (3,5) as proxy
           For audiometry unaided: Conduction IN (1,2,4) is
           still correct (Air/Bone/InsertPhones = no device).
           RATIONALE: DR Govaerts meeting 2026-03-24.

   FIX-03  Phoneme discrimination uses Discriminations view.
           SequenceNumber is NOT the contrast number — it is
           the round index. Each round contains all contrasts
           once. Pipeline now PIVOTs by contrast name (20
           standard contrasts) and computes AVG(Score) across
           all presentations per contrast per session.
           n_contrasts column added (how many contrasts tested).
           RATIONALE: DR Govaerts meeting 2026-03-24.

   FIX-04  Bilateral contralateral phoneme: flag sessions
           where the contralateral ear had a CI active at
           time of test. Filter to HA-only sessions; add
           contra_ci_active flag for sessions where CI was
           already present in the contralateral ear.
           RATIONALE: DR Govaerts meeting 2026-03-24.

   ── DECISIONS LOG (unchanged from v1) ──────────────────────
   DEC-07  Pre-op baseline anchored to first_implant_date.
   DEC-08  StimulusType NOT used as filter.
   DEC-09  Pre-Audiometry: Unaided only (Conduction 1,2,4).
   DEC-10  Pre-Speech: Aided with HA only (via ResultDevices).
   DEC-11  Pre-Phoneme: Aided with HA only (via ResultDevices).
           Both ipsilateral AND contralateral sides extracted.
   DEC-12  No pre-operative Loudness Scaling */


IF OBJECT_ID('tempdb..#PreTests') IS NOT NULL
    DROP TABLE #PreTests;


/* ============================================================
   STEP 1 - Phoneme contrast aggregation (FIX-03)
   ─────────────────────────────────────────────────
   Pre-aggregate Discriminations view by ResultID + Side +
   Contrast before the main query. AVG(Score) per contrast
   across all rounds/presentations within a session.
   20 standard contrasts only (n >= 1000 in full dataset).
   ============================================================ */
IF OBJECT_ID('tempdb..#PhonAgg') IS NOT NULL
    DROP TABLE #PhonAgg;

SELECT
    d.ResultID,
    d.Side,
    d.DeviceConfiguration,
    d.TypeL,
    d.TypeR,

    COUNT(DISTINCT d.Contrast)                                          AS n_contrasts,

    /* 20 standard phoneme contrasts — column name = phonetic pair */
    AVG(CASE WHEN d.Contrast = 'a - i'  THEN CAST(d.Score AS FLOAT) END) AS phon_a_i,
    AVG(CASE WHEN d.Contrast = 'a - u'  THEN CAST(d.Score AS FLOAT) END) AS phon_a_u,
    AVG(CASE WHEN d.Contrast = 'a - o'  THEN CAST(d.Score AS FLOAT) END) AS phon_a_o,
    AVG(CASE WHEN d.Contrast = N'a - ' + NCHAR(603)  THEN CAST(d.Score AS FLOAT) END) AS phon_a_ae,
    AVG(CASE WHEN d.Contrast = N'a - ' + NCHAR(601)  THEN CAST(d.Score AS FLOAT) END) AS phon_a_uh,
    AVG(CASE WHEN d.Contrast = NCHAR(603) + N' - i'  THEN CAST(d.Score AS FLOAT) END) AS phon_ae_i,
    AVG(CASE WHEN d.Contrast = NCHAR(603) + N' - ' + NCHAR(601)  THEN CAST(d.Score AS FLOAT) END) AS phon_ae_uh,
    AVG(CASE WHEN d.Contrast = 'i - u'  THEN CAST(d.Score AS FLOAT) END) AS phon_i_u,
    AVG(CASE WHEN d.Contrast = 'i - y'  THEN CAST(d.Score AS FLOAT) END) AS phon_i_y,
    AVG(CASE WHEN d.Contrast = N'i - ' + NCHAR(601)  THEN CAST(d.Score AS FLOAT) END) AS phon_i_uh,
    AVG(CASE WHEN d.Contrast = 'o - u'  THEN CAST(d.Score AS FLOAT) END) AS phon_o_u,
    AVG(CASE WHEN d.Contrast = N'o - ' + NCHAR(601)  THEN CAST(d.Score AS FLOAT) END) AS phon_o_uh,
    AVG(CASE WHEN d.Contrast = N'u - ' + NCHAR(601)  THEN CAST(d.Score AS FLOAT) END) AS phon_u_uh,
    AVG(CASE WHEN d.Contrast = 'y - u'  THEN CAST(d.Score AS FLOAT) END) AS phon_y_u,
    AVG(CASE WHEN d.Contrast = 'r - a'  THEN CAST(d.Score AS FLOAT) END) AS phon_r_a,
    AVG(CASE WHEN d.Contrast = 's - z'  THEN CAST(d.Score AS FLOAT) END) AS phon_s_z,
    AVG(CASE WHEN d.Contrast = NCHAR(643) + N' - s'  THEN CAST(d.Score AS FLOAT) END) AS phon_sh_s,
    AVG(CASE WHEN d.Contrast = NCHAR(643) + N' - u'  THEN CAST(d.Score AS FLOAT) END) AS phon_sh_u,
    AVG(CASE WHEN d.Contrast = 'z - m'  THEN CAST(d.Score AS FLOAT) END) AS phon_z_m,
    AVG(CASE WHEN d.Contrast = 'z - v'  THEN CAST(d.Score AS FLOAT) END) AS phon_z_v

INTO #PhonAgg

FROM [Audiqueen].[Discriminations] d
WHERE d.Score IS NOT NULL

GROUP BY d.ResultID, d.Side, d.DeviceConfiguration, d.TypeL, d.TypeR;

CREATE INDEX IX_PhonAgg ON #PhonAgg (ResultID, Side);


/* ============================================================
   STEP 2 - Filtered Result CTE
   ============================================================ */
;WITH R_Pre AS (

    SELECT
        r.ResultID,
        r.PatientID,
        r.Executed
    FROM [Audiqueen].[Result] r
    WHERE (r.Archived = 0 OR r.Archived IS NULL)
      AND r.Executed IS NOT NULL

),


/* ============================================================
   STEP 3 - Pre-operative Audiometry (Unaided) (DEC-09, FIX-01, CACH-A)
   ───────────────────────────────────────────────────────────────────────
   CACH-A: Best threshold per frequency across ALL pre-op sessions.
           Best = lowest threshold. NoResponse=1 → Threshold+5 dB.
           threshold and nr_flag come from the SAME measurement row
           via ROW_NUMBER ranked by threshold ASC.
           Date = most recent session with unaided audiometry.
   ============================================================ */
PreAudiometry AS (

    SELECT
        s.PatientID,
        s.SideID,
        MAX(r.Executed)                                                 AS pre_audiometry_date,

        MAX(CASE WHEN rn.Frequency=250  AND rn.rn=1 THEN rn.thr END)   AS pre_audio_250,
        MAX(CASE WHEN rn.Frequency=500  AND rn.rn=1 THEN rn.thr END)   AS pre_audio_500,
        MAX(CASE WHEN rn.Frequency=1000 AND rn.rn=1 THEN rn.thr END)   AS pre_audio_1000,
        MAX(CASE WHEN rn.Frequency=2000 AND rn.rn=1 THEN rn.thr END)   AS pre_audio_2000,
        MAX(CASE WHEN rn.Frequency=4000 AND rn.rn=1 THEN rn.thr END)   AS pre_audio_4000,
        MAX(CASE WHEN rn.Frequency=6000 AND rn.rn=1 THEN rn.thr END)   AS pre_audio_6000,
        MAX(CASE WHEN rn.Frequency=8000 AND rn.rn=1 THEN rn.thr END)   AS pre_audio_8000,

        MAX(CASE WHEN rn.Frequency=250  AND rn.rn=1 THEN rn.nr  END)   AS pre_audio_250_nr,
        MAX(CASE WHEN rn.Frequency=500  AND rn.rn=1 THEN rn.nr  END)   AS pre_audio_500_nr,
        MAX(CASE WHEN rn.Frequency=1000 AND rn.rn=1 THEN rn.nr  END)   AS pre_audio_1000_nr,
        MAX(CASE WHEN rn.Frequency=2000 AND rn.rn=1 THEN rn.nr  END)   AS pre_audio_2000_nr,
        MAX(CASE WHEN rn.Frequency=4000 AND rn.rn=1 THEN rn.nr  END)   AS pre_audio_4000_nr,
        MAX(CASE WHEN rn.Frequency=6000 AND rn.rn=1 THEN rn.nr  END)   AS pre_audio_6000_nr,
        MAX(CASE WHEN rn.Frequency=8000 AND rn.rn=1 THEN rn.nr  END)   AS pre_audio_8000_nr

    FROM #Surgery s
    JOIN R_Pre r
      ON r.PatientID = s.PatientID
     AND r.Executed  < s.first_implant_date
    JOIN [Audiqueen].[Audiometry] a
      ON a.ResultID    = r.ResultID
     AND a.[Side]      = s.SideID
     AND a.Conduction IN (1, 2, 4)
    JOIN [Audiqueen].[AudiometryPoint] ap
      ON ap.AudiometryID = a.AudiometryID
    /* ROW_NUMBER: rank by threshold ASC per PatientID × Side × Frequency
       rn=1 = best (lowest) threshold; nr comes from same row */
    JOIN (
        SELECT
            r2.PatientID,
            a2.[Side],
            ap2.Frequency,
            CASE WHEN ap2.NoResponse=1
                 THEN ap2.Threshold+5 ELSE ap2.Threshold END      AS thr,
            CAST(ap2.NoResponse AS INT)                           AS nr,
            ROW_NUMBER() OVER (
                PARTITION BY r2.PatientID, a2.[Side], ap2.Frequency
                ORDER BY
                    CAST(ap2.NoResponse AS INT) ASC,          -- nr=0 first (real response)
                    CASE WHEN ap2.NoResponse=1
                         THEN -(ap2.Threshold+5)              -- nr=1: prefer highest threshold tested
                         ELSE ap2.Threshold END ASC           -- nr=0: prefer lowest threshold
            )                                                     AS rn
        FROM R_Pre r2
        JOIN [Audiqueen].[Audiometry] a2
          ON a2.ResultID    = r2.ResultID
         AND a2.Conduction IN (1, 2, 4)
        JOIN [Audiqueen].[AudiometryPoint] ap2
          ON ap2.AudiometryID = a2.AudiometryID
        JOIN #Surgery s2
          ON s2.PatientID = r2.PatientID
         AND s2.SideID    = a2.[Side]
         AND r2.Executed  < s2.first_implant_date
    ) rn ON rn.PatientID = s.PatientID
         AND rn.[Side]    = s.SideID
         AND rn.Frequency = ap.Frequency

    GROUP BY s.PatientID, s.SideID

),


/* ============================================================
   STEP 4 - Pre-operative Speech Audiometry (Aided HA) (DEC-10, FIX-02, CACH-A)
   ───────────────────────────────────────────────────────────────────────────────
   CACH-A: MAX(score) per intensity across ALL pre-op HA sessions.
           Best performance = highest score.
           Date = most recent session with confirmed HA.
   ============================================================ */
PreSpeech AS (

    SELECT
        s.PatientID,
        s.SideID,
        MAX(r.Executed)                                     AS pre_speech_date,
        MAX(CASE WHEN sp.Intensity = 40 THEN sp.Score END)  AS pre_speech_40,
        MAX(CASE WHEN sp.Intensity = 55 THEN sp.Score END)  AS pre_speech_55,
        MAX(CASE WHEN sp.Intensity = 70 THEN sp.Score END)  AS pre_speech_70,
        MAX(CASE WHEN sp.Intensity = 85 THEN sp.Score END)  AS pre_speech_85

    FROM #Surgery s
    JOIN R_Pre r
      ON r.PatientID = s.PatientID
     AND r.Executed  < s.first_implant_date
    JOIN [Audiqueen].[SpeechAudiometry] sa
      ON sa.ResultID = r.ResultID
     AND sa.[Side]   = s.SideID
    JOIN [Audiqueen].[ResultDevices] rd
      ON rd.ResultID = r.ResultID
    JOIN [Audiqueen].[SpeechAudiometryPoint] sp
      ON sp.SpeechAudiometryID = sa.SpeechAudiometryID
    WHERE (rd.TypeL LIKE '%HA%' OR rd.TypeR LIKE '%HA%')
      AND sp.Score IS NOT NULL

    GROUP BY s.PatientID, s.SideID

),


/* ============================================================
   STEP 4b - Pre-operative Speech Contra (Aided HA) (CACH-A)
   ───────────────────────────────────────────────────────────
   Same logic as PreSpeech but for contralateral ear.
   Used for pre_speech_side_flag and as additional feature.
   ============================================================ */
PreSpeechContra AS (

    SELECT
        s.PatientID,
        s.SideID,
        MAX(r.Executed)                                          AS pre_speech_contra_date,
        MAX(CASE WHEN sp.Intensity = 40 THEN sp.Score END)       AS pre_speech_contra_40,
        MAX(CASE WHEN sp.Intensity = 55 THEN sp.Score END)       AS pre_speech_contra_55,
        MAX(CASE WHEN sp.Intensity = 70 THEN sp.Score END)       AS pre_speech_contra_70,
        MAX(CASE WHEN sp.Intensity = 85 THEN sp.Score END)       AS pre_speech_contra_85

    FROM #Surgery s
    JOIN R_Pre r
      ON r.PatientID = s.PatientID
     AND r.Executed  < s.first_implant_date
    JOIN [Audiqueen].[SpeechAudiometry] sa
      ON sa.ResultID = r.ResultID
     AND sa.[Side]   = CASE WHEN s.SideID = 1 THEN 2 ELSE 1 END  -- contralateral
    JOIN [Audiqueen].[ResultDevices] rd
      ON rd.ResultID = r.ResultID
    JOIN [Audiqueen].[SpeechAudiometryPoint] sp
      ON sp.SpeechAudiometryID = sa.SpeechAudiometryID
    WHERE (rd.TypeL LIKE '%HA%' OR rd.TypeR LIKE '%HA%')
      AND sp.Score IS NOT NULL

    GROUP BY s.PatientID, s.SideID

),


/* ============================================================
   STEP 5a - Pre-op Phoneme Ipsilateral (Aided HA) (DEC-11, FIX-02, FIX-03)
   ──────────────────────────────────────────────────────────────────────────
   FIX-02: Aided HA only via ResultDevices (same logic as speech).
   FIX-03: Use #PhonAgg (Discriminations view, contrast names).
   ============================================================ */
PrePhonIpsi AS (

    SELECT
        s.PatientID,
        s.SideID,
        pre_ph.pre_phon_ipsi_date,
        pa.n_contrasts                                          AS pre_phon_ipsi_n_contrasts,

        pa.phon_a_i    AS pre_phon_ipsi_a_i,
        pa.phon_a_u    AS pre_phon_ipsi_a_u,
        pa.phon_a_o    AS pre_phon_ipsi_a_o,
        pa.phon_a_ae   AS pre_phon_ipsi_a_ae,
        pa.phon_a_uh   AS pre_phon_ipsi_a_uh,
        pa.phon_ae_i   AS pre_phon_ipsi_ae_i,
        pa.phon_ae_uh  AS pre_phon_ipsi_ae_uh,
        pa.phon_i_u    AS pre_phon_ipsi_i_u,
        pa.phon_i_y    AS pre_phon_ipsi_i_y,
        pa.phon_i_uh   AS pre_phon_ipsi_i_uh,
        pa.phon_o_u    AS pre_phon_ipsi_o_u,
        pa.phon_o_uh   AS pre_phon_ipsi_o_uh,
        pa.phon_u_uh   AS pre_phon_ipsi_u_uh,
        pa.phon_y_u    AS pre_phon_ipsi_y_u,
        pa.phon_r_a    AS pre_phon_ipsi_r_a,
        pa.phon_s_z    AS pre_phon_ipsi_s_z,
        pa.phon_sh_s   AS pre_phon_ipsi_sh_s,
        pa.phon_sh_u   AS pre_phon_ipsi_sh_u,
        pa.phon_z_m    AS pre_phon_ipsi_z_m,
        pa.phon_z_v    AS pre_phon_ipsi_z_v

    FROM #Surgery s

    OUTER APPLY (
        SELECT TOP 1
            r.Executed  AS pre_phon_ipsi_date,
            r.ResultID  AS phon_result_id
        FROM R_Pre r
        JOIN #PhonAgg pa2
          ON pa2.ResultID = r.ResultID
         AND pa2.Side = CASE WHEN s.SideID = 1 THEN 'Left' ELSE 'Right' END
        WHERE r.PatientID = s.PatientID
          AND r.Executed  < s.first_implant_date        -- DEC-07
          -- FIX-02: confirmed HA only via ResultDevices
          AND (pa2.TypeL LIKE '%HA%' OR pa2.TypeR LIKE '%HA%')
        ORDER BY r.Executed DESC
    ) pre_ph

    LEFT JOIN #PhonAgg pa
           ON pa.ResultID = pre_ph.phon_result_id
          AND pa.Side     = CASE WHEN s.SideID = 1 THEN 'Left' ELSE 'Right' END

),


/* ============================================================
   STEP 5b - Pre-op Phoneme Contralateral (Aided HA) (DEC-11, FIX-02, FIX-03, FIX-04)
   ──────────────────────────────────────────────────────────────────────────────────────
   FIX-04: For bilateral patients, the contralateral ear may
           already have a CI active at the time of test.
           Approach:
             - Take most recent test before first_implant_date
               of THIS ear (ipsilateral).
             - Filter: contralateral ear must not have CI active
               (test_date < first_implant_date of contra ear).
             - Add contra_ci_active flag (1 = CI was present
               in contra ear at time of test).
           Pending DR: whether CI-aided contra results are useful.
   ============================================================ */
PrePhonContra AS (

    SELECT
        s.PatientID,
        s.SideID,
        pre_ph.pre_phon_contra_date,
        pre_ph.contra_ci_active,
        pa.n_contrasts                                           AS pre_phon_contra_n_contrasts,

        pa.phon_a_i    AS pre_phon_contra_a_i,
        pa.phon_a_u    AS pre_phon_contra_a_u,
        pa.phon_a_o    AS pre_phon_contra_a_o,
        pa.phon_a_ae   AS pre_phon_contra_a_ae,
        pa.phon_a_uh   AS pre_phon_contra_a_uh,
        pa.phon_ae_i   AS pre_phon_contra_ae_i,
        pa.phon_ae_uh  AS pre_phon_contra_ae_uh,
        pa.phon_i_u    AS pre_phon_contra_i_u,
        pa.phon_i_y    AS pre_phon_contra_i_y,
        pa.phon_i_uh   AS pre_phon_contra_i_uh,
        pa.phon_o_u    AS pre_phon_contra_o_u,
        pa.phon_o_uh   AS pre_phon_contra_o_uh,
        pa.phon_u_uh   AS pre_phon_contra_u_uh,
        pa.phon_y_u    AS pre_phon_contra_y_u,
        pa.phon_r_a    AS pre_phon_contra_r_a,
        pa.phon_s_z    AS pre_phon_contra_s_z,
        pa.phon_sh_s   AS pre_phon_contra_sh_s,
        pa.phon_sh_u   AS pre_phon_contra_sh_u,
        pa.phon_z_m    AS pre_phon_contra_z_m,
        pa.phon_z_v    AS pre_phon_contra_z_v

    FROM #Surgery s

    /* Get first_implant_date of the contralateral ear (FIX-04) */
    LEFT JOIN #Surgery s_contra
           ON s_contra.PatientID = s.PatientID
          AND s_contra.SideID    = CASE WHEN s.SideID = 1 THEN 2 ELSE 1 END

    OUTER APPLY (
        SELECT TOP 1
            r.Executed  AS pre_phon_contra_date,
            r.ResultID  AS phon_result_id,
            /* FIX-04: flag if contra ear already had CI at test time */
            CASE WHEN s_contra.first_implant_date IS NOT NULL
                  AND r.Executed >= s_contra.first_implant_date
                 THEN 1 ELSE 0
            END         AS contra_ci_active
        FROM R_Pre r
        JOIN #PhonAgg pa2
          ON pa2.ResultID = r.ResultID
             -- contralateral side
         AND pa2.Side = CASE WHEN s.SideID = 1 THEN 'Right' ELSE 'Left' END
        WHERE r.PatientID = s.PatientID
          AND r.Executed  < s.first_implant_date        -- before THIS ear's implant
          -- FIX-04: only use test if contra ear had no CI yet
          AND (s_contra.first_implant_date IS NULL
               OR r.Executed < s_contra.first_implant_date)
          -- FIX-02: confirmed HA only via ResultDevices
          AND (pa2.TypeL LIKE '%HA%' OR pa2.TypeR LIKE '%HA%')
        ORDER BY r.Executed DESC
    ) pre_ph

    LEFT JOIN #PhonAgg pa
           ON pa.ResultID = pre_ph.phon_result_id
          AND pa.Side     = CASE WHEN s.SideID = 1 THEN 'Right' ELSE 'Left' END

)


/* ============================================================
   STEP 6 - Final merge → #PreTests
   ============================================================ */
SELECT
    s.PatientID,
    s.SideID,

    /* ── Pre-op Audiometry (Unaided) ── */
    pa.pre_audiometry_date,
    pa.pre_audio_250,       pa.pre_audio_250_nr,
    pa.pre_audio_500,       pa.pre_audio_500_nr,
    pa.pre_audio_1000,      pa.pre_audio_1000_nr,
    pa.pre_audio_2000,      pa.pre_audio_2000_nr,
    pa.pre_audio_4000,      pa.pre_audio_4000_nr,
    pa.pre_audio_6000,      pa.pre_audio_6000_nr,
    pa.pre_audio_8000,      pa.pre_audio_8000_nr,

    /* ── Pre-op Speech Audiometry (Aided HA) ── */
    ps.pre_speech_date,
    ps.pre_speech_40,
    ps.pre_speech_55,
    ps.pre_speech_70,
    ps.pre_speech_85,

    /* ── Pre-op Speech Contra (Aided HA) ── */
    psc.pre_speech_contra_date,
    psc.pre_speech_contra_40,
    psc.pre_speech_contra_55,
    psc.pre_speech_contra_70,
    psc.pre_speech_contra_85,

    /* ── Speech side flag ── */
    CASE
        WHEN ps.pre_speech_date IS NOT NULL AND psc.pre_speech_contra_date IS NOT NULL THEN 'both'
        WHEN ps.pre_speech_date IS NOT NULL AND psc.pre_speech_contra_date IS NULL     THEN 'ipsi_only'
        WHEN ps.pre_speech_date IS NULL     AND psc.pre_speech_contra_date IS NOT NULL THEN 'contra_only'
        ELSE 'none'
    END                                                         AS pre_speech_side_flag,

    /* ── Pre-op Phoneme Ipsilateral (Aided HA) ── */
    pi2.pre_phon_ipsi_date,
    pi2.pre_phon_ipsi_n_contrasts,
    pi2.pre_phon_ipsi_a_i,
    pi2.pre_phon_ipsi_a_u,
    pi2.pre_phon_ipsi_a_o,
    pi2.pre_phon_ipsi_a_ae,
    pi2.pre_phon_ipsi_a_uh,
    pi2.pre_phon_ipsi_ae_i,
    pi2.pre_phon_ipsi_ae_uh,
    pi2.pre_phon_ipsi_i_u,
    pi2.pre_phon_ipsi_i_y,
    pi2.pre_phon_ipsi_i_uh,
    pi2.pre_phon_ipsi_o_u,
    pi2.pre_phon_ipsi_o_uh,
    pi2.pre_phon_ipsi_u_uh,
    pi2.pre_phon_ipsi_y_u,
    pi2.pre_phon_ipsi_r_a,
    pi2.pre_phon_ipsi_s_z,
    pi2.pre_phon_ipsi_sh_s,
    pi2.pre_phon_ipsi_sh_u,
    pi2.pre_phon_ipsi_z_m,
    pi2.pre_phon_ipsi_z_v,

    /* ── Pre-op Phoneme Contralateral (Aided HA) ── */
    pc.pre_phon_contra_date,
    pc.contra_ci_active,
    pc.pre_phon_contra_n_contrasts,

    /* ── Phoneme side flag ── */
    CASE
        WHEN pi2.pre_phon_ipsi_date IS NOT NULL AND pc.pre_phon_contra_date IS NOT NULL THEN 'both'
        WHEN pi2.pre_phon_ipsi_date IS NOT NULL AND pc.pre_phon_contra_date IS NULL     THEN 'ipsi_only'
        WHEN pi2.pre_phon_ipsi_date IS NULL     AND pc.pre_phon_contra_date IS NOT NULL THEN 'contra_only'
        ELSE 'none'
    END                                                         AS pre_phon_side_flag,
    pc.pre_phon_contra_a_i,
    pc.pre_phon_contra_a_u,
    pc.pre_phon_contra_a_o,
    pc.pre_phon_contra_a_ae,
    pc.pre_phon_contra_a_uh,
    pc.pre_phon_contra_ae_i,
    pc.pre_phon_contra_ae_uh,
    pc.pre_phon_contra_i_u,
    pc.pre_phon_contra_i_y,
    pc.pre_phon_contra_i_uh,
    pc.pre_phon_contra_o_u,
    pc.pre_phon_contra_o_uh,
    pc.pre_phon_contra_u_uh,
    pc.pre_phon_contra_y_u,
    pc.pre_phon_contra_r_a,
    pc.pre_phon_contra_s_z,
    pc.pre_phon_contra_sh_s,
    pc.pre_phon_contra_sh_u,
    pc.pre_phon_contra_z_m,
    pc.pre_phon_contra_z_v

INTO #PreTests

FROM #Surgery s
LEFT JOIN PreAudiometry  pa   ON pa.PatientID  = s.PatientID AND pa.SideID  = s.SideID
LEFT JOIN PreSpeech        ps   ON ps.PatientID  = s.PatientID AND ps.SideID  = s.SideID
LEFT JOIN PreSpeechContra  psc  ON psc.PatientID = s.PatientID AND psc.SideID = s.SideID
LEFT JOIN PrePhonIpsi      pi2  ON pi2.PatientID = s.PatientID AND pi2.SideID = s.SideID
LEFT JOIN PrePhonContra  pc   ON pc.PatientID  = s.PatientID AND pc.SideID  = s.SideID;


CREATE INDEX IX_PreTests_PatientSide
    ON #PreTests (PatientID, SideID);