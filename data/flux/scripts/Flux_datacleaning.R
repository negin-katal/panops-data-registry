##### 16.04.2025, Author NK
# this code is for cleaning flux data

getwd()
setwd("/mnt/gsdata/projects/other/Flux/EcoRes/EcoRes")
library(readr)
install.packages("arrow")
library(arrow)
library(REddyProc)
library(bigleaf)
#Let's first read the BADM file to get the site infos
library(dplyr)
library(tidyr)
FLX_AA <- FLX_AA_Flx_BIF_WW_20200501
unique(EddyCovarianceMonthlyV0_007$site)

# Define the variables you want to extract
target_vars <- c("IGBP", "LOCATION_LAT", "LOCATION_LONG", "COUNTRY", "DOI", "SITE_NAME")

# Filter for only the target variables and pivot to wide format
site_meta_df <- FLX_AA %>%
  filter(VARIABLE %in% target_vars) %>%
  select(SITE_ID, VARIABLE, DATAVALUE) %>%
  pivot_wider(names_from = VARIABLE, values_from = DATAVALUE) %>%
  distinct()

library(stringr)

site_meta_df_clean <- site_meta_df %>%
  mutate(
    LOCATION_LAT = str_remove_all(LOCATION_LAT, '^c\\(|\\)$'),
    LOCATION_LONG = str_remove_all(LOCATION_LONG, '^c\\(|\\)$')
  ) %>%
  separate(LOCATION_LAT, into = paste0("LAT_", 1:3), sep = ",\\s*", fill = "right") %>%
  separate(LOCATION_LONG, into = paste0("LONG_", 1:3), sep = ",\\s*", fill = "right") %>%
  mutate(across(starts_with("LAT_"), as.numeric),
         across(starts_with("LONG_"), as.numeric))
# Convert numeric fields if needed
site_meta_df_clean <- site_meta_df %>%
  mutate(
    LOCATION_LAT = as.numeric(LOCATION_LAT),
    LOCATION_LONG = as.numeric(LOCATION_LONG)
  )
# View result
str(site_meta_df_clean)
sapply(site_meta_df_clean, class)
print(site_meta_df)
# Unlist all list-columns
site_meta_df_clean <- site_meta_df_clean %>%
  mutate(
    COUNTRY = as.character(sapply(COUNTRY, `[`, 1)),
    DOI = as.character(sapply(DOI, `[`, 1)),
    SITE_NAME = as.character(sapply(SITE_NAME, `[`, 1)),
    IGBP = as.character(sapply(IGBP, `[`, 1))
  )

# Reassign as numeric for all LAT_* and LONG_* columns
site_meta_df_clean[, grep("^LAT_|^LONG_", names(site_meta_df_clean))] <- 
  lapply(site_meta_df_clean[, grep("^LAT_|^LONG_", names(site_meta_df_clean))], as.numeric)

# Confirm they're now numeric
sapply(site_meta_df_clean[, grep("^LAT_|^LONG_", names(site_meta_df_clean))], class)


write.csv(site_meta_df_clean, "clean_data/site_metadata_Fluxnet2015.csv", row.names = FALSE)
#first check all the files format
zip_files <- list.files("ICOS_fullset", pattern = "\\.zip$", full.names = TRUE)
length(zip_files)   # See how many there are
head(zip_files)     # Preview first few
### check nside the first one
unzip(zip_files[10], list = TRUE)
#########
# List all zip files
  
zip_files <- list.files("EddyTower", pattern = "\\.zip$", full.names = TRUE)

# Filter FLX zip files
flx_zips <- zip_files[grepl("^.*FLX", basename(zip_files))]

# Pick the first FLX zip
flx_zip <- flx_zips[1]

# Look inside
flx_contents <- unzip(flx_zip, list = TRUE)

# Find the *_YY_*.csv file
flx_yy_file <- flx_contents$Name[grepl("FULLSET_HH_.*\\.csv$", flx_contents$Name)]

# Extract to tempdir
tmp_dir <- tempdir()
unzip(flx_zip, files = flx_yy_file, exdir = tmp_dir)

# Load file
flx_path <- file.path(tmp_dir, flx_yy_file)
flx_df <- readr::read_csv(flx_path, n_max = 10)
print(flx_df)
colnames(flx_df)
#####################################
# Filter ICOSETC zip files
ico_zips <- zip_files[grepl("^.*ICOSETC", basename(zip_files))]

# Pick the first ICOSETC zip
ico_zip <- ico_zips[1]

# Look inside
ico_contents <- unzip(ico_zip, list = TRUE)

# Find the *_YY_*.csv file
ico_yy_file <- ico_contents$Name[
  grepl("_HH_.*\\.csv$", ico_contents$Name) & 
    !grepl("VARINFO", ico_contents$Name)
]


# Extract to tempdir
tmp_dir <- tempdir()
unzip(ico_zip, files = ico_yy_file, exdir = tmp_dir)

# Load file
ico_path <- file.path(tmp_dir, ico_yy_file)
ico_df <- readr::read_csv(ico_path, n_max = 10)
print(ico_df)
colnames(ico_df)
#######################
library(readr)
library(dplyr)
library(stringr)

# Path to your folder
zip_path <- "EddyTower"
zip_files <- list.files(zip_path, pattern = "\\.zip$", full.names = TRUE)

