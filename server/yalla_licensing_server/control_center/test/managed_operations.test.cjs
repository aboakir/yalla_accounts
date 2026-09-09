'use strict';
const test=require('node:test'), assert=require('node:assert/strict'), fs=require('node:fs'), vm=require('node:vm'), path=require('node:path');
const org='11111111-1111-4111-8111-111111111111', sub='33333333-3333-4333-8333-333333333333', requestId='22222222-2222-4222-8222-222222222222';
function fixture(post) {
 const nodes={};
 function node(id){ return nodes[id] ||= {value:'', textContent:'', disabled:false, selectedOptions:[{textContent:id}], children:[], events:{},
  classList:{add(){},remove(){},toggle(){}}, replaceChildren(...c){this.children=c;}, addEventListener(e,fn){this.events[e]=fn;} }; }
 const ctx=vm.createContext({window:null,document:{getElementById:node,createElement:()=>({value:'',textContent:''})},crypto:{randomUUID:()=>requestId}});ctx.window=ctx;
 for(const name of ['operations.js','managed_operations.js']) vm.runInContext(fs.readFileSync(path.join(__dirname,'../web',name),'utf8'),ctx);
 let allowed=true, calls=[];
 const responses={'/capabilities':{audit_required:true,idempotency_required:true,allowed_actions:['SUBSCRIPTION.RENEW'],plan_codes:[]},'/organizations':[{id:org,name:'ورشة الاختبار'}],'/subscriptions':[{id:sub,organization_id:org}],'/devices':[]};
 const control=ctx.installManagedOperations({authorized:()=>allowed,closePanels(){},async request(p,o){calls.push({p,o});return p==='/actions'?post(o):responses[p];}});
 async function review(){await node('managedOperationsButton').events.click();node('managedAction').value='renew';node('managedOrganization').value=org;node('managedTarget').value=sub;node('managedReason').value='تجديد الاشتراك بناء على الطلب';node('managedDays').value='30';node('operationsForm').events.submit({preventDefault(){}});}
 return {node,control,review,calls,revoke(){allowed=false;}};
}
test('double click produces one request and success needs server acknowledgement',async()=>{
 let release;const f=fixture(o=>new Promise(resolve=>{release=()=>resolve({idempotency_key:o.body.idempotency_key,audit_event_id:'audit-1',status:'APPLIED'});}));
 await f.review();const first=f.node('managedConfirm').events.click();await f.node('managedConfirm').events.click();
 assert.equal(f.calls.filter(c=>c.p==='/actions').length,1);release();await first;
 assert.match(f.node('managedResult').textContent,/تم تنفيذ/);
});
test('timeout retry and close/reopen retain exact request id',async()=>{
 let n=0;const f=fixture(async o=>{if(++n===1)throw Error('timeout');return {idempotency_key:o.body.idempotency_key,audit_event_id:'audit-1',status:'ALREADY_APPLIED'};});
 await f.review();await f.node('managedConfirm').events.click();assert.match(f.node('managedResult').textContent,/لم يتأكد/);
 f.node('managedClose').events.click();await f.node('managedOperationsButton').events.click();await f.node('managedConfirm').events.click();
 const posts=f.calls.filter(c=>c.p==='/actions');assert.equal(posts.length,2);assert.equal(posts[0].o.body.idempotency_key,posts[1].o.body.idempotency_key);
 assert.equal(posts[0].o.idempotencyKey,requestId);
});
test('revoked session cannot confirm a previously reviewed action',async()=>{
 const f=fixture(async()=>{throw Error('must not post');});await f.review();f.revoke();await f.node('managedConfirm').events.click();assert.equal(f.calls.filter(c=>c.p==='/actions').length,0);
});
test('reset during a pending request cannot restore privileged UI after logout',async()=>{
 let release;const f=fixture(o=>new Promise(resolve=>{release=()=>resolve({idempotency_key:o.body.idempotency_key,audit_event_id:'audit-1',status:'APPLIED'});}));
 await f.review();const running=f.node('managedConfirm').events.click();f.revoke();f.control.reset();release();await running;assert.equal(f.node('managedResult').textContent,'');
});
