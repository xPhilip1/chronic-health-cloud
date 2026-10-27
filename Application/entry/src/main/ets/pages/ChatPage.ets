import { UserInfo } from '../model/UserModel'
import { DmMessage, DmConversation, parseMediaUrls } from '../model/ForumModel'
import {
  getCurrentUser, listDmMessages, sendDmMessage, markDmRead,
  deleteDmMessage, clearDmConversation, shareDmMessage, listMyConversations
} from '../service/ApiService'
import { BG_PAGE, CARD_BG, TILE_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, ACCENT } from '../common/Theme'
import {
  SURFACE, SURFACE_SUNK, SURFACE_2, HAIRLINE, INK, INK_SUB, INK_FAINT, CANVAS,
  JADE, JADE_SOFT, ON_PRIMARY, R_LG, R_MD, R_PILL, T_BODY, T_SM, T_CAP, T_MICRO, D_BASE
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { resolveAvatar } from '../common/Avatar'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { cloudStorage } from '@kit.CloudFoundationKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError, request } from '@kit.BasicServicesKit'

// 聊天页：与某位病友的一对一私信。从"消息"会话列表或帖子作者卡/资料卡进入。
// 传参只需 peerId + peerName；pairId 由"我"与对方的 userId 现场算出（与服务端一致的小-大格式），
// 这样对"从没聊过的人"首次发私信也能直接建会话。
// 轮询：前台每 4 秒拉一次历史并整表替换；离页 onPageHide 停，回页 onPageShow 续。
// 服务端在正文尾部携带机器标记（控制符 \u0001 起头）：
//   post:<id>   —— 引用的帖子，渲染"查看原帖"跳详情；
//   quote:<id>  —— 引用的另一条私信，渲染引用块。
// 正常打字不会出现控制符，人话部分取第一个分隔符之前。
const DM_MAX_MEDIA = 9
const MSG_META_SEP = '\u0001'
const dmBucket: cloudStorage.StorageBucket = cloudStorage.bucket()
const DANGER_RED = '#E5484D'

// 转发候选：来自我的私信联系人
interface ForwardPeer {
  id: number
  name: string
  role: string
  avatar: string
}

function msgDisplayText(raw: string): string {
  let i: number = raw.indexOf(MSG_META_SEP)
  return i < 0 ? raw : raw.substring(0, i)
}

function msgPostId(raw: string): number {
  let i: number = raw.indexOf(MSG_META_SEP)
  if (i < 0) { return 0 }
  let tail: string = raw.substring(i + 1)
  if (tail.indexOf('post:') !== 0) { return 0 }
  let id: number = Number.parseInt(tail.substring(5), 10)
  return isNaN(id) ? 0 : id
}

function msgQuoteId(raw: string): number {
  let i: number = raw.indexOf(MSG_META_SEP)
  if (i < 0) { return 0 }
  let tail: string = raw.substring(i + 1)
  if (tail.indexOf('quote:') !== 0) { return 0 }
  let id: number = Number.parseInt(tail.substring(6), 10)
  return isNaN(id) ? 0 : id
}

@Entry
@Component
struct ChatPage {
  @State myUserId: number = 0
  @State peerId: number = 0
  @State peerName: string = ''
  @State peerAvatar: string = ''
  @State pairId: string = ''
  @State messages: DmMessage[] = []
  @State inputText: string = ''
  @State sending: boolean = false

  // 图片：附图待发送（点发送后文字+图作为一条消息；不配文字即纯图）
  @State pendingMedia: string[] = []
  @State mediaUploading: boolean = false

  // 引用：待发送时携带被引用消息 id + 预览文案
  @State quoteId: number = 0
  @State quoteText: string = ''

  // 长按消息弹出的操作菜单
  @State showMenu: boolean = false
  @State menuTarget: DmMessage | null = null

  // 转发选人面板
  @State showForward: boolean = false
  @State forwardTargetId: number = 0
  @State forwardPeers: ForwardPeer[] = []
  @State forwardSelected: number[] = []

  // 全屏图片预览：非空即显示遮罩，点任意处关闭
  @State previewUrl: string = ''

  private scroller: Scroller = new Scroller()
  private pollTimer: number = -1
  private polling: boolean = false
  // 增量轮询游标：已加载消息里最大的 createdAt。轮询时只拉比它新的，避免每次整表重传。
  private lastIso: string = ''

  // 会话主键：较小userId-较大userId（与服务端 makePairId 完全一致）
  makePair(a: number, b: number): string {
    let lo: number = Math.min(a, b)
    let hi: number = Math.max(a, b)
    return lo + '-' + hi
  }

  async aboutToAppear(): Promise<void> {
    let params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    if (params !== null && params !== undefined) {
      this.peerId = params['peerId'] as number
      let pn = params['peerName']
      this.peerName = pn ? String(pn) : ('用户' + this.peerId)
      let pa = params['peerAvatar']
      this.peerAvatar = pa ? String(pa) : ''
    }
    let cur: UserInfo | null = await getCurrentUser()
    if (cur !== null) {
      this.myUserId = cur.userId
    }
    if (this.myUserId === 0 || this.peerId === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '登录状态失效，请重新登录' })
      return
    }
    this.pairId = this.makePair(this.myUserId, this.peerId)
    await this.loadMessages()
    try {
      await markDmRead(this.pairId)
    } catch (e) {
      // 标已读失败不影响看消息，静默
    }
    this.scrollToBottom()
    this.startPoll()
  }

  onPageShow(): void {
    this.startPoll()
  }

  onPageHide(): void {
    this.stopPoll()
  }

  async loadMessages(): Promise<void> {
    let list: DmMessage[] = await listDmMessages(this.pairId)
    this.messages = list
    this.lastIso = this.tailIso(list)
  }

  // 一组消息里最大的 createdAt（ISO 字典序即时间序）；空数组返回空串
  tailIso(list: DmMessage[]): string {
    let max: string = ''
    for (let i = 0; i < list.length; i++) {
      if (list[i].createdAt > max) { max = list[i].createdAt }
    }
    return max
  }

  startPoll(): void {
    if (this.pollTimer !== -1) {
      return
    }
    this.pollTimer = setInterval(() => {
      this.pollTick()
    }, 4000)
  }

  stopPoll(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer)
      this.pollTimer = -1
    }
  }

  // 轮询：首轮整取，之后只拉游标之后的新消息并按 messageId 去重追加。
  // 以前是每次整表拉取再整体替换，消息一多每 4 秒就要传一遍全部历史。
  async pollTick(): Promise<void> {
    if (this.polling) {
      return
    }
    this.polling = true
    try {
      if (this.lastIso === '') {
        await this.loadMessages()
        this.scrollToBottom()
        return
      }
      let fresh: DmMessage[] = await listDmMessages(this.pairId, this.lastIso)
      if (fresh.length === 0) {
        return
      }
      let known: Record<number, boolean> = {}
      for (let i = 0; i < this.messages.length; i++) {
        known[this.messages[i].messageId] = true
      }
      let added: DmMessage[] = []
      for (let j = 0; j < fresh.length; j++) {
        let m: DmMessage = fresh[j]
        if (!known[m.messageId]) {
          known[m.messageId] = true
          added.push(m)
        }
      }
      if (added.length === 0) {
        return
      }
      let next: DmMessage[] = this.messages.slice()
      for (let k = 0; k < added.length; k++) {
        next.push(added[k])
      }
      this.messages = next
      this.lastIso = this.tailIso(added)
      this.scrollToBottom()
    } finally {
      this.polling = false
    }
  }

  scrollToBottom(): void {
    setTimeout(() => {
      try {
        this.scroller.scrollEdge(Edge.Bottom)
      } catch (e) {
        // scroller 尚未 attached 时忽略
      }
    }, 60)
  }

  // 发送：文字与图片至少填其一；服务端负责敏感词/禁言/无权等友好文案
  async onSend(): Promise<void> {
    let text: string = this.inputText.trim()
    if (text === '' && this.pendingMedia.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入内容或选择图片' })
      return
    }
    if (this.sending || this.mediaUploading) {
      return
    }
    this.sending = true
    try {
      let created: DmMessage = await sendDmMessage(this.peerId, text, this.pendingMedia, this.quoteId)
      let next: DmMessage[] = this.messages.slice()
      next.push(created)
      this.messages = next
      // 自己发完也要推进游标，否则下一轮轮询会把刚发的这条再拉回来
      this.lastIso = this.tailIso(next)
      this.inputText = ''
      this.pendingMedia = []
      this.quoteId = 0
      this.quoteText = ''
      this.scrollToBottom()
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: (e as Error).message })
    } finally {
      this.sending = false
    }
  }

  // 选择图片 -> 逐张上传到云存储 -> 放进待发送区（复用发帖/评论那套路）
  async pickImages(): Promise<void> {
    if (this.mediaUploading || this.sending) { return }
    let remain: number = DM_MAX_MEDIA - this.pendingMedia.length
    if (remain <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '一条消息最多 ' + DM_MAX_MEDIA.toString() + ' 张图片' })
      return
    }
    let uris: string[] = []
    try {
      let options = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = remain
      let result = await new photoAccessHelper.PhotoViewPicker().select(options)
      uris = result.photoUris
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '选图失败：' + (e as Error).message })
      return
    }
    if (uris === undefined || uris.length === 0) { return }
    this.mediaUploading = true
    for (let i = 0; i < uris.length; i++) {
      try {
        let url: string = await this.uploadImage(uris[i])
        if (url !== '') {
          this.pendingMedia = this.pendingMedia.concat([url])
        }
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '上传失败：' + (e as Error).message })
        break
      }
    }
    this.mediaUploading = false
  }

  uploadImage(uri: string): Promise<string> {
    return new Promise<string>((resolve: (v: string) => void, reject: (err: Error) => void) => {
      let ctx = this.getUIContext().getHostContext()
      if (ctx === undefined) { reject(new Error('取不到应用上下文')); return }
      let fileName: string = uri.split('/').pop() as string
      let cachePath: string = ctx.cacheDir + '/' + fileName
      try {
        let srcFile = fileIo.openSync(uri)
        let dstFile = fileIo.openSync(cachePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE)
        fileIo.copyFileSync(srcFile.fd, dstFile.fd)
        fileIo.closeSync(srcFile)
        fileIo.closeSync(dstFile)
      } catch (e) {
        reject(new Error('复制图片失败：' + (e as Error).message))
        return
      }
      let ext: string = fileName.indexOf('.') >= 0 ? fileName.substring(fileName.lastIndexOf('.')) : '.jpg'
      let cloudPath: string = 'dm/image_' + Date.now().toString() + '_' + Math.floor(Math.random() * 100000).toString() + ext
      dmBucket.uploadFile(ctx, { localPath: cachePath, cloudPath: cloudPath }).then((task: request.agent.Task) => {
        task.on('completed', () => {
          dmBucket.getDownloadURL(cloudPath).then((url: string) => {
            fileIo.unlink(cachePath).catch(() => {})
            resolve(url)
          }).catch((err: BusinessError) => {
            fileIo.unlink(cachePath).catch(() => {})
            reject(new Error('取下载地址失败：' + err.message))
          })
        })
        task.on('failed', (progress) => {
          fileIo.unlink(cachePath).catch(() => {})
          reject(new Error('上传被拒'))
        })
        task.start().catch((err: BusinessError) => {
          fileIo.unlink(cachePath).catch(() => {})
          reject(new Error('启动上传失败：' + err.message))
        })
      }).catch((err: BusinessError) => {
        fileIo.unlink(cachePath).catch(() => {})
        reject(new Error('创建上传任务失败：' + err.message))
      })
    })
  }

  removePendingImage(index: number): void {
    let next: string[] = []
    for (let i = 0; i < this.pendingMedia.length; i++) {
      if (i !== index) { next.push(this.pendingMedia[i]) }
    }
    this.pendingMedia = next
  }

  // 从分享/@ 通知里的"查看原帖"跳到帖子详情
  openPost(postId: number): void {
    if (postId <= 0) { return }
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PostDetailPage', params: { postId: postId } })
    } catch (e) {
      console.error('跳转帖子失败: ' + (e as Error).message)
    }
  }

  // ===== 长按消息操作 =====
  openMenu(m: DmMessage): void {
    this.menuTarget = m
    this.showMenu = true
  }

  // 引用这条消息：填到待发送区，发送时随正文携带 quote 标记
  doQuote(): void {
    if (this.menuTarget === null) { return }
    let t: string = msgDisplayText(this.menuTarget.content)
    if (t === '' && parseMediaUrls(this.menuTarget.mediaUrls).length > 0) { t = '[图片]' }
    this.quoteId = this.menuTarget.messageId
    this.quoteText = t
    this.showMenu = false
  }

  // 删除这条消息：确认后软删（双方都不可见），随后刷新列表
  doDelete(): void {
    if (this.menuTarget === null) { return }
    let targetId: number = this.menuTarget.messageId
    this.showMenu = false
    this.getUIContext().showAlertDialog({
      title: '删除这条消息',
      message: '删除后这条消息将不再显示（对你和对方都隐藏），确定吗？',
      primaryButton: {
        value: '删除',
        fontColor: DANGER_RED,
        action: async () => {
          try {
            await deleteDmMessage(targetId)
            await this.loadMessages()
          } catch (e) {
            this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message })
          }
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {}
      }
    })
  }

  // 转发这条消息：先拉一次私信联系人作候选（排除自己与当前对话方），再开选人面板
  async doForward(): Promise<void> {
    if (this.menuTarget === null) { return }
    let mid: number = this.menuTarget.messageId
    this.showMenu = false
    try {
      let convs: DmConversation[] = await listMyConversations()
      let peers: ForwardPeer[] = []
      let seen: number[] = []
      for (let i = 0; i < convs.length; i++) {
        let pid: number = convs[i].peerId
        if (pid <= 0 || pid === this.myUserId || pid === this.peerId) { continue }
        if (seen.indexOf(pid) >= 0) { continue }
        seen.push(pid)
        let p: ForwardPeer = {
          id: pid,
          name: convs[i].peerName,
          role: '',
          avatar: convs[i].peerAvatar ?? ''
        }
        peers.push(p)
      }
      this.forwardPeers = peers
    } catch (e) {
      this.forwardPeers = []
    }
    if (this.forwardPeers.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有可转发的病友' })
      return
    }
    this.forwardTargetId = mid
    this.forwardSelected = []
    this.showForward = true
  }

  toggleForwardTarget(id: number): void {
    let idx: number = this.forwardSelected.indexOf(id)
    let next: number[] = []
    if (idx >= 0) {
      for (let i = 0; i < this.forwardSelected.length; i++) {
        if (i !== idx) { next.push(this.forwardSelected[i]) }
      }
    } else {
      next = this.forwardSelected.slice()
      next.push(id)
    }
    this.forwardSelected = next
  }

  async confirmForward(): Promise<void> {
    if (this.forwardSelected.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '至少选择一位病友' })
      return
    }
    try {
      let n: number = await shareDmMessage(this.forwardTargetId, this.forwardSelected)
      this.showForward = false
      this.getUIContext().getPromptAction().showToast({ message: '已转发给 ' + n.toString() + ' 位病友' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '转发失败：' + (e as Error).message })
    }
  }

  // 清空整个会话：确认后所有消息软删 + 会话从列表移除（双方）
  onClearConversation(): void {
    this.getUIContext().showAlertDialog({
      title: '清空聊天记录',
      message: '将删除你与 ' + this.peerName + ' 的所有聊天记录（对你和对方都隐藏），此操作不可恢复，确定吗？',
      primaryButton: {
        value: '清空',
        fontColor: DANGER_RED,
        action: async () => {
          try {
            await clearDmConversation(this.pairId)
            this.messages = []
            this.quoteId = 0
            this.quoteText = ''
            this.getUIContext().getPromptAction().showToast({ message: '已清空聊天记录' })
          } catch (e) {
            this.getUIContext().getPromptAction().showToast({ message: '清空失败：' + (e as Error).message })
          }
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {}
      }
    })
  }

  // 引用的原文预览：优先从已加载消息里找到被引用者，取人话/占位
  quotePreview(quoteId: number): string {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].messageId === quoteId) {
        let t: string = msgDisplayText(this.messages[i].content)
        if (t === '' && parseMediaUrls(this.messages[i].mediaUrls).length > 0) { t = '[图片]' }
        return t
      }
    }
    return '引用内容'
  }

  // 被引用消息的可见文字（供引用块渲染；找不到/无文字返回空串）
  qTextOf(quoteId: number): string {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].messageId === quoteId) {
        return msgDisplayText(this.messages[i].content)
      }
    }
    return ''
  }

  // 被引用消息的图片列表（供引用块显示缩略图）
  qMediaOf(quoteId: number): string[] {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].messageId === quoteId) {
        return parseMediaUrls(this.messages[i].mediaUrls)
      }
    }
    return []
  }

  // ===== 长按操作菜单弹层 =====
  @Builder
  menuSheet() {
    Column({ space: 4 }) {
      this.menuAction('转发给病友', ACCENT, () => { this.doForward() })
      this.menuAction('引用', TEXT_MAIN, () => { this.doQuote() })
      Divider().color(HAIRLINE).strokeWidth(1).margin({ top: 4, bottom: 4 })
      this.menuAction('删除', DANGER_RED, () => { this.doDelete() })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  menuAction(label: string, color: ResourceColor, handler: () => void) {
    Row() {
      Text(label).fontSize(16).fontColor(color)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 14, bottom: 14 })
    .onClick(() => { handler() })
  }

  // ===== 转发选人弹层 =====
  @Builder
  forwardSheet() {
    Column() {
      if (this.forwardPeers.length === 0) {
        Text('没有可转发的病友').fontSize(14).fontColor(TEXT_FAINT)
          .width('100%').textAlign(TextAlign.Center).padding({ top: 30, bottom: 30 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.forwardPeers, (p: ForwardPeer) => {
              Row() {
                Stack({ alignContent: Alignment.Center }) {
                  if (p.avatar !== '') {
                    Image(p.avatar).width(20).height(20).objectFit(ImageFit.Cover)
                  } else {
                    Image(resolveAvatar('', p.role))
                      .width(9).height(9).fillColor('#FFFFFF')
                  }
                }
                .width(20).height(20).borderRadius(10).backgroundColor(ACCENT)
                .clip(true)
                Text(p.name).fontSize(15).fontColor(TEXT_MAIN).margin({ left: 10 }).layoutWeight(1)
                if (this.forwardSelected.indexOf(p.id) >= 0) {
                  Text('✓').fontSize(14).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                    .width(24).height(24).borderRadius(12).backgroundColor(ACCENT)
                } else {
                  Text('').width(22).height(22).borderRadius(11)
                    .border({ width: 1.5, color: TEXT_FAINT })
                }
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
              .onClick(() => { this.toggleForwardTarget(p.id) })
            }, (p: ForwardPeer) => p.id.toString() + '_' + (this.forwardSelected.indexOf(p.id) >= 0 ? 1 : 0))
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      Button('转发（已选 ' + this.forwardSelected.length.toString() + '）')
        .width('100%').height(46).fontSize(15).fontColor('#FFFFFF')
        .backgroundColor(ACCENT).borderRadius(14).margin({ top: 12 })
        .onClick(() => { this.confirmForward() })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  // 气泡派生值封成方法：@Builder 内不能写 let，改为在 UI 表达式里内联调用
  isSelf(m: DmMessage): boolean {
    return m.senderId === this.myUserId
  }
  visibleOf(m: DmMessage): string {
    return msgDisplayText(m.content)
  }
  qidOf(m: DmMessage): number {
    return msgQuoteId(m.content)
  }
  mediaOf(m: DmMessage): string[] {
    return parseMediaUrls(m.mediaUrls)
  }

  // 单条气泡：我发的靠右主色，对方靠左浅底；支持图片、引用块、查看原帖；长按弹菜单
  @Builder
  buildBubble(m: DmMessage) {
    Row() {
      Column() {
        // 引用块（有 quote 标记才显示）：显示被引用的文字/缩略图，点缩略图放大
        if (this.qidOf(m) > 0) {
          Column() {
            if (this.qTextOf(this.qidOf(m)) !== '') {
              Text('引用：' + this.qTextOf(this.qidOf(m)))
                .fontSize(12).fontColor(TEXT_SUB)
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            } else {
              Text('引用：图片')
                .fontSize(12).fontColor(TEXT_SUB)
                .width('100%')
            }
            if (this.qMediaOf(this.qidOf(m)).length > 0) {
              Row() {
                ForEach(this.qMediaOf(this.qidOf(m)).slice(0, 3), (url: string) => {
                  Image(url)
                    .width(44).height(44)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(6)
                    .backgroundColor('#FFFFFF')
                    .margin({ right: 4 })
                    .onClick(() => { this.previewUrl = url })
                }, (url: string) => url)
              }
              .margin({ top: 6 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.isSelf(m) ? 'rgba(15, 122, 92, 0.08)' : SURFACE_2)
          .borderRadius(10)
          .constraintSize({ maxWidth: '72%' })
          .margin({ bottom: 4 })
        }

        // 文字气泡（纯图时不显示空文字）
        if (this.visibleOf(m) !== '') {
          Text(this.visibleOf(m))
            .fontSize(T_BODY)
            .fontColor(this.isSelf(m) ? ON_PRIMARY : INK)
            .lineHeight(22)
            .padding({ left: 13, right: 13, top: 9, bottom: 9 })
            .backgroundColor(this.isSelf(m) ? JADE : SURFACE)
            .borderRadius(this.isSelf(m)
              ? { topLeft: R_MD, topRight: 6, bottomLeft: R_MD, bottomRight: R_MD }
              : { topLeft: 6, topRight: R_MD, bottomLeft: R_MD, bottomRight: R_MD })
            .border({ width: this.isSelf(m) ? 0 : 1, color: HAIRLINE })
            .textAlign(TextAlign.Start)
            .constraintSize({ maxWidth: '72%' })
        }

        // 图片（可多张，九宫格）
        if (this.mediaOf(m).length > 0) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: this.isSelf(m) ? FlexAlign.End : FlexAlign.Start }) {
            ForEach(this.mediaOf(m), (url: string) => {
              Image(url)
                .width(this.visibleOf(m) === '' ? '48%' : '32%')
                .aspectRatio(1)
                .objectFit(ImageFit.Cover)
                .borderRadius(10)
                .backgroundColor(TILE_BG)
                .margin({ left: 3, right: 3, top: 4 })
                .onClick(() => { this.previewUrl = url })
            }, (url: string) => url)
          }
          .constraintSize({ maxWidth: '74%' })
          .margin({ top: this.visibleOf(m) === '' ? 0 : 4 })
        }

        // 查看原帖（引用了帖子时）
        if (msgPostId(m.content) > 0) {
          Text('查看原帖 ›')
            .fontSize(T_MICRO)
            .fontColor(JADE)
            .backgroundColor(JADE_SOFT)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(R_PILL)
            .margin({ top: 6 })
            .onClick(() => { this.openPost(msgPostId(m.content)) })
        }
      }
      .alignItems(this.isSelf(m) ? HorizontalAlign.End : HorizontalAlign.Start)
    }
    .width('100%')
    .justifyContent(this.isSelf(m) ? FlexAlign.End : FlexAlign.Start)
    .gesture(LongPressGesture({ duration: 350 }).onAction(() => { this.openMenu(m) }))
  }

  build() {
    Stack() {
    Column() {
      NavBar({
        title: this.peerName,
        avatarUrl: this.peerAvatar,
        showBack: true,
        rightText: this.messages.length > 0 ? '清空' : '',
        onRight: () => { this.onClearConversation() }
      })

      if (this.messages.length === 0) {
        Column() {
          Text('还没有聊天记录')
            .fontSize(T_BODY)
            .fontColor(INK_SUB)
          Text('向 ' + this.peerName + ' 发第一条私信')
            .fontSize(T_SM)
            .fontColor(INK_FAINT)
            .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 10, scroller: this.scroller }) {
          ForEach(this.messages, (m: DmMessage) => {
            ListItem() {
              this.buildBubble(m)
            }
          }, (m: DmMessage) => m.messageId.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20, top: 14, bottom: 14 })
        .scrollBar(BarState.Off)
      }

      // 输入区：引用预览 + 待发送图片 + 输入行
      Column() {
        // 引用预览条（点取消撤销引用）
        if (this.quoteId !== 0) {
          Row() {
            Text('引用：' + this.quoteText)
              .fontSize(12).fontColor(TEXT_SUB)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text('取消')
              .fontSize(12).fontColor(ACCENT)
              .onClick(() => { this.quoteId = 0; this.quoteText = '' })
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 6 })
        }

        // 待发送图片缩略图（带 ✕ 删除）
        if (this.pendingMedia.length > 0 || this.mediaUploading) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.pendingMedia, (url: string, idx: number) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(url)
                  .width(56).height(56)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(8)
                  .backgroundColor(TILE_BG)
                Text('✕')
                  .fontSize(12).fontColor('#FFFFFF')
                  .width(18).height(18).borderRadius(9)
                  .backgroundColor('#88000000')
                  .textAlign(TextAlign.Center)
                  .onClick(() => { this.removePendingImage(idx) })
              }
              .margin({ right: 8, bottom: 8 })
            }, (url: string, idx: number) => url + '_' + idx.toString())
            if (this.mediaUploading) {
              Text('上传中…').fontSize(12).fontColor(TEXT_FAINT)
                .height(56).textAlign(TextAlign.Center).margin({ right: 8, bottom: 8 })
            }
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 6 })
        }

        // 输入行
        Row() {
          Image($r('app.media.ic_data_add'))
            .width(22).height(22)
            .fillColor(this.pendingMedia.length >= DM_MAX_MEDIA ? INK_FAINT : JADE)
            .onClick(() => { this.pickImages() })

          TextInput({ placeholder: '发私信…', text: this.inputText })
            .layoutWeight(1)
            .height(44)
            .fontSize(T_SM)
            .fontColor(INK)
            .placeholderColor(INK_FAINT)
            .backgroundColor(CANVAS)
            .borderRadius(R_PILL)
            .border({ width: 1, color: HAIRLINE })
            .padding({ left: 14, right: 14 })
            .enterKeyType(EnterKeyType.Send)
            .margin({ left: 10 })
            .onChange((v: string) => { this.inputText = v })
            .onSubmit(() => { this.onSend() })

          Row() {
            Image($r('app.media.ic_arrow_right'))
              .width(16).height(16)
              .fillColor('#FFFFFF')
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .borderRadius(R_PILL)
          .backgroundColor((this.sending || this.mediaUploading) ? INK_FAINT : JADE)
          .margin({ left: 10 })
          .onClick(() => {
            if (!this.sending && !this.mediaUploading) {
              this.onSend()
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(SURFACE)
      .border({ width: { top: 1 }, color: HAIRLINE })
      .alignItems(HorizontalAlign.Start)
      .bindSheet($$this.showForward, this.forwardSheet(), {
        title: { title: '转发给病友' },
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        dragBar: true,
        showClose: true
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAGE)
    .bindSheet($$this.showMenu, this.menuSheet(), {
      title: { title: '消息操作' },
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      dragBar: true,
      showClose: true
    })

      // 全屏图片预览遮罩：覆盖在聊天内容之上，点任意处关闭
      if (this.previewUrl !== '') {
        Column() {
          Image(this.previewUrl)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .layoutWeight(1)
            .padding(12)
          Text('点击任意处关闭')
            .fontSize(13)
            .fontColor('#FFFFFF')
            .padding({ top: 6, bottom: 24 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#E0000000')
        .onClick(() => { this.previewUrl = '' })
      }
    }
    .width('100%')
    .height('100%')
  }
}
