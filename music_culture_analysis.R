library(tidyverse)
library(writexl)
library(readxl)
# =============================================================================
# CHANGELOG / REVISION NOTES (2026-09-11, revised for journal submission)
# -----------------------------------------------------------------------------
# This version supersedes the code pasted in Appendix A of the dissertation:
#   - Appendix A exports VIF as a LONG table (Model | Variable | VIF), but the
#     dissertation's Table 5-7 is a WIDE table (Variable | PC1/PC2/PC3 VIF).
#     This file generates the wide table, matching the submitted Table 5-7.
#     => Before submission, REPLACE the Appendix A code with this file.
# Changes made in this revision (each marked "(2026-09)" in the code):
#   1. VIF rows are now driven by names(vif(...)) instead of a hard-coded label
#      vector, so row order can never drift from the actual model terms.
#   2. Removed the redundant distinct(uri, country) after group_by+summarise.
#   3. Added a pivot-column dictionary check: the code assumes pivot == 0 is the
#      MAIN artist row (Kaggle Spotify Weekly Top 200 dataset, Yelexa 2022; see
#      dissertation Sec. 4.3.1 "Deduplication"). The check prints the value
#      distribution so a wrong assumption cannot silently drop data.
#   4. The duplicated correlation PDF (file.copy under a second name) was
#      removed; the figure is now written once under its final appendix name.
#   5. Region grouping (Sec. 2.2) now warns about countries that fall into
#      "Other Regions" because of hard-coded name mismatches.
#   6. Heteroscedasticity test: bptest() is called with an EXPLICIT
#      studentize = white_studentize flag (default TRUE, which reproduces the
#      submitted Table 5-8 values, e.g. PC3_60_nogdp p = 0.0147). The classic
#      (non-studentized) White form is also computed and printed for comparison.
#      If you switch white_studentize to FALSE, every p-value in Table 5-8 /
#      Appendix D2 and the text (p = 0.0147 / 0.0312) MUST be re-run and
#      updated in the dissertation.
#   7. Model sample sizes are now verified against the dissertation
#      (60 / 60 / 55 / 55) after fitting; a warning is raised on mismatch.
#   8. The region grouping now also matches "Korea" (the Spotify-sheet
#      spelling) in addition to "South Korea" (the Hofstede-sheet spelling).
#      The first run exposed that Korea silently fell into "Other Regions",
#      which also means the dissertation Sec. 5.1.1 values for East & Southeast
#      Asia (energy 0.581, loudness -6.800) were computed WITHOUT Korea and
#      MUST be updated after re-running. The regional size printout now counts
#      countries per group instead of rows after aggregation.
#   9. The scree plot now uses a full-spectrum PCA fit (ncp = 9) so the
#      elbow / eigenvalue > 1 criterion (Sec. 4.3.3) can actually be inspected;
#      all downstream analysis still uses only the first three components.
#  10. VIF values are printed to the console for a quick cross-check against
#      dissertation Table 5-7 (expect 2.19 / 2.30 / 1.18 / 1.08 / 1.69 / 1.58 /
#      2.23 for PDI / IDV / MAS / UAI / LTO / IVR / log GDPpc).
# =============================================================================
# Resolve paths relative to this script so the analysis can be rerun from a
# portable project folder rather than a user-specific Desktop path.
get_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  script_arg <- grep(file_arg, cmd_args, value = TRUE)
  if (length(script_arg) > 0) {
    return(dirname(normalizePath(sub(file_arg, "", script_arg[1]))))
  }
  # (2026-09) When sourced interactively from RStudio, fall back to the active
  # document path so the script folder is found even without --file=. Pasting
  # into the console has no script path at all, so getwd() remains the fallback
  # (set the working directory to the data folder in that case).
  if (interactive() && requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable()) {
    doc_path <- tryCatch(rstudioapi::getSourceEditorContext()$path,
                         error = function(e) NULL)
    if (!is.null(doc_path) && nzchar(doc_path)) {
      return(dirname(normalizePath(doc_path)))
    }
  }
  normalizePath(getwd())
}
project_dir <- get_script_dir()
input_dir   <- project_dir
output_dir  <- project_dir

# (2026-09) Locate the paper data workbook robustly. Order of preference:
#   1) the script/working folder itself;
#   2) any subfolder of it (covers setups where the data lives in e.g.
#      Desktop\Project\Essay\论文附件\ while the script runs from Desktop);
#   3) the parent folder. If several copies exist, the newest is used.
locate_data_file <- function(project_dir) {
  direct <- c(file.path(project_dir, "论文数据.xlsx"),
              file.path(project_dir, "country_culture_gdp.xlsx"))
  hit <- direct[file.exists(direct)]
  if (length(hit) > 0) return(hit[1])
  recursive <- list.files(project_dir,
                          pattern = "^论文数据\\.xlsx$|^country_culture_gdp\\.xlsx$",
                          recursive = TRUE, full.names = TRUE)
  if (length(recursive) > 0) {
    info <- file.info(recursive)
    return(recursive[which.max(info$mtime)])
  }
  parent <- dirname(project_dir)
  if (file.exists(file.path(parent, "论文数据.xlsx"))) {
    return(file.path(parent, "论文数据.xlsx"))
  }
  NULL
}
located_data <- locate_data_file(input_dir)

