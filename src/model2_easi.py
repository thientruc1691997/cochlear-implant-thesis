"""
model2_easi.py
--------------
Train and evaluate Model 2: prediction of post-operative EaSI (%)
at 3, 11, and 36 months. Assessable group only.

Three approaches:
  Approach 1: Audiometry + base features
  Approach 2: + preoperative speech audiometry (EaSI + individual levels)
  Approach 3: + contralateral phoneme discrimination

Usage
-----
    python src/model2_easi.py --data data/Audiometry_data.csv
"""

import argparse
import numpy as np
import pandas as pd

from preprocessing import load_and_preprocess
from features import (
    TIMEPOINTS,
    ALL_AUDIO, BASE_FEATS, SPEECH_FEATS, PHONEME_FEATS,
    SPEECH, calc_easi,
    get_features_model2,
)
from utils import (
    build_regression_models,
    run_regression_cv,
    run_regression_chronological,
    summarise_cv_regression,
    print_regression_table,
)


def _compute_post_easi(df: pd.DataFrame) -> pd.DataFrame:
    """Add post_EaSI_3m, post_EaSI_11m, post_EaSI_36m columns."""
    df = df.copy()
    for tp in TIMEPOINTS:
        levels = [f"post_speech_{l}_{tp}" for l in [40, 55, 70, 85]]
        if not all(c in df.columns for c in levels):
            continue
        has_all = df[levels].notna().all(axis=1)
        df[f"post_EaSI_{tp}"] = np.nan
        df.loc[has_all, f"post_EaSI_{tp}"] = (
            df.loc[has_all, levels[0]] +
            df.loc[has_all, levels[1]] +
            2 * df.loc[has_all, levels[2]] +
            df.loc[has_all, levels[3]]
        ) / 5
    return df


def run_model2(df: pd.DataFrame) -> pd.DataFrame:
    """
    Run all three approaches for Model 2 (EaSI prediction).

    Parameters
    ----------
    df : pd.DataFrame
        Preprocessed dataframe from load_and_preprocess().

    Returns
    -------
    pd.DataFrame with columns:
        approach, timepoint, model, n,
        kf_rmse, kf_rmse_sd, kf_mae, kf_mae_sd, ch_rmse, ch_mae
    """
    # Compute post-operative EaSI outcomes
    df = _compute_post_easi(df)

    # Restrict to assessable group
    ass_df = df[df["group"] == "assessable"].copy()
    print(f"Assessable group: n = {len(ass_df)}")

    models     = build_regression_models()
    all_results = []

    for approach in [1, 2, 3]:
        feat_cols = get_features_model2(approach)
        feat_cols = [c for c in feat_cols if c in ass_df.columns]
        print(f"\nApproach {approach} | Features: {len(feat_cols)}")

        for tp in TIMEPOINTS:
            outcome = f"post_EaSI_{tp}"
            if outcome not in ass_df.columns:
                continue

            sub = ass_df[feat_cols + [outcome, "implant_year"]].dropna(
                subset=[outcome])
            if len(sub) < 30:
                continue

            X = sub[feat_cols]
            y = sub[outcome].values

            print(f"  {tp}: n={len(sub)}, mean EaSI={y.mean():.1f}%")

            # 5-fold CV
            cv_res = run_regression_cv(X, y, models)
            cv_df  = summarise_cv_regression(cv_res)

            # Chronological split
            chron_res = run_regression_chronological(
                sub, feat_cols, outcome, models)

            print_regression_table(cv_df, chron_res,
                                   label=f"A{approach} | {tp}")

            for _, row in cv_df.iterrows():
                ch = chron_res.get(row["model"], {})
                all_results.append({
                    "approach":   approach,
                    "timepoint":  tp,
                    "model":      row["model"],
                    "n":          len(sub),
                    "kf_rmse":    row["kf_rmse"],
                    "kf_rmse_sd": row["kf_rmse_sd"],
                    "kf_mae":     row["kf_mae"],
                    "kf_mae_sd":  row["kf_mae_sd"],
                    "ch_rmse":    ch.get("rmse", np.nan),
                    "ch_mae":     ch.get("mae",  np.nan),
                })

    return pd.DataFrame(all_results)


def print_summary(results: pd.DataFrame) -> None:
    """Print best model per approach per timepoint."""
    print(f"\n{'='*65}\nMODEL 2 SUMMARY — Best RF per approach")
    for tp in TIMEPOINTS:
        print(f"\n  {tp}:")
        print(f"  {'Approach':<15} {'CV RMSE':>9} {'CH RMSE':>9} {'CH MAE':>8}")
        print("  " + "-" * 45)
        for approach in [1, 2, 3]:
            r = results[
                (results["approach"] == approach) &
                (results["timepoint"] == tp) &
                (results["model"] == "RF")
            ]
            if r.empty:
                continue
            print(
                f"  A{approach:<14}"
                f" {r['kf_rmse'].values[0]:>9.2f}"
                f" {r['ch_rmse'].values[0]:>9.2f}"
                f" {r['ch_mae'].values[0]:>8.2f}"
            )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data",   default="data/Audiometry_data.csv")
    parser.add_argument("--output", default="outputs/model2_results.csv")
    args = parser.parse_args()

    print("Loading and preprocessing data...")
    df = load_and_preprocess(args.data)

    print("\nRunning Model 2 (EaSI prediction)...")
    results = run_model2(df)

    results.to_csv(args.output, index=False)
    print(f"\nResults saved to {args.output}")

    print_summary(results)
