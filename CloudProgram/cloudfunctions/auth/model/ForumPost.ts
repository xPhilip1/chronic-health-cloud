// 服务端 CloudDB 模型（对应 objecttype/ForumPost.json）。
// collection() 会 new 本类并校验 getFieldTypeMap/getClassName/getPrimaryKeyList/
// getIndexList/getEncryptedFieldList 五个方法，缺任一报 2047。
// 字段类型字符串必须与 ForumPost.json 的 fieldType 逐字一致。
export class ForumPost {
  postId: number = 0;
  authorId: number = 0;
  authorRole: string = '';
  title: string = '';
  content: string = '';
  createdAt: string = '';
  likeCount: number = 0;
  commentCount: number = 0;
  status: number = 0; // 0 正常 1 软删除（作者或管理员删除，保留审计）
  mediaUrls: string = '[]'; // 图片下载地址列表，JSON 数组字符串；文字帖为 '[]'
  dept: string = '';        // 科室标签（单选），空串表示未选
  topics: string = '[]';    // 话题标签列表，JSON 数组字符串；未选为 '[]'

  getClassName(): string {
    return 'ForumPost';
  }

  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('postId', 'Integer');
    m.set('authorId', 'Integer');
    m.set('authorRole', 'String');
    m.set('title', 'String');
    m.set('content', 'String');
    m.set('createdAt', 'String');
    m.set('likeCount', 'Integer');
    m.set('commentCount', 'Integer');
    m.set('status', 'Integer');
    m.set('mediaUrls', 'String');
    m.set('dept', 'String');
    m.set('topics', 'String');
    return m;
  }

  getPrimaryKeyList(): string[] {
    return ['postId'];
  }

  getIndexList(): string[] {
    return [];
  }

  getEncryptedFieldList(): string[] {
    return [];
  }
}