# Columns you want to keep
wanted_cols <- c(
  "TIMESTAMP_START", "TIMESTAMP_END", "TA_F", "TA_F_QC", "VPD_F", "VPD_F_QC", "P_F", "P_F_QC",
  "TS_F_MDS_1", "TS_F_MDS_2","TS_F_MDS_1_QC", "TS_F_MDS_2_QC", "WS_F", "WS_F_QC",
  "SWC_F_MDS_1", "SWC_F_MDS_2", "SWC_F_MDS_1_QC", "SWC_F_MDS_2_QC",
  "H_CORR", "H_RANDUNC", "H_RANDUNC_N", "NEE_VUT_REF_RANDUNC_N",
  "LE_F_MDS", "LE_F_MDS_QC", "LE_CORR", "LE_RANDUNC", "LE_RANDUNC_N",
  "H_F_MDS", "H_F_MDS_QC", "CO2_F_MDS", "CO2_F_MDS_QC",
  "NEE_VUT_REF", "NEE_VUT_REF_QC", "NEE_VUT_50", "NEE_VUT_50_QC", "NEE_VUT_REF_RANDUNC",
  "GPP_NT_VUT_REF", "GPP_DT_VUT_REF", "GPP_NT_VUT_50", "GPP_DT_VUT_50",
  "RECO_NT_VUT_REF", "RECO_DT_VUT_REF", "RECO_NT_VUT_50", "RECO_DT_VUT_50",
  "SW_IN_F", "SW_IN_F_QC", "PPFD_IN", "PPFD_DIF", "PPFD_OUT", "TA_F_MDS", "TA_F_MDS_QC",
  "VPD_F_MDS", "SW_IN_F_MDS", "SW_IN_F_MDS_QC", "SW_IN_POT", "LW_IN_F", "LW_OUT", "SW_OUT",
  "NETRAD", "USTAR", "WS", "G_F_MDS", "G_F_MDS_QC", "RH", "NIGHT", "PA"
)

# Temp dir for extraction
tmp_dir <- tempdir()

# Empty list to collect all site data
all_data <- list()

for (zip in zip_files) {
  zip_name <- basename(zip)
  
  # Determine type of file and pattern
  if (str_starts(zip_name, "FLX")) {
    site_id <- str_extract(zip_name, "(?<=FLX_)[^_]+")
    source <- "FLX"
    csv_pattern <- "FULLSET_HH_.*\\.csv$"
  } else if (str_starts(zip_name, "AMF")) {
    site_id <- str_extract(zip_name, "(?<=AMF_)[^_]+")
    source <- "AMF"
    csv_pattern <- "FULLSET_HH_.*\\.csv$"
  } else if (str_starts(zip_name, "ICOSETC")) {
    site_id <- str_extract(zip_name, "(?<=ICOSETC_)[^_]+")
    source <- "ICOSETC"
    csv_pattern <- "_HH_.*\\.csv$"
  } else {
    next  # Skip unrecognized files
  }
  
  # List content and find the CSV file (skip VARINFO)
  file_list <- unzip(zip, list = TRUE)$Name
  target_file <- file_list[grepl(csv_pattern, file_list) & !grepl("VARINFO", file_list)]
  
  if (length(target_file) == 0) {
    warning(paste("No valid CSV found in:", zip_name))
    next
  }
  
  # Extract to a temp subfolder
  unzip_tmp <- file.path(tmp_dir, paste0("unzipped_", site_id))
  dir.create(unzip_tmp, showWarnings = FALSE, recursive = TRUE)
  unzip(zip, files = target_file, exdir = unzip_tmp, overwrite = TRUE)
  
  file_path <- file.path(unzip_tmp, target_file)
  
  # Read and filter
  df <- tryCatch({
    df_read <- read_csv(file_path, guess_max = 10000, show_col_types = FALSE)
    df_read %>%
      select(any_of(wanted_cols)) %>%
      mutate(siteID = site_id, source = source, .before = 1)
  }, error = function(e) {
    message(paste("Error reading:", target_file))
    NULL
  })
  
  if (!is.null(df)) {
    all_data[[length(all_data) + 1]] <- df
  }
}

# Combine all into one dataframe
combined_df <- bind_rows(all_data)
colnames(combined_df)
str(combined_df)
unique(combined_df$source)

##### restructure the dataset as the one in Mirco's paper
# Define the rename map (original to new)
library(data.table)
library(dplyr)
library(rlang)
library(tidyselect)
combined_df <- fread("408_site_HH_notclean.csv")
rename_map <- c(
  "CO2_F_MDS"            = "CO2",
  "CO2_F_MDS_QC"         = "CO2_QC",
  "GPP_DT_VUT_REF"       = "GPP_DT",
  "GPP_NT_VUT_REF"       = "GPP_NT",
  "G_F_MDS"              = "G",
  "G_F_MDS_QC"           = "G_QC",
  "H_CORR"               = "H_CORR",
  "H_F_MDS"              = "H",
  "H_F_MDS_QC"           = "H_QC",
  "H_RANDUNC"            = "H_RANDUNC",
  "H_RANDUNC_N"          = "H_RANDUNC_N",
  "LE_CORR"              = "LE_CORR",
  "LE_F_MDS"             = "LE",
  "LE_F_MDS_QC"          = "LE_QC",
  "LE_RANDUNC"           = "LE_RANDUNC",
  "LE_RANDUNC_N"         = "LE_RANDUNC_N",
  "LW_IN_F"              = "LW_IN",
  "LW_OUT"               = "LW_OUT",
  "NEE_VUT_REF"          = "NEE",
  "NEE_VUT_REF_QC"       = "NEE_QC",
  "NEE_VUT_REF_RANDUNC"  = "NEE_RANDUNC",
  "NEE_VUT_REF_RANDUNC_N"= "NEE_RANDUNC_N",
  "NETRAD"               = "NETRAD",
  "NIGHT"                = "NIGHT",
  "P_F"                  = "P",
  "PA"                   = "PA",
  "PPFD_DIF"             = "PPFD_DIF",
  "PPFD_IN"              = "PPFD_IN",
  "PPFD_OUT"             = "PPFD_OUT",
  "RECO_DT_VUT_REF"      = "RECO_DT",
  "RECO_NT_VUT_REF"      = "RECO_NT",
  "SWC_F_MDS_1"          = "SWC_1",
  "SWC_F_MDS_1_QC"       = "SWC_1_QC",
  "SWC_F_MDS_2"          = "SWC_2",
  "SWC_F_MDS_2_QC"       = "SWC_2_QC",
  "SW_IN_F"              = "SW_IN",
  "SW_IN_F_QC"           = "SW_IN_QC",
  "SW_OUT"               = "SW_OUT",
  "SW_IN_POT"            = "SW_IN_POT",
  "TA_F"                 = "TA",
  "TA_F_QC"              = "TA_QC",
  "TS_F_MDS_1"           = "TS_1",
  "TS_F_MDS_2"           = "TS_2",
  "TS_F_MDS_1_QC"        = "TS_1_QC",
  "TS_F_MDS_2_QC"        = "TS_2_QC",
  "USTAR"                = "USTAR",
  "VPD_F"                = "VPD",
  "VPD_F_QC"             = "VPD_QC"
)


