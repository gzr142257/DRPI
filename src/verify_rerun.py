"""Verify the four recorded reruns and compare them with retained results.

This script reads results only. It does not fit models or modify the paper.
"""
from pathlib import Path
import argparse
import csv
import datetime
import hashlib
import json
import math
import re
import statistics

ROOT = Path(__file__).resolve().parent
SETTINGS = ['sim_NOelastic_net', 'sim1elastic_net', 'sim1random_forest',
            'sim2elastic_net', 'sim2random_forest', 'sim3elastic_net', 'sim3random_forest',
            'Concreteelastic_net', 'Concreterandom_forest', 'Diabeteselastic_net',
            'Diabetesrandom_forest', 'WineRedelastic_net', 'WineRedrandom_forest']
METHODS = ['SplitCP', 'LCP_Gaussian', 'LCP_kNN', 'LWCI', 'WCP', 'ACPI', 'DRF', 'MAP_DNCPmini']


def read(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def matrix(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.reader(stream))


def write_csv(path, rows):
    if rows:
        with path.open('w', encoding='utf-8-sig', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)


def result_stats(path):
    rows = read(path)
    seeds = [int(row['Seed']) for row in rows]
    coverage = [float(row['Coverage']) for row in rows]
    length = [float(row['Length']) for row in rows]
    if len(rows) != 100 or len(set(seeds)) != 100:
        raise ValueError(f'{path}: expected 100 distinct seeds')
    if any(not math.isfinite(v) for v in coverage + length):
        raise ValueError(f'{path}: nonfinite values')
    if any(not 0 <= v <= 1 for v in coverage) or any(v < 0 for v in length):
        raise ValueError(f'{path}: invalid coverage or length')
    return seeds, [statistics.mean(coverage), statistics.variance(coverage),
                   statistics.mean(length), statistics.variance(length)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('batch', type=Path)
    parser.add_argument('--require-complete', action='store_true')
    parser.add_argument('--finalize', action='store_true', help='Assemble the Table 1 matrix from all 48 completed cell files.')
    args = parser.parse_args()
    batch = args.batch.resolve()
    comparisons, sensitivity, theory = [], [], []
    counts = dict(main=0, sensitivity=0, stability=0, theory=0)
    pending, errors, sources = [], [], []

    def audit(path):
        sources.append(dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest()))

    def compare(path, old, group, name):
        if not path.exists():
            pending.append(str(path))
            return None
        audit(path)
        seeds, values = result_stats(path)
        _, original = result_stats(old)
        counts[group] += 1
        row = dict(Setting=name, File=path.name, Seeds=len(seeds))
        for metric, new, prior in zip(['MeanCoverage', 'VarCoverage', 'MeanLength', 'VarLength'], values, original):
            row[metric] = new
            row['Previous' + metric] = prior
            row['Delta' + metric] = new - prior
        (comparisons if group == 'main' else sensitivity).append(row)
        return seeds

    for setting in SETTINGS:
        reference_seeds = None
        for method in METHODS:
            path = batch / 'main/results' / setting / (method + '.csv')
            seeds = compare(path, ROOT / 'experiment_results' / setting / path.name, 'main', setting)
            if seeds is not None:
                if reference_seeds is None:
                    reference_seeds = seeds
                elif seeds != reference_seeds:
                    errors.append(f'{setting}: main method seeds differ')
        reference_seeds = None
        for value in [0, .25, .5, .75, 1]:
            path = batch / 'sensitivity/sensitivity' / setting / f'DNCPmini_lambda_{value:g}.csv'
            seeds = compare(path, ROOT / 'sensitivity_analysis/dncpmini_lambda' / setting / path.name,
                            'sensitivity', setting)
            if seeds is not None:
                if reference_seeds is None:
                    reference_seeds = seeds
                elif seeds != reference_seeds:
                    errors.append(f'{setting}: lambda seeds differ')

    alpha = [.20, .15, .10, .05]
    epsilon = [.1, .05, .01, .005]
    tau = [.90, .95, .99]
    table_path = batch / 'stability/results/DNCPmini_tau_table.csv'
    old_table = matrix(ROOT / 'experiment_results/DNCPmini_tau_table.csv')
    if args.finalize and all((batch / 'stability/results' / f'cell_{cell:02d}_replicates.csv').exists() for cell in range(1, 49)):
        assembled = [row.copy() for row in old_table]
        for cell in range(1, 49):
            rows = read(batch / 'stability/results' / f'cell_{cell:02d}_replicates.csv')
            if len(rows) != 1000:
                raise ValueError(f'cell {cell}: expected 1000 rows before finalization')
            ai, remainder = divmod(cell - 1, 12)
            assembled[2 + ai][1 + remainder] = f'{sum(row["WithinTolerance"] == "TRUE" for row in rows) / 1000:.4f}'
        with table_path.open('w', encoding='utf-8', newline='') as stream:
            csv.writer(stream).writerows(assembled)
    new_table = matrix(table_path) if table_path.exists() else None
    stability = []
    for cell in range(1, 49):
        path = batch / 'stability/results' / f'cell_{cell:02d}_replicates.csv'
        if not path.exists():
            pending.append(str(path))
            continue
        audit(path)
        rows = read(path)
        ai, remainder = divmod(cell - 1, 12)
        ei, ti = divmod(remainder, 3)
        if len(rows) != 1000 or [int(r['Seed']) for r in rows] != list(range(cell * 1000000 + 1, cell * 1000000 + 1001)):
            errors.append(f'cell {cell}: wrong repetitions/seeds')
        valid = []
        for row in rows:
            c = float(row['Coverage'])
            if not math.isfinite(c) or not 0 <= c <= 1:
                errors.append(f'cell {cell}: invalid coverage')
            within = abs(c - (1 - alpha[ai])) <= epsilon[ei]
            saved_within = row['WithinTolerance'] == 'TRUE'
            if within != saved_within and abs(abs(c - (1 - alpha[ai])) - epsilon[ei]) > 1e-12:
                errors.append(f'cell {cell}: wrong tolerance indicator')
            valid.append(saved_within)
        proportion = statistics.mean(valid)
        previous = float(old_table[2 + ai][1 + ei * 3 + ti])
        if new_table and abs(float(new_table[2 + ai][1 + ei * 3 + ti]) - proportion) > 1e-10:
            errors.append(f'cell {cell}: summary differs from replicates')
        stability.append(dict(Cell=cell, Alpha=alpha[ai], Epsilon=epsilon[ei], TargetTau=tau[ti],
                              NCalibration=int(rows[0]['NCalibration']), Repetitions=len(rows),
                              CountWithinTolerance=sum(valid), TauHat=proportion,
                              PreviousTauHat=previous, DeltaTauHat=proportion - previous))
        counts['stability'] += 1
    if not new_table:
        pending.append(str(table_path))

    theory_path = batch / 'theory/results/gaussian_variance_ratios.csv'
    if theory_path.exists():
        audit(theory_path)
        rows = read(theory_path)
        paper = (ROOT.parent / 'Latex/DRPI_revised_source_20261002/tables/table_03.tex').read_text(encoding='utf-8')
        lookup = {}
        for line in paper.splitlines():
            match = re.match(r'^(\d+)\s*&\s*([\d.]+)\s*&\s*([\d.]+)\s*&\s*([\d.]+)', line)
            if match:
                for a, value in zip([.2, .1, .05], match.groups()[1:]):
                    lookup[int(match.group(1)), a] = value
        for row in rows:
            n, a, value = int(float(row['N'])), float(row['Alpha']), float(row['Ratio'])
            prior = lookup[n, a]
            tolerance = .5 * 10 ** (-len(prior.split('.')[1])) + 1e-10
            if any(not math.isfinite(float(row[k])) or float(row[k]) <= 0 for k in ['VarMLE', 'VarSCP', 'Ratio']):
                errors.append(f'theory {n}/{a}: invalid variance or ratio')
            consistent = abs(value - float(prior)) <= tolerance
            theory.append(dict(N=n, Alpha=a, Ratio=value, PaperRatio=float(prior),
                               Delta=value-float(prior), MatchesDisplayedPrecision=consistent))
            if not consistent:
                errors.append(f'theory {n}/{a}: differs from paper at displayed precision')
        counts['theory'] = len(rows)
        if len(rows) != 27 or len({(r['N'], r['Alpha']) for r in rows}) != 27:
            errors.append('theory: expected 27 distinct cells')
    else:
        pending.append(str(theory_path))

    statuses = []
    for stage in ['main', 'stability', 'theory', 'sensitivity']:
        for directory in sorted((batch / stage / 'records').glob('*')):
            status_file = directory / 'status.csv'
            if (directory / 'interrupted.json').exists():
                state = {'Status': 'interrupted_for_parallel_resume'}
            else:
                state = read(status_file)[0] if status_file.exists() else {'Status': 'running'}
            statuses.append(dict(Stage=stage, Record=str(directory), **state))
            if state['Status'] == 'failed':
                errors.append(f'{directory.name}: {state.get("Error", "failed")}')
            snapshot = directory / ('empirical_coverage_stability.R' if stage == 'stability' else
                                    'theoretical_proof_numerical_integration.R' if stage == 'theory' else
                                    'conformal_prediction_pipeline.R')
            if snapshot.exists() and re.search(r'rosner|outlier|screen_outlier', snapshot.read_text(encoding='utf-8'), re.I):
                errors.append(f'{snapshot}: forbidden exclusion code')
    expected = dict(main=104, sensitivity=65, stability=48, theory=27)
    finished = {stage: sum(r['Stage'] == stage and r['Status'] == 'complete' for r in statuses)
                for stage in ['main', 'sensitivity', 'theory']}
    complete = (counts == expected and not pending and finished == dict(main=13, sensitivity=65, theory=1)
                and all(r['Status'] in ['complete', 'interrupted_for_parallel_resume'] for r in statuses)
                and (batch / 'parallel_status.json').exists())
    report = dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  counts=counts, expected=expected, complete=complete, errors=errors,
                  pending=pending, statuses=statuses, inputs=sources)
    (batch / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    write_csv(batch / 'main_comparison.csv', comparisons)
    write_csv(batch / 'sensitivity_comparison.csv', sensitivity)
    write_csv(batch / 'table1_comparison.csv', stability)
    write_csv(batch / 'table3_comparison.csv', theory)
    lines = ['# 四项实验重跑与核对', '', f'批次：`{batch}`', '',
             f'状态：{"全部完成" if complete else "进行中"}；核对错误：{len(errors)}。', '',
             '| 项目 | 已核对 | 预期 |', '|---|---:|---:|']
    lines += [f'| {name} | {counts[name]} | {expected[name]} |' for name in counts]
    lines += ['', '主实验和敏感性每份CSV应有100个不同种子；表1每格应有1000次重复；表3应有27个不同积分格。',
              '全部运行保留源码快照、参数、环境、输入/输出校验值、划分记录和日志。', '',
              '对照文件：`main_comparison.csv`、`sensitivity_comparison.csv`、`table1_comparison.csv`、`table3_comparison.csv`。',
              '比较对象是现存旧结果和论文表3；未覆盖旧结果，也未改写LaTeX或PDF。', '',
              '最初的表1整表进程在完成部分单元格后停止，已完成的逐次结果保留，其余单元格改为独立并行任务；中断记录在原运行目录。', '',
              '随机森林敏感性实验仅启用G-DRPI；主实验启用全部方法。此前方法消耗的随机数会影响后续森林，因此λ=0.5不应被假定逐行相同。']
    if errors:
        lines += ['', '核对问题：'] + ['- ' + error for error in errors]
    (batch / 'rerun_summary.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ['counts', 'expected', 'complete', 'errors']}, ensure_ascii=False, indent=2))
    if errors or (args.require_complete and not complete):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
