"""Local Windows workforce pipeline orchestrator. Run under authorized ETL identity."""
import argparse
import datetime as dt
import logging
import shutil
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['daily', 'full', 'publish'], default='daily')
    parser.add_argument('--root', type=Path, default=Path(r'C:\Projects\IndianaWorkforceIntelligence'))
    args = parser.parse_args()
    root = args.root.resolve()
    logs = root / 'logs'
    logs.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    logfile = logs / f'pipeline_{stamp}.log'
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s', handlers=[logging.FileHandler(logfile, encoding='utf-8'), logging.StreamHandler()])
    log = logging.getLogger('pipeline')
    lock = logs / 'pipeline.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        log.error('Pipeline lock exists. Check for active execution before removing stale lock: %s', lock)
        return 1
    try:
        etl = root / 'scripts' / 'etl'
        publication = root / 'database' / 'scripts' / '26_publish_runtime.sql'
        csv = root / 'data' / 'raw' / 'idwd' / 'idwd_data_410.csv'
        sqlcmd = shutil.which('sqlcmd')
        if not sqlcmd:
            raise RuntimeError('sqlcmd not found on PATH')
        stages = []
        required = [publication]
        if args.mode in ('daily', 'full'):
            script = etl / 'ingest_bls_laus_runtime.py'
            required.append(script)
            stages.append(('BLS LAUS', [sys.executable, '-u', str(script)], 600))
        if args.mode == 'full':
            oews = etl / 'ingest_bls_oews_runtime.py'
            idwd = etl / 'ingest_idwd_projections_runtime.py'
            required.extend([oews, idwd, csv])
            stages.extend([('BLS OEWS', [sys.executable, '-u', str(oews)], 1800), ('IDWD projections', [sys.executable, '-u', str(idwd), '--file', str(csv)], 600)])
        for path in required:
            if not path.is_file():
                raise FileNotFoundError(path)
        # Step 21 already validates and publishes in a single transaction.
        stages.append(('Validate and publish', [sqlcmd, '-S', 'Matt', '-d', 'IndianaWorkforceDW', '-E', '-C', '-b', '-i', str(publication)], 600))
        log.info('START mode=%s', args.mode)
        for name, command, timeout in stages:
            log.info('START stage=%s', name)
            with logfile.open('a', encoding='utf-8') as out:
                result = subprocess.run(command, cwd=root, stdout=out, stderr=subprocess.STDOUT, timeout=timeout, check=False)
            if result.returncode != 0:
                raise RuntimeError(f'{name} failed with exit code {result.returncode}; inspect {logfile}')
            log.info('PASS stage=%s', name)
        log.info('PIPELINE SUCCESS; log=%s', logfile)
        return 0
    except Exception:
        log.exception('PIPELINE FAILED; remaining stages skipped. Inspect publication status if publication had started.')
        return 1
    finally:
        lock.rmdir()


if __name__ == '__main__':
    sys.exit(main())
