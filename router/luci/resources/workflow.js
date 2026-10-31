(function(root){'use strict';
root.PhonePanelDialogFocus=function(dialog){dialog.addEventListener('keydown',event=>{
 if(event.key!=='Tab')return;
 const items=Array.from(dialog.querySelectorAll('button,input,select,textarea,a[href],summary,[tabindex]')).filter(el=>!el.disabled&&el.tabIndex>=0&&el.getClientRects().length);
 if(!items.length){event.preventDefault();return}
 const first=items[0],last=items[items.length-1],active=document.activeElement;
 if(event.shiftKey&&(active===first||!items.includes(active))){event.preventDefault();last.focus()}
 else if(!event.shiftKey&&(active===last||!items.includes(active))){event.preventDefault();first.focus()}
})};
function attach(api){
 const $=id=>document.getElementById(id);let current=[],groups=[],busy=false,refreshing=false,signature='',focused=root.sessionStorage.getItem('phone-panel-current-operation');const completed=new Set();
 function update(status){
  groups=status.groups;current=status.groups.flatMap(g=>(g.phones||[]).map(p=>({...p,node:g.node,group:g.id,exit_ip:g.health&&g.health.exit_ip})));
  const select=$('edit-device'),old=select.value,key=JSON.stringify(current.map(p=>[p.ip,p.hostname,p.mac,p.lease_current_ip,p.node]));
  if(key!==signature){select.innerHTML='<option value="">请选择要编辑的设备</option>'+current.map(p=>'<option value="'+api.esc(p.ip)+'">'+api.esc((p.hostname||'未命名')+' · '+p.ip+' · '+(p.mac||'MAC 未知'))+'</option>').join('');select.value=current.some(p=>p.ip===old)?old:'';signature=key;if(old&&$('device-dialog').hasAttribute('open')){$('edit-ip').dispatchEvent(new root.Event('input'));$('edit-apply').hidden=true;$('edit-result').hidden=false;$('edit-result').textContent='设备状态已变化，请重新预览；当前输入已保留。'}}
  detail();devices();change();
 }
 function detail(){const p=current.find(p=>p.ip===$('edit-device').value);$('edit-device-info').textContent=p?'固定配置：'+p.ip+'｜当前租约：'+(p.lease_current_ip||'未发现')+'｜'+(p.lease_current_ip&&p.lease_current_ip!==p.ip?'等待重连 Wi-Fi':'租约已一致／待确认')+'｜节点：'+p.node+'｜最近检测公网出口：'+(p.exit_ip||'未检测'): '请选择设备，固定 IP、当前租约和公网出口会分别显示。'}
 $('edit-device').onchange=()=>{const p=current.find(p=>p.ip===$('edit-device').value);$('edit-ip').value=p?p.ip:'';if(p){$('edit-name').value=p.hostname||'';$('edit-group').value=String(p.group)}$('edit-ip').dispatchEvent(new root.Event('input'));detail()};
 let deviceOpener=null,deviceSignature='',deviceLimit=10;
 function devices(){
  const search=$('managed-device-search').value.trim().toLowerCase(),rows=current.filter(p=>[p.hostname,p.ip,p.mac,p.node].join(' ').toLowerCase().includes(search));
  $('managed-device-count').textContent=Math.min(rows.length,deviceLimit)+' / '+rows.length+' 台';$('managed-device-more').hidden=rows.length<=deviceLimit;
  const signature=JSON.stringify([deviceLimit,rows.map(p=>[p.ip,p.hostname,p.mac,p.node,p.exit_ip,p.lease_current_ip])]);if(signature===deviceSignature)return;deviceSignature=signature;
  $('managed-device-rows').innerHTML=rows.slice(0,deviceLimit).map(p=>'<tr><td data-label="设备"><strong>'+api.esc(p.hostname||'未命名')+'</strong><small>'+api.esc(p.mac||'MAC 未记录')+'</small></td><td data-label="固定 IP / 当前租约">'+api.esc(p.ip)+'<small>'+(p.lease_current_ip&&p.lease_current_ip!==p.ip?'当前 '+api.esc(p.lease_current_ip)+' · 等待重连':p.lease_current_ip?'租约一致':'尚未发现租约')+'</small></td><td data-label="绑定节点">'+api.esc(p.node)+'</td><td data-label="最近公网出口">'+api.esc(p.exit_ip||'未检测')+'<small>最近检测记录，非实时出口</small></td><td data-label="操作"><button type="button" data-device-edit="'+api.esc(p.ip)+'">编辑设备</button></td></tr>').join('')||'<tr><td colspan="5" class="empty-state">'+(current.length?'没有符合条件的设备。':'暂无受管设备，可从主页添加绑定设备。')+'</td></tr>';
 }
 function change(){
  const p=current.find(p=>p.ip===$('edit-device').value);if(!p)return;
  const op=$('edit-op').value,target=groups.find(g=>String(g.id)===$('edit-group').value);
  $('edit-change').textContent=op==='rename'?'名称：'+(p.hostname||'未命名')+' → '+($('edit-name').value.trim()||'填写新名称'):op==='change_ip'?'固定 IP：'+p.ip+' → '+($('edit-new-ip').value.trim()||'填写新 IP'):op==='rebind'?'绑定节点：'+p.node+' → '+(target?target.node:'请选择目标节点'):'设备 '+p.ip+'：受保护 → 解除保护（保留 DHCP 租约）';
 }
 function closeDevice(){
  const dialog=$('device-dialog');if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open');
  $('edit-apply').hidden=true;$('edit-ip').dispatchEvent(new root.Event('input'));
  if(deviceOpener&&deviceOpener.isConnected)deviceOpener.focus();else $('managed-device-search').focus();
 }
 $('managed-device-search').oninput=()=>{deviceLimit=10;devices()};$('managed-device-more').onclick=()=>{deviceLimit+=10;devices()};
 $('managed-device-rows').onclick=e=>{const button=e.target.closest('[data-device-edit]');if(!button)return;if(api.editorBusy&&api.editorBusy()){$('device-manager-note').textContent='设备请求正在提交，请稍后再打开编辑器。';return}deviceOpener=button;$('edit-device').value=button.dataset.deviceEdit;$('edit-op').value='rename';$('edit-new-ip').value='';$('edit-result').hidden=true;$('edit-device').onchange();$('edit-op').dispatchEvent(new root.Event('change'));const p=current.find(p=>p.ip===button.dataset.deviceEdit);$('device-dialog-title').textContent='编辑 '+(p.hostname||p.ip);change();const dialog=$('device-dialog');if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','')};
 root.PhonePanelDialogFocus($('device-dialog'));
 $('device-dialog-close').onclick=closeDevice;
 $('device-dialog').addEventListener('cancel',()=>{$('edit-apply').hidden=true;$('edit-ip').dispatchEvent(new root.Event('input'))});
 ['edit-name','edit-new-ip','edit-group','edit-op'].forEach(id=>{['input','change'].forEach(event=>$(id).addEventListener(event,change))});
 const names={binding_migrate:'设备绑定持久化',node_test:'节点检测',device_edit:'设备修改',node_change:'节点变更',device_add:'添加设备',device_batch:'批量添加',initialize:'初始化',upgrade:'程序升级',backup:'创建备份',doctor:'环境检查',dependencies:'安装依赖',repair_hooks:'修复钩子',restore:'配置恢复',restore_release:'程序恢复'};
 const states={queued:'等待执行',running:'执行中',done:'已完成',failed:'失败',interrupted:'执行中断'};
 let records=[],limit=5;const expanded=new Set(),folded=new Set(),announced=new Set();
 const needsRecovery=o=>o.recovery_required&&!o.historical&&['failed','interrupted'].includes(o.status);
 function outcomes(o){
  if(o.result){const r=o.result,flag=v=>v===true?'通过':v===false?'失败':'未测';return '检测结果：DNS '+flag(r.dns_ok)+'｜出口 '+flag(r.exit_ok)+'｜UDP '+flag(r.udp&&r.udp.udp_ok)}
  if(o.checks)return (o.checks.dhcp_static?'DHCP 静态配置验收通过；':'')+'配置验收通过；手机实际业务及完整 UDP 另行检测';
  return o.status==='done'?'任务执行完成（不代表所有业务正常）':o.historical?'历史记录，不代表当前仍有故障':'';
 }
 function paint(){
  const filter=$('operation-filter').value,active=records.filter(o=>['queued','running'].includes(o.status));
  $('operation-count').textContent='进行中 '+active.length+' · 待核查记录 '+records.filter(needsRecovery).length+' · 历史失败 '+records.filter(o=>['failed','interrupted'].includes(o.status)&&!needsRecovery(o)).length;
  const visible=records.filter(o=>filter==='all'||filter==='active'&&['queued','running'].includes(o.status)||filter==='failed'&&['failed','interrupted'].includes(o.status)||filter===o.status);
  $('operation-more').hidden=visible.length<=limit;
  $('operation-list').innerHTML=visible.slice(0,limit).map(o=>{
   const isActive=['queued','running'].includes(o.status),open=expanded.has(o.id)||!folded.has(o.id)&&(isActive||o.id===focused);
   const time=o.at?new Date(o.at*1000).toLocaleString():'时间未知',duration=o.finished_at&&o.at?' · 耗时 '+Math.max(0,o.finished_at-o.at)+' 秒':'';
   const title=[names[o.action]||o.action,o.subject,o.historical&&o.status==='failed'?'历史失败':states[o.status]||o.status].filter(Boolean).join(' · ');
   return '<details data-task-id="'+api.esc(o.id)+'" class="notice operation-'+api.esc(o.status)+'" '+(open?'open':'')+'><summary>'+api.esc(title)+'<div class="operation-meta">'+api.esc(time+duration)+'</div></summary><p>'+api.esc(outcomes(o))+'</p><p>阶段：'+api.esc(o.stage||'—')+'</p><p>'+api.esc(o.message||'')+'</p><small>任务编号：'+api.esc(o.id)+'</small>'+(o.files_restored!=null?'<p>文件恢复：'+(o.files_restored?'通过':'未通过')+'；运行态恢复：'+(o.runtime_restored?'通过':'未确认')+'</p>':o.rolled_back!=null?'<p>历史回滚记录：'+(o.rolled_back?'已报告恢复':'未确认恢复')+'</p>':'')+(o.rollback_error?'<p>恢复详情：'+api.esc(o.rollback_error)+'</p>':'')+(o.recovery_required?'<p>⚠ 需要人工核查备份与网络；不会自动重试。</p>':'')+(o.backup?'<small>恢复记录：'+api.esc(o.backup)+'</small>':'')+(o.backup&&o.backup.startsWith('/root/phone-panel-transactions/')?'<button type="button" data-operation-restore="'+api.esc(o.backup)+'">恢复操作前配置（需确认）</button>':'')+(o.result?'<pre>'+api.esc(JSON.stringify(o.result,null,2))+'</pre>':'')+'</details>';
  }).join('')||'没有符合条件的任务';
  $('operation-list').querySelectorAll('[data-task-id]').forEach(el=>el.addEventListener('toggle',()=>{if(!el.isConnected)return;const id=el.dataset.taskId;if(el.open){expanded.add(id);folded.delete(id)}else{expanded.delete(id);folded.add(id)}}));
  $('operation-list').querySelectorAll('[data-operation-restore]').forEach(b=>b.onclick=async()=>{if(busy)return;const backup=b.dataset.operationRestore;if(!root.confirm('将恢复此操作之前保存的源配置、受管设备、节点库及 DHCP/防火墙快照。可能影响全部受管设备，并非只撤销当前一条设备。先备份当前配置，再重载网络。确认恢复 '+backup+'？'))return;try{const r=await api.post('operation_restore',{backup});watch(r.operation_id)}catch(e){$('operation-note').textContent=e.message}});
 }
 $('operation-filter').onchange=()=>{limit=5;paint()};$('operation-more').onclick=()=>{limit+=10;paint()};
 async function poll(){
  if(refreshing)return;refreshing=true;
  try{const d=await api.get('operations');busy=d.operations.some(o=>['queued','running'].includes(o.status));
   records=d.operations.slice().sort((a,b)=>(b.at||0)-(a.at||0));
   const attention=records.filter(o=>['queued','running'].includes(o.status)||needsRecovery(o));
   const attentionKey=o=>o.id+(needsRecovery(o)?':recovery':':active');
   if(attention.some(o=>!announced.has(attentionKey(o))))$('operation-panel').open=true;
   attention.forEach(o=>announced.add(attentionKey(o)));
   // Capture open state before replacing DOM; polling never folds a user's details.
   $('operation-list').querySelectorAll('[data-task-id]').forEach(el=>{if(el.open)expanded.add(el.dataset.taskId);else folded.add(el.dataset.taskId)});paint();
   for(const o of d.operations){if(['done','failed','interrupted'].includes(o.status)&&!completed.has(o.id)){completed.add(o.id);if(o.id===root.sessionStorage.getItem('phone-panel-current-operation')){root.sessionStorage.removeItem('phone-panel-current-operation');const target=o.action==='device_edit'?'device-manager-note':['node_change','node_test'].includes(o.action)?'node-list-note':null;if(target)$(target).textContent=o.status==='done'?(o.action==='node_test'?outcomes(o):'配置验收通过。请核对设备租约，并按需检测实际出口与 UDP。'):'操作未完成，请展开任务与恢复查看失败和恢复结果。';await api.refresh();document.dispatchEvent(new root.Event('phone-panel-operation-complete'))}}}
  }catch(e){$('operation-note').textContent='暂时读不到任务：'+e.message+'。任务在后台继续，刷新后可恢复查询。'}finally{refreshing=false}
 }
 function watch(id){busy=true;focused=id;$('operation-panel').open=true;root.sessionStorage.setItem('phone-panel-current-operation',id);$('operation-note').textContent='后台任务 '+id+' 已提交，可刷新页面；任务完成前请勿重复操作。';poll()}
 let bindingPlan=null,recoveryBackup=null,bindingRevision=0;
 async function persistence(){
  bindingRevision++;
  const data=await api.get('persistence'),record=data.status||{},labels={generating:'正在合并',generated:'已生成 · 待验收',verified:'运行态已验收',blocked:'存在冲突',interrupted:'执行中断'};
  $('binding-state').textContent=data.blocked?'数据需恢复':data.initialized?(labels[record.state]||'独立记录已保存'):'尚未迁移';
  $('binding-info').textContent=data.message||((data.initialized?'已保存 '+data.count+' 台设备，格式 '+data.schema+'，修订 '+data.revision+'。':'已有设备请先预览迁移。')+' '+(record.message||'')+(record.at?' · '+new Date(record.at*1000).toLocaleString():''));
  recoveryBackup=data.last_good&&data.last_good.backup||null;$('binding-restore').hidden=!recoveryBackup;
  bindingPlan=null;$('binding-apply').hidden=true;$('binding-preview').className='primary';
 }
 function bindingMessage(value){$('binding-result').hidden=false;$('binding-result').textContent=value}
 $('binding-refresh').onclick=()=>persistence().catch(e=>bindingMessage(e.message));
 $('binding-preview').onclick=async()=>{if(busy)return;const sequence=++bindingRevision;bindingPlan=null;$('binding-apply').hidden=true;try{const p=await api.post('binding_preview',{});if(sequence!==bindingRevision)return;bindingPlan={revision:p.revision};bindingMessage((p.already_initialized?'核对现有独立绑定':'首次迁移清单')+' · '+p.count+' 台\n'+p.devices.map(d=>d.name+(d.dhcp_name&&d.dhcp_name!==d.name?'（DHCP 名称：'+d.dhcp_name+'）':'')+' · '+d.mac+' · '+d.ip+' → '+d.node).join('\n')+'\n'+p.warning);$('binding-apply').hidden=false;$('binding-preview').className=''}catch(e){if(sequence===bindingRevision)bindingMessage(e.message)}};
 $('binding-apply').onclick=async()=>{if(busy||!bindingPlan||!root.confirm('确认保存独立绑定并合并当前配置？会先备份并重载代理，请保留本地管理连接。'))return;const request=bindingPlan;bindingPlan=null;$('binding-apply').hidden=true;try{const r=await api.post('binding_apply',request);watch(r.operation_id);bindingMessage(r.message||'后台任务已提交')}catch(e){bindingMessage(e.message)}};
 $('binding-restore').onclick=async()=>{if(busy||!recoveryBackup||!root.confirm('将恢复上次通过验收的完整配置，包括配置选择、设置、节点、设备和 DHCP，可能影响全部受管设备。当前配置会先备份。确认恢复？'))return;try{const r=await api.post('operation_restore',{backup:recoveryBackup});watch(r.operation_id)}catch(e){bindingMessage(e.message)}};
 document.addEventListener('phone-panel-operation-complete',()=>{if($('pp').classList.contains('maintenance-page'))persistence().catch(e=>bindingMessage(e.message))});
 if($('pp').classList.contains('maintenance-page'))persistence().catch(e=>bindingMessage(e.message));
 let backupPlan=null,backupRows=[],backupLimit=5,backupRevision=0;const backupSelected=new Set();
 function backupMessage(value){$('backup-result').hidden=false;$('backup-result').textContent=value}
 function paintBackups(){
  $('backup-items').innerHTML='<table><thead><tr><th>选择 / 保护原因</th><th>备份</th><th>大小</th><th>时间</th></tr></thead><tbody>'+backupRows.slice(0,backupLimit).map(r=>{
   const name=r.id.split('/').pop(),reason=r.recyclable?'可回收':r.protection_reason||'受保护，不可回收';
   return '<tr><td><input type="checkbox" data-backup="'+api.esc(r.id)+'" '+(r.recyclable?'':'disabled')+' '+(backupSelected.has(r.id)?'checked':'')+' aria-label="选择备份 '+api.esc(name)+'"><span class="backup-protection">'+api.esc(reason)+'</span></td><td class="backup-path"><span class="backup-name">'+api.esc(name)+'</span><details><summary>完整路径</summary><small>'+api.esc(r.id)+'</small></details></td><td>'+api.esc((r.bytes/1048576).toFixed(2))+' MiB</td><td>'+api.esc(new Date(r.at*1000).toLocaleString())+'</td></tr>';
  }).join('')+'</tbody></table>';
  if(!backupRows.length)$('backup-items').textContent='暂无备份';
  $('backup-more').hidden=backupRows.length<=backupLimit;
  $('backup-preview').disabled=backupSelected.size===0;
 }
 async function backupInventory(){
  backupRevision++;backupPlan=null;$('backup-recycle').hidden=true;
  const d=await api.get('maintenance_health');backupRows=d.items;backupLimit=5;backupSelected.clear();
  $('backup-total').textContent=d.count+' 条 · '+(d.total_bytes/1048576).toFixed(1)+' MiB · 可回收 '+d.items.filter(r=>r.recyclable).length+' 条 · 回收目录 '+((d.recycle_bytes||0)/1048576).toFixed(1)+' MiB';
  paintBackups();backupPlan=null;$('backup-recycle').hidden=true;
 }
 if($('backup-refresh')){ $('backup-refresh').onclick=()=>backupInventory().catch(e=>backupMessage(e.message));
 $('backup-items').onchange=e=>{const box=e.target;if(!box.matches('[data-backup]')||box.disabled)return;if(box.checked)backupSelected.add(box.dataset.backup);else backupSelected.delete(box.dataset.backup);backupRevision++;backupPlan=null;$('backup-recycle').hidden=true;$('backup-preview').disabled=backupSelected.size===0};
 $('backup-more').onclick=()=>{backupLimit+=5;paintBackups()};
 $('backup-preview').onclick=async()=>{if(busy)return;const revision=backupRevision;try{const ids=Array.from(backupSelected);const d=await api.post('backup_preview',{ids});if(revision!==backupRevision)return;backupPlan={ids,revision:d.revision};backupMessage(d.items.map(r=>r.id).join('\n')+'\n'+d.warning);$('backup-recycle').hidden=false}catch(e){if(revision===backupRevision)backupMessage(e.message)}};
 $('backup-recycle').onclick=async()=>{if(!backupPlan||busy||!root.confirm('确认将预览的旧备份移入回收目录？不永久删除，也不会释放磁盘空间。'))return;try{const d=await api.post('backup_recycle',backupPlan);backupMessage(d.message+'\n'+d.recycle);await backupInventory()}catch(e){backupMessage(e.message)}};
 if($('pp').classList.contains('maintenance-page'))backupInventory().catch(e=>{$('backup-total').textContent='读取失败，展开后重试';backupMessage(e.message)});}
 $('operation-refresh').onclick=poll;poll();root.setInterval(poll,5000);return {update,watch,busy:()=>busy,poll};
}root.PhonePanelWorkflow={attach};})(typeof window==='undefined'?globalThis:window);
