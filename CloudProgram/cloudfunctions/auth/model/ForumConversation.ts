// 服务端 CloudDB 模型（对应 objecttype/ForumConversation.json）。
// collection() 会 new 本类并校验 getFieldTypeMap/getClassName/getPrimaryKeyList/
// getIndexList/getEncryptedFieldList 五个方法，缺任一报 2047。
// 字段类型字符串必须与 ForumConversation.json 的 fieldType 逐字一致。
// pairId = 两个 userId 中较小值 + '-' + 较大值，保证同一对用户有唯一会话主键。
export class ForumConversation {
  pairId: string = '';
  userId1: number = 0;      // 较小的 userId
  userId2: number = 0;      // 较大的 userId
  lastMessage: string = ''; // 会话列表预览文本（截断存摘要）
  lastSenderId: number = 0; // 最后一条消息发送者
  lastCreatedAt: string = '';// 最后一条消息时间，列表按此倒序
  unreadForUser1: number = 0; // userId1 的未读数
  unreadForUser2: number = 0; // userId2 的未读数
  createdAt: string = '';
  status: number = 0;       // 0 正常 1 软删除（清空会话，保留审计）

  getClassName(): string {
    return 'ForumConversation';
  }

  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('pairId', 'String');
    m.set('userId1', 'Integer');
    m.set('userId2', 'Integer');
    m.set('lastMessage', 'String');
    m.set('lastSenderId', 'Integer');
    m.set('lastCreatedAt', 'String');
    m.set('unreadForUser1', 'Integer');
    m.set('unreadForUser2', 'Integer');
    m.set('createdAt', 'String');
    m.set('status', 'Integer');
    return m;
  }

  getPrimaryKeyList(): string[] {
    return ['pairId'];
  }

  getIndexList(): string[] {
    return [];
  }

  getEncryptedFieldList(): string[] {
    return [];
  }
}
