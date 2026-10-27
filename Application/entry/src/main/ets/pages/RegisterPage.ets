import { register, probeUsername } from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_SUNK, INK, INK_SUB, INK_FAINT, JADE, JADE_SOFT, HAIRLINE, DANGER, OK,
  R_LG, R_MD, R_PILL, T_H1, T_BODY, T_SM, T_CAP, T_MICRO, D_BASE
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { GradientButton } from '../components/GradientButton'

@Entry
@Component
struct RegisterPage {
  @State username: string = ''
  @State password: string = ''
  @State confirmPassword: string = ''
  @State role: string = 'patient'
  @State license: string = ''
  @State errorMsg: string = ''
  @State isSubmitting: boolean = false
  @State nameTip: string = ''
  @State checkingName: boolean = false
  @State formIn: boolean = false

  aboutToAppear(): void {
    setTimeout(() => {
      this.formIn = true
    }, 60)
  }

  // 用户名失焦时预检查是否已被占用（最终能否注册仍由服务端裁决）
  async probeName(): Promise<void> {
    let n: string = this.username.trim()
    if (n === '') {
      this.nameTip = ''
      return
    }
    this.checkingName = true
    let tip: string = await probeUsername(n)
    if (this.username.trim() === n) {
      this.nameTip = tip
    }
    this.checkingName = false
  }

