#!/usr/bin/env Rscript
# ============================================================================
# World map of the 93 tree-cover >=30% sites, coloured by relative mortality
# (500m), natural-break diverging scale - same colour ramp and midpoint logic
# as the dot column in Fig 3 / plot_v10_site_shap_distmetrics.R:
#   low = "#1B4965" (below NB), mid = "#F5F5F5" (at NB), high = "#C41E3A"
#   midpoint = mean + 0.5*SD (the "High" natural-break cut), same as Fig 3.
# Per-site value = max across years (matches Fig 3's site_dist aggregation).
# ============================================================================
suppressMessages({library(data.table); library(ggplot2); library(maps)})
setwd("/mnt/gsdata/projects/panops/panops-data-registry/data/flux")

B   <- "derived_tables/outputs_afterEGU_results"
OUT <- "plots/V10/site_maps"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

harm_file <- sprintf("%s/v10/v10_B1_GPPsat_harmonized.csv", B)
efp_file  <- sprintf("%s/EFP_mortality_trait_hydro_combined_with_meteo_dist_lags.csv", B)

harm <- fread(harm_file, select = c("SITE_ID", "YEAR", "relative_mortality_500m"))
v10_sites <- unique(harm$SITE_ID)
cat("tc>=30 site list:", length(v10_sites), "sites\n")

meta <- fread(efp_file, select = c("SITE_ID", "IGBP", "LOCATION_LAT", "LOCATION_LONG"))
meta <- unique(meta[SITE_ID %in% v10_sites], by = "SITE_ID")

na_inf <- function(x) { x[!is.finite(x)] <- NA; x }
dist_site <- harm[, .(rel_mort = na_inf(max(relative_mortality_500m, na.rm = TRUE))), by = SITE_ID]
sites <- merge(dist_site, meta, by = "SITE_ID", all.x = TRUE)
setnames(sites, c("LOCATION_LAT", "LOCATION_LONG"), c("LAT", "LONG"))
sites <- sites[!is.na(LAT)]
cat("sites with coordinates:", nrow(sites), "| missing rel_mort:", sum(is.na(sites$rel_mort)), "\n")

# ── same natural-break HIGH cut as Fig 3 ─────────────────────────────────────
nb_high <- mean(sites$rel_mort, na.rm = TRUE) + 0.5 * sd(sites$rel_mort, na.rm = TRUE)
max_val <- ceiling(max(sites$rel_mort, na.rm = TRUE) / 5) * 5
max_val <- max(max_val, nb_high * 2)
cat(sprintf("Natural-break HIGH cut (relative mortality) = %.2f | scale max = %.1f\n", nb_high, max_val))

world <- map_data("world")

p <- ggplot() +
  geom_polygon(data = world, aes(x = long, y = lat, group = group),
               fill = "#1C2733", colour = "#2E3F50", linewidth = 0.15) +
  geom_point(data = sites, aes(x = LONG, y = LAT, colour = rel_mort, size = rel_mort),
             shape = 16, alpha = 0.9) +
  scale_colour_gradient2(low = "#1B4965", mid = "#F5F5F5", high = "#C41E3A",
                        midpoint = nb_high, limits = c(0, max_val), na.value = "grey50",
                        name = sprintf("Relative Mortality\n(%%)  NB=%.1f", nb_high)) +
  scale_size_continuous(range = c(1.2, 5.5), limits = c(0, max_val), guide = "none") +
  coord_fixed(1.3, xlim = c(-170, 175), ylim = c(-55, 75), expand = FALSE) +
  labs(x = NULL, y = NULL) +
  theme_void(base_size = 10) +
  theme(
    # same dark theme as Fig 1's map panel (plot_v10_fig1_site_map.R)
    plot.background = element_rect(fill = "#0D1117", colour = NA),
    panel.background = element_rect(fill = "#0D1117", colour = NA),
    legend.position = "right",
    legend.title = element_text(colour = "#C9D1D9", size = 8.5),
    legend.text = element_text(colour = "#C9D1D9", size = 8),
    legend.key = element_rect(fill = NA, colour = NA),
    legend.background = element_rect(fill = NA, colour = NA),
    legend.key.height = unit(1.1, "cm")
  )

stem <- file.path(OUT, "mortality_map_tc30_natural_breaks")
ggsave(paste0(stem, ".png"), p, width = 11, height = 6, dpi = 300, bg = "#0D1117")
ggsave(paste0(stem, ".pdf"), p, width = 11, height = 6, bg = "#0D1117")
fwrite(sites[order(-rel_mort)], file.path(OUT, "mortality_map_tc30_site_values.csv"))
cat("\nSaved:", stem, ".png/.pdf\n")
cat(sprintf("Sites above the High cut (%.1f): %d / %d\n", nb_high, sum(sites$rel_mort > nb_high, na.rm=TRUE), nrow(sites)))
