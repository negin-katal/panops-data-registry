#!/usr/bin/env python3
"""
Optuna (TPE) hyperparameter search for one learner x one response.

Optuna is used ONLY as the sampler. Every trial is scored by
scripts/optuna_cv_objective.R, i.e. by the same ranger / xgboost / lightgbm R
code that trains the reported models, on the same grouped 5-fold CV objective as
the exhaustive-grid sweeps (folds = disjoint site groups, seed 42, averaged over
M2_12m and M6_raw_12m). So the only thing that differs from the grid-tuned
variants is the SEARCH STRATEGY, not the objective, the folds, or the learner.

The search space is deliberately WIDER than the grids: 4 dimensions for RF and
7 for the boosters. An exhaustive grid over that is >10,000 combinations, which
is where TPE actually earns its keep.

    python3 optuna_tune.py <RF|XGB|LGB> <response> [n_trials] [n_jobs]

Writes  plots/V10/Optuna/<learner>_<response>_trials.csv
        plots/V10/Optuna/<learner>_<response>_best.json
"""
import json, os, subprocess, sys, warnings
warnings.filterwarnings("ignore")
import optuna
optuna.logging.set_verbosity(optuna.logging.WARNING)

ROOT    = "/mnt/gsdata/projects/panops/panops-data-registry/data/flux"
RSCRIPT = "/home/nk1125/miniconda3/envs/clean_r_env/bin/Rscript"
OBJ     = os.path.join(ROOT, "scripts", "optuna_cv_objective.R")
OUT     = os.path.join(ROOT, "plots", "V10", "Optuna")
SEED    = 42

learner  = sys.argv[1]
response = sys.argv[2]
n_trials = int(sys.argv[3]) if len(sys.argv) > 3 else 50
n_jobs   = int(sys.argv[4]) if len(sys.argv) > 4 else 6


def space(t):
    """Search space per learner - wider than the exhaustive grids."""
    if learner == "RF":
        return dict(
            mtry_frac       = t.suggest_float("mtry_frac", 0.02, 1.0),
            num_trees       = t.suggest_int("num_trees", 250, 1500, step=250),
            min_node_size   = t.suggest_int("min_node_size", 1, 30),
            sample_fraction = t.suggest_float("sample_fraction", 0.4, 1.0),
        )
    if learner == "XGB":
        return dict(
            learning_rate    = t.suggest_float("learning_rate", 0.01, 0.30, log=True),
            nrounds          = t.suggest_int("nrounds", 100, 1000, step=100),
            max_depth        = t.suggest_int("max_depth", 1, 8),
            min_child_weight = t.suggest_float("min_child_weight", 1.0, 20.0),
            subsample        = t.suggest_float("subsample", 0.5, 1.0),
            colsample_bytree = t.suggest_float("colsample_bytree", 0.2, 1.0),
            reg_lambda       = t.suggest_float("reg_lambda", 1e-3, 50.0, log=True),
        )
    if learner == "LGB":
        return dict(
            learning_rate    = t.suggest_float("learning_rate", 0.01, 0.30, log=True),
            nrounds          = t.suggest_int("nrounds", 100, 1000, step=100),
            num_leaves       = t.suggest_int("num_leaves", 2, 63),
            min_data_in_leaf = t.suggest_int("min_data_in_leaf", 2, 40),
            feature_fraction = t.suggest_float("feature_fraction", 0.2, 1.0),
            bagging_fraction = t.suggest_float("bagging_fraction", 0.5, 1.0),
            lambda_l2        = t.suggest_float("lambda_l2", 1e-3, 50.0, log=True),
        )
    raise ValueError(learner)


def objective(trial):
    p = space(trial)
    try:
        r = subprocess.run(
            [RSCRIPT, OBJ, learner, response, json.dumps(p)],
            capture_output=True, text=True, cwd=ROOT, timeout=3600,
            env={**os.environ, "OMP_NUM_THREADS": "1"},
        )
        val = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "NA"
        if val == "NA":
            raise optuna.TrialPruned()
        return float(val)
    except (subprocess.TimeoutExpired, ValueError, IndexError):
        raise optuna.TrialPruned()


def main():
    os.makedirs(OUT, exist_ok=True)
    study = optuna.create_study(
        direction="minimize",
        sampler=optuna.samplers.TPESampler(seed=SEED),
        study_name=f"{learner}_{response}",
    )
    study.optimize(objective, n_trials=n_trials, n_jobs=n_jobs,
                   catch=(Exception,), show_progress_bar=False)

    done = [t for t in study.trials if t.value is not None]
    if not done:
        print(f"{learner}/{response}: ALL TRIALS FAILED", flush=True)
        return

    rows = ["trial,value," + ",".join(sorted(done[0].params))]
    for t in done:
        rows.append(f"{t.number},{t.value:.8f}," +
                    ",".join(str(t.params[k]) for k in sorted(t.params)))
    with open(os.path.join(OUT, f"{learner}_{response}_trials.csv"), "w") as f:
        f.write("\n".join(rows) + "\n")

    best = dict(learner=learner, response=response,
                best_value=study.best_value, n_trials=len(done),
                params=study.best_params)
    with open(os.path.join(OUT, f"{learner}_{response}_best.json"), "w") as f:
        json.dump(best, f, indent=2)

    print(f"{learner}/{response}: best CV={study.best_value:.5f} "
          f"({len(done)}/{n_trials} trials ok) {study.best_params}", flush=True)


if __name__ == "__main__":
    main()
