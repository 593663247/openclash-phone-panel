(function(root){'use strict';
function attach(api){
 const $=id=>document.getElementById(id);let plan=null,revision=0,busy=false;
 const fields=['node-name','node-server','node-port','node-user','node-password','node-udp','node-front'];
 function invalidate(){revision++;plan=null;$('node-apply').hidden=true}
 function message(value){$('node-result').textContent=value;$('node-result').hidden=false}
 async function catalog(){
  const data=await api.get('node_catalog'),front=$('node-front'),selected=front.value;
  front.innerHTML='<option value="">直连落地（不使用前置代理）</option>'+data.nodes.map(n=>'<option value="'+api.esc(n.name)+'">'+api.esc(n.name)+'</option>').join('');
  front.value=data.nodes.some(n=>n.name===selected)?selected:'';
  $('node-name').placeholder=data.prefix+'新节点';invalidate();
 }
 function input(){return {name:$('node-name').value.trim(),server:$('node-server').value.trim(),port:$('node-port').value,username:$('node-user').value,password:$('node-password').value,udp:$('node-udp').checked,dialer_proxy:$('node-front').value}}
 fields.forEach(id=>{for(const event of ['input','change'])$(id).addEventListener(event,invalidate)});
 $('node-form').onsubmit=async e=>{
  e.preventDefault();if(busy||api.busy())return;invalidate();const current=revision;busy=true;$('node-preview').disabled=true;
  try{const request=input(),data=await api.post('node_preview',request);if(current!==revision)return;plan={request:Object.assign(request,{revision:data.revision}),summary:data.summary};message(JSON.stringify(data.summary,null,2)+'\n'+data.warning);$('node-apply').hidden=false}
  catch(e){message(e.message)}finally{busy=false;$('node-preview').disabled=false}
 };
 $('node-apply').onclick=async()=>{
  if(!plan||busy||api.busy()||!root.confirm('确认新增落地节点？会备份源配置并重载 OpenClash，代理可能短暂中断。不会自动绑定设备。'))return;
  const request=plan.request;busy=true;$('node-apply').disabled=true;$('node-preview').disabled=true;
  try{const data=await api.post('node_apply',request);invalidate();$('node-password').value='';message(data.message+'\n备份：'+data.backup);$('node-form').reset();await catalog();await api.refresh()}
  catch(e){invalidate();message(e.message+'\n请检查路由器记录后重新预览，不要重复提交。')}
  finally{busy=false;$('node-apply').disabled=false;$('node-preview').disabled=false}
 };
 $('node-reload').onclick=()=>catalog().catch(e=>message(e.message));
 catalog().catch(e=>message(e.message));
 return {catalog};
}
root.PhonePanelNodes={attach};
})(typeof window==='undefined'?globalThis:window);
