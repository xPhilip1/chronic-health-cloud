import { ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { pushService } from '@kit.PushKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { initApiService } from '../service/ApiService'
import { restoreSkin } from '../service/SkinStore'

const HILOG_DOMAIN = 0x0000;
const TAG = '[EntryAbility]';

export default class EntryAbility extends UIAbility {
  onCreate() {
    // 初始化 mock 服务层（阶段 B 会换成云后端，初始化入口保留）
    initApiService(this.context)
    // app 一启动就取一次推送 token（它绑设备+应用，与登录账号无关）
    this.requestPushToken();
    // 恢复上次选择的主题（浅色 / 深色），未设置时默认浅色
    restoreSkin(this.context).catch((err: BusinessError) => {
      hilog.error(HILOG_DOMAIN, TAG, 'restoreSkin failed: %{public}s', JSON.stringify(err));
    });
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onCreate');
  }

  // 取本机当前应用的推送 token；第一层先只打印出来，方便复制去 AGC 控制台手发通知
  requestPushToken(): void {
    pushService.getToken().then((token: string) => {
      // 成功：这串就是离线推送要用的设备 token，非空即代表 Push Kit 注册成功
      hilog.info(HILOG_DOMAIN, TAG, 'PUSH_TOKEN=%{public}s', token);
    }).catch((err: BusinessError) => {
      // 失败：常见是 AGC 未开通推送服务 / 手机未登录华为账号 / 包名不匹配
      hilog.error(HILOG_DOMAIN, TAG, 'getToken failed code=%{public}d msg=%{public}s', err.code, err.message);
    });
  }

  onDestroy(): void {
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(HILOG_DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(HILOG_DOMAIN, TAG, 'Succeeded in loading our Index page.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(HILOG_DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}
