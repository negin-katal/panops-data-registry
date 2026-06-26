library(data.table)
library(ranger)
library(fastshap)

# -------------------------------
# Load saved workspace
# -------------------------------
load("derived_tables/checkpoints/workspace_partial.RData")

cat("Workspace loaded.\n")

# -------------------------------
# Load dataset again (safe)
# -------------------------------
dt <- fread("derived_tables/modeldata_MASTER_complete_3yr_lag24_anomlag12.csv")

# -------------------------------
# Make sure group_map exists
# -------------------------------
if (!exists("group_map")) {
  group_map <- data.table(variable = all_predictors)
  
  group_map[, group := fifelse(variable %in% lag24_vars, "Meteo",
                        fifelse(variable %in% trait_vars, "Traits",
                        fifelse(variable %in% deadwood_vars, "Deadwood",
                        fifelse(variable %in% memory_vars, "Memory",
                        "Other"))))]
}

# -------------------------------
# Continue ONLY missing parts
# -------------------------------

response_vars <- c("uWUE", "ETmax", "GPPsat", "NEPmax")
igbp_levels <- sort(unique(na.omit(dt$IGBP)))

results_list <- list()
k <- 1

for (resp in response_vars) {
  for (ig in igbp_levels) {
    
    id_label <- paste0("IGBP_", ig)
    
    cat("\n", format(Sys.time(), "%H:%M:%S"),
        "- Running:", id_label, "|", resp, "\n")
    
    d_sub <- dt[IGBP == ig]
    
    res <- compute_grouped_shap(
      data_subset = d_sub,
      response_var = resp,
      id_label = id_label,
      nsim = 20,  # reduced for speed
      num_trees = 500,
      min_rows = 20,
      min_sites = 5
    )
    
    if (!is.null(res)) {
      results_list[[k]] <- res
      
      # ✅ checkpoint save EVERY iteration
      fwrite(res,
        paste0("derived_tables/checkpoints/shap_", resp, "_", ig, ".csv")
      )
      
      k <- k + 1
    }
  }
}

# combine final
shap_by_igbp <- rbindlist(results_list, fill = TRUE)

fwrite(shap_by_igbp,
       "derived_tables/grouped_shap_by_igbp_FINAL.csv")

cat("\nDone.\n")