  async handleRegister(): Promise<void> {
    this.errorMsg = ''

    let name: string = this.username.trim()
    if (name === '' || this.password === '') {
      this.errorMsg = '请填写用户名和密码'
      return
    }
    if (name.length < 3 || name.length > 20) {
      this.errorMsg = '用户名长度需在 3-20 个字符之间'
      return
    }
    if (this.password.length < 6) {
      this.errorMsg = '密码至少6位'
      return
    }
    if (this.password !== this.confirmPassword) {
      this.errorMsg = '两次密码不一致'
      return
    }
    // 医生必须填写执业证号，注册后等待管理员审核
    let lic: string = this.license.trim()
    if (this.role === 'doctor' && lic.length < 6) {
      this.errorMsg = '请填写有效的执业证号（至少 6 位）'
      return
    }

    this.isSubmitting = true
    try {
      let ok: boolean = await register(name, this.password, this.role, lic)
      if (ok) {
        try {
          let tip: string = this.role === 'doctor' ? '注册成功，医生资质待管理员审核' : '注册成功，请登录'
          this.getUIContext().getPromptAction().showToast({ message: tip })
        } catch (e) {
          console.error('提示失败: ' + (e as Error).message)
        }
        setTimeout(() => {
          try {
            this.getUIContext().getRouter().back()
          } catch (e) {
            console.error('返回失败: ' + (e as Error).message)
          }
        }, 800)
      } else {
        this.errorMsg = '用户名已存在'
      }
    } catch (e) {
      let msg: string = (e as Error).message
      this.errorMsg = (msg === '' || msg === undefined) ? '注册失败，请稍后重试' : msg
    } finally {
      this.isSubmitting = false
    }
  }

  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(T_CAP)
      .fontColor(INK_FAINT)
      .letterSpacing(0.5)
      .alignSelf(ItemAlign.Start)
      .margin({ bottom: 8 })
  }

  @Builder
  roleOption(label: string, value: string, desc: string) {
    Column() {
      Text(label)
        .fontSize(T_BODY)
        .fontWeight(this.role === value ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.role === value ? JADE : INK_SUB)
      Text(desc)
        .fontSize(T_MICRO)
        .fontColor(this.role === value ? JADE : INK_FAINT)
        .opacity(this.role === value ? 0.8 : 1)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.role === value ? SURFACE : Color.Transparent)
    .borderRadius(R_MD)
    .border({ width: this.role === value ? 1 : 0, color: JADE_SOFT })
    .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      this.role = value
    })
  }

  build() {
    Column() {
      NavBar({ title: '创建账号' })

      Scroll() {
        Column() {
          Text('创建你的账号')
            .fontSize(T_H1)
            .fontWeight(FontWeight.Medium)
            .fontColor(INK)
            .width('100%')

          Text('患者用于记录健康数据，医生用于查看绑定患者')
            .fontSize(T_SM)
            .fontColor(INK_FAINT)
            .width('100%')
            .margin({ top: 8 })

          // 身份选择
          this.fieldLabel('身份')
          Row() {
            this.roleOption('患者', 'patient', '记录与查看自己的数据')
            this.roleOption('医生', 'doctor', '查看绑定患者的数据')
          }
          .width('100%')
          .padding(4)
          .backgroundColor(SURFACE_SUNK)
          .borderRadius(R_MD)
          .margin({ top: 2 })

          // 医生：执业证号（必填，注册后进入待审核状态）
          if (this.role === 'doctor') {
            Column() {
              this.fieldLabel('执业证号')
              TextInput({ placeholder: '请输入医师执业证书编号', text: this.license })
                .height(52)
                .fontSize(T_BODY)
                .fontColor(INK)
                .placeholderColor(INK_FAINT)
                .backgroundColor(CANVAS)
                .borderRadius(R_MD)
                .border({ width: 1, color: HAIRLINE })
                .padding({ left: 14, right: 14 })
                .maxLength(40)
                .onChange((v: string) => {
                  this.license = v
                  this.errorMsg = ''
                })
              Text('医生账号需管理员审核资质，通过后才能查看绑定患者的数据')
                .fontSize(T_MICRO)
                .fontColor(INK_FAINT)
                .lineHeight(16)
                .margin({ top: 8 })
                .alignSelf(ItemAlign.Start)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 18 })
          }

          // 用户名
          Column() {
            this.fieldLabel('用户名')
            TextInput({ placeholder: '3-20 位，不含空格', text: this.username })
              .height(52)
              .fontSize(T_BODY)
              .fontColor(INK)
              .placeholderColor(INK_FAINT)
              .backgroundColor(CANVAS)
              .borderRadius(R_MD)
              .border({ width: 1, color: HAIRLINE })
              .padding({ left: 14, right: 14 })
              .maxLength(20)
              .onChange((v: string) => {
                this.username = v
                this.nameTip = ''
                this.errorMsg = ''
              })
              .onBlur(() => {
                this.probeName()
              })

            if (this.nameTip !== '') {
              Text(this.nameTip)
                .fontSize(T_MICRO)
                .fontColor(DANGER)
                .margin({ top: 6 })
                .alignSelf(ItemAlign.Start)
            } else if (this.checkingName) {
              Text('正在检查用户名…')
                .fontSize(T_MICRO)
                .fontColor(INK_FAINT)
                .margin({ top: 6 })
                .alignSelf(ItemAlign.Start)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 20 })

          // 密码
          Column() {
            this.fieldLabel('密码')
            TextInput({ placeholder: '至少 6 位', text: this.password })
              .type(InputType.Password)
              .height(52)
              .fontSize(T_BODY)
              .fontColor(INK)
              .placeholderColor(INK_FAINT)
              .backgroundColor(CANVAS)
              .borderRadius(R_MD)
              .border({ width: 1, color: HAIRLINE })
              .padding({ left: 14, right: 14 })
              .onChange((v: string) => {
                this.password = v
                this.errorMsg = ''
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 18 })

          // 确认密码
          Column() {
            this.fieldLabel('确认密码')
            TextInput({ placeholder: '再输入一次', text: this.confirmPassword })
              .type(InputType.Password)
              .height(52)
              .fontSize(T_BODY)
              .fontColor(INK)
              .placeholderColor(INK_FAINT)
              .backgroundColor(CANVAS)
              .borderRadius(R_MD)
              .border({ width: 1, color: HAIRLINE })
              .padding({ left: 14, right: 14 })
              .onChange((v: string) => {
                this.confirmPassword = v
                this.errorMsg = ''
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 18 })

          if (this.errorMsg !== '') {
            Row() {
              Circle()
                .width(4)
                .height(4)
                .fill(DANGER)
              Text(this.errorMsg)
                .fontSize(T_SM)
                .fontColor(DANGER)
                .margin({ left: 7 })
                .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 14 })
            .alignItems(VerticalAlign.Center)
          }

          Column() {
            GradientButton({
              text: this.isSubmitting ? '注册中…' : '注 册',
              enabledState: !this.isSubmitting,
              onTap: () => {
                this.handleRegister()
              }
            })
          }
          .width('100%')
          .margin({ top: 26 })

          Text('注册即表示你已阅读并同意《隐私与免责声明》')
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 14, bottom: 32 })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 12 })
        .translate({ y: this.formIn ? 0 : 14 })
        .opacity(this.formIn ? 1 : 0)
        .animation({ duration: 460, curve: Curve.FastOutSlowIn })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }
}