# (2026-09) Startup check: if no data file is found, print where the script
# looked and how to fix it, so a wrong working directory is obvious instead of
# a generic "file not found" error several steps later.
if (is.null(located_data)) {
  cat("\n!!! Data file not found.\n")
  cat("!!! Current working directory :", getwd(), "\n")
  cat("!!! Searched in               :", input_dir, " (and its subfolders)\n")
  cat("!!! Fix (option 1): put 论文数据.xlsx anywhere under this folder and re-source.\n")
  cat("!!! Fix (option 2): in RStudio: Session > Set Working Directory > To Source File Location\n")
  cat("!!! Fix (option 3): run  setwd('path/to/folder-with-data')  before sourcing.\n")
} else {
  cat("Using data file:", located_data, "\n")
}
optional_song_level_path <- file.path(input_dir, "final.csv")
if (file.exists(optional_song_level_path)) {
  # Optional song-level rebuild. The dissertation's submitted analysis is based
  # on the supplied paper source workbook, 论文数据.xlsx, below. If final.csv is
  # present, this block regenerates country.xlsx as an additional audit trail.
  df <- read_csv(optional_song_level_path) %>%
    # Convert pivot to numeric to prevent read_csv from misidentifying it as
    # character and causing silent filtering failures
    mutate(pivot = as.numeric(pivot))

  # (2026-09) Data-dictionary check for the pivot column.
  # Assumption (must be verified against the dataset's own dictionary):
  #   pivot == 0  -> main artist record (kept)
  #   pivot == 1  -> additional/featured artist row of the same track URI
  #                  (dropped to avoid double counting collaborations)
  # See dissertation Sec. 4.3.1 "Deduplication" (split collaboration tracks).
  cat("\n[pivot dictionary check] unique values after as.numeric():",
      paste(unique(df$pivot), collapse = ", "), "\n")
  pivot_tab <- table(df$pivot, useNA = "ifany")
  print(pivot_tab)
  unexpected <- setdiff(names(pivot_tab), c("0", "1"))
  if (length(unexpected) > 0) {
    warning("pivot contains values other than 0/1: ",
            paste(unexpected, collapse = ", "),
            ". Verify the data dictionary before trusting filter(pivot == 0).")
  }

  # ==================== Step 1: Song-level Cleaning and Deduplication ====================
  song_level <- df %>%
    # Pre-filter abnormal streams, removing dirty data where streams is NA, 0, or negative
    filter(!is.na(streams) & streams > 0) %>%
    # Core filter: Keep only the main artist records to solve the duplicate
    # counting of collaborating artists
    filter(pivot == 0) %>%
    # 1. Group by country and unique song ID, summing up the streams for all weeks over the 18 months
    group_by(country, uri) %>%
    summarise(
      total_streams = sum(streams, na.rm = TRUE),
      # Audio features are constant for the same uri, taking the first one is sufficient
      danceability     = first(danceability),
      energy           = first(energy),
      loudness         = first(loudness),
      speechiness      = first(speechiness),
      acousticness     = first(acousticness),
      instrumentalness = first(instrumentalness),
      liveness         = first(liveness),
      valence          = first(valence),
      tempo            = first(tempo),
      .groups = "drop"
    )
  # (2026-09) Removed the redundant distinct(uri, country, .keep_all = TRUE):
  # the group_by(country, uri) + summarise above already guarantees exactly one
  # row per (country, uri), so the extra distinct had no effect.

  # ==================== Step 2: Country-level Weighted Aggregation of Streams ====================
  country_data <- song_level %>%
    group_by(country) %>%
    summarise(
      # Core: Weighted average of weekly streaming volume
      danceability     = weighted.mean(danceability, w = total_streams, na.rm = TRUE),
      energy           = weighted.mean(energy, w = total_streams, na.rm = TRUE),
      loudness         = weighted.mean(loudness, w = total_streams, na.rm = TRUE),
      speechiness      = weighted.mean(speechiness, w = total_streams, na.rm = TRUE),
      acousticness     = weighted.mean(acousticness, w = total_streams, na.rm = TRUE),
      instrumentalness = weighted.mean(instrumentalness, w = total_streams, na.rm = TRUE),
      liveness         = weighted.mean(liveness, w = total_streams, na.rm = TRUE),
      valence          = weighted.mean(valence, w = total_streams, na.rm = TRUE),
      tempo            = weighted.mean(tempo, w = total_streams, na.rm = TRUE),

      # Bring out country attributes
      country_streams  = sum(total_streams, na.rm = TRUE), # Total streams volume for the country
      n_songs          = n(),
      .groups = "drop"
    ) %>%
    # Filter out the global chart
    filter(country != "Global") %>%
    # Sort descending within country, then descending by streams
    arrange(country, desc(country_streams))
  # Preview the weighted aggregation results at the country level
  print(head(country_data, 10))
  # Export final results
  write_xlsx(country_data, file.path(output_dir, "country.xlsx"))
} else {
  message(
    "Optional song-level final.csv was not found; ",
    "continuing with the supplied paper data workbook."
  )
}
# ==============================================================================
# Empirical Study on the Correlation between Global Music Aesthetics and Cultural Values
# ==============================================================================
library(FactoMineR)
library(corrplot)
library(tidyverse)
library(readxl)
library(writexl)
library(factoextra)
library(ggplot2)
library(car)
library(lmtest)
library(Hmisc)
library(modelsummary)
library(sandwich)
library(flextable)
library(officer)
# Set working directory for all exported tables and figures
setwd(output_dir)
# ==============================================================================
# 1. Data Preparation and Preprocessing
# ==============================================================================
# 1.1 Define variable groups
audio_vars     <- c("danceability", "energy", "loudness", "speechiness",
                    "acousticness", "instrumentalness", "liveness", "valence", "tempo")
culture_vars   <- c("pdi", "idv", "mas", "uai", "lto", "ivr")
culture_vars_4 <- c("pdi", "idv", "mas", "uai")
control_vars   <- c("2021GDPPC")
# 1.2 Import and merge data from the paper source workbook
# Uses the locator defined at the top of the script (located_data).
paper_data_path <- located_data
if (!is.null(paper_data_path) && basename(paper_data_path) == "论文数据.xlsx") {
  spotify_sheet <- read_excel(paper_data_path, sheet = "Spotify") %>%
    select(country, all_of(audio_vars), country_streams, n_songs) %>%
    rename(`country or region` = country)

  hofstede_sheet <- read_excel(paper_data_path, sheet = "Hofstede") %>%
    select(country, all_of(culture_vars)) %>%
    rename(`country or region` = country)

  gdp_sheet <- read_excel(paper_data_path, sheet = "DGPPC") %>%
    select(`Country Name`, `2021`) %>%
    rename(`country or region` = `Country Name`,
           `2021GDPPC` = `2021`)

  df <- spotify_sheet %>%
    left_join(hofstede_sheet, by = "country or region") %>%
    left_join(gdp_sheet, by = "country or region")

  # Export the merged analysis-ready dataset for transparent reproducibility.
  write_xlsx(df, file.path(output_dir, "country_culture_gdp.xlsx"))
} else if (!is.null(paper_data_path) && basename(paper_data_path) == "country_culture_gdp.xlsx") {
  df <- read_excel(paper_data_path)
} else {
  stop("Neither 论文数据.xlsx nor country_culture_gdp.xlsx was found (searched: ",
       input_dir, " and its subfolders).")
}
# 1.3 Data cleaning and filtering (construct 73-country analysis sample)
data_clean <- df %>%
  column_to_rownames(var = "country or region") %>%
  select(all_of(c(audio_vars, culture_vars, control_vars))) %>%
  filter(if_all(all_of(audio_vars), ~ !is.na(.)) & !is.na(`2021GDPPC`))
