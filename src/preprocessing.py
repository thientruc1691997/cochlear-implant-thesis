import numpy as np
import pandas as pd

from features import (
    SPEECH,
    CONTRA_COLS,
    calc_easi,
)


#  Manufacturer mapping 

def _get_manufacturer(desc: str) -> str:
    """Map device description string to manufacturer label."""
    if pd.isna(desc):
        return "Other"
    d = str(desc).upper()
    if "NUCLEUS" in d:
        return "Cochlear"
    if "AB " in d or "HIRES" in d:
        return "AB"
    if "DIGISONIC" in d or "NEURELEC" in d:
        return "Neurelec"
    if "MED-EL" in d or "MEDEL" in d or "SONATA" in d or "CONCERTO" in d:
        return "MedEl"
    return "Other"


# Main preprocessing function 

def load_and_preprocess(data_path: str) -> pd.DataFrame:
    """
    Load the raw CSV and return a fully preprocessed DataFrame.

    Parameters
    ----------
    data_path : str
        Path to Audiometry_data.csv (SQL pipeline export).

    Returns
    -------
    pd.DataFrame
        Preprocessed DataFrame with 795 rows (after exclusions).
        Adds columns: implant_year, SideLabel_enc, manufacturer,
        mfr_* dummies, pre_EaSI, pre_phon_contra_pct, group.
    """
    df = pd.read_csv(data_path)

    # Parse dates 
    date_cols = [
        "first_implant_date",
        "pre_audiometry_date",
        "pre_speech_date",
        "pre_phon_contra_date",
    ]
    for col in date_cols:
        df[col] = pd.to_datetime(df[col], errors="coerce")

    # Days between preoperative test and implant 
    df["days_audio"]  = (df["first_implant_date"] - df["pre_audiometry_date"]).dt.days
    df["days_speech"] = (df["first_implant_date"] - df["pre_speech_date"]).dt.days
    df["days_phon"]   = (df["first_implant_date"] - df["pre_phon_contra_date"]).dt.days

    # Exclusion: preoperative tests > 2 years before implant 
    too_old = (
        (df["days_audio"]  > 730) |
        (df["days_speech"] > 730) |
        (df["days_phon"]   > 730)
    )
    n_before = len(df)
    df = df[~too_old].reset_index(drop=True)
    n_excluded = n_before - len(df)
    print(f"Excluded {n_excluded} patients with preoperative tests > 2 years before implant.")
    print(f"Final cohort: n = {len(df)}")

    # Implant year for chronological split 
    df["implant_year"] = df["first_implant_date"].dt.year

    # Ear side encoding 
    df["SideLabel_enc"] = (df["SideLabel"] == "Right").astype(int)

    # Manufacturer dummy encoding (Cochlear = reference category) 
    df["manufacturer"] = df["device_description_1"].apply(_get_manufacturer)
    mfr_dummies = pd.get_dummies(df["manufacturer"], prefix="mfr")
    mfr_dummies = mfr_dummies.drop(columns=["mfr_Cochlear"], errors="ignore")
    df = pd.concat([df, mfr_dummies], axis=1)

    #  Pre-operative EaSI 
    df["pre_EaSI"] = df.apply(calc_easi, axis=1)

    #  Patient stratification 
    # Non-assessable: age < 6, or SIR >= 3, or SIR missing
    non_assessable_mask = (
        (df["age_at_first_implant"] < 6) |
        (df["sir_intelligibility_score"] >= 3) |
        (df["sir_intelligibility_score"].isna())
    )
    df["group"] = np.where(non_assessable_mask, "non_assessable", "assessable")

    n_ass     = (df["group"] == "assessable").sum()
    n_non_ass = (df["group"] == "non_assessable").sum()
    print(f"Assessable: n = {n_ass} | Non-assessable: n = {n_non_ass}")

    # Phoneme discrimination: mean score across 20 contrast pairs 
    available_contra = [c for c in CONTRA_COLS if c in df.columns]
    df["pre_phon_contra_pct"] = df[available_contra].mean(axis=1)
    # Set to NaN where all contrasts are missing
    all_missing = df[available_contra].isna().all(axis=1)
    df.loc[all_missing, "pre_phon_contra_pct"] = np.nan

    # Phoneme imputation (conditional MNAR/MAR) 
    # See thesis methodology section 4.1 for rationale.
    df = _impute_phoneme(df)

    return df


def _impute_phoneme(df: pd.DataFrame) -> pd.DataFrame:
    """
    Conditional imputation of pre_phon_contra_pct:

    MNAR: EaSI < 40% or no speech data → impute 0
          (patient cannot perform the test due to poor hearing)
    MAR:  EaSI >= 40% but phoneme missing → impute training-set median
          (documentation / extraction issue, not inability)

    Note: in model training, median is recomputed per training fold
    to avoid leakage. This function applies the rule only during
    the full-dataset preprocessing step for EDA purposes.
    """
    has_phoneme = df["pre_phon_contra_pct"].notna()
    has_speech  = df[["pre_speech_40", "pre_speech_55",
                       "pre_speech_70", "pre_speech_85"]].notna().any(axis=1)
    low_speech  = df["pre_speech_70"].fillna(0) < 40

    mnar_mask = (~has_phoneme) & (low_speech | ~has_speech)
    mar_mask  = (~has_phoneme) & ~mnar_mask

    df.loc[mnar_mask, "pre_phon_contra_pct"] = 0.0

    if mar_mask.any():
        median_val = df.loc[has_phoneme, "pre_phon_contra_pct"].median()
        df.loc[mar_mask, "pre_phon_contra_pct"] = median_val

    return df


def apply_phoneme_imputation_per_fold(
    X_train: pd.DataFrame,
    X_val: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    Apply fold-safe phoneme imputation:
    MNAR rows already imputed as 0 in load_and_preprocess.
    MAR rows: compute median from training fold only.

    Call this inside each cross-validation fold for LR and SVM
    (tree-based models handle missing values natively).
    """
    X_train = X_train.copy()
    X_val   = X_val.copy()

    if "pre_phon_contra_pct" not in X_train.columns:
        return X_train, X_val

    has_phon_train = X_train["pre_phon_contra_pct"].notna()
    has_phon_val   = X_val["pre_phon_contra_pct"].notna()

    train_median = X_train.loc[has_phon_train, "pre_phon_contra_pct"].median()

    X_train.loc[~has_phon_train, "pre_phon_contra_pct"] = train_median
    X_val.loc[~has_phon_val,   "pre_phon_contra_pct"] = train_median

    return X_train, X_val


if __name__ == "__main__":
    import sys
    path = sys.argv[1] if len(sys.argv) > 1 else "data/Audiometry_data.csv"
    df = load_and_preprocess(path)
    print(df[["group", "pre_EaSI", "pre_phon_contra_pct"]].describe())
