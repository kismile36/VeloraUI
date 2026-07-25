local Velora = loadstring(game:HttpGet("https://raw.githubusercontent.com/kismile36/VeloraUI/main/Velora.lua"))()

local UI = Velora.new({
	Name = "VeloraChineseDemo",
	DestroyExisting = true,
	Theme = "Midnight",
	ToggleKey = Enum.KeyCode.G,
	OpenButton = {
		Title = "打开 Velora",
		Icon = "界",
		OnlyMobile = false,
		OnlyIcon = false,
		Draggable = true,
	},
	Config = {
		Folder = "VeloraDemo",
		File = "chinese_demo",
		AutoSave = false,
	},
})

UI:RegisterTheme("AuroraCN", {
	Background = Color3.fromRGB(8, 13, 25),
	Surface = Color3.fromRGB(15, 24, 42),
	SurfaceAlt = Color3.fromRGB(22, 34, 56),
	SurfaceHover = Color3.fromRGB(31, 47, 74),
	Border = Color3.fromRGB(48, 73, 104),
	Text = Color3.fromRGB(237, 248, 255),
	Muted = Color3.fromRGB(143, 175, 197),
	Accent = Color3.fromRGB(71, 224, 190),
	AccentDark = Color3.fromRGB(31, 156, 137),
	AccentText = Color3.fromRGB(4, 31, 29),
})

local Window = UI:CreateWindow({
	Title = "Velora UI 中文演示",
	Subtitle = "完整控件、通知、主题与配置示例",
	Icon = "界",
	Size = UDim2.fromOffset(960, 640),
	Resizable = true,
	Search = true,
	ShowUser = true,
	CloseBehavior = "Destroy",
	ConfirmOnClose = true,
	CloseConfirmTitle = "是否关闭窗口",
	CloseConfirmContent = "关闭后将销毁中文演示窗口，且不会显示顶部恢复悬浮窗。",
	CloseConfirmCancel = "否",
	CloseConfirmConfirm = "是",
})

local function notify(title, content, notificationType, extra)
	local options = extra or {}
	options.Title = title
	options.Content = content
	options.Type = notificationType or "Info"
	return UI:Notify(options)
end

local function countEntries(values)
	local count = 0
	for _ in pairs(values) do
		count = count + 1
	end
	return count
end

local function storageName(backend)
	local names = {
		memory = "当前会话内存",
		filesystem = "本地文件",
		adapter = "自定义存储适配器",
	}
	return names[backend] or "当前运行环境"
end

local OverviewTab = Window:AddTab({
	Title = "总览",
	Icon = "总",
	Description = "快速了解界面与主要交互",
})

local WelcomeSection = OverviewTab:AddSection({
	Title = "欢迎使用",
	Description = "从这里快速体验常用功能",
	Side = "Left",
})

WelcomeSection:AddParagraph({
	Title = "为实际项目准备",
	Content = "Velora 提供响应式布局、统一状态、顶部弹层、实时主题、配置管理与完整清理。主窗口可自由拖到屏幕外；右上角减号用于最小化，关闭按钮会先请求确认。",
})

WelcomeSection:AddButton({
	Title = "最小化到顶部悬浮窗",
	Description = "效果与点击窗口右上角减号相同",
	ActionText = "体验",
	Variant = "Primary",
	Callback = function()
		Window:Minimize()
	end,
})

WelcomeSection:AddButton({
	Title = "打开命令面板",
	Description = "也可以按 Ctrl + K 搜索中文控件与命令",
	ActionText = "打开",
	Callback = function()
		UI:OpenCommandPalette()
	end,
})

WelcomeSection:AddButton({
	Title = "显示三按钮对话框",
	Description = "演示主要、次要与危险操作",
	ActionText = "查看",
	Callback = function()
		local dialog = UI:Dialog({
			Title = "请选择一个操作",
			Content = "这是一个多按钮对话框。灰色遮罩应覆盖整个屏幕，包括 Roblox 顶栏区域。",
			Width = 460,
			Dismissible = true,
			Buttons = {
				{
					Title = "稍后处理",
					Value = "稍后处理",
					Variant = "Secondary",
					Callback = function()
						notify("已暂缓", "本次演示没有修改任何游戏数据。", "Info")
					end,
				},
				{
					Title = "继续演示",
					Value = "继续演示",
					Variant = "Primary",
					Callback = function()
						notify("操作完成", "主要按钮回调已成功执行。", "Success")
					end,
				},
				{
					Title = "取消操作",
					Value = "取消操作",
					Variant = "Danger",
					Callback = function()
						notify("操作已取消", "危险按钮仅用于样式演示。", "Warning")
					end,
				},
			},
		})
		if dialog then
			dialog.Closed:Connect(function(result)
				notify("对话框已关闭", result and ("返回值：“" .. tostring(result) .. "”。") or "通过遮罩或 Esc 键关闭，没有返回值。", "Info")
			end)
		end
	end,
})

