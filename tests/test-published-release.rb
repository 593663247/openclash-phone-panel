require_relative 'support'
require_relative '../router/phone-dns/releases'

fixture_directory do |root|
 ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root
 response={'tag_name'=>'v1.2.3','draft'=>false,'prerelease'=>false};calls=0
 PhoneRelease.define_singleton_method(:http_json) do |path,timeout:20|
  assert(path=='/releases/latest'&&timeout==10);calls+=1
  raise 'network unavailable' if response.nil?
  response
 end
 first=PhoneRelease.published_release;assert(first['tag']=='v1.2.3'&&first['status']=='available')
 assert(PhoneRelease.published_release==first&&calls==1,'page reads must reuse successful cache')
 response=nil;failed=PhoneRelease.published_release(refresh:true)
 assert(failed['status']=='unavailable'&&failed['tag']=='v1.2.3'&&failed['checked_at']==first['checked_at'],'failed checks retain labelled last-success data')
 PhoneRelease.published_release;assert(calls==2,'failed automatic checks must be throttled')
 response={'tag_name'=>'v2.0.0','draft'=>false,'prerelease'=>false}
 assert(PhoneRelease.published_release(refresh:true)['tag']=='v2.0.0','manual checks bypass the cache')
 [{'tag_name'=>'javascript:fixture','draft'=>false,'prerelease'=>false},{'tag_name'=>'v3.0.0','draft'=>true,'prerelease'=>false},{'tag_name'=>'v3.0.0','draft'=>false,'prerelease'=>true}].each do |invalid|
  response=invalid;record=PhoneRelease.published_release(refresh:true)
  assert(record['status']=='unavailable'&&record['tag']=='v2.0.0','invalid or unpublished tags cannot replace the latest release')
 end
 File.delete(PanelStore.state+'/published-release.yaml');response=nil
 unknown=PhoneRelease.published_release;assert(unknown['status']=='unavailable'&&!unknown.key?('tag'),'uncached failure must not invent a latest version')
end
ENV.delete('PHONE_PANEL_TEST_ROOT');ENV.delete('PHONE_PANEL_TEST')
puts 'Published releases: real tags, cache/manual refresh, failure retention and invalid/draft/prerelease rejection PASS'
