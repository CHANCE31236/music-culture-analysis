# Global Music Aesthetics and Cultural Values: A Cross-Country Empirical Study

An empirical study linking **streaming-era music aesthetics** (Spotify audio
features) to **national cultural values** (Hofstede's six dimensions), using
streaming-volume weighted country-level aggregates, PCA, hierarchical
clustering, and nested regression designs.

This repository contains the R pipeline that generates every table and figure
reported in the dissertation *"Global Music Aesthetics and Cultural Values: An
Empirical Study Based on Cross-Country Streaming Data"*.

## Research design

| Step | Method | Output |
| --- | --- | --- |
| 1. Aggregation | Weekly Top-200 streams (18 months) weighted by country, main-artist rows only (`pivot == 0`), deduplicated by track URI | Country-level audio features × 73 countries |
| 2. EDA | Descriptive statistics, regional grouping, normality (Shapiro-Wilk), Pearson/Spearman correlation | Table 5-1, Appendix D1 |
| 3. Dimensionality reduction | PCA on 9 audio features (standardized); 3 components retained (eigenvalue > 1 / scree elbow) | Table 5-2, scree & loading plots |
| 4. Clustering | Hierarchical clustering on principal components (HCPC, 3 clusters) + ANOVA & Kruskal-Wallis on Hofstede dimensions | Table 5-3, cluster boxplots |
| 5. Nested regression | PC1–PC3 scores regressed on Hofstede dimensions, with and without log GDP per capita, on nested samples (60 vs 55 countries) | Tables 5-4 to 5-6 |
| 6. RQ3 incremental analysis | Nested F-tests: 55-country four-dimension baseline (PDI, IDV, MAS, UAI) vs six-dimension model (+ LTO, IVR), without GDP control | Table 6-1 |
| 7. Diagnostics | VIF (multicollinearity), White / studentized Breusch-Pagan test (heteroscedasticity), HC3 robust standard errors, sample-size audit | Tables 5-7, 5-8 |

## Key findings (direction of association; see the dissertation for full estimates)

- **PC1 "Energetic & Upbeat"** (high loadings: energy, valence, loudness,
  danceability; negative: acousticness) — negatively associated with
  **Uncertainty Avoidance (UAI)**; stable across sample tiers and GDP controls.
- **PC3 "Instrumental Purity"** (high loading: instrumentalness) — associated
  with **Individualism (IDV)** and **Long-Term Orientation (LTO)**.
- HCPC clusters differ significantly on **PDI, IDV, UAI, IVR** (ANOVA);
  Kruskal-Wallis confirms PDI/IDV/UAI (non-parametric robustness).
- All VIF values ≤ 2.30; mild heteroscedasticity in PC3 models addressed with
  HC3 robust standard errors.

## Repository structure

```
.
├── music_culture_analysis.R     # Complete reproducible analysis pipeline
├── data/
│   ├── country_culture_gdp.xlsx # Merged analysis-ready data (73 countries)
│   ├── Final_Data_55_Countries.xlsx  # Nested sample: full 6 Hofstede dims
│   └── Final_Data_60_Countries.xlsx  # Nested sample: 4 classical dims + GDP
├── tables/                      # Tables 5-1 … 5-8, 6-1 (Word, APA-style)
└── figures/                     # PCA, correlation, cluster figures (PDF)
```

## Reproducing the analysis

**Requirements:** R ≥ 4.1 with `tidyverse`, `readxl`, `writexl`, `FactoMineR`,
`factoextra`, `corrplot`, `ggplot2`, `car`, `lmtest`, `Hmisc`, `modelsummary`,
`sandwich`, `flextable`, `officer`.

```r
source("music_culture_analysis.R")
```

The script locates `data/country_culture_gdp.xlsx` relative to its own path, so
it can be sourced from anywhere. It runs end to end and writes all tables
(.docx), figures (.pdf), and intermediate data (.xlsx) to the working folder.

Built-in checks: data-file locator, region-grouping sanity check, model
sample-size verification (60/60/55/55), and a VIF cross-check against the
reported Table 5-7.

The script can also rebuild the country-level aggregates from raw song-level
data: place a `final.csv` (Kaggle Spotify Weekly Top 200 format) next to the
script and it will regenerate `country.xlsx` as an audit trail. That step is
optional — the committed country-level workbook is sufficient for everything
else.

## Data sources & licensing

- **Spotify audio features & weekly charts:** Spotify Weekly Top 200, Feb 2021 –
  Jul 2022 (Kaggle, Yelexa 2022), 73 countries. Only **aggregated** country-level
  output is shared here; raw row-level streaming data is not redistributed.
- **Cultural dimensions:** Hofstede et al. (2010), six-dimensional model.
- **Control variable:** GDP per capita 2021 (World Bank).

The code in this repository is MIT-licensed (see [LICENSE](LICENSE)). The
underlying data remains subject to the terms of its original sources; the
Hofstede dimensions and World Bank figures should be cited to their publishers.

If you use this work, please cite the dissertation (see the reference in the
paper).