local TipsSection = OverviewTab:AddSection({
	Title = "使用提示",
	Description = "桌面端与移动端均可使用",
	Side = "Right",
})

TipsSection:AddLabel({
	Text = "G 键：显示或隐藏整个界面",
	Bold = true,
	ColorToken = "Text",
})

TipsSection:AddDivider()

TipsSection:AddParagraph({
	Title = "搜索与定位",
	Content = "点击右上角搜索图标或按 Ctrl + K，可搜索所有标签页、控件与下方注册的中文命令。",
})

TipsSection:AddSpacer(6)

TipsSection:AddButton({
	Title = "显示欢迎通知",
	Description = "通知会根据正文长度自动安排显示时间",
	ActionText = "发送",
	Callback = function()
		notify("欢迎使用 Velora", "中文完整演示已加载，可以从左侧标签页逐项体验。", "Success")
	end,
})

local NotificationTab = Window:AddTab({
	Title = "通知",
	Icon = "通",
	Description = "五种状态与完整生命周期",
})

local TypeSection = NotificationTab:AddSection({
	Title = "通知类型",
	Description = "成功、信息、警告、错误与加载",
	Side = "Left",
})

TypeSection:AddButton({
	Title = "成功通知与详情",
	Description = "点击通知中的详情按钮检查全屏遮罩",
	ActionText = "成功",
	Variant = "Primary",
	Callback = function()
		local detailNotification = UI:Notify({
			Title = "保存成功",
			Content = "设置已经安全保存。点击详情可打开全屏对话框。",
			Type = "Success",
			Duration = 7,
			CanClose = true,
			MaxVisible = 5,
			Actions = {
				{
					Title = "详情",
					Variant = "Primary",
					Callback = function()
						UI:Dialog({
							Title = "通知详情",
							Content = "这层灰色遮罩使用独立的全屏界面，应覆盖画面顶部与 Roblox 顶栏区域。",
							Buttons = {
								{ Title = "知道了", Variant = "Primary" },
							},
						})
					end,
				},
			},
		})
		detailNotification.Closed:Connect(function(reason)
			notify("通知关闭事件", "上一条通知的关闭原因是：“" .. tostring(reason) .. "”。", "Info")
		end)
	end,
})

TypeSection:AddButton({
	Title = "信息通知",
	Description = "适合普通状态说明",
	ActionText = "信息",
	Callback = function()
		notify("同步提示", "当前设置已经与统一状态中心同步。", "Info")
	end,
})

TypeSection:AddButton({
	Title = "警告通知",
	Description = "适合需要用户留意的内容",
	ActionText = "警告",
	Callback = function()
		notify("请注意", "这是演示警告，不会影响角色或游戏数据。", "Warning")
	end,
})

TypeSection:AddButton({
	Title = "错误通知",
	Description = "适合显示失败状态",
	ActionText = "错误",
	Danger = true,
	Callback = function()
		notify("演示错误", "这是用于预览样式的模拟错误。", "Error")
	end,
})

local loadingNotification

TypeSection:AddButton({
	Title = "加载通知",
	Description = "创建一个不会自动关闭的加载状态",
	ActionText = "开始",
	Callback = function()
		if loadingNotification then
			loadingNotification:Update({ Content = "加载仍在进行，请稍候……", Duration = math.huge })
			return
		end
		loadingNotification = UI:Notify({
			Id = "velora_demo_loading",
			Title = "正在加载",
			Content = "正在准备演示资源，请稍候……",
			Type = "Loading",
			Duration = math.huge,
			OnClose = function()
				loadingNotification = nil
			end,
		})
	end,
})

local LifecycleSection = NotificationTab:AddSection({
	Title = "通知生命周期",
	Description = "更新、关闭与去重",
	Side = "Right",
})

