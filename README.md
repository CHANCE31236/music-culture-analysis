# Global Music Aesthetics and Cultural Values: A Cross-Country Empirical Study

An empirical study linking **streaming-era music aesthetics** (Spotify audio features)
to **national cultural values** (Hofstede's six dimensions), using streaming-volume
weighted country-level aggregates, PCA, hierarchical clustering, and nested
regression designs.

This repository contains the complete, reproducible R analysis pipeline that
generates every table and figure reported in the dissertation *"Global Music
Aesthetics and Cultural Values: An Empirical Study Based on Cross-Country
Streaming Data"* (Appendix A mirrors `music_culture_analysis.R`).

## Research Design

| Step | Method | Output |
| --- | --- | --- |
| 1. Aggregation | Weekly Top-200 streams (18 months) weighted by country, main-artist rows only (`pivot == 0`), deduplicated by track URI | Country-level audio features × 73 countries |
| 2. EDA | Descriptive statistics, regional grouping, normality (Shapiro-Wilk), Pearson/Spearman correlation | Table 5-1, Appendix D1 |
| 3. Dimensionality reduction | PCA on 9 audio features (standardized); 3 components retained (eigenvalue > 1 / scree elbow) | Table 5-2, scree & loading plots |
| 4. Clustering | Hierarchical clustering on principal components (HCPC, 3 clusters) + ANOVA & Kruskal-Wallis on Hofstede dimensions | Table 5-3, cluster boxplots |
| 5. Nested regression | PC1–PC3 scores regressed on Hofstede dimensions, with and without log GDP per capita, on nested samples (60 vs 55 countries) | Tables 5-4 to 5-6 |
| 6. Diagnostics | VIF (multicollinearity), White / studentized Breusch-Pagan test (heteroscedasticity), HC3 robust standard errors, sample-size audit | Tables 5-7, 5-8 |

## Key Findings (direction of association; see dissertation for full estimates)

- **PC1 "Energetic & Upbeat"** (high loadings: energy, valence, loudness,
  danceability; negative: acousticness) — negatively associated with
  **Uncertainty Avoidance (UAI)**; stable across sample tiers and GDP controls.
- **PC3 "Instrumental Purity"** (high loading: instrumentalness) — associated
  with **Individualism (IDV)** and **Long-Term Orientation (LTO)**.
- HCPC clusters differ significantly on **PDI, IDV, UAI, IVR** (ANOVA);
  Kruskal-Wallis confirms PDI/IDV/UAI (non-parametric robustness).
- All VIF values ≤ 2.31; mild heteroscedasticity in PC3 models addressed with
  HC3 robust standard errors.

## Repository Structure

```
.
├── music_culture_analysis.R     # Complete reproducible analysis pipeline
├── data/
│   ├── country_culture_gdp.xlsx # Merged analysis-ready data (73 countries)
│   ├── Final_Data_55_Countries.xlsx  # Nested sample: full 6 Hofstede dims
│   └── Final_Data_60_Countries.xlsx  # Nested sample: 4 classical dims + GDP
├── tables/                      # Tables 5-1 … 5-8 (Word, APA-style)
└── figures/                     # PCA, correlation, cluster figures (PDF)
```

## Reproducibility

**Requirements:** R ≥ 4.1 with packages `tidyverse`, `readxl`, `writexl`,
`FactoMineR`, `factoextra`, `corrplot`, `ggplot2`, `car`, `lmtest`, `Hmisc`,
`modelsummary`, `sandwich`, `flextable`, `officer`.

```r
# From the project folder (place 论文数据.xlsx next to the script, or run the
# script from anywhere above the data folder — the script auto-locates the
# workbook, preferring 论文数据.xlsx over the merged country_culture_gdp.xlsx)
source("music_culture_analysis.R")
```

The script runs end-to-end and writes all tables (.docx), figures (.pdf), and
intermediate data (.xlsx) to the working folder. It includes built-in audit
checks: data-file locator, region-grouping sanity check, model sample-size
verification (60/60/55/55), and a VIF cross-check against the dissertation.

## Data Sources & Licensing

- **Spotify audio features & weekly charts:** Spotify Weekly Top 200, Feb 2021 –
  Jul 2022 (Kaggle, Yelexa 2022), 73 countries. Only **aggregated** country-level
  output is shared here; raw row-level streaming data is not redistributed.
- **Cultural dimensions:** Hofstede et al. (2010), six-dimensional model.
- **Control variable:** GDP per capita 2021 (World Bank).

Aggregated data and code are shared for transparency and replication. If you
use this work, please cite the dissertation (see reference in the paper).

## Status

Part of the author's PhD application research portfolio; planned for journal
submission. Public release is intentional (open science: code and data precede
submission, preprint and journal peer review follow).
