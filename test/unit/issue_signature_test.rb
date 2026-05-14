require File.expand_path('../test_helper', __dir__)

class IssueSignatureTest < Minitest::Test
  def test_character_name_and_parenthesized_id_become_slot
    assert_equal(
      '[캐릭터][애니] {slot} 고유 카드 애니 {slot}',
      RedmineTxHeatmap::IssueSignature.title_template('[캐릭터][애니] 나인(30047) 고유 카드 애니 1')
    )

    assert_equal(
      '[애니] {slot} 고유 카드 애니 {slot}',
      RedmineTxHeatmap::IssueSignature.title_template('[애니] 티페라(Tipera)(30084) 고유 카드 애니 2')
    )
  end

  def test_well_sampled_existing_templates_keep_their_shape
    samples = {
      '[원화] 티페라(Tipera)(30084) 포트 일러스트 - 1차 (원본)' =>
        '[원화] {slot} 포트 일러스트 - {slot}차 (원본)',
      '[전투] 초공간 유역 황혼 시즌 2 컨텐츠 데이터 작업' =>
        '[전투] 초공간 유역 황혼 시즌 {slot} 컨텐츠 데이터 작업',
      '[전투] 초공간 유역 황혼 시즌2 컨텐츠 데이터 작업' =>
        '[전투] 초공간 유역 황혼 시즌{slot} 컨텐츠 데이터 작업',
      '[원화] 티페라(Tipera)(30084) 컨셉 (방향성) 시안 - 1차' =>
        '[원화] {slot} 컨셉 (방향성) 시안 - {slot}차',
      '[이펙트] 티페라(Tipera)(30084) SD 기본모션+U1~U4 이펙트' =>
        '[이펙트] {slot} SD 기본모션+U{slot}~U{slot} 이펙트',
      '[전투] 티페라(Tipera)(30084) 잠재력,에고발현 기획' =>
        '[전투] {slot} 잠재력, 에고발현 기획'
    }

    samples.each do |subject, template|
      assert_equal template, RedmineTxHeatmap::IssueSignature.title_template(subject)
    end
  end

  def test_template_matching_tolerates_position_spacing_and_punctuation
    template = '{slot} 몬스터 리소스 폴리싱 {slot}'

    assert RedmineTxHeatmap::IssueSignature.title_template_matches?(
      template,
      '[몬스터] [원화] 몬스터 리소스 폴리싱 - 켄트리스'
    )
    assert RedmineTxHeatmap::IssueSignature.title_template_matches?(
      template,
      '[몬스터][원화] 켄트리스 / 몬스터리소스 폴리싱'
    )
    assert RedmineTxHeatmap::IssueSignature.title_template_matches?(
      '[전투] {slot} 잠재력, 에고발현 기획',
      '[전투] 티페라(Tipera)(30084) 잠재력,에고발현 기획'
    )
  end
end
