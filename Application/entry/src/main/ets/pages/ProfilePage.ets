import { UserInfo } from '../model/UserModel'
import { getCurrentUser, refreshCurrentUser, logout, updateUserInfo, updateNickname, getMyDoctor, deleteAccount } from '../service/ApiService'
import { loadSkinDark, setSkinDark } from '../service/SkinStore'
import { pickOneImage, uploadImage } from '../service/ImageUploader'
import { updateAvatar } from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_2, HAIRLINE, INK, INK_SUB, INK_FAINT,
  MINT, MINT_SOFT, AMBER, DANGER, R_PILL, R_XS, R_MD,
  T_H1, T_H2, T_BODY, T_SM, T_CAP, T_MICRO, TRACK_LABEL, D_BASE
} from '../common/Theme'
import { resolveAvatar } from '../common/Avatar'
import { displayNameOf } from '../common/UserUtil'
import { BottomNav } from '../components/BottomNav'

interface InfoRow {
  label: string
  value: string
}

interface EntryRow {
  label: string
  url: string
}

interface StripCell {
  label: string
  value: string
}

interface GenderOpt {
  label: string
  value: string
}

@Entry
@Component
struct ProfilePage {
  @State displayName: string = '未登录'
  @State displayRole: string = ''
  @State displayEmail: string = '-'
  @State displayPhone: string = '-'
  @State displayBirth: string = '-'
  @State displayGender: string = '未填写'
  @State displayLicense: string = ''
  @State refreshing: boolean = false
  @State displayCreated: string = '-'
  @State isDoctor: boolean = false
  @State isPatient: boolean = false
  @State avatarIcon: Resource = $r('app.media.ic_avatar_default')
  @State avatarUrl: string = ''
  @State avatarUploading: boolean = false
  @State myUserId: number = 0

  @State doctorName: string = ''

  @State editing: boolean = false
  @State editEmail: string = ''
  @State editPhone: string = ''
  @State editBirth: string = ''
  @State editGender: string = 'other'
  @State saving: boolean = false

  @State displayAccount: string = ''
  @State nickname: string = ''
  @State nicknameUpdatedAt: string = ''
  @State editNickname: string = ''
  @State nicknameLeft: number = 0
  private nicknameTimer: number = -1

  // 主题（浅色 / 深色）
  @State darkMode: boolean = false

  // 注销账号
  @State showDeleteAccount: boolean = false
  @State deletePwd: string = ''
  @State deleting: boolean = false

  async aboutToAppear(): Promise<void> {
    await this.loadProfile()
    this.startNicknameTimer()
    // 读回当前主题，保证开关状态与实际一致
    let ctx = this.getUIContext().getHostContext()
    if (ctx !== undefined) {
      this.darkMode = await loadSkinDark(ctx)
    }
  }

  // 更换头像：选图 → 上传云存储 → 写库 → 刷新展示
  async changeAvatar(): Promise<void> {
    if (this.avatarUploading) {
      return
    }
    try {
      let uri: string = await pickOneImage()
      if (uri === '') {
        return
      }
      let ctx = this.getUIContext().getHostContext()
      if (ctx === undefined) {
        return
      }
      this.avatarUploading = true
      let url: string = await uploadImage(ctx, uri, 'avatar', 'u' + this.myUserId.toString())
      let updated = await updateAvatar(url)
      this.avatarUrl = (updated !== null && updated.avatarUrl !== '') ? updated.avatarUrl : url
      this.getUIContext().getPromptAction().showToast({ message: '头像已更新' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '更换头像失败：' + (e as Error).message })
    } finally {
      this.avatarUploading = false
    }
  }

