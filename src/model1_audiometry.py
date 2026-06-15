import argparse
import numpy as np
import pandas as pd

from preprocessing import load_and_preprocess
from features import (
    AUDIO_FREQS, TIMEPOINTS,
    ALL_AUDIO, BASE_FEATS, SPEECH_FEATS, PHONEME_FEATS,
    FREQ_PREDS,
    get_features_model1,
)
from utils import (
    build_regression_models,
    run_regression_cv,
    run_regression_chronological,
    summarise_cv_regression,
    print_regression_table,
)


def run_model1(df: pd.DataFrame) -> pd.DataFrame:
    """
    Run all three approaches for Model 1.

    Returns
    -------
    pd.DataFrame with columns:
        approach, group, freq, timepoint, model,
        n, kf_rmse, kf_rmse_sd, kf_mae, kf_mae_sd,
        ch_rmse, ch_mae
    """
    models = build_regression_models()
    all_results = []

    configs = [
        # (approach, group_name, mask_fn)
        (1, "combined",       lambda df: df),
        (2, "combined",       lambda df: df),
        (3, "assessable",     lambda df: df[df["group"] == "assessable"]),
        (3, "non_assessable", lambda df: df[df["group"] == "non_assessable"]),
    ]

    for approach, group_name, subset_fn in configs:
        sub_df = subset_fn(df).copy()
        print(f"\nApproach {approach} | Group: {group_name} | n={len(sub_df)}")

        for freq in AUDIO_FREQS:
            feat_cols = get_features_model1(approach, freq, group_name)
            # Keep only columns that exist in the dataframe
            feat_cols = [c for c in feat_cols if c in sub_df.columns]

            for tp in TIMEPOINTS:
                outcome = f"post_audio_{freq}_{tp}"
                if outcome not in sub_df.columns:
                    continue

                sub = sub_df[feat_cols + [outcome, "implant_year"]].dropna(
                    subset=[outcome])
                if len(sub) < 30:
                    continue

                X = sub[feat_cols]
                y = sub[outcome].values

                # 5-fold cross-validation
                cv_res = run_regression_cv(X, y, models)
                cv_df  = summarise_cv_regression(cv_res)

                # Chronological split
                chron_res = run_regression_chronological(
                    sub, feat_cols, outcome, models)

                for _, row in cv_df.iterrows():
                    ch = chron_res.get(row["model"], {})
                    all_results.append({
                        "approach":   approach,
                        "group":      group_name,
                        "freq":       freq,
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
    """Print mean RMSE across 7 frequencies for each approach/group/timepoint."""
    configs = [
        (1, "combined"),
        (2, "combined"),
        (3, "assessable"),
        (3, "non_assessable"),
    ]
    for approach, group in configs:
        print(f"\n{'='*65}")
        print(f"Approach {approach} | {group}")
        sub = results[
            (results["approach"] == approach) &
            (results["group"]    == group)
        ]
        for tp in TIMEPOINTS:
            tp_sub = sub[sub["timepoint"] == tp]
            if tp_sub.empty:
                continue
            print(f"\n  {tp}:")
            print(f"  {'Model':<12} {'CV RMSE':>9} {'±SD':>6} {'CV MAE':>8}"
                  f" {'CH RMSE':>9} {'CH MAE':>8}")
            print("  " + "-" * 55)
            for model in ["Baseline", "LR", "SVM", "XGB", "RF"]:
                r = tp_sub[tp_sub["model"] == model]
                if r.empty:
                    continue
                print(
                    f"  {model:<12}"
                    f" {r['kf_rmse'].mean():>9.2f}"
                    f" {r['kf_rmse_sd'].mean():>6.2f}"
                    f" {r['kf_mae'].mean():>8.2f}"
                    f" {r['ch_rmse'].mean():>9.2f}"
                    f" {r['ch_mae'].mean():>8.2f}"
                )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data",   default="data/Audiometry_data.csv")
    parser.add_argument("--output", default="outputs/model1_results.csv")
    args = parser.parse_args()

    print("Loading and preprocessing data...")
    df = load_and_preprocess(args.data)

    print("\nRunning Model 1 (audiometry prediction)...")
    results = run_model1(df)

    results.to_csv(args.output, index=False)
    print(f"\nResults saved to {args.output}")

    print_summary(results)
