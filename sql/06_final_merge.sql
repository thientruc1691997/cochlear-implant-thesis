/* ============================================================
   MODULE   : 06_final_merge.sql
   PURPOSE  : Combine all modules into the final ML training table.
   INPUT    : #Patient      (Module 01)
              #Surgery      (Module 02)
              #PreTests     (Module 03)
              #PostTests    (Module 04)
              #Keywords     (Module 05)
   OUTPUT   : #Final
   GRAIN    : 1 row = 1 PatientID x 1 SideID

   COLUMN GROUPS:
     [A] Patient demographics          from #Patient
     [B] Surgery / implant info        from #Surgery
     [C] Pre-op Audiometry             from #PreTests
     [D] Pre-op Speech Audiometry      from #PreTests
     [E] Pre-op Phoneme (ipsilateral)  from #PreTests
     [F] Pre-op Phoneme (contralateral)from #PreTests
     [G] Post-op Audiometry   3m/11m/36m from #PostTests
     [H] Post-op Speech       3m/11m/36m from #PostTests 
     [I] Post-op Phoneme      3m/11m/36m from #PostTests
     [J] Post-op Loudness     3m/11m/36m from #PostTests
     [K] Keywords                       from #Keywords

   TARGET VARIABLES:
     post_speech_55_3m   Primary target  (3 months)
     post_speech_55_11m  Secondary target (11 months)
     post_speech_55_36m  Secondary target (36 months)

   ── DECISIONS LOG ──────────────────────────────────────────
   DEC-25  Final table uses LEFT JOIN for all test modules.
           Patients with no post-op tests are retained
           (all test columns = NULL).
           These records may be excluded during ML preprocessing.

   DEC-26  age_at_first_implant computed in Module 02.
           age_at_last_implant also available for reimplant cases.

   DEC-27  Row count must equal #Surgery (1,469).
           Any inflation indicates a JOIN bug.
   ── END DECISIONS LOG ──────────────────────────────────────
   ============================================================ */


IF OBJECT_ID('tempdb..#Final') IS NOT NULL
    DROP TABLE #Final;