# 1.4 Define unified plotting style
plot_style <- list(
  method = "color", type = "upper", diag = FALSE, tl.col = "black",
  tl.cex = 0.85, tl.srt = 45, addCoef.col = "black", number.cex = 0.65,
  number.digits = 2, addgrid.col = "grey80", mar = c(0, 0, 2, 1),
  col = colorRampPalette(c("#053061", "white", "#67001F"))(200)
)
# 1.5 General function: add significance stars
add_stars <- function(coef, p_val) {
  sig <- case_when(
    p_val < 0.001 ~ "***",
    p_val < 0.01  ~ "**",
    p_val < 0.05  ~ "*",
    TRUE          ~ ""
  )
  ifelse(is.na(coef), "NA", paste0(sprintf("%.3f", coef), sig))
}
# 1.6 General function: export APA three-line table
export_apa_table <- function(data_df, table_title, file_name, note_text = NULL,
                             col_widths = NULL, font_size = 10) {
  ft <- flextable(data_df) %>%
    set_caption(table_title) %>%
    theme_booktabs() %>%
    fontsize(size = font_size, part = "all") %>%
    padding(padding = 2, part = "all") %>%
    align(align = "center", part = "all") %>%
    align(align = "left", j = 1, part = "all") %>%
    set_table_properties(layout = "fixed")

  if (!is.null(col_widths)) {
    for (j in seq_along(col_widths)) {
      ft <- width(ft, j = j, width = col_widths[j])
    }
  } else {
    ft <- autofit(ft)
  }

  if (!is.null(note_text)) {
    ft <- add_footer_lines(ft, note_text)
  }

  save_as_docx(ft, path = file_name)
}
# ==============================================================================
# 2. Exploratory Data Analysis (EDA)
# ==============================================================================
audio_data <- data_clean %>% select(all_of(audio_vars))
# 2.1 Descriptive Statistics of Audio Features + Export Table 5-1
cat("\n=== 2.1 Descriptive Statistics of Audio Features ===\n")
desc_stats <- audio_data %>%
  summarise(across(everything(),
                   list(Mean = ~mean(.x, na.rm = TRUE),
                        StdDev = ~sd(.x, na.rm = TRUE),
                        Minimum = ~min(.x, na.rm = TRUE),
                        Maximum = ~max(.x, na.rm = TRUE)))) %>%
  pivot_longer(everything(),
               names_to = c("Audio Feature", ".value"),
               names_sep = "_") %>%
  mutate(
    across(where(is.numeric), ~ round(.x, 3)),
    `Audio Feature` = case_when(
      `Audio Feature` == "danceability"     ~ "Danceability",
      `Audio Feature` == "energy"           ~ "Energy",
      `Audio Feature` == "loudness"         ~ "Loudness",
      `Audio Feature` == "speechiness"      ~ "Speechiness",
      `Audio Feature` == "acousticness"     ~ "Acousticness",
      `Audio Feature` == "instrumentalness" ~ "Instrumentalness",
      `Audio Feature` == "liveness"         ~ "Liveness",
      `Audio Feature` == "valence"          ~ "Valence",
      `Audio Feature` == "tempo"            ~ "Tempo",
      TRUE ~ `Audio Feature`
    )
  ) %>%
  rename(`Std. Dev` = StdDev)
print(desc_stats, row.names = FALSE)
# Export Table 5-1 (strictly match paper title)
export_apa_table(
  data_df = desc_stats,
  table_title = "Table 5-1 Descriptive Statistics of Audio Features for the Full Sample of 73 Countries",
  file_name = "Table_5-1_Descriptive_Statistics.docx"
)
cat("\n=== Table 5-1 exported to Word ===\n")
# 2.2 Regional Descriptive Statistics of Audio Features
cat("\n=== 2.2 Regional Descriptive Statistics of Audio Features ===\n")
region_flagged <- data_clean %>%
  # Restore the country name column to match the original dataset's column name
  rownames_to_column(var = "country or region") %>%
  select(`country or region`, all_of(audio_vars)) %>%
  # Custom grouping to strictly align with the four regions described in the text
  mutate(cultural_group = case_when(
    # Latin America
    `country or region` %in% c("Argentina", "Bolivia", "Brazil", "Chile", "Colombia", "Costa Rica",
                               "Dominican Republic", "Ecuador", "El Salvador", "Guatemala", "Honduras",
                               "Mexico", "Nicaragua", "Panama", "Paraguay", "Peru", "Uruguay", "Venezuela") ~ "Latin America",
    # East & Southeast Asia
    # (2026-09) "Korea" is the Spotify-sheet spelling; "South Korea" is the
    # Hofstede-sheet spelling. Both must match, otherwise Korea silently falls
    # into "Other Regions" (confirmed by the region check on the submitted data).
    `country or region` %in% c("Hong Kong", "Indonesia", "Japan", "Malaysia", "Philippines",
                               "Singapore", "Korea", "South Korea", "Taiwan", "Thailand", "Vietnam") ~ "East & Southeast Asia",
    # English-speaking countries
    `country or region` %in% c("Australia", "Canada", "Ireland", "New Zealand",
                               "United Kingdom", "United States") ~ "English-speaking",
    # Eastern Europe
    `country or region` %in% c("Belarus", "Bulgaria", "Czech Republic", "Estonia", "Hungary",
                               "Latvia", "Lithuania", "Poland", "Romania", "Russia", "Slovakia", "Ukraine") ~ "Eastern Europe",
    TRUE ~ "Other Regions"
  ))

