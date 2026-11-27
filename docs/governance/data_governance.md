# Data governance and analytical standards

## Ownership and controls
Proposed operating model: business data owner approves definitions and usage; steward maintains metadata and reference mappings; architect owns standards and design decisions; engineer owns pipelines and recovery; analyst owns analytical interpretation; security lead reviews access and risk. These are proposed responsibilities, not staffed roles.

Control objects include PipelineRun, DataQualityRule, DataQualityResult, PublishedBatch and pipeline health view. Quarantine.RejectedObservation supports exception retention. Workforce publication validates schema, uniqueness, domains, lineage, reconciliation and completeness; freshness is a warning. Coverage is not equivalent to exhaustive testing. Recruitment uses collection-specific validation and transaction checks rather than assuming identical governance coverage.

## Recruitment semantics
Active means observed in the latest complete listing inventory. Newly observed means first seen by the platform, not necessarily newly advertised. No longer observed does not establish hiring, cancellation or expiration. Reactivated means observed again after absence. Cumulative unique postings counts distinct historical posting identities. Baseline observations must be identified separately. Incomplete listing collections must not drive removal decisions. Detail completeness is separate from listing completeness.

## Compensation policy
Select reviewed applicable override first, then unambiguous description base salary, then valid listing fallback. Use the lower advertised base endpoint; exclude bonuses, tips, differentials and unrelated budgets. Strict listing format validation rejects malformed grouping and reversed ranges. Multiple conflicting description candidates remain unresolved. Explicit frequencies take precedence; bare amounts may be assumed annual and flagged for review. Hourly FTE annualization uses 75 hours per biweekly period times 26 = 1950 hours. Monthly and biweekly values use 12 and 26 periods respectively. Estimates are not guaranteed earnings. Parser 2.1 retains evidence, candidate count and source identifiers. VALIDATED means rule-based classification, not independent human verification.

## Data quality and limitations
At checkpoint 461/468 salaries available, 142 explicit frequencies, 319 assumed annual, seven unresolved. Fourteen reviewed overrides. Availability is not accuracy. Parser misses some wording and may fall back despite unrecognized conflicting evidence. Mixed-unit ranges and multi-role descriptions need additional controls. Overrides may cease applying when detail lineage changes. Skill extraction is keyword-based, not a verified qualification classification. Agency aliases are limited reference mappings. Source revisions and missing periods require future controls.

## Proposed governance extensions
Maintain a business glossary, source contracts, named stewards, issue register, retention schedule and change approvals. Review privacy and source terms before new ingestion. Do not infer that public availability removes all obligations. Responsible AI, model validation and human oversight are future governance requirements; no production AI model is deployed.
