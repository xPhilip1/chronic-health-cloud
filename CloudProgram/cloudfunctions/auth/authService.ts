import { AGCClient, CredentialParser } from '@agconnect/common-server';
import { cloud, CloudDBZoneObjectOperator, CloudDBZoneObjectOperatorConstraint } from '@hw-agconnect/cloud-server';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { User } from './model/User';
import { HealthData } from './model/HealthData';
import { HealthWarning } from './model/HealthWarning';
import { ForumPost } from './model/ForumPost';
import { ForumComment } from './model/ForumComment';
import { ForumLike } from './model/ForumLike';
import { ForumFavorite } from './model/ForumFavorite';
import { ForumViolation } from './model/ForumViolation';
import { ForumConversation } from './model/ForumConversation';
import { ForumPrivateMessage } from './model/ForumPrivateMessage';
import { matchSensitive, muteSecondsFor, formatMute } from './model/sensitive';
import { getServerCredJson } from './model/servercred';
import { signToken, verifyToken, TokenPayload } from './model/token';
import * as crypto from 'crypto';
import * as https from 'https';
import { getApiKey, DEEPSEEK_HOST, DEEPSEEK_PATH, DEEPSEEK_MODEL, DEEPSEEK_TIMEOUT_MS } from './model/aiConfig';

const ZONE_NAME = 'Chronic';
// PBKDF2 迭代次数：越慢越抗暴力破解，10 万次是常见下限
const PBKDF2_ITER = 100000;
// 哈希存储格式前缀，用来区分"新哈希"和"存量明文"
const PREFIX = 'pbkdf2$';

// 论坛分页每页条数与文本长度上限
const FORUM_PAGE_SIZE = 20;
// 搜索时最多扫描的最新帖子条数（CloudDB 无全文索引，只能拉回内存匹配，用窗口兜住上限）
const SEARCH_SCAN_LIMIT = 500;
// 单用户健康数据列表一次最多返回的条数（趋势图与列表都按时间倒序取最近这些）
const HEALTH_PAGE_LIMIT = 1000;
// AI 报告：命中同一用户的服务端缓存有效时长；以及强制重新生成的最小间隔（防刷 DeepSeek）
const AI_REPORT_CACHE_MS = 30 * 60 * 1000;
const AI_REPORT_COOLDOWN_MS = 30 * 1000;
const TITLE_MAX = 50;
const POST_CONTENT_MAX = 2000;
const COMMENT_MAX = 500;
// 单帖最多携带的图片数（云存储地址）
const MAX_MEDIA_PER_POST = 3;
// 单帖最多话题标签数（科室单选 + 话题多选，合计≤3）
const MAX_TOPIC_PER_POST = 2;
// 私信正文长度上限与列表预览摘要截断长度
const DM_CONTENT_MAX = 500;
const DM_PREVIEW_MAX = 40;
// 单条私信最多携带的图片数（纯图/图文皆可，无文字时用 [图片] 作预览）
const DM_MAX_MEDIA = 9;
// 一条评论/帖子最多能 @ 多少人（防刷），以及通知私信里携带的原文摘要长度
const MAX_MENTION = 10;
const MENTION_SNIPPET_MAX = 40;

// 允许自助注册的角色白名单。管理员不开放注册——否则任何人都能自助拿到最高权限，
// 管理员账号只能在 AGC 控制台手工把某个账号的 role 改成 admin。
const SELF_REGISTER_ROLES: string[] = ['patient', 'doctor'];
// 账号 / 密码长度约束
const USERNAME_MIN = 3;
const USERNAME_MAX = 20;
const PASSWORD_MIN = 6;
const PASSWORD_MAX = 64;
// 昵称 / 备注 / 标签长度约束
const NICKNAME_MAX = 20;
const NOTES_MAX = 200;
const TAG_MAX = 20;
// 健康数据合理区间（0 一律视为"未填写"跳过校验）。
// 目的是挡住负数、明显笔误和乱填的值，避免脏数据污染趋势图与 AI 报告。
const RANGE_SYSTOLIC: number[] = [40, 300];
const RANGE_DIASTOLIC: number[] = [20, 200];
const RANGE_SUGAR: number[] = [0.5, 50];
const RANGE_HEART_RATE: number[] = [20, 250];
const RANGE_WEIGHT: number[] = [20, 400];
const RANGE_EXERCISE_MIN: number[] = [0, 1440];
const RANGE_CALORIES: number[] = [0, 5000];

// 演示数据账号（仅管理员可一键生成；正式上线前请删除这三个常量与 seedDemoData）
const DEMO_PATIENT_USER = 'demo_patient';
const DEMO_DOCTOR_USER = 'demo_doctor';
const DEMO_PASSWORD = 'demo123456';
const DEMO_DOCTOR_LICENSE = 'DEMO-2026-0001';

let userCollection: any = null;
let healthCollection: any = null;
let warningCollection: any = null;
let forumPostCollection: any = null;
let forumCommentCollection: any = null;
let forumLikeCollection: any = null;
let forumFavoriteCollection: any = null;
let forumViolationCollection: any = null;
let forumConversationCollection: any = null;
let forumPrivateMessageCollection: any = null;
let dbReady = false;

// AI 报告缓存（按 userId）+ 上次调用时间（限流用）。
// 存在云函数进程内存里，实例回收即失效——属于"尽力而为"的缓存，但足以挡住
// "每次进页面都重新生成""连点重新生成"这类浪费 DeepSeek 额度的行为。
interface AiReportCacheEntry {
  at: number;
  data: Record<string, Object>;
  generatedAt: string;
  sampleCount: number;
}
const aiReportCache: Record<number, AiReportCacheEntry> = {};
const aiReportLastCall: Record<number, number> = {};

// 加盐哈希：每个用户独立随机 salt，格式 pbkdf2$迭代$盐hex$哈希hex
function hashPassword(password: string): string {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(password, salt, PBKDF2_ITER, 32, 'sha256').toString('hex');
  return PREFIX + PBKDF2_ITER + '$' + salt + '$' + hash;
}

// 校验密码：哈希格式走 PBKDF2 常数时间比较；存量明文走直接比较（仅迁移期）
function verifyPassword(password: string, stored: string): boolean {
  if (stored.indexOf(PREFIX) !== 0) {
    return stored === password;
  }
  const parts = stored.split('$');
  if (parts.length !== 4) { return false; }
  const iter = parseInt(parts[1], 10);
  const salt = parts[2];
  const expect = parts[3];
  const actual = crypto.pbkdf2Sync(password, salt, iter, 32, 'sha256').toString('hex');
  const a = Buffer.from(actual, 'hex');
  const b = Buffer.from(expect, 'hex');
  if (a.length !== b.length) { return false; }
  return crypto.timingSafeEqual(a, b);
}

function isLegacyPlain(stored: string): boolean {
  return stored.indexOf(PREFIX) !== 0;
}

// 初始化并缓存三张集合（内嵌服务端凭证写临时文件再解析）
async function ensureDb(): Promise<void> {
  if (dbReady) { return; }
  const tmpPath = path.join(os.tmpdir(), 'agconnect-services.json');
  fs.writeFileSync(tmpPath, getServerCredJson(), 'utf8');
  const credential = CredentialParser.toCredential(tmpPath);
  AGCClient.initialize(credential);
  const db = cloud.database({ zoneName: ZONE_NAME });
  userCollection = db.collection(User);
  healthCollection = db.collection(HealthData);
  warningCollection = db.collection(HealthWarning);
  forumPostCollection = db.collection(ForumPost);
  forumCommentCollection = db.collection(ForumComment);
  forumLikeCollection = db.collection(ForumLike);
  forumFavoriteCollection = db.collection(ForumFavorite);
  forumViolationCollection = db.collection(ForumViolation);
  forumConversationCollection = db.collection(ForumConversation);
  forumPrivateMessageCollection = db.collection(ForumPrivateMessage);
  dbReady = true;
}

// 查询结果归一化为数组（不同版本 SDK 返回快照或数组两种形态）
function toList(result: any): any[] {
  if (Array.isArray(result)) { return result; }
  if (result && typeof result.getSnapshotObjects === 'function') { return result.getSnapshotObjects() || []; }
  if (result && Array.isArray(result.values)) { return result.values; }
  return [];
}

// 云数据库 Integer 为 32 位有符号（上限 2147483647），毫秒时间戳会溢出，故用「秒级 + 随机段」。
// 随机段有个隐患：同一次调用里连续生成多枚 id（一次录入触发多条预警、一次 @ 多人写多条通知私信）
// 有概率撞在一起，而 upsert 撞主键是静默覆盖、不报错。所以这里再加一道「同实例内单调递增」：
// 任何后取的 id 一定大于前一枚，循环里批量插入就绝不会自撞。
// 残留风险：两个云函数实例在同一秒取到同一随机值时仍可能撞号（约 1/10 万量级）。
// 根治要把主键换成字符串/UUID，属于改表范畴，且旧数据需要迁移，暂不在本轮动。
const ID_RANDOM_SPAN = 100000;
const ID_MAX = 2147483647;
let lastIssuedId = 0;

function newId(): number {
  const sec = Math.floor(Date.now() / 1000);
  let id = sec + Math.floor(Math.random() * ID_RANDOM_SPAN);
  if (id <= lastIssuedId) {
    id = lastIssuedId + 1;
  }
  if (id > ID_MAX) {
    id = sec;
  }
  lastIssuedId = id;
  return id;
}

// 数值是否落在合理区间（0 表示"未填写"，直接放行）
function within(value: number, range: number[]): boolean {
  if (!value || value === 0) { return true; }
  return value >= range[0] && value <= range[1];
}

// 任意入参转成有限数字，非法值一律当 0（"未填写"）处理
function toNum(v: any): number {
  const n = Number(v);
  return isFinite(n) ? n : 0;
}

// 局部字段更新：只提交 fields 里的字段，不整行覆盖。
// 为什么不用 upsert：upsert 会把对象上的所有属性（含没打算改的默认值 '' / 0）一起写回，
// 既容易误伤其它字段（例如保存资料时把昵称一并写成空），也依赖服务端是否做字段合并。
// 这里用 SDK 的 CloudDBZoneObjectOperator 按主键只更新目标字段，语义是确定的。
async function updateFields(
  collection: any,
  clazz: new () => any,
  pk: Record<string, any>,
  fields: Record<string, any>
): Promise<void> {
  const inst: any = new clazz();
  const pkKeys = Object.keys(pk);
  for (let i = 0; i < pkKeys.length; i++) {
    inst[pkKeys[i]] = pk[pkKeys[i]];
  }
  const op = CloudDBZoneObjectOperator.build(inst);
  const fk = Object.keys(fields);
  for (let j = 0; j < fk.length; j++) {
    op.update(fk[j], fields[fk[j]]);
  }
  await collection.update(op);
}

// 角色是否合法（防止端侧伪造 role 字段提权）
function isValidRole(role: string): boolean {
  return role === 'patient' || role === 'doctor' || role === 'admin';
}

// 按条件批量删除；失败只记日志不抛出——
// 注销是"尽力清空"，某个表删失败不应该让整个账号卡在中间状态。
async function batchDeleteSafe(collection: any, constraint: any, label: string): Promise<void> {
  try {
    await collection.batchDeleteByCondition(constraint);
  } catch (e) {
    console.warn('[deleteAccount] ' + label + ' failed: ' + String((e as Error).message || e));
  }
}

// 把 id 数组切成若干块（in 条件单次最多 100 项）
function chunkIds(ids: number[], size: number): number[][] {
  const out: number[][] = [];
  for (let i = 0; i < ids.length; i += size) {
    out.push(ids.slice(i, i + size));
  }
  return out;
}

// 演示账号去重：同名多条时只保留 userId 最小（最早注册）的一条，其余删除。
// 删医生前先把其名下患者转到保留的那条，避免患者被挂空；
// 删患者时顺带清掉其健康记录，避免留下孤儿数据。
async function dedupeDemoAccount(username: string, isDoctor: boolean): Promise<User | null> {
  const res = await userCollection.query().equalTo('username', username).get();
  const rows = toList(res) as User[];
  if (rows.length === 0) { return null; }
  rows.sort((a: User, b: User) => a.userId - b.userId);
  const keeper = rows[0];
  for (let i = 1; i < rows.length; i++) {
    const extra = rows[i];
    try {
      if (isDoctor) {
        const pres = await userCollection.query().equalTo('doctorId', extra.userId).get();
        for (const pt of toList(pres) as User[]) {
          await updateFields(userCollection, User, { userId: pt.userId }, { doctorId: keeper.userId });
        }
      } else {
        await batchDeleteSafe(healthCollection,
          CloudDBZoneObjectOperatorConstraint.build(HealthData).equalTo('userId', extra.userId), 'dup health');
      }
      await userCollection.delete(extra);
      console.warn('[seed] removed duplicate demo account username=' + username + ' userId=' + extra.userId);
    } catch (e) {
      console.warn('[seed] dedupe failed username=' + username + ': ' + String((e as Error).message || e));
    }
  }
  return keeper;
}

// 清洗图片地址：解析 JSON 数组字符串，只留非空字符串并按上限截断；异常一律返回空数组
function sanitizeMediaUrls(raw: string): string[] {
  if (!raw) { return []; }
  let arr: Object;
  try {
    arr = JSON.parse(raw);
  } catch (e) { return []; }
  if (!Array.isArray(arr)) { return []; }
  const out: string[] = [];
  for (let i = 0; i < arr.length && out.length < MAX_MEDIA_PER_POST; i++) {
    const v = arr[i];
    if (typeof v === 'string') {
      const s = v.trim();
      if (s !== '') { out.push(s); }
    }
  }
  return out;
}

// 清洗话题标签：解析 JSON 数组，去重、剔空、按上限截断；异常一律返回空数组
function sanitizeTopics(raw: string): string[] {
  if (!raw) { return []; }
  let arr: Object;
  try {
    arr = JSON.parse(raw);
  } catch (e) { return []; }
  if (!Array.isArray(arr)) { return []; }
  const out: string[] = [];
  for (let i = 0; i < arr.length && out.length < MAX_TOPIC_PER_POST; i++) {
    const v = arr[i];
    if (typeof v === 'string') {
      const s = v.trim();
      if (s !== '' && out.indexOf(s) < 0) { out.push(s); }
    }
  }
  return out;
}

// 清洗被 @ 的用户 id 列表：解析 JSON 数组，只留正整数、去重、限量；异常返回空数组
function sanitizeMentionIds(raw: string): number[] {
  if (!raw) { return []; }
  let arr: Object;
  try {
    arr = JSON.parse(raw);
  } catch (e) { return []; }
  if (!Array.isArray(arr)) { return []; }
  const out: number[] = [];
  for (let i = 0; i < arr.length && out.length < MAX_MENTION; i++) {
    const v = arr[i];
    if (typeof v === 'number' && isFinite(v) && v > 0) {
      const id = Math.floor(v);
      if (id > 0 && out.indexOf(id) < 0) { out.push(id); }
    }
  }
  return out;
}

// ===== 医生资质审核状态 =====
// 权威状态存放在 User.doctorStatus（pending / approved / rejected）。
// 兼容两件事：
//   1) 该列需要在 AGC 控制台给已存在的表手工添加；列还没建时，写入会自动降级为
//      "doctorLicense 前缀"方案，避免整个注册/审核流程直接失败；
//   2) 早期版本用前缀写入的数据（PENDING|证号 / REJECTED|证号）仍然能被正确识别。
// 读取顺序：doctorStatus 非空就用它，否则解析证号前缀。
const LICENSE_PENDING = 'PENDING|';
const LICENSE_REJECTED = 'REJECTED|';
const DOCTOR_STATES: string[] = ['pending', 'approved', 'rejected'];

// 'pending' | 'rejected' | 'approved'
function licenseState(u: User): string {
  const s = (u.doctorStatus || '').trim();
  if (DOCTOR_STATES.indexOf(s) >= 0) { return s; }
  // 兜底：解析证号前缀（兼容列未建的历史数据）
  const lic = u.doctorLicense || '';
  if (lic.indexOf(LICENSE_PENDING) === 0) { return 'pending'; }
  if (lic.indexOf(LICENSE_REJECTED) === 0) { return 'rejected'; }
  return 'approved';
}

// 去掉状态前缀后的真实证号
function rawLicense(u: User): string {
  const s = u.doctorLicense || '';
  if (s.indexOf(LICENSE_PENDING) === 0) { return s.substring(LICENSE_PENDING.length); }
  if (s.indexOf(LICENSE_REJECTED) === 0) { return s.substring(LICENSE_REJECTED.length); }
  return s;
}

// 医生是否处于"已通过审核"的可用状态（非医生一律返回 false）
function isDoctorActive(u: User | null): boolean {
  if (!u || u.role !== 'doctor') { return false; }
  return licenseState(u) === 'approved';
}

// 新建用户：先尝试带 doctorStatus 写入；若云端还没有该列（未知字段导致失败），
// 就丢掉该字段重试一次，状态由 doctorLicense 前缀承载。
// fallbackStatus 只在"列不存在"时使用：register 传 'pending'，造数传 'approved'。
async function insertUserRow(row: User, licensePlain: string, fallbackStatus: string): Promise<void> {
  try {
    await userCollection.insert(row);
    return;
  } catch (e) {
    if ((row as any).doctorStatus === undefined && (row as any).avatarUrl === undefined) { throw e; }
    console.warn('[register] new column missing, fallback without optional fields: ' + String((e as Error).message || e));
    // 云端可能还没加 doctorStatus / avatarUrl 列：先都去掉再试一次，状态退回证号前缀方案
    if ((row as any).doctorStatus !== undefined) {
      (row as any).doctorStatus = undefined;
    }
    if ((row as any).avatarUrl !== undefined) {
      (row as any).avatarUrl = undefined;
    }
    if (row.role === 'doctor' && licensePlain !== '') {
      row.doctorLicense = fallbackStatus === 'pending'
        ? (LICENSE_PENDING + licensePlain)
        : (fallbackStatus === 'rejected' ? (LICENSE_REJECTED + licensePlain) : licensePlain);
    }
    await userCollection.insert(row);
  }
}

