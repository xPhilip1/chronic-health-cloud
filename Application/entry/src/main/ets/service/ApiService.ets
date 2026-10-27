import { UserInfo, UserRole, PatientOverview } from '../model/UserModel'
import { HealthData, HealthWarning, HealthAdvice, HealthReport, TrendPoint, AiHealthReport, AiMetricRead, AiReportCache } from '../model/HealthModel'
import { ForumPost, ForumComment, ForumViolationStatus, ForumLikeResult, ForumPostPage, DmConversation, DmMessage, ForumUserBrief } from '../model/ForumModel'
import { preferences } from '@kit.ArkData'
import { cloudFunction } from '@kit.CloudFoundationKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { router } from '@kit.ArkUI'

const STORE_NAME = 'chronic_health'
const HILOG_DOMAIN = 0x0000
const TAG = '[ApiService]'
let context: Context | null = null

// 初始化
export function initApiService(ctx: Context): void {
  context = ctx
}

async function getStore(): Promise<preferences.Preferences> {
  if (!context) {
    throw new Error('ApiService 未初始化，请先调用 initApiService')
  }
  return await preferences.getPreferences(context, STORE_NAME)
}

// ==================== 云函数调用底座 ====================
// 1d：端侧不再直连 CloudDB，所有数据读写统一走 auth 云函数，
// 令牌放在参数首位，由服务端验签做“登录态 + 角色”行级鉴权。

// 服务端令牌失效时的固定文案，与 authService 保持一致
const AUTH_EXPIRED_MSG = '未登录或登录已过期'
// 防止并发请求同时触发多次跳转
let redirectingToLogin: boolean = false

// 令牌过期/被吊销：清掉本地会话并回登录页。
// 以前这里什么都不做，结果就是令牌过期后各页面拿到空数据、界面一片空白且没有提示。
async function handleAuthExpired(): Promise<void> {
  if (redirectingToLogin) {
    return
  }
  redirectingToLogin = true
  try {
    let store = await getStore()
    await store.delete('token')
    await store.delete('currentUser')
    await store.delete('currentUserId')
    await store.flush()
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'clear expired session err %{public}s', JSON.stringify(e))
  }
  try {
    router.replaceUrl({ url: 'pages/LoginPage' })
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'redirect to login err %{public}s', JSON.stringify(e))
  }
  // 留一个窗口期，避免页面里多个并发请求把跳转排队重复执行
  setTimeout(() => {
    redirectingToLogin = false
  }, 2000)
}

// 把 AGC 平台的英文分发错误翻译成能看懂的中文
function translateCloudError(method: string, raw: string): Error {
  let low: string = raw.toLowerCase()
  if (low.indexOf('find cloud object method') >= 0 || low.indexOf('cannot find') >= 0) {
    return new Error('云函数缺少方法 ' + method + '，请重新部署 auth 云函数后再试')
  }
  return new Error(raw)
}

// 直接调 auth 云函数，解析 { ok, data/error } 信封；ok!=true 抛错
async function callAuth(method: string, params: Object[]): Promise<Record<string, Object>> {
  let payload: Record<string, Object> | null = null
  try {
    let res = await cloudFunction.call({
      name: 'auth',
      version: '$latest',
      data: { method: method, params: params }
    })
    payload = res.result as Record<string, Object>
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'cloud call failed method=%{public}s err=%{public}s',
      method, JSON.stringify(e))
    throw translateCloudError(method, (e as Error).message)
  }
  if (payload === null) {
    throw new Error('云服务无响应')
  }
  if (payload['ok'] !== true) {
    // 优先取业务错误文案；message 是部分网关错误的字段名
    let msg: string = ''
    if (payload['error']) {
      msg = String(payload['error'])
    } else if (payload['message']) {
      msg = String(payload['message'])
    } else {
      // 既没有 ok 也没有 error：说明请求没走到云函数的业务分支，
      // 最常见的原因是"云函数还是旧版本、没有这个方法"，或网关直接拒了这次调用。
      // 把原始返回打到日志里，方便对照 AGC 的函数版本。
      hilog.error(HILOG_DOMAIN, TAG, 'unhandled envelope method=%{public}s payload=%{public}s',
        method, JSON.stringify(payload))
      let code: string = payload['errorCode'] ? String(payload['errorCode']) : ''
      msg = '云函数未返回错误原因（方法 ' + method + (code !== '' ? '，错误码 ' + code : '') + '）'
      msg += '，通常是 auth 云函数还没有部署到最新版本'
    }
    if (msg === AUTH_EXPIRED_MSG) {
      // 不阻塞调用方拿错误：先清会话跳登录，同时让页面照常收到"登录已过期"
      handleAuthExpired()
      throw new Error('登录已过期，请重新登录')
    }
    throw new Error(msg)
  }
  return payload
}

// 取本地令牌 -> 拼到参数首位 -> 调 callAuth
async function authCall(method: string, extra: Object[]): Promise<Record<string, Object>> {
  let store = await getStore()
  let token = await store.get('token', '') as string
  let params: Object[] = []
  params.push(token)
  for (let i = 0; i < extra.length; i++) {
    params.push(extra[i])
  }
  return await callAuth(method, params)
}

