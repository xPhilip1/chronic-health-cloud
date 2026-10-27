// 会话令牌：登录成功后由服务端签发，端侧每次数据请求带上，服务端验签得到 {uid, role}。
// 因为端云一体化 CloudDB 只按设备华为 ID 鉴权、无法区分 App 用户，
// 所以"哪个用户在访问"必须由我们自己的令牌承载，这也是 1d 角色鉴权的基础。
// 签名密钥以密文内嵌（见 model/secretBox.ts）：源码里搜不到明文，但同包可还原，
// 生产环境应改由环境变量/密钥管理服务注入。
import * as crypto from 'crypto';
import { open } from './secretBox';

// 令牌签名密钥（密文内嵌）。轮换此值会让所有已签发令牌立即失效，用户需重新登录。
const TOKEN_SECRET_SEALED: string =
  '';  // 已移除内嵌签名密钥：请配置环境变量 TOKEN_SECRET
const TOKEN_SECRET: string = open(TOKEN_SECRET_SEALED) || 'dev-only-token-secret-change-me';

// 令牌有效期：7 天（毫秒）
const TOKEN_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export interface TokenPayload {
  uid: number;
  role: string;
  exp: number;
}

// 签发：base64(JSON{uid,role,exp}) + '.' + HMAC-SHA256(payload)
export function signToken(uid: number, role: string): string {
  const payload: TokenPayload = { uid: uid, role: role, exp: Date.now() + TOKEN_TTL_MS };
  const body = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64');
  const sig = crypto.createHmac('sha256', TOKEN_SECRET).update(body).digest('hex');
  return body + '.' + sig;
}

// 验签：签名不符 / 结构异常 / 已过期 -> 返回 null
export function verifyToken(token: string): TokenPayload | null {
  if (!token || token.indexOf('.') < 0) {
    return null;
  }
  const dot = token.indexOf('.');
  const body = token.substring(0, dot);
  const sig = token.substring(dot + 1);
  const expect = crypto.createHmac('sha256', TOKEN_SECRET).update(body).digest('hex');
  const a = Buffer.from(sig, 'utf8');
  const b = Buffer.from(expect, 'utf8');
  if (a.length !== b.length) {
    return null;
  }
  if (!crypto.timingSafeEqual(a, b)) {
    return null;
  }
  try {
    const obj = JSON.parse(Buffer.from(body, 'base64').toString('utf8')) as TokenPayload;
    if (!obj || typeof obj.uid !== 'number' || !obj.role || obj.exp < Date.now()) {
      return null;
    }
    return obj;
  } catch (e) {
    return null;
  }
}