# (2026-09) Region sanity check: any country that falls into "Other Regions"
# because its name does not match the hard-coded lists above would silently
# disappear from the four named groups. Surface it now.
unassigned <- region_flagged %>%
  filter(cultural_group == "Other Regions") %>%
  pull(`country or region`)
if (length(unassigned) > 0) {
  cat("[region check] WARNING - countries NOT matched by the hard-coded group lists:\n")
  print(unassigned)
} else {
  cat("[region check] OK - all countries matched to a named region group.\n")
}

region_desc <- region_flagged %>%
  # Calculate the mean of each audio feature by group, rounded to 3 decimal places
  group_by(cultural_group) %>%
  summarise(across(all_of(audio_vars), ~ mean(.x, na.rm = TRUE), .names = "{.col}")) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)))
cat("\n--- Regional group size verification (countries per group) ---\n")
print(table(region_flagged$cultural_group))
cat("\n--- Regional mean audio features ---\n")
print(region_desc, row.names = FALSE)
# 2.3 Normality test for audio features (Shapiro-Wilk)
cat("\n=== 2.3 Normality Test for Audio Features ===\n")
audio_normality <- sapply(audio_data, function(x) shapiro.test(x)$p.value)
normality_df <- data.frame(
  `Audio Feature` = names(audio_normality),
  `P Value` = round(audio_normality, 4),
  check.names = FALSE
)
print(normality_df, row.names = FALSE)
# 2.4 Correlation analysis (Pearson vs Spearman)
res.cor_audio_pearson  <- cor(audio_data, method = "pearson")
res.cor_audio_spearman <- cor(audio_data, method = "spearman")
# (2026-09) Figure is written once under its final appendix name; the old
# file.copy(..., "1_Audio_Features_Correlation_Spearman_Appendix.pdf") that
# duplicated the same PDF under a second name has been removed.
pdf("1_Audio_Features_Correlation_Spearman_Appendix.pdf", width = 10, height = 10)
do.call(corrplot, c(list(res.cor_audio_spearman, title = "Audio Features Correlation (Spearman)"), plot_style))
dev.off()
# ==============================================================================
# 3. Principal Component Analysis (PCA)
# ==============================================================================
# 3.1 Perform PCA dimensionality reduction
pca_data <- data_clean %>% select(all_of(audio_vars))
res.pca  <- PCA(pca_data, scale.unit = TRUE, ncp = 3, graph = FALSE)
# 3.2 Plot visualization charts
# (2026-09) Refit with the full eigenvalue spectrum (ncp = 9) ONLY for the
# scree plot: with ncp = 3 the plot would show just three points and could not
# support the elbow / eigenvalue > 1 criterion described in Sec. 4.3.3. All
# downstream analysis keeps res.pca (ncp = 3), so nothing else changes.
res.pca_all <- PCA(pca_data, scale.unit = TRUE, ncp = 9, graph = FALSE)
pdf("PCA_ScreePlot.pdf", width = 10, height = 8)
fviz_eig(res.pca_all, addlabels = TRUE, title = "Scree Plot")
dev.off()
pdf("PCA_Variable_Map.pdf", width = 10, height = 8)
fviz_pca_var(res.pca, col.var = "contrib", repel = TRUE, title = "PCA Contribution", gradient.cols = c("#053061", "#E7B800", "#67001F"))
dev.off()
pdf("PCA_Country_Map.pdf", width = 12, height = 10)
fviz_pca_ind(res.pca, repel = TRUE, geom = "text", col.ind = "cos2", gradient.cols = c("#053061","#E7B800","#67001F"), title = "Global Music Preference Map")
dev.off()
# 3.3 Output principal component dimension interpretation
pca_desc_sig <- dimdesc(res.pca, axes = c(1,2,3), proba = 0.05)
print(pca_desc_sig$Dim.1$quanti); print(pca_desc_sig$Dim.2$quanti); print(pca_desc_sig$Dim.3$quanti)
# 3.4 Export Table 5-2 Factor Loading Matrix (complete PCA loading matrix)
# The paper reports the full PCA loading matrix, not only significant
# dimdesc results. P-values are retained only to add significance stars.
pca_desc_all <- dimdesc(res.pca, axes = c(1,2,3), proba = 1)
extract_dim_p <- function(dim_name, p_name) {
  as.data.frame(pca_desc_all[[dim_name]]$quanti) %>%
    rownames_to_column("Audio Feature") %>%
    select(`Audio Feature`, p.value) %>%
    rename(!!p_name := p.value)
}
loading_order <- c("energy", "valence", "loudness", "danceability", "speechiness",
                   "liveness", "tempo", "acousticness", "instrumentalness")
loading_table <- as.data.frame(res.pca$var$coord[, 1:3]) %>%
  rownames_to_column("Audio Feature") %>%
  rename(PC1 = Dim.1, PC2 = Dim.2, PC3 = Dim.3) %>%
  left_join(extract_dim_p("Dim.1", "p1"), by = "Audio Feature") %>%
  left_join(extract_dim_p("Dim.2", "p2"), by = "Audio Feature") %>%
  left_join(extract_dim_p("Dim.3", "p3"), by = "Audio Feature") %>%
  mutate(
    `Audio Feature` = factor(`Audio Feature`, levels = loading_order),
    PC1 = add_stars(PC1, p1),
    PC2 = add_stars(PC2, p2),
    PC3 = add_stars(PC3, p3)
  ) %>%
  arrange(`Audio Feature`) %>%
  mutate(
    `Audio Feature` = case_when(
      as.character(`Audio Feature`) == "danceability"     ~ "Danceability",
      as.character(`Audio Feature`) == "energy"           ~ "Energy",
      as.character(`Audio Feature`) == "loudness"         ~ "Loudness",
      as.character(`Audio Feature`) == "speechiness"      ~ "Speechiness",
      as.character(`Audio Feature`) == "acousticness"     ~ "Acousticness",
      as.character(`Audio Feature`) == "instrumentalness" ~ "Instrumentalness",
      as.character(`Audio Feature`) == "liveness"         ~ "Liveness",
      as.character(`Audio Feature`) == "valence"          ~ "Valence",
      as.character(`Audio Feature`) == "tempo"            ~ "Tempo",
      TRUE ~ as.character(`Audio Feature`)
    )
  ) %>%
  select(`Audio Feature`, PC1, PC2, PC3)
