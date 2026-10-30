require 'yaml'
# Optional root argument is solely for offline image preparation/testing.
root=ARGV[1] || ''
raise 'Root must be absolute' unless root.empty? || root.start_with?('/')
mode=ARGV[0] || 'install';raise 'install or remove required' unless %w[install remove].include?(mode)
start='# BEGIN PHONE-PANEL MANAGED HOOK';finish='# END PHONE-PANEL MANAGED HOOK'
blocks={
'openclash_custom_overwrite.sh'=>"ruby /etc/phone-dns/align-dns.rb \"$1\" || exit 1\nruby /etc/phone-dns/add-listeners.rb \"$1\" || exit 1\n",
'openclash_custom_firewall_rules.sh'=>"/etc/openclash/custom/phone-routing.sh || exit 1\nCFG=$(uci -q get openclash.config.config_path)\nruby /etc/phone-dns/align-dns.rb \"/etc/openclash/${CFG##*/}\" live || exit 1\n"}
base=root+'/etc/openclash/custom';raise 'OpenClash custom directory missing' unless Dir.exist?(base)
original={};updates={}
blocks.each do |name,body|
 path=base+'/'+name;old=File.exist?(path) ? File.read(path) : nil;original[path]=old
 text=old || "#!/bin/sh\nexit 0\n"
 raise 'Unbalanced hook markers; repair manually' unless text.scan(start).size==text.scan(finish).size && text.scan(start).size<=1
 text=text.sub(/#{Regexp.escape(start)}\n.*?#{Regexp.escape(finish)}\n?/m,'')
 if mode=='install'
  # Existing legacy hooks cannot safely be guessed or replaced.
  raise 'Unmarked legacy phone-panel integration found; migrate manually' if text.include?('/etc/phone-dns/') || text.include?('phone-routing.sh') || text.include?('codex_phone_routing.sh')
  block=start+"\n"+body+finish+"\n"
  index=text.index(/^\s*exit\s+0\s*$/)
  text=index ? text[0...index]+block+text[index..-1] : text+"\n"+block
 end
 updates[path]=text
end
backup=root+'/root/phone-panel-hook-backups';Dir.mkdir(backup,0700) unless Dir.exist?(backup)
id=Time.now.strftime('%Y%m%d%H%M%S')+'-'+Process.pid.to_s
record={}
begin
 updates.each do |path,text|
  record[path]={'present'=>!original[path].nil?,'content'=>original[path]}
  tmp=path+'.phone-panel-tmp';File.write(tmp,text);File.chmod(0700,tmp)
  raise 'Shell syntax check failed' unless system('sh','-n',tmp)
 end
 File.open(backup+'/'+id+'.yaml','w',0600){|f|f.write(record.to_yaml)}
 updates.each{|path,text|File.rename(path+'.phone-panel-tmp',path)}
 puts "Hook #{mode} complete; private backup: #{backup}/#{id}.yaml"
rescue
 original.each{|path,text|text ? File.write(path,text) : (File.delete(path) if File.exist?(path))}
 raise
ensure
 updates.each_key{|path|File.delete(path+'.phone-panel-tmp') if File.exist?(path+'.phone-panel-tmp')}
end
