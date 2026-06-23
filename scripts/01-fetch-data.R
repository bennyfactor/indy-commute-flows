suppressMessages({library(lehdr); library(dplyr)})
source("R/regions.R"); source("R/lodes.R")

dir.create("data", showWarnings = FALSE)
year <- newest_lodes_year("in")
message("Using LODES year: ", year)
writeLines(as.character(year), "data/lodes_year.txt")

od <- grab_lodes(state = "in", year = year, lodes_type = "od",
                 job_type = "JT00", segment = "S000",
                 state_part = "main", agg_geo = "bg", version = "LODES8")

# grab_lodes(agg_geo="bg") yields h_bg / w_bg (12-digit) and S000.
flows <- od |>
  transmute(origin = as.character(h_bg),
            dest   = as.character(w_bg),
            count  = as.numeric(S000)) |>
  filter(in_region(origin), in_region(dest), count > 0)

message("Region OD pairs: ", nrow(flows),
        " | total commuters: ", format(sum(flows$count), big.mark=","))
saveRDS(flows, "data/flows.rds")
cat("FETCH OK\n")