// ==================== 记录 -> 本地对象 映射 ====================
function recToUserInfo(r: Record<string, Object>): UserInfo {
  let info: UserInfo = {
    userId: r['userId'] as number,
    username: r['username'] as string,
    email: r['email'] as string,
    phone: r['phone'] as string,
    gender: r['gender'] as string,
    role: r['role'] as UserRole,
    dateOfBirth: r['dateOfBirth'] as string,
    doctorLicense: r['doctorLicense'] as string,
    doctorId: r['doctorId'] as number,
    createdAt: r['createdAt'] as string,
    nickname: r['nickname'] ? (r['nickname'] as string) : '',
    nicknameUpdatedAt: r['nicknameUpdatedAt'] ? (r['nicknameUpdatedAt'] as string) : '',
    doctorStatus: r['doctorStatus'] ? (r['doctorStatus'] as string) : '',
    avatarUrl: r['avatarUrl'] ? (r['avatarUrl'] as string) : ''
  }
  return info
}

function recListToUserInfo(v: Object): UserInfo[] {
  let out: UserInfo[] = []
  if (!v) {
    return out
  }
  let arr = v as Record<string, Object>[]
  for (let i = 0; i < arr.length; i++) {
    out.push(recToUserInfo(arr[i]))
  }
  return out
}

function recToHealth(r: Record<string, Object>): HealthData {
  let d: HealthData = {
    dataId: r['dataId'] as number,
    userId: r['userId'] as number,
    bloodPressureSystolic: r['bloodPressureSystolic'] as number,
    bloodPressureDiastolic: r['bloodPressureDiastolic'] as number,
    bloodSugar: r['bloodSugar'] as number,
    weight: r['weight'] as number,
    heartRate: r['heartRate'] as number,
    exerciseType: r['exerciseType'] ? (r['exerciseType'] as string) : '',
    exerciseDuration: r['exerciseDuration'] ? (r['exerciseDuration'] as number) : 0,
    exerciseCalories: r['exerciseCalories'] ? (r['exerciseCalories'] as number) : 0,
    recordTime: r['recordTime'] as string,
    dataSource: r['dataSource'] as string,
    notes: r['notes'] as string
  }
  return d
}

function recListToHealth(v: Object): HealthData[] {
  let out: HealthData[] = []
  if (!v) {
    return out
  }
  let arr = v as Record<string, Object>[]
  for (let i = 0; i < arr.length; i++) {
    out.push(recToHealth(arr[i]))
  }
  return out
}

function recToWarning(r: Record<string, Object>): HealthWarning {
  let w: HealthWarning = {
    warningId: r['warningId'] as number,
    userId: r['userId'] as number,
    warningType: r['warningType'] as string,
    warningMessage: r['warningMessage'] as string,
    warningTime: r['warningTime'] as string,
    acknowledged: r['acknowledged'] as boolean,
    severity: r['severity'] as string
  }
  return w
}

function recListToWarning(v: Object): HealthWarning[] {
  let out: HealthWarning[] = []
  if (!v) {
    return out
  }
  let arr = v as Record<string, Object>[]
  for (let i = 0; i < arr.length; i++) {
    out.push(recToWarning(arr[i]))
  }
  return out
}

// ==================== 用户块 ====================

// 登录：云端加盐哈希校验 + 签发会话令牌；端侧只存令牌与用户快照
export async function login(username: string, password: string): Promise<UserInfo | null> {
  let payload = await callAuth('login', [username, password])
  let u = payload['user'] as Record<string, Object>
  let info = recToUserInfo(u)
  let store = await getStore()
  await store.put('currentUserId', info.userId)
  let token = payload['token'] ? String(payload['token']) : ('cloud_token_' + info.userId)
  await store.put('token', token)
  await store.put('currentUser', JSON.stringify(info))
  await store.flush()
  return info
}

// 注册：查重与密码加盐哈希都在 auth 云函数完成。
// 医生必须带执业证号（license），注册后处于待审核状态，管理员通过后才能查看患者数据。
export async function register(username: string, password: string, role: string, license: string = ''): Promise<boolean> {
  let res = await cloudFunction.call({
    name: 'auth',
    version: '$latest',
    data: { method: 'register', params: [username, password, role, license] }
  })
  let payload = res.result as Record<string, Object>
  if (!payload) {
    throw new Error('注册失败：云服务无响应')
  }
  if (payload['ok'] !== true) {
    let msg = String(payload['error'])
    if (msg === '用户名已存在') {
      return false
    }
    throw new Error(msg)
  }
  return true
}

// 管理员：待审核医生列表
export async function getPendingDoctors(): Promise<UserInfo[]> {
  try {
    let payload = await authCall('listPendingDoctors', [])
    return recListToUserInfo(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getPendingDoctors err %{public}s', JSON.stringify(e))
    let empty: UserInfo[] = []
    return empty
  }
}

// 管理员：审核医生（pass=true 通过，false 驳回）。返回 ''=成功，其它=错误信息
export async function reviewDoctor(doctorId: number, pass: boolean): Promise<string> {
  try {
    await authCall('reviewDoctor', [doctorId, pass])
    return ''
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'reviewDoctor err %{public}s', JSON.stringify(e))
    return (e as Error).message
  }
}

