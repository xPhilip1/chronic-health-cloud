import {
  BG_PAGE, CARD_BG, TEXT_MAIN, TEXT_SUB, TEXT_FAINT, DANGER, R_CARD, SHADOW_CARD
} from '../common/Theme'
import { NavBar } from '../components/NavBar'

// 隐私政策 + 医疗免责声明页
// 说明：本页为纯静态文本，展示应用如何收集/存储/访问用户数据，以及辅助工具性质的法律免责。
@Entry
@Component
struct AboutPage {

  build() {
    Column() {
      NavBar({ title: '隐私与免责声明' })

      Scroll() {
        Column() {
          // 顶部小字：版本与更新日期
          Text('慢性病健康管理 · 版本 v1.0')
            .fontSize(12)
            .fontColor(TEXT_FAINT)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 12, bottom: 4 })

          Text('最近更新：2026-10-12')
            .fontSize(12)
            .fontColor(TEXT_FAINT)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ bottom: 12 })

          // 一、隐私政策
          this.buildSection('一、我们收集哪些信息',
            '仅收集为你提供健康记录、趋势查看、医生绑定与预警功能所必需的信息：\n\n' +
            '· 账号信息：注册时你主动填写的用户名、邮箱、手机号、生日、性别；医生身份还需填写执业证号。\n\n' +
            '· 健康数据：你手动记录或系统采集的血压（收缩压/舒张压）、血糖、体重、心率，以及记录时间与备注。\n\n' +
            '· 关系与预警：患者与医生的绑定关系、由健康数据触发的阈值预警记录。\n\n' +
            '我们不会收集与上述功能无关的信息，也不会向第三方出售或投放广告数据。')

          this.buildSection('二、信息如何存储与传输',
            '所有数据统一保存在华为云 CloudDB 云数据库（位于中国区域），由应用的服务端云函数集中读写。\n\n' +
            '客户端不直连数据库，全部请求经鉴权后由云端处理，数据传输走华为云网络通道。')

          this.buildSection('三、谁能看到你的数据',
            '遵循“最小可见”原则：\n\n' +
            '· 本人：始终可以查看和管理自己的全部记录与预警。\n\n' +
            '· 已绑定医生：可查看该患者的健康记录与预警，用于随访参考。\n\n' +
            '· 其他用户：无法访问你的任何数据。\n\n' +
            '系统通过登录令牌与用户角色对每一次访问进行校验，越权请求会被服务端拒绝。')

          this.buildSection('四、密码与安全',
            '你的登录密码以“加盐哈希”方式存储（PBKDF2 算法）。系统不保存、也无法还原你的明文密码，云端仅保存加密后的校验值。')

          this.buildSection('五、你的权利',
            '· 你可以随时在“个人中心”查看并修改自己的资料。\n\n' +
            '· 退出登录会清除本机的登录状态。\n\n' +
            '· 如需注销账号，可在「个人中心 → 注销账号」自助完成。注销后，你的健康记录、预警、社区内容与私信将被永久删除且不可恢复。')

          // 二、医疗免责声明
          this.buildDisclaimerTitle('医疗免责声明')

          this.buildWarningCard(
            '本应用是慢性病自我管理与记录辅助工具，不构成医疗建议、诊断结论或治疗方案。')

          this.buildSection('需要你知晓',
            '· 血压、血糖、心率等阈值预警仅基于通用参考数值给出提示，不能替代专业医疗判断。个体控制目标因人而异，请以医生的诊断和指导为准。\n\n' +
            '· 若应用提供 AI 健康建议，其内容由语言模型自动生成，仅供参考，可能存在不准确或不适用之处。切勿据此自行用药、停药或调整治疗。\n\n' +
            '· 出现紧急或严重症状时，请立即就医或拨打急救电话，不要依赖本应用。\n\n' +
            '· 本应用及其开发者不提供医疗服务，也不对因使用本应用而产生的任何后果承担责任。')

          Text('继续使用本应用即表示你已阅读并理解上述隐私政策与医疗免责声明。')
            .fontSize(12)
            .fontColor(TEXT_SUB)
            .width('100%')
            .padding({ left: 4, right: 4 })
            .margin({ top: 4, bottom: 40 })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_PAGE)
  }

  // 普通内容卡片：小标题 + 正文（正文用 \n 控制换行/分段）
  @Builder
  buildSection(title: string, content: string) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_MAIN)
        .width('100%')
        .margin({ bottom: 8 })

      Text(content)
        .fontSize(13)
        .fontColor(TEXT_SUB)
        .lineHeight(21)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(CARD_BG)
    .borderRadius(R_CARD)
    .shadow(SHADOW_CARD)
    .margin({ top: 12 })
  }

  // 免责声明小标题（红色调，与前面政策区分）
  @Builder
  buildDisclaimerTitle(title: string) {
    Text(title)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(TEXT_MAIN)
      .width('100%')
      .margin({ top: 24, bottom: 4 })
  }

  // 重点提示卡（左侧红条强调）
  @Builder
  buildWarningCard(content: string) {
    Row() {
      Column()
        .width(4)
        .height(46)
        .backgroundColor(DANGER)
        .borderRadius(2)
        .margin({ right: 12 })

      Text(content)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_MAIN)
        .lineHeight(22)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .backgroundColor(CARD_BG)
    .borderRadius(R_CARD)
    .shadow(SHADOW_CARD)
    .margin({ top: 12 })
  }
}
