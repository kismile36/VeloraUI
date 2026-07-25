# Velora UI

Velora UI 是一个从零实现的 Roblox 单文件 UI 库。它参考了 WindUI 的主题绑定、顶层浮层和现代布局思路，也保留了 Rayfield 易学的 `CreateWindow -> CreateTab -> CreateX` 使用方式，但不复制两者的源码、模板或远程依赖。

库本身不下载代码、不上传遥测、不依赖外部 UI 资产。核心可以作为 Studio 中的 `ModuleScript` 使用，也可以在支持 `loadstring` 的客户端环境中加载。

## 功能

- 响应式窗口：无底部投影的干净描边、拖动边界、调整大小、最小化、关闭策略、桌面双栏、移动端单栏、控件上下重排与顶部悬浮恢复胶囊。
- 完整控件：Button、Toggle/Checkbox、Slider、Input/Textbox、Dropdown、MultiDropdown、Keybind、ColorPicker、Segmented/Radio、Progress、Label、Paragraph、Divider、Spacer、Code、Image。
- 统一句柄：值控件均支持 `Get`、`Set`、`Reset`、`OnChanged`、`SetDisabled`、`SetVisible`、`Highlight` 和 `Destroy`。
- 中心状态：每个值控件使用唯一 `Flag`，支持 `GetFlag`、`SetFlag`、`Observe` 和全量 `GetFlags`。
- 主题令牌：内置 Midnight、Ocean、Violet、Emerald、Amber、Rose、Crimson、Nord、Cyber、Light、Sakura、Latte、HighContrast，支持实时切换、自定义主题和 Accent。
- 顶层浮层：Dropdown、颜色选择器、Dialog、搜索与可拖动 OpenButton 不会被 Section 或 ScrollingFrame 裁切。
- 现代排版：界面字体统一为 Builder Sans，代码区域使用 Roboto Mono，文本测量与实际渲染保持一致。
- 全局搜索：`Ctrl + K` 搜索所有 Tab、控件、标题、描述和自定义命令，可直接跳转并高亮目标。
- 通知系统：Info、Success、Warning、Error、Loading，支持去重、更新、最多三个等宽操作按钮、自动阅读时长和按屏幕高度控制并发。
- 配置系统：JSON/table 导入导出，支持 Color3、透明度、Enum、Vector2/Vector3、CFrame、UDim2、自定义主题、窗口状态、待创建 Flag、自动保存防抖和配置列表。
- 环境兼容：标准 Roblox API 为核心；`gethui`、剪贴板和文件 API 只做可选能力检测，无能力时安全降级。
- 生命周期：Library、Window、Tab、Section、Control 分层清理，所有公开 `Destroy()` 均可重复调用。

## Studio 安装

1. 将 [Velora.lua](./Velora.lua) 放入 `ReplicatedStorage`，创建为名叫 `Velora` 的 `ModuleScript`。
2. 在 `StarterPlayerScripts` 的 `LocalScript` 中加载：

```lua
local Velora = require(game:GetService("ReplicatedStorage"):WaitForChild("Velora"))
local UI = Velora.new({ Theme = "Midnight" })
```

项目包含 `default.project.json`，使用 Rojo 时可将 `Velora.lua` 同步为 `ReplicatedStorage.Velora`。`examples/demo.client.lua` 按你的要求仅使用远程 `loadstring`，不会被 Rojo 自动挂载为 Studio LocalScript。

## 单文件加载

```lua
local Velora = loadstring(game:HttpGet("https://raw.githubusercontent.com/kismile36/VeloraUI/main/Velora.lua"))()
local UI = Velora.new({
    Name = "MyInterface",
    DestroyExisting = true,
    Parent = "Auto",
    Theme = "Midnight",
    ToggleKey = Enum.KeyCode.G,
    IgnoreGuiInset = false,
    OpenButton = {
        Title = "Open Velora",
        Icon = "V",
        Draggable = true,
        OnlyIcon = false,
        OnlyMobile = false,
    },
})
```

上面的方式适用于提供 `loadstring` 和 `game:HttpGet` 的客户端环境。标准 Roblox Studio 项目请使用前面的 `ModuleScript + require` 安装方式。

`Parent = "Auto"` 在可用时选择 `gethui()`，否则使用 `LocalPlayer.PlayerGui`。也可以显式传入 `PlayerGui` 或其他能够容纳 `ScreenGui` 的父级。

`IgnoreGuiInset` 默认是 `false`，用于控制主窗口和通知是否避开 Roblox 顶栏。顶部悬浮按钮始终使用 WindUI 同款全屏坐标层，初始显示在顶栏下方，并可自由拖到物理屏幕顶部。

## 顶部悬浮按钮

主界面隐藏后会显示一个 WindUI 风格的顶部胶囊：44px 触摸高度、青紫渐变描边、图标与标题、独立拖动把手。拖动采用与 WindUI 相同的全屏坐标增量，不限制顶部位置；点击胶囊会恢复目标窗口。

```lua
local OpenButton = Window:EditOpenButton({
    Title = "Open Velora",
    Icon = "V",
    Draggable = true,
    OnlyIcon = false,
    OnlyMobile = false,
    Scale = 1,
    StrokeThickness = 1,
})

OpenButton:SetTitle("Velora UI")
OpenButton:SetIcon("V")
OpenButton:SetScale(0.95)
OpenButton:ResetPosition()
OpenButton:Visible(nil) -- 恢复自动显隐
```

