local Velora = loadstring(game:HttpGet("https://raw.githubusercontent.com/kismile36/VeloraUI/main/Velora.lua"))()

local UI = Velora.new({
	Name = "VeloraDemo",
	DestroyExisting = true,
	Theme = "Midnight",
	ToggleKey = Enum.KeyCode.RightShift,
	OpenButton = {
		Title = "Velora UI",
		Icon = "V",
		OnlyMobile = false,
		Draggable = true,
	},
	Config = {
		Folder = "VeloraDemo",
		File = "showcase",
		AutoSave = false,
	},
})

local Window = UI:CreateWindow({
	Title = "Velora UI",
	Subtitle = "Complete component showcase",
	Icon = "V",
	Size = UDim2.fromOffset(920, 600),
	Resizable = true,
	Search = true,
	ShowUser = true,
})

local Home = Window:AddTab({
	Title = "Home",
	Icon = "H",
	Description = "Overview and quick actions",
})

local Welcome = Home:AddSection({
	Title = "Welcome",
	Description = "A self-contained Roblox interface library",
	Side = "Left",
})

Welcome:AddParagraph({
	Title = "Designed for real projects",
	Content = "Responsive layout, unified state, safe callbacks, top-level popups, live themes, configuration profiles and complete cleanup are built in.",
})

Welcome:AddButton({
	Title = "Show notification",
	Description = "Notifications support types, actions and deduplication",
	ActionText = "Preview",
	Variant = "Primary",
	Callback = function()
		UI:Notify({
			Title = "Velora is ready",
			Content = "This notification adapts its duration to the amount of text.",
			Type = "Success",
			Actions = {
				{
					Title = "Details",
					Variant = "Primary",
					Callback = function()
						UI:Dialog({
							Title = "Notification actions",
							Content = "Buttons can run callbacks and optionally keep the notification open.",
						})
					end,
				},
			},
		})
	end,
})

Welcome:AddButton({
	Title = "Dangerous action",
	Description = "Buttons can request confirmation before running",
	ActionText = "Reset",
	Danger = true,
	Confirm = "This is only a confirmation preview. No data will be changed.",
	Callback = function()
		UI:Notify({ Title = "Confirmed", Content = "The callback ran successfully.", Type = "Info" })
	end,
})

local LiveState = Home:AddSection({
	Title = "Live state",
	Description = "Every value control uses a stable Flag",
	Side = "Right",
})

local Enabled = LiveState:AddToggle({
	Title = "Feature enabled",
	Description = "The whole row is clickable",
	Flag = "demo.enabled",
	Default = true,
})

local Intensity = LiveState:AddSlider({
	Title = "Intensity",
	Description = "Mouse, touch and keyboard arrows are supported",
	Flag = "demo.intensity",
	Min = 0,
	Max = 100,
	Step = 5,
	Default = 65,
	Suffix = "%",
})

LiveState:AddProgress({
	Title = "Completion",
	Description = "Progress can be determinate or indeterminate",
	Flag = "demo.progress",
	Default = 65,
})

Enabled:OnChanged(function(value)
	Intensity:SetDisabled(not value, "Enable the feature first")
end)

local Controls = Window:AddTab({
	Title = "Controls",
	Icon = "C",
	Description = "Inputs, selections and bindings",
})

local Inputs = Controls:AddSection({
	Title = "Input",
	Description = "Validated text and number entry",
	Side = "Left",
})

Inputs:AddInput({
	Title = "Display name",
	Flag = "profile.name",
	Default = "Player",
	Placeholder = "Type a name...",
	MaxLength = 24,
})

Inputs:AddInput({
	Title = "Walk speed",
	Flag = "profile.speed",
	Default = 16,
	Numeric = true,
	Min = 0,
	Max = 100,
})

Inputs:AddInput({
	Title = "Notes",
	Description = "Multiline input expands into a larger editor",
	Flag = "profile.notes",
	Default = "",
	Placeholder = "Write something...",
	Multiline = true,
})

local Selections = Controls:AddSection({
	Title = "Selection",
	Description = "Searchable overlays never get clipped",
	Side = "Right",
})

Selections:AddDropdown({
	Title = "Region",
	Flag = "profile.region",
	Values = {
		{ Title = "Automatic", Description = "Choose the closest region", Value = "Auto" },
		{ Title = "Asia", Description = "Singapore and Tokyo", Value = "Asia" },
		{ Title = "Europe", Description = "Frankfurt and London", Value = "Europe" },
		{ Title = "North America", Description = "Virginia and Oregon", Value = "NA" },
	},
	Default = "Auto",
	Searchable = true,
})

