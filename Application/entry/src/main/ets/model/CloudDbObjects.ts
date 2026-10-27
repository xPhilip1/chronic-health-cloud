// 云数据库对象模型：类名必须与 CloudProgram/clouddb/objecttype/*.json 的 objectTypeName 完全一致
// （CloudDB SDK 靠类名找云端表，名字对不上查询会返回空）
// 字段必须和 objecttype/*.json 一一对应
import { cloudDatabase } from '@kit.CloudFoundationKit';

// 用户表（对应 objecttype/User.json）
export class User extends cloudDatabase.DatabaseObject {
  userId: number = 0
  username: string = ''
  password: string = ''
  email: string = ''
  phone: string = ''
  gender: string = 'other'
  role: string = 'patient'
  dateOfBirth: string = ''
  doctorLicense: string = ''
  doctorId: number = 0
  createdAt: string = ''
}

// 健康数据表（对应 objecttype/HealthData.json）
export class HealthData extends cloudDatabase.DatabaseObject {
  dataId: number = 0
  userId: number = 0
  bloodPressureSystolic: number = 0
  bloodPressureDiastolic: number = 0
  bloodSugar: number = 0
  weight: number = 0
  heartRate: number = 0
  recordTime: string = ''
  dataSource: string = 'user_input'
  notes: string = ''
}

// 健康预警表（对应 objecttype/HealthWarning.json）
export class HealthWarning extends cloudDatabase.DatabaseObject {
  warningId: number = 0
  userId: number = 0
  warningType: string = ''
  warningMessage: string = ''
  warningTime: string = ''
  acknowledged: boolean = false
  severity: string = 'low'
}
