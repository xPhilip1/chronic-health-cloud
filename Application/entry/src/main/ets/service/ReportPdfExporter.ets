import { pdfService } from '@kit.PDFKit'
import { systemShare } from '@kit.ShareKit'
import { fileUri } from '@kit.CoreFileKit'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AiHealthReport, AiMetricRead } from '../model/HealthModel'

const TAG = '[ReportPdf]'
const DOMAIN = 0x0000

// A4 尺寸（单位 pt）
const PAGE_W: number = 595
const PAGE_H: number = 842
const MARGIN_L: number = 48
const MARGIN_R: number = 48
const MARGIN_T: number = 56
const MARGIN_B: number = 56
const CONTENT_W: number = PAGE_W - MARGIN_L - MARGIN_R
// 中文字体：设备系统字体路径（HarmonyOS 自带）
const FONT_PATH: string = '/system/fonts/HarmonyOS_Sans_SC.ttf'

// 颜色（0xRRGGBB）
const C_TITLE: number = 0x1F2A44
const C_ACCENT: number = 0x2C6EAA
const C_BODY: number = 0x333333
const C_SUB: number = 0x6B7280
const C_DANGER: number = 0xD9534F

// 估算单个字符宽度（CJK 近全宽，ASCII 约 0.55 倍）
function charWidth(ch: string, size: number): number {
  const code: number = ch.charCodeAt(0)
  if (code >= 0x2E80) {
    return size
  }
  if (code === 0x20) {
    return size * 0.30
  }
  return size * 0.55
}

// 按估算宽度对中文/英文混排文本做换行切分（先按已有 \n 分段）
function wrapText(text: string, size: number, maxW: number): string[] {
  const out: string[] = []
  const paras: string[] = text.split('\n')
  for (let p = 0; p < paras.length; p++) {
    const para: string = paras[p]
    if (para === '') {
      out.push('')
      continue
    }
    let cur: string = ''
    let w: number = 0
    for (let i = 0; i < para.length; i++) {
      const ch: string = para[i]
      const cw: number = charWidth(ch, size)
      if (w + cw > maxW) {
        out.push(cur)
        cur = ch
        w = cw
      } else {
        cur += ch
        w += cw
      }
    }
    if (cur !== '') {
      out.push(cur)
    }
  }
  return out
}

// PDF 绘制器：维护当前页与从上往下的游标
class PdfBuilder {
  doc: pdfService.PdfDocument
  page: pdfService.PdfPage | null = null
  cursorY: number = MARGIN_T

  constructor() {
    this.doc = new pdfService.PdfDocument()
    this.doc.createDocument(PAGE_W, PAGE_H)
    if (this.doc.getPageCount() > 0) {
      this.page = this.doc.getPage(0)
    } else {
      this.newPage()
    }
  }

  newPage(): void {
    this.page = this.doc.insertBlankPage(this.doc.getPageCount(), PAGE_W, PAGE_H)
    this.cursorY = MARGIN_T
  }

  ensure(h: number): void {
    if (this.cursorY + h > PAGE_H - MARGIN_B) {
      this.newPage()
    }
  }

  gap(h: number): void {
    this.ensure(h)
    this.cursorY += h
  }

  // 写一段文本（自动换行 + 自动分页）
  text(str: string, size: number, color: number, bold: boolean, left: number, maxW: number): void {
    if (this.page === null) {
      this.newPage()
    }
    const style: pdfService.TextStyle = new pdfService.TextStyle()
    const fi: pdfService.FontInfo = new pdfService.FontInfo()
    fi.fontPath = FONT_PATH
    style.fontInfo = fi
    style.textSize = size
    style.textColor = color
    style.isBold = bold
    const lines: string[] = wrapText(str, size, maxW)
    const lh: number = size * 1.6
    for (let i = 0; i < lines.length; i++) {
      this.ensure(lh)
      const pdfY: number = PAGE_H - this.cursorY - size
      this.page!.addTextObject(lines[i], left, pdfY, style)
      this.cursorY += lh
    }
  }

  // 标题（带下划线分隔的简单处理：加粗 + 稍大 + 间距）
  heading(str: string): void {
    this.gap(10)
    this.text(str, 15, C_ACCENT, true, MARGIN_L, CONTENT_W)
    this.gap(4)
  }

