# Flux Tower Data Quality Report

**Generated:** 2026-06-29 15:37 UTC  
**Dataset:** FLUXNET 2017–2025 V02  
**EFP file:** 233 sites, 1535 site-years  
**Meteo file:** 329 sites, 20664 site-months  
**Years (EFP):** 2017–2025

---
## 1. Executive Summary

### 🚨 Red Flags

- 🚨 EFP `GPPsat`: 21.5% missing
- 🚨 EFP `NEPmax`: 13.7% missing
- 🚨 EFP `uWUE`: 21.6% missing
- 🚨 EFP `WUE`: 21.6% missing
- 🚨 Physically impossible `uWUE` values: 6 site-year(s)
- 🚨 Physically impossible `WUE` values: 6 site-year(s)
- 🚨 Meteo `VPD_mean` failed `> 80 hPa (possible Pa units?)`: 60 records
- 🚨 Meteo `P_sum` failed `> 2000 mm/month`: 6 records
- 🚨 JPF: `JPF_JP-Tak_FLUXNET_1998-2021_v1.3_r1.zip` is corrupted (listed in bad_or_corrupted_zip_files.csv). Total 9 corrupted/bad zips in the dataset (1 ICOS, 8 JPF/TERN).
- 🚨 ICOS `CD-Ygb`: VPD_mean in monthly meteo up to 2109 hPa — values are in Pa (divide by 100).
- 🚨 AMF `US-HB4`: P_sum monthly values up to 39,140 mm/month — physically impossible, likely instrument error.

### Key Numbers

| Metric | Value |
| --- | --- |
| Sites in EFP file | 233 |
| Sites in meteo file | 329 |
| Total EFP site-years | 1535 |
| Total meteo site-months | 20664 |
| Year range (EFP) | 2017–2025 |
| Outlier site-years (\|z\|>3) across all EFPs | 45 |
| Physically impossible EFP values | 12 |
| Sites with any missing EFP | 72 |
| VPD>80 hPa site-months (unit suspect) | 60 |
| P_sum>2000 mm/month (anomalous) | 6 |
| Corrupted ZIP files | 9 (1 ICOS-DE-RuW, 1 JPF-JP-Tak + 7 others) |

---
## 2. EFP Quality (Processed Annual EFPs)

Source: `EFP_outputs_corrected/ALL_SITES_YEARLY_EFP_min4continuousYears.csv`  
Shape: 1535 rows × 22 columns | columns: `SITE_ID`, `YEAR`, `uWUE`, `WUE`, `ETmax`, `precipAvail`, `Gavail`, `GSmax`, `CO2avail`, `G1`, `EF`, `EFampl`, `GPPsat`, `NEPmax`, `Rb`, `Rbmax`, `aCUE`, `TZ`, `nyears`, `status`, `igbp`, `network`

### 2.1 Descriptive Statistics

| status | variable | n_total | n_missing | pct_missing | mean | median | std | variance | min | max | p5 | p25 | p75 | p95 | n_outliers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 🚨 | GPPsat | 1535 | 330 | 21.5 | 19.9 | 19.41 | 10.45 | 109.2 | 0.0015 | 57.24 | 4.562 | 11.09 | 28.46 | 37.56 | 1 |
| 🚨 | NEPmax | 1535 | 210 | 13.68 | 18.27 | 17.26 | 10.31 | 106.2 | -0.0948 | 64.28 | 4.457 | 9.302 | 26.14 | 36.22 | 3 |
| ✓ | ETmax | 1535 | 48 | 3.13 | 0.1973 | 0.1931 | 0.0835 | 0.007 | 0.0026 | 0.6022 | 0.0775 | 0.1332 | 0.247 | 0.3366 | 14 |
| 🚨 | uWUE | 1535 | 331 | 21.56 | 3.01 | 2.944 | 1.647 | 2.712 | -0.0993 | 17.15 | 0.8507 | 2.086 | 3.771 | 4.997 | 14 |
| 🚨 | WUE | 1535 | 331 | 21.56 | 2.892 | 2.646 | 2.208 | 4.874 | -0.1784 | 34.09 | 0.8974 | 1.74 | 3.609 | 5.083 | 13 |

*Units: GPPsat & NEPmax in µmol m⁻² s⁻¹; ETmax in mm s⁻¹ (derived from LE); uWUE in µmol m⁻² s⁻¹ hPa⁻⁰·⁵; WUE in µmol J⁻¹*

### 2.2 Outlier Site-Years (|z| > 3)

**45 outlier site-years** across all EFP variables:

