# Run from the repository root: Rscript --vanilla tests/smoke.R
check_analysis <- function() {
  repo <- normalizePath(".", winslash = "/")
  output <- tempfile("music-output-")
  previous_output <- Sys.getenv("MUSIC_CULTURE_OUTPUT_DIR", unset = NA_character_)
  original_wd <- getwd()
  on.exit({
    setwd(original_wd)
    if (is.na(previous_output)) Sys.unsetenv("MUSIC_CULTURE_OUTPUT_DIR")
    else Sys.setenv(MUSIC_CULTURE_OUTPUT_DIR = previous_output)
  }, add = TRUE)
  Sys.setenv(MUSIC_CULTURE_OUTPUT_DIR = output)
  setwd(tempdir())
  caller_wd <- getwd()
  source(file.path(repo, "music_culture_analysis.R"))
  stopifnot(identical(getwd(), caller_wd))
  sample55 <- readxl::read_xlsx(file.path(output, "Final_Data_55_Countries.xlsx"))
  sample60 <- readxl::read_xlsx(file.path(output, "Final_Data_60_Countries.xlsx"))
  stopifnot(nrow(sample55) == 55L, nrow(sample60) == 60L,
            all(sample55[["country or region"]] %in% sample60[["country or region"]]))
  tables <- list.files(output, pattern = "^Table_.*\\.docx$", full.names = TRUE)
  figures <- list.files(output, pattern = "\\.pdf$", full.names = TRUE)
  stopifnot(length(tables) == 9L, length(figures) >= 7L,
            all(file.info(c(tables, figures))$size > 0),
            file.info(file.path(output, "session-info.txt"))$size > 0)
  cat("Music analysis reproducibility checks passed.\n")
}
check_analysis()
