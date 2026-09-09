(function (root) {
  'use strict';
  const actions = Object.freeze({
    issue: { code: 'LICENSE.ISSUE', label: 'إصدار ترخيص', target: 'ORGANIZATION', expiry: true, plan: true },
    renew: { code: 'SUBSCRIPTION.RENEW', label: 'تجديد الاشتراك', target: 'SUBSCRIPTION', days: 'renewal_days' },
    freeze: { code: 'SUBSCRIPTION.SUSPEND', label: 'تجميد الاشتراك', target: 'SUBSCRIPTION' },
    cancel: { code: 'SUBSCRIPTION.CANCEL', label: 'إلغاء الاشتراك', target: 'SUBSCRIPTION' },
    exception: { code: 'SUBSCRIPTION.EXCEPTION_GRANT', label: 'منح استثناء مؤقت', target: 'SUBSCRIPTION', expiry: true },
    trial: { code: 'SUBSCRIPTION.TRIAL_EXTEND', label: 'تمديد الفترة التجريبية', target: 'SUBSCRIPTION', days: 'extension_days' },
    disable: { code: 'DEVICE.DEACTIVATE', label: 'تعطيل جهاز', target: 'DEVICE' },
    replace: { code: 'DEVICE.REPLACE', label: 'استبدال جهاز', target: 'DEVICE', replacement: true },
  });
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  function isAuthorized(identity) {
    const roles = identity?.roles || identity?.authorization?.roles || [];
    return Array.isArray(roles) && roles.some(role => ['YALLA_SUPER_OWNER', 'YALLA_BREAK_GLASS'].includes(role)) &&
      identity?.authentication_level === 'MFA';
  }
  function available(capabilities) {
    if (!capabilities || capabilities.audit_required !== true || capabilities.idempotency_required !== true) return [];
    return Object.entries(actions).filter(([, a]) => Array.isArray(capabilities.allowed_actions) && capabilities.allowed_actions.includes(a.code));
  }
  function build(kind, input, capabilities, now = Date.now()) {
    const action = actions[kind];
    if (!action || !available(capabilities).some(([id]) => id === kind)) throw Error('هذا الإجراء غير مفعّل من الخادم.');
    if (!uuid.test(input.organizationId) || !uuid.test(input.targetId) || !uuid.test(input.requestId)) throw Error('اختر الورشة والسجل المطلوبين.');
    const reason = String(input.reason || '').trim();
    if (reason.length < 8 || reason.length > 1000) throw Error('اكتب سببًا واضحًا من 8 إلى 1000 حرف.');
    const state = {};
    if (action.days) {
      const days = Number(input.days);
      if (!Number.isInteger(days) || days < 1 || days > 3650) throw Error('عدد الأيام يجب أن يكون بين 1 و3650.');
      state[action.days] = days;
    }
    let expiry = null;
    if (action.expiry) {
      const parsed = Date.parse(input.expiry);
      if (!Number.isFinite(parsed) || parsed <= now) throw Error('حدد تاريخ انتهاء مستقبليًا.');
      expiry = new Date(parsed).toISOString();
      state.expires_at = expiry;
    }
    if (action.plan) {
      if (!Array.isArray(capabilities.plan_codes) || !capabilities.plan_codes.includes(input.plan)) throw Error('اختر خطة معتمدة من الخادم.');
      state.plan_code = input.plan;
    }
    if (action.replacement) {
      if (!uuid.test(input.replacementId) || input.replacementId === input.targetId) throw Error('اختر جهازًا بديلًا مسجّلًا ومختلفًا.');
      state.replacement_device_id = input.replacementId;
    }
    return { action_code: action.code, organization_id: input.organizationId,
      target_entity_type: action.target, target_entity_id: input.targetId,
      reason, requested_state: state, expires_at: expiry, idempotency_key: input.requestId };
  }
  function validateTargets(request, records) {
    const org = request.organization_id;
    if (!records.organizations.some(r => r.id === org)) throw Error('الورشة غير موجودة.');
    const rows = request.target_entity_type === 'ORGANIZATION' ? records.organizations :
      request.target_entity_type === 'SUBSCRIPTION' ? records.subscriptions : records.devices;
    const valid = rows.some(r => r.id === request.target_entity_id &&
      (request.target_entity_type === 'ORGANIZATION' ? r.id === org : r.organization_id === org));
    if (!valid) throw Error('السجل لا يتبع الورشة المختارة.');
    const replacement = request.requested_state.replacement_device_id;
    if (replacement && !records.devices.some(r => r.id === replacement && r.organization_id === org)) throw Error('الجهاز البديل لا يتبع الورشة.');
    return true;
  }
  function accepted(result, requestId) {
    return result && result.idempotency_key === requestId && typeof result.audit_event_id === 'string' &&
      result.audit_event_id.length > 0 && ['APPLIED', 'ALREADY_APPLIED'].includes(result.status);
  }
  function telemetry(row) {
    return [row.last_activation_at || null, row.last_sync_at || null, row.last_backup_at || null];
  }
  root.YallaOperations = Object.freeze({ actions, available, build, validateTargets, accepted, isAuthorized, telemetry });
})(typeof window !== 'undefined' ? window : globalThis);
