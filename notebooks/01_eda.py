
# %%
import sys, os
sys.path.insert(0, os.path.abspath("../src"))

import warnings
warnings.filterwarnings("ignore")

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

from preprocessing import load_and_preprocess
from features import AUDIO_FREQS, TIMEPOINTS, SPEECH, CONTRA_COLS, calc_easi

plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 10,
    "axes.titlesize": 11, "axes.labelsize": 10,
    "axes.spines.top": False, "axes.spines.right": False,
    "figure.dpi": 150,
})

C1, C2 = "#2196F3", "#FF9800"   # assessable=blue, non-assessable=orange
OUTPUT  = "../outputs/"

# %%
# ── Load data ─────────────────────────────────────────────────────────────────
DATA_PATH = "../data/Audiometry_data.csv"
df = load_and_preprocess(DATA_PATH)

# Compute post-operative EaSI
for tp in TIMEPOINTS:
    cols = [f"post_speech_{l}_{tp}" for l in [40, 55, 70, 85]]
    if all(c in df.columns for c in cols):
        has = df[cols].notna().all(axis=1)
        df[f"post_EaSI_{tp}"] = np.nan
        df.loc[has, f"post_EaSI_{tp}"] = (
            df.loc[has, cols[0]] + df.loc[has, cols[1]] +
            2 * df.loc[has, cols[2]] + df.loc[has, cols[3]]
        ) / 5

ass_df = df[df["group"] == "assessable"].copy()
print(f"Total: n={len(df)} | Assessable: {len(ass_df)} | Non-assessable: {len(df)-len(ass_df)}")

# %%
# ── Figure 1: Missingness ────────────────────────────────────────────────────
miss_audio = {f"{f} Hz": df[f"pre_audio_{f}"].isna().mean() * 100
              for f in AUDIO_FREQS}
miss_speech = {
    "Speech 40 dB": df["pre_speech_40"].isna().mean() * 100,
    "Speech 55 dB": df["pre_speech_55"].isna().mean() * 100,
    "Speech 70 dB": df["pre_speech_70"].isna().mean() * 100,
    "Speech 85 dB": df["pre_speech_85"].isna().mean() * 100,
    "Phoneme disc.": df[[c for c in CONTRA_COLS if c in df.columns]].isna().all(axis=1).mean() * 100,
}

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4))
for ax, data, color, title in [
    (ax1, miss_audio,  C1, "(a) Audiometry missingness"),
    (ax2, miss_speech, C2, "(b) Speech and phoneme missingness"),
]:
    bars = ax.bar(data.keys(), data.values(), color=color, alpha=0.85, edgecolor="white")
    ax.set_ylabel("Missing (%)"); ax.set_title(title); ax.set_ylim(0, 75)
    for bar, val in zip(bars, data.values()):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 1,
                f"{val:.0f}%", ha="center", va="bottom", fontsize=9)

plt.tight_layout()
plt.savefig(f"{OUTPUT}fig1_missingness.pdf", bbox_inches="tight")
plt.show()
print("Fig 1 saved")

# %%
# ── Figure 2: Pre-operative distributions ───────────────────────────────────
fig, axes = plt.subplots(1, 2, figsize=(12, 5))

# Boxplot: audiometry by group
data_ass = [df.loc[df["group"] == "assessable",     f"pre_audio_{f}"].dropna().values for f in AUDIO_FREQS]
data_non = [df.loc[df["group"] == "non_assessable", f"pre_audio_{f}"].dropna().values for f in AUDIO_FREQS]

x, w = np.arange(len(AUDIO_FREQS)), 0.35
for data, pos, col in [(data_ass, x - w/2, C1), (data_non, x + w/2, C2)]:
    axes[0].boxplot(data, positions=pos, widths=0.3, patch_artist=True,
                    boxprops=dict(facecolor=col, alpha=0.7),
                    medianprops=dict(color="black", linewidth=2),
                    whiskerprops=dict(color="grey"), capprops=dict(color="grey"),
                    flierprops=dict(marker="o", markersize=2, color="grey", alpha=0.3))
axes[0].set_xticks(x)
axes[0].set_xticklabels([f"{f} Hz" for f in AUDIO_FREQS], rotation=45)
axes[0].set_ylabel("Threshold (dB HL)")
axes[0].set_title("(a) Pre-operative audiometry by group")
axes[0].invert_yaxis()
axes[0].legend([mpatches.Patch(facecolor=C1, alpha=0.7),
                mpatches.Patch(facecolor=C2, alpha=0.7)],
               ["Assessable", "Non-assessable"], loc="lower right")

