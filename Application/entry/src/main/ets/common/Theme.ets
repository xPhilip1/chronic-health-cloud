// ============================================================
// 设计系统 v2.2 · 双主题（浅色 / 深色）
//
// 颜色不再写死成字符串，而是指向资源色：$r('app.color.*')。
// 两套数值分别放在：
//   resources/base/element/color.json   —— 浅色（默认）
//   resources/dark/element/color.json   —— 深色
// 运行时通过 ApplicationContext.setColorMode() 切换，ArkUI 会用对应的
// 资源色重绘整个界面，所以 30 多个页面不需要各自接状态变量。
//
// 注意：Canvas 绘制（健康环、趋势图）需要字符串而非 Resource，
// 那两个文件内部维护了一份本地色板，用 isDarkNow() 选择。
// ============================================================
import { ConfigurationConstant } from '@kit.AbilityKit'

// ---------- 画布与表面 ----------
export const CANVAS: Resource = $r('app.color.canvas')
export const CANVAS_2: Resource = $r('app.color.canvas_2')
export const SURFACE: Resource = $r('app.color.surface')
export const SURFACE_2: Resource = $r('app.color.surface_2')
export const SURFACE_3: Resource = $r('app.color.surface_3')
export const HAIRLINE: Resource = $r('app.color.hairline')
export const HAIRLINE_STRONG: Resource = $r('app.color.hairline_strong')

// ---------- 文字 ----------
export const INK: Resource = $r('app.color.ink')
export const INK_SUB: Resource = $r('app.color.ink_sub')
export const INK_FAINT: Resource = $r('app.color.ink_faint')
export const ON_PRIMARY: Resource = $r('app.color.on_primary')

// ---------- 品牌 / 强调 ----------
export const MINT: Resource = $r('app.color.mint')
export const MINT_DEEP: Resource = $r('app.color.mint_deep')
export const MINT_SOFT: Resource = $r('app.color.mint_soft')
export const MINT_GLOW: Resource = $r('app.color.mint_glow')
export const AMBER: Resource = $r('app.color.amber')
export const AMBER_SOFT: Resource = $r('app.color.amber_soft')

// ---------- 语义 ----------
export const DANGER: Resource = $r('app.color.danger')
export const DANGER_SOFT: Resource = $r('app.color.danger_soft')
export const WARN: Resource = $r('app.color.warn')
export const WARN_SOFT: Resource = $r('app.color.warn_soft')
export const OK: Resource = $r('app.color.ok')
export const OK_SOFT: Resource = $r('app.color.ok_soft')

// ---------- 指标 ----------
export const M_BP: Resource = $r('app.color.m_bp')
export const M_BP_BG: Resource = $r('app.color.m_bp_bg')
export const M_SUGAR: Resource = $r('app.color.m_sugar')
export const M_SUGAR_BG: Resource = $r('app.color.m_sugar_bg')
export const M_HR: Resource = $r('app.color.m_hr')
export const M_HR_BG: Resource = $r('app.color.m_hr_bg')
export const M_WEIGHT: Resource = $r('app.color.m_weight')
export const M_WEIGHT_BG: Resource = $r('app.color.m_weight_bg')
export const M_EXERCISE: Resource = $r('app.color.m_exercise')
export const M_EXERCISE_BG: Resource = $r('app.color.m_exercise_bg')

// ---------- 间距 ----------
export const S1: number = 4
export const S2: number = 8
export const S3: number = 12
export const S4: number = 16
export const S5: number = 20
export const S6: number = 24
export const S7: number = 28
export const S8: number = 32

// ---------- 圆角 ----------
export const R_LG: number = 24
export const R_MD: number = 16
export const R_SM: number = 12
export const R_XS: number = 8
export const R_PILL: number = 999

