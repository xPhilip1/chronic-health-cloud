// DeepSeek 大模型接入配置（仅在服务端云函数使用，Key 绝不下发到客户端）。
//
// 取值优先级：环境变量 DEEPSEEK_API_KEY > 下方内嵌密文（见 model/secretBox.ts）。
// 生产建议：在 AGC 云函数的环境变量里配置 DEEPSEEK_API_KEY，内嵌值只作比赛演示兜底。
// 密文说明：源码里不再是明文 Key；如需轮换，请用 secretBox.seal('新Key') 生成新密文后替换。
import { open } from './secretBox';

// 内嵌密文（XOR+Base64 混淆，非强加密）
const DEEPSEEK_API_KEY_SEALED: string =
  '';  // 已移除内嵌 Key：请配置环境变量 DEEPSEEK_API_KEY

// 密文只解一次，后续复用（避免每次调用都做 Base64 解码）
let cachedKey: string = '';

// 读取顺序：先取运行时环境变量，取不到再回退到内嵌密文
export function getApiKey(): string {
  const fromEnv: string | undefined =
    (typeof process !== 'undefined' && process.env) ? process.env.DEEPSEEK_API_KEY : undefined;
  if (fromEnv && fromEnv.length > 0) {
    return fromEnv;
  }
  if (cachedKey === '') {
    try {
      cachedKey = open(DEEPSEEK_API_KEY_SEALED);
    } catch (e) {
      cachedKey = '';
    }
  }
  return cachedKey;
}

// DeepSeek OpenAI 兼容接口
export const DEEPSEEK_HOST: string = 'api.deepseek.com';
export const DEEPSEEK_PATH: string = '/v1/chat/completions';
export const DEEPSEEK_MODEL: string = 'deepseek-chat';
// 单次请求超时（毫秒）。大模型生成较慢，给足 60s。
export const DEEPSEEK_TIMEOUT_MS: number = 60000;
