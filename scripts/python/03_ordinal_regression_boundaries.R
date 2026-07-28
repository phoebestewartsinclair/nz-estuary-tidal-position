# 03_ordinal_regression_boundaries.R
#
# Estimates habitat elevation boundaries (seagrass-mangrove,
# mangrove-saltmarsh, or seagrass-saltmarsh) for each estuary using weighted
# ordinal (three-habitat) or binomial (two-habitat) logistic regression on
# per-pixel DEM elevation samples. Performs its own IQR-based outlier
# removal per habitat class (this is the authoritative cleaning step used
# for the manuscript's results - it does not depend on the output of
# utility_combine_samples_by_group.R).
#
# Reads directly from the raw sample output of
# 02_sample_dem_at_habitat_pixels.py.
#
# Outputs:
#   data/processed/Habitat_boundaries_per_estuary_ordinal_regression_weighted.csv
#   data/processed/Table_S5_ordinal_regression_model_summary.csv
#   figures/ordinal_regression_plots/*.pdf

########################## Ordinal regression #############################

library(MASS)      # polr
library(data.table)

# ---------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------
# Paths relative to repository root
input_dir  <- "data/raw/habitat_samples"
output_dir <- "data/processed"
plot_dir   <- file.path("figures", "ordinal_regression_plots")

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
if (!dir.exists(plot_dir)) dir.create(plot_dir, recursive = TRUE)

# ---------------------------------------------------------------------
# Read file list
# ---------------------------------------------------------------------
setwd(input_dir)
f_all <- list.files(pattern = "\\.csv$")
f_SG  <- f_all[f_all %like% "Seagrass"]

# get estuary names from filenames
Estuaries <- f_SG
for (i in seq_along(f_SG)) {
  Estuaries[i] <- substr(
    f_SG[i],
    nchar("BCE_") + 1,
    nchar(f_SG[i]) - nchar("_Seagrass_sample.csv")
  )
}

# Patterson Inlet has only -9999 so remove from list
Estuaries <- Estuaries[!Estuaries %like% "Patterson_Inlet_Big_Glory_Bay"]

# ---------------------------------------------------------------------
# Helper for safe filenames
# ---------------------------------------------------------------------
safe_name <- function(x) {
  gsub("[^A-Za-z0-9_\\-]", "_", x)
}

# ---------------------------------------------------------------------
# First pass: calculate global x/y limits for consistent plotting
# ---------------------------------------------------------------------
global_xmin <- Inf
global_xmax <- -Inf
global_ymax <- 0

for (i in seq_along(Estuaries)) {
  setwd(input_dir)
  f <- f_all[f_all %like% Estuaries[i]]
  
  if (length(f[f %like% "Mangroves"]) != 0) {
    f1 <- read.csv(f[f %like% "Seagrass"])
    f1 <- as.data.frame(f1[, colnames(f1) %like% "BCE|DEM"])
    colnames(f1) <- "NZ_DEM_Mos"
    f1$habitat <- "Seagrass"
    
    f2 <- read.csv(f[f %like% "Mangroves"])
    f2 <- as.data.frame(f2[, colnames(f2) %like% "BCE|DEM"])
    colnames(f2) <- "NZ_DEM_Mos"
    f2$habitat <- "Mangroves"
    
    f3 <- read.csv(f[f %like% "Saltmarsh"])
    f3 <- as.data.frame(f3[, colnames(f3) %like% "BCE|DEM"])
    colnames(f3) <- "NZ_DEM_Mos"
    f3$habitat <- "Saltmarsh"
    
    DF <- rbind(f1, f2, f3)
  } else {
    f1 <- read.csv(f[f %like% "Seagrass"])
    f1 <- as.data.frame(f1[, colnames(f1) %like% "BCE|DEM"])
    colnames(f1) <- "NZ_DEM_Mos"
    f1$habitat <- "Seagrass"
    
    f3 <- read.csv(f[f %like% "Saltmarsh"])
    f3 <- as.data.frame(f3[, colnames(f3) %like% "BCE|DEM"])
    colnames(f3) <- "NZ_DEM_Mos"
    f3$habitat <- "Saltmarsh"
    
    DF <- rbind(f1, f3)
  }
  
  DF <- DF[DF$NZ_DEM_Mos > -9000, ]
  DF <- DF[!is.na(DF$NZ_DEM_Mos), ]
  
  global_xmin <- min(global_xmin, min(DF$NZ_DEM_Mos))
  global_xmax <- max(global_xmax, max(DF$NZ_DEM_Mos))
  
  h <- hist(DF$NZ_DEM_Mos, breaks = 40, plot = FALSE)
  global_ymax <- max(global_ymax, max(h$density, na.rm = TRUE))
  
  for (hab in unique(DF$habitat)) {
    vals <- DF$NZ_DEM_Mos[DF$habitat == hab]
    if (length(unique(vals)) > 1) {
      d <- density(vals)
      global_ymax <- max(global_ymax, max(d$y, na.rm = TRUE))
    }
  }
}

