"""
01_clip_dem_to_habitat.py

Clips the national 1 m coastal LiDAR DEM (LINZ, 2026) to every habitat
polygon (seagrass / mangroves / saltmarsh, per estuary), producing one
clipped elevation raster per estuary/habitat combination.

Loops over every shapefile found under data/external/habitat_shapefiles/,
clipping the same national DEM mosaic against each. Skips a shapefile if
its output raster already exists, and writes a run log.

Inputs (not included in this repository — see README):
  - National 1 m DEM mosaic (LINZ New Zealand LiDAR 1m DEM, CC BY 4.0)
    https://data.linz.govt.nz/layer/121859-new-zealand-lidar-1m-dem/
    expected at data/external/dem/NZ_DEM_Mosaic
  - Per-estuary, per-habitat polygon shapefiles (seagrass / mangroves /
    saltmarsh), from Bulmer et al. (2024), expected under
    data/external/habitat_shapefiles/{estuary}/*.shp

Outputs:
  - data/external/dem_clipped/{estuary}/{shapefile_name}.tif — one clipped
    raster per habitat polygon
  - data/external/dem_clipped/clip_log.txt — run log
"""

import arcpy
from arcpy.sa import ExtractByMask
import os
import datetime

# Enable Spatial Analyst
arcpy.CheckOutExtension("Spatial")
arcpy.env.overwriteOutput = True

# ---------------------------------------------------------------------
# Paths (relative to repository root)
# ---------------------------------------------------------------------
IN_MOSAIC = r"data/external/dem/NZ_DEM_Mosaic"
SHAPEFILE_ROOT = r"data/external/habitat_shapefiles"
OUTPUT_ROOT = r"data/external/dem_clipped"

os.makedirs(OUTPUT_ROOT, exist_ok=True)
log_file = os.path.join(OUTPUT_ROOT, "clip_log.txt")

with open(log_file, "a", encoding="utf-8") as log:
    log.write("\n--- Run started: {} ---\n".format(datetime.datetime.now()))

    # Walk every estuary subfolder and clip each habitat shapefile found
    for root, _, files in os.walk(SHAPEFILE_ROOT):
        for f in files:
            if not f.lower().endswith(".shp"):
                continue

            shp_path = os.path.join(root, f)
            shp_name = os.path.splitext(f)[0]

            # Mirror the estuary subfolder structure in the output
            estuary_subdir = os.path.relpath(root, SHAPEFILE_ROOT)
            out_dir = os.path.join(OUTPUT_ROOT, estuary_subdir)
            os.makedirs(out_dir, exist_ok=True)
            out_raster = os.path.join(out_dir, f"{shp_name}.tif")

            try:
                # Skip if output already exists
                if arcpy.Exists(out_raster):
                    msg = f"Skipping {shp_name} (already exists)."
                    print(msg)
                    log.write(msg + "\n")
                    continue

                msg = f"Clipping with {shp_name}..."
                print(msg)
                log.write(msg + "\n")

                clipped = ExtractByMask(IN_MOSAIC, shp_path)
                clipped.save(out_raster)

                msg = f"Saved: {out_raster}"
                print(msg)
                log.write(msg + "\n")

            except Exception as e:
                msg = f"Failed on {shp_name}: {e}"
                print(msg)
                log.write(msg + "\n")

    log.write("--- Run finished: {} ---\n".format(datetime.datetime.now()))
