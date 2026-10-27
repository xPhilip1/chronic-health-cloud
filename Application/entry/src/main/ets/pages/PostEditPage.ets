import { ForumPost, DmConversation } from '../model/ForumModel'
import { createForumPost, listMyConversations, getCurrentUser } from '../service/ApiService'
import {
  BG_PAGE, CARD_BG, TILE_BG, TEXT_MAIN, TEXT_FAINT, ACCENT, WARN, R_CARD, SHADOW_CARD
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { photoAccessHelper } from '@kit.MediaLibraryKit'
import { cloudStorage } from '@kit.CloudFoundationKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError, request } from '@kit.BasicServicesKit'
import { DISEASE_TAGS, TOPIC_TAGS, MAX_TOPIC } from '../common/Tags'
import { Draft, saveDraft, getDraft, deleteDraft, newDraftId } from '../service/DraftStore'

const MAX_MEDIA = 3
const bucket: cloudStorage.StorageBucket = cloudStorage.bucket()

// 发帖时可选的 @ 对象（这里取自"我的私信联系人"）
interface MentionCandidate {
  id: number
  name: string
  role: string
}

@Entry
@Component
struct PostEditPage {
  @State title: string = ''
  @State content: string = ''
  @State submitting: boolean = false
  @State mediaUrls: string[] = []   // 已上传到云存储、可直接展示的图片地址
  @State uploading: boolean = false // 是否有图片正在上传（上传中禁止再加/发布）
  @State selectedDept: string = ''       // 病种标签（单选），空串表示不选；字段名沿用 dept 以兼容存储
  @State selectedTopics: string[] = []   // 话题标签（多选，最多 MAX_TOPIC 个）
  @State draftId: string = ''            // 非空表示正在编辑一条已有草稿
  // @某人：候选=我的私信联系人；只在发帖时用来把 @昵称 插进正文并记录要通知谁的 userId
  @State mentionAll: MentionCandidate[] = []
  @State showMentionSheet: boolean = false
  @State mentionKeyword: string = ''
  private myUserId: number = 0

  async aboutToAppear(): Promise<void> {
    let params = this.getUIContext().getRouter().getParams() as Record<string, string>
    let did: string = (params !== null && params !== undefined && params['draftId']) ? (params['draftId'] as string) : ''
    // 记下当前用户，@ 时排除自己
    let cur = await getCurrentUser()
    if (cur !== null) { this.myUserId = cur.userId }
    if (did === '') { return }
    // 从草稿箱进来：回填草稿内容，之后可原地覆盖这条草稿
    this.draftId = did
    let ctx = this.getUIContext().getHostContext()
    if (ctx === undefined) { return }
    let d: Draft | null = await getDraft(ctx, did)
    if (d !== null) {
      this.title = d.title
      this.content = d.content
      this.mediaUrls = d.mediaUrls
      this.selectedDept = d.dept
      this.selectedTopics = d.topics
    }
  }

  // 选图 → 逐张上传云存储 → 收集下载地址
  async pickImages(): Promise<void> {
    if (this.uploading || this.submitting) { return }
    let remain: number = MAX_MEDIA - this.mediaUrls.length
    if (remain <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '最多上传 ' + MAX_MEDIA.toString() + ' 张图片' })
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
      console.error('选图失败: ' + (e as Error).message)
      this.getUIContext().getPromptAction().showToast({ message: '选图失败：' + (e as Error).message })
      return
    }
    if (uris === undefined || uris.length === 0) { return }
    this.uploading = true
    for (let i = 0; i < uris.length; i++) {
      try {
        let url = await this.uploadOne(uris[i])
        if (url !== '') {
          this.mediaUrls = this.mediaUrls.concat([url])
        }
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '上传失败：' + (e as Error).message })
        break
      }
    }
    this.uploading = false
  }

  // 把相册里的图片拷到缓存 → 上传 → 拿下载地址 → 删缓存；任一步失败都抛出具体原因
  uploadOne(uri: string): Promise<string> {
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
        reject(new Error('复制图片到缓存失败：' + (e as Error).message))
        return
      }
      let ext: string = fileName.indexOf('.') >= 0 ? fileName.substring(fileName.lastIndexOf('.')) : '.jpg'
      let cloudPath: string = 'forum/image_' + Date.now().toString() + '_' + Math.floor(Math.random() * 100000).toString() + ext
      bucket.uploadFile(ctx, { localPath: cachePath, cloudPath: cloudPath }).then((task: request.agent.Task) => {
        let lastResp: string = ''
        task.on('response', (res) => {
          lastResp = 'HTTP ' + res.statusCode.toString() + ' ' + JSON.stringify(res)
          console.error('上传 response: ' + lastResp)
        })
        task.on('completed', () => {
          bucket.getDownloadURL(cloudPath).then((url: string) => {
            fileIo.unlink(cachePath).catch((err: BusinessError) => {})
            resolve(url)
          }).catch((err: BusinessError) => {
            console.error('getDownloadURL 失败 code=' + err.code.toString() + ' msg=' + err.message)
            fileIo.unlink(cachePath).catch((e2: BusinessError) => {})
            reject(new Error('取下载地址失败(' + err.code.toString() + ')：' + err.message))
          })
        })
        task.on('failed', (progress) => {
          console.error('上传任务失败 resp=' + JSON.stringify(progress))
          fileIo.unlink(cachePath).catch((err: BusinessError) => {})
          let hint: string = lastResp === '' ? '（无响应码，多为未登录/未关联存储实例）' : lastResp
          reject(new Error('云存储上传被拒 ' + hint))
        })
        task.start().catch((err: BusinessError) => {
          console.error('task.start 失败 code=' + err.code.toString() + ' msg=' + err.message)
          fileIo.unlink(cachePath).catch((e2: BusinessError) => {})
          reject(new Error('启动上传失败(' + err.code.toString() + ')：' + err.message))
        })
      }).catch((err: BusinessError) => {
        console.error('uploadFile 建任务失败 code=' + err.code.toString() + ' msg=' + err.message)
        fileIo.unlink(cachePath).catch((e2: BusinessError) => {})
        reject(new Error('创建上传任务失败(' + err.code.toString() + ')：' + err.message))
      })
    })
  }

  // 移除某张已上传预览（仅从本次待发列表删除，云端文件留待后续清理）
  removeImage(index: number): void {
    let next: string[] = []
    for (let i = 0; i < this.mediaUrls.length; i++) {
      if (i !== index) { next.push(this.mediaUrls[i]) }
    }
    this.mediaUrls = next
  }

  // 病种：单选，再点同一个即取消
  toggleDept(name: string): void {
    this.selectedDept = this.selectedDept === name ? '' : name
  }

  // 话题：多选，最多 MAX_TOPIC 个；已选满再点新的给提示
  toggleTopic(name: string): void {
    let idx: number = this.selectedTopics.indexOf(name)
    if (idx >= 0) {
      let next: string[] = []
      for (let i = 0; i < this.selectedTopics.length; i++) {
        if (i !== idx) { next.push(this.selectedTopics[i]) }
      }
      this.selectedTopics = next
      return
    }
    if (this.selectedTopics.length >= MAX_TOPIC) {
      this.getUIContext().getPromptAction().showToast({ message: '话题最多选 ' + MAX_TOPIC.toString() + ' 个' })
      return
    }
    this.selectedTopics = this.selectedTopics.concat([name])
  }

  // @某人候选人=我的私信联系人（懒加载一次），发帖时把 @昵称 插进正文，发布时据此解析要通知谁
  async ensureMentionsLoaded(): Promise<void> {
    if (this.mentionAll.length > 0) { return }
    let out: MentionCandidate[] = []
    let seen: number[] = []
    try {
      let convs: DmConversation[] = await listMyConversations()
      for (let i = 0; i < convs.length; i++) {
        let id: number = convs[i].peerId
        let name: string = convs[i].peerName
        if (id <= 0 || id === this.myUserId || name === '' || seen.indexOf(id) >= 0) { continue }
        seen.push(id)
        out.push({ id: id, name: name, role: '' })
      }
    } catch (e) {
      // 拉联系人失败不影响发帖，只是没有可@的人
    }
    this.mentionAll = out
  }

  filteredMentions(): MentionCandidate[] {
    let kw: string = this.mentionKeyword.trim().toLowerCase()
    if (kw === '') { return this.mentionAll }
    let out: MentionCandidate[] = []
    for (let i = 0; i < this.mentionAll.length; i++) {
      if (this.mentionAll[i].name.toLowerCase().indexOf(kw) >= 0) { out.push(this.mentionAll[i]) }
    }
    return out
  }

  async openMentionPicker(): Promise<void> {
    this.mentionKeyword = ''
    await this.ensureMentionsLoaded()
    this.showMentionSheet = true
  }

  insertMention(c: MentionCandidate): void {
    this.content = this.content + '@' + c.name + ' '
    this.showMentionSheet = false
  }

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

  async onPublish(): Promise<void> {
    let c = this.content.trim()
    if (this.uploading) {
      this.getUIContext().getPromptAction().showToast({ message: '图片上传中，请稍候…' })
      return
    }
    if (c === '' && this.mediaUrls.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '正文和图片至少填一项' })
      return
    }
    this.submitting = true
    await this.ensureMentionsLoaded()
    let mentionIds: number[] = this.extractMentionIds(c)
    try {
      let p: ForumPost = await createForumPost(this.title.trim(), c, this.mediaUrls, this.selectedDept, this.selectedTopics, mentionIds)
      // 发帖成功 = 这条草稿已经"落地"成正式帖，若本次是从草稿箱带出来的(draftId 非空)，就把本地草稿清掉，避免草稿箱里留一份过期的
      if (this.draftId !== '') {
        let ctx = this.getUIContext().getHostContext()
        if (ctx !== undefined) { await deleteDraft(ctx, this.draftId) }
      }
      this.getUIContext().getPromptAction().showToast({ message: '发布成功' })
      // 发帖成功后退回论坛列表（onPageShow 会自动刷新出这条新帖）
      this.getUIContext().getRouter().back()
    } catch (e) {
      // 命中敏感词/处于禁言时，服务端返回的是给用户看的友好文案，直接展示
      this.getUIContext().getPromptAction().showToast({ message: (e as Error).message })
    }
    this.submitting = false
  }

  // 存草稿：不发出去，只把当前编辑内容(标题/正文/图片/标签)落到本地草稿箱。
  // 与"发布"不同，草稿允许是空的或半成的——只有标题、只有图、甚至只字未打都能存。
  async onSaveDraft(): Promise<void> {
    if (this.uploading) {
      this.getUIContext().getPromptAction().showToast({ message: '图片上传中，请稍候…' })
      return
    }
    let ctx = this.getUIContext().getHostContext()
    if (ctx === undefined) { return }
    // 已经在编辑某条草稿就沿用它原来的 id(原地覆盖)，否则新建一条
    let id: string = this.draftId !== '' ? this.draftId : newDraftId()
    let draft: Draft = {
      id: id,
      title: this.title,
      content: this.content,
      mediaUrls: this.mediaUrls,
      dept: this.selectedDept,
      topics: this.selectedTopics,
      updatedAt: new Date().toISOString()
    }
    try {
      await saveDraft(ctx, draft)
      this.getUIContext().getPromptAction().showToast({ message: '已存入草稿箱' })
      this.getUIContext().getRouter().back()
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '存草稿失败：' + (e as Error).message })
    }
  }

  // 选人弹层：搜索 + 候选人列表，点一条把 @昵称 插进正文
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
        Text('还没有可 @ 的人——先去和病友/医生私信互动，之后就能在这里 @ 到对方')
          .fontSize(13).fontColor(TEXT_FAINT)
          .width('100%').textAlign(TextAlign.Center).margin({ top: 40 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.filteredMentions(), (c: MentionCandidate) => {
              Row() {
                Text(c.name).fontSize(14).fontColor(TEXT_MAIN)
                Blank()
                Text('@').fontSize(18).fontColor(ACCENT).fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .padding({ top: 12, bottom: 12 })
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

  build() {
    Column() {
      NavBar({
        title: '发布帖子',
        rightText: this.submitting ? '发布中' : '发布',
        onRight: () => {
          if (!this.submitting) {
            this.onPublish()
          }
        }
      })

      Column() {
        Scroll() {
          Column() {
          TextInput({ placeholder: '标题（可选，最多 50 字）', text: this.title })
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(TEXT_MAIN)
            .backgroundColor(TILE_BG)
            .borderRadius(14)
            .maxLength(50)
            .onChange((v: string) => { this.title = v })

          TextArea({ placeholder: '分享你的经验或疑问…（最多 2000 字）', text: this.content })
            .width('100%')
            .height(220)
            .fontSize(14)
            .fontColor(TEXT_MAIN)
            .backgroundColor(TILE_BG)
            .borderRadius(14)
            .maxLength(2000)
            .margin({ top: 14 })
            .onChange((v: string) => { this.content = v })

          // @某人：从私信联系人里选，选中把 @昵称 插进正文，发布时通知对方
          Row() {
            Text('@ 提醒某人')
              .fontSize(13)
              .fontColor(ACCENT)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(TILE_BG)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(16)
              .onClick(() => { this.openMentionPicker() })
              .bindSheet($$this.showMentionSheet, this.mentionSheet(), {
                title: { title: '选择要 @ 的人' },
                detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                dragBar: true,
                showClose: true
              })
          }
          .width('100%')
          .margin({ top: 10 })
          .alignItems(VerticalAlign.Center)

          // 图片区：已上传预览 + 添加按钮
          Row() {
            Text('图片')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(TEXT_MAIN)
            Text('（最多 ' + MAX_MEDIA.toString() + ' 张，' + this.mediaUrls.length.toString() + '/' + MAX_MEDIA.toString() + '）')
              .fontSize(12)
              .fontColor(TEXT_FAINT)
          }
          .width('100%')
          .margin({ top: 16, bottom: 10 })
          .alignItems(VerticalAlign.Bottom)

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.mediaUrls, (url: string, index: number) => {
              Stack({ alignContent: Alignment.TopEnd }) {
                Image(url)
                  .width(84)
                  .height(84)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(12)
                  .backgroundColor(TILE_BG)
                Text('×')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .textAlign(TextAlign.Center)
                  .width(22)
                  .height(22)
                  .borderRadius(11)
                  .backgroundColor('#99000000')
                  .margin({ top: 4, right: 4 })
                  .onClick(() => { this.removeImage(index) })
              }
              .width(84)
              .height(84)
              .margin({ right: 10, bottom: 10 })
            }, (url: string, index: number) => index.toString() + '_' + url)

            if (this.mediaUrls.length < MAX_MEDIA) {
              Column() {
                if (this.uploading) {
                  Text('上传中…')
                    .fontSize(12)
                    .fontColor(WARN)
                } else {
                  Text('+')
                    .fontSize(28)
                    .fontColor(TEXT_FAINT)
                  Text('添加图片')
                    .fontSize(11)
                    .fontColor(TEXT_FAINT)
                    .margin({ top: 2 })
                }
              }
              .width(84)
              .height(84)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderRadius(12)
              .borderWidth(1)
              .borderStyle(BorderStyle.Dashed)
              .borderColor(TEXT_FAINT)
              .backgroundColor(TILE_BG)
              .onClick(() => {
                if (!this.uploading && !this.submitting) {
                  this.pickImages()
                }
              })
            }
          }
          .width('100%')

          // 标签区：病种单选 + 话题多选（内联渲染，随 @State 即时刷新）
          Row() {
            Text('标签')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(TEXT_MAIN)
            Text('（选标签方便病友按病种/话题找到你的帖子）')
              .fontSize(12)
              .fontColor(TEXT_FAINT)
          }
          .width('100%')
          .margin({ top: 16, bottom: 10 })
          .alignItems(VerticalAlign.Bottom)

          Text('病种（单选）')
            .fontSize(12)
            .fontColor(TEXT_FAINT)
            .width('100%')
            .margin({ bottom: 8 })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(DISEASE_TAGS, (dis: string) => {
              Text(dis)
                .fontSize(13)
                .fontColor(this.selectedDept === dis ? '#FFFFFF' : TEXT_MAIN)
                .backgroundColor(this.selectedDept === dis ? ACCENT : TILE_BG)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .borderRadius(16)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => { this.toggleDept(dis) })
            }, (dis: string) => dis + '_' + (this.selectedDept === dis ? 1 : 0))
          }
          .width('100%')

          Text('话题（最多 ' + MAX_TOPIC.toString() + ' 个，已选 ' + this.selectedTopics.length.toString() + '）')
            .fontSize(12)
            .fontColor(TEXT_FAINT)
            .width('100%')
            .margin({ top: 6, bottom: 8 })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(TOPIC_TAGS, (topic: string) => {
              Text(topic)
                .fontSize(13)
                .fontColor(this.selectedTopics.indexOf(topic) >= 0 ? '#FFFFFF' : TEXT_MAIN)
                .backgroundColor(this.selectedTopics.indexOf(topic) >= 0 ? ACCENT : TILE_BG)
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .borderRadius(16)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => { this.toggleTopic(topic) })
            }, (topic: string) => topic + '_' + (this.selectedTopics.indexOf(topic) >= 0 ? 1 : 0))
          }
          .width('100%')

          Text('温馨提示：请勿发布违规、广告或不实医疗信息，违规将被拦截并累计处罚。')
            .fontSize(12)
            .fontColor(TEXT_FAINT)
            .width('100%')
            .margin({ top: 14 })
            .textAlign(TextAlign.Start)

          // 存草稿按钮：描边样式，和右上角实心"发布"区分开；提交/上传中禁用
          Button(this.uploading ? '图片上传中…' : '存草稿')
            .width('100%')
            .height(46)
            .fontSize(15)
            .fontColor(ACCENT)
            .backgroundColor(TILE_BG)
            .borderRadius(14)
            .border({ width: 1, color: ACCENT })
            .margin({ top: 16 })
            .enabled(!this.submitting && !this.uploading)
            .onClick(() => { this.onSaveDraft() })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(CARD_BG)
        .borderRadius(R_CARD)
        .shadow(SHADOW_CARD)
        .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 20, right: 20, top: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAGE)
  }
}
