"""Resume this recorded four-stage batch with bounded independent R jobs.

Completed results and the two already running main/sensitivity jobs are reused.
Stability cells use their original cell IDs and random seeds.
"""
import argparse
import atexit
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parent
MATRIX = [('sim_NO', 'elastic_net')] + [(d, m) for d in ['sim1', 'sim2', 'sim3', 'Concrete', 'Diabetes', 'WineRed']
                                        for m in ['elastic_net', 'random_forest']]


def load_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('batch', type=Path)
    parser.add_argument('--rscript', type=Path, required=True)
    parser.add_argument('--main-workers', type=int, default=3)
    parser.add_argument('--sensitivity-workers', type=int, default=3)
    parser.add_argument('--stability-workers', type=int, default=4)
    args = parser.parse_args()
    batch = args.batch.resolve()
    if not args.rscript.is_file() or min(args.main_workers, args.sensitivity_workers, args.stability_workers) < 1:
        raise ValueError('Provide an existing Rscript executable and positive worker counts.')
    lock = batch / 'parallel_dispatch.lock'
    with lock.open('x', encoding='utf-8') as stream:
        stream.write(str(os.getpid()))
    atexit.register(lambda: lock.unlink(missing_ok=True))
    plan = json.loads((batch / 'parallel_resume_plan.json').read_text(encoding='utf-8-sig'))
    data = ROOT.parent / 'Real Data'
    dispatch = batch / 'dispatch'
    dispatch.mkdir(exist_ok=True)
    environment = dict(os.environ, OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1', MKL_NUM_THREADS='1')

    def run(job):
        stage, key, script, options = job
        record_root = batch / stage / 'records'
        command = [str(args.rscript), str(ROOT / script), *options, f'--runs-root={record_root}']
        job_path = dispatch / (stage + '_' + key)
        def artifact(suffix):
            return Path(str(job_path) + suffix)
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        artifact('.arguments.json').write_text(json.dumps(command, ensure_ascii=False, indent=2), encoding='utf-8')
        with artifact('.stdout.log').open('w', encoding='utf-8') as out, artifact('.stderr.log').open('w', encoding='utf-8') as err:
            process = subprocess.run(command, stdout=out, stderr=err, env=environment,
                                     creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        artifact('.status.json').write_text(json.dumps(dict(stage=stage, key=key,
            exit_code=process.returncode, started_utc=started,
            ended_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()), indent=2), encoding='utf-8')
        if process.returncode:
            raise RuntimeError(f'{stage}/{key} exited {process.returncode}; see {job_path}.stderr.log')
        print(f'Completed {stage}/{key}', flush=True)
        return job

    jobs = dict(main=[], sensitivity=[], stability=[])
    inflight_main = plan['inflight_main'] if not (Path(plan['inflight_records']['main']) / 'status.csv').exists() else None
    inflight_sensitivity = plan['inflight_sensitivity'] if not (Path(plan['inflight_records']['sensitivity']) / 'status.csv').exists() else None
    for dataset, model in MATRIX:
        key = dataset + model
        folder = batch / 'main/results' / key
        if key != inflight_main and not (folder / 'G-DRPI.csv').exists():
            jobs['main'].append(('main', key, 'conformal_prediction_pipeline.R', [
                '--stage=main', f'--dataset={dataset}', f'--base-model={model}', '--method=all', '--n-seeds=100',
                f'--data-root={data}', f'--export-root={batch / "main/results"}']))
        for value in [0, .25, .5, .75, 1]:
            lambda_key = f'{key}_lambda_{value:g}'
            path = batch / 'sensitivity/sensitivity' / key / f'G-DRPI_lambda_{value:g}.csv'
            if lambda_key != inflight_sensitivity and not path.exists():
                jobs['sensitivity'].append(('sensitivity', lambda_key, 'conformal_prediction_pipeline.R', [
                    '--stage=main', f'--dataset={dataset}', f'--base-model={model}', '--method=G-DRPI',
                    '--n-seeds=100', f'--g-drpi-lambda={value:g}', '--lambda-sensitivity-output=true',
                    f'--data-root={data}', f'--export-root={batch / "sensitivity/sensitivity"}']))
    for cell in range(1, 49):
        if not (batch / 'stability/results' / f'cell_{cell:02d}_replicates.csv').exists():
            jobs['stability'].append(('stability', f'cell_{cell:02d}', 'empirical_coverage_stability.R', [
                '--mode=experiment', '--seed-max=1000', f'--cells={cell}',
                f'--export-root={batch / "stability/cell_jobs" / f"cell_{cell:02d}"}']))
    pools = {stage: ThreadPoolExecutor(max_workers=getattr(args, stage + '_workers')) for stage in jobs}
    futures = [pools[stage].submit(run, job) for stage in jobs for job in jobs[stage]]
    errors = []
    for future in as_completed(futures):
        try:
            stage, key, script, options = future.result()
            if stage == 'stability':
                source = batch / 'stability/cell_jobs' / key
                shutil.copyfile(source / (key + '_replicates.csv'), batch / 'stability/results' / (key + '_replicates.csv'))
        except Exception as error:
            errors.append(str(error))
            print(str(error), flush=True)
    for pool in pools.values():
        pool.shutdown(wait=True)

    # Finish collecting already running R processes, without launching duplicates.
    for stage, record in plan['inflight_records'].items():
        status = Path(record) / 'status.csv'
        while not status.exists():
            time.sleep(2)
        if load_csv(status)[0]['Status'] != 'complete':
            errors.append(f'Existing job failed: {record}')

    missing = []
    for dataset, model in MATRIX:
        folder = dataset + model
        for method in ['SplitCP', 'LCP_Gaussian', 'LCP_kNN', 'LWCI', 'WCP', 'ACPI', 'C-DRPI', 'G-DRPI']:
            path = batch / 'main/results' / folder / (method + '.csv')
            if not path.exists():
                missing.append(str(path))
        for value in [0, .25, .5, .75, 1]:
            path = batch / 'sensitivity/sensitivity' / folder / f'G-DRPI_lambda_{value:g}.csv'
            if not path.exists():
                missing.append(str(path))
    missing += [str(batch / 'stability/results' / f'cell_{cell:02d}_replicates.csv')
                for cell in range(1, 49)
                if not (batch / 'stability/results' / f'cell_{cell:02d}_replicates.csv').exists()]
    if not missing:
        original = ROOT / 'experiment_results/G-DRPI_tau_table.csv'
        with original.open(encoding='utf-8-sig', newline='') as stream:
            table = list(csv.reader(stream))
        for cell in range(1, 49):
            rows = load_csv(batch / 'stability/results' / f'cell_{cell:02d}_replicates.csv')
            if len(rows) != 1000:
                raise ValueError(f'Wrong repetition count: cell {cell}')
            ai, remainder = divmod(cell - 1, 12)
            table[ai + 2][remainder + 1] = f'{sum(r["WithinTolerance"] == "TRUE" for r in rows) / 1000:.4f}'
        with (batch / 'stability/results/G-DRPI_tau_table.csv').open('w', encoding='utf-8', newline='') as stream:
            csv.writer(stream).writerows(table)
    state = dict(status='complete' if not missing else 'failed', errors=errors, missing=missing,
                 ended_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    (batch / 'parallel_status.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(state, ensure_ascii=False), flush=True)
    if errors:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
