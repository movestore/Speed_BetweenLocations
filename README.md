# Speed Between Locations

MoveApps

Github repository: https://github.com/movestore/Speed_BetweenLocations

## Description
Calculation of the speed between consecutive locations, with histograms, boxplots and a summary table per track to quickly compare tracks and identify those with suspiciously high speeds.

## Documentation
This App calculates the speed between each pair of consecutive locations of every track. Speed is a property of a segment, so it is assigned to the first location of each segment. The last location of each track therefore gets the speed NA. The speed is added to the data in the column `speed` and returned for use in later Apps.

To help find tracks with unusual speeds, for example suspiciously high values seen in the histogram of all individuals, the App produces:

- a PDF with:
  - a histogram of all individuals;
  - boxplots of speed per track, sorted by maximum speed;
  - overview pages with the histograms of up to 16 tracks per page;
  - one histogram per track;
- a CSV table with summary statistics of speed per track, sorted by maximum speed.

By default all track histograms use the same x-axis range as the full data set, so they can be compared directly. Optionally, a speed threshold can be set. The number and percentage of speeds above it are then reported per track, and it is marked in all plots.

### Application scope
#### Generality of App usability
This App was developed for any taxonomic group.

#### Required data properties
The App should work for any kind of location data. Tracks need at least two locations to calculate a speed. Tracks with only one location are listed in the summary table but are not included in the plots.

### Input type
`move2::move2_loc`

### Output type
`move2::move2_loc`

### Artefacts
`speed_histogram.pdf`: PDF with the following pages:
1. Histogram of the speeds of all individuals (only if there is more than one track).
2. Boxplots of speed per track, sorted by maximum speed (highest at the top), with up to 40 tracks per page. Tracks with suspiciously high values appear at the top.
3. Overview pages with the speed histograms of up to 16 tracks per page (only if there is more than one track).
4. One page with the speed histogram of each track.

If a speed threshold is set, it is shown as a red dashed line in all plots. In the histograms, every speed above the threshold is also marked with a red tick along the x-axis, because single values are often not visible as histogram bars. This PDF is not created if no speed can be calculated, i.e. if all tracks have only one location.

`speed_summary_by_track.csv`: table with one row per track, sorted by maximum speed (highest first). Columns:
- the track ID;
- `n_locations` and `n_speed_values`;
- `min_speed`, `q25_speed`, `median_speed`, `mean_speed`, `q75_speed`, `q95_speed` and `max_speed`;
- `unit`.

If a speed threshold is set, the columns `n_above_threshold` and `pct_above_threshold` (number and percentage of speed values above the threshold) are added. Tracks with only one location are included with `n_speed_values` = 0 and empty statistics.

### Settings
`Units` (units): unit in which the speed is calculated and plotted. Available are `m/s` and `km/h`. Default: `m/s`.

`Same x-axis range for all tracks` (fixed_x_axis): if selected, all track histograms (overview pages and individual pages) use the speed range of the full data set and the same bins, so tracks can be compared directly with each other and with the histogram of all individuals. If not selected, each track histogram uses its own speed range. The boxplots always use the range of the full data set. Default: selected (`true`).

`Speed threshold (optional)` (speed_threshold): optional speed in the selected unit. For each track, the number and percentage of speeds above this value are added to the summary table, and the threshold is marked in all plots. The log also states how many tracks have speeds above the threshold. Default: empty (no threshold).

### Changes in output data
The App adds the column `speed` to the input data. It contains the speed between each location and the next location of the same track, in the selected unit, and stores that unit with the values. The last location of each track has the speed NA. If the input data already contain a column `speed`, it is overwritten and a warning is written to the log. No locations are removed.

### Errors and null handling
**Setting `speed_threshold`:** if left empty, no threshold is used. If a negative value is given, it is ignored with a warning and no threshold is used.

**Input data:** tracks with only one location get the speed NA. They are listed in the summary table, are excluded from the plots, and their number is stated in the log. If no track has more than one location, no PDF is created and a warning is written to the log. The summary table is still created and the full input data, with the `speed` column added, is returned.

**Data:** the full input data set with the added `speed` column is returned for use in the next App.

### Technical details
- Speed is calculated with `move2::mt_speed()`. It divides the distance between consecutive locations by the time between them, per track. Distances are calculated by `sf` in the projection of the input data, as great-circle distances for longitude/latitude data. The data are not reprojected.
- Plots are made with `ggplot2`. The summary statistics are calculated per track on the non-NA speed values.
- The numbers of tracks per page (40 for boxplots, 16 for the overview histograms) are fixed in the code.
- Very large numbers of tracks lead to many PDF pages, because each track also gets its own histogram page.