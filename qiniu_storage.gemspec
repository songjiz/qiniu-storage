lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'qiniu_storage/version'

Gem::Specification.new do |spec|
  spec.name          = 'qiniu-storage'
  spec.version       = QiniuStorage::VERSION
  spec.authors       = ['songji']
  spec.email         = ['lekyzsj@gmail.com']
  spec.summary       = %q{Unoffical gem for Qiniu Cloud Storage.}
  spec.description   = %q{Unoffical gem for Qiniu Cloud Storage.}
  spec.homepage      = 'https://github.com/songjiz/qiniu-storage.'
  spec.license       = 'MIT'
  spec.require_paths = ['lib']
  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.add_development_dependency 'bundler', '~> 1.16'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
end
