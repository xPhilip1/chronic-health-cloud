import { UserInfo } from '../model/UserModel'
import { ForumPost, ForumPostPage, ForumViolationStatus } from '../model/ForumModel'
import {
  getCurrentUser, listForumPosts, adminListForumPosts, getMyForumViolation, toggleForumLike
} from '../service/ApiService'
import {
  CANVAS, INK, INK_SUB, INK_FAINT, HAIRLINE, MINT, MINT_SOFT, DANGER, DANGER_SOFT, WARN,
  T_H1, T_SM, T_CAP, T_MICRO, TRACK_LABEL, R_PILL, R_XS, D_BASE, SHADOW_GLOW
} from '../common/Theme'
import { BottomNav } from '../components/BottomNav'
import { PostCard } from '../components/PostCard'
import { StateView } from '../components/StateView'
import { ForumFilterTag, buildFilterTags } from '../common/Tags'

@Entry
@Component
struct ForumPage {
  @State posts: ForumPost[] = []
  @State myRole: string = 'patient'
  @State isAdmin: boolean = false
  @State isLoading: boolean = true
  @State refreshing: boolean = false
  @State hasMore: boolean = false
  @State page: number = 0
  @State muted: boolean = false
  @State muteRemainText: string = ''
  @State violationCount: number = 0
  @State fabScale: number = 1
  @State filterTags: ForumFilterTag[] = buildFilterTags()
  @State activeTagIndex: number = 0

  currentDept(): string {
    if (this.activeTagIndex < 0 || this.activeTagIndex >= this.filterTags.length) {
      return ''
    }
    return this.filterTags[this.activeTagIndex].dept
  }

  currentTopic(): string {
    if (this.activeTagIndex < 0 || this.activeTagIndex >= this.filterTags.length) {
      return ''
    }
    return this.filterTags[this.activeTagIndex].topic
  }

  onPageShow(): void {
    this.loadData(true, false)
  }

  async loadData(reset: boolean, skipSpinner: boolean = false): Promise<void> {
    let cur: UserInfo | null = await getCurrentUser()
    if (cur === null) {
      this.isLoading = false
      return
    }
    this.myRole = cur.role
    this.isAdmin = cur.role === 'admin'

    let targetPage: number = reset ? 0 : this.page + 1
    if (reset && !skipSpinner) {
      this.isLoading = true
    }
    let result: ForumPostPage = this.isAdmin
      ? await adminListForumPosts(targetPage)
      : await listForumPosts(targetPage, this.currentDept(), this.currentTopic())

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

    if (!this.isAdmin) {
      let v: ForumViolationStatus = await getMyForumViolation()
      this.muted = v.muted
      this.muteRemainText = v.muteRemainText
      this.violationCount = v.violationCount
    }
    this.isLoading = false
    this.refreshing = false
  }

  async onRefresh(): Promise<void> {
    this.refreshing = true
    await this.loadData(true, true)
  }

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
          next.push({
            postId: p.postId, authorId: p.authorId, authorRole: p.authorRole, authorName: p.authorName, authorAvatar: p.authorAvatar,
            title: p.title, content: p.content, createdAt: p.createdAt,
            likeCount: r.likeCount, commentCount: p.commentCount, status: p.status, likedByMe: r.liked,
            favorited: p.favorited, mediaUrls: p.mediaUrls, dept: p.dept, topics: p.topics
          })
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

