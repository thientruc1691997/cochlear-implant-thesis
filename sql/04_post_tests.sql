/* ============================================================
   MODULE   : 04_post_tests_v2.sql
   PURPOSE  : Extract post-operative audiological test results
              at three clinical follow-up time points.
   INPUT    : #Surgery (Module 02), #PhonAgg (Module 03)
   OUTPUT   : #PostTests
   GRAIN    : 1 row = 1 PatientID x 1 SideID

   NAMING CONVENTION:
     post_audio_[freq]_[time]              Audiometry threshold (dB HL)
     post_speech_[intensity]_[time]        Speech perception score (%)
     post_phon_[contrast]_[time]           Phoneme contrast score (0.0-1.0)
     post_ls_[freq]_[intensity]_[time]     Loudness scaling score

   TIME POINTS:
     _3m  = 3 months  (window: months 1-6)
     _11m = 11 months (window: months 7-18)
     _36m = 36 months (window: months 24-48)

   ── CHANGES v2 ─────────────────────────────────────────────
   FIX-01  NoResponse → Threshold + 5 dB (not NULL).
           Same logic as Module 03.
           Flag post_audio_[freq]_nr_[time] added.

   FIX-02  Session selection: BEST result within window,
           not nearest to target month.
           Speech:    MAX(score at 55 dB) → best session
           Audiometry: MAX(n_frequencies) → most complete
           Phoneme:   MAX(n_contrasts) → most complete
           Tie-break: ABS(months - target) ASC

   FIX-03  Time windows widened (DR Govaerts meeting 2026-03-24):
           3m:  months 1-6   (was 2-4)
           11m: months 7-18  (was 8-14)
           36m: months 24-48 (was 30-42)

   FIX-04  Phoneme: Discriminations view + contrast names.
           Same logic as Module 03.
           Uses #PhonAgg temp table (built in Module 03).
           AVG(Score) per contrast across all rounds.

   ── DECISIONS LOG ──────────────────────────────────────────
   DEC-13  Post-op anchored to last_implant_date.
   DEC-14  Time windows widened — see FIX-03.
   DEC-15  All post-op tests: CI-aided (ResultDevices CI/ESP).
   DEC-16  Audiometry: 7 frequencies (250-8000 Hz).
   DEC-17  Phoneme: ipsilateral (implanted ear) only.
   DEC-18  Loudness Scaling: 4 intensities x 6 frequencies.
   DEC-19  extended_loudness_protocol = 1 if >= 2020-04-10.
   ── END DECISIONS LOG ──────────────────────────────────────
   ============================================================ */


/* ============================================================
   MODULE   : 04_post_tests_v2.sql
   PURPOSE  : Extract post-operative audiological test results
              at three clinical follow-up time points.
   INPUT    : #Surgery (Module 02), #PhonAgg (Module 03)
   OUTPUT   : #PostTests
   GRAIN    : 1 row = 1 PatientID x 1 SideID

   NAMING CONVENTION:
     post_audio_[freq]_[time]              Audiometry threshold (dB HL)
     post_speech_[intensity]_[time]        Speech perception score (%)
     post_phon_[contrast]_[time]           Phoneme contrast score (0.0-1.0)
     post_ls_[freq]_[intensity]_[time]     Loudness scaling score

   TIME POINTS:
     _3m  = 3 months  (window: months 1-6)
     _11m = 11 months (window: months 7-18)
     _36m = 36 months (window: months 24-48)

   ── CHANGES v2 ─────────────────────────────────────────────
   FIX-01  NoResponse → Threshold + 5 dB (not NULL).
           Same logic as Module 03.
           Flag post_audio_[freq]_nr_[time] added.

   FIX-02  Session selection: BEST result within window,
           not nearest to target month.
           Speech:    MAX(score at 55 dB) → best session
           Audiometry: MAX(n_frequencies) → most complete
           Phoneme:   MAX(n_contrasts) → most complete
           Tie-break: ABS(months - target) ASC

   FIX-03  Time windows widened (DR Govaerts meeting 2026-03-24):
           3m:  months 1-6   (was 2-4)
           11m: months 7-18  (was 8-14)
           36m: months 24-48 (was 30-42)

   FIX-04  Phoneme: Discriminations view + contrast names.
           Same logic as Module 03.
           Uses #PhonAgg temp table (built in Module 03).
           AVG(Score) per contrast across all rounds.

   ── DECISIONS LOG ──────────────────────────────────────────
   DEC-13  Post-op anchored to last_implant_date.
   DEC-14  Time windows widened — see FIX-03.
   DEC-15  All post-op tests: CI-aided (ResultDevices CI/ESP).
   DEC-16  Audiometry: 7 frequencies (250-8000 Hz).
   DEC-17  Phoneme: ipsilateral (implanted ear) only.
   DEC-18  Loudness Scaling: 4 intensities x 6 frequencies.
   DEC-19  extended_loudness_protocol = 1 if >= 2020-04-10.
   ── END DECISIONS LOG ──────────────────────────────────────
   ============================================================ */


IF OBJECT_ID('tempdb..#PostTests') IS NOT NULL
    DROP TABLE #PostTests;


/* ============================================================
   STEP 1 - Filtered Result CTE
   ============================================================ */
;WITH R_Post AS (
    SELECT r.ResultID, r.PatientID, r.Executed
    FROM [Audiqueen].[Result] r
    WHERE (r.Archived = 0 OR r.Archived IS NULL)
      AND r.Executed IS NOT NULL
),


/* ============================================================
   STEP 2 - Post-operative Audiometry
   Window logic uses DATEADD for exact date windows.
   CACH-A: Best threshold per frequency per window.
           Response rows preferred over NoResponse rows.
           If NoResponse=1, threshold is adjusted as Threshold + 5 dB.
   ============================================================ */
