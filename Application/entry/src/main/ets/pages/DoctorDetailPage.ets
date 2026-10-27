import { UserInfo } from '../model/UserModel'
import { getUserById, getPatientsByDoctor, getCurrentUser, reviewDoctor } from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_SUNK, HAIRLINE, INK, INK_SUB, INK_FAINT,
  JADE, JADE_SOFT, M_SUGAR, DANGER, DANGER_SOFT, WARN, R_LG, R_MD, R_PILL, R_XS,
  T_H2, T_H3, T_BODY, T_SM, T_CAP, T_MICRO
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { StateView } from '../components/StateView'
import { resolveAvatar } from '../common/Avatar'
import { displayNameOf } from '../common/UserUtil'

@Entry
@Component
struct DoctorDetailPage {
  @State doctor: UserInfo | null = null
  @State patients: UserInfo[] = []
  @State isLoading: boolean = true
  @State refreshing: boolean = false
  @State reviewing: boolean = false
  private targetUserId: number = 0
  private myUserId: number = 0
  private myRole: string = 'patient'

  async aboutToAppear(): Promise<void> {
    let params = this.getUIContext().getRouter().getParams() as Record<string, number>
    if (params !== null && params !== undefined) {
      this.targetUserId = params['userId']
    }
    let cur: UserInfo | null = await getCurrentUser()
    if (cur !== null) {
      this.myUserId = cur.userId
      this.myRole = cur.role
    }
    await this.loadData()
  }

  canDm(): boolean {
    if (this.doctor === null) {
      return false
    }
    if (this.myRole === 'admin') {
      return false
    }
    return this.doctor.userId !== this.myUserId
  }

