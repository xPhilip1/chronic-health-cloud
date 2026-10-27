import { AiHealthReport, AiMetricRead, AiReportCache } from '../model/HealthModel'
import { UserInfo } from '../model/UserModel'
import { getCachedReport, requestReport, getCurrentUser } from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_SUNK, HAIRLINE, INK, INK_SUB, INK_FAINT,
  JADE, JADE_SOFT, BRASS, BRASS_SOFT, DANGER, DANGER_SOFT, WARN, WARN_SOFT, OK, OK_SOFT,
  R_LG, R_MD, R_PILL, R_XS, T_H1, T_H2, T_H3, T_BODY, T_SM, T_CAP, T_MICRO, D_BASE
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { StateView } from '../components/StateView'
import { displayNameOf } from '../common/UserUtil'
import { exportAndShareReportPdf } from '../service/ReportPdfExporter'
import { GradientButton } from '../components/GradientButton'
import { common } from '@kit.AbilityKit'

interface AdviceCard {
  body: string
  title: string
  icon: Resource
}

@Entry
@Component
struct AdvicePage {
  @State report: AiHealthReport | null = null
  @State loading: boolean = true
  @State refreshing: boolean = false
  @State empty: boolean = false
  @State errMsg: string = ''
  @State generatedAt: string = ''
  @State sampleCount: number = 0
  @State exporting: boolean = false
  @State displayName: string = ''
  @State account: string = ''
  @State contentIn: boolean = false

  async aboutToAppear(): Promise<void> {
    let cached: AiReportCache | null = await getCachedReport()
    if (cached !== null) {
      this.apply(cached)
      this.loading = false
    } else {
      await this.doGenerate()
    }
    try {
      let u: UserInfo | null = await getCurrentUser()
      if (u !== null) {
        this.account = u.username
        this.displayName = displayNameOf(u.nickname, u.username)
      }
    } catch (e) {
      console.error('读取用户信息失败: ' + (e as Error).message)
    }
    setTimeout(() => {
      this.contentIn = true
    }, 40)
  }

  apply(wrap: AiReportCache): void {
    this.report = wrap.report
    this.generatedAt = this.formatTime(wrap.generatedAt)
    this.sampleCount = wrap.sampleCount
    this.empty = false
    this.errMsg = ''
  }

  async doGenerate(): Promise<void> {
    this.loading = true
    this.errMsg = ''
    this.empty = false
    try {
      let wrap: AiReportCache = await requestReport()
      this.apply(wrap)
    } catch (e) {
      let msg: string = (e as Error).message
      if (msg.indexOf('NO_DATA') >= 0) {
        this.empty = true
      } else {
        this.errMsg = msg
      }
    } finally {
      this.loading = false
    }
  }

  async regenerate(): Promise<void> {
    this.errMsg = ''
    this.empty = false
    try {
      let wrap: AiReportCache = await requestReport()
      this.apply(wrap)
    } catch (e) {
      let msg: string = (e as Error).message
      if (msg.indexOf('NO_DATA') >= 0) {
        this.empty = true
      } else {
        this.errMsg = msg
      }
    }
  }

  handleRegenerate(): void {
    if (this.loading) {
      return
    }
    this.doGenerate()
  }

  async handleExportPdf(): Promise<void> {
    if (this.report === null) {
      this.getUIContext().getPromptAction().showToast({ message: '请先生成报告' })
      return
    }
    this.exporting = true
    try {
      let ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext
      await exportAndShareReportPdf(
        this.report, this.displayName, this.account, this.generatedAt, this.sampleCount, ctx
      )
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败：' + (e as Error).message })
    } finally {
      this.exporting = false
    }
  }

  formatTime(iso: string): string {
    if (iso === '') {
      return ''
    }
    let d = new Date(iso)
    if (isNaN(d.getTime())) {
      return iso
    }
    let m = (d.getMonth() + 1).toString().padStart(2, '0')
    let day = d.getDate().toString().padStart(2, '0')
    let hh = d.getHours().toString().padStart(2, '0')
    let mm = d.getMinutes().toString().padStart(2, '0')
    return d.getFullYear() + '-' + m + '-' + day + ' ' + hh + ':' + mm
  }

