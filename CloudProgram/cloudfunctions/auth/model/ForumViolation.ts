// 服务端 CloudDB 模型（对应 objecttype/ForumViolation.json）。
// 违规台账单独一张表，主键 userId，避免去改已锁死的 User 对象类型。
export class ForumViolation {
  userId: number = 0;
  violationCount: number = 0;
  lastTime: string = '';   // 最近一次命中的 ISO 时间
  muteUntil: string = '';  // 禁言截止 ISO 时间，空或已过期=未禁言

  getClassName(): string {
    return 'ForumViolation';
  }

  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('userId', 'Integer');
    m.set('violationCount', 'Integer');
    m.set('lastTime', 'String');
    m.set('muteUntil', 'String');
    return m;
  }

  getPrimaryKeyList(): string[] {
    return ['userId'];
  }

  getIndexList(): string[] {
    return [];
  }

  getEncryptedFieldList(): string[] {
    return [];
  }
}
