import {
  INK, INK_SUB, INK_FAINT, DANGER, DANGER_SOFT, HAIRLINE,
  T_HERO, T_MICRO, TRACK_LABEL, R_PILL, D_BASE, isDarkNow
} from '../common/Theme'

interface LegendItem {
  dot: string
  name: string
  value: string
  valueColor: Resource
}

// 健康仪表盘 v2：四段弧 + 外圈刻度 + 中央超大数值。
// 弧长按"达标程度"生长，超标段颜色转为警示色并加深；轻点切换中央指标。
// 视觉目标是"医用仪表的精度感"，所以用刻度环、宽字距标签、超大数字，而不是卡片堆叠。
@Component
export struct HealthRing {
  @Prop @Watch('redraw') systolic: number = 0
  @Prop @Watch('redraw') diastolic: number = 0
  @Prop @Watch('redraw') bloodSugar: number = 0
  @Prop @Watch('redraw') heartRate: number = 0
  @Prop @Watch('redraw') weight: number = 0

  @State centerIndex: number = 0
  @State @Watch('redraw') progress: number = 0
  @State centerOpacity: number = 1

  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)
  private ready: boolean = false

  private ringSize: number = 264
  private strokeW: number = 8
  private gapDeg: number = 26

  aboutToAppear(): void {
    // Canvas 只能接收字符串色值，先记录当前主题，绘制时据此选色
    this.dark = isDarkNow()
    setTimeout(() => {
      try {
        this.getUIContext().animateTo({ duration: 1000, curve: Curve.FastOutSlowIn }, () => {
          this.progress = 1
        })
      } catch (e) {
        this.progress = 1
        this.draw()
      }
    }, 120)
  }

  scoreOf(v: number, lo: number, hi: number, floor: number, ceil: number): number {
    if (v <= 0) {
      return 0
    }
    if (v >= lo && v <= hi) {
      return 1
    }
    if (v < lo) {
      let d: number = lo - floor
      return d <= 0 ? 0 : Math.max(0, (v - floor) / d)
    }
    let d2: number = ceil - hi
    return d2 <= 0 ? 0 : Math.max(0, (ceil - v) / d2)
  }

  bpScore(): number { return this.scoreOf(this.systolic, 90, 139, 60, 200) }
  sugarScore(): number { return this.scoreOf(this.bloodSugar, 3.9, 7.8, 2.8, 15) }
  hrScore(): number { return this.scoreOf(this.heartRate, 60, 100, 40, 180) }
  weightScore(): number { return this.weight > 0 ? 1 : 0 }

  scoreOfIndex(i: number): number {
    if (i === 0) { return this.bpScore() }
    if (i === 1) { return this.sugarScore() }
    if (i === 2) { return this.hrScore() }
    return this.weightScore()
  }

  // Canvas 与图例圆点需要字符串色值，这里本地维护一份双主题色板
  private dark: boolean = false

  private pick(light: string, darkc: string): string {
    return this.dark ? darkc : light
  }

  baseColor(i: number): string {
    let list: string[] = [
      this.pick('#0F7A5C', '#46D6A6'),
      this.pick('#1D7A93', '#5BC8E8'),
      this.pick('#B04A3A', '#FF8A76'),
      this.pick('#5D7A33', '#B9D77E')
    ]
    return list[i]
  }

  dangerColor(): string {
    return this.pick('#C0392B', '#FF6F61')
  }

  trackColor(): string {
    return this.pick('rgba(16, 32, 26, 0.07)', 'rgba(255, 255, 255, 0.08)')
  }

  tickStrong(): string {
    return this.pick('rgba(16, 32, 26, 0.16)', 'rgba(255, 255, 255, 0.16)')
  }

  tickWeak(): string {
    return this.pick('rgba(16, 32, 26, 0.06)', 'rgba(255, 255, 255, 0.06)')
  }

  hasData(i: number): boolean {
    if (i === 0) { return this.systolic > 0 }
    if (i === 1) { return this.bloodSugar > 0 }
    if (i === 2) { return this.heartRate > 0 }
    return this.weight > 0
  }

  abnormal(i: number): boolean {
    if (i === 3) { return false }
    return this.hasData(i) && this.scoreOfIndex(i) < 0.999
  }

  // 正常用指标色；超标转警示色，一眼能看出是哪一项出了范围
  metricDisplay(i: number): string {
    return this.abnormal(i) ? this.dangerColor() : this.baseColor(i)
  }

  centerValue(): string {
    if (this.centerIndex === 1) { return this.bloodSugar > 0 ? this.bloodSugar.toString() : '—' }
    if (this.centerIndex === 2) { return this.heartRate > 0 ? this.heartRate.toString() : '—' }
    if (this.centerIndex === 3) { return this.weight > 0 ? this.weight.toString() : '—' }
    return this.systolic > 0 ? this.systolic + '/' + this.diastolic : '—'
  }

  centerName(): string {
    let names: string[] = ['血压', '血糖', '心率', '体重']
    return names[this.centerIndex]
  }

  centerUnit(): string {
    let units: string[] = ['mmHg', 'mmol/L', 'bpm', 'kg']
    return units[this.centerIndex]
  }

  centerColor(): string {
    if (this.centerIndex === 3 && this.weight <= 0) { return this.pick('#8B9893', '#6B7873') }
    return this.metricDisplay(this.centerIndex)
  }

  nextMetric(): void {
    try {
      this.getUIContext().animateTo({ duration: 110, curve: Curve.EaseIn }, () => {
        this.centerOpacity = 0
      })
    } catch (e) {
      this.centerOpacity = 0
    }
    setTimeout(() => {
      this.centerIndex = (this.centerIndex + 1) % 4
      this.draw()
      try {
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.centerOpacity = 1
        })
      } catch (e) {
        this.centerOpacity = 1
      }
    }, 110)
  }

  redraw(): void {
    if (this.ready) { this.draw() }
  }

  draw(): void {
    if (!this.ready || this.ctx.width === 0) { return }
    let ctx: CanvasRenderingContext2D = this.ctx
    let w: number = ctx.width
    let h: number = ctx.height
    ctx.clearRect(0, 0, w, h)
    let cx: number = w / 2
    let cy: number = h / 2
    let R: number = Math.min(w, h) / 2 - this.strokeW / 2 - 18
    let spanDeg: number = 90 - this.gapDeg
    let fullSpanRad: number = spanDeg * Math.PI / 180

    // 外圈刻度：60 格，每 5 格加长，做出仪表盘质感
    for (let t = 0; t < 60; t++) {
      let ang: number = (t * 6 - 90) * Math.PI / 180
      let long: boolean = t % 5 === 0
      let r1: number = R + 10
      let r2: number = R + (long ? 16 : 13)
      ctx.beginPath()
      ctx.strokeStyle = long ? this.tickStrong() : this.tickWeak()
      ctx.lineWidth = 1
      ctx.moveTo(cx + Math.cos(ang) * r1, cy + Math.sin(ang) * r1)
      ctx.lineTo(cx + Math.cos(ang) * r2, cy + Math.sin(ang) * r2)
      ctx.stroke()
    }

    ctx.lineCap = 'round'

    for (let i = 0; i < 4; i++) {
      let selected: boolean = i === this.centerIndex
      let startRad: number = (-90 + i * 90 + this.gapDeg / 2) * Math.PI / 180

      // 轨道
      ctx.lineWidth = selected ? this.strokeW + 1 : this.strokeW
      ctx.strokeStyle = this.trackColor()
      ctx.beginPath()
      ctx.arc(cx, cy, R, startRad, startRad + fullSpanRad)
      ctx.stroke()

      // 数据弧
      if (this.hasData(i)) {
        let ratio: number = this.scoreOfIndex(i)
        if (ratio < 0.08) { ratio = 0.08 }
        let arcRad: number = fullSpanRad * ratio * this.progress
        let color: string = this.metricDisplay(i)
        ctx.strokeStyle = color
        ctx.lineWidth = selected ? this.strokeW + 2 : this.strokeW
        if (selected) {
          ctx.shadowBlur = 16
          ctx.shadowColor = color
        }
        ctx.beginPath()
        ctx.arc(cx, cy, R, startRad, startRad + arcRad)
        ctx.stroke()
        ctx.shadowBlur = 0
      }
    }
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Canvas(this.ctx)
          .width(this.ringSize)
          .height(this.ringSize)
          .onReady(() => {
            this.ready = true
            this.draw()
          })

        Column() {
          Text(this.centerName())
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .letterSpacing(TRACK_LABEL)
          Text(this.centerValue())
            .fontSize(this.centerIndex === 0 ? 44 : T_HERO)
            .fontWeight(FontWeight.Medium)
            .fontColor(INK)
            .letterSpacing(-1)
            .margin({ top: 2 })
          Text(this.centerUnit())
            .fontSize(T_MICRO)
            .fontColor(INK_FAINT)
            .letterSpacing(1)
            .margin({ top: 2 })

          if (this.abnormal(this.centerIndex)) {
            Text('超出范围')
              .fontSize(9.5)
              .fontColor(DANGER)
              .backgroundColor(DANGER_SOFT)
              .borderRadius(R_PILL)
              .padding({ left: 9, right: 9, top: 3, bottom: 3 })
              .margin({ top: 10 })
          }
        }
        .opacity(this.centerOpacity)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width(this.ringSize)
      .height(this.ringSize)
      .onClick(() => {
        this.nextMetric()
      })

      // 图例：四行两列，只有发丝线分隔
      Column() {
        Divider().color(HAIRLINE).strokeWidth(1)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          this.legend({ dot: this.metricDisplay(0), name: '血压', value: this.systolic > 0 ? this.systolic + '/' + this.diastolic : '—', valueColor: this.systolic > 0 ? INK : INK_FAINT })
          this.legend({ dot: this.metricDisplay(1), name: '血糖', value: this.bloodSugar > 0 ? this.bloodSugar.toString() : '—', valueColor: this.bloodSugar > 0 ? INK : INK_FAINT })
          this.legend({ dot: this.metricDisplay(2), name: '心率', value: this.heartRate > 0 ? this.heartRate.toString() : '—', valueColor: this.heartRate > 0 ? INK : INK_FAINT })
          this.legend({ dot: this.metricDisplay(3), name: '体重', value: this.weight > 0 ? this.weight.toString() : '—', valueColor: this.weight > 0 ? INK : INK_FAINT })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  legend(opt: LegendItem) {
    Row() {
      Circle()
        .width(5)
        .height(5)
        .fill(opt.dot)
      Text(opt.name)
        .fontSize(T_MICRO)
        .fontColor(INK_SUB)
        .letterSpacing(0.6)
        .margin({ left: 7 })
      Blank()
      Text(opt.value)
        .fontSize(T_MICRO)
        .fontWeight(FontWeight.Medium)
        .fontColor(opt.valueColor)
    }
    .width('47%')
    .padding({ top: 10, bottom: 10 })
  }
}
