# Operational runbook

## Environment
Windows, SQL Server Developer, ODBC Driver 18, Python/Anaconda, R 4.4.2, Git and PowerShell. Run commands from the project root. Configure local database identity and connection settings for the actual host. Source scripts include historical experiments and migrations; do not execute all SQL files in numeric order blindly. A clean-install migration sequence has not been validated.

## Routine operation
Workforce task IndianaWorkforce-DailyPipeline is scheduled at 6 AM local time; recruitment task IndianaWorkforce-DailyRecruitment at 5 PM local time. Recruitment requires the configured interactive user session and machine availability. Check task history and logs after execution. The separate Airflow proof of concept is not required.

```powershell
python .\scripts\24_run_pipeline.py
python .\scripts\34_run_recruitment_pipeline.py --check
python .\scripts\34_run_recruitment_pipeline.py
```
The recruitment check compiles relevant scripts; it does not perform end-to-end execution. A successful same-day run skips website collection but reruns compensation assessment, reconciliation, archive export and synchronization. A fresh-day run collects complete inventory, retrieves new/changed/retry/periodic details, processes lifecycle, standardizes compensation and exports aggregate history. Periodic detail recheck is seven days. The collector uses HTTPS, bounded retries and stops on access/rate-limit responses. Do not bypass source restrictions.

## Dashboard operation
```powershell
& "C:\Program Files\R\R-4.4.2\bin\Rscript.exe" -e "shiny::runApp('dashboard/shiny',host='127.0.0.1',port=3838,launch.browser=TRUE)"
& "C:\Program Files\R\R-4.4.2\bin\Rscript.exe" -e "shiny::runApp('dashboard/recruitment',host='127.0.0.1',port=3839,launch.browser=TRUE)"
```
Run in separate terminals. Stop with Ctrl+C. Recruitment refreshes every five minutes and retains last good data on refresh failure. Compensation summary is global rather than linked to inventory filters. Historical standardized compensation is not available through the active-only serving view.

## Failure recovery
1. Inspect task exit code and pipeline logs; identify the failed stage.
2. Check source collection completeness, SQL connectivity and lineage before rerun.
3. Do not force removal from an incomplete inventory or manually edit facts to hide errors.
4. If collection is committed, rerun the orchestrator for same-day compensation/archive recovery. If collection succeeded but load failed, inspect the existing manifest before recollection; automatic reuse is not implemented.
5. If a lock remains after abnormal termination, confirm no pipeline process is running before removing it.
6. For archive errors, verify CSV/checksum and remote status; do not force-push.
7. Record incident, impact, recovery action and validation results.

## SQL maintenance
Current compensation assessment table: script 47; current standardized view: 48; integration: 42; compensation serving: 49. Script 37 supplies current agency mapping and recruitment serving definitions. Earlier salary parser/view scripts are historical and must not overwrite current definitions. Manual correction scripts are reviewed data changes, not daily tasks. Database restore and full clean-install procedures remain untested.
