# AutoHideKeyboard — 微信发送消息后自动收起键盘 (v2.0)

iOS 微信 Theos/Logos 插件（tweak），功能与参考的 `AutoHideKeyboard.dylib` 一致：
在微信聊天中**发送文字消息后自动收起键盘**。

## 功能

| 功能 | 说明 |
|---|---|
| 发送后收起 | 覆盖普通聊天 / 群聊 / 企业微信 / 群发助手的 `SendTextMessage:` 系列方法 |
| 闲置收起（可选） | 关闭"仅发送后收起"时，输入闲置超过延迟秒数且输入框为空才收起 |
| 组词保护 | 正在打拼音（markedTextRange 非空）不收，与原版行为一致 |
| 延迟可调 | 默认 0.2 秒，设置页滑杆调节（0.05–3 秒，0.02 秒步进） |
| 内嵌设置页 | 微信「我 → 设置」底部新增「自动收起键盘」入口 |
| 配置键 | `AutoHideKeyboardEnabled` / `AutoHideKeyboardDelay` / `AutoHideKeyboardSendOnly` / `AutoHideKeyboardLog`（NSUserDefaults） |

## v2.0 界面优化

- 设置页改用 **iOS 13+ 内缩分组样式**（Inset Grouped），与系统设置观感一致
- 延迟调节从文本框改为**滑杆 + 实时数值显示**（等宽数字字体）
- 新增 **「立即测试收起」** 行，一键验证插件是否生效
- 分区标题 / 页脚说明文案重写，页脚标注版本号与隐私声明（不联网、不读聊天记录）

## 文件结构

```
AutoHideKeyboard/
├── Tweak.x                  # 主源码（Hooks + 内嵌设置页 AHKSettingsViewController）
├── Makefile                 # Theos 构建脚本
├── control                  # deb 包描述
├── AutoHideKeyboard.plist   # 过滤器：只在 com.tencent.xin 中加载
└── .github/workflows/
    └── build.yml            # GitHub Actions 自动编译（推荐，无需本地环境）
```

## 编译方式

### 方式 1：GitHub Actions 云端编译（推荐，本地零环境）

1. 在 GitHub 建一个仓库，把本目录所有文件（含 `.github/`）推上去
2. 仓库页 → Actions → "Build AutoHideKeyboard" → Run workflow
3. 跑完后在 Artifacts 下载 `AutoHideKeyboard.zip`，内含：
   - `AutoHideKeyboard.dylib`（TrollFools 注入用）
   - `com.user.autohidekeyboard_2.0.0_iphoneos-arm.deb`（越狱安装用）

### 方式 2：本地 Theos（macOS / Linux / WSL）

Theos 只能运行在 macOS / Linux / WSL（Windows 本机不支持）。

```bash
# 1. 安装 Theos（macOS/Linux/WSL 通用）
git clone --recursive https://github.com/theos/theos.git ~/theos
export THEOS=~/theos

# 2. 编译
cd AutoHideKeyboard
make package FINAL=1
# 产物: packages/com.user.autohidekeyboard_2.0.0_iphoneos-arm.deb
# 以及 .theos/obj/release/AutoHideKeyboard.dylib
```

## 安装方式（二选一）

### 方式 A：无根越狱（Dopamine / palera1n rootless）

```bash
make install THEOS_DEVICE_IP=<设备IP>
# 或手动把 deb 拖进手机用 Sileo 安装
# dylib 会落到 /var/jb/Library/MobileSubstrate/DynamicLibraries/
```

### 方式 B：TrollFools 注入（推荐，无需越狱）

1. 从 Actions 产物（或本地编译）拿到 `AutoHideKeyboard.dylib`
2. 手机装 TrollFools，选中微信，把 dylib 插入
3. TrollFools 会自动处理签名（参考 dylib 文件名的 "_cert" 就是这个含义）

## 注意与风险

- **封号风险**：向微信注入 dylib 属于修改客户端行为，微信客户端有完整性检测，
  存在功能限制或封号的可能，请自行权衡，建议小号先试。
- **类名漂移**：`NewSettingViewController` 及 5 个聊天控制器类名是当前微信版本的
  私有类，微信大版本更新后可能改名或签名变化。Hook 不存在的类会静默跳过（不崩溃），
  但入口可能消失；届时需用 class-dump 重新核对类名。
- **本工程为逆向重建**：行为按 dylib 符号与配置键 1:1 还原，未逐字节反汇编验证
  边缘逻辑（如设置入口的具体挂载位置可能与原版略有差异）。

## 验证

1. 微信开启任意聊天 → 设置页开关确认「启用」为开
2. 发送一条文字消息 → 键盘在延迟秒数后自动收起
3. 打开「输出日志」开关后，可在 Console.app / idevicesyslog 过滤 `[AHK]` 查看行为日志：
   - `keyboard hidden` 成功收起
   - `skip hide: no first responder` 无输入焦点，跳过
   - `skip hide: disabled by user` 总开关关闭，跳过
