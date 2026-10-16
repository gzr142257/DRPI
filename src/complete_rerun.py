"""Keep a long local experiment batch running through collection and verification.

Monitor the already started dispatcher, refresh the report, assemble Table 1,
and retry missing independent jobs after a dispatcher failure. No paper edits.
"""
import argparse
import ctypes
import csv
from ctypes import wintypes
import datetime
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent


def running(pid):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.WaitForSingleObject.restype = wintypes.DWORD
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.OpenProcess(0x100000, False, pid)
    if not handle:
        return False
    try:
        return kernel.WaitForSingleObject(handle, 0) == 0x102
    finally:
        kernel.CloseHandle(handle)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('batch', type=Path)
    parser.add_argument('--dispatcher-pid', type=int, required=True)
    parser.add_argument('--rscript', type=Path, required=True)
    args = parser.parse_args()
    batch = args.batch.resolve()
    status_path = batch / 'completion_status.json'
    started = datetime.datetime.now(datetime.timezone.utc).isoformat()

    def state(status, **values):
        payload = dict(status=status, started_utc=started,
                       updated_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), **values)
        status_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding='utf-8')

    def collect():
        for path in (batch / 'stability/cell_jobs').glob('cell_*/cell_*_replicates.csv'):
            target = batch / 'stability/results' / path.name
            if not target.exists():
                with path.open(encoding='utf-8-sig', newline='') as stream:
                    rows = list(csv.DictReader(stream))
                if len(rows) != 1000 or any(row.get('WithinTolerance') not in ['TRUE', 'FALSE'] for row in rows):
                    continue
                shutil.copyfile(path, target)
        early = batch / 'stability/early_cells_verified'
        ready = False
        for record in (batch / 'stability/records').glob('*'):
            status = record / 'status.csv'
            arguments = record / 'arguments.R'
            if status.exists() and arguments.exists() and str(early).replace('\\', '/') in arguments.read_text(encoding='utf-8').replace('\\\\', '/'):
                with status.open(encoding='utf-8-sig', newline='') as stream:
                    ready = next(csv.DictReader(stream))['Status'] == 'complete'
                if ready:
                    break
        if ready:
            for path in early.glob('cell_*_replicates.csv'):
                shutil.copyfile(path, batch / 'stability/results' / path.name)

    def verify(final=False):
        command = [sys.executable, str(ROOT / 'verify_rerun.py'), str(batch)]
        if final:
            command += ['--finalize', '--require-complete']
        with (batch / 'completion_verification_stdout.log').open('w', encoding='utf-8') as out, \
             (batch / 'completion_verification_stderr.log').open('w', encoding='utf-8') as err:
            return subprocess.run(command, stdout=out, stderr=err, creationflags=subprocess.CREATE_NO_WINDOW).returncode

    state('running', dispatcher_pid=args.dispatcher_pid)
    try:
        while running(args.dispatcher_pid):
            collect()
            verify()
            time.sleep(45)
        collect()
        result = verify(final=True)
        for attempt in range(1, 4):
            if result == 0:
                break
            report = json.loads((batch / 'verification.json').read_text(encoding='utf-8'))
            if report['errors']:
                break
            lock = batch / 'parallel_dispatch.lock'
            if lock.exists():
                lock_pid = int(lock.read_text(encoding='utf-8-sig').strip())
                if running(lock_pid):
                    raise RuntimeError(f'Dispatcher {lock_pid} is still running')
                lock.unlink()
            state('retrying_missing_jobs', attempt=attempt)
            with (batch / f'retry_{attempt}_stdout.log').open('w', encoding='utf-8') as out, \
                 (batch / f'retry_{attempt}_stderr.log').open('w', encoding='utf-8') as err:
                subprocess.run([sys.executable, str(ROOT / 'run_parallel_experiments.py'), str(batch),
                                '--rscript', str(args.rscript)], stdout=out, stderr=err,
                               creationflags=subprocess.CREATE_NO_WINDOW)
            collect()
            result = verify(final=True)
        if result:
            state('failed', verification_exit_code=result,
                  details='See verification.json and completion_verification_stderr.log; retained results are preserved.')
            raise SystemExit(1)
        state('complete', details='All four experiments collected and independently verified; paper remains unchanged.')
    except Exception as error:
        state('failed', error=str(error))
        raise


if __name__ == '__main__':
    main()
