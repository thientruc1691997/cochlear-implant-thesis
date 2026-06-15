import numpy as np
import pandas as pd

# ── Frequencies and timepoints ────────────────────────────────────────────────
AUDIO_FREQS = [250, 500, 1000, 2000, 4000, 6000, 8000]
TIMEPOINTS  = ["3m", "11m", "36m"]

# ── Pre-operative column names ────────────────────────────────────────────────
ALL_AUDIO = [f"pre_audio_{f}" for f in AUDIO_FREQS]
SPEECH    = ["pre_speech_40", "pre_speech_55", "pre_speech_70", "pre_speech_85"]

CONTRA_COLS = [
    "pre_phon_contra_a_i",  "pre_phon_contra_a_u",  "pre_phon_contra_a_o",
    "pre_phon_contra_a_ae", "pre_phon_contra_a_uh",  "pre_phon_contra_ae_i",
    "pre_phon_contra_ae_uh","pre_phon_contra_i_u",  "pre_phon_contra_i_y",
    "pre_phon_contra_i_uh", "pre_phon_contra_o_u",  "pre_phon_contra_o_uh",
    "pre_phon_contra_u_uh", "pre_phon_contra_y_u",  "pre_phon_contra_r_a",
    "pre_phon_contra_s_z",  "pre_phon_contra_sh_s", "pre_phon_contra_sh_u",
    "pre_phon_contra_z_m",  "pre_phon_contra_z_v",
]

# ── Post-operative phoneme column names (per timepoint) ───────────────────────
PHON_PAIRS = [
    "a_i", "a_u", "a_o", "a_ae", "a_uh", "ae_i", "ae_uh", "i_u", "i_y",
    "i_uh", "o_u", "o_uh", "u_uh", "y_u", "r_a", "s_z", "sh_s", "sh_u",
    "z_m", "z_v",
]

def post_phon_cols(tp: str) -> list[str]:
    return [f"post_phon_{pair}_{tp}" for pair in PHON_PAIRS]

# ── Base features (demographics + device + aetiology) ─────────────────────────
PATIENT_FEATS = [
    "age_at_first_implant",
    "reimplant_flag",
    "implant_event_count",
    "SideLabel_enc",
]

DEVICE_FEATS = [
    "mfr_AB",
    "mfr_MedEl",
    "mfr_Neurelec",
    "mfr_Other",
]

ETIOLOGY_FEATS = [
    "kw_congenital_type",
    "kw_postlingually_acquired",
    "kw_perilingual",
    "kw_progressive_slow",
    "kw_sudden",
    "kw_unknown_cause",
    "kw_congenital_cause",
    "kw_normal_ear",
    "kw_ci_bilateral",
    "has_malformation",
    "kw_enlarged_vestibular_aqueduct",
    "has_genetic",
    "kw_connexine_26",
    "kw_coch_dfna9",
    "has_infectious",
    "kw_meningitis",
    "has_meniere",
    "has_risk_factor",
    "kw_family_history",
]

BASE_FEATS = PATIENT_FEATS + DEVICE_FEATS + ETIOLOGY_FEATS

SPEECH_FEATS  = ["pre_EaSI"] + SPEECH
PHONEME_FEATS = ["pre_phon_contra_pct"]

# ── Tonotopic frequency-specific predictor sets ───────────────────────────────
# Each outcome frequency is predicted using only the adjacent
# preoperative frequencies along the tonotopic axis of the cochlea.
FREQ_PREDS = {
    250:  ["pre_audio_250", "pre_audio_500", "pre_audio_1000"],
    500:  ["pre_audio_250", "pre_audio_500", "pre_audio_1000"],
    1000: ["pre_audio_500", "pre_audio_1000", "pre_audio_2000"],
    2000: ["pre_audio_1000", "pre_audio_2000", "pre_audio_4000"],
    4000: ["pre_audio_2000", "pre_audio_4000", "pre_audio_6000", "pre_audio_8000"],
    6000: ["pre_audio_2000", "pre_audio_4000", "pre_audio_6000"],
    8000: ["pre_audio_2000", "pre_audio_4000", "pre_audio_8000"],
}

# ── Feature set builders ──────────────────────────────────────────────────────

def get_features_model1(approach: int, freq: int, group: str) -> list[str]:
    """
    Return feature columns for Model 1 (audiometry prediction).

    approach : 1 = all 7 freq, 2 = tonotopic, 3 = tonotopic + split
    freq     : outcome frequency in Hz
    group    : 'assessable' or 'non_assessable'
    """
    if approach == 1:
        audio = ALL_AUDIO
    else:
        audio = FREQ_PREDS[freq]

    feats = audio + BASE_FEATS

    if approach == 3 and group == "assessable":
        feats = feats + SPEECH_FEATS + PHONEME_FEATS

    return feats


def get_features_model2(approach: int) -> list[str]:
    """
    Return feature columns for Model 2 (EaSI prediction).

    approach : 1 = audio + base, 2 = + speech, 3 = + speech + phoneme
    """
    feats = ALL_AUDIO + BASE_FEATS
    if approach >= 2:
        feats = feats + SPEECH_FEATS
    if approach == 3:
        feats = feats + PHONEME_FEATS
    return feats


def get_features_model3(approach: int) -> list[str]:
    """
    Return feature columns for Model 3 (phoneme classification).

    approach : 1 = audio + base, 2 = + speech, 3 = + speech + phoneme
    """
    return get_features_model2(approach)


def calc_easi(row: pd.Series) -> float:
    """
    Compute Eargroup Speech Index from four speech levels.
    Returns NaN if any level is missing.

    EaSI = (SRS_40 + SRS_55 + 2*SRS_70 + SRS_85) / 5
    """
    vals = [row[c] for c in SPEECH]
    if any(pd.isna(v) for v in vals):
        return np.nan
    return (vals[0] + vals[1] + 2 * vals[2] + vals[3]) / 5