Selections:AddMultiDropdown({
	Title = "Visible panels",
	Flag = "profile.panels",
	Values = { "Stats", "Inventory", "Chat", "Map", "Quests", "Friends", "Settings" },
	Default = { "Stats", "Map" },
})

Selections:AddSegmented({
	Title = "Quality",
	Flag = "profile.quality",
	Values = { "Low", "Medium", "High" },
	Default = "High",
})

local Advanced = Controls:AddSection({
	Title = "Advanced",
	Description = "Keyboard and color controls",
	Side = "Right",
})

Advanced:AddKeybind({
	Title = "Quick action",
	Flag = "profile.keybind",
	Default = Enum.KeyCode.G,
	Mode = "Press",
	OnActivated = function()
		UI:Notify({ Title = "Keybind", Content = "The quick action was triggered.", Type = "Info" })
	end,
})

Advanced:AddColorPicker({
	Title = "Accent preview",
	Flag = "profile.color",
	Default = Color3.fromRGB(124, 99, 255),
	Transparency = 0,
	AllowTransparency = true,
})

local Themes = Window:AddTab({
	Title = "Appearance",
	Icon = "A",
	Description = "Live theme switching",
})

local ThemeSection = Themes:AddSection({
	Title = "Themes",
	Description = "All existing objects update without rebuilding",
	Side = "Left",
})

for _, themeName in ipairs({
	"Midnight",
	"Ocean",
	"Violet",
	"Emerald",
	"Amber",
	"Rose",
	"Crimson",
	"Nord",
	"Cyber",
	"Light",
	"Sakura",
	"Latte",
	"HighContrast",
}) do
	ThemeSection:AddButton({
		Title = themeName,
		ActionText = "Apply",
		Callback = function()
			UI:SetTheme(themeName)
		end,
	})
end

local DisplaySection = Themes:AddSection({
	Title = "Display components",
	Description = "Useful for dashboards and documentation",
	Side = "Right",
})

DisplaySection:AddButton({
	Title = "Preview top open button",
	Description = "Hide the main window and restore it from the draggable floating pill",
	ActionText = "Preview",
	Callback = function()
		Window:Close()
	end,
})

DisplaySection:AddToggle({
	Title = "Icon-only open button",
	Description = "Switch the floating pill between compact and labeled layouts",
	Default = false,
	Callback = function(value)
		Window:EditOpenButton({ OnlyIcon = value })
	end,
})

DisplaySection:AddLabel({
	Text = "A compact informational label",
	Bold = true,
	ColorToken = "Text",
})

DisplaySection:AddDivider()

DisplaySection:AddCode({
	Title = "Current flags",
	Code = "local enabled = UI:GetFlag(\"demo.enabled\")\nUI:SetFlag(\"demo.intensity\", 75)",
	Height = 150,
})

local Settings = Window:AddTab({
	Title = "Settings",
	Icon = "S",
	Description = "Configuration and lifecycle",
})

local ConfigSection = Settings:AddSection({
	Title = "Configuration",
	Description = "File storage when available, memory fallback otherwise",
	Side = "Left",
})

ConfigSection:AddButton({
	Title = "Save profile",
	ActionText = "Save",
	Callback = function()
		local success, backend = UI:SaveConfig("showcase")
		UI:Notify({
			Title = success and "Saved" or "Save failed",
			Content = success and ("Backend: " .. tostring(backend)) or tostring(backend),
			Type = success and "Success" or "Error",
		})
	end,
})

ConfigSection:AddButton({
	Title = "Load profile",
	ActionText = "Load",
	Callback = function()
		local success, report = UI:LoadConfig("showcase")
		UI:Notify({
			Title = success and "Loaded" or "Load failed",
			Content = success and ("Applied flags: " .. tostring(report.Applied)) or tostring(report),
			Type = success and "Success" or "Error",
		})
	end,
})

ConfigSection:AddButton({
	Title = "Reset visible demo values",
	ActionText = "Reset",
	Confirm = true,
	Callback = function()
		Enabled:Reset()
		Intensity:Reset()
	end,
})

UI:RegisterCommand({
	Title = "Switch to Emerald",
	Description = "Apply the Emerald theme",
	Keywords = { "theme", "green", "appearance" },
	Callback = function()
		UI:SetTheme("Emerald")
	end,
})

UI:RegisterCommand({
	Title = "Show welcome notification",
	Description = "Preview the notification system",
	Keywords = { "toast", "message" },
	Callback = function()
		UI:Notify({ Title = "Welcome", Content = "Command palette actions work.", Type = "Success" })
	end,
})
