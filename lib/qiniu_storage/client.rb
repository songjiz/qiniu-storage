require "base64"
require "digest"
require "json"
require "net/https"
require "openssl"
require "uri"

module QiniuStorage
  class Client
    DEFAULT_USER_AGENT   = "qiniu-storage-ruby/#{QiniuStorage::VERSION} ruby-#{RUBY_VERSION}/#{RUBY_PLATFORM}"
    DEFAULT_CONTENT_TYPE = "application/x-www-form-urlencoded"

    attr_reader :access_key, :secret_key

    def initialize(access_key:, secret_key:)
      @access_key = access_key
      @secret_key = secret_key
    end

    def buckets
      url = build_url(Zone::RS_HOST, "/buckets")
      token = generate_access_token(url)
      data = rs_get "/buckets", headers: { "Authorization" => "QBox #{token}" }
      Array(data).map { |name| bucket name }
    end

    def bucket(name, region: nil)
      QiniuStorage::Bucket.new name: name, client: self, region: region
    end

    def uploader
      @uploader ||= QiniuStorage::Uploader.new client: self
    end

    def generate_access_token(url, body = nil)
      uri = URI.parse(url.to_s)
      signing_str = uri.path
      if uri.query && !uri.query.empty?
        signing_str << "?#{uri.query}"
      end
      signing_str << "\n"
      if body && !body.empty?
        signing_str << body
      end
      signing_str  = QiniuStorage.hmac_sha1_digest(secret_key, signing_str)
      encoded_sign = QiniuStorage.base64_urlsafe_encode(signing_str)
      [access_key, encoded_sign].join(":")
    end

    def generate_upload_token(bucket, key, expires_in = nil, policy: {})
      scope = [bucket, key].compact.join(":")
      deadline = Time.now.utc.to_i + Integer(expires_in || QiniuStorage.configuration.upload_token_expires_in)
      upload_policy = { scope: scope, deadline: deadline }
      upload_policy.merge!(policy)
      upload_policy.keys.each do |pk|
        ck =  if pk.respond_to?(:camelcase)
                pk.camelcase(:lower)
              else
                pk.to_s.gsub(/_([a-z])/) { $1.upcase }
              end
        upload_policy[ck] = upload_policy.delete(pk)
      end
      encoded_policy = QiniuStorage.base64_urlsafe_encode(upload_policy.to_json)
      hmac_sha1_sign = QiniuStorage.hmac_sha1_digest(secret_key, encoded_policy)
      encoded_sign   = QiniuStorage.base64_urlsafe_encode(hmac_sha1_sign)
      [access_key, encoded_sign, encoded_policy].join ":"
    end

    def sign_url(url, expires_in)
      expires_at = Time.now.utc.to_i + expires_in
      uri = URI(url)
      url = uri.to_s
      if url.include?("?")
        url << "&e=#{expires_at}"
      else
        url << "?e=#{expires_at}"
      end
      signing_str  = QiniuStorage.hmac_sha1_digest(secret_key, uri.to_s)
      encoded_sign = QiniuStorage.base64_urlsafe_encode(signing_str)
      token = [access_key, encoded_sign].join(":")
      url << "&token=#{token}"
      url
    end

    def invalid_upload_token?(token)
      return true if token.nil?
      claims = token.split(":")
      encoded_policy = claims[2]
      policy_json = QiniuStorage.base64_urlsafe_decode(encoded_policy)
      policy = JSON.load(policy_json)
      Time.now.utc.to_i > policy["deadline"]
    rescue
      true
    end

    def uc_post(path, params: nil, body: nil, **headers)
      with_access_token(Zone::UC_HOST, path, params, body) do |url, token|
        http_post url, body, headers.merge("Authorization" => "QBox #{token}")
      end
    end

    def api_get(path, params: nil, **headers)
      with_access_token(Zone::API_HOST, path, params) do |url, token|
        http_get url, headers.merge("Authorization" => "QBox #{token}")
      end
    end

    def rs_get(path, params: nil, **headers)
      with_access_token(Zone::RS_HOST, path, params) do |url, token|
        http_get url, headers.merge("Authorization" => "QBox #{token}")
      end
    end

    def rs_post(path, params: nil, body: nil, **headers)
      with_access_token(Zone::RS_HOST, path, params, body) do |url, token|
        http_post url, body, headers.merge("Authorization" => "QBox #{token}")
      end
    end

    def rsf_get(path, params: nil, **headers)
      with_access_token(Zone::RSF_HOST, path, params) do |url, token|
        http_get url, headers.merge("Authorization" => "QBox #{token}")
      end
    end

    def iovip_post(path, params: nil, body: nil, **headers)
      with_access_token(Zone::IOVIP_HOST, path, params, body) do |url, token|
        http_post url, body, headers.merge("Authorization" => "QBox #{token}")
      end
    end

    def build_url(host, path = nil, params = {})
      query = QiniuStorage.encode_params(params)
      QiniuStorage.build_url host: host, path: path.to_s, query: query
    end

    def http_get(url, headers = {})
      uri = URI(url)
      http = build_http(uri)
      request = Net::HTTP::Get.new(uri.request_uri)
      default_headers.merge!(headers).each { |k, v| request[k] = v }
      response = http.request(request)
      handle_response response
    end

    def http_post(url, data = "", headers = {})
      uri = URI(url)
      http = build_http(uri)
      request = Net::HTTP::Post.new(uri.request_uri)
      default_headers.merge!(headers).each { |k, v| request[k] = v }
      case data
      when Hash, Array
        # Support multipart mode
        if request["Content-Type"] =~ /multipart\/form-data/
          request.set_form data, "multipart/form-data"
        else
          request.set_form data
        end
      when String
        request.body = data
      end
      response = http.request(request)
      handle_response response
    end

    private
      def default_headers
        { "User-Agent" => DEFAULT_USER_AGENT, "Content-Type" => DEFAULT_CONTENT_TYPE }
      end

      def with_access_token(host, path, params = nil, body = nil)
        url = build_url(host, path, params)
        yield url, generate_access_token(url, body)
      end

      def build_http(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          if uri.scheme == "https"
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
          if QiniuStorage.configuration.debug_mode?
            http.set_debug_output STDOUT
          end
        end
      end

      def handle_response(response)
        if response.code.to_i == 200 || response.code.to_i == 298
          if response["Content-Type"] =~ /application\/json/ && !response.body.empty?
            JSON.parse(response.body)
          else
            response.body
          end
        else
          # https://developer.qiniu.com/kodo/api/3928/error-responses
          json = JSON.parse(response.body)
          raise QiniuStorage::Error, code: json["code"], message: json["error"]
        end
      end
  end
end