  // 切换主题：写偏好 + 立即应用（ArkUI 会用 dark 资源色重绘整个界面）
  async toggleSkin(v: boolean): Promise<void> {
    this.darkMode = v
    try {
      let ctx = this.getUIContext().getHostContext()
      if (ctx !== undefined) {
        await setSkinDark(ctx, v)
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '切换主题失败：' + (e as Error).message })
    }
  }

  aboutToDisappear(): void {
    this.stopNicknameTimer()
  }

  onPageShow(): void {
    this.loadProfile()
  }

  computeNicknameLeft(): number {
    if (this.nicknameUpdatedAt === '') {
      return 0
    }
    let last = new Date(this.nicknameUpdatedAt).getTime()
    if (isNaN(last)) {
      return 0
    }
    let remain = 5 * 60 * 1000 - (Date.now() - last)
    if (remain <= 0) {
      return 0
    }
    return Math.ceil(remain / 1000)
  }

  startNicknameTimer(): void {
    this.stopNicknameTimer()
    this.nicknameLeft = this.computeNicknameLeft()
    this.nicknameTimer = setInterval(() => {
      this.nicknameLeft = this.computeNicknameLeft()
    }, 1000)
  }

  stopNicknameTimer(): void {
    if (this.nicknameTimer !== -1) {
      clearInterval(this.nicknameTimer)
      this.nicknameTimer = -1
    }
  }

  async loadProfile(): Promise<void> {
    let cached: UserInfo | null = await getCurrentUser()
    if (cached !== null) {
      await this.applyUser(cached)
    }
    let fresh: UserInfo | null = await refreshCurrentUser()
    if (fresh !== null) {
      await this.applyUser(fresh)
    }
  }

  async applyUser(user: UserInfo): Promise<void> {
    this.displayAccount = user.username
    this.displayName = displayNameOf(user.nickname, user.username)
    this.displayRole = this.getRoleLabel(user.role)
    this.displayEmail = user.email === '' ? '-' : user.email
    this.displayPhone = user.phone === '' ? '-' : user.phone
    this.displayBirth = user.dateOfBirth === '' ? '-' : user.dateOfBirth
    this.displayGender = this.getGenderLabel(user.gender)
    this.displayLicense = user.doctorLicense
    this.displayCreated = user.createdAt.substring(0, 10)
    this.isDoctor = user.role === 'doctor'
    this.isPatient = user.role === 'patient'
    this.avatarIcon = resolveAvatar(user.gender, user.role)
    this.avatarUrl = user.avatarUrl === undefined ? '' : user.avatarUrl
    this.myUserId = user.userId

    this.nickname = user.nickname
    this.nicknameUpdatedAt = user.nicknameUpdatedAt
    this.editNickname = user.nickname
    this.nicknameLeft = this.computeNicknameLeft()

    this.editEmail = user.email
    this.editPhone = user.phone
    this.editBirth = user.dateOfBirth
    this.editGender = user.gender === '' ? 'other' : user.gender

    if (this.isPatient) {
      let doc: UserInfo | null = await getMyDoctor()
      this.doctorName = doc ? displayNameOf(doc.nickname, doc.username) : ''
    }
  }

  async saveEdit(): Promise<void> {
    this.saving = true
    try {
      let newNick: string = this.editNickname.trim()
      let nickChanged: boolean = newNick !== this.nickname
      if (nickChanged) {
        if (newNick === '') {
          this.getUIContext().getPromptAction().showToast({ message: '昵称不能为空' })
          return
        }
        if (newNick.length > 20) {
          this.getUIContext().getPromptAction().showToast({ message: '昵称不能超过 20 个字符' })
          return
        }
        if (this.nicknameLeft > 0) {
          this.getUIContext().getPromptAction().showToast({ message: '昵称修改过于频繁，请 ' + this.nicknameLeft + ' 秒后再试' })
          return
        }
      }
      let err = await updateUserInfo(this.editEmail, this.editPhone, this.editGender, this.editBirth)
      if (err !== '') {
        this.getUIContext().getPromptAction().showToast({ message: '资料保存失败：' + err })
        return
      }
      if (nickChanged) {
        let nickErr = await updateNickname(newNick)
        if (nickErr !== '') {
          if (nickErr.indexOf('NEED_COOLDOWN') >= 0) {
            this.nicknameLeft = this.computeNicknameLeft()
            this.getUIContext().getPromptAction().showToast({ message: '昵称修改过于频繁，请稍后再试' })
          } else {
            this.getUIContext().getPromptAction().showToast({ message: '昵称保存失败：' + nickErr })
          }
          return
        }
      }
      if (nickChanged) {
        this.nickname = newNick
        this.editNickname = newNick
        this.nicknameUpdatedAt = new Date().toISOString()
        this.nicknameLeft = this.computeNicknameLeft()
        this.displayName = displayNameOf(this.nickname, this.displayAccount)
      }
      this.displayEmail = this.editEmail === '' ? '-' : this.editEmail
      this.displayPhone = this.editPhone === '' ? '-' : this.editPhone
      this.displayBirth = this.editBirth === '' ? '-' : this.editBirth
      this.displayGender = this.getGenderLabel(this.editGender)
      this.editing = false
      this.getUIContext().getPromptAction().showToast({ message: '保存成功' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + (e as Error).message })
    } finally {
      this.saving = false
    }
  }

  handleRightTap(): void {
    if (this.editing) {
      this.saveEdit()
    } else {
      this.editing = true
    }
  }

  async handleLogout(): Promise<void> {
    try {
      let result = await this.getUIContext().getPromptAction().showDialog({
        title: '退出登录',
        message: '确定要退出当前账号吗？',
        buttons: [
          { text: '取消', color: INK_SUB },
          { text: '退出', color: DANGER }
        ]
      })
      if (result.index === 1) {
        await logout()
        try {
          this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' })
        } catch (e) {
          console.error('跳转失败: ' + (e as Error).message)
        }
      }
    } catch (e) {
      console.error('操作失败: ' + (e as Error).message)
    }
  }

  // 注销账号：密码二次确认 → 服务端彻底删除 → 清本地会话 → 回登录页
  async confirmDeleteAccount(): Promise<void> {
    if (this.deleting) {
      return
    }
    if (this.deletePwd === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入登录密码' })
      return
    }
    this.deleting = true
    try {
      await deleteAccount(this.deletePwd)
      this.showDeleteAccount = false
      this.deletePwd = ''
      await logout()
      this.getUIContext().getPromptAction().showToast({ message: '账号已注销' })
      this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: (e as Error).message })
    } finally {
      this.deleting = false
    }
  }

  getRoleLabel(role: string): string {
    if (role === 'patient') { return '患者' }
    if (role === 'doctor') { return '医生' }
    if (role === 'admin') { return '管理员' }
    return ''
  }

  getGenderLabel(g: string): string {
    if (g === 'male') { return '男' }
    if (g === 'female') { return '女' }
    if (g === 'other') { return '其他' }
    return '未填写'
  }

  go(url: string): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: url })
    } catch (e) {
      console.error('跳转失败: ' + (e as Error).message)
    }
  }

  entries(): EntryRow[] {
    let out: EntryRow[] = []
    out.push({ label: '我的发布', url: 'pages/MyPostsPage' })
    out.push({ label: '草稿箱', url: 'pages/DraftsPage' })
    out.push({ label: '我的收藏', url: 'pages/FavoritePage' })
    if (this.isPatient) {
      out.push({ label: '主管医生', url: 'pages/BindDoctorPage' })
    }
    out.push({ label: '隐私与免责', url: 'pages/AboutPage' })
    return out
  }

  @Builder
  headerBar() {
    Row() {
      Text('我的')
        .fontSize(T_H1)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
        .letterSpacing(0.4)
      Blank()
      Text(this.editing ? (this.saving ? '保存中' : '保存') : '编辑')
        .fontSize(T_SM)
        .fontColor(this.editing ? MINT : INK_SUB)
        .letterSpacing(0.6)
        .padding({ left: 4, top: 8, bottom: 8 })
        .onClick(() => {
          if (!this.saving) {
            this.handleRightTap()
          }
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  hero() {
    Row() {
      // 头像：有自定义图就显示图，否则回退角色/性别图标；点一下可更换
      Stack({ alignContent: Alignment.BottomEnd }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.avatarUrl !== '') {
            Image(this.avatarUrl)
              .width(64)
              .height(64)
              .objectFit(ImageFit.Cover)
          } else {
            Image(this.avatarIcon)
              .width(26)
              .height(26)
              .fillColor(MINT)
          }
        }
        .width(64)
        .height(64)
        .borderRadius(32)
        .backgroundColor(MINT_SOFT)
        .border({ width: 1, color: 'rgba(15, 122, 92, 0.25)' })
        .clip(true)

        // 右下角"换头像"小徽标
        Row() {
          if (this.avatarUploading) {
            LoadingProgress()
              .width(12)
              .height(12)
              .color('#04231A')
          } else {
            Text('+')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#04231A')
          }
        }
        .width(20)
        .height(20)
        .justifyContent(FlexAlign.Center)
        .borderRadius(10)
        .backgroundColor(MINT)
        .border({ width: 1.5, color: CANVAS })
        .margin({ right: -2, bottom: -2 })
      }
      .width(64)
      .height(64)
      .onClick(() => {
        this.changeAvatar()
      })

      Column() {
        Text(this.displayName)
          .fontSize(T_H1)
          .fontWeight(FontWeight.Medium)
          .fontColor(INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(this.displayRole)
            .fontSize(T_MICRO)
            .fontColor(MINT)
            .letterSpacing(0.6)
          Text('@' + this.displayAccount)
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .letterSpacing(0.4)
            .margin({ left: 10 })
        }
        .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 16 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 20 })
    .alignItems(VerticalAlign.Center)
  }

  // 注意：@Builder 的值类型参数不会随状态刷新（ArkUI 限制），
  // 所以凡是内容会异步变化的，一律传对象引用，否则会永远停在首帧的空值上。
  @Builder
  stripCell(opt: StripCell) {
    Column() {
      Text(opt.label)
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .letterSpacing(TRACK_LABEL)
      Text(opt.value)
        .fontSize(T_SM)
        .fontColor(INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  // 这一条三栏信息直接内联渲染（不走 @Builder）：
  // 这三项都是异步加载后才有的值，走 builder 会停在首帧的空值上。
  @Builder
  infoStrip() {
    Column() {
      Divider().color(HAIRLINE).strokeWidth(1)
      Row() {
        Column() {
          Text('注 册 于')
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .letterSpacing(TRACK_LABEL)
          Text(this.displayCreated)
            .fontSize(T_SM)
            .fontColor(INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Divider().vertical(true).height(26).color(HAIRLINE).strokeWidth(1).margin({ left: 8, right: 16 })

        Column() {
          Text('身 份')
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .letterSpacing(TRACK_LABEL)
          Text(this.displayRole === '' ? '—' : this.displayRole)
            .fontSize(T_SM)
            .fontColor(INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 6 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Divider().vertical(true).height(26).color(HAIRLINE).strokeWidth(1).margin({ left: 8, right: 16 })

        Column() {
          if (this.isDoctor) {
            Text('执 业 证')
              .fontSize(T_MICRO)
              .fontColor(INK_FAINT)
              .letterSpacing(TRACK_LABEL)
            Text(this.displayLicense === '' ? '暂无' : this.displayLicense)
              .fontSize(T_SM)
              .fontColor(INK)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
          } else {
            Text('主 管 医 生')
              .fontSize(T_MICRO)
              .fontColor(INK_FAINT)
              .letterSpacing(TRACK_LABEL)
            Text(this.doctorName === '' ? '未绑定' : this.doctorName)
              .fontSize(T_SM)
              .fontColor(INK)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 6 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Center)
      Divider().color(HAIRLINE).strokeWidth(1)
    }
    .width('100%')
  }

  @Builder
  infoRow(opt: InfoRow) {
    Row() {
      Text(opt.label)
        .fontSize(T_SM)
        .fontColor(INK_FAINT)
      Blank()
      Text(opt.value)
        .fontSize(T_SM)
        .fontColor(INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 14 })
  }

  @Builder
  editRow(label: string, value: string, placeholder: string, inputType: InputType, onChange: (v: string) => void) {
    Row() {
      Text(label)
        .fontSize(T_CAP)
        .fontColor(INK_FAINT)
        .width(52)
        .letterSpacing(0.6)
      TextInput({ text: value, placeholder: placeholder })
        .layoutWeight(1)
        .height(38)
        .fontSize(T_SM)
        .fontColor(INK)
        .placeholderColor('#8B9893')
        .type(inputType)
        .textAlign(TextAlign.End)
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .onChange(onChange)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  genderChip(opt: GenderOpt) {
    Text(opt.label)
      .fontSize(T_CAP)
      .fontColor(this.editGender === opt.value ? '#FFFFFF' : INK_SUB)
      .backgroundColor(this.editGender === opt.value ? MINT : Color.Transparent)
      .border({ width: 1, color: this.editGender === opt.value ? MINT : HAIRLINE })
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(R_PILL)
      .margin({ left: 8 })
      .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
      .onClick(() => { this.editGender = opt.value })
  }

  @Builder
  detailSection() {
    Column() {
      if (this.editing) {
        this.editRow('昵称', this.editNickname, '最多 20 字', InputType.Normal, (v: string) => { this.editNickname = v })
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
        this.editRow('邮箱', this.editEmail, '请输入邮箱', InputType.Normal, (v: string) => { this.editEmail = v })
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
        this.editRow('手机', this.editPhone, '请输入手机号', InputType.Number, (v: string) => { this.editPhone = v })
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
        this.editRow('生日', this.editBirth, 'YYYY-MM-DD', InputType.Normal, (v: string) => { this.editBirth = v })
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
        Row() {
          Text('性别')
            .fontSize(T_CAP)
            .fontColor(INK_FAINT)
            .width(52)
            .letterSpacing(0.6)
          Blank()
          this.genderChip({ label: '男', value: 'male' })
          this.genderChip({ label: '女', value: 'female' })
          this.genderChip({ label: '其他', value: 'other' })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 10, bottom: 10 })
        .alignItems(VerticalAlign.Center)

        if (this.nicknameLeft > 0) {
          Text('昵称 5 分钟内仅可修改一次，剩余 ' + this.nicknameLeft + ' 秒')
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .width('100%')
            .textAlign(TextAlign.End)
            .padding({ right: 24, bottom: 12 })
        }
      } else {
        this.infoRow({ label: '昵称', value: this.nickname === '' ? '未设置' : this.nickname })
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
        this.infoRow({ label: '邮箱', value: this.displayEmail })
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
        this.infoRow({ label: '手机', value: this.displayPhone })
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
        this.infoRow({ label: '生日', value: this.displayBirth })
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
        this.infoRow({ label: '性别', value: this.displayGender })
      }
    }
    .width('100%')
  }

  @Builder
  entryRow(opt: EntryRow, isLast: boolean) {
    Column() {
      Row() {
        Text(opt.label)
          .fontSize(T_BODY)
          .fontColor(INK)
        Blank()
        Image($r('app.media.ic_arrow_right'))
          .width(13)
          .height(13)
          .fillColor(INK_FAINT)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => { this.go(opt.url) })

      if (!isLast) {
        Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      this.headerBar()

      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            this.hero()
            this.infoStrip()

            this.detailSection()

            if (!this.editing) {
              Column() {
                Text('功 能')
                  .fontSize(T_MICRO)
                  .fontColor(INK_FAINT)
                  .letterSpacing(2)
                  .width('100%')
                  .padding({ left: 24, top: 28, bottom: 6 })

                // 深色模式开关（立即生效，并记住选择）
                Row() {
                  Text('深色模式')
                    .fontSize(T_BODY)
                    .fontColor(INK)
                  Blank()
                  Toggle({ type: ToggleType.Switch, isOn: this.darkMode })
                    .selectedColor(MINT)
                    .onChange((v: boolean) => {
                      this.toggleSkin(v)
                    })
                }
                .width('100%')
                .padding({ left: 24, right: 24, top: 8, bottom: 8 })
                .alignItems(VerticalAlign.Center)

                Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })

                ForEach(this.entries(), (e: EntryRow, idx: number) => {
                  this.entryRow(e, idx === this.entries().length - 1)
                }, (e: EntryRow) => e.label)
              }
              .width('100%')

              Text('退出登录')
                .fontSize(T_SM)
                .fontColor(DANGER)
                .letterSpacing(0.6)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 30, bottom: 12 })
                .onClick(() => { this.handleLogout() })

              // 注销账号：入口做得比"退出登录"更轻，避免误触
              Text('注销账号')
                .fontSize(T_MICRO)
                .fontColor(INK_FAINT)
                .letterSpacing(0.4)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 4, bottom: 30 })
                .onClick(() => {
                  this.deletePwd = ''
                  this.showDeleteAccount = true
                })
            } else {
              Column().height(28)
            }
          }
          .width('100%')
          .padding({ bottom: 8 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .onRefreshing(async () => {
        await this.loadProfile()
        this.refreshing = false
      })

      BottomNav({ current: 'mine', isPatient: this.isPatient })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
    .bindSheet($$this.showDeleteAccount, this.deleteAccountSheet(), {
      height: 360,
      dragBar: true,
      showClose: true,
      backgroundColor: SURFACE,
      onDisappear: () => {
        this.showDeleteAccount = false
      }
    })
  }

  // 注销确认弹层：把"会删除什么"写清楚，再要求输入密码
  @Builder
  deleteAccountSheet() {
    Column() {
      Text('注销账号')
        .fontSize(T_H2)
        .fontWeight(FontWeight.Medium)
        .fontColor(DANGER)
        .width('100%')
      Text('这是一个不可恢复的操作，注销后以下数据将被永久删除：')
        .fontSize(T_CAP)
        .fontColor(INK_SUB)
        .lineHeight(20)
        .width('100%')
        .margin({ top: 10 })

      Column() {
        this.deleteWarningRow('全部健康记录与趋势数据')
        this.deleteWarningRow('预警记录与未读提醒')
        this.deleteWarningRow('你发布的帖子、评论、点赞与收藏')
        this.deleteWarningRow('你与医生/病友的全部私信')
      }
      .width('100%')
      .margin({ top: 8 })

      if (this.isDoctor) {
        Text('注销后，绑定在你名下的患者会被自动解绑。')
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .width('100%')
          .margin({ top: 8 })
      }

      TextInput({ placeholder: '输入登录密码以确认', text: this.deletePwd })
        .height(48)
        .fontSize(T_SM)
        .fontColor(INK)
        .placeholderColor(INK_FAINT)
        .type(InputType.Password)
        .backgroundColor(SURFACE_2)
        .borderRadius(R_MD)
        .border({ width: 1, color: HAIRLINE })
        .padding({ left: 14, right: 14 })
        .margin({ top: 18 })
        .onChange((v: string) => {
          this.deletePwd = v
        })

      Blank()

      Text(this.deleting ? '注销中…' : '确认注销')
        .fontSize(T_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(48)
        .borderRadius(R_MD)
        .backgroundColor(DANGER)
        .opacity(this.deleting ? 0.5 : 1)
        .onClick(() => {
          this.confirmDeleteAccount()
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 12, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  deleteWarningRow(text: string) {
    Row() {
      Circle()
        .width(4)
        .height(4)
        .fill(DANGER)
      Text(text)
        .fontSize(T_CAP)
        .fontColor(INK_SUB)
        .margin({ left: 8 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }
}
