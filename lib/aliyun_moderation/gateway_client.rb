# frozen_string_literal: true

require 'json'
require 'net/http'

module ::AliyunModeration
  class GatewayClient
    def initialize(url:, timeout_ms:)
      @uri = URI(url)
      @timeout_seconds = timeout_ms.to_f / 1000.0
    end

    def moderate!(payload)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = @uri.scheme == 'https'
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds

      request = Net::HTTP::Post.new(@uri.request_uri)
      request['Content-Type'] = 'application/json'
      request.body = JSON.generate(payload)

      response = http.request(request)
      raise ::AliyunModeration::Error, "gateway_http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise ::AliyunModeration::Error, "gateway_json_error: #{e.message}"
    end
  end
end
