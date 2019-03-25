# Load GRASS library
library("rgrass7")
 
# Define GRASS working environment
gisDbase <- '/data/scratch/grass'
location <- 'ETRS_33N'
PERMANENT <- 'p_ConnectivityNetwork'

gis_data_dir <-  '/data/scratch/geodata/rasterized/'
rasterlist <- system(paste0('ls ', '/data/scratch/geodata/rasterized/'),
                     intern=TRUE)
rastermaplist <- gsub('-','_', gsub(".tif", "", rasterlist))

## Full path to mapset
#wd <- paste(gisDbase, location, mapset, sep='/')

if (dir.exists(paste(gisDbase, location, sep='/'))==FALSE) {
# Create mapset if it does not exist
try(system( paste("grass -text -c EPSG:25833",
                  paste(gisDbase, location, sep='/'), '-e')))
}

# Get GRASS library path
grasslib <- try(system('grass --config', intern=TRUE))[4]
 
# Full path to mapset
wd <- paste(gisDbase, location, PERMANENT, sep='/')

if (dir.exists(wd)==FALSE) {
# Create mapset if it does not exist
try(system( paste("grass -text -c -e", wd)))
}

# Initialize GRASS session
initGRASS(gisBase=grasslib, location=location,
          mapset=PERMANENT, gisDbase=gisDbase,
		  override = TRUE)

for (r in 1:length(rasterlist)) {
execGRASS('r.external', input=paste(gis_data_dir, rasterlist[r], sep='/'),
          output=rastermaplist[r], flags=c('overwrite'))
}

unlink_.gislock()
remove_GISRC()
