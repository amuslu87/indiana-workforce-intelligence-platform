# Security architecture and risk register

## Implemented boundaries
Local SQL Server uses Windows Integrated Authentication and local connectivity. ODBC encryption is configured with trust of the local server certificate; this is not production certificate validation. Shiny is hosted on loopback. Raw data, logs, installation packages, backups and credentials are excluded from source control. Source repository and separate aggregate archive are private by project design; verify visibility in GitHub settings before any change.

## Identity and access
rl_dashboard_reader grants approved serving-view reads; usr_dashboard_test is a database test principal without login. Tests confirmed restricted access and denial of underlying schema access. Actual Shiny connections use the configured Windows user, not the restricted principal. A dedicated nonadministrator ETL service identity, protected runtime directories and rl_workforce_etl were provisioned and tested in a proof of concept. Recruitment permissions and scheduled execution under that identity are not deployed. Scheduled tasks currently run under the configured interactive Windows identity.

## Repository controls
Archive synchronization validates six approved aggregate fields, unique dates, numeric values, SHA-256, expected remote and branch, and outgoing file allowlist. Raw posting content stays local. A preliminary scan of 43 eligible new source files found no credential-pattern matches or files larger than 5 MB. Identical SQL verification scripts were detected by SHA-256; the redundant copy was excluded locally. Pattern scans do not prove absence of secrets. Review staged content and repository history before public release.

## Risk register
| Risk | Current mitigation | Remaining action |
|---|---|---|
| Excessive runtime privileges | Tested roles and service identity | Deploy least-privilege identities and test recruitment grants |
| Local certificate trust | Encrypted local connection | Trusted certificate and validation for network deployment |
| Data leakage | Private repositories and exclusions | Formal secret scanning, access review and retention policy |
| Partial publication | Transaction checks and same-day recovery | Atomic recruitment release boundary |
| Local machine failure | Source code and aggregate archive | Database backup, restore drills and recovery objectives |
| Source changes | Collection validation and evidence | Contract monitoring and incident response |

No formal compliance certification, penetration test, enterprise disaster recovery or production security accreditation is claimed.