PostAudiometry AS (
    SELECT
        s.PatientID,
        s.SideID,

        /* 3m */
        MAX(CASE WHEN m = 3 THEN dt END) AS post_audio_date_3m,
        MAX(CASE WHEN m = 3 THEN months_actual END) AS post_audio_months_actual_3m,

        MAX(CASE WHEN m = 3 AND freq = 250  AND rn = 1 THEN thr END) AS post_audio_250_3m,
        MAX(CASE WHEN m = 3 AND freq = 500  AND rn = 1 THEN thr END) AS post_audio_500_3m,
        MAX(CASE WHEN m = 3 AND freq = 1000 AND rn = 1 THEN thr END) AS post_audio_1000_3m,
        MAX(CASE WHEN m = 3 AND freq = 2000 AND rn = 1 THEN thr END) AS post_audio_2000_3m,
        MAX(CASE WHEN m = 3 AND freq = 4000 AND rn = 1 THEN thr END) AS post_audio_4000_3m,
        MAX(CASE WHEN m = 3 AND freq = 6000 AND rn = 1 THEN thr END) AS post_audio_6000_3m,
        MAX(CASE WHEN m = 3 AND freq = 8000 AND rn = 1 THEN thr END) AS post_audio_8000_3m,

        MAX(CASE WHEN m = 3 AND freq = 250  AND rn = 1 THEN nr END) AS post_audio_250_nr_3m,
        MAX(CASE WHEN m = 3 AND freq = 500  AND rn = 1 THEN nr END) AS post_audio_500_nr_3m,
        MAX(CASE WHEN m = 3 AND freq = 1000 AND rn = 1 THEN nr END) AS post_audio_1000_nr_3m,
        MAX(CASE WHEN m = 3 AND freq = 2000 AND rn = 1 THEN nr END) AS post_audio_2000_nr_3m,
        MAX(CASE WHEN m = 3 AND freq = 4000 AND rn = 1 THEN nr END) AS post_audio_4000_nr_3m,
        MAX(CASE WHEN m = 3 AND freq = 6000 AND rn = 1 THEN nr END) AS post_audio_6000_nr_3m,
        MAX(CASE WHEN m = 3 AND freq = 8000 AND rn = 1 THEN nr END) AS post_audio_8000_nr_3m,

        /* 11m */
        MAX(CASE WHEN m = 11 THEN dt END) AS post_audio_date_11m,
        MAX(CASE WHEN m = 11 THEN months_actual END) AS post_audio_months_actual_11m,

        MAX(CASE WHEN m = 11 AND freq = 250  AND rn = 1 THEN thr END) AS post_audio_250_11m,
        MAX(CASE WHEN m = 11 AND freq = 500  AND rn = 1 THEN thr END) AS post_audio_500_11m,
        MAX(CASE WHEN m = 11 AND freq = 1000 AND rn = 1 THEN thr END) AS post_audio_1000_11m,
        MAX(CASE WHEN m = 11 AND freq = 2000 AND rn = 1 THEN thr END) AS post_audio_2000_11m,
        MAX(CASE WHEN m = 11 AND freq = 4000 AND rn = 1 THEN thr END) AS post_audio_4000_11m,
        MAX(CASE WHEN m = 11 AND freq = 6000 AND rn = 1 THEN thr END) AS post_audio_6000_11m,
        MAX(CASE WHEN m = 11 AND freq = 8000 AND rn = 1 THEN thr END) AS post_audio_8000_11m,

        MAX(CASE WHEN m = 11 AND freq = 250  AND rn = 1 THEN nr END) AS post_audio_250_nr_11m,
        MAX(CASE WHEN m = 11 AND freq = 500  AND rn = 1 THEN nr END) AS post_audio_500_nr_11m,
        MAX(CASE WHEN m = 11 AND freq = 1000 AND rn = 1 THEN nr END) AS post_audio_1000_nr_11m,
        MAX(CASE WHEN m = 11 AND freq = 2000 AND rn = 1 THEN nr END) AS post_audio_2000_nr_11m,
        MAX(CASE WHEN m = 11 AND freq = 4000 AND rn = 1 THEN nr END) AS post_audio_4000_nr_11m,
        MAX(CASE WHEN m = 11 AND freq = 6000 AND rn = 1 THEN nr END) AS post_audio_6000_nr_11m,
        MAX(CASE WHEN m = 11 AND freq = 8000 AND rn = 1 THEN nr END) AS post_audio_8000_nr_11m,

        /* 36m */
        MAX(CASE WHEN m = 36 THEN dt END) AS post_audio_date_36m,
        MAX(CASE WHEN m = 36 THEN months_actual END) AS post_audio_months_actual_36m,

        MAX(CASE WHEN m = 36 AND freq = 250  AND rn = 1 THEN thr END) AS post_audio_250_36m,
        MAX(CASE WHEN m = 36 AND freq = 500  AND rn = 1 THEN thr END) AS post_audio_500_36m,
        MAX(CASE WHEN m = 36 AND freq = 1000 AND rn = 1 THEN thr END) AS post_audio_1000_36m,
        MAX(CASE WHEN m = 36 AND freq = 2000 AND rn = 1 THEN thr END) AS post_audio_2000_36m,
        MAX(CASE WHEN m = 36 AND freq = 4000 AND rn = 1 THEN thr END) AS post_audio_4000_36m,
        MAX(CASE WHEN m = 36 AND freq = 6000 AND rn = 1 THEN thr END) AS post_audio_6000_36m,
        MAX(CASE WHEN m = 36 AND freq = 8000 AND rn = 1 THEN thr END) AS post_audio_8000_36m,

        MAX(CASE WHEN m = 36 AND freq = 250  AND rn = 1 THEN nr END) AS post_audio_250_nr_36m,
        MAX(CASE WHEN m = 36 AND freq = 500  AND rn = 1 THEN nr END) AS post_audio_500_nr_36m,
        MAX(CASE WHEN m = 36 AND freq = 1000 AND rn = 1 THEN nr END) AS post_audio_1000_nr_36m,
        MAX(CASE WHEN m = 36 AND freq = 2000 AND rn = 1 THEN nr END) AS post_audio_2000_nr_36m,
        MAX(CASE WHEN m = 36 AND freq = 4000 AND rn = 1 THEN nr END) AS post_audio_4000_nr_36m,
        MAX(CASE WHEN m = 36 AND freq = 6000 AND rn = 1 THEN nr END) AS post_audio_6000_nr_36m,
        MAX(CASE WHEN m = 36 AND freq = 8000 AND rn = 1 THEN nr END) AS post_audio_8000_nr_36m

    FROM #Surgery s

    JOIN (
        SELECT
            z.*,
            ROW_NUMBER() OVER (
                PARTITION BY z.PatientID, z.[Side], z.freq, z.m
                ORDER BY
                    z.nr ASC,
                    CASE
                        WHEN z.nr = 1 THEN -z.thr
                        ELSE z.thr
                    END ASC,
                    z.dt DESC,
                    z.ResultID DESC
            ) AS rn
        FROM (
            SELECT
                r.ResultID,
                r.PatientID,
                a.[Side],
                r.Executed AS dt,
                ap.Frequency AS freq,
                CASE
                    WHEN ap.NoResponse = 1 THEN ap.Threshold + 5
                    ELSE ap.Threshold
                END AS thr,
                CAST(ap.NoResponse AS INT) AS nr,

                CAST(DATEDIFF(DAY, s2.last_implant_date, r.Executed) / 30.44 AS DECIMAL(6,2)) AS months_actual,

                CASE
                    WHEN r.Executed >  s2.last_implant_date
                     AND r.Executed <  DATEADD(MONTH, 7, s2.last_implant_date)
                    THEN 3

                    WHEN r.Executed >= DATEADD(MONTH, 7, s2.last_implant_date)
                     AND r.Executed <  DATEADD(MONTH, 19, s2.last_implant_date)
                    THEN 11

                    WHEN r.Executed >= DATEADD(MONTH, 19, s2.last_implant_date)
                     AND r.Executed <  DATEADD(MONTH, 49, s2.last_implant_date)
                    THEN 36
                END AS m

            FROM R_Post r

            JOIN [Audiqueen].[Audiometry] a
              ON a.ResultID = r.ResultID
             AND a.Conduction = 3

            JOIN [Audiqueen].[AudiometryPoint] ap
              ON ap.AudiometryID = a.AudiometryID

            JOIN #Surgery s2
              ON s2.PatientID = r.PatientID
             AND s2.SideID = a.[Side]

            WHERE r.Executed > s2.last_implant_date
              AND r.Executed < DATEADD(MONTH, 49, s2.last_implant_date)
              AND ap.Frequency IN (250, 500, 1000, 2000, 4000, 6000, 8000)
              AND ap.Threshold IS NOT NULL
        ) z
        WHERE z.m IS NOT NULL
    ) x
      ON x.PatientID = s.PatientID
     AND x.[Side] = s.SideID

    GROUP BY s.PatientID, s.SideID
),


