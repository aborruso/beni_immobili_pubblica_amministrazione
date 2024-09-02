#!/bin/bash

set -x
set -e
set -u
set -o pipefail

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$folder"/../data
mkdir -p "$folder"/../data/raw
mkdir -p "$folder"/tmp

URL="https://www.de.mef.gov.it/it/attivita_istituzionali/patrimonio_pubblico/censimento_immobili_pubblici/open_data_immobili/dati_immobili_2019.html"

curl -c "$folder"/tmp/cookies.txt -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36' "$URL"

curl -b "$folder"/tmp/cookies.txt -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36' "$URL" | scrape -be '//li/a[contains(@href, "zip")]' | xq . | jq -c '.html.body.a[]' | mlrgo --jsonl gsub -f "#text" " *\t.*" "" then clean-whitespace then rename -r '^(@|#)(.+)$,\2' >"$folder"/tmp/beni_immobili_pubblici.jsonl

while IFS= read -r line || [ -n "$line" ]; do
    # Esegui qui le operazioni su ogni riga. Ad esempio, puoi fare echo per stamparla.
    echo "$line"
    href=$(echo "$line" | jq -r '.href')
    base_url="https://www.de.mef.gov.it"
    name=$(basename "$href")
    # if file "$folder"/../data/raw/"$name" exist, delete it
    if [ ! -f "$folder"/../data/raw/"$name" ]; then
        curl -kL -b "$folder"/tmp/cookies.txt -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/' "$base_url$href" -o "$folder"/../data/raw/"$name"
    fi
done < "$folder"/tmp/beni_immobili_pubblici.jsonl

mlrgo --ijsonl --ocsv cut -f href,text then label href,titolo then put '$file=sub($href,".+/","")' then reorder -f titolo,file,href "$folder"/tmp/beni_immobili_pubblici.jsonl >"$folder"/../data/beni_immobili_pubblici_anagrafica_file.csv
