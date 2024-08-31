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
duckdb --csv -c "COPY (SELECT * REPLACE (regexp_replace(filename,'^.+/','') AS filename) FROM read_csv_auto('../data/raw/*.csv',filename=true,types={'id_bene':'VARCHAR','latitudine': 'FLOAT','longitudine': 'FLOAT','superficie_mq': 'FLOAT','cubatura_mc': 'FLOAT','sup_aree_pertinenziali_mq': 'FLOAT','superficie_di_riferimento_mq': 'FLOAT'},normalize_names=true,decimal_separator=',')) TO '"$folder"/../data/beni_immobili_pubblici.parquet' (FORMAT PARQUET, COMPRESSION 'zstd', ROW_GROUP_SIZE 100_000)"

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
