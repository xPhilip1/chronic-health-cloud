// 服务端 CloudDB 模型（对应 objecttype/ForumComment.json）。
export class ForumComment {
  commentId: number = 0;
  postId: number = 0;
  authorId: number = 0;
  authorRole: string = '';
  content: string = '';
  createdAt: string = '';
  status: number = 0; // 0 正常 1 软删除
  parentId: number = 0; // 0=主评论；>0=回复某条评论(直接父评论的 commentId)
  mediaUrls: string = '[]'; // 评论图片地址列表 JSON 数组；纯文字评论为 '[]'

  getClassName(): string {
    return 'ForumComment';
  }

  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('commentId', 'Integer');
    m.set('postId', 'Integer');
    m.set('authorId', 'Integer');
    m.set('authorRole', 'String');
    m.set('content', 'String');
    m.set('createdAt', 'String');
    m.set('status', 'Integer');
    m.set('parentId', 'Integer');
    m.set('mediaUrls', 'String');
    return m;
  }

  getPrimaryKeyList(): string[] {
    return ['commentId'];
  }

  getIndexList(): string[] {
    return [];
  }

  getEncryptedFieldList(): string[] {
    return [];
  }
}
