(function(root){'use strict';
function attach(api){
 const $=id=>document.getElementById(id);let plan=null,revision=0,busy=false,nodes=[];
 const fields=['node-name','node-server','node-port','node-user','node-password','node-udp','node-front','node-operation','node-select','node-clear-auth'];
 function invalidate(){revision++;plan=null;$('node-apply').hidden=true}
 function message(value){$('node-result').textContent=value;$('node-result').hidden=false}
 async function catalog(){
  const data=await api.get('node_catalog');nodes=data.nodes;const target=$('node-select'),previous=target.value;target.innerHTML='<option value="">请选择节点</option>'+nodes.filter(n=>n.editable).map(n=>'<option value="'+api.esc(n.name)+'">'+api.esc(n.name)+(n.managed?' · 面板托管':' · 源配置')+'</option>').join('');target.value=nodes.some(n=>n.name===previous)?previous:'';const front=$('node-front'),selected=front.value;
  front.innerHTML='<option value="">直连落地（不使用前置代理）</option>'+data.nodes.map(n=>'<option value="'+api.esc(n.name)+'">'+api.esc(n.name)+'</option>').join('');
  front.value=data.nodes.some(n=>n.name===selected)?selected:'';
  $('node-name').placeholder=data.prefix+'新节点';invalidate();mode();
 }
 function mode(){const op=$('node-operation').value,n=nodes.find(n=>n.name===$('node-select').value);$('node-select').disabled=op==='create';$('node-name').readOnly=op!=='create';for(const id of ['node-name','node-server','node-port','node-user','node-password','node-udp','node-front','node-clear-auth'])$(id).disabled=op==='delete';$('node-references').textContent=n?'引用：'+((n.references||[]).join('；')||'无设备/规则引用')+'；认证：'+(n.authentication||'未配置') : '编辑/删除/检测前请选择已有节点';}
 function populate(){const n=nodes.find(n=>n.name===$('node-select').value);if(n){$('node-name').value=n.name;$('node-server').value=n.server||'';$('node-port').value=n.port||'';$('node-udp').checked=n.udp===true;$('node-front').value=n['dialer-proxy']||'';$('node-user').value='';$('node-password').value=''}mode();invalidate()}
 function input(){return {operation:$('node-operation').value,original_name:$('node-select').value,clear_auth:$('node-clear-auth').checked,name:$('node-name').value.trim(),server:$('node-server').value.trim(),port:$('node-port').value,username:$('node-user').value,password:$('node-password').value,udp:$('node-udp').checked,dialer_proxy:$('node-front').value}}
 fields.forEach(id=>{for(const event of ['input','change'])$(id).addEventListener(event,invalidate)});$('node-operation').addEventListener('change',mode);$('node-select').addEventListener('change',populate);document.addEventListener('phone-panel-operation-complete',()=>catalog().catch(e=>message(e.message)));
 $('node-form').onsubmit=async e=>{
  e.preventDefault();if(busy||api.busy())return;invalidate();const current=revision;busy=true;$('node-preview').disabled=true;
  try{const request=input(),data=await api.post('node_preview',request);if(current!==revision)return;plan={request:Object.assign(request,{revision:data.revision}),summary:data.summary};message(JSON.stringify(data.summary,null,2)+'\n'+data.warning);$('node-apply').hidden=false}
  catch(e){message(e.message)}finally{busy=false;$('node-preview').disabled=false}
 };
 $('node-apply').onclick=async()=>{
  if(!plan||busy||api.busy()||!root.confirm('确认节点操作？会备份源配置并重载 OpenClash，代理可能短暂中断。不会自动绑定设备。'))return;
  const request=plan.request;busy=true;$('node-apply').disabled=true;$('node-preview').disabled=true;
  try{const data=await api.post('node_apply',request);invalidate();$('node-password').value='';message(data.message+(data.operation_id?'\n任务：'+data.operation_id:'\n备份：'+data.backup));$('node-form').reset();await catalog();await api.refresh()}
  catch(e){invalidate();message(e.message+'\n请检查路由器记录后重新预览，不要重复提交。')}
  finally{busy=false;$('node-apply').disabled=false;$('node-preview').disabled=false}
 };
 $('node-test').onclick=async()=>{if(busy||api.busy())return;const name=$('node-select').value;if(!name)return message('请先选择已有节点');try{const r=await api.post('node_test',{name});message(r.message||JSON.stringify(r.result,null,2))}catch(e){message(e.message)}};
 $('node-reload').onclick=()=>catalog().catch(e=>message(e.message));
 catalog().catch(e=>message(e.message));
 return {catalog};
}
root.PhonePanelNodes={attach};
})(typeof window==='undefined'?globalThis:window);
