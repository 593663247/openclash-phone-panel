require_relative '../router/phone-dns/tasks'
raise unless PanelTasks::ACTIONS.keys.sort==%w[backup dependencies doctor initialize repair_hooks].sort
raise unless PanelTasks::ACTIONS.values.all?{|a|a.is_a?(Array) && a.all?{|v|v.is_a?(String)}}
raise unless YAML.safe_load(PanelTasks.json({'test'=>"quote\"\nback\\",'array'=>[true,false,nil,3]}))=={'test'=>"quote\"\nback\\",'array'=>[true,false,nil,3]}
puts 'Task allow-list and JSON serialization PASS (no router writes)'
