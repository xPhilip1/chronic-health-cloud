import { UserInfo } from '../model/UserModel'
import { getDoctorList, bindDoctor, getMyDoctor } from '../service/ApiService'
import {
  BG_PAGE, CARD_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, ACCENT, OK,
  BRAND_A, BRAND_B, R_CARD, SHADOW_CARD
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { displayNameOf } from '../common/UserUtil'

@Entry
@Component
struct BindDoctorPage {
  @State doctors: UserInfo[] = []
  @State currentDoctorId: number = 0
  @State isLoading: boolean = true
  @State refreshing: boolean = false

  async aboutToAppear(): Promise<void> {
    await this.loadData()
  }

  // 拉取医生列表与当前绑定医生（首屏加载与下拉刷新共用）
  async loadData(): Promise<void> {
    this.doctors = await getDoctorList()
    let mine: UserInfo | null = await getMyDoctor()
    this.currentDoctorId = mine ? mine.userId : 0
    this.isLoading = false
  }

  getGenderLabel(g: string): string {
    if (g === 'male') {
      return '男'
    }
    if (g === 'female') {
      return '女'
    }
    return '其他'
  }

  async handleBind(doctorId: number): Promise<void> {
    try {
      let ok = await bindDoctor(doctorId)
      if (ok) {
        this.currentDoctorId = doctorId
        this.getUIContext().getPromptAction().showToast({ message: '绑定成功' })
        // 稍作停留后返回，让首页/个人中心刷新
        setTimeout(() => {
          try {
            this.getUIContext().getRouter().back()
          } catch (e) {
            console.error('返回失败: ' + (e as Error).message)
          }
        }, 800)
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '绑定失败' })
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '绑定失败：' + (e as Error).message })
    }
  }

  build() {
    Column() {
      NavBar({ title: '选择医生' })

      Text('选择一位医生作为您的主管医生，绑定后医生可以查看您的健康记录。')
        .fontSize(13)
        .fontColor(TEXT_SUB)
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(ACCENT)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.doctors.length === 0) {
        Column() {
          Image($r('app.media.ic_stethoscope'))
            .width(40)
            .height(40)
            .fillColor(TEXT_FAINT)
            .margin({ bottom: 10 })
          Text('暂无可绑定的医生')
            .fontSize(16)
            .fontColor(TEXT_SUB)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            List({ space: 12 }) {
              ForEach(this.doctors, (item: UserInfo) => {
            ListItem() {
              Row() {
                Stack({ alignContent: Alignment.Center }) {
                  if (item.avatarUrl !== '') {
                    Image(item.avatarUrl).width(46).height(46).objectFit(ImageFit.Cover)
                  } else {
                    Image($r('app.media.ic_avatar_doctor'))
                      .width(26)
                      .height(26)
                      .fillColor('#FFFFFF')
                  }
                }
                .width(46)
                .height(46)
                .borderRadius(15)
                .linearGradient({ angle: 135, colors: [[OK, 0], [BRAND_A, 1]] })

                Column() {
                  Text(displayNameOf(item.nickname, item.username) + ' 医生')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(TEXT_MAIN)
                  Text('性别：' + this.getGenderLabel(item.gender) +
                    (item.doctorLicense === '' ? '' : '　执业证号：' + item.doctorLicense))
                    .fontSize(12)
                    .fontColor(TEXT_SUB)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 12 })

                Blank()

                if (this.currentDoctorId === item.userId) {
                  Text('已绑定')
                    .fontSize(13)
                    .fontColor(OK)
                } else {
                  Text('绑定')
                    .fontSize(13)
                    .fontColor('#FFFFFF')
                    .backgroundColor(ACCENT)
                    .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                    .borderRadius(16)
                    .onClick(() => {
                      this.handleBind(item.userId)
                    })
                }
              }
              .width('100%')
              .padding(16)
              .backgroundColor(CARD_BG)
              .borderRadius(R_CARD)
              .shadow(SHADOW_CARD)
            }
          }, (item: UserInfo) => item.userId.toString())
            }
            .width('100%')
            .height('100%')
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20, bottom: 20 })
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
    .backgroundColor(BG_PAGE)
  }
}
