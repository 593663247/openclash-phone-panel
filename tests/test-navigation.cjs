const assert=require('node:assert/strict'),fs=require('node:fs'),{JSDOM}=require('jsdom');
const template=fs.readFileSync('router/luci/view/phone_panel.htm','utf8');
const script=template.match(/<script>([\s\S]*?)<\/script>/)[1].replace(/<%[\s\S]*?%>/g,'test');
for(const page of ['home','management','maintenance']){
 const dom=new JSDOM(template.replace(/<%[\s\S]*?%>/g,''),{runScripts:'outside-only',url:'https://router.invalid'}),w=dom.window,d=w.document,reads=[];
 d.getElementById('pp').className=page+'-page';w.setInterval=()=>0;w.setTimeout=()=>0;w.fetch=url=>{reads.push(url);return new Promise(()=>{})};
 w.eval(fs.readFileSync('router/luci/resources/workflow.js','utf8'));w.eval(fs.readFileSync('router/luci/resources/nodes.js','utf8'));w.eval(script);
 assert.deepEqual(Array.from(d.querySelectorAll('.console-nav a'),a=>a.textContent),['主页','设备与节点','管理维护','设置']);
 assert.equal(w.getComputedStyle(d.querySelector('.management-only')).display==='none',page!=='management');
 assert.equal(w.getComputedStyle(d.querySelector('.maintenance-only')).display==='none',page!=='maintenance');
 assert.equal(w.getComputedStyle(d.querySelector('.home-only')).display==='none',page!=='home');
 assert.equal(reads.some(url=>url.endsWith('/node_catalog')),page==='management','node controls initialize on their new route');
 assert.equal(reads.some(url=>url.endsWith('/maintenance_health')),page==='maintenance','backup inventory is loaded only on its route');
 assert.equal(d.getElementById('operation-panel').open,false);assert.equal(d.getElementById('backup-panel').open,false);
 assert(d.getElementById('node-manager').closest('.management-only'));assert(d.getElementById('edit-device').closest('.management-only'));
 dom.window.close();
}
console.log('PASS: home/management/maintenance visibility, horizontal navigation, route-specific node and backup initialization');