/* ============================================================
   STEP 3 - Post-operative Speech Audiometry
   Window logic uses DATEADD for exact date windows.
   Best performance = MAX(score) per intensity per window.
   ============================================================ */
PostSpeech AS (
    SELECT
        s.PatientID,
        s.SideID,

        /* 3m */
        MAX(CASE WHEN m = 3 THEN dt END) AS post_speech_date_3m,
        MAX(CASE WHEN m = 3 THEN months_actual END) AS post_speech_months_actual_3m,
        MAX(CASE WHEN m = 3 AND intensity = 40 THEN score END) AS post_speech_40_3m,
        MAX(CASE WHEN m = 3 AND intensity = 55 THEN score END) AS post_speech_55_3m,
        MAX(CASE WHEN m = 3 AND intensity = 70 THEN score END) AS post_speech_70_3m,
        MAX(CASE WHEN m = 3 AND intensity = 85 THEN score END) AS post_speech_85_3m,

        /* 11m */
        MAX(CASE WHEN m = 11 THEN dt END) AS post_speech_date_11m,
        MAX(CASE WHEN m = 11 THEN months_actual END) AS post_speech_months_actual_11m,
        MAX(CASE WHEN m = 11 AND intensity = 40 THEN score END) AS post_speech_40_11m,
        MAX(CASE WHEN m = 11 AND intensity = 55 THEN score END) AS post_speech_55_11m,
        MAX(CASE WHEN m = 11 AND intensity = 70 THEN score END) AS post_speech_70_11m,
        MAX(CASE WHEN m = 11 AND intensity = 85 THEN score END) AS post_speech_85_11m,

        /* 36m */
        MAX(CASE WHEN m = 36 THEN dt END) AS post_speech_date_36m,
        MAX(CASE WHEN m = 36 THEN months_actual END) AS post_speech_months_actual_36m,
        MAX(CASE WHEN m = 36 AND intensity = 40 THEN score END) AS post_speech_40_36m,
        MAX(CASE WHEN m = 36 AND intensity = 55 THEN score END) AS post_speech_55_36m,
        MAX(CASE WHEN m = 36 AND intensity = 70 THEN score END) AS post_speech_70_36m,
        MAX(CASE WHEN m = 36 AND intensity = 85 THEN score END) AS post_speech_85_36m

    FROM #Surgery s

    JOIN (
        SELECT
            r.PatientID,
            sa.[Side],
            r.Executed AS dt,
            sap.Intensity AS intensity,
            sap.Score AS score,

            CAST(DATEDIFF(DAY, s2.last_implant_date, r.Executed) / 30.44 AS DECIMAL(6,2)) AS months_actual,

            CASE
                WHEN r.Executed >  s2.last_implant_date
                 AND r.Executed <  DATEADD(MONTH, 7, s2.last_implant_date)
                THEN 3

                WHEN r.Executed >= DATEADD(MONTH, 7, s2.last_implant_date)
                 AND r.Executed <  DATEADD(MONTH, 19, s2.last_implant_date)
                THEN 11

                WHEN r.Executed >= DATEADD(MONTH, 19, s2.last_implant_date)
                 AND r.Executed <  DATEADD(MONTH, 49, s2.last_implant_date)
                THEN 36
            END AS m

        FROM R_Post r

        JOIN [Audiqueen].[SpeechAudiometry] sa
          ON sa.ResultID = r.ResultID
         AND sa.Conduction = 3

        JOIN [Audiqueen].[SpeechAudiometryPoint] sap
          ON sap.SpeechAudiometryID = sa.SpeechAudiometryID

        JOIN #Surgery s2
          ON s2.PatientID = r.PatientID
         AND s2.SideID = sa.[Side]

        WHERE r.Executed > s2.last_implant_date
          AND r.Executed < DATEADD(MONTH, 49, s2.last_implant_date)
          AND sap.Score IS NOT NULL
    ) x
      ON x.PatientID = s.PatientID
     AND x.[Side] = s.SideID
     AND x.m IS NOT NULL

    GROUP BY s.PatientID, s.SideID
),


/* ============================================================
   STEP 4 - Post-operative Phoneme with cumulative best
   Window logic uses DATEADD for exact date windows.

   Scores:
     3m  = cumulative best from surgery to < 7 months
     11m = cumulative best from surgery to < 19 months
     36m = cumulative best from surgery to < 49 months

   Date / n_sessions / n_contrasts:
     actual window only:
       3m  = > surgery and < 7 months
       11m = >= 7 and < 19 months
       36m = >= 19 and < 49 months
   ============================================================ */
