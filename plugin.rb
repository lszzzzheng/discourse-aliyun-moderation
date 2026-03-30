# frozen_string_literal: true

# name: discourse-aliyun-moderation
# about: Pre-publish moderation via Aliyun multimodal gateway
# version: 0.1.0
# authors: ClubContentReview
# required_version: 3.2.0

enabled_site_setting :aliyun_moderation_enabled

after_initialize do
  module ::AliyunModeration
    PLUGIN_NAME = 'discourse-aliyun-moderation'

    class Error < StandardError; end
    class ReviewIntercept < StandardError; end
    class RejectIntercept < StandardError; end
  end

  require_relative 'lib/aliyun_moderation/gateway_client'
  require_relative 'lib/aliyun_moderation/payload_builder'
  require_relative 'lib/aliyun_moderation/review_queue'
  require_relative 'lib/aliyun_moderation/moderator'

  module ::AliyunModeration
    def self.enabled_for?(user)
      return false unless SiteSetting.aliyun_moderation_enabled
      return false if user&.staff?

      true
    end

    def self.profile_enabled_for?(user)
      return false unless SiteSetting.aliyun_moderation_profile_enabled
      return false if user.blank? || user.id == Discourse::SYSTEM_USER_ID
      return false if user.staff?

      true
    end
  end

  DiscourseEvent.on(:before_create_post) do |creator|
    user = creator.user
    next unless ::AliyunModeration.enabled_for?(user)

    begin
      result = ::AliyunModeration::Moderator.moderate_before_create!(creator)

      if result[:decision] == 'REVIEW'
        ::AliyunModeration::ReviewQueue.enqueue!(creator: creator, result: result)
        raise ::AliyunModeration::ReviewIntercept
      elsif result[:decision] == 'REJECT'
        raise ::AliyunModeration::RejectIntercept
      end
    rescue ::AliyunModeration::ReviewIntercept
      creator.errors.add(:base, I18n.t('aliyun_moderation.review_required'))
      raise Discourse::InvalidAccess.new(I18n.t('aliyun_moderation.review_required'))
    rescue ::AliyunModeration::RejectIntercept
      creator.errors.add(:base, I18n.t('aliyun_moderation.rejected'))
      raise Discourse::InvalidAccess.new(I18n.t('aliyun_moderation.rejected'))
    rescue => e
      # Conservative fail-safe: send to review queue instead of direct publish.
      ::AliyunModeration::ReviewQueue.enqueue!(creator: creator, result: { decision: 'REVIEW', error: e.message, labels: [], risk_level: 'unknown' })
      creator.errors.add(:base, I18n.t('aliyun_moderation.review_required'))
      raise Discourse::InvalidAccess.new(I18n.t('aliyun_moderation.review_required'))
    end
  end

  User.class_eval do
    validate :aliyun_moderate_profile_text

    def aliyun_moderate_profile_text
      return unless ::AliyunModeration.profile_enabled_for?(self)
      return unless new_record? || will_save_change_to_name? || will_save_change_to_username?

      result = ::AliyunModeration::Moderator.moderate_profile_user!(self)
      case result[:decision]
      when 'PASS'
        nil
      when 'REVIEW'
        errors.add(:base, I18n.t('aliyun_moderation.profile_review_required'))
      when 'REJECT'
        errors.add(:base, I18n.t('aliyun_moderation.profile_rejected'))
      end
    rescue => e
      if SiteSetting.aliyun_moderation_fail_safe_mode == 'pass'
        Rails.logger.warn("[AliyunModeration] profile text fallback pass: #{e.class}: #{e.message}")
      else
        errors.add(:base, I18n.t('aliyun_moderation.profile_review_required'))
      end
    end
  end

  UserAvatar.class_eval do
    validate :aliyun_moderate_custom_avatar

    def aliyun_moderate_custom_avatar
      return unless custom_upload_id.present?
      return unless will_save_change_to_custom_upload_id?
      return unless ::AliyunModeration.profile_enabled_for?(user)

      result = ::AliyunModeration::Moderator.moderate_profile_avatar!(user: user, avatar_upload: custom_upload)
      case result[:decision]
      when 'PASS'
        nil
      when 'REVIEW'
        errors.add(:base, I18n.t('aliyun_moderation.profile_avatar_review_required'))
      when 'REJECT'
        errors.add(:base, I18n.t('aliyun_moderation.profile_avatar_rejected'))
      end
    rescue => e
      if SiteSetting.aliyun_moderation_fail_safe_mode == 'pass'
        Rails.logger.warn("[AliyunModeration] avatar fallback pass: #{e.class}: #{e.message}")
      else
        errors.add(:base, I18n.t('aliyun_moderation.profile_avatar_review_required'))
      end
    end
  end
end
