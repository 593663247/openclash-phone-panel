const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const html=fs.readFileSync(path.join(__dirname,'../router/luci/view/phone_panel.htm'),'utf8').replace(/<%[\s\S]*?%>/g,'');
const source=fs.readFileSync(path.join(__dirname,'../router/luci/resources/features.js'),'utf8');
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const settle=()=>new Promise(resolve=>setImmediate(resolve));

async function run(){
 const dom=new JSDOM(html,{runScripts:'outside-only',url:'https://router.invalid/'}),w=dom.window,d=w.document;
 w.confirm=()=>true;w.eval(source);
 d.getElementById('pp').className='maintenance-page';
 const good={at:100,dns_ok:true,exit_ok:true,exit_ip:'203.0.113.1',dns_ms:12,exit_ms:45,category:'ok',checks:[{layer:'DNS',ok:true}]};
 const groups=[{id:1,node:'手机-01-纽约',region:'美国',dns_listening:true,socks_listening:true,binding_ok:true,
  phones:[{ip:'192.168.1.101',mac:'02:11:22:33:44:55',hostname:'<img src=x onerror=alert(1)>',online_state:'active',online_evidence:'connection',last_seen:100,traffic:{available:true,rate_up:1234,rate_down:4321,today:{up:1,down:2},month:{up:10,down:20}}}],
  health:{exit_changed:true,baseline_ip:'203.0.113.1',exit_ip:'203.0.113.2',checks:2,failures:0,success_percent:100,history:[good],last:good}},
 {id:2,node:'手机-02-法国',region:'法国',dns_listening:false,socks_listening:true,binding_ok:true,phones:[{ip:'192.168.1.102',hostname:'Second',online_state:'unknown',traffic:{}}],health:{checks:0}}];
 const calls=[],jobs=[];let candidatePreviewResolve,delayBulk=false,ci=false;
 const current='a'.repeat(40),latest='b'.repeat(40);
 const versions={current,releases:[{id:'20261030120000-abcdef123456',status:'installed',from:current,at:100}],update:{can_upgrade:false}};
 const api={esc,groups:()=>groups,busy:()=>false,refresh:async()=>{},watchJob:id=>jobs.push(id),
  get:async route=>{
   if(route==='versions')return versions;
   if(route==='candidates')return {devices:[{ip:'192.168.1.103',mac:'02:11:22:33:44:77',name:'New device'}]};
   if(route.startsWith('probe?'))return good;
   if(route.startsWith('health?'))return {node:groups[0].node,health:{checks:2,failures:1,history:[good,{...good,at:200,dns_ok:false}],last:good}};
   throw Error('Unexpected GET '+route);
  },
  post:async(route,payload)=>{
   calls.push({route,payload});
   if(route==='bulk_preview'){
    const result={plan:{devices:payload.devices.map(x=>({...x,node:groups[0].node})),revision:'revision',warning:'Review'}};
    if(delayBulk)return new Promise(resolve=>candidatePreviewResolve=()=>resolve(result));
    return result;
   }
   if(route==='bulk_apply')return {job:'20261030120000-123456abcdef'};
   if(route==='check_update')return {current,latest,can_upgrade:ci,message:ci?'Ready':'CI pending'};
   if(route==='upgrade'||route==='restore_release')return {id:'20261030120000-abcdef123456'};
   if(route==='ack')return {ok:true};
   throw Error('Unexpected POST '+route);
  }};
 d.getElementById('pp-grid').innerHTML=groups.map(g=>'<section class="card" data-group="'+g.id+'"><div class="body"></div></section>').join('');
 const ui=w.PhonePanelFeatures.attach(api);await settle();
 ui.update({groups,monitor:{fresh:true,sample_at:100,counter_available:true}});
 assert.equal(d.querySelectorAll('#pf-device-rows tr').length,2);
 assert.equal(d.querySelector('#pf-device-rows img'),null,'device names must be escaped');
 assert.equal(d.querySelectorAll('.pf-health').length,2,'cards must expose diagnostics/history');
 d.getElementById('pf-region').value='法国';d.getElementById('pf-region').onchange();
 assert.equal(d.querySelector('[data-group="1"]').hidden,true);
 assert.equal(d.querySelectorAll('#pf-device-rows tr').length,1);
 d.getElementById('pf-filter-reset').onclick();
 d.getElementById('pf-search').value='02:11:22:33:44:55';d.getElementById('pf-search').oninput();
 assert.equal(d.querySelector('[data-group="2"]').hidden,true,'MAC search must filter cards and table');
 ui.update({groups,monitor:{fresh:true,sample_at:115}});
 assert.equal(d.getElementById('pf-search').value,'02:11:22:33:44:55','refresh preserves filters');
 d.getElementById('pf-filter-reset').onclick();
 await d.querySelector('[data-ack]').onclick();
 assert.equal(calls.at(-1).route,'ack');assert.equal(calls.at(-1).payload.exit_ip,'203.0.113.2');
 await d.querySelector('[data-diagnose]').onclick();
 assert.equal(d.getElementById('pf-diagnostic').hidden,false);
 assert.equal(d.querySelectorAll('#pf-diagnostic-body tbody tr').length,2);
 await d.getElementById('pf-bulk-load').onclick();
 const checkbox=d.querySelector('#pf-candidates input[type=checkbox]');checkbox.checked=true;
 delayBulk=true;const stale=d.getElementById('pf-bulk-preview').onclick();
 const name=d.querySelector('#pf-candidates [data-name]');name.value='Edited';name.dispatchEvent(new w.Event('input',{bubbles:true}));
 candidatePreviewResolve();await stale;
 assert.equal(d.getElementById('pf-bulk-apply').hidden,true,'stale bulk plan must not enable application');
 delayBulk=false;await d.getElementById('pf-bulk-preview').onclick();
 assert.equal(d.getElementById('pf-bulk-apply').hidden,false);
 await d.getElementById('pf-bulk-apply').onclick();
 assert.deepEqual(jobs,['20261030120000-123456abcdef']);
 await d.getElementById('pf-update-check').onclick();assert.equal(d.getElementById('pf-upgrade').disabled,true,'CI failure must block upgrade');
 ci=true;await d.getElementById('pf-update-check').onclick();assert.equal(d.getElementById('pf-upgrade').disabled,false);
 d.getElementById('pf-upgrade').onclick();await settle();
 assert.equal(calls.at(-1).route,'upgrade');assert.equal(calls.at(-1).payload.target,latest);
 assert.equal(calls.at(-1).payload.confirm,'UPGRADE');
 await d.getElementById('pf-version-refresh').onclick();
 d.getElementById('pf-restore').onclick();await settle();
 assert.equal(calls.at(-1).route,'restore_release');assert.equal(calls.at(-1).payload.confirm,'RESTORE_CODE');
 dom.window.close();
 console.log('PASS: real DOM filters, escaping, alerts, diagnostics, stale bulk plans and update/restore confirmations');
}
run().catch(error=>{console.error(error);process.exitCode=1});
