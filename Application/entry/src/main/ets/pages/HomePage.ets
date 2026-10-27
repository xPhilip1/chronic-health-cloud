import { HealthData } from '../model/HealthModel'
import { UserInfo, PatientOverview } from '../model/UserModel'
import {
  getCurrentUser, getHealthDataList, getUnacknowledgedCount,
  getMyDoctor, getPatientsOverview, getDoctorList, seedDemoData
} from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_2, HAIRLINE, INK, INK_SUB, INK_FAINT,
  MINT, MINT_SOFT, AMBER, DANGER, DANGER_SOFT, OK,
  M_BP, M_SUGAR, M_HR, M_WEIGHT, M_EXERCISE,
  T_HERO, T_H1, T_H2, T_H3, T_BODY, T_SM, T_CAP, T_MICRO, TRACK_LABEL,
  R_LG, R_MD, R_PILL, R_XS, D_BASE, SHADOW_FLOAT
} from '../common/Theme'
import { HealthRing } from '../components/HealthRing'
import { resolveAvatar } from '../common/Avatar'
import { displayNameOf } from '../common/UserUtil'
import { BottomNav } from '../components/BottomNav'
import { StateView } from '../components/StateView'

interface PatientRow {
  userId: number
  name: string
  gender: string
  latestBp: string
  warnCount: number
  avatarUrl: string
}

interface DoctorRow {
  userId: number
  name: string
  gender: string
  phone: string
  license: string
  patientCount: number
  doctorStatus: string
  avatarUrl: string
}

interface QuickAction {
  title: string
  icon: Resource
  url: string
  // 每个入口一枚同色系圆盘 + 本色图标，靠颜色区分，比统一黑色更易辨认
  color: Resource
  bg: string
  ring: string
}

// @Builder 的值类型参数不会随状态刷新，凡是内容会变的都走对象参数
interface MiniStat {
  label: string
  value: string
  color: Resource
}

interface TabOpt {
  label: string
  key: string
}

@Entry
@Component
struct HomePage {
  @State user: UserInfo | null = null
  @State role: string = 'patient'

  @State latestData: HealthData | null = null
  @State warningCount: number = 0
  @State myDoctor: UserInfo | null = null
  @State showDoctorCard: boolean = false

  @State patients: PatientRow[] = []
  @State doctors: DoctorRow[] = []
  @State adminTab: string = 'patient'
  @State isLoading: boolean = true
  @State refreshing: boolean = false
  @State seeding: boolean = false

  private quickActions: QuickAction[] = [
    {
      title: '健康记录', icon: $r('app.media.ic_data_records'), url: 'pages/HealthDataPage',
      color: M_BP, bg: 'rgba(15, 122, 92, 0.13)', ring: 'rgba(15, 122, 92, 0.22)'
    },
    {
      title: '趋势分析', icon: $r('app.media.ic_trend_chart'), url: 'pages/TrendsPage',
      color: M_SUGAR, bg: 'rgba(29, 122, 147, 0.13)', ring: 'rgba(29, 122, 147, 0.22)'
    },
    {
      title: '预警中心', icon: $r('app.media.ic_warning'), url: 'pages/WarningsPage',
      color: M_HR, bg: 'rgba(176, 74, 58, 0.12)', ring: 'rgba(176, 74, 58, 0.20)'
    },
    {
      title: 'AI 建议', icon: $r('app.media.ic_robot'), url: 'pages/AdvicePage',
      color: M_EXERCISE, bg: 'rgba(140, 106, 46, 0.13)', ring: 'rgba(140, 106, 46, 0.22)'
    }
  ]

  onPageShow(): void {
    this.loadData()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    await this.fetchData()
    this.isLoading = false
  }

  async refreshData(): Promise<void> {
    await this.fetchData()
  }

