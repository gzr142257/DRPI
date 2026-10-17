"""Build paper tables/plot inputs from saved results. Does not fit any model.

Default publication sources are pinned in publication_sources.json when present.
Tables 2/3 are retained only when no corresponding source is configured or supplied.
"""
from pathlib import Path
import argparse,csv,json,statistics,re,hashlib,math,datetime

ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parent
SETTINGS=[('sim_NOelastic_net','Sim Normal-EN'),('sim1elastic_net','Sim 1-EN'),
 ('sim1random_forest','Sim 1-RF'),('sim2elastic_net','Sim 2-EN'),('sim2random_forest','Sim 2-RF'),
 ('sim3elastic_net','Sim 3-EN'),('sim3random_forest','Sim 3-RF'),('Concreteelastic_net','Concrete-EN'),
 ('Concreterandom_forest','Concrete-RF'),('Diabeteselastic_net','Diabetes-EN'),
 ('Diabetesrandom_forest','Diabetes-RF'),('WineRedelastic_net','Wine Red-EN'),('WineRedrandom_forest','Wine Red-RF')]
METHODS=[('Split CP','SplitCP'),('LCP-Gaussian','LCP_Gaussian'),('LCP-KNN','LCP_kNN'),
 ('LWCI','LWCI'),('WCP','WCP'),('ACPI','ACPI'),('C-DRPI','C-DRPI'),('G-DRPI','G-DRPI')]
def read(p):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def stats(rows, expected):
 seeds=[int(r['Seed']) for r in rows]
 if len(seeds)!=expected or len(set(seeds))!=len(seeds):raise ValueError('Wrong seed count or duplicate seeds')
 cov=[float(r['Coverage']) for r in rows];leng=[float(r['Length']) for r in rows]
 if any(not math.isfinite(v) for v in cov+leng) or any(not 0<=v<=1 for v in cov) or any(v<0 for v in leng):
  raise ValueError('Invalid coverage/length value')
 return [statistics.mean(cov),statistics.variance(cov),statistics.mean(leng),statistics.variance(leng)]
def replace_body(text, rows):
 start=text.index('\\midrule')+len('\\midrule')
 end=text.rindex('\\botrule')
 return text[:start]+'\n'+'\n'.join(rows)+'\n'+text[end:]
