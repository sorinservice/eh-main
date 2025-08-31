-- orion-loader.lua
-- Hauptlogik der (modifizierten) Orion-Library für SorinHub
-- Liest Konfiguration aus getgenv()._SorinOrionConfig ODER (Fallback) per URL.

-- ======= Konfig-Lade-Strategie =======================================
local CONFIG_URL = "https://raw.githubusercontent.com/sorinservice/eh-main/dev/orion-lib/orion-config.lua"

local function safeLoadConfig()
    -- 1) Global bereits gesetzt?
    local ok1, cfg = pcall(function() return getgenv and getgenv()._SorinOrionConfig end)
    if ok1 and type(cfg) == "table" then return cfg end

    -- 2) Remote laden als Fallback
    local ok2, out = pcall(function()
        return loadstring(game:HttpGet(CONFIG_URL))()
    end)
    if ok2 and type(out) == "table" then return out end

    -- 3) Harte Fallback-Defaults (falls Remote nicht erreichbar)
    return {
        CHANNEL = "DEV",
        GuiName = "SorinUI",
        IntroEnabled = true,
        IntroText = "SorinHub",
        IntroIcon = "rbxassetid://8834748103",
        WindowIcon = "rbxassetid://122633020844347",
        Theme = {
            Main    = Color3.fromRGB(22, 20, 26),
            Second  = Color3.fromRGB(30, 28, 36),
            Stroke  = Color3.fromRGB(70, 62, 92),
            Divider = Color3.fromRGB(52, 46, 68),
            Text    = Color3.fromRGB(238, 236, 244),
            TextDark= Color3.fromRGB(176, 168, 196),
        },
        Accent = {
            Primary   = Color3.fromRGB(158, 96, 255),
            PrimaryHi = Color3.fromRGB(182, 126, 255),
        },
        Icons = {
            home    = "rbxassetid://133768243848629",
            info    = "rbxassetid://133768243848629",
            visual  = "rbxassetid://133768243848629",
            bypass  = "rbxassetid://133768243848629",
            utility = "rbxassetid://133768243848629",
            close   = "rbxassetid://7072725342",
            minimize= "rbxassetid://7072719338",
            unmin   = "rbxassetid://7072720870",
            dropdown= "rbxassetid://7072706796",
            check   = "rbxassetid://3944680095",
            avatarFrame = "rbxassetid://4031889928",
        },
        SaveConfig = false,
        ConfigFolder = "SorinHub",
    }
end

local Cfg = safeLoadConfig()

-- ======= Roblox Services ============================================
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local LocalPlayer      = game:GetService("Players").LocalPlayer
local Mouse            = LocalPlayer:GetMouse()
local HttpService      = game:GetService("HttpService")

-- ======= Global gethui-Helper =======================================
getgenv().gethui = getgenv().gethui or function()
    return game.CoreGui
end

-- ======= OrionLib Grundgerüst =======================================
local OrionLib = {
    Elements = {},
    ThemeObjects = {},
    Connections = {},
    Flags = {},
    Themes = {
        Default = {
            Main    = Cfg.Theme.Main,
            Second  = Cfg.Theme.Second,
            Stroke  = Cfg.Theme.Stroke,
            Divider = Cfg.Theme.Divider,
            Text    = Cfg.Theme.Text,
            TextDark= Cfg.Theme.TextDark,
        }
    },
    SelectedTheme = "Default",
    Folder = nil,
    SaveCfg = false
}

-- ======= Icon-Mapping ===============================================
local Icons = Cfg.Icons or {}
local function GetIcon(key)
    return Icons and Icons[key] or nil
end

-- ======= ScreenGui Setup ============================================
local Orion = Instance.new("ScreenGui")
Orion.Name = Cfg.GuiName or "SorinUI"

if syn and syn.protect_gui then
    syn.protect_gui(Orion)
    Orion.Parent = game.CoreGui
else
    Orion.Parent = gethui() or game.CoreGui
end

-- Single-instance Guard
do
    local parent = gethui and gethui() or game.CoreGui
    for _, Interface in ipairs(parent:GetChildren()) do
        if Interface.Name == Orion.Name and Interface ~= Orion then
            Interface:Destroy()
        end
    end
end

function OrionLib:IsRunning()
    local parent = gethui and gethui() or game:GetService("CoreGui")
    return Orion.Parent == parent
end

local function AddConnection(Signal, Function)
    if (not OrionLib:IsRunning()) then return end
    local SignalConnect = Signal:Connect(Function)
    table.insert(OrionLib.Connections, SignalConnect)
    return SignalConnect
end

task.spawn(function()
    while (OrionLib:IsRunning()) do task.wait() end
    for _, Connection in next, OrionLib.Connections do
        pcall(function() Connection:Disconnect() end)
    end
end)

-- ======= Mini-UI-Factory ============================================
local function Create(Name, Properties, Children)
    local Object = Instance.new(Name)
    for i, v in next, Properties or {} do Object[i] = v end
    for _, v in next, Children or {} do v.Parent = Object end
    return Object
end

