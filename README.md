# ChronicHealth · 慢病健康管理（HarmonyOS 端云一体）

> 面向慢性病患者的健康管理 App：记录血压 / 血糖 / 体重 / 运动，看趋势、收预警，绑定自己的医生，
> 还能在社区里交流、向 AI 健康助手提问。

> ⚠️ **开箱跑不起来**：AI（Agent）接口要你自己填 Key，云端还要自建 AGC 项目。
> 具体清单见下面的 [运行前必须自己准备](#运行前必须自己准备)。

采用华为 **端云一体化**开发模式：ArkTS 客户端 + AGC Serverless 云函数 + CloudDB 云数据库，
业务规则与鉴权全部放在云端，客户端只负责呈现。

## 功能特性

**患者端**

- 健康数据录入：收缩压 / 舒张压、血糖、体重、心率、运动类型与时长、卡路里、备注
- 趋势分析：按时间维度的折线图与健康环，异常值高亮
- 健康预警：超阈值自动生成预警记录，集中查看
- AI 健康助手：基于 DeepSeek 的多轮对话与个性化建议（`AdvicePage` / `ChatPage`）
- 健康报告：一键导出 PDF（`ReportPdfExporter`）
- 医生绑定：按执业证号搜索、绑定 / 解绑、查看医生详情
- 社区论坛：发帖、评论、点赞、收藏、私信、举报，敏感词过滤与违规记录
- 个人中心：头像上传（CloudStorage）、昵称、皮肤主题、草稿箱

**医生端**

- 查看绑定患者列表与患者详情、健康数据、预警记录
- 在社区以医生身份发布内容

**通用**

- 账号体系：注册 / 登录 / 改密 / 注销，患者与医生角色分离，职业资质校验
- 令牌鉴权：PBKDF2 口令哈希 + HMAC 签名令牌（7 天有效），服务端验签后再做行级权限过滤

## 技术栈

| 层 | 选型 |
| --- | --- |
| 客户端 | HarmonyOS ArkTS / ArkUI，compatibleSdkVersion 6.0.2(22)，DevEco Studio 6 |
| 云函数 | AGC Cloud Functions（Node.js / TypeScript），单函数多 action 路由 |
| 数据库 | AGC CloudDB（对象化 schema + 数据条目） |
| 存储 | AGC CloudStorage（头像、报告） |
| 推送 | Push Kit（设备 token 注册） |
| 大模型 | DeepSeek `deepseek-chat`（OpenAI 兼容接口，仅在云函数侧调用） |

## 目录结构

```
chronic-health-cloud/
├── Application/                 # HarmonyOS 客户端工程（DevEco 打开这一层）
│   ├── entry/src/main/ets/
│   │   ├── pages/               # 25 个页面：Home / HealthData / Trends / Warnings / Forum / Chat …
│   │   ├── components/          # HealthRing、PostCard、BottomNav 等复用组件
│   │   ├── service/             # ApiService（云函数调用）、ImageUploader、ReportPdfExporter
│   │   ├── model/               # 客户端数据模型
│   │   └── entryability/
│   ├── cloud_objects/           # CloudDB 对象声明
│   └── AppScope/                # 应用级配置与资源
└── CloudProgram/                # AGC 云端工程
    ├── cloudfunctions/auth/     # 主云函数：认证、业务、AI、论坛（含 model/ 子模块）
    ├── cloudfunctions/id-generator/
    ├── clouddb/                 # objecttype（表结构）+ dataentry（种子数据）
    └── cloud-config.json
```

数据库对象：`User`、`HealthData`、`HealthWarning`、`Post`、`ForumPost` / `ForumComment` / `ForumLike` /
`ForumFavorite` / `ForumPrivateMessage` / `ForumConversation` / `ForumViolation`。

## 运行步骤

1. **准备 AGC 项目**
   - 在 AppGallery Connect 创建项目与应用（包名需与 `AppScope/app.json5` 一致）；
   - 开通 CloudDB、Cloud Functions、CloudStorage、Push；
   - 用 DevEco Studio 的「端云一体化」向导把项目与 AGC 关联，生成 `agconnect-services.json`。
2. **导入数据库**
   - 把 `CloudProgram/clouddb/objecttype/*.json` 的对象类型导入 CloudDB；
   - 需要演示数据时，导入 `clouddb/dataentry/*.json`（注意其中的示例账号密码是明文演示数据）。
3. **部署云函数**
   - 在 CloudProgram 上右键部署 `auth` 与 `id-generator`；
   - 配置环境变量（见下）。
4. **配置签名并运行客户端**
   - DevEco Studio → Project Structure → Signing Configs → 自动生成签名；
   - 连接真机或模拟器运行 `Application`。

## 运行前必须自己准备

这个 App 是"客户端 + 云函数"的端云一体结构，**没有云端配置跑不起来**，AI 助手还需要你自己的大模型 Key。
本副本已把原项目里的所有密钥清空，以下各项都得自己补。

### 1. AI（Agent）接口 —— 必须自己填

AI 健康助手与 AI 报告走 DeepSeek 的 OpenAI 兼容接口，**仓库里没有可用 Key**：

| 项 | 在哪填 | 怎么拿 |
| --- | --- | --- |
| `DEEPSEEK_API_KEY` | AGC 控制台 → Cloud Functions → `auth` → 环境变量 | 到 [platform.deepseek.com](https://platform.deepseek.com) 申请，形如 `sk-...` |
| 模型 / 地址（可选） | `CloudProgram/cloudfunctions/auth/model/aiConfig.ts` | 默认 `api.deepseek.com` + `/v1/chat/completions` + `deepseek-chat`；换别的兼容服务改这里 |

> **不填会怎样**：登录、健康数据、趋势、论坛都正常，但 **AI 对话与 AI 建议会失败**——
> 云函数在 `authService.ts` 里检查 Key，取不到就直接抛
> `AI 未配置：请在 model/aiConfig.ts 填写 DeepSeek Key`。所以部署完云函数，第一件事是配这个环境变量。
>
> **不要把 Key 写回源码**：客户端安装包和云函数产物都可能被反编译，原项目用 XOR+Base64"加密"过，
> 但密钥与代码同包，等于没加密。正确做法就是环境变量 / 密钥管理服务。

### 2. AGC 云端配置 —— 必须自己建项目

| 位置 | 需要填什么 |
| --- | --- |
| `CloudProgram/cloudfunctions/auth/model/agconnect-services.json` | 自己 AGC 项目的 `client_secret`、`api_key` |
| `.../model/credential.ts` | `CRED_JSON` 填入自己的 AGC 凭证 JSON（或改由环境变量注入） |
| `.../model/servercred.ts` | AGC 服务端凭证（`type=project_client_id`，由 AGC 的 client_secret 生成） |
| `.../model/token.ts` | 令牌签名密钥，建议用环境变量 `TOKEN_SECRET`（不配则回退到代码里的 dev 兜底值） |
| 云函数环境变量 | 除 `DEEPSEEK_API_KEY` 外，建议一并配 `TOKEN_SECRET` |

另外要开通 CloudDB、CloudStorage、Push，并把 `CloudProgram/clouddb/objecttype/*.json`
导入 CloudDB（需要演示数据再导入 `dataentry/*.json`）。

### 3. 客户端签名

| 位置 | 需要填什么 |
| --- | --- |
| `Application/build-profile.json5` | 签名证书路径与口令（`YOUR_SIGNING_FILE.*` / `YOUR_*_PASSWORD`）；在 DevEco 里勾"自动生成签名"最省事 |

签名与 AGC 项目绑定，换台机器/换项目都要重新配。

## 关于本副本

为公开发布做的处理：

- 剔除了 `node_modules/`、`oh_modules/`、`build/`、`.hvigor/`、`.idea/`、`local.properties` 等依赖与构建产物；
- 剔除了非运行必需的素材：比赛文档（docx/pptx/pdf）、AGC 控制台截图、图标设计稿、测试图片、文档生成脚本；
- 清空了内嵌的 DeepSeek Key、AGC `client_secret` / `api_key`、AGC 服务端凭证、令牌签名密钥与签名口令
  （原项目用 XOR+Base64 混淆，密钥与代码同包，混淆不能当作加密）；
- 保留了完整的业务代码：`Application`（客户端）+ `CloudProgram`（云函数与 CloudDB）。

## 已知问题与改进方向

- `authService.ts` 单文件 15 万字符，集认证、健康数据、论坛、AI 于一体，建议按领域拆分云函数；
- CloudDB 的对象权限目前只给 Administrator 读写，实际业务要靠云函数代转，建议评估「按用户的行级权限」；
- 口令已用 PBKDF2 加盐，但令牌没有刷新机制，7 天后需重新登录；
- 论坛敏感词表是静态数组，建议外置为可热更新的配置。

## License

课程/竞赛作品，仅供学习交流。
