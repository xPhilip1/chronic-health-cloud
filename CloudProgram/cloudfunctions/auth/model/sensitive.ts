// 敏感词表 + 命中判定（首版纯文字，够用即可，不追求 DFA 性能）。
// 中文没有空格分词，直接按“包含”匹配子串；英文/拼音统一转小写再比。
// 命中即拦截发布，并交由调用方累加违规、按阈值升级禁言。
// 后续可扩充：把词表挪到独立配置、做同音字/变体（如 v、符号分隔）归一化。

// 分级：脏话辱骂 / 广告导流 / 违法诈骗 / 医疗风险（偏方骗局、劝停医嘱）
const SENSITIVE_WORDS: string[] = [
  // —— 脏话 / 人身攻击 ——
  '傻逼', '沙比', '傻B', '贱人', '畜生', '狗东西', '王八蛋', '去死', '滚蛋',
  '妈的', '他妈的', '尼玛', '草泥马', '废物', '脑残', '白痴', '蠢货', '操你',
  // —— 广告 / 导流 ——
  '加微信', '加v', '加V', '私聊', '代开发票', '办证', '一条龙服务', '返利',
  '刷单', '兼职日结', '转账', '点击链接', '进群', '招代理', '传销', '资金盘',
  // —— 违法 / 诈骗 ——
  '博彩', '赌场', '六合彩', '澳门', '毒品', '冰毒', '海洛因', '枪支', '仿真枪',
  '迷药', '春药', '代孕', '卖肾', '人肉', '黑客', '外挂', '赌博',
  // —— 医疗风险 / 偏方骗局 ——
  '包治百病', '祖传秘方', '彻底根治', '根除不复发', '停药', '替代医院',
  '无效退款', '神药', '偏方治好', '胰岛素戒掉', '偏方降压', '偏方降糖'
];

// 命中的词返回去重数组；空数组=干净。
export function matchSensitive(text: string): string[] {
  if (!text) {
    return [];
  }
  const lower = text.toLowerCase();
  const hits: string[] = [];
  for (let i = 0; i < SENSITIVE_WORDS.length; i++) {
    const w = SENSITIVE_WORDS[i];
    const target = w.toLowerCase();
    if (lower.indexOf(target) >= 0 && hits.indexOf(w) < 0) {
      hits.push(w);
    }
  }
  return hits;
}

// 违规升级策略：命中次数 -> 禁言秒数。0=仅提醒不禁言。
// 第 1 次：警告；第 2 次：30 秒；第 3 次：5 分钟；第 4 次：30 分钟；
// 第 5 次：2 小时；第 6 次及以上：1 天。
// 注：从第 3 次起，若距上次违规满 24 小时无新违规，计数归零重新从第 1 次算（见 registerViolation）。
export function muteSecondsFor(count: number): number {
  if (count <= 1) { return 0; }
  if (count === 2) { return 30; }
  if (count === 3) { return 300; }
  if (count === 4) { return 1800; }
  if (count === 5) { return 7200; }
  return 86400;
}

// 把禁言秒数格式化成中文时长文案；<=0 返回空串（仅提醒场景）。
export function formatMute(sec: number): string {
  if (!sec || sec <= 0) { return ''; }
  if (sec < 60) { return Math.ceil(sec) + ' 秒'; }
  if (sec < 3600) { return Math.ceil(sec / 60) + ' 分钟'; }
  if (sec < 86400) { return Math.ceil(sec / 3600) + ' 小时'; }
  return Math.ceil(sec / 86400) + ' 天';
}