  openDm(): void {
    if (this.doctor === null) {
      return
    }
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatPage',
        params: {
          peerId: this.doctor!.userId,
          peerName: displayNameOf(this.doctor!.nickname, this.doctor!.username),
          peerAvatar: this.doctor!.avatarUrl
        }
      })
    } catch (e) {
      console.error('打开私信失败: ' + (e as Error).message)
    }
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    await this.fetchDetail()
    this.isLoading = false
  }

  async refreshData(): Promise<void> {
    await this.fetchDetail()
  }

  async fetchDetail(): Promise<void> {
    this.doctor = await getUserById(this.targetUserId)
    this.patients = await getPatientsByDoctor(this.targetUserId)
  }

  // 管理员审核：通过后该医生才能看到患者数据；驳回会同时解绑其名下患者
  async handleReview(pass: boolean): Promise<void> {
    if (this.doctor === null || this.reviewing) {
      return
    }
    this.reviewing = true
    let err: string = await reviewDoctor(this.doctor.userId, pass)
    this.reviewing = false
    if (err !== '') {
      this.getUIContext().getPromptAction().showToast({ message: err })
      return
    }
    this.getUIContext().getPromptAction().showToast({ message: pass ? '已通过审核' : '已驳回该医生' })
    await this.loadData()
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

  goPatientDetail(userId: number): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/PatientDetailPage',
        params: { userId: userId }
      })
    } catch (e) {
      console.error('跳转失败: ' + (e as Error).message)
    }
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(T_SM)
        .fontColor(INK_FAINT)
      Blank()
      Text(value)
        .fontSize(T_SM)
        .fontColor(INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  build() {
    Column() {
      NavBar({ title: '医生详情' })

      if (this.isLoading) {
        Column() {
          StateView({ kind: 'loading', title: '正在加载' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.doctor === null) {
        Column() {
          StateView({ kind: 'empty', title: '医生不存在', desc: '该账号可能已被删除' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              // 名片
              Column() {
                Row() {
                  Stack({ alignContent: Alignment.Center }) {
                    if (this.doctor !== null && this.doctor!.avatarUrl !== '') {
                      Image(this.doctor!.avatarUrl).width(58).height(58).objectFit(ImageFit.Cover)
                    } else {
                      Image($r('app.media.ic_avatar_doctor'))
                        .width(28)
                        .height(28)
                        .fillColor('#FFFFFF')
                    }
                  }
                  .width(58)
                  .height(58)
                  .borderRadius(29)
                  .backgroundColor(M_SUGAR)

                  Column() {
                    Text(displayNameOf(this.doctor!.nickname, this.doctor!.username))
                      .fontSize(T_H2)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(INK)
                    Row() {
                      Text('主管医生 · ' + this.getGenderLabel(this.doctor!.gender))
                        .fontSize(T_MICRO)
                        .fontColor(INK_FAINT)
                      if (this.doctor!.doctorStatus === 'pending') {
                        Text('待审核')
                          .fontSize(T_MICRO)
                          .fontColor(WARN)
                          .backgroundColor('rgba(154, 109, 37, 0.10)')
                          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                          .borderRadius(R_XS)
                          .margin({ left: 8 })
                      } else if (this.doctor!.doctorStatus === 'rejected') {
                        Text('已驳回')
                          .fontSize(T_MICRO)
                          .fontColor(DANGER)
                          .backgroundColor(DANGER_SOFT)
                          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                          .borderRadius(R_XS)
                          .margin({ left: 8 })
                      }
                    }
                    .margin({ top: 5 })
                    .alignItems(VerticalAlign.Center)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 14 })

                  if (this.canDm()) {
                    Text('私信')
                      .fontSize(T_CAP)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(JADE)
                      .backgroundColor(JADE_SOFT)
                      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                      .borderRadius(R_PILL)
                      .onClick(() => { this.openDm() })
                  }
                }
                .width('100%')

                Divider().color(HAIRLINE).strokeWidth(1).margin({ top: 16, bottom: 4 })

                this.infoRow('执业执照号', this.doctor!.doctorLicense !== '' ? this.doctor!.doctorLicense : '暂无')
                Divider().color(HAIRLINE).strokeWidth(1).opacity(0.6)
                this.infoRow('联系电话', this.doctor!.phone !== '' ? this.doctor!.phone : '暂无')
                Divider().color(HAIRLINE).strokeWidth(1).opacity(0.6)
                this.infoRow('邮箱', this.doctor!.email !== '' ? this.doctor!.email : '暂无')
              }
              .width('100%')
              .padding({ left: 18, right: 18, top: 18, bottom: 6 })
              .backgroundColor(SURFACE)
              .borderRadius(R_LG)
              .border({ width: 1, color: HAIRLINE })

              // 管理员审核区：只有未通过的医生才显示
              if (this.myRole === 'admin' && this.doctor!.doctorStatus !== 'approved') {
                Column() {
                  Row() {
                    Text('资质审核')
                      .fontSize(T_H3)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(INK)
                    Blank()
                    Text(this.doctor!.doctorStatus === 'pending' ? '待审核' : '已驳回')
                      .fontSize(T_MICRO)
                      .fontColor(this.doctor!.doctorStatus === 'pending' ? WARN : DANGER)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)

                  Text('该医生尚未通过资质审核，当前看不到任何患者数据；患者也无法绑定到他名下。')
                    .fontSize(T_CAP)
                    .fontColor(INK_SUB)
                    .lineHeight(20)
                    .width('100%')
                    .margin({ top: 8 })

                  if (this.doctor!.doctorStatus === 'rejected') {
                    Text('驳回原因请联系本人线下补充材料后重新注册。')
                      .fontSize(T_MICRO)
                      .fontColor(INK_FAINT)
                      .width('100%')
                      .margin({ top: 6 })
                  }

                  Row() {
                    Text(this.reviewing ? '处理中…' : '通过审核')
                      .fontSize(T_CAP)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#FFFFFF')
                      .textAlign(TextAlign.Center)
                      .layoutWeight(1)
                      .height(40)
                      .borderRadius(R_MD)
                      .backgroundColor(JADE)
                      .opacity(this.reviewing ? 0.5 : 1)
                      .onClick(() => {
                        if (!this.reviewing) { this.handleReview(true) }
                      })

                    Text('驳回')
                      .fontSize(T_CAP)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(DANGER)
                      .textAlign(TextAlign.Center)
                      .layoutWeight(1)
                      .height(40)
                      .borderRadius(R_MD)
                      .border({ width: 1, color: DANGER_SOFT })
                      .backgroundColor(DANGER_SOFT)
                      .margin({ left: 10 })
                      .opacity(this.reviewing ? 0.5 : 1)
                      .onClick(() => {
                        if (!this.reviewing) { this.handleReview(false) }
                      })
                  }
                  .width('100%')
                  .margin({ top: 14 })
                }
                .width('100%')
                .padding(18)
                .backgroundColor(SURFACE)
                .borderRadius(R_LG)
                .border({ width: 1, color: HAIRLINE })
                .margin({ top: 12 })
                .alignItems(HorizontalAlign.Start)
              }

              // 名下患者
              Column() {
                Row() {
                  Text('名下患者')
                    .fontSize(T_H3)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(INK)
                  Blank()
                  Text(this.patients.length + ' 人')
                    .fontSize(T_MICRO)
                    .fontColor(INK_FAINT)
                }
                .width('100%')
                .margin({ bottom: 12 })

                if (this.patients.length === 0) {
                  Text('该医生名下还没有绑定患者')
                    .fontSize(T_SM)
                    .fontColor(INK_FAINT)
                    .width('100%')
                } else {
                  ForEach(this.patients, (item: UserInfo, idx: number) => {
                    Row() {
                      Stack({ alignContent: Alignment.Center }) {
                        if (item.avatarUrl !== undefined && item.avatarUrl !== '') {
                          Image(item.avatarUrl).width(38).height(38).objectFit(ImageFit.Cover)
                        } else {
                          Image(resolveAvatar(item.gender, item.role))
                            .width(18)
                            .height(18)
                            .fillColor('#FFFFFF')
                        }
                      }
                      .width(38)
                      .height(38)
                      .borderRadius(19)
                      .clip(true)
                      .backgroundColor(JADE)

                      Column() {
                        Text(displayNameOf(item.nickname, item.username))
                          .fontSize(T_SM)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(INK)
                        Text('性别 ' + this.getGenderLabel(item.gender))
                          .fontSize(T_MICRO)
                          .fontColor(INK_FAINT)
                          .margin({ top: 3 })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)
                      .margin({ left: 12 })

                      Image($r('app.media.ic_arrow_right'))
                        .width(14)
                        .height(14)
                        .fillColor(INK_FAINT)
                    }
                    .width('100%')
                    .padding({ top: 10, bottom: 10 })
                    .border({ width: { top: idx === 0 ? 0 : 1 }, color: HAIRLINE })
                    .onClick(() => {
                      this.goPatientDetail(item.userId)
                    })
                  }, (item: UserInfo) => item.userId.toString())
                }
              }
              .width('100%')
              .padding(18)
              .backgroundColor(SURFACE)
              .borderRadius(R_LG)
              .border({ width: 1, color: HAIRLINE })
              .margin({ top: 12, bottom: 24 })
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 4 })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .onRefreshing(async () => {
          await this.refreshData()
          this.refreshing = false
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }
}