LifecycleSection:AddButton({
	Title = "更新加载通知",
	Description = "复用已有句柄修改标题与正文",
	ActionText = "更新",
	Callback = function()
		if loadingNotification then
			loadingNotification:Update({
				Title = "加载即将完成",
				Content = "进度已更新，仍保持常驻显示。",
				Duration = math.huge,
			})
		else
			notify("没有加载通知", "请先点击左侧的“加载通知”。", "Warning")
		end
	end,
})

LifecycleSection:AddButton({
	Title = "关闭加载通知",
	Description = "通过通知句柄主动关闭",
	ActionText = "关闭",
	Callback = function()
		if loadingNotification then
			loadingNotification:Close("demo")
		else
			notify("无需关闭", "当前没有正在显示的加载通知。", "Info")
		end
	end,
})

LifecycleSection:AddButton({
	Title = "演示通知去重",
	Description = "相同编号只保留一个通知，并更新其内容",
	ActionText = "去重",
	Callback = function()
		UI:Notify({
			Id = "velora_demo_deduplicate",
			Title = "去重通知",
			Content = "第一次发送：正在等待更新。",
			Type = "Info",
			Duration = 6,
		})
		task.delay(0.2, function()
			UI:Notify({
				Id = "velora_demo_deduplicate",
				Title = "去重完成",
				Content = "第二次发送更新了原通知，没有创建重复卡片。",
				Type = "Info",
				Duration = 6,
			})
		end)
	end,
})

LifecycleSection:AddButton({
	Title = "可保留的通知操作",
	Description = "操作按钮可选择不立即关闭通知",
	ActionText = "发送",
	Callback = function()
		UI:Notify({
			Title = "选择操作",
			Content = "“刷新内容”会保留通知，“完成”会关闭通知。",
			Type = "Info",
			Duration = 0,
			Actions = {
				{
					Title = "刷新内容",
					Close = false,
					Callback = function(handle)
						handle:Update({ Content = "内容已刷新，通知仍然保留。" })
					end,
				},
				{ Title = "完成", Variant = "Primary" },
			},
		})
	end,
})

local ControlsTab = Window:AddTab({
	Title = "控件",
	Icon = "控",
	Description = "输入、选择、按键与颜色",
})

local BasicSection = ControlsTab:AddSection({
	Title = "基础控件",
	Description = "按钮、开关、滑块与进度",
	Side = "Left",
})

local FeatureEnabled = BasicSection:AddToggle({
	Title = "启用演示功能",
	Description = "关闭后会禁用音量滑块",
	Flag = "demo.enabled",
	Default = true,
})

local CheckOption = BasicSection:AddToggle({
	Title = "复选风格选项",
	Description = "同一个开关控件也可用于布尔选项",
	Flag = "demo.checkbox",
	Default = false,
})

local Volume = BasicSection:AddSlider({
	Title = "界面音量",
	Description = "2.5 步进；拖动连续跟手，松手后精确吸附",
	Flag = "demo.volume",
	Min = 0,
	Max = 100,
	Step = 2.5,
	Default = 65,
	Suffix = "%",
})

local VolumeProgress = BasicSection:AddProgress({
	Title = "音量进度",
	Description = "由状态观察器实时同步",
	Flag = "demo.volume_progress",
	Min = 0,
	Max = 100,
	Default = 65,
	NoSave = true,
})

BasicSection:AddButton({
	Title = "普通按钮",
	Description = "执行一个安全的示例回调",
	ActionText = "运行",
	Variant = "Primary",
	Callback = function()
		notify("按钮已触发", "普通按钮的回调运行成功。", "Success")
	end,
})

local progressIndeterminate = false
BasicSection:AddButton({
	Title = "切换不确定进度",
	Description = "演示 SetIndeterminate 与 GetPercentage",
	ActionText = "切换",
	Callback = function()
		progressIndeterminate = not progressIndeterminate
		VolumeProgress:SetIndeterminate(progressIndeterminate)
		if not progressIndeterminate then
			notify("进度恢复", "当前确定进度为 " .. tostring(math.floor(VolumeProgress:GetPercentage())) .. "% 。", "Info")
		end
	end,
})

local InputSection = ControlsTab:AddSection({
	Title = "输入控件",
	Description = "普通、数字与多行输入",
	Side = "Right",
})

local NameInput = InputSection:AddInput({
	Title = "显示名称",
	Description = "最多输入二十四个字符",
	Flag = "profile.name",
	Default = "玩家",
	Placeholder = "请输入名称……",
	MaxLength = 24,
	OnEnter = function(value)
		notify("名称已确认", "当前显示名称为：“" .. tostring(value) .. "”。", "Success")
	end,
})

