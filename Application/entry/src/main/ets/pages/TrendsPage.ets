import { HealthData } from '../model/HealthModel'
import { getHealthDataList } from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_SUNK, HAIRLINE, INK, INK_SUB, INK_FAINT,
  JADE, JADE_SOFT, ON_PRIMARY, DANGER, OK, OK_SOFT,
  M_BP, M_SUGAR, M_HR, M_WEIGHT, R_LG, R_MD, R_PILL, R_XS,
  T_H1, T_H2, T_H3, T_BODY, T_SM, T_CAP, T_MICRO, D_BASE, isDarkNow
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { StateView } from '../components/StateView'

interface ChartPoint {
  v: number
  t: string
}

interface StatItem {
  label: string
  value: string
  color: string
}

interface MetricOption {
  key: string
  label: string
}

interface RangeOption {
  key: string
  label: string
}

const PAD_L: number = 40
const PAD_R: number = 12
const PAD_T: number = 16
const PAD_B: number = 28

@Entry
@Component
struct TrendsPage {
  @State allData: HealthData[] = []
  @State pts: ChartPoint[] = []
  @State selectedMetric: string = 'systolic'
  @State selectedRange: string = 'all'
  @State selectedIndex: number = -1
  @State avgText: string = '-'
  @State maxText: string = '-'
  @State minText: string = '-'
  @State trendText: string = '—'
  @State trendColor: string = ''
  @State refreshing: boolean = false
  // 折线生长动画进度
  @State @Watch('redraw') drawProgress: number = 1

  private metrics: MetricOption[] = [
    { key: 'systolic', label: '收缩压' },
    { key: 'diastolic', label: '舒张压' },
    { key: 'bloodSugar', label: '血糖' },
    { key: 'heartRate', label: '心率' },
    { key: 'weight', label: '体重' }
  ]

  private ranges: RangeOption[] = [
    { key: 'all', label: '全部' },
    { key: '7', label: '近 7 天' },
    { key: '30', label: '近 30 天' },
    { key: '90', label: '近 90 天' }
  ]

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private ready: boolean = false

  async aboutToAppear(): Promise<void> {
    this.dark = isDarkNow()
    await this.reloadData()
  }

  // 重画时先归零再生长，形成"折线从左往右画出"的效果
  animateChart(): void {
    this.drawProgress = 0
    setTimeout(() => {
      try {
        this.getUIContext().animateTo({ duration: 720, curve: Curve.FastOutSlowIn }, () => {
          this.drawProgress = 1
        })
      } catch (e) {
        this.drawProgress = 1
        this.draw()
      }
    }, 30)
  }

  async reloadData(): Promise<void> {
    let all: HealthData[] = await getHealthDataList()
    this.allData = all
    this.refresh()
    this.animateChart()
  }

  getVal(item: HealthData): number {
    if (this.selectedMetric === 'systolic') {
      return item.bloodPressureSystolic
    }
    if (this.selectedMetric === 'diastolic') {
      return item.bloodPressureDiastolic
    }
    if (this.selectedMetric === 'bloodSugar') {
      return item.bloodSugar
    }
    if (this.selectedMetric === 'heartRate') {
      return item.heartRate
    }
    return item.weight
  }

  refresh(): void {
    let cutoff: number = 0
    if (this.selectedRange === '7') {
      cutoff = Date.now() - 7 * 86400000
    } else if (this.selectedRange === '30') {
      cutoff = Date.now() - 30 * 86400000
    } else if (this.selectedRange === '90') {
      cutoff = Date.now() - 90 * 86400000
    }
    let filtered: HealthData[] = []
    for (let i = 0; i < this.allData.length; i++) {
      let it: HealthData = this.allData[i]
      let ts: number = new Date(it.recordTime).getTime()
      if (cutoff === 0 || ts >= cutoff) {
        filtered.push(it)
      }
    }
    filtered.sort((a: HealthData, b: HealthData) => {
      return new Date(a.recordTime).getTime() - new Date(b.recordTime).getTime()
    })
    let arr: ChartPoint[] = []
    for (let i = 0; i < filtered.length; i++) {
      arr.push({ v: this.getVal(filtered[i]), t: filtered[i].recordTime })
    }
    this.pts = arr
    this.selectedIndex = -1
    this.computeStats()
    this.draw()
  }

