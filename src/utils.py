"""
utils.py
--------
Shared utilities: model builders, cross-validation runners,
metric helpers, and results formatting.
"""

import copy
import numpy as np
import pandas as pd

from sklearn.linear_model import LinearRegression, LogisticRegression
from sklearn.svm import SVR, SVC
from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.model_selection import KFold, StratifiedKFold
from sklearn.metrics import (
    mean_squared_error,
    mean_absolute_error,
    roc_auc_score,
    f1_score,
    precision_score,
    recall_score,
)
from xgboost import XGBRegressor, XGBClassifier

RANDOM_SEED = 42
CHRON_SPLIT_YEAR = 2020


# ── Model builders ────────────────────────────────────────────────────────────

def build_regression_models() -> dict:
    """Return dict of regression models with thesis hyperparameters."""
    return {
        "Baseline": None,
        "LR": Pipeline([
            ("imp", SimpleImputer(strategy="median")),
            ("sc",  StandardScaler()),
            ("m",   LinearRegression()),
        ]),
        "SVM": Pipeline([
            ("imp", SimpleImputer(strategy="median")),
            ("sc",  StandardScaler()),
            ("m",   SVR(kernel="rbf", C=10, epsilon=0.5)),
        ]),
        "XGB": XGBRegressor(
            n_estimators=400, max_depth=4, learning_rate=0.05,
            random_state=RANDOM_SEED, verbosity=0, tree_method="hist",
        ),
        "RF": RandomForestRegressor(
            n_estimators=300, max_depth=6, min_samples_leaf=5,
            random_state=RANDOM_SEED, n_jobs=-1,
        ),
    }


def build_classification_models() -> dict:
    """
    Return dict of classification models for Model 3.
    All include class imbalance handling.
    """
    return {
        "Baseline": None,  # majority class predictor
        "LR": Pipeline([
            ("imp", SimpleImputer(strategy="median")),
            ("sc",  StandardScaler()),
            ("m",   LogisticRegression(class_weight="balanced",
                                       max_iter=1000,
                                       random_state=RANDOM_SEED)),
        ]),
        "SVM": Pipeline([
            ("imp", SimpleImputer(strategy="median")),
            ("sc",  StandardScaler()),
            ("m",   SVC(kernel="rbf", C=10,
                        class_weight="balanced",
                        probability=True,
                        random_state=RANDOM_SEED)),
        ]),
        "XGB": XGBClassifier(
            n_estimators=200, max_depth=4, learning_rate=0.05,
            scale_pos_weight=10,
            random_state=RANDOM_SEED, verbosity=0, tree_method="hist",
        ),
        "RF": RandomForestClassifier(
            n_estimators=100, max_depth=6, min_samples_leaf=5,
            class_weight="balanced",
            random_state=RANDOM_SEED, n_jobs=-1,
        ),
    }


# ── Cross-validation: regression ─────────────────────────────────────────────

def run_regression_cv(
    X: pd.DataFrame,
    y: np.ndarray,
    models: dict,
    n_splits: int = 5,
) -> dict:
    """
    5-fold cross-validation for regression models.

    Returns
    -------
    dict : {model_name: {"rmse": [...], "mae": [...]}}
    """
    kf = KFold(n_splits=n_splits, shuffle=True, random_state=RANDOM_SEED)
    results = {name: {"rmse": [], "mae": []} for name in models}

    for tr_idx, va_idx in kf.split(X):
        X_tr, X_va = X.iloc[tr_idx], X.iloc[va_idx]
        y_tr, y_va = y[tr_idx], y[va_idx]

        baseline_pred = np.full(len(va_idx), y_tr.mean())
        results["Baseline"]["rmse"].append(
            np.sqrt(mean_squared_error(y_va, baseline_pred)))
        results["Baseline"]["mae"].append(
            mean_absolute_error(y_va, baseline_pred))

        for name, model in models.items():
            if name == "Baseline":
                continue
            m = copy.deepcopy(model)
            m.fit(X_tr, y_tr)
            preds = m.predict(X_va)
            results[name]["rmse"].append(
                np.sqrt(mean_squared_error(y_va, preds)))
            results[name]["mae"].append(
                mean_absolute_error(y_va, preds))

    return results


def run_regression_chronological(
    df: pd.DataFrame,
    feat_cols: list[str],
    outcome: str,
    models: dict,
    split_year: int = CHRON_SPLIT_YEAR,
) -> dict:
    """
    Chronological train/test split for regression.

    Returns
    -------
    dict : {model_name: {"rmse": float, "mae": float}}
    """
    sub = df[feat_cols + [outcome, "implant_year"]].dropna(subset=[outcome])
    tr  = sub[sub["implant_year"] <  split_year]
    te  = sub[sub["implant_year"] >= split_year]

    if len(tr) < 20 or len(te) < 10:
        return {}

    X_tr, y_tr = tr[feat_cols], tr[outcome].values
    X_te, y_te = te[feat_cols], te[outcome].values
    results = {}

    baseline_pred = np.full(len(te), y_tr.mean())
    results["Baseline"] = {
        "rmse": np.sqrt(mean_squared_error(y_te, baseline_pred)),
        "mae":  mean_absolute_error(y_te, baseline_pred),
    }

    for name, model in models.items():
        if name == "Baseline":
            continue
        m = copy.deepcopy(model)
        m.fit(X_tr, y_tr)
        preds = m.predict(X_te)
        results[name] = {
            "rmse": np.sqrt(mean_squared_error(y_te, preds)),
            "mae":  mean_absolute_error(y_te, preds),
        }

    return results


