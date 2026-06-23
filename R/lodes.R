suppressMessages(library(lehdr))
# Try candidate years newest-first; return the first that downloads without error.
newest_lodes_year <- function(state = "in", candidates = 2024:2018) {
  for (y in candidates) {
    ok <- tryCatch({
      suppressWarnings(suppressMessages(
        grab_lodes(state = state, year = y, lodes_type = "od",
                   job_type = "JT00", segment = "S000",
                   state_part = "main", agg_geo = "bg", version = "LODES8")
      ))
      TRUE
    }, error = function(e) FALSE)
    if (ok) return(y)
    message(sprintf("LODES %d not available for %s, trying older...", y, state))
  }
  stop("No LODES year available for ", state)
}