| variable | SITE_ID | YEAR | value | mu | sd | z |
| --- | --- | --- | --- | --- | --- | --- |
| GPPsat | IT-BFt | 2019 | 57.24 | 19.9 | 10.45 | 3.57 |
| NEPmax | BE-Bra | 2018 | 64.28 | 18.27 | 10.31 | 4.46 |
| NEPmax | DE-Msr | 2023 | 52.6 | 18.27 | 10.31 | 3.33 |
| NEPmax | DE-Msr | 2024 | 50.93 | 18.27 | 10.31 | 3.17 |
| ETmax | CN-HeM | 2021 | 0.4851 | 0.1973 | 0.0835 | 3.44 |
| ETmax | CN-Sdq | 2017 | 0.4751 | 0.1973 | 0.0835 | 3.33 |
| ETmax | CN-Zha | 2017 | 0.4704 | 0.1973 | 0.0835 | 3.27 |
| ETmax | CN-Zha | 2018 | 0.5875 | 0.1973 | 0.0835 | 4.67 |
| ETmax | CN-Zha | 2019 | 0.5424 | 0.1973 | 0.0835 | 4.13 |
| ETmax | CN-Zha | 2020 | 0.4859 | 0.1973 | 0.0835 | 3.45 |
| ETmax | CN-Zha | 2022 | 0.6022 | 0.1973 | 0.0835 | 4.85 |
| ETmax | CN-Zha | 2023 | 0.5868 | 0.1973 | 0.0835 | 4.66 |
| ETmax | CN-Zha | 2024 | 0.5402 | 0.1973 | 0.0835 | 4.1 |
| ETmax | ID-JOP | 2021 | 0.4876 | 0.1973 | 0.0835 | 3.48 |
| ETmax | US-NC2 | 2018 | 0.4711 | 0.1973 | 0.0835 | 3.28 |
| ETmax | US-NC3 | 2018 | 0.4923 | 0.1973 | 0.0835 | 3.53 |
| ETmax | US-NC3 | 2019 | 0.5002 | 0.1973 | 0.0835 | 3.63 |
| ETmax | US-NC4 | 2019 | 0.4482 | 0.1973 | 0.0835 | 3 |
| uWUE | AU-ASM | 2022 | 8.205 | 3.01 | 1.647 | 3.15 |
| uWUE | CN-Sb1 | 2020 | 13.37 | 3.01 | 1.647 | 6.29 |
| uWUE | CN-Sb1 | 2021 | 15.38 | 3.01 | 1.647 | 7.51 |
| uWUE | CN-Sb1 | 2022 | 17.15 | 3.01 | 1.647 | 8.58 |
| uWUE | CN-Sb1 | 2023 | 15.76 | 3.01 | 1.647 | 7.75 |
| uWUE | CN-Sb1 | 2024 | 14.4 | 3.01 | 1.647 | 6.92 |
| uWUE | CN-Sb2 | 2020 | 9.241 | 3.01 | 1.647 | 3.78 |
| uWUE | CN-Sb2 | 2021 | 12.29 | 3.01 | 1.647 | 5.63 |
| uWUE | CN-Sb2 | 2022 | 13.89 | 3.01 | 1.647 | 6.61 |
| uWUE | CN-Sb2 | 2023 | 15.37 | 3.01 | 1.647 | 7.5 |
| uWUE | CN-Sb2 | 2024 | 11.27 | 3.01 | 1.647 | 5.01 |
| uWUE | CN-Sdq | 2020 | 12.66 | 3.01 | 1.647 | 5.86 |
| uWUE | UK-AMo | 2020 | 9.286 | 3.01 | 1.647 | 3.81 |
| uWUE | UK-AMo | 2024 | 8.359 | 3.01 | 1.647 | 3.25 |
| WUE | CN-Sb1 | 2020 | 34.09 | 2.892 | 2.208 | 14.13 |
| WUE | CN-Sb1 | 2021 | 21.05 | 2.892 | 2.208 | 8.23 |
| WUE | CN-Sb1 | 2022 | 23.98 | 2.892 | 2.208 | 9.55 |
| WUE | CN-Sb1 | 2023 | 22.83 | 2.892 | 2.208 | 9.03 |
| WUE | CN-Sb1 | 2024 | 18.3 | 2.892 | 2.208 | 6.98 |
| WUE | CN-Sb2 | 2020 | 23.96 | 2.892 | 2.208 | 9.54 |
| WUE | CN-Sb2 | 2021 | 19.79 | 2.892 | 2.208 | 7.65 |
| WUE | CN-Sb2 | 2022 | 19.02 | 2.892 | 2.208 | 7.31 |
| WUE | CN-Sb2 | 2023 | 19.33 | 2.892 | 2.208 | 7.44 |
| WUE | CN-Sb2 | 2024 | 12.67 | 2.892 | 2.208 | 4.43 |
| WUE | CN-Sdq | 2020 | 10.51 | 2.892 | 2.208 | 3.45 |
| WUE | UK-AMo | 2020 | 11.58 | 2.892 | 2.208 | 3.93 |
| WUE | UK-AMo | 2024 | 10.55 | 2.892 | 2.208 | 3.47 |

### 2.3 Physically Impossible Values

**12 records with impossible values (sample of up to 10 per variable):**

