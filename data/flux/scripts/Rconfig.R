#!/usr/bin/env Rscript
# R Setup Script
# Author: Christopher Smith
# Date: 2024-10-07

# Prerequisites: Install R and IDE (manual steps, not included in script)

# Define the mirror URL (edit as needed)
cran_mirror <- "https://lib.stat.cmu.edu/R/CRAN/"

# Get the HOME directory, which is where R looks for .Renviron
# Note: gsub is used to replace backslashes with forward slashes
home_dir <- gsub("\\\\", "/", Sys.getenv("HOME"))

# Get the USERPROFILE directory, which on Windows systems with OneDrive
# may be a better choice than HOME for library paths (because R sets
# HOME to the Documents folder like some kind of psychopath)
userprofile_dir <- gsub("\\\\", "/", Sys.getenv("USERPROFILE"))

# Define the library path in a cross-platform compatible way
lib_path <- if (Sys.info()["sysname"] == "Darwin") {
  file.path(home_dir, "Library/R/library")
} else {
  file.path(userprofile_dir, ".R/library")
}

# Define the path to the .Renviron file
renviron_path <- file.path(home_dir, ".Renviron")

# Create the .Renviron file if it doesn't exist
if (!file.exists(renviron_path)) {
  file.create(renviron_path)
}

# Create the R_LIBS_USER line to be added to .Renviron
r_libs_user_line <- sprintf("R_LIBS_USER=%s", lib_path)

# Append the R_LIBS_USER line to .Renviron if it doesn't already exist
if (!any(grepl("^R_LIBS_USER=", readLines(renviron_path)))) {
  cat(r_libs_user_line, file = renviron_path, append = TRUE, sep = "\n")
  cat("Added R_LIBS_USER to .Renviron\n")
} else {
  cat("R_LIBS_USER already exists in .Renviron. Skipping...\n")
}

# Reload .Renviron to apply changes to the current environment
readRenviron(renviron_path)

# Add the library path to .libPaths()
.libPaths(lib_path)

# Create the library directory if it doesn't exist
if (!dir.exists(lib_path)) {
  success <- dir.create(lib_path, recursive = TRUE, showWarnings = TRUE)
  if (!success) {
    stop("Failed to create library directory at: ", lib_path,
         "\nPlease check permissions and ensure parent directories exist.")
  }
  cat("Successfully created library directory at: ", lib_path, "\n")
} else {
  cat("Library directory already exists at: ", lib_path, "\n")
}

# Verify the directory exists and is writable before proceeding
if (!dir.exists(lib_path)) {
  stop("Library directory does not exist: ", lib_path)
}
if (!file.access(lib_path, mode = 2) == 0) {
  stop("Library directory is not writable: ", lib_path)
}

# Define the path to the .Rprofile file
rprofile_path <- file.path(home_dir, ".Rprofile")

# Create the .Rprofile file if it doesn't exist
if (!file.exists(rprofile_path)) {
  file.create(rprofile_path)
}

# Content to be added to .Rprofile
rprofile_content <- sprintf('
if (file.exists("~/.Renviron")) {
  readRenviron("~/.Renviron")
}
options(repos = c(CRAN = "%s"))
', cran_mirror)

# Read existing .Rprofile content
existing_content <- readLines(rprofile_path, warn = FALSE)

# Check if the content already exists
if (!any(grepl("readRenviron\\(\"~/.Renviron\"\\)", existing_content)) &&
      !any(grepl(sprintf("options\\(repos = c\\(CRAN = \"%s\"\\)\\)",
                         cran_mirror), existing_content))) {

  # Append the new content to .Rprofile
  cat(rprofile_content, file = rprofile_path, append = TRUE)
  cat("Added necessary lines to .Rprofile\n")
} else {
  cat("Required content already exists in .Rprofile. Skipping...\n")
}

# Execute the contents of the .Rprofile file
source(rprofile_path)

# Install user-level packages
install.packages(c("devtools", "renv", "httpgd"), lib = lib_path)
install.packages("languageserver", repos = c(
  reditorsupport = "https://reditorsupport.r-universe.dev",
  getOption("repos")
), lib = lib_path)

# Note: Changes to .Rprofile will take effect in the next R session
cat("Note: Restart R for changes in .Rprofile to take effect.\n")
cat("After restart, run print(.libPaths()) to verify the library path\n")
cat("and print(options()$repos) to verify the mirror setting.\n")
