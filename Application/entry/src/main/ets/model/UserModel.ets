//用户角色
export type UserRole = 'patient' | 'doctor' | 'admin'

//用户数据结构
export interface UserInfo {
  userId: number
  username: string
  email: string
  phone: string
  gender: string
  role: UserRole
  dateOfBirth: string
  doctorLicense: string
  doctorId: number
  createdAt: string
  nickname: string          // 昵称（展示名）；为空时界面回退显示账号 username
  nicknameUpdatedAt: string // 上次修改昵称的时间(ISO)，用于 5 分钟冷却
  doctorStatus: string      // 医生资质状态：pending 待审核 / approved 已通过 / rejected 已驳回；非医生为空
  avatarUrl: string         // 自定义头像的云存储地址；空串表示用内置角色/性别图标
}

// 首页"患者概览"行：服务端 patientsOverview 一次算好姓名/性别/最近血压/未确认预警数，
// 避免端侧为每个患者各发两次云函数调用（N+1）。
export interface PatientOverview {
  userId: number
  name: string
  gender: string
  latestBp: string
  warnCount: number
  doctorId: number   // 绑定医生（管理员按医生统计患者数时用）
  avatarUrl: string  // 患者头像；空串表示用内置图标
}