// 医生：给绑定患者发送随访建议（患者会在「消息」里收到一条【随访建议】）
export async function sendFollowUp(patientId: number, text: string): Promise<void> {
  await authCall('sendFollowUp', [patientId, text])
}

// 管理员：一键生成演示数据（演示账号 + 近 30 天记录 + 预警 + 社区内容 + 一段医患对话）
// 返回云端给的提示文案（账号已存在时会是"未重复生成"）
export async function seedDemoData(): Promise<string> {
  let payload = await authCall('seedDemoData', [])
  return payload['message'] ? String(payload['message']) : '演示数据已生成'
}

// 注册前预检查用户名（不需要登录态）：返回 '' 表示可用，其它字符串是给用户看的原因。
// 预检本身失败（网络/云端异常）时也返回 ''，不把用户挡在门外——真正的裁决仍在服务端 register。
export async function probeUsername(username: string): Promise<string> {
  try {
    let res = await cloudFunction.call({
      name: 'auth',
      version: '$latest',
      data: { method: 'checkUsername', params: [username] }
    })
    let payload = res.result as Record<string, Object>
    if (!payload || payload['ok'] !== true) {
      return ''
    }
    if (payload['available'] === true) {
      return ''
    }
    let reason = payload['reason'] ? String(payload['reason']) : ''
    return reason === '' ? '该用户名已被占用' : reason
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'probeUsername err %{public}s', JSON.stringify(e))
    return ''
  }
}

// 获取当前登录用户（读本地会话缓存，避免每次开页都查云）
export async function getCurrentUser(): Promise<UserInfo | null> {
  let store = await getStore()
  let userJson = await store.get('currentUser', '') as string
  if (userJson) {
    return JSON.parse(userJson) as UserInfo
  }
  return null
}

// 从云端刷新当前用户资料并回写缓存（个人中心进入时以服务端为准，防止本地缓存与云端不同步）
export async function refreshCurrentUser(): Promise<UserInfo | null> {
  let store = await getStore()
  let uid = await store.get('currentUserId', 0) as number
  if (uid === 0) {
    let cached = await getCurrentUser()
    if (cached) {
      uid = cached.userId
    }
  }
  if (uid === 0) {
    return null
  }
  try {
    let payload = await authCall('getUserById', [uid])
    let u = payload['data'] as Record<string, Object>
    if (!u || u['userId'] === undefined) {
      return null
    }
    let info = recToUserInfo(u)
    await store.put('currentUser', JSON.stringify(info))
    await store.flush()
    return info
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'refreshCurrentUser err %{public}s', JSON.stringify(e))
    return null
  }
}

// 更新头像地址（云存储下载地址），返回更新后的用户信息
export async function updateAvatar(url: string): Promise<UserInfo | null> {
  let payload = await authCall('updateAvatar', [url])
  let u = payload['data'] as Record<string, Object>
  if (!u) {
    return null
  }
  let info = recToUserInfo(u)
  let store = await getStore()
  await store.put('currentUser', JSON.stringify(info))
  await store.flush()
  return info
}

// 注销账号：校验密码后由服务端彻底删除该用户的全部数据（健康记录/预警/社区内容/私信），不可恢复。
// 成功后调用方还需清理本地会话并回到登录页。
export async function deleteAccount(password: string): Promise<void> {
  await authCall('deleteAccount', [password])
}

// 退出登录
export async function logout(): Promise<void> {
  let store = await getStore()
  let user = await getCurrentUser()
  await store.delete('token')
  await store.delete('currentUser')
  await store.delete('currentUserId')
  if (user) {
    // 清除本机缓存的 AI 健康报告，避免残留个人健康信息
    await store.delete('aiReport_' + user.userId)
  }
  await store.flush()
}

// 检查是否已登录
export async function isLoggedIn(): Promise<boolean> {
  let store = await getStore()
  let token = await store.get('token', '') as string
  return token !== ''
}

// 更新当前用户个人信息（邮箱/手机/性别/生日）：走云函数 + 刷新本地缓存
// 返回 ''=成功，其它=错误信息（供界面提示定位原因）
export async function updateUserInfo(email: string, phone: string, gender: string, dateOfBirth: string): Promise<string> {
  try {
    let payload = await authCall('updateUserInfo', [email, phone, gender, dateOfBirth])
    let u = payload['data'] as Record<string, Object>
    // 云端 ok:true 但没回传完整用户（云函数版本过旧/字段缺失）时，绝不缓存空数据
    if (!u || u['userId'] === undefined || u['username'] === undefined) {
      hilog.error(HILOG_DOMAIN, TAG, 'updateUserInfo bad payload %{public}s', JSON.stringify(payload))
      return '云端未返回更新后的用户资料（云函数版本可能过旧，请重新部署 auth 云函数）'
    }
    let info = recToUserInfo(u)
    let store = await getStore()
    await store.put('currentUser', JSON.stringify(info))
    await store.flush()
    return ''
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'updateUserInfo err %{public}s', JSON.stringify(e))
    return (e as Error).message
  }
}

