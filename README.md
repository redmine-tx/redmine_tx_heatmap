# Redmine Tx Heatmap

`redmine_tx_heatmap` renders a weekly or monthly team workload heatmap from Redmine issue data.

## Scope

- Uses all visible project issues in the selected period.
- Includes completed issues.
- Excludes only discarded issues from `redmine_tx_advanced_issue_status`.
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
- Issues with no dates are shown in the separate no-date column when their fixed version effective date is inside the selected period.
- Issues with only one date are placed in the current week or month when the selected period contains the current period.
- Issues without `estimated_hours` can use configured subject regex MD rules. Rules can be restricted by group and issue category.
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

- regex MD rules
- default subproject inclusion
- unmapped row visibility
- default display unit, weekly or monthly

Issue query results are cached for one hour per project, period, subproject option, current user, and settings digest.

For compatibility, heatmap still reads its old local team settings when the shared base team setting has no display groups.

## Verification

After restarting Redmine, enable the `Team heatmap` project module and open the `히트맵` project menu.
