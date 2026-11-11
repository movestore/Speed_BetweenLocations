library("move2")
library("ggplot2")
library("sf")
library("units")

## The parameter "data" is reserved for the data object passed on from the previous App.
## Settings (defaults are defined in appspec.json / app-configuration.json):
##   units           - unit in which speed is calculated ("m/s" or "km/h")
##   fixed_x_axis    - TRUE: all per-track histograms use the x-axis range of the full data set
##   speed_threshold - optional speed (in `units`); speeds above it are counted per track and
##                     marked in the plots. NULL = no threshold.

# number of tracks per page in the multi-track overview pages
TRACKS_PER_BOXPLOT_PAGE <- 40
TRACKS_PER_GRID_PAGE <- 16

# summary statistics of the speed values of one track
summarise_track <- function(speed, threshold) {
  s <- speed[!is.na(speed)]
  n <- length(s)
  stat <- function(f) if (n > 0) f(s) else NA_real_
  out <- data.frame(
    n_locations = length(speed),
    n_speed_values = n,
    min_speed = stat(min),
    q25_speed = stat(function(x) unname(quantile(x, 0.25))),
    median_speed = stat(median),
    mean_speed = stat(mean),
    q75_speed = stat(function(x) unname(quantile(x, 0.75))),
    q95_speed = stat(function(x) unname(quantile(x, 0.95))),
    max_speed = stat(max)
  )
  if (!is.null(threshold)) {
    out$n_above_threshold <- sum(s > threshold)
    out$pct_above_threshold <- if (n > 0) round(100 * out$n_above_threshold / n, 2) else NA_real_
  }
  out
}

# adds the threshold line to a plot with speed on the x axis.
# For histograms (`d` given), speeds above the threshold are additionally marked as red
# ticks along the x axis, as single values are often invisible as histogram bars.
add_threshold <- function(p, threshold, d = NULL) {
  if (is.null(threshold)) return(p)
  p <- p + geom_vline(xintercept = threshold, colour = "red", linetype = "dashed")
  if (!is.null(d) && any(d$speed > threshold)) {
    p <- p + geom_rug(data = d[d$speed > threshold, ], aes(x = speed), inherit.aes = FALSE,
                      colour = "red", sides = "b", length = grid::unit(0.04, "npc"))
  }
  p
}

# histogram layer: with a shared x axis all tracks use the same bin grid as the full data set
hist_layer <- function(x_fixed) {
  if (is.null(x_fixed)) {
    geom_histogram(bins = 100)
  } else {
    geom_histogram(binwidth = x_fixed$binwidth, boundary = x_fixed$range[1])
  }
}