  computeStats(): void {
    if (this.pts.length === 0) {
      this.avgText = '-'
      this.maxText = '-'
      this.minText = '-'
      this.trendText = '—'
      this.trendColor = this.cInkFaint()
      return
    }
    let sum: number = 0
    let mx: number = -Number.MAX_VALUE
    let mn: number = Number.MAX_VALUE
    for (let i = 0; i < this.pts.length; i++) {
      sum += this.pts[i].v
      if (this.pts[i].v > mx) {
        mx = this.pts[i].v
      }
      if (this.pts[i].v < mn) {
        mn = this.pts[i].v
      }
    }
    this.avgText = (sum / this.pts.length).toFixed(1)
    this.maxText = mx.toFixed(1)
    this.minText = mn.toFixed(1)

    let half: number = Math.floor(this.pts.length / 2)
    if (half >= 1) {
      let f1: number = 0
      let f2: number = 0
      for (let i = 0; i < half; i++) {
        f1 += this.pts[i].v
      }
      for (let i = half; i < this.pts.length; i++) {
        f2 += this.pts[i].v
      }
      let avg1: number = f1 / half
      let avg2: number = f2 / (this.pts.length - half)
      if (avg1 === 0) {
        this.trendText = '—'
        this.trendColor = this.cInkFaint()
      } else {
        let delta: number = (avg2 - avg1) / avg1
        if (delta > 0.05) {
          this.trendText = '↑ 上升'
          this.trendColor = this.cDanger()
        } else if (delta < -0.05) {
          this.trendText = '↓ 下降'
          this.trendColor = this.cOk()
        } else {
          this.trendText = '→ 平稳'
          this.trendColor = this.cInkFaint()
        }
      }
    } else {
      this.trendText = '—'
      this.trendColor = this.cInkFaint()
    }
  }

  getMetricLabel(): string {
    if (this.selectedMetric === 'systolic') {
      return '收缩压'
    }
    if (this.selectedMetric === 'diastolic') {
      return '舒张压'
    }
    if (this.selectedMetric === 'bloodSugar') {
      return '血糖'
    }
    if (this.selectedMetric === 'heartRate') {
      return '心率'
    }
    return '体重'
  }

  getUnit(): string {
    if (this.selectedMetric === 'bloodPressure' || this.selectedMetric === 'systolic' || this.selectedMetric === 'diastolic') {
      return 'mmHg'
    }
    if (this.selectedMetric === 'bloodSugar') {
      return 'mmol/L'
    }
    if (this.selectedMetric === 'heartRate') {
      return 'bpm'
    }
    return 'kg'
  }

  // Canvas 需要字符串色值，这里按当前主题取
  private dark: boolean = false

  private pick(light: string, darkc: string): string {
    return this.dark ? darkc : light
  }

  private cInk(): string { return this.pick('#121C18', '#F2F6F4') }
  private cInkFaint(): string { return this.pick('#8B9893', '#6B7873') }
  private cDanger(): string { return this.pick('#C0392B', '#FF6F61') }
  private cOk(): string { return this.pick('#0F7A5C', '#46D6A6') }
  private cSurface(): string { return this.pick('#FFFFFF', '#151A19') }
  private cHairline(): string { return this.pick('rgba(16, 32, 26, 0.08)', 'rgba(255, 255, 255, 0.09)') }
  private cBand(): string { return this.pick('rgba(15, 122, 92, 0.06)', 'rgba(70, 214, 166, 0.08)') }
  private cBandLine(): string { return this.pick('rgba(15, 122, 92, 0.18)', 'rgba(70, 214, 166, 0.20)') }
  private cGuide(): string { return this.pick('rgba(16, 32, 26, 0.16)', 'rgba(255, 255, 255, 0.18)') }

  getLine(): string {
    if (this.selectedMetric === 'systolic' || this.selectedMetric === 'diastolic') {
      return this.pick('#0F7A5C', '#46D6A6')
    }
    if (this.selectedMetric === 'bloodSugar') {
      return this.pick('#1D7A93', '#5BC8E8')
    }
    if (this.selectedMetric === 'heartRate') {
      return this.pick('#B04A3A', '#FF8A76')
    }
    return this.pick('#5D7A33', '#B9D77E')
  }