local SpeedInput = InputSection:AddInput({
	Title = "数值输入",
	Description = "只接受零到一百之间的数字",
	Flag = "profile.number",
	Default = 16,
	Placeholder = "请输入数字……",
	Numeric = true,
	Min = 0,
	Max = 100,
})

local NotesInput = InputSection:AddInput({
	Title = "多行备注",
	Description = "适合较长的说明文本",
	Flag = "profile.notes",
	Default = "",
	Placeholder = "在这里输入多行内容……",
	Multiline = true,
	MaxLength = 240,
})

local SelectionSection = ControlsTab:AddSection({
	Title = "选择控件",
	Description = "下拉、多选与分段选择",
	Side = "Left",
})

local RegionDropdown = SelectionSection:AddDropdown({
	Title = "服务器区域",
	Description = "选项较多时支持搜索",
	Flag = "profile.region",
	Values = {
		{ Title = "自动选择", Description = "优先选择延迟最低的区域", Value = "auto" },
		{ Title = "亚洲", Description = "新加坡与东京", Value = "asia" },
		{ Title = "欧洲", Description = "法兰克福与伦敦", Value = "europe" },
		{ Title = "北美", Description = "弗吉尼亚与俄勒冈", Value = "north_america" },
	},
	Default = "auto",
	Searchable = true,
})

local PanelsDropdown = SelectionSection:AddMultiDropdown({
	Title = "显示面板",
	Description = "可同时选择多个项目",
	Flag = "profile.panels",
	Values = { "状态", "背包", "聊天", "地图", "任务", "好友", "设置" },
	Default = { "状态", "地图" },
})

local QualitySegment = SelectionSection:AddSegmented({
	Title = "画面质量",
	Description = "紧凑的单选控件",
	Flag = "profile.quality",
	Values = { "流畅", "均衡", "精致" },
	Default = "精致",
})

local AdvancedSection = ControlsTab:AddSection({
	Title = "高级控件",
	Description = "按键绑定与颜色选择",
	Side = "Right",
})

local QuickKey = AdvancedSection:AddKeybind({
	Title = "快捷操作按键",
	Description = "点击右侧按键框后按下新按键",
	Flag = "profile.keybind",
	Default = Enum.KeyCode.H,
	Mode = "Press",
	BlackList = { Enum.KeyCode.G },
	OnActivated = function()
		notify("快捷键已触发", "按键绑定回调运行成功。", "Info")
	end,
})

local PreviewColor = AdvancedSection:AddColorPicker({
	Title = "预览颜色",
	Description = "支持十六进制颜色与透明度",
	Flag = "profile.color",
	Default = Color3.fromRGB(124, 99, 255),
	Transparency = 0.1,
	AllowTransparency = true,
})

AdvancedSection:AddButton({
	Title = "读取高级控件",
	Description = "演示获取下拉、按键与颜色值",
	ActionText = "读取",
	Callback = function()
		notify(
			"当前选择",
			"区域：" .. tostring(RegionDropdown:Get()) .. "；快捷键：" .. tostring(QuickKey:Get()) .. "；透明度：" .. string.format("%.0f%%", PreviewColor:GetTransparency() * 100) .. "。",
			"Info"
		)
	end,
})

local DisplayTab = Window:AddTab({
	Title = "展示",
	Icon = "展",
	Description = "文本、代码、图片与布局组件",
})

local TextDisplaySection = DisplayTab:AddSection({
	Title = "文字与布局",
	Description = "标签、段落、分隔线与留白",
	Side = "Left",
})

local DynamicLabel = TextDisplaySection:AddLabel({
	Text = "这是一个可动态更新的文字标签",
	Bold = true,
	ColorToken = "Text",
})

TextDisplaySection:AddDivider()

local DemoParagraph = TextDisplaySection:AddParagraph({
	Title = "段落组件",
	Content = "段落适合说明功能、展示更新日志，或向用户提供较长的上下文信息。",
})

TextDisplaySection:AddSpacer(12)

TextDisplaySection:AddButton({
	Title = "更新文字内容",
	Description = "调用静态控件的 Set 方法",
	ActionText = "更新",
	Callback = function()
		DynamicLabel:Set("文字标签已在运行时更新")
		DemoParagraph:Set({
			Title = "内容已更新",
			Content = "标签与段落也提供统一的 Set、Reset 与可见性接口。",
		})
	end,
})

