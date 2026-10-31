(function(root){'use strict';
function attach(api){
 const $=id=>document.getElementById(id);let plan=null,revision=0,busy=false,applying=false,nodes=[],catalogSignature='',listSignature='',opener=null,listLimit=10,health=new Map(),ttl=1800;
 const fields=['node-name','node-server','node-port','node-user','node-password','node-udp','node-front','node-operation','node-select','node-clear-auth'];
 function invalidate(){revision++;plan=null;$('node-apply').hidden=true;$('node-preview').className='primary'}
 function message(value){$('node-result').textContent=value;$('node-result').hidden=false}
 function note(value){$('node-list-note').textContent=value}
 function renderList(){
  const query=$('node-search').value.trim().toLowerCase(),all=nodes.filter(n=>n.editable),rows=all.filter(n=>[n.name,n.server].join(' ').toLowerCase().includes(query)),key=JSON.stringify([rows,Array.from(health),query,listLimit]);
  $('node-count').textContent=Math.min(rows.length,listLimit)+' / '+rows.length+' 个';$('node-list-more').hidden=rows.length<=listLimit;if(key===listSignature)return;listSignature=key;
  $('node-rows').innerHTML=rows.slice(0,listLimit).map(n=>{
   const h=health.get(n.name)||{},last=h.last,stale=!last||!last.at||Date.now()/1000-last.at>ttl;
   const result=!last?'未检测':stale?'检测记录已过期':last.dns_ok&&last.exit_ok?'DNS / 出口通过':'链路需检查';
   const udp=last&&last.udp&&typeof last.udp.udp_ok==='boolean'?(last.udp.udp_ok?'UDP 最近回包通过':'UDP 最近回包失败'):(n.udp?'UDP 已开启 · 未实测':'UDP 未开启');
   const refs=n.references||[];
   return '<tr><td data-label="节点"><strong>'+api.esc(n.name)+'</strong><small>'+(n.managed?'面板托管':'源配置')+' · SOCKS5</small></td><td data-label="服务器">'+api.esc(n.server||'—')+':'+api.esc(String(n.port||'—'))+'<small>'+api.esc(n['dialer-proxy']?'经由 '+n['dialer-proxy']:'直连落地')+'</small></td><td data-label="引用">'+(refs.length?'<details><summary>'+refs.length+' 处引用</summary><small>'+refs.map(r=>api.esc(r)).join('<br>')+'</small></details>':'无引用')+'</td><td data-label="最近检测"><span class="pf-state '+(stale?'pf-unknown':last.dns_ok&&last.exit_ok?'pf-active':'pf-offline')+'">'+result+'</span><small>'+api.esc(h.exit_ip||last&&last.exit_ip||'无出口记录')+' · '+api.esc(udp)+'</small></td><td data-label="操作"><div class="row-actions"><button type="button" data-node-edit="'+api.esc(n.name)+'">编辑</button><button type="button" data-node-check="'+api.esc(n.name)+'">检测</button><button class="danger-quiet" type="button" data-node-delete="'+api.esc(n.name)+'" '+(refs.length?'disabled title="仍有引用，请先迁移设备或规则"':'')+'>删除</button></div></td></tr>';
  }).join('')||'<tr><td colspan="5" class="empty-state">'+(all.length?'没有符合条件的节点。':'暂无可管理的落地节点，点击“新增节点”开始。')+'</td></tr>';
 }
 function update(status){health=new Map(status.groups.map(g=>[g.node,g.health||{}]));ttl=Math.max(900,Number(status.settings&&status.settings.probe_interval||900)*2);renderList()}
 async function catalog(){
  const data=await api.get('node_catalog'),key=JSON.stringify(data.nodes),changed=key!==catalogSignature;nodes=data.nodes;catalogSignature=key;renderList();
  $('node-name').placeholder=data.prefix+'新节点';
  const target=$('node-select'),previous=target.value;target.innerHTML='<option value="">请选择节点</option>'+nodes.filter(n=>n.editable).map(n=>'<option value="'+api.esc(n.name)+'">'+api.esc(n.name)+'</option>').join('');if(previous&&!nodes.some(n=>n.name===previous))target.innerHTML+='<option value="'+api.esc(previous)+'">'+api.esc(previous)+'（已不在目录）</option>';target.value=previous;
  const front=$('node-front'),selected=front.value;front.innerHTML='<option value="">直连落地（不使用前置代理）</option>'+nodes.map(n=>'<option value="'+api.esc(n.name)+'">'+api.esc(n.name)+'</option>').join('');if(selected&&!nodes.some(n=>n.name===selected))front.innerHTML+='<option value="'+api.esc(selected)+'">'+api.esc(selected)+'（已不在目录）</option>';front.value=selected;
  if($('node-dialog').hasAttribute('open')){if(changed){invalidate();message('节点目录已变化，请重新预览；当前填写内容已保留。')}return}

  invalidate();mode();
 }
 function mode(){const op=$('node-operation').value,n=nodes.find(n=>n.name===$('node-select').value);$('node-select').disabled=op==='create';$('node-name').readOnly=op!=='create';for(const id of ['node-name','node-server','node-port','node-user','node-password','node-udp','node-front','node-clear-auth'])$(id).disabled=op==='delete';$('node-references').textContent=n?'引用：'+((n.references||[]).join('；')||'无设备/规则引用')+'；认证：'+(n.authentication||'未配置') : '新增节点不会自动改绑设备；填写后先预览。';$('node-delete-warning').hidden=op!=='delete';$('node-form').hidden=op==='delete';$('node-clear-auth').closest('label').hidden=op!=='update';$('node-dialog-title').textContent=op==='create'?'新增落地节点':op==='update'?'编辑 '+(n?n.name:'节点'):'删除 '+(n?n.name:'节点');$('node-apply').className=op==='delete'?'danger':'primary';$('node-test').hidden=op!=='update';$('node-preview').textContent=op==='delete'?'预览删除':'预览节点';}
 function populate(){const n=nodes.find(n=>n.name===$('node-select').value);if(n){$('node-name').value=n.name;$('node-server').value=n.server||'';$('node-port').value=n.port||'';$('node-udp').checked=n.udp===true;$('node-front').value=n['dialer-proxy']||'';$('node-user').value='';$('node-password').value=''}mode();invalidate()}
 function closeEditor(force=false){if(applying&&!force)return;invalidate();$('node-form').reset();$('node-password').value='';$('node-user').value='';$('node-clear-auth').checked=false;const dialog=$('node-dialog');if(typeof dialog.close==='function')dialog.close();else dialog.removeAttribute('open');if(opener&&opener.isConnected)opener.focus();else $('node-create').focus();}
 function openEditor(operation,name,button){if(busy)return;opener=button;invalidate();$('node-form').reset();$('node-password').value='';$('node-user').value='';$('node-clear-auth').checked=false;$('node-result').hidden=true;$('node-operation').value=operation;$('node-select').value=name||'';if(operation!=='create')populate();else mode();const dialog=$('node-dialog');if(typeof dialog.showModal==='function')dialog.showModal();else dialog.setAttribute('open','')}
 function input(){return {operation:$('node-operation').value,original_name:$('node-select').value,clear_auth:$('node-clear-auth').checked,name:$('node-name').value.trim(),server:$('node-server').value.trim(),port:$('node-port').value,username:$('node-user').value,password:$('node-password').value,udp:$('node-udp').checked,dialer_proxy:$('node-front').value}}
 function previewText(s){return [(s.operation==='delete'?'删除节点':s.operation==='update'?'修改节点':'新增节点')+'：'+s.name,s.server?'服务器：'+s.server+':'+s.port:null,s['dialer-proxy']?'前置代理：'+s['dialer-proxy']:null,s.authentication?'认证：'+s.authentication:null,typeof s.udp==='boolean'?'UDP：'+(s.udp?'开启（实际可用性需检测）':'关闭'):null].filter(Boolean).join('\n')}
 fields.forEach(id=>{for(const event of ['input','change'])$(id).addEventListener(event,invalidate)});$('node-operation').addEventListener('change',mode);$('node-select').addEventListener('change',populate);document.addEventListener('phone-panel-operation-complete',()=>catalog().catch(e=>note(e.message)));
 if(root.PhonePanelDialogFocus)root.PhonePanelDialogFocus($('node-dialog'));
 $('node-create').onclick=()=>openEditor('create','',$('node-create'));$('node-dialog-close').onclick=()=>closeEditor();
 $('node-dialog').addEventListener('cancel',e=>{e.preventDefault();closeEditor()});
 $('node-search').oninput=()=>{listLimit=10;renderList()};$('node-list-more').onclick=()=>{listLimit+=10;renderList()};$('node-list-refresh').onclick=()=>catalog().catch(e=>note('读取节点失败：'+e.message));
 $('node-rows').onclick=e=>{const b=e.target.closest('button');if(!b||b.disabled)return;if(b.dataset.nodeEdit)openEditor('update',b.dataset.nodeEdit,b);else if(b.dataset.nodeDelete)openEditor('delete',b.dataset.nodeDelete,b);else if(b.dataset.nodeCheck)testNode(b.dataset.nodeCheck)};
 $('node-form').onsubmit=async e=>{
  e.preventDefault();if(busy||api.busy())return;invalidate();const current=revision;busy=true;$('node-preview').disabled=true;
  try{const request=input(),data=await api.post('node_preview',request);if(current!==revision)return;plan={request:Object.assign(request,{revision:data.revision}),summary:data.summary};message(previewText(data.summary)+'\n'+data.warning);$('node-apply').hidden=false;$('node-preview').className=''}
  catch(e){if(current===revision)message(e.message)}finally{busy=false;$('node-preview').disabled=false}
 };
 $('node-apply').onclick=async()=>{
  if(!plan||busy||api.busy()||!root.confirm('确认节点操作？会备份源配置并重载 OpenClash，代理可能短暂中断。不会自动绑定设备。'))return;
  const request=plan.request;busy=true;applying=true;$('node-apply').disabled=true;$('node-preview').disabled=true;
  try{const data=await api.post('node_apply',request);invalidate();closeEditor(true);note((data.message||'已提交节点操作')+(data.operation_id?' · 后台任务已提交，请查看任务与恢复':' · 请检测实际连通性'));await catalog();await api.refresh()}
  catch(e){invalidate();message(e.message+'\n请核对任务结果后重新预览，不要重复提交。')}
  finally{busy=false;applying=false;$('node-apply').disabled=false;$('node-preview').disabled=false}
 };
 async function testNode(name){if(busy||api.busy()){note('已有任务正在执行，请等待完成。');return}busy=true;note('正在提交 '+name+' 的检测…');try{const r=await api.post('node_test',{name});if(r.result){const x=r.result;note(name+'：DNS '+(x.dns_ok?'通过':'失败')+' · 出口 '+(x.exit_ok?'通过':'失败')+' · UDP '+(x.udp&&typeof x.udp.udp_ok==='boolean'?(x.udp.udp_ok?'通过':'失败'):'未测'));}else note(name+'：'+(r.message||'检测任务已提交，请查看任务与恢复'));await api.refresh()}catch(e){note(e.message)}finally{busy=false}}
 $('node-test').onclick=()=>{const name=$('node-select').value;if(!name)return message('请先选择已有节点');return testNode(name)};
 $('node-reload').onclick=()=>catalog().catch(e=>message(e.message));
 catalog().catch(e=>note('读取节点失败：'+e.message));
 return {catalog,update};
}
root.PhonePanelNodes={attach};
})(typeof window==='undefined'?globalThis:window);
