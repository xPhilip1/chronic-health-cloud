// 帖子搜索页：顶部关键词输入 + 提交式搜索，结果列表复用 PostCard 组件。
// 与论坛列表共用同一套卡片渲染，样式只需改 PostCard 一处。
import { ForumPost, ForumPostPage } from '../model/ForumModel'
import { searchForumPosts, toggleForumLike } from '../service/ApiService'
import {
  BG_PAGE, TILE_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, ACCENT
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { PostCard } from '../components/PostCard'

@Entry
@Component
struct SearchPage {
  @State keyword: string = ''
  @State posts: ForumPost[] = []
  @State hasMore: boolean = false
  @State page: number = 0
  @State loading: boolean = false     // 首次搜索整页转圈
  @State searching: boolean = false   // 正在发请求（含"加载更多"），用于按钮文案与防抖
  @State searched: boolean = false    // 是否已执行过至少一次搜索（区分"未搜索"与"无结果"）

  // 提交式搜索：reset=true 从第 0 页重搜；false 追加下一页
  async doSearch(reset: boolean): Promise<void> {
    let kw: string = this.keyword.trim()
    if (kw === '') {
      this.getUIContext().getPromptAction().showToast({ message: '请输入搜索关键词' })
      return
    }
    if (this.searching) {
      return
    }
    let targetPage: number = reset ? 0 : this.page + 1
    this.searching = true
    if (reset) {
      this.loading = true
    }
    let result: ForumPostPage = await searchForumPosts(kw, targetPage)
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
    this.searched = true
    this.loading = false
    this.searching = false
  }

  // 清空关键词，回到未搜索状态
  clearKeyword(): void {
    this.keyword = ''
    this.posts = []
    this.hasMore = false
    this.page = 0
    this.searched = false
  }

  // 结果内点赞：调云函数 -> 回填该条 -> 重建数组触发刷新（与论坛列表一致）
  async onLike(post: ForumPost): Promise<void> {
    if (post.status === 1) {
      return
    }
    try {
      let r = await toggleForumLike(post.postId)
      let next: ForumPost[] = []
      for (let i = 0; i < this.posts.length; i++) {
        let p: ForumPost = this.posts[i]
        if (p.postId === post.postId) {
          let copy: ForumPost = {
            postId: p.postId, authorId: p.authorId, authorRole: p.authorRole, authorName: p.authorName, authorAvatar: p.authorAvatar,
            title: p.title, content: p.content, createdAt: p.createdAt,
            likeCount: r.likeCount, commentCount: p.commentCount, status: p.status, likedByMe: r.liked, favorited: p.favorited, mediaUrls: p.mediaUrls, dept: p.dept, topics: p.topics
          }
          next.push(copy)
        } else {
          next.push(p)
        }
      }
      this.posts = next
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败：' + (e as Error).message })
    }
  }

  openDetail(post: ForumPost): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PostDetailPage', params: { postId: post.postId } })
    } catch (e) {
      console.error('打开帖子失败: ' + (e as Error).message)
    }
  }

  @Builder
  searchBar() {
    Row() {
      Image($r('app.media.ic_search'))
        .width(18)
        .height(18)
        .fillColor(TEXT_FAINT)
        .margin({ left: 12, right: 8 })
      TextInput({ placeholder: '搜索帖子标题或正文', text: this.keyword })
        .layoutWeight(1)
        .height(40)
        .fontSize(14)
        .fontColor(TEXT_MAIN)
        .backgroundColor(Color.Transparent)
        .placeholderColor(TEXT_FAINT)
        .onChange((v: string) => { this.keyword = v })
        .onSubmit(() => { this.doSearch(true) })
      if (this.keyword !== '') {
        Text('×')
          .fontSize(20)
          .fontColor(TEXT_FAINT)
          .width(24)
          .textAlign(TextAlign.Center)
          .onClick(() => { this.clearKeyword() })
      }
      Text(this.searching ? '搜索中' : '搜索')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .fontWeight(FontWeight.Medium)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(18)
        .backgroundColor(ACCENT)
        .margin({ left: 8, right: 12 })
        .onClick(() => { this.doSearch(true) })
    }
    .width('100%')
    .height(52)
    .backgroundColor(TILE_BG)
    .borderRadius(26)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      NavBar({ title: '搜索帖子', showBack: true })

      Column() {
        this.searchBar()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14, bottom: 10 })

      if (this.loading) {
        Column() {
          LoadingProgress().width(48).height(48).color(ACCENT)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (!this.searched) {
        Column() {
          Image($r('app.media.ic_search'))
            .width(56).height(56).fillColor(TEXT_FAINT)
            .margin({ bottom: 14 })
          Text('输入关键词，找相关帖子')
            .fontSize(15).fontColor(TEXT_SUB)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.posts.length === 0) {
        Column() {
          Image($r('app.media.ic_lightbulb'))
            .width(56).height(56).fillColor(TEXT_FAINT)
            .margin({ bottom: 14 })
          Text('没有找到"' + this.keyword.trim() + '"相关的帖子')
            .fontSize(15).fontColor(TEXT_SUB)
          Text('换个关键词试试～')
            .fontSize(13).fontColor(TEXT_FAINT).margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column() {
            Text('共 ' + this.posts.length.toString() + ' 条结果')
              .fontSize(12)
              .fontColor(TEXT_FAINT)
              .width('100%')
              .margin({ bottom: 10 })
            ForEach(this.posts, (item: ForumPost) => {
              PostCard({
                post: item,
                onLike: (p: ForumPost): void => { this.onLike(p) },
                onOpen: (p: ForumPost): void => { this.openDetail(p) }
              })
            }, (item: ForumPost) => {
              // key 编进会就地变化的字段，点赞后 @Prop 才会刷新
              return item.postId.toString() + '_' + item.likeCount.toString() + '_' + item.commentCount.toString() + '_' + (item.likedByMe ? 1 : 0)
            })

            if (this.hasMore) {
              Text(this.searching ? '加载中…' : '加载更多')
                .fontSize(14)
                .fontColor(ACCENT)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(14)
                .onClick(() => { this.doSearch(false) })
            } else {
              Text('— 到底啦 —')
                .fontSize(12)
                .fontColor(TEXT_FAINT)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(14)
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 14, bottom: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAGE)
  }
}
