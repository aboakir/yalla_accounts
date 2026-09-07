import fs from 'node:fs';
import path from 'node:path';

export class JsonStore {
  constructor(filePath) {
    this.filePath = filePath;
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
  }

  load() {
    if (!fs.existsSync(this.filePath)) {
      return {
        schema: 1,
        activationCodeSha256: '',
        subscriptions: {},
        devices: {},
        licenses: {},
        activationChallenges: {},
        lifecycleChallenges: {},
        accountDeletionRequests: [],
      };
    }
    return JSON.parse(fs.readFileSync(this.filePath, 'utf8'));
  }

  save(state) {
    const tmp = `${this.filePath}.tmp`;
    fs.writeFileSync(tmp, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
    fs.renameSync(tmp, this.filePath);
  }
}
