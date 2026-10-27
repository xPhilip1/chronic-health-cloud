import { HealthData, HealthWarning } from '../model/HealthModel'
import { UserInfo } from '../model/UserModel'
import {
  getUserById, getUserHealthData, getUserWarnings, getCurrentUser,
  acknowledgeWarning, sendFollowUp
} from '../service/ApiService'
import { resolveAvatar } from '../common/Avatar'
import { displayNameOf } from '../common/UserUtil'
import {
  BG_PAGE, TILE_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, ACCENT, DANGER, OK, DANGER_SOFT,
  BRAND_A, BRAND_B, R_CARD, SHADOW_CARD, JADE, JADE_SOFT, HAIRLINE, SURFACE,
  C_BP, C_SUGAR, C_HR, C_WEIGHT, C_EXERCISE,
  T_SM, T_CAP, T_MICRO
} from '../common/Theme'
import { NavBar } from '../components/NavBar'

@Entry
@Component
struct PatientDetailPage {
  @State patient: UserInfo | null = null
  @State dataList: HealthData[] = []
  @State warnings: HealthWarning[] = []
  @State isLoading: boolean = true
  @State refreshing: boolean = false
  // 随访建议弹层
  @State showFollowUp: boolean = false
  @State followUpText: string = ''
  @State sendingFollowUp: boolean = false
  private targetUserId: number = 0
  private myUserId: number = 0
  private myRole: string = 'patient'

  async aboutToAppear(): Promise<void> {
    // 从路由参数里取出患者 ID
    let params = this.getUIContext().getRouter().getParams() as Record<string, number>
    if (params !== null && params !== undefined) {
      this.targetUserId = params['userId']
    }
    let cur: UserInfo | null = await getCurrentUser()
    if (cur !== null) {
      this.myUserId = cur.userId
      this.myRole = cur.role
    }
    await this.loadData()
  }

  // 是否可对该患者发起私信：查看者非管理员、且不是自己
  canDm(): boolean {
    if (this.patient === null) {
      return false
    }
    if (this.myRole === 'admin') {
      return false
    }
    return this.patient.userId !== this.myUserId
  }

  // 医生对本人的患者才有干预权限（服务端还会再校验一次绑定关系与审核状态）
  canManage(): boolean {
    if (this.patient === null) {
      return false
    }
    if (this.myRole !== 'doctor') {
      return false
    }
    return this.patient.doctorId === this.myUserId
  }

