// 服务端凭证（type=project_client_id），由 gen_servercred.py 从 agc_secret.txt 生成。
// SDK 要求顶层 type 字段且 client_secret 为明文，app 端 agconnect-services.json 两者都不满足。
// 明文改为密文内嵌（见 model/secretBox.ts）：仓库里不再有可直接复制的 client_secret，
// 但同包仍可还原，仅作比赛演示的"不裸奔"处理；正式环境请改由环境变量注入。
import { open } from './secretBox';

// 密文（XOR+Base64）
const SERVER_CRED_SEALED: string =
  '';  // 已移除内嵌 AGC 服务端凭证：请填入自己的 agc_secret 或改用环境变量

// 解密一次并缓存，供 ensureDb() 写临时文件用
let cachedCredJson: string = '';

export function getServerCredJson(): string {
  if (cachedCredJson === '') {
    cachedCredJson = open(SERVER_CRED_SEALED);
  }
  return cachedCredJson;
}
