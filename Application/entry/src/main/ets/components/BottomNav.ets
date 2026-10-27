import {
  SURFACE, CANVAS, INK_FAINT, MINT, MINT_SOFT, ON_PRIMARY, HAIRLINE, DANGER,
  D_BASE, SHADOW_GLOW
} from '../common/Theme'
import { getDmUnreadTotal } from '../service/ApiService'

// 底部导航 v2：通栏深色条 + 顶部发丝线（不再是悬浮胶囊）。
// 选中项：薄荷色图标 + 上方一枚 3px 光点；中间仍是最大的"添加"圆钮。
// 圆钮尺寸收在 76 高的条内（54 + 上下留白 11），不会被容器裁切。
@Component
export struct BottomNav {
  @Prop current: string = 'home'
  @Prop isPatient: boolean = true
  @State plusScale: number = 1
  @State unread: number = 0

  async aboutToAppear(): Promise<void> {
    try {
      this.unread = await getDmUnreadTotal()
    } catch (e) {
      this.unread = 0
    }
  }

  switchTo(url: string, key: string): void {
    if (this.current === key) {
      return
    }
    try {
      this.getUIContext().getRouter().replaceUrl({ url: url })
    } catch (e) {
      console.error('底部导航跳转失败: ' + (e as Error).message)
    }
  }

  goAddData(): void {
    if (!this.isPatient) {
      this.getUIContext().getPromptAction().showToast({ message: '添加健康数据仅对患者开放' })
      return
    }
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/AddDataPage' })
    } catch (e) {
      console.error('跳转添加数据失败: ' + (e as Error).message)
    }
  }

  @Builder
  buildItem(key: string, label: string, icon: Resource, url: string) {
    Column() {
      // 选中光点
      Column()
        .width(4)
        .height(4)
        .borderRadius(2)
        .backgroundColor(this.current === key ? MINT : 'rgba(0,0,0,0)')
        .margin({ bottom: 6 })
        .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })

      Stack({ alignContent: Alignment.TopEnd }) {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(this.current === key ? MINT : INK_FAINT)
        if (key === 'message' && this.unread > 0 && this.current !== 'message') {
          Text(this.unread > 99 ? '99+' : this.unread.toString())
            .fontSize(8)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .height(13)
            .constraintSize({ minWidth: 13 })
            .padding({ left: 3, right: 3 })
            .borderRadius(7)
            .backgroundColor(DANGER)
            .margin({ top: -5, right: -8 })
        }
      }
      .width(22)
      .height(22)

      Text(label)
        .fontSize(10)
        .fontColor(this.current === key ? MINT : INK_FAINT)
        .letterSpacing(0.5)
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.switchTo(url, key)
    })
  }

  @Builder
  buildCenterAdd() {
    Column() {
      Row() {
        Image($r('app.media.ic_data_add'))
          .width(22)
          .height(22)
          .fillColor(ON_PRIMARY)
      }
      .width(54)
      .height(54)
      .justifyContent(FlexAlign.Center)
      .borderRadius(27)
      .backgroundColor(MINT)
      .shadow(SHADOW_GLOW)
      .scale({ x: this.plusScale, y: this.plusScale })
      .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
      .onTouch((ev: TouchEvent) => {
        if (ev.type === TouchType.Down) {
          this.plusScale = 0.92
        } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
          this.plusScale = 1
        }
      })
      .onClick(() => {
        this.goAddData()
      })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Divider()
        .color(HAIRLINE)
        .strokeWidth(1)

      Row() {
        this.buildItem('home', '首页', $r('app.media.ic_heart'), 'pages/HomePage')
        this.buildItem('forum', '社区', $r('app.media.ic_lightbulb'), 'pages/ForumPage')
        this.buildCenterAdd()
        this.buildItem('message', '消息', $r('app.media.ic_message'), 'pages/MessagePage')
        this.buildItem('mine', '我的', $r('app.media.ic_user'), 'pages/ProfilePage')
      }
      .width('100%')
      .height(76)
      .padding({ left: 4, right: 4 })
    }
    .width('100%')
    .backgroundColor(SURFACE)
    .clip(false)
  }
}
