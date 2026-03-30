# frozen_string_literal: true

module ::AliyunModeration
  class PayloadBuilder
    IMAGE_PATTERN = %r{https?://[^\s)\]"'>]+\.(?:jpg|jpeg|png|gif|webp|bmp|heic|heif)}i

    def self.from_creator(subject)
      context = submission_context(subject)

      {
        scene: 'post',
        title: context[:title],
        text: context[:raw],
        images: extract_images(context[:raw]),
        comments: extract_context_posts(context[:topic])
      }
    end

    def self.from_user(user:, avatar_upload: nil)
      name_text = user.name.presence || user.username.to_s
      avatar_url = avatar_upload_url(user: user, avatar_upload: avatar_upload)

      {
        scene: 'profile',
        text: name_text,
        images: avatar_url.present? ? [avatar_url] : [],
        comments: []
      }
    end

    def self.extract_images(text)
      text.to_s.scan(IMAGE_PATTERN).uniq.first(10)
    end

    def self.extract_context_posts(topic)
      return [] if topic.blank?

      limit = SiteSetting.aliyun_moderation_include_context_posts
      return [] if limit <= 0

      topic.posts.order(:post_number).last(limit).map do |post|
        {
          dataId: post.id.to_s,
          text: post.raw.to_s,
          postTime: post.created_at.strftime('%Y-%m-%d %H:%M:%S')
        }
      end
    end

    def self.avatar_upload_url(user:, avatar_upload:)
      upload = avatar_upload || user.user_avatar&.custom_upload
      return nil if upload.blank? || upload.url.blank?

      to_absolute_url(upload.url)
    end

    def self.to_absolute_url(url)
      return url if url.start_with?('http://', 'https://')

      "#{Discourse.base_url_no_prefix}#{url}"
    end

    def self.submission_context(subject)
      if subject.respond_to?(:opts)
        opts = subject.opts || {}
        topic = fetch_topic_by_id(opts[:topic_id])

        {
          raw: opts[:raw].to_s,
          title: opts[:title].presence || topic&.title.to_s,
          topic: topic,
          archetype: opts[:archetype],
          category: opts[:category],
          topic_id: opts[:topic_id],
          reply_to_post_number: opts[:reply_to_post_number]
        }
      else
        topic = subject.respond_to?(:topic) ? subject.topic : nil

        {
          raw: subject.respond_to?(:raw) ? subject.raw.to_s : '',
          title: inferred_post_title(subject, topic),
          topic: topic,
          archetype: topic&.archetype,
          category: topic&.category_id,
          topic_id: subject.respond_to?(:topic_id) ? subject.topic_id : nil,
          reply_to_post_number: subject.respond_to?(:reply_to_post_number) ? subject.reply_to_post_number : nil
        }
      end
    end

    def self.review_queue_payload(subject, result:)
      context = submission_context(subject)

      {
        raw: context[:raw],
        title: context[:title],
        archetype: context[:archetype],
        category: context[:category],
        topic_id: context[:topic_id],
        reply_to_post_number: context[:reply_to_post_number],
        meta: {
          decision: result[:decision],
          risk_level: result[:risk_level],
          labels: result[:labels],
          req_id: result[:req_id],
          error: result[:error]
        }
      }
    end

    def self.fetch_topic_by_id(topic_id)
      return nil if topic_id.blank?

      Topic.find_by(id: topic_id)
    end

    def self.inferred_post_title(subject, topic)
      return topic.title.to_s if topic&.title.present?
      return subject.title.to_s if subject.respond_to?(:title) && subject.title.present?

      ''
    end
  end
end
