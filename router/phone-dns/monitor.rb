require_relative 'status-lib'

module PhoneMonitor
 def self.sample(state,now=Time.now.to_i)
  status=PhoneStatus.collect
  raise 'Router status unavailable' if status['error']
  phones=status['groups'].flat_map{|g|g['phones']}
  ips=phones.map{|p|p['ip']}.uniq.sort
  signature=[PhoneSettings['bridge'],ips]
  counters=PhoneCounters.read
  if @signature!=signature || counters.nil?
   PhoneCounters.sync(ips);@signature=signature;counters=PhoneCounters.read
  end
  boot=File.read('/proc/sys/kernel/random/boot_id').strip
  state=PhoneTelemetry.tick(state,phones,counters,now,boot)
  PanelStore.write(PanelStore.ram+'/metrics.yaml',state)
  [state,status]
 end
 def self.run(once=false)
  PanelStore.with_lock(PanelStore.path('/var/lock/phone-panel-monitor.lock'),true) do
   state=PanelStore.read(PanelStore.ram+'/metrics.yaml',{})
   state=PanelStore.read(PanelStore.state+'/traffic.yaml',{}) if state.empty?
   stopping=false;Signal.trap('TERM'){stopping=true};Signal.trap('INT'){stopping=true}
   checkpoint=0
   until stopping
    begin
     PhoneSettings.instance_variable_set(:@values,nil)
     if PhoneSettings['monitor_enabled']=='1'
      @disabled=false
      state,status=sample(state)
      if Time.now.to_i-checkpoint>=300
       PanelStore.write(PanelStore.state+'/traffic.yaml',state);checkpoint=Time.now.to_i
      end
      # One due group per sampling cycle, never a parallel probe storm.
      due=status['groups'].min_by{|g|PhoneHealth.read(g).dig('last','at').to_i}
      if due && Time.now.to_i-PhoneHealth.read(due).dig('last','at').to_i>=PhoneSettings.port('probe_interval')
       PhoneProbe.run(due)
      end
     elsif !@disabled
      PanelStore.capture('nft','delete','table','inet',PhoneCounters::TABLE)
      @signature=nil;@disabled=true
     end
    rescue =>e
     # Do not log raw command output, source configuration or credentials.
     warn "Phone monitor sample unavailable (#{e.class})"
    end
    break if once
    PhoneSettings.port('sample_interval').times{break if stopping;sleep 1}
   end
   PanelStore.write(PanelStore.state+'/traffic.yaml',state) unless state.empty?
  end
 end
end
PhoneMonitor.run(ARGV.include?('--once')) if $0==__FILE__
