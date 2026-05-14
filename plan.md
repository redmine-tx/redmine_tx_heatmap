# Redmine Heatmap MD 추정 Ruleset 구현 계획

## 1. 배경과 목표

이 플러그인은 `/var/www/redmine/plugins/redmine_tx_heatmap`에 있는 Redmine 업무부하 히트맵 플러그인이다. 현재 히트맵은 이슈를 월별로 배치하고, `estimated_hours / 8` 기반으로 MD를 산정한다.

문제는 Art 계열 업무처럼 몇 달씩 이어지거나 `estimated_hours`, `start_date`, `due_date`가 누락된 이슈에서 팀별 월간 업무부하가 현실과 크게 어긋나는 것이다. 날짜 분배 정책은 이미 개선된 상태로 보고, 이번 구현의 주 목표는 "비슷한 종류의 이슈가 보통 비슷한 MD를 가진다"는 가정을 Redmine 데이터만으로 일반화하는 것이다.

`art_tool`의 데이터, 규칙, 특수 분류는 절대 참조하지 않는다. 이 구현은 범용 Redmine 플러그인 기능이어야 한다.

## 2. 현재 동작과 유지해야 할 정책

현재 MD 산정은 `estimated_hours`가 있으면 `estimated_hours / 8`을 사용하고, 없으면 unknown으로 남긴다.

날짜 배치 정책은 유지한다. `start_date`와 `due_date`가 모두 있으면 해당 기간 영업일에 분배한다. `start_date`만 있으면 추정 MD를 시작일부터 앞으로 분배한다. `due_date`만 있으면 추정 MD를 종료일부터 뒤로 분배한다. 둘 다 없고 `fixed_version.effective_date`가 있으면 그 날짜를 `due_date`로 간주한다. 날짜와 추정 MD가 모두 부족하면 unknown 또는 기준 월에만 표시한다.

기존 제목 패턴 기반 설정 rule은 사용하지 않는다. 새 DB 기반 rule이 없으면 unknown으로 남긴다.

## 3. 설계 원칙

MD 추정 rule은 사람이 검토하고 설명 가능해야 한다. 통계 후보가 자동으로 운영 히트맵에 반영되면 안 된다.

같은 유형의 일감은 보통 `tracker`, `category`, 실제 작업자 그룹, 제목 구조가 같다. 특히 제목 prefix는 의미 있는 정보일 수 있으므로 제거하지 말고 feature로 보존한다.

Redmine `IssueCategory`는 project별 ID를 가지므로 rule의 주요 비교값은 `category_id`가 아니라 정규화된 `category_name_key`로 둔다. `category_id`는 수동 exact restriction 용도로만 선택적으로 저장한다.

기본 MD 환산값은 hard-coded `8` 대신 plugin setting `hours_per_md`로 분리한다. 기본값은 `8.0`이다.

## 4. 데이터 모델

`db/migrate/001_create_tx_heatmap_estimation_rules.rb`를 추가한다. 모델은 `app/models/redmine_tx_heatmap/estimation_rule.rb`에 두고 `RedmineTxHeatmap::EstimationRule`로 정의한다.

`tx_heatmap_estimation_rules` 필드는 `enabled:boolean`, `priority:integer`, `owner_group_id:integer`, `tracker_id:integer`, `category_name_key:string`, `category_label:string`, `category_id:integer`, `prefix_signature:string`, `title_template:text`, `stage_token:string`, `md:decimal(10,2)`, `confidence:string`, `source:string`, `sample_count:integer`, `median_md:decimal(10,2)`, `spread:decimal(10,4)`, `fingerprint:string`, `note:text`, `created_at`, `updated_at`로 한다.

`db/migrate/002_create_tx_heatmap_estimation_candidates.rb`를 추가한다. 모델은 `app/models/redmine_tx_heatmap/estimation_candidate.rb`에 두고 `RedmineTxHeatmap::EstimationCandidate`로 정의한다.

`tx_heatmap_estimation_candidates` 필드는 rule 조건 필드와 동일한 signature 필드, `status:string`, `sample_count:integer`, `median_md:decimal(10,2)`, `p25_md:decimal(10,2)`, `p75_md:decimal(10,2)`, `dispersion:decimal(10,4)`, `confidence:string`, `example_issue_ids:text`, `stats_snapshot:text`, `fingerprint:string`, `created_at`, `updated_at`로 한다.

`example_issue_ids`와 `stats_snapshot`은 DB 호환성을 위해 JSON 컬럼이 아니라 text에 JSON 문자열로 저장한다. MySQL/MariaDB/SQLite 호환성을 우선한다.

`fingerprint`는 `owner_group_id`, `tracker_id`, `category_name_key`, `prefix_signature`, `title_template`, `stage_token`을 `\x1f`로 join한 뒤 SHA256으로 만든다. rules와 candidates 모두 fingerprint unique index를 둔다.

## 5. 핵심 서비스

