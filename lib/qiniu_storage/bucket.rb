module QiniuStorage
  class Bucket
    extend Forwardable

    attr_reader :name, :client, :region
    def_delegators :client, :generate_access_token, :sign_url
    def_delegators :client, :uc_post, :api_get, :rs_get, :rs_post, :rsf_get, :iovip_post

    def initialize(name:, client:, region: nil)
      @name = name
      @client = client
      @region = region || QiniuStorage.configuration.region
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

    alias :drop :destroy

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
      form = { bucket: name, private: yes ? 1 : 0 }
      body = QiniuStorage.encode_form(form)
      uc_post "/private", body: body
    end

    def acl_public(yes = true)
      acl_private !yes
    end

    def up_host(mode = nil)
      if (mode == :cdn) || (mode.nil? && QiniuStorage.enable_cdn?)
        zone.cdn_up_hosts.first
      else
        zone.src_up_hosts.first
      end
    end

    def files(limit: 1000, prefix: nil, delimiter: nil, marker: nil)
      QiniuStorage::File::Bundle.new bucket: self, limit: limit, prefix: prefix, delimiter: delimiter, marker: marker
    end

    def file(key)
      QiniuStorage::File.new(bucket: self, key: key)
    end

    def encoded_uri(key)
      QiniuStorage.encode_entry self, key
    end

    def stat(key)
      rs_get QiniuStorage::Operation::Stat.new(bucket: self, key: key)
    end

    alias :metadata :stat

    def exists?
      client.buckets.any? { |other| other.name == self.name }
    end

    def delete(key)
      rs_post QiniuStorage::Operation::Delete.new(bucket: self, key: key)
    end

    alias :remove :delete

    def rename(key, new_key, force: false)
      move key, new_bucket: self, new_key: new_key, force: force
    end

    def move(key, new_bucket: nil, new_key: nil, force: false)
      if new_bucket.nil? && new_key.nil?
        raise ArgumentError, "Must specify at least one bucket name or key"
      end
      key = extract_file_key(key)
      new_bucket ||= self
      new_key    ||= key
      rs_post QiniuStorage::Operation::Move.new(bucket: self, key: key, new_bucket: new_bucket, new_key: new_key, force: force)
    end

    def copy(key, new_bucket: nil, new_key: nil, force: false)
      if new_bucket.nil? && new_key.nil?
        raise ArgumentError, "Must specify at least one bucket name or key"
      end
      key = extract_file_key(key)
      new_bucket ||= self
      new_key    ||= key
      rs_post QiniuStorage::Operation::Copy.new(bucket: self, key: key, new_bucket: new_bucket, new_key: new_key, force: force)
    end

    def chmime(key, mime)
      rs_post QiniuStorage::Operation::ChMime.new(bucket: self, key: extract_file_key(key), mime: mime)
    end

    def chtype(key, type)
      rs_post QiniuStorage::Operation::ChType.new(bucket: self, key: extract_file_key(key), type: type)
    end

    def standard(key)
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

    def fetch(source_url, key = nil)
      op = QiniuStorage::Operation::Fetch.new(bucket: self, key: key, source_url: source_url)
      metadatas = iovip_post(op)
      QiniuStorage::File.new(bucket: self, key: key).tap { |f| f.update_metadatas metadatas }
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

    def batch_move(*keys, new_bucket, force: false)
      batch keys.flatten.map { |key| extract_file_key(key) }.uniq.map { |key| QiniuStorage::Operation::Move.new(bucket: self, key: key, new_bucket: new_bucket, new_key: key, force: force) }
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

    def batch_standard(*keys)
      batch_chtype *keys, 0
    end

    def batch_low_freq(*keys)
      batch_chtype *keys, 1
    end

    def url_for(key, options = {})
      public_url = QiniuStorage.build_url(scheme: options[:scheme], host: domains.first, path: "/#{key}", query: options[:fop].to_s)
      expires_in = options[:expires_in]
      if expires_in
        sign_url public_url, expires_in
      else
        public_url
      end
    end
    
    alias :file_url :url_for

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
      client.http_get url_for(key, expires_in: expires_in), range: range_header
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

    def direct_upload_url(https: true)
      client.build_url scheme: https ? "https" : "http", host: up_host
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
        when QiniuStorage::File
          obj.key
        else
          obj.to_s
        end
      end

  end
end
