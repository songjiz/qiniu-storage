module QiniuStorage
  class Object
    class Bundle
      include Enumerable

      attr_reader :bucket, :limit, :prefix, :delimiter, :marker

      def initialize(bucket:, limit: 1000, prefix: nil, delimiter: nil, marker: nil)
        @bucket = bucket
        @limit = limit
        @prefix = prefix
        @delimiter = delimiter
        @marker = marker
      end

      def common_prefixes
        @common_prefixes ||= []
      end

      def next?
        !@next_marker.nil?
      end

      def next
        return nil unless next?
        self.class.new(bucket: @bucket, limit: @limit, prefix: @prefix, delimiter: @delimiter, marker: @next_marker)
      end

      def to_ary
        entities.dup
      end

      alias :to_a :to_ary

      def reload
        @next_marker = nil
        @common_prefixes = nil
        @entities = nil
        self
      end

      def entities
        load_entities
        @entities
      end

      def empty?
        entities.empty?
      end

      def last
        entities.last
      end

      def each(&block)
        entities.each &block
      end

      def keys
        map &:key
      end

      def names
        map &:name
      end

      def length
        entities.length
      end

      alias :size :length

      def batch_delete
        bucket.batch_delete keys
      end

      alias :batch_remove :batch_delete
      alias :delete_all :batch_delete
      alias :remove :batch_delete

      def batch_stat
        bucket.batch_stat(keys).tap do |res|
          res.each_with_index do |item, index|
            if item["code"] == 200
              entities[index].update_metadata item["data"]
            end
          end
        end
      end

      alias :stat :batch_stat
      alias :metadata :batch_stat

      def batch_move(to_bucket, force: false)
        target_bucket = build_bucket(to_bucket)
        bucket.batch_move(keys, target_bucket, force: force).tap do |res|
          res.each_with_index do |item, index|
            if item["code"] == 200
              entities[index].bucket = target_bucket
            end
          end
        end
      end

      alias :move :batch_move

      def batch_copy(to_bucket, force: false)
        target_bucket = build_bucket(to_bucket)
        bucket.batch_copy(keys, target_bucket, force: force)
      end

      alias :copy :batch_copy

      def batch_chstatus(status)
        bucket.batch_chstatus(keys, status).tap do |res|
          res.each_with_index do |item, index|
            if item["code"] == 200
              entities[index].status = status
            end
          end
        end
      end

      alias :chstatus :batch_chstatus

      def batch_enable
        batch_chstatus 0
      end

      alias :enable :batch_enable

      def batch_disable
        batch_chstatus 1
      end

      alias :disable :batch_disable

      def batch_chtype(type)
        bucket.batch_chtype(keys, type).tap do |res|
          res.each_with_index do |item, index|
            if item["code"] == 200
              entities[index].type = type
            end
          end
        end
      end

      alias :chtype :batch_chtype

      def batch_chmime(mime)
        bucket.batch_chmime(keys, mime).tap do |res|
          res.each_with_index do |item, index|
            if item["code"] == 200
              entities[index].mime_type = mime
            end
          end
        end
      end

      alias :chmime :batch_chmime

      def batch_standardize
        batch_chtype 0
      end

      alias :standardize :batch_standardize

      def batch_low_freq
        batch_chtype 1
      end

      alias :low_freq :batch_low_freq

      def reload
        @entities = nil
        @next_marker = nil
        load_entities
        self
      end

      private
        def filter_params
          QiniuStorage.prune_hash!(
            bucket: @bucket.name,
            limit: @limit,
            prefix: @prefix,
            delimiter: @delimiter,
            marker: @marker
          )
        end

        def load_entities
          @entities ||= begin
            data = bucket.rsf_get("/list", params: filter_params)
            @next_marker = data["marker"]
            @common_prefixes = data["commonPrefixes"]
            Array(data["items"]).map do |opts|
              QiniuStorage::Object.new(
                bucket: bucket,
                key: opts["key"],
                etag: opts["hash"],
                mime_type: opts["mimeType"],
                fsize: opts["fsize"],
                type: opts["type"],
                put_time: opts["putTime"],
                status: opts["status"]
              )
            end
          end
        end

        def build_bucket(obj)
          case obj
          when QiniuStorage::Bucket
            obj
          else
            bucket.client.bucket obj.to_s
          end
        end
    end

    attr_accessor :bucket, :key

    def initialize(bucket:, key:, **options)
      @bucket = bucket
      @key = key
      @_metadata = {}
    end

    def name
      "#{bucket_name}:#{key}"
    end

    def bucket_name
      bucket.name
    end

    def to_s
      name
    end

    def etag
      @_metadata[:hash]
    end

    def etag=(val)
      @_metadata[:hash] = val
    end

    def each_meta(&block)
      @_metadata.each &block
    end

    def []=(key, val)
      @_metadata[convert_metadata_key(key)] = val
    end

    def [](key)
      @_metadata[convert_metadata_key(key)]
    end

    %i(status fsize md5 mime_type type put_time end_user).each do |name|
      class_eval <<-RUBY, __FILE__, __LINE__ + 1
        def #{name}
          @_metadata[:#{name}]
        end

        def #{name}=(val)
          @_metadata[:#{name}] = val
        end
      RUBY
    end

    alias :size :fsize

    def image?
      mime_type.to_s.start_with? "image"
    end

    def audio?
      mime_type.to_s.start_with? "audio"
    end

    def video?
      mime_type.to_s.start_with? "video"
    end

    def text?
      mime_type.to_s.start_with? "text"
    end

    def encoded_uri
      bucket.encoded_uri key
    end

    def chstatus(status)
      bucket.chstatus key, status
      self.status = status
    end

    def enabled?
      status.nil? || status.zero?
    end

    def enable
      return if enabled?
      chstatus 0
    end

    def disabled?
      !enabled?
    end

    def disable
      return if disabled?
      chstatus 1
    end

    def delete_after_days(days)
      bucket.delete_after_days key, days
    end

    alias :life_cycle :delete_after_days

    def standard?
      type.zero?
    end

    def low_freq?
      !standard?
    end

    def chtype(type)
      bucket.chtype(key, type)
      self.type = type
    end

    def standardize
      return if standard?
      chtype 0
    end

    def low_freq
      return if low_freq?
      chtype 1
    end

    def stat
      bucket.stat(key).tap { |options| update_metadata(options) }
    end
    
    alias :metadata :stat

    def chmime(mime)
      bucket.chmime(key, mime)
      self.mime_type = mime
    end

    def move(to_bucket: nil, to_key: nil, force: false)
      self.tap do |obj|
        bucket.move key, to_bucket: to_bucket, to_key: to_key, force: force
        obj.bucket = to_bucket || bucket
        obj.key    = to_key || key
      end
    end

    def copy(to_bucket: nil, to_key: nil, force: false)
      bucket.copy key, to_bucket: to_bucket, to_key: to_key, force: force
      self.class.new(bucket: to_bucket || bucket , key: to_key || key)
    end

    def delete
      bucket.delete key
    end

    alias :remove :delete

    def rename(to_key, force: false)
      bucket.rename key, to_key, force: force
      @key = to_key
    end

    def fetch(source_url)
      obj = bucket.fetch(source_url, key)
      obj.each_meta do |k, v|
        self[k] = v
      end
      self
    end

    def prefetch
      bucket.prefetch key
    end

    def put(source, options = {})
      bucket.upload source, options.merge(key: key)
    end

    alias :attach :put

    def multipart_upload(source, options = {})
      bucket.multipart_upload source, options.merge(key: key)
    end

    def resumable_upload(source, options = {})
      bucket.resumable_upload source, options.merge(key: key)
    end

    def exists?
      !bucket.objects(prefix: key).empty?
    end

    def url(options = {})
      bucket.object_url key, options
    end

    def img_info(options = {})
      bucket.client.http_get url(options.merge(fop: QiniuStorage::Operation::ImageInfo.new))
    end

    def av_info(options = {})
      bucket.client.http_get url(options.merge(fop: QiniuStorage::Operation::AvInfo.new))
    end

    def download(range: nil, expires_in: nil)
      bucket.download key, range: range, expires_in: expires_in
    end

    def streaming_download(offset: 0, chunk_size: nil, expires_in: nil, &block)
      bucket.streaming_download key, offset: offset, chunk_size: chunk_size, expires_in: expires_in, &block
    end

    def update_metadata(options)
      options.each do |key, val|
        @_metadata[convert_metadata_key(key)] = val
      end
    end

    private
      def convert_metadata_key(key)
        if key.respond_to?(:underscore)
          key.underscore.to_sym
        else
          key.to_s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
        end
      end
  end
end
