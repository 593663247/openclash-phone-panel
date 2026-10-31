require 'digest'
require_relative 'panel-store'

# Stable manifest interpreter. A release requiring a newer interpreter is blocked.
module PhoneUpdatePackage
 FORMAT=1
 ASSET='phone-panel-update.tar.gz'
 REQUIRED=%w[/etc/phone-dns/releases.rb /etc/phone-dns/update-package.rb /etc/phone-dns/operations.rb /etc/phone-dns/panel-status.rb /etc/init.d/phone-panel-guard /usr/share/phone-panel/VERSION /usr/lib/lua/luci/controller/phone_panel.lua /usr/lib/lua/luci/view/phone_panel.htm].freeze
 def self.candidate
  release=PhoneRelease.http_json('/releases/latest');tag=release['tag_name'].to_s
  raise '没有可用的正式发布版本' unless tag.match?(/\Av?\d+\.\d+\.\d+\z/)&&release['draft']==false&&release['prerelease']==false&&release['id'].is_a?(Integer)
  object=PhoneRelease.http_json('/git/ref/tags/'+tag).fetch('object')
  4.times do
   break if object['type']=='commit'
   raise '发布标签指向无效对象' unless object['type']=='tag'&&object['sha'].to_s.match?(PhoneRelease::SHA)
   object=PhoneRelease.http_json('/git/tags/'+object['sha']).fetch('object')
  end
  commit=object['sha'].to_s
  raise '发布标签没有有效提交' unless object['type']=='commit'&&commit.match?(PhoneRelease::SHA)
  assets=release.fetch('assets',[]).select{|a|a['name']==ASSET}
  raise '此发布缺少新版在线升级包，请安装完整 IPK 后再使用在线升级' unless assets.size==1
  asset=assets.first;digest=asset['digest'].to_s
  raise '发布包缺少有效 SHA-256 或大小异常' unless digest.match?(/\Asha256:[a-f0-9]{64}\z/)&&asset['size'].is_a?(Integer)&&asset['size'].between?(1,20*1024*1024)&&asset['id'].is_a?(Integer)
  expected="https://github.com/#{PhoneRelease::REPOSITORY}/releases/download/#{tag}/#{ASSET}"
  raise '发布包下载地址不属于固定仓库' unless asset['browser_download_url']==expected
  data={'release_id'=>release['id'],'tag'=>tag,'latest'=>commit,'asset_id'=>asset['id'],'asset_sha256'=>digest.delete_prefix('sha256:'),'asset_size'=>asset['size'],'asset_url'=>expected}
  data['fingerprint']=Digest::SHA256.hexdigest(PanelStore.json(data));data
 end
 def self.entries(source,commit,tag)
  manifest_path=source+'/update-manifest.json'
  raise '升级文件清单缺失或过大' unless File.file?(manifest_path)&&!File.symlink?(manifest_path)&&File.size(manifest_path)<=1024*1024
  manifest=YAML.safe_load(File.binread(manifest_path),aliases:false)
  raise '升级文件清单格式不兼容，请先安装完整 IPK' unless manifest.is_a?(Hash)&&manifest['schema']==FORMAT&&manifest['min_updater'].is_a?(Integer)&&manifest['min_updater'].between?(1,FORMAT)
  raise '升级包版本与正式发布不一致' unless manifest['commit']==commit&&manifest['version']==tag.delete_prefix('v')
  rows=manifest['files'];raise '升级文件清单为空或过大' unless rows.is_a?(Array)&&rows.size.between?(REQUIRED.size,1900)
  destinations=[];sources=[]
  pairs=rows.map do |row|
   raise '升级文件条目格式无效' unless row.is_a?(Hash)
   relative=row['source'];destination=row['destination'];mode=row['mode']
   raise '升级文件路径无效' unless relative.is_a?(String)&&relative.match?(%r{\Afiles/[a-zA-Z0-9_./-]+\z})&&!relative.split('/').any?{|part|%w[. ..].include?(part)}
   raise '升级目标路径无效' unless destination.is_a?(String)&&relative=='files'+destination&&PhoneRelease.allowed_destination?(destination)&&!destination.split('/').any?{|part|%w[. ..].include?(part)}
   raise '升级清单不能替换保留的版本标记' if %w[/usr/share/phone-panel/deployed-commit /usr/share/phone-panel/installed-update-manifest.json].include?(destination)
   raise '升级文件权限无效' unless [0600,0644,0700,0755].include?(mode)
   raise '启动脚本必须可执行' if destination.start_with?('/etc/init.d/')&&mode!=0755
   raise '升级文件重复' if sources.include?(relative)||destinations.include?(destination)
   sources<<relative;destinations<<destination
   file=source+'/'+relative
   raise '升级文件缺失或校验失败' unless File.file?(file)&&!File.symlink?(file)&&row['sha256'].to_s.match?(/\A[a-f0-9]{64}\z/)&&Digest::SHA256.file(file).hexdigest==row['sha256']
   [file,destination,mode]
  end
  raise '升级包缺少必要程序文件' unless (REQUIRED-destinations).empty?
  actual=Dir.glob(source+'/**/*',File::FNM_DOTMATCH).reject{|p|File.directory?(p)}.map{|p|p.delete_prefix(source+'/')}
  raise '升级包包含未声明文件' unless actual.sort==(sources+['update-manifest.json']).sort
  raise '升级包内版本文件不一致' unless File.read(source+'/files/usr/share/phone-panel/VERSION').strip==manifest['version']
  pairs+[[manifest_path,'/usr/share/phone-panel/installed-update-manifest.json',0600]]
 end
 def self.verify_installed(pairs)
  pairs.each do |from,destination,mode|
   file=PanelStore.path(destination)
   raise '已安装文件内容不一致：'+destination unless File.file?(file)&&!File.symlink?(file)&&Digest::SHA256.file(file).hexdigest==Digest::SHA256.file(from).hexdigest
   raise '已安装文件权限不一致：'+destination unless RUBY_PLATFORM.match?(/mswin|mingw/)||(File.stat(file).mode&0777)==mode
  end
  true
 end
end