# Step 1: Flip the rename_map to new_name = old_name
flipped_map <- setNames(names(rename_map), rename_map)

# Step 2: Keep only the valid entries (old names exist, new names don't yet exist)
safe_map <- flipped_map[
  flipped_map %in% names(flux_all_cleaned) &
    !(names(flipped_map) %in% names(flux_all_cleaned))
]

# ✅ Step 3: Convert to list and apply rename
combined_df_renamed <- flux_all_cleaned %>%
  rename(!!!as.list(safe_map))



combined_df <- combined_df %>%
  mutate(
    DateTime = lubridate::ymd_hm(as.character(TIMESTAMP_START), tz = "UTC")
  ) %>%
  relocate(siteID, DateTime)


str(combined_df_renamed)

##############################################  
library(lubridate)
combined_df <- combined_df %>%
  mutate(
    # Convert TIMESTAMP_START to character first, then parse with ymd_hm
    year = year(DateTime),
    month = month(DateTime),
    doy = day(DateTime),
    hour = hour(DateTime)
  )



# Count how many sources per siteID-year
source_counts <- combined_df %>%
  group_by(siteID, year) %>%
  summarise(n_sources = n_distinct(source), .groups = "drop")

# Identify siteID-year combos with >1 source
duplicates <- source_counts %>% filter(n_sources > 1)

# Optionally preview
print(duplicates)

# Define which source you want to prefer (e.g., FLX over AMF or ICOSETC)
preferred_source_order <- c("FLX", "AMF", "ICOSETC")  # highest priority first

# Add preference ranking to flux_all
flux_all_cleaned <- combined_df %>%
  mutate(source_priority = match(source, preferred_source_order)) %>%
  group_by(siteID, year) %>%
  arrange(source_priority) %>%
  # Keep only rows from the top-ranked source per site-year
  filter(source == first(source)) %>%
  ungroup() %>%
  select(-source_priority)  # optional: drop the helper column

str(flux_all)
write.csv(flux_all, "clean_data/408_site_HH.csv", row.names = FALSE)
write_parquet(flux_all, "clean_data/flux_all.parquet")

write.csv(combined_df, "408_site_HH_notclean.csv", row.names = FALSE)
########################################################## Check for meta data
# Find zips that contain a SITEINFO or METADATA file
for (zip in zip_files) {
  contents <- unzip(zip, list = TRUE)$Name
  
  # Filter out files that start with "BIF"
  siteinfo_files <- contents[grepl("SITEINFO|METADATA", contents, ignore.case = TRUE) & !grepl("^BIF", basename(contents))]
  
  if (length(siteinfo_files) > 0) {
    cat("Found site info in:", basename(zip), "\n")
    print(siteinfo_files)
  }
}


library(readr)

zip_file <- "ICOS_fullset/ICOSETC_UK-AMo_ARCHIVE_L2.zip"

# File inside the ZIP you want to open
csv_file <- "BIF_SiteInfo_Variables.csv"
# Temporary extraction path
tmp_dir <- tempdir()

# Extract just that file
unzip(zip_file, files = csv_file, exdir = tmp_dir, overwrite = TRUE)

# Full path to the extracted file
csv_path <- file.path(tmp_dir, csv_file)

# Read the CSV
df <- read_csv(csv_path, show_col_types = FALSE)

# View first few rows
print(df)




library(readr)
library(dplyr)
library(stringr)

# Variables you want to extract
wanted_vars <- c("SITE_DESK", "LOCATION_LAT", "LOCATION_LONG",
                 "LOCATION_ELEV", "IGBP", "MAT", "MAP")

# Empty list to store site data
site_info_list <- list()

# Loop through zip files
for (zip in zip_files) {
  contents <- unzip(zip, list = TRUE)$Name
  
  # Find the correct site info file, skip BIF files
  siteinfo_file <- contents[grepl("SITEINFO|METADATA", contents, ignore.case = TRUE) & 
                              !grepl("^BIF", basename(contents))]
  
  if (length(siteinfo_file) == 0) next  # Skip if none found
  
  # Extract just the first valid siteinfo file
  target_file <- siteinfo_file[1]
  unzip(zip, files = target_file, exdir = tempdir(), overwrite = TRUE)
  file_path <- file.path(tempdir(), target_file)
  
  # Try reading and filtering
  site_df <- tryCatch({
    df <- read_csv(file_path, show_col_types = FALSE)
    # Some files might use lowercase column names
    colnames(df) <- toupper(colnames(df))
    df %>%
      filter(VARIABLE %in% wanted_vars) %>%
      select(VARIABLE, DATAVALUE)
  }, error = function(e) {
    message("Error reading: ", zip)
    NULL
  })
  
  if (!is.null(site_df)) {
    # Extract site ID from file name (e.g., ICOSETC_UK-AMo_SITEINFO_L2.csv)
    site_id <- str_extract(basename(target_file), "[A-Z]{2}-[A-Za-z]+")
    site_info_list[[site_id]] <- site_df
  }
}

# You can view one example:
print(site_info_list[["UK-AMo"]])

###### reshape it
library(dplyr)
library(tidyr)
library(purrr)
library(data.table)

# Combine and reshape all site dataframes
reshaped_site_info <- map_dfr(names(site_info_list), function(site_id) {
  df <- site_info_list[[site_id]]
  df %>%
    pivot_wider(names_from = VARIABLE, values_from = DATAVALUE) %>%
    mutate(site_id = site_id, .before = 1)
})

# View the final dataframe
print(reshaped_site_info)

write_csv(reshaped_site_info, "clean_data/ICOS_siteinfo.csv")
#### Let's read all other site infos we have
site_metadata_fluxnet2015 <- fread("clean_data/site_metadata_Fluxnet2015.csv")
all_tower_location <- fread("clean_data/all_tower_location_cleaned.csv")
colnames(reshaped_site_info)
#### clean the metadata:
library(dplyr)