rFunction <- function(data, units, fixed_x_axis, speed_threshold, ...) {
  
  if (!is.null(speed_threshold) && (is.na(speed_threshold) || speed_threshold < 0)) {
    logger.warn("The speed threshold must be a positive number. No threshold is used.")
    speed_threshold <- NULL
  }
  
  if ("speed" %in% names(data)) {
    logger.warn("The input data already contain a column 'speed'. It is overwritten with the newly calculated speed.")
  }
  data$speed <- mt_speed(data, units = units)
  
  speed_label <- paste0("Speed (", units, ")")
  track_col <- mt_track_id_column(data)
  track_id <- mt_track_id(data)
  track_levels <- if (is.factor(track_id)) levels(droplevels(track_id)) else unique(as.character(track_id))
  track_id <- factor(as.character(track_id), levels = track_levels)
  speed_num <- as.numeric(data$speed)
  
  ## ---- summary table by track (all tracks, also those without speed values) ----
  speed_by_track <- split(speed_num, track_id)
  summary_tab <- do.call(rbind, lapply(speed_by_track, summarise_track, threshold = speed_threshold))
  summary_tab <- cbind(setNames(data.frame(names(speed_by_track)), track_col), summary_tab)
  summary_tab$unit <- units
  summary_tab <- summary_tab[order(summary_tab$max_speed, decreasing = TRUE, na.last = TRUE), ]
  rownames(summary_tab) <- NULL
  write.csv(summary_tab, appArtifactPath("speed_summary_by_track.csv"), row.names = FALSE)
  
  n_no_speed <- sum(summary_tab$n_speed_values == 0)
  if (n_no_speed > 0) {
    logger.info(paste0(n_no_speed, " track(s) have only one location, so no speed can be calculated. They are excluded from the plots."))
  }
  if (!is.null(speed_threshold)) {
    n_tr_above <- sum(summary_tab$n_above_threshold > 0)
    logger.info(paste0(n_tr_above, " of ", nrow(summary_tab), " track(s) have speeds above the threshold of ",
                       speed_threshold, " ", units, " (", sum(summary_tab$n_above_threshold), " values in total)."))
  }
  
  ## ---- plots ----
  # NA speeds are removed, so tracks with only one location (speed NA) are excluded from the plots
  dataPlot <- data.frame(track = track_id, speed = speed_num)
  dataPlot <- dataPlot[!is.na(dataPlot$speed), ]
  dataPlot$track <- droplevels(dataPlot$track)
  
  if (nrow(dataPlot) == 0) {
    logger.warn("No speed values could be calculated (all tracks have only one location). No histogram PDF is created.")
    return(data)
  }
  
  x_range <- range(dataPlot$speed)
  x_fixed <- if (isTRUE(fixed_x_axis) && diff(x_range) > 0) list(range = x_range, binwidth = diff(x_range) / 100) else NULL
  x_coord <- if (is.null(x_fixed)) NULL else coord_cartesian(xlim = x_range)
  tracks <- levels(dataPlot$track)
  n_tracks <- length(tracks)
  
  # track order for the boxplots: highest maximum speed first (shown at the top)
  max_by_track <- tapply(dataPlot$speed, dataPlot$track, max)
  tracks_by_max <- names(sort(max_by_track, decreasing = TRUE))
  
  pdf(appArtifactPath("speed_histogram.pdf"), width = 10, height = 8)
  
  # 1. all individuals
  if (n_tracks > 1) {
    p <- ggplot(dataPlot, aes(speed)) + geom_histogram(bins = 100) +
      xlab(speed_label) + ggtitle("All Individuals", subtitle = paste(n_tracks, "tracks")) + theme_bw()
    print(add_threshold(p, speed_threshold, dataPlot))
  }
  
  # 2. boxplots by track, sorted by maximum speed
  box_pages <- split(tracks_by_max, ceiling(seq_along(tracks_by_max) / TRACKS_PER_BOXPLOT_PAGE))
  for (i in seq_along(box_pages)) {
    pg <- box_pages[[i]]
    d <- dataPlot[dataPlot$track %in% pg, ]
    d$track <- factor(as.character(d$track), levels = rev(pg))
    p <- ggplot(d, aes(x = speed, y = track)) + geom_boxplot(outlier.size = 0.8) +
      coord_cartesian(xlim = x_range) + xlab(speed_label) + ylab(track_col) +
      ggtitle("Speed by track, sorted by maximum speed",
              subtitle = if (length(box_pages) > 1) paste("Page", i, "of", length(box_pages)) else NULL) +
      theme_bw()
    print(add_threshold(p, speed_threshold))
  }
  
  if (n_tracks > 1) {
    # 3. overview grid: several track histograms per page
    grid_pages <- split(tracks, ceiling(seq_along(tracks) / TRACKS_PER_GRID_PAGE))
    for (i in seq_along(grid_pages)) {
      d <- dataPlot[dataPlot$track %in% grid_pages[[i]], ]
      d$track <- droplevels(d$track)
      p <- ggplot(d, aes(speed)) + hist_layer(x_fixed) +
        facet_wrap(~track, ncol = 4, scales = if (is.null(x_fixed)) "free" else "free_y") +
        x_coord + xlab(speed_label) +
        ggtitle("Speed histograms by track",
                subtitle = if (length(grid_pages) > 1) paste("Page", i, "of", length(grid_pages)) else NULL) +
        theme_bw()
      print(add_threshold(p, speed_threshold, d))
    }
  }
  
  # 4. one page per track
  invisible(lapply(tracks, function(tr) {
    logger.info(paste("Plotting speed histogram of track", tr))
    d <- dataPlot[dataPlot$track == tr, ]
    p <- ggplot(d, aes(speed)) + hist_layer(x_fixed) + x_coord +
      xlab(speed_label) + ggtitle(tr, subtitle = paste(nrow(d), "speed values")) + theme_bw()
    print(add_threshold(p, speed_threshold, d))
  }))
  
  dev.off()
  
  return(data)
}