# 4. Export Table 5-2
export_apa_table(
  data_df = loading_table,
  table_title = "Table 5-2 Factor Loading Matrix of Principal Components",
  file_name = "Table_5-2_Factor_Loading_Matrix.docx",
  note_text = "Note: * p<0.05, ** p<0.01, *** p<0.001; ns = not significant",
  col_widths = c(1.55, 1.00, 1.00, 1.00),
  font_size = 10
)
cat("\n=== Table 5-2 exported to Word successfully ===\n")
# ==============================================================================
# 4. Data Export and Nested Sample Preparation
# ==============================================================================
# 4.1 Merge principal component scores
final_base <- data_clean %>%
  rownames_to_column("country or region") %>%
  left_join(res.pca$ind$coord %>% as.data.frame() %>% rownames_to_column("country or region"), by = "country or region") %>%
  rename(PC1_Score = Dim.1, PC2_Score = Dim.2, PC3_Score = Dim.3)
# 4.2 Export nested sample sets (55 and 60 countries)
# (2026-09) Sample composition per dissertation Sec. 4.1.2:
#   60 = 55 (full six dimensions) + 4 (Ecuador, Guatemala, Costa Rica, Panama,
#        four classical dimensions only) + Israel (LTO missing, four dims OK)
#   55 = countries with complete data on all six Hofstede dimensions
export_55_data <- final_base %>% filter(complete.cases(select(., all_of(culture_vars))))
export_60_data <- final_base %>% filter(complete.cases(select(., all_of(culture_vars_4))))
write_xlsx(export_55_data, "Final_Data_55_Countries.xlsx")
write_xlsx(export_60_data, "Final_Data_60_Countries.xlsx")
# ==============================================================================
# 5. Correlation Analysis: Principal Components and Cultural Dimensions
# ==============================================================================
pearson_data <- export_55_data %>% mutate(log_GDP = log(`2021GDPPC`)) %>%
  select(PC1_Score, PC2_Score, PC3_Score, pdi, idv, mas, uai, lto, ivr, log_GDP)
# 5.1 Pearson correlation analysis and plotting
pearson_result <- rcorr(as.matrix(pearson_data), type = "pearson")
pdf("5_Pearson_Correlation_Main.pdf", width = 12, height = 10)
do.call(corrplot, c(list(pearson_result$r, title = "Pearson Correlation"), plot_style))
dev.off()
# 5.2 Spearman correlation analysis and plotting
spearman_result <- rcorr(as.matrix(pearson_data), type = "spearman")
pdf("5_Spearman_Correlation_Appendix.pdf", width = 12, height = 10)
do.call(corrplot, c(list(spearman_result$r, title = "Spearman Correlation"), plot_style))
dev.off()
# ==============================================================================
# 6. Cluster Analysis (HCPC) and Difference Testing
# ==============================================================================
# 6.1 Perform clustering (set seed to ensure reproducibility)
set.seed(123)
res.hcpc <- HCPC(res.pca, nb.clust = 3, kk = Inf, graph = FALSE)
country_clusters <- res.hcpc$data.clust %>% select(clust) %>% rownames_to_column("country or region")
cluster_with_culture <- final_base %>% inner_join(country_clusters, by = "country or region")
cluster_complete_culture <- cluster_with_culture %>%
  filter(complete.cases(select(., all_of(culture_vars))))
# 6.2 Difference testing
# 6.2.1 ANOVA inter-group difference test
aov_result <- aov(cbind(pdi, idv, mas, uai, lto, ivr) ~ clust, data = cluster_complete_culture)
print(summary(aov_result))
# 6.2.2 Organize ANOVA results and export Table 5-3
# Extract ANOVA statistics for each dimension
anova_summary <- summary(aov_result)
anova_table <- data.frame(
  `Cultural Dimension` = c("Power Distance (PDI)", "Individualism (IDV)", "Masculinity (MAS)",
                           "Uncertainty Avoidance (UAI)", "Long-Term Orientation (LTO)", "Indulgence (IVR)"),
  `df Between` = sapply(anova_summary, function(x) x$Df[1]),
  `df Within` = sapply(anova_summary, function(x) x$Df[2]),
  `F-statistic` = round(sapply(anova_summary, function(x) x$`F value`[1]), 2),
  `p-value` = round(sapply(anova_summary, function(x) x$`Pr(>F)`[1]), 4),
  check.names = FALSE
)
# Add significance marks
anova_table <- anova_table %>%
  mutate(Significance = case_when(
    `p-value` < 0.001 ~ "***",
    `p-value` < 0.01  ~ "**",
    `p-value` < 0.05  ~ "*",
    TRUE              ~ "ns"
  ))
# Export Table 5-3
export_apa_table(
  data_df = anova_table,
  table_title = "Table 5-3 ANOVA Results for Cultural Dimension Differences Across Clusters",
  file_name = "Table_5-3_ANOVA_Cluster_Differences.docx",
  note_text = "Note: * p<0.05, ** p<0.01, *** p<0.001; ns = not significant"
)
cat("\n=== Table 5-3 exported to Word ===\n")
# 6.2.3 Kruskal-Wallis robustness test (non-parametric)
cat("\n=== [Robustness Test] Kruskal-Wallis Test ===\n")
kw_results <- lapply(culture_vars, function(var) kruskal.test(as.formula(paste(var, "~ clust")), data = cluster_complete_culture))
print(sapply(kw_results, function(x) x$p.value))
# 6.3 Plot "Boxplot of Cultural Differences Between Clusters"
pdf("Cluster_Culture_Differences_Boxplot.pdf", width = 12, height = 8)
# Convert wide data to long data for easier ggplot plotting
plot_data <- cluster_with_culture %>%
  filter(complete.cases(select(., all_of(culture_vars)))) %>%
  select(clust, all_of(culture_vars)) %>%
  pivot_longer(cols = -clust, names_to = "Dimension", values_to = "Score")
