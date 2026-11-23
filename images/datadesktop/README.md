# datadesktop

`scidesktop` for general-purpose data science: narrows sciget to the
`datascience` catalog (`sciget-datascience`) and adds a locked Python 3.13
**Data Science** Jupyter kernel (`/opt/datascience-env`) with `numpy`, `scipy`,
`pandas`, `polars`, `pyarrow`, `duckdb` (+ `jupysql` / `duckdb-engine`),
`scikit-learn`, `statsmodels`, `xgboost`, `lightgbm`, `optuna`, `shap`,
`matplotlib`, `seaborn`, `plotly`, `altair`, and `sqlalchemy`, without the
background PostgreSQL/Airflow services of `aidesktop`.

| Component | What it adds |
| --- | --- |
| `sciget-datascience` | narrows sciget to the datascience catalog |
| `datascience-env` | locked Python 3.13 data science kernel (`/opt/datascience-env`) |

```sh
docker buildx bake datadesktop
./test/image-smoke.sh datadesktop
```