SELECT

    /* ── [A] Patient demographics ──────────────────────── */
    s.PatientID,
    s.SideID,
    s.SideLabel,                            -- 'Left' / 'Right'
    p.BirthDate,

    /* ── [B] Surgery / implant info ────────────────────── */
    s.first_implant_date,
    s.last_implant_date,
    s.age_at_first_implant,
    s.age_at_last_implant,
    s.implant_event_count,
    s.confirmed_implant_count,
    s.reimplant_flag,
    s.device_description_1,
    s.device_1_date,
    s.device_description_2,
    s.device_2_date,
    s.explant_count,
    s.last_explant_date,
    s.explant_flag,
    s.needs_dr_review,

    /* ── [C] Pre-op Audiometry (unaided) ───────────────── */
    pre.pre_audiometry_date,
    pre.pre_audio_250,
    pre.pre_audio_500,
    pre.pre_audio_1000,
    pre.pre_audio_2000,
    pre.pre_audio_4000,
    pre.pre_audio_6000,
    pre.pre_audio_8000,


    /* ── [D] Pre-op Speech Audiometry (aided) ──────────── */
    pre.pre_speech_date,
    pre.pre_speech_40,
    pre.pre_speech_55,
    pre.pre_speech_70,
    pre.pre_speech_85,

    /* ── [E] Pre-op Phoneme Discrimination (ipsilateral) ── */
    pre.pre_phon_ipsi_date,
    pre.pre_phon_ipsi_a_i,
    pre.pre_phon_ipsi_a_u,
    pre.pre_phon_ipsi_a_o,
    pre.pre_phon_ipsi_a_ae,
    pre.pre_phon_ipsi_a_uh,
    pre.pre_phon_ipsi_ae_i,
    pre.pre_phon_ipsi_ae_uh,
    pre.pre_phon_ipsi_i_u,
    pre.pre_phon_ipsi_i_y,
    pre.pre_phon_ipsi_i_uh,
    pre.pre_phon_ipsi_o_u,
    pre.pre_phon_ipsi_o_uh,
    pre.pre_phon_ipsi_u_uh,
    pre.pre_phon_ipsi_y_u,
    pre.pre_phon_ipsi_r_a,
    pre.pre_phon_ipsi_s_z,
    pre.pre_phon_ipsi_sh_s,
    pre.pre_phon_ipsi_sh_u,
    pre.pre_phon_ipsi_z_m,
    pre.pre_phon_ipsi_z_v,

    /* ── [F] Pre-op Phoneme Discrimination (contralateral) ─ */
    pre.pre_phon_contra_date,
    pre.pre_phon_contra_a_i,
    pre.pre_phon_contra_a_u,
    pre.pre_phon_contra_a_o,
    pre.pre_phon_contra_a_ae,
    pre.pre_phon_contra_a_uh,
    pre.pre_phon_contra_ae_i,
    pre.pre_phon_contra_ae_uh,
    pre.pre_phon_contra_i_u,
    pre.pre_phon_contra_i_y,
    pre.pre_phon_contra_i_uh,
    pre.pre_phon_contra_o_u,
    pre.pre_phon_contra_o_uh,
    pre.pre_phon_contra_u_uh,
    pre.pre_phon_contra_y_u,
    pre.pre_phon_contra_r_a,
    pre.pre_phon_contra_s_z,
    pre.pre_phon_contra_sh_s,
    pre.pre_phon_contra_sh_u,
    pre.pre_phon_contra_z_m,
    pre.pre_phon_contra_z_v,

    /* ── [G] Post-op Audiometry ─────────────────────────── */
    post.post_audio_date_3m,
    post.post_audio_250_3m,  post.post_audio_500_3m,  post.post_audio_1000_3m,
    post.post_audio_2000_3m, post.post_audio_4000_3m, post.post_audio_6000_3m,
    post.post_audio_8000_3m,
    post.post_audio_date_11m,
    post.post_audio_250_11m, post.post_audio_500_11m, post.post_audio_1000_11m,
    post.post_audio_2000_11m,post.post_audio_4000_11m,post.post_audio_6000_11m,
    post.post_audio_8000_11m,
    post.post_audio_date_36m,
    post.post_audio_250_36m, post.post_audio_500_36m, post.post_audio_1000_36m,
    post.post_audio_2000_36m,post.post_audio_4000_36m,post.post_audio_6000_36m,
    post.post_audio_8000_36m,

    /* ── [H] Post-op Speech Audiometry  ─────────────────────────── */
    post.post_speech_date_3m,
    post.post_speech_40_3m,
    post.post_speech_55_3m,                 
    post.post_speech_70_3m,
    post.post_speech_85_3m,
    post.post_speech_date_11m,
    post.post_speech_40_11m,
    post.post_speech_55_11m,                
    post.post_speech_70_11m,
    post.post_speech_85_11m,
    post.post_speech_date_36m,
    post.post_speech_40_36m,
    post.post_speech_55_36m,                -- SECONDARY TARGE
    post.post_speech_70_36m,
    post.post_speech_85_36m,


    /* ── [I] Post-op Phoneme Discrimination ─────────────── */
    post.post_phon_date_3m,
    post.post_phon_months_actual_3m,
    post.post_phon_n_sessions_3m,
    post.post_phon_n_contrasts_3m,
    post.post_phon_a_i_3m,
    post.post_phon_a_u_3m,
    post.post_phon_a_o_3m,
    post.post_phon_a_ae_3m,
    post.post_phon_a_uh_3m,
    post.post_phon_ae_i_3m,
    post.post_phon_ae_uh_3m,
    post.post_phon_i_u_3m,
    post.post_phon_i_y_3m,
    post.post_phon_i_uh_3m,
    post.post_phon_o_u_3m,
    post.post_phon_o_uh_3m,
    post.post_phon_u_uh_3m,
    post.post_phon_y_u_3m,
    post.post_phon_r_a_3m,
    post.post_phon_s_z_3m,
    post.post_phon_sh_s_3m,
    post.post_phon_sh_u_3m,
    post.post_phon_z_m_3m,
    post.post_phon_z_v_3m,

    post.post_phon_date_11m,
    post.post_phon_months_actual_11m,
    post.post_phon_n_sessions_11m,
    post.post_phon_n_contrasts_11m,
    post.post_phon_a_i_11m,
    post.post_phon_a_u_11m,
    post.post_phon_a_o_11m,
    post.post_phon_a_ae_11m,
    post.post_phon_a_uh_11m,
    post.post_phon_ae_i_11m,
    post.post_phon_ae_uh_11m,
    post.post_phon_i_u_11m,
    post.post_phon_i_y_11m,
    post.post_phon_i_uh_11m,
    post.post_phon_o_u_11m,
    post.post_phon_o_uh_11m,
    post.post_phon_u_uh_11m,
    post.post_phon_y_u_11m,
    post.post_phon_r_a_11m,
    post.post_phon_s_z_11m,
    post.post_phon_sh_s_11m,
    post.post_phon_sh_u_11m,
    post.post_phon_z_m_11m,
    post.post_phon_z_v_11m,

    post.post_phon_date_36m,
    post.post_phon_months_actual_36m,
    post.post_phon_n_sessions_36m,
    post.post_phon_n_contrasts_36m,
    post.post_phon_a_i_36m,
    post.post_phon_a_u_36m,
    post.post_phon_a_o_36m,
    post.post_phon_a_ae_36m,
    post.post_phon_a_uh_36m,
    post.post_phon_ae_i_36m,
    post.post_phon_ae_uh_36m,
    post.post_phon_i_u_36m,
    post.post_phon_i_y_36m,
    post.post_phon_i_uh_36m,
    post.post_phon_o_u_36m,
    post.post_phon_o_uh_36m,
    post.post_phon_u_uh_36m,
    post.post_phon_y_u_36m,
    post.post_phon_r_a_36m,
    post.post_phon_s_z_36m,
    post.post_phon_sh_s_36m,
    post.post_phon_sh_u_36m,
    post.post_phon_z_m_36m,
    post.post_phon_z_v_36m,

    /* ── [J] Post-op Loudness Scaling ───────────────────── */
    post.post_ls_date_3m,
    post.extended_loudness_protocol_3m,
    post.post_ls_250_35_3m,  post.post_ls_250_50_3m,
    post.post_ls_250_65_3m,  post.post_ls_250_80_3m,
    post.post_ls_500_35_3m,  post.post_ls_500_50_3m,
    post.post_ls_500_65_3m,  post.post_ls_500_80_3m,
    post.post_ls_1000_35_3m, post.post_ls_1000_50_3m,
    post.post_ls_1000_65_3m, post.post_ls_1000_80_3m,
    post.post_ls_2000_35_3m, post.post_ls_2000_50_3m,
    post.post_ls_2000_65_3m, post.post_ls_2000_80_3m,
    post.post_ls_4000_35_3m, post.post_ls_4000_50_3m,
    post.post_ls_4000_65_3m, post.post_ls_4000_80_3m,
    post.post_ls_6000_35_3m, post.post_ls_6000_50_3m,
    post.post_ls_6000_65_3m, post.post_ls_6000_80_3m,
    post.post_ls_date_11m,
    post.extended_loudness_protocol_11m,
    post.post_ls_250_35_11m,  post.post_ls_250_50_11m,
    post.post_ls_250_65_11m,  post.post_ls_250_80_11m,
    post.post_ls_500_35_11m,  post.post_ls_500_50_11m,
    post.post_ls_500_65_11m,  post.post_ls_500_80_11m,
    post.post_ls_1000_35_11m, post.post_ls_1000_50_11m,
    post.post_ls_1000_65_11m, post.post_ls_1000_80_11m,
    post.post_ls_2000_35_11m, post.post_ls_2000_50_11m,
    post.post_ls_2000_65_11m, post.post_ls_2000_80_11m,
    post.post_ls_4000_35_11m, post.post_ls_4000_50_11m,
    post.post_ls_4000_65_11m, post.post_ls_4000_80_11m,
    post.post_ls_6000_35_11m, post.post_ls_6000_50_11m,
    post.post_ls_6000_65_11m, post.post_ls_6000_80_11m,
    post.post_ls_date_36m,
    post.extended_loudness_protocol_36m,
    post.post_ls_250_35_36m,  post.post_ls_250_50_36m,
    post.post_ls_250_65_36m,  post.post_ls_250_80_36m,
    post.post_ls_500_35_36m,  post.post_ls_500_50_36m,
    post.post_ls_500_65_36m,  post.post_ls_500_80_36m,
    post.post_ls_1000_35_36m, post.post_ls_1000_50_36m,
    post.post_ls_1000_65_36m, post.post_ls_1000_80_36m,
    post.post_ls_2000_35_36m, post.post_ls_2000_50_36m,
    post.post_ls_2000_65_36m, post.post_ls_2000_80_36m,
    post.post_ls_4000_35_36m, post.post_ls_4000_50_36m,
    post.post_ls_4000_65_36m, post.post_ls_4000_80_36m,
    post.post_ls_6000_35_36m, post.post_ls_6000_50_36m,
    post.post_ls_6000_65_36m, post.post_ls_6000_80_36m,


    /* ── [K] Keywords ───────────────────────────────────── */
    kw.keywords,
    kw.parent_keywords,
    kw.keyword_parent_pairs,
    kw.keyword_count,
    kw.has_bilateral_kw,

    /* SIR */
    kw.sir_score,                    
    kw.sir_intelligibility_score,        
    kw.has_sir,
    kw.sir_child_implanted_before_6,
    kw.sir_completely_intelligible,
    kw.sir_mostly_intelligible,
    kw.sir_somewhat_intelligible,

    /* Type of Hearing Loss */
    kw.kw_postlingually_acquired,
    kw.kw_congenital_type,
    kw.kw_perilingual,

    /* Course of Hearing Loss */
    kw.kw_progressive_slow,
    kw.kw_sudden,

    /* Cause of Hearing Loss */
    kw.kw_unknown_cause,
    kw.kw_congenital_cause,

    /* Ear */
    kw.kw_normal_ear,

    /* OTHER */
    kw.kw_ci_bilateral,

    /* Genetic */
    kw.has_genetic,
    kw.kw_connexine_26,
    kw.kw_coch_dfna9,

    /* Malformation */
    kw.has_malformation,
    kw.kw_enlarged_vestibular_aqueduct,

    /* Degenerative/Aging */
    kw.has_meniere,

    /* Risk Factor */
    kw.has_risk_factor,
    kw.kw_family_history,

    /* Infectious */
    kw.has_infectious,
    kw.kw_meningitis,

    /* Study: keep for audit, not main model */
    kw.has_study_keyword,
    kw.kw_og060_ci_reimplantation

