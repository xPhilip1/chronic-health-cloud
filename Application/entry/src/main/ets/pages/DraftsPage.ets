// 草稿箱页面：展示本地保存的帖子草稿，点击可继续编辑，右划删除。
import { Draft, listDrafts, deleteDraft } from '../service/DraftStore'
import {
  BG_PAGE, CARD_BG, TILE_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, ACCENT, DANGER, R_CARD, SHADOW_CARD
} from '../common/Theme'
import { NavBar } from '../components/NavBar'

@Entry
@Component
struct DraftsPage {
  @State drafts: Draft[] = []
  @State isLoading: boolean = true

  onPageShow(): void {
    this.loadData()
  }

  async loadData(): Promise<void> {
    let ctx = this.getUIContext().getHostContext()
    if (ctx === undefined) { this.isLoading = false; return }
    this.drafts = await listDrafts(ctx)
    this.isLoading = false
  }

  openEdit(draft: Draft): void {
    try {
      this.getUIContext().getRouter().pushUrl({ url: 'pages/PostEditPage', params: { draftId: draft.id } })
    } catch (e) {
      console.error('打开草稿失败: ' + (e as Error).message)
    }
  }

  async removeDraft(id: string): Promise<void> {
    let ctx = this.getUIContext().getHostContext()
    if (ctx === undefined) { return }
    await deleteDraft(ctx, id)
    this.loadData()
  }

  // ISO -> MM-DD HH:mm
  formatTime(iso: string): string {
    if (iso === '' || iso.length < 16) { return iso }
    return iso.substring(5, 10) + ' ' + iso.substring(11, 16)
  }

  build() {
    Column() {
      NavBar({ title: '草稿箱', showBack: true })

      if (this.isLoading) {
        Column() {
          LoadingProgress().width(48).height(48).color(ACCENT)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.drafts.length === 0) {
        Column() {
          Image($r('app.media.ic_data_records'))
            .width(56).height(56).fillColor(TEXT_FAINT)
            .margin({ bottom: 14 })
          Text('没有草稿')
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(TEXT_SUB)
          Text('编辑帖子时可以保存为草稿')
            .fontSize(13).fontColor(TEXT_FAINT).margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column() {
            ForEach(this.drafts, (d: Draft) => {
              Row() {
                Column() {
                  Text(d.title === '' ? '（无标题）' : d.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(TEXT_MAIN)
                    .width('100%')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(d.content === '' ? '（仅图片）' : d.content)
                    .fontSize(13)
                    .fontColor(TEXT_SUB)
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                  Text('最近编辑 ' + this.formatTime(d.updatedAt))
                    .fontSize(11)
                    .fontColor(TEXT_FAINT)
                    .margin({ top: 6 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text('删除')
                  .fontSize(13)
                  .fontColor(DANGER)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .onClick(() => { this.removeDraft(d.id) })
              }
              .width('100%')
              .padding(16)
              .backgroundColor(CARD_BG)
              .borderRadius(R_CARD)
              .shadow(SHADOW_CARD)
              .margin({ bottom: 12 })
              .alignItems(VerticalAlign.Center)
              .onClick(() => { this.openEdit(d) })
            }, (d: Draft) => d.id + '_' + d.updatedAt)
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