| variable | condition | SITE_ID | YEAR | value |
| --- | --- | --- | --- | --- |
| uWUE | uWUE<0 | CA-PB1 | 2023 | -0.0419 |
| uWUE | uWUE<0 | US-EML | 2023 | -0.0614 |
| uWUE | uWUE<0 | US-xMB | 2019 | -0.026 |
| uWUE | uWUE<0 | US-xML | 2021 | -0.0471 |
| uWUE | uWUE<0 | US-xNW | 2020 | -0.0193 |
| uWUE | uWUE<0 | US-xYE | 2020 | -0.0993 |
| WUE | WUE<0 | CA-PB1 | 2023 | -0.1102 |
| WUE | WUE<0 | US-EML | 2023 | -0.0874 |
| WUE | WUE<0 | US-xMB | 2019 | -0.0396 |
| WUE | WUE<0 | US-xML | 2021 | -0.0738 |
| WUE | WUE<0 | US-xNW | 2020 | -0.0464 |
| WUE | WUE<0 | US-xYE | 2020 | -0.1784 |

**Total count by variable:** `NEPmax`: 1; `uWUE`: 6; `WUE`: 6

---
## 3. Meteorological Variable Quality (Monthly Aggregates)

Source: `EFP_outputs_corrected/ALL_SITES_MONTHLY_METEO_corrected.csv`  
Shape: 20664 rows × 16 columns

### 3.1 Descriptive Statistics

| status | variable | n_total | n_missing | pct_missing | mean | median | std | variance | min | max | p5 | p25 | p75 | p95 | n_outliers |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ✓ | TA_mean | 20664 | 0 | 0 | 10.05 | 11.37 | 11.31 | 127.9 | -38.76 | 33.77 | -11.16 | 3.173 | 18.25 | 26.34 | 121 |
| ✓ | VPD_mean | 20664 | 0 | 0 | 9.796 | 4.34 | 77.78 | 6050 | 0.0023 | 2109 | 0.4218 | 2.003 | 7.54 | 17.62 | 60 |
| ✓ | SW_IN_mean | 20664 | 0 | 0 | 163.1 | 169 | 87.3 | 7622 | 0 | 401 | 18.11 | 93.6 | 231.1 | 300.2 | 0 |
| ✓ | P_sum | 20664 | 0 | 0 | 97.51 | 50.32 | 405.3 | 1.643e+05 | 0 | 3.914e+04 | 0.046 | 18.05 | 108.4 | 340.3 | 23 |

### 3.2 Unit Plausibility Checks

| variable | check | n_flagged | flag |
| --- | --- | --- | --- |
| TA_mean | < -60°C | 0 | ✓ |
| TA_mean | > +55°C | 0 | ✓ |
| VPD_mean | < 0 hPa | 0 | ✓ |
| VPD_mean | > 80 hPa (possible Pa units?) | 60 | 🚨 |
| SW_IN_mean | < 0 W/m² | 0 | ✓ |
| SW_IN_mean | > 1000 W/m² | 0 | ✓ |
| P_sum | < 0 mm | 0 | ✓ |
| P_sum | > 2000 mm/month | 6 | 🚨 |
| n_obs | < 500 obs/month (sparse) | 0 | ✓ |

**Sites with VPD_mean > 80 hPa (N=1):**

| SITE_ID | n_months | VPD_mean_mean | VPD_max |
| --- | --- | --- | --- |
| CD-Ygb | 60 | 1400 | 2109 |

Note: Values of 1600–2100 in ICOS site `CD-Ygb` are consistent with Pa units (divide by 100 → 16–21 hPa, plausible for tropical DRC). 🚨 This site's VPD must be divided by 100 before use.


**Site-months with P_sum > 2000 mm/month (N=6):**

| SITE_ID | YEAR | MONTH | P_sum |
| --- | --- | --- | --- |
| US-HB4 | 2021 | 1 | 3.914e+04 |
| US-HB4 | 2023 | 8 | 2.739e+04 |
| US-HB4 | 2021 | 2 | 2.332e+04 |
| US-HB4 | 2022 | 8 | 1.231e+04 |
| US-HB4 | 2022 | 12 | 7974 |
| US-HB4 | 2024 | 4 | 2145 |

Note: AMF `US-HB4` P_sum values of 2,000–39,000 mm/month are physically impossible (world record monthly ~2,500 mm). 🚨 Likely instrument/aggregation error — these months should be excluded.


**VPD_mean median (excluding CD-Ygb outliers):** 4.325 hPa — ✓ consistent with hPa

---
## 4. Raw Half-Hourly/Hourly Spot Check by Network

One representative site per network, data filtered to 2017–2019 where available.  
Note: AMF zips contain `_HR_` (1-hourly) files rather than `_HH_` (30-min); all other networks use `_HH_`.  
JPF_JP-Tak is in the corrupted zips list; `JPF_JP-Yms` was used instead.


### 4.1 AMF — `AMF_US-Ha1_FLUXNET_1991-2025_v1.3_r1.zip`