local MediaSection = DisplayTab:AddSection({
	Title = "代码与图片",
	Description = "适合教程、文档与媒体预览",
	Side = "Right",
})

local DemoCode = MediaSection:AddCode({
	Title = "状态 API 示例",
	Code = "local current = UI:GetFlag(\"demo.volume\")\nUI:SetFlag(\"demo.volume\", 80, { Source = \"api\" })\nprint(\"当前音量\", current)",
	Height = 150,
	CopyText = "复制",
	CopiedText = "已复制",
	FailedText = "失败",
	UnavailableText = "不可用",
})

MediaSection:AddImage({
	Title = "图片组件预览",
	Image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
	Height = 170,
	ScaleType = Enum.ScaleType.Fit,
})

MediaSection:AddButton({
	Title = "更新代码片段",
	Description = "演示 SetCode 特殊方法",
	ActionText = "更新",
	Callback = function()
		DemoCode:SetCode("local flags = UI:GetFlags()\nprint(\"状态数量\", #flags)\n-- 中文演示代码已更新")
	end,
})

local StateTab = Window:AddTab({
	Title = "状态",
	Icon = "态",
	Description = "统一句柄与中心状态 API",
})

local StateApiSection = StateTab:AddSection({
	Title = "读取与写入",
	Description = "Get、Set、Reset、Observe 与 GetFlags",
	Side = "Left",
})

local StateStatus = StateApiSection:AddLabel({
	Text = "等待状态变化",
	Bold = true,
	ColorToken = "Accent",
	Wrap = true,
	Height = 44,
})

StateApiSection:AddButton({
	Title = "读取控件值",
	Description = "使用控件句柄的 Get 方法",
	ActionText = "读取",
	Callback = function()
		StateStatus:Set("Get：开关=" .. tostring(FeatureEnabled:Get()) .. "，音量=" .. tostring(Volume:Get()))
	end,
})

StateApiSection:AddButton({
	Title = "写入示例值",
	Description = "使用 Set 修改多个控件",
	ActionText = "写入",
	Callback = function()
		FeatureEnabled:Set(true, { Source = "api" })
		Volume:Set(80, { Source = "api" })
		NameInput:Set("Velora 玩家", { Source = "api" })
	end,
})

StateApiSection:AddButton({
	Title = "重置示例值",
	Description = "恢复控件创建时的默认值",
	ActionText = "重置",
	Callback = function()
		FeatureEnabled:Reset()
		CheckOption:Reset()
		Volume:Reset()
		NameInput:Reset()
		SpeedInput:Reset()
		NotesInput:Reset()
		RegionDropdown:Reset()
		PanelsDropdown:Reset()
		QualitySegment:Reset()
		QuickKey:Reset()
		PreviewColor:Reset()
	end,
})

StateApiSection:AddButton({
	Title = "读取全部状态",
	Description = "使用 GetFlags 获取所有已注册标记",
	ActionText = "查看",
	Callback = function()
		local flags = UI:GetFlags()
		UI:Dialog({
			Title = "状态中心摘要",
			Content = "当前共有 " .. tostring(countEntries(flags)) .. " 个状态标记。音量为 " .. tostring(flags["demo.volume"]) .. "，名称为“" .. tostring(flags["profile.name"]) .. "”。",
			Buttons = {
				{ Title = "关闭", Variant = "Primary" },
			},
		})
	end,
})

local LifecycleApiSection = StateTab:AddSection({
	Title = "控件生命周期",
	Description = "禁用、隐藏、高亮与状态观察",
	Side = "Right",
})

LifecycleApiSection:AddToggle({
	Title = "禁用音量滑块",
	Description = "演示 SetDisabled 与禁用原因",
	Flag = "api.disable_volume",
	Default = false,
	NoSave = true,
	Callback = function(value)
		Volume:SetDisabled(value, "音量滑块已被演示开关锁定")
	end,
})

local paragraphVisible = true
LifecycleApiSection:AddButton({
	Title = "切换段落可见性",
	Description = "演示 SetVisible，不会销毁控件",
	ActionText = "切换",
	Callback = function()
		paragraphVisible = not paragraphVisible
		DemoParagraph:SetVisible(paragraphVisible)
		StateStatus:Set(paragraphVisible and "SetVisible：段落已显示" or "SetVisible：段落已隐藏")
	end,
})

