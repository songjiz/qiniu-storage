module QiniuStorage
  module Operation
    class AbstractOperation
      def call
        raise NotImplementedError
      end

      def to_s
        call
      end
    end

    class AvInfo < AbstractOperation
      def call
        "avinfo"
      end
    end

    class ChMime < AbstractOperation
      def initialize(bucket:, key:, mime:)
        @bucket = bucket
        @key = key
        @mime = mime
      end

      def call
        encoded_entry = QiniuStorage.encode_entry(@bucket, @key)
        encoded_mime = QiniuStorage.base64_urlsafe_encode(@mime)
        "/chgm/#{encoded_entry}/mime/#{encoded_mime}"
      end
    end

    class ChStatus < AbstractOperation
      def initialize(bucket:, key:, status:)
        @bucket = bucket
        @key = key
        @status = status
      end

      def call
        encoded_entry = QiniuStorage.encode_entry(@bucket, @key)
        "/chstatus/#{encoded_entry}/status/#{@status}"
      end
    end

    class ChType < AbstractOperation
      def initialize(bucket:, key:, type:)
        @bucket = bucket
        @key = key
        @type = type
      end

      def call
        encoded_entry = QiniuStorage.encode_entry(@bucket, @key)
        "/chtype/#{encoded_entry}/type/#{@type}"
      end
    end

    class Copy < AbstractOperation
      def initialize(bucket:, key:, new_bucket:, new_key:, force: false)
        @bucket = bucket
        @key = key
        @new_bucket = new_bucket
        @new_key = new_key
        @force = force
      end

      def call
        source_encoded_entry = QiniuStorage.encode_entry(@bucket, @key)
        target_encoded_entry = QiniuStorage.encode_entry(@new_bucket, @new_key)
        "/copy/#{source_encoded_entry}/#{target_encoded_entry}/force/#{@force}"
      end
    end

    class DeleteAfterDays < AbstractOperation
      def initialize(bucket:, key:, days:)
        @bucket = bucket
        @key = key
        @days = days
      end

      def call
        encoded_entry = QiniuStorage.encode_entry(@bucket, @key)
        "/deleteAfterDays/#{encoded_entry}/#{days}"
      end
    end

    class Delete < AbstractOperation
      def initialize(bucket:, key:)
        @bucket = bucket
        @key = key
      end

      def call
        encoded_entry = QiniuStorage.encode_entry @bucket, @key
        "/delete/#{encoded_entry}"
      end
    end

    class Move < AbstractOperation
      def initialize(bucket:, key:, new_bucket:, new_key: nil, force: false)
        @bucket = bucket
        @key = key
        @new_bucket = new_bucket
        @new_key = new_key
        @force = force
      end

      def call
        source_encoded_entry = QiniuStorage.encode_entry(@bucket, @key)
        target_encoded_entry = QiniuStorage.encode_entry(@new_bucket, @new_key)
        "/move/#{source_encoded_entry}/#{target_encoded_entry}/force/#{@force}"
      end
    end

    class Fetch < AbstractOperation
      def initialize(bucket:, key:, source_url:)
        @bucket = bucket
        @key = key
        @source_url = source_url
      end

      def call
        resource = QiniuStorage.base64_urlsafe_encode(@source_url)
        encoded_entry = QiniuStorage.encode_entry(@bucket, @key)
        "/fetch/#{resource}/to/#{encoded_entry}"
      end
    end

    class PreFetch < AbstractOperation
      def initialize(bucket:, key:)
        @bucket = bucket
        @key = key
      end

      def call
        encoded_entry = QiniuStorage.encode_entry(@bucket, @key)
        "/prefetch/#{encoded_entry}"
      end
    end

    class ImageInfo < AbstractOperation
      def call
        "imageInfo"
      end
    end

    class Stat < AbstractOperation
      def initialize(bucket:, key:)
        @bucket = bucket
        @key = key
      end

      def call
        encoded_entry = QiniuStorage.encode_entry @bucket, @key
        "/stat/#{encoded_entry}"
      end
    end
  end
end
