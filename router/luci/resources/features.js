(function(root){'use strict';
const onlineText={active:'有连接／可达',recent:'近期可达',offline:'探测未达',unknown:'未确认'};
const categories={ok:'链路检测通过',socks_not_listening:'本地 SOCKS 入口未监听',binding_mismatch:'节点绑定配置不一致',timeout:'连接超时',proxy_or_auth_failed:'代理／SOCKS 协商失败，可能涉及认证或上游',tls_failed:'HTTPS 证书验证失败',egress_failed:'HTTPS 出口失败',dns_failed:'DNS 解析失败'};
function bytes(value){if(value==null)return '—';let n=Number(value)||0;const units=['B','KiB','MiB','GiB','TiB'];let i=0;while(n>=1024&&i<4){n/=1024;i++}return n.toFixed(i?1:0)+' '+units[i]}
function date(value){return value?new Date(value*1000).toLocaleString():'尚未观察到'}
function ready(g){return !!(g.dns_listening&&g.socks_listening&&g.binding_ok)}
function failed(g){return !ready(g)||!!(g.health&&g.health.last&&(!g.health.last.dns_ok||!g.health.last.exit_ok))}
function matchGroup(g,filters){
 if(filters.group&&String(g.id)!==filters.group)return false;
 if(filters.region&&g.region!==filters.region)return false;
 if(filters.online&&!(g.phones||[]).some(p=>(p.online_state||'unknown')===filters.online))return false;
 if(filters.health==='failed'&&!failed(g))return false;
 if(filters.health==='changed'&&!(g.health&&g.health.exit_changed))return false;
 if(filters.health==='abnormal'&&!failed(g)&&!(g.health&&g.health.exit_changed)&&!(g.phones||[]).some(p=>p.traffic&&p.traffic.alert))return false;
 const haystack=[g.node,g.region,...(g.phones||[]).flatMap(p=>[p.hostname,p.ip,p.mac])].join(' ').toLowerCase();
 return !filters.search||haystack.includes(filters.search.toLowerCase());
}
function attach(api){
 const $=id=>document.getElementById(id),esc=api.esc;
 let snapshot=null,bulkPlan=null,bulkRevision=0,candidates=[],versionData=null,versionBusy=false;
 const seenTasks=new Set();
 function text(id,value){$(id).textContent=value}
 function filters(){return {search:$('pf-search').value.trim(),group:$('pf-group').value,region:$('pf-region').value,online:$('pf-online').value,health:$('pf-health').value}}
 function options(element,values,first){const selected=element.value;element.innerHTML='<option value="">'+first+'</option>'+values.map(([value,label])=>'<option value="'+esc(value)+'">'+esc(label)+'</option>').join('');element.value=values.some(([v])=>String(v)===selected)?selected:''}
 function message(id,error){text(id,error&&error.message?error.message:String(error))}
 function table(){
  if(!snapshot)return;
  const f=filters(),rows=[];
  for(const g of snapshot.groups){
   if(!matchGroup(g,f))continue;
   for(const p of g.phones||[]){
    if(f.online&&(p.online_state||'unknown')!==f.online)continue;
    if(f.search&&![p.hostname,p.ip,p.mac,g.node,g.region].join(' ').toLowerCase().includes(f.search.toLowerCase()))continue;
    const t=p.traffic||{},today=t.today||{},month=t.month||{};
    const todayText=t.today_available===false?'尚未累计':bytes((today.up||0)+(today.down||0)),monthText=t.month_available===false?'尚未累计':bytes((month.up||0)+(month.down||0));
    const h=g.health||{},last=h.last;
    rows.push('<tr'+(t.alert?' class="pf-attention"':'')+'><td data-label="设备"><strong>'+esc(p.hostname||'未命名')+'</strong></td><td data-label="固定 IP">'+esc(p.ip)+(p.lease_current_ip&&p.lease_current_ip!==p.ip?'<small class="pf-danger">当前 '+esc(p.lease_current_ip)+' · 等待重连</small>':'')+'</td><td data-label="在线状态"><span class="pf-state pf-'+esc(p.online_state||'unknown')+'" title="'+esc(p.online_evidence||'')+'">'+esc(onlineText[p.online_state]||onlineText.unknown)+'</span></td><td data-label="绑定节点">'+esc(g.node)+'<small>'+esc(g.region||'未分类')+(!ready(g)?' · 入口待检查':'')+'</small></td><td data-label="最近公网出口">'+esc(h.exit_ip||'未检测')+'<small>'+esc(last?date(last.at):'尚无检测时间')+(last&&(!last.dns_ok||!last.exit_ok)?' · 最近检测未通过':'')+'</small></td><td data-label="详细信息"><details><summary>流量与观察</summary><small>MAC：'+esc(p.mac||'未记录')+'<br>最近观察：'+esc(date(p.last_seen))+'<br>在线依据：'+esc(p.online_evidence||'未确认')+'<br>实时 ↑ / ↓：'+esc(t.available?bytes(t.rate_up)+' / '+bytes(t.rate_down):'采样未就绪')+'<br>今日：'+esc(todayText)+' · 本月：'+esc(monthText)+(t.alert?'<br>达到流量或速率提醒阈值':'')+'</small></details></td></tr>');
   }
  }
  $('pf-device-rows').innerHTML=rows.join('')||'<tr><td colspan="6">没有符合条件的设备。</td></tr>';
  text('pf-result-count',rows.length+' 台设备');
 }
 function applyFilters(){
  if(!snapshot)return;
  const f=filters(),extra=[f.region,f.online,f.health].filter(Boolean).length;text('pf-filter-summary','更多筛选'+(extra?'（'+extra+'项）':''));
  document.querySelectorAll('#pp-grid [data-group]').forEach(card=>{const g=snapshot.groups.find(g=>String(g.id)===card.dataset.group);card.hidden=!g||!matchGroup(g,f)});
  table();
 }
 function decorateCards(){
  if(!snapshot)return;
  document.querySelectorAll('#pp-grid [data-group]').forEach(card=>{
   const g=snapshot.groups.find(g=>String(g.id)===card.dataset.group);if(!g)return;
   const old=card.querySelector('.pf-health');if(old)old.remove();
   const h=g.health||{},last=h.last,block=document.createElement('details');block.className='pf-health';
   block.innerHTML='<summary>健康记录与诊断</summary><div class="pf-health-top"><span>'+esc(g.region||'未分类')+' · '+esc(h.checks?String(h.success_percent)+'% 最近检测通过':'等待首次检测')+'</span><button type="button" data-diagnose="'+esc(g.id)+'">诊断与记录</button></div>'+
    '<div class="pf-spark" role="img" aria-label="最近链路检测结果">'+(h.history||[]).slice(-24).map(r=>'<span class="'+(r.dns_ok&&r.exit_ok?'pf-good':'pf-bad')+'" title="'+esc(date(r.at)+' · DNS '+r.dns_ms+'ms / 出口 '+r.exit_ms+'ms')+'"></span>').join('')+'</div>'+
    '<small>'+esc(last?date(last.at)+' · '+(categories[last.category]||'检测结果待确认'):'后台监测启动后会分批检测，不自动切换节点。')+'</small>'+
    (h.exit_ip?'<div class="'+(h.exit_changed?'pf-danger':'')+'">出口 '+esc(h.exit_ip)+(h.exit_changed?' · 与确认基线不同':'')+'</div>':'');
   const ttl=Math.max(900,Number(snapshot.settings&&snapshot.settings.probe_interval||900)*2);
   if(!last||Date.now()/1000-last.at>ttl){const note=document.createElement('span');note.className='stale-note';note.textContent=last?'检测结果已过期，请重新检测；历史成功不代表当前可用':'尚未实测，请点击检测';block.appendChild(note);card.classList.add('pf-stale');const main=card.querySelector('.probe');if(main)main.classList.remove('ok')}else card.classList.remove('pf-stale');
   block.querySelector('button').onclick=()=>diagnose(g.id);
   card.querySelector('.body').appendChild(block);
  });
 }
 function alerts(){
  const changed=snapshot.groups.filter(g=>g.health&&g.health.exit_changed);
  $('pf-alerts').hidden=!changed.length;
  $('pf-alerts').innerHTML=changed.length?'<h3>出口 IP 变化提醒</h3>'+changed.map(g=>'<div class="pf-alert-row"><div><strong>'+esc(g.node)+'</strong><br>'+esc(g.health.baseline_ip||'—')+' → '+esc(g.health.exit_ip||'—')+'<small>仅提醒，不切换节点；确认后以当前出口为基线。</small></div><button type="button" data-ack="'+esc(g.id)+'">确认当前出口</button></div>').join(''):'';
  $('pf-alerts').querySelectorAll('[data-ack]').forEach(button=>button.onclick=async()=>{
   const g=snapshot.groups.find(g=>String(g.id)===button.dataset.ack);button.disabled=true;
   try{await api.post('ack',{group:g.id,exit_ip:g.health.exit_ip});await api.refresh()}catch(e){message('pf-notice',e)}finally{button.disabled=false}
  });
 }
 function update(data){
  const previous=snapshot&&JSON.stringify(snapshot.groups.map(g=>[g.id,g.node]));snapshot=data;
  const catalog=JSON.stringify(data.groups.map(g=>[g.id,g.node]));
  options($('pf-group'),data.groups.map(g=>[String(g.id),g.node]),'全部节点');
  options($('pf-region'),[...new Set(data.groups.map(g=>g.region||'未分类'))].sort().map(x=>[x,x]),'全部地区标签');
  if(previous&&previous!==catalog){
   invalidateBulk();
   $('pf-candidates').querySelectorAll('select').forEach(select=>{
    const selected=select.value;
    select.innerHTML='<option value="">请选择节点</option>'+data.groups.map(g=>'<option value="'+esc(g.id)+'">'+esc(g.node)+'</option>').join('');
    select.value=data.groups.some(g=>String(g.id)===selected)?selected:'';
   });
  }
  const phones=data.groups.flatMap(g=>g.phones||[]),online=phones.filter(p=>['active','recent'].includes(p.online_state));
  text('pf-online-count',online.length+' / '+phones.length);
  text('pf-exit-count',data.groups.filter(g=>g.health&&g.health.exit_changed).length);
  const rates=phones.filter(p=>p.traffic&&p.traffic.available&&Number.isFinite(p.traffic.rate_up)&&Number.isFinite(p.traffic.rate_down));
  text('pf-rate',rates.length?bytes(rates.reduce((n,p)=>n+(p.traffic.rate_up||0),0))+' / '+bytes(rates.reduce((n,p)=>n+(p.traffic.rate_down||0),0)):'采样未就绪');
  text('pf-sample',data.monitor&&data.monitor.enabled===false?'已关闭':data.monitor&&data.monitor.fresh?'采样正常':'尚未就绪');text('pf-sample-at',data.monitor&&data.monitor.sample_at?'最近 '+date(data.monitor.sample_at):'等待后台采样');
  text('pf-traffic-note',(data.monitor&&data.monitor.note||'流量从启用监测开始累计，不回填历史数据。')+' 按路由器日期统计，约每 5 分钟保存累计数据。');
  alerts();decorateCards();applyFilters();
 }
 async function diagnose(id){
  $('pf-diagnostic').hidden=false;text('pf-diagnostic-title','正在逐层诊断…');text('pf-diagnostic-body','正在检测入口、DNS 和 HTTPS 出口，请稍候。');
  try{
   const result=await api.get('probe?id='+encodeURIComponent(id));
   const history=await api.get('health?id='+encodeURIComponent(id)),health=history.health||{};
   text('pf-diagnostic-title',history.node+' · 故障诊断与健康记录');
   const last=result.checks?result:health.last||{};
   $('pf-diagnostic-body').innerHTML=(result.busy?'<p>已有检测正在执行，下方展示最近记录。</p>':'')+'<p>'+esc(categories[last.category]||'暂无检测记录')+' · '+esc(date(last.at))+'</p>'+
    '<div class="pf-checks">'+(last.checks||[]).map(c=>'<div><span class="pf-state '+(c.ok===true?'pf-active':c.ok===false?'pf-offline':'pf-unknown')+'">'+(c.ok===true?'通过':c.ok===false?'失败':'未验证')+'</span> '+esc(c.layer)+(c.ms!=null?' · '+esc(c.ms)+' ms':'')+(c.note?'<small>'+esc(c.note)+'</small>':'')+'</div>').join('')+'</div>'+
    '<p>最近 '+esc(health.checks||0)+' 次检测，失败 '+esc(health.failures||0)+' 次。通过率仅针对 DNS 与 HTTPS 出口。</p><div class="pf-scroll"><table><thead><tr><th>时间</th><th>DNS</th><th>出口</th><th>耗时 DNS / 出口</th><th>分类</th></tr></thead><tbody>'+
    (health.history||[]).slice().reverse().map(r=>'<tr><td>'+esc(date(r.at))+'</td><td>'+esc(r.dns_ok?'通过':'失败')+'</td><td>'+esc(r.exit_ip||'失败')+'</td><td>'+esc(r.dns_ms)+' / '+esc(r.exit_ms)+' ms</td><td>'+esc(categories[r.category]||r.category)+'</td></tr>').join('')+'</tbody></table></div>';
   await api.refresh();
  }catch(e){message('pf-diagnostic-body',e)}
 }
 function invalidateBulk(){bulkRevision++;bulkPlan=null;$('pf-bulk-apply').hidden=true}
 function chosen(){return [...$('pf-candidates').querySelectorAll('[data-candidate]')].filter(row=>row.querySelector('input[type=checkbox]').checked).map(row=>{
  const source=candidates[Number(row.dataset.candidate)];return {ip:source.ip,mac:source.mac,name:row.querySelector('[data-name]').value,group:row.querySelector('select').value};
 })}
 $('pf-bulk-load').onclick=async function(){
  invalidateBulk();this.disabled=true;message('pf-bulk-result','正在读取未纳管 DHCP 租约…');
  try{
   const data=await api.get('candidates');candidates=data.devices||[];
   const groups=api.groups();
   $('pf-candidates').innerHTML=candidates.map((d,index)=>'<tr data-candidate="'+index+'"><td><input type="checkbox" aria-label="选择 '+esc(d.ip)+'" '+(d.conflict?'disabled':'')+'></td><td><input data-name maxlength="40" value="'+esc(d.name)+'" aria-label="设备名称"></td><td>'+esc(d.ip)+'<small>'+esc(d.mac)+'</small></td><td><select aria-label="绑定节点">'+groups.map(g=>'<option value="'+esc(g.id)+'">'+esc(g.node)+'</option>').join('')+'</select>'+(d.conflict?'<small class="pf-danger">'+esc(d.conflict)+'</small>':'')+'</td></tr>').join('')||'<tr><td colspan="4">当前没有可供选择的未纳管有效 DHCP 租约。</td></tr>';
   message('pf-bulk-result','选择 1～32 台设备并分配节点，再统一预览。未发现租约不代表 IP 空闲。');
  }catch(e){message('pf-bulk-result',e)}finally{this.disabled=false}
 };
 $('pf-bulk').oninput=invalidateBulk;$('pf-bulk').onchange=invalidateBulk;
 $('pf-bulk-preview').onclick=async function(){
  if(api.busy())return;invalidateBulk();const revision=bulkRevision,devices=chosen();this.disabled=true;
  try{const data=await api.post('bulk_preview',{devices});if(revision!==bulkRevision)return;bulkPlan=data.plan;message('pf-bulk-result',bulkPlan.devices.map(d=>d.name+' | '+d.ip+' | '+d.mac+' → '+d.node).join('\n')+'\n'+bulkPlan.warning);$('pf-bulk-apply').hidden=false}
  catch(e){if(revision===bulkRevision)message('pf-bulk-result',e)}finally{this.disabled=false}
 };
 $('pf-bulk-apply').onclick=async function(){
  if(!bulkPlan||api.busy()||!root.confirm('确认整批添加？将统一备份和校验，并短暂重启代理一次。'))return;
  this.disabled=true;
  try{const data=await api.post('bulk_apply',bulkPlan);invalidateBulk();if(data.job)api.watchJob(data.job);message('pf-bulk-result',data.message||'已提交，请查看统一任务中心')}
  catch(e){message('pf-bulk-result',e)}finally{this.disabled=false}
 };
 function paintVersions(){
  if(!versionData)return;
  const data=versionData,up=data.update||{};
  text('pf-version',data.version?'v'+data.version:'版本未设置');text('pf-version-source','源码标记：'+(data.current?data.current.slice(0,12):'未设置'));
  text('pf-update-message',up.message||'点击检查 GitHub 更新；不会自动安装或改动网络。');
  $('pf-upgrade').disabled=versionBusy||!up.can_upgrade;
  const pre=up.preflight; $('upgrade-preflight').innerHTML=pre?'<p>升级预检查 · '+esc(date(pre.at))+'</p>'+pre.checks.map(c=>'<span class="console-check '+(c.ok?'':'bad')+'">'+esc((c.ok?'✓ ':'! ')+c.name+' · '+c.detail)+'</span>').join(''):'';
  $('pf-restore').disabled=versionBusy||!(data.releases||[]).some(r=>r.status==='installed'&&/^[a-f0-9]{40}$/.test(r.from||''));
  const selected=$('pf-release').value;
  $('pf-release').innerHTML=(data.releases||[]).filter(r=>r.status==='installed'&&/^[a-f0-9]{40}$/.test(r.from||'')).map(r=>'<option value="'+esc(r.id)+'">'+esc(date(r.at)+' → '+r.from.slice(0,12))+'</option>').join('');
  if([...$('pf-release').options].some(o=>o.value===selected))$('pf-release').value=selected;
 }
 async function versions(){try{versionData=await api.get('versions');paintVersions()}catch(e){message('pf-update-message',e)}}
 $('pf-update-check').onclick=async function(){
  if(versionBusy)return;versionBusy=true;this.disabled=true;paintVersions();text('pf-update-message','正在核对固定仓库 main、可快进关系与 CI…');
  try{const data=await api.post('check_update',{});versionData={...(versionData||{}),current:data.current,update:data};paintVersions()}
  catch(e){versionData={...(versionData||{}),update:{can_upgrade:false,message:e.message}};message('pf-update-message',e)}finally{versionBusy=false;this.disabled=false;paintVersions()}
 };
 async function releaseTask(action,payload,warning){
  if(versionBusy||api.busy()||!root.confirm(warning))return;versionBusy=true;paintVersions();
  try{const data=await api.post(action,payload);text('pf-update-message','任务 '+data.id+' 已提交；请在维护任务记录查看结果。升级前自动备份，失败会尝试恢复原程序。')}
  catch(e){message('pf-update-message',e)}finally{versionBusy=false;$('pf-upgrade').disabled=true;$('pf-restore').disabled=true}
 }
 $('pf-upgrade').onclick=()=>{const up=versionData&&versionData.update;if(up&&up.can_upgrade)releaseTask('upgrade',{target:up.latest,confirm:'UPGRADE'},'确认升级到 '+up.latest.slice(0,12)+'？将先备份，再更新程序和监测服务，保留现有设备与节点配置。')};
 $('pf-restore').onclick=()=>releaseTask('restore_release',{release:$('pf-release').value,confirm:'RESTORE_CODE'},'确认恢复所选快照的程序版本？保留当前设备、租约、节点和 DNS 配置；旧版本可能不包含新功能。');
 $('pf-version-refresh').onclick=versions;
 ['pf-search','pf-group','pf-region','pf-online','pf-health'].forEach(id=>{$(id).oninput=applyFilters;$(id).onchange=applyFilters});
 $('pf-filter-reset').onclick=()=>{['pf-search','pf-group','pf-region','pf-online','pf-health'].forEach(id=>$(id).value='');applyFilters()};
 $('pf-diagnostic-close').onclick=()=>{$('pf-diagnostic').hidden=true};
 if($('pp').classList.contains('maintenance-page'))versions();
 function syncTasks(tasks){
  const changed=(tasks||[]).filter(t=>['upgrade','restore_release'].includes(t.action)&&['done','failed'].includes(t.status)&&!seenTasks.has(t.id));
  changed.forEach(t=>seenTasks.add(t.id));if(changed.length)versions();
 }
 return {update,applyFilters,decorateCards,invalidateBulk,syncTasks,jobMessage:value=>text('pf-bulk-result',value)};
}
root.PhonePanelFeatures={attach,matchGroup,bytes};
})(typeof window==='undefined'?globalThis:window);
