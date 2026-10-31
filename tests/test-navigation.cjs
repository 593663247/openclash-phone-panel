const assert=require('node:assert/strict'),fs=require('node:fs'),{JSDOM}=require('jsdom');
const template=fs.readFileSync('router/luci/view/phone_panel.htm','utf8');
const script=template.match(/<script>([\s\S]*?)<\/script>/)[1].replace(/<%[\s\S]*?%>/g,'test');
const controller=fs.readFileSync('router/luci/controller/phone_panel.lua','utf8');
const tabs=Array.from(controller.matchAll(/entry\(\{'admin','services','phone_panel','(home|management|maintenance|settings)'\}[^\n]*?,(\d+)\)/g),m=>({route:m[1],order:Number(m[2])})).sort((a,b)=>a.order-b.order);
assert.deepEqual(tabs.map(t=>t.route),['home','management','maintenance','settings'],'native LuCI tabs place management immediately after home');
for(const page of ['home','management','maintenance']){
 const dom=new JSDOM(template.replace(/<%[\s\S]*?%>/g,''),{runScripts:'outside-only',url:'https://router.invalid'}),w=dom.window,d=w.document,reads=[];
 d.getElementById('pp').className=page+'-page';w.setInterval=()=>0;w.setTimeout=()=>0;w.fetch=url=>{reads.push(url);return new Promise(()=>{})};
 w.eval(fs.readFileSync('router/luci/resources/workflow.js','utf8'));w.eval(fs.readFileSync('router/luci/resources/nodes.js','utf8'));w.eval(script);
 assert.equal(d.querySelector('.console-nav'),null,'use LuCI tabs without a duplicate in-page navigation');
 assert.equal(w.getComputedStyle(d.querySelector('.management-only')).display==='none',page!=='management');
 assert.equal(w.getComputedStyle(d.querySelector('.maintenance-only')).display==='none',page!=='maintenance');
 assert.equal(w.getComputedStyle(d.querySelector('.home-only')).display==='none',page!=='home');
 assert.equal(reads.some(url=>url.endsWith('/node_catalog')),page==='management','node controls initialize on their new route');
 assert.equal(reads.some(url=>url.endsWith('/maintenance_health')),page==='maintenance','backup inventory is loaded only on its route');
 assert.equal(d.getElementById('operation-panel').open,false);assert.equal(d.getElementById('backup-panel').open,false);
 assert(d.getElementById('node-manager').closest('.management-only'));assert(d.getElementById('edit-device').closest('.management-only'));
 dom.window.close();
}
console.log('PASS: home/management/maintenance visibility, single LuCI navigation, route-specific node and backup initialization');
