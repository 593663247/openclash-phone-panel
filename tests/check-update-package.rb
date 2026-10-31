require_relative 'support'
require_relative '../router/phone-dns/releases'

if RUBY_PLATFORM.match?(/mswin|mingw/)
 require 'zlib'
 PhoneRelease.define_singleton_method(:extract) do |archive,destination|
  Zlib::GzipReader.open(archive){|io|PhoneRelease.unpack_stream(io,destination);io.read}
 end
end
archive=File.expand_path(ARGV.fetch(0));original_run=PanelStore.method(:run)
%w[1.0.1 1.0.2 1.0.3 1.1.0 1.1.1 1.2.0 1.2.1].each do |old_version|
 fixture_directory do |root|
  ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
  stage=root+'/inspect';PhoneRelease.extract(archive,stage)
  doc=YAML.safe_load(File.binread(stage+'/update-manifest.json'));target=doc['commit'];tag='v'+doc['version']
  pairs=PhoneUpdatePackage.entries(stage,target,tag)
  assert(pairs.any?{|_,to,_|to=='/etc/phone-dns/update-package.rb'},'a newly introduced module must be in the manifest')
  PanelStore.mkdir(PanelStore.path('/var/lock'))
  PanelStore.atomic(PanelStore.path('/usr/share/phone-panel/deployed-commit'),'a'*40)
  PanelStore.atomic(PanelStore.path('/usr/share/phone-panel/VERSION'),old_version)
  # Old deployments can lack newly introduced code and init scripts.
  PanelStore.atomic(PanelStore.path('/etc/phone-dns/releases.rb'),'old '+old_version)
  paths=%w[/etc/config/dhcp /etc/config/openclash /etc/config/phone_panel /etc/phone-dns/managed-bindings.yaml /etc/phone-dns/managed-nodes.yaml /etc/phone-dns/persistent-guard.yaml]
  paths.each{|p|PanelStore.atomic(PanelStore.path(p),'preserve fixture '+p)}
  PhoneRelease.define_singleton_method(:protected_paths){paths}
  PhoneRelease.define_singleton_method(:activate){true}
  PhoneRelease.define_singleton_method(:health_check){{'groups'=>[{'id'=>1,'dns_listening'=>true,'socks_listening'=>true,'binding_ok'=>true}],'device_count'=>1,'guard_ready'=>true,'dns_redirect_ready'=>true}}
  PhoneMaintenanceHealth.define_singleton_method(:preflight){{'ok'=>true,'checks'=>[]}}
  PhoneMaintenanceHealth.define_singleton_method(:space){|_|1024*1024*1024}
  PhoneRelease.define_singleton_method(:http_json) do |path|
   case path
   when '/releases/latest'
    {'id'=>1,'tag_name'=>tag,'draft'=>false,'prerelease'=>false,'assets'=>[{'id'=>2,'name'=>PhoneUpdatePackage::ASSET,'size'=>File.size(archive),'digest'=>'sha256:'+Digest::SHA256.file(archive).hexdigest,'browser_download_url'=>"https://github.com/#{PhoneRelease::REPOSITORY}/releases/download/#{tag}/#{PhoneUpdatePackage::ASSET}"}]}
   when '/git/ref/tags/'+tag;{'object'=>{'type'=>'commit','sha'=>target}}
   when %r{\A/compare/};{'status'=>'ahead'}
   when %r{\A/actions/runs};{'workflow_runs'=>[{'path'=>'.github/workflows/ci.yml','event'=>'push','head_sha'=>target,'status'=>'completed','conclusion'=>'success','run_number'=>1}]}
   else;raise 'unexpected API: '+path;end
  end
  PanelStore.define_singleton_method(:capture){|*args|['123',0]}
  bad_download=false
  PanelStore.define_singleton_method(:run) do |*args|
   if args.first=='curl'
    output=args[args.index('-o')+1];IO.copy_stream(archive,output);File.open(output,'ab'){|f|f.write('interrupted transfer')} if bad_download;''
   elsif args.first=='sha256sum';Digest::SHA256.file(args[1]).hexdigest+'  '+args[1]
   elsif args.include?('backup');'/root/fixture-config-backup'
   else;'';end
  end
  checked=PhoneRelease.check;assert(checked['can_upgrade'],'valid formal release should be upgradeable from '+old_version)
  before=PhoneRelease.hashes(paths)
  bad_download=true
  rejects('corrupt downloads must abort before installed code changes'){PhoneRelease.upgrade(target,fingerprint:checked['fingerprint'])}
  assert(PhoneRelease.current=='a'*40&&File.binread(PanelStore.path('/etc/phone-dns/releases.rb'))=='old '+old_version)
  assert(PhoneRelease.records.empty?,'download failure must not begin an install transaction')
  bad_download=false
  rejects('changed or stale published asset identity must abort'){PhoneRelease.upgrade(target,fingerprint:'f'*64)}
  PhoneMaintenanceHealth.define_singleton_method(:space){|_|0}
  rejects('insufficient installation/recovery space must abort'){PhoneRelease.upgrade(target,fingerprint:checked['fingerprint'])}
  assert(PhoneRelease.records.empty?&&PhoneRelease.current=='a'*40)
  PhoneMaintenanceHealth.define_singleton_method(:space){|_|1024*1024*1024}
  result=PhoneRelease.upgrade(target,fingerprint:checked['fingerprint'])
  assert(result['ok']&&PhoneRelease.current==target&&PhoneRelease.version==doc['version'])
  PhoneUpdatePackage.verify_installed(pairs)
  assert(PhoneRelease.hashes(paths)==before,'program upgrades must preserve desired device/node/DHCP/config state')
  assert(PhoneRelease.records.first['status']=='installed')
  assert(PhoneRelease.check['can_upgrade']==false,'the installed formal release cannot be replayed')
 end
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
PanelStore.define_singleton_method(:run,original_run)
puts 'Packaged online update: seven legacy-version fixtures, missing new helpers, stale assets, corrupt downloads, complete installed hashes and untouched desired/network state PASS'
