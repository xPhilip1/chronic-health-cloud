import { HealthData } from '../model/HealthModel'
import { getHealthDataList } from '../service/ApiService'
import {
  CANVAS, SURFACE, SURFACE_SUNK, HAIRLINE, INK, INK_SUB, INK_FAINT,
  JADE, JADE_SOFT, DANGER, DANGER_SOFT, OK_SOFT,
  M_BP, M_BP_BG, M_SUGAR, M_SUGAR_BG, M_HR, M_HR_BG, M_WEIGHT, M_WEIGHT_BG,
  M_EXERCISE, M_EXERCISE_BG, R_LG, R_MD, R_PILL, R_XS,
  T_H3, T_BODY, T_SM, T_CAP, T_MICRO
} from '../common/Theme'
import { NavBar } from '../components/NavBar'
import { StateView } from '../components/StateView'

interface MiniMetric {
  label: string
  value: string
  unit: string
  color: Resource
  bg: Resource
  abnormal: boolean
}

@Entry
@Component
struct HealthDataPage {
  @State dataList: HealthData[] = []
  @State isLoading: boolean = true
  @State refreshing: boolean = false

  async aboutToAppear(): Promise<void> {
    await this.loadData()
  }

  async loadData(): Promise<void> {
    this.dataList = await getHealthDataList()
    this.isLoading = false
  }

  formatTime(isoStr: string): string {
    let parts: string[] = isoStr.split('T')
    if (parts.length < 2) {
      return isoStr
    }
    let date: string = parts[0]
    let time: string = parts[1].substring(0, 5)
    return date + ' ' + time
  }

  exerciseSummary(item: HealthData): string {
    let seg: string[] = []
    if (item.exerciseType !== '') {
      seg.push(item.exerciseType)
    }
    if (item.exerciseDuration > 0) {
      seg.push(item.exerciseDuration + ' 分钟')
    }
    if (item.exerciseCalories > 0) {
      seg.push(item.exerciseCalories + ' kcal')
    }
    return seg.join(' · ')
  }

  bpBad(item: HealthData): boolean {
    let sys: boolean = item.bloodPressureSystolic > 0 &&
      (item.bloodPressureSystolic < 90 || item.bloodPressureSystolic > 139)
    let dia: boolean = item.bloodPressureDiastolic > 0 &&
      (item.bloodPressureDiastolic < 60 || item.bloodPressureDiastolic > 89)
    return sys || dia
  }

  sugarBad(item: HealthData): boolean {
    return item.bloodSugar > 0 && (item.bloodSugar < 3.9 || item.bloodSugar > 7.8)
  }

  hrBad(item: HealthData): boolean {
    return item.heartRate > 0 && (item.heartRate < 60 || item.heartRate > 100)
  }

  isAbnormal(item: HealthData): boolean {
    return this.bpBad(item) || this.sugarBad(item) || this.hrBad(item)
  }

  @Builder
  miniMetric(m: MiniMetric) {
    Column() {
      Text(m.label)
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
      Text(m.value)
        .fontSize(T_H3)
        .fontWeight(FontWeight.Medium)
        .fontColor(m.abnormal ? DANGER : INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
      Text(m.unit)
        .fontSize(T_MICRO)
        .fontColor(INK_FAINT)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 10, bottom: 10, left: 12, right: 12 })
    .backgroundColor(SURFACE_SUNK)
    .borderRadius(R_MD)
  }

  @Builder
  dataCard(item: HealthData) {
    Column() {
      Row() {
        Text(this.formatTime(item.recordTime))
          .fontSize(T_CAP)
          .fontColor(INK_FAINT)
        Blank()
        if (this.isAbnormal(item)) {
          Text('需关注')
            .fontSize(T_MICRO)
            .fontColor(DANGER)
            .backgroundColor(DANGER_SOFT)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(R_XS)
            .margin({ right: 8 })
        }
        Text(item.dataSource === 'doctor_input' ? '医生录入' : (item.dataSource === 'device' ? '设备同步' : '手动录入'))
          .fontSize(T_MICRO)
          .fontColor(INK_FAINT)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        this.miniMetric({
          label: '血压',
          value: item.bloodPressureSystolic > 0 ? item.bloodPressureSystolic + '/' + item.bloodPressureDiastolic : '—',
          unit: 'mmHg',
          color: M_BP,
          bg: M_BP_BG,
          abnormal: this.bpBad(item)
        })
        this.miniMetric({
          label: '血糖',
          value: item.bloodSugar > 0 ? item.bloodSugar.toString() : '—',
          unit: 'mmol/L',
          color: M_SUGAR,
          bg: M_SUGAR_BG,
          abnormal: this.sugarBad(item)
        })
      }
      .width('100%')
      .margin({ top: 12 })

      Row({ space: 8 }) {
        this.miniMetric({
          label: '心率',
          value: item.heartRate > 0 ? item.heartRate.toString() : '—',
          unit: 'bpm',
          color: M_HR,
          bg: M_HR_BG,
          abnormal: this.hrBad(item)
        })
        this.miniMetric({
          label: '体重',
          value: item.weight > 0 ? item.weight.toString() : '—',
          unit: 'kg',
          color: M_WEIGHT,
          bg: M_WEIGHT_BG,
          abnormal: false
        })
      }
      .width('100%')
      .margin({ top: 8 })

      if (item.exerciseType !== '' || item.exerciseDuration > 0 || item.exerciseCalories > 0) {
        Row() {
          Image($r('app.media.ic_exercise'))
            .width(13)
            .height(13)
            .fillColor(M_EXERCISE)
            .margin({ right: 6 })
          Text(this.exerciseSummary(item))
            .fontSize(T_CAP)
            .fontColor(M_EXERCISE)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .margin({ top: 10 })
        .backgroundColor(M_EXERCISE_BG)
        .borderRadius(R_XS)
      }

      if (item.notes !== '') {
        Text('备注 · ' + item.notes)
          .fontSize(T_CAP)
          .fontColor(INK_SUB)
          .width('100%')
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SURFACE)
    .borderRadius(R_LG)
    .border({ width: 1, color: HAIRLINE })
  }

  build() {
    Column() {
      NavBar({
        title: '健康记录',
        rightText: '添加',
        onRight: () => {
          try {
            this.getUIContext().getRouter().pushUrl({ url: 'pages/AddDataPage' })
          } catch (e) {
            console.error('跳转失败: ' + (e as Error).message)
          }
        }
      })

      if (this.isLoading) {
        Column() {
          StateView({ kind: 'loading', title: '正在加载记录' })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.dataList.length === 0) {
        Column() {
          StateView({
            kind: 'empty',
            title: '还没有健康记录',
            desc: '每次测量后记一笔，趋势与报告都会更准确',
            actionText: '记录第一条',
            icon: $r('app.media.ic_data_records'),
            onAction: () => {
              try {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/AddDataPage' })
              } catch (e) {
                console.error('跳转失败: ' + (e as Error).message)
              }
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Refresh({ refreshing: $$this.refreshing }) {
          List({ space: 12 }) {
            ForEach(this.dataList, (item: HealthData) => {
              ListItem() {
                this.dataCard(item)
              }
            }, (item: HealthData) => item.dataId.toString())
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20, top: 4, bottom: 20 })
          .scrollBar(BarState.Off)
        }
        .layoutWeight(1)
        .onRefreshing(async () => {
          await this.loadData()
          this.refreshing = false
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CANVAS)
  }
}
