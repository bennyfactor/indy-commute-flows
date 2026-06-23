# 15 central-Indiana counties (state FIPS 18). Indianapolis-Carmel-Anderson MSA (11)
# plus Monroe (Bloomington), Tippecanoe/Clinton/White (Lafayette area).
region_counties <- function() {
  c("18011", # Boone
    "18013", # Brown
    "18023", # Clinton
    "18057", # Hamilton
    "18059", # Hancock
    "18063", # Hendricks
    "18081", # Johnson
    "18095", # Madison
    "18097", # Marion (Indianapolis)
    "18105", # Monroe (Bloomington)
    "18109", # Morgan
    "18133", # Putnam
    "18145", # Shelby
    "18157", # Tippecanoe (Lafayette)
    "18181") # White
}

in_region <- function(geoid) {
  substr(geoid, 1, 5) %in% region_counties()
}