// 返回给端侧的用户对象：剔除 password 字段
// role 兜底：库里若存了空串/脏值，统一按 patient 返回，避免端侧三态视图落进空分支
function toPublicUser(u: User): Record<string, Object> {
  return {
    userId: u.userId,
    username: u.username,
    email: u.email,
    phone: u.phone,
    gender: u.gender,
    role: isValidRole(u.role) ? u.role : 'patient',
    dateOfBirth: u.dateOfBirth,
    doctorLicense: rawLicense(u),
    doctorStatus: u.role === 'doctor' ? licenseState(u) : '',
    avatarUrl: u.avatarUrl === undefined || u.avatarUrl === null ? '' : u.avatarUrl,
    doctorId: u.doctorId,
    createdAt: u.createdAt,
    nickname: u.nickname,
    nicknameUpdatedAt: u.nicknameUpdatedAt
  };
}

function toPublicHealth(h: HealthData): Record<string, Object> {
  return {
    dataId: h.dataId,
    userId: h.userId,
    bloodPressureSystolic: h.bloodPressureSystolic,
    bloodPressureDiastolic: h.bloodPressureDiastolic,
    bloodSugar: h.bloodSugar,
    weight: h.weight,
    heartRate: h.heartRate,
    exerciseType: h.exerciseType,
    exerciseDuration: h.exerciseDuration,
    exerciseCalories: h.exerciseCalories,
    recordTime: h.recordTime,
    dataSource: h.dataSource,
    notes: h.notes
  };
}

function toPublicWarning(w: HealthWarning): Record<string, Object> {
  return {
    warningId: w.warningId,
    userId: w.userId,
    warningType: w.warningType,
    warningMessage: w.warningMessage,
    warningTime: w.warningTime,
    acknowledged: w.acknowledged,
    severity: w.severity
  };
}

// 某个用户的健康记录（按记录时间倒序，最多 HEALTH_PAGE_LIMIT 条）
// 快路径走服务端分页；缺索引时退回全量再排序。
async function loadHealthRows(userId: number): Promise<HealthData[]> {
  const paged = await pagedSlice(
    healthCollection.query().equalTo('userId', userId).orderByDesc('recordTime').limit(HEALTH_PAGE_LIMIT, 0),
    HEALTH_PAGE_LIMIT);
  if (paged !== null) {
    return paged.rows as HealthData[];
  }
  const res = await healthCollection.query().equalTo('userId', userId).get();
  return sortByTimeDesc(toList(res), 'recordTime') as HealthData[];
}

// 某个会话里"谁还没读"的真实条数（未读数以子表行数为权威，不再靠 +1 自增，避免并发漂移）
async function unreadCountFor(pairId: string, receiverId: number): Promise<number> {
  const res = await forumPrivateMessageCollection.query()
    .equalTo('pairId', pairId)
    .equalTo('receiverId', receiverId)
    .equalTo('readFlag', 0)
    .equalTo('status', 0)
    .get();
  return toList(res).length;
}

// 写完一条消息后维护会话摘要与未读。
// 未读取"接收方未读消息行数"（权威值），不再用 +1 自增——并发发消息时自增会漂移，
// 出现"明明看完了还挂着 3 个红点"这类问题。
async function touchConversation(
  pairId: string, lo: number, hi: number, senderId: number, preview: string): Promise<void> {
  const nowIso = new Date().toISOString();
  const cres = await forumConversationCollection.query().equalTo('pairId', pairId).get();
  const crows = toList(cres);
  const conv = crows.length > 0 ? (crows[0] as ForumConversation) : null;
  const receiver = senderId === lo ? hi : lo;
  const unreadReceiver = await unreadCountFor(pairId, receiver);

  if (conv === null) {
    // 首次对话：会话行还不存在，必须 insert
    const row = new ForumConversation();
    row.pairId = pairId;
    row.userId1 = lo;
    row.userId2 = hi;
    row.lastMessage = preview;
    row.lastSenderId = senderId;
    row.lastCreatedAt = nowIso;
    row.createdAt = nowIso;
    row.unreadForUser1 = receiver === lo ? unreadReceiver : 0;
    row.unreadForUser2 = receiver === hi ? unreadReceiver : 0;
    row.status = 0;
    await forumConversationCollection.insert(row);
    return;
  }

  // 已存在：只更新摘要与接收方未读，不动 sender 自己那一侧的未读
  const fields: Record<string, any> = {
    lastMessage: preview,
    lastSenderId: senderId,
    lastCreatedAt: nowIso,
    status: 0
  };
  if (receiver === lo) {
    fields.unreadForUser1 = unreadReceiver;
  } else {
    fields.unreadForUser2 = unreadReceiver;
  }
  await updateFields(forumConversationCollection, ForumConversation, { pairId: pairId }, fields);
}

// 按 userId 取用户行（服务端内部鉴权/更新用）
async function getUserRow(userId: number): Promise<User | null> {
  const res = await userCollection.query().equalTo('userId', userId).get();
  const rows = toList(res);
  return rows.length > 0 ? (rows[0] as User) : null;
}

// 数据访问鉴权：谁能看某个用户的健康数据/预警
// admin 全可；本人可；doctor 仅当 target 是绑定到自己名下的患者，且医生本人已通过资质审核。
// 审核未通过的医生即使拿到令牌也看不到任何患者数据，这是"防冒充医生"的最后一道闸。
async function canView(caller: TokenPayload, targetUserId: number): Promise<boolean> {
  if (caller.role === 'admin') { return true; }
  if (caller.uid === targetUserId) { return true; }
  if (caller.role === 'doctor') {
    const me = await getUserRow(caller.uid);
    if (!isDoctorActive(me)) { return false; }
    const t = await getUserRow(targetUserId);
    return !!t && t.role === 'patient' && t.doctorId === caller.uid;
  }
  return false;
}

// ISO 字符串按字典序即等于时间序，倒序（新在前）
function sortByTimeDesc(rows: any[], field: string): any[] {
  return rows.slice().sort((a: any, b: any) => (a[field] < b[field] ? 1 : a[field] > b[field] ? -1 : 0));
}

// 阈值预警（双阈值），命中即写一条 HealthWarning；逻辑从端侧搬到服务端，配合 1c 锁权限
async function generateWarnings(userId: number, h: HealthData): Promise<void> {
  const hits: Array<{ t: string; m: string; s: string }> = [];
  if (h.bloodPressureSystolic > 140) {
    hits.push({ t: 'high_blood_pressure', m: '您的收缩压偏高 (' + h.bloodPressureSystolic + ' mmHg)，超过了正常范围', s: 'medium' });
  }
  if (h.bloodPressureSystolic < 90 && h.bloodPressureSystolic > 0) {
    hits.push({ t: 'other', m: '您的收缩压偏低 (' + h.bloodPressureSystolic + ' mmHg)', s: 'low' });
  }
  if (h.bloodSugar > 7.0 && h.bloodSugar > 0) {
    hits.push({ t: 'high_blood_sugar', m: '您的血糖偏高 (' + h.bloodSugar + ' mmol/L)，超过了正常范围', s: 'medium' });
  }
  if (h.bloodSugar < 3.9 && h.bloodSugar > 0) {
    hits.push({ t: 'low_blood_sugar', m: '您的血糖偏低 (' + h.bloodSugar + ' mmol/L)', s: 'medium' });
  }
  if (h.heartRate > 100 && h.heartRate > 0) {
    hits.push({ t: 'other', m: '您的心率偏快 (' + h.heartRate + ' 次/分钟)', s: 'low' });
  }
  if (h.heartRate < 60 && h.heartRate > 0) {
    hits.push({ t: 'other', m: '您的心率偏慢 (' + h.heartRate + ' 次/分钟)', s: 'low' });
  }
  for (const hit of hits) {
    const w = new HealthWarning();
    w.warningId = newId();
    w.userId = userId;
    w.warningType = hit.t;
    w.warningMessage = hit.m;
    w.warningTime = new Date().toISOString();
    w.acknowledged = false;
    w.severity = hit.s;
    // 每条预警都是新行：newId() 已保证同一次调用内不重号，用 insert 撞号会报错而不是静默覆盖
    await warningCollection.insert(w);
  }
}

// ==================== AI 健康报告（DeepSeek）辅助 ====================

// 指标统计结果
interface MetricStat {
  name: string;        // 中文指标名
  count: number;       // 有效记录条数
  latest: number;      // 最近一次值
  avg: number;         // 均值（1 位小数）
  min: number;         // 最低
  max: number;         // 最高
  trend: string;       // '上升' | '下降' | '平稳'
}

// 根据 ISO 生日算周岁
function computeAge(dob: string): number {
  if (!dob) { return -1; }
  const d = new Date(dob);
  if (isNaN(d.getTime())) { return -1; }
  const now = new Date();
  let age = now.getFullYear() - d.getFullYear();
  const m = now.getMonth() - d.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < d.getDate())) { age -= 1; }
  return age;
}

// 取某项指标的数值数组（0 或 null 视为未记录，过滤掉）
function pickValues(rows: HealthData[], field: keyof HealthData): number[] {
  const out: number[] = [];
  for (const r of rows) {
    const v = r[field] as unknown as number;
    if (typeof v === 'number' && v > 0) { out.push(v); }
  }
  return out;
}

function round1(x: number): number {
  return Math.round(x * 10) / 10;
}

// 对单指标做统计。rows 已按时间倒序（新在前）。
function summarizeMetric(name: string, rows: HealthData[], field: keyof HealthData): MetricStat | null {
  const vals = pickValues(rows, field);
  if (vals.length === 0) { return null; }
  const sum = vals.reduce((a: number, b: number) => a + b, 0);
  const avg = sum / vals.length;
  const min = Math.min.apply(null, vals);
  const max = Math.max.apply(null, vals);
  // rows 是新在前，vals 保持同序，latest=vals[0]
  const latest = vals[0];
  // 趋势：把时间轴正序（旧->新）对半切，比较后半段均值与前半段均值
  const chrono = vals.slice().reverse();
  let trend = '平稳';
  if (chrono.length >= 4) {
    const half = Math.floor(chrono.length / 2);
    const first = chrono.slice(0, half);
    const second = chrono.slice(half);
    const fAvg = first.reduce((a: number, b: number) => a + b, 0) / first.length;
    const sAvg = second.reduce((a: number, b: number) => a + b, 0) / second.length;
    const diffPct = fAvg === 0 ? 0 : (sAvg - fAvg) / fAvg;
    if (diffPct > 0.05) { trend = '上升'; }
    else if (diffPct < -0.05) { trend = '下降'; }
    else { trend = '平稳'; }
  }
  return {
    name: name,
    count: vals.length,
    latest: round1(latest),
    avg: round1(avg),
    min: round1(min),
    max: round1(max),
    trend: trend
  };
}

// 汇总近 30 天各指标统计
function buildStats(rows: HealthData[]): MetricStat[] {
  const cutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
  const recent = rows.filter((r: HealthData) => {
    const t = new Date(r.recordTime).getTime();
    return !isNaN(t) && t >= cutoff;
  });
  const stats: MetricStat[] = [];
  const push = (n: string, f: keyof HealthData) => {
    const s = summarizeMetric(n, recent, f);
    if (s) { stats.push(s); }
  };
  push('收缩压(高压, mmHg)', 'bloodPressureSystolic');
  push('舒张压(低压, mmHg)', 'bloodPressureDiastolic');
  push('血糖(mmol/L)', 'bloodSugar');
  push('心率(次/分)', 'heartRate');
  push('体重(kg)', 'weight');
  return stats;
}

// 汇总近 30 天运动记录，生成给 AI 的文字段落
function buildExerciseSummary(rows: HealthData[]): string {
  const cutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
  const recent = rows.filter((r: HealthData) => {
    const t = new Date(r.recordTime).getTime();
    return !isNaN(t) && t >= cutoff;
  });
  const done = recent.filter((r: HealthData) =>
    (r.exerciseDuration && r.exerciseDuration > 0) || (r.exerciseType && r.exerciseType.length > 0));
  if (done.length === 0) {
    return '近30天没有录入运动数据。';
  }
  let sumDur = 0;
  let sumCal = 0;
  let durCnt = 0;
  let calCnt = 0;
  const typeMap: Record<string, number> = {};
  for (const r of done) {
    if (r.exerciseDuration && r.exerciseDuration > 0) { sumDur += r.exerciseDuration; durCnt += 1; }
    if (r.exerciseCalories && r.exerciseCalories > 0) { sumCal += r.exerciseCalories; calCnt += 1; }
    if (r.exerciseType && r.exerciseType.length > 0) {
      typeMap[r.exerciseType] = (typeMap[r.exerciseType] || 0) + 1;
    }
  }
  const avgDur = durCnt > 0 ? Math.round(sumDur / durCnt) : 0;
  const avgCal = calCnt > 0 ? Math.round(sumCal / calCnt) : 0;
  const typeArr: string[] = Object.keys(typeMap);
  typeArr.sort((a: string, b: string) => typeMap[b] - typeMap[a]);
  const typeText = typeArr.length > 0
    ? typeArr.map((k: string) => k + '(' + typeMap[k] + '次)').join('、')
    : '未标注类型';
  return '近30天运动情况：共 ' + done.length + ' 次运动记录；' +
    '平均每次时长约 ' + avgDur + ' 分钟，合计约 ' + sumDur + ' 分钟；' +
    '平均每次消耗约 ' + avgCal + ' kcal；运动类型分布：' + typeText + '。';
}

// 用 Node 内置 https 调 DeepSeek OpenAI 兼容接口，返回助手文本内容
function callDeepSeek(systemPrompt: string, userPrompt: string): Promise<string> {
  return new Promise<string>((resolve: (v: string) => void, reject: (e: Error) => void) => {
    const key = getApiKey();
    if (!key || key.indexOf('PASTE_YOUR') === 0) {
      reject(new Error('AI 未配置：请在 model/aiConfig.ts 填写 DeepSeek Key'));
      return;
    }
    const body = JSON.stringify({
      model: DEEPSEEK_MODEL,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userPrompt }
      ],
      temperature: 0.4,
      response_format: { type: 'json_object' }
    });
    const req = https.request({
      host: DEEPSEEK_HOST,
      path: DEEPSEEK_PATH,
      method: 'POST',
      timeout: DEEPSEEK_TIMEOUT_MS,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + key,
        'Content-Length': Buffer.byteLength(body)
      }
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        const code = res.statusCode || 0;
        if (code < 200 || code >= 300) {
          reject(new Error('DeepSeek 返回 ' + code + '：' + data.substring(0, 200)));
          return;
        }
        try {
          const json = JSON.parse(data);
          const content = json && json.choices && json.choices[0] && json.choices[0].message
            ? String(json.choices[0].message.content) : '';
          if (!content) { reject(new Error('DeepSeek 返回内容为空')); return; }
          resolve(content);
        } catch (e) {
          reject(new Error('解析 DeepSeek 响应失败：' + String((e as Error).message || e)));
        }
      });
    });
    req.on('timeout', () => { req.destroy(new Error('调用 DeepSeek 超时')); });
    req.on('error', (e) => { reject(new Error('调用 DeepSeek 网络错误：' + String((e as Error).message || e))); });
    req.write(body);
    req.end();
  });
}

// 从模型返回文本中稳妥地抠出 JSON 对象（去掉可能的 ```json 围栏）
function extractJsonObject(text: string): Record<string, Object> | null {
  let s = text.trim();
  const fence = /```(?:json)?/i;
  if (fence.test(s)) {
    s = s.replace(/```(?:json)?/gi, '').trim();
  }
  const first = s.indexOf('{');
  const last = s.lastIndexOf('}');
  if (first < 0 || last <= first) { return null; }
  s = s.substring(first, last + 1);
  try {
    return JSON.parse(s) as Record<string, Object>;
  } catch (e) {
    return null;
  }
}

// 组装给模型的用户 prompt：画像 + 近30天统计 + 输出结构约定
function buildUserPrompt(user: User, stats: MetricStat[], exerciseText: string): string {
  const age = computeAge(user.dateOfBirth);
  const genderMap: Record<string, string> = { male: '男', female: '女', other: '其他' };
  const profile = '用户画像：角色=' + user.role + '，性别=' + (genderMap[user.gender] || '未知') +
    '，年龄=' + (age >= 0 ? age + '岁' : '未填写') + '。';
  let statsText = '';
  if (stats.length === 0) {
    statsText = '近30天没有可统计的健康数据。';
  } else {
    statsText = '近30天各项指标统计（记录条数/最新值/均值/最低/最高/趋势）：\n' +
      stats.map((s) => s.name + '：条数' + s.count + '，最新' + s.latest +
        '，均值' + s.avg + '，最低' + s.min + '，最高' + s.max + '，趋势' + s.trend).join('\n');
  }
  return '你是一名慢病管理健康助理。请基于以下真实数据，用简体中文生成一份个性化、具体、可操作的健康报告，' +
    '避免空泛套话，也不要编造数据里没有的数值。\n\n' +
    profile + '\n' + statsText + '\n' + exerciseText + '\n\n' +
    '请只输出一个 JSON 对象（不要多余文字、不要代码围栏），字段如下：\n' +
    '{\n' +
    '  "riskLevel": "low" | "medium" | "high"，\n' +
    '  "overallAssessment": "2-4句总体健康评估",\n' +
    '  "metrics": [ { "name": "指标名", "status": "正常/偏高/偏低/波动大 等", "detail": "结合数值的具体解读与建议" } ]（只列有数据的指标）,\n' +
    '  "trendAnalysis": "结合趋势方向的解读",\n' +
    '  "dietAdvice": "个性化饮食建议",\n' +
    '  "exerciseAdvice": "必须结合上面『近30天运动情况』的真实记录来写：若运动不足给出循序渐进的加量方案，若已有规律运动则在其运动类型/时长/频率基础上给出优化建议（含强度/频率）",\n' +
    '  "lifestyleAdvice": "作息与生活方式建议",\n' +
    '  "followUpAdvice": "复查与就医提醒",\n' +
    '  "redFlags": "出现哪些情况需立即就医（危险信号）"\n' +
    '}\n' +
    '注意：这是自我管理的辅助参考，不构成医疗诊断；措辞谨慎、贴合数据。';
}

