# frozen_string_literal: true

module ::AliyunModeration
  class ReviewQueue
    def self.enqueue!(creator:, result:)
      payload = ::AliyunModeration::PayloadBuilder.review_queue_payload(creator, result: result)
      target_user = creator.respond_to?(:user) ? creator.user : nil

      reviewable = ReviewableQueuedPost.needs_review!(
        created_by: Discourse.system_user,
        target_created_by: target_user,
        payload: payload,
        reviewable_by_moderator: true
      )

      reason = "aliyun_moderation decision=#{result[:decision]} risk=#{result[:risk_level]}"
      reviewable.add_score(
        Discourse.system_user,
        ReviewableScore.types[:needs_approval],
        reason: reason,
        force_review: true
      )

      reviewable
    rescue => e
      Rails.logger.error("[AliyunModeration] failed to enqueue review: #{e.class}: #{e.message}")
      raise e
    end
  end
end
