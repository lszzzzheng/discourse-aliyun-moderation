# frozen_string_literal: true

# name: discourse-aliyun-moderation
# about: Pre-publish moderation via Aliyun multimodal gateway
# version: 0.1.6
# authors: ClubContentReview
# required_version: 3.2.0

enabled_site_setting :aliyun_moderation_enabled

after_initialize do
  module ::AliyunModeration
    PLUGIN_NAME = 'discourse-aliyun-moderation'

    class Error < StandardError; end
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

    def self.handle_post_moderation_result(post:, result:)
      case result[:decision]
      when 'PASS'
        true
      when 'REVIEW'
        post.errors.add(:base, review_message_for(result))
        false
      when 'REJECT'
        post.errors.add(:base, I18n.t('aliyun_moderation.rejected'))
        false
      else
        post.errors.add(:base, I18n.t('aliyun_moderation.review_required'))
        false
      end
    end

    def self.review_message_for(result)
      if result[:risk_level].to_s == 'too_many_images' || result[:error].to_s == 'too_many_images'
        I18n.t('aliyun_moderation.too_many_images_review_required', count: ::AliyunModeration::PayloadBuilder::MAX_AUTOMATED_IMAGES)
      elsif result[:risk_level].to_s == 'text_too_long_for_multimodal' || result[:error].to_s == 'text_too_long_for_multimodal'
        I18n.t('aliyun_moderation.text_too_long_review_required', count: ::AliyunModeration::PayloadBuilder::MAX_MULTIMODAL_TEXT_CHARS)
      else
        I18n.t('aliyun_moderation.review_required')
      end
    end
  end

  DiscourseEvent.on(:before_create_post) do |post, opts|
    user = post.user
    next unless ::AliyunModeration.enabled_for?(user)

    begin
      result = ::AliyunModeration::Moderator.moderate_before_create!(post: post, opts: opts || {})

      if result[:decision] == 'REVIEW'
        enqueued = ::AliyunModeration::ReviewQueue.safe_enqueue_new_post!(post: post, opts: opts || {}, result: result)
        if !enqueued
          post.errors.add(:base, I18n.t('aliyun_moderation.review_queue_unavailable'))
          next
        end
      end

      ::AliyunModeration.handle_post_moderation_result(post: post, result: result)
    rescue => e
      enqueued = ::AliyunModeration::ReviewQueue.safe_enqueue_new_post!(
        post: post,
        opts: opts || {},
        result: { decision: 'REVIEW', error: e.message, labels: [], risk_level: 'unknown' }
      )
      post.errors.add(:base, enqueued ? I18n.t('aliyun_moderation.review_required') : I18n.t('aliyun_moderation.review_queue_unavailable'))
    end
  end

  module ::AliyunModeration::PostRevisorExtension
    def revise!(editor, fields, opts = {})
      if ::AliyunModeration.enabled_for?(editor) &&
           ::AliyunModeration::PayloadBuilder.reviewable_edit?(post: @post, fields: fields)
        result = ::AliyunModeration::Moderator.moderate_before_edit!(post: @post, fields: fields)
        return false unless ::AliyunModeration.handle_post_moderation_result(post: @post, result: result)
      end

      super
    rescue => e
      if SiteSetting.aliyun_moderation_fail_safe_mode == 'pass'
        super
      else
        @post.errors.add(:base, I18n.t('aliyun_moderation.review_required'))
        false
      end
    end
  end

  ::PostRevisor.prepend(::AliyunModeration::PostRevisorExtension)

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