INTO #Final

FROM #Surgery s

JOIN #Patient p
  ON p.PatientID = s.PatientID

LEFT JOIN #PreTests pre
       ON pre.PatientID = s.PatientID
      AND pre.SideID    = s.SideID

LEFT JOIN #PostTests post
       ON post.PatientID = s.PatientID
      AND post.SideID    = s.SideID

LEFT JOIN #Keywords kw
       ON kw.PatientID = s.PatientID
      AND kw.SideID    = s.SideID;


/* ============================================================
   QA CHECK — Final table
   ─────────────────────
   DEC-27: row count must equal #Surgery (1,469)
   ============================================================ */
SELECT
    COUNT(*)                                                            AS total_rows,
    COUNT(DISTINCT PatientID)                                           AS unique_patients,
    COUNT(*) - COUNT(DISTINCT CONCAT(
                    CAST(PatientID AS NVARCHAR(50)),'-',
                    CAST(SideID AS NVARCHAR(5))))                       AS duplicate_rows,

    /* Surgery info */
    SUM(reimplant_flag)                                                 AS reimplant_ears,
    SUM(explant_flag)                                                   AS explant_ears,
    SUM(needs_dr_review)                                                AS dr_review_ears,

    /* Pre-op coverage */
    ROUND(100.0*SUM(CASE WHEN pre_audio_1000  IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_pre_audio,
    ROUND(100.0*SUM(CASE WHEN pre_speech_55   IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_pre_speech,
    ROUND(100.0*SUM(CASE WHEN pre_phon_ipsi_1 IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_pre_phon,

    /* Post-op coverage (target variables) */
    ROUND(100.0*SUM(CASE WHEN post_speech_55_3m  IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_target_3m,
    ROUND(100.0*SUM(CASE WHEN post_speech_55_11m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_target_11m,
    ROUND(100.0*SUM(CASE WHEN post_speech_55_36m IS NULL THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_target_36m,

    /* Keywords */
    ROUND(100.0*SUM(CASE WHEN keywords = '' THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_no_keywords

FROM #Final;


/* -- Column count ------------------------------------------ */
SELECT COUNT(*) AS total_columns
FROM tempdb.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME LIKE '#Final%';
/* ============================================================
   QA CHECK — Final table
   ============================================================ */
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT PatientID) AS unique_patients,
    COUNT(*) - COUNT(DISTINCT CONCAT(
        CAST(PatientID AS NVARCHAR(50)), '-',
        CAST(SideID AS NVARCHAR(5))
    )) AS duplicate_rows,

    /* Surgery info */
    SUM(reimplant_flag) AS reimplant_ears,
    SUM(explant_flag) AS explant_ears,
    SUM(needs_dr_review) AS dr_review_ears,

    /* Pre-op coverage */
    ROUND(100.0 * SUM(CASE WHEN pre_audio_1000 IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_no_pre_audio,
    ROUND(100.0 * SUM(CASE WHEN pre_speech_55 IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_no_pre_speech,
    ROUND(100.0 * SUM(CASE WHEN pre_phon_ipsi_1 IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_no_pre_phon,

    /* Post-op coverage */
    ROUND(100.0 * SUM(CASE WHEN post_speech_55_3m IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_no_target_3m,
    ROUND(100.0 * SUM(CASE WHEN post_speech_55_11m IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_no_target_11m,
    ROUND(100.0 * SUM(CASE WHEN post_speech_55_36m IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_no_target_36m,

    /* Keywords */
    ROUND(100.0 * SUM(CASE WHEN keywords = '' OR keywords IS NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_no_keywords,
    SUM(has_sir) AS n_has_sir,
    SUM(CASE WHEN sir_intelligibility_score IS NULL THEN 1 ELSE 0 END) AS n_missing_sir_intelligibility,
    SUM(sir_child_implanted_before_6) AS n_child_implanted_before_6,

    SUM(kw_postlingually_acquired) AS n_postlingual,
    SUM(kw_congenital_type) AS n_congenital_type,
    SUM(kw_perilingual) AS n_perilingual,
    SUM(kw_progressive_slow) AS n_progressive_slow,
    SUM(kw_sudden) AS n_sudden,
    SUM(kw_unknown_cause) AS n_unknown_cause,
    SUM(kw_ci_bilateral) AS n_ci_bilateral,
    SUM(has_genetic) AS n_has_genetic,
    SUM(kw_connexine_26) AS n_connexine_26,
    SUM(kw_coch_dfna9) AS n_coch_dfna9,
    SUM(has_malformation) AS n_has_malformation,
    SUM(has_infectious) AS n_has_infectious,
    SUM(kw_meningitis) AS n_meningitis,
    SUM(has_study_keyword) AS n_has_study_keyword

FROM #Final;

/* -- Preview ----------------------------------------------- */
SELECT *
FROM #Final
ORDER BY PatientID, SideID;
