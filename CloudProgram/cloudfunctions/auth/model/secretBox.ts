// 密钥轻量混淆（不是强加密，只是不让人一眼搜到明文）。
//
// 用途：把 DeepSeek Key、令牌签名密钥、AGC 服务端凭证这类常量做 XOR + Base64 后内嵌，
// 源码仓库里直接 grep 不到明文；运行时由 open() 还原成原始字符串。
//
// 边界（务必知情）：
//   · 这是"混淆"不是"加密"。密钥与本文件同包下发，拿到云函数产物的人照样能还原。
//     它挡的是"随手翻代码 / 公开仓库被搜到 Key"，挡不住有决心的攻击者。
//   · 真正安全的做法是环境变量或密钥管理服务（AGC 密钥库 / KMS）。
//     DeepSeek Key 已支持环境变量 DEEPSEEK_API_KEY 优先，本文件只是兜底。
//   · 令牌密钥与 AGC 凭证无法从环境变量读，才退化为这里的内嵌混淆。
//
// 轮换密钥：本文件导出 seal()，在云函数里临时打一行 seal('新密钥') 拿到密文，
// 替换对应常量后重新部署即可（换令牌密钥会让所有旧令牌失效，需重新登录）。

// 混淆盐：改这个值会让下面所有密文失效，别乱动
const BOX_KEY = 'ChronicCloud#2026';

// 明文 -> 密文（XOR + Base64），仅在轮换密钥时用于生成常量
export function seal(plain: string): string {
  const k = Buffer.from(BOX_KEY, 'utf8');
  const b = Buffer.from(plain, 'utf8');
  for (let i = 0; i < b.length; i++) {
    b[i] = b[i] ^ k[i % k.length];
  }
  return b.toString('base64');
}

// 密文 -> 明文，运行时使用
export function open(sealed: string): string {
  const k = Buffer.from(BOX_KEY, 'utf8');
  const b = Buffer.from(sealed, 'base64');
  for (let i = 0; i < b.length; i++) {
    b[i] = b[i] ^ k[i % k.length];
  }
  return b.toString('utf8');
}