LifecycleApiSection:AddButton({
	Title = "高亮音量滑块",
	Description = "演示 Highlight 的临时强调边框",
	ActionText = "高亮",
	Callback = function()
		Window:SelectTab(ControlsTab)
		Volume:Highlight(1.2)
	end,
})

LifecycleApiSection:AddButton({
	Title = "通过状态中心写入",
	Description = "使用 SetFlag 更新已经注册的控件",
	ActionText = "设为 35",
	Callback = function()
		UI:SetFlag("demo.volume", 35, { Source = "state_api" })
	end,
})

FeatureEnabled:OnChanged(function(value, previous, source)
	Volume:SetDisabled(not value, "请先启用演示功能")
	StateStatus:Set("OnChanged：启用状态由 " .. tostring(previous) .. " 变为 " .. tostring(value) .. "，来源=" .. tostring(source))
end)

UI:Observe("demo.volume", function(value, previous, source)
	VolumeProgress:Set(value, { Source = "observe" })
	StateStatus:Set("Observe：音量由 " .. tostring(previous) .. " 变为 " .. tostring(value) .. "，来源=" .. tostring(source))
end)

local AppearanceTab = Window:AddTab({
	Title = "外观",
	Icon = "色",
	Description = "十三套主题、强调色与顶部悬浮窗",
})

local ThemeSection = AppearanceTab:AddSection({
	Title = "主题与强调色",
	Description = "切换主题时所有现有控件都会实时更新",
	Side = "Left",
})

local themeNames = {
	Midnight = "午夜",
	Ocean = "深海",
	Violet = "紫罗兰",
	Emerald = "翡翠",
	Amber = "琥珀",
	Rose = "玫瑰",
	Crimson = "绯红",
	Nord = "北境",
	Cyber = "赛博",
	Light = "明亮",
	Sakura = "樱花",
	Latte = "拿铁",
	HighContrast = "高对比",
	AuroraCN = "极光自定义",
	Custom = "自定义配色",
}

ThemeSection:AddDropdown({
	Title = "内置主题（十三套）",
	Description = "选择后立即应用，不会重建窗口",
	Flag = "appearance.theme_preview",
	Values = {
		{ Title = "午夜", Description = "深色中性配色", Value = "Midnight" },
		{ Title = "深海", Description = "蓝色深海配色", Value = "Ocean" },
		{ Title = "紫罗兰", Description = "紫色强调配色", Value = "Violet" },
		{ Title = "翡翠", Description = "清爽绿色配色", Value = "Emerald" },
		{ Title = "琥珀", Description = "温暖金色配色", Value = "Amber" },
		{ Title = "玫瑰", Description = "柔和粉色配色", Value = "Rose" },
		{ Title = "绯红", Description = "浓郁红色配色", Value = "Crimson" },
		{ Title = "北境", Description = "冷静低饱和配色", Value = "Nord" },
		{ Title = "赛博", Description = "高亮青色配色", Value = "Cyber" },
		{ Title = "明亮", Description = "浅色界面配色", Value = "Light" },
		{ Title = "樱花", Description = "浅粉色界面配色", Value = "Sakura" },
		{ Title = "拿铁", Description = "温和米色配色", Value = "Latte" },
		{ Title = "高对比", Description = "强调可读性的配色", Value = "HighContrast" },
	},
	Default = "Midnight",
	Searchable = true,
	Callback = function(value)
		UI:SetTheme(value)
	end,
})

ThemeSection:AddColorPicker({
	Title = "自定义强调色",
	Description = "通过 SetAccent 覆盖当前强调色",
	Flag = "appearance.accent",
	Default = Color3.fromRGB(124, 99, 255),
	Callback = function(value)
		UI:SetAccent(value)
	end,
})

ThemeSection:AddButton({
	Title = "应用极光自定义主题",
	Description = "演示 RegisterTheme 与 SetTheme",
	ActionText = "应用",
	Variant = "Primary",
	Callback = function()
		UI:SetTheme("AuroraCN")
	end,
})

ThemeSection:AddButton({
	Title = "查看当前主题",
	Description = "读取当前主题名称",
	ActionText = "查看",
	Callback = function()
		local current = UI:GetCurrentTheme()
		notify("当前主题", themeNames[current] or "自定义主题", "Info")
	end,
})

local OpenButtonSection = AppearanceTab:AddSection({
	Title = "顶部悬浮窗",
	Description = "编辑 Wind UI 风格的恢复胶囊",
	Side = "Right",
})

