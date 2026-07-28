# 04_tidal_datum_summary.R
#
# Summarises per-node TELEMAC-2D tidal model output (Highest Astronomical
# Tide, Lowest Astronomical Tide, and MHWS10) for each estuary as a simple
# (unweighted) mean, min, max, and node count. Node values are not
# area-weighted (see manuscript Methods and response to reviewers).
#
# Input:
#   data/raw/tidal_stats/*.csv  — one CSV per estuary, one row per TELEMAC
#   model node, with columns including hat, lat, mhws10
#
# Outputs:
#   data/processed/tidal_summaries/{estuary}_summary.csv  — per-estuary summary
#   data/processed/combined_summary.csv                    — all estuaries combined

# Set the folder path
folder_path <- "data/raw/tidal_stats"

# List all .csv files in the folder
csv_files <- list.files(path = folder_path, pattern = "\\.csv$", full.names = TRUE)

# Read each CSV into a list of data frames
data_list <- lapply(csv_files, read.csv)

# Optionally, name each data frame in the list using the file names (without extension)
names(data_list) <- tools::file_path_sans_ext(basename(csv_files))

# Define which columns you want to summarise
columns_of_interest <- c("mhws10", "hat", "lat")

# Calculate summary statistics for those columns in each dataframe
summary_list <- lapply(data_list, function(df) {
  # Keep only the specific columns that are numeric and present in the data frame
  cols <- intersect(columns_of_interest, names(df))
  num_df <- df[cols]
  
  # Apply summary functions
  data.frame(
    Column = cols,
    Mean = sapply(num_df, mean, na.rm = TRUE),
    Min  = sapply(num_df, min, na.rm = TRUE),
    Max  = sapply(num_df, max, na.rm = TRUE),
    row.names = NULL
  )
})

# Set output folder (adjust as needed)
output_folder <- "data/processed/tidal_summaries"

# Create the folder if it doesn't exist
if (!dir.exists(output_folder)) {
  dir.create(output_folder, recursive = TRUE)
}

# Write each summary to a CSV file
invisible(lapply(names(summary_list), function(name) {
  out_file <- file.path(output_folder, paste0(name, "_summary.csv"))
  write.csv(summary_list[[name]], out_file, row.names = FALSE)
}))

# Combine all summaries into one data frame
combined_summary <- do.call(rbind, lapply(names(summary_list), function(name) {
  summary_df <- summary_list[[name]]
  summary_df$Source <- name  # Add a column for the original file name
  return(summary_df)
}))

#get observation counts 
obs_counts <- sapply(data_list, nrow)

# Rebuild combined summary with obs count added
combined_summary <- do.call(rbind, lapply(names(summary_list), function(name) {
  summary_df <- summary_list[[name]]
  summary_df$Source <- name
  summary_df$N_Obs <- obs_counts[[name]]  # Add observation count
  return(summary_df)
}))

# Set the output file path
output_file <- "data/processed/combined_summary.csv"

# Write the combined summary to a CSV file
write.csv(combined_summary, output_file, row.names = FALSE)


