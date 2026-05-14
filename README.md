# Redmine Tx Heatmap

`redmine_tx_heatmap` renders a weekly or monthly team workload heatmap from Redmine issue data.

## Scope

- Uses all visible project issues in the selected period.
- Includes completed issues.
- Excludes only discarded issues from `redmine_tx_advanced_issue_status`.
- Excludes bug issues when `redmine_tx_advanced_tracker` exposes bug trackers.
- Uses selected Redmine groups as teams.
- Uses active group members, minus configured exclusions, as capacity.
- Excludes weekends and holidays exposed by `redmine_tx_0_base`.
- Does not depend on Redmine saved queries.

## Scheduling Rules

- The default display unit is weekly. Plugin settings can switch the default to monthly.
- Weekly default range is from three weeks before the current week through eight weeks after the current week.
- Weekly column headers use `MM-#N` labels, where `N` is the week number within the start month. The exact date range is available as the header tooltip.
- Monthly default range is from three months before the current month through eight months after the current month.
- Issues with both start and due dates are split across selected periods by inclusive business days.
- Issues with no dates use the fixed version effective date as an assumed due date and spread estimated MD backward across business days.
- If an issue has no dates, a fixed version effective date, and no MD estimate, it is counted as an unknown item in the period that contains the fixed version date.
- Issues with only one date use estimated MD to spread work forward from the start date or backward from the due date across business days.
- If an issue has only one date and no MD estimate, it is counted as an unknown item in the period that contains the known date.
- Issues without `estimated_hours` can use approved DB-based MD estimation rules. Pending candidates are never applied to heatmap totals.
- The current period column is highlighted in the table header and body.
- Clicking a group name toggles member heatmap rows for that group's active, non-excluded members.
- Cell detail lists are loaded on demand by AJAX and use `redmine_tx_0_base`'s shared issue list partial with heatmap-specific virtual columns for period and MD.

## Settings

Team composition is shared through `Redmine Tx Base plugin` settings.

Open Redmine administration plugin settings for `Redmine Tx Base plugin`, then use the organization/team tab to configure:

- groups excluded from team aggregation
- excluded users per group
- room/grouping names such as planning office or programming office

Open `Redmine Tx Heatmap` settings to configure:

- hours per MD
- DB-based MD estimation rules and candidates
- default subproject inclusion
- unmapped row visibility
- default display unit, weekly or monthly

Issue query results are cached for one hour per project, period, subproject option, current user, settings digest, and estimation rule digest.

MD estimation candidates can be rebuilt from historical closed issues:

```
bundle exec rake redmine_tx_heatmap:rebuild_estimation_candidates RAILS_ENV=production
```

For compatibility, heatmap still reads its old local team settings when the shared base team setting has no display groups.

## Verification

After restarting Redmine, enable the `Team heatmap` project module and open the `히트맵` project menu.
