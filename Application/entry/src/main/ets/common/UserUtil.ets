// 全局展示名：优先昵称，昵称为空则回退账号用户名。
// 这样"账号(登录凭证)"与"昵称(展示名)"分离，且老用户没设昵称时仍显示账号。
export function displayNameOf(nickname: string, username: string): string {
  if (nickname !== '' && nickname !== undefined && nickname !== null) {
    return nickname
  }
  return username
}
