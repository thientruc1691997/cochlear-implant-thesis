"""
model3_phoneme.py
-----------------
Train and evaluate Model 3: binary classification of post-operative
phoneme discrimination failure on the most acoustically challenging
contrast pairs.

Due to ceiling effects (79-90% perfect scores), regression is not
feasible. Binary outcome: 1 = patient failed to achieve perfect
score on a given contrast pair, 0 = perfect score.

Eligibility: only contrast pairs with >= 10 failures at a given
timepoint are included (n_fail >= 10).

Three approaches match Model 2:
  Approach 1: Audiometry + base features
  Approach 2: + speech audiometry
  Approach 3: + phoneme discrimination

Usage
-----
    python src/model3_phoneme.py --data data/Audiometry_data.csv
"""

import argparse
import numpy as np
import pandas as pd

from preprocessing import load_and_preprocess
from features import (
    TIMEPOINTS, PHON_PAIRS, post_phon_cols,
    get_features_model3,
)
from utils import (
    build_classification_models,
    run_classification_cv,
    summarise_cv_classification,
)

MIN_FAILURES = 10  # eligibility threshold


def get_eligible_pairs(
    df: pd.DataFrame,
    min_failures: int = MIN_FAILURES,
) -> list[tuple[str, str]]:
    """
    Return list of (pair, timepoint) combinations with >= min_failures
    in the assessable group.
    """
    ass_df = df[df["group"] == "assessable"]
    eligible = []
    for tp in TIMEPOINTS:
        for pair in PHON_PAIRS:
            col = f"post_phon_{pair}_{tp}"
            if col not in df.columns:
                continue
            data = pd.to_numeric(ass_df[col], errors="coerce").dropna()
            n_fail = (data < 1.0).sum()
            if n_fail >= min_failures:
                eligible.append((pair, tp, int(n_fail), len(data)))
    return eligible


def run_model3(df: pd.DataFrame) -> pd.DataFrame:
    """
    Run Model 3 for all eligible contrast pairs and approaches.

    Returns
    -------
    pd.DataFrame with columns:
        pair, timepoint, n_total, n_fail, approach, model,
        auc, f1, precision, recall
    """
    ass_df   = df[df["group"] == "assessable"].copy()
    models   = build_classification_models()
    eligible = get_eligible_pairs(df)

    print(f"\nEligible contrast-timepoint combinations: {len(eligible)}")
    for pair, tp, n_fail, n_total in eligible:
        pct = 100 * n_fail / n_total
        print(f"  /{pair.replace('_', '/')}/ at {tp}: "
              f"{n_fail} failures / {n_total} ({pct:.1f}%)")

    all_results = []

    for approach in [1, 2, 3]:
        feat_cols = get_features_model3(approach)
        feat_cols = [c for c in feat_cols if c in ass_df.columns]
        print(f"\nApproach {approach} | Features: {len(feat_cols)}")

        for pair, tp, n_fail, n_total in eligible:
            col = f"post_phon_{pair}_{tp}"

            sub = ass_df[feat_cols + [col]].copy()
            sub[col] = pd.to_numeric(sub[col], errors="coerce")
            sub = sub.dropna(subset=[col])

            # Binary outcome: 1 = failure (score < 1.0), 0 = perfect
            y = (sub[col] < 1.0).astype(int).values
            X = sub[feat_cols]

            if y.sum() < MIN_FAILURES:
                continue

            cv_res = run_classification_cv(X, y, models)
            cv_df  = summarise_cv_classification(cv_res)

            pair_label = pair.replace("_", "/")
            print(f"\n  /{pair_label}/ at {tp} "
                  f"({n_fail} fail / {n_total}, A{approach}):")
            print(f"  {'Model':<12} {'AUC':>7} {'F1':>7} "
                  f"{'Prec':>7} {'Recall':>7}")
            print("  " + "-" * 40)
            for _, row in cv_df.iterrows():
                print(f"  {row['model']:<12} {row['auc']:>7.3f} "
                      f"{row['f1']:>7.3f} {row['precision']:>7.3f} "
                      f"{row['recall']:>7.3f}")

            for _, row in cv_df.iterrows():
                all_results.append({
                    "pair":      pair,
                    "timepoint": tp,
                    "n_total":   n_total,
                    "n_fail":    n_fail,
                    "approach":  approach,
                    "model":     row["model"],
                    "auc":       row["auc"],
                    "f1":        row["f1"],
                    "precision": row["precision"],
                    "recall":    row["recall"],
                })

    return pd.DataFrame(all_results)


def print_summary(results: pd.DataFrame) -> None:
    """Print best AUC and F1 per pair/timepoint combination."""
    print(f"\n{'='*65}\nMODEL 3 SUMMARY — Best RF results")
    rf = results[results["model"] == "RF"]
    print(f"\n  {'Pair':<20} {'TP':<5} {'A':<3} {'AUC':>7} {'F1':>7}")
    print("  " + "-" * 45)
    for _, row in rf.iterrows():
        pair = row["pair"].replace("_", "/")
        print(f"  /{pair:<19}/ {row['timepoint']:<5} "
              f"A{row['approach']:<2} {row['auc']:>7.3f} {row['f1']:>7.3f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data",   default="data/Audiometry_data.csv")
    parser.add_argument("--output", default="outputs/model3_results.csv")
    args = parser.parse_args()

    print("Loading and preprocessing data...")
    df = load_and_preprocess(args.data)

    print("\nRunning Model 3 (phoneme discrimination classification)...")
    results = run_model3(df)

    results.to_csv(args.output, index=False)
    print(f"\nResults saved to {args.output}")

    print_summary(results)