PostPhoneme AS (
    SELECT
        s.PatientID,
        s.SideID,

        /* 3m actual visit info */
        MAX(CASE WHEN w.actual_m = 3 THEN r.Executed END) AS post_phon_date_3m,
        MAX(CASE WHEN w.actual_m = 3 THEN w.months_actual END) AS post_phon_months_actual_3m,
        COUNT(DISTINCT CASE WHEN w.actual_m = 3 THEN r.ResultID END) AS post_phon_n_sessions_3m,
        MAX(CASE WHEN w.actual_m = 3 THEN pa.n_contrasts END) AS post_phon_n_contrasts_3m,

        /* 3m cumulative best scores */
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_a_i END) AS post_phon_a_i_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_a_u END) AS post_phon_a_u_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_a_o END) AS post_phon_a_o_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_a_ae END) AS post_phon_a_ae_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_a_uh END) AS post_phon_a_uh_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_ae_i END) AS post_phon_ae_i_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_ae_uh END) AS post_phon_ae_uh_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_i_u END) AS post_phon_i_u_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_i_y END) AS post_phon_i_y_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_i_uh END) AS post_phon_i_uh_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_o_u END) AS post_phon_o_u_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_o_uh END) AS post_phon_o_uh_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_u_uh END) AS post_phon_u_uh_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_y_u END) AS post_phon_y_u_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_r_a END) AS post_phon_r_a_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_s_z END) AS post_phon_s_z_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_sh_s END) AS post_phon_sh_s_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_sh_u END) AS post_phon_sh_u_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_z_m END) AS post_phon_z_m_3m,
        MAX(CASE WHEN w.cum_3m = 1 THEN pa.phon_z_v END) AS post_phon_z_v_3m,

        /* 11m actual visit info */
        MAX(CASE WHEN w.actual_m = 11 THEN r.Executed END) AS post_phon_date_11m,
        MAX(CASE WHEN w.actual_m = 11 THEN w.months_actual END) AS post_phon_months_actual_11m,
        COUNT(DISTINCT CASE WHEN w.actual_m = 11 THEN r.ResultID END) AS post_phon_n_sessions_11m,
        MAX(CASE WHEN w.actual_m = 11 THEN pa.n_contrasts END) AS post_phon_n_contrasts_11m,

        /* 11m cumulative best scores */
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_a_i END) AS post_phon_a_i_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_a_u END) AS post_phon_a_u_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_a_o END) AS post_phon_a_o_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_a_ae END) AS post_phon_a_ae_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_a_uh END) AS post_phon_a_uh_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_ae_i END) AS post_phon_ae_i_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_ae_uh END) AS post_phon_ae_uh_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_i_u END) AS post_phon_i_u_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_i_y END) AS post_phon_i_y_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_i_uh END) AS post_phon_i_uh_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_o_u END) AS post_phon_o_u_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_o_uh END) AS post_phon_o_uh_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_u_uh END) AS post_phon_u_uh_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_y_u END) AS post_phon_y_u_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_r_a END) AS post_phon_r_a_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_s_z END) AS post_phon_s_z_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_sh_s END) AS post_phon_sh_s_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_sh_u END) AS post_phon_sh_u_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_z_m END) AS post_phon_z_m_11m,
        MAX(CASE WHEN w.cum_11m = 1 THEN pa.phon_z_v END) AS post_phon_z_v_11m,

        /* 36m actual visit info */
        MAX(CASE WHEN w.actual_m = 36 THEN r.Executed END) AS post_phon_date_36m,
        MAX(CASE WHEN w.actual_m = 36 THEN w.months_actual END) AS post_phon_months_actual_36m,
        COUNT(DISTINCT CASE WHEN w.actual_m = 36 THEN r.ResultID END) AS post_phon_n_sessions_36m,
        MAX(CASE WHEN w.actual_m = 36 THEN pa.n_contrasts END) AS post_phon_n_contrasts_36m,

        /* 36m cumulative best scores */
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_a_i END) AS post_phon_a_i_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_a_u END) AS post_phon_a_u_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_a_o END) AS post_phon_a_o_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_a_ae END) AS post_phon_a_ae_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_a_uh END) AS post_phon_a_uh_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_ae_i END) AS post_phon_ae_i_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_ae_uh END) AS post_phon_ae_uh_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_i_u END) AS post_phon_i_u_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_i_y END) AS post_phon_i_y_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_i_uh END) AS post_phon_i_uh_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_o_u END) AS post_phon_o_u_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_o_uh END) AS post_phon_o_uh_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_u_uh END) AS post_phon_u_uh_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_y_u END) AS post_phon_y_u_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_r_a END) AS post_phon_r_a_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_s_z END) AS post_phon_s_z_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_sh_s END) AS post_phon_sh_s_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_sh_u END) AS post_phon_sh_u_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_z_m END) AS post_phon_z_m_36m,
        MAX(CASE WHEN w.cum_36m = 1 THEN pa.phon_z_v END) AS post_phon_z_v_36m

    FROM #Surgery s

    JOIN R_Post r
      ON r.PatientID = s.PatientID
     AND r.Executed > s.last_implant_date
     AND r.Executed < DATEADD(MONTH, 49, s.last_implant_date)

    JOIN #PhonAgg pa
      ON pa.ResultID = r.ResultID
     AND pa.Side = CASE WHEN s.SideID = 1 THEN 'Left' ELSE 'Right' END

    CROSS APPLY (
        SELECT
            CAST(DATEDIFF(DAY, s.last_implant_date, r.Executed) / 30.44 AS DECIMAL(6,2)) AS months_actual,

            CASE
                WHEN r.Executed >  s.last_implant_date
                 AND r.Executed <  DATEADD(MONTH, 7, s.last_implant_date)
                THEN 3

                WHEN r.Executed >= DATEADD(MONTH, 7, s.last_implant_date)
                 AND r.Executed <  DATEADD(MONTH, 19, s.last_implant_date)
                THEN 11

                WHEN r.Executed >= DATEADD(MONTH, 19, s.last_implant_date)
                 AND r.Executed <  DATEADD(MONTH, 49, s.last_implant_date)
                THEN 36
            END AS actual_m,

            CASE WHEN r.Executed > s.last_implant_date
                   AND r.Executed < DATEADD(MONTH, 7, s.last_implant_date)
                 THEN 1 ELSE 0 END AS cum_3m,

            CASE WHEN r.Executed > s.last_implant_date
                   AND r.Executed < DATEADD(MONTH, 19, s.last_implant_date)
                 THEN 1 ELSE 0 END AS cum_11m,

            CASE WHEN r.Executed > s.last_implant_date
                   AND r.Executed < DATEADD(MONTH, 49, s.last_implant_date)
                 THEN 1 ELSE 0 END AS cum_36m
    ) w

    GROUP BY s.PatientID, s.SideID
),

/* ============================================================
   STEP 5 - Post-operative Loudness Scaling (FIX-02, FIX-03)
   ─────────────────────────────────────────────────────────────
   FIX-02: Nearest to target month (no "best" concept for LS).
   FIX-03: Windows widened.
   ============================================================ */
