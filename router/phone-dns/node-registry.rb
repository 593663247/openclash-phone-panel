require_relative 'panel-store'
module PhoneNodeRegistry
 def self.path;PanelStore.path('/etc/phone-dns/managed-nodes.yaml');end
 def self.read
  return [] unless File.exist?(path)
  raise '面板节点库不安全或体积异常' if File.symlink?(path) || !File.file?(path) || File.size(path)>2*1024*1024
  nodes=YAML.safe_load(File.binread(path),aliases:false)
  raise '面板节点库格式无效' unless nodes.is_a?(Array)&&nodes.all?{|n|n.is_a?(Hash)&&n['name'].is_a?(String)&&n['type']=='socks5'}&&nodes.map{|n|n['name']}.uniq.size==nodes.size
  raise '面板节点参数损坏，请从备份恢复' unless nodes.all?{|n|n['server'].is_a?(String)&&n['server'].bytesize.between?(1,253)&&!n['server'].match?(/[\x00-\x20\x7f]/)&&n['port'].is_a?(Integer)&&n['port'].between?(1,65535)}
  nodes
 rescue Psych::Exception
  raise '面板节点库损坏，已停止合并；请从备份恢复'
 end
 def self.merge(cfg,registry=read)
  nodes=cfg['proxies']||=[]
  registry.each do |node|
   current=nodes.find{|n|n['name']==node['name']}
   raise "托管节点 #{node['name']} 与当前配置同名但参数不同，请先解决冲突" if current && !node.all?{|k,v|current[k]==v}
   nodes<<Marshal.load(Marshal.dump(node)) unless current
  end
  cfg
 end
 def self.write(nodes);PanelStore.write(path,nodes);end
 def self.redact(node)
  node.reject{|k,_|%w[username password].include?(k)}.merge('has_credentials'=>node.key?('password'))
 end
end
