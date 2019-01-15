require "base64"
require "digest"

module QiniuStorage
	module QEtag
		BLOCK_SIZE = 4 * 1024 * 1024

		class << self
			def etag(source)
				case source
				when String, Pathname
					::File.open(source, "rb") do |f|
						generate_etag collect_sha1_digests(f)
					end
				else
					if QiniuStorage.streamable?(source)
						generate_etag collect_sha1_digests(source)
					else
						raise ArgumentError, "Expected a String, Pathname, IO, StringIO or Tempfile, but got #{source.inspect}"
					end
				end
			end

			private
				def collect_sha1_digests(io)
					sha1 = []
					io.rewind
					until io.eof?
						chunk = io.read(BLOCK_SIZE)
						sha1 << Digest::SHA1.digest(chunk)
					end
					sha1
				ensure
					io.rewind
				end

				def generate_etag(sha1_digests)
					if sha1_digests.size == 1
						Base64.urlsafe_encode64(0x16.chr + sha1_digests[0])
					else
						Base64.urlsafe_encode64(0x96.chr + Digest::SHA1.digest(sha1_digests.join))
					end 
				end
		end
	end
end