// 修改昵称（服务端强制 5 分钟冷却）：返回 ''=成功，其它=错误信息（含 NEED_COOLDOWN）
export async function updateNickname(nickname: string): Promise<string> {
  try {
    let payload = await authCall('updateNickname', [nickname])
    let u = payload['data'] as Record<string, Object>
    if (!u || u['userId'] === undefined || u['username'] === undefined) {
      hilog.error(HILOG_DOMAIN, TAG, 'updateNickname bad payload %{public}s', JSON.stringify(payload))
      return '云端未返回更新后的用户资料（请重新部署 auth 云函数）'
    }
    let info = recToUserInfo(u)
    // 乐观覆盖：不信云端回读（写后读可能延迟返回旧空值），直接用刚发出的昵称 + 当前时间
    info.nickname = nickname
    info.nicknameUpdatedAt = new Date().toISOString()
    let store = await getStore()
    await store.put('currentUser', JSON.stringify(info))
    await store.flush()
    return ''
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'updateNickname err %{public}s', JSON.stringify(e))
    return (e as Error).message
  }
}

// 获取所有医生（供患者选择绑定）
export async function getDoctorList(): Promise<UserInfo[]> {
  try {
    let payload = await authCall('listDoctors', [])
    return recListToUserInfo(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getDoctorList err %{public}s', JSON.stringify(e))
    let empty: UserInfo[] = []
    return empty
  }
}

// 患者绑定/更换医生
export async function bindDoctor(doctorId: number): Promise<boolean> {
  try {
    let payload = await authCall('bindDoctor', [doctorId])
    let u = payload['data'] as Record<string, Object>
    let info = recToUserInfo(u)
    let store = await getStore()
    await store.put('currentUser', JSON.stringify(info))
    await store.flush()
    return true
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'bindDoctor err %{public}s', JSON.stringify(e))
    return false
  }
}

// 获取当前患者绑定的医生
export async function getMyDoctor(): Promise<UserInfo | null> {
  try {
    let payload = await authCall('getMyDoctor', [])
    let u = payload['data'] as Record<string, Object>
    if (!u) {
      return null
    }
    return recToUserInfo(u)
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getMyDoctor err %{public}s', JSON.stringify(e))
    return null
  }
}

