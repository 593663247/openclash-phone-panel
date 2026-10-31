require_relative 'support'
require_relative '../router/phone-dns/panel-store'
require 'rbconfig'
binary=ARGV.fetch(0)
fixture_directory do |root|
 settings=root+'/settings.yaml';File.binwrite(settings,'{}')
 PhoneSettings.instance_variable_set(:@values,PhoneSettings.validate({}))
 [[],[PhoneSettings.group(1,'手机-01-示例',['192.168.1.101'])],[PhoneSettings.group(7,'手机-07-示例',['192.168.1.107']),PhoneSettings.group(9,'手机-09-示例')]].each do |mapping|
  ENV['PHONE_PANEL_TEST']='1';ENV['PHONE_PANEL_TEST_ROOT']=root;ENV['PHONE_PANEL_TEST_CONFIG']=settings
  PanelStore.write(PanelStore.path('/etc/phone-dns/mapping.yaml'),mapping)
  assert(system(RbConfig.ruby,File.expand_path('../router/phone-dns/render-dns.rb',__dir__)),'production renderer failed')
  assert(system(binary,'check','-c',PanelStore.path('/etc/phone-dns/config.json')),'generated DNS config rejected by real sing-box')
 end
end
puts 'PASS: real sing-box checks for empty, active and mixed empty/active DNS groups'
