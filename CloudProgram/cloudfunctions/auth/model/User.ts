// 服务端 CloudDB 模型（对应 objecttype User）。
// 注意：@hw-agconnect/cloud-server 的 collection() 会 new 这个类并校验实例上
// 必须有 getFieldTypeMap/getClassName/getPrimaryKeyList/getIndexList/getEncryptedFieldList
// 五个方法（Utils.clazzCheck），缺任何一个都会报 2047 the input class is invalid。
// 字段类型字符串须与 objecttype/User.json 的 fieldType 逐字一致。
export class User {
  userId: number = 0;
  username: string = '';
  password: string = '';
  email: string = '';
  phone: string = '';
  gender: string = 'other';
  role: string = 'patient';
  dateOfBirth: string = '';
  doctorLicense: string = '';
  // 医生资质审核状态：pending / approved / rejected；非医生为空串。
  // 注意：该列需要在 AGC 控制台给已存在的 User 表手工添加；
  // 若云端还没有这一列，服务端会自动降级为"doctorLicense 前缀"方案（见 authService）。
  doctorStatus: string = '';
  // 自定义头像的云存储下载地址；空串表示继续用内置的角色/性别图标
  avatarUrl: string = '';
  doctorId: number = 0;
  createdAt: string = '';
  nickname: string = '';
  nicknameUpdatedAt: string = '';

  // 对象类型名，须与 objectTypeName 逐字一致
  getClassName(): string {
    return 'User';
  }

  // 字段名 -> 字段类型（SDK 用它校验查询条件与反序列化结果）
  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('userId', 'Integer');
    m.set('username', 'String');
    m.set('password', 'String');
    m.set('email', 'String');
    m.set('phone', 'String');
    m.set('gender', 'String');
    m.set('role', 'String');
    m.set('dateOfBirth', 'String');
    m.set('doctorLicense', 'String');
    m.set('doctorStatus', 'String');
    m.set('avatarUrl', 'String');
    m.set('doctorId', 'Integer');
    m.set('createdAt', 'String');
    m.set('nickname', 'String');
    m.set('nicknameUpdatedAt', 'String');
    return m;
  }

  // 主键字段名列表
  getPrimaryKeyList(): string[] {
    return ['userId'];
  }

  // 索引列表（SDK 仅校验方法存在，查询未用到，返回空数组）
  getIndexList(): string[] {
    return [];
  }

  // 加密字段列表（User 表无加密字段）
  getEncryptedFieldList(): string[] {
    return [];
  }
}
