(() => {
  'use strict';

  const sections = [
    ['dashboard','ملخص الإدارة','/dashboard'],['organizations','المشتركون والورش','/organizations'],
    ['subscriptions','الاشتراكات','/subscriptions'],['licenses','التراخيص','/licenses'],
    ['devices','الأجهزة','/devices'],['plans','الخطط','/plans'],['features','الخدمات','/features'],
    ['entitlements','الصلاحيات','/entitlements'],['activations','التفعيلات','/activations'],
    ['renewals','التجديدات','/renewals'],['overrides','الاستثناءات','/overrides'],
    ['security-events','أحداث الأمان','/security-events'],['audit-logs','سجل التدقيق','/audit-logs'],
    ['admin-users','مسؤولو يلا','/admin-users'],['break-glass','الوصول الطارئ','/break-glass'],
    ['privileged-actions','الإجراءات الإدارية','/privileged-actions'],
    ['admin-sessions','جلسات الإدارة','/auth/sessions'],['admin-security','أمان الإدارة','/admin-security-events']
  ];

  const publicConfig = window.YALLA_CONTROL_CENTER_CONFIG || {};
  const apiBase = String(publicConfig.apiBaseUrl || '').trim().replace(/\/+$/, '');
  let csrfToken = '';
  let mfaChallengeId = '';
  let reauthContextId = '';
  let reauthExpiresAt = 0;
  let authorization = null;
  let adminIdentity = null;

  const $ = id => document.getElementById(id);
  const nav=$('nav'), title=$('title'), content=$('content');
  const authGate=$('authGate'), appShell=$('appShell');

  function escapeHtml(value) { return String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'})[ch]); }
  function setAuthMessage(message,error=false){$('authMessage').textContent=message;$('authMessage').classList.toggle('auth-error',error);}
  function showAuthView(view){for(const id of ['loginView','mfaView','recoveryView']) $(id).classList.add('hidden');$(view).classList.remove('hidden');}
  function closePanels(){for(const id of ['actionPanel','breakGlassPanel','sessionsPanel','managedOperations']) $(id).classList.remove('open');}
  function showApp(){authGate.classList.add('hidden');appShell.classList.remove('hidden');}
  function showLogin(message='سجّل الدخول بحساب إدارة يلا.'){
    csrfToken='';mfaChallengeId='';reauthContextId='';reauthExpiresAt=0;authorization=null;adminIdentity=null;managed.reset();
    appShell.classList.add('hidden');authGate.classList.remove('hidden');showAuthView('loginView');setAuthMessage(message);
    $('loginPassword').value='';$('mfaCode').value='';$('reauthPassword').value='';$('reauthMfa').value='';
  }

  async function request(path,{method='GET',body=null,csrf=true,idempotencyKey=null}={}){
    if(!apiBase) throw new Error('لم يتم ربط خادم إدارة يلا بعد.');
    const endpoint = new URL(apiBase);
    if(endpoint.username || endpoint.password) throw Error('لا تضع بيانات دخول في عنوان الخادم.');
    if (endpoint.protocol !== 'https:' && !(publicConfig.allowLocalDevelopment === true && ['localhost', '127.0.0.1', '[::1]'].includes(endpoint.hostname))) throw Error('يلزم اتصال HTTPS آمن.');
    const headers={'Accept':'application/json'};
    if(body!==null) headers['Content-Type']='application/json';
    if(idempotencyKey) headers['Idempotency-Key']=idempotencyKey;
    if(csrf && method!=='GET' && !csrfToken) throw Error('انتهت صلاحية الجلسة؛ سجّل الدخول مجددًا.');
    if(csrf && method!=='GET' && csrfToken) headers['X-Yalla-CSRF']=csrfToken;
    const response=await fetch(`${apiBase}/v1/control-center${path}`,{
      method,headers,body:body===null?undefined:JSON.stringify(body),credentials:'include',cache:'no-store',redirect:'error',signal:AbortSignal.timeout(12000)
    });
    const payload=await response.json().catch(()=>({}));
    if(!response.ok){const error=new Error(payload.message||`HTTP ${response.status}`);error.status=response.status;throw error;}
    if(payload.csrf_token) csrfToken=payload.csrf_token;
    return payload;
  }

  async function bootstrapSession(){
    try{
      const payload=await request('/auth/session',{csrf:false});
      csrfToken=payload.csrf_token||csrfToken;
      if (!window.YallaOperations.isAuthorized(payload)) throw Error('هذه اللوحة تتطلب حساب إدارة يلا وتحققًا إضافيًا.');
      adminIdentity=payload;authorization=payload.authorization||payload;
      showApp();renderActor(payload);await loadSection(sections[0]);
    }catch(error){showLogin(error.status===401?'سجّل الدخول بحساب إدارة يلا.':error.message);}
  }

  function renderActor(payload){
    const roles=payload.roles||payload.authorization?.roles||[];
    $('actorState').textContent=roles.includes('YALLA_SUPER_OWNER')?'مسؤول يلا الرئيسي':'إدارة يلا بصلاحية مؤقتة';
    $('actorState').classList.toggle('super-owner',roles.includes('YALLA_SUPER_OWNER'));
    $('sessionState').textContent=payload.authentication_level==='MFA'?'جلسة محمية':'تم التحقق';$('sessionState').classList.add('ok');
  }

  async function login(){
    setAuthMessage('جارٍ التحقق...');
    try{
      const payload=await request('/auth/login',{method:'POST',csrf:false,body:{email:$('loginEmail').value.trim(),password:$('loginPassword').value}});
      $('loginPassword').value='';
      if(payload.status==='MFA_REQUIRED'){
        mfaChallengeId=payload.challenge_id||'';if(!mfaChallengeId) throw new Error('Server did not return an MFA challenge.');
        showAuthView('mfaView');setAuthMessage('أدخل رمز التحقق الإضافي.');return;
      }
      await bootstrapSession();
    }catch(error){$('loginPassword').value='';setAuthMessage('تعذر الدخول. راجع بياناتك أو حاول لاحقًا.',true);}
  }

  async function verifyMfa(){
    try{
      const method=$('mfaMethod').value;
      const proof=method==='TOTP'?{code:$('mfaCode').value.trim()}:{webauthn_response:'BROWSER_CEREMONY_REQUIRED'};
      await request('/auth/mfa/verify',{method:'POST',csrf:false,body:{challenge_id:mfaChallengeId,method,proof}});
      $('mfaCode').value='';mfaChallengeId='';await bootstrapSession();
    }catch(error){$('mfaCode').value='';setAuthMessage('رمز التحقق غير صحيح أو منتهي.',true);}
  }

  async function logout(){
    try{await request('/auth/logout',{method:'POST',body:{reason:'USER_LOGOUT'}});}catch(_){ }
    showLogin('تم تسجيل الخروج.');
  }

  async function loadSection(section){
    const [id,label,endpoint]=section;title.innerHTML=`${escapeHtml(label)} <span class="authorized">جلسة إدارة موثقة</span>`;
    [...nav.querySelectorAll('button')].forEach(b=>b.classList.toggle('active',b.dataset.section===id));
    content.innerHTML='<div class="empty"><span>جارٍ التحميل...</span></div>';
    try{const payload=await request(endpoint,{csrf:false});renderPayload(id,payload);}
    catch(error){if(error.status===401){showLogin('انتهت الجلسة. سجّل الدخول مجددًا.');return;}content.innerHTML=`<div class="error">تعذر تحميل ${escapeHtml(label)}. حاول مجددًا.</div>`;}
  }

  function renderPayload(id,payload){
    if(id==='dashboard'){
      const source=payload.counts||payload.data||payload; const metricLabels={organizations:'الورش',total_organizations:'عدد الورش',pending_onboarding:'طلبات تسجيل معلقة',active_subscriptions:'اشتراكات نشطة',suspended_subscriptions:'اشتراكات مجمدة',unpaid_subscriptions:'اشتراكات غير مدفوعة',devices:'الأجهزة',active_devices:'الأجهزة المفعلة',pending_activations:'تفعيلات معلقة',security_events:'أحداث الأمان'}; const entries=Object.entries(source).filter(([key,value])=>key in metricLabels && (typeof value==='number' || typeof value==='string')); if(!entries.length){content.textContent='لا توجد بيانات ملخص متاحة.';return;}
      content.innerHTML=`<div class="metrics">${entries.map(([key,value])=>`<div class="metric"><span>${escapeHtml(metricLabels[key])}</span><strong>${escapeHtml(value)}</strong></div>`).join('')}</div>`;return;
    }
    const rows=Array.isArray(payload)?payload:(payload.items||payload.data||[]);
    if(!Array.isArray(rows)||rows.length===0){content.innerHTML='<div class="empty"><strong>لا توجد سجلات</strong><span>لم ترد بيانات من الخادم.</span></div>';return;}
    const labels = {name:'الاسم',display_name:'الاسم',organization_name:'الورشة',email:'البريد',phone:'الهاتف',status:'الحالة',plan_code:'الخطة',expires_at:'الانتهاء',created_at:'الإنشاء',last_activation_at:'آخر تفعيل',last_sync_at:'آخر مزامنة',last_backup_at:'آخر نسخة',device_name:'الجهاز',platform:'النظام',subscriber_name:'المشترك',subscription_id:'الاشتراك',device_id:'الجهاز',license_id:'الترخيص',id:'المعرّف',organization_id:'الورشة',action_code:'الإجراء',timestamp:'الوقت',reason:'السبب'}; const keys=Object.keys(labels).filter(k=>rows.some(row=>k in row));content.innerHTML=`<div class="table-wrap"><table><thead><tr>${keys.map(k=>`<th>${escapeHtml(labels[k] || k)}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${keys.map(k=>`<td>${escapeHtml(row[k] == null ? 'لم يرد سجل' : typeof row[k]==='object' ? '—' : row[k])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
  }

  async function submitPrivilegedAction(){
    const reason=$('actionReason').value.trim();if(reason.length<8){$('actionResult').textContent='Reason must be at least 8 characters.';return;}
    let requestedState;try{requestedState=JSON.parse($('actionState').value||'{}');}catch(_){$('actionResult').textContent='Requested state must be valid JSON.';return;}
    const body={action_code:$('actionCode').value.trim(),organization_id:$('actionOrganization').value.trim()||null,target_entity_type:$('actionTargetType').value.trim()||null,target_entity_id:$('actionTargetId').value.trim()||null,reason,requested_state:requestedState,break_glass_grant_id:$('actionBreakGlass').value.trim()||null,expires_at:$('actionExpiresAt').value||null};
    try{const payload=await request('/actions',{method:'POST',body});$('actionResult').textContent=`Accepted: ${JSON.stringify(payload)}`;}catch(error){$('actionResult').textContent=`Rejected: ${error.message}`;}
  }

  async function stepUpReauth(){
    const result=$('reauthState');result.textContent='Verifying…';
    try{
      const payload=await request('/auth/re-auth',{method:'POST',body:{purpose:'BREAK_GLASS',password:$('reauthPassword').value,mfa_method:'TOTP',mfa_proof:{code:$('reauthMfa').value.trim()}}});
      $('reauthPassword').value='';$('reauthMfa').value='';reauthContextId=payload.reauth_context_id||'';reauthExpiresAt=Date.parse(payload.expires_at||'');
      if(!reauthContextId||!Number.isFinite(reauthExpiresAt)) throw new Error('Invalid reauthentication context.');result.textContent='Verified for up to 5 minutes';
    }catch(error){reauthContextId='';reauthExpiresAt=0;$('reauthPassword').value='';$('reauthMfa').value='';result.textContent=`Failed: ${error.message}`;}
  }

  async function openBreakGlass(){
    const reason=$('bgReason').value.trim(), duration=Number($('bgDuration').value), result=$('bgResult');
    if(!reauthContextId||Date.now()>=reauthExpiresAt){result.textContent='Fresh MFA reauthentication is required first.';return;}
    if(reason.length<15||duration<5||duration>60){result.textContent='Reason >= 15 chars and duration 5-60 minutes are required.';return;}
    try{
      const payload=await request('/break-glass',{method:'POST',body:{organization_id:$('bgOrganization').value.trim(),reason,duration_minutes:duration,reauth_context_id:reauthContextId}});
      result.textContent=`الوصول الطارئ opened: ${JSON.stringify(payload)}`;reauthContextId='';reauthExpiresAt=0;$('reauthState').textContent='Required';$('actorState').classList.add('break-glass');
    }catch(error){result.textContent=`Rejected: ${error.message}`;}
  }

  async function refreshSessions(){try{const p=await request('/auth/sessions',{csrf:false});const rows=Array.isArray(p)?p:p.items||p.sessions||[];$('sessionsResult').textContent=rows.length?rows.map(r=>['الحالة: '+(r.status||'غير محددة'),'البداية: '+(r.created_at||'لم يرد سجل'),'الانتهاء: '+(r.expires_at||'لم يرد سجل')].join(' — ')).join('\n'):'لا توجد جلسات معروضة.';}catch(_){$('sessionsResult').textContent='تعذر تحميل الجلسات.';}}
  async function logoutAll(){try{await request('/auth/logout-all',{method:'POST',body:{reason:'USER_REQUESTED_REVOKE_ALL'}});}finally{showLogin('تم إنهاء جميع جلساتك.');}}

  async function startRecovery(){
    try{await request('/auth/recovery/start',{method:'POST',csrf:false,body:{email:$('recoveryEmail').value.trim()}});$('recoveryComplete').classList.remove('hidden');setAuthMessage('إذا كان الحساب مؤهلًا، ستصلك تعليمات الاستعادة.');}
    catch(_){$('recoveryComplete').classList.remove('hidden');setAuthMessage('إذا كان الحساب مؤهلًا، ستصلك تعليمات الاستعادة.');}
  }
  async function completeRecovery(){
    try{
      await request('/auth/recovery/complete',{method:'POST',csrf:false,body:{challenge_id:$('recoveryChallengeId').value.trim(),recovery_secret:$('recoverySecret').value,recovery_code:$('recoveryCode').value,new_password:$('recoveryNewPassword').value}});
      for(const id of ['recoverySecret','recoveryCode','recoveryNewPassword']) $(id).value='';showLogin('تمت الاستعادة. ادخل بكلمة المرور الجديدة.');
    }catch(error){for(const id of ['recoverySecret','recoveryCode','recoveryNewPassword']) $(id).value='';setAuthMessage('تعذر إكمال الاستعادة.',true);}
  }

  sections.forEach(section=>{const b=document.createElement('button');b.type='button';b.dataset.section=section[0];b.textContent=section[1];b.addEventListener('click',()=>loadSection(section));nav.appendChild(b);});
  $('loginButton').addEventListener('click',login);$('mfaButton').addEventListener('click',verifyMfa);$('backToLogin').addEventListener('click',()=>showLogin());
  $('recoveryButton').addEventListener('click',()=>{showAuthView('recoveryView');setAuthMessage('استعادة حساب الإدارة.');});$('cancelRecovery').addEventListener('click',()=>showLogin());$('startRecovery').addEventListener('click',startRecovery);$('completeRecovery').addEventListener('click',completeRecovery);
  $('logoutButton').addEventListener('click',logout);$('actionsButton').addEventListener('click',()=>{closePanels();$('actionPanel').classList.toggle('open');});$('breakGlassButton').addEventListener('click',()=>{closePanels();$('breakGlassPanel').classList.toggle('open');});$('sessionsButton').addEventListener('click',()=>{closePanels();$('sessionsPanel').classList.toggle('open');refreshSessions();});
  $('closeAction').addEventListener('click',closePanels);$('closeBreakGlass').addEventListener('click',closePanels);$('closeSessions').addEventListener('click',closePanels);$('submitAction').addEventListener('click',submitPrivilegedAction);$('reauthButton').addEventListener('click',stepUpReauth);$('openBreakGlass').addEventListener('click',openBreakGlass);$('refreshSessions').addEventListener('click',refreshSessions);$('logoutAll').addEventListener('click',logoutAll);
  const managed = window.installManagedOperations({ request, authorized: () => window.YallaOperations.isAuthorized(adminIdentity), closePanels });
  bootstrapSession();
})();
