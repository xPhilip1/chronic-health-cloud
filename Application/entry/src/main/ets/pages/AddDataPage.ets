import { addHealthData } from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_SUNK, HAIRLINE, INK, INK_SUB, INK_FAINT,
  JADE, JADE_SOFT, DANGER, DANGER_SOFT, OK, OK_SOFT, BRASS, BRASS_SOFT,
  M_BP, M_SUGAR, M_HR, M_WEIGHT, M_EXERCISE,
  R_LG, R_MD, R_PILL, R_XS, T_H3, T_BODY, T_SM, T_CAP, T_MICRO, D_BASE
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { GradientButton } from '../components/GradientButton'

const EXERCISE_TYPES: string[] = ['散步', '快走', '慢跑', '骑车', '游泳', '太极', '其他']

@Entry
@Component
struct AddDataPage {
  @State systolic: string = ''
  @State diastolic: string = ''
  @State bloodSugar: string = ''
  @State heartRate: string = ''
  @State weight: string = ''
  @State exerciseType: string = ''
  @State exerciseDuration: string = ''
  @State exerciseCalories: string = ''
  @State notes: string = ''

  @State isSaving: boolean = false
  @State errorMsg: string = ''
  @State successMsg: string = ''
  @State formIn: boolean = false

  aboutToAppear(): void {
    setTimeout(() => {
      this.formIn = true
    }, 40)
  }

  async handleSave(): Promise<void> {
    this.errorMsg = ''
    this.successMsg = ''

    let dur: number = this.exerciseDuration === '' ? 0 : Number(this.exerciseDuration)
    let cal: number = this.exerciseCalories === '' ? 0 : Number(this.exerciseCalories)
    let hasExercise: boolean = this.exerciseType !== '' || this.exerciseDuration !== '' || this.exerciseCalories !== ''

    if (this.systolic === '' && this.bloodSugar === '' && this.heartRate === '' && this.weight === '' && !hasExercise) {
      this.errorMsg = '请至少填写一项健康或运动数据'
      return
    }

    let sys: number = this.systolic === '' ? 0 : Number(this.systolic)
    let dia: number = this.diastolic === '' ? 0 : Number(this.diastolic)
    let sugar: number = this.bloodSugar === '' ? 0 : Number(this.bloodSugar)
    let hr: number = this.heartRate === '' ? 0 : Number(this.heartRate)
    let wt: number = this.weight === '' ? 0 : Number(this.weight)

    if (isNaN(sys) || isNaN(dia) || isNaN(sugar) || isNaN(hr) || isNaN(wt) || isNaN(dur) || isNaN(cal)) {
      this.errorMsg = '请输入有效的数字'
      return
    }

    this.isSaving = true
    try {
      await addHealthData(sys, dia, sugar, hr, wt, this.notes, this.exerciseType, dur, cal)
      this.successMsg = '已保存'
      setTimeout(() => {
        try {
          this.getUIContext().getRouter().back()
        } catch (e) {
          console.error('返回失败: ' + (e as Error).message)
        }
      }, 900)
    } catch (e) {
      this.errorMsg = (e as Error).message
    } finally {
      this.isSaving = false
    }
  }

