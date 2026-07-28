[README.md](https://github.com/user-attachments/files/30440483/README.md)

# nz-estuary-tidal-position

Code and data for a national synthesis of coastal wetland tidal position (STPI) across 47 New Zealand estuaries — LiDAR elevation, TELEMAC tidal modelling, and ordinal regression, accompanying Stewart-Sinclair et al., *Estuarine, Coastal and Shelf Science* (manuscript YECSS-D-26-00570).

## Citation

If you use this code or data, please cite the accompanying paper [FULL CITATION — add once accepted] and this repository:

[ZENODO DOI BADGE / CITATION — add after first release]

## Pipeline overview

Data flows through four numbered steps. Each script's header comment documents its inputs, outputs, and any assumptions.

| Step | Script | Input | Output |
|---|---|---|---|
| 1 | `scripts/python/01_clip_dem_to_habitat.py` | National 1 m DEM (external), habitat shapefiles (external) | Clipped per-estuary/habitat rasters (external, not archived here) |
| 2 | `scripts/python/02_sample_dem_at_habitat_pixels.py` | Clipped rasters, habitat shapefiles | `data/raw/habitat_samples/*.csv` — one row per sampled pixel |
| 3 | `scripts/r/03_ordinal_regression_boundaries.R` | `data/raw/habitat_samples/` | `data/processed/03_habitat_elevation_boundaries.csv`, `data/processed/03_table_s4_regression_model_summary.csv` |
| 4 | `scripts/r/04_tidal_datum_summary.R` | `data/raw/tidal_stats/` | `data/processed/04_tidal_datum_summary.csv` |
| 5 | *(manual, in Excel)* | Outputs of steps 3 and 4 | `data/processed/05_STPI_calculations_by_estuary.xlsx` — final STPI values (Tables 1–3 in the manuscript) |

Step 3 performs its own outlier removal (1.5×IQR per habitat class) and habitat-frequency weighting inline; it does not depend on any other cleaning step.

## Repository structure

```
scripts/
  python/     ArcPy scripts (steps 1-2)
  r/          R scripts (steps 3-4)
data/
  external/   Not tracked in this repository — see "External data" below
  raw/        Per-pixel and per-node CSVs (steps 2 and pre-4 inputs)
  processed/  Final analysis-ready outputs (steps 3-5)
```

## External data (not included in this repository)

- **National 1 m DEM**: LINZ New Zealand LiDAR 1m DEM. Vertical datum NZVD2016; vertical accuracy ±0.2 m (95%), horizontal accuracy ±1.0 m (95%); surveys acquired 2005–present. Licensed CC BY 4.0. https://data.linz.govt.nz/layer/121859-new-zealand-lidar-1m-dem/
- **Habitat polygons** (seagrass, mangroves, saltmarsh): Bulmer et al. (2024), *Restoration Ecology* 32. Blue carbon habitats in Aotearoa New Zealand.
- **NZ Tide Model (NZTIDE)**: TELEMAC-2D national tide model. See Reeve (2019) and Reeve & Wadhwa (2021) for model calibration and validation.

Expected local paths for scripts 1–2 (create these folders locally; not tracked in git — see `.gitignore`):
```
data/external/dem/                 — national DEM mosaic
data/external/habitat_shapefiles/  — per-estuary, per-habitat polygons
data/external/dem_clipped/         — output of script 01
```

## Excluded estuaries

Three estuaries were excluded from the final 47-estuary dataset (see manuscript Methods > Study areas and `05_STPI_calculations_by_estuary.xlsx`, sheet `excluded_estuaries`):

- **Patterson Inlet / Big Glory Bay** — habitat elevation data were entirely invalid (-9999 fill value)
- **Blueskin Bay** — TELEMAC tidal statistics were anomalous and could not be interpreted with confidence
- **Jacobs River** — only saltmarsh habitat was mapped; no second habitat class was present, so no elevation transition boundary could be estimated

## Key methodological notes

- **Seagrass lower and saltmarsh upper STPI boundaries are imposed analytical limits** (fixed at LAT and HAT respectively), not regression-estimated transitions. The seagrass-mangrove, mangrove-saltmarsh, and seagrass-saltmarsh (no-mangrove estuaries) boundaries are genuine regression-estimated transitions.
- **TELEMAC node averaging** (HAT/LAT per estuary) is a simple, unweighted mean of model nodes within each estuary boundary — not area-weighted.
- **Mean Tide Level (MTL)** is approximated as mean sea level (0 m on NZVD2016) throughout, not calculated directly from the tide model. See `05_STPI_calculations_by_estuary.xlsx`, sheet `README`, and the manuscript's supplementary material for a sensitivity check on this approximation.

## License

Code: MIT (see `LICENSE`). Processed data (CSVs and the STPI workbook): CC BY 4.0, consistent with the licensing of the source LINZ DEM.

## Contact

Dr Phoebe Stewart-Sinclair, James Cook University — [email/ORCID — add]