# Histogram: pre-EaSI
easi_ass = ass_df["pre_EaSI"].dropna()
axes[1].hist(easi_ass, bins=25, color=C1, alpha=0.8, edgecolor="white")
axes[1].axvline(easi_ass.median(), color="black", linestyle="--", linewidth=1.5,
                label=f"Median = {easi_ass.median():.0f}%")
axes[1].set_xlabel("Pre-operative EaSI (%)")
axes[1].set_ylabel("Count")
axes[1].set_title(f"(b) Pre-operative EaSI (assessable, n={len(easi_ass)})")
axes[1].legend()

plt.tight_layout()
plt.savefig(f"{OUTPUT}fig2_preop.pdf", bbox_inches="tight")
plt.show()

# %%
# ── Figure 3: Post-operative audiometry by timepoint ─────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(15, 5))
tp_colors = {"3m": "#42A5F5", "11m": "#1565C0", "36m": "#0D47A1"}

for ax, tp in zip(axes, TIMEPOINTS):
    data = [pd.to_numeric(df[f"post_audio_{f}_{tp}"], errors="coerce").dropna().values
            for f in AUDIO_FREQS if f"post_audio_{f}_{tp}" in df.columns]
    freqs = [f for f in AUDIO_FREQS if f"post_audio_{f}_{tp}" in df.columns]
    bp = ax.boxplot(data, patch_artist=True,
                    medianprops=dict(color="black", linewidth=2),
                    whiskerprops=dict(color="grey"), capprops=dict(color="grey"),
                    flierprops=dict(marker="o", markersize=2, color="grey", alpha=0.3))
    for patch in bp["boxes"]:
        patch.set_facecolor(tp_colors[tp]); patch.set_alpha(0.7)
    ax.set_xticks(range(1, len(freqs) + 1))
    ax.set_xticklabels([f"{f} Hz" for f in freqs], rotation=45)
    ax.set_ylabel("Threshold (dB HL)")
    idx = TIMEPOINTS.index(tp)
    ax.set_title(f"({chr(97+idx)}) {['3 months','11 months','36 months'][idx]}")
    ax.invert_yaxis()

plt.suptitle("Post-operative audiometry thresholds by timepoint", fontsize=12, y=1.02)
plt.tight_layout()
plt.savefig(f"{OUTPUT}fig3_postop_audio.pdf", bbox_inches="tight")
plt.show()

# %%
# ── Figure 4: Post-operative EaSI by timepoint ───────────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(15, 5))
labels = ["3 months", "11 months", "36 months"]

for ax, tp, label, col in zip(axes, TIMEPOINTS, labels,
                               ["#42A5F5", "#1565C0", "#0D47A1"]):
    data = df[f"post_EaSI_{tp}"].dropna()
    idx  = TIMEPOINTS.index(tp)
    ax.hist(data, bins=25, color=col, alpha=0.8, edgecolor="white")
    ax.axvline(data.median(), color="black", linestyle="--", linewidth=1.5,
               label=f"Median={data.median():.0f}%")
    ax.set_xlabel("Post-operative EaSI (%)")
    ax.set_ylabel("Count")
    ax.set_title(f"({chr(97+idx)}) {label} (n={len(data)})")
    ax.legend(fontsize=9)

plt.suptitle("Post-operative EaSI distribution by timepoint (assessable group)",
             fontsize=12, y=1.02)
plt.tight_layout()
plt.savefig(f"{OUTPUT}fig4_postop_easi.pdf", bbox_inches="tight")
plt.show()

# %%
# ── Figure 5: Phoneme failure rates by timepoint ─────────────────────────────
from features import PHON_PAIRS, post_phon_cols

fig, axes = plt.subplots(1, 3, figsize=(16, 5))
labels = ["3 months", "11 months", "36 months"]

for ax, tp, label in zip(axes, TIMEPOINTS, labels):
    fail_rates = {}
    for pair in PHON_PAIRS:
        col  = f"post_phon_{pair}_{tp}"
        if col not in df.columns:
            continue
        data = pd.to_numeric(ass_df[col], errors="coerce").dropna()
        if len(data) >= 10:
            fail_rates[pair.replace("_", "/")] = (data < 1.0).mean() * 100

    if not fail_rates:
        continue

    fr_df = pd.DataFrame(list(fail_rates.items()),
                         columns=["pair", "fail_rate"]).sort_values(
                             "fail_rate", ascending=False)
    colors = ["#D32F2F" if v >= 5 else "#90CAF9" for v in fr_df["fail_rate"]]
    ax.barh(fr_df["pair"], fr_df["fail_rate"], color=colors, alpha=0.85, edgecolor="white")
    ax.axvline(5, color="red", linestyle="--", linewidth=1, alpha=0.5)
    ax.set_xlabel("Failure rate (%)")
    idx = TIMEPOINTS.index(tp)
    ax.set_title(f"({chr(97+idx)}) {label}")

