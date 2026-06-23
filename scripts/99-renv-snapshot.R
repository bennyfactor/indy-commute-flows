# scripts/99-renv-snapshot.R
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::snapshot(packages = c("mapgl","lehdr","tigris","sf","dplyr","htmlwidgets","renv"),
               prompt = FALSE, lockfile = "renv.lock")
cat("SNAPSHOT OK\n")
