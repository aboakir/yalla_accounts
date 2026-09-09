(function (root) {
  'use strict';
  root.installManagedOperations = function ({ request, authorized, closePanels }) {
    const api = root.YallaOperations, $ = id => document.getElementById(id);
    let caps = null, organizations = [], subscriptions = [], devices = [], pending = null, busy = false, generation = 0;
    const items = p => Array.isArray(p) ? p : (p.items || p.data || []);
    const option = (value, label) => { const node = document.createElement('option'); node.value = value; node.textContent = label; return node; };
    function fill(id, rows, getId = r => r.id, label = r => r.name || r.display_name || r.device_name || r.id) {
      $(id).replaceChildren(option('', 'اختر...'), ...rows.map(r => option(getId(r), label(r))));
    }
    function reset() {
      generation++; caps = null; pending = null; busy = false;
      organizations = []; subscriptions = []; devices = [];
      $('operationsForm').classList.add('hidden'); $('managedReview').classList.add('hidden');
      $('managedReason').value = ''; $('managedResult').textContent = '';
      $('managedConfirm').disabled = false; $('managedClose').disabled = false;
      $('managedCancel').disabled = false; $('managedOperations').classList.remove('open');
    }
    function targets() {
      const action = api.actions[$('managedAction').value], org = $('managedOrganization').value;
      if (!action) return;
      const records = action.target === 'ORGANIZATION' ? organizations.filter(r => r.id === org) :
        (action.target === 'SUBSCRIPTION' ? subscriptions : devices).filter(r => r.organization_id === org);
      fill('managedTarget', records); fill('managedReplacement', devices.filter(r => r.organization_id === org));
      for (const [id, show] of [['managedDaysLabel', action.days], ['managedExpiryLabel', action.expiry],
        ['managedPlanLabel', action.plan], ['managedReplacementLabel', action.replacement]]) $(id).classList.toggle('hidden', !show);
      const row = organizations.find(r => r.id === org);
      if (row) $('operationsAvailability').textContent = api.telemetry(row).map((v, i) =>
        ['آخر تفعيل', 'آخر مزامنة', 'آخر نسخة احتياطية'][i] + ': ' + (v || 'لم يرد سجل')).join(' — ');
    }
    async function open() {
      if (busy) return;
      if (pending) { closePanels(); $('managedOperations').classList.add('open'); return; }
      reset(); closePanels(); $('managedOperations').classList.add('open');
      $('operationsAvailability').textContent = 'جارٍ التحقق من خدمات الإدارة...';
      const current = generation;
      try {
        if (!authorized()) throw Error('يلزم حساب إدارة يلا مع التحقق الإضافي.');
        const results = await Promise.all(['/capabilities', '/organizations', '/subscriptions', '/devices'].map(path => request(path, { csrf: false })));
        if (current !== generation || !authorized()) return;
        caps = results[0]; organizations = items(results[1]).map(r=>({...r,id:r.id||r.organization_id})); subscriptions = items(results[2]).map(r=>({...r,id:r.id||r.subscription_id})); devices = items(results[3]).map(r=>({...r,id:r.id||r.device_id}));
        const choices = api.available(caps);
        if (!choices.length) throw Error('إجراءات الإدارة غير مفعلة على الخادم بعد.');
        fill('managedAction', choices, r => r[0], r => r[1].label);
        fill('managedOrganization', organizations); fill('managedPlan', (caps.plan_codes || []).map(code => ({ id: code, name: code })));
        $('operationsAvailability').textContent = 'اختر الورشة والإجراء. كل تغيير يتطلب سببًا وأثر تدقيق من الخادم.';
        $('operationsForm').classList.remove('hidden');
      } catch (_) {
        if (current === generation) $('operationsAvailability').textContent = 'الإدارة غير متاحة الآن. يلزم ربط خادم يدعم الصلاحيات وسجل التدقيق ومنع تكرار الطلبات.';
      }
    }
    function review(event) {
      event.preventDefault(); if (busy || !authorized()) return;
      try {
        const org = $('managedOrganization').value, target = $('managedTarget').value;
        pending = api.build($('managedAction').value, { organizationId: org, targetId: target, reason: $('managedReason').value,
          days: $('managedDays').value, expiry: $('managedExpiry').value, plan: $('managedPlan').value,
          replacementId: $('managedReplacement').value, requestId: crypto.randomUUID() }, caps);
        api.validateTargets(pending, { organizations, subscriptions, devices });
        const selected = id => $(id).selectedOptions[0]?.textContent || '';
        $('managedReviewText').textContent = [api.actions[$('managedAction').value].label, selected('managedOrganization'),
          selected('managedTarget'), pending.reason, pending.expires_at ? 'الانتهاء: ' + pending.expires_at : '',
          pending.requested_state.renewal_days || pending.requested_state.extension_days ? 'الأيام: ' + (pending.requested_state.renewal_days || pending.requested_state.extension_days) : '',
          pending.requested_state.plan_code || '', pending.requested_state.replacement_device_id ? 'الجهاز البديل: ' + selected('managedReplacement') : ''].filter(Boolean).join('\n');
        $('operationsForm').classList.add('hidden'); $('managedReview').classList.remove('hidden'); $('managedResult').textContent = '';
      } catch (error) { pending = null; $('managedResult').textContent = error.message; }
    }
    async function confirm() {
      if (busy || !pending || !authorized()) return;
      busy = true; const current = generation;
      for (const id of ['managedConfirm', 'managedCancel', 'managedClose']) $(id).disabled = true;
      $('managedResult').textContent = 'جارٍ إرسال الطلب...';
      try {
        const result = await request('/actions', { method: 'POST', body: pending, idempotencyKey: pending.idempotency_key });
        if (current !== generation || !authorized()) return;
        if (!api.accepted(result, pending.idempotency_key)) throw Error('لم يرد تأكيد موثق من الخادم.');
        $('managedResult').textContent = 'تم تنفيذ الإجراء وتسجيله في سجل التدقيق.';
        pending = null; $('managedReview').classList.add('hidden');
      } catch (_) {
        if (current === generation) $('managedResult').textContent = 'لم يتأكد تنفيذ الطلب. أعد المحاولة بنفس الطلب؛ سيمنع الخادم تكراره.';
      } finally {
        if (current === generation) {
          busy = false; for (const id of ['managedConfirm', 'managedCancel', 'managedClose']) $(id).disabled = false;
          // An uncertain request cannot be edited into a new request; retry retains its key.
          $('managedCancel').disabled = pending !== null;
        }
      }
    }
    $('managedOperationsButton').addEventListener('click', open);
    $('managedAction').addEventListener('change', targets); $('managedOrganization').addEventListener('change', targets);
    $('operationsForm').addEventListener('submit', review); $('managedConfirm').addEventListener('click', confirm);
    $('managedCancel').addEventListener('click', () => { if (busy) return; pending = null; $('managedReview').classList.add('hidden'); $('operationsForm').classList.remove('hidden'); });
    $('managedClose').addEventListener('click', () => { if (!busy) $('managedOperations').classList.remove('open'); });
    return { reset };
  };
})(window);