# Step 1: Prepare site_metadata_fluxnet2015
fluxnet2015_clean <- site_metadata_fluxnet2015 %>%
  transmute(
    SITE_ID = SITE_ID,
    SITE_NAME = SITE_NAME,
    LAT = as.numeric(LAT_1),
    LONG = as.numeric(LONG_1),
    LOCATION_ELEV = NA_real_,  # not available here
    IGBP = IGBP
  )

# Step 2: Prepare all_tower_location
tower_clean <- all_tower_location %>%
  transmute(
    SITE_ID = SITE_ID,
    SITE_NAME = SITE_NAME,
    LAT = as.numeric(LOCATION_LAT),
    LONG = as.numeric(LOCATION_LONG),
    LOCATION_ELEV = as.numeric(LOCATION_ELEV),
    IGBP = IGBP
  )

# Step 3: Prepare reshaped_site_info
reshaped_clean <- reshaped_site_info %>%
  transmute(
    SITE_ID = site_id,
    SITE_NAME = NA_character_,  # not available here
    LAT = as.numeric(LOCATION_LAT),
    LONG = as.numeric(LOCATION_LONG),
    LOCATION_ELEV = as.numeric(LOCATION_ELEV),
    IGBP = IGBP
  )

# Step 4: Bind all together
combined_all <- bind_rows(
  reshaped_clean,      # put this first so its values take priority
  tower_clean,
  fluxnet2015_clean
)

# Step 5: Deduplicate by SITE_ID, keeping first non-NA values
combined_clean <- combined_all %>%
  group_by(SITE_ID) %>%
  summarise(
    SITE_NAME = coalesce(SITE_NAME[!is.na(SITE_NAME)][1], NA_character_),
    LAT = coalesce(LAT[!is.na(LAT)][1], NA_real_),
    LONG = coalesce(LONG[!is.na(LONG)][1], NA_real_),
    LOCATION_ELEV = coalesce(LOCATION_ELEV[!is.na(LOCATION_ELEV)][1], NA_real_),
    IGBP = coalesce(IGBP[!is.na(IGBP)][1], NA_character_),
    .groups = "drop"
  )

# Step 6: Clean and standardize fluxcites_long
fluxcites_clean <- fluxcites_long %>%
  transmute(
    SITE_ID = site,
    SITE_NAME = NA_character_,
    LAT = as.numeric(tower_lat),
    LONG = as.numeric(tower_lon),
    LOCATION_ELEV = NA_real_,
    IGBP = as.character(PFT)
  )

# Step 7: Append to previous combined_all
combined_all_extended <- bind_rows(
  reshaped_clean,       # highest priority
  tower_clean,
  fluxnet2015_clean,
  fluxcites_clean       # lowest priority, added last
)

# Step 8: Deduplicate by SITE_ID, keeping first non-NA values
combined_clean <- combined_all_extended %>%
  group_by(SITE_ID) %>%
  summarise(
    SITE_NAME = coalesce(SITE_NAME[!is.na(SITE_NAME)][1], NA_character_),
    LAT = coalesce(LAT[!is.na(LAT)][1], NA_real_),
    LONG = coalesce(LONG[!is.na(LONG)][1], NA_real_),
    LOCATION_ELEV = coalesce(LOCATION_ELEV[!is.na(LOCATION_ELEV)][1], NA_real_),
    IGBP = coalesce(IGBP[!is.na(IGBP)][1], NA_character_),
    .groups = "drop"
  )

# View the cleaned result
glimpse(combined_clean)

# Write the final cleaned metadata to CSV
write.csv(combined_clean, "clean_data/combined_site_metadata.csv", row.names = FALSE)

########
#### let's merge the site info with flux info
###read the yearly flux data
yearly_flux <- read_csv("clean_data/combined_ICOS_data_yearly.csv")
Icos_only <- yearly_flux %>% 
  filter(source=="ICOSETC")

Icos_merged <- Icos_only %>%
  left_join(reshaped_site_info, by = "site_id")

###########################################################################
library(dplyr)
library(lubridate)
library(ggplot2)

combined_countries <- combined_df %>%
  mutate(country_code = substr(site_id, 1, 2))  # Extract first two characters

germany <- combined_countries %>% 
  filter(country_code=="DE")

ggplot(germany, aes(x = as.character(year), y = NEE_VUT_REF)) +
  geom_bar(stat = "identity") +
  facet_wrap(~ site_id, scales = "free_y") +
  theme_minimal() +
  labs(x = "Year", y = "NEE", title = "NEE per Site in Germany")


ggplot(Icos_merged, aes(x = TIMESTAMP, y = GPP_NT_VUT_REF, color = IGBP)) +
  geom_line() +
  #geom_bar(stat = "identity") +
  facet_wrap(~ site_id, scales = "free_y") +
  labs(title = "Yearly GPP per Site by Year",
       x = "Year",
       y = "Yearly GPP",
       color = "IGBP") +
  theme_minimal()

########################################################################################
####### based on the list that Jake send it 
#### Cleaning the PTFs
library(tidyverse)
library(ggplot2)
install.packages("rnaturalearth")
install.packages("rnaturalearthdata")
library(rnaturalearth)
library(rnaturalearthdata)
library(sf)

#flux_sites_long <- flux_sites %>%
#  pivot_longer(
#    cols = 4:20,              # columns with PFTs (adjust if needed)
#    names_to = "PFT",         # new column name for PFT type
#    values_to = "value"       # new column name for presence (0/1)
#  ) %>%
#  filter(value == 1) %>%      # keep only PFTs present at each site
#  select(site, tower_lat, tower_lon, PFT)  # final columns

library(readr)
fluxsites_long <- read_csv("clean_data/fluxcites_long.csv")
View(fluxsites_long)

# Load world map
world <- ne_countries(scale = "medium", returnclass = "sf")
# Remove "PFT_" prefix from IGBP values
efp_with_meta <- efp_with_meta %>%
  mutate(IGBP = str_remove(IGBP, "^PFT_"))
# Plot
ggplot() +
  geom_sf(data = world, fill = "gray95", color = "gray80") +  # background map
  geom_point(data = efp_with_meta, 
             aes(x = LOCATION_LONG, y = LOCATION_LAT, color = IGBP), 
             size = 2, alpha = 0.8) +  # site points
  scale_color_viridis_d(option = "turbo") +  # colorful palette
  coord_sf() +
  theme_minimal() +
  labs(title = "Current available data 07.08.2025",
       x = "Longitude", y = "Latitude", color = "IGBP")