  // 管理员：一键生成演示数据
  async handleSeed(): Promise<void> {
    if (this.seeding) {
      return
    }
    try {
      let res = await this.getUIContext().getPromptAction().showDialog({
        title: '生成演示数据',
        message: '将创建演示患者 / 医生账号、近 30 天健康记录、预警、社区内容与一段医患对话。演示账号已存在时会自动跳过。',
        buttons: [
          { text: '取消', color: INK_SUB },
          { text: '生成', color: MINT }
        ]
      })
      if (res.index !== 1) {
        return
      }
    } catch (e) {
      return
    }
    this.seeding = true
    try {
      let msg = await seedDemoData()
      this.getUIContext().getPromptAction().showToast({ message: msg })
      await this.loadData()
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '生成失败：' + (e as Error).message })
    } finally {
      this.seeding = false
    }
  }

  async fetchData(): Promise<void> {
    let cur: UserInfo | null = await getCurrentUser()
    this.user = cur
    if (cur === null) {
      return
    }
    this.role = cur.role

    if (cur.role === 'patient') {
      let dataList: HealthData[] = await getHealthDataList()
      this.latestData = dataList.length > 0 ? dataList[0] : null
      this.warningCount = await getUnacknowledgedCount()
      this.myDoctor = await getMyDoctor()
    } else {
      let overview: PatientOverview[] = await getPatientsOverview()
      let rows: PatientRow[] = []
      for (let i = 0; i < overview.length; i++) {
        let o: PatientOverview = overview[i]
        rows.push({
          userId: o.userId,
          name: o.name,
          gender: o.gender,
          latestBp: o.latestBp,
          warnCount: o.warnCount,
          avatarUrl: o.avatarUrl
        })
      }
      this.patients = rows

      if (cur.role === 'admin') {
        let docs: UserInfo[] = await getDoctorList()
        let drows: DoctorRow[] = []
        for (let k = 0; k < docs.length; k++) {
          let d: UserInfo = docs[k]
          let cnt: number = 0
          for (let m = 0; m < overview.length; m++) {
            if (overview[m].doctorId === d.userId) {
              cnt++
            }
          }
          drows.push({
            userId: d.userId,
            avatarUrl: d.avatarUrl,
            name: displayNameOf(d.nickname, d.username),
            gender: this.getGenderLabel(d.gender),
            phone: d.phone === '' ? '暂无' : d.phone,
            license: d.doctorLicense === '' ? '暂无' : d.doctorLicense,
            patientCount: cnt,
            doctorStatus: d.doctorStatus
          })
        }
        this.doctors = drows
      }
    }
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

  todayLine(): string {
    let d: Date = new Date()
    let weeks: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
    return (d.getMonth() + 1) + ' 月 ' + d.getDate() + ' 日 · ' + weeks[d.getDay()]
  }

  greeting(): string {
    let h: number = new Date().getHours()
    if (h < 6) { return '夜深了' }
    if (h < 11) { return '早上好' }
    if (h < 14) { return '中午好' }
    if (h < 18) { return '下午好' }
    return '晚上好'
  }

  // 今日状态：任一项超标即"需关注"
  todayStatus(): string {
    if (this.latestData === null) {
      return '暂无数据'
    }
    let d: HealthData = this.latestData
    let bad: boolean = (d.bloodPressureSystolic > 139) || (d.bloodSugar > 7.8) ||
      (d.heartRate > 100) || (d.bloodPressureSystolic > 0 && d.bloodPressureSystolic < 90)
    return bad ? '需关注' : '状态平稳'
  }

  statusColor(): Resource {
    let s: string = this.todayStatus()
    if (s === '需关注') { return DANGER }
    if (s === '暂无数据') { return INK_FAINT }
    return MINT
  }

  goPatientDetail(userId: number): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PatientDetailPage', params: { userId: userId } })
    } catch (e) {
      console.error('跳转失败: ' + (e as Error).message)
    }
  }

  goDoctorDetail(userId: number): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/DoctorDetailPage', params: { userId: userId } })
    } catch (e) {
      console.error('跳转失败: ' + (e as Error).message)
    }
  }

  go(url: string): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: url })
    } catch (e) {
      console.error('跳转失败: ' + (e as Error).message)
    }
  }

  doctorDm(): void {
    if (this.myDoctor === null) {
      return
    }
    this.showDoctorCard = false
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatPage',
        params: {
          peerId: this.myDoctor!.userId,
          peerName: displayNameOf(this.myDoctor!.nickname, this.myDoctor!.username),
          peerAvatar: this.myDoctor!.avatarUrl
        }
      })
    } catch (e) {
      console.error('打开私信失败: ' + (e as Error).message)
    }
  }

  regDateText(iso: string): string {
    if (iso === '' || iso.length < 10) {
      return '未知'
    }
    return iso.substring(0, 10)
  }

  // ===== 顶部 =====
  @Builder
  headerBar() {
    Row() {
      Column() {
        Text(this.todayLine())
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .letterSpacing(TRACK_LABEL)
        Text(this.greeting() + '，' + (this.user ? displayNameOf(this.user.nickname, this.user.username) : ''))
          .fontSize(T_H1)
          .fontWeight(FontWeight.Medium)
          .fontColor(INK)
          .letterSpacing(0.3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.role === 'patient') {
        Stack({ alignContent: Alignment.TopEnd }) {
          Image($r('app.media.ic_bell'))
            .width(21)
            .height(21)
            .fillColor(INK)
            .margin({ top: 10, right: 8 })
          if (this.warningCount > 0) {
            Circle()
              .width(7)
              .height(7)
              .fill(DANGER)
              .margin({ top: 8, right: 6 })
          }
        }
        .width(44)
        .height(44)
        .onClick(() => {
          this.go('pages/WarningsPage')
        })
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 10 })
    .alignItems(VerticalAlign.Top)
  }

  // ===== 仪表盘主体 =====
  @Builder
  dashboard() {
    Column() {
      Row() {
        Text('今 日 指 标')
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .letterSpacing(2)
        Blank()
        Row() {
          Circle()
            .width(5)
            .height(5)
            .fill(this.statusColor())
          Text(this.todayStatus())
            .fontSize(T_MICRO)
            .fontColor(this.statusColor())
            .letterSpacing(0.6)
            .margin({ left: 6 })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 24, right: 24 })

      if (this.latestData) {
        Column() {
          HealthRing({
            systolic: this.latestData!.bloodPressureSystolic,
            diastolic: this.latestData!.bloodPressureDiastolic,
            bloodSugar: this.latestData!.bloodSugar,
            heartRate: this.latestData!.heartRate,
            weight: this.latestData!.weight
          })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 10 })
      } else {
        Column() {
          StateView({
            kind: 'empty',
            title: '还没有健康记录',
            desc: '记录第一条数据后，这里会显示你的指标仪表盘',
            actionText: '去记录',
            icon: $r('app.media.ic_data_records'),
            onAction: () => {
              this.go('pages/AddDataPage')
            }
          })
        }
        .width('100%')
        .padding({ top: 46, bottom: 46 })
      }
    }
    .width('100%')
  }

  // ===== 快捷入口：四个图标列，无边框 =====
  @Builder
  quickRow() {
    Row() {
      ForEach(this.quickActions, (a: QuickAction) => {
        Column() {
          Row() {
            Image(a.icon)
              .width(21)
              .height(21)
              .fillColor(a.color)
          }
          .width(46)
          .height(46)
          .justifyContent(FlexAlign.Center)
          .borderRadius(23)
          .backgroundColor(a.bg)
          .border({ width: 1, color: a.ring })
          Text(a.title)
            .fontSize(T_CAP)
            .fontColor(INK)
            .letterSpacing(0.3)
            .margin({ top: 9 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.go(a.url)
        })
      }, (a: QuickAction) => a.title)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  // ===== 我的医生（发丝行） =====
  @Builder
  doctorLine() {
    Column() {
      Divider().color(HAIRLINE).strokeWidth(1)
      Row() {
        Image($r('app.media.ic_stethoscope'))
          .width(18)
          .height(18)
          .fillColor(MINT)

        Column() {
          Text('主管医生')
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .letterSpacing(0.8)
          Text(this.myDoctor ? displayNameOf(this.myDoctor!.nickname, this.myDoctor!.username) : '尚未绑定')
            .fontSize(T_BODY)
            .fontColor(INK)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

        if (this.myDoctor) {
          Text('发私信')
            .fontSize(T_CAP)
            .fontColor(MINT)
            .letterSpacing(0.4)
            .padding({ left: 4, top: 6, bottom: 6 })
            .onClick(() => {
              this.doctorDm()
            })
        } else {
          Text('去绑定')
            .fontSize(T_CAP)
            .fontColor(MINT)
            .letterSpacing(0.4)
            .padding({ left: 4, top: 6, bottom: 6 })
            .onClick(() => {
              this.go('pages/BindDoctorPage')
            })
        }

        Image($r('app.media.ic_arrow_right'))
          .width(13)
          .height(13)
          .fillColor(INK_FAINT)
          .margin({ left: 6 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.myDoctor) {
          this.showDoctorCard = true
        } else {
          this.go('pages/BindDoctorPage')
        }
      })
      Divider().color(HAIRLINE).strokeWidth(1)
    }
    .width('100%')
    .bindSheet($$this.showDoctorCard, this.doctorSheet(), {
      height: 420,
      dragBar: true,
      showClose: true,
      backgroundColor: SURFACE,
      onDisappear: () => { this.showDoctorCard = false }
    })
  }

  @Builder
  doctorSheet() {
    Column() {
      Text(displayNameOf(this.myDoctor!.nickname, this.myDoctor!.username))
        .fontSize(T_H2)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
        .width('100%')
      Text('主管医生 · ' + this.getGenderLabel(this.myDoctor!.gender))
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .letterSpacing(0.6)
        .width('100%')
        .margin({ top: 6 })

      Column() {
        this.sheetRow('执业执照号', this.myDoctor!.doctorLicense !== '' ? this.myDoctor!.doctorLicense : '暂无')
        Divider().color(HAIRLINE).strokeWidth(1)
        this.sheetRow('联系电话', this.myDoctor!.phone !== '' ? this.myDoctor!.phone : '暂无')
        Divider().color(HAIRLINE).strokeWidth(1)
        this.sheetRow('注册于', this.regDateText(this.myDoctor!.createdAt))
      }
      .width('100%')
      .margin({ top: 22 })

      Blank()

      Text('发私信')
        .fontSize(T_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .textAlign(TextAlign.Center)
        .width('100%')
        .height(50)
        .borderRadius(R_MD)
        .backgroundColor(MINT)
        .onClick(() => {
          this.doctorDm()
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 8, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  sheetRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(T_SM)
        .fontColor(INK_FAINT)
      Blank()
      Text(value)
        .fontSize(T_SM)
        .fontColor(INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }

  // ===== 最近一次记录 =====
  @Builder
  latestLine() {
    if (this.latestData) {
      Column() {
        Text('最 近 一 次')
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .letterSpacing(2)
          .width('100%')
        Row() {
          Text(this.latestData!.recordTime.substring(0, 10))
            .fontSize(T_BODY)
            .fontColor(INK)
          Text(this.latestData!.recordTime.substring(11, 16))
            .fontSize(T_SM)
            .fontColor(INK_FAINT)
            .margin({ left: 8 })
          Blank()
          Text(this.latestData!.exerciseType !== '' ? this.latestData!.exerciseType : '手动录入')
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
        }
        .width('100%')
        .margin({ top: 10 })
        .alignItems(VerticalAlign.Center)

        Row() {
          this.miniStat({ label: '血压', value: this.latestData!.bloodPressureSystolic > 0 ? this.latestData!.bloodPressureSystolic + '/' + this.latestData!.bloodPressureDiastolic : '—', color: M_BP })
          this.miniStat({ label: '血糖', value: this.latestData!.bloodSugar > 0 ? this.latestData!.bloodSugar.toString() : '—', color: M_SUGAR })
          this.miniStat({ label: '心率', value: this.latestData!.heartRate > 0 ? this.latestData!.heartRate.toString() : '—', color: M_HR })
          this.miniStat({ label: '体重', value: this.latestData!.weight > 0 ? this.latestData!.weight.toString() : '—', color: M_WEIGHT })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  miniStat(opt: MiniStat) {
    Column() {
      Row() {
        Circle()
          .width(4)
          .height(4)
          .fill(opt.color)
        Text(opt.label)
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .margin({ left: 5 })
      }
      .alignItems(VerticalAlign.Center)
      Text(opt.value)
        .fontSize(T_H2)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  patientBody() {
    Refresh({ refreshing: $$this.refreshing }) {
      Scroll() {
        Column() {
          this.dashboard()
          this.quickRow()
          this.doctorLine()
          this.latestLine()
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
    .onRefreshing(async () => {
      await this.refreshData()
      this.refreshing = false
    })
  }

  // ===== 医护视角 =====
  @Builder
  tabText(opt: TabOpt) {
    Column() {
      Text(opt.label)
        .fontSize(T_SM)
        .fontColor(this.adminTab === opt.key ? INK : INK_FAINT)
        .letterSpacing(0.6)
      Divider()
        .width(18)
        .color(this.adminTab === opt.key ? MINT : 'rgba(0,0,0,0)')
        .strokeWidth(2)
        .margin({ top: 7 })
        .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
    }
    .margin({ right: 24 })
    .onClick(() => {
      this.adminTab = opt.key
    })
  }

  @Builder
  patientLine(item: PatientRow) {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          if (item.avatarUrl !== undefined && item.avatarUrl !== '') {
            Image(item.avatarUrl).width(34).height(34).objectFit(ImageFit.Cover)
          } else {
            Image(resolveAvatar(item.gender, 'patient'))
              .width(15)
              .height(15)
              .fillColor(MINT)
          }
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .clip(true)
        .backgroundColor(MINT_SOFT)

        Column() {
          Text(item.name)
            .fontSize(T_BODY)
            .fontColor(INK)
          Text('最近血压 ' + item.latestBp)
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

        if (item.warnCount > 0) {
          Text(item.warnCount.toString())
            .fontSize(T_MICRO)
            .fontColor(DANGER)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(R_XS)
            .backgroundColor(DANGER_SOFT)
        } else {
          Text('平稳')
            .fontSize(T_MICRO)
            .fontColor(MINT)
        }

        Image($r('app.media.ic_arrow_right'))
          .width(13)
          .height(13)
          .fillColor(INK_FAINT)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 15, bottom: 15 })
      .alignItems(VerticalAlign.Center)
      Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
    }
    .width('100%')
    .onClick(() => {
      this.goPatientDetail(item.userId)
    })
  }

  @Builder
  doctorLineRow(item: DoctorRow) {
    Column() {
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          if (item.avatarUrl !== '') {
            Image(item.avatarUrl).width(34).height(34).objectFit(ImageFit.Cover)
          } else {
            Image($r('app.media.ic_avatar_doctor'))
              .width(15)
              .height(15)
              .fillColor('#FFFFFF')
          }
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(MINT)
        .clip(true)

        Column() {
          Text(item.name)
            .fontSize(T_BODY)
            .fontColor(INK)
          Text('执照 ' + item.license)
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

        if (item.doctorStatus === 'pending') {
          Text('待审核')
            .fontSize(T_MICRO)
            .fontColor(AMBER)
            .backgroundColor('rgba(154, 109, 37, 0.10)')
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(R_XS)
        } else if (item.doctorStatus === 'rejected') {
          Text('已驳回')
            .fontSize(T_MICRO)
            .fontColor(DANGER)
            .backgroundColor(DANGER_SOFT)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .borderRadius(R_XS)
        } else {
          Text(item.patientCount + ' 位')
            .fontSize(T_MICRO)
            .fontColor(AMBER)
        }

        Image($r('app.media.ic_arrow_right'))
          .width(13)
          .height(13)
          .fillColor(INK_FAINT)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 15, bottom: 15 })
      .alignItems(VerticalAlign.Center)
      Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
    }
    .width('100%')
    .onClick(() => {
      this.goDoctorDetail(item.userId)
    })
  }

  @Builder
  staffBody() {
    Column() {
      if (this.role === 'admin') {
        // 分段切换直接内联，避免 @Builder 参数不刷新导致下划线卡住
        Row() {
          Column() {
            Text('患者')
              .fontSize(T_SM)
              .fontColor(this.adminTab === 'patient' ? INK : INK_FAINT)
              .letterSpacing(0.6)
            Divider()
              .width(18)
              .color(this.adminTab === 'patient' ? MINT : 'rgba(0,0,0,0)')
              .strokeWidth(2)
              .margin({ top: 7 })
              .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
          }
          .margin({ right: 24 })
          .onClick(() => {
            this.adminTab = 'patient'
          })

          Column() {
            Text('医生')
              .fontSize(T_SM)
              .fontColor(this.adminTab === 'doctor' ? INK : INK_FAINT)
              .letterSpacing(0.6)
            Divider()
              .width(18)
              .color(this.adminTab === 'doctor' ? MINT : 'rgba(0,0,0,0)')
              .strokeWidth(2)
              .margin({ top: 7 })
              .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
          }
          .margin({ right: 24 })
          .onClick(() => {
            this.adminTab = 'doctor'
          })

          Blank()
        }
        .width('100%')
        .padding({ left: 24, right: 24, bottom: 6 })
      }

      // 医生本人未通过审核时，明确告知原因（此时看不到任何患者数据）
      if (this.role === 'doctor' && this.user !== null && this.user.doctorStatus !== 'approved') {
        Row() {
          Circle()
            .width(5)
            .height(5)
            .fill(AMBER)
          Text(this.user.doctorStatus === 'pending'
            ? '资质待管理员审核，通过后才能查看患者数据'
            : '资质审核未通过，请联系管理员补充材料')
            .fontSize(T_CAP)
            .fontColor(this.user.doctorStatus === 'pending' ? AMBER : DANGER)
            .margin({ left: 7 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 4, bottom: 10 })
        .alignItems(VerticalAlign.Center)
      }

      Row() {
        Text(this.role === 'admin' && this.adminTab === 'doctor' ? '医 生 团 队' : (this.role === 'doctor' ? '我 的 患 者' : '全 部 患 者'))
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .letterSpacing(2)
        Blank()
        Text((this.role === 'admin' && this.adminTab === 'doctor' ? this.doctors.length : this.patients.length).toString())
          .fontSize(T_MICRO)
          .fontColor(MINT)

        // 仅管理员：一键生成演示数据（账号 + 30 天记录 + 预警 + 社区内容 + 医患对话）
        if (this.role === 'admin') {
          Text(this.seeding ? '生成中…' : '生成演示数据')
            .fontSize(T_MICRO)
            .fontColor(this.seeding ? INK_FAINT : MINT)
            .letterSpacing(0.4)
            .padding({ left: 10, top: 4, bottom: 4 })
            .margin({ left: 12 })
            .onClick(() => {
              this.handleSeed()
            })
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 10, bottom: 12 })

      Refresh({ refreshing: $$this.refreshing }) {
        List() {
          if (this.role === 'admin' && this.adminTab === 'doctor') {
            ForEach(this.doctors, (item: DoctorRow) => {
              ListItem() {
                this.doctorLineRow(item)
              }
            }, (item: DoctorRow) => item.userId.toString())
          } else {
            ForEach(this.patients, (item: PatientRow) => {
              ListItem() {
                this.patientLine(item)
              }
            }, (item: PatientRow) => item.userId.toString())
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .onRefreshing(async () => {
        await this.refreshData()
        this.refreshing = false
      })
    }
    .layoutWeight(1)
  }

  build() {
    Column() {
      this.headerBar()

      // 只有"首次加载、还没有任何用户数据"时才整屏 loading。
      // 从其它 tab 切回来时 user 已存在，直接渲染上一帧内容、后台静默刷新，
      // 这样底部导航与页面都不会闪一下（之前的整屏 opacity 淡入就是闪烁的来源）。
      if (this.isLoading && this.user === null) {
        Column() {
          StateView({ kind: 'loading', title: '正在读取数据' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.role === 'patient') {
        this.patientBody()
      } else {
        this.staffBody()
      }

      BottomNav({ current: 'home', isPatient: this.role === 'patient' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }
}