// ==================== 论坛（Phase ① 纯文字）辅助 ====================

// 作者展示名：昵称优先，退化为用户名，再退化为占位（与服务端 toPublicUser 口径一致）
function forumDisplayName(nickname: string, username: string, userId: number): string {
  const nick = (nickname || '').trim();
  if (nick !== '') { return nick; }
  const uname = (username || '').trim();
  if (uname !== '') { return uname; }
  return '用户' + userId;
}

// 按 id 集合批量取作者展示信息（in 查询），只读这一页涉及的用户。
// 以前这里是 query().get() 全表加载 User，用户表一大，每次翻列表都要把所有人捞一遍。
async function loadAuthorMapByIds(ids: number[]): Promise<Record<number, { name: string; role: string; avatar: string }>> {
  const map: Record<number, { name: string; role: string; avatar: string }> = {};
  const uniq: number[] = [];
  for (const id of ids) {
    if (id > 0 && uniq.indexOf(id) < 0) { uniq.push(id); }
  }
  // in 条件单次最多 100 项，超出分批
  for (let i = 0; i < uniq.length; i += 100) {
    const chunk = uniq.slice(i, i + 100);
    const res = await userCollection.query().in('userId', chunk).get();
    const rows = toList(res) as User[];
    for (const u of rows) {
      map[u.userId] = {
        name: forumDisplayName(u.nickname, u.username, u.userId),
        role: u.role,
        avatar: u.avatarUrl === undefined || u.avatarUrl === null ? '' : u.avatarUrl
      };
    }
  }
  return map;
}

// 评论总数以 ForumComment 真实未删除行数为权威：自增缓存会因 CloudDB 快照 upsert 竞态漂移，
// 故读取时按实际行数覆盖。这里只查当页涉及的帖子（in 条件），不再全表归并。
async function commentCountsFor(postIds: number[]): Promise<Record<number, number>> {
  const map: Record<number, number> = {};
  const uniq: number[] = [];
  for (const id of postIds) {
    if (id > 0 && uniq.indexOf(id) < 0) { uniq.push(id); }
  }
  for (let i = 0; i < uniq.length; i += 100) {
    const chunk = uniq.slice(i, i + 100);
    const res = await forumCommentCollection.query().in('postId', chunk).get();
    const rows = toList(res) as ForumComment[];
    for (const c of rows) {
      if (c.status === 0) {
        map[c.postId] = (map[c.postId] || 0) + 1;
      }
    }
  }
  return map;
}

// 服务端分页取数：靠 orderBy + limit(count, offset) 只拉一页，不再整表回传。
// AGC 对分页查询有硬约束：只允许「一个 equalTo + 一个 orderBy + limit」，
// equalTo 必须写在 orderBy 之前且不能与 orderBy 同字段，且必须有匹配索引
// （缺索引会直接抛 3037029）。所以这里统一吞掉异常并返回 null，
// 由调用方回退到原来的全量实现——缺索引只会退化成慢，不会让列表打不开。
async function pagedSlice(query: any, pageSize: number): Promise<{ rows: any[]; hasMore: boolean } | null> {
  try {
    const res = await query.get();
    const raw = toList(res);
    const hasMore = raw.length > pageSize;
    return { rows: hasMore ? raw.slice(0, pageSize) : raw, hasMore: hasMore };
  } catch (e) {
    console.warn('[paged] query rejected, fallback to full scan: ' + String((e as Error).message || e));
    return null;
  }
}


// 单个帖子真实未删除评论数：供详情读取覆盖 + 增删评论后回写缓存字段
async function countActiveComments(postId: number): Promise<number> {
  const res = await forumCommentCollection.query().equalTo('postId', postId).get();
  const rows = toList(res) as ForumComment[];
  let n = 0;
  for (const c of rows) {
    if (c.status === 0) { n++; }
  }
  return n;
}

function toPublicPost(p: ForumPost, authorName: string, likedByMe: boolean, commentCountOverride?: number, favoritedByMe?: boolean, authorAvatar?: string): Record<string, Object> {
  return {
    postId: p.postId,
    authorId: p.authorId,
    authorRole: p.authorRole,
    authorName: authorName,
    authorAvatar: authorAvatar === undefined ? '' : authorAvatar,
    title: p.title,
    content: p.content,
    createdAt: p.createdAt,
    likeCount: p.likeCount,
    commentCount: commentCountOverride === undefined ? p.commentCount : commentCountOverride,
    status: p.status,
    likedByMe: likedByMe,
    favoritedByMe: favoritedByMe === undefined ? false : favoritedByMe,
    mediaUrls: p.mediaUrls === undefined || p.mediaUrls === '' ? '[]' : p.mediaUrls,
    dept: p.dept === undefined ? '' : p.dept,
    topics: p.topics === undefined || p.topics === '' ? '[]' : p.topics
  };
}

function toPublicComment(c: ForumComment, authorName: string, authorAvatar?: string): Record<string, Object> {
  return {
    commentId: c.commentId,
    postId: c.postId,
    authorId: c.authorId,
    authorRole: c.authorRole,
    authorName: authorName,
    authorAvatar: authorAvatar === undefined ? '' : authorAvatar,
    content: c.content,
    createdAt: c.createdAt,
    status: c.status,
    parentId: c.parentId,
    mediaUrls: (c.mediaUrls === undefined || c.mediaUrls === '') ? '[]' : c.mediaUrls
  };
}

// ===== 私信辅助：会话主键、行投影 =====
// pairId 固定为「较小userId-较大userId」，保证同一对用户无论谁先发起都落到同一条会话。
function makePairId(a: number, b: number): string {
  const lo = Math.min(a, b);
  const hi = Math.max(a, b);
  return lo + '-' + hi;
}

// 私信"引用某帖"的机器标记：正文末尾追加 分隔符 + post:<id>，端侧据此渲染"查看原帖"。
// 分隔符用控制符 \u0001，正常打字不会出现；预览摘要取分隔符之前的人话部分。
const MSG_META_SEP = '\u0001';
function postMarker(postId: number): string {
  return MSG_META_SEP + 'post:' + postId;
}
function stripMarker(text: string): string {
  const i = text.indexOf(MSG_META_SEP);
  return i < 0 ? text : text.slice(0, i);
}
// 从正文尾部标记里取 postId（无则 0）——转发分享时据此把「查看原帖」一起带过去
function extractPostId(text: string): number {
  const i = text.indexOf(MSG_META_SEP);
  if (i < 0) { return 0; }
  const tail = text.slice(i + 1);
  if (tail.indexOf('post:') !== 0) { return 0; }
  const id = Number.parseInt(tail.slice(5), 10);
  return isNaN(id) ? 0 : id;
}
// 引用某条私信的标记：正文末尾追加 分隔符 + quote:<messageId>，端侧据此渲染引用块
function quoteMarker(messageId: number): string {
  return MSG_META_SEP + 'quote:' + messageId;
}
function extractQuoteId(text: string): number {
  const i = text.indexOf(MSG_META_SEP);
  if (i < 0) { return 0; }
  const tail = text.slice(i + 1);
  if (tail.indexOf('quote:') !== 0) { return 0; }
  const id = Number.parseInt(tail.slice(6), 10);
  return isNaN(id) ? 0 : id;
}

// 会话列表投影：peer=对方；unread=属于"我"的未读数（按我在 pair 中的位次取对应字段）
function toPublicConversation(c: ForumConversation, me: number, peerName: string, peerAvatar?: string): Record<string, Object> {
  const peerId = c.userId1 === me ? c.userId2 : c.userId1;
  const unread = c.userId1 === me ? c.unreadForUser1 : c.unreadForUser2;
  return {
    pairId: c.pairId,
    peerId: peerId,
    peerName: peerName,
    peerAvatar: peerAvatar === undefined ? '' : peerAvatar,
    lastMessage: c.lastMessage,
    lastSenderId: c.lastSenderId,
    lastCreatedAt: c.lastCreatedAt,
    unread: unread,
    status: c.status
  };
}

// 单条私信投影
function toPublicMessage(m: ForumPrivateMessage): Record<string, Object> {
  return {
    messageId: m.messageId,
    pairId: m.pairId,
    senderId: m.senderId,
    receiverId: m.receiverId,
    content: m.content,
    createdAt: m.createdAt,
    readFlag: m.readFlag,
    status: m.status,
    mediaUrls: (m.mediaUrls === undefined || m.mediaUrls === '') ? '[]' : m.mediaUrls
  };
}

// 以"系统"身份给某人写一条私信通知（复用正常会话结构）。
// 不再走敏感词/禁言/管理员校验——这是服务端自造的通知，正文已在发帖/评论时被过滤过。
async function insertSystemDm(fromUid: number, toUid: number, text: string, mediaJson?: string): Promise<void> {
  const pairId = makePairId(fromUid, toUid);
  const now = new Date().toISOString();
  const lo = Math.min(fromUid, toUid);
  const hi = Math.max(fromUid, toUid);
  const media = (mediaJson === undefined || mediaJson === '') ? '[]' : mediaJson;

  const msg = new ForumPrivateMessage();
  msg.messageId = newId();
  msg.pairId = pairId;
  msg.senderId = fromUid;
  msg.receiverId = toUid;
  msg.content = text;
  msg.createdAt = now;
  msg.readFlag = 0;
  msg.status = 0;
  msg.mediaUrls = media;
  await forumPrivateMessageCollection.insert(msg);

  // 会话摘要 + 未读（未读取真实行数，见 touchConversation）
  const cleanText = stripMarker(text);
  let preview = cleanText.length > DM_PREVIEW_MAX ? cleanText.slice(0, DM_PREVIEW_MAX) : cleanText;
  if (preview === '' && media !== '[]') { preview = '[图片]'; }
  await touchConversation(pairId, lo, hi, fromUid, preview);
}

// 给所有被 @ 的人各发一条私信通知；任何单人失败都不影响其它人，整体也不抛出，避免拖垮主流程
async function notifyMentions(authorUid: number, postId: number, mentionIds: number[], postTitle: string, snippet: string): Promise<void> {
  if (!mentionIds || mentionIds.length === 0) { return; }
  const title = (postTitle || '').trim();
  const where = title === '' ? '一条内容' : ('《' + title + '》');
  const snip = (snippet || '').trim().slice(0, MENTION_SNIPPET_MAX);
  const body = snip === '' ? '（点击查看原帖）' : ('：' + snip);
  const text = '有人@了你：在' + where + '里提到你' + body + postMarker(postId);
  // 一次性把这批人的角色查回来（in 查询），不再逐人一次 getUserRow
  const targets = await loadUsersByIds(mentionIds);
  for (let i = 0; i < mentionIds.length; i++) {
    const toUid = mentionIds[i];
    if (toUid <= 0 || toUid === authorUid) { continue; }
    try {
      const target = targets[toUid];
      if (!target || target.role === 'admin') { continue; }   // 不存在或管理员，跳过
      await insertSystemDm(authorUid, toUid, text);
    } catch (e) {
      // 单个通知失败不影响其它人
    }
  }
}

// 按 id 集合批量取用户行（in 查询，分批 100），供 @ 通知/分享等批量场景复用，
// 替代"每个目标一次网络往返"的串行查询。
async function loadUsersByIds(ids: number[]): Promise<Record<number, User>> {
  const map: Record<number, User> = {};
  const uniq: number[] = [];
  for (const id of ids) {
    if (id > 0 && uniq.indexOf(id) < 0) { uniq.push(id); }
  }
  for (let i = 0; i < uniq.length; i += 100) {
    const chunk = uniq.slice(i, i + 100);
    const res = await userCollection.query().in('userId', chunk).get();
    for (const u of toList(res) as User[]) { map[u.userId] = u; }
  }
  return map;
}

// 一批患者的未确认预警数（in 查询一次取回，按 userId 归并）
async function unackCountsFor(userIds: number[]): Promise<Record<number, number>> {
  const map: Record<number, number> = {};
  const uniq: number[] = [];
  for (const id of userIds) {
    if (id > 0 && uniq.indexOf(id) < 0) { uniq.push(id); }
  }
  for (let i = 0; i < uniq.length; i += 100) {
    const chunk = uniq.slice(i, i + 100);
    const res = await warningCollection.query().in('userId', chunk).get();
    for (const w of toList(res) as HealthWarning[]) {
      if (!w.acknowledged) {
        map[w.userId] = (map[w.userId] || 0) + 1;
      }
    }
  }
  return map;
}

// 某患者最近一条血压（"120/80"），无数据返回"暂无"。
// 只取最新一条：equalTo + orderByDesc + limit(1,0)；缺索引时退回读一批再取首条。
async function latestBpOf(userId: number): Promise<string> {
  let rows: HealthData[] = [];
  const paged = await pagedSlice(
    healthCollection.query().equalTo('userId', userId).orderByDesc('recordTime').limit(1, 0), 1);
  if (paged !== null) {
    rows = paged.rows as HealthData[];
  } else {
    rows = await loadHealthRows(userId);
  }
  if (rows.length === 0) { return '暂无'; }
  const h = rows[0];
  if (!h.bloodPressureSystolic) { return '暂无'; }
  return h.bloodPressureSystolic + '/' + h.bloodPressureDiastolic;
}

// 取某用户的违规台账行（无则返回 null）
async function getViolationRow(userId: number): Promise<ForumViolation | null> {
  const res = await forumViolationCollection.query().equalTo('userId', userId).get();
  const rows = toList(res);
  return rows.length > 0 ? (rows[0] as ForumViolation) : null;
}

// 是否处于禁言中：muteUntil 是未来时间才算生效
function isMutedNow(v: ForumViolation | null): boolean {
  if (!v || !v.muteUntil) { return false; }
  const until = new Date(v.muteUntil).getTime();
  return !isNaN(until) && until > Date.now();
}

// 记录一次违规命中并返回升级结果。写回 violationCount/lastTime/muteUntil。
// 阶梯（秒）：1 警告、2 30 秒、3 5 分钟、4 30 分钟、5 2 小时、6+ 1 天。
// 归零：从第 3 次起，若距上次违规满 24 小时无新违规，则本次按第 1 次重新计（计数归零）。
// 返回：violationCount 本次累计次数、muteSec 本次禁言秒数、muteText 禁言时长中文文案（0 时空串）。
async function registerViolation(userId: number): Promise<{ violationCount: number; muteSec: number; muteText: string }> {
  let row = await getViolationRow(userId);
  if (!row) {
    row = new ForumViolation();
    row.userId = userId;
    row.violationCount = 0;
    row.lastTime = '';
    row.muteUntil = '';
  }
  const now = Date.now();
  // 达到过第 3 次及以上 + 距上次违规超过一天 -> 重新从第一次算
  let base = row.violationCount;
  if (base >= 3 && row.lastTime) {
    const last = new Date(row.lastTime).getTime();
    if (!isNaN(last) && now - last > 24 * 3600 * 1000) {
      base = 0;
    }
  }
  const nextCount = base + 1;
  const muteSec = muteSecondsFor(nextCount);
  const updated = new ForumViolation();
  updated.userId = userId;
  updated.violationCount = nextCount;
  updated.lastTime = new Date(now).toISOString();
  if (muteSec > 0) {
    updated.muteUntil = new Date(now + muteSec * 1000).toISOString();
  } else {
    updated.muteUntil = row.muteUntil || ''; // 首次仅提醒，不改变既有解禁时间
  }
  await forumViolationCollection.upsert(updated);
  return { violationCount: nextCount, muteSec: muteSec, muteText: formatMute(muteSec) };
}

// 某用户点过赞的帖子 id 集合，用于列表页回填 likedByMe
async function loadLikedPostIds(userId: number): Promise<Record<number, boolean>> {
  const set: Record<number, boolean> = {};
  const res = await forumLikeCollection.query().equalTo('userId', userId).get();
  const rows = toList(res) as ForumLike[];
  for (const r of rows) {
    set[r.postId] = true;
  }
  return set;
}

// 我收藏过的帖子 postId 集合（与点赞同理，供列表/详情回传收藏态）
async function loadFavoritedPostIds(userId: number): Promise<Record<number, boolean>> {
  const set: Record<number, boolean> = {};
  const res = await forumFavoriteCollection.query().equalTo('userId', userId).get();
  const rows = toList(res) as ForumFavorite[];
  for (const r of rows) {
    set[r.postId] = true;
  }
  return set;
}

// ISO 字符串按时间正序（旧在前，新在后）——评论区按发言先后阅读更自然
function sortByTimeAsc(rows: any[], field: string): any[] {
  return rows.slice().sort((a: any, b: any) => (a[field] > b[field] ? 1 : a[field] < b[field] ? -1 : 0));
}

export class AuthService {

  // 版本探针：排查"方法明明写了却报云端调用失败"这类问题时，
  // 在 AGC 控制台 → 云函数 → 函数测试里发 {"method":"version"} 即可确认线上是否已更新。
  async version() {
    return {
      ok: true,
      data: {
        build: '2026-10-22-r3',
        methods: [
          'register', 'login', 'checkUsername', 'deleteAccount', 'seedDemoData',
          'sendFollowUp', 'reviewDoctor', 'listPendingDoctors', 'patientsOverview',
          'updateAvatar'
        ]
      }
    };
  }