ggplot(plot_data, aes(x = factor(clust), y = Score, fill = factor(clust))) +
  geom_boxplot(alpha = 0.7) +
  facet_wrap(~ Dimension, scales = "free_y") +
  theme_minimal() +
  labs(title = "Cultural Dimension Distribution by Cluster",
       x = "Cluster ID", y = "Score") +
  scale_fill_brewer(palette = "Set1")
dev.off()
# ==============================================================================
# 7. Multiple Linear Regression Analysis
# ==============================================================================
# 7.1 Build regression models (loop fitting PC1/PC2/PC3)
models <- list()
for(pc in c("PC1_Score", "PC2_Score", "PC3_Score")) {
  models[[paste0(pc, "_60_nogdp")]] <- lm(as.formula(paste(pc, "~ pdi + idv + mas + uai")), data = export_60_data)
  models[[paste0(pc, "_60_gdp")]]   <- lm(as.formula(paste(pc, "~ pdi + idv + mas + uai + log(`2021GDPPC`)")), data = export_60_data)
  models[[paste0(pc, "_55_nogdp")]] <- lm(as.formula(paste(pc, "~ pdi + idv + mas + uai + lto + ivr")), data = export_55_data)
  models[[paste0(pc, "_55_gdp")]]   <- lm(as.formula(paste(pc, "~ pdi + idv + mas + uai + lto + ivr + log(`2021GDPPC`)")), data = export_55_data)
}
# 7.2 Define unified regression table export function
# Custom goodness-of-fit metrics
gof_custom <- tribble(
  ~raw, ~clean, ~fmt,
  "nobs", "Observations", 0,
  "r.squared", "R²", 3,
  "adj.r.squared", "Adjusted R²", 3,
  "aic", "AIC", 1,
  "bic", "BIC", 1,
  "fstatistic", "F-statistic", 3,
  "rmse", "RMSE", 2
)
# Custom significance star rules (match paper notes)
stars_custom <- c("†" = 0.1, "*" = 0.05, "**" = 0.01, "***" = 0.001)
# Unified regression export function
export_reg_table <- function(model_list, table_title, file_name, col_names) {
  ft <- modelsummary(
    model_list,
    vcov = "HC3",
    output = "flextable",
    stars = stars_custom,
    gof_map = gof_custom,
    coef_rename = c(
      "(Intercept)" = "(Intercept)",
      "pdi" = "PDI",
      "idv" = "IDV",
      "mas" = "MAS",
      "uai" = "UAI",
      "lto" = "LTO",
      "ivr" = "IVR",
      "log(`2021GDPPC`)" = "log GDPpc",
      "log(2021GDPPC)" = "log GDPpc"
    ),
    estimate = "{estimate}{stars}",
    statistic = "({std.error})"
  ) %>%
    set_caption(table_title) %>%
    add_footer_lines("Note: Robust standard errors in parentheses; † p<0.1, * p<0.05, ** p<0.01, *** p<0.001") %>%
    theme_booktabs() %>%
    fontsize(size = 9.5, part = "all") %>%
    padding(padding = 1, part = "all") %>%
    width(j = 1, width = 1.15) %>%
    width(j = 2:5, width = 0.92) %>%
    set_table_properties(layout = "fixed") %>%
    align(align = "center", part = "all") %>%
    align(align = "left", j = 1, part = "all")

  # Rename model columns to match paper style
  for (i in seq_along(col_names)) {
    ft <- compose(ft, i = 1, j = i+1, value = as_paragraph(col_names[i]), part = "header")
  }

  save_as_docx(ft, path = file_name)
}
# 7.3 Export regression tables in paper order
# Table 5-4 PC1
export_reg_table(
  model_list = models[1:4],
  table_title = "Table 5-4 Nested Regression Results for PC1 (Energetic and Upbeat Aesthetic Factor)",
  file_name = "Table_5-4_PC1_Regression.docx",
  col_names = c("Model 1\n(60, no GDP)", "Model 2\n(60, GDP)",
                "Model 3\n(55, no GDP)", "Model 4\n(55, GDP)")
)
cat("\n=== Table 5-4 exported to Word ===\n")
# Table 5-5 PC2
export_reg_table(
  model_list = models[5:8],
  table_title = "Table 5-5 Nested Regression Results for PC2 (Rhythmic-Live vs. Vocal-Studio Differentiation Factor)",
  file_name = "Table_5-5_PC2_Regression.docx",
  col_names = c("Model 1\n(60, no GDP)", "Model 2\n(60, GDP)",
                "Model 3\n(55, no GDP)", "Model 4\n(55, GDP)")
)
cat("\n=== Table 5-5 exported to Word ===\n")
# Table 5-6 PC3
export_reg_table(
  model_list = models[9:12],
  table_title = "Table 5-6 Nested Regression Results for PC3 (Instrumental Purity Aesthetic Factor)",
  file_name = "Table_5-6_PC3_Regression.docx",
  col_names = c("Model 1\n(60, no GDP)", "Model 2\n(60, GDP)",
                "Model 3\n(55, no GDP)", "Model 4\n(55, GDP)")
)
cat("\n=== Table 5-6 exported to Word ===\n")
cat("\n=== All core regression tables exported in paper order ===\n")
# 7.4 Sample-size verification (2026-09)
# The dissertation reports Observations 60 | 60 | 55 | 55 for every PC table.
# lm() silently drops rows with any missing predictor, so verify the effective
# sample size actually used by each model and warn if it has drifted.
cat("\n=== Model effective sample sizes (expected: 60/60/55/55) ===\n")
nobs_check <- sapply(models, function(m) nobs(m))
print(nobs_check)
expected_nobs <- c("PC1_Score_60_nogdp" = 60, "PC1_Score_60_gdp" = 60,
                   "PC1_Score_55_nogdp" = 55, "PC1_Score_55_gdp" = 55)
