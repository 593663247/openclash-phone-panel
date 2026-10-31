require_relative 'panel-store'
module PhoneNodeRegistry
 def self.path;PanelStore.path('/etc/phone-dns/managed-nodes.yaml');end
 def self.read;PanelStore.read(path,[]);end
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