local function CreateElement(ElementName, ElementFunction)
    OrionLib.Elements[ElementName] = function(...) return ElementFunction(...) end
end
local function MakeElement(ElementName, ...) return OrionLib.Elements[ElementName](...) end

local function SetProps(Element, Props)
    for k, v in pairs(Props or {}) do Element[k] = v end
    return Element
end
local function SetChildren(Element, Children)
    for _, c in ipairs(Children or {}) do c.Parent = Element end
    return Element
end

local function ReturnProperty(Object)
    if Object:IsA("Frame") or Object:IsA("TextButton") then
        return "BackgroundColor3"
    end
    if Object:IsA("ScrollingFrame") then
        return "ScrollBarImageColor3"
    end
    if Object:IsA("UIStroke") then
        return "Color"
    end
    if Object:IsA("TextLabel") or Object:IsA("TextBox") then
        return "TextColor3"
    end
    if Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
        return "ImageColor3"
    end
end

local function AddThemeObject(Object, Type)
    OrionLib.ThemeObjects[Type] = OrionLib.ThemeObjects[Type] or {}
    table.insert(OrionLib.ThemeObjects[Type], Object)
    Object[ReturnProperty(Object)] = OrionLib.Themes[OrionLib.SelectedTheme][Type]
    return Object
end

-- ======= Config Load/Save ===========================================
local function PackColor(Color) return {R=Color.R*255,G=Color.G*255,B=Color.B*255} end
local function UnpackColor(Color) return Color3.fromRGB(Color.R, Color.G, Color.B) end

local function LoadCfg(Config)
    local Data = HttpService:JSONDecode(Config)
    for a,b in pairs(Data) do
        if OrionLib.Flags[a] then
            task.spawn(function()
                if OrionLib.Flags[a].Type == "Colorpicker" then
                    OrionLib.Flags[a]:Set(UnpackColor(b))
                else
                    OrionLib.Flags[a]:Set(b)
                end
            end)
        end
    end
end

local function SaveCfg(Name)
    local Data = {}
    for i,v in pairs(OrionLib.Flags) do
        if v.Save then
            if v.Type == "Colorpicker" then
                Data[i] = PackColor(v.Value)
            else
                Data[i] = v.Value
            end
        end
    end
    if writefile then
        writefile(OrionLib.Folder .. "/" .. Name .. ".txt", HttpService:JSONEncode(Data))
    end
end

-- ======= Basic Elements =============================================
CreateElement("Corner", function(Scale, Offset)
    return Create("UICorner", { CornerRadius = UDim.new(Scale or 0, Offset or 10) })
end)
CreateElement("Stroke", function(Color, Thickness)
    return Create("UIStroke", { Color = Color or Color3.fromRGB(255,255,255), Thickness = Thickness or 1 })
end)
CreateElement("List", function(Scale, Offset)
    return Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(Scale or 0, Offset or 0) })
