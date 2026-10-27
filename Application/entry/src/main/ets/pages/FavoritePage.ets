import { ForumPost } from '../model/ForumModel'
import { listForumFavorites, toggleForumFavorite } from '../service/ApiService'
import {
  BG_PAGE, CARD_BG, TILE_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, ACCENT, WARN,
  C_SUGAR, R_CARD, SHADOW_CARD, HAIRLINE
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { resolveAvatar } from '../common/Avatar'

// 我的收藏：列出当前用户收藏过的帖子，按收藏时间倒序。
// 点卡片进详情；点右侧星形可就地取消收藏（本地剔除，不重查，规避 CloudDB 写完即读的旧快照）。
// 与论坛页同款 flicker-safe 加载：首次走 loadData 管 isLoading，下拉/返回只走 fetchList 不碰 isLoading。
@Entry
@Component
struct FavoritePage {
  @State posts: ForumPost[] = []
  @State isLoading: boolean = true
  @State refreshing: boolean = false
  @State hasMore: boolean = false
  @State page: number = 0

  async aboutToAppear(): Promise<void> {
    await this.loadData()
  }

  // 从详情页返回：可能收藏态有变，重新拉一次（走 fetchList，不闪）
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
    let result = await listForumFavorites(targetPage)
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

  // 就地取消收藏：调云函数后从本地列表移除该条（重建数组触发刷新）
  async onUnfavorite(p: ForumPost): Promise<void> {
    try {
      await toggleForumFavorite(p.postId)
      let next: ForumPost[] = []
      for (let i = 0; i < this.posts.length; i++) {
        if (this.posts[i].postId !== p.postId) {
          next.push(this.posts[i])
        }
      }
      this.posts = next
      this.getUIContext().getPromptAction().showToast({ message: '已取消收藏' })
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败：' + (e as Error).message })
    }
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
          .backgroundColor(p.authorRole === 'doctor' ? TILE_BG : TILE_BG)
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

      Divider().color(HAIRLINE).strokeWidth(1).margin({ top: 12, bottom: 10 })

      // 底部：统计 + 取消收藏
      Row() {
        Text(p.likeCount.toString() + ' 点赞')
          .fontSize(12).fontColor(TEXT_SUB)
        Text(p.commentCount.toString() + ' 回复')
          .fontSize(12).fontColor(TEXT_SUB).margin({ left: 16 })
        Blank()
        Row() {
          Image($r('app.media.ic_star'))
            .width(16).height(16).fillColor(WARN)
          Text('取消收藏')
            .fontSize(12).fontColor(WARN).margin({ left: 4 })
        }
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .onClick(() => { this.onUnfavorite(p) })
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
        Image($r('app.media.ic_star'))
          .width(56).height(56).fillColor(TEXT_FAINT)
          .margin({ bottom: 14 })
        Text('还没有收藏的帖子')
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(TEXT_SUB)
        Text('在帖子详情页点右下角"收藏"就能收进这里')
          .fontSize(13).fontColor(TEXT_FAINT).margin({ top: 8 })
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
    } else {
      Scroll() {
        Column() {
          ForEach(this.posts, (p: ForumPost) => {
            this.buildCard(p)
          }, (p: ForumPost) => p.postId.toString() + '_' + p.likeCount.toString() + '_' + p.commentCount.toString())

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
      NavBar({ title: '我的收藏' })

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