  // 注册：校验入参 -> 角色白名单 -> 查重 -> 密码加盐哈希 -> 写云端
  // 安全要点：role 由端侧传入，必须服务端白名单收口，否则任何人可注册成管理员。
  // 医生必须填写执业证号，且注册后处于"待审核"状态（PENDING|），管理员通过后才可见患者数据。
  async register(username: string, password: string, role: string, license?: string) {
    try {
      await ensureDb();
      const name = (username || '').trim();
      const pwd = password || '';
      const wantRole = (role || '').trim();
      const lic = (license || '').trim();

      if (name.length < USERNAME_MIN || name.length > USERNAME_MAX) {
        return { ok: false, error: '用户名长度需在 ' + USERNAME_MIN + '-' + USERNAME_MAX + ' 个字符之间' };
      }
      if (/\s/.test(name)) {
        return { ok: false, error: '用户名不能包含空格' };
      }
      if (pwd.length < PASSWORD_MIN || pwd.length > PASSWORD_MAX) {
        return { ok: false, error: '密码长度需在 ' + PASSWORD_MIN + '-' + PASSWORD_MAX + ' 位之间' };
      }
      // 角色白名单：管理员不允许自助注册
      if (SELF_REGISTER_ROLES.indexOf(wantRole) < 0) {
        return { ok: false, error: '不支持注册该身份' };
      }
      if (matchSensitive(name).length > 0) {
        return { ok: false, error: '用户名包含违规词，请更换' };
      }
      // 医生：执业证号必填 + 长度/字符校验，落库时打上待审核标记
      if (wantRole === 'doctor') {
        if (lic.length < 6 || lic.length > 40) {
          return { ok: false, error: '请填写有效的执业证号（6-40 个字符）' };
        }
        if (!/^[A-Za-z0-9\u4e00-\u9fa5\-]+$/.test(lic)) {
          return { ok: false, error: '执业证号只能包含字母、数字、汉字或短横线' };
        }
        if (matchSensitive(lic).length > 0) {
          return { ok: false, error: '执业证号包含违规词' };
        }
      }

      // 查重：用户名之外，医生还要防"同一证号重复注册"
      const exist = await userCollection.query().equalTo('username', name).get();
      if (toList(exist).length > 0) {
        return { ok: false, error: '用户名已存在' };
      }
      if (wantRole === 'doctor') {
        const licExist = await userCollection.query().equalTo('role', 'doctor').get();
        const docs = toList(licExist) as User[];
        for (const d of docs) {
          if (rawLicense(d) === lic) {
            return { ok: false, error: '该执业证号已被注册' };
          }
        }
      }

      const row = new User();
      row.userId = newId();
      row.username = name;
      row.password = hashPassword(pwd);
      row.email = '';
      row.phone = '';
      row.gender = 'other';
      row.role = wantRole;
      row.dateOfBirth = '';
      // 证号存干净值；审核状态写正式列（列不存在时由 insertUserRow 自动降级为前缀方案）
      row.doctorLicense = wantRole === 'doctor' ? lic : '';
      row.doctorStatus = wantRole === 'doctor' ? 'pending' : '';
      row.doctorId = 0;
      row.createdAt = new Date().toISOString();
      row.nickname = '';
      row.nicknameUpdatedAt = '';
      // 新用户用 insert 而不是 upsert：万一同秒撞出重复主键，insert 会报错，
      // 不会像 upsert 那样把另一个用户整行覆盖掉。
      await insertUserRow(row, lic, 'pending');

      // 写后确认（消除并发重名）：
      // 并发注册同名时，两边都可能通过上面的查重，于是各插一条。CloudDB 的索引只做查询加速、
      // 没有唯一约束，所以只能在这里兜住：再查一次同名记录，只保留 userId 最小（最早注册）的那条，
      // 自己若不是就删掉再回报"已存在"。
      // 这样最坏情况退化为"后来者注册失败"，而不是"两个同名账号里有一个永远登不上"。
      let loser = false;
      try {
        const again = await userCollection.query().equalTo('username', name).get();
        const same = toList(again) as User[];
        if (same.length > 1) {
          let survivorId = row.userId;
          for (let i = 0; i < same.length; i++) {
            if (same[i].userId < survivorId) { survivorId = same[i].userId; }
          }
          if (survivorId !== row.userId) {
            // 自己不是最早那条：先删掉自己这条，再按"已存在"回报
            loser = true;
          } else {
            console.error('[register] duplicated username "' + name + '", kept userId=' + survivorId);
          }
        }
      } catch (e2) {
        // 确认环节失败不影响已插入的账号；真出现重名还有 login 的容错兜底
        console.error('[register] post-check failed: ' + String((e2 as Error).message || e2));
      }
      if (loser) {
        try {
          await userCollection.delete(row);
        } catch (e3) {
          // 删不掉也照样报"已存在"：宁可留下一条脏数据，也不能让用户以为自己注册成功了
          console.error('[register] rollback loser row failed: ' + String((e3 as Error).message || e3));
        }
        return { ok: false, error: '用户名已存在' };
      }
      return { ok: true };
    } catch (e) {
      return { ok: false, error: String((e as Error).message || e) };
    }
  }

  // 用户名可用性预检查（注册页失焦时调用，不需要登录态）。
  // 只回答"这个名字能不能用"，不返回任何其它账号信息；真正的裁决仍在 register 里。
  async checkUsername(username: string) {
    try {
      await ensureDb();
      const name = (username || '').trim();
      if (name.length < USERNAME_MIN || name.length > USERNAME_MAX) {
        return { ok: true, available: false, reason: '用户名长度需在 ' + USERNAME_MIN + '-' + USERNAME_MAX + ' 个字符之间' };
      }
      if (/\s/.test(name)) {
        return { ok: true, available: false, reason: '用户名不能包含空格' };
      }
      if (matchSensitive(name).length > 0) {
        return { ok: true, available: false, reason: '用户名包含违规词' };
      }
      const res = await userCollection.query().equalTo('username', name).get();
      return { ok: true, available: toList(res).length === 0, reason: '' };
    } catch (e) {
      return { ok: false, error: String((e as Error).message || e) };
    }
  }

  // 登录：云端校验；存量明文密码在验证通过后就地升级为哈希（懒迁移）；签发会话令牌
  async login(username: string, password: string) {
    try {
      await ensureDb();
      const name = (username || '').trim();
      if (name === '') { return { ok: false, error: '请输入用户名' }; }
      const res = await userCollection.query().equalTo('username', name).get();
      const rows = toList(res) as User[];
      if (rows.length === 0) {
        return { ok: false, error: '用户不存在' };
      }

      // 同名多条的兜底（历史并发注册留下的脏数据）：用密码逐条比对，只认匹配上的那一条。
      // 以前直接取 rows[0]，导致重复账号里排后面的那个"密码是对的却永远登不上"。
      let row: User | null = null;
      if (rows.length === 1) {
        row = verifyPassword(password || '', rows[0].password) ? rows[0] : null;
      } else {
        const matched: User[] = [];
        for (let i = 0; i < rows.length; i++) {
          if (verifyPassword(password || '', rows[i].password)) { matched.push(rows[i]); }
        }
        if (matched.length > 0) {
          matched.sort((a: User, b: User) => a.userId - b.userId);   // 多条都匹配时取最早注册的
          row = matched[0];
        }
        console.error('[login] duplicated username "' + name + '" rows=' + rows.length + ' matched=' + matched.length);
      }
      if (!row) {
        return { ok: false, error: '密码错误，请重新输入' };
      }

      const stored = row.password;
      if (isLegacyPlain(stored)) {
        // 只更新密码字段，不动其它列（整行 upsert 会把查询快照里的旧值一起写回）
        await updateFields(userCollection, User, { userId: row.userId }, { password: hashPassword(password) });
      }
      const token = signToken(row.userId, isValidRole(row.role) ? row.role : 'patient');
      return { ok: true, user: toPublicUser(row), token: token };
    } catch (e) {
      return { ok: false, error: String((e as Error).message || e) };
    }
  }

  // ===== 以下为 1d 数据方法：全部先验令牌、按角色做行级鉴权，再用服务端凭证读写 =====

