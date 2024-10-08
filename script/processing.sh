#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$folder"/../data
mkdir -p "$folder"/../data/raw
mkdir -p "$folder"/tmp

# unzip all files in data/raw and overwrite them. Use find and while loop
find "$folder"/../data/raw -type f -name "*.zip" | while IFS= read -r file; do
    name=$(basename "$file" .zip)
    # if file "$folder"/../data/raw/"$name" exist, delete it
    if [ ! -f "$folder"/../data/raw/"$name".csv ]; then
        #unzip -o -d "$folder"/../data/raw "$file"
        unzip -j "$file" -d "$folder"/../data/raw
        # change encoding to utf-8 from Windows-1252
        iconv -f Windows-1252 -t UTF-8 "$folder"/../data/raw/"$name".csv > "$folder"/../data/raw/tmp.csv
        mv "$folder"/../data/raw/tmp.csv "$folder"/../data/raw/"$name".csv
    fi
done

# crea file parquet
duckdb -c "COPY (
  SELECT
    * REPLACE (regexp_replace(filename, '^.+/', '') AS filename)
  FROM
    read_csv_auto(
      '$folder/../data/raw/*.csv',
      filename = TRUE,
      normalize_names = TRUE,
      decimal_separator = ','
    )
) TO '../data/beni_immobili_pubblici.parquet' (
  FORMAT PARQUET,
  COMPRESSION 'zstd',
  ROW_GROUP_SIZE 100_000
)"

# Da qui in poi lo script "esce". Ma c'è il codice per creare il file csv.gz e il file geo parquet.

# crea file csv.gz
duckdb --csv -c "COPY (SELECT * FROM '"$folder"/../data/beni_immobili_pubblici.parquet') TO '"$folder"/../data/beni_immobili_pubblici.csv.gz'"

# crea file temporaneo FlatGeobuf
duckdb -c "COPY (SELECT *,ST_POINT(longitudine,latitudine) geom FROM '"$folder"/../data/beni_immobili_pubblici.parquet' WHERE longitudine IS NOT NULL OR latitudine IS NOT NULL) TO '"$folder"/tmp/tmp.fgb' WITH (FORMAT GDAL, DRIVER 'FlatGeobuf',SRS 'EPSG:4326')"

# converti file temporaneo FlatGeobuf in geo parquet
ogr2ogr -f parquet -lco COMPRESSION=ZSTD "$folder"/../data/beni_immobili_pubblici_geo.parquet "$folder"/tmp/tmp.fgb

# elimina file temporaneo FlatGeobuf
find "$folder"/tmp -type f -name "tmp.fgb" -delete

# elima tutti i file csv in ../data/raw/. usa find e -delete
find "$folder"/../data/raw -type f -name "*.csv" -delete

# crea griglia H3 di livello 5
duckdb -c "LOAD h3;COPY (
  SELECT
    h3_cell_to_boundary_wkt(h3_latlng_to_cell(latitudine, longitudine, 5)):: geometry geom,
    COUNT(*) AS conteggio_immobili
  FROM
    '../data/beni_immobili_pubblici_geo.parquet'
  GROUP BY
    1
) TO '../data/beni_immobili_pubblici_h3_5.gpkg' WITH (
  FORMAT GDAL,
  DRIVER 'GPKG',
  LAYER_CREATION_OPTIONS 'WRITE_BBOX=YES',
  SRS 'EPSG:4326'
);"
