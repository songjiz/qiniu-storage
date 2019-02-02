require "forwardable"
require "fileutils"
require "pathname"

module QiniuStorage
  class Uploader
    extend Forwardable
    
    using Module.new {
      refine Hash do
        def deep_symbolize_keys!
          keys.each do |key|
            val = self.delete key
            self[(key.to_sym rescue key)] = \
              case val
              when Hash
                val.deep_symbolize_keys!
              when Array
                val.map do |item|
                  item.is_a?(Hash) ? item.deep_symbolize_keys! : item
                end
              else
                val
              end
          end
          self
        end unless method_defined? :deep_symbolize_keys!
      end
    }

    module Resumable
      class Context
        attr_reader :value, :offset, :expired_at, :checksum, :crc32
    
        def initialize(value:, offset:, expired_at:, checksum: nil, crc32: nil)
          @value = value
          @offset = offset
          @expired_at = expired_at.to_i
          @checksum = checksum
          @crc32 = crc32
        end
    
        def to_s
          @value
        end
    
        def expired?
          Time.now.utc.to_i > @expired_at
        end
    
        def to_h
          { value: @value, offset: @offset, checksum: @checksum, crc32: @crc32, expired_at: @expired_at }
        end
      end

      class Progress
        attr_accessor :token
        attr_reader :parts
    
        def initialize(token: nil, parts: [])
          @token = token
          @parts = []
          @mutex = Mutex.new
          Array(parts).each{ |hash| _push_part hash }
        end
    
        def clear
          synchronize { parts.clear }
        end
    
        def take
          synchronize do
            part = parts.detect { |part| !part.completed? && !part.took? }
            part && part.took!
          end
        end

        def completed
          synchronize do
            parts.select(&:completed?)
          end
        end

        def completed?
          !uncompleted?
        end

        def uncompleted
          synchronize do
            parts.select(&:uncompleted?)
          end
        end

        def uncompleted?
          synchronize do
            parts.any?(&:uncompleted?)
          end
        end
    
        def push(part)
          synchronize { _push_part part }
          self
        end
    
        def last_ctx_values
          synchronize { parts.sort_by(&:id).map(&:last_ctx).map(&:value) }
        end
    
        def to_h
          { token: token, parts: parts.map(&:to_h) }
        end
    
        private
          def synchronize(&block)
            @mutex.synchronize &block
          end
    
          def _push_part(part)
            case part
            when QiniuStorage::Uploader::Resumable::Part
              parts.push part
            when Hash
              parts.push QiniuStorage::Uploader::Resumable::Part.new(part)
            else
              raise ArgumentError, "Expected a QiniuStorage::Uploader::Resumable::Part or Hash, but got #{part.inspect}"
            end
          end
      end

      class Part
        attr_reader :id, :range, :ctxs
    
        def initialize(id:, range:, ctxs: nil)
          @id = id
          case range
          when Array
            @range = Range.new(range[0], range[1])
          when Range
            @range = range
          else
            raise ArgumentError, "Expected a Range or Array, but got #{range.inspect}"
          end
          @took = false
          @ctxs = []
          Array(ctxs).each { |hash| push hash }
        end
    
        def offset
          @range.begin
        end
    
        def last_ctx
          @ctxs.last
        end
    
        def took?
          @took
        end
    
        def took!
          self.tap { @took = true }
        end
    
        def empty?
          @ctxs.empty?
        end
    
        def completed?
          last_ctx && (offset + last_ctx.offset - 1) == range.max
        end

        def uncompleted?
          !completed?
        end
    
        def size
          range.size
        end
    
        alias_method :length, :size
    
        def uploaded_size
          if empty?
            0
          else
            last_ctx.offset
          end
        end
        
        alias_method :completed_size, :uploaded_size
    
        def uncompleted_size
          size - uploaded_size
        end
    
        def ctxs_values
          @ctxs.map(&:value)
        end
    
        def push(ctx)
          case ctx
          when QiniuStorage::Uploader::Resumable::Context
            @ctxs.push ctx
          when Hash
            @ctxs.push QiniuStorage::Uploader::Resumable::Context.new(ctx)
          else
            raise ArgumentError, "Expected a QiniuStorage::Uploader::Resumable::Context or Hash, but got #{ctx.inspect}"
          end
          self
        end
    
        def to_h
          { id: id, range: [range.begin, range.max], ctxs: ctxs.map(&:to_h) }
        end
      end
    end

    attr_reader :client
    def_delegators :client, :generate_upload_token, :invalid_upload_token?

    def initialize(client:)
      @client = client
      @resumable_mutex = Mutex.new
    end

    def upload(source, bucket, options = {})
      source_size = if String === source || Pathname === source
                      File.size source
                    elsif streamable?(source)
                      source.size
                    else
                      raise ArgumentError, "Expected a String, Pathname, IO, StringIO or Tempfile, but got #{source.inspect}"
                    end
      if source_size > QiniuStorage.configuration.upload_resumable_threshold
        resumable_upload source, bucket, options
      else
        multipart_upload source, bucket, options
      end
    end

    def multipart_upload(source, bucket, options = {})
      bucket = build_bucket(bucket)
      policy = options.fetch(:policy, {})
      expires_in = options.fetch(:expires_in, QiniuStorage.configuration.upload_token_expires_in)
      with_streamable(source) do |stream|
        form = {}
        if options[:key]
          form["key"] = options[:key]
        end
        if !options.fetch(:skip_crc32, QiniuStorage.configuration.skip_crc32_checksum?)
          form["crc32"] = QiniuStorage.crc32_checksum(stream).to_s
        end
        form["file"] = stream
        form["token"] = generate_upload_token(bucket.name, form["key"], expires_in, policy: policy)
        options.fetch(:extras, {}).each { |k, v| form["x:#{k}"] = v }
        url = client.build_url(host: bucket.up_host)
        result = client.http_post(url, form, "Content-Type" => "multipart/form-data")
        QiniuStorage::Object.new(bucket: bucket, key: result["key"], hash: result["hash"])
      end
    end

    def resumable_upload(source, bucket, options = {})
      complete = false
      bucket = build_bucket(bucket)
      up_host = bucket.up_host
      policy = options.fetch(:policy, {})
      expires_in = options.fetch(:expires_in, QiniuStorage.configuration.upload_token_expires_in)
      block_size = options.fetch(:block_size, QiniuStorage.configuration.upload_block_size)
      chunk_size = options.fetch(:chunk_size, QiniuStorage.configuration.upload_chunk_size)
      threads_count = options.fetch(:threads, QiniuStorage.configuration.upload_max_threads).to_i
      skip_crc32 = options.fetch(:skip_crc32_checksum, QiniuStorage.configuration.skip_crc32_checksum?)
      with_streamable(source) do |stream|
        progress_file = lookup_resumable_progress_file(bucket, stream)
        progress = load_resumable_progress(progress_file)
        token = progress.token
        if invalid_upload_token?(token)
          token = generate_upload_token(bucket.name, options[:key], expires_in, policy: policy)
          progress.clear
          progress.token = token
          generate_parts(stream.size, block_size) { |part| progress.push part }
        end
        (1..[threads_count, progress.parts.count].min).map { schedule_upload_part(up_host, token, stream, progress, chunk_size, skip_crc32) }.map(&:join)
        result = mkfile(up_host, token, stream, progress.last_ctx_values, key: options[:key], mime_type: options[:mime_type], extras: options[:extras])
        complete = true
        QiniuStorage::Object.new(bucket: bucket, key: result["key"], hash: result["hash"])
      ensure
        if progress_file && progress
          if complete
            FileUtils.rm_f progress_file
          else
            if QiniuStorage.configuration.use_upload_cache?
              dump_resumable_progress(progress, progress_file)
            end
          end
        end
      end
    end

    def lookup_resumable_progress_file(bucket, io)
      digest = QiniuStorage.md5_checksum(io)
      File.join QiniuStorage.configuration.cache_dir, bucket.to_s, digest
    end

    def dump_resumable_progress(progress, to)
      resumable_synchronize do
        unless File.exist?(to)
          FileUtils.mkdir_p File.dirname(to)
        end
        File.open(to, "wb") { |f| f.puts JSON.pretty_generate(progress.to_h) }
      end
    end

    def load_resumable_progress(from)
      resumable_synchronize do
        hash = JSON.load(File.read from)
        Resumable::Progress.new hash.deep_symbolize_keys!
      rescue => e
        QiniuStorage.logger.debug "[QiniuStorage] Faild to open progress file, reason: #{e.message}"
        Resumable::Progress.new
      end      
    end

    private
      def build_bucket(bucket)
        case bucket
        when QiniuStorage::Bucket
          bucket
        when String, Symbol
          QiniuStorage::Bucket.new(name: bucket.to_s, client: client)
        else
          raise ArgumentError, "Expected a QiniuStorage::Bucket or a Symbol bucket name or a String bucket name, but got #{bucket.inspect}"
        end
      end

      def with_streamable(source)
        if String === source || Pathname === source
          File.open(source, "rb") { |f| yield f }
        elsif streamable?(source)
          yield source
        else
          raise ArgumentError, "Expected a String, Pathname, IO, StringIO or Tempfile, but got #{source.inspect}"
        end
      end

      def streamable?(source)
        QiniuStorage.streamable? source
      end

      def schedule_upload_part(host, token, io, progress, chunk_size, skip_crc32 = false)
        Thread.new do
          loop do
            part = progress.take
            unless part
              QiniuStorage.logger.debug "[QiniuStorage] No more parts to upload, thead##{Thread.current.object_id} quit."
              break
            end
            QiniuStorage.logger.debug "[QiniuStorage] Start uploading part #{part.id + 1}/#{progress.parts.count} in thead##{Thread.current.object_id}"
            upload_part host, token, io, part, chunk_size, skip_crc32
          end
        end
      end

      def upload_part(host, token, io, part, chunk_size, skip_crc32 = false)
        if part.empty?
          io.seek part.offset
          chunk = io.read([chunk_size, part.size].min)
          result = mkblock(host, token, part.size, chunk)
          !skip_crc32 && verify_crc32_checksum!(chunk, result["crc32"])
          part.push(value: result["ctx"], offset: result["offset"], checksum: result["checksum"], crc32: result["crc32"], expired_at: result["expired_at"])
        end
        until part.completed? do
          ctx = part.last_ctx
          io.seek(part.offset + ctx.offset)
          chunk = io.read([chunk_size, part.uncompleted_size].min)
          result = mkchunk(host, token, chunk, ctx.value, ctx.offset)
          !skip_crc32 && verify_crc32_checksum!(chunk, result["crc32"])
          part.push(value: result["ctx"], offset: result["offset"], checksum: result["checksum"], crc32: result["crc32"], expired_at: result["expired_at"])
        end
      end

      def mkblock(host, token, size, chunk)
        url = client.build_url(host: host, path: "/mkblk/#{size}")
        client.http_post url, chunk, "Authorization" => "UpToken #{token}"
      end

      def mkchunk(host, token, chunk, ctx, offset)
        url = client.build_url(host: host, path: "/bput/#{ctx}/#{offset}")
        client.http_post url, chunk, "Authorization" => "UpToken #{token}"
      end

      def mkfile(host, token, io, ctxs, key: nil, mime_type: nil, extras: nil)
        path = "/mkfile/#{io.size}"
        key && path << "/key/#{QiniuStorage.base64_urlsafe_encode(key)}"
        mime_type && path << "/mimeType/#{QiniuStorage.base64_urlsafe_encode(mime_type)}"
        (extras || {}).each do |k, v|
          var_name = "x:#{k}"
          var_value = QiniuStorage.base64_urlsafe_encode(v)
          path << "/#{var_name}/#{var_value}"
        end
        url = client.build_url(host: host, path: path)
        body = ctxs.join(",")
        client.http_post url, body, "Authorization" => "UpToken #{token}"
      end

      def generate_parts(io_size, block_size)
        parts = (io_size.to_f / block_size).ceil
        (0...parts).each do |i|
          form = i * block_size
          to = [(i + 1) * block_size, io_size].min
          yield id: i, range: form...to
        end
      end
    
      def resumable_synchronize(&block)
        @resumable_mutex.synchronize &block
      end

      def verify_crc32_checksum!(data, crc32)
        checksum = QiniuStorage.crc32_checksum(data)
        raise "Invalid CRC32, expected `#{checksum}`, but got `#{crc32}`" unless checksum == crc32
      end
  end
end
