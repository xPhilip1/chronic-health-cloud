// 服务端 CloudDB 模型（对应 objecttype HealthWarning.json）。
// 同 HealthData/User，必须带 clazzCheck 的五个方法；fieldTypeMap 与 json 逐字一致（含 Boolean）。
export class HealthWarning {
  warningId: number = 0;
  userId: number = 0;
  warningType: string = '';
  warningMessage: string = '';
  warningTime: string = '';
  acknowledged: boolean = false;
  severity: string = 'low';

  getClassName(): string {
    return 'HealthWarning';
  }

  getFieldTypeMap(): Map<string, string> {
    const m = new Map<string, string>();
    m.set('warningId', 'Integer');
    m.set('userId', 'Integer');
    m.set('warningType', 'String');
    m.set('warningMessage', 'String');
    m.set('warningTime', 'String');
    m.set('acknowledged', 'Boolean');
    m.set('severity', 'String');
    return m;
  }

  getPrimaryKeyList(): string[] {
    return ['warningId'];
  }

  getIndexList(): string[] {
    return [];
  }

  getEncryptedFieldList(): string[] {
    return [];
  }
}
