// 论坛（Phase ① 纯文字）端侧数据结构。
// 字段与服务端 auth 云函数 toPublicPost/toPublicComment 回传的键一一对应。

// 帖子
export interface ForumPost {
  postId: number
  authorId: number
  authorRole: string    // 'patient' | 'doctor' | 'admin'
  authorName: string    // 服务端已解析好的展示名（昵称/用户名）
  authorAvatar?: string // 作者自定义头像地址；空/未定义时回退内置图标
  title: string
  content: string
  createdAt: string     // ISO
  likeCount: number
  commentCount: number
  status: number        // 0 正常 1 已软删（仅管理员列表能看到）
  likedByMe: boolean
  favorited: boolean    // 是否被当前用户收藏（服务端 favoritedByMe）
  mediaUrls: string     // 图片下载地址列表的 JSON 数组字符串；文字帖为 '[]'
  dept: string          // 病种标签（单选）；未设置为空串
  topics: string        // 话题标签列表的 JSON 数组字符串（最多 2 个）；无则为 '[]'
}

// 把帖子携带的图片地址 JSON 字符串解析成数组；异常/空一律返回空数组
export function parseMediaUrls(raw: string): string[] {
  let out: string[] = []
  if (raw === '' || raw === undefined || raw === null) {
    return out
  }
  try {
    let arr = JSON.parse(raw) as string[]
    if (Array.isArray(arr)) {
      for (let i = 0; i < arr.length; i++) {
        let v = arr[i]
        if (typeof v === 'string' && v !== '') {
          out.push(v)
        }
      }
    }
  } catch (e) {
    return []
  }
  return out
}

// 把帖子携带的话题标签 JSON 字符串解析成数组；异常/空一律返回空数组
export function parseTopics(raw: string): string[] {
  let out: string[] = []
  if (raw === '' || raw === undefined || raw === null) {
    return out
  }
  try {
    let arr = JSON.parse(raw) as string[]
    if (Array.isArray(arr)) {
      for (let i = 0; i < arr.length; i++) {
        let v = arr[i]
        if (typeof v === 'string' && v !== '') {
          out.push(v)
        }
      }
    }
  } catch (e) {
    return []
  }
  return out
}

// 评论
export interface ForumComment {
  commentId: number
  postId: number
  authorId: number
  authorRole: string
  authorName: string
  authorAvatar?: string  // 作者自定义头像；空/未定义时回退内置图标
  content: string
  createdAt: string
  status: number
  parentId: number   // 0=主评论；>0=回复某条评论(直接父评论 commentId)
  mediaUrls: string  // 评论图片地址列表 JSON 数组；纯文字评论为 '[]'
}

// 当前用户违规/禁言状态
export interface ForumViolationStatus {
  violationCount: number
  muted: boolean
  muteRemainText: string
}

// 点赞返回
export interface ForumLikeResult {
  liked: boolean
  likeCount: number
}

// 帖子分页结果
export interface ForumPostPage {
  posts: ForumPost[]
  hasMore: boolean
}

// ===== 私信 =====
// 会话（对应服务端 toPublicConversation 回传的键）
export interface DmConversation {
  pairId: string          // 会话主键：较小userId-较大userId
  peerId: number          // 对方 userId
  peerName: string        // 服务端已解析好的对方展示名
  peerAvatar?: string     // 对方自定义头像；空/未定义时回退内置图标
  lastMessage: string     // 列表预览摘要（截断）
  lastSenderId: number    // 最后一条发送者
  lastCreatedAt: string   // 最后一条时间（ISO），列表按此倒序
  unread: number          // 属于"我"的未读数
  status: number          // 0 正常 1 已软删
}

// 单条私信（对应服务端 toPublicMessage 回传的键）
export interface DmMessage {
  messageId: number
  pairId: string
  senderId: number
  receiverId: number
  content: string
  createdAt: string       // ISO
  readFlag: number        // 0 未读 1 已读（仅对接收方有意义）
  status: number          // 0 正常 1 已软删
  mediaUrls: string       // 图片地址列表 JSON 数组；纯文字消息为 '[]'
}

// 论坛用户公开简介（对应服务端 getUserBrief 返回，点头像弹出的详情卡片）
export interface ForumUserBrief {
  userId: number
  nickname: string        // 服务端已解析好的展示名
  role: string            // patient / doctor / admin
  genderText: string      // 男 / 女 / 未填写
  createdAt: string       // 注册时间（ISO），端侧据此算注册时长
  postCount: number       // 发帖数（未删除）
  likeTotal: number       // 获赞总数
  doctorLicense: string   // 仅医生有值，其余为空串
  avatarUrl?: string      // 自定义头像；空/未定义时回退内置图标
}
