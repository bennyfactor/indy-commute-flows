# Dockerfile
FROM rocker/geospatial:4.4.2
# rocker/geospatial already has sf, GDAL/GEOS/PROJ, tidyverse, htmlwidgets
RUN install2.r --error --skipinstalled \
      lehdr tigris \
 && installGithub.r walkerke/mapgl \
 && rm -rf /tmp/downloaded_packages
