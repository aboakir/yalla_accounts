export class SupabaseBridgeError extends Error {
  constructor(status, message, body = null) {
    super(message);
    this.status = status;
    this.body = body;
  }
}

export class SupabaseBridge {
  constructor() {
    this.url = String(process.env.YALLA_SUPABASE_URL || '').replace(/\/$/, '');
    this.publicKey = String(process.env.YALLA_SUPABASE_PUBLISHABLE_KEY || '');
    this.token = String(process.env.YALLA_CONTROL_SERVER_TOKEN || '');
  }

  get isConfigured() {
    return this.url.startsWith('https://') &&
      this.publicKey.length >= 20 && this.token.length >= 32;
  }

  async rpc(name, params = {}) {
    if (!this.isConfigured) {
      throw new SupabaseBridgeError(503, 'Supabase server bridge is not configured.');
    }
    const response = await fetch(`${this.url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {
        apikey: this.publicKey,
        'content-type': 'application/json',
        'x-yalla-control-key': this.token,
      },
      body: JSON.stringify(params),
    });
    const text = await response.text();
    let body = null;
    if (text) {
      try {
        body = JSON.parse(text);
      } catch {
        body = text;
      }
    }
    if (!response.ok) {
      const message = body?.message || body?.details || String(body || response.statusText);
      throw new SupabaseBridgeError(response.status, message, body);
    }
    return body;
  }

  prepareLifecycle({ licenseId, subscriptionId, device, action }) {
    return this.rpc('licensing_server_prepare_lifecycle', {
      p_license_id: licenseId,
      p_subscription_id: subscriptionId,
      p_device: device,
      p_action: action,
    });
  }

  recordSyncMutation({ licenseId, subscriptionId, device, message }) {
    return this.rpc('sync_server_record_mutation', {
      p_license_id: licenseId,
      p_subscription_id: subscriptionId,
      p_device: device,
      p_message: message,
    });
  }
}
