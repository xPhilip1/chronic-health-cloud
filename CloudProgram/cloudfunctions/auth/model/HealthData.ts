// 服务端 CloudDB 模型（对应 objecttype HealthData.json）。
// 与 model/User.ts 同理：@hw-agconnect/cloud-server 的 collection() 会 new 本类并
// 校验实例上必须有 getFieldTypeMap/getClassName/getPrimaryKeyList/getIndexList/
// getEncryptedFieldList 五个方法（Utils.clazzCheck），缺任一报 2047。
// 字段类型字符串必须与 objecttype/HealthData.json 的 fieldType 逐字一致（含 Double）。
export class HealthData {
  dataId: number = 0;
  userId: number = 0;
  bloodPressureSystolic: number = 0;
  bloodPressureDiastolic: number = 0;
  bloodSugar: number = 0;
  weight: number = 0;
  heartRate: number = 0;
  exerciseType: string = '';
  exerciseDuration: number = 0;
  exerciseCalories: number = 0;
  recordTime: string = '';
  dataSource: string = 'user_input';
  notes: string = '';

  getClassName(): string {
    return 'HealthData';
  }

  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('dataId', 'Integer');
    m.set('userId', 'Integer');
    m.set('bloodPressureSystolic', 'Integer');
    m.set('bloodPressureDiastolic', 'Integer');
    m.set('bloodSugar', 'Double');
    m.set('weight', 'Double');
    m.set('heartRate', 'Integer');
    m.set('exerciseType', 'String');
    m.set('exerciseDuration', 'Integer');
    m.set('exerciseCalories', 'Integer');
    m.set('recordTime', 'String');
    m.set('dataSource', 'String');
    m.set('notes', 'String');
    return m;
  }

  getPrimaryKeyList(): string[] {
    return ['dataId'];
  }

  getIndexList(): string[] {
    return [];
  }

  getEncryptedFieldList(): string[] {
    return [];
  }
}
