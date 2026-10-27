// 服务端 CloudDB 模型（对应 objecttype/ForumPrivateMessage.json）。
// 五个 getter 齐全否则报 2047；字段类型字符串与 JSON 逐字一致。
export class ForumPrivateMessage {
  messageId: number = 0;   // newId() 秒级+随机数，避 Integer 溢出
  pairId: string = '';     // 归属会话（小id-大id）
  senderId: number = 0;
  receiverId: number = 0;
  content: string = '';
  createdAt: string = '';  // ISO 时间，会话内按此正序
  readFlag: number = 0;    // 0 未读 1 已读（接收方读后置 1）
  status: number = 0;      // 0 正常 1 软删除
  mediaUrls: string = '[]'; // 图片地址列表 JSON 数组；纯文字消息为 '[]'（对齐 ForumComment）

  getClassName(): string {
    return 'ForumPrivateMessage';
  }

  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('messageId', 'Integer');
    m.set('pairId', 'String');
    m.set('senderId', 'Integer');
    m.set('receiverId', 'Integer');
    m.set('content', 'String');
    m.set('createdAt', 'String');
    m.set('readFlag', 'Integer');
    m.set('status', 'Integer');
    m.set('mediaUrls', 'String');
    return m;
  }

  getPrimaryKeyList(): string[] {
    return ['messageId'];
  }

  getIndexList(): string[] {
    return [];
  }

  getEncryptedFieldList(): string[] {
    return [];
  }
}
