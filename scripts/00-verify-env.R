# scripts/00-verify-env.R
pkgs <- c("mapgl","lehdr","tigris","sf","dplyr","htmlwidgets")
for (p in pkgs) {
  v <- as.character(packageVersion(p))
  cat(sprintf("%-12s %s\n", p, v))
}
stopifnot("mapgl >= 0.5.0 required" = packageVersion("mapgl") >= "0.5.0")
stopifnot("add_flowmap missing" = "add_flowmap" %in% getNamespaceExports("mapgl"))
cat("ENV OK\n")
