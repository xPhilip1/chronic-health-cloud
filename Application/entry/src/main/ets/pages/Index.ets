import { isLoggedIn } from '../service/ApiService'
import { CANVAS, INK, INK_FAINT, MINT, HAIRLINE, T_DISPLAY, T_MICRO, TRACK_LABEL } from '../common/Theme'

// 启动页 v2：没有大图标、没有色块。
// 只有一枚发光的薄荷点、依次淡入的字标，以及一条 1.1s 走完的发丝级进度线。
@Entry
@Component
struct Index {
  @State loggedIn: boolean = false
  @State dotIn: boolean = false
  @State textIn: boolean = false
  @State barW: number = 0
  @State barOpacity: number = 0

  async aboutToAppear(): Promise<void> {
    this.loggedIn = await isLoggedIn()

    setTimeout(() => {
      this.dotIn = true
    }, 80)
    setTimeout(() => {
      this.textIn = true
    }, 240)
    setTimeout(() => {
      this.barOpacity = 1
      this.barW = 132
    }, 320)

    setTimeout(() => {
      try {
        if (this.loggedIn) {
          this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' })
        } else {
          this.getUIContext().getRouter().replaceUrl({ url: 'pages/LoginPage' })
        }
      } catch (e) {
        console.error('页面跳转失败: ' + (e as Error).message)
      }
    }, 1180)
  }

  build() {
    Column() {
      Row() {
        Circle()
          .width(6)
          .height(6)
          .fill(MINT)
          .shadow({ radius: 16, color: 'rgba(15, 122, 92, 0.35)', offsetX: 0, offsetY: 0 })
        Text('CHRONICCLOUD')
          .fontSize(T_MICRO)
          .fontColor(INK)
          .letterSpacing(4)
          .margin({ left: 10 })
      }
      .opacity(this.dotIn ? 1 : 0)
      .animation({ duration: 480, curve: Curve.FastOutSlowIn })

      Blank()

      Column() {
        Text('守住每一天的\n健康数值')
          .fontSize(T_DISPLAY)
          .fontWeight(FontWeight.Medium)
          .fontColor(INK)
          .lineHeight(46)
          .letterSpacing(0.5)
        Text('慢病管理 · 数据记录 · 医患协同')
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .letterSpacing(TRACK_LABEL)
          .margin({ top: 16 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .translate({ y: this.textIn ? 0 : 14 })
      .opacity(this.textIn ? 1 : 0)
      .animation({ duration: 620, curve: Curve.FastOutSlowIn })

      Blank()

      Divider()
        .width(this.barW)
        .color(MINT)
        .strokeWidth(2)
        .opacity(this.barOpacity)
        .animation({ duration: 820, curve: Curve.EaseInOut })
        .alignSelf(ItemAlign.Start)

      Text('v1.0')
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .letterSpacing(1)
        .margin({ top: 14, bottom: 8 })
        .alignSelf(ItemAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 32, right: 32, top: 64, bottom: 32 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(CANVAS)
  }
}
