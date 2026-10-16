"""Exercise CLI configuration without loading packages or running models."""
from pathlib import Path
import csv,json,subprocess,tempfile,argparse,shutil
ROOT=Path(__file__).resolve().parent
ALL={'splitcp','lcp-gaussian','lcp-knn','lwci','wcp','acpi','dncp','dncp-mini'}
def main():
 ap=argparse.ArgumentParser()
 ap.add_argument('--rscript',default=shutil.which('Rscript'),help='Rscript executable; defaults to Rscript on PATH.')
 args=ap.parse_args()
 if not args.rscript:
  ap.error('Rscript was not found on PATH. Install R or pass --rscript with the path to Rscript.')
 resolved_rscript=shutil.which(args.rscript)
 if not resolved_rscript:
  ap.error('The --rscript executable was not found or is not executable. Provide a valid path to Rscript.')
 args.rscript=resolved_rscript
 checks=[]
 with tempfile.TemporaryDirectory(prefix='drpi_entry_checks_') as temp:
  for method,expected in [('all',ALL),('wcp',{'wcp'}),('both',{'dncp','dncp-mini'}),('c-drpi,g-drpi',{'dncp','dncp-mini'})]:
   run_root=Path(temp)/method.replace(',','_')
   cmd=[args.rscript,str(ROOT/'conformal_prediction_pipeline.R'),'--check-config=true',f'--method={method}',f'--runs-root={run_root}']
   proc=subprocess.run(cmd,capture_output=True,text=True,errors='replace')
   if proc.returncode:raise RuntimeError(proc.stdout+proc.stderr)
   run=next(run_root.iterdir())
   with (run/'method_flags.csv').open(encoding='utf-8-sig') as f:rows=list(csv.DictReader(f))
   enabled={r['Method'] for r in rows if r['Enabled']=='TRUE'}
   assert enabled==expected,(method,enabled)
   assert not (run/'inputs.csv').exists(),'Configuration check unexpectedly loaded model inputs'
   checks.append({'method':method,'enabled':sorted(enabled),'passed':True})
 report={'models_executed':False,'checks':checks}
 (ROOT/'entry_validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
 print(json.dumps(report,indent=2))
if __name__=='__main__':main()