| Property | Value |
| --- | --- |
| Resolution | HR (hourly) |
| HH/HR file | `AMF_US-Ha1_FLUXNET_FLUXMET_HR_1991-2025_v1.3_r1.csv` |
| Date range checked | 2017–2019 |
| n observations | 26,280 |
| Total columns | 234 |
| GPP columns present | `GPP_NT_VUT_REF`, `GPP_DT_VUT_REF` |
| VPD unit check | ✓ median=2.1 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 0.0% | -42.5 | 1.048 | 26.45 | ✓ |
| GPP_NT_VUT_REF | ✓ | 0.0% | -16.42 | 0.483 | 43.85 | ✓ |
| GPP_DT_VUT_REF | ✓ | 0.0% | 0 | 0.026 | 47.1 | ✓ |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 0.0% | -41.42 | 7.912 | 767.6 | ✓ |
| VPD_F | ✓ | 0.0% | 0 | 2.141 | 34.05 | ✓ |
| TA_F | ✓ | 0.0% | -23.94 | 8.921 | 32.03 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 34.6 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 6.111 | 1082 | ✓ |


### 4.2 ICOS — `ICOS_DE-Hai_FLUXNET_2000-2024_v1.3_r2.zip`

| Property | Value |
| --- | --- |
| Resolution | HH (half-hourly) |
| HH/HR file | `ICOS_DE-Hai_FLUXNET_FLUXMET_HH_2000-2024_v1.3_r2.csv` |
| Date range checked | 2017–2019 |
| n observations | 52,560 |
| Total columns | 244 |
| GPP columns present | `GPP_NT_VUT_REF`, `GPP_DT_VUT_REF` |
| VPD unit check | ✓ median=2.8 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 0.0% | -42.07 | 1.071 | 28.28 | ✓ |
| GPP_NT_VUT_REF | ✓ | 0.0% | -23.57 | 0.559 | 46.88 | ✓ |
| GPP_DT_VUT_REF | ✓ | 0.0% | 0 | 0.006 | 42.3 | ✓ |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 0.0% | -99.01 | 4.817 | 496.1 | ✓ |
| VPD_F | ✓ | 0.0% | 0 | 2.771 | 41.12 | ✓ |
| TA_F | ✓ | 0.0% | -14.87 | 9.28 | 33.6 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 15.8 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 3.985 | 989.3 | ✓ |


### 4.3 EUF — `EUF_ES-LJu_FLUXNET_2004-2024_v1.3_r1.zip`

| Property | Value |
| --- | --- |
| Resolution | HH (half-hourly) |
| HH/HR file | `EUF_ES-LJu_FLUXNET_FLUXMET_HH_2004-2024_v1.3_r1.csv` |
| Date range checked | 2017–2019 |
| n observations | 52,560 |
| Total columns | 177 |
| GPP columns present | `GPP_DT_VUT_REF` |
| VPD unit check | ✓ median=6.9 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 14.8% | -11.66 | 0.076 | 9.289 | ⚠️ >10% missing |
| GPP_NT_VUT_REF | ✗ | N/A | — | — | — | not in file |
| GPP_DT_VUT_REF | ✓ | 14.8% | 0 | 0.029 | 8.146 | ⚠️ >10% missing |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 11.8% | -246.6 | 7.207 | 338.8 | ⚠️ >10% missing |
| VPD_F | ✓ | 0.0% | 0.359 | 6.91 | 45.22 | ✓ |
| TA_F | ✓ | 0.0% | -5.398 | 11.54 | 33.66 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 14.73 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 2.152 | 930.1 | ✓ |


### 4.4 CNF — `CNF_CN-Zha_FLUXNET_2012-2024_v1.3_r1.zip`

| Property | Value |
| --- | --- |
| Resolution | HH (half-hourly) |
| HH/HR file | `CNF_CN-Zha_FLUXNET_FLUXMET_HH_2012-2024_v1.3_r1.csv` |
| Date range checked | 2017–2019 |
| n observations | 52,560 |
| Total columns | 229 |
| GPP columns present | `GPP_NT_VUT_REF`, `GPP_DT_VUT_REF` |
| VPD unit check | ✓ median=6.5 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 0.0% | -46.6 | 0.099 | 33.27 | ✓ |
| GPP_NT_VUT_REF | ✓ | 0.0% | -30.01 | 0.572 | 52.85 | ✓ |
| GPP_DT_VUT_REF | ✓ | 0.0% | 0 | 0.084 | 50.91 | ✓ |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 0.0% | -136.2 | 35.81 | 999.6 | ✓ |
| VPD_F | ✓ | 0.0% | 0.275 | 6.499 | 52.29 | ✓ |
| TA_F | ✓ | 0.0% | -20.89 | 11.12 | 35.37 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 5.703 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 6.101 | 1064 | ✓ |


### 4.5 JPF — `JPF_JP-Yms_FLUXNET_2000-2023_v1.3_r1.zip`