excluded_pfts <- c("PFT_CRO", "PFT_GRA", "PFT_CVM", 
                   "PFT_URB", "PFT_WAT", "PFT_BSV", "PFT_SNO")

flux_sites_filtered <- fluxsites_long %>%
  filter(!PFT %in% excluded_pfts)

#write.csv(flux_sites_long, "Data/Flux/fluxcites_long.csv")



# Load base map
world <- ne_countries(scale = "medium", returnclass = "sf")

# Plot with filtered PFTs
ggplot() +
  geom_sf(data = world, fill = "gray95", color = "gray80") +
  geom_point(data = flux_sites_filtered, 
             aes(x = tower_lon, y = tower_lat, color = PFT), 
             size = 2, alpha = 0.8) +
  scale_color_viridis_d(option = "turbo") +
  coord_sf() +
  theme_minimal() +
  labs(title = "Flux Sites by PFT (Filtered)",
       x = "Longitude", y = "Latitude", color = "PFT")

selected_pfts <- c("PFT_DBF", "PFT_DNF", "PFT_EBF", "PFT_ENF", 
                   "PFT_MF", "PFT_SAV", "PFT_WSA", "PFT_OSH", "PFT_CSH")

flux_sites_selected <- fluxcites_long %>%
  filter(PFT %in% selected_pfts)

ggplot() +
  geom_sf(data = world, fill = "gray95", color = "gray80") +
  geom_point(data = flux_sites_selected, 
             aes(x = tower_lon, y = tower_lat, color = PFT), 
             size = 2, alpha = 0.8) +
  scale_color_viridis_d(option = "turbo") +
  coord_sf() +
  theme_minimal() +
  labs(title = "Flux Sites Forest",
       x = "Longitude", y = "Latitude", color = "PFT")


library(dplyr)
library(ggplot2)
library(ggsci)

# Count the number of sites for each PFT
pft_counts <- flux_sites_filtered %>%
  group_by(PFT) %>%
  summarise(n_sites = n_distinct(site)) %>%
  arrange(desc(n_sites))

ggplot(pft_counts, aes(x = reorder(PFT, -n_sites), y = n_sites, fill = PFT)) +
  geom_bar(stat = "identity") +
  theme_minimal() +
  labs(title = "Number of Sites per PFT",
       x = "PFT", y = "Number of Sites") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  ggsci::scale_fill_npg()

library(scales)  # for hue_pal

# Generate 20 distinct colors
my_colors <- hue_pal()(length(unique(pft_counts$PFT)))

ggplot(pft_counts, aes(x = reorder(PFT, -n_sites), y = n_sites, fill = PFT)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = n_sites), vjust = -0.3, size = 3) +  # <- Add count above bar
  theme_minimal() +
  labs(title = "Number of Sites per PFT",
       x = "PFT", y = "Number of Sites") +
  theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
  scale_fill_manual(values = my_colors)

############################################################ 27.05.2025 GPP max/sat
#### rectangular hyperbolic light response model
install.packages("minpack.lm")

library(minpack.lm)
library(dplyr)
library(tidyr)
library(purrr)

# Non-rectangular hyperbola (simplified rectangular version here)
light_response_model <- function(df) {
  tryCatch({
    fit <- nlsLM(GPP_NT_VUT_REF ~ (alpha * PPFD_IN * GPP_sat) / (alpha * PPFD_IN + GPP_sat),
                 data = df,
                 start = list(alpha = 0.01, GPP_sat = 20),
                 control = nls.lm.control(maxiter = 500))
    
    tibble(GPP_sat = coef(fit)["GPP_sat"],
           alpha = coef(fit)["alpha"],
           GPP_max = max(df$GPP_NT_VUT_REF, na.rm = TRUE))
  }, error = function(e) {
    tibble(GPP_sat = NA, alpha = NA, GPP_max = NA)
  })
}
# Prepare data (optional filters to improve fit quality)
filtered_data <- half_hourly_flux %>%
  filter(PPFD_IN > 50, 
         !is.na(GPP_NT_VUT_REF), 
         !is.na(PPFD_IN), 
         VPD_F_MDS < 1.5, 
         TA_F_MDS >= 5 & TA_F_MDS <= 30)

# Fit model per site_id and year
gpp_fits <- filtered_data %>%
  group_by(site_id, year) %>%
  nest() %>%
  mutate(fit = map(data, light_response_model)) %>%
  unnest(fit) %>%
  select(-data)

colnames(gpp_fits)
write.csv(gpp_fits, "GPP_max_sat_by_site_year_flxarchive.csv", row.names = FALSE)

####clean the data
gpp_fits_clean <- gpp_fits %>%
  filter(GPP_sat > 0, GPP_max > 0, alpha > 0)

gpp_fits_clean <- gpp_fits_clean %>%
  filter(GPP_sat < 1000)

library(ggplot2)

gpp_fits_clean %>%
  filter(site_id == "DE-Tha") %>%
  ggplot(aes(x = year, y = GPP_max)) +
  geom_line() +
  geom_point() +
  labs(title = "GPP_max over time for DE-Tha",
       x = "Year", y = "GPP_max (µmol m⁻² s⁻¹)") +
  theme_minimal()

gpp_fits_clean %>%
  filter(year == 2018) %>%
  ggplot(aes(x = reorder(site_id, GPP_sat), y = GPP_sat)) +
  geom_col(fill = "steelblue") +
  coord_flip() +
  labs(title = "GPP_sat across sites in 2018",
       x = "Site", y = "GPP_sat (µmol m⁻² s⁻¹)") +
  theme_minimal()


gpp_fits_clean %>%
  ggplot(aes(x = year, y = site_id, fill = GPP_max)) +
  geom_tile() +
  scale_fill_viridis_c() +
  labs(title = "Heatmap of GPP_max across sites and years",
       x = "Year", y = "Site", fill = "GPP_max") +
  theme_minimal()


