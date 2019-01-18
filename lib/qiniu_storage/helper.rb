require "base64"
require "digest"
require "openssl"
require "stringio"
require "tempfile"
require "uri"
require "zlib"
require "qiniu_storage/qetag"

module QiniuStorage
  module Helper

    def qetag(source)
      QiniuStorage::QEtag.etag source
    end

    def encode_entry(bucket, key = nil)
      entry = [bucket, key].compact.join(":")
      base64_urlsafe_encode entry
    end

    def crc32_checksum(data)
      if streamable?(data)
        begin
          Zlib.crc32(data.read)
        ensure
          data.rewind
        end
      else
        Zlib.crc32(data)
      end
    end

    def base64_urlsafe_encode(data)
      Base64.urlsafe_encode64 data
    end

    def base64_urlsafe_decode(data)
      Base64.urlsafe_decode64 data
    end

    def hmac_sha1_digest(data, secret_key)
      digest = OpenSSL::Digest.new("sha1")
      OpenSSL::HMAC.digest digest, secret_key, data
    end

    def md5_checksum(data)
      if data.is_a?(String)
        Digest::MD5.base64digest data
      elsif streamable?(data)
        Digest::MD5.new.tap do |md5|
          until data.eof?
            md5 << data.read(5242880)
          end
          data.rewind
        end.base64digest
      end
    end

    def streamable?(obj)
      obj.is_a?(IO) ||
      obj.is_a?(StringIO) ||
      obj.is_a?(Tempfile) ||
      (obj.respond_to?(:read) && obj.respond_to?(:rewind) && obj.respond_to?(:eof?))
    end

    def encode_form(hash)
      URI.encode_www_form(hash || {})
    end

    alias_method :encode_params, :encode_form

    def build_url(host:, port: nil, path: nil, params: nil, use_https: nil)
      options = { host: host, port: port, path: path }
      query = encode_params(params)
      unless query.empty?
        options[:query] = query
      end
      if use_https
        URI::HTTPS.build(options).to_s
      else
        URI::HTTP.build(options).to_s
      end
    end
  end
end