  body(str: string): void {
    this.text(str, 11.5, C_BODY, false, MARGIN_L, CONTENT_W)
  }

  save(path: string): boolean {
    return this.doc.saveDocument(path)
  }
}

// 风险等级 -> 文案
function riskLabel(level: string): string {
  if (level === 'high') {
    return '高风险'
  }
  if (level === 'medium') {
    return '需关注'
  }
  return '总体平稳'
}

// 生成报告 PDF 到应用沙箱，返回文件绝对路径
export function buildReportPdf(
  report: AiHealthReport,
  displayName: string,
  account: string,
  generatedAt: string,
  sampleCount: number,
  filesDir: string
): string {
  const b: PdfBuilder = new PdfBuilder()

  // 标题
  b.text('AI 健康建议报告', 22, C_TITLE, true, MARGIN_L, CONTENT_W)
  b.gap(6)
  let sub: string = '用户：' + displayName
  if (account !== '' && account !== displayName) {
    sub += '（账号 ' + account + '）'
  }
  b.text(sub, 11, C_SUB, false, MARGIN_L, CONTENT_W)
  let meta: string = '生成时间：' + generatedAt
  if (sampleCount > 0) {
    meta += '    基于近 30 天 ' + sampleCount + ' 条数据'
  }
  b.text(meta, 11, C_SUB, false, MARGIN_L, CONTENT_W)
  b.gap(4)

  // 总体评估
  b.heading('总体评估：' + riskLabel(report.riskLevel))
  b.body(report.overallAssessment)

  // 指标解读
  if (report.metrics.length > 0) {
    b.heading('指标解读')
    for (let i = 0; i < report.metrics.length; i++) {
      const m: AiMetricRead = report.metrics[i]
      b.text(m.name + '：' + m.status, 12, C_TITLE, true, MARGIN_L, CONTENT_W)
      b.text(m.detail, 11, C_BODY, false, MARGIN_L + 12, CONTENT_W - 12)
      b.gap(4)
    }
  }

  // 各建议段落
  const sections: string[][] = [
    ['趋势分析', report.trendAnalysis],
    ['饮食建议', report.dietAdvice],
    ['运动建议', report.exerciseAdvice],
    ['生活方式', report.lifestyleAdvice],
    ['复查与就医', report.followUpAdvice]
  ]
  for (let i = 0; i < sections.length; i++) {
    const title: string = sections[i][0]
    const content: string = sections[i][1]
    if (content !== '') {
      b.heading(title)
      b.body(content)
    }
  }

  // 危险信号
  if (report.redFlags !== '') {
    b.heading('危险信号')
    b.text(report.redFlags, 11.5, C_DANGER, false, MARGIN_L, CONTENT_W)
  }

  // 免责声明
  b.gap(14)
  b.text('本报告由 AI 依据你录入的数据自动生成，仅供健康管理参考，不能替代医生诊断。如有不适请及时就医。',
    9.5, C_SUB, false, MARGIN_L, CONTENT_W)

  const ts: number = Date.now()
  const path: string = filesDir + '/health_report_' + ts + '.pdf'
  const ok: boolean = b.save(path)
  if (!ok) {
    throw new Error('PDF 保存失败')
  }
  return path
}

// 用系统分享面板分享 PDF（可保存到文件、发送微信等）
export async function sharePdf(context: common.UIAbilityContext, filePath: string, title: string): Promise<void> {
  const uri: string = fileUri.getUriFromPath(filePath)
  const record: systemShare.SharedRecord = {
    utd: 'com.adobe.pdf',
    uri: uri,
    title: title
  }
  const data: systemShare.SharedData = new systemShare.SharedData(record)
  const controller: systemShare.ShareController = new systemShare.ShareController(data)
  await controller.show(context, {
    selectionMode: systemShare.SelectionMode.SINGLE
  })
}

// 组合：生成 + 分享，返回路径
export async function exportAndShareReportPdf(
  report: AiHealthReport,
  displayName: string,
  account: string,
  generatedAt: string,
  sampleCount: number,
  context: common.UIAbilityContext
): Promise<string> {
  const path: string = buildReportPdf(report, displayName, account, generatedAt, sampleCount, context.filesDir)
  hilog.info(DOMAIN, TAG, 'pdf built: %{public}s', path)
  await sharePdf(context, path, 'AI健康建议报告')
  return path
}