####### Anamoly analysis
flux_clean <- combined_df %>%
  mutate(
    timestamp = ymd_hm(as.character(TIMESTAMP_START)),  # fix timestamp
    year = year(timestamp),
    doy = yday(timestamp),
    hour = hour(timestamp),
    PPFD = PPFD_IN,  # rename for clarity
    GPP = GPP_NT_VUT_REF  # choose your preferred GPP product
  ) %>%
  filter(GPP >= 0, PPFD > 0)  # remove non-physical or nighttime values


light_response_model <- function(df) {
  tryCatch({
    fit <- nls(GPP ~ (alpha * PPFD * GPP_sat) / (alpha * PPFD + GPP_sat),
               data = df,
               start = list(alpha = 0.01, GPP_sat = 20),
               control = nls.control(maxiter = 200))
    coef_df <- as.data.frame(t(coef(fit)))
    coef_df$GPP_max <- with(coef_df, (alpha * GPP_sat) / (alpha + 1))
    return(coef_df)
  }, error = function(e) {
    return(tibble(alpha = NA, GPP_sat = NA, GPP_max = NA))
  })
}

# Fit model per site_id and month
library(purrr)
library(tidyr)

monthly_fits <- flux_clean %>%
  group_by(site_id, year, month) %>%
  filter(n() > 100) %>%
  nest() %>%
  mutate(fit = map(data, light_response_model)) %>%
  unnest(fit) %>%
  select(site_id, year, month, GPP_sat, GPP_max, alpha)

library(ggplot2)

monthly_fits %>%
  filter(site_id == "DE-Hai", month %in% 5:9) %>%
  ggplot(aes(x = month, y = GPP_max, color = as.factor(year))) +
  geom_line(size = 1) +
  geom_point() +
  scale_color_manual(values = c("2018" = "red")) +
  labs(title = "GPP_max at DE-Hai (May–Sep)",
       y = "GPP_max", x = "Month") +
  theme_minimal()

##### Based on Talie's paper non-rectangular hyperbolic light response model
# Load necessary libraries
# Required libraries
library(dplyr)
library(slider)
library(purrr)
library(broom)
library(tidyr)
library(ggplot2)
library(readr)

combined_df <- read_csv("clean_data/combined_ICOS_data_HH_NEW.csv", show_col_types = FALSE)

colnames(combined_df)
Germany_forest <- combined_df %>%
  filter(site_id %in% selected_sites)


light_response_model <- function(par, gpp, saturating_ppfd = 2000) {
  model <- function(PAR, alpha, Amax, theta) {
    # Non-rectangular hyperbola
    term <- sqrt((alpha * PAR + Amax)^2 - 4 * alpha * PAR * Amax * theta)
    return(((alpha * PAR + Amax - term) / (2 * theta)))
  }
  
  df <- data.frame(PAR = par, GPP = gpp)
  # Initial guesses
  start_vals <- list(alpha = 0.05, Amax = max(gpp, na.rm = TRUE), theta = 0.9)
  
  tryCatch({
    fit <- nls(GPP ~ model(PAR, alpha, Amax, theta), data = df,
               start = start_vals, control = nls.control(maxiter = 500))
    # predict GPP at 2000 µmol m⁻² s⁻¹
    coefs <- coef(fit)
    GPPsat <- model(saturating_ppfd, coefs["alpha"], coefs["Amax"], coefs["theta"])
    return(GPPsat)
  }, error = function(e) {
    return(NA_real_)
  })
}


#filter and prepare the data
cleaned_df <- Germany_forest %>%
  filter(!is.na(GPP_NT_VUT_REF), !is.na(PPFD_IN), PPFD_IN > 0, GPP_NT_VUT_REF > 0)

str(cleaned_df)

#check the number pf core
library(parallel)
cores <- detectCores()
print(cores)

##### split the job
site_data_list <- cleaned_df %>%
  group_by(site_id) %>%
  group_split()

library(furrr)
plan(multisession, workers = 16)
arrange(gppsat_estimates, site_id, datetime)
# Function that applies slide_index_dbl on one site
run_site_gppsat <- function(df) {
  df %>%
    arrange(datetime) %>%
    mutate(GPPsat = slide_index_dbl(
      .x = tibble(PPFD_IN = df$PPFD_IN, GPP = df$GPP_NT_VUT_REF),
      .i = df$datetime,
      .f = ~light_response_model(.x$PPFD_IN, .x$GPP),
      .before = as.difftime(2.5, units = "days"),
      .after = as.difftime(2.5, units = "days"),
      .complete = TRUE
    ))
}


gppsat_estimates <- future_map_dfr(site_data_list, run_site_gppsat, .progress = TRUE)

str(gppsat_estimates)

#write csv
write_csv(gppsat_estimates, "clean_data/GPPsat_estimates_germany.csv")
str(gppsat_estimates)
density(gppsat_estimates$GPPsat, na.rm = TRUE) %>%
  plot(main = "Density of GPPsat Estimates", xlab = "GPPsat", ylab = "Density")
# Save the results
###### Calculate NEP max based on Mirco's paper
library(dplyr)
library(lubridate)

# 1. Add NEP as -NEE
gppsat_estimates <- gppsat_estimates %>%
  mutate(
    NEP = -NEE_VUT_REF,
    date = as.Date(datetime)
  )

# 2. Compute daily GPP per site and year
daily_gpp <- gppsat_estimates %>%
  group_by(site_id, year, date) %>%
  summarise(daily_GPP = sum(GPP_NT_VUT_REF, na.rm = TRUE), .groups = "drop")

# 3. Compute annual GPP amplitude per site and year
gpp_stats <- daily_gpp %>%
  group_by(site_id, year) %>%
  summarise(
    GPP_min = min(daily_GPP, na.rm = TRUE),
    GPP_max = max(daily_GPP, na.rm = TRUE),
    GPP_amp = GPP_max - GPP_min,
    threshold = GPP_min + 0.3 * (GPP_max - GPP_min),
    .groups = "drop"
  )

# 4. Tag growing season days
daily_gpp_gs <- daily_gpp %>%
  left_join(gpp_stats, by = c("site_id", "year")) %>%
  mutate(growing_season = daily_GPP > threshold) %>%
  select(site_id, year, date, growing_season)
