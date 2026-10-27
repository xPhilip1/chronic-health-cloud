import { UserInfo } from '../model/UserModel'
import { ForumPost, ForumComment, ForumUserBrief, DmConversation, parseMediaUrls, parseTopics } from '../model/ForumModel'
import {
  getForumPostDetail, listForumComments, addForumComment,
  deleteForumComment, deleteForumPost, toggleForumLike, getCurrentUser, getForumUserBrief, toggleForumFavorite, listMyConversations, shareForumPost
} from '../service/ApiService'
import {
  BG_PAGE, CARD_BG, TILE_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, ACCENT, DANGER, WARN,
  C_SUGAR, C_SUGAR_BG, R_CARD, SHADOW_CARD,
  SURFACE_SUNK, JADE_SOFT, HAIRLINE
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { resolveAvatar } from '../common/Avatar'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { cloudStorage } from '@kit.CloudFoundationKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError, request } from '@kit.BasicServicesKit'

const MAX_COMMENT_MEDIA = 3
const cBucket: cloudStorage.StorageBucket = cloudStorage.bucket()

// 一条回复的展示视图：附上"回复 @某人"的名字（仅当直接父级本身也是回复时非空）
interface ReplyView {
  c: ForumComment
  mention: string
}

// 一个评论线程：主评论 + 归并到它下面的所有回复
interface CommentThread {
  root: ForumComment
  replies: ReplyView[]
}

// 可被 @ 的人（本帖作者 + 评论区作者 + 我的私信联系人，按 userId 去重）
interface MentionCandidate {
  id: number
  name: string
  role: string
  avatar: string
}

// 把评论正文按命中的 @昵称 切成小段：uid=0 是普通文字，>0 是可点击的 @提及
interface MentionSegment {
  text: string
  uid: number
}

@Entry
@Component
struct PostDetailPage {
  @State post: ForumPost | null = null
  @State comments: ForumComment[] = []
  @State isLoading: boolean = true
  @State refreshing: boolean = false
  @State isPosting: boolean = false
  @State commentText: string = ''
  @State commentMedia: string[] = []       // 评论图片地址（已上传到云存储）
  @State commentUploading: boolean = false // 评论图片上传中
  // 当前回复目标：0=发主评论；>0=回复该评论
  @State replyToId: number = 0
  @State replyToName: string = ''
  private postId: number = 0
  private myUserId: number = 0
  private myRole: string = 'patient'
  // 点头像弹出的用户详情卡片
  @State showProfile: boolean = false
  @State brief: ForumUserBrief | null = null
  @State briefLoading: boolean = false
  // 弹窗当前指向的用户（私信跳转与兜底展示用）
  private sheetPeerId: number = 0
  private sheetPeerName: string = ''
  private sheetPeerRole: string = 'patient'
  // @某人：可@的人全集（本帖作者+评论作者+私信联系人去重），既喂给选人弹层，也用于评论正文里命中高亮
  @State mentionAll: MentionCandidate[] = []
  @State showMentionSheet: boolean = false
  @State mentionKeyword: string = ''
  // 站内分享：把本帖以私信转发给选中的人
  @State showShareSheet: boolean = false
  @State shareSelected: number[] = []

  async aboutToAppear(): Promise<void> {
    let params = this.getUIContext().getRouter().getParams() as Record<string, number>
    if (params !== null && params !== undefined) {
      this.postId = params['postId']
    }
    let cur: UserInfo | null = await getCurrentUser()
    if (cur !== null) {
      this.myUserId = cur.userId
      this.myRole = cur.role
    }
    await this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    await this.fetchDetail()
    this.isLoading = false
  }

  // 下拉刷新：重新拉取但不切换 isLoading，避免刷新组件被卸载导致动画中断
  async refreshData(): Promise<void> {
    await this.fetchDetail()
  }

  async fetchDetail(): Promise<void> {
    let p: ForumPost | null = await getForumPostDetail(this.postId)
    this.post = p
    if (p !== null) {
      await this.readComments()
      await this.buildMentionCandidates()
    }
  }

  // 单独把评论列表读回来并触发重排（服务端最终一致，写入后需稍后才是权威值）
  async readComments(): Promise<void> {
    this.comments = await listForumComments(this.postId)
  }

  // 组装可被 @ 的候选人：本帖作者 + 评论区所有作者 + 我的私信联系人，按 userId 去重、剔除自己
  async buildMentionCandidates(): Promise<void> {
    let seen: number[] = []
    let out: MentionCandidate[] = []
    let push = (id: number, name: string, role: string, avatar: string): void => {
      if (id <= 0 || id === this.myUserId) { return }   // 无效 id / 自己，跳过
      if (seen.indexOf(id) >= 0) { return }             // 去重（先加的优先保留其名字）
      if (name === '') { return }
      seen.push(id)
      out.push({ id: id, name: name, role: role, avatar: avatar })
    }
    // 线程里的人先加：这样 @ 高亮优先命中帖子/评论作者的展示名
    if (this.post !== null) {
      push(this.post.authorId, this.post.authorName, this.post.authorRole,
        this.post.authorAvatar !== undefined ? this.post.authorAvatar : '')
    }
    for (let i = 0; i < this.comments.length; i++) {
      let c: ForumComment = this.comments[i]
      push(c.authorId, c.authorName, c.authorRole, c.authorAvatar !== undefined ? c.authorAvatar : '')
    }
    // 再补私信联系人（没有角色信息，展示名以服务端解析的 peerName 为准）
    try {
      let convs: DmConversation[] = await listMyConversations()
      for (let j = 0; j < convs.length; j++) {
        push(convs[j].peerId, convs[j].peerName, '', convs[j].peerAvatar ?? '')
      }
    } catch (e) {
      // 私信拉取失败不影响本贴 @，忽略即可
    }
    this.mentionAll = out
  }

  // 选人弹层里根据关键字过滤候选人
  filteredMentions(): MentionCandidate[] {
    let kw: string = this.mentionKeyword.trim().toLowerCase()
    if (kw === '') { return this.mentionAll }
    let out: MentionCandidate[] = []
    for (let i = 0; i < this.mentionAll.length; i++) {
      if (this.mentionAll[i].name.toLowerCase().indexOf(kw) >= 0) { out.push(this.mentionAll[i]) }
    }
    return out
  }

  // 打开选人弹层：首次打开时懒加载候选人
  async openMentionPicker(): Promise<void> {
    this.mentionKeyword = ''
    if (this.mentionAll.length === 0) {
      await this.buildMentionCandidates()
    }
    this.showMentionSheet = true
  }

  // 选中某人 → 把 @昵称 追加到评论输入框末尾，收起弹层
  insertMention(c: MentionCandidate): void {
    this.commentText = this.commentText + '@' + c.name + ' '
    this.showMentionSheet = false
  }

  roleTextOf(role: string): string {
    if (role === 'doctor') { return '医生' }
    if (role === 'admin') { return '管理员' }
    return '病友'
  }

  // 把评论正文按命中的 @昵称 切成段：普通文字 uid=0，@提及带上对应 userId（供点击跳资料）
  splitMentions(content: string): MentionSegment[] {
    let segs: MentionSegment[] = []
    if (content === '' || this.mentionAll.length === 0) {
      segs.push({ text: content, uid: 0 })
      return segs
    }
    let pos: number = 0
    let n: number = content.length
    while (pos < n) {
      let bestIdx: number = -1
      let bestName: string = ''
      let bestId: number = 0
      for (let i = 0; i < this.mentionAll.length; i++) {
        let cand: MentionCandidate = this.mentionAll[i]
        let token: string = '@' + cand.name
        if (cand.name === '') { continue }
        let idx: number = content.indexOf(token, pos)
        if (idx < 0) { continue }
        // 取最靠前的命中；同一位置若多个名字都命中，选更长的名字（避免 @张三丰 被 @张三 抢先）
        if (idx < bestIdx || bestIdx < 0) {
          bestIdx = idx; bestName = cand.name; bestId = cand.id
        } else if (idx === bestIdx && cand.name.length > bestName.length) {
          bestName = cand.name; bestId = cand.id
        }
      }
      if (bestIdx < 0) {
        segs.push({ text: content.substring(pos, n), uid: 0 })
        break
      }
      if (bestIdx > pos) {
        segs.push({ text: content.substring(pos, bestIdx), uid: 0 })
      }
      segs.push({ text: '@' + bestName, uid: bestId })
      pos = bestIdx + 1 + bestName.length   // 游标一定前进，防死循环
    }
    return segs
  }

  // 从文本里挑出真正被 @ 到的人的 userId（去重、排除自己），作为 mentionIds 传给服务端发通知
  extractMentionIds(text: string): number[] {
    let ids: number[] = []
    if (text === '') { return ids }
    for (let i = 0; i < this.mentionAll.length; i++) {
      let cand: MentionCandidate = this.mentionAll[i]
      if (cand.name === '' || cand.id === this.myUserId) { continue }
      if (text.indexOf('@' + cand.name) >= 0 && ids.indexOf(cand.id) < 0) {
        ids.push(cand.id)
      }
    }
    return ids
  }

  // 点评论里的 @昵称 → 打开那个人资料（复用现成 openProfile）
  openMentionProfile(uid: number): void {
    for (let i = 0; i < this.mentionAll.length; i++) {
      if (this.mentionAll[i].id === uid) {
        this.openProfile(uid, this.mentionAll[i].name, this.mentionAll[i].role)
        return
      }
    }
    this.openProfile(uid, '', 'patient')
  }

  // 富文本评论正文：把命中的 @昵称 高亮成可点击片段，其余按普通文字渲染
  @Builder
  commentBody(topGap: number, content: string, fsize: number, color: ResourceColor, lh: number) {
    Text() {
      ForEach(this.splitMentions(content), (seg: MentionSegment) => {
        if (seg.uid > 0) {
          Span(seg.text)
            .fontSize(fsize).fontColor(ACCENT).fontWeight(FontWeight.Medium)
            .onClick(() => { this.openMentionProfile(seg.uid) })
        } else {
          Span(seg.text).fontSize(fsize).fontColor(color)
        }
      }, (seg: MentionSegment, index: number) => index.toString() + '_' + seg.uid.toString() + '_' + seg.text)
    }
    .width('100%')
    .margin({ top: topGap })
    .lineHeight(lh)
    .textAlign(TextAlign.Start)
  }

  // 选人弹层：搜索 + 候选人列表，点一条把 @昵称 插进输入框
  @Builder
  mentionSheet() {
    Column() {
      Text('选择要 @ 的人')
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(TEXT_MAIN)
        .width('100%').margin({ top: 4, bottom: 12 })

      TextInput({ placeholder: '搜索昵称', text: this.mentionKeyword })
        .height(40).fontSize(14)
        .fontColor(TEXT_MAIN).backgroundColor(TILE_BG).borderRadius(12)
        .onChange((v: string) => { this.mentionKeyword = v })

      if (this.filteredMentions().length === 0) {
        Text('还没有可 @ 的人——多在帖子和评论里互动，之后就能 @ 到对方')
          .fontSize(13).fontColor(TEXT_FAINT)
          .width('100%').textAlign(TextAlign.Center).margin({ top: 40 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.filteredMentions(), (c: MentionCandidate) => {
              Row() {
                Stack({ alignContent: Alignment.Center }) {
                  if (c.avatar !== '') {
                    Image(c.avatar).width(34).height(34).objectFit(ImageFit.Cover)
                  } else {
                    Image(resolveAvatar('', c.role))
                      .width(15).height(15).fillColor('#FFFFFF')
                  }
                }
                .width(34).height(34).borderRadius(17)
                .backgroundColor(c.role === 'doctor' ? C_SUGAR : ACCENT)
                .clip(true)
                Column() {
                  Text(c.name).fontSize(14).fontColor(TEXT_MAIN)
                  Text(this.roleTextOf(c.role)).fontSize(11).fontColor(TEXT_FAINT)
                }
                .alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)
                Text('@').fontSize(18).fontColor(ACCENT).fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .onClick(() => { this.insertMention(c) })
            }, (c: MentionCandidate) => c.id.toString())
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  async onLike(): Promise<void> {
    if (this.post === null) {
      return
    }
    try {
      let r = await toggleForumLike(this.post.postId)
      let old: ForumPost = this.post
      let copy: ForumPost = {
        postId: old.postId, authorId: old.authorId, authorRole: old.authorRole, authorName: old.authorName, authorAvatar: old.authorAvatar,
        title: old.title, content: old.content, createdAt: old.createdAt,
        likeCount: r.likeCount, commentCount: old.commentCount, status: old.status, likedByMe: r.liked, favorited: old.favorited, mediaUrls: old.mediaUrls, dept: old.dept, topics: old.topics
      }
      this.post = copy
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败：' + (e as Error).message })
    }
  }

  // 收藏/取消收藏：只改 favorited，不动其它计数字段
  async onFavorite(): Promise<void> {
    if (this.post === null) {
      return
    }
    try {
      let fav: boolean = await toggleForumFavorite(this.post.postId)
      let old: ForumPost = this.post
      let copy: ForumPost = {
        postId: old.postId, authorId: old.authorId, authorRole: old.authorRole, authorName: old.authorName, authorAvatar: old.authorAvatar,
        title: old.title, content: old.content, createdAt: old.createdAt,
        likeCount: old.likeCount, commentCount: old.commentCount, status: old.status, likedByMe: old.likedByMe, favorited: fav, mediaUrls: old.mediaUrls, dept: old.dept, topics: old.topics
      }
      this.post = copy
      this.getUIContext().getPromptAction().showToast({ message: fav ? '已收藏' : '已取消收藏' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败：' + (e as Error).message })
    }
  }

  async onDeletePost(): Promise<void> {
    if (this.post === null) {
      return
    }
    try {
      await deleteForumPost(this.post.postId)
      this.getUIContext().getPromptAction().showToast({ message: '已删除' })
      this.getUIContext().getRouter().back()
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message })
    }
  }

  // 发评论/回复：parentId 取当前回复目标（无则 0 发主评论）
  async onSubmitComment(): Promise<void> {
    let text = this.commentText.trim()
    if (text === '' && this.commentMedia.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '评论内容和图片至少填一项' })
      return
    }
    if (this.post === null) {
      return
    }
    this.isPosting = true
    let mentionIds: number[] = this.extractMentionIds(text)
    try {
      let created: ForumComment = await addForumComment(this.post.postId, text, this.replyToId, this.commentMedia, mentionIds)
      this.commentText = ''
      this.commentMedia = []
      this.replyToId = 0
      this.replyToName = ''
      // 直接把云函数已返回的新评论并入本地列表（不重查，规避 CloudDB 写完即读的旧快照）
      let next: ForumComment[] = []
      for (let i = 0; i < this.comments.length; i++) {
        next.push(this.comments[i])
      }
      next.push(created)
      this.comments = next
      // 评论数本地 +1（同样避免重查帖子拿到旧计数）
      let old: ForumPost = this.post
      let copy: ForumPost = {
        postId: old.postId, authorId: old.authorId, authorRole: old.authorRole, authorName: old.authorName, authorAvatar: old.authorAvatar,
        title: old.title, content: old.content, createdAt: old.createdAt,
        likeCount: old.likeCount, commentCount: old.commentCount + 1, status: old.status, likedByMe: old.likedByMe, favorited: old.favorited, mediaUrls: old.mediaUrls, dept: old.dept, topics: old.topics
      }
      this.post = copy
      this.getUIContext().getPromptAction().showToast({ message: '已发布' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: (e as Error).message })
    }
    this.isPosting = false
  }

  async onDeleteComment(commentId: number): Promise<void> {
    try {
      await deleteForumComment(commentId)
      // 本地剔除该条（重建数组触发刷新），不重查，避免写完即读的旧快照
      let next: ForumComment[] = []
      for (let i = 0; i < this.comments.length; i++) {
        if (this.comments[i].commentId !== commentId) {
          next.push(this.comments[i])
        }
      }
      this.comments = next
      if (this.post !== null) {
        let old: ForumPost = this.post
        let copy: ForumPost = {
          postId: old.postId, authorId: old.authorId, authorRole: old.authorRole, authorName: old.authorName, authorAvatar: old.authorAvatar,
          title: old.title, content: old.content, createdAt: old.createdAt,
          likeCount: old.likeCount, commentCount: old.commentCount > 0 ? old.commentCount - 1 : 0,
          status: old.status, likedByMe: old.likedByMe, favorited: old.favorited, mediaUrls: old.mediaUrls, dept: old.dept, topics: old.topics
        }
        this.post = copy
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '删除失败：' + (e as Error).message })
    }
  }

  startReply(c: ForumComment): void {
    this.replyToId = c.commentId
    this.replyToName = c.authorName
  }

  cancelReply(): void {
    this.replyToId = 0
    this.replyToName = ''
  }

  // ===== 评论图片选择/上传（复用云存储，同 PostEditPage 那套路） =====
  async pickCommentImages(): Promise<void> {
    if (this.commentUploading || this.isPosting) { return }
    let remain: number = MAX_COMMENT_MEDIA - this.commentMedia.length
    if (remain <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '评论最多 ' + MAX_COMMENT_MEDIA.toString() + ' 张图片' })
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
    this.commentUploading = true
    for (let i = 0; i < uris.length; i++) {
      try {
        let url = await this.uploadCommentImage(uris[i])
        if (url !== '') {
          this.commentMedia = this.commentMedia.concat([url])
        }
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '上传失败：' + (e as Error).message })
        break
      }
    }
    this.commentUploading = false
  }

  uploadCommentImage(uri: string): Promise<string> {
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
      let cloudPath: string = 'comment/image_' + Date.now().toString() + '_' + Math.floor(Math.random() * 100000).toString() + ext
      cBucket.uploadFile(ctx, { localPath: cachePath, cloudPath: cloudPath }).then((task: request.agent.Task) => {
        task.on('completed', () => {
          cBucket.getDownloadURL(cloudPath).then((url: string) => {
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

  removeCommentImage(index: number): void {
    let next: string[] = []
    for (let i = 0; i < this.commentMedia.length; i++) {
      if (i !== index) { next.push(this.commentMedia[i]) }
    }
    this.commentMedia = next
  }

  canDeletePost(): boolean {
    if (this.post === null) {
      return false
    }
    return this.myRole === 'admin' || this.post.authorId === this.myUserId
  }

  canDeleteComment(c: ForumComment): boolean {
    if (this.post === null) {
      return c.authorId === this.myUserId
    }
    return this.myRole === 'admin' || c.authorId === this.myUserId || this.post.authorId === this.myUserId
  }

  // 是否可对作者发起私信：非管理员、作者非本人且非管理员
  canDmAuthor(): boolean {
    if (this.post === null) {
      return false
    }
    if (this.myRole === 'admin') {
      return false
    }
    return this.post.authorRole !== 'admin' && this.post.authorId !== this.myUserId
  }

  openAuthorDm(): void {
    if (this.post === null) {
      return
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatPage',
        params: {
          peerId: this.post!.authorId,
          peerName: this.post!.authorName,
          peerAvatar: this.post!.authorAvatar !== undefined ? this.post!.authorAvatar : ''
        }
      })
    } catch (e) {
      console.error('打开私信失败: ' + (e as Error).message)
    }
  }

  // 点头像：先记下目标用户并打开弹层，再异步拉公开简介（失败也能显示名字/角色兜底）
  openProfile(userId: number, name: string, role: string): void {
    if (userId <= 0) {
      return
    }
    this.sheetPeerId = userId
    this.sheetPeerName = name
    this.sheetPeerRole = role
    this.brief = null
    this.briefLoading = true
    this.showProfile = true
    getForumUserBrief(userId).then((b: ForumUserBrief | null) => {
      this.brief = b
      this.briefLoading = false
    })
  }

  // 弹层里是否显示"私信"：本人/管理员不可发，对方是管理员也不发
  canDmBrief(): boolean {
    const r: string = this.brief !== null ? this.brief.role : this.sheetPeerRole
    if (this.myRole === 'admin') {
      return false
    }
    return this.sheetPeerId !== this.myUserId && r !== 'admin'
  }

  // 从弹层发起私信：先收起弹层再跳转
  openDmFromBrief(): void {
    this.showProfile = false
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatPage',
        params: {
          peerId: this.sheetPeerId,
          peerName: this.sheetPeerName,
          peerAvatar: (this.brief !== null && this.brief.avatarUrl !== undefined) ? this.brief.avatarUrl : ''
        }
      })
    } catch (e) {
      console.error('打开私信失败: ' + (e as Error).message)
    }
  }

  // 注册时间 YYYY-MM-DD
  regDateText(iso: string): string {
    if (iso === '' || iso.length < 10) {
      return '未知'
    }
    return iso.substring(0, 10)
  }

  // 注册时长："已加入 X"
  joinDuration(iso: string): string {
    if (iso === '' || iso.length < 10) {
      return '未知'
    }
    const then: number = new Date(iso).getTime()
    if (isNaN(then)) {
      return '未知'
    }
    const days: number = Math.floor((Date.now() - then) / 86400000)
    if (days <= 0) {
      return '今天刚加入'
    }
    if (days < 30) {
      return days + ' 天'
    }
    if (days < 365) {
      return Math.floor(days / 30) + ' 个月'
    }
    const y: number = Math.floor(days / 365)
    const m: number = Math.floor((days % 365) / 30)
    return m > 0 ? (y + ' 年 ' + m + ' 个月') : (y + ' 年')
  }

  roleLabel(role: string): string {
    if (role === 'doctor') { return '医生' }
    if (role === 'admin') { return '管理员' }
    return '病友'
  }

  formatTime(iso: string): string {
    if (iso === '' || iso.length < 16) {
      return iso
    }
    return iso.substring(0, 10) + ' ' + iso.substring(11, 16)
  }

  // 沿 parentId 上溯到主评论 id（带环保护）
  rootAncestorId(c: ForumComment, map: Map<number, ForumComment>): number {
    let cur: ForumComment = c
    let guard: number = 0
    while (cur.parentId !== 0 && guard < 50) {
      let parent: ForumComment | undefined = map.get(cur.parentId)
      if (parent === undefined) {
        break
      }
      cur = parent
      guard++
    }
    return cur.commentId
  }

  // 把扁平评论组装成两级线程：主评论 + 归并回复（回复的回复并进同一线程）
  buildThreads(): CommentThread[] {
    let map: Map<number, ForumComment> = new Map<number, ForumComment>()
    for (let i = 0; i < this.comments.length; i++) {
      map.set(this.comments[i].commentId, this.comments[i])
    }
    let roots: ForumComment[] = []
    for (let j = 0; j < this.comments.length; j++) {
      if (this.comments[j].parentId === 0) {
        roots.push(this.comments[j])
      }
    }
    roots.sort((a: ForumComment, b: ForumComment) => (a.createdAt > b.createdAt ? 1 : a.createdAt < b.createdAt ? -1 : 0))

    let threads: CommentThread[] = []
    for (let r = 0; r < roots.length; r++) {
      let root: ForumComment = roots[r]
      let replies: ReplyView[] = []
      for (let k = 0; k < this.comments.length; k++) {
        let c: ForumComment = this.comments[k]
        if (c.parentId !== 0 && this.rootAncestorId(c, map) === root.commentId) {
          // 直接父级本身是回复时，才显示"回复 @某人"
          let parent: ForumComment | undefined = map.get(c.parentId)
          let mention: string = (parent !== undefined && parent.parentId !== 0) ? parent.authorName : ''
          let rv: ReplyView = { c: c, mention: mention }
          replies.push(rv)
        }
      }
      replies.sort((a: ReplyView, b: ReplyView) => (a.c.createdAt > b.c.createdAt ? 1 : a.c.createdAt < b.c.createdAt ? -1 : 0))
      let thread: CommentThread = { root: root, replies: replies }
      threads.push(thread)
    }
    return threads
  }

  @Builder
  buildCommentHeader(c: ForumComment, avatarSize: number) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        if (c.authorAvatar !== undefined && c.authorAvatar !== '') {
          Image(c.authorAvatar).width(avatarSize).height(avatarSize).objectFit(ImageFit.Cover)
        } else {
          Image(resolveAvatar('', c.authorRole))
            .width(avatarSize * 0.44).height(avatarSize * 0.44).fillColor('#FFFFFF')
        }
      }
      .width(avatarSize).height(avatarSize).borderRadius(avatarSize * 0.5)
      .backgroundColor(c.authorRole === 'doctor' ? C_SUGAR : ACCENT)
      .clip(true)
      .onClick(() => { this.openProfile(c.authorId, c.authorName, c.authorRole) })
      Text(c.authorName)
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(TEXT_MAIN).margin({ left: 8 })
        .onClick(() => { this.openProfile(c.authorId, c.authorName, c.authorRole) })
      Text(this.roleLabel(c.authorRole))
        .fontSize(10).fontColor(c.authorRole === 'doctor' ? C_SUGAR : TEXT_SUB)
        .backgroundColor(c.authorRole === 'doctor' ? C_SUGAR_BG : TILE_BG)
        .padding({ left: 5, right: 5, top: 1, bottom: 1 }).borderRadius(6).margin({ left: 6 })
      Blank()
      Text(this.formatTime(c.createdAt))
        .fontSize(10).fontColor(TEXT_FAINT)
    }
    .width('100%')
  }

  @Builder
  buildCommentActions(c: ForumComment) {
    Row() {
      Blank()
      if (this.myRole !== 'admin') {
        Text('回复')
          .fontSize(11).fontColor(ACCENT).margin({ right: 14 })
          .onClick(() => { this.startReply(c) })
      }
      if (this.canDeleteComment(c)) {
        Text('删除')
          .fontSize(11).fontColor(DANGER)
          .onClick(() => { this.onDeleteComment(c.commentId) })
      }
    }
    .width('100%')
    .margin({ top: 6 })
  }

  @Builder
  buildReplyItem(rv: ReplyView) {
    Column() {
      this.buildCommentHeader(rv.c, 18)

      // "回复 @某人" 前缀（回复的回复才有）
      if (rv.mention !== '') {
        Text('回复 @' + rv.mention)
          .fontSize(12).fontColor(ACCENT)
          .width('100%').margin({ top: 5 }).textAlign(TextAlign.Start)
      }

      this.commentBody(4, rv.c.content, 13, '#5A6072', 18)

      if (parseMediaUrls(rv.c.mediaUrls).length > 0) {
        Row() {
          ForEach(parseMediaUrls(rv.c.mediaUrls), (url: string) => {
            Image(url).width(64).height(64).objectFit(ImageFit.Cover).borderRadius(8).backgroundColor(TILE_BG).margin({ right: 6 })
          }, (url: string) => url)
        }.width('100%').margin({ top: 6 })
      }

      this.buildCommentActions(rv.c)
    }
    .width('100%')
    .padding({ left: 34, top: 10, bottom: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildThread(thread: CommentThread) {
    Column() {
      // 主评论
      Column() {
        this.buildCommentHeader(thread.root, 22)
        this.commentBody(6, thread.root.content, 14, '#3A4157', 21)
        if (parseMediaUrls(thread.root.mediaUrls).length > 0) {
          Row() {
            ForEach(parseMediaUrls(thread.root.mediaUrls), (url: string) => {
              Image(url).width(72).height(72).objectFit(ImageFit.Cover).borderRadius(8).backgroundColor(TILE_BG).margin({ right: 6 })
            }, (url: string) => url)
          }.width('100%').margin({ top: 6 })
        }
        this.buildCommentActions(thread.root)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 回复区（浅底 + 左缩进）
      if (thread.replies.length > 0) {
        Column() {
          ForEach(thread.replies, (rv: ReplyView) => {
            this.buildReplyItem(rv)
          }, (rv: ReplyView) => rv.c.commentId.toString())
        }
        .width('100%')
        .backgroundColor(SURFACE_SUNK)
        .borderRadius(12)
        .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  profileSheet() {
    Column() {
      // 顶部：头像 + 昵称 + 角色
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          if (this.brief !== null && this.brief.avatarUrl !== undefined && this.brief.avatarUrl !== '') {
            Image(this.brief.avatarUrl).width(44).height(44).objectFit(ImageFit.Cover)
          } else {
            Image(resolveAvatar('', this.brief !== null ? this.brief.role : this.sheetPeerRole))
              .width(19).height(19).fillColor('#FFFFFF')
          }
        }
        .width(44).height(44).borderRadius(22)
        .backgroundColor((this.brief !== null ? this.brief.role : this.sheetPeerRole) === 'doctor' ? C_SUGAR : ACCENT)
        .clip(true)
        Column() {
          Text(this.brief !== null ? this.brief.nickname : this.sheetPeerName)
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
          Text(this.roleLabel(this.brief !== null ? this.brief.role : this.sheetPeerRole))
            .fontSize(11).fontColor(TEXT_SUB).margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })
        Blank()
      }
      .width('100%')
      .padding({ top: 8, bottom: 14 })

      if (this.briefLoading) {
        Column() {
          LoadingProgress().width(32).height(32).color(ACCENT)
        }
        .width('100%').height(140).justifyContent(FlexAlign.Center)
      } else if (this.brief === null) {
        Text('简介加载失败，请稍后重试')
          .fontSize(13).fontColor(TEXT_FAINT)
          .width('100%').height(120).textAlign(TextAlign.Center)
      } else {
        Scroll() {
          Column() {
            // 统计块：发帖数 / 获赞数
            Row() {
              Column() {
                Text(this.brief.postCount.toString())
                  .fontSize(22).fontWeight(FontWeight.Bold).fontColor(ACCENT)
                Text('发帖').fontSize(12).fontColor(TEXT_SUB).margin({ top: 4 })
              }
              .layoutWeight(1).height(78)
              .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
              .backgroundColor(TILE_BG).borderRadius(R_CARD)

              Column() {
                Text(this.brief.likeTotal.toString())
                  .fontSize(22).fontWeight(FontWeight.Bold).fontColor(DANGER)
                Text('获赞').fontSize(12).fontColor(TEXT_SUB).margin({ top: 4 })
              }
              .layoutWeight(1).height(78)
              .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
              .backgroundColor(TILE_BG).borderRadius(R_CARD)
              .margin({ left: 12 })
            }
            .width('100%')
            .margin({ bottom: 14 })

            // 明细行
            Column() {
              this.infoRow('性别', this.brief.genderText)
              this.infoRow('注册于', this.regDateText(this.brief.createdAt))
              this.infoRow('已加入', this.joinDuration(this.brief.createdAt))
              if (this.brief.role === 'doctor' && this.brief.doctorLicense !== '') {
                this.infoRow('执业执照号', this.brief.doctorLicense)
              }
            }
            .width('100%')

            // 私信入口
            if (this.canDmBrief()) {
              Button('发私信')
                .width('100%').height(44)
                .backgroundColor(ACCENT).fontColor('#FFFFFF')
                .borderRadius(R_CARD)
                .margin({ top: 18 })
                .onClick(() => { this.openDmFromBrief() })
            } else if (this.sheetPeerId === this.myUserId) {
              Text('这是你本人')
                .fontSize(12).fontColor(TEXT_FAINT)
                .width('100%').textAlign(TextAlign.Center).margin({ top: 16 })
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
    .backgroundColor(CARD_BG)
    .alignItems(HorizontalAlign.Start)
  }

  // 弹层里的「标签 - 值」一行
  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor(TEXT_SUB)
      Blank()
      Text(value).fontSize(14).fontColor(TEXT_MAIN)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  // 站内分享：选人 → 把本帖以私信转发过去
  async openShare(): Promise<void> {
    if (this.post === null) { return }
    this.shareSelected = []
    if (this.mentionAll.length === 0) {
      await this.buildMentionCandidates()
    }
    this.showShareSheet = true
  }

  toggleShareTarget(id: number): void {
    let idx: number = this.shareSelected.indexOf(id)
    let next: number[] = []
    if (idx >= 0) {
      for (let i = 0; i < this.shareSelected.length; i++) {
        if (i !== idx) { next.push(this.shareSelected[i]) }
      }
      this.shareSelected = next
    } else {
      next = this.shareSelected.slice()
      next.push(id)
      this.shareSelected = next
    }
  }

  async confirmShare(): Promise<void> {
    if (this.post === null) { return }
    if (this.shareSelected.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择要分享的人' })
      return
    }
    try {
      let n: number = await shareForumPost(this.post.postId, this.shareSelected)
      this.showShareSheet = false
      this.getUIContext().getPromptAction().showToast({ message: '已分享给 ' + n.toString() + ' 位病友' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: (e as Error).message })
    }
  }

  @Builder
  shareSheet() {
    Column() {
      Text('分享给')
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(TEXT_MAIN)
        .width('100%').margin({ top: 4, bottom: 8 })

      if (this.mentionAll.length === 0) {
        Text('还没有可分享的人——先在帖子和评论里互动，或和别人私信过，就能把帖子转给他')
          .fontSize(13).fontColor(TEXT_FAINT)
          .width('100%').textAlign(TextAlign.Center).margin({ top: 40 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.mentionAll, (c: MentionCandidate) => {
              Row() {
                Stack({ alignContent: Alignment.Center }) {
                  if (c.avatar !== '') {
                    Image(c.avatar).width(34).height(34).objectFit(ImageFit.Cover)
                  } else {
                    Image(resolveAvatar('', c.role))
                      .width(15).height(15).fillColor('#FFFFFF')
                  }
                }
                .width(34).height(34).borderRadius(17)
                .backgroundColor(c.role === 'doctor' ? C_SUGAR : ACCENT)
                .clip(true)
                Column() {
                  Text(c.name).fontSize(14).fontColor(TEXT_MAIN)
                  Text(this.roleTextOf(c.role)).fontSize(11).fontColor(TEXT_FAINT)
                }
                .alignItems(HorizontalAlign.Start).margin({ left: 10 }).layoutWeight(1)

                // 选中态：实心勾圆，未选：描边空圆
                if (this.shareSelected.indexOf(c.id) >= 0) {
                  Text('✓').fontSize(14).fontColor('#FFFFFF').textAlign(TextAlign.Center)
                    .width(24).height(24).borderRadius(12).backgroundColor(ACCENT)
                } else {
                  Text('').width(22).height(22).borderRadius(11)
                    .border({ width: 1.5, color: TEXT_FAINT })
                }
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .onClick(() => { this.toggleShareTarget(c.id) })
            }, (c: MentionCandidate) => c.id.toString() + '_' + (this.shareSelected.indexOf(c.id) >= 0 ? 1 : 0))
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      Button('发送（已选 ' + this.shareSelected.length.toString() + '）')
        .width('100%').height(46).fontSize(15).fontColor('#FFFFFF')
        .backgroundColor(ACCENT).borderRadius(14).margin({ top: 12 })
        .onClick(() => { this.confirmShare() })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      NavBar({
        title: '帖子详情',
        rightText: this.canDeletePost() ? '删除' : '',
        onRight: () => { this.onDeletePost() }
      })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(48).height(48).color(ACCENT)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else if (this.post === null) {
        Column() {
          Text('帖子不存在或已被删除')
            .fontSize(15).fontColor(TEXT_SUB)
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              // 帖子正文卡
              Column() {
                Row() {
                  Stack({ alignContent: Alignment.Center }) {
                    if (this.post!.authorAvatar !== undefined && this.post!.authorAvatar !== '') {
                      Image(this.post!.authorAvatar).width(22).height(22).objectFit(ImageFit.Cover)
                    } else {
                      Image(resolveAvatar('', this.post!.authorRole))
                        .width(10).height(10).fillColor('#FFFFFF')
                    }
                  }
                  .width(22).height(22).borderRadius(12)
                  .backgroundColor(this.post!.authorRole === 'doctor' ? C_SUGAR : ACCENT)
                  .clip(true)
                  .onClick(() => { this.openProfile(this.post!.authorId, this.post!.authorName, this.post!.authorRole) })
                  Text(this.post!.authorName)
                    .fontSize(14).fontWeight(FontWeight.Medium).fontColor(TEXT_MAIN).margin({ left: 8 })
                    .onClick(() => { this.openProfile(this.post!.authorId, this.post!.authorName, this.post!.authorRole) })
                  Text(this.roleLabel(this.post!.authorRole))
                    .fontSize(10).fontColor(this.post!.authorRole === 'doctor' ? C_SUGAR : TEXT_SUB)
                    .backgroundColor(this.post!.authorRole === 'doctor' ? C_SUGAR_BG : TILE_BG)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(8).margin({ left: 6 })
                  if (this.canDmAuthor()) {
                    Text('私信')
                      .fontSize(11).fontColor(ACCENT)
                      .backgroundColor(JADE_SOFT)
                      .padding({ left: 10, right: 10, top: 3, bottom: 3 }).borderRadius(10).margin({ left: 8 })
                      .onClick(() => { this.openAuthorDm() })
                  }
                  Blank()
                  Text(this.formatTime(this.post!.createdAt))
                    .fontSize(11).fontColor(TEXT_FAINT)
                }
                .width('100%')

                Text(this.post!.title)
                  .fontSize(19).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
                  .width('100%').margin({ top: 14 }).textAlign(TextAlign.Start)

                this.commentBody(10, this.post!.content, 14, '#3A4157', 22)

                if (this.post!.dept !== '' || parseTopics(this.post!.topics).length > 0) {
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    if (this.post!.dept !== '') {
                      Text(this.post!.dept)
                        .fontSize(12).fontColor(ACCENT)
                        .backgroundColor(JADE_SOFT)
                        .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                        .borderRadius(8)
                        .margin({ right: 8, top: 12 })
                    }
                    ForEach(parseTopics(this.post!.topics), (tp: string) => {
                      Text(tp)
                        .fontSize(12).fontColor(C_SUGAR)
                        .backgroundColor(C_SUGAR_BG)
                        .padding({ left: 9, right: 9, top: 4, bottom: 4 })
                        .borderRadius(8)
                        .margin({ right: 8, top: 12 })
                    }, (tp: string) => tp)
                  }
                  .width('100%')
                }

                if (parseMediaUrls(this.post!.mediaUrls).length > 0) {
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(parseMediaUrls(this.post!.mediaUrls), (url: string) => {
                      Image(url)
                        .width('32%')
                        .aspectRatio(1)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(10)
                        .backgroundColor(TILE_BG)
                        .margin({ right: '0.6%', top: 10 })
                    }, (url: string) => url)
                  }
                  .width('100%')
                  .margin({ top: 4 })
                }

                Divider().color(HAIRLINE).strokeWidth(1).margin({ top: 16, bottom: 12 })

                Row() {
                  Row() {
                    Image($r('app.media.ic_heart'))
                      .width(18).height(18)
                      .fillColor(this.post!.likedByMe ? DANGER : TEXT_FAINT)
                    Text(this.post!.likeCount.toString() + ' 点赞')
                      .fontSize(13).fontColor(this.post!.likedByMe ? DANGER : TEXT_SUB).margin({ left: 5 })
                  }
                  .onClick(() => { this.onLike() })

                  Blank()

                  Text(this.post!.commentCount.toString() + ' 回复')
                    .fontSize(13).fontColor(TEXT_SUB)

                  Blank()

                  Row() {
                    Image($r('app.media.ic_star'))
                      .width(18).height(18)
                      .fillColor(this.post!.favorited ? WARN : TEXT_FAINT)
                    Text(this.post!.favorited ? '已收藏' : '收藏')
                      .fontSize(13).fontColor(this.post!.favorited ? WARN : TEXT_SUB).margin({ left: 5 })
                  }
                  .onClick(() => { this.onFavorite() })

                  // 分享：站内转发给互动过的人（管理员不参与私信/分享，故隐藏）
                  if (this.myRole !== 'admin') {
                    Blank()
                    Row() {
                      Image($r('app.media.ic_share'))
                        .width(18).height(18)
                        .fillColor(TEXT_SUB)
                      Text('分享')
                        .fontSize(13).fontColor(TEXT_SUB).margin({ left: 5 })
                    }
                    .onClick(() => { this.openShare() })
                    .bindSheet($$this.showShareSheet, this.shareSheet(), {
                      title: { title: '分享帖子' },
                      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                      dragBar: true,
                      showClose: true
                    })
                  }
                }
                .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor(CARD_BG)
              .borderRadius(R_CARD)
              .shadow(SHADOW_CARD)
              .alignItems(HorizontalAlign.Start)
              .margin({ top: 16 })

              // 评论区（两级线程）
              Column() {
                Text('全部回复（' + this.comments.length + '）')
                  .fontSize(15).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
                  .width('100%').margin({ bottom: 4 })

                if (this.comments.length === 0) {
                  Text('还没有回复，抢占第一条吧～')
                    .fontSize(13).fontColor(TEXT_FAINT).width('100%')
                    .textAlign(TextAlign.Center).padding({ top: 20, bottom: 20 })
                } else {
                  ForEach(this.buildThreads(), (t: CommentThread) => {
                    Divider().color('#F0F2F8').strokeWidth(1)
                    this.buildThread(t)
                  }, (t: CommentThread) => {
                    // key 需包含本线程所有回复 id：仅用 root.commentId 时，
                    // 增删线程内的回复不会改变 key 集合，ArkUI 会跳过重渲染导致界面不更新
                    let ids: string = ''
                    for (let i = 0; i < t.replies.length; i++) {
                      ids += '_' + t.replies[i].c.commentId.toString()
                    }
                    return t.root.commentId.toString() + ids
                  })
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor(CARD_BG)
              .borderRadius(R_CARD)
              .shadow(SHADOW_CARD)
              .alignItems(HorizontalAlign.Start)
              .margin({ top: 14, bottom: 16 })
            }
            .width('100%')
            .padding({ left: 20, right: 20 })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
          }
          .layoutWeight(1)
          .onRefreshing(async () => {
            await this.refreshData()
            this.refreshing = false
          })

          // 底部输入区（管理员不参与发言）
          if (this.myRole !== 'admin') {
            Column() {
              if (this.replyToId !== 0) {
                Row() {
                  Text('回复 @' + this.replyToName)
                    .fontSize(12).fontColor(ACCENT)
                  Blank()
                  Text('取消')
                    .fontSize(12).fontColor(TEXT_SUB)
                    .onClick(() => { this.cancelReply() })
                }
                .width('100%')
                .padding({ left: 4, right: 4, bottom: 8 })
              }

              Row() {
                TextInput({ placeholder: this.replyToId !== 0 ? ('回复 @' + this.replyToName + '…') : '写下你的回复…', text: this.commentText })
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(14)
                  .backgroundColor(TILE_BG)
                  .borderRadius(21)
                  .onChange((v: string) => { this.commentText = v })

                // @某人：打开选人弹层，选中后把 @昵称 插进输入框
                Text('@')
                  .fontSize(18)
                  .fontColor(ACCENT)
                  .fontWeight(FontWeight.Bold)
                  .width(26)
                  .height(26)
                  .textAlign(TextAlign.Center)
                  .margin({ left: 10 })
                  .onClick(() => { this.openMentionPicker() })

                Image($r('app.media.ic_data_add'))
                  .width(22)
                  .height(22)
                  .fillColor(this.commentMedia.length >= MAX_COMMENT_MEDIA ? TEXT_FAINT : ACCENT)
                  .margin({ left: 10 })
                  .onClick(() => { this.pickCommentImages() })

                Text('发送')
                  .fontSize(14)
                  .fontColor('#FFFFFF')
                  .fontWeight(FontWeight.Medium)
                  .padding({ left: 18, right: 18, top: 10, bottom: 10 })
                  .borderRadius(21)
                  .backgroundColor(this.isPosting ? TEXT_FAINT : ACCENT)
                  .margin({ left: 10 })
                  .onClick(() => {
                    if (!this.isPosting) {
                      this.onSubmitComment()
                    }
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .bindSheet($$this.showMentionSheet, this.mentionSheet(), {
                title: { title: '选择要 @ 的人' },
                detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                dragBar: true,
                showClose: true
              })

              if (this.commentMedia.length > 0 || this.commentUploading) {
                Row() {
                  ForEach(this.commentMedia, (url: string, idx: number) => {
                    Stack({ alignContent: Alignment.TopEnd }) {
                      Image(url)
                        .width(52)
                        .height(52)
                        .objectFit(ImageFit.Cover)
                        .borderRadius(8)
                        .backgroundColor(TILE_BG)
                      Text('×')
                        .fontSize(14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#FFFFFF')
                        .width(18)
                        .height(18)
                        .borderRadius(9)
                        .backgroundColor('#99000000')
                        .textAlign(TextAlign.Center)
                        .onClick(() => { this.removeCommentImage(idx) })
                    }
                    .width(52)
                    .height(52)
                    .margin({ right: 8 })
                  }, (url: string, idx: number) => idx.toString() + '_' + url)
                  if (this.commentUploading) {
                    Text('上传中…')
                      .fontSize(11)
                      .fontColor(WARN)
                  }
                }
                .width('100%')
                .padding({ top: 8 })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 12 })
            .backgroundColor(CARD_BG)
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAGE)
    .bindSheet($$this.showProfile, this.profileSheet(), {
      height: 460,
      dragBar: true,
      showClose: true,
      backgroundColor: CARD_BG,
      onDisappear: () => { this.showProfile = false }
    })
  }
}