def main():
 pinned_path=ROOT/'publication_sources.json'
 pinned=json.loads(pinned_path.read_text(encoding='utf-8')) if pinned_path.exists() else {}
 def default_path(name,fallback=None):
  return ROOT/pinned[name] if pinned.get(name) else fallback
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('--paper-root',type=Path,default=PROJECT/'Latex/DRPI_revised_source_20261002')
 ap.add_argument('--result-root',type=Path,default=default_path('result_root',ROOT/'experiment_results'))
 ap.add_argument('--sensitivity-root',type=Path,default=default_path('sensitivity_root',ROOT/'sensitivity_analysis/G-DRPI_lambda'))
 ap.add_argument('--stability-csv',type=Path,default=default_path('stability_csv'))
 ap.add_argument('--case-summary',type=Path,default=default_path('case_summary'))
 ap.add_argument('--theory-csv',type=Path,default=default_path('theory_csv'))
 ap.add_argument('--sc-reference',type=Path,default=default_path('sc_reference'))
 ap.add_argument('--audit-manifest',type=Path,default=default_path('audit_manifest'),help='Require a completed audit and verify its recorded result hashes before generation.')
 ap.add_argument('--expected-seeds',type=int,default=100)
 ap.add_argument('--check-only',action='store_true')
 ap.add_argument('--redraw',action='store_true',help='Redraw the existing stability figure; requires matplotlib/numpy.')
 args=ap.parse_args();paper=args.paper_root.resolve();inputs=[];updates={};summary=[]
 def source(p):
  p=p.resolve();inputs.append(dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()));return p
 if pinned:source(pinned_path)
 if args.audit_manifest:
  audit=json.loads(source(args.audit_manifest).read_text(encoding='utf-8-sig'))
  if not audit.get('complete') or audit.get('errors') or audit.get('pending'):
   raise ValueError('The supplied experiment audit is not complete and clean')
  for entry in audit['inputs']:
   if hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()!=entry['sha256']:
    raise ValueError('Audited result changed: '+entry['path'])
 def result_path(folder,name):
  return source(args.result_root/folder/(name+'.csv'))
 for ti,(folder,title) in enumerate(SETTINGS,4):
  lines=[];seed_reference=None
  for label,name in METHODS:
   p=result_path(folder,name);rows=read(p);values=stats(rows,args.expected_seeds)
   seeds=[r['Seed'] for r in rows]
   if seed_reference is None:seed_reference=seeds
   if seeds!=seed_reference:raise ValueError(f'Method seeds differ in {folder}')
   lines.append(label+' & '+' & '.join(f'{v:.6f}' for v in values)+r' \\')
   summary.append(dict(group='Simulation' if ti<11 else 'Real Data',dataset_title=title,
     dataset_folder=folder,method=label,result_file=p.name,coverage_mean=values[0],
     coverage_var=values[1],length_mean=values[2],length_var=values[3]))
  target=paper/f'tables/table_{ti:02}.tex';updates[target]=replace_body(target.read_text(encoding='utf-8'),lines)
 # Table 1 retains the published 48 cell matrix.
 tau_path=source(args.stability_csv or args.result_root/'G-DRPI_tau_table.csv')
 with tau_path.open(encoding='utf-8-sig',newline='') as f:tau=list(csv.reader(f))
 if len(tau)!=6 or any(len(r)!=13 for r in tau):raise ValueError('Expected a 6x13 stability matrix')
 lines=[]
 for row in tau[2:]:
  for ti,t in enumerate([90,95,99]):
   counts=[str(round(float(row[1+3*ei+ti])*1000)) for ei in range(4)]
   if any(not 0<=int(c)<=1000 for c in counts):raise ValueError('Invalid tolerance count')
   lines.append((row[0].replace('%',r'\%') if ti==0 else '')+f' & {t}'+r'\% & '+' & '.join(counts)+r' \\')
  lines.append(r'\addlinespace')
 target=paper/'tables/table_01.tex';updates[target]=replace_body(target.read_text(encoding='utf-8'),lines[:-1])
 states={'table_01':'generated from saved stability proportions (1000 repetitions)',
   'table_02':'retained; supply --case-summary to update','table_03':'retained; supply --theory-csv to update'}
 states.update({f'table_{ti:02}':'generated from the supplied main-result root (100 splits)' for ti in range(4,17)})
 if args.case_summary:
  rows=read(source(args.case_summary));lookup={r['Algorithm']:r for r in rows};lines=[]
  for label,name in METHODS:
   row=lookup[name]
   if int(row['Repetitions'])!=100:raise ValueError('Table 2 requires 100 verified repetitions per method')
   reps=read(source(args.case_summary.parent/f'{name}_replicates.csv'))
   for rep in reps:
    lower,upper,y=float(rep['Lower']),float(rep['Upper']),float(rep['Response'])
    if int(rep['RowID'])!=337 or abs(float(rep['Length'])-(upper-lower))>1e-8 or int(rep['Covered'])!=int(lower<=y<=upper):
     raise ValueError('Case endpoint/coverage evidence is inconsistent')
   vals=stats([{'Seed':r['Seed'],'Coverage':r['Covered'],'Length':r['Length']} for r in reps],100)
   if abs(vals[0]-float(row['Correct_Frequency']))>1e-10 or abs(vals[3]-float(row['Var_Length']))>1e-7:
    raise ValueError('Case summary disagrees with raw replicates')
   lines.append(f'{label} & {vals[0]:.2f} & {vals[3]:.1f}'+r' \\')
  target=paper/'tables/table_02.tex';updates[target]=replace_body(target.read_text(encoding='utf-8'),lines)
  states['table_02']='generated from verified case replicates'
 if args.theory_csv:
  rows=read(source(args.theory_csv));lookup={(int(float(r['N'])),round(float(r['Alpha']),2)):float(r['Ratio']) for r in rows};lines=[]
  for n in [50,100,500,1000,2000,5000,10000,50000,100000]:
   lines.append(str(n)+' & '+' & '.join(f'{lookup[n,a]:.6f}' for a in [.2,.1,.05])+r' \\')
  target=paper/'tables/table_03.tex';updates[target]=replace_body(target.read_text(encoding='utf-8'),lines)
  states['table_03']='generated from numerical integration export'
 # Read all five lambda cells independently; do not silently borrow a different run.
 lines=[];pooled={v:[] for v in [0,.25,.5,.75,1]};sensitivity_summary=[]
 for folder,title in SETTINGS:
  means=[]
  for value in pooled:
   tag=f'{value:g}';p=source(args.sensitivity_root/folder/f'G-DRPI_lambda_{tag}.csv')
   data=read(p);values=stats(data,args.expected_seeds);means.append(values[0]);pooled[value].append(values[0])
   sensitivity_summary.append(dict(DatasetModel=folder,Lambda=value,Seeds=len(data),MeanCoverage=values[0],
     VarCoverage=values[1],MeanLength=values[2],VarLength=values[3],ResultFile=f'{folder}/{p.name}'))
  lines.append(title+' & '+' & '.join(f'{v:.4f}' for v in means)+r' \\')
 lines += [r'\midrule','Average & '+' & '.join(f'{statistics.mean(v):.4f}' for v in pooled.values())+r' \\']
 target=paper/'tables/table_17.tex';updates[target]=replace_body(target.read_text(encoding='utf-8'),lines)
 states['table_17']='generated from 65 saved per-seed CSVs'
 if args.sc_reference:source(args.sc_reference)
 manifest={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'check_only':args.check_only,
   'table_states':states,'inputs':inputs,'generated_tables':[str(p) for p in updates]}
 if args.check_only:
  print(json.dumps({'tables_checked':len(updates),'source_files':len(inputs),'states':states},ensure_ascii=False,indent=2));return
 for p,text in updates.items():p.write_text(text,encoding='utf-8')
 for path,rows in [(paper/'figures/stability_summary.csv',summary),(args.sensitivity_root/'G-DRPI_lambda_sensitivity_summary.csv',sensitivity_summary)]:
  with path.open('w',encoding='utf-8',newline='') as f:
   w=csv.DictWriter(f,fieldnames=rows[0]);w.writeheader();w.writerows(rows)
 if args.sc_reference:
  (paper/'delivery/SC_reference_table1.csv').write_bytes(args.sc_reference.read_bytes())
 (paper/'delivery').mkdir(exist_ok=True)
 if args.redraw:
  import subprocess,sys
  subprocess.run([sys.executable,str(paper/'figures/redraw_stability.py')],check=True)
 artifacts=list(updates)+[paper/'figures/stability_summary.csv']
 if args.redraw:
  artifacts += [paper/'figures'/('simulation_real_data_stability.'+ext) for ext in ['pdf','svg','png']]
 manifest['generated_artifacts']=[dict(path=str(p.resolve()),sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in artifacts]
 manifest['figure_state']='redrawn from the supplied audited main results' if args.redraw else 'not redrawn'
 (paper/'delivery/result_generation_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
 print('Saved tables, plot summary and generation manifest:',paper)
if __name__=='__main__':main()