str(daily_gpp_gs)
# 5. Join back to half-hourly data to tag growing season records
nep_with_gs <- gppsat_estimates %>%
  left_join(daily_gpp_gs, by = c("site_id", "year", "date")) %>%
  filter(growing_season == TRUE)
str(nep_with_gs)
# 6. Compute NEPmax per site/year (90th percentile during growing season)
nepmax_summary <- nep_with_gs %>%
  group_by(site_id, year) %>%
  summarise(NEP_max = quantile(NEP, 0.9, na.rm = TRUE), .groups = "drop")

# ✅ Final output: NEPmax
nepmax_summary
# Save the NEPmax summary
write_csv(nep_with_gs, "clean_data/NEP_with_GS_Germany.csv")


library(dplyr)
str(gppsat_estimates)
# Step 1: Aggregate annual GPPsat
annual_gppsat <- gppsat_estimates %>%
  filter(!is.na(GPPsat)) %>%
  group_by(site_id, year) %>%
  summarise(GPPsat_90 = quantile(GPPsat, probs = 0.9, na.rm = TRUE), .groups = "drop")

# Step 2: Filter sites with at least 2 years before & after 2018
sites_with_full_window <- annual_gppsat %>%
  group_by(site_id) %>%
  summarise(
    has_pre2018 = sum(year < 2018) >= 1,
    has_post2018 = sum(year > 2018) >= 1
  ) %>%
  filter(has_pre2018 & has_post2018)

# Filter the annual data to only those sites
filtered_annual_gppsat <- annual_gppsat %>%
  filter(site_id %in% sites_with_full_window$site_id)

# Step 3: Calculate anomalies as deviation from site mean
gppsat_anomalies <- filtered_annual_gppsat %>%
  group_by(site_id) %>%
  mutate(
    GPPsat_mean = mean(GPPsat_90, na.rm = TRUE),
    GPPsat_anomaly = GPPsat_90 - GPPsat_mean
  ) %>%
  ungroup()

str(gppsat_anomalies)

library(ggplot2)



unique(gppsat_anomalies$site_id)
gppsat_anomalies %>% group_by(site_id) %>% summarise(n = n(), n_na = sum(is.na(GPPsat_anomaly)))
str(gppsat_anomalies$year)

gppsat_anomalies_clean <- gppsat_anomalies_clean %>%
  mutate(country = substr(site_id, 1, 2))


gppsat_anomalies_clean %>% 
  filter(site_id == "AT_Neu") %>% 
  ggplot(aes(x = year, y = GPPsat_anomaly)) +
  geom_line() +
  geom_point()

gppsat_anomalies_clean <- gppsat_anomalies %>%
  group_by(site_id) %>%
  filter(!all(is.na(GPPsat_anomaly)) & !all(GPPsat_anomaly == 0)) %>%
  ungroup()

ggplot(gppsat_anomalies, aes(x = year, y = GPPsat_anomaly, color = site_id)) +
  geom_line() +
  geom_point() +
  facet_wrap(~ country, ncol = 1, scales = "free_y") +
  geom_vline(xintercept = 2018, linetype = "dashed", color = "red") +
  labs(title = "GPPsat Anomalies by Site",
       y = "GPPsat Anomaly (µmolC/m²/year)",
       x = "Year") +
  theme_minimal()

  str(gppsat_anomalies_clean$site_id)


library(dplyr)

# Step 1: Calculate NEPmax anomalies by subtracting each site's mean
nepmax_anomalies <- nepmax_summary %>%
  group_by(site_id) %>%
  mutate(
    NEP_max_mean = mean(NEP_max, na.rm = TRUE),
    NEP_max_anomaly = NEP_max - NEP_max_mean
  ) %>%
  ungroup()

valid_nep_sites <- nepmax_anomalies %>%
  group_by(site_id) %>%
  summarise(
    has_pre2018 = sum(year < 2018) >= 1,
    has_post2018 = sum(year > 2018) >= 1
  ) %>%
  filter(has_pre2018 & has_post2018)

nepmax_anomalies_filtered <- nepmax_anomalies %>%
  filter(site_id %in% valid_nep_sites$site_id)

nepmax_anomalies_filtered <- nepmax_anomalies_filtered %>%
  mutate(country = substr(site_id, 1, 2))


ggplot(nepmax_anomalies_filtered, aes(x = year, y = NEP_max_anomaly, color = site_id)) +
  geom_line() +
  geom_point() +
  facet_wrap(~ country, ncol = 1, scales = "free_y") +
  geom_vline(xintercept = 2018, linetype = "dashed", color = "red") +
  labs(title = "NEPmax Anomalies by Site",
       y = "NEPmax Anomaly (µmolC/m²/year)",
       x = "Year") +
  theme_minimal()  

str(gppsat_estimates)
gppsat_estimates <- flux_df
#### calculate uWUE based on Mirco's paper
library(dplyr)
uwue_df <- gppsat_estimates %>%
  filter(GPP_NT_VUT_REF > 0, 
         VPD_F > 0, 
         LE_F_MDS > 0) %>%
  mutate(
    # Convert LE from W/m² to mmol H₂O m⁻² s⁻¹ (approx. 1 W/m² = 0.408 mmol m⁻² s⁻¹)
    ET = LE_F_MDS * 0.408,
    
    # uWUE in µmol CO₂ / mmol H₂O
    uWUE = GPP_NT_VUT_REF * sqrt(VPD_F) / ET
  )

str(uwue_df)
uwue_df <- uwue_df %>%
  mutate(country = substr(site_id, 1, 2))

### calculate per site and for functional property
uwue_summary <- uwue_df %>%
  group_by(site_id) %>%
  summarise(
    uWUE_median = median(uWUE, na.rm = TRUE),
    n_obs = n()
  ) %>%
  ungroup()

install.packages("data.table")
library(data.table)
library(readr)

write.csv(uwue_df, "clean_data/estimatedvariable.csv", row.names = FALSE) 
flux_df <- fread("clean_data/NEP_with_GS.csv")

str(flux_df)
#### filter the data only for Germany
germany_flux <- uwue_df 
##################################
### prepabe calculate Rb and Rbmax
library(dplyr)
library(lubridate)

