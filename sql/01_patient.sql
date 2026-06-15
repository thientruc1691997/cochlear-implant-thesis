/* ============================================================
   MODULE   : 01_patient.sql
   PURPOSE  : Extract core patient demographics.
   OUTPUT   : #Patient
   GRAIN    : 1 row = 1 patient (NO ear side at this stage)
 
   TABLES USED:
     [Audiqueen].[dbo].[Patient]   Patient demographics
 
   COLUMNS EXTRACTED:
     PatientID   Primary key - master join key across pipeline
     BirthDate   Used to compute age at surgery in Module 02

 
   NEXT MODULE:
     02_surgery.sql  will JOIN #Patient on PatientID
     and establish the definitive PatientID x SideID grain.
   ============================================================ */
 
 
/* -- Drop temp table if it already exists from a prior run --- */
IF OBJECT_ID('tempdb..#Patient') IS NOT NULL
    DROP TABLE #Patient;
 
 
/* ============================================================
   STEP 1 - Pull patient demographics
   ------------------------------------
   Exclusion rule:
     BirthDate IS NULL -> cannot compute age at surgery.
     These records are excluded here.
     Record the exact count in the Decisions Log.
   ============================================================ */
SELECT
    p.PatientID,
    p.BirthDate
 
INTO #Patient
 
FROM [dbo].[Patient] p
 
WHERE p.BirthDate IS NOT NULL; 
 
 

CREATE INDEX IX_Patient_PatientID
    ON #Patient (PatientID);