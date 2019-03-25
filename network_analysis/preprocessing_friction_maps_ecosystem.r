### Load required libraries
# Load GRASS library
library("rgrass7")
# Load GRASS library
library("RPostgreSQL")

# Define ecosystem to work on
ecosystem <- 'myr'
 

### Prepare protected area data in PostGIS

# DB connection
pg_host <- 'gisdata-db.nina.no'
pg_user <-  Sys.info()['user']
pg_db <- 'gisdata'
pg_drv <- dbDriver("PostgreSQL")

con <- dbConnect(pg_drv, dbname=pg_db, user=pg_user, host=pg_host, forceISOdate=FALSE)

con_string <- paste0('PG:host=', pg_host, ' dbname=', pg_db, ' user=', pg_user)

create_view <- paste0('DROP VIEW pa_network.protected_', ecosystem, ';
CREATE MATERIALIZED VIEW pa_network.protected_', ecosystem, ' AS
SELECT	pa_buffered.gid,
	-- Apply Union ("dissolve") on polygons resulting from intersection of PAs and land cover types
	ST_Union(ST_CollectionExtract(ST_Intersection(eco.geom, pa_buffered.geom), 3)) AS geom FROM
		(SELECT 	-- in the following line more columns could be selected if needed
			pa.gid, pa.geom FROM 
			"ProtectedSites"."Fenoscandia_NatDesignAreas_CDDA_ProtectedSite_Polygons" AS pa,
			(SELECT geom FROM "AdministrativeUnits"."Fenoscandia_Country_polygon" WHERE "countryCode" = \'NO\') AS no
			WHERE ST_DWithin(pa.geom, no.geom, 70000)) AS pa_buffered,
		pa_network."Fenoscandia_LandCover_polygon_', ecosystem, '" AS eco
WHERE ST_Intersects(eco.geom, pa_buffered.geom);')

rs <- dbSendQuery(con, create_view)

dbClearResult(rs)
dbDisconnect(con)

### Prepare input data for network analysis in GRASS GIS

# Define GRASS working environment
gisDbase <- '/data/scratch/grass'
location <- 'ETRS_33N'

# Get GRASS library path
grasslib <- try(system('grass --config', intern=TRUE))[4]
 
gis_data_dir <-  '/data/scratch/geodata/rasterized/'
rasterlist <- system(paste0('ls ', '/data/scratch/geodata/rasterized/'),
                     intern=TRUE)
rastermaplist <- gsub('-','_', gsub(".tif", "", rasterlist))

# Check if required location exists
if (dir.exists(paste(gisDbase, location, sep='/'))==FALSE) {
print(paste0('ERROR: Location <', location, '> not found!'))
}

# Define mapset with basic input data
PERMANENT <- 'p_ConnectivityNetwork'

# Check if mapset with basic input data exists
if (dir.exists(paste(gisDbase, location, PERMANENT, sep='/'))==FALSE) {
print(paste0('ERROR: Mapset <', mapset,
             '> not found in location <',
			 location, '>!'))
}

# Define mapset to work in
mapset <- paste0(PERMANENT, '_', ecosystem)

# Full path to mapset
wd <- paste(gisDbase, location, mapset, sep='/')

# Create mapset if it does not exist
try(system( paste("grass -text -c -e", wd)))

# Initialize GRASS session
initGRASS(gisBase=grasslib, location=location,
          mapset=mapset, gisDbase=gisDbase,
		  override = TRUE)

# Add basic project mapset to search path
execGRASS('g.mapsets', operation='add', mapset=PERMANENT)


### Get protected area polygons

# Import protected areas
execGRASS('v.in.ogr', input=con_string, flags=c('overwrite'),
          layer=paste0('pa_network.protected_', ecosystem),
		  output=paste0('protected_', ecosystem),
		  geometry='geom')

### Create friction cost mapcalc
	  
###
# Assign friction cost values
###

# Set computational region aligned to first raster map
# (all should have same pixel alignment and extent)
execGRASS('g.region', flags='p', raster=rastermaplist[1],
          align=rastermaplist[1])

# Reclassify input raster maps and assigne friction values
for (r in 1:length(rastermaplist)) {
# echo r.reclass --overwrite --verbose input=n50_arealdekke_pol output=$motstand_n50_arealdekke_pol rules=$rc_file
execGRASS('r.reclass', overwrite=TRUE, verbose=TRUE, input=rastermaplist[r],
          output=paste0(gsub('tif', '', rasterlist[r]), '_', ecosystem, '_motstand'),
		  rules=paste0(gsub('tif', '', rasterlist[r]), '_', ecosystem, '_motstand.txt'))
}

# Compile mapcalculator expression
mapcalc_expression <- paste0("motstand_",ecosystem, "_10m=int(", toString(rastermaplist, sep='+'), ")")

# Combine input raster maps using map calculator by summing up friction costs
execGRASS('r.mapcalc', overwrite=TRUE, verbose=TRUE, expression=mapcalc_expression)

###
# Aggregate to 100m resolution
###

# Set computational region to 100m, aligned to lower left corner of first input raster map
# (all should have same pixel alignment and extent)
execGRASS('g.region', flags=c('p'), raster=rastermaplist[1],
          s=as.character(gmeta()$s), w=as.character(gmeta()$w), res='100')

output_final <- paste0("motstand_",ecosystem, "_100m")
# Aggregate raster maps to 100m resolution
execGRASS('r.resamp.stats', overwrite=TRUE, verbose=TRUE,
          input=paste0("motstand_",ecosystem, "_10m"),
		  output=output_final, method='average')

# Export to GeoTiff
execGRASS('r.out.gdal', overwrite=TRUE, verbose=TRUE, input=output_final,
          output=paste0(gis_data_dir, output_final, '.tif'),
		  createopt="COMPRESS=LZW,TFW=YES")

unlink_.gislock()
remove_GISRC()

print('Done')
