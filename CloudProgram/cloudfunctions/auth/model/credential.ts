// 服务端凭证内嵌为字符串常量（由 gen_cred.py 从 agconnect-services.json 逐字节生成）。
// 原因：DevEco 部署云函数不保证把 model/ 下的 .json 数据文件带上云端，
// 运行时 CredentialParser 读不到文件会报 10501 parser credential fail。
// TS 源码一定会被编译打包，故把凭证放这里，运行时写到临时文件再交给 CredentialParser。
// 注意：含密钥，仅比赛演示用，勿上传公开仓库。
// 已移除内嵌 AGC 凭证：请填入自己的 agconnect-services.json 内容，或改用环境变量注入
export const CRED_JSON = `{}`;
