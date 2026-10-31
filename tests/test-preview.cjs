const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const template = fs.readFileSync(path.join(__dirname, '../router/luci/view/phone_panel.htm'), 'utf8');
const script = template.match(/<script>([\s\S]*?)<\/script>/)[1].replace(/<%[\s\S]*?%>/g, 'test');

function setup(storage = new Map()) {
  const elements = new Map();
  const requests = [];
  const reads = [];
  const timers = [];
  const timeouts = [];
  let api;
  const element = id => {
    if (!elements.has(id)) elements.set(id, {
      hidden: true, disabled: false, value: '', options: [], classList: {contains:()=>false},
      querySelectorAll: () => [], reset() {},
    });
    return elements.get(id);
  };
  vm.runInNewContext(script.replace('})();', 'capture({syncGroups,state,probe,render});})();'), {
    capture(value) { api = value; },
    document: { getElementById: element }, window:{confirm:()=>true}, URLSearchParams, AbortController,
    sessionStorage: { getItem: key => storage.get(key), setItem: (key,value) => storage.set(key,value), removeItem: key => storage.delete(key) },
    setInterval() {}, setTimeout(callback,delay) { if(delay!==15000)timers.push(callback);else timeouts.push(callback); }, clearTimeout() {},
    fetch(url, options) {
      // Leave automatic status refresh pending; drive preview requests explicitly.
      if (!options || options.method !== 'POST') return new Promise((resolve, reject) => {
        if(options.signal)options.signal.addEventListener('abort',()=>reject(new Error('aborted')));
        reads.push({ url, resolve: data => resolve({ ok: true, json: async () => data }), reject });
      });
      return new Promise((resolve, reject) => requests.push({ url, options,
        resolve: data => resolve({ ok: true, json: async () => data }), reject }));
    },
  });
  return { element, requests, reads, api, timers, storage, timeouts };
}

