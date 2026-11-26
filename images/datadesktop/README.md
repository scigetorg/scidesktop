# datadesktop

`scidesktop` for general-purpose data science: narrows sciget to the
`datascience` catalog (`sciget-datascience`) and adds a locked Python 3.13
**Data Science** Jupyter kernel (`/opt/datascience-env`) with `numpy`, `scipy`,
`pandas`, `polars`, `pyarrow`, `duckdb` (+ `jupysql` / `duckdb-engine`),
`scikit-learn`, `statsmodels`, `xgboost`, `lightgbm`, `optuna`, `shap`,
`matplotlib`, `seaborn`, `plotly`, `altair`, and `sqlalchemy`. It also carries
Intersect Australia's
[AI Ready workshop](https://github.com/IntersectAustralia/ai-ready-containers):
the workshop's notebooks and kernel, and an Airflow, MLflow and PostgreSQL of
its own in every session. A session opens JupyterLab, whose launcher has
Airflow and MLflow tiles; the workshop page is at `/ai-ready/`
([docs/ai-ready.md](../../docs/ai-ready.md)).

| Component | What it adds |
| --- | --- |
| `sciget-datascience` | narrows sciget to the datascience catalog |
| `datascience-env` | locked Python 3.13 data science kernel (`/opt/datascience-env`) |
| `ai-ready` | AI Ready workshop: notebooks, kernel, Airflow, MLflow and PostgreSQL |

```sh
docker buildx bake datadesktop
./test/image-smoke.sh datadesktop
```
