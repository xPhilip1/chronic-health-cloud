import { login } from '../service/ApiService'
import { UserInfo } from '../model/UserModel'
import {
  CANVAS, INK, INK_SUB, INK_FAINT, MINT, MINT_SOFT, DANGER, HAIRLINE,
  T_DISPLAY, T_BODY, T_SM, T_MICRO, T_CAP, TRACK_LABEL, R_SM, R_PILL
} from '../common/Theme'
import { GradientButton } from '../components/GradientButton'

@Entry
@Component
struct LoginPage {
  @State username: string = ''
  @State password: string = ''
  @State errorMsg: string = ''
  @State isLoading: boolean = false
  @State contentIn: boolean = false

  aboutToAppear(): void {
    setTimeout(() => {
      this.contentIn = true
    }, 60)
  }

  async handleLogin(): Promise<void> {
    if (this.username.trim() == '' || this.password == '') {
      this.errorMsg = '请输入用户名和密码'
      return
    }
    this.isLoading = true
    this.errorMsg = ''
    try {
      let user: UserInfo | null = await login(this.username.trim(), this.password)
      if (user) {
        this.getUIContext().getRouter().replaceUrl({ url: 'pages/HomePage' })
      } else {
        this.errorMsg = '登录失败，请重试'
      }
    } catch (e) {
      this.errorMsg = (e as Error).message
    } finally {
      this.isLoading = false
    }
  }

  // 下划线式输入：深色界面上用底部一条发丝线代替输入框盒子，更安静
  @Builder
  underlineField(label: string, value: string, placeholder: string, isPwd: boolean, onChange: (v: string) => void) {
    Column() {
      Text(label)
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .letterSpacing(TRACK_LABEL)
        .width('100%')

      TextInput({ text: value, placeholder: placeholder })
        .width('100%')
        .height(46)
        .fontSize(T_BODY)
        .fontColor(INK)
        .placeholderColor('#8B9893')
        .type(isPwd ? InputType.Password : InputType.Normal)
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0 })
        .onChange(onChange)
        .onSubmit(() => {
          if (!this.isLoading) {
            this.handleLogin()
          }
        })

      Divider().color(HAIRLINE).strokeWidth(1)
    }
    .width('100%')
    .margin({ top: 26 })
  }

  build() {
    Column() {
      // 顶部字标
      Row() {
        Circle()
          .width(5)
          .height(5)
          .fill(MINT)
          .shadow({ radius: 12, color: 'rgba(15, 122, 92, 0.45)', offsetX: 0, offsetY: 0 })
        Text('CHRONICCLOUD')
          .fontSize(T_MICRO)
          .fontColor(INK_SUB)
          .letterSpacing(3.4)
          .margin({ left: 9 })
      }
      .width('100%')
      .opacity(this.contentIn ? 1 : 0)
      .animation({ duration: 380, curve: Curve.FastOutSlowIn })

      Column() {
        Text('欢迎回来')
          .fontSize(T_DISPLAY)
          .fontWeight(FontWeight.Medium)
          .fontColor(INK)
          .letterSpacing(0.5)
        Text('登录后继续记录与管理你的健康数据')
          .fontSize(T_SM)
          .fontColor(INK_FAINT)
          .margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 56 })
      .translate({ y: this.contentIn ? 0 : 12 })
      .opacity(this.contentIn ? 1 : 0)
      .animation({ duration: 520, curve: Curve.FastOutSlowIn })

      // 表单
      Column() {
        this.underlineField('用 户 名', this.username, '请输入用户名', false, (v: string) => {
          this.username = v
          this.errorMsg = ''
        })
        this.underlineField('密 码', this.password, '请输入密码', true, (v: string) => {
          this.password = v
          this.errorMsg = ''
        })

        if (this.errorMsg !== '') {
          Text(this.errorMsg)
            .fontSize(T_CAP)
            .fontColor(DANGER)
            .width('100%')
            .margin({ top: 14 })
        }

        Column() {
          GradientButton({
            text: this.isLoading ? '登录中…' : '登 录',
            enabledState: !this.isLoading,
            btnHeight: 52,
            onTap: () => {
              this.handleLogin()
            }
          })
        }
        .width('100%')
        .margin({ top: 36 })
      }
      .width('100%')
      .translate({ y: this.contentIn ? 0 : 16 })
      .opacity(this.contentIn ? 1 : 0)
      .animation({ duration: 560, curve: Curve.FastOutSlowIn })

      Blank()

      // 注册入口
      Row() {
        Text('还没有账号')
          .fontSize(T_SM)
          .fontColor(INK_FAINT)
        Text('创建账号')
          .fontSize(T_SM)
          .fontWeight(FontWeight.Medium)
          .fontColor(MINT)
          .letterSpacing(0.4)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .backgroundColor(MINT_SOFT)
          .borderRadius(R_PILL)
          .margin({ left: 6 })
          .onClick(() => {
            try {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/RegisterPage' })
            } catch (e) {
              console.error('跳转失败: ' + (e as Error).message)
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      Text('健康管理辅助工具 · 不替代医生诊断')
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .letterSpacing(0.6)
        .width('100%')
        .margin({ top: 16, bottom: 4 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 32, right: 32, top: 56, bottom: 28 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(CANVAS)
  }
}
