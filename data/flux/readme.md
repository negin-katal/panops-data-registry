last modification date: 02.06.2026 by NK
######
This document is explain step by step of our approaches by data cleaning.
The flux data is downloaded using 12_FLUXNET_shuttle.ipynb only sites from 2016 to 2025 is downloaded which had wooden structure such as all forests type, savanna, shrublands and wetlands.

after that we filter them for the sites that have at least available continous data for four years. 

later with 14_calc_EFPs.ipynb we calculated the yearly ecosystem functional properties and monthly meteorological data with upper and lower quantile. 

. still we need the to calculate the center of the season
. For the new sites also get the plant traits from planttraits.earth.

The mortality data is now added to the EFPs and meteo data and this time we have a new variable called intensity which reflect the mortality intensity based on the tree cover in the following area. 