end)
CreateElement("Padding", function(Bottom, Left, Right, Top)
    return Create("UIPadding", {
        PaddingBottom = UDim.new(0, Bottom or 4),
        PaddingLeft   = UDim.new(0, Left or 4),
        PaddingRight  = UDim.new(0, Right or 4),
        PaddingTop    = UDim.new(0, Top or 4)
    })
end)
CreateElement("TFrame", function() return Create("Frame", { BackgroundTransparency = 1 }) end)
CreateElement("Frame",   function(Color) return Create("Frame", { BackgroundColor3 = Color or Color3.fromRGB(255,255,255), BorderSizePixel = 0 }) end)
CreateElement("RoundFrame", function(Color, Scale, Offset)
    return Create("Frame", {
        BackgroundColor3 = Color or Color3.fromRGB(255,255,255),
        BorderSizePixel = 0
    }, { Create("UICorner", { CornerRadius = UDim.new(Scale or 0, Offset or 10) }) })
end)
CreateElement("Button", function()
    return Create("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0 })
end)
CreateElement("ScrollFrame", function(Color, Width)
    return Create("ScrollingFrame", {
        BackgroundTransparency = 0.9,
        MidImage = "rbxassetid://7445543667",
        BottomImage = "rbxassetid://7445543667",
        TopImage = "rbxassetid://7445543667",
        ScrollBarImageColor3 = Color,
        BorderSizePixel = 0,
        ScrollBarThickness = Width or 4,
        CanvasSize = UDim2.new(0,0,0,0)
    })
end)
CreateElement("Image", function(ImageID)
    local ImageNew = Create("ImageLabel", { Image = ImageID, BackgroundTransparency = 1 })
    -- Wenn ImageID ein Icon-Key ist, mappe auf Asset-ID
    if type(ImageID) == "string" and GetIcon(ImageID) then
        ImageNew.Image = GetIcon(ImageID)
    end
    return ImageNew
end)
CreateElement("ImageButton", function(ImageID)
    return Create("ImageButton", { Image = ImageID, BackgroundTransparency = 1 })
end)
CreateElement("Label", function(Text, TextSize, Transparency)
    return Create("TextLabel", {
        Text = Text or "",
        TextColor3 = OrionLib.Themes.Default.Text,
        TextTransparency = Transparency or 0,
        TextSize = TextSize or 15,
        Font = Enum.Font.Gotham,
        RichText = true,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left
    })
end)

-- ======= Notification Holder ========================================
local NotificationHolder = SetProps(SetChildren(MakeElement("TFrame"), {
    SetProps(MakeElement("List"), {
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Padding = UDim.new(0, 5)
    })
}), {
    Position = UDim2.new(1, -25, 1, -25),
    Size = UDim2.new(0, 300, 1, -25),
    AnchorPoint = Vector2.new(1, 1),
    Parent = Orion
})

function OrionLib:MakeNotification(cfg)
    task.spawn(function()
        cfg = cfg or {}
        cfg.Name = cfg.Name or "Notification"
        cfg.Content = cfg.Content or "Test"
        cfg.Image = cfg.Image or "rbxassetid://4384403532"
        cfg.Time = cfg.Time or 10

        local Parent = SetProps(MakeElement("TFrame"), {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = NotificationHolder
        })

        local Frame = SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 10), {
            Parent = Parent, 
            Size = UDim2.new(1, 0, 0, 0),
            Position = UDim2.new(1, -55, 0, 0),
            BackgroundTransparency = 0,
            AutomaticSize = Enum.AutomaticSize.Y
        }), {
            MakeElement("Stroke", OrionLib.Themes.Default.Stroke, 1.2),
            MakeElement("Padding", 12, 12, 12, 12),
            SetProps(MakeElement("Image", cfg.Image), {
                Size = UDim2.new(0, 20, 0, 20),
                ImageColor3 = OrionLib.Themes.Default.Text,
                Name = "Icon"
            }),
            SetProps(MakeElement("Label", cfg.Name, 15), {
                Size = UDim2.new(1, -30, 0, 20),
                Position = UDim2.new(0, 30, 0, 0),
                Font = Enum.Font.GothamBold,
                Name = "Title"
            }),
            SetProps(MakeElement("Label", cfg.Content, 14), {
                Size = UDim2.new(1, 0, 0, 0),
                Position = UDim2.new(0, 0, 0, 25),
                Font = Enum.Font.GothamSemibold,
                Name = "Content",
                AutomaticSize = Enum.AutomaticSize.Y,
                TextColor3 = OrionLib.Themes.Default.TextDark,
                TextWrapped = true
            })
        })

        TweenService:Create(Frame, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {Position = UDim2.new(0, 0, 0, 0)}):Play()
        task.wait(math.max(0, (cfg.Time or 10) - 0.88))
        TweenService:Create(Frame, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {BackgroundTransparency = 0.6}):Play()
        task.wait(0.35)
        TweenService:Create(Frame, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {Position = UDim2.new(1, 20, 0, 0)}):Play()
        task.wait(1.35)
        Frame:Destroy()
    end)
end

-- ======= Dragging ====================================================
local function AddDraggingFunctionality(DragPoint, Main)
    pcall(function()
        local Dragging, DragInput, MousePos, FramePos = false
        DragPoint.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                Dragging = true
                MousePos = Input.Position
                FramePos = Main.Position
                Input.Changed:Connect(function()
                    if Input.UserInputState == Enum.UserInputState.End then
                        Dragging = false
                    end
                end)
            end
        end)
        DragPoint.InputChanged:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseMovement then
                DragInput = Input
            end
        end)
        UserInputService.InputChanged:Connect(function(Input)
            if Input == DragInput and Dragging then
                local Delta = Input.Position - MousePos
                TweenService:Create(Main, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                    { Position = UDim2.new(FramePos.X.Scale,FramePos.X.Offset + Delta.X, FramePos.Y.Scale, FramePos.Y.Offset + Delta.Y) }
                ):Play()
            end
        end)
    end)
end

-- ======= Init/Window =================================================
function OrionLib:Init()
    OrionLib.Folder = Cfg.ConfigFolder or "SorinHub"
    OrionLib.SaveCfg = Cfg.SaveConfig and true or false

    if OrionLib.SaveCfg and isfolder and not isfolder(OrionLib.Folder) then
        makefolder(OrionLib.Folder)
    end
    if OrionLib.SaveCfg then
        pcall(function()
            if isfile and isfile(OrionLib.Folder .. "/" .. game.GameId .. ".txt") then
                LoadCfg(readfile(OrionLib.Folder .. "/" .. game.GameId .. ".txt"))
                OrionLib:MakeNotification({
                    Name = "Configuration",
                    Content = "Auto-loaded configuration for game " .. game.GameId .. ".",
                    Time = 5
                })
            end
        end)
    end
end