# little buffer
global_ymax <- global_ymax * 1.15

# ---------------------------------------------------------------------
# Output tables
# ---------------------------------------------------------------------
Bnds_DF <- data.frame(matrix(NA, nrow = length(Estuaries), ncol = 4))
colnames(Bnds_DF) <- c(
  "Estuary",
  "Seagrass|Mangroves",
  "Mangroves|Saltmarsh",
  "Seagrass|Saltmarsh"
)

S5_DF <- data.frame(
  Estuary = character(),
  Mangroves_present = character(),
  Model = character(),
  n_total_clean = numeric(),
  n_seagrass_clean = numeric(),
  n_mangroves_clean = numeric(),
  n_saltmarsh_clean = numeric(),
  outliers_seagrass = numeric(),
  outliers_mangroves = numeric(),
  outliers_saltmarsh = numeric(),
  boundary1_m = numeric(),
  boundary2_m = numeric(),
  AIC = numeric(),
  logLik = numeric(),
  accuracy = numeric(),
  stringsAsFactors = FALSE
)

# ---------------------------------------------------------------------
# Lists for combined multi-panel plotting
# ---------------------------------------------------------------------
plot_data_yes <- list()
plot_data_no  <- list()

# ---------------------------------------------------------------------
# Loop through estuaries
# ---------------------------------------------------------------------
for (i in seq_along(Estuaries)) {
  
  setwd(input_dir)
  f <- f_all[f_all %like% Estuaries[i]]
  
  if (length(f[f %like% "Mangroves"]) != 0) {   # ---------------- 3 habitats
    
    f1 <- read.csv(f[f %like% "Seagrass"])
    f1 <- as.data.frame(f1[, colnames(f1) %like% "BCE|DEM"])
    colnames(f1) <- "NZ_DEM_Mos"
    f1$habitat <- "Seagrass"
    
    f2 <- read.csv(f[f %like% "Mangroves"])
    f2 <- as.data.frame(f2[, colnames(f2) %like% "BCE|DEM"])
    colnames(f2) <- "NZ_DEM_Mos"
    f2$habitat <- "Mangroves"
    
    f3 <- read.csv(f[f %like% "Saltmarsh"])
    f3 <- as.data.frame(f3[, colnames(f3) %like% "BCE|DEM"])
    colnames(f3) <- "NZ_DEM_Mos"
    f3$habitat <- "Saltmarsh"
    
    DF <- rbind(f1, f2, f3)
    
    DF <- DF[DF$NZ_DEM_Mos > -9000, ]
    DF <- DF[!is.na(DF$NZ_DEM_Mos), ]
    
    cat("\n")
    print(paste("################################  ", Estuaries[i], "  ############################"))
    
    DF$hab_ord <- factor(
      DF$habitat,
      levels = c("Seagrass", "Mangroves", "Saltmarsh"),
      ordered = TRUE
    )
    
    DF$outlier <- FALSE
    
    for (cl in levels(DF$hab_ord)) {
      vals <- DF$NZ_DEM_Mos[DF$hab_ord == cl]
      
      Q1 <- quantile(vals, 0.25)
      Q3 <- quantile(vals, 0.75)
      IQR_val <- Q3 - Q1
      lower <- Q1 - 1.5 * IQR_val
      upper <- Q3 + 1.5 * IQR_val
      
      idx <- which(
        DF$hab_ord == cl &
          (DF$NZ_DEM_Mos < lower | DF$NZ_DEM_Mos > upper)
      )
      DF$outlier[idx] <- TRUE
    }
    
    cat("\n")
    print("********* Outliers **********")
    print(table(DF$habitat, DF$outlier))
    
    out_sg <- sum(DF$habitat == "Seagrass"  & DF$outlier)
    out_mg <- sum(DF$habitat == "Mangroves" & DF$outlier)
    out_sm <- sum(DF$habitat == "Saltmarsh" & DF$outlier)
    
    DF_clean <- subset(DF, outlier == FALSE)
    
    NN   <- nrow(DF_clean)
    N_SG <- nrow(DF_clean[DF_clean$habitat == "Seagrass", ])
    N_MG <- nrow(DF_clean[DF_clean$habitat == "Mangroves", ])
    N_SM <- nrow(DF_clean[DF_clean$habitat == "Saltmarsh", ])
    
    DF_clean$weight <- 1
    DF_clean[DF_clean$habitat == "Seagrass",  "weight"] <- NN / N_SG
    DF_clean[DF_clean$habitat == "Mangroves", "weight"] <- NN / N_MG
    DF_clean[DF_clean$habitat == "Saltmarsh", "weight"] <- NN / N_SM
    
    fit_polr <- polr(
      hab_ord ~ NZ_DEM_Mos,
      data = DF_clean,
      weights = DF_clean$weight,
      Hess = TRUE
    )
    summary(fit_polr)
    
    x_grid <- seq(
      min(DF_clean$NZ_DEM_Mos),
      max(DF_clean$NZ_DEM_Mos),
      length.out = 1000
    )
    pred_df <- data.frame(NZ_DEM_Mos = x_grid)
    probs <- predict(fit_polr, newdata = pred_df, type = "prob")
    
    max_cat <- apply(probs, 1, which.max)
    boundaries <- x_grid[c(FALSE, diff(max_cat) != 0)]
    
    cat("\n")
    print("********* Boundaries **********")
    print(boundaries)
    
    Bnds_DF$Estuary[i] <- Estuaries[i]
    Bnds_DF$`Seagrass|Mangroves`[i] <- boundaries[1]
    Bnds_DF$`Mangroves|Saltmarsh`[i] <- boundaries[2]
    
    # ---- save plot to PDF ----
    plot_file <- file.path(plot_dir, paste0(safe_name(Estuaries[i]), "_ordinal_regression.pdf"))
    pdf(plot_file, width = 8, height = 6)
    
    cols <- c("Seagrass" = "darkgreen", "Mangroves" = "black", "Saltmarsh" = "red")
    
    hist(
      DF_clean$NZ_DEM_Mos,
      breaks = 40,
      col = rgb(0.8, 0.8, 0.8, 0.4),
      border = NA,
      freq = FALSE,
      xlim = c(global_xmin, global_xmax),
      ylim = c(0, global_ymax),
      xlab = "Elevation (m)",
      ylab = "Density / Probability",
      main = Estuaries[i]
    )
    
    # habitat densities
    for (hab in c("Seagrass", "Mangroves", "Saltmarsh")) {
      vals <- DF_clean$NZ_DEM_Mos[DF_clean$habitat == hab]
      if (length(unique(vals)) > 1) {
        lines(density(vals), col = cols[hab], lwd = 2)
      }
    }
    
    # model probabilities
    matlines(
      x_grid, probs,
      lty = 1,
      lwd = 2,
      col = cols[colnames(probs)]
    )
    
    # rug plots
    rug(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Seagrass"],   col = cols["Seagrass"],   ticksize = 0.02, side = 1)
    rug(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Mangroves"],  col = cols["Mangroves"],  ticksize = 0.04, side = 1)
    rug(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Saltmarsh"],  col = cols["Saltmarsh"],  ticksize = 0.06, side = 1)
    
    abline(v = boundaries, lty = 2, col = "black", lwd = 2)
    
    legend(
      "topright",
      legend = c(
        "Seagrass density", "Mangroves density", "Saltmarsh density",
        "Seagrass model", "Mangroves model", "Saltmarsh model",
        "Boundary"
      ),
      col = c(cols["Seagrass"], cols["Mangroves"], cols["Saltmarsh"],
              cols["Seagrass"], cols["Mangroves"], cols["Saltmarsh"],
              "black"),
      lty = c(1,1,1,1,1,1,2),
      lwd = c(2,2,2,2,2,2,2),
      bty = "n",
      cex = 0.8
    )
    
    dev.off()
    
    # store for combined plots
    plot_data_yes[[length(plot_data_yes) + 1]] <- list(
      estuary = Estuaries[i],
      DF_clean = DF_clean,
      x_grid = x_grid,
      probs = probs,
      boundaries = boundaries
    )
    
    pred_class <- predict(fit_polr, newdata = DF_clean, type = "class")
    cat("\n")
    print("********* Confusion matrix **********")
    cm <- table(True = DF_clean$habitat, Predicted = pred_class)
    print(cm)
    
    acc <- sum(diag(cm)) / sum(cm)
    
    S5_DF <- rbind(
      S5_DF,
      data.frame(
        Estuary = Estuaries[i],
        Mangroves_present = "Yes",
        Model = "Ordinal logistic",
        n_total_clean = NN,
        n_seagrass_clean = N_SG,
        n_mangroves_clean = N_MG,
        n_saltmarsh_clean = N_SM,
        outliers_seagrass = out_sg,
        outliers_mangroves = out_mg,
        outliers_saltmarsh = out_sm,
        boundary1_m = boundaries[1],
        boundary2_m = boundaries[2],
        AIC = AIC(fit_polr),
        logLik = as.numeric(logLik(fit_polr)),
        accuracy = acc
      )
    )
    
  } else {   # ----------------------------------------------- 2 habitats only
    
    f1 <- read.csv(f[f %like% "Seagrass"])
    f1 <- as.data.frame(f1[, colnames(f1) %like% "BCE|DEM"])
    colnames(f1) <- "NZ_DEM_Mos"
    f1$habitat <- "Seagrass"
    
    f3 <- read.csv(f[f %like% "Saltmarsh"])
    f3 <- as.data.frame(f3[, colnames(f3) %like% "BCE|DEM"])
    colnames(f3) <- "NZ_DEM_Mos"
    f3$habitat <- "Saltmarsh"
    
    DF <- rbind(f1, f3)
    
    DF <- DF[DF$NZ_DEM_Mos > -9000, ]
    DF <- DF[!is.na(DF$NZ_DEM_Mos), ]
    
    cat("\n")
    print(paste("################################  ", Estuaries[i], "  ############################"))
    
    DF$hab_ord <- factor(
      DF$habitat,
      levels = c("Seagrass", "Saltmarsh"),
      ordered = TRUE
    )
    
    DF$outlier <- FALSE
    
    for (cl in levels(DF$hab_ord)) {
      vals <- DF$NZ_DEM_Mos[DF$hab_ord == cl]
      
      Q1 <- quantile(vals, 0.25)
      Q3 <- quantile(vals, 0.75)
      IQR_val <- Q3 - Q1
      lower <- Q1 - 1.5 * IQR_val
      upper <- Q3 + 1.5 * IQR_val
      
      idx <- which(
        DF$hab_ord == cl &
          (DF$NZ_DEM_Mos < lower | DF$NZ_DEM_Mos > upper)
      )
      DF$outlier[idx] <- TRUE
    }
    
    cat("\n")
    print("********* Outliers **********")
    print(table(DF$habitat, DF$outlier))
    
    out_sg <- sum(DF$habitat == "Seagrass" & DF$outlier)
    out_sm <- sum(DF$habitat == "Saltmarsh" & DF$outlier)
    
    DF_clean <- subset(DF, outlier == FALSE)
    
    NN   <- nrow(DF_clean)
    N_SG <- nrow(DF_clean[DF_clean$habitat == "Seagrass", ])
    N_SM <- nrow(DF_clean[DF_clean$habitat == "Saltmarsh", ])
    
    DF_clean$weight <- 1
    DF_clean[DF_clean$habitat == "Seagrass", "weight"] <- NN / N_SG
    DF_clean[DF_clean$habitat == "Saltmarsh", "weight"] <- NN / N_SM
    
    fit_glm <- glm(
      hab_ord ~ NZ_DEM_Mos,
      data = DF_clean,
      family = binomial,
      weights = DF_clean$weight
    )
    summary(fit_glm)
    
    x_grid <- seq(
      min(DF_clean$NZ_DEM_Mos),
      max(DF_clean$NZ_DEM_Mos),
      length.out = 1000
    )
    pred_df <- data.frame(NZ_DEM_Mos = x_grid)
    probs <- predict(fit_glm, newdata = pred_df, type = "response")
    probs2 <- cbind(Seagrass = 1 - probs, Saltmarsh = probs)
    
    boundaries <- -coef(fit_glm)[1] / coef(fit_glm)[2]
    
    cat("\n")
    print("********* Boundaries **********")
    print(as.numeric(boundaries))
    
    Bnds_DF$Estuary[i] <- Estuaries[i]
    Bnds_DF$`Seagrass|Saltmarsh`[i] <- boundaries[1]
    
    # ---- save plot to PDF ----
    plot_file <- file.path(plot_dir, paste0(safe_name(Estuaries[i]), "_binomial_regression.pdf"))
    pdf(plot_file, width = 8, height = 6)
    
    cols <- c("Seagrass" = "darkgreen", "Saltmarsh" = "red")
    
    hist(
      DF_clean$NZ_DEM_Mos,
      breaks = 40,
      col = rgb(0.8, 0.8, 0.8, 0.4),
      border = NA,
      freq = FALSE,
      xlim = c(global_xmin, global_xmax),
      ylim = c(0, global_ymax),
      xlab = "Elevation (m)",
      ylab = "Density / Probability",
      main = Estuaries[i]
    )
    
    if (length(unique(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Seagrass"])) > 1) {
      lines(density(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Seagrass"]),
            col = cols["Seagrass"], lwd = 2)
    }
    if (length(unique(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Saltmarsh"])) > 1) {
      lines(density(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Saltmarsh"]),
            col = cols["Saltmarsh"], lwd = 2)
    }
    
    matlines(
      x_grid, probs2,
      lty = 1,
      lwd = 2,
      col = cols[colnames(probs2)]
    )
    
    rug(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Seagrass"],  col = cols["Seagrass"],  ticksize = 0.03, side = 1)
    rug(DF_clean$NZ_DEM_Mos[DF_clean$habitat == "Saltmarsh"], col = cols["Saltmarsh"], ticksize = 0.06, side = 1)
    
    abline(v = boundaries, lty = 2, col = "black", lwd = 2)
    
    legend(
      "topright",
      legend = c(
        "Seagrass density", "Saltmarsh density",
        "Seagrass model", "Saltmarsh model",
        "Boundary"
      ),
      col = c(cols["Seagrass"], cols["Saltmarsh"],
              cols["Seagrass"], cols["Saltmarsh"],
              "black"),
      lty = c(1,1,1,1,2),
      lwd = c(2,2,2,2,2),
      bty = "n",
      cex = 0.8
    )
    
    dev.off()
    
    plot_data_no[[length(plot_data_no) + 1]] <- list(
      estuary = Estuaries[i],
      DF_clean = DF_clean,
      x_grid = x_grid,
      probs2 = probs2,
      boundaries = boundaries
    )
    
    probs_pred <- predict(fit_glm, type = "response")
    pred_class <- ifelse(probs_pred > 0.5, "Saltmarsh", "Seagrass")
    
    cat("\n")
    print("********* Confusion matrix **********")
    cm <- table(True = DF_clean$habitat, Predicted = pred_class)
    print(cm)
    
    acc <- sum(diag(cm)) / sum(cm)
    
    S5_DF <- rbind(
      S5_DF,
      data.frame(
        Estuary = Estuaries[i],
        Mangroves_present = "No",
        Model = "Binomial logistic",
        n_total_clean = NN,
        n_seagrass_clean = N_SG,
        n_mangroves_clean = NA,
        n_saltmarsh_clean = N_SM,
        outliers_seagrass = out_sg,
        outliers_mangroves = NA,
        outliers_saltmarsh = out_sm,
        boundary1_m = as.numeric(boundaries[1]),
        boundary2_m = NA,
        AIC = AIC(fit_glm),
        logLik = as.numeric(logLik(fit_glm)),
        accuracy = acc
      )
    )
  }
}

# ---------------------------------------------------------------------
# Combined multi-panel PDFs
# ---------------------------------------------------------------------
if (length(plot_data_yes) > 0) {
  pdf(file.path(plot_dir, "All_estuaries_with_mangroves_combined.pdf"), width = 11, height = 14)
  par(mfrow = c(4, 3), mar = c(3, 3, 2, 1), oma = c(1, 1, 1, 1))
  for (pd in plot_data_yes) {
    cols <- c("Seagrass" = "darkgreen", "Mangroves" = "black", "Saltmarsh" = "red")
    hist(
      pd$DF_clean$NZ_DEM_Mos,
      breaks = 40,
      col = rgb(0.8, 0.8, 0.8, 0.4),
      border = NA,
      freq = FALSE,
      xlim = c(global_xmin, global_xmax),
      ylim = c(0, global_ymax),
      xlab = "Elevation",
      ylab = "Density",
      main = pd$estuary,
      cex.main = 0.8
    )
    for (hab in c("Seagrass", "Mangroves", "Saltmarsh")) {
      vals <- pd$DF_clean$NZ_DEM_Mos[pd$DF_clean$habitat == hab]
      if (length(unique(vals)) > 1) lines(density(vals), col = cols[hab], lwd = 1.5)
    }
    matlines(pd$x_grid, pd$probs, lty = 1, lwd = 1.5, col = cols[colnames(pd$probs)])
    abline(v = pd$boundaries, lty = 2, col = "black")
  }
  dev.off()
}

if (length(plot_data_no) > 0) {
  pdf(file.path(plot_dir, "All_estuaries_without_mangroves_combined.pdf"), width = 11, height = 14)
  par(mfrow = c(4, 3), mar = c(3, 3, 2, 1), oma = c(1, 1, 1, 1))
  for (pd in plot_data_no) {
    cols <- c("Seagrass" = "darkgreen", "Saltmarsh" = "red")
    hist(
      pd$DF_clean$NZ_DEM_Mos,
      breaks = 40,
      col = rgb(0.8, 0.8, 0.8, 0.4),
      border = NA,
      freq = FALSE,
      xlim = c(global_xmin, global_xmax),
      ylim = c(0, global_ymax),
      xlab = "Elevation",
      ylab = "Density",
      main = pd$estuary,
      cex.main = 0.8
    )
    if (length(unique(pd$DF_clean$NZ_DEM_Mos[pd$DF_clean$habitat == "Seagrass"])) > 1) {
      lines(density(pd$DF_clean$NZ_DEM_Mos[pd$DF_clean$habitat == "Seagrass"]),
            col = cols["Seagrass"], lwd = 1.5)
    }
    if (length(unique(pd$DF_clean$NZ_DEM_Mos[pd$DF_clean$habitat == "Saltmarsh"])) > 1) {
      lines(density(pd$DF_clean$NZ_DEM_Mos[pd$DF_clean$habitat == "Saltmarsh"]),
            col = cols["Saltmarsh"], lwd = 1.5)
    }
    matlines(pd$x_grid, pd$probs2, lty = 1, lwd = 1.5, col = cols[colnames(pd$probs2)])
    abline(v = pd$boundaries, lty = 2, col = "black")
  }
  dev.off()
}

# ---------------------------------------------------------------------
# Round outputs for cleaner export
# ---------------------------------------------------------------------
Bnds_DF$`Seagrass|Mangroves` <- round(Bnds_DF$`Seagrass|Mangroves`, 6)
Bnds_DF$`Mangroves|Saltmarsh` <- round(Bnds_DF$`Mangroves|Saltmarsh`, 6)
Bnds_DF$`Seagrass|Saltmarsh` <- round(Bnds_DF$`Seagrass|Saltmarsh`, 6)

S5_DF$boundary1_m <- round(S5_DF$boundary1_m, 6)
S5_DF$boundary2_m <- round(S5_DF$boundary2_m, 6)
S5_DF$AIC         <- round(S5_DF$AIC, 2)
S5_DF$logLik      <- round(S5_DF$logLik, 2)
S5_DF$accuracy    <- round(S5_DF$accuracy, 3)

# ---------------------------------------------------------------------
# Write outputs
# ---------------------------------------------------------------------
setwd(output_dir)

write.csv(
  Bnds_DF,
  "Habitat_boundaries_per_estuary_ordinal_regression_weighted.csv",
  row.names = FALSE
)

write.csv(
  S5_DF,
  "Table_S5_ordinal_regression_model_summary.csv",
  row.names = FALSE
)
