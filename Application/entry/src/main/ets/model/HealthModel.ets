// 健康数据记录
export interface HealthData {
  dataId: number
  userId: number
  bloodPressureSystolic: number      // 收缩压 （高压）
  bloodPressureDiastolic: number     // 舒张压 （低压）
  bloodSugar: number                 // 血糖 mmol/L
  weight: number                     // 体重 kg
  heartRate: number                  // 心率 次/分钟
  exerciseType: string               // 运动类型（如 散步/慢跑/骑车/游泳/其他，空=未记录）
  exerciseDuration: number           // 运动时长 分钟
  exerciseCalories: number           // 消耗热量 kcal
  recordTime: string                 // 记录时间
  dataSource: string                 // 'user_input' | 'device' | 'doctor_input'
  notes: string                      // 备注
}

// 健康趋势数据点
export interface TrendPoint {
  value: number
  time: string
}

// 健康预警
export interface HealthWarning {
  warningId: number
  userId: number
  warningType: string                // 'high_blood_pressure' | 'low_blood_sugar' | 'high_blood_sugar' | 'other'
  warningMessage: string
  warningTime: string
  acknowledged: boolean               // 确认与否
  severity: string                   // 'low' | 'medium' | 'high'
}

// 健康建议
export interface HealthAdvice {
  adviceId: number
  userId: number
  adviceType: string                 // 'diet' | 'exercise' | 'lifestyle'
  adviceMessage: string
  generatedAt: string
  source: string                     // 'auto' | 'doctor'
}

// 健康报告
export interface HealthReport {
  reportId: number
  userId: number
  reportTitle: string
  generatedAt: string
  reportType: string                 // 'regular' | 'monthly' | 'doctor'
  pdfAvailable: boolean
}

// ==================== AI 结构化健康报告（服务端 DeepSeek 生成） ====================

// 单个指标解读
export interface AiMetricRead {
  name: string        // 指标名
  status: string      // 状态：正常/偏高/偏低/波动大 等
  detail: string      // 结合数值的具体解读与建议
}

// 整份 AI 健康报告，字段须与云函数归一化输出逐字一致
export interface AiHealthReport {
  riskLevel: string                  // 'low' | 'medium' | 'high'
  overallAssessment: string          // 总体评估
  metrics: AiMetricRead[]            // 逐项指标解读（仅含已填写的指标）
  trendAnalysis: string              // 趋势分析
  dietAdvice: string                 // 饮食建议
  exerciseAdvice: string             // 运动建议
  lifestyleAdvice: string            // 生活方式建议
  followUpAdvice: string             // 复查与就医提醒
  redFlags: string                   // 危险信号
}

// 本地缓存结构：报告 + 生成时间 + 参与统计的数据条数
export interface AiReportCache {
  report: AiHealthReport
  generatedAt: string
  sampleCount: number
}
