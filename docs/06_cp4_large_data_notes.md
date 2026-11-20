# CP4 large-data benchmark status

Updated: 21 November 2026

The required large-data archive is not present in this checkout. The CP4 timing and plan results therefore remain pending; the CSV in this folder is a status placeholder and contains no measured values.

## Available work

- `docs/05_scalability_report.md` contains the scalability discussion and empty result sections.
- `sql/08_partitioning.sql` is an analytical partitioning experiment. It has not been run against the large dataset.
- `benchmarks/results/large/summary.csv` lists the required 30 queries with `PENDING` values. The benchmark script replaces it when real measurements are collected.

## Still required for final CP4

- Obtain `large_data.zip` from the course materials and unpack it as `large_data/` at the repository root.
- Create a fresh database, load all nine CSVs, apply the indexes, and run `ANALYZE`.
- Run the optimized 30-query workload three times per query. The script writes the measured averages and raw plans into `benchmarks/results/large/`.
- Run the partitioning experiment and save its actual plans.
- Replace the pending rows and fill the report's large-data timing, storage, growth, and target-compliance sections.

## Reproducible commands

Run from the repository root after the archive is available:

```sh
unzip -o large_data.zip -d large_data
createdb gpay_cp4
sed 's#seed_data/#large_data/#g' sql/02_load_data.sql > /tmp/02_load_large_data.sql
psql -v ON_ERROR_STOP=1 -d gpay_cp4 -f sql/01_schema.sql -f /tmp/02_load_large_data.sql
psql -v ON_ERROR_STOP=1 -d gpay_cp4 -f sql/05_indexes.sql
psql -v ON_ERROR_STOP=1 -d gpay_cp4 -c 'ANALYZE'
./benchmarks/run_benchmark.sh gpay_cp4 large 3 sql/06_optimized_queries.sql
psql -v ON_ERROR_STOP=1 -d gpay_cp4 -f sql/08_partitioning.sql > benchmarks/results/large/partitioning_plans.txt
```

The loader substitution is written to `/tmp`; it leaves the tracked seed loader unchanged. These commands have not been run here because the dataset and a running PostgreSQL server were unavailable.