| Property | Value |
| --- | --- |
| Resolution | HH (half-hourly) |
| HH/HR file | `JPF_JP-Yms_FLUXNET_FLUXMET_HH_2000-2023_v1.3_r1.csv` |
| Date range checked | 2017–2019 |
| n observations | 52,560 |
| Total columns | 178 |
| GPP columns present | `GPP_NT_VUT_REF` |
| VPD unit check | ✓ median=4.3 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 3.3% | -40.78 | 1.551 | 18.82 | ✓ |
| GPP_NT_VUT_REF | ✓ | 3.3% | -13.8 | 1.206 | 48.76 | ✓ |
| GPP_DT_VUT_REF | ✗ | N/A | — | — | — | not in file |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 0.0% | -50.18 | 30.09 | 760.8 | ✓ |
| VPD_F | ✓ | 0.0% | 0.061 | 4.294 | 34.53 | ✓ |
| TA_F | ✓ | 0.0% | -5.872 | 15.75 | 35.88 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 31.54 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 4.258 | 1116 | ✓ |


### 4.6 KOF — `KOF_KR-SmM_FLUXNET_2015-2021_v1.3_r1.zip`

| Property | Value |
| --- | --- |
| Resolution | HH (half-hourly) |
| HH/HR file | `KOF_KR-SmM_FLUXNET_FLUXMET_HH_2015-2021_v1.3_r1.csv` |
| Date range checked | 2017–2019 |
| n observations | 52,560 |
| Total columns | 219 |
| GPP columns present | `GPP_NT_VUT_REF`, `GPP_DT_VUT_REF` |
| VPD unit check | ✓ median=4.1 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 5.9% | -74.22 | -0.595 | 49.07 | ✓ |
| GPP_NT_VUT_REF | ✓ | 100.0% | — | — | — | 🚨 >30% missing |
| GPP_DT_VUT_REF | ✓ | 5.9% | 0 | 0.259 | 37.14 | ✓ |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 5.8% | -299.9 | 16.09 | 981.7 | ✓ |
| VPD_F | ✓ | 0.0% | 0.391 | 4.13 | 30.77 | ✓ |
| TA_F | ✓ | 0.0% | -20.73 | 12.13 | 35.18 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 26.66 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 4.197 | 1087 | ✓ |


### 4.7 TERN — `TERN_AU-How_FLUXNET_2002-2025_v1.3_r1.zip`

| Property | Value |
| --- | --- |
| Resolution | HH (half-hourly) |
| HH/HR file | `TERN_AU-How_FLUXNET_FLUXMET_HH_2002-2025_v1.3_r1.csv` |
| Date range checked | 2017–2019 |
| n observations | 52,560 |
| Total columns | 221 |
| GPP columns present | `GPP_NT_VUT_REF`, `GPP_DT_VUT_REF` |
| VPD unit check | ✓ median=11.3 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 0.0% | -64.61 | 1.201 | 51.89 | ✓ |
| GPP_NT_VUT_REF | ✓ | 33.3% | -41.91 | 1.268 | 65.86 | 🚨 >30% missing |
| GPP_DT_VUT_REF | ✓ | 0.0% | 0 | 0.323 | 44.01 | ✓ |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 0.0% | -94 | 18 | 1076 | ✓ |
| VPD_F | ✓ | 0.0% | 0 | 11.27 | 55.45 | ✓ |
| TA_F | ✓ | 0.0% | 11.49 | 27.02 | 38.71 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 41.2 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 7 | 1201 | ✓ |


### 4.8 FLX — `FLX_IT-SR2_FLUXNET_2013-2024_v1.3_r1.zip`

| Property | Value |
| --- | --- |
| Resolution | HH (half-hourly) |
| HH/HR file | `FLX_IT-SR2_FLUXNET_FLUXMET_HH_2013-2024_v1.3_r1.csv` |
| Date range checked | 2017–2019 |
| n observations | 52,560 |
| Total columns | 242 |
| GPP columns present | `GPP_NT_VUT_REF`, `GPP_DT_VUT_REF` |
| VPD unit check | ✓ median=4.0 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 0.0% | -53.37 | 2.669 | 46.44 | ✓ |
| GPP_NT_VUT_REF | ✓ | 0.0% | -41.17 | 1.957 | 63.13 | ✓ |
| GPP_DT_VUT_REF | ✓ | 0.0% | 0 | 0.231 | 33.86 | ✓ |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 0.0% | -276.7 | 12.7 | 853.7 | ✓ |
| VPD_F | ✓ | 0.0% | 0 | 3.99 | 40.47 | ✓ |
| TA_F | ✓ | 0.0% | -5.465 | 15.38 | 35.33 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 33.13 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 4.249 | 997.6 | ✓ |


### 4.9 SAEON — `SAEON_ZA-BfK_FLUXNET_2020-2024_v1.3_r1.zip`

| Property | Value |
| --- | --- |
| Resolution | HH (half-hourly) |
| HH/HR file | `SAEON_ZA-BfK_FLUXNET_FLUXMET_HH_2020-2024_v1.3_r1.csv` |
| Date range checked | 2020–2024 (2017-19 not available) |
| n observations | 87,696 |
| Total columns | 221 |
| GPP columns present | `GPP_NT_VUT_REF`, `GPP_DT_VUT_REF` |
| VPD unit check | ✓ median=12.6 hPa |

