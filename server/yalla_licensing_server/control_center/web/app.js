(() => {
  'use strict';

  const sections = [
    ['dashboard','Dashboard','/dashboard'],['organizations','Organizations','/organizations'],
    ['subscriptions','Subscriptions','/subscriptions'],['licenses','Licenses','/licenses'],
    ['devices','Devices','/devices'],['plans','Plans','/plans'],['features','Features','/features'],
    ['entitlements','Entitlements','/entitlements'],['activations','Activations','/activations'],
    ['renewals','Renewals','/renewals'],['overrides','Overrides','/overrides'],
    ['security-events','Security Events','/security-events'],['audit-logs','Audit Logs','/audit-logs'],
    ['admin-users','Yalla Admin Users','/admin-users'],['break-glass','Break Glass','/break-glass'],
    ['privileged-actions','Privileged Actions','/privileged-actions'],
    ['admin-sessions','Admin Sessions','/auth/sessions'],['admin-security','Admin Security','/admin-security-events']
  ];

  const publicConfig = window.YALLA_CONTROL_CENTER_CONFIG || {};
  const apiBase = String(publicConfig.apiBaseUrl || '').trim().replace(/\/+$/, '');
  let csrfToken = '';
  let mfaChallengeId = '';
  let reauthContextId = '';
  let reauthExpiresAt = 0;
  let authorization = null;

  const $ = id => document.getElementById(id);
  const nav=$('nav'), title=$('title'), content=$('content');
  const authGate=$('authGate'), appShell=$('appShell');

  function escapeHtml(value) { return String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'})[ch]); }
  function setAuthMessage(message,error=false){$('authMessage').textContent=message;$('authMessage').classList.toggle('auth-error',error);}
  function showAuthView(view){for(const id of ['loginView','mfaView','recoveryView']) $(id).classList.add('hidden');$(view).classList.remove('hidden');}
  function closePanels(){for(const id of ['actionPanel','breakGlassPanel','sessionsPanel']) $(id).classList.remove('open');}
  function showApp(){authGate.classList.add('hidden');appShell.classList.remove('hidden');}
  function showLogin(message='Sign in with your Yalla administrator identity.'){
    csrfToken='';mfaChallengeId='';reauthContextId='';reauthExpiresAt=0;authorization=null;
    appShell.classList.add('hidden');authGate.classList.remove('hidden');showAuthView('loginView');setAuthMessage(message);
    $('loginPassword').value='';$('mfaCode').value='';$('reauthPassword').value='';$('reauthMfa').value='';
  }

  async function request(path,{method='GET',body=null,csrf=true}={}){
    if(!apiBase) throw new Error('Control Center API base URL is not configured.');
    const headers={'Accept':'application/json'};
    if(body!==null) headers['Content-Type']='application/json';
    if(csrf && method!=='GET' && csrfToken) headers['X-Yalla-CSRF']=csrfToken;
    const response=await fetch(`${apiBase}/v1/control-center${path}`,{
      method,headers,body:body===null?undefined:JSON.stringify(body),credentials:'include',cache:'no-store'
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
      authorization=payload.authorization||payload;
      showApp();renderActor(payload);await loadSection(sections[0]);
    }catch(error){showLogin(error.status===401?'Sign in with your Yalla administrator identity.':error.message);}
  }

  function renderActor(payload){
    const roles=payload.roles||payload.authorization?.roles||[];
    $('actorState').textContent=roles.includes('YALLA_SUPER_OWNER')?'YALLA_SUPER_OWNER':(roles[0]||'Authorized admin');
    $('actorState').classList.toggle('super-owner',roles.includes('YALLA_SUPER_OWNER'));
    $('sessionState').textContent=payload.authentication_level==='MFA'?'MFA session':'Authenticated';$('sessionState').classList.add('ok');
  }

  async function login(){
    setAuthMessage('Verifying credentials…');
    try{
      const payload=await request('/auth/login',{method:'POST',csrf:false,body:{email:$('loginEmail').value.trim(),password:$('loginPassword').value}});
      $('loginPassword').value='';
      if(payload.status==='MFA_REQUIRED'){
        mfaChallengeId=payload.challenge_id||'';if(!mfaChallengeId) throw new Error('Server did not return an MFA challenge.');
        showAuthView('mfaView');setAuthMessage('Password verified. Complete MFA.');return;
      }
      await bootstrapSession();
    }catch(error){$('loginPassword').value='';setAuthMessage('Sign-in failed. Check your credentials or try again later.',true);}
  }

  async function verifyMfa(){
    try{
      const method=$('mfaMethod').value;
      const proof=method==='TOTP'?{code:$('mfaCode').value.trim()}:{webauthn_response:'BROWSER_CEREMONY_REQUIRED'};
      await request('/auth/mfa/verify',{method:'POST',csrf:false,body:{challenge_id:mfaChallengeId,method,proof}});
      $('mfaCode').value='';mfaChallengeId='';await bootstrapSession();
    }catch(error){$('mfaCode').value='';setAuthMessage('MFA verification failed.',true);}
  }

  async function logout(){
    try{await request('/auth/logout',{method:'POST',body:{reason:'USER_LOGOUT'}});}catch(_){ }
    showLogin('Signed out.');
  }

  async function loadSection(section){
    const [id,label,endpoint]=section;title.innerHTML=`${escapeHtml(label)} <span class="authorized">SERVER AUTH · SEC.015</span>`;
    [...nav.querySelectorAll('button')].forEach(b=>b.classList.toggle('active',b.dataset.section===id));
    content.innerHTML='<div class="empty"><span>Loading…</span></div>';
    try{const payload=await request(endpoint,{csrf:false});renderPayload(id,payload);}
    catch(error){if(error.status===401){showLogin('Your session expired. Sign in again.');return;}content.innerHTML=`<div class="error">Unable to load ${escapeHtml(label)}: ${escapeHtml(error.message)}</div>`;}
  }

  function renderPayload(id,payload){
    if(id==='dashboard'){
      const source=payload.data||payload;const entries=Object.entries(source).filter(([key])=>key!=='generated_at');
      content.innerHTML=`<div class="metrics">${entries.map(([key,value])=>`<div class="metric"><span>${escapeHtml(key.replaceAll('_',' '))}</span><strong>${escapeHtml(value)}</strong></div>`).join('')}</div>`;return;
    }
    const rows=Array.isArray(payload)?payload:(payload.items||payload.data||[]);
    if(!Array.isArray(rows)||rows.length===0){content.innerHTML='<div class="empty"><strong>No records</strong><span>The server returned an empty collection.</span></div>';return;}
    const keys=Object.keys(rows[0]);content.innerHTML=`<div class="table-wrap"><table><thead><tr>${keys.map(k=>`<th>${escapeHtml(k)}</th>`).join('')}</tr></thead><tbody>${rows.map(row=>`<tr>${keys.map(k=>`<td>${escapeHtml(typeof row[k]==='object'?JSON.stringify(row[k]):row[k])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
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
      result.textContent=`Break Glass opened: ${JSON.stringify(payload)}`;reauthContextId='';reauthExpiresAt=0;$('reauthState').textContent='Required';$('actorState').classList.add('break-glass');
    }catch(error){result.textContent=`Rejected: ${error.message}`;}
  }

  async function refreshSessions(){try{$('sessionsResult').textContent=JSON.stringify(await request('/auth/sessions',{csrf:false}),null,2);}catch(error){$('sessionsResult').textContent=error.message;}}
  async function logoutAll(){try{await request('/auth/logout-all',{method:'POST',body:{reason:'USER_REQUESTED_REVOKE_ALL'}});}finally{showLogin('All of your sessions were revoked.');}}

  async function startRecovery(){
    try{await request('/auth/recovery/start',{method:'POST',csrf:false,body:{email:$('recoveryEmail').value.trim()}});$('recoveryComplete').classList.remove('hidden');setAuthMessage('If the account is eligible, recovery instructions have been sent.');}
    catch(_){$('recoveryComplete').classList.remove('hidden');setAuthMessage('If the account is eligible, recovery instructions have been sent.');}
  }
  async function completeRecovery(){
    try{
      await request('/auth/recovery/complete',{method:'POST',csrf:false,body:{challenge_id:$('recoveryChallengeId').value.trim(),recovery_secret:$('recoverySecret').value,recovery_code:$('recoveryCode').value,new_password:$('recoveryNewPassword').value}});
      for(const id of ['recoverySecret','recoveryCode','recoveryNewPassword']) $(id).value='';showLogin('Recovery completed. Sign in with the new password.');
    }catch(error){for(const id of ['recoverySecret','recoveryCode','recoveryNewPassword']) $(id).value='';setAuthMessage('Recovery could not be completed.',true);}
  }

  sections.forEach(section=>{const b=document.createElement('button');b.type='button';b.dataset.section=section[0];b.textContent=section[1];b.addEventListener('click',()=>loadSection(section));nav.appendChild(b);});
  $('loginButton').addEventListener('click',login);$('mfaButton').addEventListener('click',verifyMfa);$('backToLogin').addEventListener('click',()=>showLogin());
  $('recoveryButton').addEventListener('click',()=>{showAuthView('recoveryView');setAuthMessage('Start account recovery.');});$('cancelRecovery').addEventListener('click',()=>showLogin());$('startRecovery').addEventListener('click',startRecovery);$('completeRecovery').addEventListener('click',completeRecovery);
  $('logoutButton').addEventListener('click',logout);$('actionsButton').addEventListener('click',()=>{closePanels();$('actionPanel').classList.toggle('open');});$('breakGlassButton').addEventListener('click',()=>{closePanels();$('breakGlassPanel').classList.toggle('open');});$('sessionsButton').addEventListener('click',()=>{closePanels();$('sessionsPanel').classList.toggle('open');refreshSessions();});
  $('closeAction').addEventListener('click',closePanels);$('closeBreakGlass').addEventListener('click',closePanels);$('closeSessions').addEventListener('click',closePanels);$('submitAction').addEventListener('click',submitPrivilegedAction);$('reauthButton').addEventListener('click',stepUpReauth);$('openBreakGlass').addEventListener('click',openBreakGlass);$('refreshSessions').addEventListener('click',refreshSessions);$('logoutAll').addEventListener('click',logoutAll);
  bootstrapSession();
})();