// ---------- 字号 / 行高 ----------
export const T_HERO: number = 52
export const T_DISPLAY: number = 34
export const L_DISPLAY: number = 42
export const T_H1: number = 26
export const L_H1: number = 34
export const T_H2: number = 20
export const L_H2: number = 28
export const T_H3: number = 17
export const L_H3: number = 24
export const T_BODY: number = 15
export const L_BODY: number = 23
export const T_SM: number = 13
export const L_SM: number = 20
export const T_CAP: number = 12
export const L_CAP: number = 17
export const T_MICRO: number = 10.5
export const L_MICRO: number = 15
export const TRACK_LABEL: number = 1.6

// ---------- 动效 ----------
export const D_FAST: number = 140
export const D_BASE: number = 220
export const D_SLOW: number = 320
export const STAGGER_MS: number = 45

// ---------- 阴影 ----------
export const SHADOW_FLOAT: ShadowOptions = {
  radius: 24,
  color: 'rgba(16, 32, 26, 0.10)',
  offsetX: 0,
  offsetY: 10
}

export const SHADOW_SOFT: ShadowOptions = {
  radius: 16,
  color: 'rgba(16, 32, 26, 0.06)',
  offsetX: 0,
  offsetY: 4
}

export const SHADOW_GLOW: ShadowOptions = {
  radius: 18,
  color: 'rgba(15, 122, 92, 0.26)',
  offsetX: 0,
  offsetY: 8
}

// ============================================================
// 主题切换
// ============================================================

// AppStorage 中保存"是否深色"的键（供页面读取当前值）
export const SKIN_DARK_KEY: string = 'skinDark'

// 应用配色模式：切换后 ArkUI 会用 base / dark 两份资源色重绘整个界面
export function applySkinMode(ctx: Context | null, dark: boolean): void {
  try {
    AppStorage.setOrCreate<boolean>(SKIN_DARK_KEY, dark)
  } catch (e) {
    console.error('记录主题状态失败: ' + (e as Error).message)
  }
  if (ctx === null) {
    return
  }
  try {
    ctx.getApplicationContext().setColorMode(
      dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
    )
  } catch (e) {
    console.error('切换主题失败: ' + (e as Error).message)
  }
}

// 当前是否深色（给 Canvas 这类必须用字符串的地方挑色板）
export function isDarkNow(): boolean {
  try {
    return AppStorage.get<boolean>(SKIN_DARK_KEY) === true
  } catch (e) {
    return false
  }
}

// ============================================================
// 旧令牌别名（未重排页面继续可用）
// ============================================================
export const BG_PAGE: Resource = CANVAS
export const CARD_BG: Resource = SURFACE
export const TILE_BG: Resource = SURFACE_2
export const TEXT_MAIN: Resource = INK
export const TEXT_SUB: Resource = INK_SUB
export const TEXT_FAINT: Resource = INK_FAINT
export const ACCENT: Resource = MINT
export const BRAND_A: Resource = MINT
export const BRAND_B: Resource = MINT_DEEP
export const R_CARD: number = R_LG
export const R_TILE: number = R_MD
export const SHADOW_CARD: ShadowOptions = SHADOW_SOFT
export const SHADOW_TILE: ShadowOptions = SHADOW_SOFT
export const C_BP: Resource = M_BP
export const C_BP_BG: Resource = M_BP_BG
export const C_SUGAR: Resource = M_SUGAR
export const C_SUGAR_BG: Resource = M_SUGAR_BG
export const C_HR: Resource = M_HR
export const C_HR_BG: Resource = M_HR_BG
export const C_WEIGHT: Resource = M_WEIGHT
export const C_WEIGHT_BG: Resource = M_WEIGHT_BG
export const C_EXERCISE: Resource = M_EXERCISE
export const C_EXERCISE_BG: Resource = M_EXERCISE_BG
export const CANVAS_DEEP: Resource = CANVAS_2
export const SURFACE_SUNK: Resource = SURFACE_2
export const JADE: Resource = MINT
export const JADE_DEEP: Resource = MINT_DEEP
export const JADE_SOFT: Resource = MINT_SOFT
export const JADE_TINT: Resource = MINT_SOFT
export const BRASS: Resource = AMBER
export const BRASS_SOFT: Resource = AMBER_SOFT
