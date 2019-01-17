module QiniuStorage
  class AsyncFetchJob
    attr_reader :bucket, :job_id, :wait

    def initialize(bucket:, job_id:, wait:)
      @bucket = bucket
      @job_id = job_id
      @wait = wait
    end

    def fetch
      bucket.async_fetch_job(job_id).tap do |result|
        @wait = result["wait"]
      end
    end

    alias_method :refresh, :fetch
  end
end