PostLoudness AS (
    SELECT
        s.PatientID,
        s.SideID,

        /* 3m */
        sess_ls_3m.post_ls_date_3m,
        sess_ls_3m.ext_protocol_3m              AS extended_loudness_protocol_3m,
        MAX(CASE WHEN ls3m.Frequency=250  AND CAST(lsp3m.Intensity AS INT)=35 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_250_35_3m,
        MAX(CASE WHEN ls3m.Frequency=250  AND CAST(lsp3m.Intensity AS INT)=50 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_250_50_3m,
        MAX(CASE WHEN ls3m.Frequency=250  AND CAST(lsp3m.Intensity AS INT)=65 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_250_65_3m,
        MAX(CASE WHEN ls3m.Frequency=250  AND CAST(lsp3m.Intensity AS INT)=80 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_250_80_3m,
        MAX(CASE WHEN ls3m.Frequency=500  AND CAST(lsp3m.Intensity AS INT)=35 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_500_35_3m,
        MAX(CASE WHEN ls3m.Frequency=500  AND CAST(lsp3m.Intensity AS INT)=50 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_500_50_3m,
        MAX(CASE WHEN ls3m.Frequency=500  AND CAST(lsp3m.Intensity AS INT)=65 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_500_65_3m,
        MAX(CASE WHEN ls3m.Frequency=500  AND CAST(lsp3m.Intensity AS INT)=80 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_500_80_3m,
        MAX(CASE WHEN ls3m.Frequency=1000 AND CAST(lsp3m.Intensity AS INT)=35 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_1000_35_3m,
        MAX(CASE WHEN ls3m.Frequency=1000 AND CAST(lsp3m.Intensity AS INT)=50 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_1000_50_3m,
        MAX(CASE WHEN ls3m.Frequency=1000 AND CAST(lsp3m.Intensity AS INT)=65 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_1000_65_3m,
        MAX(CASE WHEN ls3m.Frequency=1000 AND CAST(lsp3m.Intensity AS INT)=80 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_1000_80_3m,
        MAX(CASE WHEN ls3m.Frequency=2000 AND CAST(lsp3m.Intensity AS INT)=35 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_2000_35_3m,
        MAX(CASE WHEN ls3m.Frequency=2000 AND CAST(lsp3m.Intensity AS INT)=50 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_2000_50_3m,
        MAX(CASE WHEN ls3m.Frequency=2000 AND CAST(lsp3m.Intensity AS INT)=65 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_2000_65_3m,
        MAX(CASE WHEN ls3m.Frequency=2000 AND CAST(lsp3m.Intensity AS INT)=80 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_2000_80_3m,
        MAX(CASE WHEN ls3m.Frequency=4000 AND CAST(lsp3m.Intensity AS INT)=35 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_4000_35_3m,
        MAX(CASE WHEN ls3m.Frequency=4000 AND CAST(lsp3m.Intensity AS INT)=50 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_4000_50_3m,
        MAX(CASE WHEN ls3m.Frequency=4000 AND CAST(lsp3m.Intensity AS INT)=65 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_4000_65_3m,
        MAX(CASE WHEN ls3m.Frequency=4000 AND CAST(lsp3m.Intensity AS INT)=80 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_4000_80_3m,
        MAX(CASE WHEN ls3m.Frequency=6000 AND CAST(lsp3m.Intensity AS INT)=35 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_6000_35_3m,
        MAX(CASE WHEN ls3m.Frequency=6000 AND CAST(lsp3m.Intensity AS INT)=50 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_6000_50_3m,
        MAX(CASE WHEN ls3m.Frequency=6000 AND CAST(lsp3m.Intensity AS INT)=65 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_6000_65_3m,
        MAX(CASE WHEN ls3m.Frequency=6000 AND CAST(lsp3m.Intensity AS INT)=80 THEN CAST(lsp3m.Score AS FLOAT) END) AS post_ls_6000_80_3m,

        /* 11m */
        sess_ls_11m.post_ls_date_11m,
        sess_ls_11m.ext_protocol_11m            AS extended_loudness_protocol_11m,
        MAX(CASE WHEN ls11m.Frequency=250  AND CAST(lsp11m.Intensity AS INT)=35 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_250_35_11m,
        MAX(CASE WHEN ls11m.Frequency=250  AND CAST(lsp11m.Intensity AS INT)=50 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_250_50_11m,
        MAX(CASE WHEN ls11m.Frequency=250  AND CAST(lsp11m.Intensity AS INT)=65 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_250_65_11m,
        MAX(CASE WHEN ls11m.Frequency=250  AND CAST(lsp11m.Intensity AS INT)=80 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_250_80_11m,
        MAX(CASE WHEN ls11m.Frequency=500  AND CAST(lsp11m.Intensity AS INT)=35 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_500_35_11m,
        MAX(CASE WHEN ls11m.Frequency=500  AND CAST(lsp11m.Intensity AS INT)=50 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_500_50_11m,
        MAX(CASE WHEN ls11m.Frequency=500  AND CAST(lsp11m.Intensity AS INT)=65 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_500_65_11m,
        MAX(CASE WHEN ls11m.Frequency=500  AND CAST(lsp11m.Intensity AS INT)=80 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_500_80_11m,
        MAX(CASE WHEN ls11m.Frequency=1000 AND CAST(lsp11m.Intensity AS INT)=35 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_1000_35_11m,
        MAX(CASE WHEN ls11m.Frequency=1000 AND CAST(lsp11m.Intensity AS INT)=50 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_1000_50_11m,
        MAX(CASE WHEN ls11m.Frequency=1000 AND CAST(lsp11m.Intensity AS INT)=65 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_1000_65_11m,
        MAX(CASE WHEN ls11m.Frequency=1000 AND CAST(lsp11m.Intensity AS INT)=80 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_1000_80_11m,
        MAX(CASE WHEN ls11m.Frequency=2000 AND CAST(lsp11m.Intensity AS INT)=35 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_2000_35_11m,
        MAX(CASE WHEN ls11m.Frequency=2000 AND CAST(lsp11m.Intensity AS INT)=50 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_2000_50_11m,
        MAX(CASE WHEN ls11m.Frequency=2000 AND CAST(lsp11m.Intensity AS INT)=65 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_2000_65_11m,
        MAX(CASE WHEN ls11m.Frequency=2000 AND CAST(lsp11m.Intensity AS INT)=80 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_2000_80_11m,
        MAX(CASE WHEN ls11m.Frequency=4000 AND CAST(lsp11m.Intensity AS INT)=35 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_4000_35_11m,
        MAX(CASE WHEN ls11m.Frequency=4000 AND CAST(lsp11m.Intensity AS INT)=50 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_4000_50_11m,
        MAX(CASE WHEN ls11m.Frequency=4000 AND CAST(lsp11m.Intensity AS INT)=65 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_4000_65_11m,
        MAX(CASE WHEN ls11m.Frequency=4000 AND CAST(lsp11m.Intensity AS INT)=80 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_4000_80_11m,
        MAX(CASE WHEN ls11m.Frequency=6000 AND CAST(lsp11m.Intensity AS INT)=35 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_6000_35_11m,
        MAX(CASE WHEN ls11m.Frequency=6000 AND CAST(lsp11m.Intensity AS INT)=50 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_6000_50_11m,
        MAX(CASE WHEN ls11m.Frequency=6000 AND CAST(lsp11m.Intensity AS INT)=65 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_6000_65_11m,
        MAX(CASE WHEN ls11m.Frequency=6000 AND CAST(lsp11m.Intensity AS INT)=80 THEN CAST(lsp11m.Score AS FLOAT) END) AS post_ls_6000_80_11m,

        /* 36m */
        sess_ls_36m.post_ls_date_36m,
        sess_ls_36m.ext_protocol_36m            AS extended_loudness_protocol_36m,
        MAX(CASE WHEN ls36m.Frequency=250  AND CAST(lsp36m.Intensity AS INT)=35 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_250_35_36m,
        MAX(CASE WHEN ls36m.Frequency=250  AND CAST(lsp36m.Intensity AS INT)=50 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_250_50_36m,
        MAX(CASE WHEN ls36m.Frequency=250  AND CAST(lsp36m.Intensity AS INT)=65 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_250_65_36m,
        MAX(CASE WHEN ls36m.Frequency=250  AND CAST(lsp36m.Intensity AS INT)=80 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_250_80_36m,
        MAX(CASE WHEN ls36m.Frequency=500  AND CAST(lsp36m.Intensity AS INT)=35 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_500_35_36m,
        MAX(CASE WHEN ls36m.Frequency=500  AND CAST(lsp36m.Intensity AS INT)=50 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_500_50_36m,
        MAX(CASE WHEN ls36m.Frequency=500  AND CAST(lsp36m.Intensity AS INT)=65 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_500_65_36m,
        MAX(CASE WHEN ls36m.Frequency=500  AND CAST(lsp36m.Intensity AS INT)=80 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_500_80_36m,
        MAX(CASE WHEN ls36m.Frequency=1000 AND CAST(lsp36m.Intensity AS INT)=35 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_1000_35_36m,
        MAX(CASE WHEN ls36m.Frequency=1000 AND CAST(lsp36m.Intensity AS INT)=50 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_1000_50_36m,
        MAX(CASE WHEN ls36m.Frequency=1000 AND CAST(lsp36m.Intensity AS INT)=65 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_1000_65_36m,
        MAX(CASE WHEN ls36m.Frequency=1000 AND CAST(lsp36m.Intensity AS INT)=80 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_1000_80_36m,
        MAX(CASE WHEN ls36m.Frequency=2000 AND CAST(lsp36m.Intensity AS INT)=35 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_2000_35_36m,
        MAX(CASE WHEN ls36m.Frequency=2000 AND CAST(lsp36m.Intensity AS INT)=50 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_2000_50_36m,
        MAX(CASE WHEN ls36m.Frequency=2000 AND CAST(lsp36m.Intensity AS INT)=65 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_2000_65_36m,
        MAX(CASE WHEN ls36m.Frequency=2000 AND CAST(lsp36m.Intensity AS INT)=80 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_2000_80_36m,
        MAX(CASE WHEN ls36m.Frequency=4000 AND CAST(lsp36m.Intensity AS INT)=35 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_4000_35_36m,
        MAX(CASE WHEN ls36m.Frequency=4000 AND CAST(lsp36m.Intensity AS INT)=50 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_4000_50_36m,
        MAX(CASE WHEN ls36m.Frequency=4000 AND CAST(lsp36m.Intensity AS INT)=65 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_4000_65_36m,
        MAX(CASE WHEN ls36m.Frequency=4000 AND CAST(lsp36m.Intensity AS INT)=80 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_4000_80_36m,
        MAX(CASE WHEN ls36m.Frequency=6000 AND CAST(lsp36m.Intensity AS INT)=35 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_6000_35_36m,
        MAX(CASE WHEN ls36m.Frequency=6000 AND CAST(lsp36m.Intensity AS INT)=50 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_6000_50_36m,
        MAX(CASE WHEN ls36m.Frequency=6000 AND CAST(lsp36m.Intensity AS INT)=65 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_6000_65_36m,
        MAX(CASE WHEN ls36m.Frequency=6000 AND CAST(lsp36m.Intensity AS INT)=80 THEN CAST(lsp36m.Score AS FLOAT) END) AS post_ls_6000_80_36m

    FROM #Surgery s

    OUTER APPLY (
        SELECT TOP 1
            r.Executed AS post_ls_date_3m,
            r.ResultID AS result_id_3m,
            CASE WHEN r.Executed >= '2020-04-10' THEN 1 ELSE 0 END AS ext_protocol_3m
        FROM R_Post r
        JOIN [Audiqueen].[LoudnessScaling] ls_check
          ON ls_check.ResultID = r.ResultID
         AND ls_check.[Side] = s.SideID
        WHERE r.PatientID = s.PatientID
          AND r.Executed > s.last_implant_date
          AND r.Executed < DATEADD(MONTH, 7, s.last_implant_date)
        ORDER BY
            ABS(DATEDIFF(DAY, DATEADD(MONTH, 3, s.last_implant_date), r.Executed)),
            r.Executed DESC,
            r.ResultID DESC
    ) sess_ls_3m

    OUTER APPLY (
        SELECT TOP 1
            r.Executed AS post_ls_date_11m,
            r.ResultID AS result_id_11m,
            CASE WHEN r.Executed >= '2020-04-10' THEN 1 ELSE 0 END AS ext_protocol_11m
        FROM R_Post r
        JOIN [Audiqueen].[LoudnessScaling] ls_check
          ON ls_check.ResultID = r.ResultID
         AND ls_check.[Side] = s.SideID
        WHERE r.PatientID = s.PatientID
          AND r.Executed >= DATEADD(MONTH, 7, s.last_implant_date)
          AND r.Executed <  DATEADD(MONTH, 19, s.last_implant_date)
        ORDER BY
            ABS(DATEDIFF(DAY, DATEADD(MONTH, 11, s.last_implant_date), r.Executed)),
            r.Executed DESC,
            r.ResultID DESC
    ) sess_ls_11m

    OUTER APPLY (
        SELECT TOP 1
            r.Executed AS post_ls_date_36m,
            r.ResultID AS result_id_36m,
            CASE WHEN r.Executed >= '2020-04-10' THEN 1 ELSE 0 END AS ext_protocol_36m
        FROM R_Post r
        JOIN [Audiqueen].[LoudnessScaling] ls_check
          ON ls_check.ResultID = r.ResultID
         AND ls_check.[Side] = s.SideID
        WHERE r.PatientID = s.PatientID
          AND r.Executed >= DATEADD(MONTH, 19, s.last_implant_date)
          AND r.Executed <  DATEADD(MONTH, 49, s.last_implant_date)
        ORDER BY
            ABS(DATEDIFF(DAY, DATEADD(MONTH, 36, s.last_implant_date), r.Executed)),
            r.Executed DESC,
            r.ResultID DESC
    ) sess_ls_36m

    LEFT JOIN [Audiqueen].[LoudnessScaling] ls3m
       ON ls3m.ResultID = sess_ls_3m.result_id_3m AND ls3m.[Side] = s.SideID
      AND ls3m.Frequency IN (250,500,1000,2000,4000,6000)

    LEFT JOIN [Audiqueen].[LoudnessScalingPoint] lsp3m
        ON lsp3m.LoudnessScalingID = ls3m.LoudnessScalingID
        AND CAST(lsp3m.Intensity AS INT) IN (35,50,65,80)

    LEFT JOIN [Audiqueen].[LoudnessScaling] ls11m
        ON ls11m.ResultID = sess_ls_11m.result_id_11m AND ls11m.[Side] = s.SideID
        AND ls11m.Frequency IN (250,500,1000,2000,4000,6000)
    LEFT JOIN [Audiqueen].[LoudnessScalingPoint] lsp11m
        ON lsp11m.LoudnessScalingID = ls11m.LoudnessScalingID
        AND CAST(lsp11m.Intensity AS INT) IN (35,50,65,80)

    LEFT JOIN [Audiqueen].[LoudnessScaling] ls36m
           ON ls36m.ResultID = sess_ls_36m.result_id_36m AND ls36m.[Side] = s.SideID
          AND ls36m.Frequency IN (250,500,1000,2000,4000,6000)
    LEFT JOIN [Audiqueen].[LoudnessScalingPoint] lsp36m
           ON lsp36m.LoudnessScalingID = ls36m.LoudnessScalingID
          AND CAST(lsp36m.Intensity AS INT) IN (35,50,65,80)

    GROUP BY s.PatientID, s.SideID,
             sess_ls_3m.post_ls_date_3m,   sess_ls_3m.ext_protocol_3m,
             sess_ls_11m.post_ls_date_11m, sess_ls_11m.ext_protocol_11m,
             sess_ls_36m.post_ls_date_36m, sess_ls_36m.ext_protocol_36m
)


/* ============================================================
   STEP 6 - Final merge → #PostTests
   ============================================================ */
SELECT
    s.PatientID,
    s.SideID,

    /* Audiometry */
    pa.post_audio_date_3m,
    pa.post_audio_months_actual_3m,
    pa.post_audio_250_3m,  pa.post_audio_250_nr_3m,
    pa.post_audio_500_3m,  pa.post_audio_500_nr_3m,
    pa.post_audio_1000_3m, pa.post_audio_1000_nr_3m,
    pa.post_audio_2000_3m, pa.post_audio_2000_nr_3m,
    pa.post_audio_4000_3m, pa.post_audio_4000_nr_3m,
    pa.post_audio_6000_3m, pa.post_audio_6000_nr_3m,
    pa.post_audio_8000_3m, pa.post_audio_8000_nr_3m,

    pa.post_audio_date_11m,
    pa.post_audio_months_actual_11m,
    pa.post_audio_250_11m,  pa.post_audio_250_nr_11m,
    pa.post_audio_500_11m,  pa.post_audio_500_nr_11m,
    pa.post_audio_1000_11m, pa.post_audio_1000_nr_11m,
    pa.post_audio_2000_11m, pa.post_audio_2000_nr_11m,
    pa.post_audio_4000_11m, pa.post_audio_4000_nr_11m,
    pa.post_audio_6000_11m, pa.post_audio_6000_nr_11m,
    pa.post_audio_8000_11m, pa.post_audio_8000_nr_11m,

    pa.post_audio_date_36m,
    pa.post_audio_months_actual_36m,
    pa.post_audio_250_36m,  pa.post_audio_250_nr_36m,
    pa.post_audio_500_36m,  pa.post_audio_500_nr_36m,
    pa.post_audio_1000_36m, pa.post_audio_1000_nr_36m,
    pa.post_audio_2000_36m, pa.post_audio_2000_nr_36m,
    pa.post_audio_4000_36m, pa.post_audio_4000_nr_36m,
    pa.post_audio_6000_36m, pa.post_audio_6000_nr_36m,
    pa.post_audio_8000_36m, pa.post_audio_8000_nr_36m,

    /* Speech — PRIMARY TARGET */
    ps.post_speech_date_3m,  ps.post_speech_months_actual_3m,
    ps.post_speech_40_3m,  ps.post_speech_55_3m,
    ps.post_speech_70_3m,  ps.post_speech_85_3m,
    ps.post_speech_date_11m, ps.post_speech_months_actual_11m,
    ps.post_speech_40_11m, ps.post_speech_55_11m,
    ps.post_speech_70_11m, ps.post_speech_85_11m,
    ps.post_speech_date_36m, ps.post_speech_months_actual_36m,
    ps.post_speech_40_36m, ps.post_speech_55_36m,
    ps.post_speech_70_36m, ps.post_speech_85_36m,

    /* Phoneme */
    pp.post_phon_date_3m,   pp.post_phon_months_actual_3m,  pp.post_phon_n_sessions_3m,  pp.post_phon_n_contrasts_3m,
    pp.post_phon_a_i_3m,    pp.post_phon_a_u_3m,    pp.post_phon_a_o_3m,
    pp.post_phon_a_ae_3m,   pp.post_phon_a_uh_3m,   pp.post_phon_ae_i_3m,
    pp.post_phon_ae_uh_3m,  pp.post_phon_i_u_3m,    pp.post_phon_i_y_3m,
    pp.post_phon_i_uh_3m,   pp.post_phon_o_u_3m,    pp.post_phon_o_uh_3m,
    pp.post_phon_u_uh_3m,   pp.post_phon_y_u_3m,    pp.post_phon_r_a_3m,
    pp.post_phon_s_z_3m,    pp.post_phon_sh_s_3m,   pp.post_phon_sh_u_3m,
    pp.post_phon_z_m_3m,    pp.post_phon_z_v_3m,
    pp.post_phon_date_11m,  pp.post_phon_months_actual_11m,  pp.post_phon_n_sessions_11m, pp.post_phon_n_contrasts_11m,
    pp.post_phon_a_i_11m,   pp.post_phon_a_u_11m,   pp.post_phon_a_o_11m,
    pp.post_phon_a_ae_11m,  pp.post_phon_a_uh_11m,  pp.post_phon_ae_i_11m,
    pp.post_phon_ae_uh_11m, pp.post_phon_i_u_11m,   pp.post_phon_i_y_11m,
    pp.post_phon_i_uh_11m,  pp.post_phon_o_u_11m,   pp.post_phon_o_uh_11m,
    pp.post_phon_u_uh_11m,  pp.post_phon_y_u_11m,   pp.post_phon_r_a_11m,
    pp.post_phon_s_z_11m,   pp.post_phon_sh_s_11m,  pp.post_phon_sh_u_11m,
    pp.post_phon_z_m_11m,   pp.post_phon_z_v_11m,
    pp.post_phon_date_36m,  pp.post_phon_months_actual_36m,  pp.post_phon_n_sessions_36m, pp.post_phon_n_contrasts_36m,
    pp.post_phon_a_i_36m,   pp.post_phon_a_u_36m,   pp.post_phon_a_o_36m,
    pp.post_phon_a_ae_36m,  pp.post_phon_a_uh_36m,  pp.post_phon_ae_i_36m,
    pp.post_phon_ae_uh_36m, pp.post_phon_i_u_36m,   pp.post_phon_i_y_36m,
    pp.post_phon_i_uh_36m,  pp.post_phon_o_u_36m,   pp.post_phon_o_uh_36m,
    pp.post_phon_u_uh_36m,  pp.post_phon_y_u_36m,   pp.post_phon_r_a_36m,
    pp.post_phon_s_z_36m,   pp.post_phon_sh_s_36m,  pp.post_phon_sh_u_36m,
    pp.post_phon_z_m_36m,   pp.post_phon_z_v_36m,

    /* Loudness Scaling */
    pl.post_ls_date_3m,  pl.extended_loudness_protocol_3m,
    pl.post_ls_250_35_3m,  pl.post_ls_250_50_3m,  pl.post_ls_250_65_3m,  pl.post_ls_250_80_3m,
    pl.post_ls_500_35_3m,  pl.post_ls_500_50_3m,  pl.post_ls_500_65_3m,  pl.post_ls_500_80_3m,
    pl.post_ls_1000_35_3m, pl.post_ls_1000_50_3m, pl.post_ls_1000_65_3m, pl.post_ls_1000_80_3m,
    pl.post_ls_2000_35_3m, pl.post_ls_2000_50_3m, pl.post_ls_2000_65_3m, pl.post_ls_2000_80_3m,
    pl.post_ls_4000_35_3m, pl.post_ls_4000_50_3m, pl.post_ls_4000_65_3m, pl.post_ls_4000_80_3m,
    pl.post_ls_6000_35_3m, pl.post_ls_6000_50_3m, pl.post_ls_6000_65_3m, pl.post_ls_6000_80_3m,
    pl.post_ls_date_11m, pl.extended_loudness_protocol_11m,
    pl.post_ls_250_35_11m,  pl.post_ls_250_50_11m,  pl.post_ls_250_65_11m,  pl.post_ls_250_80_11m,
    pl.post_ls_500_35_11m,  pl.post_ls_500_50_11m,  pl.post_ls_500_65_11m,  pl.post_ls_500_80_11m,
    pl.post_ls_1000_35_11m, pl.post_ls_1000_50_11m, pl.post_ls_1000_65_11m, pl.post_ls_1000_80_11m,
    pl.post_ls_2000_35_11m, pl.post_ls_2000_50_11m, pl.post_ls_2000_65_11m, pl.post_ls_2000_80_11m,
    pl.post_ls_4000_35_11m, pl.post_ls_4000_50_11m, pl.post_ls_4000_65_11m, pl.post_ls_4000_80_11m,
    pl.post_ls_6000_35_11m, pl.post_ls_6000_50_11m, pl.post_ls_6000_65_11m, pl.post_ls_6000_80_11m,
    pl.post_ls_date_36m, pl.extended_loudness_protocol_36m,
    pl.post_ls_250_35_36m,  pl.post_ls_250_50_36m,  pl.post_ls_250_65_36m,  pl.post_ls_250_80_36m,
    pl.post_ls_500_35_36m,  pl.post_ls_500_50_36m,  pl.post_ls_500_65_36m,  pl.post_ls_500_80_36m,
    pl.post_ls_1000_35_36m, pl.post_ls_1000_50_36m, pl.post_ls_1000_65_36m, pl.post_ls_1000_80_36m,
    pl.post_ls_2000_35_36m, pl.post_ls_2000_50_36m, pl.post_ls_2000_65_36m, pl.post_ls_2000_80_36m,
    pl.post_ls_4000_35_36m, pl.post_ls_4000_50_36m, pl.post_ls_4000_65_36m, pl.post_ls_4000_80_36m,
    pl.post_ls_6000_35_36m, pl.post_ls_6000_50_36m, pl.post_ls_6000_65_36m, pl.post_ls_6000_80_36m

INTO #PostTests

FROM #Surgery s
LEFT JOIN PostAudiometry pa ON pa.PatientID = s.PatientID AND pa.SideID = s.SideID
LEFT JOIN PostSpeech     ps ON ps.PatientID = s.PatientID AND ps.SideID = s.SideID
LEFT JOIN PostPhoneme    pp ON pp.PatientID = s.PatientID AND pp.SideID = s.SideID
LEFT JOIN PostLoudness   pl ON pl.PatientID = s.PatientID AND pl.SideID = s.SideID
WHERE s.explant_flag = 0;   -- exclude ears with active explant (no CI)


CREATE INDEX IX_PostTests_PatientSide
    ON #PostTests (PatientID, SideID);


/* ============================================================
   QA CHECK
   ============================================================ */
SELECT
    COUNT(*)                                                                    AS total_rows,
    COUNT(*) - COUNT(DISTINCT CONCAT(
                    CAST(PatientID AS NVARCHAR(50)),'-',
                    CAST(SideID AS NVARCHAR(5))))                               AS duplicate_rows,

    /* Speech coverage (primary target) */
    ROUND(100.0*SUM(CASE WHEN post_speech_55_3m  IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_speech_3m,
    ROUND(100.0*SUM(CASE WHEN post_speech_55_11m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_speech_11m,
    ROUND(100.0*SUM(CASE WHEN post_speech_55_36m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_speech_36m,

    /* Audiometry coverage */
    ROUND(100.0*SUM(CASE WHEN post_audio_1000_3m  IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_audio_3m,
    ROUND(100.0*SUM(CASE WHEN post_audio_1000_11m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_audio_11m,
    ROUND(100.0*SUM(CASE WHEN post_audio_1000_36m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_audio_36m,

    /* Phoneme coverage */
    ROUND(100.0*SUM(CASE WHEN post_phon_date_3m  IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_phon_3m,
    ROUND(100.0*SUM(CASE WHEN post_phon_date_11m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_phon_11m,
    ROUND(100.0*SUM(CASE WHEN post_phon_date_36m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_phon_36m,


    /* Loudness coverage */
    ROUND(100.0*SUM(CASE WHEN post_ls_1000_50_3m  IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_ls_3m,
    ROUND(100.0*SUM(CASE WHEN post_ls_1000_50_11m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_ls_11m,

    /* Extended protocol */
    SUM(CASE WHEN extended_loudness_protocol_3m = 1 THEN 1 ELSE 0 END)         AS n_extended_protocol_3m,

    /* NoResponse flags */
    SUM(CASE WHEN post_audio_1000_nr_3m = 1 THEN 1 ELSE 0 END)                 AS n_no_response_3m,

    /* months_post_actual distribution check */
    ROUND(AVG(CAST(post_audio_months_actual_3m  AS FLOAT)), 1)                  AS avg_audio_months_3m,
    ROUND(AVG(CAST(post_audio_months_actual_11m AS FLOAT)), 1)                  AS avg_audio_months_11m,
    ROUND(AVG(CAST(post_audio_months_actual_36m AS FLOAT)), 1)                  AS avg_audio_months_36m,
    ROUND(AVG(CAST(post_speech_months_actual_3m  AS FLOAT)), 1)                 AS avg_speech_months_3m,
    ROUND(AVG(CAST(post_speech_months_actual_11m AS FLOAT)), 1)                 AS avg_speech_months_11m,
    ROUND(AVG(CAST(post_speech_months_actual_36m AS FLOAT)), 1)                 AS avg_speech_months_36m

FROM #PostTests;

/* Check exact date windows */
SELECT
    MIN(post_audio_months_actual_3m)  AS min_audio_months_3m,
    MAX(post_audio_months_actual_3m)  AS max_audio_months_3m,
    MIN(post_audio_months_actual_11m) AS min_audio_months_11m,
    MAX(post_audio_months_actual_11m) AS max_audio_months_11m,
    MIN(post_audio_months_actual_36m) AS min_audio_months_36m,
    MAX(post_audio_months_actual_36m) AS max_audio_months_36m,

    MIN(post_speech_months_actual_3m)  AS min_speech_months_3m,
    MAX(post_speech_months_actual_3m)  AS max_speech_months_3m,
    MIN(post_speech_months_actual_11m) AS min_speech_months_11m,
    MAX(post_speech_months_actual_11m) AS max_speech_months_11m,
    MIN(post_speech_months_actual_36m) AS min_speech_months_36m,
    MAX(post_speech_months_actual_36m) AS max_speech_months_36m
FROM #PostTests;

SELECT TOP 10 * FROM #PostTests ORDER BY PatientID, SideID;