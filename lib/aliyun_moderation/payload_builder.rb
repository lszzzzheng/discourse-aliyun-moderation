# frozen_string_literal: true

module ::AliyunModeration
  class PayloadBuilder
    MAX_AUTOMATED_IMAGES = 10
    MAX_MULTIMODAL_TEXT_CHARS = 5000

    IMAGE_PATTERN = %r{https?://[^\s)\]"'>]+\.(?:jpg|jpeg|png|gif|webp|bmp|heic|heif|tif|tiff|svg|ico)}i
    RELATIVE_UPLOAD_PATTERN = %r{/uploads/[^\s)\]"'>]+}i
    IMG_SRC_PATTERN = /<img[^>]+src=["']([^"']+)["']/i
    LINK_HREF_PATTERN = /<a[^>]+href=["']([^"']+)["']/i

    def self.from_create(post:, opts:)
      context = create_context(post: post, opts: opts)
      images = extract_images(context[:raw])
      {
        scene: 'post',
        title: context[:title],
        text: context[:raw],
        images: images.first(MAX_AUTOMATED_IMAGES),
        image_count: images.length,
        text_length: multimodal_text_length(context[:title], context[:raw]),
        comments: extract_context_posts(context[:topic])
      }
    end

    def self.from_edit(post:, fields:)
      context = edit_context(post: post, fields: fields)
      images = extract_images(context[:raw])

      {
        scene: 'post',
        title: context[:title],
        text: context[:raw],
        images: images.first(MAX_AUTOMATED_IMAGES),
        image_count: images.length,
        text_length: multimodal_text_length(context[:title], context[:raw]),
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
      raw_text = text.to_s
      urls = raw_text.scan(IMAGE_PATTERN)
      urls.concat(raw_text.scan(RELATIVE_UPLOAD_PATTERN))

      cooked = PrettyText.cook(raw_text)
      urls.concat(extract_image_sources(cooked))
      urls.concat(extract_image_links(cooked))

      urls
        .map { |url| normalize_image_url(url) }
        .compact
        .uniq
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

    def self.extract_image_sources(html)
      html.to_s.scan(IMG_SRC_PATTERN).flatten.select { |url| reviewable_image_url?(url, allow_extensionless: true) }
    end

    def self.extract_image_links(html)
      html.to_s.scan(LINK_HREF_PATTERN).flatten.select { |url| reviewable_image_url?(url) }
    end

    def self.normalize_image_url(url)
      return nil if url.blank?
      return nil unless reviewable_image_url?(url, allow_extensionless: true)

      if url.start_with?('/uploads/', '/original/')
        to_absolute_url(url)
      elsif url.start_with?('http://', 'https://')
        url
      end
    end

    def self.reviewable_image_url?(url, allow_extensionless: false)
      candidate = url.to_s.split('?').first.to_s
      return false unless candidate.start_with?('http://', 'https://', '/uploads/', '/original/')
      return true if candidate.match?(/\.(?:jpg|jpeg|png|gif|webp|bmp|heic|heif|tif|tiff|svg|ico)\z/i)
      return true if allow_extensionless && candidate.start_with?('/uploads/', '/original/')

      false
    end

    def self.review_queue_payload_from_create(post:, opts:, result:)
      context = create_context(post: post, opts: opts)

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

    def self.reviewable_edit?(post:, fields:)
      normalized = fields.to_h.with_indifferent_access
      normalized.key?(:raw) || (post.is_first_post? && normalized.key?(:title))
    end

    def self.create_context(post:, opts:)
      normalized = opts.to_h.with_indifferent_access
      topic = fetch_topic_by_id(normalized[:topic_id])

      {
        raw: normalized[:raw].presence || post.raw.to_s,
        title: normalized[:title].presence || topic&.title.to_s,
        topic: topic,
        archetype: normalized[:archetype],
        category: normalized[:category],
        topic_id: normalized[:topic_id],
        reply_to_post_number: normalized[:reply_to_post_number]
      }
    end

    def self.edit_context(post:, fields:)
      normalized = fields.to_h.with_indifferent_access
      topic = post.topic

      {
        raw: normalized[:raw].presence || post.raw.to_s,
        title: normalized[:title].presence || inferred_post_title(post, topic),
        topic: topic,
        archetype: topic&.archetype,
        category: normalized[:category_id].presence || topic&.category_id,
        topic_id: post.topic_id,
        reply_to_post_number: post.reply_to_post_number
      }
    end

    def self.fetch_topic_by_id(topic_id)
      return nil if topic_id.blank?

      Topic.find_by(id: topic_id)
    end

    def self.multimodal_text_length(title, text)
      title.to_s.length + text.to_s.length
    end

    def self.inferred_post_title(subject, topic)
      return topic.title.to_s if topic&.title.present?
      return subject.title.to_s if subject.respond_to?(:title) && subject.title.present?

      ''
    end
  end
end
