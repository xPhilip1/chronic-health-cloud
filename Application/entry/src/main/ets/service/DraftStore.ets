// 草稿箱本地存储（Preferences）。
// 不建云表、不部署，卸载即丢——对"草稿"这种临时数据足够。
// 所有方法第一个参数是 Context（页面里用 this.getUIContext().getHostContext()!）。
import { preferences } from '@kit.ArkData'

const STORE_NAME = 'chronic_health'   // 跟 ApiService 共用同一个 Preferences 文件
const KEY_DRAFTS = 'forum_drafts'     // 存 JSON 数组字符串

// 一条草稿
export interface Draft {
  id: string          // 唯一标识：时间戳 + 随机
  title: string
  content: string
  mediaUrls: string[] // 已上传到云存储的图片地址
  dept: string        // 病种
  topics: string[]    // 话题
  updatedAt: string   // ISO 时间，列表按此排序
}

// 读取全部草稿（异常返回空数组）
async function readAll(ctx: Context): Promise<Draft[]> {
  try {
    let store = await preferences.getPreferences(ctx, STORE_NAME)
    let raw = await store.get(KEY_DRAFTS, '[]') as string
    let arr = JSON.parse(raw) as Draft[]
    if (Array.isArray(arr)) { return arr }
    return []
  } catch (e) {
    return []
  }
}

// 写入全部草稿
async function writeAll(ctx: Context, list: Draft[]): Promise<void> {
  let store = await preferences.getPreferences(ctx, STORE_NAME)
  await store.put(KEY_DRAFTS, JSON.stringify(list))
  await store.flush()
}

// 保存/更新一条草稿（按 id 去重：有则覆盖，无则追加）
export async function saveDraft(ctx: Context, draft: Draft): Promise<void> {
  let list = await readAll(ctx)
  let replaced = false
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === draft.id) {
      list[i] = draft
      replaced = true
      break
    }
  }
  if (!replaced) {
    list.push(draft)
  }
  await writeAll(ctx, list)
}

// 列出全部草稿，按更新时间倒序
export async function listDrafts(ctx: Context): Promise<Draft[]> {
  let list = await readAll(ctx)
  list.sort((a: Draft, b: Draft) => b.updatedAt.localeCompare(a.updatedAt))
  return list
}

// 删除一条草稿
export async function deleteDraft(ctx: Context, id: string): Promise<void> {
  let list = await readAll(ctx)
  let next: Draft[] = []
  for (let i = 0; i < list.length; i++) {
    if (list[i].id !== id) { next.push(list[i]) }
  }
  await writeAll(ctx, next)
}

// 获取单条草稿（不存在返回 null）
export async function getDraft(ctx: Context, id: string): Promise<Draft | null> {
  let list = await readAll(ctx)
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === id) { return list[i] }
  }
  return null
}

// 生成草稿 id
export function newDraftId(): string {
  return 'd' + Date.now().toString() + '_' + Math.floor(Math.random() * 100000).toString()
}
