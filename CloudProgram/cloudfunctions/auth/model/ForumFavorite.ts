// 服务端 CloudDB 模型（对应 objecttype/ForumFavorite.json）。
// 联合主键 postId + userId：数据库层面天然保证"同一用户对同一帖最多一条收藏"，
// 取消收藏即删除该行，无需额外去重。结构与 ForumLike 完全对称。
export class ForumFavorite {
  postId: number = 0;
  userId: number = 0;
  createdAt: string = '';

  getClassName(): string {
    return 'ForumFavorite';
  }

  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('postId', 'Integer');
    m.set('userId', 'Integer');
    m.set('createdAt', 'String');
    return m;
  }

  getPrimaryKeyList(): string[] {
    return ['postId', 'userId'];
  }

  getIndexList(): string[] {
    return [];
  }

  getEncryptedFieldList(): string[] {
    return [];
  }
}
