require_relative 'alignment'
begin
 result=PhoneAlignment.run(ARGV.fetch(0),live:ARGV[1]=='live')
 puts "Aligned #{result['count']} devices"
rescue=>e
 warn "Configuration merge stopped; independent protection retained: #{e.message}"
 exit 1
end