local OnlyIconToggle = OpenButtonSection:AddToggle({
	Title = "仅显示图标",
	Description = "将顶部胶囊切换为紧凑模式",
	Flag = "appearance.open_only_icon",
	Default = false,
	NoSave = true,
	Callback = function(value)
		Window:EditOpenButton({ OnlyIcon = value })
	end,
})

local DraggableToggle = OpenButtonSection:AddToggle({
	Title = "允许拖动悬浮窗",
	Description = "与 Wind UI 一样，可拖到屏幕最顶部",
	Flag = "appearance.open_draggable",
	Default = true,
	NoSave = true,
	Callback = function(value)
		Window:EditOpenButton({ Draggable = value })
	end,
})

local OpenScale = OpenButtonSection:AddSlider({
	Title = "悬浮窗缩放",
	Description = "调整顶部胶囊的整体尺寸",
	Flag = "appearance.open_scale",
	Min = 0.7,
	Max = 1.3,
	Step = 0.05,
	Default = 1,
	NoSave = true,
	Callback = function(value)
		Window:EditOpenButton({ Scale = value })
	end,
})

local OpenColor = OpenButtonSection:AddColorPicker({
	Title = "悬浮窗描边颜色",
	Description = "选择纯色描边，重置后恢复渐变",
	Flag = "appearance.open_color",
	Default = Color3.fromRGB(64, 201, 255),
	NoSave = true,
	Callback = function(value)
		Window:EditOpenButton({ Color = value })
	end,
})

OpenButtonSection:AddButton({
	Title = "恢复悬浮窗默认样式",
	Description = "恢复标题、位置、缩放与渐变描边",
	ActionText = "恢复",
	Callback = function()
		OnlyIconToggle:Set(false)
		DraggableToggle:Set(true)
		OpenScale:Set(1)
		OpenColor:Reset({ Silent = true })
		local openButton = Window:EditOpenButton({
			Title = "打开 Velora",
			Icon = "界",
			OnlyIcon = false,
			Draggable = true,
			Scale = 1,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(64, 201, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(232, 28, 255)),
			}),
		})
		if openButton then
			openButton:ResetPosition()
		end
	end,
})

OpenButtonSection:AddButton({
	Title = "立即显示顶部悬浮窗",
	Description = "隐藏主窗口后，点击胶囊即可完整恢复",
	ActionText = "最小化",
	Variant = "Primary",
	Callback = function()
		Window:Minimize()
	end,
})

local ConfigTab = Window:AddTab({
	Title = "配置",
	Icon = "配",
	Description = "保存、加载、列表、删除与导入导出",
})

local StorageSection = ConfigTab:AddSection({
	Title = "配置存储",
	Description = "支持文件环境，也会自动回退到会话内存",
	Side = "Left",
})

StorageSection:AddButton({
	Title = "保存演示配置",
	Description = "保存当前主题、状态与窗口信息",
	ActionText = "保存",
	Variant = "Primary",
	Callback = function()
		local success, backend = UI:SaveConfig("chinese_demo")
		if success then
			notify("配置已保存", "存储位置：" .. storageName(backend) .. "。", "Success")
		else
			notify("保存失败", "当前运行环境无法保存配置。", "Error")
		end
	end,
})

StorageSection:AddButton({
	Title = "加载演示配置",
	Description = "将已保存值重新应用到控件",
	ActionText = "加载",
	Callback = function()
		local success, report = UI:LoadConfig("chinese_demo")
		if success then
			notify("配置已加载", "已应用 " .. tostring(report.Applied) .. " 个状态值。", "Success")
		else
			notify("加载失败", "请先保存一次演示配置。", "Warning")
		end
	end,
})