`lib/redmine_tx_heatmap/team_resolver.rb`를 추가한다. `planned_owner_group(issue)`는 `worker` 기준으로 히트맵에 쓰는 팀을 반환한다. `redmine_tx_auto_date`가 없는 환경처럼 worker association이 없거나 worker가 비어 있으면 assignee로 fallback한다.

`lib/redmine_tx_heatmap/issue_signature.rb`를 추가한다. `IssueSignature.build(issue, owner_group_id:)`는 owner group, tracker, category name key, prefix signature, title template, stage token을 반환한다.

`prefix_signature`는 제목 앞쪽의 bracket/parenthesis prefix와 첫 colon 앞 prefix를 보존해 만든다. 예시는 `[FX][Boss] 스킬 A`, `(애니) 캐릭터: 공격` 같은 형태다. prefix는 제거하거나 무시하지 않는다.

`title_template`은 같은 owner group, tracker, category, prefix bucket 안에서 제목 token을 비교해 반복되는 literal은 유지하고 변하는 고유명사성 구간은 `{slot}`으로 치환해 만든다. 캐릭터명 사전이나 art_tool 특수 규칙은 사용하지 않는다.

`stage_token`은 제목의 마지막 colon segment 또는 반복적으로 나타나는 종료 단계 문구에서 추출한다. 예시는 `러프`, `본작업`, `수정`, `최종`, `이펙트 제작` 같은 반복 문구다. 단, 고정 목록으로 판정하지 말고 샘플 내 반복성으로 판정한다.

`lib/redmine_tx_heatmap/issue_estimator.rb`를 추가한다. `IssueEstimator.estimate(issue)`는 `EstimateResult(md:, source:, confidence:, rule_id:, explanation:)`를 반환한다.

`IssueEstimator`의 우선순위는 `estimated_hours / hours_per_md`, 승인된 DB rule, unknown 순서다. pending candidate는 절대 runtime estimate에 쓰지 않는다.

`lib/redmine_tx_heatmap/estimation_candidate_builder.rb`를 추가한다. `CandidateBuilder.rebuild(scope:, min_samples:, dry_run:)`은 historical issue를 스캔해 pending candidate를 생성하거나 갱신한다.

## 6. Candidate 생성 정책

기본 rebuild 대상은 closed issue 중 `estimated_hours > 0`, tracker 존재, category 존재, owner group 식별 가능 조건을 만족하는 이슈다. 버그 tracker로 분류된 이슈는 히트맵과 후보 생성에서 제외한다.

discarded status는 제외한다. Redmine core의 closed status와 플러그인의 discarded status 개념이 모두 있으면 discarded 제외를 먼저 적용하고 closed만 사용한다.

목표 MD는 `estimated_hours / hours_per_md`로 계산한다. v1에서는 MD ground truth는 `estimated_hours`, owner group 추론은 `worker` 우선 및 assignee fallback으로 제한한다.

기본 그룹핑 키는 `owner_group_id + tracker_id + category_name_key + prefix_signature + title_template/stage_token`이다.

최소 샘플 수는 기본 `5`다. 대표 MD는 평균이 아니라 median을 사용한다.

분산도는 `IQR / median`으로 계산한다. median이 0이거나 비정상 값이면 candidate를 만들지 않는다.

confidence 기준은 `high = sample_count >= 8 && dispersion <= 0.25`, `medium = sample_count >= 5 && dispersion <= 0.35`, 나머지는 `low`다. low candidate는 저장하되 기본 목록에서는 접어서 보여준다.

approve 시 candidate의 median MD를 rule의 `md`로 복사한다. rule의 priority 기본값은 `100`이고, 더 구체적인 rule이 먼저 매칭되도록 동일 priority에서는 specificity가 높은 rule을 우선한다.

reject된 candidate는 같은 fingerprint로 다시 pending 생성하지 않는다. 다만 통계값은 갱신해 관리자가 나중에 재검토할 수 있게 한다.

## 7. 관리자 UI와 라우팅

`app/controllers/heatmap_estimation_rules_controller.rb`를 추가한다. 모든 변경 액션은 `require_admin`으로 보호한다.

routes는 `GET /heatmap/estimation_rules`, `PATCH /heatmap/estimation_rules/:id`, `POST /heatmap/estimation_rules/:id/disable`, `POST /heatmap/estimation_rules/:id/enable`, `GET /heatmap/estimation_candidates`, `POST /heatmap/estimation_candidates/rebuild`, `POST /heatmap/estimation_candidates/:id/approve`, `POST /heatmap/estimation_candidates/:id/reject`로 둔다.

plugin settings 화면에는 `MD 추정 규칙` 링크, `hours_per_md` 입력, candidate rebuild 진입점을 추가한다.

candidate 목록은 조건, median MD, sample count, dispersion, confidence, 대표 이슈 5개 링크, approve/reject 버튼을 보여준다.

approved rule 목록은 enabled, priority, owner group, tracker, category, prefix, template, stage token, md, confidence, source, note를 보여준다.

