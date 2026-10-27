import { UserInfo } from '../model/UserModel'
import { DmConversation } from '../model/ForumModel'
import { getCurrentUser, listMyConversations } from '../service/ApiService'
import {
  CANVAS, INK, INK_SUB, INK_FAINT, HAIRLINE, MINT, MINT_SOFT, DANGER,
  T_H1, T_BODY, T_SM, T_CAP, T_MICRO, TRACK_LABEL, R_XS
} from '../common/Theme'
import { BottomNav } from '../components/BottomNav'
import { StateView } from '../components/StateView'

@Entry
@Component
struct MessagePage {
  @State isPatient: boolean = true
  @State isAdmin: boolean = false
  @State conversations: DmConversation[] = []
  @State refreshing: boolean = false
  @State isLoading: boolean = true

  async aboutToAppear(): Promise<void> {
    await this.loadData()
  }

  async onPageShow(): Promise<void> {
    await this.fetchList()
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    await this.fetchList()
    this.isLoading = false
  }

  async fetchList(): Promise<void> {
    let cur: UserInfo | null = await getCurrentUser()
    if (cur !== null) {
      this.isPatient = cur.role === 'patient'
      this.isAdmin = cur.role === 'admin'
    }
    if (this.isAdmin) {
      this.conversations = []
      return
    }
    this.conversations = await listMyConversations()
  }

  async onRefresh(): Promise<void> {
    await this.fetchList()
    this.refreshing = false
  }

  formatTime(iso: string): string {
    if (iso === '' || iso.length < 16) {
      return iso
    }
    return iso.substring(5, 10) + ' ' + iso.substring(11, 16)
  }

  openChat(c: DmConversation): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/ChatPage',
        params: { peerId: c.peerId, peerName: c.peerName, peerAvatar: c.peerAvatar }
      })
    } catch (e) {
      console.error('打开聊天失败: ' + (e as Error).message)
    }
  }

  @Builder
  headerBar() {
    Column() {
      Text('消息')
        .fontSize(T_H1)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
        .letterSpacing(0.4)
        .width('100%')
      Text(this.isAdmin ? '管理员不使用私信' : '与医生、病友保持联系')
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .letterSpacing(TRACK_LABEL)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  convRow(c: DmConversation) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        if (c.peerAvatar !== undefined && c.peerAvatar !== '') {
          Image(c.peerAvatar).width(42).height(42).objectFit(ImageFit.Cover)
        } else {
          Image($r('app.media.ic_user'))
            .width(17)
            .height(17)
            .fillColor(MINT)
        }
      }
      .width(42)
      .height(42)
      .borderRadius(21)
      .backgroundColor(MINT_SOFT)
      .clip(true)

      Column() {
        Row() {
          Text(c.peerName)
            .fontSize(T_BODY)
            .fontColor(INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.formatTime(c.lastCreatedAt))
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .margin({ left: 8 })
        }
        .width('100%')

        Row() {
          Text(c.lastMessage === '' ? '暂无消息' : c.lastMessage)
            .fontSize(T_SM)
            .fontColor(c.unread > 0 ? INK_SUB : INK_FAINT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (c.unread > 0) {
            Text(c.unread > 99 ? '99+' : c.unread.toString())
              .fontSize(9)
              .fontColor('#FFFFFF')
              .textAlign(TextAlign.Center)
              .height(16)
              .constraintSize({ minWidth: 16 })
              .padding({ left: 4, right: 4 })
              .borderRadius(8)
              .backgroundColor(MINT)
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .margin({ top: 5 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 15, bottom: 15 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => { this.openChat(c) })
  }

  build() {
    Column() {
      this.headerBar()

      if (this.isLoading) {
        Column() {
          StateView({ kind: 'loading', title: '正在读取会话' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.isAdmin) {
        Column() {
          StateView({
            kind: 'empty',
            title: '管理员不使用私信',
            desc: '私信仅在患者与医生之间开放',
            icon: $r('app.media.ic_message')
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.conversations.length === 0) {
        Column() {
          StateView({
            kind: 'empty',
            title: '还没有消息',
            desc: '在帖子或用户资料页点「私信」即可开始',
            icon: $r('app.media.ic_message')
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          List() {
            ForEach(this.conversations, (c: DmConversation) => {
              ListItem() {
                Column() {
                  this.convRow(c)
                  Divider().color(HAIRLINE).strokeWidth(1).margin({ left: 24, right: 24 })
                }
              }
            }, (c: DmConversation) => c.pairId + '_' + c.unread.toString() + '_' + c.lastCreatedAt)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .onRefreshing(() => { this.onRefresh() })
      }

      BottomNav({ current: 'message', isPatient: this.isPatient })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }
}