StorageSection:AddButton({
	Title = "列出已有配置",
	Description = "调用 ListConfigs 获取配置列表",
	ActionText = "列出",
	Callback = function()
		local configs = UI:ListConfigs()
		if #configs == 0 then
			notify("配置列表", "当前没有可用配置。", "Info")
		else
			notify("配置列表", "共找到 " .. tostring(#configs) .. " 个配置。", "Info")
		end
	end,
})

StorageSection:AddButton({
	Title = "删除演示配置",
	Description = "删除前会打开中文确认对话框",
	ActionText = "删除",
	Danger = true,
	Callback = function()
		UI:Dialog({
			Title = "删除演示配置？",
			Content = "只会删除名为“中文演示”的示例配置，不会修改任何游戏数据。",
			Buttons = {
				{ Title = "取消", Variant = "Secondary" },
				{
					Title = "确认删除",
					Variant = "Danger",
					Callback = function()
						local success = UI:DeleteConfig("chinese_demo")
						if success then
							notify("配置已删除", "演示配置已从当前存储中移除。", "Success")
						else
							notify("没有可删除的配置", "请先保存一次演示配置。", "Info")
						end
					end,
				},
			},
		})
	end,
})

local TransferSection = ConfigTab:AddSection({
	Title = "导入与导出",
	Description = "JSON 配置可用于复制或自定义存储",
	Side = "Right",
})

local ExportPreview = TransferSection:AddCode({
	Title = "导出内容预览",
	Code = "-- 点击下方按钮生成当前配置",
	Height = 180,
	CopyText = "复制",
	CopiedText = "已复制",
	FailedText = "失败",
	UnavailableText = "不可用",
})

local exportedConfig

TransferSection:AddButton({
	Title = "导出当前配置",
	Description = "调用 ExportConfig 生成 JSON 字符串",
	ActionText = "导出",
	Variant = "Primary",
	Callback = function()
		local content = UI:ExportConfig()
		if content then
			exportedConfig = content
			local preview = string.sub(content, 1, 700)
			if #content > #preview then
				preview = preview .. "\n...（内容已截断）"
			end
			ExportPreview:SetCode(preview)
			notify("导出成功", "已生成 " .. tostring(#content) .. " 个字符的配置内容。", "Success")
		else
			notify("导出失败", "当前状态无法编码为配置。", "Error")
		end
	end,
})

TransferSection:AddButton({
	Title = "导入刚才的配置",
	Description = "调用 ImportConfig 恢复最近一次导出",
	ActionText = "导入",
	Callback = function()
		if not exportedConfig then
			notify("尚未导出", "请先点击“导出当前配置”。", "Warning")
			return
		end
		local success, report = UI:ImportConfig(exportedConfig)
		if success then
			notify("导入成功", "已应用 " .. tostring(report.Applied) .. " 个状态值。", "Success")
		else
			notify("导入失败", "导出内容已经失效，请重新导出。", "Error")
		end
	end,
})

TransferSection:AddButton({
	Title = "导出为数据表",
	Description = "演示 ExportConfig 的数据表模式",
	ActionText = "查看",
	Callback = function()
		local data = UI:ExportConfig({ AsTable = true })
		UI:Dialog({
			Title = "数据表导出摘要",
			Content = "配置结构版本为 " .. tostring(data.Schema) .. "，包含 " .. tostring(countEntries(data.Values)) .. " 个可保存状态。",
			Buttons = {
				{ Title = "关闭", Variant = "Primary" },
			},
		})
	end,
})

UI:RegisterCommand({
	Title = "打开总览",
	Description = "跳转到中文演示总览页",
	Keywords = { "首页", "欢迎", "开始" },
	Callback = function()
		Window:SelectTab(OverviewTab)
	end,
})

UI:RegisterCommand({
	Title = "打开控件演示",
	Description = "跳转到全部输入与选择控件",
	Keywords = { "开关", "滑块", "输入", "下拉" },
	Callback = function()
		Window:SelectTab(ControlsTab)
	end,
})

UI:RegisterCommand({
	Title = "切换翡翠主题",
	Description = "立即应用清爽的绿色主题",
	Keywords = { "主题", "绿色", "外观" },
	Callback = function()
		UI:SetTheme("Emerald")
	end,
})

UI:RegisterCommand({
	Title = "显示欢迎通知",
	Description = "发送一条中文成功通知",
	Keywords = { "消息", "提示", "通知" },
	Callback = function()
		notify("欢迎回来", "命令面板中的中文操作运行成功。", "Success")
	end,
})

UI:RegisterCommand({
	Title = "打开配置管理",
	Description = "跳转到保存、加载与导入导出页面",
	Keywords = { "保存", "加载", "导出", "导入" },
	Callback = function()
		Window:SelectTab(ConfigTab)
	end,
})

UI:RegisterCommand({
	Title = "最小化到顶部悬浮窗",
	Description = "隐藏主窗口并显示顶部恢复胶囊",
	Keywords = { "隐藏", "缩小", "胶囊", "悬浮" },
	Callback = function()
		Window:Minimize()
	end,
})

Window:SelectTab(OverviewTab)

notify("Velora 已就绪", "中文全功能演示加载完成，点击左侧标签页开始体验。", "Success")