  getRange(): number[] | null {
    if (this.selectedMetric === 'systolic') {
      return [90, 139]
    }
    if (this.selectedMetric === 'diastolic') {
      return [60, 89]
    }
    if (this.selectedMetric === 'bloodSugar') {
      return [3.9, 7.8]
    }
    if (this.selectedMetric === 'heartRate') {
      return [60, 100]
    }
    return null
  }

  inRange(v: number): boolean {
    let r: number[] | null = this.getRange()
    if (r === null) {
      return true
    }
    return v >= r[0] && v <= r[1]
  }

  xFor(i: number): number {
    let w: number = this.ctx.width
    let plotW: number = w - PAD_L - PAD_R
    if (this.pts.length <= 1) {
      return PAD_L + plotW / 2
    }
    return PAD_L + plotW * i / (this.pts.length - 1)
  }

  nearestIndex(x: number): number {
    let w: number = this.ctx.width
    let plotW: number = w - PAD_L - PAD_R
    let n: number = this.pts.length
    if (n === 0) {
      return -1
    }
    if (n === 1) {
      return 0
    }
    let rel: number = (x - PAD_L) / plotW
    if (rel < 0) {
      rel = 0
    }
    if (rel > 1) {
      rel = 1
    }
    return Math.round(rel * (n - 1))
  }

  fmtDate(iso: string): string {
    let d = new Date(iso)
    if (isNaN(d.getTime())) {
      return ''
    }
    let m = (d.getMonth() + 1).toString().padStart(2, '0')
    let day = d.getDate().toString().padStart(2, '0')
    return m + '-' + day
  }

  redraw(): void {
    this.draw()
  }

