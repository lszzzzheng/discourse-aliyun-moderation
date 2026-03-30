# frozen_string_literal: true

module ::AliyunModeration
  class ReviewQueue
    def self.enqueue!(creator:, result:)
      payload = {
        raw: creator.opts[:raw].to_s,
        title: creator.opts[:title].to_s,
        archetype: creator.opts[:archetype],
        category: creator.opts[:category],
        topic_id: creator.opts[:topic_id],
        reply_to_post_number: creator.opts[:reply_to_post_number],
        meta: {
          decision: result[:decision],
          risk_level: result[:risk_level],
          labels: result[:labels],
          req_id: result[:req_id],
          error: result[:error]
        }
      }

      reviewable = ReviewableQueuedPost.needs_review!(
        created_by: Discourse.system_user,
        target_created_by: creator.user,
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