  getRiskLabel(level: string): string {
    if (level === 'high') {
      return '高风险'
    }
    if (level === 'medium') {
      return '需关注'
    }
    return '总体平稳'
  }

  getRiskColor(level: string): Resource {
    if (level === 'high') {
      return DANGER
    }
    if (level === 'medium') {
      return WARN
    }
    return OK
  }

  getRiskSoft(level: string): Resource {
    if (level === 'high') {
      return DANGER_SOFT
    }
    if (level === 'medium') {
      return WARN_SOFT
    }
    return OK_SOFT
  }

  mapStatusToLevel(status: string): string {
    if (status.indexOf('危') >= 0 || status.indexOf('严重') >= 0) {
      return 'high'
    }
    if (status.indexOf('高') >= 0 || status.indexOf('低') >= 0 ||
      status.indexOf('异常') >= 0 || status.indexOf('波动') >= 0) {
      return 'medium'
    }
    return 'low'
  }

  @Builder
  sectionTitle(title: string, icon: Resource) {
    Row() {
      Image(icon)
        .width(14)
        .height(14)
        .fillColor(JADE)
        .margin({ right: 7 })
      Text(title)
        .fontSize(T_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  // 值类型参数不随状态刷新，报告内容会变，所以用对象传参
  @Builder
  textCard(opt: AdviceCard) {
    if (opt.body !== '') {
      Column() {
        this.sectionTitle(opt.title, opt.icon)
        Text(opt.body)
          .fontSize(T_SM)
          .fontColor(INK_SUB)
          .lineHeight(23)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(18)
      .backgroundColor(SURFACE)
      .borderRadius(R_LG)
      .border({ width: 1, color: HAIRLINE })
      .margin({ top: 12 })
    }
  }

  build() {
    Column() {
      NavBar({
        title: 'AI 健康建议',
        rightText: this.loading ? '生成中' : '重新生成',
        rightEnabled: !this.loading,
        onRight: () => {
          this.handleRegenerate()
        }
      })

      if (this.loading) {
        Column() {
          StateView({
            kind: 'loading',
            title: 'AI 正在分析你近 30 天的数据',
            desc: '生成一份完整报告通常需要几秒'
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.empty) {
        Column() {
          StateView({
            kind: 'empty',
            title: '还没有可分析的数据',
            desc: '录入近 30 天的血压 / 血糖 / 心率等记录后，AI 会为你生成个性化报告',
            actionText: '去添加数据',
            icon: $r('app.media.ic_data_records'),
            onAction: () => {
              try {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/AddDataPage' })
              } catch (e) {
                console.error('跳转失败: ' + (e as Error).message)
              }
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errMsg !== '') {
        Column() {
          StateView({
            kind: 'error',
            title: '暂时无法生成报告',
            desc: this.errMsg,
            actionText: '重试',
            icon: $r('app.media.ic_warning'),
            iconColor: DANGER,
            iconBg: DANGER_SOFT,
            onAction: () => { this.doGenerate() }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.report !== null) {
        this.buildReport(this.report)
      } else {
        Column() {
          StateView({ kind: 'empty', title: '暂无报告', desc: '点右上角重新生成' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }

  @Builder
  buildReport(report: AiHealthReport) {
    Refresh({ refreshing: $$this.refreshing }) {
      Scroll() {
        Column() {
          // 评估总览
          Column() {
            Row() {
              Text(this.getRiskLabel(report.riskLevel))
                .fontSize(T_CAP)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.getRiskColor(report.riskLevel))
                .backgroundColor(this.getRiskSoft(report.riskLevel))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(R_PILL)
              Blank()
              Row() {
                Image($r('app.media.ic_robot'))
                  .width(13)
                  .height(13)
                  .fillColor(INK_FAINT)
                  .margin({ right: 4 })
                Text('AI 生成')
                  .fontSize(T_MICRO)
                  .fontColor(INK_FAINT)
              }
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')

            Text(report.overallAssessment)
              .fontSize(T_BODY)
              .fontColor(INK)
              .lineHeight(26)
              .width('100%')
              .margin({ top: 14 })

            if (this.generatedAt !== '' || this.sampleCount > 0) {
              Text('生成于 ' + this.generatedAt + (this.sampleCount > 0 ? (' · 基于 ' + this.sampleCount + ' 条数据') : ''))
                .fontSize(T_MICRO)
                .fontColor(INK_FAINT)
                .width('100%')
                .margin({ top: 14 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(18)
          .backgroundColor(SURFACE)
          .borderRadius(R_LG)
          .border({ width: 1, color: HAIRLINE })

          // 指标解读
          if (report.metrics.length > 0) {
            Column() {
              this.sectionTitle('指标解读', $r('app.media.ic_heart'))
              ForEach(report.metrics, (item: AiMetricRead, idx: number) => {
                Column() {
                  Row() {
                    Text(item.name)
                      .fontSize(T_SM)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(INK)
                      .layoutWeight(1)
                    Text(item.status)
                      .fontSize(T_MICRO)
                      .fontColor(this.getRiskColor(this.mapStatusToLevel(item.status)))
                      .backgroundColor(this.getRiskSoft(this.mapStatusToLevel(item.status)))
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .borderRadius(R_XS)
                  }
                  .width('100%')

                  Text(item.detail)
                    .fontSize(T_CAP)
                    .fontColor(INK_SUB)
                    .lineHeight(21)
                    .width('100%')
                    .margin({ top: 6 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ top: 12, bottom: 12 })
                .border({ width: { top: idx === 0 ? 0 : 1 }, color: HAIRLINE })
              }, (item: AiMetricRead) => item.name + '|' + item.status + '|' + item.detail)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(18)
            .backgroundColor(SURFACE)
            .borderRadius(R_LG)
            .border({ width: 1, color: HAIRLINE })
            .margin({ top: 12 })
          }

          this.textCard({ body: report.trendAnalysis, title: '趋势分析', icon: $r('app.media.ic_trend_chart') })
          this.textCard({ body: report.dietAdvice, title: '饮食建议', icon: $r('app.media.ic_diet') })
          this.textCard({ body: report.exerciseAdvice, title: '运动建议', icon: $r('app.media.ic_exercise') })
          this.textCard({ body: report.lifestyleAdvice, title: '生活方式', icon: $r('app.media.ic_moon') })
          this.textCard({ body: report.followUpAdvice, title: '复查与就医', icon: $r('app.media.ic_stethoscope') })

          // 危险信号
          if (report.redFlags !== '') {
            Column() {
              this.sectionTitle('危险信号', $r('app.media.ic_siren'))
              Text(report.redFlags)
                .fontSize(T_SM)
                .fontColor(INK)
                .lineHeight(23)
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(18)
            .backgroundColor(DANGER_SOFT)
            .borderRadius(R_LG)
            .border({ width: 1, color: '#EFD6D2' })
            .margin({ top: 12 })
          }

          Column() {
            GradientButton({
              text: this.exporting ? '导出中…' : '导出 PDF 报告',
              enabledState: !this.exporting,
              btnHeight: 50,
              onTap: () => {
                this.handleExportPdf()
              }
            })
          }
          .width('100%')
          .margin({ top: 20 })

          Text('本报告由 AI 依据你录入的数据自动生成，仅供健康管理参考，不能替代医生诊断。如有不适请及时就医。')
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .lineHeight(18)
            .width('100%')
            .margin({ top: 14, bottom: 28 })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 4 })
        .opacity(this.contentIn ? 1 : 0)
        .animation({ duration: 300, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .layoutWeight(1)
    .onRefreshing(async () => {
      await this.regenerate()
      this.refreshing = false
    })
  }
}