  draw(): void {
    if (!this.ready || this.ctx.width === 0) {
      return
    }
    let ctx: CanvasRenderingContext2D = this.ctx
    let w: number = ctx.width
    let h: number = ctx.height
    ctx.clearRect(0, 0, w, h)
    let n: number = this.pts.length
    if (n === 0) {
      return
    }
    let plotW: number = w - PAD_L - PAD_R
    let plotH: number = h - PAD_T - PAD_B

    let lo: number = Number.MAX_VALUE
    let hi: number = -Number.MAX_VALUE
    for (let i = 0; i < n; i++) {
      if (this.pts[i].v < lo) {
        lo = this.pts[i].v
      }
      if (this.pts[i].v > hi) {
        hi = this.pts[i].v
      }
    }
    let range: number[] | null = this.getRange()
    if (range !== null) {
      if (range[0] < lo) {
        lo = range[0]
      }
      if (range[1] > hi) {
        hi = range[1]
      }
    }
    if (lo === hi) {
      lo -= 1
      hi += 1
    }
    let padv: number = (hi - lo) * 0.14
    lo -= padv
    hi += padv
    if (lo < 0) {
      lo = 0
    }

    let yFor = (v: number): number => PAD_T + plotH * (1 - (v - lo) / (hi - lo))

    // 正常参考带
    if (range !== null) {
      let yTop: number = yFor(range[1])
      let yBot: number = yFor(range[0])
      ctx.fillStyle = this.cBand()
      ctx.fillRect(PAD_L, yTop, plotW, yBot - yTop)
      ctx.strokeStyle = this.cBandLine()
      ctx.lineWidth = 1
      ctx.setLineDash([4, 4])
      ctx.beginPath()
      ctx.moveTo(PAD_L, yTop)
      ctx.lineTo(w - PAD_R, yTop)
      ctx.moveTo(PAD_L, yBot)
      ctx.lineTo(w - PAD_R, yBot)
      ctx.stroke()
      ctx.setLineDash([])
    }

    // 网格 + Y 轴
    ctx.strokeStyle = this.cHairline()
    ctx.fillStyle = this.cInkFaint()
    ctx.lineWidth = 1
    ctx.font = '10px sans-serif'
    ctx.textAlign = 'right'
    ctx.textBaseline = 'middle'
    for (let g = 0; g <= 4; g++) {
      let val: number = lo + (hi - lo) * g / 4
      let y: number = yFor(val)
      ctx.beginPath()
      ctx.moveTo(PAD_L, y)
      ctx.lineTo(w - PAD_R, y)
      ctx.stroke()
      ctx.fillText(val.toFixed(0), PAD_L - 8, y)
    }

    let lineColor: string = this.getLine()

    // 折线 + 面积：用裁剪实现"从左往右画出"的生长动画
    ctx.save()
    let revealW: number = plotW * this.drawProgress + 2
    ctx.beginPath()
    ctx.rect(PAD_L, 0, revealW, h)
    ctx.clip()

    if (n > 1) {
      let grad = ctx.createLinearGradient(0, PAD_T, 0, PAD_T + plotH)
      grad.addColorStop(0, lineColor + '2E')
      grad.addColorStop(1, lineColor + '00')
      ctx.beginPath()
      ctx.moveTo(this.xFor(0), yFor(this.pts[0].v))
      for (let i = 1; i < n; i++) {
        ctx.lineTo(this.xFor(i), yFor(this.pts[i].v))
      }
      ctx.lineTo(this.xFor(n - 1), PAD_T + plotH)
      ctx.lineTo(this.xFor(0), PAD_T + plotH)
      ctx.closePath()
      ctx.fillStyle = grad
      ctx.fill()
    }

    ctx.strokeStyle = lineColor
    ctx.lineWidth = 2
    ctx.lineJoin = 'round'
    ctx.lineCap = 'round'
    ctx.beginPath()
    for (let i = 0; i < n; i++) {
      let x: number = this.xFor(i)
      let y: number = yFor(this.pts[i].v)
      if (i === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    }
    ctx.stroke()

    // 数据点
    for (let i = 0; i < n; i++) {
      let x: number = this.xFor(i)
      let y: number = yFor(this.pts[i].v)
      let selected: boolean = i === this.selectedIndex
      ctx.beginPath()
      ctx.fillStyle = selected ? lineColor : this.cSurface()
      ctx.strokeStyle = lineColor
      ctx.lineWidth = 1.5
      ctx.arc(x, y, selected ? 5 : 3, 0, Math.PI * 2)
      ctx.fill()
      ctx.stroke()
    }
    ctx.restore()

    // 选中辅助线
    if (this.selectedIndex >= 0 && this.selectedIndex < n) {
      let sx: number = this.xFor(this.selectedIndex)
      ctx.strokeStyle = this.cGuide()
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(sx, PAD_T)
      ctx.lineTo(sx, h - PAD_B)
      ctx.stroke()
    }

    // X 轴日期
    ctx.fillStyle = this.cInkFaint()
    ctx.font = '9px sans-serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'alphabetic'
    let step: number = Math.max(1, Math.ceil(n / 5))
    for (let i = 0; i < n; i += step) {
      ctx.fillText(this.fmtDate(this.pts[i].t), this.xFor(i), h - 8)
    }
    if ((n - 1) % step !== 0 && n > 1) {
      ctx.fillText(this.fmtDate(this.pts[n - 1].t), this.xFor(n - 1), h - 8)
    }
  }

  selectedTip(): string {
    if (this.selectedIndex < 0 || this.selectedIndex >= this.pts.length) {
      return '点击图中的点查看某天详情'
    }
    let p: ChartPoint = this.pts[this.selectedIndex]
    let flag: string = this.inRange(p.v) ? '正常范围内' : '超出正常范围'
    return this.fmtDate(p.t) + ' · ' + p.v + ' ' + this.getUnit() + ' · ' + flag
  }

  @Builder
  metricChip(opt: MetricOption) {
    Text(opt.label)
      .fontSize(T_SM)
      .fontWeight(this.selectedMetric === opt.key ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.selectedMetric === opt.key ? ON_PRIMARY : INK_SUB)
      .backgroundColor(this.selectedMetric === opt.key ? JADE : SURFACE)
      .border({ width: 1, color: this.selectedMetric === opt.key ? JADE : HAIRLINE })
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(R_PILL)
      .margin({ right: 8 })
      .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
      .onClick(() => {
        if (this.selectedMetric === opt.key) {
          return
        }
        this.selectedMetric = opt.key
        this.refresh()
        this.animateChart()
      })
  }

  @Builder
  rangeChip(opt: RangeOption) {
    Text(opt.label)
      .fontSize(T_CAP)
      .fontColor(this.selectedRange === opt.key ? JADE : INK_FAINT)
      .backgroundColor(this.selectedRange === opt.key ? JADE_SOFT : Color.Transparent)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(R_PILL)
      .margin({ right: 6 })
      .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
      .onClick(() => {
        if (this.selectedRange === opt.key) {
          return
        }
        this.selectedRange = opt.key
        this.refresh()
        this.animateChart()
      })
  }

  @Builder
  statCell(opt: StatItem) {
    Column() {
      Text(opt.value)
        .fontSize(T_H3)
        .fontWeight(FontWeight.Medium)
        .fontColor(opt.color)
      Text(opt.label)
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      NavBar({ title: '趋势分析' })

      Scroll() {
        Row() {
          ForEach(this.metrics, (m: MetricOption) => {
            this.metricChip(m)
          }, (m: MetricOption) => m.key + '_' + (this.selectedMetric === m.key ? 1 : 0))
        }
        .padding({ left: 20, right: 20 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ bottom: 10 })

      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            // 图表卡
            Column() {
              Row() {
                Column() {
                  Text(this.getMetricLabel())
                    .fontSize(T_H3)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(INK)
                  Text(this.getUnit())
                    .fontSize(T_MICRO)
                    .fontColor(INK_FAINT)
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                Blank()
              }
              .width('100%')

              Row() {
                ForEach(this.ranges, (r: RangeOption) => {
                  this.rangeChip(r)
                }, (r: RangeOption) => r.key + '_' + (this.selectedRange === r.key ? 1 : 0))
              }
              .width('100%')
              .margin({ top: 10, bottom: 4 })

              if (this.pts.length === 0) {
                Column() {
                  StateView({
                    kind: 'empty',
                    title: '该时间范围内暂无数据',
                    desc: '换一个时间范围，或先记录一次数据',
                    icon: $r('app.media.ic_bar_chart')
                  })
                }
                .width('100%')
                .height(220)
                .justifyContent(FlexAlign.Center)
              } else {
                Canvas(this.ctx)
                  .width('100%')
                  .height(226)
                  .onReady(() => {
                    this.ready = true
                    this.draw()
                    this.animateChart()
                  })
                  .onTouch((e: TouchEvent) => {
                    if (e.type === TouchType.Down || e.type === TouchType.Move) {
                      let x: number = e.touches[0].x
                      this.selectedIndex = this.nearestIndex(x)
                      this.draw()
                    }
                  })

                Text(this.selectedTip())
                  .fontSize(T_MICRO)
                  .fontColor(this.selectedIndex >= 0 ? INK_SUB : INK_FAINT)
                  .width('100%')
                  .margin({ top: 6 })

                Row() {
                  this.legend(this.cOk(), '正常范围')
                  this.legend(this.cDanger(), '超出范围')
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .margin({ top: 8 })
              }
            }
            .width('100%')
            .padding(18)
            .backgroundColor(SURFACE)
            .borderRadius(R_LG)
            .border({ width: 1, color: HAIRLINE })

            // 统计小结
            if (this.pts.length > 0) {
              Row() {
                this.statCell({ label: '平均', value: this.avgText, color: this.cInk() })
                this.statCell({ label: '最高', value: this.maxText, color: this.cInk() })
                this.statCell({ label: '最低', value: this.minText, color: this.cInk() })
                this.statCell({ label: '趋势', value: this.trendText, color: this.trendColor })
              }
              .width('100%')
              .padding({ top: 16, bottom: 16 })
              .backgroundColor(SURFACE)
              .borderRadius(R_LG)
              .border({ width: 1, color: HAIRLINE })
              .margin({ top: 12, bottom: 24 })
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
      .layoutWeight(1)
      .onRefreshing(async () => {
        await this.reloadData()
        this.refreshing = false
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }

  @Builder
  legend(color: string, label: string) {
    Row() {
      Circle()
        .width(6)
        .height(6)
        .fill(color)
      Text(label)
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .margin({ left: 5 })
    }
    .margin({ left: 10, right: 10 })
  }
}
