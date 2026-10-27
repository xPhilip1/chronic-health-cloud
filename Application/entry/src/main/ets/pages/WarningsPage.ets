import { HealthWarning } from '../model/HealthModel'
import { getWarningList, acknowledgeWarning } from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_SUNK, HAIRLINE, INK, INK_SUB, INK_FAINT,
  JADE, JADE_SOFT, ON_PRIMARY, DANGER, DANGER_SOFT, WARN, WARN_SOFT, OK, OK_SOFT,
  R_LG, R_MD, R_PILL, R_XS, T_H3, T_BODY, T_SM, T_CAP, T_MICRO, D_BASE
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { StateView } from '../components/StateView'

interface FilterOpt {
  label: string
  value: string
  count: number
}

@Entry
@Component
struct WarningsPage {
  @State warnings: HealthWarning[] = []
  @State filter: string = 'all'
  @State refreshing: boolean = false

  async aboutToAppear(): Promise<void> {
    await this.loadData()
  }

  async loadData(): Promise<void> {
    this.warnings = await getWarningList()
  }

  async handleAcknowledge(id: number): Promise<void> {
    await acknowledgeWarning(id)
    this.warnings = await getWarningList()
  }

  getFilteredList(): HealthWarning[] {
    if (this.filter === 'unacknowledged') {
      let result: HealthWarning[] = []
      for (let i = 0; i < this.warnings.length; i++) {
        if (!this.warnings[i].acknowledged) {
          result.push(this.warnings[i])
        }
      }
      return result
    }
    return this.warnings
  }

  unackCount(): number {
    let n: number = 0
    for (let i = 0; i < this.warnings.length; i++) {
      if (!this.warnings[i].acknowledged) {
        n++
      }
    }
    return n
  }

  getSeverityColor(sev: string): Resource {
    if (sev === 'high') {
      return DANGER
    }
    if (sev === 'medium') {
      return WARN
    }
    return INK_FAINT
  }

  getSeveritySoft(sev: string): Resource {
    if (sev === 'high') {
      return DANGER_SOFT
    }
    if (sev === 'medium') {
      return WARN_SOFT
    }
    return SURFACE_SUNK
  }

  getSeverityLabel(sev: string): string {
    if (sev === 'high') {
      return '高危'
    }
    if (sev === 'medium') {
      return '中危'
    }
    return '低危'
  }

  getTypeLabel(type: string): string {
    if (type === 'high_blood_pressure') {
      return '高血压'
    }
    if (type === 'high_blood_sugar') {
      return '高血糖'
    }
    if (type === 'low_blood_sugar') {
      return '低血糖'
    }
    if (type === 'other') {
      return '其他'
    }
    return type
  }

  formatTime(isoStr: string): string {
    let parts: string[] = isoStr.split('T')
    if (parts.length < 2) {
      return isoStr
    }
    return parts[0] + ' ' + parts[1].substring(0, 5)
  }

  // 值类型参数不随状态刷新，这里用对象传参（选中态与计数都会变）
  @Builder
  filterChip(opt: FilterOpt) {
    Row() {
      Text(opt.label)
        .fontSize(T_SM)
        .fontWeight(this.filter === opt.value ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.filter === opt.value ? ON_PRIMARY : INK_SUB)
      if (opt.count > 0) {
        Text(opt.count.toString())
          .fontSize(T_MICRO)
          .fontColor(this.filter === opt.value ? ON_PRIMARY : INK_FAINT)
          .margin({ left: 5 })
      }
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .borderRadius(R_PILL)
    .backgroundColor(this.filter === opt.value ? JADE : SURFACE)
    .border({ width: 1, color: this.filter === opt.value ? JADE : HAIRLINE })
    .margin({ right: 8 })
    .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      this.filter = opt.value
    })
  }

  @Builder
  warningCard(item: HealthWarning) {
    Row() {
      // 左侧严重度色条（固定高度，避免在自适应高度的行里用 100% 导致高度塌陷）
      Column()
        .width(3)
        .height(40)
        .borderRadius(2)
        .backgroundColor(this.getSeverityColor(item.severity))
        .margin({ right: 14, top: 2 })

      Column() {
        Row() {
          Text(this.getSeverityLabel(item.severity))
            .fontSize(T_MICRO)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.getSeverityColor(item.severity))
            .backgroundColor(this.getSeveritySoft(item.severity))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(R_XS)
          Text(this.getTypeLabel(item.warningType))
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .margin({ left: 8 })
          Blank()
          Text(this.formatTime(item.warningTime))
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
        }
        .width('100%')

        Text(item.warningMessage)
          .fontSize(T_SM)
          .fontColor(INK)
          .lineHeight(22)
          .width('100%')
          .margin({ top: 10 })

        Row() {
          Blank()
          if (!item.acknowledged) {
            Text('标记已读')
              .fontSize(T_MICRO)
              .fontWeight(FontWeight.Medium)
              .fontColor(JADE)
              .backgroundColor(JADE_SOFT)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(R_PILL)
              .margin({ top: 12 })
              .onClick(() => {
                this.handleAcknowledge(item.warningId)
              })
          } else {
            Row() {
              Image($r('app.media.ic_check'))
                .width(13)
                .height(13)
                .fillColor(OK)
              Text('已确认')
                .fontSize(T_MICRO)
                .fontColor(OK)
                .margin({ left: 4 })
            }
            .margin({ top: 12 })
            .alignItems(VerticalAlign.Center)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 16, top: 16, bottom: 16 })
    .backgroundColor(SURFACE)
    .borderRadius(R_LG)
    .border({ width: 1, color: HAIRLINE })
    .alignItems(VerticalAlign.Top)
    .opacity(item.acknowledged ? 0.72 : 1)
  }

  build() {
    Column() {
      NavBar({ title: '预警中心' })

      Row() {
        this.filterChip({ label: '全部', value: 'all', count: 0 })
        this.filterChip({ label: '未确认', value: 'unacknowledged', count: this.unackCount() })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 12 })

      if (this.getFilteredList().length === 0) {
        Column() {
          StateView({
            kind: 'empty',
            title: this.filter === 'unacknowledged' ? '没有未确认的预警' : '暂无预警',
            desc: '指标出现异常时，这里会第一时间提醒你',
            icon: $r('app.media.ic_check_circle'),
            iconColor: OK,
            iconBg: OK_SOFT
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: 12 }) {
            ForEach(this.getFilteredList(), (item: HealthWarning) => {
              ListItem() {
                this.warningCard(item)
              }
            }, (item: HealthWarning) => item.warningId.toString() + '_' + (item.acknowledged ? 1 : 0))
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20, bottom: 20 })
          .scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .onRefreshing(async () => {
          await this.loadData()
          this.refreshing = false
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }
}