  async listDoctors(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const res = await userCollection.query().get();
      const all = toList(res).filter((u: User) => u.role === 'doctor') as User[];
      // 患者只应看到"已通过审核"的医生（否则会出现一个绑不上的名字）；
      // 管理员需要看到全部（含待审核）才能审核。
      const visible = caller.role === 'admin' ? all : all.filter((u: User) => isDoctorActive(u));
      return { ok: true, data: visible.map((u: User) => toPublicUser(u)) };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async listAllPatients(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'admin') { return { ok: false, error: '无权访问' }; }
      const res = await userCollection.query().get();
      const patients = toList(res).filter((u: User) => u.role === 'patient').map((u: User) => toPublicUser(u));
      return { ok: true, data: patients };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async listMyPatients(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'doctor' && caller.role !== 'admin') { return { ok: true, data: [] }; }
      // 医生未通过资质审核时，一条患者数据都不返回
      if (caller.role === 'doctor') {
        const me = await getUserRow(caller.uid);
        if (!isDoctorActive(me)) { return { ok: true, data: [] }; }
      }
      const res = await userCollection.query().get();
      const mine = toList(res).filter((u: User) =>
        u.role === 'patient' && (caller.role === 'admin' || u.doctorId === caller.uid)
      ).map((u: User) => toPublicUser(u));
      return { ok: true, data: mine };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async listPatientsByDoctor(token: string, doctorId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'admin' && caller.uid !== doctorId) { return { ok: false, error: '无权访问' }; }
      if (caller.role === 'doctor') {
        const me = await getUserRow(caller.uid);
        if (!isDoctorActive(me)) { return { ok: true, data: [] }; }
      }
      const res = await userCollection.query().get();
      const pts = toList(res).filter((u: User) => u.role === 'patient' && u.doctorId === doctorId).map((u: User) => toPublicUser(u));
      return { ok: true, data: pts };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 首页"患者概览"：医生看自己名下、管理员看全部，一次调用返回 姓名/性别/最近血压/未确认预警数。
  // 替代端侧原来的 N+1 —— 以前首页要为每个患者各发两次云函数调用（查全部健康记录 + 查全部预警），
  // 患者一多首页就要转好几秒；现在固定 2 次批量查询 + 每人一次"只取最新一条"的小查询。
  async patientsOverview(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'doctor' && caller.role !== 'admin') {
        return { ok: true, data: [] };
      }

      let patients: User[] = [];
      if (caller.role === 'admin') {
        const res = await userCollection.query().equalTo('role', 'patient').get();
        patients = toList(res) as User[];
      } else {
        // 医生：先确认资质已通过，再只查绑定到自己的患者
        const me = await getUserRow(caller.uid);
        if (!isDoctorActive(me)) { return { ok: true, data: [] }; }
        const res = await userCollection.query().equalTo('doctorId', caller.uid).get();
        patients = (toList(res) as User[]).filter((u: User) => u.role === 'patient');
      }
      if (patients.length === 0) { return { ok: true, data: [] }; }

      const ids: number[] = [];
      for (const p of patients) { ids.push(p.userId); }
      const warnMap = await unackCountsFor(ids);

      const data: Record<string, Object>[] = [];
      for (const p of patients) {
        const bp = await latestBpOf(p.userId);
        data.push({
          userId: p.userId,
          name: forumDisplayName(p.nickname, p.username, p.userId),
          gender: p.gender === 'male' ? '男' : (p.gender === 'female' ? '女' : '其他'),
          latestBp: bp,
          warnCount: warnMap[p.userId] || 0,
          doctorId: p.doctorId || 0,
          avatarUrl: p.avatarUrl === undefined || p.avatarUrl === null ? '' : p.avatarUrl
        });
      }
      return { ok: true, data: data };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async getMyDoctor(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const me = await getUserRow(caller.uid);
      if (!me || me.doctorId === 0) { return { ok: true, data: null }; }
      const doc = await getUserRow(me.doctorId);
      return { ok: true, data: doc ? toPublicUser(doc) : null };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async getUserById(token: string, userId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (!(await canView(caller, userId))) { return { ok: false, error: '无权查看该用户' }; }
      const row = await getUserRow(userId);
      return { ok: true, data: row ? toPublicUser(row) : null };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async updateUserInfo(token: string, email: string, phone: string, gender: string, dateOfBirth: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const row = await getUserRow(caller.uid);
      if (!row) { return { ok: false, error: '用户不存在' }; }

      const mail = (email || '').trim();
      const tel = (phone || '').trim();
      const birth = (dateOfBirth || '').trim();
      const g = (gender || '').trim();

      // 入参校验：脏数据会直接进个人中心与 AI 报告的年龄计算
      if (mail.length > 64) { return { ok: false, error: '邮箱过长' }; }
      if (mail !== '' && mail.indexOf('@') <= 0) { return { ok: false, error: '邮箱格式不正确' }; }
      if (tel !== '' && !/^[0-9+\-]{5,20}$/.test(tel)) { return { ok: false, error: '手机号格式不正确' }; }
      if (birth !== '' && !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(birth)) {
        return { ok: false, error: '生日格式应为 YYYY-MM-DD' };
      }
      if (birth !== '') {
        const bt = new Date(birth).getTime();
        if (isNaN(bt) || bt > Date.now()) { return { ok: false, error: '生日不是有效日期' }; }
      }
      const genderOk = (g === 'male' || g === 'female' || g === 'other');

      // 只写这 4 个字段：昵称、角色、医生绑定等其它列一概不碰。
      // 这里刻意不再用"new 一个整行 + upsert"的写法——那会把 nickname 等未传字段打回默认空值。
      await updateFields(userCollection, User, { userId: caller.uid }, {
        email: mail,
        phone: tel,
        gender: genderOk ? g : (row.gender || 'other'),
        dateOfBirth: birth
      });
      // 回读一次，以库里真正落库的数据为准（写失败时不会假装成功）
      const saved = await getUserRow(caller.uid);
      if (!saved) { return { ok: false, error: '更新后回读失败' }; }
      return { ok: true, data: toPublicUser(saved) };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 修改昵称：服务端强制 5 分钟冷却（权威校验，防绕过）
  async updateNickname(token: string, nickname: string) {
    const COOLDOWN_MS = 5 * 60 * 1000;
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const row = await getUserRow(caller.uid);
      if (!row) { return { ok: false, error: '用户不存在' }; }
      const nick = (nickname || '').trim();
      if (nick === '') { return { ok: false, error: '昵称不能为空' }; }
      if (nick.length > NICKNAME_MAX) { return { ok: false, error: '昵称不能超过 ' + NICKNAME_MAX + ' 个字符' }; }
      // 昵称会出现在帖子/评论/私信列表里，等同于公开内容，同样要过敏感词
      if (matchSensitive(nick).length > 0) { return { ok: false, error: '昵称包含违规词，请更换' }; }
      // 冷却校验：距上次修改不足 5 分钟则拒绝
      if (row.nicknameUpdatedAt) {
        const last = new Date(row.nicknameUpdatedAt).getTime();
        const elapsed = Date.now() - last;
        if (!isNaN(last) && elapsed < COOLDOWN_MS) {
          const remain = Math.ceil((COOLDOWN_MS - elapsed) / 1000);
          return { ok: false, error: 'NEED_COOLDOWN', remain: remain };
        }
      }
      // 只写这两个字段，避免整行覆盖
      await updateFields(userCollection, User, { userId: caller.uid }, {
        nickname: nick,
        nicknameUpdatedAt: new Date().toISOString()
      });
      const saved = await getUserRow(caller.uid);
      if (!saved) { return { ok: false, error: '更新后回读失败' }; }
      return { ok: true, data: toPublicUser(saved) };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 更新头像（云存储下载地址直接存库）：只接受 https 地址，长度上限 500
  async updateAvatar(token: string, url: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const u = (url || '').trim();
      if (u.length > 500) { return { ok: false, error: '头像地址过长' }; }
      if (u !== '' && u.indexOf('https://') !== 0) { return { ok: false, error: '头像地址不合法' }; }
      try {
        await updateFields(userCollection, User, { userId: caller.uid }, { avatarUrl: u });
      } catch (e1) {
        console.warn('[avatar] update failed: ' + String((e1 as Error).message || e1));
        return { ok: false, error: '云数据库缺少 avatarUrl 字段，请先在 AGC 控制台为 User 表添加该列' };
      }
      const saved = await getUserRow(caller.uid);
      if (!saved) { return { ok: false, error: '更新后回读失败' }; }
      return { ok: true, data: toPublicUser(saved) };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // ===== 注销账号 =====
  // 校验密码后彻底删除该用户的全部数据。跨 10 张表，逐表按条件批量删，
  // 最后才删 User 行——任何一步失败都不会留下"删了一半的账号"。
  // 管理员账号不允许自助注销（避免把演示环境的唯一管理员删掉）。
  async deleteAccount(token: string, password: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员账号不支持自助注销，请联系运维处理' }; }

      const me = await getUserRow(caller.uid);
      if (!me) { return { ok: false, error: '用户不存在' }; }
      if (!verifyPassword(password || '', me.password)) {
        return { ok: false, error: '密码错误，无法注销账号' };
      }

      const uid = caller.uid;

      // 1) 先记下自己发过的帖子：别人在这些帖子下的评论/点赞/收藏也要跟着清掉，否则会变成孤儿数据
      const myPostIds: number[] = [];
      try {
        const pres = await forumPostCollection.query().equalTo('authorId', uid).get();
        for (const p of toList(pres) as ForumPost[]) { myPostIds.push(p.postId); }
      } catch (e1) {
        console.warn('[deleteAccount] collect posts failed: ' + String((e1 as Error).message || e1));
      }

      // 2) 健康数据 / 预警 / 违规台账
      await batchDeleteSafe(healthCollection,
        CloudDBZoneObjectOperatorConstraint.build(HealthData).equalTo('userId', uid), 'health');
      await batchDeleteSafe(warningCollection,
        CloudDBZoneObjectOperatorConstraint.build(HealthWarning).equalTo('userId', uid), 'warnings');
      await batchDeleteSafe(forumViolationCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumViolation).equalTo('userId', uid), 'violation');

      // 3) 互动关系：点赞、收藏
      await batchDeleteSafe(forumLikeCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumLike).equalTo('userId', uid), 'likes');
      await batchDeleteSafe(forumFavoriteCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumFavorite).equalTo('userId', uid), 'favorites');

      // 4) 自己写的评论 + 自己帖子下的评论/点赞/收藏（分批 in 查询，单次最多 100 个 id）
      await batchDeleteSafe(forumCommentCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumComment).equalTo('authorId', uid), 'own comments');
      const chunks: number[][] = chunkIds(myPostIds, 100);
      for (const chunk of chunks) {
        await batchDeleteSafe(forumCommentCollection,
          CloudDBZoneObjectOperatorConstraint.build(ForumComment).in('postId', chunk), 'post comments');
        await batchDeleteSafe(forumLikeCollection,
          CloudDBZoneObjectOperatorConstraint.build(ForumLike).in('postId', chunk), 'post likes');
        await batchDeleteSafe(forumFavoriteCollection,
          CloudDBZoneObjectOperatorConstraint.build(ForumFavorite).in('postId', chunk), 'post favorites');
      }
      await batchDeleteSafe(forumPostCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumPost).equalTo('authorId', uid), 'posts');

      // 5) 私信与会话（两侧都要清）
      await batchDeleteSafe(forumPrivateMessageCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumPrivateMessage).equalTo('senderId', uid), 'sent messages');
      await batchDeleteSafe(forumPrivateMessageCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumPrivateMessage).equalTo('receiverId', uid), 'received messages');
      await batchDeleteSafe(forumConversationCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumConversation).equalTo('userId1', uid), 'conv as user1');
      await batchDeleteSafe(forumConversationCollection,
        CloudDBZoneObjectOperatorConstraint.build(ForumConversation).equalTo('userId2', uid), 'conv as user2');

      // 6) 医生被注销：把名下患者解绑，避免他们挂在一个不存在的医生下面
      if (me.role === 'doctor') {
        try {
          const pres = await userCollection.query().equalTo('doctorId', uid).get();
          for (const p of toList(pres) as User[]) {
            await updateFields(userCollection, User, { userId: p.userId }, { doctorId: 0 });
          }
        } catch (e2) {
          console.warn('[deleteAccount] unbind patients failed: ' + String((e2 as Error).message || e2));
        }
      }

      // 7) 最后删账号本身
      await userCollection.delete(me);
      return { ok: true };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // ===== 医生资质审核（管理员） =====

  // 待审核医生列表
  async listPendingDoctors(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'admin') { return { ok: false, error: '无权访问' }; }
      const res = await userCollection.query().equalTo('role', 'doctor').get();
      const pend = (toList(res) as User[])
        .filter((u: User) => licenseState(u) === 'pending')
        .map((u: User) => toPublicUser(u));
      return { ok: true, data: pend };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 审核医生：pass=true 通过（去掉 PENDING 前缀），false 驳回（改成 REJECTED 前缀）
  // 驳回时同时解绑其名下患者，避免患者挂在一个不可用的医生下面
  async reviewDoctor(token: string, doctorId: number, pass: boolean) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'admin') { return { ok: false, error: '无权访问' }; }
      const did = (!doctorId || isNaN(doctorId)) ? 0 : Math.floor(doctorId);
      if (did <= 0) { return { ok: false, error: '医生不存在' }; }
      const target = await getUserRow(did);
      if (!target || target.role !== 'doctor') { return { ok: false, error: '医生不存在' }; }

      const lic = rawLicense(target);
      const nextStatus = (pass === true) ? 'approved' : 'rejected';
      // 通过时把证号写成干净值（顺手清掉历史前缀）；驳回时保留拒绝标记作为冗余
      const nextLicense = (pass === true) ? lic : (LICENSE_REJECTED + lic);
      try {
        await updateFields(userCollection, User, { userId: did }, {
          doctorLicense: nextLicense,
          doctorStatus: nextStatus
        });
      } catch (e1) {
        // doctorStatus 列还没建：只写证号前缀，读取侧仍能正确解析
        console.warn('[review] doctorStatus column missing, fallback to license prefix: ' + String((e1 as Error).message || e1));
        await updateFields(userCollection, User, { userId: did }, { doctorLicense: nextLicense });
      }

      if (pass !== true) {
        const pres = await userCollection.query().equalTo('doctorId', did).get();
        const pts = toList(pres) as User[];
        for (const p of pts) {
          await updateFields(userCollection, User, { userId: p.userId }, { doctorId: 0 });
        }
      }
      const saved = await getUserRow(did);
      return { ok: true, data: saved ? toPublicUser(saved) : null };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // ===== 演示数据 =====
  // 一键生成：演示账号（患者+医生）、近 30 天健康记录、4 条预警、社区帖子/评论/点赞、一段医患对话。
  // 幂等：按"两个账号各自是否已存在 + 患者是否已有健康数据"判断；
  // 并会先做一次自我修复，把历史上重复的演示账号合并成一条（保留最早注册的）。
  async seedDemoData(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'admin') { return { ok: false, error: '仅管理员可生成演示数据' }; }

      const now = Date.now();
      const nowIso = new Date(now).toISOString();

      // ===== 0) 自我修复：同名演示账号只保留最早的一条 =====
      const existedPatient = await dedupeDemoAccount(DEMO_PATIENT_USER, false);
      const existedDoctor = await dedupeDemoAccount(DEMO_DOCTOR_USER, true);

      // ===== 1) 医生：没有就建，已有就确保"已通过审核 + 证号干净" =====
      let d: User;
      if (existedDoctor !== null) {
        d = existedDoctor;
        if (!isDoctorActive(d) || rawLicense(d) !== DEMO_DOCTOR_LICENSE) {
          await updateFields(userCollection, User, { userId: d.userId }, {
            doctorLicense: DEMO_DOCTOR_LICENSE,
            doctorStatus: 'approved'
          });
          d.doctorLicense = DEMO_DOCTOR_LICENSE;
          d.doctorStatus = 'approved';
        }
      } else {
        d = new User();
        d.userId = newId();
        d.username = DEMO_DOCTOR_USER;
        d.password = hashPassword(DEMO_PASSWORD);
        d.email = 'demo.doctor@example.com';
        d.phone = '13800000002';
        d.gender = 'female';
        d.role = 'doctor';
        d.dateOfBirth = '1980-09-02';
        d.doctorLicense = DEMO_DOCTOR_LICENSE;
        d.doctorStatus = 'approved';
        d.doctorId = 0;
        d.createdAt = nowIso;
        d.nickname = '李医生';
        d.nicknameUpdatedAt = '';
        await insertUserRow(d, DEMO_DOCTOR_LICENSE, 'approved');
      }

      // ===== 2) 患者：没有就建 =====
      let p: User;
      if (existedPatient !== null) {
        p = existedPatient;
      } else {
        p = new User();
        p.userId = newId();
        p.username = DEMO_PATIENT_USER;
        p.password = hashPassword(DEMO_PASSWORD);
        p.email = 'demo.patient@example.com';
        p.phone = '13800000001';
        p.gender = 'male';
        p.role = 'patient';
        p.dateOfBirth = '1962-04-18';
        p.doctorLicense = '';
        p.doctorStatus = '';
        p.doctorId = 0;
        p.createdAt = nowIso;
        p.nickname = '老张';
        p.nicknameUpdatedAt = '';
        await insertUserRow(p, '', '');
      }

      // ===== 3) 绑定关系（每次都对一遍，修复历史解绑）=====
      if (p.doctorId !== d.userId) {
        await updateFields(userCollection, User, { userId: p.userId }, { doctorId: d.userId });
      }

      // ===== 4) 患者已有健康记录 → 说明内容已经灌过，不再重复生成 =====
      const existedHealth = await healthCollection.query().equalTo('userId', p.userId).get();
      if (toList(existedHealth).length > 0) {
        return {
          ok: true,
          already: true,
          message: '演示数据已存在，未重复生成',
          data: { patientUser: DEMO_PATIENT_USER, doctorUser: DEMO_DOCTOR_USER, password: DEMO_PASSWORD }
        };
      }

      // ===== 2) 近 30 天健康记录 =====
      const healthRows: HealthData[] = [];
      for (let back = 29; back >= 0; back--) {
        const day = new Date(now - back * 86400000);
        day.setHours(8, 30, 0, 0);
        const phase = (29 - back) % 7;
        let sys = 126 + (phase % 4) * 3;
        let dia = 80 + (phase % 3) * 2;
        let sugar = Math.round((5.8 + (phase % 5) * 0.3) * 10) / 10;
        let hr = 73 + (phase % 4) * 3;
        let wt = Math.round((68.6 - (29 - back) * 0.04) * 10) / 10;
        let note = '';
        // 两个明显异常点：趋势图与预警都不会空着
        if (back === 12) { sys = 158; dia = 98; note = '昨晚应酬，睡得晚'; }
        if (back === 5) { sugar = 9.6; note = '早餐吃了两个包子'; }

        const h = new HealthData();
        h.dataId = newId();
        h.userId = p.userId;
        h.bloodPressureSystolic = sys;
        h.bloodPressureDiastolic = dia;
        h.bloodSugar = sugar;
        h.weight = wt;
        h.heartRate = hr;
        h.exerciseType = phase % 3 === 0 ? '散步' : '';
        h.exerciseDuration = phase % 3 === 0 ? 30 : 0;
        h.exerciseCalories = phase % 3 === 0 ? 120 : 0;
        h.recordTime = day.toISOString();
        h.dataSource = 'user_input';
        h.notes = note;
        healthRows.push(h);
      }
      await healthCollection.insert(healthRows);

      // ===== 3) 预警：2 条未处理 + 2 条已处理 =====
      const warnRows: HealthWarning[] = [];
      const addWarn = (type: string, msg: string, sev: string, acked: boolean, daysAgo: number) => {
        const w = new HealthWarning();
        w.warningId = newId();
        w.userId = p.userId;
        w.warningType = type;
        w.warningMessage = msg;
        w.warningTime = new Date(now - daysAgo * 86400000).toISOString();
        w.acknowledged = acked;
        w.severity = sev;
        warnRows.push(w);
      };
      addWarn('high_blood_pressure', '您的收缩压偏高 (158 mmHg)，超过了正常范围', 'high', false, 12);
      addWarn('high_blood_sugar', '您的血糖偏高 (9.6 mmol/L)，超过了正常范围', 'medium', false, 5);
      addWarn('high_blood_pressure', '您的收缩压偏高 (144 mmHg)，超过了正常范围', 'medium', true, 21);
      addWarn('other', '您的心率偏快 (104 次/分钟)', 'low', true, 18);
      await warningCollection.insert(warnRows);

      // ===== 4) 社区内容 =====
      const posts: ForumPost[] = [];
      const addPost = (authorId: number, role: string, title: string, body: string, dept: string,
        topics: string[], daysAgo: number, likes: number, comments: number) => {
        const post = new ForumPost();
        post.postId = newId();
        post.authorId = authorId;
        post.authorRole = role;
        post.title = title;
        post.content = body;
        post.createdAt = new Date(now - daysAgo * 86400000).toISOString();
        post.likeCount = likes;
        post.commentCount = comments;
        post.status = 0;
        post.mediaUrls = '[]';
        post.dept = dept;
        post.topics = JSON.stringify(topics);
        posts.push(post);
      };
      addPost(p.userId, 'patient', '血压稳定在 130/85 了，说说我这三个月的作息',
        '每天早上六点半量一次血压，晚上九点再量一次，都记在这里。晚饭后固定散步半小时，盐基本戒了。最近三个月基本稳定在 130/85 左右，医生说继续保持。',
        '高血压', ['血压', '运动'], 3, 6, 2);
      addPost(p.userId, 'patient', '刚确诊糖尿病，主食到底该怎么吃？',
        '上周体检查出来血糖高，医生让先控制饮食。想问下大家主食是怎么安排的？米饭能不能吃？',
        '糖尿病', ['饮食'], 6, 4, 1);
      addPost(p.userId, 'patient', '每天散步 30 分钟，坚持一个月的变化',
        '以前爬三楼就喘，现在能连着走四十分钟。血压也降了一点，最重要的是睡得好了。',
        '高血压', ['运动'], 14, 9, 0);
      addPost(d.userId, 'doctor', '【医生提醒】换季时血压容易波动，注意这三点',
        '一是早晚温差大，起床不要猛起；二是不要自行加减药；三是如果连续三天血压超过 150/95，请及时联系我。',
        '高血压', ['用药', '血压'], 2, 12, 1);
      await forumPostCollection.insert(posts);

      // 评论（挂在前两篇帖子下）
      const commentRows: ForumComment[] = [];
      const addComment = (post: ForumPost, authorId: number, role: string, body: string, daysAgo: number) => {
        const c = new ForumComment();
        c.commentId = newId();
        c.postId = post.postId;
        c.authorId = authorId;
        c.authorRole = role;
        c.content = body;
        c.createdAt = new Date(now - daysAgo * 86400000).toISOString();
        c.status = 0;
        c.parentId = 0;
        c.mediaUrls = '[]';
        commentRows.push(c);
      };
      addComment(posts[0], d.userId, 'doctor', '记录得很规范，早晚各一次非常好。继续保持，下次复诊带上这些数据。', 2);
      addComment(posts[0], d.userId, 'doctor', '如果早上起床时头晕，记得先坐一会再站起来。', 1);
      addComment(posts[1], d.userId, 'doctor', '主食可以吃，关键是总量和粗细搭配：一半换成杂粮饭，每餐一小碗。', 5);
      addComment(posts[3], p.userId, 'patient', '收到，最近早晚温差确实大，我注意保暖。', 1);
      await forumCommentCollection.insert(commentRows);

      // 点赞（联合主键 postId+userId）
      const likeRows: ForumLike[] = [];
      const addLike = (postId: number, userId: number, daysAgo: number) => {
        const l = new ForumLike();
        l.postId = postId;
        l.userId = userId;
        l.createdAt = new Date(now - daysAgo * 86400000).toISOString();
        likeRows.push(l);
      };
      addLike(posts[0].postId, p.userId, 2);
      addLike(posts[0].postId, d.userId, 2);
      addLike(posts[3].postId, p.userId, 1);
      await forumLikeCollection.insert(likeRows);

      // ===== 5) 一段医患对话（患者提问 + 医生随访建议）=====
      await insertSystemDm(p.userId, d.userId, '李医生您好，最近两天早上起来有点头晕，血压 148/92。');
      await insertSystemDm(d.userId, p.userId,
        '【随访建议】血压 148/92 暂不需要加药。请连续记录一周早晚血压；起床慢一点；如果出现头痛或视物模糊请立即就医。');

      return {
        ok: true,
        message: '演示数据已生成',
        data: {
          patientUser: DEMO_PATIENT_USER,
          doctorUser: DEMO_DOCTOR_USER,
          password: DEMO_PASSWORD,
          healthRecords: healthRows.length,
          warnings: warnRows.length,
          posts: posts.length
        }
      };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // ===== 医生随访建议 =====
  // 以站内私信形式送达患者（复用现有私信表，零改表）。
  // 患者会在「消息」里收到一条以【随访建议】开头的内容，形成"预警 → 医生处理 → 患者收到建议"的闭环。
  async sendFollowUp(token: string, patientId: number, text: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'doctor') { return { ok: false, error: '仅医生可发送随访建议' }; }
      const me = await getUserRow(caller.uid);
      if (!isDoctorActive(me)) { return { ok: false, error: '账号尚未通过资质审核，暂不能发送建议' }; }

      const pid = (!patientId || isNaN(patientId)) ? 0 : Math.floor(patientId);
      if (pid <= 0) { return { ok: false, error: '患者不存在' }; }
      const patient = await getUserRow(pid);
      if (!patient || patient.role !== 'patient') { return { ok: false, error: '患者不存在' }; }
      if (patient.doctorId !== caller.uid) { return { ok: false, error: '该患者不在你的名下' }; }

      const body = (text || '').trim();
      if (body === '') { return { ok: false, error: '请输入建议内容' }; }
      if (body.length > 300) { return { ok: false, error: '建议内容不能超过 300 字' }; }
      if (matchSensitive(body).length > 0) { return { ok: false, error: '内容包含违规词' }; }

      await insertSystemDm(caller.uid, pid, '【随访建议】' + body);
      return { ok: true };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 患者绑定/更换医生
  async bindDoctor(token: string, doctorId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'patient') { return { ok: false, error: '仅患者可绑定医生' }; }
      const row = await getUserRow(caller.uid);
      if (!row) { return { ok: false, error: '用户不存在' }; }

      // 目标必须是真实存在的医生账号：不校验的话，随便传一个 userId 就能绑定到患者/管理员头上，
      // 之后该"医生"若恰好是医生角色以外的人，数据可见性会变得很诡异。
      const did = (!doctorId || isNaN(doctorId)) ? 0 : Math.floor(doctorId);
      if (did <= 0) { return { ok: false, error: '请选择医生' }; }
      if (did === caller.uid) { return { ok: false, error: '不能绑定自己' }; }
      const target = await getUserRow(did);
      if (!target || target.role !== 'doctor') { return { ok: false, error: '该医生不存在' }; }
      // 未通过资质审核的医生不能被绑定——否则冒充注册的账号也能拿到患者数据
      if (!isDoctorActive(target)) { return { ok: false, error: '该医生尚未通过资质审核，暂不能绑定' }; }

      // 只更新 doctorId，其它列不动
      await updateFields(userCollection, User, { userId: caller.uid }, { doctorId: did });
      const saved = await getUserRow(caller.uid);
      if (!saved) { return { ok: false, error: '绑定后回读失败' }; }
      return { ok: true, data: toPublicUser(saved) };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async addHealthData(token: string, systolic: number, diastolic: number, bloodSugar: number, heartRate: number, weight: number, notes: string, exerciseType: string, exerciseDuration: number, exerciseCalories: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }

      // 统一转型 + 区间校验：挡住负数、明显笔误和乱填的值。
      // 不校验的话，脏数据会直接进趋势图、预警判定和 AI 报告。
      const sys = toNum(systolic);
      const dia = toNum(diastolic);
      const sugar = toNum(bloodSugar);
      const hr = toNum(heartRate);
      const wt = toNum(weight);
      const dur = Math.round(toNum(exerciseDuration));
      const cal = Math.round(toNum(exerciseCalories));
      const exType = (exerciseType || '').trim();
      const note = (notes || '').trim();

      if (sys < 0 || dia < 0 || sugar < 0 || hr < 0 || wt < 0 || dur < 0 || cal < 0) {
        return { ok: false, error: '数值不能为负数' };
      }
      if (!within(sys, RANGE_SYSTOLIC)) { return { ok: false, error: '收缩压应在 40-300 mmHg 之间' }; }
      if (!within(dia, RANGE_DIASTOLIC)) { return { ok: false, error: '舒张压应在 20-200 mmHg 之间' }; }
      if (!within(sugar, RANGE_SUGAR)) { return { ok: false, error: '血糖应在 0.5-50 mmol/L 之间' }; }
      if (!within(hr, RANGE_HEART_RATE)) { return { ok: false, error: '心率应在 20-250 次/分钟之间' }; }
      if (!within(wt, RANGE_WEIGHT)) { return { ok: false, error: '体重应在 20-400 kg 之间' }; }
      if (dur > RANGE_EXERCISE_MIN[1]) { return { ok: false, error: '运动时长不能超过 1440 分钟' }; }
      if (cal > RANGE_CALORIES[1]) { return { ok: false, error: '消耗热量不能超过 5000 kcal' }; }
      if (note.length > NOTES_MAX) { return { ok: false, error: '备注不能超过 ' + NOTES_MAX + ' 字' }; }
      if (exType.length > TAG_MAX) { return { ok: false, error: '运动类型过长' }; }
      if (exType !== '' && matchSensitive(exType).length > 0) { return { ok: false, error: '运动类型包含违规词' }; }
      if (sys === 0 && dia === 0 && sugar === 0 && hr === 0 && wt === 0 && exType === '' && dur === 0 && cal === 0) {
        return { ok: false, error: '请至少填写一项健康或运动数据' };
      }

      const row = new HealthData();
      row.dataId = newId();
      row.userId = caller.uid;
      row.bloodPressureSystolic = sys;
      row.bloodPressureDiastolic = dia;
      row.bloodSugar = sugar;
      row.weight = wt;
      row.heartRate = hr;
      row.exerciseType = exType;
      row.exerciseDuration = dur;
      row.exerciseCalories = cal;
      row.recordTime = new Date().toISOString();
      row.dataSource = 'user_input';
      row.notes = note;
      await healthCollection.insert(row);
      await generateWarnings(caller.uid, row);
      return { ok: true, data: toPublicHealth(row) };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async listMyHealthData(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const rows = await loadHealthRows(caller.uid);
      const list = rows.map((h: HealthData) => toPublicHealth(h));
      return { ok: true, data: list };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async getUserHealthData(token: string, userId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (!(await canView(caller, userId))) { return { ok: false, error: '无权查看该患者数据' }; }
      const rows = await loadHealthRows(userId);
      const list = rows.map((h: HealthData) => toPublicHealth(h));
      return { ok: true, data: list };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async listMyWarnings(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const res = await warningCollection.query().equalTo('userId', caller.uid).get();
      const list = sortByTimeDesc(toList(res), 'warningTime').map((w: HealthWarning) => toPublicWarning(w));
      return { ok: true, data: list };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async getUserWarnings(token: string, userId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (!(await canView(caller, userId))) { return { ok: false, error: '无权查看该患者预警' }; }
      const res = await warningCollection.query().equalTo('userId', userId).get();
      const list = sortByTimeDesc(toList(res), 'warningTime').map((w: HealthWarning) => toPublicWarning(w));
      return { ok: true, data: list };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async acknowledgeWarning(token: string, warningId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const res = await warningCollection.query().equalTo('warningId', warningId).get();
      const rows = toList(res);
      if (rows.length === 0) { return { ok: true }; }
      const w = rows[0] as HealthWarning;
      // 谁能处理这条预警：本人 / 管理员 / 该患者绑定的、已通过审核的医生
      let allowed: boolean = (w.userId === caller.uid) || (caller.role === 'admin');
      if (!allowed && caller.role === 'doctor') {
        const me = await getUserRow(caller.uid);
        const patient = await getUserRow(w.userId);
        allowed = isDoctorActive(me) && !!patient && patient.role === 'patient' && patient.doctorId === caller.uid;
      }
      if (!allowed) { return { ok: false, error: '无权操作该预警' }; }
      if (w.acknowledged) { return { ok: true }; }   // 幂等：已确认过就直接返回
      await updateFields(warningCollection, HealthWarning, { warningId: warningId }, { acknowledged: true });
      return { ok: true };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  async unackCount(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      // 只要数字，不要行：countQuery 由云端直接计数，避免把整张预警表传回来再数
      try {
        const cnt = await warningCollection.query()
          .equalTo('userId', caller.uid)
          .equalTo('acknowledged', false)
          .countQuery('warningId');
        return { ok: true, data: Number(cnt) };
      } catch (e1) {
        // countQuery 不可用时退回读行计数
        const res = await warningCollection.query().equalTo('userId', caller.uid).get();
        const un = toList(res).filter((w: HealthWarning) => !w.acknowledged).length;
        return { ok: true, data: un };
      }
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // ===== AI 健康报告：服务端读该用户近30天数据 -> 组 prompt -> 调 DeepSeek -> 返回结构化报告 =====
  async generateHealthReport(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const user = await getUserRow(caller.uid);
      if (!user) { return { ok: false, error: '用户不存在' }; }

      // 服务端缓存：同一用户的报告在有效期内直接复用，避免每次进页面都烧一次 DeepSeek 调用
      const now = Date.now();
      const hit = aiReportCache[caller.uid];
      if (hit && now - hit.at < AI_REPORT_CACHE_MS) {
        return { ok: true, data: hit.data, generatedAt: hit.generatedAt, sampleCount: hit.sampleCount, cached: true };
      }
      // 限流：两次强制生成之间留最小间隔，挡住连点"重新生成"
      const lastCall = aiReportLastCall[caller.uid];
      if (lastCall && now - lastCall < AI_REPORT_COOLDOWN_MS) {
        const wait = Math.ceil((AI_REPORT_COOLDOWN_MS - (now - lastCall)) / 1000);
        return { ok: false, error: 'AI 生成较慢，请 ' + wait + ' 秒后再试' };
      }
      aiReportLastCall[caller.uid] = now;

      // 只取近 30 天的记录（按 recordTime 下界过滤），不再把全部历史都传进云函数内存
      const cutoffIso = new Date(now - 30 * 24 * 60 * 60 * 1000).toISOString();
      let rows: HealthData[] = [];
      try {
        const res = await healthCollection.query()
          .equalTo('userId', caller.uid)
          .greaterThanOrEqualTo('recordTime', cutoffIso)
          .get();
        rows = sortByTimeDesc(toList(res), 'recordTime') as HealthData[];
      } catch (e1) {
        rows = await loadHealthRows(caller.uid);
      }
      if (rows.length === 0) {
        // 近 30 天没数据时，再确认一下是不是"完全没录过"，好给出不同文案
        const all = await loadHealthRows(caller.uid);
        if (all.length === 0) {
          return { ok: false, error: 'NO_DATA', message: '您还没有录入健康数据，先去添加几条记录再来看 AI 报告吧' };
        }
        return { ok: false, error: 'NO_DATA', message: '近30天没有可统计的健康数据，请补充近期记录后再生成' };
      }

      const stats = buildStats(rows);
      if (stats.length === 0) {
        return { ok: false, error: 'NO_DATA', message: '近30天没有可统计的健康数据，请补充近期记录后再生成' };
      }

      const systemPrompt = '你是严谨的慢病健康管理助手，只依据提供的数据给出一般性健康参考，不做诊断、不开处方，' +
        '涉及用药或异常时提示就医。所有文字用简体中文，务必只输出合法 JSON。';
      const userPrompt = buildUserPrompt(user, stats, buildExerciseSummary(rows));
      const raw = await callDeepSeek(systemPrompt, userPrompt);
      const obj = extractJsonObject(raw);
      if (!obj) {
        return { ok: false, error: 'AI 返回格式异常，请稍后重试' };
      }

      // 归一化：缺字段给默认值，避免端侧渲染崩溃
      const s = (v: any): string => (typeof v === 'string' ? v : (v === undefined || v === null ? '' : String(v)));
      let risk = s(obj['riskLevel']).toLowerCase();
      if (risk !== 'medium' && risk !== 'high') { risk = 'low'; }
      const rawMetrics: any[] = Array.isArray(obj['metrics']) ? (obj['metrics'] as any[]) : [];
      const metrics = rawMetrics.map((m: any) => ({
        name: s(m['name']),
        status: s(m['status']),
        detail: s(m['detail'])
      }));
      const report = {
        riskLevel: risk,
        overallAssessment: s(obj['overallAssessment']),
        metrics: metrics,
        trendAnalysis: s(obj['trendAnalysis']),
        dietAdvice: s(obj['dietAdvice']),
        exerciseAdvice: s(obj['exerciseAdvice']),
        lifestyleAdvice: s(obj['lifestyleAdvice']),
        followUpAdvice: s(obj['followUpAdvice']),
        redFlags: s(obj['redFlags'])
      };
      const generatedAt = new Date().toISOString();
      // 记录参与统计的窗口与条数，便于端侧展示"基于 N 条数据"
      const sampleCount = rows.length;
      aiReportCache[caller.uid] = { at: Date.now(), data: report, generatedAt: generatedAt, sampleCount: sampleCount };
      return { ok: true, data: report, generatedAt: generatedAt, sampleCount: sampleCount };
    } catch (e) {
      return { ok: false, error: String((e as Error).message || e) };
    }
  }

  // ==================== 论坛 Phase ①（纯文字） ====================

  // 发帖：管理员不参与；先过禁言门槛，再验长度，命中敏感词即拦截并累计违规
  async createPost(token: string, title: string, content: string, mediaUrlsJson: string, deptJson: string, topicsJson: string, mentionIdsJson: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员账号不参与发帖' }; }

      const vio = await getViolationRow(caller.uid);
      if (isMutedNow(vio)) { return { ok: false, error: '您因多次违规已被临时禁言，请稍后再试' }; }

      const t = (title || '').trim();
      const c = (content || '').trim();

      // 清洗图片地址：只保留非空字符串，限量，重新序列化成干净的 JSON 数组
      const mediaUrls = sanitizeMediaUrls(mediaUrlsJson);
      const mediaJson = JSON.stringify(mediaUrls);

      // 清洗标签：科室单选（可空），话题多选去重限量
      const dept = (deptJson || '').trim();
      const topics = sanitizeTopics(topicsJson);
      const topicsJson2 = JSON.stringify(topics);

      if (c === '' && mediaUrls.length === 0) { return { ok: false, error: '正文和图片至少填一项' }; }
      if (t.length > TITLE_MAX) { return { ok: false, error: '标题不能超过 ' + TITLE_MAX + ' 字' }; }
      if (c.length > POST_CONTENT_MAX) { return { ok: false, error: '正文不能超过 ' + POST_CONTENT_MAX + ' 字' }; }
      // 标签也会被全站展示，长度与敏感词一并校验（端侧限定枚举，但服务端不能只信端侧）
      if (dept.length > TAG_MAX) { return { ok: false, error: '病种标签过长' }; }
      if (dept !== '' && matchSensitive(dept).length > 0) { return { ok: false, error: '病种标签包含违规词' }; }
      for (let i = 0; i < topics.length; i++) {
        if (topics[i].length > TAG_MAX) { return { ok: false, error: '话题标签过长' }; }
        if (matchSensitive(topics[i]).length > 0) { return { ok: false, error: '话题标签包含违规词' }; }
      }

      const matched = matchSensitive(t + ' ' + c);
      if (matched.length > 0) {
        const res = await registerViolation(caller.uid);
        const msg = res.muteSec > 0
          ? ('内容含违规词，已拦截并禁言 ' + res.muteText + '（累计违规 ' + res.violationCount + ' 次）')
          : ('内容含违规词，已拦截（违规提醒 ' + res.violationCount + ' 次）');
        return { ok: false, error: msg };
      }

      const me = await getUserRow(caller.uid);
      const authorName = me ? forumDisplayName(me.nickname, me.username, me.userId) : ('用户' + caller.uid);
      const post = new ForumPost();
      post.postId = newId();
      post.authorId = caller.uid;
      post.authorRole = caller.role;
      post.title = t === '' ? '（无标题）' : t;
      post.content = c;
      post.createdAt = new Date().toISOString();
      post.likeCount = 0;
      post.commentCount = 0;
      post.status = 0;
      post.mediaUrls = mediaJson;
      post.dept = dept;
      post.topics = topicsJson2;
      await forumPostCollection.insert(post);
      // 发帖成功 → 给被 @ 的人各发一条私信通知（不影响发帖结果，内部已吞异常）
      const mentionIds = sanitizeMentionIds(mentionIdsJson);
      if (mentionIds.length > 0) {
        await notifyMentions(caller.uid, post.postId, mentionIds, post.title, c);
      }
      return { ok: true, data: toPublicPost(post, authorName, false, undefined, undefined, me ? (me.avatarUrl === undefined ? '' : me.avatarUrl) : '') };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 帖子列表：只返回未删除，时间倒序，分页；可选按科室/话题标签筛选；管理员可另调 adminListPosts 看全量
  async listPosts(token: string, page: number, deptFilter: string, topicFilter: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const pageNum = (!page || isNaN(page)) ? 0 : Math.floor(page);
      const df = (deptFilter || '').trim();
      const tf = (topicFilter || '').trim();
      const offset = pageNum * FORUM_PAGE_SIZE;

      let slice: ForumPost[] = [];
      let hasMore = false;
      let fastDone = false;

      // 快路径：不筛选时由服务端按 createdAt 倒序取一页，只回传 20 条。
      // （分页查询只允许一个 equalTo + 一个 orderBy，所以 status 之外的条件不能带，
      //   带标签筛选时走下面的慢路径。）
      if (df === '' && tf === '') {
        const paged = await pagedSlice(
          forumPostCollection.query()
            .equalTo('status', 0)
            .orderByDesc('createdAt')
            .limit(FORUM_PAGE_SIZE + 1, offset),
          FORUM_PAGE_SIZE);
        if (paged !== null) {
          slice = paged.rows as ForumPost[];
          hasMore = paged.hasMore;
          fastDone = true;
        }
      }

      // 慢路径：带标签筛选，或快路径因缺索引被拒——沿用原来的全量过滤，保证结果正确
      if (!fastDone) {
        const res = await forumPostCollection.query().get();
        let all = sortByTimeDesc(toList(res) as ForumPost[], 'createdAt').filter((p: ForumPost) => p.status === 0);
        if (df !== '') {
          all = all.filter((p: ForumPost) => (p.dept || '') === df);
        }
        if (tf !== '') {
          all = all.filter((p: ForumPost) => sanitizeTopics(p.topics || '').indexOf(tf) >= 0);
        }
        slice = all.slice(offset, offset + FORUM_PAGE_SIZE);
        hasMore = (pageNum + 1) * FORUM_PAGE_SIZE < all.length;
      }

      const authorIds: number[] = [];
      const postIds: number[] = [];
      for (const p of slice) {
        authorIds.push(p.authorId);
        postIds.push(p.postId);
      }
      const map = await loadAuthorMapByIds(authorIds);
      const liked = await loadLikedPostIds(caller.uid);
      const fav = await loadFavoritedPostIds(caller.uid);
      const ccMap = await commentCountsFor(postIds);
      const data = slice.map((p: ForumPost) => toPublicPost(
        p, map[p.authorId] ? map[p.authorId].name : ('用户' + p.authorId), !!liked[p.postId], ccMap[p.postId] || 0, !!fav[p.postId], map[p.authorId] ? map[p.authorId].avatar : ''));
      return { ok: true, data: data, hasMore: hasMore };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 搜索帖子：按关键词在标题/正文里做不区分大小写的"包含"匹配，时间倒序，分页
  // 说明：CloudDB 没有全文检索，只能把候选集拉回内存匹配。这里限定"最新 N 条"作为候选集，
  // 避免帖子量大了以后每次搜索都全表回传（N 之外的旧帖不参与搜索，属于已知取舍）。
  async searchPosts(token: string, keyword: string, page: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const kw = (keyword || '').trim().toLowerCase();
      const pageNum = (!page || isNaN(page)) ? 0 : Math.floor(page);
      if (kw === '') { return { ok: true, data: [], hasMore: false }; }

      let candidates: ForumPost[] | null = null;
      const windowed = await pagedSlice(
        forumPostCollection.query().orderByDesc('createdAt').limit(SEARCH_SCAN_LIMIT, 0),
        SEARCH_SCAN_LIMIT);
      if (windowed !== null) {
        candidates = windowed.rows as ForumPost[];
      } else {
        const res = await forumPostCollection.query().get();
        candidates = toList(res) as ForumPost[];
      }

      const all = sortByTimeDesc(candidates, 'createdAt')
        .filter((p: ForumPost) => p.status === 0)
        .filter((p: ForumPost) => {
          const title = (p.title || '').toLowerCase();
          const content = (p.content || '').toLowerCase();
          return title.indexOf(kw) >= 0 || content.indexOf(kw) >= 0;
        });
      const slice = all.slice(pageNum * FORUM_PAGE_SIZE, pageNum * FORUM_PAGE_SIZE + FORUM_PAGE_SIZE);
      const authorIds: number[] = [];
      const postIds: number[] = [];
      for (const p of slice) {
        authorIds.push(p.authorId);
        postIds.push(p.postId);
      }
      const map = await loadAuthorMapByIds(authorIds);
      const liked = await loadLikedPostIds(caller.uid);
      const fav = await loadFavoritedPostIds(caller.uid);
      const ccMap = await commentCountsFor(postIds);
      const data = slice.map((p: ForumPost) => toPublicPost(
        p, map[p.authorId] ? map[p.authorId].name : ('用户' + p.authorId), !!liked[p.postId], ccMap[p.postId] || 0, !!fav[p.postId], map[p.authorId] ? map[p.authorId].avatar : ''));
      return { ok: true, data: data, hasMore: (pageNum + 1) * FORUM_PAGE_SIZE < all.length };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 帖子详情：已删除的帖子非管理员看不到
  async getPost(token: string, postId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const res = await forumPostCollection.query().equalTo('postId', postId).get();
      const rows = toList(res);
      if (rows.length === 0) { return { ok: false, error: '帖子不存在' }; }
      const p = rows[0] as ForumPost;
      if (p.status === 1 && caller.role !== 'admin') { return { ok: false, error: '该帖子已被删除' }; }
      const author = await getUserRow(p.authorId);
      const authorName = author ? forumDisplayName(author.nickname, author.username, author.userId) : ('用户' + p.authorId);
      const liked = await forumLikeCollection.query().equalTo('postId', postId).equalTo('userId', caller.uid).get();
      const isLiked = toList(liked).length > 0;
      const favRes = await forumFavoriteCollection.query().equalTo('postId', postId).equalTo('userId', caller.uid).get();
      const isFavorited = toList(favRes).length > 0;
      const realCount = await countActiveComments(postId);
      return { ok: true, data: toPublicPost(p, authorName, isLiked, realCount, isFavorited, author ? (author.avatarUrl === undefined ? '' : author.avatarUrl) : '') };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 删除帖子（软删）：作者本人或管理员可删；用新实例整行回写避免快照 upsert 被忽略
  async deletePost(token: string, postId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const res = await forumPostCollection.query().equalTo('postId', postId).get();
      const rows = toList(res);
      if (rows.length === 0) { return { ok: false, error: '帖子不存在' }; }
      const p = rows[0] as ForumPost;
      if (p.authorId !== caller.uid && caller.role !== 'admin') { return { ok: false, error: '无权删除该帖子' }; }
      if (p.status === 1) { return { ok: true }; }   // 幂等：已删过直接返回
      await updateFields(forumPostCollection, ForumPost, { postId: postId }, { status: 1 });

      // 级联清理子行：帖子软删后，评论/点赞/收藏若留着就是孤儿数据——
      // 「我的收藏」会出现点不开的空壳条目、详情页评论数与实际对不上。
      // 评论保持软删（留审计痕迹）；点赞、收藏是纯关系行，直接物理删除。
      // 清理失败不影响帖子已删除这一结果，只记日志，避免用户重复点删除都失败。
      try {
        await forumCommentCollection.batchUpdateByCondition(
          CloudDBZoneObjectOperator.build(new ForumComment()).update('status', 1),
          CloudDBZoneObjectOperatorConstraint.build(ForumComment).equalTo('postId', postId)
        );
      } catch (e1) {
        console.error('[deletePost] cascade comments failed: ' + String((e1 as Error).message || e1));
      }
      try {
        await forumLikeCollection.batchDeleteByCondition(
          CloudDBZoneObjectOperatorConstraint.build(ForumLike).equalTo('postId', postId)
        );
      } catch (e2) {
        console.error('[deletePost] cascade likes failed: ' + String((e2 as Error).message || e2));
      }
      try {
        await forumFavoriteCollection.batchDeleteByCondition(
          CloudDBZoneObjectOperatorConstraint.build(ForumFavorite).equalTo('postId', postId)
        );
      } catch (e3) {
        console.error('[deletePost] cascade favorites failed: ' + String((e3 as Error).message || e3));
      }
      return { ok: true };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 评论列表：某帖未删除评论，按时间正序
  async listComments(token: string, postId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const res = await forumCommentCollection.query().equalTo('postId', postId).get();
      const list = sortByTimeAsc((toList(res) as ForumComment[]).filter((c: ForumComment) => c.status === 0), 'createdAt');
      const authorIds: number[] = [];
      for (const c of list) { authorIds.push(c.authorId); }
      const map = await loadAuthorMapByIds(authorIds);
      const data = list.map((c: ForumComment) => toPublicComment(c,
        map[c.authorId] ? map[c.authorId].name : ('用户' + c.authorId),
        map[c.authorId] ? map[c.authorId].avatar : ''));
      return { ok: true, data: data };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 发评论/回复：管理员不参与；同样过禁言 + 敏感词；成功则给所属帖子评论数 +1
  // parentId=0 为主评论；>0 为对某条评论的回复（回复的回复也并进同一主评论线程）
  async addComment(token: string, postId: number, content: string, parentId: number, mediaUrlsJson: string, mentionIdsJson: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员账号不参与发言' }; }

      const vio = await getViolationRow(caller.uid);
      if (isMutedNow(vio)) { return { ok: false, error: '您因多次违规已被临时禁言，请稍后再试' }; }

      const c = (content || '').trim();
      const mediaUrls = sanitizeMediaUrls(mediaUrlsJson);
      const mediaJson = JSON.stringify(mediaUrls);
      if (c === '' && mediaUrls.length === 0) { return { ok: false, error: '评论和图片至少填一项' }; }
      if (c.length > COMMENT_MAX) { return { ok: false, error: '评论不能超过 ' + COMMENT_MAX + ' 字' }; }

      const matched = matchSensitive(c);
      if (matched.length > 0) {
        const res = await registerViolation(caller.uid);
        const msg = res.muteSec > 0
          ? ('评论含违规词，已拦截并禁言 ' + res.muteText + '（累计违规 ' + res.violationCount + ' 次）')
          : ('评论含违规词，已拦截（违规提醒 ' + res.violationCount + ' 次）');
        return { ok: false, error: msg };
      }

      const pres = await forumPostCollection.query().equalTo('postId', postId).get();
      const prows = toList(pres);
      if (prows.length === 0 || (prows[0] as ForumPost).status === 1) { return { ok: false, error: '帖子不存在或已删除' }; }
      const post = prows[0] as ForumPost;

      // 校验 parentId：非 0 时必须是对本帖一条未删除的评论
      const pid = (!parentId || isNaN(parentId)) ? 0 : Math.floor(parentId);
      if (pid > 0) {
        const parentRes = await forumCommentCollection.query().equalTo('commentId', pid).get();
        const parentRows = toList(parentRes);
        if (parentRows.length === 0) { return { ok: false, error: '要回复的评论不存在' }; }
        const parent = parentRows[0] as ForumComment;
        if (parent.status === 1 || parent.postId !== postId) { return { ok: false, error: '要回复的评论不存在' }; }
      }

      const me = await getUserRow(caller.uid);
      const authorName = me ? forumDisplayName(me.nickname, me.username, me.userId) : ('用户' + caller.uid);
      const comment = new ForumComment();
      comment.commentId = newId();
      comment.postId = postId;
      comment.authorId = caller.uid;
      comment.authorRole = caller.role;
      comment.content = c;
      comment.createdAt = new Date().toISOString();
      comment.status = 0;
      comment.parentId = pid;
      comment.mediaUrls = mediaJson;
      await forumCommentCollection.insert(comment);

      // 评论数以子表真实未删除行数为权威，不再做 +1 自增（自增在并发下会漂移）
      const realCount = await countActiveComments(postId);
      await updateFields(forumPostCollection, ForumPost, { postId: postId }, { commentCount: realCount });

      // 评论成功 → 给被 @ 的人各发一条私信通知（不影响评论结果，内部已吞异常）
      const mentionIds = sanitizeMentionIds(mentionIdsJson);
      if (mentionIds.length > 0) {
        await notifyMentions(caller.uid, postId, mentionIds, post.title, c);
      }

      return { ok: true, data: toPublicComment(comment, authorName, me ? (me.avatarUrl === undefined ? '' : me.avatarUrl) : '') };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 删除评论（软删）：评论作者 / 帖子作者 / 管理员可删；成功则帖子评论数 -1（不小于 0）
  async deleteComment(token: string, commentId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const cres = await forumCommentCollection.query().equalTo('commentId', commentId).get();
      const crows = toList(cres);
      if (crows.length === 0) { return { ok: false, error: '评论不存在' }; }
      const cm = crows[0] as ForumComment;

      const pres = await forumPostCollection.query().equalTo('postId', cm.postId).get();
      const prows = toList(pres);
      const post = prows.length > 0 ? (prows[0] as ForumPost) : null;

      const canDelete = cm.authorId === caller.uid || (post && post.authorId === caller.uid) || caller.role === 'admin';
      if (!canDelete) { return { ok: false, error: '无权删除该评论' }; }

      const updated = new ForumComment();
      updated.commentId = cm.commentId;
      updated.postId = cm.postId;
      updated.authorId = cm.authorId;
      updated.authorRole = cm.authorRole;
      updated.content = cm.content;
      updated.createdAt = cm.createdAt;
      updated.status = 1;
      await forumCommentCollection.upsert(updated);

      if (post && post.status === 0) {
        const realCount = await countActiveComments(post.postId);
        await updateFields(forumPostCollection, ForumPost, { postId: post.postId }, { commentCount: realCount });
      }
      return { ok: true };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 点赞/取消：联合主键 (postId,userId) 天然去重，有点就删、没点就插，并同步帖子 likeCount
  async toggleLike(token: string, postId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const pres = await forumPostCollection.query().equalTo('postId', postId).get();
      const prows = toList(pres);
      if (prows.length === 0 || (prows[0] as ForumPost).status === 1) { return { ok: false, error: '帖子不存在或已删除' }; }
      const post = prows[0] as ForumPost;

      const lres = await forumLikeCollection.query().equalTo('postId', postId).equalTo('userId', caller.uid).get();
      const lrows = toList(lres);
      let liked: boolean;
      if (lrows.length > 0) {
        const del = new ForumLike();
        del.postId = postId;
        del.userId = caller.uid;
        del.createdAt = (lrows[0] as ForumLike).createdAt;
        await forumLikeCollection.delete(del);
        liked = false;
      } else {
        const add = new ForumLike();
        add.postId = postId;
        add.userId = caller.uid;
        add.createdAt = new Date().toISOString();
        await forumLikeCollection.insert(add);
        liked = true;
      }

      // 点赞数以点赞子表真实行数为权威：原来的 likeCount±1 在并发点击或历史脏数据下会越走越偏
      const allLikes = await forumLikeCollection.query().equalTo('postId', postId).get();
      const newCount = toList(allLikes).length;
      await updateFields(forumPostCollection, ForumPost, { postId: postId }, { likeCount: newCount });
      return { ok: true, liked: liked, likeCount: newCount };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 收藏/取消收藏：联合主键 (postId,userId) 天然去重，有就删、没就插。
  // 收藏只维护"我的收藏"关系，不改动帖子任何计数字段。
  async toggleFavorite(token: string, postId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const pres = await forumPostCollection.query().equalTo('postId', postId).get();
      const prows = toList(pres);
      if (prows.length === 0 || (prows[0] as ForumPost).status === 1) { return { ok: false, error: '帖子不存在或已删除' }; }

      const cres = await forumFavoriteCollection.query().equalTo('postId', postId).equalTo('userId', caller.uid).get();
      const crows = toList(cres);
      let favorited: boolean;
      if (crows.length > 0) {
        const del = new ForumFavorite();
        del.postId = postId;
        del.userId = caller.uid;
        del.createdAt = (crows[0] as ForumFavorite).createdAt;
        await forumFavoriteCollection.delete(del);
        favorited = false;
      } else {
        const add = new ForumFavorite();
        add.postId = postId;
        add.userId = caller.uid;
        add.createdAt = new Date().toISOString();
        await forumFavoriteCollection.insert(add);
        favorited = true;
      }
      return { ok: true, favorited: favorited };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 我的收藏列表：只返回我收藏且未删除的帖子，按收藏时间倒序（新收藏在前），分页。
  async listFavorites(token: string, page: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const pageNum = (!page || isNaN(page)) ? 0 : Math.floor(page);
      const offset = pageNum * FORUM_PAGE_SIZE;

      // 先对"收藏关系表"分页（只查我自己的收藏），再按 postId 批量取帖子，
      // 不再把整张帖子表拉回来做过滤。
      let favPage: ForumFavorite[] = [];
      let hasMore = false;
      const paged = await pagedSlice(
        forumFavoriteCollection.query()
          .equalTo('userId', caller.uid)
          .orderByDesc('createdAt')
          .limit(FORUM_PAGE_SIZE + 1, offset),
        FORUM_PAGE_SIZE);
      if (paged !== null) {
        favPage = paged.rows as ForumFavorite[];
        hasMore = paged.hasMore;
      } else {
        const fres = await forumFavoriteCollection.query().equalTo('userId', caller.uid).get();
        const allFavs = sortByTimeDesc(toList(fres) as ForumFavorite[], 'createdAt') as ForumFavorite[];
        favPage = allFavs.slice(offset, offset + FORUM_PAGE_SIZE);
        hasMore = (pageNum + 1) * FORUM_PAGE_SIZE < allFavs.length;
      }
      if (favPage.length === 0) { return { ok: true, data: [], hasMore: false }; }

      const wanted: number[] = [];
      for (const f of favPage) { wanted.push(f.postId); }
      const pres = await forumPostCollection.query().in('postId', wanted).get();
      const aliveMap: Record<number, ForumPost> = {};
      for (const p of toList(pres) as ForumPost[]) {
        if (p.status === 0) { aliveMap[p.postId] = p; }
      }
      // in 查询不保证顺序，按收藏时间顺序回填
      const slice: ForumPost[] = [];
      for (const f of favPage) {
        const p = aliveMap[f.postId];
        if (p) { slice.push(p); }
      }
      const liked = await loadLikedPostIds(caller.uid);
      const postIds: number[] = [];
      const authorIds: number[] = [];
      for (const p of slice) {
        postIds.push(p.postId);
        authorIds.push(p.authorId);
      }
      const map = await loadAuthorMapByIds(authorIds);
      const ccMap = await commentCountsFor(postIds);
      const data = slice.map((p: ForumPost) => toPublicPost(
        p, map[p.authorId] ? map[p.authorId].name : ('用户' + p.authorId), !!liked[p.postId], ccMap[p.postId] || 0, true, map[p.authorId] ? map[p.authorId].avatar : ''));
      return { ok: true, data: data, hasMore: hasMore };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 我发布的帖子：只返回我自己发的、未删除的帖子，时间倒序分页
  async listMyPosts(token: string, page: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const pageNum = (!page || isNaN(page)) ? 0 : Math.floor(page);
      const offset = pageNum * FORUM_PAGE_SIZE;

      let slice: ForumPost[] = [];
      let hasMore = false;
      let fastDone = false;
      // 快路径：authorId 有索引，直接按作者 + createdAt 取一页
      const paged = await pagedSlice(
        forumPostCollection.query()
          .equalTo('authorId', caller.uid)
          .orderByDesc('createdAt')
          .limit(FORUM_PAGE_SIZE + 1, offset),
        FORUM_PAGE_SIZE);
      if (paged !== null) {
        // 分页查询只能带一个条件，status 只能在内存里再筛（自己删掉的帖子很少，误差可接受）
        slice = (paged.rows as ForumPost[]).filter((p: ForumPost) => p.status === 0);
        hasMore = paged.hasMore;
        fastDone = true;
      }
      if (!fastDone) {
        const pres = await forumPostCollection.query().equalTo('authorId', caller.uid).get();
        const mine = sortByTimeDesc(
          (toList(pres) as ForumPost[]).filter((p: ForumPost) => p.status === 0),
          'createdAt') as ForumPost[];
        slice = mine.slice(offset, offset + FORUM_PAGE_SIZE);
        hasMore = (pageNum + 1) * FORUM_PAGE_SIZE < mine.length;
      }
      if (slice.length === 0) { return { ok: true, data: [], hasMore: hasMore }; }

      const postIds: number[] = [];
      const authorIds: number[] = [];
      for (const p of slice) {
        postIds.push(p.postId);
        authorIds.push(p.authorId);
      }
      const map = await loadAuthorMapByIds(authorIds);
      const liked = await loadLikedPostIds(caller.uid);
      const fav = await loadFavoritedPostIds(caller.uid);
      const ccMap = await commentCountsFor(postIds);
      const data = slice.map((p: ForumPost) => toPublicPost(
        p, map[p.authorId] ? map[p.authorId].name : ('用户' + p.authorId), !!liked[p.postId], ccMap[p.postId] || 0, !!fav[p.postId], map[p.authorId] ? map[p.authorId].avatar : ''));
      return { ok: true, data: data, hasMore: hasMore };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 查自己的违规/禁言状态，供论坛页顶部提示条展示
  async myViolation(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const v = await getViolationRow(caller.uid);
      let remainSec = 0;
      if (v && isMutedNow(v)) {
        remainSec = Math.ceil((new Date(v.muteUntil).getTime() - Date.now()) / 1000);
      }
      return {
        ok: true,
        data: {
          violationCount: v ? v.violationCount : 0,
          muted: isMutedNow(v),
          muteRemainText: remainSec > 0 ? formatMute(remainSec) : ''
        }
      };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 管理员专用：查看全部帖子（含已软删），用于审核
  async adminListPosts(token: string, page: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role !== 'admin') { return { ok: false, error: '无权访问' }; }
      const pageNum = (!page || isNaN(page)) ? 0 : Math.floor(page);
      const offset = pageNum * FORUM_PAGE_SIZE;

      let slice: ForumPost[] = [];
      let hasMore = false;
      let fastDone = false;
      // 快路径：退审列表不需要过滤条件，直接按 createdAt 倒序取一页（含已删）
      const paged = await pagedSlice(
        forumPostCollection.query().orderByDesc('createdAt').limit(FORUM_PAGE_SIZE + 1, offset),
        FORUM_PAGE_SIZE);
      if (paged !== null) {
        slice = paged.rows as ForumPost[];
        hasMore = paged.hasMore;
        fastDone = true;
      }
      if (!fastDone) {
        const res = await forumPostCollection.query().get();
        const all = sortByTimeDesc(toList(res) as ForumPost[], 'createdAt') as ForumPost[];
        slice = all.slice(offset, offset + FORUM_PAGE_SIZE);
        hasMore = (pageNum + 1) * FORUM_PAGE_SIZE < all.length;
      }

      const postIds: number[] = [];
      const authorIds: number[] = [];
      for (const p of slice) {
        postIds.push(p.postId);
        authorIds.push(p.authorId);
      }
      const map = await loadAuthorMapByIds(authorIds);
      const ccMap = await commentCountsFor(postIds);
      const data = slice.map((p: ForumPost) => toPublicPost(
        p, map[p.authorId] ? map[p.authorId].name : ('用户' + p.authorId), false, ccMap[p.postId] || 0, false, map[p.authorId] ? map[p.authorId].avatar : ''));
      return { ok: true, data: data, hasMore: hasMore };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 论坛用户公开简介：点开头像弹出的详情卡片所需字段。
  // 只暴露公开信息（昵称/角色/性别/注册时间/发帖数/获赞数/医生执照），绝不返回密码/邮箱/手机/生日/健康数据。
  async getUserBrief(token: string, userId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      const uid = (!userId || isNaN(userId)) ? 0 : Math.floor(userId);
      const u = await getUserRow(uid);
      if (!u) { return { ok: false, error: '用户不存在' }; }
      // 只查这个人的帖子（authorId 有索引），不再全表遍历
      const pres = await forumPostCollection.query().equalTo('authorId', uid).get();
      let postCount = 0;
      let likeTotal = 0;
      for (const p of toList(pres) as ForumPost[]) {
        if (p.status === 0) {
          postCount++;
          likeTotal += (p.likeCount || 0);
        }
      }
      const genderMap: Record<string, string> = { male: '男', female: '女', other: '未填写' };
      const brief: Record<string, Object> = {
        userId: u.userId,
        nickname: forumDisplayName(u.nickname, u.username, u.userId),
        role: u.role,
        genderText: genderMap[u.gender] || '未填写',
        createdAt: u.createdAt,
        postCount: postCount,
        likeTotal: likeTotal,
        doctorLicense: u.role === 'doctor' ? (u.doctorLicense || '') : '',
        avatarUrl: u.avatarUrl === undefined || u.avatarUrl === null ? '' : u.avatarUrl
      };
      return { ok: true, data: brief };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // ===== 私信：会话列表 / 历史消息 / 发送 / 标记已读 / 未读总数 =====
  // 全链路走服务端凭证读写（objecttype 权限仅 Administrator），端侧只经云函数鉴权。
  // 管理员双向排除：既不能主动发，也不作为收信方。

  // 我的会话列表：只保留未删除、我参与的，按最后一条时间倒序；对方昵称在此解析
  async listMyConversations(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员不参与私信' }; }
      // 只查"我是 userId1"和"我是 userId2"两侧，不再全表扫会话
      const r1 = await forumConversationCollection.query().equalTo('userId1', caller.uid).get();
      const r2 = await forumConversationCollection.query().equalTo('userId2', caller.uid).get();
      const mine: ForumConversation[] = [];
      const seen: Record<string, boolean> = {};
      for (const c of toList(r1) as ForumConversation[]) {
        if (c.status === 0 && !seen[c.pairId]) { seen[c.pairId] = true; mine.push(c); }
      }
      for (const c of toList(r2) as ForumConversation[]) {
        if (c.status === 0 && !seen[c.pairId]) { seen[c.pairId] = true; mine.push(c); }
      }
      const sorted = sortByTimeDesc(mine, 'lastCreatedAt') as ForumConversation[];
      const peerIds: number[] = [];
      for (const c of sorted) {
        peerIds.push(c.userId1 === caller.uid ? c.userId2 : c.userId1);
      }
      const map = await loadAuthorMapByIds(peerIds);
      const data = sorted.map((c: ForumConversation) => {
        const peerId = c.userId1 === caller.uid ? c.userId2 : c.userId1;
        const peerName = map[peerId] ? map[peerId].name : ('用户' + peerId);
        return toPublicConversation(c, caller.uid, peerName, map[peerId] ? map[peerId].avatar : '');
      });
      return { ok: true, data: data };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 某会话历史消息：校验我是会话成员；未删除按时间正序。
  // afterIso 非空时只返回该时间之后的消息——端侧轮询据此增量拉取，不必每 4 秒整表重传。
  async listMessages(token: string, pairId: string, afterIso?: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员不参与私信' }; }
      const cres = await forumConversationCollection.query().equalTo('pairId', pairId).get();
      const crows = toList(cres);
      if (crows.length === 0) { return { ok: false, error: '会话不存在' }; }
      const conv = crows[0] as ForumConversation;
      if (conv.userId1 !== caller.uid && conv.userId2 !== caller.uid) { return { ok: false, error: '无权访问该会话' }; }

      const since = (afterIso || '').trim();
      let mres: any;
      if (since !== '') {
        // 增量：只取比游标新的消息（ISO 字符串字典序即时间序）
        mres = await forumPrivateMessageCollection.query()
          .equalTo('pairId', pairId)
          .greaterThanOrEqualTo('createdAt', since)
          .get();
      } else {
        mres = await forumPrivateMessageCollection.query().equalTo('pairId', pairId).get();
      }
      const list = sortByTimeAsc((toList(mres) as ForumPrivateMessage[]).filter((m: ForumPrivateMessage) => m.status === 0), 'createdAt');
      return { ok: true, data: list.map((m: ForumPrivateMessage) => toPublicMessage(m)) };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 发送私信：管理员/自发自收拦截 + 禁言 + 敏感词；支持图片与引用；写消息 + 会话摘要/未读回写
  async sendMessage(token: string, toUserId: number, content: string, mediaUrlsJson?: string, quoteId?: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员不参与私信' }; }
      const to = (!toUserId || isNaN(toUserId)) ? 0 : Math.floor(toUserId);
      if (to === 0) { return { ok: false, error: '对方不存在' }; }
      if (to === caller.uid) { return { ok: false, error: '不能给自己发私信' }; }
      const target = await getUserRow(to);
      if (!target) { return { ok: false, error: '对方不存在' }; }
      if (target.role === 'admin') { return { ok: false, error: '不能向管理员发送私信' }; }

      const vio = await getViolationRow(caller.uid);
      if (isMutedNow(vio)) { return { ok: false, error: '您因多次违规已被临时禁言，请稍后再试' }; }

      // 图片：清洗并按私信上限截断（与评论同一套 sanitizeMediaUrls）
      const media = sanitizeMediaUrls(mediaUrlsJson === undefined ? '' : mediaUrlsJson).slice(0, DM_MAX_MEDIA);
      // 引用：合法正整数才生效
      const qidNum = Number(quoteId);
      const qid = (!quoteId || isNaN(qidNum)) ? 0 : Math.floor(qidNum);

      const c = (content || '').trim();
      if (c === '' && media.length === 0) { return { ok: false, error: '请输入内容或选择图片' }; }
      if (c.length > DM_CONTENT_MAX) { return { ok: false, error: '私信不能超过 ' + DM_CONTENT_MAX + ' 字' }; }

      // 敏感词只查可见文字（图片地址、机器标记不参与）
      if (c !== '') {
        const matched = matchSensitive(c);
        if (matched.length > 0) {
          const rv = await registerViolation(caller.uid);
          const msg = rv.muteSec > 0
            ? ('私信含违规词，已拦截并禁言 ' + rv.muteText + '（累计违规 ' + rv.violationCount + ' 次）')
            : ('私信含违规词，已拦截（违规提醒 ' + rv.violationCount + ' 次）');
          return { ok: false, error: msg };
        }
      }

      const pairId = makePairId(caller.uid, to);
      const now = new Date().toISOString();
      const lo = Math.min(caller.uid, to);
      const hi = Math.max(caller.uid, to);
      // 最终正文：可见文字 + 引用标记（引用以机器标记随正文携带，端侧渲染引用块）
      const finalContent = c + (qid > 0 ? quoteMarker(qid) : '');
      const mediaJson = JSON.stringify(media);

      const msg = new ForumPrivateMessage();
      msg.messageId = newId();
      msg.pairId = pairId;
      msg.senderId = caller.uid;
      msg.receiverId = to;
      msg.content = finalContent;
      msg.createdAt = now;
      msg.readFlag = 0;
      msg.status = 0;
      msg.mediaUrls = mediaJson;
      await forumPrivateMessageCollection.insert(msg);

      // 会话摘要 + 未读（未读取真实行数，见 touchConversation）
      let preview = c.length > DM_PREVIEW_MAX ? c.slice(0, DM_PREVIEW_MAX) : c;
      if (preview === '' && media.length > 0) { preview = '[图片]'; }
      await touchConversation(pairId, lo, hi, caller.uid, preview);

      return { ok: true, data: toPublicMessage(msg) };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 站内分享：把某条帖子以"私信"形式转发给选中的若干人，消息自带帖子标记，对方点「查看原帖」直达详情
  async sharePost(token: string, postId: number, targetIdsJson: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员账号不参与分享' }; }

      const pid = (!postId || isNaN(postId)) ? 0 : Math.floor(postId);
      if (pid === 0) { return { ok: false, error: '帖子不存在' }; }
      const pres = await forumPostCollection.query().equalTo('postId', pid).get();
      const prows = toList(pres);
      if (prows.length === 0 || (prows[0] as ForumPost).status === 1) { return { ok: false, error: '帖子不存在或已删除' }; }
      const post = prows[0] as ForumPost;
      const title = (post.title || '').trim();
      const where = title === '' ? '一条内容' : ('《' + title + '》');

      const ids = sanitizeMentionIds(targetIdsJson);
      if (ids.length === 0) { return { ok: true, data: { shared: 0 } }; }
      const text = '有人给你分享了一条帖子：' + where + postMarker(pid);

      // 一次性把这批人的角色查回来，避免逐人一次网络往返
      const targets = await loadUsersByIds(ids);
      let shared = 0;
      for (let i = 0; i < ids.length; i++) {
        const toUid = ids[i];
        if (toUid <= 0 || toUid === caller.uid) { continue; }
        try {
          const target = targets[toUid];
          if (!target || target.role === 'admin') { continue; }
          await insertSystemDm(caller.uid, toUid, text);
          shared++;
        } catch (e) {
          // 单个转发失败不影响其它人
        }
      }
      return { ok: true, data: { shared: shared } };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 删除单条私信（软删：status=1）；仅限会话参与方，删除后双方都不可见
  async deleteMessage(token: string, messageId: number) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员不参与私信' }; }
      const mid = (!messageId || isNaN(messageId)) ? 0 : Math.floor(messageId);
      if (mid === 0) { return { ok: false, error: '消息不存在' }; }
      const mres = await forumPrivateMessageCollection.query().equalTo('messageId', mid).get();
      const mrows = toList(mres);
      if (mrows.length === 0) { return { ok: false, error: '消息不存在' }; }
      const m = mrows[0] as ForumPrivateMessage;
      if (m.status !== 0) { return { ok: true }; }   // 已删除，幂等返回
      if (m.senderId !== caller.uid && m.receiverId !== caller.uid) { return { ok: false, error: '无权删除该消息' }; }
      const del = new ForumPrivateMessage();
      del.messageId = m.messageId;
      del.pairId = m.pairId;
      del.senderId = m.senderId;
      del.receiverId = m.receiverId;
      del.content = m.content;
      del.createdAt = m.createdAt;
      del.readFlag = m.readFlag;
      del.status = 1;
      del.mediaUrls = (m.mediaUrls === undefined || m.mediaUrls === '') ? '[]' : m.mediaUrls;
      await forumPrivateMessageCollection.upsert(del);
      return { ok: true };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 清空与某人的整个会话：所有消息软删 + 会话本身置为不显示（共用一行，双方都会从列表消失）
  async clearConversation(token: string, pairId: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员不参与私信' }; }
      if (!pairId) { return { ok: false, error: '会话不存在' }; }
      const cres = await forumConversationCollection.query().equalTo('pairId', pairId).get();
      const crows = toList(cres);
      if (crows.length === 0) { return { ok: false, error: '会话不存在' }; }
      const conv = crows[0] as ForumConversation;
      if (conv.userId1 !== caller.uid && conv.userId2 !== caller.uid) { return { ok: false, error: '无权访问该会话' }; }

      // 该会话下所有未删消息置 status=1（批量，一次请求搞定，不再逐条写）
      try {
        await forumPrivateMessageCollection.batchUpdateByCondition(
          CloudDBZoneObjectOperator.build(new ForumPrivateMessage()).update('status', 1),
          CloudDBZoneObjectOperatorConstraint.build(ForumPrivateMessage)
            .equalTo('pairId', pairId)
            .equalTo('status', 0)
        );
      } catch (e1) {
        console.warn('[clear] batch failed, fallback to row loop: ' + String((e1 as Error).message || e1));
        const mres = await forumPrivateMessageCollection.query().equalTo('pairId', pairId).get();
        const msgs = toList(mres) as ForumPrivateMessage[];
        for (const m of msgs) {
          if (m.status === 0) {
            await updateFields(forumPrivateMessageCollection, ForumPrivateMessage, { messageId: m.messageId }, { status: 1 });
          }
        }
      }
      // 会话本身隐藏（仅 status=1，其余字段保留）；之后若再发私信 sendMessage 会把它复活
      await updateFields(forumConversationCollection, ForumConversation, { pairId: pairId }, {
        status: 1,
        unreadForUser1: 0,
        unreadForUser2: 0
      });
      return { ok: true };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 站内转发某条私信给选中的若干人：复制可见文字(含原帖标记)+图片，发送者记为"我"
  async shareMessage(token: string, messageId: number, targetIdsJson: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员账号不参与分享' }; }
      const mid = (!messageId || isNaN(messageId)) ? 0 : Math.floor(messageId);
      if (mid === 0) { return { ok: false, error: '消息不存在' }; }
      const mres = await forumPrivateMessageCollection.query().equalTo('messageId', mid).get();
      const mrows = toList(mres);
      if (mrows.length === 0) { return { ok: false, error: '消息不存在' }; }
      const m = mrows[0] as ForumPrivateMessage;
      if (m.status !== 0) { return { ok: false, error: '消息已被删除' }; }
      if (m.senderId !== caller.uid && m.receiverId !== caller.uid) { return { ok: false, error: '无权转发该消息' }; }

      const visible = stripMarker(m.content);
      const postId = extractPostId(m.content);   // 若原消息引用了帖子，转发时把「查看原帖」一并带上
      const text = visible + (postId > 0 ? postMarker(postId) : '');
      const mediaJson = JSON.stringify(sanitizeMediaUrls(m.mediaUrls).slice(0, DM_MAX_MEDIA));

      const ids = sanitizeMentionIds(targetIdsJson);
      if (ids.length === 0) { return { ok: true, data: { shared: 0 } }; }

      // 一次性把这批人的角色查回来，避免逐人一次网络往返
      const targets = await loadUsersByIds(ids);
      let shared = 0;
      for (let i = 0; i < ids.length; i++) {
        const toUid = ids[i];
        if (toUid <= 0 || toUid === caller.uid) { continue; }
        try {
          const target = targets[toUid];
          if (!target || target.role === 'admin') { continue; }
          await insertSystemDm(caller.uid, toUid, text, mediaJson);
          shared++;
        } catch (e) {
          // 单个转发失败不影响其它人
        }
      }
      return { ok: true, data: { shared: shared } };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 标记会话已读：清零"我"这一侧未读 + 把我收到的未读消息置已读
  async markConversationRead(token: string, pairId: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: false, error: '管理员不参与私信' }; }
      const cres = await forumConversationCollection.query().equalTo('pairId', pairId).get();
      const crows = toList(cres);
      if (crows.length === 0) { return { ok: false, error: '会话不存在' }; }
      const conv = crows[0] as ForumConversation;
      if (conv.userId1 !== caller.uid && conv.userId2 !== caller.uid) { return { ok: false, error: '无权访问该会话' }; }

      // 只把我这一侧的未读清零（局部字段更新）
      const convFields: Record<string, any> = {};
      if (caller.uid === conv.userId1) {
        convFields.unreadForUser1 = 0;
      } else {
        convFields.unreadForUser2 = 0;
      }
      await updateFields(forumConversationCollection, ForumConversation, { pairId: pairId }, convFields);

      // 把"我收到且未读"的消息批量置为已读。
      // 原来是逐条 upsert：会话长了就是几百次写请求，很容易把云函数拖到超时。
      try {
        await forumPrivateMessageCollection.batchUpdateByCondition(
          CloudDBZoneObjectOperator.build(new ForumPrivateMessage()).update('readFlag', 1),
          CloudDBZoneObjectOperatorConstraint.build(ForumPrivateMessage)
            .equalTo('pairId', pairId)
            .equalTo('receiverId', caller.uid)
            .equalTo('readFlag', 0)
            .equalTo('status', 0)
        );
      } catch (e1) {
        // 批量接口不可用时退回逐条更新，保证"已读"一定能落地
        console.warn('[markRead] batch failed, fallback to row loop: ' + String((e1 as Error).message || e1));
        const mres = await forumPrivateMessageCollection.query().equalTo('pairId', pairId).get();
        const msgs = toList(mres) as ForumPrivateMessage[];
        for (const m of msgs) {
          if (m.receiverId === caller.uid && m.readFlag === 0 && m.status === 0) {
            await updateFields(forumPrivateMessageCollection, ForumPrivateMessage, { messageId: m.messageId }, { readFlag: 1 });
          }
        }
      }
      return { ok: true };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }

  // 未读总数：供"消息"tab 红点徽标；累加我参与的未删除会话中属于我的未读
  async unreadTotal(token: string) {
    try {
      await ensureDb();
      const caller = verifyToken(token);
      if (!caller) { return { ok: false, error: '未登录或登录已过期' }; }
      if (caller.role === 'admin') { return { ok: true, data: 0 }; }
      // 只查我参与的两侧会话，不再全表扫
      const r1 = await forumConversationCollection.query().equalTo('userId1', caller.uid).get();
      const r2 = await forumConversationCollection.query().equalTo('userId2', caller.uid).get();
      let total = 0;
      for (const c of toList(r1) as ForumConversation[]) {
        if (c.status === 0) { total += c.unreadForUser1 || 0; }
      }
      for (const c of toList(r2) as ForumConversation[]) {
        if (c.status === 0) { total += c.unreadForUser2 || 0; }
      }
      return { ok: true, data: total };
    } catch (e) { return { ok: false, error: String((e as Error).message || e) }; }
  }
}
