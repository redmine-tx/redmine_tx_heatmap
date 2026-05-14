require File.expand_path('../test_helper', __dir__)

class TitleTemplateMinerTest < Minitest::Test
  def test_mines_repeated_work_phrase_without_assuming_trailing_target
    subjects = [
      '[몬스터][원화] 몬스터 리소스 폴리싱 - 켄트리스',
      '[몬스터][원화] 비아데우스 몬스터 리소스 폴리싱',
      '[몬스터][원화] 몬스터 리소스 폴리싱: 아르고스',
      '[몬스터][원화] 흑색 인면수 / 몬스터 리소스 폴리싱',
      '[몬스터][원화] 은하계재해 몬스터 공격 컷인 리소스 제작 - 갈망의 시동 하쿠 (3000340)'
    ]

    templates = RedmineTxHeatmap::TitleTemplateMiner.templates_for(subjects, :min_samples => 4)
    polishing = templates.find { |entry| entry[:template] == '{slot} 몬스터 리소스 폴리싱 {slot}' }

    refute_nil polishing
    assert_equal [0, 1, 2, 3], polishing[:indexes]
    refute templates.any? { |entry| entry[:template] == '{slot} 몬스터 {slot}' }
  end

  def test_mines_existing_well_sampled_phrase_candidates
    subjects = [
      '[원화] 티페라(Tipera)(30084) 포트 일러스트 - 1차 (원본)',
      '[원화] 티아나(Tiana)(30085) 포트 일러스트 - 1차 (원본)',
      '[원화] 루이샹(Ruixiang)(30092) 포트 일러스트 - 1차 (원본)',
      '[원화] 리타(Rita)(30097) 포트 일러스트 - 1차 (원본)',
      '[원화] 하이데마리(Heidemarie)(30093) 포트 일러스트 - 1차 (원본)'
    ]

    templates = RedmineTxHeatmap::TitleTemplateMiner.templates_for(subjects, :min_samples => 5)
    assert_includes(
      templates.map { |entry| entry[:template] },
      '{slot} 포트 일러스트 1차 원본 {slot}'
    )
  end
end