# Create DoY and Hour
uwue_df_prep <- uwue_df %>%
  mutate(
    DoY = yday(datetime),
    Hour = hour(datetime) + minute(datetime) / 60
  ) %>%
  rename(
    NEE = NEE_VUT_REF,
    Tair = TA_F
  ) %>%
  select(site_id, datetime, year, DoY, Hour, NEE, Tair) %>%
  filter(!is.na(NEE), !is.na(Tair))  # REddyProc can't handle NAs

str(uwue_df_prep)
############################  
library(REddyProc)

results <- list()

for (site in unique(uwue_df_prep$site_id)) {
  cat("Processing site:", site, "\n")

  site_data <- uwue_df_prep %>%
    filter(site_id == site) %>%
    mutate(Year = year(datetime)) %>%
    select(Year, DoY, Hour, NEE, Tair)

  print(head(site_data))
  

  s <- sEddyProc$new(
    site, site_data, c("NEE", "Tair"),
    DTS = "HH"
  )

  # Estimate uStar threshold and gap-fill NEE
  s$sEstimateUstarScenarios()
  s$sMDSGapFill("NEE")

  # Partition NEE using fixed E0 (can adjust value as needed)
  s$sNEEPartitionGL_F("NEE", TempVar = "Tair", E0Fixed = 100)

  # Export daily basal respiration (Rbd) and add site_id
  df_proc <- s$sExportResults() %>%
    select(DateTime = TIMESTAMP, Rbd = RRef) %>%
    mutate(site_id = site)

  results[[site]] <- df_proc
}

rb_all <- bind_rows(results)


library(dplyr)
#calculate and visualize, GPPsat, NEPmax, VPD max and ET max for each year
yearly_extremes <- germany_flux %>%
  group_by(site_id, year) %>%
  summarise(
    GPPsat90 = quantile(GPPsat,0.9, na.rm = TRUE),
    NEPmax     = quantile(NEP, 0.9, na.rm = TRUE),
    VPDmax     = max(VPD_F, na.rm = TRUE),
    ETmax      = quantile(ET, 0.95, na.rm = TRUE),
    .groups    = "drop"
  )

str(yearly_extremes)

library(tidyr)
library(ggplot2)

# Reshape for faceted plotting
long_df <- yearly_extremes %>%
  pivot_longer(cols = c(GPPsat90, NEPmax, VPDmax, ETmax),
               names_to = "variable", values_to = "value")

ggplot(long_df, aes(x = year, y = value, color = site_id)) +
  geom_line() +
  geom_point() +
  facet_wrap(~ variable, scales = "free_y", ncol = 1) +
  theme_minimal() +
  labs(title = "Annual Maximum GPPsat, NEP, VPD, and ET per Site",
       x = "Year", y = "Value")




# Filter your actual dataframe
selected_sites <- c("DE-Hai", "DE-HoH", "DE-Obe", "DE-Har", "DE-Tha", "DE-Hzd")

unique(long_df$site_id)

filtered_long_df <- long_df %>%
  filter(site_id %in% selected_sites)


filtered_after2018 <- filtered_long_df %>%
  filter(year >= 2018)

# Plot
ggplot(filtered_after2018, aes(x = year, y = value, color = site_id)) +
  geom_line() +
  geom_point() +
  facet_wrap(~ variable, scales = "free_y", ncol = 1) +
  theme_minimal() +
  labs(title = "Annual Maximum GPPsat, NEP, VPD, and ET per Site",
       x = "Year", y = "Value")

str(filtered_long_df)

###### calculate the anomalies for before and after year 2018
library(tidyr)

yearly_extremes_after2010 <- yearly_extremes %>%
  filter(year >= 2010)

long_extremes <- yearly_extremes_after2010 %>%
  pivot_longer(cols = c(GPPsat90, NEPmax, VPDmax, ETmax), 
               names_to = "variable", 
               values_to = "value")
#calculate the Mean per site and variable excluding the year 2018
reference_means <- long_extremes %>%
  filter(year != 2018) %>%
  group_by(site_id, variable) %>%
  summarise(mean_value = mean(value, na.rm = TRUE), .groups = "drop")

#join and compute anomalies
anomalies <- long_extremes %>%
  left_join(reference_means, by = c("site_id", "variable")) %>%
  mutate(anomaly = value - mean_value)
# focus on the year 2018
anomalies_2018 <- anomalies %>% filter(year == 2018)

library(ggplot2)

ggplot(anomalies, aes(x = year, y = anomaly, color = variable)) +
  geom_line() +
  geom_point() +
  geom_vline(xintercept = 2018, linetype = "dashed", color = "#28286f") +
  geom_hline(yintercept = 0, linetype = "dotted", color = "black") +
  facet_wrap(~site_id, ncol = 2) +
  theme_minimal() +
  labs(title = "Anomalies in GPPsat, NEPmax, VPDmax, and ETmax",
       y = "Anomaly (unit matches original variable)",
       x = "Year")

ggsave("anomalies_plot_DE02.pdf", width = 8, height = 10, dpi = 300)

################
############## now calculate anomalies with the assumption that before 2018 is baseline
library(dplyr)

baseline <- long_extremes %>%
  filter(year < 2018) %>%  # Only pre-2018 years
  group_by(site_id, variable) %>%
  summarise(baseline_mean = mean(value, na.rm = TRUE), .groups = "drop")


anomalies_post2018 <- long_extremes %>%
  left_join(baseline, by = c("site_id", "variable")) %>%
  mutate(anomaly = value - baseline_mean)  # Difference from pre-2018 mean

anomalies_after2018 <- anomalies_post2018 %>%
  filter(year >= 2018)


library(ggplot2)

ggplot(anomalies_post2018, aes(x = year, y = anomaly, color = variable)) +
  geom_line() +
  geom_point() +
  geom_vline(xintercept = 2018, linetype = "dashed", color = "red") +
  geom_hline(yintercept = 0, linetype = "dotted", color = "black")+
  facet_wrap(~site_id, ncol = 2) +
  theme_minimal() +
  labs(title = "Anomalies Relative to Pre-2018 Baseline",
       y = "Anomaly (vs pre-2018 mean)",
       x = "Year")
ggsave("anomalies_plot_pre2018_DE02.pdf", width = 8, height = 10, dpi = 300)

