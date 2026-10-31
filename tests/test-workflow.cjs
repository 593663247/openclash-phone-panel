const assert=require('node:assert/strict'),fs=require('node:fs'),{JSDOM}=require('jsdom');
(async()=>{
 const dom=new JSDOM(fs.readFileSync('router/luci/view/phone_panel.htm','utf8').replace(/<%[\s\S]*?%>/g,''),{runScripts:'outside-only',url:'https://router.invalid'}),w=dom.window,d=w.document,$=id=>d.getElementById(id);w.setInterval=()=>{};w.confirm=()=>true;
 w.eval(fs.readFileSync('router/luci/resources/workflow.js','utf8'));
 let records=[],refreshes=0;const api={esc:s=>String(s??'').replace(/[&<>"']/g,'_'),get:async()=>({operations:records}),refresh:async()=>{refreshes++},post:async()=>({operation_id:'example'})};
 const flow=w.PhonePanelWorkflow.attach(api);await new Promise(r=>setImmediate(r));
 flow.update({groups:[{id:1,node:'手机-01-示例',health:{exit_ip:'192.0.2.10'},phones:[{ip:'192.168.1.113',hostname:'device',mac:'02:11:22:33:44:55',lease_current_ip:'192.168.1.193'}]}]});
 $('edit-device').value='192.168.1.113';$('edit-device').onchange();assert.equal($('edit-ip').value,'192.168.1.113');assert.equal($('edit-name').value,'device');assert.match($('edit-device-info').textContent,/等待重连 Wi-Fi/);assert.match($('edit-device-info').textContent,/192\.0\.2\.10/);
 records=[{id:'test',action:'device_edit',status:'running',stage:'验证配置'}];await flow.poll();assert(flow.busy());assert.match($('operation-list').textContent,/验证配置/);
 w.sessionStorage.setItem('phone-panel-current-operation','test');records=[{id:'test',action:'device_edit',status:'done',stage:'完成',message:'success'}];await flow.poll();assert(!flow.busy());assert.equal(refreshes,1);assert.equal(w.sessionStorage.getItem('phone-panel-current-operation'),null);
 records=[{id:'other',action:'device_edit',status:'interrupted',recovery_required:true,stage:'执行中断',message:'inspect backups'}];await flow.poll();assert.match($('operation-list').textContent,/不会自动重试/);
 dom.window.close();console.log('PASS: device selection/autofill, fixed/leased/exit IP distinction, persistent task status and interruption notices');
})().catch(e=>{console.error(e);process.exit(1)});
