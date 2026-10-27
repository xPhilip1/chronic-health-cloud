// 论坛发帖标签预设清单（标签分两组：病种单选 + 话题多选）。
// 端侧 PostEditPage 渲染选择区、ForumPage 渲染顶部筛选条都从这里取，保证两端一致。
// 说明：这些是固定枚举，用户只能从中选，避免自由输入导致的脏数据；服务端 createPost 也会各自裁剪。
// 注：底层存储字段仍叫 dept（仅是列名，用户不可见），语义已改为"病种/慢病类型"，贴合慢性病管理主线。

// 一篇帖子最多 1 个病种
export const MAX_DEPT = 1
// 一篇帖子最多 2 个话题（病种 + 话题合计最多 3 个标签，符合产品约定）
export const MAX_TOPIC = 2

// 病种标签（单选）——聚焦国家基本公卫重点慢病 + 常见代谢病
export const DISEASE_TAGS: string[] = [
  '高血压',
  '糖尿病',
  '冠心病',
  '脑卒中',
  '慢阻肺',
  '哮喘',
  '慢性肾病',
  '甲亢',
  '甲减',
  '痛风',
  '高血脂'
]

// 话题标签（多选）
export const TOPIC_TAGS: string[] = [
  '饮食',
  '运动',
  '用药',
  '血糖',
  '血压',
  '检查报告',
  '并发症',
  '心理',
  '中医调理',
  '医保就医'
]

// 供 ForumPage 顶部筛选条使用：把「全部」以外的病种、话题拼成一条可横滑的标签序列。
// 返回的元素形如 { label: '高血压', dept: '高血压', topic: '' }，
// 其中 dept/topic 恰有一个非空，代表点它时传给 listForumPosts 的筛选维度（dept 即病种维度）。
export interface ForumFilterTag {
  label: string   // 展示文案
  dept: string    // 命中病种时填，话题维度留空
  topic: string   // 命中话题时填，病种维度留空
}

// 构造筛选条标签数组：[全部, ...病种, ...话题]
export function buildFilterTags(): ForumFilterTag[] {
  let out: ForumFilterTag[] = []
  let all: ForumFilterTag = { label: '全部', dept: '', topic: '' }
  out.push(all)
  for (let i = 0; i < DISEASE_TAGS.length; i++) {
    let t: ForumFilterTag = { label: DISEASE_TAGS[i], dept: DISEASE_TAGS[i], topic: '' }
    out.push(t)
  }
  for (let j = 0; j < TOPIC_TAGS.length; j++) {
    let t2: ForumFilterTag = { label: TOPIC_TAGS[j], dept: '', topic: TOPIC_TAGS[j] }
    out.push(t2)
  }
  return out
}