plt.suptitle("Post-operative phoneme failure rates (assessable group)", fontsize=12, y=1.02)
plt.tight_layout()
plt.savefig(f"{OUTPUT}fig5_phoneme_failure.pdf", bbox_inches="tight")
plt.show()

# %%
# ── Figure 6: Pre-op vs post-op correlations ─────────────────────────────────
fig, axes = plt.subplots(2, 3, figsize=(15, 9))

pre_pta = df[["pre_audio_500", "pre_audio_1000",
              "pre_audio_2000", "pre_audio_4000"]].mean(axis=1)

for col_i, (tp, label) in enumerate(zip(TIMEPOINTS,
                                         ["3 months", "11 months", "36 months"])):
    # Row 0: audiometry correlation
    ax0 = axes[0][col_i]
    post_cols = [f"post_audio_{f}_{tp}" for f in [500, 1000, 2000, 4000]]
    if all(c in df.columns for c in post_cols):
        post_pta = df[post_cols].apply(pd.to_numeric, errors="coerce").mean(axis=1)
        mask = pre_pta.notna() & post_pta.notna()
        grp_colors = [C1 if g == "assessable" else C2 for g in df.loc[mask, "group"]]
        ax0.scatter(pre_pta[mask], post_pta[mask], c=grp_colors, alpha=0.35, s=12)
        r = np.corrcoef(pre_pta[mask], post_pta[mask])[0, 1]
        ax0.set_xlabel("Pre-op PTA (dB HL)")
        ax0.set_ylabel("Post-op PTA (dB HL)")
        ax0.set_title(f"({chr(97+col_i)}) Audiometry {label}\nr = {r:.2f}")
        ax0.invert_xaxis(); ax0.invert_yaxis()
        if col_i == 0:
            ax0.legend([mpatches.Patch(facecolor=C1, alpha=0.7),
                        mpatches.Patch(facecolor=C2, alpha=0.7)],
                       ["Assessable", "Non-assessable"], fontsize=8)

    # Row 1: EaSI correlation
    ax1 = axes[1][col_i]
    post_easi_col = f"post_EaSI_{tp}"
    if post_easi_col in df.columns:
        mask2 = df["pre_EaSI"].notna() & df[post_easi_col].notna()
        if mask2.sum() > 10:
            ax1.scatter(df.loc[mask2, "pre_EaSI"], df.loc[mask2, post_easi_col],
                        color=C1, alpha=0.35, s=12)
            r2 = np.corrcoef(df.loc[mask2, "pre_EaSI"],
                             df.loc[mask2, post_easi_col])[0, 1]
            ax1.set_xlabel("Pre-op EaSI (%)")
            ax1.set_ylabel("Post-op EaSI (%)")
            ax1.set_title(f"({chr(100+col_i)}) EaSI {label}\nr = {r2:.2f}")

plt.suptitle("Pre-operative vs post-operative correlations by timepoint",
             fontsize=13, y=1.01)
plt.tight_layout()
plt.savefig(f"{OUTPUT}fig6_prepost_correlation.pdf", bbox_inches="tight")
plt.show()

# %%
# ── Table 1 preview: demographics ───────────────────────────────────────────
print("\nCohort demographics summary:")
print(f"Total n = {len(df)}")
print(f"Assessable n = {(df['group']=='assessable').sum()}")
print(f"Age at implant: median={df['age_at_first_implant'].median():.1f}, "
      f"IQR {df['age_at_first_implant'].quantile(0.25):.1f}–"
      f"{df['age_at_first_implant'].quantile(0.75):.1f}")
print(f"Pre-EaSI (assessable, n={ass_df['pre_EaSI'].notna().sum()}): "
      f"median={ass_df['pre_EaSI'].median():.0f}%, "
      f"IQR {ass_df['pre_EaSI'].quantile(0.25):.0f}–"
      f"{ass_df['pre_EaSI'].quantile(0.75):.0f}%")
print(f"Train (<=2019): n={( df['implant_year'] < 2020).sum()}")
print(f"Test  (>=2020): n={(df['implant_year'] >= 2020).sum()}")

print("\nAll EDA figures saved to outputs/")

# %%