if (any(nobs_check[c("PC1_Score_60_nogdp", "PC1_Score_60_gdp")] != 60) ||
    any(nobs_check[c("PC1_Score_55_nogdp", "PC1_Score_55_gdp")] != 55)) {
  warning("Effective sample size differs from the dissertation's 60/60/55/55. ",
          "Check for missing values in GDP or the cultural dimensions before submitting.")
} else {
  cat("[nobs check] OK - all models match the dissertation sample sizes (60/60/55/55).\n")
}
# ==============================================================================
# 8. Diagnostics and Robustness Testing
# ==============================================================================
# 8.1 VIF test summary table (export Table 5-7)
# The dissertation reports the concise six-dimension + GDP model summary for
# PC1, PC2, and PC3. The same predictor set is used across the three dependent
# variables, so the VIF values should be identical across columns.
vif_model_keys <- c(
  PC1 = "PC1_Score_55_gdp",
  PC2 = "PC2_Score_55_gdp",
  PC3 = "PC3_Score_55_gdp"
)
extract_vif <- function(model_key) {
  v <- vif(models[[model_key]])
  if (is.matrix(v)) v <- v[, 1]
  round(as.numeric(v), 2)
}
vif_values <- lapply(vif_model_keys, extract_vif)
# (2026-09) Row labels and order are DRIVEN by names(vif(...)) so they can never
# drift from the actual model terms if the specification changes. Unknown terms
# fall back to their raw term label with a warning instead of silently shifting.
vif_terms <- names(vif(models[[vif_model_keys[[1]]]]))
vif_label_map <- c(
  "pdi"                 = "Power Distance (PDI)",
  "idv"                 = "Individualism (IDV)",
  "mas"                 = "Masculinity (MAS)",
  "uai"                 = "Uncertainty Avoidance (UAI)",
  "lto"                 = "Long-Term Orientation (LTO)",
  "ivr"                 = "Indulgence (IVR)",
  "log(`2021GDPPC`)"    = "log GDPpc",
  "log(2021GDPPC)"      = "log GDPpc"
)
vif_labels <- unname(vif_label_map[vif_terms])
if (anyNA(vif_labels)) {
  warning("Unmapped VIF term(s) - check the model specification: ",
          paste(vif_terms[is.na(vif_labels)], collapse = ", "))
  vif_labels[is.na(vif_labels)] <- vif_terms[is.na(vif_labels)]
}
if (length(vif_labels) != 7) {
  warning("Expected 7 VIF rows (6 dimensions + log GDPpc), got ",
          length(vif_labels), ".")
}
vif_df <- data.frame(
  Variable = vif_labels,
  `PC1 VIF` = vif_values$PC1,
  `PC2 VIF` = vif_values$PC2,
  `PC3 VIF` = vif_values$PC3,
  check.names = FALSE
)
print(vif_df)  # (2026-09) printed for quick comparison with dissertation Table 5-7
# Export Table 5-7
export_apa_table(
  data_df = vif_df,
  table_title = "Table 5-7 Variance Inflation Factor Summary for Regression Predictors",
  file_name = "Table_5-7_VIF_Diagnostics.docx",
  note_text = "Note: VIF values are reported for the six-dimension models with GDP control. All values are below the conventional threshold of 10, indicating no severe multicollinearity."
)
cat("\n=== Table 5-7 exported to Word ===\n")
# 8.2 Heteroscedasticity test summary (export Table 5-8)
# (2026-09) Explicit form flag. The dissertation's Table 5-8 reports the
# STUDENTIZED form (lmtest::bptest default; model names carry the ".BP"
# suffix, e.g. PC3_Score_60_nogdp p = 0.0147). Keep white_studentize = TRUE to
# reproduce those values. The classic (non-studentized) White test is computed
# and printed alongside so the two forms can be compared. If you switch this
# flag to FALSE, re-run EVERYTHING and update Table 5-8, Appendix D2 and the
# p-values quoted in the text (Sec. 5.5.3).
white_studentize <- TRUE
white_tests <- sapply(models, function(m) {
  bptest(m, ~ fitted(m) + I(fitted(m)^2), studentize = white_studentize)$p.value
})
white_classic <- sapply(models, function(m) {
  bptest(m, ~ fitted(m) + I(fitted(m)^2), studentize = FALSE)$p.value
})
cat("\n[White test] studentized (reported in dissertation) vs classic form:\n")
print(data.frame(Model = names(white_tests),
                 Studentized_BP = round(white_tests, 4),
                 Classic_White = round(white_classic, 4),
                 row.names = NULL))
white_df <- data.frame(
  Model = names(white_tests),
  `P Value` = round(white_tests, 4),
  check.names = FALSE
)
export_apa_table(
  data_df = white_df,
  table_title = "Table 5-8 White Test for Heteroscedasticity",
  file_name = "Table_5-8_White_Test_Results.docx"
)
cat("\n=== All diagnostic tables exported to Word ===\n")
cat("\n=== All tables generated in strict paper order with unified APA format ===\n")


# ==============================================================================

# ==============================================================================
# 9. RQ3 Incremental Explanatory Power: 55-Country Four-Dimension Baseline vs
#    Six-Dimension Models (added 2026-09 for dissertation Sec. 6.3.2 / Table 6-1)
# ==============================================================================
# The submitted dissertation states (Sec. 6.3.2) that "supplementary
# hierarchical comparisons were considered within the same 55-country baseline
# tracking environment" but did not include the 55-country four-dimension
# baseline tables. This block produces the baseline models, the nested F-tests
# and Table 6-1, so every number quoted in Sec. 6.3.2 is directly reproducible.