# ── Cross-validation: classification ─────────────────────────────────────────

def optimise_threshold(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    thresholds: np.ndarray = np.arange(0.05, 0.91, 0.05),
) -> float:
    """
    Find the probability threshold that maximises F1 on a validation set.
    Returns the optimal threshold value.
    """
    best_f1, best_thr = 0.0, 0.5
    for thr in thresholds:
        preds = (y_prob >= thr).astype(int)
        f1 = f1_score(y_true, preds, zero_division=0)
        if f1 > best_f1:
            best_f1, best_thr = f1, thr
    return best_thr


def run_classification_cv(
    X: pd.DataFrame,
    y: np.ndarray,
    models: dict,
    n_splits: int = 5,
) -> dict:
    """
    5-fold stratified cross-validation for binary classification.
    Threshold is optimised per fold to maximise F1.

    Returns
    -------
    dict : {model_name: {"auc": [...], "f1": [...],
                         "precision": [...], "recall": [...]}}
    """
    skf = StratifiedKFold(n_splits=n_splits, shuffle=True,
                          random_state=RANDOM_SEED)
    metrics = ["auc", "f1", "precision", "recall"]
    results = {name: {m: [] for m in metrics} for name in models}

    for tr_idx, va_idx in skf.split(X, y):
        X_tr, X_va = X.iloc[tr_idx], X.iloc[va_idx]
        y_tr, y_va = y[tr_idx], y[va_idx]

        # Majority-class baseline
        majority = int(np.bincount(y_tr).argmax())
        bl_preds = np.full(len(va_idx), majority)
        results["Baseline"]["auc"].append(
            roc_auc_score(y_va, bl_preds) if len(np.unique(y_va)) > 1 else 0.5)
        results["Baseline"]["f1"].append(
            f1_score(y_va, bl_preds, zero_division=0))
        results["Baseline"]["precision"].append(
            precision_score(y_va, bl_preds, zero_division=0))
        results["Baseline"]["recall"].append(
            recall_score(y_va, bl_preds, zero_division=0))

        for name, model in models.items():
            if name == "Baseline":
                continue
            m = copy.deepcopy(model)
            m.fit(X_tr, y_tr)
            y_prob = m.predict_proba(X_va)[:, 1]
            thr    = optimise_threshold(y_va, y_prob)
            preds  = (y_prob >= thr).astype(int)

            results[name]["auc"].append(
                roc_auc_score(y_va, y_prob) if len(np.unique(y_va)) > 1 else 0.5)
            results[name]["f1"].append(
                f1_score(y_va, preds, zero_division=0))
            results[name]["precision"].append(
                precision_score(y_va, preds, zero_division=0))
            results[name]["recall"].append(
                recall_score(y_va, preds, zero_division=0))

    return results


# ── Result summarisation helpers ──────────────────────────────────────────────

def summarise_cv_regression(cv_results: dict) -> pd.DataFrame:
    """Convert CV regression results dict to a summary DataFrame."""
    rows = []
    for name, vals in cv_results.items():
        rows.append({
            "model":    name,
            "kf_rmse":  round(np.mean(vals["rmse"]), 2),
            "kf_rmse_sd": round(np.std(vals["rmse"]), 2),
            "kf_mae":   round(np.mean(vals["mae"]),  2),
            "kf_mae_sd":  round(np.std(vals["mae"]),  2),
        })
    return pd.DataFrame(rows)


def summarise_cv_classification(cv_results: dict) -> pd.DataFrame:
    """Convert CV classification results dict to a summary DataFrame."""
    rows = []
    for name, vals in cv_results.items():
        rows.append({
            "model":     name,
            "auc":       round(np.mean(vals["auc"]),       3),
            "f1":        round(np.mean(vals["f1"]),        3),
            "precision": round(np.mean(vals["precision"]), 3),
            "recall":    round(np.mean(vals["recall"]),    3),
        })
    return pd.DataFrame(rows)


def print_regression_table(
    cv_df: pd.DataFrame,
    chron_dict: dict,
    label: str = "",
) -> None:
    """Print a formatted regression results table to stdout."""
    if label:
        print(f"\n{'='*65}\n{label}")
    header = f"  {'Model':<12} {'CV RMSE':>9} {'±SD':>6} {'CV MAE':>8} {'CH RMSE':>9} {'CH MAE':>8}"
    print(header)
    print("  " + "-" * 55)
    for _, row in cv_df.iterrows():
        ch = chron_dict.get(row["model"], {})
        print(
            f"  {row['model']:<12} {row['kf_rmse']:>9.2f} "
            f"{row['kf_rmse_sd']:>6.2f} {row['kf_mae']:>8.2f} "
            f"{ch.get('rmse', float('nan')):>9.2f} "
            f"{ch.get('mae',  float('nan')):>8.2f}"
        )
