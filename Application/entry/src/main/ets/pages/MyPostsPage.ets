import { ForumPost, parseMediaUrls } from '../model/ForumModel'
import { listMyForumPosts } from '../service/ApiService'
import {
  BG_PAGE, CARD_BG, TILE_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, ACCENT,
  C_SUGAR, R_CARD, SHADOW_CARD, HAIRLINE
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { resolveAvatar } from '../common/Avatar'

// 我发布的帖子：列出当前用户自己发的、未删除的帖子，时间倒序。
// 点卡片进详情（详情里可删除/编辑）。与论坛页同款 flicker-safe 加载：
// 首次走 loadData 管 isLoading，下拉/返回只走 fetchList 不碰 isLoading。
@Entry
@Component
struct MyPostsPage {
  @State posts: ForumPost[] = []
  @State isLoading: boolean = true
  @State refreshing: boolean = false
  @State hasMore: boolean = false
  @State page: number = 0

  async aboutToAppear(): Promise<void> {
    await this.loadData()
  }

  // 从详情页返回：可能删了帖或改了计数，重新拉一次（走 fetchList，不闪）
  async onPageShow(): Promise<void> {
    await this.fetchList(true)
  }

  async loadData(): Promise<void> {
    this.isLoading = true
    await this.fetchList(true)
    this.isLoading = false
  }

  // reset=true 覆盖列表；false 追加（加载更多）
  async fetchList(reset: boolean): Promise<void> {
    let targetPage: number = reset ? 0 : this.page + 1
    let result = await listMyForumPosts(targetPage)
    if (reset) {
      this.posts = result.posts
      this.page = 0
    } else {
      let merged: ForumPost[] = []
      for (let i = 0; i < this.posts.length; i++) {
        merged.push(this.posts[i])
      }
      for (let j = 0; j < result.posts.length; j++) {
        merged.push(result.posts[j])
      }
      this.posts = merged
      this.page = targetPage
    }
    this.hasMore = result.hasMore
  }

  async onRefresh(): Promise<void> {
    await this.fetchList(true)
    this.refreshing = false
  }

  openDetail(p: ForumPost): void {
    try {
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/PostDetailPage',
        params: { postId: p.postId }
      })
    } catch (e) {
      console.error('打开帖子详情失败: ' + (e as Error).message)
    }
  }

  formatTime(iso: string): string {
    if (iso === '' || iso.length < 16) {
      return iso
    }
    return iso.substring(5, 10) + ' ' + iso.substring(11, 16)
  }

  roleLabel(role: string): string {
    if (role === 'doctor') { return '医生' }
    if (role === 'admin') { return '管理员' }
    return '病友'
  }

  @Builder
  buildCard(p: ForumPost) {
    Column() {
      // 作者行
      Row() {
        Stack({ alignContent: Alignment.Center }) {
          if (p.authorAvatar !== undefined && p.authorAvatar !== '') {
            Image(p.authorAvatar).width(20).height(20).objectFit(ImageFit.Cover)
          } else {
            Image(resolveAvatar('', p.authorRole))
              .width(9).height(9).fillColor('#FFFFFF')
          }
        }
        .width(20).height(20).borderRadius(10)
        .backgroundColor(p.authorRole === 'doctor' ? C_SUGAR : ACCENT)
        .clip(true)
        Text(p.authorName)
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(TEXT_MAIN).margin({ left: 8 })
        Text(this.roleLabel(p.authorRole))
          .fontSize(10).fontColor(p.authorRole === 'doctor' ? C_SUGAR : TEXT_SUB)
          .backgroundColor(TILE_BG)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 }).borderRadius(8).margin({ left: 6 })
        Blank()
        Text(this.formatTime(p.createdAt))
          .fontSize(11).fontColor(TEXT_FAINT)
      }
      .width('100%')

      Text(p.title)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(TEXT_MAIN)
        .width('100%').textAlign(TextAlign.Start).margin({ top: 10 })
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(p.content)
        .fontSize(13).fontColor('#5A6072')
        .width('100%').textAlign(TextAlign.Start).margin({ top: 6 })
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })

      if (parseMediaUrls(p.mediaUrls).length > 0) {
        Row() {
          ForEach(parseMediaUrls(p.mediaUrls), (url: string) => {
            Image(url)
              .width(72)
              .height(72)
              .objectFit(ImageFit.Cover)
              .borderRadius(10)
              .backgroundColor(TILE_BG)
              .margin({ right: 8 })
          }, (url: string) => url)
        }
        .width('100%')
        .margin({ top: 10 })
      }

      Divider().color(HAIRLINE).strokeWidth(1).margin({ top: 12, bottom: 10 })

      // 底部：统计
      Row() {
        Text(p.likeCount.toString() + ' 点赞')
          .fontSize(12).fontColor(TEXT_SUB)
        Text(p.commentCount.toString() + ' 回复')
          .fontSize(12).fontColor(TEXT_SUB).margin({ left: 16 })
        Blank()
        Text('查看详情 ›')
          .fontSize(12).fontColor(ACCENT)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(CARD_BG)
    .borderRadius(R_CARD)
    .shadow(SHADOW_CARD)
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 12 })
    .onClick(() => { this.openDetail(p) })
  }

  @Builder
  buildBody() {
    if (this.posts.length === 0) {
      Column() {
        Image($r('app.media.ic_data_records'))
          .width(56).height(56).fillColor(TEXT_FAINT)
          .margin({ bottom: 14 })
        Text('还没有发布过帖子')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(TEXT_SUB)
        Text('去论坛点右下角"发布"就能发出第一条')
          .fontSize(13).fontColor(TEXT_FAINT).margin({ top: 8 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    } else {
      Scroll() {
        Column() {
          ForEach(this.posts, (p: ForumPost) => {
            this.buildCard(p)
          }, (p: ForumPost) => p.postId.toString() + '_' + p.likeCount.toString() + '_' + p.commentCount.toString() + '_' + p.mediaUrls)

          if (this.hasMore) {
            Text('加载更多')
              .fontSize(14).fontColor(ACCENT)
              .width('100%').textAlign(TextAlign.Center)
              .padding({ top: 10, bottom: 10 })
              .onClick(() => { this.fetchList(false) })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      }
      .width('100%').height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
  }

  build() {
    Column() {
      NavBar({ title: '我的发布' })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(40).height(40).color(ACCENT)
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          this.buildBody()
        }
        .layoutWeight(1)
        .onRefreshing(() => { this.onRefresh() })
      }
    }
    .width('100%').height('100%')
    .backgroundColor(BG_PAGE)
  }
}
