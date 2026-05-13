--!strict
return {
    RootGui = "YourUiPack!",
    Panels = {
        "DailyRewards",
        "PlaytimeRewards",
        "Rewards",
        "Shop",
        "Discover",
        "Index",
        "Rebirth",
        "LeftSide",
        "LeftBottomBar",
    },
    NavigationButtons = {
        DailyRewards = { "LeftSide", "ReadyBtn" },
        Shop = { "LeftSide", "ShopBtn" },
        Index = { "LeftSide", "IndexBtn" },
        Rebirth = { "LeftSide", "RebirthBtn" },
        Discover = { "LeftBottomBar", "IconBtn03" },
        PlaytimeRewards = { "LeftBottomBar", "IconBtn05" },
    },
    ExternalPanels = {
        -- Path entries are traversed in order via SafeWait.FindPath from PlayerGui.
        Shop = { "Shop", "ItemShopUI" },
    },
    ActionButtons = {
        Roll = { "LeftBottomBar", "IconBtn01" },
        AutoRoll = { "LeftBottomBar", "IconBtn02" },
        LuckProduct = { "LeftBottomBar", "IconBtn04" },
        RewardsWatch = { "Rewards", "Content", "WatchBtn" },
        Rebirth = { "Rebirth", "Content", "Btns", "RebirthBtn" },
        SkipRebirth = { "Rebirth", "Content", "Btns", "SkipRebirthBtn" },
    },
    CloseButtons = {
        DailyRewards = { "DailyRewards", "Header", "CloseBtn" },
        PlaytimeRewards = { "PlaytimeRewards", "Header", "CloseBtn" },
        Rewards = { "Rewards", "Header", "CloseBtn" },
        Index = { "Index", "Main", "Header", "CloseBtn" },
        Rebirth = { "Rebirth", "Header", "CloseBtn" },
    },
    DiscoverOrder = { "Normal", "Candy", "Gold", "Diamond", "Rainbow", "Vulcan" },
    FeaturedProductKey = "LuckBurst",
    RebirthSkipProductKey = "SkipRebirth",
    Loading = {
        ScreenGuiName = "LoadingScreen",
        PreloadAssetsFolder = "Assets",
        FadeDuration = 0.35,
    },
    AutoRoll = {
        RollPanelTopPosition = UDim2.new(0.5, 0, 0.08, 0),
        RollPanelTopAnchorPoint = Vector2.new(0.5, 0),
    },
}