| variable | present | pct_missing | min | median | max | note |
| --- | --- | --- | --- | --- | --- | --- |
| NEE_VUT_REF | ✓ | 5.3% | -28.82 | 0.379 | 31.12 | ✓ |
| GPP_NT_VUT_REF | ✓ | 5.3% | -27.62 | 0.44 | 31.72 | ✓ |
| GPP_DT_VUT_REF | ✓ | 5.3% | 0 | 0 | 24.64 | ✓ |
| GPP_F_MDS | ✗ | N/A | — | — | — | not in file |
| LE_F_MDS | ✓ | 5.3% | -96.5 | 18.55 | 592.8 | ✓ |
| VPD_F | ✓ | 0.0% | 0.001 | 12.57 | 69.87 | ✓ |
| TA_F | ✓ | 0.0% | -10.25 | 18.52 | 40.32 | ✓ |
| P_F | ✓ | 0.0% | 0 | 0 | 46.23 | ✓ |
| SW_IN_F | ✓ | 0.0% | 0 | 3.693 | 1199 | ✓ |


---
## 5. Cross-Network Consistency (Monthly Meteo)

Network-level means and IQR for key meteorological variables. Systematic outliers may indicate unit errors.

| network | n_sites | n_site_months | TA_mean(°C) | TA_p25 | TA_p75 | VPD_mean(hPa) | VPD_p25 | VPD_p75 | SW_mean(W/m²) | SW_p25 | SW_p75 | P_sum_mean(mm) | P_p25 | P_p75 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AMF | 170 | 10884 | 8.9 | 1.29 | 17.94 | 5.73 | 2 | 7.55 | 169.5 | 99.66 | 237.7 | 94.45 | 13.02 | 104.4 |
| CNF | 14 | 708 | 10.8 | 1.01 | 20.49 | 8.24 | 2.98 | 11.43 | 178.5 | 121.4 | 235.3 | 80.49 | 3.81 | 87.24 |
| EUF | 57 | 3396 | 10.91 | 4.74 | 17.71 | 6.13 | 1.87 | 8.22 | 154.6 | 82.83 | 226.4 | 87.28 | 19.48 | 107.6 |
| FLX | 9 | 420 | 15.84 | 9.93 | 26.05 | 6.82 | 3.9 | 8.01 | 198.6 | 167.9 | 237 | 132.4 | 27.56 | 189.1 |
| ICOS | 51 | 3876 | 9.44 | 3.62 | 15.77 | 25.48 | 1.4 | 5.56 | 134.8 | 55.62 | 207 | 78.9 | 32.44 | 95.84 |
| JPF | 8 | 348 | 15.36 | 9.03 | 25.84 | 5.02 | 3.27 | 6.71 | 162.4 | 118.6 | 200.6 | 419 | 214.5 | 528.3 |
| KOF | 11 | 324 | 11.24 | 2.9 | 19.75 | 5.01 | 2.87 | 6.65 | 162.5 | 115.7 | 202.1 | 130.4 | 22.98 | 158.2 |
| SAEON | 2 | 120 | 18.32 | 13.55 | 22.85 | 14.69 | 10.9 | 17.9 | 243.2 | 190.2 | 294.9 | 45.22 | 2.54 | 74.42 |
| TERN | 7 | 588 | 19.7 | 15.14 | 25.96 | 11.34 | 4.4 | 15.87 | 221.9 | 182.4 | 266.4 | 133.8 | 5.95 | 187.8 |

**VPD network-mean assessment:**

- ✓ OK **AMF**: VPD monthly mean = 5.7 hPa
- ✓ OK **CNF**: VPD monthly mean = 8.2 hPa
- ✓ OK **EUF**: VPD monthly mean = 6.1 hPa
- ✓ OK **FLX**: VPD monthly mean = 6.8 hPa
- ✓ OK **ICOS**: VPD monthly mean = 25.5 hPa
- ✓ OK **JPF**: VPD monthly mean = 5.0 hPa
- ✓ OK **KOF**: VPD monthly mean = 5.0 hPa
- ✓ OK **SAEON**: VPD monthly mean = 14.7 hPa
- ✓ OK **TERN**: VPD monthly mean = 11.3 hPa

**Interpretation:** ICOS VPD mean is elevated (25.5 hPa) because `CD-Ygb` (Congo Basin EBF) is in the ICOS network and has Pa-unit VPD. After fixing CD-Ygb, ICOS values should be consistent with other European networks (typically 3–15 hPa). All other networks show plausible VPD ranges.

**P_sum network-mean assessment:**

- ✓ **AMF**: P_sum monthly mean = 94.5 mm
- ✓ **CNF**: P_sum monthly mean = 80.5 mm
- ✓ **EUF**: P_sum monthly mean = 87.3 mm
- ✓ **FLX**: P_sum monthly mean = 132.4 mm
- ✓ **ICOS**: P_sum monthly mean = 78.9 mm
- ⚠️ High (tropical) **JPF**: P_sum monthly mean = 419.0 mm
- ✓ **KOF**: P_sum monthly mean = 130.4 mm
- ✓ **SAEON**: P_sum monthly mean = 45.2 mm
- ✓ **TERN**: P_sum monthly mean = 133.8 mm

