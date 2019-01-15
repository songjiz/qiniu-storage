module QiniuStorage
  # https://developer.qiniu.com/kodo/manual/1671/region-endpoint
  class Zone
    UC_HOST    = "uc.qbox.me"
    RS_HOST    = "rs.qiniu.com"
    RSF_HOST   = "rsf.qiniu.com"
    API_HOST   = "api.qiniu.com"
    IOVIP_HOST = "iovip.qbox.me"
    LIST       = ["z0", "z1", "z2", "na0", "as0"].freeze

    class << self
      def zones_map
        @zones_map ||= LIST.inject({}) { |memo, name| memo[name] = self.send(name) ; memo }
      end

      def default
        z0
      end
      
      def z0
        new({
          name: "z0",
          src_up_hosts: [
            "up.qiniup.com",
            "up-jjh.qiniup.com",
            "up-xs.qiniup.com"
          ],
          cdn_up_hosts: [
            "upload.qiniup.com",
            "upload-nb.qiniup.com",
            "upload-xs.qiniup.com"
          ]
        })
      end

      def z1
        new({
          name: "z1",
          rs_host: "rs-z1.qbox.me",
          rsf_host: "rsf-z1.qbox.me",
          api_host: "api-z1.qiniu.com",
          iovip_host: "iovip-z1.qbox.me",
          src_up_hosts: [
            "up-z1.qiniup.com"
          ],
          cdn_up_hosts: [
            "upload-z1.qiniup.com"
          ]
        })
      end

      def z2
        new({
          name: "z2",
          rs_host: "rs-z2.qbox.me",
          rsf_host: "rsf-z2.qbox.me",
          api_host: "api-z2.qiniu.com",
          iovip_host: "iovip-z2.qbox.me",
          src_up_hosts: [
            "up-z2.qiniup.com"
          ],
          cdn_up_hosts: [
            "upload-z2.qiniup.com"
          ]
        })
      end

      def na0
        new({
          name: "na0",
          rs_host: "rs-na0.qbox.me",
          rsf_host: "rsf-na0.qbox.me",
          api_host: "api-na0.qiniu.com",
          iovip_host: "iovip-na0.qbox.me",
          src_up_hosts: [
            "up-na0.qiniup.com"
          ],
          cdn_up_hosts: [
            "upload-na0.qiniup.com"
          ]
        })
      end

      def as0
        new({
          name: "as0",
          rs_host: "rs-as0.qbox.me",
          rsf_host: "rsf-as0.qbox.me",
          api_host: "api-as0.qiniu.com",
          iovip_host: "iovip-as0.qbox.me",
          src_up_hosts: [
            "up-as0.qiniup.com"
          ],
          cdn_up_hosts: [
            "upload-as0.qiniup.com"
          ]
        })
      end

      def [](region)
        zones_map[region.to_s]
      end
    end

    attr_reader :name
    attr_reader :src_up_hosts, :cdn_up_hosts, :iovip_host
    attr_reader :rs_host, :rsf_host, :api_host, :uc_host

    def initialize(name:, **options)
      @name = name
      @src_up_hosts = Array(options[:src_up_hosts])
      @cdn_up_hosts = Array(options[:cdn_up_hosts])
      @uc_host = options.fetch(:uc_host, UC_HOST)
      @iovip_host = options.fetch(:iovip_host, IOVIP_HOST)
      @rs_host = options.fetch(:rs_host, RS_HOST)
      @rsf_host = options.fetch(:rsf_host, RSF_HOST)
      @api_host = options.fetch(:api_host, API_HOST)
    end
  end
end
