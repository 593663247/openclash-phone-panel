(function(root){'use strict';function attach(api){
 const $=id=>document.getElementById(id);let current=[],busy=false,refreshing=false,signature='',focused=root.sessionStorage.getItem('phone-panel-current-operation');const completed=new Set();
 function update(status){
  current=status.groups.flatMap(g=>(g.phones||[]).map(p=>({...p,node:g.node,group:g.id,exit_ip:g.health&&g.health.exit_ip})));
  const select=$('edit-device'),old=select.value,key=JSON.stringify(current.map(p=>[p.ip,p.hostname,p.mac,p.lease_current_ip,p.node]));
  if(key!==signature){select.innerHTML='<option value="">请选择要编辑的设备</option>'+current.map(p=>'<option value="'+api.esc(p.ip)+'">'+api.esc((p.hostname||'未命名')+' · '+p.ip+' · '+(p.mac||'MAC 未知'))+'</option>').join('');select.value=current.some(p=>p.ip===old)?old:'';signature=key}
  detail();
 }
 function detail(){const p=current.find(p=>p.ip===$('edit-device').value);$('edit-device-info').textContent=p?'固定配置：'+p.ip+'｜当前租约：'+(p.lease_current_ip||'未发现')+'｜'+(p.lease_current_ip&&p.lease_current_ip!==p.ip?'等待重连 Wi-Fi':'租约已一致／待确认')+'｜节点：'+p.node+'｜最近检测公网出口：'+(p.exit_ip||'未检测'): '请选择设备，固定 IP、当前租约和公网出口会分别显示。'}
 $('edit-device').onchange=()=>{const p=current.find(p=>p.ip===$('edit-device').value);$('edit-ip').value=p?p.ip:'';if(p){$('edit-name').value=p.hostname||'';$('edit-group').value=String(p.group)}$('edit-ip').dispatchEvent(new root.Event('input'));detail()};
 const names={node_test:'节点检测',device_edit:'设备修改',node_change:'节点变更',device_add:'添加设备',device_batch:'批量添加',initialize:'初始化',upgrade:'程序升级',backup:'创建备份',doctor:'环境检查',dependencies:'安装依赖',repair_hooks:'修复钩子',restore:'配置恢复',restore_release:'程序恢复'};
 const states={queued:'等待执行',running:'执行中',done:'已完成',failed:'失败',interrupted:'执行中断'};
 let records=[],limit=5;const expanded=new Set(),folded=new Set();
 function outcomes(o){
  if(o.result){const r=o.result,flag=v=>v===true?'通过':v===false?'失败':'未测';return '检测结果：DNS '+flag(r.dns_ok)+'｜出口 '+flag(r.exit_ok)+'｜UDP '+flag(r.udp&&r.udp.udp_ok)}
  if(o.checks)return '配置验收通过；手机实际业务及完整 UDP 另行检测';
  return o.status==='done'?'任务执行完成（不代表所有业务正常）':o.historical?'历史记录，不代表当前仍有故障':'';
 }
 function paint(){
  const filter=$('operation-filter').value,active=records.filter(o=>['queued','running'].includes(o.status));
  $('operation-count').textContent='进行中 '+active.length+' · 失败/中断 '+records.filter(o=>['failed','interrupted'].includes(o.status)).length+' · 共 '+records.length+' 条';
  const visible=records.filter(o=>filter==='all'||filter==='active'&&['queued','running'].includes(o.status)||filter==='failed'&&['failed','interrupted'].includes(o.status)||filter===o.status);
  $('operation-more').hidden=visible.length<=limit;
  $('operation-list').innerHTML=visible.slice(0,limit).map(o=>{
   const isActive=['queued','running'].includes(o.status),open=expanded.has(o.id)||!folded.has(o.id)&&(isActive||o.id===focused);
   const time=o.at?new Date(o.at*1000).toLocaleString():'时间未知',duration=o.finished_at&&o.at?' · 耗时 '+Math.max(0,o.finished_at-o.at)+' 秒':'';
   const title=(names[o.action]||o.action)+' · '+(o.subject||'操作对象未记录')+' · '+(o.historical&&o.status==='failed'?'历史失败':states[o.status]||o.status);
   return '<details data-task-id="'+api.esc(o.id)+'" class="notice operation-'+api.esc(o.status)+'" '+(open?'open':'')+'><summary>'+api.esc(title)+'<div class="operation-meta">'+api.esc(time+duration)+'</div></summary><p>'+api.esc(outcomes(o))+'</p><p>阶段：'+api.esc(o.stage||'—')+'</p><p>'+api.esc(o.message||'')+'</p><small>任务编号：'+api.esc(o.id)+'</small>'+(o.files_restored!=null?'<p>文件恢复：'+(o.files_restored?'通过':'未通过')+'；运行态恢复：'+(o.runtime_restored?'通过':'未确认')+'</p>':o.rolled_back!=null?'<p>历史回滚记录：'+(o.rolled_back?'已报告恢复':'未确认恢复')+'</p>':'')+(o.recovery_required?'<p>⚠ 执行中断，先核查备份与网络；不会自动重试。</p>':'')+(o.backup?'<small>恢复记录：'+api.esc(o.backup)+'</small>':'')+(o.backup&&o.backup.startsWith('/root/phone-panel-transactions/')?'<button type="button" data-operation-restore="'+api.esc(o.backup)+'">恢复操作前配置（需确认）</button>':'')+(o.result?'<pre>'+api.esc(JSON.stringify(o.result,null,2))+'</pre>':'')+'</details>';
  }).join('')||'没有符合条件的任务';
  $('operation-list').querySelectorAll('[data-task-id]').forEach(el=>el.addEventListener('toggle',()=>{if(!el.isConnected)return;const id=el.dataset.taskId;if(el.open){expanded.add(id);folded.delete(id)}else{expanded.delete(id);folded.add(id)}}));
  $('operation-list').querySelectorAll('[data-operation-restore]').forEach(b=>b.onclick=async()=>{if(busy)return;const backup=b.dataset.operationRestore;if(!root.confirm('将恢复此操作之前保存的源配置、受管设备、节点库及 DHCP/防火墙快照。可能影响全部受管设备，并非只撤销当前一条设备。先备份当前配置，再重载网络。确认恢复 '+backup+'？'))return;try{const r=await api.post('operation_restore',{backup});watch(r.operation_id)}catch(e){$('operation-note').textContent=e.message}});
 }
 $('operation-filter').onchange=()=>{limit=5;paint()};$('operation-more').onclick=()=>{limit+=10;paint()};
 async function poll(){
  if(refreshing)return;refreshing=true;
  try{const d=await api.get('operations');busy=d.operations.some(o=>['queued','running'].includes(o.status));
   records=d.operations.slice().sort((a,b)=>(b.at||0)-(a.at||0));
   // Capture open state before replacing DOM; polling never folds a user's details.
   $('operation-list').querySelectorAll('[data-task-id]').forEach(el=>{if(el.open)expanded.add(el.dataset.taskId);else folded.add(el.dataset.taskId)});paint();
   for(const o of d.operations){if(['done','failed','interrupted'].includes(o.status)&&!completed.has(o.id)){completed.add(o.id);if(o.id===root.sessionStorage.getItem('phone-panel-current-operation')){root.sessionStorage.removeItem('phone-panel-current-operation');await api.refresh();document.dispatchEvent(new root.Event('phone-panel-operation-complete'))}}}
  }catch(e){$('operation-note').textContent='暂时读不到任务：'+e.message+'。任务在后台继续，刷新后可恢复查询。'}finally{refreshing=false}
 }
 function watch(id){busy=true;focused=id;root.sessionStorage.setItem('phone-panel-current-operation',id);$('operation-note').textContent='后台任务 '+id+' 已提交，可刷新页面；任务完成前请勿重复操作。';poll()}
 let backupPlan=null;
 function backupMessage(value){$('backup-result').hidden=false;$('backup-result').textContent=value}
 async function backupInventory(){const d=await api.get('maintenance_health');$('backup-total').textContent=d.count+' 条备份 · '+(d.total_bytes/1048576).toFixed(1)+' MiB · 回收目录 '+((d.recycle_bytes||0)/1048576).toFixed(1)+' MiB';$('backup-items').innerHTML='<table><thead><tr><th>选择</th><th>备份</th><th>大小</th><th>时间</th></tr></thead><tbody>'+d.items.map(r=>'<tr><td><input type="checkbox" data-backup="'+api.esc(r.id)+'" '+(r.recyclable?'':'disabled')+' aria-label="选择备份 '+api.esc(r.id)+'"></td><td>'+api.esc(r.id)+'</td><td>'+api.esc((r.bytes/1048576).toFixed(2))+' MiB</td><td>'+api.esc(new Date(r.at*1000).toLocaleString())+'</td></tr>').join('')+'</tbody></table>';backupPlan=null;$('backup-recycle').hidden=true}
 if($('backup-refresh')){ $('backup-refresh').onclick=()=>backupInventory().catch(e=>backupMessage(e.message));
 $('backup-items').onchange=()=>{backupPlan=null;$('backup-recycle').hidden=true};
 $('backup-preview').onclick=async()=>{if(busy)return;try{const ids=Array.from($('backup-items').querySelectorAll('[data-backup]:checked')).map(e=>e.dataset.backup);const d=await api.post('backup_preview',{ids});backupPlan={ids,revision:d.revision};backupMessage(d.items.map(r=>r.id).join('\n')+'\n'+d.warning);$('backup-recycle').hidden=false}catch(e){backupMessage(e.message)}};
 $('backup-recycle').onclick=async()=>{if(!backupPlan||busy||!root.confirm('确认将预览的旧备份移入回收目录？不永久删除，也不会释放磁盘空间。'))return;try{const d=await api.post('backup_recycle',backupPlan);backupMessage(d.message+'\n'+d.recycle);await backupInventory()}catch(e){backupMessage(e.message)}};
 backupInventory().catch(e=>backupMessage(e.message));}
 $('operation-refresh').onclick=poll;poll();root.setInterval(poll,5000);return {update,watch,busy:()=>busy,poll};
}root.PhonePanelWorkflow={attach};})(typeof window==='undefined'?globalThis:window);
