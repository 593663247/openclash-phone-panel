require_relative 'support'
require 'rbconfig'
script=File.expand_path('../scripts/hooks.rb',__dir__)
fixture_directory do |root|
 base=root+'/etc/openclash/custom';parts=base.split('/');parts.each_index{|i|p=parts[0..i].join('/');Dir.mkdir(p,0700) unless p.empty?||Dir.exist?(p)}
 original={
  'openclash_custom_overwrite.sh'=>"#!/bin/sh\n# retain administrator customization\ntrue\nruby /etc/phone-dns/align-dns.rb \"$1\" || exit 1\nruby /etc/phone-dns/add-listeners.rb \"$1\" || exit 1\nexit 0\n",
  'openclash_custom_firewall_rules.sh'=>"#!/bin/sh\n# retain administrator firewall customization\ntrue\n/etc/openclash/custom/codex_phone_routing.sh\nCFG=$(uci -q get openclash.config.config_path)\nruby /etc/phone-dns/align-dns.rb \"/etc/openclash/${CFG##*/}\" live || logger -t phone-dns \"Auto-alignment failed; inspect configuration\"\nexit 0\n"}
 original.each{|name,text|File.binwrite(base+'/'+name,text)}
 Dir.mkdir(root+'/root',0700)
 invoke=lambda do
  output=IO.popen([RbConfig.ruby,script,'install',root,{err:[:child,:out]}],&:read)
  [$?.success?,output]
 end
 ok,output=invoke.call;assert(ok,'known legacy hooks must migrate: '+output)
 first=original.to_h do |name,_|
  text=File.read(base+'/'+name)
  assert(text.scan('# BEGIN PHONE-PANEL MANAGED HOOK').size==1)
  assert(text.include?('retain administrator')&&text.include?("true\n"),'unrelated custom code must survive')
  assert(text.index('# END PHONE-PANEL MANAGED HOOK')<text.index('exit 0'),'managed hook must remain reachable')
  [name,text]
 end
 assert(!first['openclash_custom_firewall_rules.sh'].include?('codex_phone_routing.sh'))
 assert(invoke.call.first,'managed hook installation must be idempotent')
 first.each{|name,text|assert(File.read(base+'/'+name)==text)}
 unknown=original['openclash_custom_overwrite.sh'].sub('align-dns.rb','unknown-custom.rb')
 File.binwrite(base+'/openclash_custom_overwrite.sh',unknown)
 before=original.keys.to_h{|name|[name,File.binread(base+'/'+name)]}
 assert(!invoke.call.first,'unknown legacy integrations must not be guessed')
 before.each{|name,text|assert(File.binread(base+'/'+name)==text,'failed detection must not modify either hook')}
end
puts 'OpenClash hooks: exact early-install migration, custom-code preservation, reachable/idempotent blocks and unknown-integration rejection PASS'
