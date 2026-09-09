'use strict';
const test=require('node:test'), assert=require('node:assert/strict'), fs=require('node:fs'), vm=require('node:vm'), path=require('node:path');
async function boot(identity, config={apiBaseUrl:'https://licensing.example.test'}) {
 const nodes={};let count=0;
 function fresh(){const classes=new Set();return {textContent:'',innerHTML:'',value:'',dataset:{},children:[],events:{},classList:{add(v){classes.add(v)},remove(v){classes.delete(v)},toggle(v,force){if(force===undefined?!classes.has(v):force)classes.add(v);else classes.delete(v)},contains(v){return classes.has(v)}},addEventListener(e,f){this.events[e]=f},appendChild(n){this.children.push(n)},querySelectorAll(){return this.children},replaceChildren(...c){this.children=c}};}
 const get=id=>nodes[id]||=(fresh());get('appShell').classList.add('hidden');
 const context=vm.createContext({window:null,document:{getElementById:get,createElement:fresh},URL,AbortSignal,crypto:require('node:crypto').webcrypto,YALLA_CONTROL_CENTER_CONFIG:config,
  fetch:async url=>{count++;return {ok:true,status:200,json:async()=>String(url).endsWith('/auth/session')?identity:{counts:{active_subscriptions:3,organizations:2},secret_token:'MUST_NOT_RENDER'}}}});
 context.window=context;
 for(const file of ['operations.js','managed_operations.js','app.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,'../web',file),'utf8'),context);
 await new Promise(resolve=>setImmediate(resolve));await new Promise(resolve=>setImmediate(resolve));return {get,requests:()=>count};
}
test('unconfigured app displays explanatory Arabic gate without making a request',async()=>{
 const f=await boot({},{});assert.equal(f.requests(),0);assert.match(f.get('authMessage').textContent,/لم يتم ربط/);assert.equal(f.get('appShell').classList.contains('hidden'),true);
});
test('real bootstrap rejects local workshop Owner even with an MFA flag',async()=>{
 const f=await boot({roles:['owner'],authentication_level:'MFA'});assert.equal(f.get('appShell').classList.contains('hidden'),true);assert.equal(f.requests(),1);
});
test('verified Yalla admin opens Arabic overview and renders only allowed data',async()=>{
 const f=await boot({roles:['YALLA_SUPER_OWNER'],authentication_level:'MFA',csrf_token:'session-csrf'});
 assert.equal(f.get('appShell').classList.contains('hidden'),false);assert.match(f.get('content').innerHTML,/اشتراكات نشطة/);assert.doesNotMatch(f.get('content').innerHTML,/MUST_NOT_RENDER/);assert.equal(f.requests(),2);
});
test('insecure production endpoint and credentials in endpoint never receive login data',async()=>{
 for(const url of ['http://licensing.example.test','https://user:password@licensing.example.test']){const f=await boot({}, {apiBaseUrl:url});assert.equal(f.requests(),0);assert.equal(f.get('appShell').classList.contains('hidden'),true);}
});
