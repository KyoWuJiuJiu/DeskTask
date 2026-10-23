# DeskTask

[English](README.md) · [简体中文](README.zh-CN.md)

一个 macOS 桌面提醒小部件，用 Swift + AppKit 从零写的。

![展开面板](docs/preview-expanded.png)

---

一个 macOS 桌面提醒小部件。灵感来自 Softorino 的 [DeskMinder](https://setapp.com/apps/deskminder)：
屏幕上只有一个 **+ 号**，点开是两个模式。

## 两种模式

点 **+** 展开面板，出现两个入口：

| 入口 | 模式 | 行为 |
| --- | --- | --- |
| **拉长计时** | reminder | 拉多长＝定多久（1/2/3/5/10/15/30/60 分钟），**松手立刻开始倒计时**，不需要输入任何东西，像番茄钟 |
| **选择日期** | task | 选「完成日期」（只要日期，不用时刻）＋ 写任务内容 → **同步创建到 Apple「提醒事项」**的默认列表（带到期日） |

点 **+** 之后，除了这两个入口，还有一排**快捷计时**按钮：**5 / 10 / 25 / 30 / 60 分钟**。
点一下就直接建对应时长的倒计时，等价于把皮筋拉到那一档 —— 区别是 25 分钟这种不在皮筋档位里的
时长也能一键建出来（皮筋的档位只有 1/2/3/5/10/15/30/60）。

任务卡片上：**✓ = 在提醒事项里标记完成并移除**，**✕ = 只从桌面移除**（不动提醒事项）。
计时卡片上：**✕ = 丢弃这次计时**。

到点之后：响铃（系统 *Glass* 音效，每 30 秒再响一次、最多 5 次）、窗口浮到最前、卡片变红；
**2 分钟后卡片自动从清单里移除**，不会一直留着一条红的。

**倒计时剩余时间会同步显示在菜单栏**（图标右边），这样窗口被挡住也能一眼看到。

标题栏右侧有个**「收起」**按钮，随时可以手动折叠回横条（自动折叠依然生效，只是不必等它）。

**过期的任务会保留**：到期日已过的任务仍然留在清单里，用红色标成「已过期」（不再静默地躺在
那里），横条也会优先显示「过期 N 个任务」。

```
空闲（没东西在跑）      空闲（有东西在跑）              展开态：
    ╭────╮        ╭────────────────────────────────╮   ┌──────────────────────────────┐
    │ +  │        │ ████████  还剩 12 分钟   今日 2 个任务 │   │ ⠿ DeskTask          ⊖   │
    ╰────╯        ╰────────────────────────────────╯   │ [拉长计时] [选择日期]        │
                                                       │ ◖▬▬▬▬▬▬◗  ← 橡皮筋            │
                                                       │ [今天][明天][后天] [2026/12/25]│
                                                       │ [任务内容…              ] [添加]│
                                                       ├──────────────────────────────┤
                                                       │ ◔ 10  开会          还剩 09:58 │
                                                       └──────────────────────────────┘
```

## 位置固定

窗口**不跟随拖动**，永远贴在**屏幕水平居中、刘海正下方 24pt**：

```
屏幕宽 1512 → 窗口 x = 756 - 宽/2      （宽度变化时保持居中）
窗口顶边 y = 菜单栏/刘海高度 + 24pt      （safeAreaInsets.top 取不到时退化用 33）
```

宽度会随状态变化，锚点取的是**顶边中点**（不是左上角），所以展开/收起时始终居中。

## 空闲时收成什么

鼠标离开 **1 秒**后自动收起，收成什么取决于里面还有没有"在跑的东西"：

| 状态 | 外形 |
| --- | --- |
| 有进行中的倒计时，或还有没完成的任务 | **一条 296×26 的状态条**：左边「还剩 N 分钟」（最近一条倒计时，底色填充就是它的进度），右边「今日 N 个任务」 |
| 什么都没有（倒计时跑完、任务都完成） | **一个 42pt 的圆形玻璃 + 号** |

- **打字时不会被打断**：每次按键都把 1 秒倒计时往后推，停手 1 秒才收；
  收起前会把正在编辑的文本提交掉（输入法组字中的内容也会落盘）。
- **建完也会自己收**：新建一条之后 2.5 秒自动收起，不必把鼠标移开；
  打字会不断把倒计时往后推，而且**正在拉长 / 正在填任务时不会收**
  （否则会把用户填到一半的东西藏起来）。
- **点一下才展开**：点横杠或加号都会展开面板。
- **不再沉到桌面层级**：窗口始终在浮层（`level = 3`），否则会被桌面小组件盖住，
  一旦盖住就彻底找不着了。
- **到点必然弹出**：计时结束时不管收没收起来，都会响铃并把它提回最前。

## 提示音

计时到点会播 `NSSound(named: "Glass")`（已实测可解析，1.65 秒）；
未被确认的话每 30 秒再响一次，最多 5 次。同时窗口浮到最前、卡片变红。

### 手感的实现（`Sources/PullStops.swift`）

「阻尼感」「粘性」不是动画，是一条分段函数：

- 每一档之间，前 `gap - stick` 点 **1:1 跟手**；靠近刻度时斜率降到 `stickFactor = 0.45`，
  所以越接近刻度越"拉不动"，跨过去又恢复跟手 —— 这就是粘滞。
- 超过最后一档后斜率降到 `resistance = 0.25`，拉不出窗口。
- 松手后用 0.26 秒 cubic ease-out 弹回，像橡皮筋。

## Apple「提醒事项」同步

task 模式通过 `osascript` 调用 Reminders，日期逐段赋值（不依赖系统 locale 的日期格式）：

```applescript
set theDate to (current date)
set day of theDate to 1          -- 先置 1，避开 31 号跳到没有 31 号的月份
set year of theDate to 2026
set month of theDate to 12
set day of theDate to 25
set time of theDate to 0
tell application "Reminders"
  set r to make new reminder at end of default list with properties {name:theTitle, due date:theDate}
  return id of r                 -- 记住 id，之后才能按 id 标记完成
end tell
```

**第一次创建任务时，macOS 会弹「DeskTask 想要控制『提醒事项』」**，必须点允许。
若被拒绝，卡片上会显示「未同步」并提示系统设置的路径；把鼠标停在那行可以看到完整原因。

## 构建 / 运行

只需要 **Command Line Tools**（不需要 Xcode）：

```bash
cd DeskTask
./run.sh          # 编译 + 结束旧实例 + 启动（推荐）；产物是 build/DeskTask.app
```

## 装成正式应用 / 开机自启

```bash
./install.sh             # 装进 /Applications（启动台可见）+ 设置开机自启
./install.sh --no-login  # 只装进 /Applications
./install.sh --uninstall # 全部移除
```

- 装进 `/Applications` 才会被**启动台**和聚焦搜索索引到。
- 开机自启用的是 **LaunchAgent**（`~/Library/LaunchAgents/local.desktask.login.plist`），
  不是系统「登录项」。原因：macOS 13+ 的原生接口 `SMAppService` 要求应用有正式签名
  （Developer ID），本地 ad-hoc 签名的构建注册会直接报权限错误。
  代价是它不会出现在「系统设置 → 通用 → 登录项」的开关列表里，只能用脚本关。
- 装过之后 `./run.sh` 会自动同步 `/Applications` 里那一份，避免启动台里跑的是旧版本。

## 图标

图标是**代码画出来的**，不是二进制资源：`tools/make-icon/main.swift` 用 CoreGraphics 绘制
（Big Sur 规范的圆角矩形 + 蓝色渐变 + 环形进度 + 加号，与应用内部的视觉语言一致），
再交给系统自带的 `iconutil` 打成 `.icns`：

```bash
./tools/make-icon.sh    # 重新生成 Assets/AppIcon.icns
```

改配色/形状就改那个 `main.swift`。

**别用 `open` 单独启动。** 如果同一个 bundle 已经在运行，`open` 只会去"激活"那个旧窗口——
进程里跑的还是旧代码，磁盘上的新二进制根本没被加载，表现就是"重新构建后没有任何反应"。
`run.sh` 会先按**绝对路径**结束旧实例（只杀这个 build，不会碰 App Store 装的那个 DeskMinder），
再启动。

只想编译：`./build.sh`。

- 折叠成一个 + 时，**拖那个 +** 就能移动窗口；展开时拖标题栏。
- 位置记在 `UserDefaults`（key `anchor`）。
- 退出：**⌘Q**，或右键部件 → 退出 DeskTask。

## 文件

| 文件 | 作用 |
| --- | --- |
| `Sources/PullStops.swift` | 拉动距离 ↔ 时长 的分段映射（粘滞与阻尼） |
| `Sources/PullBandView.swift` | 弹性带：鼠标事件 + 手绘 + 回弹动画 |
| `Sources/PanelViews.swift` | + 按钮、圆角按钮、模式选择行、日期+内容输入 |
| `Sources/Model.swift` | 数据、倒计时心跳、到点触发 |
| `Sources/ChipView.swift` | 提醒卡片（计时 / 任务两种外观） |
| `Sources/RemindersBridge.swift` | osascript 桥：创建任务、按 id 标记完成 |
| `Sources/WidgetView.swift` | 浮窗根视图：状态机 + 布局 + 自适应尺寸 |
| `Sources/WindowSupport.swift` | 可成为 key window 的无边框窗口 |
| `Sources/main.swift` | 入口、浮窗装配、响铃 |
| `tools/make-icon/main.swift` | 用 CoreGraphics 画应用图标并打包成 `.icns` |

## 三个踩过的坑（别改回去）

1. **输入框的 `stringValue` 只在创建时写一次。**
   心跳是 0.25 秒一次，如果刷新时回写 `stringValue`，输入法组字（marked text）会被反复重置，
   表现为"中文每打一个字母就被提交"，中文永远打不进来。`ChipView.refresh()` 里绝不能碰它。
2. **SwiftUI 的属性包装器在这台机器上用不了。**
   这个 SDK 里 `@State` / `@Binding` / `@ObservedObject` 都已改成宏，而宏实现插件
   `SwiftUIMacros` 只随 Xcode 提供。只用 Command Line Tools 时它们全部无法展开，
   所以整个界面是纯 AppKit 手写的。
3. **收进桌面时的窗口层级必须高于 Finder 的桌面窗口。**
   实测 Finder 的桌面窗口是**整屏** 1512x982、层级 `-2147483603`。若放到它下面一层，
   窗口照样可见（那层是透明的）但点击全被 Finder 吃掉，表现就是"+ 号点不动"。
   现在用 `desktopIconWindow + 1`。另外点击/拖动的判定按**鼠标位移**而不是窗口原点，
   因为 `performDrag` 可能把窗口挪一两个点，按原点比较会把点击误判成拖动。
4. **启动时不要立刻收起。**
   启动瞬间窗口要从初始的 328x120 缩成 42x42（左上角不动），鼠标会因为窗口"缩走"
   而触发一次 `mouseExited`，接着 2 秒后就把自己藏进桌面 —— 表现为"启动后什么都没发生"。
   现在只有用户真的操作过（点 + / 拉皮筋 / 提交任务）之后才启用空闲折叠。
5. **给 bundle 重新签名前要清扩展属性。**
   桌面在 iCloud Drive 下，fileprovider 会异步把 `com.apple.FinderInfo` 加回来，
   所以 `build.sh` 里是「清一次 + 重试 5 轮」，不然签名会间歇性失败。

## 许可证

[MIT](LICENSE)。这是一个独立实现，交互灵感来自 Softorino 的 DeskMinder，与该产品及其公司无关。

## 已知取舍

- **不接系统通知中心**：到点是「响一声 + 窗口浮到最前 + 卡片变红」。`UNUserNotificationCenter`
  在未签名的本地 app 上会直接抛异常，宁可不引入这个崩溃点。
- **固定深色玻璃**（`.darkAqua` + `.hudWindow`），不随系统浅色/深色切换，保证配色稳定。
- **不做本地持久化**：提醒只活在进程内存里，退出即消失（task 的持久化交给「提醒事项」）。
- 任务内容为空时点「添加」不会提交，光标会留在输入框里。

## 菜单栏图标

菜单栏有一个计时器图标：**左键**显示/收起部件，**右键**出菜单
（显示 / 收进桌面 / 清除全部提醒 / 退出）。它同时是"永远有办法退出"的保底通道 ——
部件一旦收进桌面且被窗口挡住，没有它就可能退不掉。
- **无法嵌入 Atoll 之类的刘海软件**：Atoll（`com.Ebullioscopic.Atoll` v2.3.3）没有
  PlugIns / Extensions / AppleScript 字典 / URL scheme，不对外提供任何嵌部件的接口。
  若想常驻"刘海旁边"，native 的做法是加一个菜单栏图标（`NSStatusItem`）。
