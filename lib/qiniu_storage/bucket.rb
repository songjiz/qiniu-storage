module QiniuStorage
  class Bucket
    extend Forwardable

    attr_reader :name, :client, :region
    def_delegators :client, :generate_access_token, :sign_url
    def_delegators :client, :uc_post, :api_get, :rs_get, :rs_post, :rsf_get, :iovip_post

    def initialize(name:, client:, region: nil)
      @name = name
      @client = client
      @region = region || QiniuStorage.configuration.zone
    end

    def to_s
      name
    end

    def create
      path = "/mkbucketv2/#{encoded_name}"
      if region
        path << "/region/#{region}"
      end
      rs_post path
    end

    def destroy
      rs_post "/drop/#{name}"
    end

    alias_method :drop, :destroy

    def domains
      @domains ||= api_get("/v6/domain/list", params: { tbl: name })
    end

    def zone
      @zone ||= begin
        zone = QiniuStorage::Zone[region]
        return zone unless zone.nil?
        data = uc_post("/v2/query", params: { ak: client.access_key, bucket: name })
        iovip_host = data["io"]["src"]["main"].first
        src_up_hosts = Array(data["up"]["src"]["main"]) + Array(data["up"]["src"]["backup"])
        cdn_up_hosts = Array(data["up"]["acc"]["main"]) + Array(data["up"]["acc"]["backup"])
        QiniuStorage::Zone.new name: region, iovip_host: iovip_host, src_up_hosts: src_up_hosts, cdn_up_hosts: cdn_up_hosts
      end
    end

    def acl_private(yes = true)
      body = QiniuStorage.encode_form(bucket: name, private: yes ? 1 : 0)
      uc_post "/private", body: body
    end

    def acl_public(yes = true)
      acl_private !yes
    end

    def up_host(mode = nil)
      if (mode == :cdn) || (mode.nil? && QiniuStorage.configuration.use_cdn?)
        zone.cdn_up_hosts.first
      else
        zone.src_up_hosts.first
      end
    end

    def objects(limit: 1000, prefix: nil, delimiter: nil, marker: nil)
      QiniuStorage::Object::Bundle.new bucket: self, limit: limit, prefix: prefix, delimiter: delimiter, marker: marker
    end

    alias_method :files, :objects

    def object(key)
      QiniuStorage::Object.new(bucket: self, key: key)
    end

    alias_method :file, :object

    def encoded_uri(key)
      QiniuStorage.encode_entry self, key
    end

    def stat(key)
      rs_get QiniuStorage::Operation::Stat.new(bucket: self, key: key)
    end

    alias_method :metadata, :stat

    def exists?
      client.buckets.any? { |other| other.name == self.name }
    end

    def delete(key)
      rs_post QiniuStorage::Operation::Delete.new(bucket: self, key: key)
    end

    alias_method :remove, :delete

    def rename(key, new_key, force: false)
      move key, to_bucket: self, to_key: new_key, force: force
    end

    def move(key, to_bucket: nil, to_key: nil, force: false)
      if to_bucket.nil? && to_key.nil?
        raise ArgumentError, "Must specify at least one bucket name or key"
      end
      key = extract_file_key(key)
      to_bucket ||= self
      to_key    ||= key
      rs_post QiniuStorage::Operation::Move.new(bucket: self, key: key, to_bucket: to_bucket, to_key: to_key, force: force)
    end

    def copy(key, to_bucket: nil, to_key: nil, force: false)
      if to_bucket.nil? && to_key.nil?
        raise ArgumentError, "Must specify at least one bucket name or key"
      end
      key = extract_file_key(key)
      to_bucket ||= self
      to_key    ||= key
      rs_post QiniuStorage::Operation::Copy.new(bucket: self, key: key, to_bucket: to_bucket, to_key: to_key, force: force)
    end

    def chmime(key, mime)
      rs_post QiniuStorage::Operation::ChMime.new(bucket: self, key: extract_file_key(key), mime: mime)
    end

    def chtype(key, type)
      rs_post QiniuStorage::Operation::ChType.new(bucket: self, key: extract_file_key(key), type: type)
    end

    def standardize(key)
      chtype extract_file_key(key), 0
    end

    def low_freq(key)
      chtype extract_file_key(key), 1
    end

    def chstatus(key, status)
      rs_post QiniuStorage::Operation::ChStatus.new(bucket: self, key: extract_file_key(key), status: status)
    end

    def disable(key)
      chstatus extract_file_key(key), 1
    end

    def enable(key)
      chstatus extract_file_key(key), 0
    end

    def delete_after_days(key, days)
      rs_post QiniuStorage::Operation::DeleteAfterDays.new(bucket: self, key: extract_file_key(key), days: days)
    end

    alias_method :life_cycle, :delete_after_days

    def fetch(source_url, key = nil)
      op = QiniuStorage::Operation::Fetch.new(bucket: self, key: key, source_url: source_url)
      data = iovip_post(op)
      QiniuStorage::Object.new(bucket: self, key: key).tap { |f| f.update_metadata data }
    end

    def async_fetch(source_url, key: nil, md5: nil, etag: nil, callback_url: nil, callback_body: nil, callback_body_type: nil, callback_host: nil, file_type: 0, force: false)
      payload = {
        url: source_url,
        bucket: name,
        key: key,
        md5: md5,
        etag: etag,
        ignore_same_key: !force,
        callbackurl: callback_url,
        callbackbody: callback_body,
        callbackbodytype: callback_body_type,
        callbackhost: callback_host,
        file_type: file_type
      }
      QiniuStorage.prune_hash!(payload)
      client.with_http_request_authentication do
        result = client.http_post(client.build_url(host: zone.api_host, path: "/sisyphus/fetch"), payload.to_json, "Content-Type" => "application/json")
        QiniuStorage::AsyncFetchJob.new(bucket: self, job_id: result["id"], wait: result["wait"])
      end
    end

    def async_fetch_job(job_id)
      client.with_http_request_authentication do
        client.http_get client.build_url(host: zone.api_host, path: "/sisyphus/fetch", params: { id: job_id }), "Content-Type" => "application/json"
      end
    end

    def prefetch(key)
      iovip_post QiniuStorage::Operation::PreFetch.new(bucket: self, key: extract_file_key(key))
    end

    def batch(*ops)
      body = ops.flatten.map(&:to_s).compact.map { |op| "op=#{op}" }.join("&")
      rs_post "/batch", body: body
    end

    def batch_delete(*keys)
      batch keys.flatten.map { |key| extract_file_key(key) }.uniq.map { |key| QiniuStorage::Operation::Delete.new(bucket: self, key: key) }
    end

    def batch_stat(*keys)
      batch keys.flatten.map { |key| extract_file_key(key) }.uniq.map { |key| QiniuStorage::Operation::Stat.new(bucket: self, key: key) }
    end

    def batch_move(*keys, to_bucket, force: false)
      batch keys.flatten.map { |key| extract_file_key(key) }.uniq.map { |key| QiniuStorage::Operation::Move.new(bucket: self, key: key, to_bucket: to_bucket, to_key: key, force: force) }
    end

    def batch_copy(*keys, to_bucket, force: false)
      batch keys.flatten.map { |key| extract_file_key(key) }.uniq.map { |key| QiniuStorage::Operation::Copy.new(bucket: self, key: key, to_bucket: to_bucket, to_key: key, force: force) }
    end

    def batch_chstatus(*keys, status)
      batch keys.flatten.map { |key| extract_file_key(key) }.uniq.map { |key| QiniuStorage::Operation::ChStatus.new(bucket: self, key: key, status: status) }
    end

    def batch_enable(*keys)
      batch_chstatus *keys, 0
    end

    def batch_disable(*keys)
      batch_chstatus *keys, 1
    end

    def batch_chtype(*keys, type)
      batch keys.flatten.map { |key| extract_file_key(key) }.uniq.map { |key| QiniuStorage::Operation::ChType.new(bucket: self, key: key, type: type) }
    end

    def batch_chmime(*keys, mime)
      batch keys.flatten.map { |key| extract_file_key(key) }.uniq.map { |key| QiniuStorage::Operation::ChMime.new(bucket: self, key: key, mime: mime) }
    end

    def batch_standardize(*keys)
      batch_chtype *keys, 0
    end

    def batch_low_freq(*keys)
      batch_chtype *keys, 1
    end

    def url_for(key, options = {})
      public_url = client.build_url(host: domains.first, path: "/#{key}", params: { fop: options[:fop].to_s }, use_https: options[:use_https])
      expires_in = options[:expires_in]
      if expires_in
        sign_url public_url, expires_in
      else
        public_url
      end
    end
    
    alias_method :object_url, :url_for

    def download(key, range: nil, expires_in: nil)
      range_header = \
        case range
        when String
          range
        when Range
          "bytes=#{range.begin}-#{range.max}"
        when Array
          "bytes=#{range[0]}-#{range[1]}"
        end
      # Fix me: OpenSSL::SSL::SSLError: SSL_connect returned=1 errno=0 state=SSLv2/v3 read server hello A: sslv3 alert handshake failure
      # use HTTP instead of HTTPS temporarily
      client.http_get url_for(key, use_https: false, expires_in: expires_in), range: range_header
    end

    def streaming_download(key, offset: 0, chunk_size: nil, expires_in: nil)
      fsize = metadata(key)["fsize"]
      chunk_size ||= QiniuStorage.configuration.download_chunk_size
      while offset < fsize
        yield download(key, range: offset...(offset + chunk_size))
        offset += chunk_size
      end
    end

    def upload(source, options = {})
      uploader.upload source, self, options
    end

    def multipart_upload(source, options = {})
      uploader.multipart_upload source, self, options
    end

    def resumable_upload(source, options = {})
      uploader.resumable_upload source, self, options
    end

    def direct_upload_url(use_https: nil)
      client.build_url host: up_host, use_https: use_https
    end

    def encoded_name
      QiniuStorage.base64_urlsafe_encode name
    end

    private
      def uploader
        client.uploader
      end

      def extract_file_key(obj)
        case obj
        when QiniuStorage::Object
          obj.key
        else
          obj.to_s
        end
      end

  end
end