async function check() {
  for (const event of ['oninput', 'onchange']) {
    const { element, requests } = setup();
    element('add-name').value = 'Original';
    const pending = element('pp-add').onsubmit({ preventDefault() {} });
    element('add-name').value = 'Edited';
    element('pp-add')[event]();
    requests[0].resolve({ plan: { name: 'Original' } });
    await pending;
    assert.equal(element('add-apply').hidden, true, `${event}: stale preview must stay hidden`);
    await element('add-apply').onclick();
    assert.equal(requests.length, 1, `${event}: stale plan must not be applied`);
    assert.equal(element('add-preview').disabled, false);
  }

  const { element, requests } = setup();
  const pending = element('pp-add').onsubmit({ preventDefault() {} });
  requests[0].resolve({ plan: { name: 'Current', warning: 'Review' } });
  await pending;
  assert.equal(element('add-apply').hidden, false, 'unchanged form can confirm');
  assert.match(element('add-result').textContent, /Current/);
  element('pp-add').oninput();
  assert.equal(element('add-apply').hidden, true, 'editing a completed preview invalidates it');

  const failed = element('pp-add').onsubmit({ preventDefault() {} });
  element('pp-add').onchange();
  requests[1].reject(new Error('Old error'));
  await failed;
  assert.doesNotMatch(element('add-result').textContent, /Old error/, 'stale errors must not replace current feedback');
  const synced = setup();
  const group = { id: 1, node: 'Node A', dns_port: 15301, socks_port: 18001, ips: [], phones: [] };
  synced.api.syncGroups([group]);
  assert.match(synced.element('add-group').innerHTML, /Node A/);
  synced.api.syncGroups([group, { ...group, id: 2, node: 'Node B' }]);
  synced.element('add-group').value = '2';
  synced.api.syncGroups([group, { ...group, id: 2, node: 'Node B renamed' }]);
  assert.equal(synced.element('add-group').value, '2', 'refresh preserves selected group');
  assert.match(synced.element('add-group').innerHTML, /Node B renamed/);
  synced.api.syncGroups([group]);
  assert.equal(synced.element('add-group').value, '1', 'removed selection falls back to an existing group');
  const previewing = synced.element('pp-add').onsubmit({ preventDefault() {} });
  synced.requests[0].resolve({ plan: { name: 'Device' } });
  await previewing;
  synced.api.syncGroups([group]);
  assert.equal(synced.element('add-apply').hidden, false, 'unchanged refresh preserves preview');
  synced.api.syncGroups([{ ...group, node: 'Replacement' }]);
  assert.equal(synced.element('add-apply').hidden, true, 'catalog change invalidates preview');
  synced.api.state.probes[1] = { exit_ip: 'test' };
  synced.api.syncGroups([{ ...group, ips: ['192.168.1.101'] }]);
  assert.equal(synced.api.state.probes[1], undefined, 'binding change clears old probe');
  const probing = synced.api.probe(1);
  synced.api.syncGroups([{ ...group, node: 'Changed during probe' }]);
  synced.reads[1].resolve({ dns_ok: true, exit_ok: true, exit_ip: 'old result' });
  await probing;
  assert.equal(synced.api.state.probes[1], undefined, 'late probe cannot restore stale result');
  synced.api.syncGroups([]);
  assert.equal(synced.element('add-group').value, '', 'empty catalog clears selection');
  const timed = setup();
  const timedPreview = timed.element('pp-add').onsubmit({ preventDefault() {} });
  timed.requests[0].resolve({ plan: { name: 'Device' } });
  await timedPreview;
  const applying = timed.element('add-apply').onclick();
  timed.requests[1].resolve({ job: 'test-job' });
  await applying;
  for (let i = 0; i < 100; i++) {
    const polling = timed.timers.shift()();
    timed.reads.at(-1).resolve({ status: 'running', message: 'Running' });
    await polling;
  }
  assert.equal(timed.element('add-preview').disabled, true, 'unresolved task blocks new device submission');
  assert.equal(timed.element('add-resume').hidden, false, 'timeout offers task recovery');
  assert.equal(timed.element('add-apply').disabled, false, 'timeout releases confirmation button');
  assert.equal(timed.element('add-apply').hidden, true, 'timeout discards previous confirmation');
  await timed.element('add-apply').onclick();
  assert.equal(timed.requests.length, 2, 'expired confirmation cannot submit a duplicate job');
  assert.match(timed.element('add-result').textContent, /test-job/);
  timed.element('add-resume').onclick();
  const recovering=timed.timers.shift()();
  timed.reads.at(-1).resolve({ status: 'failed', message: 'Failed', rolled_back: true });
  await recovering;
  assert.equal(timed.element('add-preview').disabled, false, 'terminal task releases form');
  assert.equal(timed.storage.size, 0, 'terminal task clears saved ID');
  const saved=new Map([['phone-panel-job:test','20261030120000-abcdef123456']]);
  const resumed=setup(saved);
  assert.equal(resumed.element('add-preview').disabled, true, 'reload blocks new submission during recovery');
  const restored=resumed.timers.shift()();
  assert.match(resumed.reads.at(-1).url, /job\?id=20261030120000-abcdef123456/);
  resumed.reads.at(-1).resolve({ status: 'failed', message: 'Failed', rolled_back: false });
  await restored;
  assert.equal(saved.size,0,'reload recovery clears completed task');
  const unavailable=setup();
  unavailable.reads[0].resolve({ groups: [{...group, connections_available:false}], logs: [], time:'test', connections_available:false });
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(unavailable.element('pp-conns').textContent,'无法读取','API failure is not zero connections');
  assert.match(unavailable.element('pp-grid').innerHTML,/无法读取/);
  const hanging=setup();
  hanging.timeouts[0]();
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(hanging.element('pp-refresh').disabled,false,'timeout releases refresh lock');
  assert.match(hanging.element('pp-error').textContent,/超时/);
  const background=setup();
  background.api.syncGroups([{...group,health:{last:{at:200,dns_ok:true,exit_ok:true,exit_ip:'203.0.113.8',time:'background'}}}]);
  background.api.state.probes[1]={at:100,dns_ok:false,exit_ok:false,time:'older manual'};
  background.api.render();
  assert.match(background.element('pp-grid').innerHTML,/203\.0\.113\.8/,'newer background check replaces stale manual display');
  const edit=setup();
  const editPending=edit.element('edit-preview').onclick();
  edit.element('edit-ip').oninput();
  edit.requests[0].resolve({ revision:'old',summary:{},warning:'' });
  await editPending;
  assert.equal(edit.element('edit-apply').hidden,true,'editing fields invalidates in-flight edit preview');
  await edit.element('edit-apply').onclick();
  assert.equal(edit.requests.length,1,'stale edit must not apply');
  edit.element('edit-op').value='change_ip';
  edit.element('edit-new-ip').value='192.168.1.120';
  const validEdit=edit.element('edit-preview').onclick();
  edit.requests[1].resolve({ revision:'current',summary:{operation:'rename'},warning:'Review' });
  await validEdit;
  assert.equal(edit.element('edit-apply').hidden,false,'valid edit can confirm');
  edit.element('edit-new-ip').oninput();
  assert.equal(edit.element('edit-apply').hidden,true,'changing the target IP invalidates confirmation');
  edit.api.syncGroups([group]);
  assert.equal(edit.element('edit-apply').hidden,true,'catalog changes invalidate device edit preview');
  const selector=setup();
  selector.api.syncGroups([{...group,id:1,node:'手机-01-纽约'},{...group,id:2,node:'手机-02-纽约'}]);
  selector.element('edit-op').value='rebind';selector.element('edit-op').onchange();
  assert.equal(selector.element('edit-group').hidden,false,'rebind shows node selector');
  assert.equal(selector.element('edit-new-ip').hidden,true,'rebind hides IP field');
  assert.match(selector.element('edit-group').innerHTML,/手机-02-纽约/);
  await selector.element('edit-preview').onclick();
  assert.equal(selector.requests.length,0,'empty node choice is rejected before POST');
  selector.element('edit-ip').value='192.168.1.101';selector.element('edit-group').value='2';
  const choose=selector.element('edit-preview').onclick();
  const payload=JSON.parse(selector.requests[0].options.body.get('payload'));
  assert.equal(payload.group,'2','node label submits underlying group ID');
  selector.requests[0].resolve({revision:'valid',summary:payload,warning:''});await choose;
  selector.element('edit-op').value='change_ip';selector.element('edit-op').onchange();
  assert.equal(selector.element('edit-group').hidden,true);
  assert.equal(selector.element('edit-new-ip').hidden,false);
  assert.equal(selector.element('edit-apply').hidden,true,'switching operation invalidates preview');
  console.log('PASS: add/edit previews, catalog refresh, stale probes, job recovery and request timeout');
}

check().catch(error => { console.error(error); process.exitCode = 1; });
