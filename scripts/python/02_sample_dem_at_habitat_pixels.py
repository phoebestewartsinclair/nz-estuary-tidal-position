"""
02_sample_dem_at_habitat_pixels.py

Samples the clipped DEM (output of 01_clip_dem_to_habitat.py) at every 1x1 m
pixel within each habitat polygon, for every estuary and habitat type.
Writes one CSV per estuary/habitat combination, each containing the
elevation of every sampled pixel.

Production version — loops over all shapefiles and matching DEM rasters,
with pre-checks (spatial reference match, extent overlap, band count) and a
run log. This is the script referenced in the manuscript's Methods and
Supplementary S1.2.

Inputs (not included in this repository — see README):
  - data/external/habitat_shapefiles/  — per-estuary, per-habitat polygons
  - data/external/dem_clipped/         — clipped DEMs, output of script 01

Outputs:
  - data/raw/habitat_samples/{estuary}_{habitat}_sample.csv  — one row per
    sampled pixel, elevation in the BCE/DEM-named column
  - data/raw/habitat_samples/sampling_log.csv                — run log
"""

import arcpy
import os
import pandas as pd

# ---------------------------------------------------------------------
# Paths (relative to repository root)
# ---------------------------------------------------------------------
SHAPEFILE_ROOT = r"data/external/habitat_shapefiles"
DEM_ROOT = r"data/external/dem_clipped"
OUT_CSV_FOLDER = r"data/raw/habitat_samples"
LOG_CSV = os.path.join(OUT_CSV_FOLDER, "sampling_log.csv")

arcpy.CheckOutExtension("Spatial")
arcpy.env.overwriteOutput = True

os.makedirs(OUT_CSV_FOLDER, exist_ok=True)

# --- Collect shapefiles ---
shapefiles = {}
for root, _, files in os.walk(SHAPEFILE_ROOT):
    for f in files:
        if f.lower().endswith(".shp"):
            shapefiles[os.path.splitext(f)[0]] = os.path.join(root, f)

# --- Collect DEM rasters ---
dems = {}
for root, _, files in os.walk(DEM_ROOT):
    for f in files:
        if f.lower().endswith((".tif", ".img", ".asc")):
            dems[os.path.splitext(f)[0]] = os.path.join(root, f)

# --- Logging ---
log_records = []

# --- Loop through shapefiles ---
for name, shapefile in shapefiles.items():
    if name not in dems:
        msg = f"No matching DEM found for {name}"
        print("Skipped:", msg)
        log_records.append([name, shapefile, None, "SKIPPED", msg])
        continue

    dem_raster = dems[name]
    print(f"\nProcessing: {name}")
    print(f"   Shapefile: {shapefile}")
    print(f"   DEM: {dem_raster}")

    # --- Pre-checks ---
    try:
        shp_desc = arcpy.Describe(shapefile)
        dem_desc = arcpy.Describe(dem_raster)

        shp_sr = getattr(shp_desc, "spatialReference", None)
        dem_sr = getattr(dem_desc, "spatialReference", None)

        if shp_sr and dem_sr:
            if shp_sr.name != dem_sr.name:
                print(f"Warning: spatial reference mismatch: {shp_sr.name} vs {dem_sr.name}")
        else:
            print("Warning: could not read spatial reference for one of the datasets")

        # Extent overlap
        shp_ext = shp_desc.extent
        dem_ext = dem_desc.extent
        if (shp_ext.XMax < dem_ext.XMin or shp_ext.XMin > dem_ext.XMax or
                shp_ext.YMax < dem_ext.YMin or shp_ext.YMin > dem_ext.YMax):
            msg = "Shapefile is completely outside DEM extent. Skipping..."
            print("Skipped:", msg)
            log_records.append([name, shapefile, dem_raster, "SKIPPED", msg])
            continue

        # Raster band check
        raster_obj = arcpy.Raster(dem_raster)
        if raster_obj.bandCount > 1:
            print(f"DEM {name} has {raster_obj.bandCount} bands, using Band_1")
            dem_raster = dem_raster + "/Band_1"

    except Exception as e:
        msg = f"Error during pre-check: {e}"
        print("Failed:", msg)
        log_records.append([name, shapefile, dem_raster, "FAILED", msg])
        continue

    # --- Run Sample ---
    temp_dbf = os.path.join(OUT_CSV_FOLDER, f"{name}_tbl.dbf")
    csv_path = os.path.join(OUT_CSV_FOLDER, f"{name}_sample.csv")

    try:
        arcpy.sa.Sample(
            in_rasters=dem_raster,
            in_location_data=shapefile,
            out_table=temp_dbf,
            resampling_type="NEAREST"
        )

        # Convert DBF to pandas DataFrame
        arr = arcpy.da.TableToNumPyArray(temp_dbf, "*")
        df = pd.DataFrame(arr)
        df.to_csv(csv_path, index=False)
        print(f"Saved CSV: {csv_path}")

        log_records.append([name, shapefile, dem_raster, "SUCCESS", "OK"])

    except Exception as e:
        msg = f"Sample failed: {e}"
        print("Failed:", msg)
        log_records.append([name, shapefile, dem_raster, "FAILED", msg])

    finally:
        # Clean up temp DBF
        if arcpy.Exists(temp_dbf):
            arcpy.management.Delete(temp_dbf)

# --- Save log ---
log_df = pd.DataFrame(log_records, columns=["Name", "Shapefile", "DEM", "Status", "Message"])
log_df.to_csv(LOG_CSV, index=False)
print(f"\nLog saved to: {LOG_CSV}")