  goEdit(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PostEditPage' })
    } catch (e) {
      console.error('进入发帖页失败: ' + (e as Error).message)
    }
  }

  goSearch(): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage' })
    } catch (e) {
      console.error('进入搜索页失败: ' + (e as Error).message)
    }
  }

  selectTag(i: number): void {
    if (this.activeTagIndex === i) {
      return
    }
    this.activeTagIndex = i
    this.loadData(true, false)
  }

  @Builder
  headerBar() {
    Row() {
      Column() {
        Text(this.isAdmin ? '内容管理' : '社区')
          .fontSize(T_H1)
          .fontWeight(FontWeight.Medium)
          .fontColor(INK)
          .letterSpacing(0.4)
        Text(this.isAdmin ? '审核全部帖子（含已删除）' : '经验、疑问与互相打气')
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
          .letterSpacing(TRACK_LABEL)
          .margin({ top: 8 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!this.isAdmin) {
        // 热区交给外层 40×40 的 Row，图标自身不加 padding
        // （之前宽高 20 再套 padding 10，内容区被压成 0×0，图标看不见但仍可点击）
        Row() {
          Image($r('app.media.ic_search'))
            .width(20)
            .height(20)
            .fillColor(INK)
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.goSearch() })
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 10 })
    .alignItems(VerticalAlign.Top)
  }

  // 文字式筛选：选中项变薄荷色并加一条下划线，不再用胶囊按钮
  @Builder
  filterBar() {
    Scroll() {
      Row() {
        ForEach(this.filterTags, (tag: ForumFilterTag, idx: number) => {
          Column() {
            Text(tag.label)
              .fontSize(T_SM)
              .fontColor(this.activeTagIndex === idx ? INK : INK_FAINT)
              .letterSpacing(0.3)
            Divider()
              .width(16)
              .color(this.activeTagIndex === idx ? MINT : 'rgba(0,0,0,0)')
              .strokeWidth(2)
              .margin({ top: 7 })
              .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
          }
          .margin({ right: 22 })
          .onClick(() => { this.selectTag(idx) })
        }, (tag: ForumFilterTag, idx: number) => tag.label + '_' + (this.activeTagIndex === idx ? 1 : 0))
      }
      .padding({ left: 24, right: 24 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
    .width('100%')
    .padding({ bottom: 14 })
  }

  @Builder
  mutedBanner() {
    Row() {
      Circle()
        .width(5)
        .height(5)
        .fill(this.muted ? DANGER : WARN)
      Text(this.muted
        ? ('已临时禁言，剩余 ' + this.muteRemainText)
        : ('有 ' + this.violationCount + ' 次违规记录'))
        .fontSize(T_CAP)
        .fontColor(this.muted ? DANGER : WARN)
        .margin({ left: 7 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 4, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildFab() {
    Row() {
      Image($r('app.media.ic_data_add'))
        .width(22)
        .height(22)
        .fillColor('#FFFFFF')
    }
    .width(54)
    .height(54)
    .justifyContent(FlexAlign.Center)
    .borderRadius(27)
    .backgroundColor(MINT)
    .shadow(SHADOW_GLOW)
    .scale({ x: this.fabScale, y: this.fabScale })
    .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.fabScale = 0.9
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.fabScale = 1
      }
    })
    .onClick(() => { this.goEdit() })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.headerBar()

        if (!this.isAdmin && this.filterTags.length > 0) {
          this.filterBar()
        }
        if (!this.isAdmin && (this.muted || this.violationCount > 0)) {
          this.mutedBanner()
        }

        // 只在"首次进入、一篇文章都还没有"时整屏 loading；
        // 从其它 tab 切回来时直接展示已有列表并在后台刷新，避免整屏闪烁。
        if (this.isLoading && this.posts.length === 0) {
          Column() {
            StateView({ kind: 'loading', title: '正在读取社区' })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.posts.length === 0) {
          Column() {
            StateView({
              kind: 'empty',
              title: this.isAdmin ? '暂无内容' : '还没有人发言',
              desc: this.isAdmin ? '等用户发布后再来审核' : '点右下角发布第一条，说说近况',
              icon: $r('app.media.ic_lightbulb'),
              actionText: this.isAdmin ? '' : '发布',
              onAction: () => { this.goEdit() }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
            List() {
              ForEach(this.posts, (item: ForumPost) => {
                ListItem() {
                  PostCard({
                    post: item,
                    onLike: (p: ForumPost): void => { this.onLike(p) },
                    onOpen: (p: ForumPost): void => { this.openDetail(p) }
                  })
                }
              }, (item: ForumPost) => {
                return item.postId.toString() + '_' + item.likeCount.toString() + '_' + item.commentCount.toString() + '_' + (item.likedByMe ? 1 : 0)
              })

              ListItem() {
                Column() {
                  if (this.hasMore) {
                    Text('加载更多')
                      .fontSize(T_CAP)
                      .fontColor(MINT)
                      .letterSpacing(0.6)
                      .padding({ top: 22, bottom: 22 })
                      .onClick(() => { this.loadData(false) })
                  } else {
                    Text('— 到底了 —')
                      .fontSize(T_MICRO)
                      .fontColor(INK_FAINT)
                      .letterSpacing(1)
                      .padding({ top: 26, bottom: 26 })
                  }
                }
                .width('100%')
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .height('100%')
            .padding({ left: 24, right: 24 })
            .scrollBar(BarState.Off)
          }
          .layoutWeight(1)
          .onRefreshing(() => { this.onRefresh() })
        }

        BottomNav({ current: 'forum', isPatient: this.myRole === 'patient' })
      }
      .width('100%')
      .height('100%')

      if (!this.isAdmin) {
        Column() {
          this.buildFab()
        }
        .margin({ right: 24, bottom: 100 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }
}