// 医生获取绑定到自己的患者
export async function getMyPatients(): Promise<UserInfo[]> {
  try {
    let payload = await authCall('listMyPatients', [])
    return recListToUserInfo(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getMyPatients err %{public}s', JSON.stringify(e))
    let empty: UserInfo[] = []
    return empty
  }
}

// 按医生 ID 获取其名下所有患者（管理员在医生详情页查看某个医生的患者时用）
export async function getPatientsByDoctor(doctorId: number): Promise<UserInfo[]> {
  try {
    let payload = await authCall('listPatientsByDoctor', [doctorId])
    return recListToUserInfo(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getPatientsByDoctor err %{public}s', JSON.stringify(e))
    let empty: UserInfo[] = []
    return empty
  }
}

// 管理员获取所有患者
export async function getAllPatients(): Promise<UserInfo[]> {
  try {
    let payload = await authCall('listAllPatients', [])
    return recListToUserInfo(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getAllPatients err %{public}s', JSON.stringify(e))
    let empty: UserInfo[] = []
    return empty
  }
}

// 医生/管理员首页的患者概览：一次调用拿齐姓名/性别/最近血压/未确认预警数。
// 以前端侧要对每个患者各调两次接口（健康记录 + 预警），患者一多首页就转圈。
export async function getPatientsOverview(): Promise<PatientOverview[]> {
  let out: PatientOverview[] = []
  try {
    let payload = await authCall('patientsOverview', [])
    let arr = payload['data'] as Record<string, Object>[]
    if (!arr) {
      return out
    }
    for (let i = 0; i < arr.length; i++) {
      let r = arr[i]
      let row: PatientOverview = {
        userId: r['userId'] as number,
        name: r['name'] ? String(r['name']) : '',
        gender: r['gender'] ? String(r['gender']) : '其他',
        latestBp: r['latestBp'] ? String(r['latestBp']) : '暂无',
        warnCount: r['warnCount'] ? (r['warnCount'] as number) : 0,
        doctorId: r['doctorId'] ? (r['doctorId'] as number) : 0,
        avatarUrl: r['avatarUrl'] ? String(r['avatarUrl']) : ''
      }
      out.push(row)
    }
    return out
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getPatientsOverview err %{public}s', JSON.stringify(e))
    return out
  }
}

// 按 ID 获取用户（医生查看患者详情用）
export async function getUserById(userId: number): Promise<UserInfo | null> {
  try {
    let payload = await authCall('getUserById', [userId])
    let u = payload['data'] as Record<string, Object>
    if (!u) {
      return null
    }
    return recToUserInfo(u)
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getUserById err %{public}s', JSON.stringify(e))
    return null
  }
}

// ==================== 健康数据块 ====================

// 获取指定用户的健康数据（医生/管理员查看患者记录）
export async function getUserHealthData(userId: number): Promise<HealthData[]> {
  try {
    let payload = await authCall('getUserHealthData', [userId])
    return recListToHealth(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getUserHealthData err %{public}s', JSON.stringify(e))
    let empty: HealthData[] = []
    return empty
  }
}

// 获取当前登录用户的健康数据
export async function getHealthDataList(): Promise<HealthData[]> {
  try {
    let payload = await authCall('listMyHealthData', [])
    return recListToHealth(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getHealthDataList err %{public}s', JSON.stringify(e))
    let empty: HealthData[] = []
    return empty
  }
}

// 添加一条健康数据：写云端 + 服务端阈值预警生成（失败抛出，供页面提示）
export async function addHealthData(
  systolic: number,
  diastolic: number,
  bloodSugar: number,
  heartRate: number,
  weight: number,
  notes: string,
  exerciseType: string,
  exerciseDuration: number,
  exerciseCalories: number
): Promise<HealthData> {
  let payload = await authCall('addHealthData',
    [systolic, diastolic, bloodSugar, heartRate, weight, notes, exerciseType, exerciseDuration, exerciseCalories])
  let d = payload['data'] as Record<string, Object>
  return recToHealth(d)
}

// ==================== 预警块 ====================

// 获取指定用户的预警（医生/管理员查看）
export async function getUserWarnings(userId: number): Promise<HealthWarning[]> {
  try {
    let payload = await authCall('getUserWarnings', [userId])
    return recListToWarning(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getUserWarnings err %{public}s', JSON.stringify(e))
    let empty: HealthWarning[] = []
    return empty
  }
}

// 获取预警列表（当前登录用户）
export async function getWarningList(): Promise<HealthWarning[]> {
  try {
    let payload = await authCall('listMyWarnings', [])
    return recListToWarning(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getWarningList err %{public}s', JSON.stringify(e))
    let empty: HealthWarning[] = []
    return empty
  }
}

// 确认预警
export async function acknowledgeWarning(warningId: number): Promise<void> {
  try {
    await authCall('acknowledgeWarning', [warningId])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'acknowledgeWarning err %{public}s', JSON.stringify(e))
    throw new Error('确认预警失败: ' + JSON.stringify(e))
  }
}

// 获取未确认预警数量
export async function getUnacknowledgedCount(): Promise<number> {
  try {
    let payload = await authCall('unackCount', [])
    return payload['data'] as number
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getUnacknowledgedCount err %{public}s', JSON.stringify(e))
    return 0
  }
}

// ==================== 健康建议（暂无云表，保持本地） ====================

// 健康建议
export async function getAdviceList(): Promise<HealthAdvice[]> {
  let store = await getStore()
  let user = await getCurrentUser()
  if (!user) {
    return []
  }
  let json = await store.get('advice_' + user.userId, '[]') as string
  return JSON.parse(json) as HealthAdvice[]
}

// ==================== AI 结构化健康报告（服务端 DeepSeek 生成） ====================

// 读本地缓存的报告（不触发网络）。无缓存或无登录返回 null。
export async function getCachedReport(): Promise<AiReportCache | null> {
  let store = await getStore()
  let user = await getCurrentUser()
  if (!user) {
    return null
  }
  let json = await store.get('aiReport_' + user.userId, '') as string
  if (json === '') {
    return null
  }
  try {
    return JSON.parse(json) as AiReportCache
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getCachedReport parse err %{public}s', JSON.stringify(e))
    return null
  }
}

// 请求云端生成新报告：验令牌 -> 云函数 -> 归一化 -> 写本地缓存。
// 失败（含 NO_DATA / AI 未配置 / 网络）由 callAuth 抛出，交由页面 catch 处理。
export async function requestReport(): Promise<AiReportCache> {
  let store = await getStore()
  let user = await getCurrentUser()
  if (!user) {
    throw new Error('未登录或登录已过期')
  }

  let payload = await authCall('generateHealthReport', [])

  // 服务端返回 { ok:true, data:{...报告字段}, generatedAt, sampleCount }
  let dataRec = payload['data'] as Record<string, Object>
  let report: AiHealthReport = {
    riskLevel: dataRec['riskLevel'] as string,
    overallAssessment: dataRec['overallAssessment'] as string,
    metrics: dataRec['metrics'] as AiMetricRead[],
    trendAnalysis: dataRec['trendAnalysis'] as string,
    dietAdvice: dataRec['dietAdvice'] as string,
    exerciseAdvice: dataRec['exerciseAdvice'] as string,
    lifestyleAdvice: dataRec['lifestyleAdvice'] as string,
    followUpAdvice: dataRec['followUpAdvice'] as string,
    redFlags: dataRec['redFlags'] as string
  }

  let genAt: string = payload['generatedAt'] ? String(payload['generatedAt']) : new Date().toISOString()
  let cnt: number = payload['sampleCount'] ? Number(payload['sampleCount']) : 0

  let wrap: AiReportCache = { report: report, generatedAt: genAt, sampleCount: cnt }
  await store.put('aiReport_' + user.userId, JSON.stringify(wrap))
  await store.flush()
  return wrap
}

// ==================== 论坛块（Phase ① 纯文字） ====================

function recToForumPost(r: Record<string, Object>): ForumPost {
  let p: ForumPost = {
    postId: r['postId'] as number,
    authorId: r['authorId'] as number,
    authorRole: r['authorRole'] ? (r['authorRole'] as string) : '',
    authorName: r['authorName'] ? (r['authorName'] as string) : '',
    authorAvatar: r['authorAvatar'] ? (r['authorAvatar'] as string) : '',
    title: r['title'] ? (r['title'] as string) : '',
    content: r['content'] ? (r['content'] as string) : '',
    createdAt: r['createdAt'] ? (r['createdAt'] as string) : '',
    likeCount: r['likeCount'] ? (r['likeCount'] as number) : 0,
    commentCount: r['commentCount'] ? (r['commentCount'] as number) : 0,
    status: r['status'] ? (r['status'] as number) : 0,
    likedByMe: r['likedByMe'] ? (r['likedByMe'] as boolean) : false,
    favorited: r['favoritedByMe'] ? (r['favoritedByMe'] as boolean) : false,
    mediaUrls: r['mediaUrls'] ? (r['mediaUrls'] as string) : '[]',
    dept: r['dept'] ? (r['dept'] as string) : '',
    topics: r['topics'] ? (r['topics'] as string) : '[]'
  }
  return p
}

function recListToForumPost(v: Object): ForumPost[] {
  let out: ForumPost[] = []
  if (!v) {
    return out
  }
  let arr = v as Record<string, Object>[]
  for (let i = 0; i < arr.length; i++) {
    out.push(recToForumPost(arr[i]))
  }
  return out
}

function recToForumComment(r: Record<string, Object>): ForumComment {
  let c: ForumComment = {
    commentId: r['commentId'] as number,
    postId: r['postId'] as number,
    authorId: r['authorId'] as number,
    authorRole: r['authorRole'] ? (r['authorRole'] as string) : '',
    authorName: r['authorName'] ? (r['authorName'] as string) : '',
    authorAvatar: r['authorAvatar'] ? (r['authorAvatar'] as string) : '',
    content: r['content'] ? (r['content'] as string) : '',
    createdAt: r['createdAt'] ? (r['createdAt'] as string) : '',
    status: r['status'] ? (r['status'] as number) : 0,
    parentId: r['parentId'] ? (r['parentId'] as number) : 0,
    mediaUrls: r['mediaUrls'] ? (r['mediaUrls'] as string) : '[]'
  }
  return c
}

function recListToForumComment(v: Object): ForumComment[] {
  let out: ForumComment[] = []
  if (!v) {
    return out
  }
  let arr = v as Record<string, Object>[]
  for (let i = 0; i < arr.length; i++) {
    out.push(recToForumComment(arr[i]))
  }
  return out
}

// 帖子列表（患者/医生视角，只含未删除）。可选按病种/话题标签筛选。失败返回空列表，页面显示"暂无帖子"。
export async function listForumPosts(page: number, dept: string, topic: string): Promise<ForumPostPage> {
  let empty: ForumPostPage = { posts: [], hasMore: false }
  try {
    let payload = await authCall('listPosts', [page, dept, topic])
    let result: ForumPostPage = {
      posts: recListToForumPost(payload['data']),
      hasMore: payload['hasMore'] ? (payload['hasMore'] as boolean) : false
    }
    return result
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'listForumPosts err %{public}s', JSON.stringify(e))
    return empty
  }
}

// 搜索帖子：按关键词在标题/正文里匹配（服务端不区分大小写）。失败返回空列表。
export async function searchForumPosts(keyword: string, page: number): Promise<ForumPostPage> {
  let empty: ForumPostPage = { posts: [], hasMore: false }
  try {
    let payload = await authCall('searchPosts', [keyword, page])
    let result: ForumPostPage = {
      posts: recListToForumPost(payload['data']),
      hasMore: payload['hasMore'] ? (payload['hasMore'] as boolean) : false
    }
    return result
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'searchForumPosts err %{public}s', JSON.stringify(e))
    return empty
  }
}

// 管理员：查看全部帖子（含已删除），失败返回空
export async function adminListForumPosts(page: number): Promise<ForumPostPage> {
  let empty: ForumPostPage = { posts: [], hasMore: false }
  try {
    let payload = await authCall('adminListPosts', [page])
    let result: ForumPostPage = {
      posts: recListToForumPost(payload['data']),
      hasMore: payload['hasMore'] ? (payload['hasMore'] as boolean) : false
    }
    return result
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'adminListForumPosts err %{public}s', JSON.stringify(e))
    return empty
  }
}

// 帖子详情：失败/无权返回 null
export async function getForumPostDetail(postId: number): Promise<ForumPost | null> {
  try {
    let payload = await authCall('getPost', [postId])
    let d = payload['data'] as Record<string, Object>
    if (!d || d['postId'] === undefined) {
      return null
    }
    return recToForumPost(d)
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getForumPostDetail err %{public}s', JSON.stringify(e))
    return null
  }
}

// 发帖：命中敏感词/处于禁言时，服务端友好文案由 callAuth 抛出，交由页面 catch 显示
export async function createForumPost(title: string, content: string, mediaUrls: string[], dept: string, topics: string[], mentionIds: number[]): Promise<ForumPost> {
  let urls: string[] = mediaUrls === undefined ? [] : mediaUrls
  let tops: string[] = topics === undefined ? [] : topics
  let dp: string = dept === undefined ? '' : dept
  let mids: number[] = mentionIds === undefined ? [] : mentionIds
  let payload = await authCall('createPost', [title, content, JSON.stringify(urls), dp, JSON.stringify(tops), JSON.stringify(mids)])
  let d = payload['data'] as Record<string, Object>
  return recToForumPost(d)
}

// 删除帖子（软删）
export async function deleteForumPost(postId: number): Promise<void> {
  await authCall('deletePost', [postId])
}

// 评论列表
export async function listForumComments(postId: number): Promise<ForumComment[]> {
  try {
    let payload = await authCall('listComments', [postId])
    return recListToForumComment(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'listForumComments err %{public}s', JSON.stringify(e))
    let empty: ForumComment[] = []
    return empty
  }
}

// 发评论/回复：parentId=0 为评论，>0 为回复该评论；mediaUrls 为图片地址列表（可选）
export async function addForumComment(postId: number, content: string, parentId: number, mediaUrls: string[], mentionIds: number[]): Promise<ForumComment> {
  let urls: string[] = mediaUrls === undefined ? [] : mediaUrls
  let mids: number[] = mentionIds === undefined ? [] : mentionIds
  let payload = await authCall('addComment', [postId, content, parentId, JSON.stringify(urls), JSON.stringify(mids)])
  let d = payload['data'] as Record<string, Object>
  return recToForumComment(d)
}

// 删除评论（软删）
export async function deleteForumComment(commentId: number): Promise<void> {
  await authCall('deleteComment', [commentId])
}

// 点赞/取消：返回最新 liked + likeCount
export async function toggleForumLike(postId: number): Promise<ForumLikeResult> {
  let payload = await authCall('toggleLike', [postId])
  let r: ForumLikeResult = {
    liked: payload['liked'] ? (payload['liked'] as boolean) : false,
    likeCount: payload['likeCount'] ? (payload['likeCount'] as number) : 0
  }
  return r
}

// 收藏/取消收藏：返回最新收藏态（异常由页面捕获提示，和点赞同理）
export async function toggleForumFavorite(postId: number): Promise<boolean> {
  let payload = await authCall('toggleFavorite', [postId])
  return payload['favorited'] ? (payload['favorited'] as boolean) : false
}

// 我的收藏列表：失败返回空
export async function listForumFavorites(page: number): Promise<ForumPostPage> {
  let empty: ForumPostPage = { posts: [], hasMore: false }
  try {
    let payload = await authCall('listFavorites', [page])
    let result: ForumPostPage = {
      posts: recListToForumPost(payload['data']),
      hasMore: payload['hasMore'] ? (payload['hasMore'] as boolean) : false
    }
    return result
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'listForumFavorites err %{public}s', JSON.stringify(e))
    return empty
  }
}

// 我发布的帖子：失败返回空
export async function listMyForumPosts(page: number): Promise<ForumPostPage> {
  let empty: ForumPostPage = { posts: [], hasMore: false }
  try {
    let payload = await authCall('listMyPosts', [page])
    let result: ForumPostPage = {
      posts: recListToForumPost(payload['data']),
      hasMore: payload['hasMore'] ? (payload['hasMore'] as boolean) : false
    }
    return result
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'listMyForumPosts err %{public}s', JSON.stringify(e))
    return empty
  }
}

// 我的违规/禁言状态，供论坛页顶部提示条
export async function getMyForumViolation(): Promise<ForumViolationStatus> {
  let empty: ForumViolationStatus = { violationCount: 0, muted: false, muteRemainText: '' }
  try {
    let payload = await authCall('myViolation', [])
    let d = payload['data'] as Record<string, Object>
    if (!d) {
      return empty
    }
    let s: ForumViolationStatus = {
      violationCount: d['violationCount'] ? (d['violationCount'] as number) : 0,
      muted: d['muted'] ? (d['muted'] as boolean) : false,
      muteRemainText: d['muteRemainText'] ? (d['muteRemainText'] as string) : ''
    }
    return s
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getMyForumViolation err %{public}s', JSON.stringify(e))
    return empty
  }
}

// 论坛用户公开简介：点开头像弹出的详情卡片，失败返回 null
export async function getForumUserBrief(userId: number): Promise<ForumUserBrief | null> {
  try {
    let payload = await authCall('getUserBrief', [userId])
    let d = payload['data'] as Record<string, Object>
    if (!d) {
      return null
    }
    let b: ForumUserBrief = {
      userId: d['userId'] ? (d['userId'] as number) : userId,
      nickname: d['nickname'] ? (d['nickname'] as string) : ('用户' + userId),
      role: d['role'] ? (d['role'] as string) : 'patient',
      genderText: d['genderText'] ? (d['genderText'] as string) : '未填写',
      createdAt: d['createdAt'] ? (d['createdAt'] as string) : '',
      postCount: d['postCount'] ? (d['postCount'] as number) : 0,
      likeTotal: d['likeTotal'] ? (d['likeTotal'] as number) : 0,
      doctorLicense: d['doctorLicense'] ? (d['doctorLicense'] as string) : '',
      avatarUrl: d['avatarUrl'] ? (d['avatarUrl'] as string) : ''
    }
    return b
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getForumUserBrief err %{public}s', JSON.stringify(e))
    return null
  }
}

// ==================== 私信：记录 -> 本地对象 映射 ====================
function recToDmConversation(r: Record<string, Object>): DmConversation {
  let c: DmConversation = {
    pairId: r['pairId'] as string,
    peerId: r['peerId'] as number,
    peerName: r['peerName'] ? (r['peerName'] as string) : '',
    peerAvatar: r['peerAvatar'] ? (r['peerAvatar'] as string) : '',
    lastMessage: r['lastMessage'] ? (r['lastMessage'] as string) : '',
    lastSenderId: r['lastSenderId'] ? (r['lastSenderId'] as number) : 0,
    lastCreatedAt: r['lastCreatedAt'] ? (r['lastCreatedAt'] as string) : '',
    unread: r['unread'] ? (r['unread'] as number) : 0,
    status: r['status'] ? (r['status'] as number) : 0
  }
  return c
}

function recListToDmConversation(v: Object): DmConversation[] {
  let out: DmConversation[] = []
  if (!v) {
    return out
  }
  let arr = v as Record<string, Object>[]
  for (let i = 0; i < arr.length; i++) {
    out.push(recToDmConversation(arr[i]))
  }
  return out
}

function recToDmMessage(r: Record<string, Object>): DmMessage {
  let m: DmMessage = {
    messageId: r['messageId'] as number,
    pairId: r['pairId'] as string,
    senderId: r['senderId'] as number,
    receiverId: r['receiverId'] as number,
    content: r['content'] ? (r['content'] as string) : '',
    createdAt: r['createdAt'] ? (r['createdAt'] as string) : '',
    readFlag: r['readFlag'] ? (r['readFlag'] as number) : 0,
    status: r['status'] ? (r['status'] as number) : 0,
    mediaUrls: r['mediaUrls'] ? (r['mediaUrls'] as string) : '[]'
  }
  return m
}

function recListToDmMessage(v: Object): DmMessage[] {
  let out: DmMessage[] = []
  if (!v) {
    return out
  }
  let arr = v as Record<string, Object>[]
  for (let i = 0; i < arr.length; i++) {
    out.push(recToDmMessage(arr[i]))
  }
  return out
}

// 我的会话列表：失败返回空，页面显示"暂无消息"
export async function listMyConversations(): Promise<DmConversation[]> {
  try {
    let payload = await authCall('listMyConversations', [])
    return recListToDmConversation(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'listMyConversations err %{public}s', JSON.stringify(e))
    let empty: DmConversation[] = []
    return empty
  }
}

// 某会话历史消息（按时间正序）：失败返回空。
// afterIso 非空时只拉该时间之后的新消息，供聊天页增量轮询使用（不必每 4 秒整表重传）。
export async function listDmMessages(pairId: string, afterIso: string = ''): Promise<DmMessage[]> {
  try {
    let payload = afterIso === ''
      ? await authCall('listMessages', [pairId])
      : await authCall('listMessages', [pairId, afterIso])
    return recListToDmMessage(payload['data'])
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'listDmMessages err %{public}s', JSON.stringify(e))
    let empty: DmMessage[] = []
    return empty
  }
}

