// 主题偏好的本地存储。
// 颜色本身走资源色（base / dark），这里只负责记住用户选了哪一套，
// 以及启动时把选择应用回去。
import { preferences } from '@kit.ArkData'
import { applySkinMode, SKIN_DARK_KEY } from '../common/Theme'

const STORE_NAME = 'chronic_health'
const KEY_SKIN = 'skinDark'

// 读取偏好（异常/未设置时按浅色）
export async function loadSkinDark(ctx: Context): Promise<boolean> {
  try {
    let store = await preferences.getPreferences(ctx, STORE_NAME)
    let v = await store.get(KEY_SKIN, '0') as string
    return v === '1'
  } catch (e) {
    return false
  }
}

// 保存偏好并立即应用
export async function setSkinDark(ctx: Context, dark: boolean): Promise<void> {
  try {
    let store = await preferences.getPreferences(ctx, STORE_NAME)
    await store.put(KEY_SKIN, dark ? '1' : '0')
    await store.flush()
  } catch (e) {
    console.error('保存主题偏好失败: ' + (e as Error).message)
  }
  applySkinMode(ctx, dark)
}

// 启动时恢复上次的主题
export async function restoreSkin(ctx: Context): Promise<void> {
  let dark = await loadSkinDark(ctx)
  applySkinMode(ctx, dark)
}
