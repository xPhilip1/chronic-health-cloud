import { MINT, ON_PRIMARY, R_MD, D_BASE, SHADOW_GLOW } from '../common/Theme'

// 主操作按钮 v2：薄荷实底 + 深色字 + 外发光。
// 深色界面里"发光"比阴影更能表达可点，所以只给主动作保留这一处光。
@Component
export struct GradientButton {
  @Prop text: string = ''
  @Prop enabledState: boolean = true
  @Prop btnHeight: number = 52
  onTap: () => void = () => {}

  @State pressScale: number = 1

  build() {
    Row() {
      Text(this.text)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(ON_PRIMARY)
        .letterSpacing(0.6)
    }
    .width('100%')
    .height(this.btnHeight)
    .justifyContent(FlexAlign.Center)
    .borderRadius(R_MD)
    .backgroundColor(MINT)
    .opacity(this.enabledState ? 1 : 0.35)
    .shadow(this.enabledState ? SHADOW_GLOW : { radius: 0, color: 'rgba(0,0,0,0)' })
    .scale({ x: this.pressScale, y: this.pressScale })
    .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
    .onTouch((ev: TouchEvent) => {
      if (!this.enabledState) {
        return
      }
      if (ev.type === TouchType.Down) {
        this.pressScale = 0.98
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.pressScale = 1
      }
    })
    .onClick(() => {
      if (this.enabledState) {
        this.onTap()
      }
    })
  }
}
