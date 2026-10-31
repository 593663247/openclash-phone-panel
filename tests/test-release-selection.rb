require_relative 'support'
require_relative '../router/phone-dns/releases'
tag='v1.3.0';commit='b'*40
release={'id'=>1,'tag_name'=>tag,'draft'=>false,'prerelease'=>false,'assets'=>[{'id'=>2,'name'=>'phone-panel-update.tar.gz','digest'=>'sha256:'+'c'*64,'size'=>100,'browser_download_url'=>"https://github.com/#{PhoneRelease::REPOSITORY}/releases/download/#{tag}/phone-panel-update.tar.gz"}]}
response=Marshal.load(Marshal.dump(release));annotated=false;paths=[]
PhoneRelease.define_singleton_method(:http_json) do |path|
 paths<<path
 case path
 when '/releases/latest';response
 when '/git/ref/tags/'+tag;{'object'=>{'type'=>annotated ? 'tag' : 'commit','sha'=>annotated ? 'd'*40 : commit}}
 when '/git/tags/'+'d'*40;{'object'=>{'type'=>'commit','sha'=>commit}}
 else;raise 'Unexpected API request';end
end
assert(PhoneUpdatePackage.candidate['latest']==commit)
annotated=true;assert(PhoneUpdatePackage.candidate['latest']==commit,'annotated tags must resolve to their commit')
assert(!paths.include?('/commits/main'),'online upgrades must never select the main branch')
[
 release.merge('draft'=>true),release.merge('prerelease'=>true),release.merge('tag_name'=>'main'),release.merge('assets'=>[]),
 release.merge('assets'=>[release['assets'][0].merge('digest'=>nil)]),
 release.merge('assets'=>[release['assets'][0].merge('size'=>21*1024*1024)]),
 release.merge('assets'=>[release['assets'][0].merge('browser_download_url'=>'https://example.invalid/package')])
].each do |invalid|
 response=invalid;rejects('unsafe or incomplete formal release accepted'){PhoneUpdatePackage.candidate}
end
puts 'Formal release selection: fixed repository, lightweight/annotated tags, no main, asset identity/digest/size and draft/prerelease rejection PASS'
