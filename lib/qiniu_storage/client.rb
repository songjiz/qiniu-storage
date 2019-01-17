require "base64"
require "digest"
require "json"
require "net/https"
require "openssl"
require "uri"

module QiniuStorage
  class Client
    DEFAULT_USER_AGENT = "qiniu-storage-ruby/#{QiniuStorage::VERSION} ruby-#{RUBY_VERSION}/#{RUBY_PLATFORM}"
    DEFAULT_CONTENT_TYPE = "application/x-www-form-urlencoded"
    WITH_HTTP_REQUEST_AUTHENTICATION_KEY = :qiniu_storage_with_http_request_authentication
    
    attr_reader :access_key, :secret_key

    def initialize(access_key:, secret_key:)
      @access_key = access_key
      @secret_key = secret_key
    end

    def buckets
      url = build_url(host: Zone::RS_HOST, path: "/buckets")
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
      signing_str  = QiniuStorage.hmac_sha1_digest(signing_str, secret_key)
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
      hmac_sha1_sign = QiniuStorage.hmac_sha1_digest(encoded_policy, secret_key)
      encoded_sign   = QiniuStorage.base64_urlsafe_encode(hmac_sha1_sign)
      [access_key, encoded_sign, encoded_policy].join ":"
    end

    def sign_http_request(method, uri_or_path, host: nil, content_type: nil, body: nil)
      data = ""
      method = method.to_s.upcase
      uri = URI(uri_or_path.to_s)
      data += "#{method} #{uri.path}"
      if uri.query
        data += "?#{uri.query}"
      end
      data += "\nHost: #{host || uri.host}"
      if content_type
        data += "\nContent-Type: #{content_type}"
      end
      data += "\n\n"
      if content_type =~ /(application\/json)|(application\/x-www-form-urlencoded)/ && body
        data += body
      end
      hmac_sha1_sign = QiniuStorage.hmac_sha1_digest(data, secret_key)
      encoded_sign   = QiniuStorage.base64_urlsafe_encode(hmac_sha1_sign)
      [access_key, encoded_sign].join ":"
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
      hmac_sha1_sign = QiniuStorage.hmac_sha1_digest(uri.to_s, secret_key)
      encoded_sign   = QiniuStorage.base64_urlsafe_encode(hmac_sha1_sign)
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

    def build_url(host:, path: nil, params: nil, use_https: nil)
      QiniuStorage.build_url host: host, path: path.to_s, params: params, use_https: use_https.nil? ? QiniuStorage.configuration.use_https? : use_https
    end

    def http_get(url, headers = {})
      uri = URI(url)
      http = build_http(uri)
      request = Net::HTTP::Get.new(uri)
      default_headers.merge!(headers).each { |k, v| request[k] = v }
      if with_http_request_authentication?
        token = sign_http_request(request.method, request.uri, content_type: request["Content-Type"])
        request["Authorization"] = "Qiniu #{token}"
      end
      response = http.request(request)
      handle_response response
    end

    def http_post(url, data = "", headers = {})
      uri = URI(url)
      http = build_http(uri)
      request = Net::HTTP::Post.new(uri)
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
      else
        if QiniuStorage.streamable?(data)
          request.body_stream = data
        end
      end
      if with_http_request_authentication?
        token = sign_http_request(request.method, request.uri, content_type: request["Content-Type"], body: request.body)
        request["Authorization"] = "Qiniu #{token}"
      end
      response = http.request(request)
      handle_response response
    end

    # With this method each HTTP Request will reset the `Authorization` HTTP Header via `sign_http_request` method.
    def with_http_request_authentication(&block)
      Thread.current[WITH_HTTP_REQUEST_AUTHENTICATION_KEY] = true
      yield
    ensure
      Thread.current[WITH_HTTP_REQUEST_AUTHENTICATION_KEY] = false
    end

    def with_http_request_authentication?
      Thread.current[WITH_HTTP_REQUEST_AUTHENTICATION_KEY]
    end

    private
      def default_headers
        { "User-Agent" => DEFAULT_USER_AGENT, "Content-Type" => DEFAULT_CONTENT_TYPE }
      end

      def with_access_token(host, path = nil, params = nil, body = nil)
        url = build_url(host: host, path: path, params: params)
        yield url, generate_access_token(url, body)
      end

      def build_http(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          if uri.scheme == "https"
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
          if QiniuStorage.configuration.http_debug_mode?
            http.set_debug_output QiniuStorage.configuration.logger
          end
        end
      end

      def handle_response(response)
        if success?(response.code.to_i)
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

      def success?(code)
        200 <= code && code < 300
      end
  end
end