전체 Redmine 이슈 대상 full rebuild는 production에서 오래 걸릴 수 있다. 따라서 동일한 builder를 호출하는 rake task `redmine_tx_heatmap:rebuild_estimation_candidates`도 추가한다. 관리자 UI 버튼은 기본적으로 최근 24개월 또는 선택 scope를 대상으로 실행하고, full rebuild는 rake task 사용을 권장한다.

## 8. Heatmap 통합

`HeatmapService#estimated_md`는 `IssueEstimator` 호출로 대체한다. 반환값에는 기존 `md`, `source` 외에 `confidence`, `rule_id`, `explanation`을 포함한다.

heatmap detail 화면에는 각 이슈별 MD 출처를 표시한다. 예시는 `estimated_hours`, `approved_rule`, `unknown`이다.

승인 rule 변경 후 캐시가 stale하지 않도록 heatmap cache key에 `EstimationRule.maximum(:updated_at)` 또는 rule fingerprint digest를 포함한다.

DB rule이 하나도 없고 `estimated_hours`가 있는 기존 이슈만 조회하는 경우 결과는 현재와 동일해야 한다.

## 9. 구현 순서

1. `hours_per_md` setting을 추가하고 기존 `estimated_hours / 8`을 `estimated_hours / hours_per_md`로 바꾼다.
2. estimation rule/candidate migration과 모델을 추가한다.
3. `TeamResolver`, `IssueSignature`, `IssueEstimator`를 추가하고 기존 heatmap MD 산정을 교체한다.
4. `CandidateBuilder`와 rake task를 추가한다.
5. 관리자 UI와 controller/routes를 추가한다.
6. heatmap detail에 source/confidence/explanation을 표시한다.
7. 캐시 키에 rule digest를 반영한다.
8. 단위 테스트와 통합 테스트를 추가한다.

## 10. 테스트 계획

`IssueSignature` 테스트는 prefix 보존, category name key 정규화, 고유명사만 다른 제목의 template 생성, stage token 추출을 검증한다.

`TeamResolver` 테스트는 worker의 group membership, worker 미지정/worker association 미존재 시 assignee fallback, assignee가 다른 팀으로 넘어간 이슈에서도 worker 기준 팀을 쓰는지 검증한다.

`IssueEstimator` 테스트는 estimated_hours 우선순위, DB rule 매칭, pending candidate 미사용, unknown 반환을 검증한다.

`CandidateBuilder` 테스트는 closed issue만 사용, estimated_hours 없는 issue 제외, 최소 샘플 수 미달 제외, median/IQR 계산, reject fingerprint 재생성 방지를 검증한다.

heatmap 통합 테스트는 기존 estimated_hours 결과 유지, 승인 rule 적용, rule 변경 후 캐시 무효화, detail metadata 표시를 검증한다.

migration 테스트는 빈 DB rule 상태에서 플러그인이 정상 부팅되고 기존 settings만으로 동작하는지 확인한다.

## 11. 배포와 운영 절차

배포 직후에는 승인된 DB rule이 없으므로 기존 결과가 거의 그대로 유지되어야 한다.

운영자는 먼저 rake task로 full rebuild를 실행해 pending candidate를 만든다.

운영자는 candidate 화면에서 sample count가 크고 dispersion이 낮은 후보부터 approve한다.

approve 후 heatmap에서 unknown MD 수와 팀별 월간 총 MD 변화량을 확인한다.

문제가 있는 rule은 disable하고 note에 사유를 남긴다.

## 12. Acceptance Criteria

`estimated_hours`가 있는 이슈는 항상 해당 값을 최우선으로 사용한다.

승인되지 않은 candidate는 어떤 경우에도 히트맵 수치에 영향을 주지 않는다.

같은 tracker/category/group/prefix/title pattern을 가진 historical issue에서 candidate가 생성된다.

관리자가 candidate를 approve하면 이후 유사 이슈의 unknown MD가 rule 기반 MD로 산정된다.

`art_tool` 관련 데이터, 파일, 규칙, 하드코딩된 Art 전용 분류가 코드에 들어가지 않는다.

날짜 분배 정책은 기존 개선안과 동일하게 유지된다.

## 13. Assumptions

Redmine의 `estimated_hours`는 시간 단위이고, 기본 `hours_per_md`는 `8.0`이다.

운영 rule은 Redmine 전체에서 재사용 가능해야 하므로 category 비교는 category ID보다 category name key를 우선한다.

실제 작업자 그룹 추론에는 `worker`를 우선 사용하되 worker 정보가 없으면 assignee로 fallback하고, MD ground truth는 v1에서 `estimated_hours`만 사용한다.

background job 인프라는 없다고 가정한다. full rebuild는 rake task로 제공하고, UI rebuild는 제한 scope에 사용한다.

새 기능은 production에서 점진적으로 켜야 하므로 DB rule이 없을 때 기존 결과를 유지하는 것이 필수다.