// 发送私信：可携带图片与引用某条消息；命中敏感词/禁言/无权等文案由 callAuth 抛出，交由页面 catch 显示
export async function sendDmMessage(toUserId: number, content: string, mediaUrls: string[], quoteId: number): Promise<DmMessage> {
  let urls: string[] = mediaUrls === undefined ? [] : mediaUrls
  let qid: number = quoteId === undefined ? 0 : quoteId
  let payload = await authCall('sendMessage', [toUserId, content, JSON.stringify(urls), qid])
  let d = payload['data'] as Record<string, Object>
  return recToDmMessage(d)
}

// 删除单条私信（软删，双方都不再可见）
export async function deleteDmMessage(messageId: number): Promise<void> {
  await authCall('deleteMessage', [messageId])
}

// 清空与某人整个会话：所有消息软删 + 会话从列表移除（双方）
export async function clearDmConversation(pairId: string): Promise<void> {
  await authCall('clearConversation', [pairId])
}

// 站内转发某条私信给选中的人，返回成功转发人数
export async function shareDmMessage(messageId: number, targetIds: number[]): Promise<number> {
  let ids: number[] = targetIds === undefined ? [] : targetIds
  let payload = await authCall('shareMessage', [messageId, JSON.stringify(ids)])
  let d = payload['data'] as Record<string, Object>
  if (d === null || d === undefined) { return 0 }
  let n = d['shared']
  return (typeof n === 'number') ? n : 0
}

// 站内分享帖子：把某帖以私信转发给选中的人，返回成功转发的人数；失败文案由 callAuth 抛出
export async function shareForumPost(postId: number, targetIds: number[]): Promise<number> {
  let ids: number[] = targetIds === undefined ? [] : targetIds
  let payload = await authCall('sharePost', [postId, JSON.stringify(ids)])
  let d = payload['data'] as Record<string, Object>
  if (d === null || d === undefined) { return 0 }
  let n = d['shared']
  return (typeof n === 'number') ? n : 0
}

// 标记会话已读（进入聊天页/收到新消息时调用）
export async function markDmRead(pairId: string): Promise<void> {
  await authCall('markConversationRead', [pairId])
}

// 未读总数：供"消息"tab 红点；失败返回 0
export async function getDmUnreadTotal(): Promise<number> {
  try {
    let payload = await authCall('unreadTotal', [])
    return payload['data'] ? (payload['data'] as number) : 0
  } catch (e) {
    hilog.error(HILOG_DOMAIN, TAG, 'getDmUnreadTotal err %{public}s', JSON.stringify(e))
    return 0
  }
}
