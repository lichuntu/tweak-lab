# tweak-lab — iOS 注入 dylib 学习/定制模板

给自己的手机做界面微调（比如把某个 App 里碍眼的按钮/广告位/标签栏删掉），
不越狱、不装电脑，用**全能签 / ESign** 这类工具把 dylib 注入 IPA 后重签名安装即可。

## 它有什么

| 功能 | 说明 |
|---|---|
| **悬浮探针「探」** | 启动 App 后左上角出现一个蓝色小球，点一下 → 弹出当前界面的**视图树**（每个控件的类名、坐标、文字）。拖动可移动，长按 3 秒临时隐藏。 |
| **按规则隐藏控件** | 在 `src/Tweak.m` 顶部的 `kHideRules()` 里填类名，重新编译 → 注入 → 该控件永久消失。 |

工作流：**用探针找到类名 → 填进规则 → 重新编译 → 覆盖安装**。

## 快速上手

1. 拿这个仓库编好的 `MinTweak.dylib`（Releases / Actions 产物），先用探针版注入任意 App 试水。
2. 打开 App，点蓝色「探」球，找到你想删的那个控件，记下**类名**（例如 `AdBannerView`、`UIButton`…）。
3. 编辑 `src/Tweak.m`：

   ```objc
   static NSArray<NSString *> *kHideRules(void) {
       static NSArray *rules = nil;
       if (!rules) {
           rules = @[
               @"AdBannerView",      // 精确匹配类名
               @"MyApp_Promo*",      // 末尾 * = 前缀匹配
           ];
       }
       return rules;
   }
   ```

4. push 到 GitHub → Actions 自动编译 → 下载新 dylib → 重新注入签名。

> 探针不需要了就把 `kEnableProbe` 改成 `NO`，成品更干净。

## 编译方式

- **云端（推荐，无需 Mac）**：push 代码，GitHub Actions 在 macOS runner 上用 Xcode 自动编译，产物在 run 页面的 Artifacts 里。
- **本地有 Mac**：`bash build.sh`，产物在 `build/MinTweak.dylib`。

编译参数关键点（脚本里已配好）：

- `-arch arm64`：Apple Silicon 设备都跑得起来，签名工具也认这个
- `-dynamiclib` + `-install_name @executable_path/MinTweak.dylib`：注入后能按相对路径找到
- `-Wl,-undefined,dynamic_lookup`：允许调用系统/私有符号，运行时解析
- `-fobjc-arc`：省内存管理烦恼

如果你的签名工具要求 dylib 放在 `Payload/App.app/Frameworks/`，把 install_name 改成
`@rpath/MinTweak.dylib` 即可（改 `build.sh` 一行）。

## 注入流程（全能签 / ESign 类工具）

1. 准备好目标 App 的 IPA（自己抓包或用工具导出已安装 App）。
2. 在签名工具里选「**注入 dylib**」→ 选中 `MinTweak.dylib`。
3. 用自己的证书签名 → 安装。
4. 首次启动如果闪退，先看工具里的崩溃日志，大概率是类名/规则写错，或探针调用了 App 里不存在的类。

## 常用调试技巧

- **闪退不知道原因**：把 `kHideRules()` 先清空、`kEnableProbe = NO`，用最小版本确认 dylib 本身能加载；再逐条加回来。
- **控件是动态创建、隐藏后又被显示**：说明有代码在后续设置 `hidden = NO`。可以在 `UIView` 的 `setHidden:` 上也做一次拦截（模板里预留了思路，需要时告诉我加）。
- **Swift 写的 App**：类名是 `_TtC...` 这样的乱码，探针会照样打出来，直接原样填进规则即可。
- **看不到日志**：签名 App 的 `NSLog` 在系统日志里，手机端可用工具查看；探针面板就是为「不想连电脑看日志」准备的。

## 免责声明

仅用于**个人学习**和**自己设备上自己安装的 App 的界面调整**。请勿用于破解付费功能、
绕过风控、窃取数据或分发修改版应用。修改他人 App 再分发可能违反其服务条款和著作权法。

## 目录

```
src/Tweak.m      # 全部逻辑：配置 + 隐藏规则 + 探针
build.sh         # macOS/iSH 编译脚本
.github/workflows/build.yml   # 云端自动编译
```
