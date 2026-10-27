import {
  SURFACE, HAIRLINE, INK, INK_SUB, INK_FAINT, R_MD, T_H2, T_MICRO, D_BASE
} from '../common/Theme'

// 指标小卡：彩色图标徽章 + 大号数值 + 标签·单位。
// 新版去掉重投影，改用极细描边；数值用主文字色，只让图标承担颜色。
@Component
export struct MetricTile {
  @Prop label: string = ''
  @Prop value: string = ''
  @Prop unit: string = ''
  @Prop color: string = '#2F6F5E'
  @Prop bg: string = '#EAF1ED'
  @Prop icon: Resource = $r('app.media.ic_bar_chart')

  @State pressScale: number = 1

  build() {
    Column() {
      Row() {
        Image(this.icon)
          .width(30)
          .height(30)
          .padding(7)
          .borderRadius(R_MD)
          .backgroundColor(this.bg)
          .fillColor(this.color)
        Blank()
      }
      .width('100%')

      Column() {
        Text(this.value)
          .fontSize(T_H2)
          .fontWeight(FontWeight.Medium)
          .fontColor(INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.label + ' · ' + this.unit)
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .margin({ top: 3 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 14 })
    }
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .width('100%')
    .backgroundColor(SURFACE)
    .borderRadius(R_MD)
    .border({ width: 1, color: HAIRLINE })
    .scale({ x: this.pressScale, y: this.pressScale })
    .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.pressScale = 0.98
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.pressScale = 1
      }
    })
  }
}