  async ackWarning(id: number): Promise<void> {
    try {
      await acknowledgeWarning(id)
      this.getUIContext().getPromptAction().showToast({ message: '已标记为处理' })
      await this.loadData()
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: (e as Error).message })
    }
  }

  async submitFollowUp(): Promise<void> {
    let text: string = this.followUpText.trim()
    if (text === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入建议内容' })
      return
    }
    this.sendingFollowUp = true
    try {
      await sendFollowUp(this.targetUserId, text)
      this.showFollowUp = false
      this.followUpText = ''
      this.getUIContext().getPromptAction().showToast({ message: '建议已发送给患者' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '发送失败：' + (e as Error).message })
    } finally {
      this.sendingFollowUp = false
    }
  }

  openDm(): void {
    if (this.patient === null) {
      return
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatPage',
        params: {
          peerId: this.patient!.userId,
          peerName: displayNameOf(this.patient!.nickname, this.patient!.username),
          peerAvatar: this.patient!.avatarUrl
        }
      })
    } catch (e) {
      console.error('打开私信失败: ' + (e as Error).message)
    }
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    await this.fetchDetail()
    this.isLoading = false
  }

  // 下拉刷新：重新拉取但不切 isLoading，避免刷新组件被整页 loading 卸载
  async refreshData(): Promise<void> {
    await this.fetchDetail()
  }

  async fetchDetail(): Promise<void> {
    this.patient = await getUserById(this.targetUserId)
    this.dataList = await getUserHealthData(this.targetUserId)
    let allWarn = await getUserWarnings(this.targetUserId)
    // 只展示未确认的预警，突出需要关注的
    let unack: HealthWarning[] = []
    for (let i = 0; i < allWarn.length; i++) {
      if (!allWarn[i].acknowledged) {
        unack.push(allWarn[i])
      }
    }
    this.warnings = unack
  }

  getGenderLabel(g: string): string {
    if (g === 'male') {
      return '男'
    }
    if (g === 'female') {
      return '女'
    }
    return '其他'
  }

  // 把 ISO 时间截成 "MM-DD HH:mm"
  formatTime(iso: string): string {
    if (iso === '' || iso.length < 16) {
      return iso
    }
    return iso.substring(5, 10) + ' ' + iso.substring(11, 16)
  }

  build() {
    Column() {
      NavBar({ title: '患者详情' })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(ACCENT)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            // 患者基本信息卡片（渐变横幅）
            Column() {
              Row() {
                Column() {
                  if (this.patient !== null && this.patient!.avatarUrl !== '') {
                    Image(this.patient!.avatarUrl).width(56).height(56).objectFit(ImageFit.Cover).borderRadius(28)
                  } else {
                    Image(this.patient ? resolveAvatar(this.patient!.gender, 'patient') : $r('app.media.ic_avatar_default'))
                      .width(30)
                      .height(30)
                      .fillColor('#FFFFFF')
                  }
                }
                .justifyContent(FlexAlign.Center)
                .width(56)
                .height(56)
                .borderRadius(18)
                .backgroundColor('rgba(255,255,255,0.22)')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Column() {
                  Text(this.patient ? displayNameOf(this.patient!.nickname, this.patient!.username) : '')
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                  Text(this.buildPatientMeta())
                    .fontSize(12)
                    .fontColor('rgba(255,255,255,0.9)')
                    .margin({ top: 6 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .margin({ left: 14 })

                if (this.canDm()) {
                  Text('私信')
                    .fontSize(13)
                    .fontColor(ACCENT)
                    .backgroundColor('#FFFFFF')
                    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                    .borderRadius(14)
                    .margin({ left: 10 })
                    .onClick(() => { this.openDm() })
                }
              }
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .borderRadius(R_CARD)
            .linearGradient({ angle: 135, colors: [[BRAND_A, 0], [BRAND_B, 1]] })
            .shadow(SHADOW_CARD)
            .margin({ top: 16, bottom: 16 })

            // 未确认预警
            Column() {
              Text('未处理预警（' + this.warnings.length + '）')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(TEXT_MAIN)
                .width('100%')
                .margin({ bottom: 12 })
              if (this.warnings.length === 0) {
                Row() {
                  Image($r('app.media.ic_check'))
                    .width(14)
                    .height(14)
                    .fillColor(OK)
                    .margin({ right: 6 })
                  Text('暂无未处理预警')
                    .fontSize(13)
                    .fontColor(OK)
                }
                .alignItems(VerticalAlign.Center)
                .width('100%')
              } else {
                ForEach(this.warnings, (item: HealthWarning) => {
                  Row() {
                    Image($r('app.media.ic_warning'))
                      .width(16)
                      .height(16)
                      .fillColor(DANGER)
                      .margin({ right: 8 })
                    Column() {
                      Text(item.warningMessage)
                        .fontSize(13)
                        .fontColor(TEXT_MAIN)
                      Text(this.formatTime(item.warningTime))
                        .fontSize(11)
                        .fontColor(TEXT_SUB)
                        .margin({ top: 4 })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    // 医生：就地处理患者预警，形成"预警→干预"闭环
                    if (this.canManage()) {
                      Text('处理')
                        .fontSize(12)
                        .fontColor(JADE)
                        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                        .backgroundColor(JADE_SOFT)
                        .borderRadius(12)
                        .onClick(() => {
                          this.ackWarning(item.warningId)
                        })
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(DANGER_SOFT)
                  .borderRadius(14)
                  .margin({ bottom: 8 })
                  .alignItems(VerticalAlign.Center)
                }, (item: HealthWarning) => item.warningId.toString())
              }

              // 医生：发送随访建议（以站内信送达患者）
              if (this.canManage()) {
                Text('发送随访建议')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .height(42)
                  .borderRadius(14)
                  .backgroundColor(JADE)
                  .margin({ top: 8 })
                  .onClick(() => {
                    this.followUpText = ''
                    this.showFollowUp = true
                  })
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(R_CARD)
            .shadow(SHADOW_CARD)
            .margin({ bottom: 16 })

            // 健康记录
            Column() {
              Text('健康记录（' + this.dataList.length + '）')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(TEXT_MAIN)
                .width('100%')
                .margin({ bottom: 12 })
              if (this.dataList.length === 0) {
                Text('该患者还没有记录健康数据')
                  .fontSize(13)
                  .fontColor(TEXT_SUB)
                  .width('100%')
              } else {
                ForEach(this.dataList, (item: HealthData) => {
                  Column() {
                    Row() {
                      Text(this.buildBpText(item))
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.bpBad(item) ? DANGER : C_BP)
                      Blank()
                      if (this.isAbnormal(item)) {
                        Text('异常')
                          .fontSize(11)
                          .fontWeight(FontWeight.Medium)
                          .fontColor('#FFFFFF')
                          .backgroundColor(DANGER)
                          .borderRadius(9)
                          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                          .margin({ right: 8 })
                      }
                      Text(this.formatTime(item.recordTime))
                        .fontSize(11)
                        .fontColor(TEXT_SUB)
                    }
                    .width('100%')

                    Row() {
                      Text('血糖 ' + item.bloodSugar + ' mmol/L')
                        .fontSize(12)
                        .fontColor(this.sugarBad(item) ? DANGER : C_SUGAR)
                      Text('心率 ' + item.heartRate + ' bpm')
                        .fontSize(12)
                        .fontColor(this.hrBad(item) ? DANGER : C_HR)
                        .margin({ left: 16 })
                      if (item.weight > 0) {
                        Text('体重 ' + item.weight + ' kg')
                          .fontSize(12)
                          .fontColor(C_WEIGHT)
                          .margin({ left: 16 })
                      }
                    }
                    .width('100%')
                    .margin({ top: 6 })

                    if (item.exerciseType !== '' || item.exerciseDuration > 0 || item.exerciseCalories > 0) {
                      Row() {
                        Image($r('app.media.ic_exercise'))
                          .width(13)
                          .height(13)
                          .fillColor(C_EXERCISE)
                          .margin({ right: 5 })
                        Text(this.exerciseSummary(item))
                          .fontSize(12)
                          .fontColor(C_EXERCISE)
                      }
                      .width('100%')
                      .margin({ top: 6 })
                    }

                    if (item.notes !== '') {
                      Text('备注：' + item.notes)
                        .fontSize(12)
                        .fontColor('#5A6072')
                        .width('100%')
                        .margin({ top: 6 })
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(TILE_BG)
                  .borderRadius(14)
                  .margin({ bottom: 8 })
                }, (item: HealthData) => item.dataId.toString())
              }
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFFFFF')
            .borderRadius(R_CARD)
            .shadow(SHADOW_CARD)
            .margin({ bottom: 24 })
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
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAGE)
    .bindSheet($$this.showFollowUp, this.followUpSheet(), {
      height: 320,
      dragBar: true,
      showClose: true,
      backgroundColor: SURFACE,
      onDisappear: () => {
        this.showFollowUp = false
      }
    })
  }

  // 随访建议弹层：医生写一段建议，以站内信形式发给患者
  @Builder
  followUpSheet() {
    Column() {
      Text('发送随访建议')
        .fontSize(T_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .width('100%')
      Text('建议会以站内信发送给 ' + (this.patient ? displayNameOf(this.patient.nickname, this.patient.username) : '患者'))
        .fontSize(T_MICRO)
        .fontColor(TEXT_FAINT)
        .width('100%')
        .margin({ top: 6 })

      TextArea({ placeholder: '例如：近一周血压偏高，建议早晚各测一次并记录；减少腌制品摄入，两周后复诊。', text: this.followUpText })
        .height(110)
        .fontSize(T_SM)
        .fontColor(TEXT_MAIN)
        .placeholderColor(TEXT_FAINT)
        .backgroundColor(TILE_BG)
        .borderRadius(12)
        .margin({ top: 14 })
        .onChange((v: string) => {
          this.followUpText = v
        })

      Blank()

      Text(this.sendingFollowUp ? '发送中…' : '发送给患者')
        .fontSize(T_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(46)
        .borderRadius(14)
        .backgroundColor(JADE)
        .opacity(this.sendingFollowUp ? 0.5 : 1)
        .onClick(() => {
          if (!this.sendingFollowUp) {
            this.submitFollowUp()
          }
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  buildPatientMeta(): string {
    if (this.patient === null) {
      return ''
    }
    let p: UserInfo = this.patient
    let meta: string = '性别：' + this.getGenderLabel(p.gender)
    if (p.dateOfBirth !== '') {
      meta += '　生日：' + p.dateOfBirth
    }
    if (p.phone !== '') {
      meta += '　电话：' + p.phone
    }
    return meta
  }

  buildBpText(item: HealthData): string {
    return '血压 ' + item.bloodPressureSystolic + '/' + item.bloodPressureDiastolic + ' mmHg'
  }

  // 各指标是否超标（与健康环同一套正常范围，仅对有数据的项判断）
  bpBad(item: HealthData): boolean {
    let sys: boolean = item.bloodPressureSystolic > 0 &&
      (item.bloodPressureSystolic < 90 || item.bloodPressureSystolic > 139)
    let dia: boolean = item.bloodPressureDiastolic > 0 &&
      (item.bloodPressureDiastolic < 60 || item.bloodPressureDiastolic > 89)
    return sys || dia
  }

  sugarBad(item: HealthData): boolean {
    return item.bloodSugar > 0 && (item.bloodSugar < 3.9 || item.bloodSugar > 7.8)
  }

  hrBad(item: HealthData): boolean {
    return item.heartRate > 0 && (item.heartRate < 60 || item.heartRate > 100)
  }

  isAbnormal(item: HealthData): boolean {
    return this.bpBad(item) || this.sugarBad(item) || this.hrBad(item)
  }

  // 运动摘要：把已填写的类型/时长/消耗拼成一句，缺的跳过
  exerciseSummary(item: HealthData): string {
    let seg: string[] = []
    if (item.exerciseType !== '') {
      seg.push(item.exerciseType)
    }
    if (item.exerciseDuration > 0) {
      seg.push(item.exerciseDuration + '分钟')
    }
    if (item.exerciseCalories > 0) {
      seg.push('消耗' + item.exerciseCalories + 'kcal')
    }
    return seg.join(' · ')
  }
}
