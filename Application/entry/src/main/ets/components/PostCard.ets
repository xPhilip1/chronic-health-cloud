// 论坛条目 v2：不再是"一张卡一个框"，而是无边框信息流（通栏 + 发丝分隔线）。
// 作者行压缩、标题放大、正文两行，标签退化成一枚小圆点 + 文字，密度更高也更像内容社区。
import { ForumPost, parseMediaUrls, parseTopics } from '../model/ForumModel'
import {
  CANVAS, INK, INK_SUB, INK_FAINT, MINT, MINT_SOFT, AMBER, DANGER,
  HAIRLINE, SURFACE_2, R_SM, R_PILL, T_H3, T_SM, T_CAP, T_MICRO, TRACK_LABEL
} from '../common/Theme'
import { resolveAvatar } from '../common/Avatar'

@Component
export struct PostCard {
  @Prop post: ForumPost
  onLike: (post: ForumPost) => void = () => {}
  onOpen: (post: ForumPost) => void = () => {}

  @State pressOpacity: number = 1

  formatTime(iso: string): string {
    if (iso === '' || iso.length < 16) {
      return iso
    }
    return iso.substring(5, 10) + ' ' + iso.substring(11, 16)
  }

  roleLabel(role: string): string {
    if (role === 'doctor') {
      return '医生'
    }
    if (role === 'admin') {
      return '管理员'
    }
    return '病友'
  }

  build() {
    Column() {
      // 作者行
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          if (this.post.authorAvatar !== undefined && this.post.authorAvatar !== '') {
            Image(this.post.authorAvatar)
              .width(26)
              .height(26)
              .objectFit(ImageFit.Cover)
          } else {
            Image(resolveAvatar('', this.post.authorRole))
              .width(16)
              .height(16)
              .fillColor(this.post.authorRole === 'doctor' ? '#FFFFFF' : MINT)
          }
        }
        .width(26)
        .height(26)
        .borderRadius(13)
        .backgroundColor(this.post.authorRole === 'doctor' ? MINT : MINT_SOFT)
        .clip(true)

        Text(this.post.authorName)
          .fontSize(12.5)
          .fontColor(INK)
          .margin({ left: 8 })

        Text(this.roleLabel(this.post.authorRole))
          .fontSize(9.5)
          .fontColor(this.post.authorRole === 'doctor' ? MINT : INK_FAINT)
          .border({ width: 1, color: this.post.authorRole === 'doctor' ? 'rgba(15, 122, 92, 0.30)' : HAIRLINE })
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .borderRadius(R_PILL)
          .margin({ left: 6 })

        Blank()

        if (this.post.status === 1) {
          Text('已删除')
            .fontSize(9.5)
            .fontColor(INK_FAINT)
            .margin({ right: 8 })
        }

        Text(this.formatTime(this.post.createdAt))
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .letterSpacing(0.4)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 标题
      Text(this.post.title)
        .fontSize(T_H3)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 12 })

      // 正文
      if (this.post.content !== '') {
        Text(this.post.content)
          .fontSize(T_SM)
          .fontColor(this.post.status === 1 ? INK_FAINT : INK_SUB)
          .lineHeight(20)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 7 })
      }

      // 标签：一枚圆点 + 文字，弱化存在感
      if (this.post.dept !== '' || parseTopics(this.post.topics).length > 0) {
        Row() {
          if (this.post.dept !== '') {
            Circle().width(4).height(4).fill(MINT)
            Text(this.post.dept)
              .fontSize(T_MICRO)
              .fontColor(MINT)
              .letterSpacing(0.4)
              .margin({ left: 5, right: 12 })
          }
          ForEach(parseTopics(this.post.topics), (tp: string) => {
            Circle().width(4).height(4).fill(AMBER)
            Text(tp)
              .fontSize(T_MICRO)
              .fontColor(AMBER)
              .letterSpacing(0.4)
              .margin({ left: 5, right: 12 })
          }, (tp: string) => tp)
        }
        .width('100%')
        .margin({ top: 10 })
        .alignItems(VerticalAlign.Center)
      }

      // 图片
      if (parseMediaUrls(this.post.mediaUrls).length > 0) {
        Row({ space: 6 }) {
          ForEach(parseMediaUrls(this.post.mediaUrls), (url: string) => {
            Image(url)
              .layoutWeight(1)
              .height(104)
              .objectFit(ImageFit.Cover)
              .borderRadius(R_SM)
              .backgroundColor(SURFACE_2)
          }, (url: string) => url)
        }
        .width('100%')
        .margin({ top: 12 })
      }

      // 互动
      Row() {
        Row() {
          Image($r('app.media.ic_heart'))
            .width(14)
            .height(14)
            .fillColor(this.post.likedByMe ? DANGER : INK_FAINT)
          Text(this.post.likeCount.toString())
            .fontSize(T_CAP)
            .fontColor(this.post.likedByMe ? DANGER : INK_FAINT)
            .margin({ left: 6 })
        }
        .padding({ top: 4, bottom: 4, right: 22 })
        .onClick(() => {
          this.onLike(this.post)
        })

        Row() {
          Image($r('app.media.ic_lightbulb'))
            .width(13)
            .height(13)
            .fillColor(INK_FAINT)
          Text(this.post.commentCount.toString())
            .fontSize(T_CAP)
            .fontColor(INK_FAINT)
            .margin({ left: 6 })
        }

        Blank()
      }
      .width('100%')
      .margin({ top: 14 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .color(HAIRLINE)
        .strokeWidth(1)
        .margin({ top: 16 })
    }
    .width('100%')
    .padding({ top: 18 })
    .opacity(this.post.status === 1 ? 0.45 : this.pressOpacity)
    .alignItems(HorizontalAlign.Start)
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.pressOpacity = 0.62
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.pressOpacity = 1
      }
    })
    .onClick(() => {
      this.onOpen(this.post)
    })
  }
}
