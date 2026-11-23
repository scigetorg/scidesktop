# datadesktop

`scidesktop` for general-purpose data science: adds a locked Python 3.13
**Data Science** Jupyter kernel (`/opt/datascience-env`) with `numpy`, `scipy`,
`pandas`, `polars`, `pyarrow`, `duckdb` (+ `jupysql` / `duckdb-engine`),
`scikit-learn`, `statsmodels`, `xgboost`, `lightgbm`, `optuna`, `shap`,
`matplotlib`, `seaborn`, `plotly`, `altair`, and `sqlalchemy`, without the
background PostgreSQL/Airflow services of `aidesktop`.

```sh
docker buildx bake datadesktop
./test/image-smoke.sh datadesktop
```
