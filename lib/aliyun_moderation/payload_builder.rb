# frozen_string_literal: true

module ::AliyunModeration
  class PayloadBuilder
    IMAGE_PATTERN = %r{https?://[^\s)\]"'>]+\.(?:jpg|jpeg|png|gif|webp|bmp|heic|heif)}i

    def self.from_creator(creator)
      raw = creator.opts[:raw].to_s
      topic = fetch_topic(creator)

      {
        scene: 'post',
        title: creator.opts[:title].presence || topic&.title.to_s,
        text: raw,
        images: extract_images(raw),
        comments: extract_context_posts(topic)
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

    def self.fetch_topic(creator)
      topic_id = creator.opts[:topic_id]
      return nil if topic_id.blank?

      Topic.find_by(id: topic_id)
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
  end
end
