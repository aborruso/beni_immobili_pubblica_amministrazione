# Verifca coerenza tra coordinate e dati amministrativi


Misura distanza levenstein tra i nomi delle regioni, dopo within tra coordinate e poligoni regionali.<br>
Di base tutti quelli in cui la distanza è maggiore di 1, sembrano errori. Sono lo 0.06%.

```sql
duckdb -c "copy (select immobili.id_bene,immobili.regione_del_bene,regioni.cod_reg,regioni.den_reg,levenshtein(lower(immobili.regione_del_bene), lower(regioni.den_reg)) levenshtein from '../data/beni_immobili_pubblici.parquet' as immobili LEFT JOIN ST_READ('https://confini-amministrativi.it/api/v2/it/20240101/regioni.geo.json') as regioni ON ST_Within(ST_POINT(longitudine,latitudine),regioni.geom)) to 'test.parquet' (FORMAT PARQUET, COMPRESSION 'zstd', ROW_GROUP_SIZE 100_000)"
```
