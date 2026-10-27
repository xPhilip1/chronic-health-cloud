import {
  INK, INK_SUB, INK_FAINT, MINT, MINT_SOFT, SURFACE_2, HAIRLINE,
  R_PILL, T_H3, T_SM, T_CAP, TRACK_LABEL
} from '../common/Theme'

// 三态视图 v2：深色下的空/错/加载。
// 圆形底座 + 大标题 + 两句说明 + 一个薄荷描边胶囊按钮，比上一版更安静。
@Component
export struct StateView {
  @Prop kind: string = 'empty'
  @Prop title: string = ''
  @Prop desc: string = ''
  @Prop actionText: string = ''
  @Prop icon: Resource = $r('app.media.ic_data_records')
  @Prop iconColor: Resource = INK_FAINT
  @Prop iconBg: Resource = SURFACE_2
  onAction: () => void = () => {}

  build() {
    Column() {
      if (this.kind === 'loading') {
        LoadingProgress()
          .width(26)
          .height(26)
          .color(MINT)
        Text(this.title === '' ? '加载中' : this.title)
          .fontSize(T_CAP)
          .fontColor(INK_FAINT)
          .letterSpacing(TRACK_LABEL)
          .margin({ top: 14 })
      } else {
        Row() {
          Image(this.icon)
            .width(24)
            .height(24)
            .fillColor(this.iconColor)
        }
        .width(64)
        .height(64)
        .justifyContent(FlexAlign.Center)
        .borderRadius(32)
        .backgroundColor(this.iconBg)
        .border({ width: 1, color: HAIRLINE })

        Text(this.title)
          .fontSize(T_H3)
          .fontWeight(FontWeight.Medium)
          .fontColor(INK)
          .textAlign(TextAlign.Center)
          .margin({ top: 20 })

        if (this.desc !== '') {
          Text(this.desc)
            .fontSize(T_SM)
            .fontColor(INK_FAINT)
            .textAlign(TextAlign.Center)
            .lineHeight(21)
            .margin({ top: 10, left: 28, right: 28 })
        }

        if (this.actionText !== '') {
          Text(this.actionText)
            .fontSize(T_CAP)
            .fontWeight(FontWeight.Medium)
            .fontColor(MINT)
            .letterSpacing(0.6)
            .padding({ left: 20, right: 20, top: 10, bottom: 10 })
            .borderRadius(R_PILL)
            .backgroundColor(MINT_SOFT)
            .border({ width: 1, color: 'rgba(15, 122, 92, 0.25)' })
            .margin({ top: 20 })
            .onClick(() => {
              this.onAction()
            })
        }
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