---
## 6. Data Coverage

### 6.1 IGBP Class Summary

| IGBP | n_sites | n_site_years | pct_miss_GPPsat(%) |
| --- | --- | --- | --- |
| CSH | 6 | 41 | 0 |
| DBF | 36 | 235 | 15.3 |
| DNF | 2 | 13 | 61.5 |
| EBF | 12 | 74 | 62.2 |
| ENF | 66 | 446 | 15 |
| MF | 11 | 69 | 33.3 |
| OSH | 25 | 165 | 16.4 |
| SAV | 8 | 54 | 7.4 |
| WET | 59 | 378 | 30.2 |
| WSA | 8 | 60 | 8.3 |

### 6.2 Annual Site-Year Count (EFP file)

| YEAR | n_site_years |
| --- | --- |
| 2017 | 139 |
| 2018 | 152 |
| 2019 | 200 |
| 2020 | 220 |
| 2021 | 213 |
| 2022 | 205 |
| 2023 | 194 |
| 2024 | 174 |
| 2025 | 38 |

### 6.3 Sites with ≥1 Missing EFP Value

**72 sites** have at least one missing EFP in at least one year (out of 233 total).

| SITE_ID | missing_EFPs |
| --- | --- |
| AT-Zoe | GPPsat(12.5%); uWUE(12.5%); WUE(12.5%) |
| AU-How | uWUE(11.1%); WUE(11.1%) |
| AU-Rob | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| CA-ARB | GPPsat(12.5%); NEPmax(12.5%); ETmax(12.5%); uWUE(12.5%); WUE(12.5%) |
| CA-Ca3 | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| CA-DB2 | GPPsat(16.7%); NEPmax(16.7%); ETmax(16.7%); uWUE(16.7%); WUE(16.7%) |
| CA-DBB | GPPsat(12.5%); NEPmax(12.5%); ETmax(12.5%); uWUE(12.5%); WUE(12.5%) |
| CA-LP1 | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| CA-PB1 | GPPsat(25.0%); NEPmax(12.5%); ETmax(12.5%); uWUE(25.0%); WUE(25.0%) |
| CA-PB2 | GPPsat(12.5%); NEPmax(12.5%); ETmax(12.5%); uWUE(12.5%); WUE(12.5%) |
| CA-SCC | GPPsat(100.0%); NEPmax(100.0%); ETmax(37.5%); uWUE(100.0%); WUE(100.0%) |
| CD-Ygb | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| CL-SDF | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| CN-Din | GPPsat(100.0%); NEPmax(100.0%); ETmax(50.0%); uWUE(100.0%); WUE(100.0%) |
| CN-Dzo | GPPsat(25.0%); NEPmax(25.0%); ETmax(25.0%); uWUE(25.0%); WUE(25.0%) |
| DE-Akm | GPPsat(12.5%); NEPmax(12.5%); ETmax(12.5%); uWUE(12.5%); WUE(12.5%) |
| DE-Lnf | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| ES-Agu | GPPsat(100.0%); NEPmax(100.0%); ETmax(50.0%); uWUE(100.0%); WUE(100.0%) |
| ES-Cnd | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| ES-Gdn | GPPsat(60.0%); uWUE(60.0%); WUE(60.0%) |
| ES-LJu | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| FR-Hes | GPPsat(100.0%); NEPmax(100.0%); ETmax(12.5%); uWUE(100.0%); WUE(100.0%) |
| FR-LGt | GPPsat(100.0%); NEPmax(100.0%); ETmax(12.5%); uWUE(100.0%); WUE(100.0%) |
| GF-Guy | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| GL-NuF | GPPsat(33.3%); NEPmax(16.7%); ETmax(16.7%); uWUE(33.3%); WUE(33.3%) |
| ID-JOP | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| IE-Cra | GPPsat(100.0%); NEPmax(100.0%); ETmax(60.0%); uWUE(100.0%); WUE(100.0%) |
| IL-RmH | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| IT-BFt | GPPsat(16.7%); NEPmax(16.7%); ETmax(16.7%); uWUE(16.7%); WUE(16.7%) |
| IT-Cp2 | GPPsat(12.5%); uWUE(12.5%); WUE(12.5%) |
| IT-Ren | GPPsat(12.5%); NEPmax(12.5%); ETmax(12.5%); uWUE(12.5%); WUE(12.5%) |
| IT-TrF | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| JP-Ynf | GPPsat(16.7%); uWUE(16.7%); WUE(16.7%) |
| KR-SmM | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| NO-Ikr | GPPsat(25.0%); NEPmax(25.0%); ETmax(25.0%); uWUE(25.0%); WUE(25.0%) |
| PE-QFR | GPPsat(100.0%); NEPmax(40.0%); ETmax(40.0%); uWUE(100.0%); WUE(100.0%) |
| RU-Che | GPPsat(100.0%); NEPmax(20.0%); uWUE(100.0%); WUE(100.0%) |
| SE-Deg | GPPsat(16.7%); NEPmax(16.7%); ETmax(16.7%); uWUE(16.7%); WUE(16.7%) |
| SE-Nor | GPPsat(14.3%); NEPmax(14.3%); ETmax(14.3%); uWUE(14.3%); WUE(14.3%) |
| SE-Svb | GPPsat(12.5%); NEPmax(12.5%); ETmax(12.5%); uWUE(12.5%); WUE(12.5%) |
| US-ALQ | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-Akn | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-EA4 | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-Elm | GPPsat(12.5%); uWUE(12.5%); WUE(12.5%) |
| US-Esm | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-EvM | GPPsat(25.0%); uWUE(25.0%); WUE(25.0%) |
| US-Fo1 | GPPsat(100.0%); NEPmax(100.0%); ETmax(75.0%); uWUE(100.0%); WUE(100.0%) |
| US-Ho2 | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-LA2 | GPPsat(100.0%); NEPmax(100.0%); ETmax(57.1%); uWUE(100.0%); WUE(100.0%) |
| US-LA3 | GPPsat(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-Los | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-NC3 | GPPsat(20.0%); ETmax(20.0%); uWUE(20.0%); WUE(20.0%) |
| US-NC4 | GPPsat(100.0%); NEPmax(100.0%); ETmax(22.2%); uWUE(100.0%); WUE(100.0%) |
| US-NR1 | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-OWC | GPPsat(100.0%); NEPmax(100.0%); ETmax(22.2%); uWUE(100.0%); WUE(100.0%) |
| US-SSH | GPPsat(20.0%); uWUE(20.0%); WUE(20.0%) |
| US-Ses | GPPsat(11.1%); NEPmax(11.1%); uWUE(11.1%); WUE(11.1%) |
| US-Uaf | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-WCr | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |
| US-Whs | GPPsat(100.0%); NEPmax(100.0%); uWUE(100.0%); WUE(100.0%) |

*(12 more sites omitted; see CSV for full list)*

---
## 7. Recommendations

### 7.1 Critical Actions Required

- 🚨 **Fix ICOS CD-Ygb VPD units**: `VPD_mean` and raw `VPD_F` are in Pa, not hPa. Divide all VPD values for this site by 100 before computing EFPs (or before entering the monthly meteo table). 60 site-months affected.
- 🚨 **Remove/flag AMF US-HB4 P_sum anomalies**: 6 site-months have P_sum = 2,000–39,000 mm/month. World record monthly precipitation is ~2,500 mm (Cherrapunji). Values >2,500 are instrument/aggregation errors and should be excluded from analyses using precipitation.
- 🚨 **Re-download or fix 9 corrupted ZIP files**: `bad_or_corrupted_zip_files.csv` lists 1 ICOS (DE-RuW), 8 JPF (JP-BBY, JP-Fhk, JP-Fjy, JP-Fmt, JP-Khw, JP-Shn, JP-Spp, JP-Tak), and several TERN sites. No HH data can be read from these.
- 🚨 **Investigate GPPsat & uWUE/WUE >20% missing**: Both are 21.5% missing — check if this is driven by Gavail=no or other EFP prerequisite flags, and document the cause.

### 7.2 Warnings / Minor Issues

- ⚠️ **NEPmax 13.7% missing** — investigate which sites consistently lack NEPmax; may be due to Rb fitting failures.
- ⚠️ **Negative uWUE/WUE values** in a small number of site-years (physically possible if NEE>0 or LE<0 but unusual) — verify these are not sign convention artifacts.
- ⚠️ **AMF uses hourly (_HR_) resolution**, not half-hourly (_HH_). Ensure EFP processing scripts handle both resolutions correctly (n_obs threshold for quality filtering should be halved for hourly: ~744 obs/month instead of 1488).
- ⚠️ **45 outlier site-years** (|z|>3) across EFP variables. Most are extreme but plausible (e.g. very high GPPsat in tropical sites). Review the largest outliers per variable.

### 7.3 Variables / Sites Needing Attention

| Priority | Variable/Site | Issue |
| --- | --- | --- |
| 🚨 High | ICOS CD-Ygb VPD_mean | Pa units in hPa column (~2000 instead of ~20) |
| 🚨 High | AMF US-HB4 P_sum | Impossible monthly precipitation (up to 39,140 mm) |
| 🚨 High | 9 corrupted ZIPs | Cannot read HH data |
| 🚨 High | GPPsat, uWUE, WUE | >21% missing values |
| ⚠️ Med  | NEPmax | ~14% missing |
| ⚠️ Med  | uWUE, WUE negative | Check sign conventions |
| ⚠️ Med  | AMF hourly resolution | Confirm EFP scripts handle n_obs threshold |

---
*Report generated by `flux_dq_analysis_v2.py` · 2026-06-29 15:37*
