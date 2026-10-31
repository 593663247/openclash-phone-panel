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
 async function poll(){
  if(refreshing)return;refreshing=true;
  try{const d=await api.get('operations');busy=d.operations.some(o=>['queued','running'].includes(o.status));
   $('operation-list').innerHTML=d.operations.map(o=>'<details class="notice" '+(['queued','running'].includes(o.status)||o.id===focused?'open':'')+'><summary>'+api.esc(o.action+' · '+o.status+' · '+(o.stage||''))+'</summary>'+api.esc(o.id)+'<br>阶段：'+api.esc(o.stage||'—')+'<br>'+api.esc(o.message||'')+(o.files_restored!=null?'<br>文件恢复：'+api.esc(String(o.files_restored))+'；运行态恢复：'+api.esc(String(o.runtime_restored)):'')+(o.recovery_required?'<br>⚠ 执行中断，请先核查备份与网络；不会自动重试。':'')+(o.backup?'<br>恢复记录：'+api.esc(o.backup):'')+(o.backup&&o.backup.startsWith('/root/phone-panel-transactions/')?'<button type="button" data-operation-restore="'+api.esc(o.backup)+'">恢复此备份（需确认）</button>':'')+(o.result?'<pre>'+api.esc(JSON.stringify(o.result,null,2))+'</pre>':'')+'</details>').join('')||'暂无任务';
   $('operation-list').querySelectorAll('[data-operation-restore]').forEach(b=>b.onclick=async()=>{if(busy)return;const backup=b.dataset.operationRestore;if(!root.confirm('恢复 '+backup+'？将先备份当前配置，再恢复并重载网络。此操作会影响所有受管设备。'))return;try{const r=await api.post('operation_restore',{backup});watch(r.operation_id)}catch(e){$('operation-note').textContent=e.message}});
   for(const o of d.operations){if(['done','failed','interrupted'].includes(o.status)&&!completed.has(o.id)){completed.add(o.id);if(o.id===root.sessionStorage.getItem('phone-panel-current-operation')){root.sessionStorage.removeItem('phone-panel-current-operation');await api.refresh();document.dispatchEvent(new root.Event('phone-panel-operation-complete'))}}}
  }catch(e){$('operation-note').textContent='暂时读不到任务：'+e.message+'。任务在后台继续，刷新后可恢复查询。'}finally{refreshing=false}
 }
 function watch(id){busy=true;focused=id;root.sessionStorage.setItem('phone-panel-current-operation',id);$('operation-note').textContent='后台任务 '+id+' 已提交，可刷新页面；任务完成前请勿重复操作。';poll()}
 $('operation-refresh').onclick=poll;poll();root.setInterval(poll,5000);return {update,watch,busy:()=>busy,poll};
}root.PhonePanelWorkflow={attach};})(typeof window==='undefined'?globalThis:window);
