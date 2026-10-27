import {
  CANVAS, INK, INK_SUB, MINT, MINT_SOFT, ON_PRIMARY, HAIRLINE,
  R_PILL, T_H3, TRACK_LABEL
} from '../common/Theme'

// 标题栏 v2：完全去装饰——没有色块、没有椭圆边框，只有一条可读的标题和极简返回箭头。
// 标题居中、操作文字用薄荷色，视觉上把注意力全部让给内容。
@Component
export struct NavBar {
  @Prop title: string = ''
  @Prop avatarUrl: string = ''
  @Prop rightText: string = ''
  @Prop showBack: boolean = true
  @Prop rightEnabled: boolean = true
  onRight: () => void = () => {}

  @State backOpacity: number = 1

  build() {
    Row() {
      Row() {
        if (this.showBack) {
          Image($r('app.media.ic_arrow_back'))
            .width(20)
            .height(20)
            .fillColor(INK)
            .opacity(this.backOpacity)
            .onTouch((ev: TouchEvent) => {
              if (ev.type === TouchType.Down) {
                this.backOpacity = 0.45
              } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
                this.backOpacity = 1
              }
            })
            .onClick(() => {
              try {
                this.getUIContext().getRouter().back()
              } catch (e) {
                console.error('返回失败: ' + (e as Error).message)
              }
            })
        }
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)

      // 可选：标题左侧的对方头像（聊天页用），不传则完全不占位
      if (this.avatarUrl !== '') {
        Stack({ alignContent: Alignment.Center }) {
          Image(this.avatarUrl)
            .width(28)
            .height(28)
            .objectFit(ImageFit.Cover)
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(MINT_SOFT)
        .clip(true)
        .margin({ left: 2, right: 8 })
      }

      Text(this.title)
        .fontSize(T_H3)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
        .letterSpacing(0.4)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .layoutWeight(1)

      Row() {
        if (this.rightText !== '') {
          Text(this.rightText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.rightEnabled ? MINT : '#8B9893')
            .letterSpacing(0.3)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .onClick(() => {
              if (this.rightEnabled) {
                this.onRight()
              }
            })
        }
      }
      .width(48)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .backgroundColor(CANVAS)
    .alignItems(VerticalAlign.Center)
  }
}