  @Builder
  sectionHead(title: string, color: Resource) {
    Row() {
      Column()
        .width(3)
        .height(13)
        .borderRadius(2)
        .backgroundColor(color)
        .margin({ right: 8 })
      Text(title)
        .fontSize(T_SM)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
    }
    .width('100%')
    .margin({ bottom: 4 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  metricRow(label: string, placeholder: string, value: string, unit: string, isDecimal: boolean, color: Resource, onChange: (v: string) => void) {
    Row() {
      Row() {
        Circle()
          .width(5)
          .height(5)
          .fill(color)
          .margin({ right: 7 })
        Text(label)
          .fontSize(T_SM)
          .fontColor(INK_SUB)
      }
      .width(88)

      TextInput({ placeholder: placeholder, text: value })
        .layoutWeight(1)
        .height(46)
        .fontSize(T_BODY)
        .fontColor(INK)
        .placeholderColor(INK_FAINT)
        .textAlign(TextAlign.End)
        .type(isDecimal ? InputType.NUMBER_DECIMAL : InputType.Number)
        .backgroundColor(SURFACE_SUNK)
        .borderRadius(R_MD)
        .padding({ left: 12, right: 12 })
        .onChange(onChange)

      Text(unit)
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .width(52)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  exerciseChip(label: string) {
    Text(label)
      .fontSize(T_SM)
      .fontColor(this.exerciseType === label ? JADE : INK_SUB)
      .backgroundColor(this.exerciseType === label ? JADE_SOFT : SURFACE_SUNK)
      .border({ width: 1, color: this.exerciseType === label ? JADE_SOFT : Color.Transparent })
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(R_PILL)
      .margin({ right: 8, bottom: 8 })
      .animation({ duration: D_BASE, curve: Curve.FastOutSlowIn })
      .onClick(() => {
        this.exerciseType = this.exerciseType === label ? '' : label
      })
  }

  build() {
    Column() {
      NavBar({ title: '添加健康数据' })

      Scroll() {
        Column() {
          // 身体指标
          Column() {
            this.sectionHead('身体指标', M_BP)
            this.metricRow('收缩压', '120', this.systolic, 'mmHg', false, M_BP, (v: string) => { this.systolic = v })
            Divider().color(HAIRLINE).strokeWidth(1).opacity(0.6)
            this.metricRow('舒张压', '80', this.diastolic, 'mmHg', false, M_BP, (v: string) => { this.diastolic = v })
            Divider().color(HAIRLINE).strokeWidth(1).opacity(0.6)
            this.metricRow('血糖', '5.6', this.bloodSugar, 'mmol/L', true, M_SUGAR, (v: string) => { this.bloodSugar = v })
            Divider().color(HAIRLINE).strokeWidth(1).opacity(0.6)
            this.metricRow('心率', '72', this.heartRate, 'bpm', false, M_HR, (v: string) => { this.heartRate = v })
            Divider().color(HAIRLINE).strokeWidth(1).opacity(0.6)
            this.metricRow('体重', '65.5', this.weight, 'kg', true, M_WEIGHT, (v: string) => { this.weight = v })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 8 })
          .backgroundColor(SURFACE)
          .borderRadius(R_LG)
          .border({ width: 1, color: HAIRLINE })

          // 运动
          Column() {
            this.sectionHead('运动记录（可选）', M_EXERCISE)

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(EXERCISE_TYPES, (t: string) => {
                this.exerciseChip(t)
              }, (t: string) => t + '_' + (this.exerciseType === t ? 1 : 0))
            }
            .width('100%')
            .margin({ top: 10 })

            Row() {
              Column() {
                Text('时长')
                  .fontSize(T_MICRO)
                  .fontColor(INK_FAINT)
                TextInput({ placeholder: '30', text: this.exerciseDuration })
                  .height(44)
                  .fontSize(T_BODY)
                  .fontColor(INK)
                  .placeholderColor(INK_FAINT)
                  .type(InputType.Number)
                  .backgroundColor(SURFACE_SUNK)
                  .borderRadius(R_MD)
                  .padding({ left: 12, right: 12 })
                  .margin({ top: 6 })
                  .onChange((v: string) => { this.exerciseDuration = v })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column() {
                Text('消耗')
                  .fontSize(T_MICRO)
                  .fontColor(INK_FAINT)
                TextInput({ placeholder: '150', text: this.exerciseCalories })
                  .height(44)
                  .fontSize(T_BODY)
                  .fontColor(INK)
                  .placeholderColor(INK_FAINT)
                  .type(InputType.Number)
                  .backgroundColor(SURFACE_SUNK)
                  .borderRadius(R_MD)
                  .padding({ left: 12, right: 12 })
                  .margin({ top: 6 })
                  .onChange((v: string) => { this.exerciseCalories = v })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(SURFACE)
          .borderRadius(R_LG)
          .border({ width: 1, color: HAIRLINE })
          .margin({ top: 12 })

          // 备注
          Column() {
            this.sectionHead('备注（可选）', INK_FAINT)
            TextArea({ placeholder: '记录一下今天的身体感受…', text: this.notes })
              .height(84)
              .fontSize(T_SM)
              .fontColor(INK)
              .placeholderColor(INK_FAINT)
              .backgroundColor(SURFACE_SUNK)
              .borderRadius(R_MD)
              .margin({ top: 8 })
              .onChange((value: string) => {
                this.notes = value
              })
          }
          .width('100%')
          .padding(16)
          .backgroundColor(SURFACE)
          .borderRadius(R_LG)
          .border({ width: 1, color: HAIRLINE })
          .margin({ top: 12 })

          // 提示
          if (this.errorMsg !== '') {
            Row() {
              Image($r('app.media.ic_warning'))
                .width(14)
                .height(14)
                .fillColor(DANGER)
              Text(this.errorMsg)
                .fontSize(T_CAP)
                .fontColor(DANGER)
                .margin({ left: 6 })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(DANGER_SOFT)
            .borderRadius(R_MD)
            .margin({ top: 12 })
          }

          if (this.successMsg !== '') {
            Row() {
              Image($r('app.media.ic_check'))
                .width(14)
                .height(14)
                .fillColor(OK)
              Text(this.successMsg)
                .fontSize(T_CAP)
                .fontColor(OK)
                .margin({ left: 6 })
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(OK_SOFT)
            .borderRadius(R_MD)
            .margin({ top: 12 })
          }

          Column().height(16)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 4 })
        .translate({ y: this.formIn ? 0 : 12 })
        .opacity(this.formIn ? 1 : 0)
        .animation({ duration: 380, curve: Curve.FastOutSlowIn })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Column() {
        GradientButton({
          text: this.isSaving ? '保存中…' : '保 存',
          enabledState: !this.isSaving,
          onTap: () => {
            this.handleSave()
          }
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 10, bottom: 16 })
      .backgroundColor(CANVAS)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }
}
