# Dockerfile
FROM rocker/geospatial:4.4.2
# rocker/geospatial already has sf, GDAL/GEOS/PROJ, tidyverse, htmlwidgets.
# mapgl is pinned to the exact commit recorded in renv.lock (v0.5.0, the first
# release exposing add_flowmap) so the image build and the lockfile agree.
RUN install2.r --error --skipinstalled \
      lehdr tigris \
 && installGithub.r walkerke/mapgl@07eaee078e7e14a14f41c9552dc57bd885935daa \
 && rm -rf /tmp/downloaded_packages /tmp/Rtmp*