function OrionLib:MakeWindow(WindowConfig)
    WindowConfig = WindowConfig or {}
    WindowConfig.Name         = WindowConfig.Name or "Orion Library"
    WindowConfig.ConfigFolder = WindowConfig.ConfigFolder or (Cfg.ConfigFolder or WindowConfig.Name)
    WindowConfig.SaveConfig   = (WindowConfig.SaveConfig ~= nil) and WindowConfig.SaveConfig or (Cfg.SaveConfig or false)
    WindowConfig.HidePremium  = WindowConfig.HidePremium or false
    if WindowConfig.IntroEnabled == nil then
        WindowConfig.IntroEnabled = (Cfg.IntroEnabled ~= nil) and Cfg.IntroEnabled or true
    end
    WindowConfig.IntroText = WindowConfig.IntroText or (Cfg.IntroText or "Orion Library")
    WindowConfig.CloseCallback = WindowConfig.CloseCallback or function() end
    WindowConfig.ShowIcon = WindowConfig.ShowIcon or (Cfg.WindowIcon ~= nil)
    WindowConfig.Icon = WindowConfig.Icon or (Cfg.WindowIcon or "rbxassetid://8834748103")
    WindowConfig.IntroIcon = WindowConfig.IntroIcon or (Cfg.IntroIcon or "rbxassetid://8834748103")

    OrionLib.Folder = WindowConfig.ConfigFolder
    OrionLib.SaveCfg = WindowConfig.SaveConfig

    if WindowConfig.SaveConfig and isfolder and not isfolder(WindowConfig.ConfigFolder) then
        makefolder(WindowConfig.ConfigFolder)
    end

    -- Tab-Liste links
    local TabHolder = AddThemeObject(SetChildren(SetProps(MakeElement("ScrollFrame", Color3.fromRGB(255,255,255), 4), {
        Size = UDim2.new(1, 0, 1, -50)
    }), {
        MakeElement("List"),
        MakeElement("Padding", 8, 0, 0, 8)
    }), "Divider")

    AddConnection(TabHolder.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        TabHolder.CanvasSize = UDim2.new(0, 0, 0, TabHolder.UIListLayout.AbsoluteContentSize.Y + 16)
    end)

    local CloseBtn = SetChildren(SetProps(MakeElement("Button"), {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        BackgroundTransparency = 1
    }), {
        AddThemeObject(SetProps(MakeElement("Image", GetIcon("close") or "rbxassetid://7072725342"), {
            Position = UDim2.new(0, 9, 0, 6),
            Size = UDim2.new(0, 18, 0, 18)
        }), "Text")
    })

    local MinimizeBtn = SetChildren(SetProps(MakeElement("Button"), {
        Size = UDim2.new(0.5, 0, 1, 0),
        BackgroundTransparency = 1
    }), {
        AddThemeObject(SetProps(MakeElement("Image", GetIcon("minimize") or "rbxassetid://7072719338"), {
            Position = UDim2.new(0, 9, 0, 6),
            Size = UDim2.new(0, 18, 0, 18),
            Name = "Ico"
        }), "Text")
    })

    local DragPoint = SetProps(MakeElement("TFrame"), { Size = UDim2.new(1, 0, 0, 50) })

    local WindowTopBarLine = AddThemeObject(SetProps(MakeElement("Frame"), {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.new(0, 0, 1, -1)
    }), "Stroke")

    local WindowName = AddThemeObject(SetProps(MakeElement("Label", WindowConfig.Name, 14), {
        Size = UDim2.new(1, -30, 2, 0),
        Position = UDim2.new(0, 25, 0, -24),
        Font = Enum.Font.GothamBlack,
        TextSize = 20
    }), "Text")

    local TabArea = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 10), {
        Size = UDim2.new(0, 150, 1, -50),
        Position = UDim2.new(0, 0, 0, 50)
    }), {
        AddThemeObject(SetProps(MakeElement("Frame"), {Size = UDim2.new(1,0,0,10), Position = UDim2.new(0,0,0,0)}), "Second"),
        AddThemeObject(SetProps(MakeElement("Frame"), {Size = UDim2.new(0,10,1,0), Position = UDim2.new(1,-10,0,0)}), "Second"),
        AddThemeObject(SetProps(MakeElement("Frame"), {Size = UDim2.new(0,1,1,0), Position = UDim2.new(1,-1,0,0)}), "Stroke"),
        TabHolder,
        SetChildren(SetProps(MakeElement("TFrame"), {
            Size = UDim2.new(1, 0, 0, 50),
            Position = UDim2.new(0, 0, 1, -50)
        }), {
            AddThemeObject(SetProps(MakeElement("Frame"), { Size = UDim2.new(1,0,0,1)}), "Stroke"),
            AddThemeObject(SetChildren(SetProps(MakeElement("Frame"), {
                AnchorPoint = Vector2.new(0,0.5),
                Size = UDim2.new(0,32,0,32),
                Position = UDim2.new(0,10,0.5,0)
            }), {
                SetProps(MakeElement("Image", "https://www.roblox.com/headshot-thumbnail/image?userId=".. LocalPlayer.UserId .."&width=420&height=420&format=png"), {
                    Size = UDim2.new(1,0,1,0)
                }),
                AddThemeObject(SetProps(MakeElement("Image", GetIcon("avatarFrame") or "rbxassetid://4031889928"), {
                    Size = UDim2.new(1,0,1,0)
                }), "Second"),
                MakeElement("Corner", 1)
            }), "Divider"),
            SetChildren(SetProps(MakeElement("TFrame"), {
                AnchorPoint = Vector2.new(0,0.5),
                Size = UDim2.new(0,32,0,32),
                Position = UDim2.new(0,10,0.5,0)
            }), {
                AddThemeObject(MakeElement("Stroke"), "Stroke"),
                MakeElement("Corner", 1)
            }),
            AddThemeObject(SetProps(MakeElement("Label", "SorinHub", WindowConfig.HidePremium and 14 or 13), {
                Size = UDim2.new(1, -60, 0, 13),
                Position = WindowConfig.HidePremium and UDim2.new(0, 50, 0, 19) or UDim2.new(0, 50, 0, 12),
                Font = Enum.Font.GothamBold,
                ClipsDescendants = true
            }), "Text"),
            AddThemeObject(SetProps(MakeElement("Label", "", 12), {
                Size = UDim2.new(1, -60, 0, 12),
                Position = UDim2.new(0, 50, 1, -25),
                Visible = not WindowConfig.HidePremium
            }), "TextDark")
        })
    }), "Second")

    local MainWindow = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 10), {
        Parent = Orion,
        Position = UDim2.new(0.5, -307, 0.5, -172),
        Size = UDim2.new(0, 615, 0, 344),
        ClipsDescendants = true
    }), {
        SetChildren(SetProps(MakeElement("TFrame"), {Size = UDim2.new(1,0,0,50), Name = "TopBar"}), {
            WindowName,
            WindowTopBarLine,
            AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 7), {
                Size = UDim2.new(0, 70, 0, 30),
                Position = UDim2.new(1, -90, 0, 10)
            }), {
                AddThemeObject(MakeElement("Stroke"), "Stroke"),
                AddThemeObject(SetProps(MakeElement("Frame"), {Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(0.5, 0, 0, 0)}), "Stroke"),
                CloseBtn,
                MinimizeBtn
            }), "Second"),
        }),
        DragPoint,
        TabArea
    }), "Main")

    -- Sorin-Logo links in der TopBar (optional)
    if Cfg.WindowIcon then
        local SorinLogo = SetProps(MakeElement("Image", Cfg.WindowIcon), {
            Size = UDim2.new(0, 20, 0, 20),
            Position = UDim2.new(0, 5, 0, 15),
            BackgroundTransparency = 1
        })
        SorinLogo.Parent = MainWindow.TopBar
        WindowName.Position = UDim2.new(0, 30, 0, -24)
    end

    AddDraggingFunctionality(DragPoint, MainWindow)

    AddConnection(CloseBtn.MouseButton1Up, function()
        MainWindow.Visible = false
        OrionLib:MakeNotification({
            Name = "Interface Hidden",
            Content = "Press RightShift to reopen the interface",
            Time = 5
        })
        (WindowConfig.CloseCallback or function() end)()
    end)

    AddConnection(UserInputService.InputBegan, function(Input)
        if Input.KeyCode == Enum.KeyCode.RightShift and not MainWindow.Visible then
            MainWindow.Visible = true
        end
    end)

    AddConnection(MinimizeBtn.MouseButton1Up, function()
        local Ico = MinimizeBtn:FindFirstChild("Ico")
        if MainWindow.Size.Y.Offset > 50 then
            MainWindow.ClipsDescendants = true
            WindowTopBarLine.Visible = false
            if Ico then Ico.Image = GetIcon("unmin") or "rbxassetid://7072720870" end
            TweenService:Create(MainWindow, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                {Size = UDim2.new(0, WindowName.TextBounds.X + 140, 0, 50)}):Play()
            task.wait(0.1)
            TabArea.Visible = false
        else
            TweenService:Create(MainWindow, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 615, 0, 344)}):Play()
            if Ico then Ico.Image = GetIcon("minimize") or "rbxassetid://7072719338" end
            task.wait(.02)
            MainWindow.ClipsDescendants = false
            TabArea.Visible = true
            WindowTopBarLine.Visible = true
        end
    end)

    local function LoadSequence()
        MainWindow.Visible = false
        local LoadLogo = SetProps(MakeElement("Image", WindowConfig.IntroIcon), {
            Parent = Orion, AnchorPoint = Vector2.new(0.5,0.5),
            Position = UDim2.new(0.5,0,0.4,0), Size = UDim2.new(0,28,0,28),
            ImageColor3 = Color3.fromRGB(255,255,255), ImageTransparency = 1
        })
        local LoadText = SetProps(MakeElement("Label", WindowConfig.IntroText, 14), {
            Parent = Orion, Size = UDim2.new(1,0,1,0),
            AnchorPoint = Vector2.new(0.5,0.5), Position = UDim2.new(0.5,19,0.5,0),
            TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold,
            TextTransparency = 1
        })

        TweenService:Create(LoadLogo, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {ImageTransparency = 0, Position = UDim2.new(0.5,0,0.5,0)}):Play()
        task.wait(0.8)
        TweenService:Create(LoadLogo, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = UDim2.new(0.5, -(LoadText.TextBounds.X/2), 0.5, 0)}):Play()
        task.wait(0.3)
        TweenService:Create(LoadText, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {TextTransparency = 0}):Play()
        task.wait(2)
        TweenService:Create(LoadText, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {TextTransparency = 1}):Play()
        MainWindow.Visible = true
        LoadLogo:Destroy()
        LoadText:Destroy()
    end
    if WindowConfig.IntroEnabled then LoadSequence() end

    -- ===================== Tabs & Elements ===========================
    local FirstTab = true

    local TabFunction = {}
    function TabFunction:MakeTab(TabConfig)
        TabConfig = TabConfig or {}
        TabConfig.Name = TabConfig.Name or "Tab"
        TabConfig.Icon = TabConfig.Icon or ""

        local TabFrame = SetChildren(SetProps(MakeElement("Button"), {
            Size = UDim2.new(1, 0, 0, 30), Parent = TabHolder
        }), {
            AddThemeObject(SetProps(MakeElement("Image", TabConfig.Icon), {
                AnchorPoint = Vector2.new(0,0.5), Size = UDim2.new(0,18,0,18),
                Position = UDim2.new(0,10,0.5,0), ImageTransparency = 0.4, Name = "Ico"
            }), "Text"),
            AddThemeObject(SetProps(MakeElement("Label", TabConfig.Name, 14), {
                Size = UDim2.new(1, -35, 1, 0), Position = UDim2.new(0,35,0,0),
                Font = Enum.Font.GothamSemibold, TextTransparency = 0.4, Name="Title"
            }), "Text")
        })

        if GetIcon(TabConfig.Icon) then
            TabFrame.Ico.Image = GetIcon(TabConfig.Icon)
        end

        local Container = AddThemeObject(SetChildren(SetProps(MakeElement("ScrollFrame", Color3.fromRGB(255,255,255), 5), {
            Size = UDim2.new(1, -150, 1, -50), Position = UDim2.new(0,150,0,50),
            Parent = MainWindow, Visible = false, Name = "ItemContainer"
        }), {
            MakeElement("List", 0, 6),
            MakeElement("Padding", 15, 10, 10, 15)
        }), "Divider")

        AddConnection(Container.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
            Container.CanvasSize = UDim2.new(0, 0, 0, Container.UIListLayout.AbsoluteContentSize.Y + 30)
        end)

        if FirstTab then
            FirstTab = false
            TabFrame.Ico.ImageTransparency = 0
            TabFrame.Title.TextTransparency = 0
            TabFrame.Title.Font = Enum.Font.GothamBlack
            Container.Visible = true
        end

        AddConnection(TabFrame.MouseButton1Click, function()
            for _, Tab in next, TabHolder:GetChildren() do
                if Tab:IsA("TextButton") then
                    Tab.Title.Font = Enum.Font.GothamSemibold
                    TweenService:Create(Tab.Ico, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = 0.4}):Play()
                    TweenService:Create(Tab.Title, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {TextTransparency = 0.4}):Play()
                end
            end
            for _, ItemContainer in next, MainWindow:GetChildren() do
                if ItemContainer.Name == "ItemContainer" then
                    ItemContainer.Visible = false
                end
            end
            TweenService:Create(TabFrame.Ico, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency = 0}):Play()
            TweenService:Create(TabFrame.Title, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {TextTransparency = 0}):Play()
            TabFrame.Title.Font = Enum.Font.GothamBlack
            Container.Visible = true
        end)

        -- ----- Element-Factory für Container -------------------------
        local function GetElements(ItemParent)
            local E = {}

            function E:AddLabel(Text)
                local LabelFrame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 5), {
                    Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 0.7, Parent = ItemParent
                }), {
                    AddThemeObject(SetProps(MakeElement("Label", Text, 15), {
                        Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 12, 0, 0),
                        Font = Enum.Font.GothamBold, Name = "Content"
                    }), "Text"),
                    AddThemeObject(MakeElement("Stroke"), "Stroke")
                }), "Second")
                local L = {}
                function L:Set(t) LabelFrame.Content.Text = t end
                return L
            end

            function E:AddParagraph(Text, Content)
                Text = Text or "Text"; Content = Content or "Content"
                local Frame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 5), {
                    Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 0.7, Parent = ItemParent
                }), {
                    AddThemeObject(SetProps(MakeElement("Label", Text, 15), {
                        Size = UDim2.new(1, -12, 0, 14), Position = UDim2.new(0, 12, 0, 10),
                        Font = Enum.Font.GothamBold, Name = "Title"
                    }), "Text"),
                    AddThemeObject(SetProps(MakeElement("Label", "", 13), {
                        Size = UDim2.new(1, -24, 0, 0), Position = UDim2.new(0, 12, 0, 26),
                        Font = Enum.Font.GothamSemibold, Name = "Content", TextWrapped = true
                    }), "TextDark"),
                    AddThemeObject(MakeElement("Stroke"), "Stroke")
                }), "Second")

                AddConnection(Frame.Content:GetPropertyChangedSignal("Text"), function()
                    Frame.Content.Size = UDim2.new(1, -24, 0, Frame.Content.TextBounds.Y)
                    Frame.Size = UDim2.new(1, 0, 0, Frame.Content.TextBounds.Y + 35)
                end)
                Frame.Content.Text = Content
                local P = {}; function P:Set(v) Frame.Content.Text = v end; return P
            end

            function E:AddButton(cfg)
                cfg = cfg or {}; cfg.Name = cfg.Name or "Button"; cfg.Callback = cfg.Callback or function() end
                cfg.Icon = cfg.Icon or GetIcon("check") or "rbxassetid://3944703587"
                local Click = SetProps(MakeElement("Button"), {Size = UDim2.new(1,0,1,0)})
                local Btn = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 5), {
                    Size = UDim2.new(1,0,0,33), Parent = ItemParent
                }), {
                    AddThemeObject(SetProps(MakeElement("Label", cfg.Name, 15), {
                        Size = UDim2.new(1,-12,1,0), Position = UDim2.new(0,12,0,0), Font = Enum.Font.GothamBold, Name="Content"
                    }), "Text"),
                    AddThemeObject(SetProps(MakeElement("Image", cfg.Icon), {
                        Size = UDim2.new(0,20,0,20), Position = UDim2.new(1,-30,0,7),
                    }), "TextDark"),
                    AddThemeObject(MakeElement("Stroke"), "Stroke"),
                    Click
                }), "Second")

                AddConnection(Click.MouseEnter, function()
                    TweenService:Create(Btn, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = Cfg.Theme.Second}):Play()
                end)
                AddConnection(Click.MouseLeave, function()
                    TweenService:Create(Btn, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = OrionLib.Themes.Default.Main}):Play()
                end)
                AddConnection(Click.MouseButton1Up, function()
                    TweenService:Create(Btn, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = Cfg.Theme.Second}):Play()
                    task.spawn(cfg.Callback)
                end)
                AddConnection(Click.MouseButton1Down, function()
                    TweenService:Create(Btn, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = Cfg.Theme.Divider}):Play()
                end)
                local B = {}; function B:Set(t) Btn.Content.Text = t end; return B
            end

            function E:AddToggle(cfg)
                cfg = cfg or {}
                cfg.Name     = cfg.Name or "Toggle"
                cfg.Default  = cfg.Default or false
                cfg.Callback = cfg.Callback or function() end
                cfg.Color    = cfg.Color or Cfg.Accent.Primary
                cfg.Flag     = cfg.Flag or nil
                cfg.Save     = cfg.Save or false

                local Toggle = {Value = cfg.Default, Save = cfg.Save}
                local Click = SetProps(MakeElement("Button"), {Size = UDim2.new(1,0,1,0)})

                local Box = SetChildren(SetProps(MakeElement("RoundFrame", cfg.Color, 0, 4), {
                    Size = UDim2.new(0,24,0,24), Position = UDim2.new(1, -24, 0.5, 0), AnchorPoint = Vector2.new(0.5,0.5)
                }), {
                    SetProps(MakeElement("Stroke"), { Color = cfg.Color, Name = "Stroke", Transparency = 0.5 }),
                    SetProps(MakeElement("Image", GetIcon("check") or "rbxassetid://3944680095"), {
                        Size = UDim2.new(0,20,0,20), AnchorPoint = Vector2.new(0.5,0.5),
                        Position = UDim2.new(0.5,0,0.5,0), ImageColor3 = Color3.fromRGB(255,255,255), Name="Ico"
                    }),
                })

                local Frame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 5), {
                    Size = UDim2.new(1,0,0,38), Parent = ItemParent
                }), {
                    AddThemeObject(SetProps(MakeElement("Label", cfg.Name, 15), {
                        Size = UDim2.new(1,-12,1,0), Position = UDim2.new(0,12,0,0), Font = Enum.Font.GothamBold, Name="Content"
                    }), "Text"),
                    AddThemeObject(MakeElement("Stroke"), "Stroke"),
                    Box, Click
                }), "Second")

                function Toggle:Set(v)
                    Toggle.Value = not not v
                    TweenService:Create(Box, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = Toggle.Value and cfg.Color or OrionLib.Themes.Default.Divider}):Play()
                    TweenService:Create(Box.Stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {Color = Toggle.Value and cfg.Color or OrionLib.Themes.Default.Stroke}):Play()
                    TweenService:Create(Box.Ico, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {ImageTransparency = Toggle.Value and 0 or 1, Size = Toggle.Value and UDim2.new(0,20,0,20) or UDim2.new(0,8,0,8)}):Play()
                    cfg.Callback(Toggle.Value)
                end
                Toggle:Set(Toggle.Value)

                AddConnection(Click.MouseEnter, function()
                    TweenService:Create(Frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = Cfg.Theme.Second}):Play()
                end)
                AddConnection(Click.MouseLeave, function()
                    TweenService:Create(Frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = OrionLib.Themes.Default.Main}):Play()
                end)
                AddConnection(Click.MouseButton1Up, function()
                    TweenService:Create(Frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = Cfg.Theme.Second}):Play()
                    SaveCfg(game.GameId)
                    Toggle:Set(not Toggle.Value)
                end)
                AddConnection(Click.MouseButton1Down, function()
                    TweenService:Create(Frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        {BackgroundColor3 = Cfg.Theme.Divider}):Play()
                end)

                if cfg.Flag then OrionLib.Flags[cfg.Flag] = Toggle end
                return Toggle
            end

            function E:AddSlider(cfg)
                cfg = cfg or {}
                cfg.Name       = cfg.Name or "Slider"
                cfg.Min        = cfg.Min or 0
                cfg.Max        = cfg.Max or 100
                cfg.Increment  = cfg.Increment or 1
                cfg.Default    = cfg.Default or 50
                cfg.Callback   = cfg.Callback or function() end
                cfg.ValueName  = cfg.ValueName or ""
                cfg.Color      = cfg.Color or Cfg.Accent.Primary
                cfg.Flag       = cfg.Flag or nil
                cfg.Save       = cfg.Save or false

                local Slider = {Value = cfg.Default, Save = cfg.Save}
                local Dragging = false

                local Drag = SetChildren(SetProps(MakeElement("RoundFrame", cfg.Color, 0, 5), {
                    Size = UDim2.new(0, 0, 1, 0), BackgroundTransparency = 0.3, ClipsDescendants = true
                }), {
                    AddThemeObject(SetProps(MakeElement("Label", "value", 13), {
                        Size = UDim2.new(1, -12, 0, 14), Position = UDim2.new(0, 12, 0, 6),
                        Font = Enum.Font.GothamBold, Name = "Value", TextTransparency = 0
                    }), "Text")
                })

                local Bar = SetChildren(SetProps(MakeElement("RoundFrame", cfg.Color, 0, 5), {
                    Size = UDim2.new(1, -24, 0, 26), Position = UDim2.new(0, 12, 0, 30), BackgroundTransparency = 0.9
                }), {
                    SetProps(MakeElement("Stroke"), { Color = cfg.Color }),
                    AddThemeObject(SetProps(MakeElement("Label", "value", 13), {
                        Size = UDim2.new(1, -12, 0, 14), Position = UDim2.new(0, 12, 0, 6),
                        Font = Enum.Font.GothamBold, Name = "Value", TextTransparency = 0.8
                    }), "Text"),
                    Drag
                })

                local Frame = AddThemeObject(SetChildren(SetProps(MakeElement("RoundFrame", OrionLib.Themes.Default.Main, 0, 4), {
                    Size = UDim2.new(1,0,0,65), Parent = ItemParent
                }), {
                    AddThemeObject(SetProps(MakeElement("Label", cfg.Name, 15), {
                        Size = UDim2.new(1,-12,0,14), Position = UDim2.new(0,12,0,10), Font = Enum.Font.GothamBold, Name="Content"
                    }), "Text"),
                    AddThemeObject(MakeElement("Stroke"), "Stroke"),
                    Bar
                }), "Second")

                local function Round(n, f) local r = math.floor(n/f + (math.sign(n)*0.5)) * f; if r < 0 then r = r + f end; return r end

                local function BeginDrag(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                        Dragging = true
                    end
                end
                local function EndDrag(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
                        Dragging = false
                    end
                end
                local function UpdateDrag(Input)
                    if Dragging and (Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch) then
                        local SizeScale = math.clamp((Input.Position.X - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
                        Slider:Set(cfg.Min + ((cfg.Max - cfg.Min) * SizeScale))
                        SaveCfg(game.GameId)
                    end
                end

                function Slider:Set(Value)
                    self.Value = math.clamp(Round(Value, cfg.Increment), cfg.Min, cfg.Max)
                    TweenService:Create(Drag, TweenInfo.new(.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        {Size = UDim2.fromScale((self.Value - cfg.Min) / (cfg.Max - cfg.Min), 1)}):Play()
                    Bar.Value.Text  = tostring(self.Value) .. " " .. cfg.ValueName
                    Drag.Value.Text = tostring(self.Value) .. " " .. cfg.ValueName
                    cfg.Callback(self.Value)
                end

                Bar.InputBegan:Connect(BeginDrag)
                Bar.InputEnded:Connect(EndDrag)
                UserInputService.InputChanged:Connect(UpdateDrag)

                Slider:Set(Slider.Value)
                if cfg.Flag then OrionLib.Flags[cfg.Flag] = Slider end
                return Slider
            end

            -- (Weitere Elemente wie Dropdown/Bind/Textbox/Colorpicker – unverändert,
            -- nur Theme/Accent/Icons greifen automatisch auf Cfg zu. Lass sie aus
            -- Platzgründen hier weg, wenn du sie brauchst, übernimm die gleichen
            -- kleinen Anpassungen wie oben bei Toggle/Slider.)
            return E
        end

        local ElementFunction = {}
        for k, v in next, GetElements(Container) do ElementFunction[k] = v end
        return ElementFunction
    end

    return TabFunction
end

function OrionLib:Destroy()
    Orion:Destroy()
end

return OrionLib