也可以在 `Velora.new({ OpenButton = {...} })` 或 `CreateWindow({ OpenButton = {...} })` 中配置。传入 `OpenButton = false` 可关闭入口；`OnlyIcon` 会切换紧凑图标模式；`Color` 支持 `Color3` 或 `ColorSequence`。

## 快速开始

```lua
local Window = UI:CreateWindow({
    Title = "Velora UI",
    Subtitle = "Example",
    Icon = "V",
    Size = UDim2.fromOffset(900, 590),
    Resizable = true,
    Search = true,
})

local Tab = Window:AddTab({ Title = "General", Icon = "G" })
local Section = Tab:AddSection({ Title = "Player", Side = "Left" })

local Toggle = Section:AddToggle({
    Title = "Enabled",
    Description = "Enable this feature",
    Flag = "player.enabled",
    Default = false,
    Callback = function(value, previous, source)
        print(value, previous, source)
    end,
})

Section:AddSlider({
    Title = "Speed",
    Flag = "player.speed",
    Min = 0,
    Max = 100,
    Step = 1,
    Default = 16,
    Suffix = " studs",
})
```

如果喜欢 Rayfield 风格，可以跳过 Section，直接调用：

```lua
local Tab = Window:CreateTab("General", "G")
Tab:CreateToggle({ Name = "Enabled", Flag = "enabled", CurrentValue = true })
Tab:CreateSlider({ Name = "Speed", Flag = "speed", Range = {0, 100}, Increment = 1, CurrentValue = 16 })
```

Velora 会为这类调用创建一个默认 Section。`AddX`、`CreateX` 和简写 `X` 指向同一实现。

窗口、Tab 与通知的 `Icon` 可传短文本、数字资产 ID 或 `rbxassetid://...`；较长的纯文本图标名会自动显示首字母，避免窄栏溢出。

## 控件 API

所有值控件提供：

```lua
Control:Get()
Control:Set(value, { Silent = false, Source = "api" })
Control:Reset()
Control:OnChanged(function(value, previous, source) end)
Control:SetVisible(true)
Control:SetDisabled(true, "Reason")
Control:Lock("Reason")
Control:Unlock()
Control:Highlight()
Control:Destroy()
```

特殊控件额外提供：

- Dropdown：`Open`、`Close`、`SetValues`、`Refresh`。
- Slider：`SetRange`、`SetMin`、`SetMax`。
- Keybind：`SetKey`、`SetMode`、`IsActive`、`Triggered`；`Callback` 默认在按键激活时调用，绑定变化请使用 `OnChanged`。
- ColorPicker：`GetTransparency`、`SetTransparency`、`OnTransparencyChanged`。
- Progress：`GetPercentage`（0–100）、`GetRatio`（0–1）、`SetRange`、`SetIndeterminate`。
- Input：`Focus`。
- Button：`Press`、`Fire`。
- Code：`SetCode`。
- Image：`SetImage`。

ColorPicker 在短屏中会自动启用内部滚动；Dialog 正文可滚动，并只显示 `Buttons` 中的前三个操作按钮。

## 状态与配置

```lua
UI:GetFlag("player.speed")
UI:SetFlag("player.speed", 25, { Source = "api" })
UI:Observe("player.speed", function(value, previous, source) end)

local json = UI:ExportConfig()
local tableData = UI:ExportConfig({ AsTable = true })
UI:ImportConfig(json, { Silent = false })

UI:SaveConfig("main")
UI:LoadConfig("main")
UI:ListConfigs()
UI:DeleteConfig("main")
```

标准 Studio 客户端没有文件 API，因此默认保存到当前会话内存。跨会话保存时可以提供 Storage Adapter：

```lua
local UI = Velora.new({
    Config = {
        Folder = "MyGame",
        File = "player",
        AutoSave = true,
        Debounce = 0.5,
        Storage = {
            Read = function(self, key) end,
            Write = function(self, key, content) end,
            Delete = function(self, key) end,
            List = function(self, folder) return {} end,
        },
    },
})
```

DataStore 只能由服务端访问。正式游戏应让 Adapter 通过 RemoteEvent 与服务端通信，并在服务端校验数据；不要把令牌或机密写入客户端配置。

## 主题与命令

```lua
UI:SetTheme("Emerald")
UI:SetAccent(Color3.fromRGB(70, 160, 255))
UI:RegisterTheme("Custom", {
    Background = Color3.fromRGB(10, 12, 18),
    Surface = Color3.fromRGB(17, 20, 30),
    Accent = Color3.fromRGB(255, 120, 80),
})

UI:RegisterCommand({
    Title = "Open settings",
    Description = "Jump to the settings tab",
    Keywords = { "preferences", "config" },
    Callback = function()
        Window:SelectTab("Settings")
    end,
})
```

按 `Ctrl + K` 打开命令面板；窗口右上角搜索按钮也会打开它。

## 完整演示

[examples/demo.client.lua](./examples/demo.client.lua) 覆盖窗口、双栏布局、全部主要控件、通知、Dialog、主题、命令面板与配置保存。建议先运行该文件确认目标设备上的字号与交互，再替换为业务代码。
