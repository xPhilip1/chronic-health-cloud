// 头像图标解析：角色优先（医生 / 管理员），其余按性别（男 / 女 / 未知）。
// gender 同时兼容原始值('male'/'female')和中文标签('男'/'女')，方便各页面直接传。
export function resolveAvatar(gender: string, role: string): Resource {
  if (role === 'doctor') {
    return $r('app.media.ic_avatar_doctor')
  }
  if (role === 'admin') {
    return $r('app.media.ic_avatar_admin')
  }
  if (gender === 'male' || gender === '男') {
    return $r('app.media.ic_avatar_male')
  }
  if (gender === 'female' || gender === '女') {
    return $r('app.media.ic_avatar_female')
  }
  return $r('app.media.ic_avatar_default')
}

// 头像取值：有自定义头像地址就用它，否则回退到内置的角色/性别图标。
// 返回 ResourceStr（string 或 Resource），Image 组件两者都能吃，
// 这样各页面只需把 resolveAvatar(...) 换成 avatarSrc(url, ...) 即可。
export function avatarSrc(url: string | undefined, gender: string, role: string): ResourceStr {
  if (url !== undefined && url !== null && url.length > 0) {
    return url
  }
  return resolveAvatar(gender, role)
}