rq3_models <- list()
for (pc in c("PC1_Score", "PC2_Score", "PC3_Score")) {
  rq3_models[[paste0(pc, "_55_4dim_nogdp")]] <- lm(as.formula(paste(pc, "~ pdi + idv + mas + uai")), data = export_55_data)
  rq3_models[[paste0(pc, "_55_4dim_gdp")]]   <- lm(as.formula(paste(pc, "~ pdi + idv + mas + uai + log(`2021GDPPC`)")), data = export_55_data)
}

cat("\n=== [RQ3] 55-country incremental comparison (4-dim baseline vs 6-dim, no GDP) ===\n")
rq3_f <- list()
for (pc in c("PC1_Score", "PC2_Score", "PC3_Score")) {
  m4d <- rq3_models[[paste0(pc, "_55_4dim_nogdp")]]
  m6d <- models[[paste0(pc, "_55_nogdp")]]
  ft  <- anova(m4d, m6d)
  rq3_f[[pc]] <- c(F = ft$F[2], p = ft$"Pr(>F)"[2], dR2 = summary(m6d)$r.squared - summary(m4d)$r.squared,
                   dadjR2 = summary(m6d)$adj.r.squared - summary(m4d)$adj.r.squared)
  cat("\n", pc, "\n")
  cat("  baseline 4-dim: R2=", summary(m4d)$r.squared,
      " adjR2=", summary(m4d)$adj.r.squared,
      " AIC=", AIC(m4d), " BIC=", BIC(m4d), " RMSE=", sqrt(mean(resid(m4d)^2)), "\n")
  cat("  full 6-dim:     R2=", summary(m6d)$r.squared,
      " adjR2=", summary(m6d)$adj.r.squared,
      " AIC=", AIC(m6d), " BIC=", BIC(m6d), " RMSE=", sqrt(mean(resid(m6d)^2)), "\n")
  cat("  delta R2=", summary(m6d)$r.squared - summary(m4d)$r.squared,
      " delta adjR2=", summary(m6d)$adj.r.squared - summary(m4d)$adj.r.squared,
      " F(2, 48)=", ft$F[2], " p=", ft$"Pr(>F)"[2], "\n")
}

cat("\n=== [RQ3] 55-country incremental comparison (4-dim+GDP vs 6-dim+GDP) ===\n")
for (pc in c("PC1_Score", "PC2_Score", "PC3_Score")) {
  m4d <- rq3_models[[paste0(pc, "_55_4dim_gdp")]]
  m6d <- models[[paste0(pc, "_55_gdp")]]
  ft  <- anova(m4d, m6d)
  cat("\n", pc, "\n")
  cat("  baseline 4-dim+GDP: R2=", summary(m4d)$r.squared,
      " adjR2=", summary(m4d)$adj.r.squared,
      " AIC=", AIC(m4d), " BIC=", BIC(m4d), " RMSE=", sqrt(mean(resid(m4d)^2)), "\n")
  cat("  full 6-dim+GDP:     R2=", summary(m6d)$r.squared,
      " adjR2=", summary(m6d)$adj.r.squared,
      " AIC=", AIC(m6d), " BIC=", BIC(m6d), " RMSE=", sqrt(mean(resid(m6d)^2)), "\n")
  cat("  delta R2=", summary(m6d)$r.squared - summary(m4d)$r.squared,
      " delta adjR2=", summary(m6d)$adj.r.squared - summary(m4d)$adj.r.squared,
      " F(2, 48)=", ft$F[2], " p=", ft$"Pr(>F)"[2], "\n")
}

# Export Table 6-1 (no-GDP comparison, matching the six-dimension columns of
# Tables C1-C3). Star coding follows the nested F-test p-value.
t61 <- data.frame(
  `Aesthetic Factor` = c("PC1 (Energetic and Upbeat)", "PC2 (Rhythmic-Live vs. Vocal-Studio)", "PC3 (Instrumental Purity)"),
  `R² (4-dim)`   = round(sapply(c("PC1_Score","PC2_Score","PC3_Score"), function(pc) summary(rq3_models[[paste0(pc,"_55_4dim_nogdp")]])$r.squared), 3),
  `R² (6-dim)`   = round(sapply(c("PC1_Score","PC2_Score","PC3_Score"), function(pc) summary(models[[paste0(pc,"_55_nogdp")]])$r.squared), 3),
  `Adj. R² (4-dim)` = round(sapply(c("PC1_Score","PC2_Score","PC3_Score"), function(pc) summary(rq3_models[[paste0(pc,"_55_4dim_nogdp")]])$adj.r.squared), 3),
  `Adj. R² (6-dim)` = round(sapply(c("PC1_Score","PC2_Score","PC3_Score"), function(pc) summary(models[[paste0(pc,"_55_nogdp")]])$adj.r.squared), 3),
  `ΔAdj. R²`     = round(sapply(c("PC1_Score","PC2_Score","PC3_Score"), function(pc) rq3_f[[pc]]["dadjR2"]), 3),
  `F(2, 48)`     = round(sapply(c("PC1_Score","PC2_Score","PC3_Score"), function(pc) rq3_f[[pc]]["F"]), 2),
  `p`            = round(sapply(c("PC1_Score","PC2_Score","PC3_Score"), function(pc) rq3_f[[pc]]["p"]), 3),
  check.names = FALSE
)
print(t61)
export_apa_table(
  data_df = t61,
  table_title = "Table 6-1 Incremental Explanatory Power of LTO and IVR within the 55-Country Core Sample",
  file_name = "Table_6-1_RQ3_Incremental_Comparison.docx",
  note_text = "Note: Four-dimension models include PDI, IDV, MAS and UAI; six-dimension models additionally include LTO and IVR. Nested F-tests compare the six-dimension against the four-dimension specification (df = 2, 48) within the 55-country sample, without GDP control. * p<0.05, ** p<0.01, *** p<0.001."
)
cat("\n=== Table 6-1 exported to Word ===\n")

cat("\n=== [Sec 5.2.1] Eigenvalues (full spectrum, first 5) ===\n")
print(res.pca_all$eig[1:5, ])

cat("\n=== [Sec 5.1.2] UAI extremes for regional description ===\n")
uai_sorted <- sort(export_55_data$uai)
print(head(uai_sorted, 5)); print(tail(uai_sorted, 5))
