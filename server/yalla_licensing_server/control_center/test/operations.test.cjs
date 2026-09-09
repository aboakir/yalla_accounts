'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname,'../web/operations.js'),'utf8'),context);
const api = context.YallaOperations;
const org='11111111-1111-4111-8111-111111111111', other='22222222-2222-4222-8222-222222222222';
const sub='33333333-3333-4333-8333-333333333333', device='44444444-4444-4444-8444-444444444444', replacement='55555555-5555-4555-8555-555555555555';
const caps={audit_required:true,idempotency_required:true,allowed_actions:Object.values(api.actions).map(a=>a.code),plan_codes:['PRO']};
const input={organizationId:org,targetId:sub,requestId:other,reason:'تجديد اشتراك الورشة',days:30,plan:'PRO',expiry:'2030-01-01T00:00:00Z',replacementId:replacement};
const records={organizations:[{id:org}],subscriptions:[{id:sub,organization_id:org}],devices:[{id:device,organization_id:org},{id:replacement,organization_id:org}]};
test('workshop owner/local administrator and non-MFA cannot open Yalla administration',()=>{
  for(const role of ['owner','admin','accountant','staff','viewer','Owner','Manager','Employee','Technician']) assert.equal(api.isAuthorized({roles:[role],authentication_level:'MFA'}),false);
  assert.equal(api.isAuthorized({roles:['YALLA_SUPER_OWNER'],authentication_level:'PASSWORD'}),false);
  assert.equal(api.isAuthorized({roles:'YALLA_SUPER_OWNER',authentication_level:'MFA'}),false);
  assert.equal(api.isAuthorized({roles:['YALLA_SUPER_OWNER'],authentication_level:'MFA'}),true);
});
test('unsupported or unaudited server disables actions',()=>{
  for(const value of [null,{}, {...caps,audit_required:false},{...caps,idempotency_required:false},{...caps,allowed_actions:'LICENSE.ISSUE'}]) assert.equal(api.available(value).length,0);
  assert.throws(()=>api.build('issue',input,{}));
});
test('renewal and trial use distinct bounded durations',()=>{
  assert.equal(api.build('renew',input,caps).requested_state.renewal_days,30);
  assert.equal(api.build('trial',input,caps).requested_state.extension_days,30);
  for(const days of [-1,0,0.5,3651,'abc']) assert.throws(()=>api.build('renew',{...input,days},caps));
});
test('issue/exception require future expiry and server-approved plan',()=>{
  assert.throws(()=>api.build('exception',{...input,expiry:'2000-01-01'},caps));
  assert.throws(()=>api.build('issue',{...input,plan:'INVENTED'},caps));
  assert.equal(api.build('issue',{...input,targetId:org},caps).requested_state.plan_code,'PRO');
});
test('all sensitive actions carry identity, reason and idempotency without signing secrets',()=>{
  for(const kind of Object.keys(api.actions)){
    const data=api.build(kind,{...input,targetId:kind==='issue'?org:api.actions[kind].target==='DEVICE'?device:sub},caps);
    assert.equal(data.reason,input.reason);assert.equal(data.idempotency_key,other);assert.equal(data.organization_id,org);
    assert.equal(JSON.stringify(data).includes('private_key'),false);
  }
  assert.throws(()=>api.build('renew',{...input,reason:'x'},caps));
  assert.throws(()=>api.build('renew',{...input,requestId:'bad'},caps));
});
test('cross-workshop target and device replacement are rejected',()=>{
  const req=api.build('renew',input,caps);assert.equal(api.validateTargets(req,records),true);
  assert.throws(()=>api.validateTargets({...req,organization_id:other},records));
  assert.throws(()=>api.validateTargets({...req,target_entity_id:other},records));
  assert.throws(()=>api.build('replace',{...input,targetId:device,replacementId:device},caps));
  const replace=api.build('replace',{...input,targetId:device},caps);
  assert.equal(api.validateTargets(replace,records),true);
  assert.throws(()=>api.validateTargets(replace,{...records,devices:[records.devices[0],{id:replacement,organization_id:other}]}));
});
test('success requires matching request id and durable server audit acknowledgement',()=>{
  const response={idempotency_key:other,audit_event_id:'audit-123',status:'APPLIED'};
  assert.equal(api.accepted(response,other),true);assert.equal(api.accepted({...response,status:'ALREADY_APPLIED'},other),true);
  for(const r of [{}, {...response,idempotency_key:org},{...response,audit_event_id:''},{...response,status:'QUEUED'}]) assert.equal(Boolean(api.accepted(r,other)),false);
});
test('missing telemetry never becomes a fabricated backup or synchronization time',()=>{
  assert.equal(api.telemetry({}).every(v=>v===null),true);
  assert.equal(api.telemetry({last_backup_at:'2026-09-01'})[2],'2026-09-01');
});
